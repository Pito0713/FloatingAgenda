import XCTest
@testable import FloatingAgenda

/// 行程轉提醒的判斷規則（使用者 2026-11-06 要求）。
///
/// 只測純函式：真的寫入 EventKit 的 `EventKitEventReminderSync` 不在測試裡跑，
/// 開發與驗證期間不得寫入使用者的提醒資料。
final class EventReminderSyncTests: XCTestCase {
    private let calendar = Formatting.calendar
    private let now = Fixture.date(2026, 11, 6, 10, 0)

    // MARK: - 要轉哪些

    @MainActor
    func testOnlyTodaysUnfinishedEventsAreConverted() {
        let events = [
            Fixture.event("已結束", start: Fixture.date(2026, 11, 6, 8, 30),
                          end: Fixture.date(2026, 11, 6, 9, 0)),
            Fixture.event("進行中", start: Fixture.date(2026, 11, 6, 9, 45),
                          end: Fixture.date(2026, 11, 6, 10, 30)),
            Fixture.event("下午", start: Fixture.date(2026, 11, 6, 14, 0),
                          end: Fixture.date(2026, 11, 6, 15, 0)),
            Fixture.event("昨天跨夜", start: Fixture.date(2026, 11, 5, 23, 0),
                          end: Fixture.date(2026, 11, 6, 11, 0)),
            Fixture.event("明天", start: Fixture.date(2026, 11, 7, 9, 0),
                          end: Fixture.date(2026, 11, 7, 10, 0)),
        ]
        let titles = EventReminderSync.drafts(for: events, now: now, existingKeys: [],
                                              calendar: calendar).map(\.title)
        XCTAssertEqual(titles, ["進行中", "下午"])
    }

    @MainActor
    func testDueIsEventStartAndAllDayHasNoTime() throws {
        let events = [
            Fixture.event("整天", start: Fixture.date(2026, 11, 6),
                          end: Fixture.date(2026, 11, 7), isAllDay: true),
            Fixture.event("開會", start: Fixture.date(2026, 11, 6, 17, 0),
                          end: Fixture.date(2026, 11, 6, 17, 45)),
        ]
        let drafts = EventReminderSync.drafts(for: events, now: now, existingKeys: [],
                                              calendar: calendar)
        XCTAssertEqual(drafts.map(\.title), ["整天", "開會"])

        let allDay = drafts[0].due
        XCTAssertEqual([allDay.year, allDay.month, allDay.day], [2026, 11, 6])
        XCTAssertNil(allDay.hour, "整天行程不能帶時間，否則提醒會顯示 00:00")

        let timed = drafts[1].due
        XCTAssertEqual([timed.year, timed.month, timed.day, timed.hour, timed.minute],
                       [2026, 11, 6, 17, 0])
    }

    // MARK: - 防重複

    @MainActor
    func testAlreadyConvertedEventsAreSkipped() throws {
        let done = Fixture.event("已轉過", start: Fixture.date(2026, 11, 6, 14, 0),
                                 end: Fixture.date(2026, 11, 6, 15, 0))
        let fresh = Fixture.event("新的", start: Fixture.date(2026, 11, 6, 16, 0),
                                  end: Fixture.date(2026, 11, 6, 17, 0))
        let existing: Set<URL> = [try XCTUnwrap(EventReminderSync.key(for: done))]
        let titles = EventReminderSync.drafts(for: [done, fresh], now: now,
                                              existingKeys: existing, calendar: calendar).map(\.title)
        XCTAssertEqual(titles, ["新的"])
    }

    @MainActor
    func testRepeatingEventGetsDifferentKeyEachDay() {
        let today = Fixture.event("每日站會", start: Fixture.date(2026, 11, 6, 9, 0),
                                  end: Fixture.date(2026, 11, 6, 9, 15), identifier: "repeat")
        let tomorrow = Fixture.event("每日站會", start: Fixture.date(2026, 11, 7, 9, 0),
                                     end: Fixture.date(2026, 11, 7, 9, 15), identifier: "repeat")
        XCTAssertNotEqual(EventReminderSync.key(for: today), EventReminderSync.key(for: tomorrow),
                          "重複行程共用 eventIdentifier，key 必須含日期，否則明天會被當成轉過")
    }

    // MARK: - 一天只跑一次

    @MainActor
    func testAutoRunOncePerDay() {
        let today = EventReminderSync.dayStamp(for: now, calendar: calendar)
        XCTAssertEqual(today, "2026-11-06")

        XCTAssertFalse(EventReminderSync.shouldAutoRun(enabled: false, lastDay: nil,
                                                       now: now, calendar: calendar))
        XCTAssertTrue(EventReminderSync.shouldAutoRun(enabled: true, lastDay: nil,
                                                      now: now, calendar: calendar))
        XCTAssertTrue(EventReminderSync.shouldAutoRun(enabled: true, lastDay: "2026-11-05",
                                                      now: now, calendar: calendar))
        XCTAssertFalse(EventReminderSync.shouldAutoRun(enabled: true, lastDay: today,
                                                       now: now, calendar: calendar))
    }

    @MainActor
    func testAutoRunSettingDefaultsOff() {
        let settings = Fixture.settings()
        XCTAssertFalse(settings.autoEventsToReminders, "會寫入使用者資料，預設必須關閉")
        XCTAssertNil(settings.lastEventsToRemindersDay)
        settings.lastEventsToRemindersDay = "2026-11-06"
        XCTAssertEqual(settings.lastEventsToRemindersDay, "2026-11-06")
    }
}
