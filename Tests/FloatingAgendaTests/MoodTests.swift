import XCTest
@testable import FloatingAgenda

/// `Mood.decide` 的判定規則（M9 計畫 §4.3）。
final class MoodTests: XCTestCase {

    private let now = Fixture.date(2026, 9, 22, 14, 0)

    // MARK: - 建構樣本

    private func reminders(_ items: [ReminderItem]) -> SectionState<ReminderItem> {
        .loaded(items: items, total: items.count)
    }

    private func projects(_ items: [ProjectItem]) -> SectionState<ProjectItem> {
        .loaded(items: items, total: items.count)
    }

    private func project(status: ProjectStatus = .green,
                         blocker: String? = nil,
                         openTodos: [String] = []) -> ProjectItem {
        ProjectItem(id: "p", name: "p", status: status, statusText: "",
                    updated: nil, done: 0, total: openTodos.count,
                    openTodos: openTodos, blocker: blocker,
                    fileURL: URL(fileURLWithPath: "/tmp/p"))
    }

    private var overdueReminder: ReminderItem {
        Fixture.reminder("逾期", due: Fixture.date(2026, 9, 22, 9, 0), dueHasTime: true)
    }

    private var dueTodayReminder: ReminderItem {
        Fixture.reminder("今天到期", due: Fixture.date(2026, 9, 22, 18, 0), dueHasTime: true)
    }

    private func decide(_ r: SectionState<ReminderItem>,
                        _ p: SectionState<ProjectItem>) -> Mood {
        Mood.decide(reminders: r, projects: p, now: now)
    }

    // MARK: - worried

    func testOverdueReminderMakesItWorried() {
        XCTAssertEqual(decide(reminders([overdueReminder]), projects([])), .worried)
    }

    func testBlockedProjectMakesItWorried() {
        XCTAssertEqual(decide(reminders([]), projects([project(blocker: "卡住了")])), .worried)
    }

    func testRedProjectMakesItWorried() {
        XCTAssertEqual(decide(reminders([]), projects([project(status: .red)])), .worried)
    }

    /// worried 的優先度最高：同時有今天到期的事也還是 worried
    func testWorriedBeatsBusy() {
        XCTAssertEqual(decide(reminders([overdueReminder, dueTodayReminder]),
                              projects([project(openTodos: ["還沒做"])])), .worried)
    }

    // MARK: - busy

    func testDueTodayReminderMakesItBusy() {
        XCTAssertEqual(decide(reminders([dueTodayReminder]), projects([])), .busy)
    }

    func testOpenProjectTodoMakesItBusy() {
        XCTAssertEqual(decide(reminders([]), projects([project(openTodos: ["還沒做"])])), .busy)
    }

    /// 黃燈本身不算 worried，只有紅燈或卡住才算
    func testYellowProjectWithoutTodosIsNotWorried() {
        XCTAssertEqual(decide(reminders([]), projects([project(status: .yellow)])), .happy)
    }

    // MARK: - happy

    func testEverythingClearIsHappy() {
        XCTAssertEqual(decide(reminders([]), projects([])), .happy)
    }

    func testProjectWithAllTodosDoneIsHappy() {
        XCTAssertEqual(decide(reminders([]), projects([project(openTodos: [])])), .happy)
    }

    // MARK: - sleepy

    func testBothUnreadableIsSleepy() {
        XCTAssertEqual(decide(.needsPermission, .failed("找不到 ~/.agent-sessions")), .sleepy)
    }

    func testStillLoadingIsSleepy() {
        XCTAssertEqual(decide(.loading, .loading), .sleepy)
    }

    /// ⚠️ 這條是整個判定最關鍵的一條，也是計畫 §4.3 表格順序的陷阱：
    /// 照表格由上往下（worried → busy → happy → sleepy）實作的話，
    /// 讀不到資料時會先命中 happy「全部清空」，
    /// 等於**把「讀不到」顯示成「都做完了」**。sleepy 必須排在 happy 之前
    func testUnreadableIsNotMistakenForAllClear() {
        XCTAssertNotEqual(decide(.needsPermission, .failed("x")), .happy,
                          "讀不到資料不該顯示成「都清空了」")
    }

    /// 只有一邊讀不到就不算睡著（計畫 §4.3 要求**兩邊都**讀不到）
    func testOnlyRemindersUnreadableIsNotSleepy() {
        XCTAssertNotEqual(decide(.needsPermission, projects([])), .sleepy)
    }

    func testOnlyProjectsUnreadableIsNotSleepy() {
        XCTAssertNotEqual(decide(reminders([]), .failed("x")), .sleepy)
    }

    /// 提醒讀不到但專案有卡住 → 還是要 worried，不能因為一邊讀不到就放過
    func testUnreadableRemindersStillAllowWorried() {
        XCTAssertEqual(decide(.needsPermission, projects([project(blocker: "卡住了")])), .worried)
    }

    // MARK: - 邊界

    /// 只有日期沒有時間的提醒，今天到期不算逾期（沿用 Formatting.isOverdue 的規則）
    func testDateOnlyReminderDueTodayIsBusyNotWorried() {
        let item = Fixture.reminder("今天", due: Fixture.date(2026, 9, 22), dueHasTime: false)
        XCTAssertEqual(decide(reminders([item]), projects([])), .busy)
    }

    /// 沒有到期日的提醒不會讓它變忙（資料層只給逾期＋今天到期，這是防禦性的）
    func testReminderWithoutDueDateDoesNotMakeItBusy() {
        let item = Fixture.reminder("沒有到期日", due: nil, dueHasTime: false)
        XCTAssertEqual(decide(reminders([item]), projects([])), .happy)
    }

    // MARK: - 顯示屬性

    func testOnlySleepyStopsMoving() {
        XCTAssertFalse(Mood.sleepy.isAnimated, "睡著就不該彈跳")
        for mood in Mood.allCases where mood != .sleepy {
            XCTAssertTrue(mood.isAnimated)
        }
    }

    func testOnlyWorriedShakes() {
        XCTAssertTrue(Mood.worried.shakes)
        for mood in Mood.allCases where mood != .worried {
            XCTAssertFalse(mood.shakes, "\(mood) 應該是彈跳不是抖動")
        }
    }
}
