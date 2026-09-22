import XCTest
@testable import FloatingAgenda

/// `Formatting.isOverdue` / `reminderDueLabel` 的日期邊界。
///
/// 這裡的第一個測試對應一個真實 bug：2026-09-18 之前「只有日期沒有時間」的提醒
/// 會從當天午夜就被判定為逾期而顯示紅字。只有日期的到期日語意是「今天內都算」，
/// 必須跟當天 00:00 比，不能跟 now 比。
final class FormattingTests: XCTestCase {
    private let now = Fixture.date(2026, 9, 18, 9, 0)

    // MARK: - isOverdue

    @MainActor
    func testDateOnlyDueTodayIsNotOverdue() {
        let reminder = Fixture.reminder("買牛奶",
                                        due: Fixture.date(2026, 9, 18),
                                        dueHasTime: false)
        XCTAssertFalse(Formatting.isOverdue(reminder, now: now),
                       "只有日期、到期日是今天 → 整天都還沒逾期")
    }

    @MainActor
    func testDateOnlyDueYesterdayIsOverdue() {
        let reminder = Fixture.reminder("昨天的",
                                        due: Fixture.date(2026, 9, 17),
                                        dueHasTime: false)
        XCTAssertTrue(Formatting.isOverdue(reminder, now: now))
    }

    @MainActor
    func testTimedDueEarlierTodayIsOverdue() {
        let reminder = Fixture.reminder("早上七點",
                                        due: Fixture.date(2026, 9, 18, 7, 0),
                                        dueHasTime: true)
        XCTAssertTrue(Formatting.isOverdue(reminder, now: now))
    }

    @MainActor
    func testTimedDueLaterTodayIsNotOverdue() {
        let reminder = Fixture.reminder("下午兩點",
                                        due: Fixture.date(2026, 9, 18, 14, 0),
                                        dueHasTime: true)
        XCTAssertFalse(Formatting.isOverdue(reminder, now: now))
    }

    @MainActor
    func testTimedDueExactlyNowIsNotOverdue() {
        let reminder = Fixture.reminder("正好現在", due: now, dueHasTime: true)
        XCTAssertFalse(Formatting.isOverdue(reminder, now: now),
                       "判定是 due < now，剛好相等不算逾期")
    }

    @MainActor
    func testNoDueDateIsNeverOverdue() {
        let reminder = Fixture.reminder("沒有到期日", due: nil, dueHasTime: false)
        XCTAssertFalse(Formatting.isOverdue(reminder, now: now))
    }

    // MARK: - reminderDueLabel
    //
    // 只驗「選對分支」（有沒有今天前綴、有沒有帶時間），不驗 DateFormatter 本身的輸出格式，
    // 因為時間格式會跟隨系統的 12/24 小時制設定。

    @MainActor
    func testLabelForTimedDueTodayHasTodayPrefixAndTime() {
        let due = Fixture.date(2026, 9, 18, 14, 0)
        let reminder = Fixture.reminder("領包裹", due: due, dueHasTime: true)
        XCTAssertEqual(Formatting.reminderDueLabel(for: reminder, now: now),
                       "今天 \(Formatting.timeString(for: due))")
    }

    @MainActor
    func testLabelForDateOnlyDueTodayIsTodayWithoutTime() {
        let reminder = Fixture.reminder("買牛奶",
                                        due: Fixture.date(2026, 9, 18),
                                        dueHasTime: false)
        XCTAssertEqual(Formatting.reminderDueLabel(for: reminder, now: now), "今天")
    }

    @MainActor
    func testLabelForTimedOverdueUsesDateAndTime() {
        let due = Fixture.date(2026, 9, 14, 14, 0)
        let reminder = Fixture.reminder("逾期的", due: due, dueHasTime: true)
        XCTAssertEqual(Formatting.reminderDueLabel(for: reminder, now: now),
                       "\(Formatting.dateTitle(for: due)) \(Formatting.timeString(for: due))")
    }

    @MainActor
    func testLabelForDateOnlyOverdueUsesDateOnly() {
        let due = Fixture.date(2026, 9, 14)
        let reminder = Fixture.reminder("逾期只有日期", due: due, dueHasTime: false)
        XCTAssertEqual(Formatting.reminderDueLabel(for: reminder, now: now),
                       Formatting.dateTitle(for: due))
    }

    @MainActor
    func testLabelIsNilWhenNoDueDate() {
        let reminder = Fixture.reminder("沒有到期日", due: nil, dueHasTime: false)
        XCTAssertNil(Formatting.reminderDueLabel(for: reminder, now: now))
    }

    // MARK: - eventTimeLabel

    @MainActor
    func testAllDayEventLabel() {
        let event = Fixture.event("中秋節",
                                  start: Fixture.date(2026, 9, 18),
                                  end: Fixture.date(2026, 9, 19),
                                  isAllDay: true)
        XCTAssertEqual(Formatting.eventTimeLabel(for: event, now: now), "整天")
    }

    @MainActor
    func testInProgressEventLabel() {
        let event = Fixture.event("工作會議",
                                  start: Fixture.date(2026, 9, 18, 8, 30),
                                  end: Fixture.date(2026, 9, 18, 9, 30))
        XCTAssertEqual(Formatting.eventTimeLabel(for: event, now: now),
                       "進行中 · 至 \(Formatting.timeString(for: event.end))")
    }

    /// 「進行中」的判定邊界與 `inProgressEvent` 是各自獨立的實作
    /// （一個決定文案、一個決定收合模式挑哪筆），所以兩邊都要測。
    /// 由 codex 在審查測試時指出（2026-09-18）。
    @MainActor
    func testEventStartingExactlyNowShowsInProgress() {
        let event = Fixture.event("正好開始",
                                  start: now,
                                  end: Fixture.date(2026, 9, 18, 10, 0))
        XCTAssertEqual(Formatting.eventTimeLabel(for: event, now: now),
                       "進行中 · 至 \(Formatting.timeString(for: event.end))",
                       "判定是 start <= now，剛好開始就算進行中")
    }

    @MainActor
    func testEventEndingExactlyNowShowsTimeRangeNotInProgress() {
        let event = Fixture.event("正好結束",
                                  start: Fixture.date(2026, 9, 18, 8, 0),
                                  end: now)
        XCTAssertEqual(Formatting.eventTimeLabel(for: event, now: now),
                       "\(Formatting.timeString(for: event.start)) – \(Formatting.timeString(for: event.end))",
                       "判定是 now < end，剛好結束就不再是進行中")
    }

    @MainActor
    func testFinishedEventShowsTimeRange() {
        let event = Fixture.event("已結束",
                                  start: Fixture.date(2026, 9, 18, 7, 0),
                                  end: Fixture.date(2026, 9, 18, 8, 0))
        XCTAssertEqual(Formatting.eventTimeLabel(for: event, now: now),
                       "\(Formatting.timeString(for: event.start)) – \(Formatting.timeString(for: event.end))")
    }

    @MainActor
    func testUpcomingEventLabelIsTimeRange() {
        let event = Fixture.event("煮飯",
                                  start: Fixture.date(2026, 9, 18, 14, 0),
                                  end: Fixture.date(2026, 9, 18, 15, 0))
        XCTAssertEqual(Formatting.eventTimeLabel(for: event, now: now),
                       "\(Formatting.timeString(for: event.start)) – \(Formatting.timeString(for: event.end))")
    }
}
