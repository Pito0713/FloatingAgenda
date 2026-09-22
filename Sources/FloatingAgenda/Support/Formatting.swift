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
