import AppKit
import SwiftUI
import XCTest
@testable import FloatingAgenda

/// 展開模式改成「看詳情」之後的文字規則（使用者 2026-11-10 要求）。
final class DetailFormattingTests: XCTestCase {

    private let now = Fixture.date(2026, 11, 10, 9, 0)

    // MARK: - 行程

    func testDurationText() {
        func duration(_ minutes: Double) -> String? {
            Formatting.eventDuration(for: Fixture.event("e", start: now,
                                                        end: now.addingTimeInterval(minutes * 60)))
        }
        XCTAssertEqual(duration(15), "15 分鐘")
        XCTAssertEqual(duration(60), "1 小時")
        XCTAssertEqual(duration(90), "1 小時 30 分")
        XCTAssertNil(duration(0), "零長度的行程不講長度")
    }

    func testAllDayDurationOnlyForMultiDay() {
        let start = Formatting.calendar.startOfDay(for: now)
        let oneDay = Fixture.event("一天", start: start, end: start.addingTimeInterval(86_400),
                                   isAllDay: true)
        let threeDays = Fixture.event("三天", start: start, end: start.addingTimeInterval(3 * 86_400),
                                      isAllDay: true)
        XCTAssertNil(Formatting.eventDuration(for: oneDay), "「整天」已經講完了，不必再說 1 天")
        XCTAssertEqual(Formatting.eventDuration(for: threeDays), "3 天")
    }

    func testEventDetailSkipsMissingCalendarTitle() {
        let event = Fixture.event("e", start: now.addingTimeInterval(3600),
                                  end: now.addingTimeInterval(7200))
        XCTAssertFalse(Formatting.eventDetail(for: event, now: now).hasSuffix(" · "))
        let titled = EventItem(eventIdentifier: "e", calendarID: "c", title: "e",
                               start: event.start, end: event.end, isAllDay: false,
                               color: .systemBlue, calendarTitle: "工作")
        XCTAssertTrue(Formatting.eventDetail(for: titled, now: now).hasSuffix("1 小時 · 工作"))
    }

    // MARK: - 提醒

    func testRelativeTimeForOverdueDays() {
        let threeDaysAgo = Fixture.reminder("r", due: Fixture.date(2026, 11, 7, 14, 30), dueHasTime: true)
        XCTAssertEqual(Formatting.reminderRelative(for: threeDaysAgo, now: now), "逾期 3 天")
        let yesterdayDateOnly = Fixture.reminder("r", due: Fixture.date(2026, 11, 9), dueHasTime: false)
        XCTAssertEqual(Formatting.reminderRelative(for: yesterdayDateOnly, now: now), "逾期 1 天")
    }

    func testRelativeTimeWithinToday() {
        let earlier = Fixture.reminder("r", due: Fixture.date(2026, 11, 10, 7, 0), dueHasTime: true)
        let later = Fixture.reminder("r", due: Fixture.date(2026, 11, 10, 11, 30), dueHasTime: true)
        let soon = Fixture.reminder("r", due: Fixture.date(2026, 11, 10, 9, 20), dueHasTime: true)
        XCTAssertEqual(Formatting.reminderRelative(for: earlier, now: now), "逾期 2 小時")
        XCTAssertEqual(Formatting.reminderRelative(for: later, now: now), "還有 2 小時")
        XCTAssertEqual(Formatting.reminderRelative(for: soon, now: now), "還有 20 分鐘")
    }

    func testDateOnlyDueTodayHasNoRelativeTime() {
        let today = Fixture.reminder("r", due: Fixture.date(2026, 11, 10), dueHasTime: false)
        XCTAssertNil(Formatting.reminderRelative(for: today, now: now))
    }

    func testPriorityMarksFollowEventKitRanges() {
        XCTAssertNil(Formatting.priorityMark(0))
        XCTAssertEqual(Formatting.priorityMark(1), "!!!")
        XCTAssertEqual(Formatting.priorityMark(5), "!!")
        XCTAssertEqual(Formatting.priorityMark(9), "!")
    }

    func testNoteKeepsOnlyTheFirstNonBlankLine() {
        XCTAssertEqual(AgendaStore.firstLine(of: "\n  記得附上報價單  \n第二行"), "記得附上報價單")
        XCTAssertNil(AgendaStore.firstLine(of: "  \n \n"))
        XCTAssertNil(AgendaStore.firstLine(of: nil))
    }

    // MARK: - 排程

    func testScheduleRunStatus() {
        func status(_ run: ScheduleRunState) -> String {
            Formatting.scheduleRunStatus(for: ScheduleItem(
                id: "local.x", name: "x", trigger: .none, run: run, logURL: nil,
                plistURL: URL(fileURLWithPath: "/tmp/local.x.plist")))
        }
        XCTAssertEqual(status(.running(pid: 4821)), "執行中 · PID 4821")
        XCTAssertEqual(status(.idle(lastExit: 0)), "上次結束 ✅ 正常")
        XCTAssertEqual(status(.idle(lastExit: 1)), "上次結束 ❌ 失敗（代碼 1）")
        XCTAssertEqual(status(.idle(lastExit: nil)), "已載入 · 還沒跑完過")
    }

    // MARK: - 捲動

    @MainActor
    func testScrollLimitLeavesScreenInsetAndPadding() {
        XCTAssertEqual(PanelController.maxContentHeight(screenHeight: 1000),
                       1000 - PanelMetrics.screenInset * 2 - PanelMetrics.padding * 2)
        XCTAssertEqual(PanelController.maxContentHeight(screenHeight: 100), 200,
                       "極端小的螢幕也要留得下標題與幾列")
    }
}

/// 專案卡改成跟著內容長高（原本固定 90pt，見 `ProjectCardView` 頭註）。
///
/// 用 `NSHostingView` 量真實排版：待辦與 review 列真的有畫出來，卡片就一定會變高。
/// 舊版是「先算能放幾項再少列」，這條防的是有人把那套截斷加回來
@MainActor
final class ProjectCardLayoutTests: XCTestCase {

    private let width = PanelMetrics.width - PanelMetrics.padding * 2

    func testEveryTodoIsShown() {
        let heights = [0, 3, 6, 9].map { height(of: project(todoCount: $0)) }
        XCTAssertEqual(heights, heights.sorted(), "待辦越多卡片要越高")
        XCTAssertGreaterThan(heights[3] - heights[2], 30, "第 7～9 項沒有被截掉")
    }

    func testReviewRowAddsALine() {
        var withReview = project(todoCount: 2)
        withReview.review = ReviewStatus(overall: .ok, ranAt: Date(), l1Result: "pass",
                                         failedChecks: [], carried: false, newFindings: 0,
                                         lagCommits: nil, reportURL: nil, firstError: nil)
        XCTAssertGreaterThan(height(of: withReview), height(of: project(todoCount: 2)))
    }

    private func height(of project: ProjectItem) -> CGFloat {
        let hosting = NSHostingView(rootView: ProjectCardView(project: project)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    private func project(todoCount: Int) -> ProjectItem {
        ProjectItem(id: "P", name: "測試專案", status: .yellow, statusText: "🟡 進行中",
                    updated: Date(), done: 3, total: 8,
                    openTodos: (0..<todoCount).map { "第 \($0 + 1) 項待辦" },
                    blocker: nil,
                    fileURL: URL(fileURLWithPath: "/tmp/P/latest.md"))
    }
}

/// 展開的卡片超過螢幕高度就捲動（使用者 2026-11-10 同意）。
///
/// 量真實排版：內容很長時整張卡的高度要停在 `maxContentHeight`（＋上下 padding），
/// 放得下時要照內容的高度，不能被撐到上限
@MainActor
final class WidgetScrollTests: XCTestCase {

    private func height(maxContentHeight: CGFloat?, reminderCount: Int) -> CGFloat {
        let now = Fixture.date(2026, 11, 10, 9, 0)
        let reminders = (0..<reminderCount).map {
            Fixture.reminder("提醒 \($0)", due: now.addingTimeInterval(Double($0) * 60),
                             dueHasTime: true)
        }
        let hosting = NSHostingView(rootView: WidgetView(
            eventsState: .loaded(items: [], total: 0),
            remindersState: .loaded(items: reminders, total: reminders.count),
            background: .opaque,
            now: now,
            maxContentHeight: maxContentHeight)
            .frame(width: PanelMetrics.width)
            .fixedSize(horizontal: false, vertical: true))
        // onGeometryChange 量到自然高度之後才會換成 ScrollView，多跑幾輪排版
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return hosting.fittingSize.height
    }

    func testTallContentIsCappedAtTheLimit() {
        let natural = height(maxContentHeight: nil, reminderCount: 40)
        XCTAssertGreaterThan(natural, 1000, "前提：40 筆提醒要夠高")
        XCTAssertEqual(height(maxContentHeight: 400, reminderCount: 40),
                       400 + PanelMetrics.padding * 2, accuracy: 1)
    }

    func testShortContentKeepsItsNaturalHeight() {
        let natural = height(maxContentHeight: nil, reminderCount: 2)
        XCTAssertEqual(height(maxContentHeight: 2000, reminderCount: 2), natural, accuracy: 1)
    }
}
