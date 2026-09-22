import XCTest
@testable import FloatingAgenda

/// 泡泡輪播清單的組成規則（M9 計畫 §4.4）。
final class BubbleComposerTests: XCTestCase {

    private let now = Fixture.date(2026, 9, 22, 14, 0)

    private func reminders(_ items: [ReminderItem]) -> SectionState<ReminderItem> {
        .loaded(items: items, total: items.count)
    }

    private func projects(_ items: [ProjectItem]) -> SectionState<ProjectItem> {
        .loaded(items: items, total: items.count)
    }

    private func project(_ id: String,
                         blocker: String? = nil,
                         openTodos: [String] = []) -> ProjectItem {
        ProjectItem(id: id, name: id, status: .green, statusText: "",
                    updated: nil, done: 0, total: openTodos.count,
                    openTodos: openTodos, blocker: blocker,
                    fileURL: URL(fileURLWithPath: "/tmp/\(id)"))
    }

    private func overdue(_ title: String) -> ReminderItem {
        Fixture.reminder(title, due: Fixture.date(2026, 9, 22, 9, 0), dueHasTime: true, id: title)
    }

    private func dueToday(_ title: String) -> ReminderItem {
        Fixture.reminder(title, due: Fixture.date(2026, 9, 22, 18, 0), dueHasTime: true, id: title)
    }

    private func lines(_ r: SectionState<ReminderItem>,
                       _ p: SectionState<ProjectItem>) -> [String] {
        BubbleComposer.lines(reminders: r, projects: p, now: now).map(\.text)
    }

    // MARK: - 優先順序

    /// §4.4 的五個層級要照順序出現
    func testLinesFollowThePrescribedOrder() {
        let result = lines(reminders([overdue("逾期的"), dueToday("今天的")]),
                           projects([project("甲", blocker: "卡住原因"),
                                     project("乙", openTodos: ["下一件事"])]))
        XCTAssertEqual(result, [
            "⏰ 逾期：逾期的",
            "📌 今天：今天的",
            "⚠️ 甲 卡住了：卡住原因",
            "🔧 乙：下一件事",
            "今天還有 3 件事，點我看看",
        ])
    }

    /// 逾期的**全部列出**，不設上限
    func testAllOverdueRemindersAreListed() {
        let items = (1...6).map { overdue("逾期\($0)") }
        let result = lines(reminders(items), projects([]))
        XCTAssertEqual(result.filter { $0.hasPrefix("⏰") }.count, 6)
    }

    /// 今天到期的**最多 3 則**
    func testDueTodayIsCappedAtThree() {
        let items = (1...6).map { dueToday("今天\($0)") }
        let result = lines(reminders(items), projects([]))
        XCTAssertEqual(result.filter { $0.hasPrefix("📌") }.count, BubbleComposer.dueTodayLimit)
    }

    /// 每個專案只取**第一件**還沒做的事
    func testOnlyTheFirstOpenTodoPerProject() {
        let result = lines(reminders([]),
                           projects([project("甲", openTodos: ["第一件", "第二件", "第三件"])]))
        XCTAssertEqual(result.filter { $0.hasPrefix("🔧") }, ["🔧 甲：第一件"])
    }

    /// 卡住的描述只取第一行（泡泡最多 3 行）
    func testBlockerUsesOnlyTheFirstLine() {
        let result = lines(reminders([]),
                           projects([project("甲", blocker: "第一行\n第二行\n第三行")]))
        XCTAssertEqual(result.filter { $0.hasPrefix("⚠️") }, ["⚠️ 甲 卡住了：第一行"])
    }

    /// 一個專案同時卡住又有待辦 → 兩則都要出現，而且卡住的排在前面
    func testBlockedProjectWithTodosProducesBothLines() {
        let result = lines(reminders([]),
                           projects([project("甲", blocker: "卡住", openTodos: ["待辦"])]))
        XCTAssertEqual(result.firstIndex(of: "⚠️ 甲 卡住了：卡住")!,
                       result.firstIndex(of: "🔧 甲：待辦")! - 1)
    }

    // MARK: - 總結

    /// 總結一定是最後一則，而且一定存在
    func testSummaryIsAlwaysLast() {
        for (r, p) in [(reminders([]), projects([])),
                       (reminders([overdue("x")]), projects([])),
                       (reminders([]), projects([project("甲", openTodos: ["y"])]))] {
            let result = lines(r, p)
            XCTAssertFalse(result.isEmpty)
            XCTAssertTrue(result.last!.contains("今天"), "最後一則應該是總結：\(result.last!)")
        }
    }

    /// 全部清空時只有一則，而且是「都清空了」
    func testEverythingClearGivesOnlyTheCelebration() {
        XCTAssertEqual(lines(reminders([]), projects([])), ["今天都清空了 ✨"])
    }

    /// 總結的數字要把逾期、今天到期與**所有**專案待辦都算進去，
    /// 不是只算泡泡上列出來的那幾則
    func testSummaryCountsEverythingNotJustTheListedLines() {
        let result = lines(reminders((1...5).map { dueToday("今天\($0)") }),
                           projects([project("甲", openTodos: ["一", "二", "三"])]))
        // 5 則今天到期（泡泡只列 3 則）＋ 3 件專案待辦（泡泡只列 1 件）＝ 8
        XCTAssertEqual(result.last, "今天還有 8 件事，點我看看")
    }

    // MARK: - 讀不到資料

    /// ⚠️ 兩邊都讀不到時**不能說「都清空了」**：那會跟 sleepy 的睡臉自相矛盾，
    /// 也會讓使用者以為今天真的沒事。§4.4 沒有定義這個情況的文案，這是自行補的
    func testUnreadableDataDoesNotClaimEverythingIsDone() {
        let result = lines(.needsPermission, .failed("找不到"))
        XCTAssertEqual(result, ["還讀不到資料…"])
    }

    func testStillLoadingDoesNotClaimEverythingIsDone() {
        XCTAssertEqual(lines(.loading, .loading), ["還讀不到資料…"])
    }

    /// 只有一邊讀不到、另一邊真的是空的 → 照樣算清空
    func testOneSideReadableAndEmptyStillCounts() {
        XCTAssertEqual(lines(reminders([]), .failed("找不到")), ["今天都清空了 ✨"])
        XCTAssertEqual(lines(.needsPermission, projects([])), ["今天都清空了 ✨"])
    }

    // MARK: - id 穩定性

    /// 同樣的輸入要得到同樣的 id，否則輪播每次重建都會跳回第一則
    func testIDsAreStableAcrossRebuilds() {
        let r = reminders([overdue("甲"), dueToday("乙")])
        let p = projects([project("丙", openTodos: ["丁"])])
        let first = BubbleComposer.lines(reminders: r, projects: p, now: now).map(\.id)
        let second = BubbleComposer.lines(reminders: r, projects: p, now: now).map(\.id)
        XCTAssertEqual(first, second)
    }

    /// 不同來源的 id 不能撞號
    func testIDsAreUniqueAcrossCategories() {
        let result = BubbleComposer.lines(
            reminders: reminders([overdue("同名"), dueToday("同名2")]),
            projects: projects([project("同名", blocker: "x", openTodos: ["y"])]),
            now: now)
        XCTAssertEqual(Set(result.map(\.id)).count, result.count, "id 有重複")
    }
}

/// 輪播狀態機：什麼時候換下一則、資料更新時怎麼處理（§4.4）
final class BubbleRotationTests: XCTestCase {

    private func line(_ id: String) -> BubbleComposer.Line {
        BubbleComposer.Line(id: id, text: id)
    }

    func testEmptyRotationHasNothingToShow() {
        XCTAssertNil(BubbleRotation().current)
    }

    func testAdvanceMovesToTheNextLine() {
        var rotation = BubbleRotation(lines: [line("a"), line("b"), line("c")])
        XCTAssertEqual(rotation.current?.id, "a")
        rotation.advance()
        XCTAssertEqual(rotation.current?.id, "b")
    }

    /// 輪完一圈從頭開始
    func testAdvanceWrapsAround() {
        var rotation = BubbleRotation(lines: [line("a"), line("b")])
        rotation.advance()
        rotation.advance()
        XCTAssertEqual(rotation.current?.id, "a")
    }

    func testAdvanceOnEmptyDoesNotCrash() {
        var rotation = BubbleRotation()
        rotation.advance()
        XCTAssertNil(rotation.current)
    }

    /// ⚠️ §4.4 最不直觀的一條：資料更新**不要打斷**正在顯示的那一則。
    /// 它在新清單裡換了位置也一樣，游標要跟著它走
    func testUpdateKeepsShowingTheCurrentLine() {
        var rotation = BubbleRotation(lines: [line("a"), line("b"), line("c")])
        rotation.advance()
        XCTAssertEqual(rotation.current?.id, "b")

        // b 在新清單裡跑到最後面
        rotation.update(lines: [line("c"), line("a"), line("b")])
        XCTAssertEqual(rotation.current?.id, "b", "正在顯示的那一則不該被打斷")
    }

    /// ⚠️ **id 相同但文字變了**，不算「這一則不見了」。
    ///
    /// 最常見的情況是總結那一則：「今天還有 3 件事」→「今天還有 2 件事」。
    /// 若用整個 `Line` 去比對就會判定成消失而跳回第一則，
    /// 每次資料更新都會打斷正在顯示的訊息（codex 2026-09-22 指出）
    func testUpdateKeepsTheCurrentLineWhenOnlyItsTextChanges() {
        var rotation = BubbleRotation(lines: [line("a"), line("summary"), line("c")])
        rotation.advance()
        XCTAssertEqual(rotation.current?.id, "summary")

        rotation.update(lines: [line("a"),
                                BubbleComposer.Line(id: "summary", text: "今天還有 2 件事"),
                                line("c")])
        XCTAssertEqual(rotation.current?.id, "summary", "只有文字變不該打斷")
        XCTAssertEqual(rotation.current?.text, "今天還有 2 件事", "但要顯示新的文字")
    }

    /// 正在顯示的那一則不在新清單裡了（例如那筆提醒被完成）→ 立刻換
    func testUpdateJumpsAwayWhenTheCurrentLineIsGone() {
        var rotation = BubbleRotation(lines: [line("a"), line("b"), line("c")])
        rotation.advance()
        XCTAssertEqual(rotation.current?.id, "b")

        rotation.update(lines: [line("a"), line("c")])
        XCTAssertEqual(rotation.current?.id, "a", "消失的那一則應該立刻換掉")
    }

    /// 內容完全沒變就什麼都不做，不能把游標重設回第一則
    func testUpdateWithIdenticalLinesIsANoOp() {
        let lines = [line("a"), line("b"), line("c")]
        var rotation = BubbleRotation(lines: lines)
        rotation.advance()
        rotation.update(lines: lines)
        XCTAssertEqual(rotation.current?.id, "b")
    }

    func testUpdateToEmptyLeavesNothingToShow() {
        var rotation = BubbleRotation(lines: [line("a")])
        rotation.update(lines: [])
        XCTAssertNil(rotation.current)
    }
}
