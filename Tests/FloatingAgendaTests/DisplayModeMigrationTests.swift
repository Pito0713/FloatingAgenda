import XCTest
@testable import FloatingAgenda

/// 舊版只有 `panelCollapsed` 兩態，新版是 `displayMode` 三態。
/// 這裡把 M9 計畫 §5.5 的遷移規則逐條釘住。
///
/// 全部用 `InMemorySettingsStore`，不會在 `~/Library/Preferences` 留下任何 plist。
@MainActor
final class DisplayModeMigrationTests: XCTestCase {

    private let displayModeKey = "displayMode"
    private let panelCollapsedKey = "panelCollapsed"

    // MARK: - 遷移

    /// 舊版收合著 → 新版要是 collapsed，而且**要真的寫進去**。
    /// 用 `register(defaults:)` 只會提供讀取後備值、不會寫入，
    /// 使用者的收合狀態會在下一次讀取時憑空消失
    func testCollapsedUserMigratesToCollapsedAndPersists() {
        let store = InMemorySettingsStore()
        store.set(true, forKey: panelCollapsedKey)

        let settings = AppSettings(defaults: store)

        XCTAssertEqual(settings.displayMode, .collapsed)
        XCTAssertEqual(store.persistedObject(forKey: displayModeKey) as? String, "collapsed",
                       "遷移必須實際寫入持久層；用 register 只是提供後備值，下次啟動就沒了")
    }

    func testExpandedUserMigratesToFull() {
        let store = InMemorySettingsStore()
        store.set(false, forKey: panelCollapsedKey)

        let settings = AppSettings(defaults: store)

        XCTAssertEqual(settings.displayMode, .full)
        XCTAssertEqual(store.persistedObject(forKey: displayModeKey) as? String, "full")
    }

    /// 全新安裝：兩個 key 都沒有 → full
    func testFreshInstallGetsFull() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(defaults: store)

        XCTAssertEqual(settings.displayMode, .full)
        XCTAssertEqual(store.persistedObject(forKey: displayModeKey) as? String, "full")
    }

    /// 已經遷移過就不要再動。使用者選了 character，重開 App 不該被舊的
    /// `panelCollapsed` 覆蓋回去
    func testExistingDisplayModeIsNotOverwrittenByLegacyKey() {
        let store = InMemorySettingsStore()
        store.set(true, forKey: panelCollapsedKey)
        store.set("character", forKey: displayModeKey)

        let settings = AppSettings(defaults: store)

        XCTAssertEqual(settings.displayMode, .character)
    }

    /// 遷移是冪等的：同一個 store 建第二次 AppSettings 不該改變結果
    func testMigrationIsIdempotent() {
        let store = InMemorySettingsStore()
        store.set(true, forKey: panelCollapsedKey)

        _ = AppSettings(defaults: store)
        let second = AppSettings(defaults: store)

        XCTAssertEqual(second.displayMode, .collapsed)
    }

    /// `panelCollapsed` 刻意保留不刪，這樣使用者退回舊版還能用（計畫 §5.5）
    func testLegacyKeyIsKeptAfterMigration() {
        let store = InMemorySettingsStore()
        store.set(true, forKey: panelCollapsedKey)

        _ = AppSettings(defaults: store)

        XCTAssertEqual(store.persistedObject(forKey: panelCollapsedKey) as? Bool, true,
                       "舊 key 不該被刪掉")
    }

    // MARK: - 讀寫

    func testAllThreeModesRoundTrip() {
        for mode in DisplayMode.allCases {
            let settings = Fixture.settings()
            settings.displayMode = mode
            XCTAssertEqual(settings.displayMode, mode)
        }
    }

    /// 使用者用 `defaults write` 塞了不認得的值 → 回 full，不能 crash
    func testUnknownRawValueFallsBackToFull() {
        let (settings, store) = Fixture.settingsWithStore()
        store.set("rainbow", forKey: displayModeKey)
        XCTAssertEqual(settings.displayMode, .full)
    }

    /// 型別不對（存成數字）也要回 full
    func testWrongTypeFallsBackToFull() {
        let (settings, store) = Fixture.settingsWithStore()
        store.set(42, forKey: displayModeKey)
        XCTAssertEqual(settings.displayMode, .full)
    }

    // MARK: - 角色模式的位置

    func testCharacterTopRightIsNilWhenNeverSaved() {
        XCTAssertNil(Fixture.settings().characterTopRight)
    }

    /// 兩個座標缺一就視為沒有記錄，否則會用一個座標配上 0 去擺面板
    func testCharacterTopRightIsNilWhenOnlyOneCoordinateStored() {
        let (settings, store) = Fixture.settingsWithStore()
        store.set(120.0, forKey: "characterTopRightX")
        XCTAssertNil(settings.characterTopRight)
    }

    func testCharacterTopRightRoundTrips() {
        let settings = Fixture.settings()
        settings.characterTopRight = CGPoint(x: 1200, y: 340)
        XCTAssertEqual(settings.characterTopRight, CGPoint(x: 1200, y: 340))
    }

    func testCharacterTopRightCanBeCleared() {
        let settings = Fixture.settings()
        settings.characterTopRight = CGPoint(x: 1200, y: 340)
        settings.characterTopRight = nil
        XCTAssertNil(settings.characterTopRight)
    }

    /// 角色模式與卡片模式的位置**分開存**，互不影響（計畫 §5.5、§7.2 第 4 項）
    func testCharacterAndCardPositionsAreIndependent() {
        let settings = Fixture.settings()
        settings.panelTopLeft = CGPoint(x: 10, y: 900)
        settings.characterTopRight = CGPoint(x: 1400, y: 120)

        XCTAssertEqual(settings.panelTopLeft, CGPoint(x: 10, y: 900))
        XCTAssertEqual(settings.characterTopRight, CGPoint(x: 1400, y: 120))

        settings.characterTopRight = nil
        XCTAssertEqual(settings.panelTopLeft, CGPoint(x: 10, y: 900),
                       "清掉角色位置不該影響卡片位置")
    }
}
