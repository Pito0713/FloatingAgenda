import XCTest
@testable import FloatingAgenda

/// 勾選完成的整條路徑（PLAN §4.4）——**整個專案唯一會寫入使用者資料的地方**。
///
/// 這批測試存在的直接理由：這條路徑的取消與清理邏輯先後有過四次漏洞，
/// 而且每次都是「在某個出口忘記清理 pending」的同一類錯誤（見 `docs/code-review-20260918.md`）。
///
/// 全程用 `SpyReminderWriter`，**不會寫入任何真實提醒**；
/// 緩衝時間注入成 60ms，測試才不必真的等 1.2 秒。
final class CompletionTests: XCTestCase {
    private let buffer = Duration.milliseconds(60)

    /// 輪詢到條件成立或逾時。
    /// 不用固定 `sleep` 等 Task：固定睡法在機器忙碌時會偶發失敗，
    /// 而且「睡完就斷言」無法證明時間真的經過（codex 於 2026-09-18 指出）。
    @MainActor
    private func waitUntil(_ label: String,
                           timeout: Duration = .seconds(3),
                           _ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("等待逾時：\(label)")
    }

    /// 負面測試（斷言「沒有寫入」）不能只是睡一段時間就下結論——
    /// 那樣有可能只是 Task 還沒跑到。做法是在狀態變更**之後**再排一筆 sentinel，
    /// 等 sentinel 真的被寫入，就證明緩衝期確實已經過去，這時斷言「那一筆沒被寫」才有意義。
    @MainActor
    private func waitForSentinel(_ store: AgendaStore, _ writer: SpyReminderWriter) async {
        store.toggleCompletion(Fixture.reminder("sentinel", due: nil, dueHasTime: false,
                                                id: "sentinel"))
        await waitUntil("sentinel 被寫入（用來證明緩衝期已過）") {
            writer.markedIDs.contains("sentinel")
        }
    }

    @MainActor
    private func makeStore(writer: SpyReminderWriter) -> AgendaStore {
        AgendaStore(settings: Fixture.settings(),
                    writer: writer,
                    completionDelay: buffer)
    }

    private func reminder(_ id: String = "r1") -> ReminderItem {
        Fixture.reminder("測試提醒", due: Fixture.date(2026, 9, 18, 9, 0),
                         dueHasTime: true, id: id)
    }

    // MARK: - 基本時序

    @MainActor
    func testTapDoesNotWriteImmediately() {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder())

        XCTAssertTrue(store.pendingCompletion.contains("r1"), "應立刻進入勾選中狀態")
        XCTAssertFalse(writer.didWriteAnything, "緩衝期內絕對不能寫入")
    }

    /// 鎖住 PLAN §4.4 規定的緩衝時間。
    /// 沒有這條的話，把 `init` 的預設值改成 0 不會讓任何測試失敗——
    /// 因為其他測試都傳入明確的 delay。
    @MainActor
    func testDefaultBufferMatchesSpec() {
        XCTAssertEqual(AgendaStore.defaultCompletionDelay, .milliseconds(1200),
                       "PLAN §4.4 規定勾選後 1.2 秒才寫入，期間可取消")
    }

    /// 先前所有測試都是「同步斷言沒寫入」或「等過緩衝期後斷言已寫入」，
    /// 兩者在 delay 被改成 0 的情況下**仍然會全部通過**——等於沒有驗證緩衝期存在。
    /// 這個測試用較長的緩衝（400ms）並在 60ms 時檢查，明確鎖住「會延遲」這件事。
    /// 由 codex 於 2026-09-18 指出。
    @MainActor
    func testBufferActuallyDelaysTheWrite() async {
        let writer = SpyReminderWriter()
        let store = AgendaStore(settings: Fixture.settings(),
                                writer: writer,
                                completionDelay: .milliseconds(400))

        store.toggleCompletion(reminder())
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(writer.didWriteAnything, "緩衝期還沒過就不該寫入")

        await waitUntil("緩衝期過後才寫入") { writer.markedIDs.contains("r1") }
    }

    @MainActor
    func testWritesAfterBufferElapses() async {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder())
        await waitUntil("r1 被寫入") { writer.markedIDs.contains("r1") }

        XCTAssertEqual(writer.markedIDs, ["r1"], "緩衝期過了才寫入，而且只寫一次")
    }

    @MainActor
    func testSecondTapWithinBufferCancelsCompletely() async {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder())
        store.toggleCompletion(reminder())   // 緩衝期內再點一次

        XCTAssertFalse(store.pendingCompletion.contains("r1"), "應回到未勾選狀態")
        await waitForSentinel(store, writer)
        XCTAssertFalse(writer.markedIDs.contains("r1"), "取消後即使緩衝期已過也不能寫入")
    }

    /// 寫入送出之後再點圓圈不能把本地標記拿掉——否則畫面顯示「取消了」，
    /// 資料其實已經完成。修於全專案 review 的第 1 條相關修正。
    @MainActor
    func testTapAfterWriteDoesNotFakeCancellation() async {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder())
        await waitUntil("r1 被寫入") { writer.markedIDs.contains("r1") }

        store.toggleCompletion(reminder())
        XCTAssertTrue(store.pendingCompletion.contains("r1"),
                      "寫入已送出，不能假裝取消成功")
    }

    @MainActor
    func testTwoRemindersAreIndependent() async {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder("a"))
        store.toggleCompletion(reminder("b"))
        store.toggleCompletion(reminder("a"))   // 只取消 a

        await waitUntil("b 被寫入") { writer.markedIDs.contains("b") }
        XCTAssertFalse(writer.markedIDs.contains("a"), "取消 a 不該影響 b，也不該寫入 a")
    }

    // MARK: - setRemindersState 漏斗
    //
    // 這是先前騙過四輪驗證的地方：任何讓使用者看不到清單的狀態，
    // 都必須把緩衝中的 pending 連計時 Task 一起取消，否則那筆會被靜默寫入。

    @MainActor
    func testPermissionLossDuringBufferPreventsWrite() async {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder())
        store.setRemindersState(.needsPermission)   // 緩衝期內權限被撤

        XCTAssertTrue(store.pendingCompletion.isEmpty)
        await waitForSentinel(store, writer)
        XCTAssertFalse(writer.markedIDs.contains("r1"),
                       "使用者看不到那一列、無法取消，就絕對不能寫入")
    }

    @MainActor
    func testHidingAllListsDuringBufferPreventsWrite() async {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder())
        // 全部清單被隱藏 → 空清單
        store.setRemindersState(.loaded(items: [], total: 0))

        XCTAssertTrue(store.pendingCompletion.isEmpty)
        await waitForSentinel(store, writer)
        XCTAssertFalse(writer.markedIDs.contains("r1"))
    }

    @MainActor
    func testReadFailureDuringBufferPreventsWrite() async {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder())
        store.setRemindersState(.failed("讀取失敗：無法取得提醒事項"))

        XCTAssertTrue(store.pendingCompletion.isEmpty)
        await waitForSentinel(store, writer)
        XCTAssertFalse(writer.markedIDs.contains("r1"),
                       "這條就是複審才抓到的第四條路徑")
    }

    @MainActor
    func testReminderLeavingTodayScopePreventsWrite() async {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder("a"))
        store.toggleCompletion(reminder("b"))
        // 重讀後 a 已不在今天的範圍內，只剩 b
        store.setRemindersState(.loaded(items: [reminder("b")], total: 1))

        // b 仍看得到所以會被寫入，這同時證明緩衝期已過
        await waitUntil("b 被寫入") { writer.markedIDs.contains("b") }
        XCTAssertFalse(writer.markedIDs.contains("a"), "已離開今天範圍的那筆不能被寫入")
    }

    /// 反面案例：仍然看得到的 pending 不能被誤清，否則使用者點了卻不會完成
    @MainActor
    func testStillVisibleReminderIsKeptAndWritten() async {
        let writer = SpyReminderWriter()
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder("a"))
        store.setRemindersState(.loaded(items: [reminder("a"), reminder("b")], total: 2))

        XCTAssertTrue(store.pendingCompletion.contains("a"), "還看得到就該保留勾選中狀態")
        await waitUntil("a 被寫入") { writer.markedIDs.contains("a") }
    }

    // MARK: - 寫入失敗

    @MainActor
    func testWriteFailureSurfacesErrorAndClearsPending() async {
        let writer = SpyReminderWriter()
        writer.errorToThrow = ReminderWriteError.notFound
        let store = makeStore(writer: writer)

        store.toggleCompletion(reminder())
        await waitUntil("錯誤訊息出現") { store.completionError != nil }

        XCTAssertFalse(writer.didWriteAnything)
        XCTAssertFalse(store.pendingCompletion.contains("r1"), "失敗後不該卡在勾選中")
        // 鎖住使用者看得到的文案。seam 重構把 notFound 從固定字串改成走通用 catch，
        // 訊息因此多了「勾選失敗：」前綴——這是刻意保留的改動（說明了是什麼動作失敗），
        // 用測試把它固定下來，之後若再變會立刻被發現。
        XCTAssertEqual(store.completionError, "勾選失敗：找不到這筆提醒，可能已被刪除")
    }

    /// 單筆失敗不該讓整個清單消失——否則其他還在緩衝期的提醒會連取消入口一起不見，
    /// 然後照樣被寫入。修於 M4 的第三條 CONFIRMED。
    @MainActor
    func testWriteFailureDoesNotDestroyRemindersState() async {
        let writer = SpyReminderWriter()
        writer.errorToThrow = ReminderWriteError.notFound
        let store = makeStore(writer: writer)

        store.setRemindersState(.loaded(items: [reminder("a"), reminder("b")], total: 2))
        store.toggleCompletion(reminder("a"))
        await waitUntil("錯誤訊息出現") { store.completionError != nil }

        guard case .loaded(let items, _) = store.remindersState else {
            return XCTFail("清單狀態不該被單筆寫入失敗取代，實際是 \(store.remindersState)")
        }
        XCTAssertEqual(items.count, 2, "兩列都要留著，取消入口才不會消失")
    }
}
