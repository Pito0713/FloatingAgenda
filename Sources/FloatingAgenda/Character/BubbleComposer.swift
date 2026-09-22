import Foundation

/// 對話泡泡的輪播清單（M9 計畫 §4.4）。
///
/// **純函式**：不碰任何全域狀態，也不管什麼時候換下一則——那是 `BubbleRotation` 的事。
enum BubbleComposer {

    /// 一則泡泡。`id` 讓輪播能在資料更新後認出「正在顯示的那一則還在不在」
    struct Line: Identifiable, Hashable {
        let id: String
        let text: String
    }

    /// 今天到期的提醒最多列幾則（§4.4）
    static let dueTodayLimit = 3

    /// 依 §4.4 的優先順序組出輪播清單。
    ///
    /// 1. 逾期提醒（全部列出）
    /// 2. 今天到期的提醒（最多 3 則）
    /// 3. 卡住的專案
    /// 4. 每個專案的下一件待辦
    /// 5. 最後一則固定是總結
    static func lines(reminders: SectionState<ReminderItem>,
                      projects: SectionState<ProjectItem>,
                      now: Date) -> [Line] {
        let reminderItems = items(of: reminders)
        let projectItems = items(of: projects)

        var lines: [Line] = []

        let overdue = reminderItems.filter { Formatting.isOverdue($0, now: now) }
        for reminder in overdue {
            lines.append(Line(id: "overdue:\(reminder.id)", text: "⏰ 逾期：\(reminder.title)"))
        }

        // 逾期的已經在上面列完了，剩下有到期日的就是今天到期的
        // （資料層只給「逾期 ＋ 今天到期」，PLAN §4.4）
        let dueToday = reminderItems.filter {
            $0.due != nil && !Formatting.isOverdue($0, now: now)
        }
        for reminder in dueToday.prefix(dueTodayLimit) {
            lines.append(Line(id: "today:\(reminder.id)", text: "📌 今天：\(reminder.title)"))
        }

        for project in projectItems {
            guard let blocker = project.blocker else { continue }
            // 只取第一行：卡住的描述可能很長，泡泡最多 3 行
            let firstLine = blocker.split(separator: "\n", maxSplits: 1).first.map(String.init)
                ?? blocker
            lines.append(Line(id: "blocked:\(project.id)",
                              text: "⚠️ \(project.name) 卡住了：\(firstLine)"))
        }

        for project in projectItems {
            guard let next = project.openTodos.first else { continue }
            lines.append(Line(id: "todo:\(project.id)", text: "🔧 \(project.name)：\(next)"))
        }

        // 總結一定是最後一則，而且一定存在——沒有它的話「全部清空」時泡泡會是空的
        let outstanding = overdue.count + dueToday.count
            + projectItems.reduce(0) { $0 + $1.openTodos.count }
        if outstanding > 0 {
            lines.append(Line(id: "summary", text: "今天還有 \(outstanding) 件事，點我看看"))
        } else if isReadable(reminders) || isReadable(projects) {
            lines.append(Line(id: "summary", text: "今天都清空了 ✨"))
        } else {
            // 兩邊都讀不到的時候**不能說「都清空了」**：那會跟 sleepy 的睡臉自相矛盾，
            // 也會讓使用者以為今天沒事。計畫 §4.4 沒有定義這個情況的文案
            lines.append(Line(id: "summary", text: "還讀不到資料…"))
        }
        return lines
    }

    private static func isReadable<T>(_ state: SectionState<T>) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    private static func items<T>(of state: SectionState<T>) -> [T] {
        if case .loaded(let items, _) = state { return items }
        return []
    }
}

/// 泡泡輪播的狀態機（§4.4）。
///
/// 抽成值型別是為了讓「資料更新時不要打斷正在顯示的那一則」這條規則能被單元測試釘住——
/// 那是這段邏輯裡唯一不直觀的地方。
struct BubbleRotation: Equatable {
    /// 每則顯示幾秒
    static let interval: TimeInterval = 8

    private(set) var lines: [BubbleComposer.Line]
    private(set) var index: Int

    init(lines: [BubbleComposer.Line] = []) {
        self.lines = lines
        index = 0
    }

    var current: BubbleComposer.Line? {
        guard lines.indices.contains(index) else { return nil }
        return lines[index]
    }

    /// 時間到，換下一則；輪完一圈從頭開始
    mutating func advance() {
        guard !lines.isEmpty else { return }
        index = (index + 1) % lines.count
    }

    /// 資料更新。
    ///
    /// **不要打斷正在顯示的那一則**：若它還在新清單裡，就把游標移到它的新位置，
    /// 等這一則的 8 秒走完再換。只有當它已經不在新清單裡（例如那筆提醒被完成了），
    /// 才立刻跳到下一則（§4.4）。
    mutating func update(lines newLines: [BubbleComposer.Line]) {
        guard newLines != lines else { return }
        let showing = current
        lines = newLines
        // ⚠️ 只比 `id` 不比整個 `Line`：總結那一則的文字會隨件數變
        //（「今天還有 3 件事」→「2 件事」），提醒改名也一樣。
        // 拿整個值去找會判定成「這一則不見了」而跳回第一則，
        // 正好違反「資料更新不要打斷正在顯示的那一則」（codex 2026-09-22 指出）
        guard let showing, let position = newLines.firstIndex(where: { $0.id == showing.id }) else {
            // 正在顯示的那一則不見了（或本來就沒有）→ 從頭開始
            index = 0
            return
        }
        index = position
    }
}
