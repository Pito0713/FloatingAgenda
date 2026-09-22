import AppKit

/// snapshot 與 M1 面板骨架用的假資料（PLAN §5.7）。
/// 只在開發期使用；M2 起面板改吃 AgendaStore 的真實資料。
@MainActor
enum MockData {
    /// 基準時間固定為當天 09:00，讓 snapshot 在任何時間跑都長一樣
    static func referenceDate(now: Date = Date()) -> Date {
        Formatting.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
    }

    static func events(now: Date = Date()) -> [EventItem] {
        let base = referenceDate(now: now)
        let calendar = Formatting.calendar
        let startOfToday = calendar.startOfDay(for: base)

        return [
            EventItem(eventIdentifier: "mock-allday",
                      calendarID: "mock-calendar",
                      title: "台灣節日：中秋節",
                      start: startOfToday,
                      end: calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday,
                      isAllDay: true,
                      color: .systemPurple),
            // 刻意讓這筆包含基準時間，用來檢查「進行中」文案
            EventItem(eventIdentifier: "mock-meeting",
                      calendarID: "mock-calendar",
                      title: "工作會議",
                      start: base.addingTimeInterval(-30 * 60),
                      end: base.addingTimeInterval(30 * 60),
                      isAllDay: false,
                      color: .systemBlue),
            EventItem(eventIdentifier: "mock-cooking",
                      calendarID: "mock-calendar",
                      title: "煮飯",
                      start: calendar.date(byAdding: .hour, value: 5, to: base) ?? base,
                      end: calendar.date(byAdding: .hour, value: 6, to: base) ?? base,
                      isAllDay: false,
                      color: .systemOrange),
            // 以下刻意讓總數超過 6 筆，用來驗證「還有 N 個行程」的收斂
            EventItem(eventIdentifier: "mock-shipping",
                      calendarID: "mock-calendar",
                      title: "副業_列印單據",
                      start: calendar.date(byAdding: .hour, value: 9, to: base) ?? base,
                      end: calendar.date(byAdding: .hour, value: 9, to: base)?.addingTimeInterval(900) ?? base,
                      isAllDay: false,
                      color: .systemPink),
            EventItem(eventIdentifier: "mock-backpack",
                      calendarID: "mock-calendar",
                      title: "整理辦公室背包",
                      start: calendar.date(byAdding: .hour, value: 12, to: base) ?? base,
                      end: calendar.date(byAdding: .hour, value: 12, to: base)?.addingTimeInterval(900) ?? base,
                      isAllDay: false,
                      color: .systemIndigo),
            EventItem(eventIdentifier: "mock-clothes",
                      calendarID: "mock-calendar",
                      title: "整理明天衣服",
                      start: calendar.date(byAdding: .hour, value: 13, to: base) ?? base,
                      end: calendar.date(byAdding: .hour, value: 13, to: base)?.addingTimeInterval(900) ?? base,
                      isAllDay: false,
                      color: .systemBrown),
            EventItem(eventIdentifier: "mock-log",
                      calendarID: "mock-calendar",
                      title: "今日記事撰寫",
                      start: calendar.date(byAdding: .hour, value: 14, to: base) ?? base,
                      end: calendar.date(byAdding: .hour, value: 14, to: base)?.addingTimeInterval(900) ?? base,
                      isAllDay: false,
                      color: .systemGray),
        ]
    }

    /// 依到期時間遞增排列，與 AgendaStore 的排序結果一致，
    /// 這樣 snapshot 才能代表真實畫面（mock 本身不會經過排序器）
    static func reminders(now: Date = Date()) -> [ReminderItem] {
        let base = referenceDate(now: now)
        let calendar = Formatting.calendar

        func today(_ hour: Int, _ minute: Int = 0) -> Date? {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
        }

        return [
            // 只有日期沒有時間 → 排在當天最前面，且不算逾期（灰字）
            ReminderItem(id: "mock-dateonly", title: "買牛奶",
                         due: calendar.startOfDay(for: base), dueHasTime: false,
                         color: .systemOrange, created: base.addingTimeInterval(-86400)),
            // 逾期：早於基準時間 09:00 → 紅字
            ReminderItem(id: "mock-overdue", title: "回覆訊息",
                         due: today(7), dueHasTime: true,
                         color: .systemRed, created: base.addingTimeInterval(-172800)),
            ReminderItem(id: "mock-today", title: "領包裹",
                         due: today(14), dueHasTime: true,
                         color: .systemBlue, created: base.addingTimeInterval(-3600)),
            ReminderItem(id: "mock-shipping", title: "副業出貨",
                         due: today(18), dueHasTime: true,
                         color: .systemPink, created: base),
            ReminderItem(id: "mock-evening", title: "購物清單：日用品",
                         due: today(21, 30), dueHasTime: true,
                         color: .systemTeal, created: base),
            ReminderItem(id: "mock-sleep", title: "睡前準備",
                         due: today(22), dueHasTime: true,
                         color: .systemIndigo, created: base),
            // 第 7 筆，用來驗證「還有 N 項」的收斂
            ReminderItem(id: "mock-read", title: "閱讀",
                         due: today(23), dueHasTime: true,
                         color: .systemGreen, created: base),
        ]
    }

    /// snapshot 用：哪幾筆要畫成「勾選中」（圓圈填滿＋刪除線）
    static var pendingReminderIDs: Set<String> { ["mock-today"] }

    /// 選單列 snapshot 用：兩個來源、其中一個刻意是隱藏狀態
    static func calendars() -> [CalendarInfo] {
        [
            CalendarInfo(id: "c1", title: "個人", sourceTitle: "iCloud",
                         color: .systemBlue, isHidden: false),
            CalendarInfo(id: "c2", title: "工作", sourceTitle: "iCloud",
                         color: .systemRed, isHidden: false),
            CalendarInfo(id: "c3", title: "煮飯", sourceTitle: "iCloud",
                         color: .systemOrange, isHidden: true),
            CalendarInfo(id: "c4", title: "Holidays in Taiwan", sourceTitle: "Google",
                         color: .systemGreen, isHidden: false),
            CalendarInfo(id: "c5", title: "Family", sourceTitle: "Google",
                         color: .systemPurple, isHidden: false),
        ]
    }

    static func reminderLists() -> [CalendarInfo] {
        [
            CalendarInfo(id: "r1", title: "每日清單", sourceTitle: "iCloud",
                         color: .systemTeal, isHidden: false),
            CalendarInfo(id: "r2", title: "待辦事項", sourceTitle: "iCloud",
                         color: .systemIndigo, isHidden: false),
            CalendarInfo(id: "r3", title: "購物清單", sourceTitle: "iCloud",
                         color: .systemPink, isHidden: true),
        ]
    }

    /// `--snapshot` 的異常狀態變體（PLAN §4.6）
    struct StateVariant {
        let name: String
        let events: SectionState<EventItem>
        let reminders: SectionState<ReminderItem>
        var reminderError: String?
    }

    static func stateVariants(reminders: [ReminderItem]) -> [StateVariant] {
        [
            // 沒有權限：兩區都要顯示說明與「打開系統設定」
            StateVariant(name: "permission",
                         events: .needsPermission,
                         reminders: .needsPermission),
            // 讀取失敗 ＋ 空狀態
            StateVariant(name: "failed",
                         events: .failed("讀取失敗：無法計算查詢區間"),
                         reminders: .loaded(items: [], total: 0)),
            // 有資料但勾選寫入失敗 → 紅色錯誤行（M4 留到 M6 驗證的那一條）
            StateVariant(name: "writefail",
                         events: .loaded(items: [], total: 0),
                         reminders: .loaded(items: Array(reminders.prefix(3)), total: 3),
                         reminderError: "勾選失敗：找不到這筆提醒，可能已被刪除"),
        ]
    }

    /// 收合模式的 snapshot 變體（PLAN §4.10）。
    /// `collapsed` 用完整 mock（其中「工作會議」涵蓋基準時間 → 進行中）；
    /// `collapsed-idle` 把進行中的那筆拿掉，驗「目前沒有行程」
    struct CollapsedVariant {
        let name: String
        let events: SectionState<EventItem>
        let reminders: SectionState<ReminderItem>
    }

    static func collapsedVariants() -> [CollapsedVariant] {
        let all = events()
        let reminders = MockData.reminders()
        let now = referenceDate()
        // 沒有進行中的，但今天稍後還有 → 應顯示即將到來的那一筆
        let upcomingOnly = all.filter { $0.start > now }
        return [
            CollapsedVariant(name: "collapsed",
                             events: .loaded(items: all, total: all.count),
                             reminders: .loaded(items: reminders, total: reminders.count)),
            CollapsedVariant(name: "collapsed-upcoming",
                             events: .loaded(items: upcomingOnly, total: upcomingOnly.count),
                             reminders: .loaded(items: reminders, total: reminders.count)),
            // 今天的行程都結束了
            CollapsedVariant(name: "collapsed-empty",
                             events: .loaded(items: [], total: 0),
                             reminders: .loaded(items: reminders, total: reminders.count)),
        ]
    }
}
