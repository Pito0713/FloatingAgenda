import XCTest
@testable import FloatingAgenda

/// `AppSettings` 的夾限與讀寫。
///
/// ⚠️ 全部使用 `InMemorySettingsStore`，**不碰 `UserDefaults`**——
/// 既不會蓋掉使用者實際在用的 App 設定，也不會在 `~/Library/Preferences` 留下檔案。
final class AppSettingsTests: XCTestCase {

    // MARK: - 透明度夾限
    //
    // 這組對應 M1 的三條 codex 發現：0 與負數原本會回傳 1.0 而非夾到下界、
    // NaN 會穿透 min/max（NaN 的比較全為 false）。

    @MainActor
    func testOpacityClampsBelowLowerBound() {
        XCTAssertEqual(AppSettings.clampOpacity(-1), 0.3)
        XCTAssertEqual(AppSettings.clampOpacity(0), 0.3)
        XCTAssertEqual(AppSettings.clampOpacity(0.1), 0.3)
    }

    @MainActor
    func testOpacityClampsAboveUpperBound() {
        XCTAssertEqual(AppSettings.clampOpacity(5), 1.0)
    }

    @MainActor
    func testOpacityPassesThroughInRange() {
        XCTAssertEqual(AppSettings.clampOpacity(0.75), 0.75)
        XCTAssertEqual(AppSettings.clampOpacity(0.3), 0.3)
        XCTAssertEqual(AppSettings.clampOpacity(1.0), 1.0)
    }

    @MainActor
    func testOpacityRejectsNonFiniteValues() {
        XCTAssertEqual(AppSettings.clampOpacity(.nan), 1.0, "NaN 的比較全為 false，會穿透 min/max")
        XCTAssertEqual(AppSettings.clampOpacity(.infinity), 1.0)
        XCTAssertEqual(AppSettings.clampOpacity(-.infinity), 1.0)
    }

    // MARK: - 透明度的讀取路徑

    @MainActor
    func testStoredOutOfRangeOpacityIsClampedOnRead() {
        let (settings, store) = Fixture.settingsWithStore()
        store.set(0.0, forKey: "opacity")
        XCTAssertEqual(settings.opacity, 0.3)
        store.set(9.9, forKey: "opacity")
        XCTAssertEqual(settings.opacity, 1.0)
    }

    @MainActor
    func testNonNumericOpacityFallsBackToFullyOpaque() {
        let (settings, store) = Fixture.settingsWithStore()
        store.set("abc", forKey: "opacity")
        XCTAssertEqual(settings.opacity, 1.0,
                       "型別不對時不該把 double(forKey:) 的 0.0 誤當成使用者選的透明度")
    }

    @MainActor
    func testOpacityDefaultsToFullyOpaque() {
        let settings = Fixture.settings()
        XCTAssertEqual(settings.opacity, 1.0)
    }

    /// 先前只測了 `clampOpacity` 與讀取路徑，setter 沒被保護——
    /// 儲存鍵寫錯或寫入時不夾限都不會被發現。由 codex 在審查測試時指出（2026-09-18）。
    @MainActor
    func testOpacitySetterClampsAndPersistsUnderExpectedKey() {
        let (settings, store) = Fixture.settingsWithStore()

        settings.opacity = 5
        XCTAssertEqual(settings.opacity, 1.0)
        XCTAssertEqual(store.object(forKey: "opacity") as? Double, 1.0,
                       "寫入時就要夾限，而且要存在 opacity 這個鍵下")

        settings.opacity = -1
        XCTAssertEqual(store.object(forKey: "opacity") as? Double, 0.3)

        settings.opacity = 0.6
        XCTAssertEqual(store.object(forKey: "opacity") as? Double, 0.6)
    }

    // MARK: - 其他設定

    @MainActor
    func testPanelVisibleDefaultsToTrueAndRoundTrips() {
        let settings = Fixture.settings()
        XCTAssertTrue(settings.panelVisible)
        settings.panelVisible = false
        XCTAssertFalse(settings.panelVisible)
    }

    @MainActor
    func testPanelCollapsedDefaultsToFalseAndRoundTrips() {
        let settings = Fixture.settings()
        XCTAssertFalse(settings.panelCollapsed)
        settings.panelCollapsed = true
        XCTAssertTrue(settings.panelCollapsed)
    }

    /// 存的是「被隱藏的 ID」而非「顯示的 ID」，新增的行事曆才會預設顯示（PLAN §4.5）
    @MainActor
    func testHiddenIDsDefaultToEmptyAndRoundTrip() {
        let settings = Fixture.settings()
        XCTAssertTrue(settings.hiddenCalendarIDs.isEmpty,
                      "預設沒有任何被隱藏的行事曆 → 新增的行事曆會顯示")
        XCTAssertTrue(settings.hiddenReminderListIDs.isEmpty)

        settings.hiddenCalendarIDs = ["cal-a", "cal-b"]
        XCTAssertEqual(settings.hiddenCalendarIDs, ["cal-a", "cal-b"])

        settings.hiddenReminderListIDs = ["list-a"]
        XCTAssertEqual(settings.hiddenReminderListIDs, ["list-a"])
        XCTAssertEqual(settings.hiddenCalendarIDs, ["cal-a", "cal-b"],
                       "兩個清單互不干擾")
    }

    // MARK: - 面板位置

    @MainActor
    func testPanelTopLeftIsNilWhenNeverSaved() {
        let settings = Fixture.settings()
        XCTAssertNil(settings.panelTopLeft)
    }

    @MainActor
    func testPanelTopLeftRoundTrips() {
        let settings = Fixture.settings()
        settings.panelTopLeft = CGPoint(x: 300, y: 1000)
        XCTAssertEqual(settings.panelTopLeft, CGPoint(x: 300, y: 1000))
    }

    @MainActor
    func testPanelTopLeftIsNilWhenOnlyOneCoordinateStored() {
        let (settings, store) = Fixture.settingsWithStore()
        store.set(300.0, forKey: "panelTopLeftX")
        XCTAssertNil(settings.panelTopLeft, "兩個座標缺一即視為沒有記錄，不能拿半個座標去定位")
    }

    @MainActor
    func testPanelTopLeftCanBeCleared() {
        let settings = Fixture.settings()
        settings.panelTopLeft = CGPoint(x: 1, y: 2)
        settings.panelTopLeft = nil
        XCTAssertNil(settings.panelTopLeft)
    }
}
