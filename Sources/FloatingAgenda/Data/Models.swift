import AppKit

/// 對 View 公開的純值型別。View 完全不碰 EKEvent / EKReminder，
/// `--snapshot` 才能用 mock 資料渲染同一套 UI。

struct EventItem: Identifiable, Hashable {
    /// 重複行程共用同一個 eventIdentifier，所以 id 必須加上開始時間才唯一
    let id: String
    /// 部分來源（例如某些生日與訂閱行事曆）的行程沒有 eventIdentifier。
    /// 沒有它就無法深層連結到那一筆，`openInCalendar` 會退回只開 App。
    let eventIdentifier: String?
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor

    /// - Parameter calendarID: 只用來在缺 `eventIdentifier` 時組出穩定的 `id`，不會被保存。
    init(eventIdentifier: String?,
         calendarID: String,
         title: String,
         start: Date,
         end: Date,
         isAllDay: Bool,
         color: NSColor) {
        // 沒有 eventIdentifier 時**絕不能用 UUID()**：那會讓每次重讀算出不同的 id，
        // SwiftUI 的 ForEach 識別跟著漂移，列會不斷重建、淡出動畫也會失準。
        // 改用「行事曆 ID ＋ 標題」這組在重讀之間穩定的欄位。
        // 結束時間也要納入：同行事曆、同標題、同開始時間但長度不同的兩筆
        // 是可能存在的，少了它就會撞號（codex 2026-09-21 指出）。
        //
        // 已知殘留限制：行事曆、標題、起訖時間**完全相同**的兩筆仍會撞號
        // （例如同名聯絡人在同一天生日）。這是刻意不修的：要再區分只剩「在陣列中的位置」
        // 可用，而陣列順序在重讀之間不保證穩定，那會讓 id 又變回不穩定——
        // 正是這次要修掉的問題。而且這兩筆在畫面上的每個欄位都一樣，合成一列並不會誤導。
        let key = eventIdentifier
            ?? "noid:\(calendarID):\(title):\(end.timeIntervalSince1970)"
        self.id = "\(key)|\(start.timeIntervalSince1970)"
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.color = color
    }
}

struct ReminderItem: Identifiable, Hashable {
    /// calendarItemIdentifier
    let id: String
    let title: String
    let due: Date?
    /// dueDateComponents 有沒有 hour——只有日期的提醒不顯示時間
    let dueHasTime: Bool
    /// 所屬清單顏色
    let color: NSColor
    let created: Date?
}

enum SectionState<T> {
    case loading
    case needsPermission
    case failed(String)
    case loaded(items: [T], total: Int)
}

/// 行事曆／提醒清單的顯示資訊（選單列篩選與 --dump 用）
struct CalendarInfo: Identifiable, Hashable {
    /// calendarIdentifier——有兩個同名的「Family」，一律用 ID 當 key，不能用名稱
    let id: String
    let title: String
    /// 來源（iCloud、Google 等）
    let sourceTitle: String
    let color: NSColor
    let isHidden: Bool
}
