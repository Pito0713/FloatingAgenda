import XCTest
@testable import FloatingAgenda

/// `AgendaStore.eventOrder`（PLAN §4.3）與 `reminderOrder`（§4.4）的排序規則。
final class OrderingTests: XCTestCase {

    // MARK: - 行程排序

    @MainActor
    func testAllDayComesFirstWithinSameDay() {
        let allDay = Fixture.event("中秋節",
                                   start: Fixture.date(2026, 9, 18),
                                   end: Fixture.date(2026, 9, 19),
                                   isAllDay: true)
        let timed = Fixture.event("工作會議",
                                  start: Fixture.date(2026, 9, 18, 9, 0),
                                  end: Fixture.date(2026, 9, 18, 10, 0))
        XCTAssertTrue(AgendaStore.eventOrder(allDay, timed))
        XCTAssertFalse(AgendaStore.eventOrder(timed, allDay))
    }

    /// 上面那個測試**不具鑑別力**：整天行程的 start 是 00:00，剛好也比定時行程早，
    /// 所以就算把「整天優先」規則整個拿掉、退回純比 start，它照樣會通過。
    /// 這個測試把兩者的 start 設成相同、並讓標題順序與期望結果相反：
    /// 規則在 → 整天優先（true）；規則被拿掉 → 落到標題比較（"ZZZ" < "AAA" 為 false）。
    /// 由 codex 在審查測試時指出（2026-09-18）。
    @MainActor
    func testAllDayRuleIsActuallyExercised() {
        let start = Fixture.date(2026, 9, 18)
        let allDay = Fixture.event("ZZZ 整天",
                                   start: start,
                                   end: Fixture.date(2026, 9, 19),
                                   isAllDay: true)
        let timed = Fixture.event("AAA 定時",
                                  start: start,
                                  end: Fixture.date(2026, 9, 18, 1, 0))
        XCTAssertTrue(AgendaStore.eventOrder(allDay, timed),
                      "整天優先的規則必須勝過標題比較，否則這條規則其實沒生效")
    }

    @MainActor
    func testTimedEventsSortByStart() {
        let morning = Fixture.event("早",
                                    start: Fixture.date(2026, 9, 18, 9, 0),
                                    end: Fixture.date(2026, 9, 18, 10, 0))
        let evening = Fixture.event("晚",
                                    start: Fixture.date(2026, 9, 18, 18, 0),
                                    end: Fixture.date(2026, 9, 18, 19, 0))
        XCTAssertTrue(AgendaStore.eventOrder(morning, evening))
        XCTAssertFalse(AgendaStore.eventOrder(evening, morning))
    }

    @MainActor
    func testSameStartTimeFallsBackToTitle() {
        let start = Fixture.date(2026, 9, 18, 9, 0)
        let end = Fixture.date(2026, 9, 18, 10, 0)
        let a = Fixture.event("AAA", start: start, end: end)
        let b = Fixture.event("BBB", start: start, end: end)
        XCTAssertTrue(AgendaStore.eventOrder(a, b), "開始時間相同時用標題決勝，排序才穩定")
    }

    /// 回歸測試，對應 code review 的 LOW #8。
    ///
    /// 舊版排序先比開始日期，所以昨天開始、跨過午夜的定時行程會排在今天的整天行程之前，
    /// 與「整天行程排最前面」矛盾。那是「顯示 7 天」時代的遺留；需求改成只看今天之後，
    /// 2026-09-21 把日期比較拿掉，整天一律優先。
    /// 這個測試原本是用來**鎖住舊行為**的，現在改成驗證新規格。
    @MainActor
    func testTodaysAllDaySortsBeforeCrossMidnightTimedEvent() {
        let crossMidnight = Fixture.event("跨午夜",
                                          start: Fixture.date(2026, 9, 17, 23, 0),
                                          end: Fixture.date(2026, 9, 18, 2, 0))
        let todaysAllDay = Fixture.event("今天整天",
                                         start: Fixture.date(2026, 9, 18),
                                         end: Fixture.date(2026, 9, 19),
                                         isAllDay: true)
        XCTAssertTrue(AgendaStore.eventOrder(todaysAllDay, crossMidnight),
                      "整天優先必須跨越開始日期的差異")
        XCTAssertFalse(AgendaStore.eventOrder(crossMidnight, todaysAllDay))
    }

    // MARK: - 提醒排序

    func testEarlierDueComesFirst() {
        let early = Fixture.reminder("早", due: Fixture.date(2026, 9, 18, 9, 0), dueHasTime: true)
        let late = Fixture.reminder("晚", due: Fixture.date(2026, 9, 18, 18, 0), dueHasTime: true)
        XCTAssertTrue(AgendaStore.reminderOrder(early, late))
        XCTAssertFalse(AgendaStore.reminderOrder(late, early))
    }

    func testDateOnlyDueSortsBeforeSameDayTimedDue() {
        let dateOnly = Fixture.reminder("只有日期",
                                        due: Fixture.date(2026, 9, 18),
                                        dueHasTime: false)
        let timed = Fixture.reminder("早上七點",
                                     due: Fixture.date(2026, 9, 18, 7, 0),
                                     dueHasTime: true)
        XCTAssertTrue(AgendaStore.reminderOrder(dateOnly, timed),
                      "只有日期的到期日等於當天 00:00，所以排在同日有時間的之前")
    }

    func testSameDueFallsBackToTitle() {
        let due = Fixture.date(2026, 9, 18, 9, 0)
        let a = Fixture.reminder("AAA", due: due, dueHasTime: true)
        let b = Fixture.reminder("BBB", due: due, dueHasTime: true)
        XCTAssertTrue(AgendaStore.reminderOrder(a, b))
    }

    /// 正式載入流程依 PLAN §4.4 排除無到期日的提醒，不會走到 nil 排序分支。
    /// 這個測試與下一個保護的是「Optional 輸入」的防禦性排序契約
    /// （`ReminderItem.due` 型別上仍可能是 nil），
    /// **不代表目前應該顯示無到期日的提醒**。未來若改需求要重新確認一次。
    func testNilDueSortsAfterAnyDueDate() {
        let withDue = Fixture.reminder("有到期日",
                                       due: Fixture.date(2026, 9, 18, 9, 0),
                                       dueHasTime: true)
        let withoutDue = Fixture.reminder("沒有到期日", due: nil, dueHasTime: false)
        XCTAssertTrue(AgendaStore.reminderOrder(withDue, withoutDue))
        XCTAssertFalse(AgendaStore.reminderOrder(withoutDue, withDue))
    }

    func testBothNilDueSortByCreationDate() {
        let older = Fixture.reminder("先建立", due: nil, dueHasTime: false,
                                     created: Fixture.date(2026, 9, 1))
        let newer = Fixture.reminder("後建立", due: nil, dueHasTime: false,
                                     created: Fixture.date(2026, 9, 10))
        XCTAssertTrue(AgendaStore.reminderOrder(older, newer))
        XCTAssertFalse(AgendaStore.reminderOrder(newer, older))
    }
}
