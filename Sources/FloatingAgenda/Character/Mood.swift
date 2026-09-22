import AppKit

/// 小精靈的心情（M9 計畫 §4.3）。
///
/// 判定寫成純函式，UI 只負責顯示。
enum Mood: String, CaseIterable {
    /// 有逾期的提醒，或任一專案卡住／亮紅燈
    case worried
    /// 沒有上面那些，但今天還有事要做
    case busy
    /// 全部清空
    case happy
    /// 提醒和專案都讀不到
    case sleepy

    var bodyColor: NSColor {
        switch self {
        case .worried: NSColor(srgbRed: 0.98, green: 0.62, blue: 0.24, alpha: 1)   // 橘
        case .busy: NSColor(srgbRed: 0.35, green: 0.62, blue: 0.96, alpha: 1)      // 藍
        case .happy: NSColor(srgbRed: 0.42, green: 0.80, blue: 0.47, alpha: 1)     // 綠
        case .sleepy: NSColor(srgbRed: 0.62, green: 0.64, blue: 0.68, alpha: 1)    // 灰
        }
    }

    /// 睡著的時候不彈跳也不抖（計畫 §4.3）
    var isAnimated: Bool { self != .sleepy }

    /// 只有 `worried` 是抖動，其餘會動的是上下彈跳
    var shakes: Bool { self == .worried }

    /// 決定心情。**純函式**，不碰任何全域狀態。
    ///
    /// 判定順序：worried → busy → sleepy → happy。
    ///
    /// ⚠️ 計畫 §4.3 的表格把 `sleepy` 列在最後，但照那個順序實作會出錯：
    /// 提醒和專案都讀不到時，「有逾期」「有今天到期」都不成立，
    /// 於是會先命中 `happy`（「全部清空」）——**把「讀不到」顯示成「都做完了」**。
    /// 所以 `sleepy` 必須排在 `happy` 之前。
    static func decide(reminders: SectionState<ReminderItem>,
                       projects: SectionState<ProjectItem>,
                       now: Date) -> Mood {
        let reminderItems = items(of: reminders)
        let projectItems = items(of: projects)

        let hasOverdue = reminderItems.contains { Formatting.isOverdue($0, now: now) }
        let hasBlockedOrRed = projectItems.contains { $0.blocker != nil || $0.status == .red }
        if hasOverdue || hasBlockedOrRed { return .worried }

        // 逾期的已經在上面處理掉了，剩下有到期日的就是今天到期的
        // （資料層只給「逾期 ＋ 今天到期」，PLAN §4.4）
        let hasDueToday = reminderItems.contains { $0.due != nil }
        let hasOpenTodos = projectItems.contains { !$0.openTodos.isEmpty }
        if hasDueToday || hasOpenTodos { return .busy }

        if !isReadable(reminders) && !isReadable(projects) { return .sleepy }

        return .happy
    }

    /// `loading` 也算讀不到：剛啟動還沒讀完時顯示睡著的樣子，比假裝「都清空了」誠實
    private static func isReadable<T>(_ state: SectionState<T>) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    private static func items<T>(of state: SectionState<T>) -> [T] {
        if case .loaded(let items, _) = state { return items }
        return []
    }
}
