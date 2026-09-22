import AppKit
import EventKit
import Observation

/// EventKit 權限、讀取、變更監聽、篩選，以及開啟原生 App。
///
/// ⚠️ **本型別是唯一會觸發寫入使用者資料的地方**：`commitCompletion` 會呼叫
/// `ReminderWriter.markCompleted`。實際碰到 EventKit 的寫入 API 的只有
/// `EventKitReminderWriter`（見 `ReminderWriter.swift`）；本型別負責的是
/// **要不要寫、什麼時候寫**的判斷，那些判斷有單元測試保護。
/// 其餘所有 EventKit 呼叫都是唯讀。動這個檔案之前先讀 `PLAN.md` §8 的紅線。
@MainActor
@Observable
final class AgendaStore {
    static let shared = AgendaStore()

    /// 整個 App 只有一個 EKEventStore
    @ObservationIgnored private let store = EKEventStore()

    private(set) var eventsState: SectionState<EventItem> = .loading
    private(set) var remindersState: SectionState<ReminderItem> = .loading
    private(set) var calendars: [CalendarInfo] = []
    private(set) var reminderLists: [CalendarInfo] = []

    @ObservationIgnored private let settings: AppSettings
    /// 抽成介面只為了讓勾選路徑可測；production 用 `EventKitReminderWriter`
    @ObservationIgnored private let writer: any ReminderWriter
    /// 勾選後到真正寫入之間的緩衝時間（PLAN §4.4 定為 1.2 秒）。
    /// 可注入是為了讓測試不必真的等 1.2 秒
    @ObservationIgnored private let completionDelay: Duration
    /// 以下這些只在主執行緒與 deinit 碰到，不是 UI 狀態，不需要被觀察。
    /// deinit 是 nonisolated，所以要標 nonisolated(unsafe) 才能在裡面收尾。
    /// 要連同註冊的 center 一起記下來：喚醒通知掛在 NSWorkspace 的 center，
    /// 拿去 NotificationCenter.default 移除是無效操作，observer 會留著不放
    @ObservationIgnored nonisolated(unsafe)
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    @ObservationIgnored nonisolated(unsafe) private var refreshTimer: Timer?
    @ObservationIgnored nonisolated(unsafe) private var debounceTask: Task<Void, Never>?
    /// 缺權限時的快速輪詢。只在缺權限期間存在，拿到權限就停
    @ObservationIgnored nonisolated(unsafe) private var permissionPollTask: Task<Void, Never>?
    /// 提醒是非同步回來的，用世代編號丟掉過期結果
    @ObservationIgnored private var reminderGeneration = 0
    /// EventKit 回傳的不透明識別值；發出下一次查詢前取消前一次，
    /// 避免過期查詢仍跑完整個讀取、轉換與排序
    @ObservationIgnored private var reminderFetchIdentifier: Any?

    /// 顯示為已勾選的提醒。涵蓋兩個階段：緩衝期內（尚未寫入、可取消），
    /// 以及寫入成功後等待 refresh 把該列移除的短暫期間（已無法取消）。
    /// **是否還能取消要看 `completionTasks` 有沒有存活的 Task，不能只看這個集合。**
    private(set) var pendingCompletion: Set<String> = []
    /// 勾選寫入失敗的訊息。刻意不動 `remindersState`——單筆失敗不該讓整個清單消失，
    /// 否則其他還在緩衝期的提醒會連取消入口一起不見，然後照樣被寫入
    private(set) var completionError: String?
    @ObservationIgnored nonisolated(unsafe)
    private var completionTasks: [String: Task<Void, Never>] = [:]
    /// 讓 `completionError` 過幾秒自動消失。不設的話紅字會一直留在卡片上
    @ObservationIgnored nonisolated(unsafe) private var errorDismissTask: Task<Void, Never>?

    /// 勾選後到寫入之間的緩衝時間，PLAN §4.4 定為 1.2 秒。
    /// 具名常數而非寫死在預設引數裡，是為了讓測試能鎖住這個規格值——
    /// 變異測試發現只把預設值改掉不會讓任何測試失敗（codex 於 2026-09-18 指出的延伸）。
    /// `nonisolated` 是必要的：預設引數在 nonisolated 情境求值，
    /// 不標的話 Swift 6 語言模式會直接變成錯誤（M1 也踩過同一個坑）
    nonisolated static let defaultCompletionDelay: Duration = .milliseconds(1200)

    init(settings: AppSettings? = nil,
         writer: (any ReminderWriter)? = nil,
         completionDelay: Duration = AgendaStore.defaultCompletionDelay) {
        self.settings = settings ?? .shared
        self.writer = writer ?? EventKitReminderWriter(store: store)
        self.completionDelay = completionDelay
    }

    deinit {
        observers.forEach { $0.center.removeObserver($0.token) }
        refreshTimer?.invalidate()
        debounceTask?.cancel()
        permissionPollTask?.cancel()
        errorDismissTask?.cancel()
        completionTasks.values.forEach { $0.cancel() }
    }

    // MARK: - 啟動

    /// ⚠️ 順序很重要，不要把 `await requestAccessIfNeeded()` 移回最前面。
    ///
    /// ad-hoc 簽章每次重建都讓 cdhash 改變，TCC 會把它當成新 App 重新評估權限，
    /// `requestFullAccessToEvents()` 這個 await **實測要 30 秒到 4 分鐘以上**才回來，
    /// 而且那段期間畫面上不一定會出現授權對話框。
    ///
    /// 舊版把 refresh／observer／計時器全排在那個 await 後面，結果是：
    /// 那幾分鐘內沒有資料、沒有變更監聽、連 60 秒重讀的計時器都還沒建立，
    /// 使用者只看到一張寫著「載入中…」的空卡片，而且**沒有任何機制能重試**
    /// （M7 加的「缺權限每 3 秒重試」也救不了，因為它是在 `refresh()` 裡排的）。
    ///
    /// 現在先把重試機制全部架好再去要權限：第一次 `refresh()` 會因為還沒授權而顯示
    /// 「需要 X 存取權限」＋「打開系統設定」按鈕（比空白的載入中清楚得多），
    /// 同時啟動 3 秒輪詢；權限一到手就會自動補上資料。
    func start() async {
        observeChanges()
        startPeriodicRefresh()
        refresh()
        await requestAccessIfNeeded()
        refresh()
    }

    private func requestAccessIfNeeded() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
    }

    /// 只有 fullAccess 算通過。writeOnly／denied／restricted 都要顯示權限提示（PLAN §4.6）
    private func hasFullAccess(to type: EKEntityType) -> Bool {
        EKEventStore.authorizationStatus(for: type) == .fullAccess
    }

    // MARK: - 讀取

    func refresh(now: Date = Date()) {
        reloadCalendarLists()
        loadEvents(now: now)
        loadReminders(now: now)
        schedulePermissionPollIfNeeded()
    }

    /// 使用者到系統設定把權限打開後，不該還要等最多 60 秒才看到資料。
    /// 缺權限時每 3 秒重試一次；拿到權限後這個輪詢就不會再排下一輪。
    private func schedulePermissionPollIfNeeded() {
        permissionPollTask?.cancel()
        guard needsAnyPermission else { return }
        permissionPollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private var needsAnyPermission: Bool {
        if case .needsPermission = eventsState { return true }
        if case .needsPermission = remindersState { return true }
        return false
    }

    private func reloadCalendarLists() {
        let newCalendars = hasFullAccess(to: .event)
            ? Self.info(for: store.calendars(for: .event), hidden: settings.hiddenCalendarIDs)
            : []
        let newReminderLists = hasFullAccess(to: .reminder)
            ? Self.info(for: store.calendars(for: .reminder), hidden: settings.hiddenReminderListIDs)
            : []
        // @Observable 不會比對相等性，指派同樣的值也會發出變更通知。
        // 缺權限時的 3 秒輪詢會一直跑這裡，不擋的話每 3 秒就白重繪一次。
        if newCalendars != calendars { calendars = newCalendars }
        if newReminderLists != reminderLists { reminderLists = newReminderLists }
    }

    private static func info(for calendars: [EKCalendar], hidden: Set<String>) -> [CalendarInfo] {
        calendars
            .map {
                CalendarInfo(id: $0.calendarIdentifier,
                             title: $0.title,
                             sourceTitle: $0.source?.title ?? "未知來源",
                             color: NSColor(cgColor: $0.cgColor) ?? .systemBlue,
                             isHidden: hidden.contains($0.calendarIdentifier))
            }
            // 加上 id 當最後一個鍵：同名行事曆的順序才不會在每次重讀後互換
            .sorted { ($0.sourceTitle, $0.title, $0.id) < ($1.sourceTitle, $1.title, $1.id) }
    }

    private func visibleCalendars(for type: EKEntityType) -> [EKCalendar]? {
        let hidden = type == .event ? settings.hiddenCalendarIDs : settings.hiddenReminderListIDs
        let visible = store.calendars(for: type).filter { !hidden.contains($0.calendarIdentifier) }
        // 全部被隱藏時回 nil 會被 EventKit 當成「全部行事曆」，必須擋掉
        return visible.isEmpty ? nil : visible
    }

    /// 只有今天（今天 00:00 到今天結束）——2026-09-16 需求變更，原本是 7 天
    private func loadEvents(now: Date) {
        guard hasFullAccess(to: .event) else {
            eventsState = .needsPermission
            return
        }
        guard let calendars = visibleCalendars(for: .event) else {
            eventsState = .loaded(items: [], total: 0)
            return
        }

        let calendar = Formatting.calendar
        let startOfToday = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            eventsState = .failed("讀取失敗：無法計算查詢區間")
            return
        }

        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: calendars)
        let items = store.events(matching: predicate)
            .filter { event in
                // 已經結束的不顯示；整天行程只要還涵蓋今天就保留
                event.isAllDay ? event.endDate > startOfToday : event.endDate > now
            }
            .map { event in
                EventItem(eventIdentifier: event.eventIdentifier,
                          calendarID: event.calendar.calendarIdentifier,
                          title: event.title ?? "（無標題）",
                          start: event.startDate,
                          end: event.endDate,
                          isAllDay: event.isAllDay,
                          color: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue)
            }
            .sorted(by: Self.eventOrder)

        eventsState = .loaded(items: items, total: items.count)
    }

    /// 整天行程一律排最前面，其餘依開始時間、標題排序（PLAN §4.3）。
    ///
    /// 不再先比開始日期：那是「顯示 7 天」時代的遺留，在只顯示今天的現在會造成
    /// 昨天開始、跨過午夜的定時行程排到今天的整天行程之前，與規則矛盾。
    /// 保留完整開始時間比較，同類型內的跨午夜與多日行程先後仍然正確。
    ///
    /// internal 而非 private：為了讓 `FloatingAgendaTests` 能直接測這條排序規則。
    /// 它是純函式、沒有副作用，放寬可見性的代價很小，換到的是日期邊界有回歸測試。
    static func eventOrder(_ lhs: EventItem, _ rhs: EventItem) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        return lhs.title < rhs.title
    }

    /// 保留 `visibleIDs` 內的 pending，其餘連計時 Task 一起取消。
    ///
    /// 三處共用：非同步結果回來時，以及 `loadReminders` 兩個同步的提前 return
    /// （那兩處使用者看不到任何提醒，所以可見集合是空的）。
    ///
    /// **為什麼一定要共用**：2026-09-18 的全專案 code review 抓到，M4 當時只修了
    /// 非同步那條路徑，兩個同步 return 留下了漏洞——緩衝期內把清單隱藏或權限被撤，
    /// 使用者看不到那一列、無法取消，1.2 秒後卻仍會被寫成已完成。
    /// 同一條規則寫在三處必然再次漂移。
    private func prunePendingCompletion(keeping visibleIDs: Set<String>) {
        for staleID in pendingCompletion.subtracting(visibleIDs) {
            completionTasks.removeValue(forKey: staleID)?.cancel()
        }
        pendingCompletion.formIntersection(visibleIDs)
    }

    /// **所有**對 `remindersState` 的寫入都必須走這裡。
    ///
    /// 只要新狀態不是「使用者看得到清單」，就把 pending 連計時 Task 一起清掉。
    /// 用漏斗而不是在每個出口各寫一次 prune，是因為「逐個出口補」這件事已經失敗兩次：
    /// M4 只補了非同步成功那條；2026-09-18 的 review 抓到兩個同步提前 return；
    /// 同日的複審又抓到非同步失敗那條，我自己再查才發現 cutoff 失敗也是同一類。
    /// 有漏斗之後就不可能再有第 N 條漏掉的路徑。
    /// internal 而非 private：這是整個專案最安全關鍵的一條不變式，
    /// 必須有單元測試直接驗證它（見 `CompletionTests`）
    func setRemindersState(_ state: SectionState<ReminderItem>) {
        switch state {
        case .loaded(let items, _):
            prunePendingCompletion(keeping: Set(items.map(\.id)))
        case .loading, .needsPermission, .failed:
            // 畫面上不會有任何一列，使用者無法取消 → 一律不准寫入
            prunePendingCompletion(keeping: [])
        }
        remindersState = state
    }

    private func loadReminders(now: Date) {
        // 世代編號要在任何提前 return 之前就遞增：否則前一次還在飛的查詢結果
        // 會通過世代檢查，把 needsPermission 或空清單蓋回成舊資料
        reminderGeneration += 1
        let generation = reminderGeneration

        if let identifier = reminderFetchIdentifier {
            reminderFetchIdentifier = nil
            store.cancelFetchRequest(identifier)
        }

        guard hasFullAccess(to: .reminder) else {
            setRemindersState(.needsPermission)
            return
        }
        guard let calendars = visibleCalendars(for: .reminder) else {
            setRemindersState(.loaded(items: [], total: 0))
            return
        }

        // 只要「逾期 ＋ 今天到期」：到期時間早於明天 00:00 就算。
        // 沒有設到期日的不顯示（2026-09-16 需求變更，見 PLAN §4.4）
        let calendar = Formatting.calendar
        let startOfToday = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            setRemindersState(.failed("讀取失敗：無法計算今天的範圍"))
            return
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil,
                                                              ending: nil,
                                                              calendars: calendars)
        // 這個 callback 會在背景 queue 回來：先在原地轉成值型別，再切回 MainActor
        reminderFetchIdentifier = store.fetchReminders(matching: predicate) { reminders in
            let items = reminders.map { Self.items(from: $0, dueBefore: cutoff) }
            Task { @MainActor [weak self] in
                // 取消不保證 callback 不會來，世代檢查仍是最後一道防線
                guard let self, generation == self.reminderGeneration else { return }
                // 只有當代的 callback 可以清掉 identifier，否則會誤清較新查詢的
                self.reminderFetchIdentifier = nil
                guard let items else {
                    self.setRemindersState(.failed("讀取失敗：無法取得提醒事項"))
                    return
                }
                self.setRemindersState(.loaded(items: items, total: items.count))
                self.schedulePermissionPollIfNeeded()
            }
        }
    }

    /// 這個方法是在 fetchReminders 的背景 queue 上呼叫的（EventKit 的契約就是如此），
    /// AgendaStore 標了 @MainActor 會讓 static 成員也繼承隔離，所以必須明確 nonisolated
    private nonisolated static func items(from reminders: [EKReminder],
                                          dueBefore cutoff: Date) -> [ReminderItem] {
        reminders
            .compactMap { reminder -> ReminderItem? in
                guard let components = reminder.dueDateComponents,
                      let due = Formatting.calendar.date(from: components),
                      due < cutoff else { return nil }
                return ReminderItem(id: reminder.calendarItemIdentifier,
                                    title: reminder.title ?? "（無標題）",
                                    due: due,
                                    dueHasTime: components.hour != nil,
                                    color: NSColor(cgColor: reminder.calendar.cgColor) ?? .systemBlue,
                                    created: reminder.creationDate)
            }
            .sorted(by: reminderOrder)
    }

    /// 顯示中的提醒依到期時間由早到晚，同到期時間依標題排序。
    ///
    /// PLAN §4.4 規定沒有到期日的不顯示，實際過濾在 `items(from:dueBefore:)`。
    /// 但 `ReminderItem.due` 型別上仍是 Optional，所以這裡保留防禦性的 nil 排序
    /// （nil 排在有到期日之後；兩者皆 nil 時依建立時間再依標題）。
    /// **這不代表允許顯示無到期日的提醒**——未來若改需求，要重新確認一次規格。
    ///
    /// internal 而非 private：理由同 `eventOrder`
    nonisolated static func reminderOrder(_ lhs: ReminderItem, _ rhs: ReminderItem) -> Bool {
        switch (lhs.due, rhs.due) {
        case let (lhsDue?, rhsDue?):
            if lhsDue != rhsDue { return lhsDue < rhsDue }
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case (nil, nil):
            let lhsCreated = lhs.created ?? .distantFuture
            let rhsCreated = rhs.created ?? .distantFuture
            if lhsCreated != rhsCreated { return lhsCreated < rhsCreated }
        }
        return lhs.title < rhs.title
    }

    // MARK: - 篩選（選單列用）

    /// 存的是「被隱藏的」ID，所以之後新增的行事曆會預設顯示（PLAN §4.5）
    func setCalendarHidden(_ id: String, _ hidden: Bool) {
        var ids = settings.hiddenCalendarIDs
        if hidden { ids.insert(id) } else { ids.remove(id) }
        settings.hiddenCalendarIDs = ids
        refresh()
    }

    func setReminderListHidden(_ id: String, _ hidden: Bool) {
        var ids = settings.hiddenReminderListIDs
        if hidden { ids.insert(id) } else { ids.remove(id) }
        settings.hiddenReminderListIDs = ids
        refresh()
    }

    // MARK: - 勾選完成（本專案唯一的寫入路徑，PLAN §4.4）

    /// 點圓圈。第一次點只做本地標記，1.2 秒後才真的寫入；
    /// 1.2 秒內再點一次就取消，完全不寫入。
    func toggleCompletion(_ reminder: ReminderItem) {
        let id = reminder.id
        if pendingCompletion.contains(id) {
            // 只有還有存活的 Task 才取消得掉。寫入已經送出去的（Task 已移除）
            // 不能把本地標記拿掉——那會讓畫面顯示「取消了」但資料其實已完成
            guard let task = completionTasks.removeValue(forKey: id) else { return }
            task.cancel()
            pendingCompletion.remove(id)
            return
        }

        setCompletionError(nil)
        pendingCompletion.insert(id)
        let delay = completionDelay
        completionTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.commitCompletion(id)
        }
    }

    /// ⚠️ 觸發寫入使用者資料的唯一入口。
    /// 只會由 `toggleCompletion` 在緩衝期結束且未被取消時呼叫。
    private func commitCompletion(_ id: String) {
        completionTasks.removeValue(forKey: id)
        // 緩衝期間這筆可能已被取消，或被 refresh 移出今天的範圍。
        // 只要本地標記已經不在，就代表使用者看到的狀態不是「勾選中」，一律不寫入。
        guard pendingCompletion.contains(id) else { return }

        do {
            try writer.markCompleted(id: id)
            // 寫入成功後 .EKEventStoreChanged 會觸發 refresh，這一列自然淡出消失。
            // pendingCompletion 留著，避免 refresh 前的短暫空窗讓勾選狀態閃回未完成。
        } catch {
            failCompletion(id, message: "勾選失敗：\(error.localizedDescription)")
        }
    }

    private func failCompletion(_ id: String, message: String) {
        pendingCompletion.remove(id)
        setCompletionError(message)
    }

    /// 錯誤訊息要停留夠久讓人讀完，但不能無限期殘留在卡片上。
    /// `refresh()` 不會清它（那會在寫入失敗後立刻被 .EKEventStoreChanged 觸發的重讀吃掉訊息），
    /// 所以改用計時自動消失。
    private func setCompletionError(_ message: String?) {
        errorDismissTask?.cancel()
        errorDismissTask = nil
        completionError = message
        guard message != nil else { return }
        errorDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.completionError = nil
        }
    }

    // MARK: - 開啟原生 App（PLAN §5.6）

    /// 點行程 → 打開行事曆 App 到那一筆。
    /// `ical://` 深層連結沒有官方文件，開不起來就退回只開 App。
    func openInCalendar(_ event: EventItem) {
        // 沒有 eventIdentifier 就無法指向那一筆（部分生日／訂閱行事曆會這樣），
        // 直接開 App 比送一個假的 identifier 好
        guard let identifier = event.eventIdentifier else {
            openApp(at: "/System/Applications/Calendar.app")
            return
        }
        let encoded = identifier
            .addingPercentEncoding(withAllowedCharacters: Self.identifierAllowed) ?? identifier
        if let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        openApp(at: "/System/Applications/Calendar.app")
    }

    /// 打開對應的隱私權設定頁（PLAN §4.6）。開不起來就退回只開系統設定。
    func openPrivacySettings(for entity: EKEntityType) {
        let anchor = entity == .event ? "Privacy_Calendars" : "Privacy_Reminders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"),
           NSWorkspace.shared.open(url) {
            return
        }
        openApp(at: "/System/Applications/System Settings.app")
    }

    /// 點提醒標題 → 打開提醒事項 App 到那一筆。開不起來就退回只開 App。
    func openInReminders(_ reminder: ReminderItem) {
        let encoded = reminder.id
            .addingPercentEncoding(withAllowedCharacters: Self.identifierAllowed) ?? reminder.id
        if let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(encoded)"),
           NSWorkspace.shared.open(url) {
            return
        }
        openApp(at: "/System/Applications/Reminders.app")
    }

    /// EventKit 的 eventIdentifier 形如 `<UUID>:<UUID>`，而 `.urlPathAllowed`
    /// 實測會把冒號編成 `%3A`。實測可用的形式是原始冒號，所以把它加回允許集合。
    private nonisolated static let identifierAllowed: CharacterSet =
        .urlPathAllowed.union(CharacterSet(charactersIn: ":"))

    private func openApp(at path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }

    // MARK: - 即時更新

    private func observeChanges() {
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        observers.append((center, center.addObserver(forName: .EKEventStoreChanged,
                                                     object: store,
                                                     queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDebouncedRefresh() }
        }))
        // 過午夜：日期標題與「今天」分組要換掉
        observers.append((center, center.addObserver(forName: .NSCalendarDayChanged,
                                                     object: nil,
                                                     queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }))
        // 從睡眠醒來：期間的行程可能已經結束
        observers.append((workspaceCenter,
                          workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                      object: nil,
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }))
    }

    /// 行事曆／提醒事項 App 一次改動會連發多則通知，等 0.3 秒再重讀
    private func scheduleDebouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// 每 60 秒重讀：把結束的行程移掉、更新「進行中」標示
    private func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        refreshTimer = timer
    }
}
