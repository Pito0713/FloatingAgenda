import Foundation

/// 日期與時間文字。全部跟隨系統設定（含 12/24 小時制）與 Locale.autoupdatingCurrent。
/// 所有呼叫點都在主執行緒（UI 或 snapshot）。
enum Formatting {
    static let calendar = Calendar.autoupdatingCurrent

    /// 星期二
    private static let weekday: DateFormatter = template("EEEE")
    /// 9月15日
    private static let monthDay: DateFormatter = template("MMMd")
    /// 10:00（.short 會跟隨系統的 12/24 小時制）
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static func template(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    static func weekdayTitle(for date: Date) -> String { weekday.string(from: date) }
    static func dateTitle(for date: Date) -> String { monthDay.string(from: date) }
    static func timeString(for date: Date) -> String { time.string(from: date) }

    /// 行程時間：整天 / 進行中 · 至 HH:mm / HH:mm – HH:mm
    static func eventTimeLabel(for event: EventItem, now: Date) -> String {
        if event.isAllDay { return "整天" }
        if event.start <= now, now < event.end {
            return "進行中 · 至 \(timeString(for: event.end))"
        }
        return "\(timeString(for: event.start)) – \(timeString(for: event.end))"
    }
}

extension Formatting {
    /// 提醒到期文字（PLAN §4.4）：今天到期 → `今天 14:00`；逾期 → `9月14日 14:00`。
    /// 只有日期沒有時間的就不顯示時間。
    static func reminderDueLabel(for reminder: ReminderItem, now: Date) -> String? {
        guard let due = reminder.due else { return nil }
        let isToday = calendar.isDate(due, inSameDayAs: now)
        if reminder.dueHasTime {
            return isToday ? "今天 \(timeString(for: due))"
                           : "\(dateTitle(for: due)) \(timeString(for: due))"
        }
        return isToday ? "今天" : dateTitle(for: due)
    }

    /// 只有日期沒有時間的提醒代表「今天內都算」，要到當天結束才算逾期
    static func isOverdue(_ reminder: ReminderItem, now: Date) -> Bool {
        guard let due = reminder.due else { return false }
        return reminder.dueHasTime ? due < now : due < calendar.startOfDay(for: now)
    }
}

// MARK: - 展開模式的詳細資訊（使用者 2026-11-10 要求）

extension Formatting {
    /// 行程長度：15 分鐘／1 小時／1 小時 30 分；整天行程只有跨好幾天才講「3 天」，一天的回 nil
    static func eventDuration(for event: EventItem) -> String? {
        if event.isAllDay {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.start),
                                               to: calendar.startOfDay(for: event.end)).day ?? 1
            return days > 1 ? "\(days) 天" : nil
        }
        let minutes = Int(event.end.timeIntervalSince(event.start) / 60)
        guard minutes > 0 else { return nil }
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) 分鐘"
        case (_, 0): return "\(hours) 小時"
        default: return "\(hours) 小時 \(rest) 分"
        }
    }

    /// 行程列的第二行：時間 · 長度 · 行事曆名稱，缺的就略過
    static func eventDetail(for event: EventItem, now: Date) -> String {
        ([eventTimeLabel(for: event, now: now), eventDuration(for: event)]
            + [event.calendarTitle.isEmpty ? nil : event.calendarTitle])
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// 提醒的相對時間：逾期 3 天／逾期 2 小時／逾期 15 分鐘／還有 2 小時／還有 30 分鐘。
    /// 只有日期的提醒今天內不講相對時間（回 nil），過了才講逾期幾天
    static func reminderRelative(for reminder: ReminderItem, now: Date) -> String? {
        guard let due = reminder.due else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        if !calendar.isDate(due, inSameDayAs: now), due < startOfToday {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: due),
                                               to: startOfToday).day ?? 0
            return "逾期 \(max(days, 1)) 天"
        }
        guard reminder.dueHasTime else { return nil }
        let minutes = Int((due.timeIntervalSince(now) / 60).rounded(.towardZero))
        let span = abs(minutes) >= 60 ? "\(abs(minutes) / 60) 小時" : "\(max(abs(minutes), 1)) 分鐘"
        return minutes < 0 ? "逾期 \(span)" : "還有 \(span)"
    }

    /// 提醒事項 App 的驚嘆號：高 !!!、中 !!、低 !；沒設是 nil
    static func priorityMark(_ priority: Int) -> String? {
        switch priority {
        case 1...4: "!!!"
        case 5: "!!"
        case 6...9: "!"
        default: nil
        }
    }
}
