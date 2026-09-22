import XCTest
@testable import FloatingAgenda

/// `EventItem.id` 的穩定性（2026-09-18 code review 第 5 條）。
///
/// 原本缺 `eventIdentifier` 時用 `UUID()` 當替代，導致每次重讀算出不同的 id：
/// SwiftUI 的 `ForEach` 識別會漂移，列不斷重建、淡出動畫失準，
/// 深層連結也會送出一個假的 identifier。
final class EventItemTests: XCTestCase {
    private let start = Fixture.date(2026, 9, 21, 9, 0)
    private let end = Fixture.date(2026, 9, 21, 10, 0)

    @MainActor
    func testIDIsStableAcrossReloadsWhenIdentifierIsMissing() {
        let first = Fixture.event("媽媽生日", start: start, end: end,
                                  hasIdentifier: false, calendarID: "birthdays")
        let second = Fixture.event("媽媽生日", start: start, end: end,
                                   hasIdentifier: false, calendarID: "birthdays")
        XCTAssertEqual(first.id, second.id,
                       "同一筆行程在兩次重讀之間必須算出相同的 id")
    }

    @MainActor
    func testMissingIdentifierStillDistinguishesDifferentEvents() {
        let a = Fixture.event("A", start: start, end: end,
                              hasIdentifier: false, calendarID: "cal")
        let b = Fixture.event("B", start: start, end: end,
                              hasIdentifier: false, calendarID: "cal")
        XCTAssertNotEqual(a.id, b.id, "標題不同就該是不同的 id")

        let sameTitleOtherCalendar = Fixture.event("A", start: start, end: end,
                                                   hasIdentifier: false, calendarID: "other")
        XCTAssertNotEqual(a.id, sameTitleOtherCalendar.id,
                          "同名但來自不同行事曆也該區分得開")
    }

    @MainActor
    func testRepeatingEventsShareIdentifierButNotID() {
        let today = Fixture.event("每日站會", start: start, end: end, identifier: "repeat-1")
        let tomorrow = Fixture.event("每日站會",
                                     start: Fixture.date(2026, 9, 22, 9, 0),
                                     end: Fixture.date(2026, 9, 22, 10, 0),
                                     identifier: "repeat-1")
        XCTAssertEqual(today.eventIdentifier, tomorrow.eventIdentifier,
                       "重複行程共用同一個 eventIdentifier")
        XCTAssertNotEqual(today.id, tomorrow.id,
                          "但 id 要加上開始時間才能區分兩次發生")
    }

    /// 同行事曆、同標題、同開始時間但長度不同的兩筆，不能撞號。
    /// 由 codex 於 2026-09-21 指出。
    @MainActor
    func testMissingIdentifierDistinguishesDifferentEndTimes() {
        let short = Fixture.event("會議", start: start,
                                  end: Fixture.date(2026, 9, 21, 9, 30),
                                  hasIdentifier: false, calendarID: "cal")
        let long = Fixture.event("會議", start: start,
                                 end: Fixture.date(2026, 9, 21, 11, 0),
                                 hasIdentifier: false, calendarID: "cal")
        XCTAssertNotEqual(short.id, long.id)
    }

    @MainActor
    func testIdentifierIsNilWhenAbsent() {
        let event = Fixture.event("無 id 的行程", start: start, end: end, hasIdentifier: false)
        XCTAssertNil(event.eventIdentifier,
                     "缺 identifier 時要如實回報 nil，讓開啟邏輯能退回只開 App")
    }
}
