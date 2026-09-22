import AppKit
import XCTest
@testable import FloatingAgenda

/// 測試共用的建構工具。
///
/// 一律用 `Formatting.calendar`（＝production 用的同一個 `Calendar.autoupdatingCurrent`）
/// 來組日期，測試才不會因為時區而與實際行為脫節。
enum Fixture {
    static func date(_ year: Int, _ month: Int, _ day: Int,
                     _ hour: Int = 0, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day,
                                        hour: hour, minute: minute)
        guard let date = Formatting.calendar.date(from: components) else {
            fatalError("測試用日期組不起來：\(year)-\(month)-\(day) \(hour):\(minute)")
        }
        return date
    }

    /// - Parameter identifier: 傳 `nil` 代表這筆行程沒有 eventIdentifier
    ///   （部分生日／訂閱行事曆的真實情況）
    static func event(_ title: String,
                      start: Date,
                      end: Date,
                      isAllDay: Bool = false,
                      identifier: String? = nil,
                      hasIdentifier: Bool = true,
                      calendarID: String = "cal") -> EventItem {
        EventItem(eventIdentifier: hasIdentifier ? (identifier ?? title) : nil,
                  calendarID: calendarID,
                  title: title,
                  start: start,
                  end: end,
                  isAllDay: isAllDay,
                  color: .systemBlue)
    }

    static func reminder(_ title: String,
                         due: Date?,
                         dueHasTime: Bool,
                         created: Date? = nil,
                         id: String? = nil) -> ReminderItem {
        ReminderItem(id: id ?? title,
                     title: title,
                     due: due,
                     dueHasTime: dueHasTime,
                     color: .systemBlue,
                     created: created)
    }

    /// 全新的記憶體設定存放區。完全不觸碰檔案系統，也不可能動到使用者真實的 App 設定。
    @MainActor
    static func settings() -> AppSettings {
        AppSettings(defaults: InMemorySettingsStore())
    }

    /// 需要直接操作底層存放區（例如塞進型別不對的值）時用這個
    @MainActor
    static func settingsWithStore() -> (AppSettings, InMemorySettingsStore) {
        let store = InMemorySettingsStore()
        return (AppSettings(defaults: store), store)
    }
}
