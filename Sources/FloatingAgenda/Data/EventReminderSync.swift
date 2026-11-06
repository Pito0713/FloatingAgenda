import AppKit
import EventKit
import Foundation

/// 把今天的行程轉成提醒事項：一筆行程一筆提醒，到期時間就是行程的開始時間。
///
/// 防重複靠提醒的 `url`：每筆轉出來的提醒都帶著 `floatingagenda://event?id=<EventItem.id>`，
/// `EventItem.id` 含開始時間，所以重複行程每天各算一筆，同一天跑幾次都只建一次。
/// 只新增，不會修改或刪除任何既有提醒，也不會跟著行程的修改同步。
@MainActor
enum EventReminderSync {
    /// 轉出來的提醒都放在這個清單，跟使用者原本的待辦分開；沒有就建一個
    static let listTitle = "行程"

    struct Draft: Equatable {
        let key: URL
        let title: String
        let due: DateComponents
    }

    static func key(for event: EventItem) -> URL? {
        var components = URLComponents()
        components.scheme = "floatingagenda"
        components.host = "event"
        components.queryItems = [URLQueryItem(name: "id", value: event.id)]
        return components.url
    }

    /// 要轉的行程：開始時間在今天、而且還沒結束（進行中的照轉）。
    /// 昨天開始、跨過午夜的不算；已經結束的不轉，晚開機也不會冒出一堆逾期提醒。
    static func eligible(_ events: [EventItem], now: Date, calendar: Calendar) -> [EventItem] {
        events
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
            .filter { $0.isAllDay || $0.end > now }
            .sorted(by: AgendaStore.eventOrder)
    }

    /// 純函式：決定要建哪些提醒。`existingKeys` 裡已經有的跳過。
    static func drafts(for events: [EventItem],
                       now: Date,
                       existingKeys: Set<URL>,
                       calendar: Calendar) -> [Draft] {
        eligible(events, now: now, calendar: calendar)
            .compactMap { event in
                guard let key = key(for: event), !existingKeys.contains(key) else { return nil }
                // 整天行程只設日期：dueDateComponents 沒有 hour，提醒事項 App 就不顯示時間
                let fields: Set<Calendar.Component> = event.isAllDay
                    ? [.year, .month, .day]
                    : [.year, .month, .day, .hour, .minute]
                var due = calendar.dateComponents(fields, from: event.start)
                due.calendar = calendar
                due.timeZone = calendar.timeZone
                return Draft(key: key, title: event.title, due: due)
            }
    }

    /// 「今天已經轉過」記的日期字串，用本地日曆的年月日
    static func dayStamp(for now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 每天自動轉換：開關打開、而且今天還沒成功轉過才跑。
    /// 一天只跑一次，使用者當天刪掉的提醒才不會被下一輪重讀建回來
    static func shouldAutoRun(enabled: Bool, lastDay: String?, now: Date, calendar: Calendar) -> Bool {
        enabled && lastDay != dayStamp(for: now, calendar: calendar)
    }
}

/// 實際讀寫 EventKit 的部分。`dryRun` 時只回傳會建哪些，完全不寫入。
@MainActor
struct EventKitEventReminderSync {
    let store: EKEventStore
    let settings: AppSettings

    struct Result {
        let created: [EventReminderSync.Draft]
        let skipped: Int
        let listTitle: String
    }

    enum SyncError: LocalizedError {
        case noAccess
        case noSourceForList

        var errorDescription: String? {
            switch self {
            case .noAccess: "需要行事曆與提醒事項的完整存取權限"
            case .noSourceForList: "找不到可以建立提醒清單的帳號"
            }
        }
    }

    func run(now: Date = Date(), dryRun: Bool) async throws -> Result {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            throw SyncError.noAccess
        }

        let calendar = Formatting.calendar
        let events = todaysEvents(now: now, calendar: calendar)
        let list = existingList()
        let existingKeys = await keys(in: list)
        let drafts = EventReminderSync.drafts(for: events, now: now,
                                              existingKeys: existingKeys, calendar: calendar)
        let skipped = EventReminderSync.eligible(events, now: now, calendar: calendar).count - drafts.count

        guard !dryRun, !drafts.isEmpty else {
            return Result(created: drafts, skipped: skipped, listTitle: EventReminderSync.listTitle)
        }

        let target = try list ?? makeList()
        for draft in drafts {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = target
            reminder.title = draft.title
            reminder.dueDateComponents = draft.due
            reminder.url = draft.key
            try store.save(reminder, commit: false)
        }
        try store.commit()
        return Result(created: drafts, skipped: skipped, listTitle: target.title)
    }

    /// 跟卡片用同一套篩選：選單列隱藏的行事曆不轉
    private func todaysEvents(now: Date, calendar: Calendar) -> [EventItem] {
        let hidden = settings.hiddenCalendarIDs
        let visible = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        let startOfToday = calendar.startOfDay(for: now)
        guard !visible.isEmpty,
              let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return [] }

        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: visible)
        return store.events(matching: predicate).map { event in
            EventItem(eventIdentifier: event.eventIdentifier,
                      calendarID: event.calendar.calendarIdentifier,
                      title: event.title ?? "（無標題）",
                      start: event.startDate,
                      end: event.endDate,
                      isAllDay: event.isAllDay,
                      color: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue)
        }
    }

    private func existingList() -> EKCalendar? {
        store.calendars(for: .reminder).first { $0.title == EventReminderSync.listTitle }
    }

    /// 已完成的也要算進來，否則使用者勾掉之後下次又會被建回來
    private func keys(in list: EKCalendar?) async -> Set<URL> {
        guard let list else { return [] }
        let predicate = store.predicateForReminders(in: [list])
        let urls: [URL] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).compactMap(\.url))
            }
        }
        return Set(urls)
    }

    /// 建在預設提醒清單所在的帳號（通常是 iCloud）
    private func makeList() throws -> EKCalendar {
        guard let source = store.defaultCalendarForNewReminders()?.source else {
            throw SyncError.noSourceForList
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = EventReminderSync.listTitle
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }
}
