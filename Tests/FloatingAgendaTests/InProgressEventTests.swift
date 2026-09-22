import XCTest
@testable import FloatingAgenda

/// `CollapsedCardView.inProgressEvent`（PLAN §4.10）。
///
/// 收合模式只顯示一列行程，所以「挑哪一筆」的規則必須明確：
/// 條件是 `start <= now < end`，同時有多筆時**有時間的優先於整天行程**
/// （使用者要的是「當前時間區間」，整天行程沒有那個語意）。
final class InProgressEventTests: XCTestCase {
    private let now = Fixture.date(2026, 9, 18, 9, 0)

    @MainActor
    func testReturnsOngoingTimedEvent() {
        let ongoing = Fixture.event("進行中",
                                    start: Fixture.date(2026, 9, 18, 8, 30),
                                    end: Fixture.date(2026, 9, 18, 9, 30))
        let later = Fixture.event("稍後",
                                  start: Fixture.date(2026, 9, 18, 14, 0),
                                  end: Fixture.date(2026, 9, 18, 15, 0))
        XCTAssertEqual(CollapsedCardView.inProgressEvent(in: [ongoing, later], now: now)?.title,
                       "進行中")
    }

    @MainActor
    func testEventStartingExactlyNowCounts() {
        let event = Fixture.event("正好開始",
                                  start: now,
                                  end: Fixture.date(2026, 9, 18, 10, 0))
        XCTAssertEqual(CollapsedCardView.inProgressEvent(in: [event], now: now)?.title, "正好開始")
    }

    @MainActor
    func testEventEndingExactlyNowDoesNotCount() {
        let event = Fixture.event("正好結束",
                                  start: Fixture.date(2026, 9, 18, 8, 0),
                                  end: now)
        XCTAssertNil(CollapsedCardView.inProgressEvent(in: [event], now: now),
                     "條件是 now < end，剛好在結束瞬間就不該再顯示為進行中")
    }

    @MainActor
    func testTimedEventWinsOverAllDay() {
        let allDay = Fixture.event("中秋節",
                                   start: Fixture.date(2026, 9, 18),
                                   end: Fixture.date(2026, 9, 19),
                                   isAllDay: true)
        let timed = Fixture.event("工作會議",
                                  start: Fixture.date(2026, 9, 18, 8, 30),
                                  end: Fixture.date(2026, 9, 18, 9, 30))
        // 刻意把整天行程放在陣列前面（production 的排序也是整天優先），
        // 確認挑選邏輯不是單純取第一筆
        XCTAssertEqual(CollapsedCardView.inProgressEvent(in: [allDay, timed], now: now)?.title,
                       "工作會議")
    }

    @MainActor
    func testFallsBackToAllDayWhenNoTimedEventOngoing() {
        let allDay = Fixture.event("中秋節",
                                   start: Fixture.date(2026, 9, 18),
                                   end: Fixture.date(2026, 9, 19),
                                   isAllDay: true)
        let later = Fixture.event("稍後",
                                  start: Fixture.date(2026, 9, 18, 14, 0),
                                  end: Fixture.date(2026, 9, 18, 15, 0))
        XCTAssertEqual(CollapsedCardView.inProgressEvent(in: [allDay, later], now: now)?.title,
                       "中秋節")
    }

    // MARK: - featuredEvent：沒有進行中就退而顯示即將到來的（PLAN §4.10，2026-09-21 需求變更）

    @MainActor
    func testFeaturedPrefersInProgressOverUpcoming() {
        let ongoing = Fixture.event("進行中",
                                    start: Fixture.date(2026, 9, 18, 8, 30),
                                    end: Fixture.date(2026, 9, 18, 9, 30))
        let later = Fixture.event("稍後",
                                  start: Fixture.date(2026, 9, 18, 14, 0),
                                  end: Fixture.date(2026, 9, 18, 15, 0))
        XCTAssertEqual(CollapsedCardView.featured(in: [ongoing, later], now: now)?.event.title,
                       "進行中")
    }

    @MainActor
    func testFeaturedFallsBackToNearestUpcoming() {
        let soon = Fixture.event("比較近",
                                 start: Fixture.date(2026, 9, 18, 11, 0),
                                 end: Fixture.date(2026, 9, 18, 12, 0))
        let later = Fixture.event("比較遠",
                                  start: Fixture.date(2026, 9, 18, 19, 0),
                                  end: Fixture.date(2026, 9, 18, 20, 0))
        // 刻意把比較遠的放前面，確認挑的是「最近的」而不是陣列第一筆
        XCTAssertEqual(CollapsedCardView.featured(in: [later, soon], now: now)?.event.title,
                       "比較近")
    }

    @MainActor
    func testFeaturedIgnoresFinishedEvents() {
        let finished = Fixture.event("已結束",
                                     start: Fixture.date(2026, 9, 18, 7, 0),
                                     end: Fixture.date(2026, 9, 18, 8, 0))
        let upcoming = Fixture.event("還沒開始",
                                     start: Fixture.date(2026, 9, 18, 14, 0),
                                     end: Fixture.date(2026, 9, 18, 15, 0))
        XCTAssertEqual(CollapsedCardView.featured(in: [finished, upcoming], now: now)?.event.title,
                       "還沒開始")
    }

    @MainActor
    func testFeaturedReturnsNilWhenTodayIsDone() {
        let finished = Fixture.event("已結束",
                                     start: Fixture.date(2026, 9, 18, 7, 0),
                                     end: Fixture.date(2026, 9, 18, 8, 0))
        XCTAssertNil(CollapsedCardView.featured(in: [finished], now: now),
                     "今天的行程都結束了 → 那一列顯示「今天沒有行程」")
    }

    @MainActor
    func testFeaturedReturnsNilForEmptyList() {
        XCTAssertNil(CollapsedCardView.featured(in: [], now: now))
    }

    /// 剛好在 now 開始的算進行中，不會被當成「即將到來」
    @MainActor
    func testEventStartingExactlyNowIsInProgressNotUpcoming() {
        let event = Fixture.event("正好開始",
                                  start: now,
                                  end: Fixture.date(2026, 9, 18, 10, 0))
        XCTAssertEqual(CollapsedCardView.featured(in: [event], now: now)?.event.title, "正好開始")
        XCTAssertNil(CollapsedCardView.upcomingEvent(in: [event], now: now),
                     "upcoming 的條件是 start > now，剛好相等不算")
    }

    // MARK: - 區塊標題（使用者 2026-09-21 要求：收合後要看得出是現在還是等一下）

    @MainActor
    func testLabelSaysInProgressWhenOngoing() {
        let ongoing = Fixture.event("進行中",
                                    start: Fixture.date(2026, 9, 18, 8, 30),
                                    end: Fixture.date(2026, 9, 18, 9, 30))
        XCTAssertEqual(CollapsedCardView.featured(in: [ongoing], now: now)?.label, "正在進行中")
    }

    @MainActor
    func testLabelSaysUpcomingWhenOnlyFutureEvents() {
        let upcoming = Fixture.event("稍後",
                                     start: Fixture.date(2026, 9, 18, 14, 0),
                                     end: Fixture.date(2026, 9, 18, 15, 0))
        XCTAssertEqual(CollapsedCardView.featured(in: [upcoming], now: now)?.label, "即將到來")
    }

    @MainActor
    func testReturnsNilWhenNothingOngoing() {
        let past = Fixture.event("已結束",
                                 start: Fixture.date(2026, 9, 18, 7, 0),
                                 end: Fixture.date(2026, 9, 18, 8, 0))
        let future = Fixture.event("還沒開始",
                                   start: Fixture.date(2026, 9, 18, 14, 0),
                                   end: Fixture.date(2026, 9, 18, 15, 0))
        XCTAssertNil(CollapsedCardView.inProgressEvent(in: [past, future], now: now))
    }

    @MainActor
    func testReturnsNilForEmptyList() {
        XCTAssertNil(CollapsedCardView.inProgressEvent(in: [], now: now))
    }
}
