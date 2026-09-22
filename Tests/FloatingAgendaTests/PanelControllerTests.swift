import XCTest
@testable import FloatingAgenda

/// 走 `PanelController` 本身的整合測試。
///
/// 純函式層的錨點換算另外在 `PanelAnchorTests`；這裡驗的是**整合路徑**：
/// 切換模式時位置存進哪個 key、還原到哪、陰影有沒有跟著換、
/// 兩個模式的位置會不會互相污染。
///
/// 全部用 `Fixture.settings()`（記憶體設定），不會動到使用者真實的 App 設定。
/// 面板只建立不顯示（沒有呼叫 `show()`），所以不會有東西跳到畫面上。
@MainActor
final class PanelControllerTests: XCTestCase {

    /// 讓 SwiftUI 有機會 layout 一次並回報尺寸。
    /// 建構完立刻讀 `panelFrame` 拿到的還是佔位值
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    private func makeController(_ configure: (AppSettings) -> Void = { _ in })
        -> (PanelController, AppSettings) {
        let settings = Fixture.settings()
        configure(settings)
        return (PanelController(settings: settings), settings)
    }

    // MARK: - 起始狀態

    func testStartsInThePersistedMode() {
        for mode in DisplayMode.allCases {
            let (controller, _) = makeController { $0.displayMode = mode }
            XCTAssertEqual(controller.displayMode, mode)
        }
    }

    func testShadowFollowsTheMode() {
        for mode in DisplayMode.allCases {
            let (controller, _) = makeController { $0.displayMode = mode }
            XCTAssertEqual(controller.panelHasShadow, mode.wantsWindowShadow,
                           "\(mode) 的視窗陰影不對")
        }
    }

    func testSwitchingModeUpdatesShadow() {
        let (controller, _) = makeController { $0.displayMode = .full }
        XCTAssertTrue(controller.panelHasShadow)

        controller.setDisplayMode(.character)
        XCTAssertFalse(controller.panelHasShadow, "角色模式不該有視窗陰影")

        controller.setDisplayMode(.full)
        XCTAssertTrue(controller.panelHasShadow, "切回卡片要把陰影加回來")
    }

    // MARK: - 位置存進哪個 key

    /// 切到角色模式後，角色的位置要被寫進 `characterTopRight`，
    /// 而且面板的**右上角**要等於那個值
    func testSwitchingToCharacterRecordsItsOwnAnchor() {
        let (controller, settings) = makeController { $0.displayMode = .full }
        XCTAssertNil(settings.characterTopRight)

        controller.setDisplayMode(.character)

        let frame = controller.panelFrame
        XCTAssertEqual(PanelAnchor.topRight.point(of: frame),
                       PanelController.defaultAnchorPoint(
                           for: .character, size: frame.size),
                       "角色模式第一次出現應該在預設的右下角")
    }

    /// 切到角色模式時，**卡片的位置必須被存起來**——這是切回來能回到原位的前提
    func testSwitchingAwayFromCardSavesTheCardPosition() {
        let (controller, settings) = makeController { $0.displayMode = .full }
        let before = PanelAnchor.topLeft.point(of: controller.panelFrame)

        controller.setDisplayMode(.character)

        XCTAssertEqual(settings.panelTopLeft, before,
                       "離開卡片模式時要把卡片的左上角存下來")
    }

    /// ⚠️ 本檔最重要的一條：完整 → 角色 → 完整之後，卡片要回到**原本的位置**。
    /// 位置存錯 key、切換順序寫反、還原時用錯錨點，這條都會失敗
    func testRoundTripReturnsTheCardToItsOriginalPosition() {
        let seeded = CGPoint(x: 120, y: 900)
        let (controller, _) = makeController {
            $0.displayMode = .full
            $0.panelTopLeft = seeded
        }
        // 比的是**錨點**不是整個 frame：高度會隨內容變（第一次 layout 之後
        // 佔位的 200 會換成真實高度），但左上角必須原封不動
        let original = PanelAnchor.topLeft.point(of: controller.panelFrame)

        controller.setDisplayMode(.character)
        XCTAssertNotEqual(PanelAnchor.topLeft.point(of: controller.panelFrame), original,
                          "角色模式的位置應該不一樣")

        controller.setDisplayMode(.full)
        XCTAssertEqual(PanelAnchor.topLeft.point(of: controller.panelFrame), original,
                       "切回來應該回到原本的卡片位置")
    }

    /// 反方向也要成立：角色 → 卡片 → 角色
    func testRoundTripReturnsTheCharacterToItsOriginalPosition() {
        let (controller, _) = makeController { $0.displayMode = .character }
        let original = PanelAnchor.topRight.point(of: controller.panelFrame)

        controller.setDisplayMode(.full)
        controller.setDisplayMode(.character)

        XCTAssertEqual(PanelAnchor.topRight.point(of: controller.panelFrame), original)
    }

    /// 切回某個模式後，面板尺寸要是真實內容的尺寸，不是佔位值。
    ///
    /// ⚠️ 這條驗的是**結果**，不是 `lastKnownSize` 快取本身：實測把快取拿掉
    /// 這條照樣會過，因為 `setFrame(display: true)` 會同步觸發一次 layout，
    /// `onGeometryChange` 每次切換都會補上正確尺寸。
    /// 快取是防「SwiftUI 不保證值未變時會再回報」這個契約層面的風險而留的，
    /// 目前沒有測試能證明它必要——詳見 docs/verification/M9.2.md
    func testReturningToAModeReusesItsLastMeasuredSize() async throws {
        let (controller, _) = makeController { $0.displayMode = .full }
        try await settle()
        let measured = controller.panelFrame.size

        // 前提：量到的尺寸必須跟佔位值不同，否則這條測試不管實作對錯都會通過
        XCTAssertNotEqual(measured, DisplayMode.full.provisionalSize,
                          "量到的尺寸與佔位值相同，這條測試就沒有鑑別力了")

        controller.setDisplayMode(.character)
        controller.setDisplayMode(.full)

        XCTAssertEqual(controller.panelFrame.size, measured,
                       "切回來的尺寸應該是上次量到的值，不是 provisionalSize")
    }

    /// 兩個模式的位置互不污染。
    ///
    /// 位置是在**離開**某個模式時才寫入（進入時沒有東西可存，預設位置是算出來的），
    /// 所以要切完一輪之後再讀
    func testCardAndCharacterPositionsDoNotContaminateEachOther() {
        let (controller, settings) = makeController { $0.displayMode = .full }
        controller.setDisplayMode(.character)   // 離開 full → 存 panelTopLeft
        controller.setDisplayMode(.full)        // 離開 character → 存 characterTopRight

        let cardAnchor = try? XCTUnwrap(settings.panelTopLeft)
        let characterAnchor = try? XCTUnwrap(settings.characterTopRight)

        XCTAssertNotNil(cardAnchor)
        XCTAssertNotNil(characterAnchor)
        XCTAssertNotEqual(cardAnchor, characterAnchor,
                          "兩個模式的預設位置本來就不同，相等代表存到同一個 key 了")
    }

    /// 只是進入某個模式、還沒離開也沒拖曳過 → 不該憑空寫入位置
    func testEnteringAModeDoesNotWriteItsPositionYet() {
        let (controller, settings) = makeController { $0.displayMode = .full }
        controller.setDisplayMode(.character)
        XCTAssertNil(settings.characterTopRight,
                     "還沒離開也沒拖曳過，位置應該留給預設值去算")
    }

    /// 完整與收合共用同一個位置 key（兩者都是卡片，錨點也都是左上角）
    func testFullAndCollapsedShareTheCardAnchor() {
        let (controller, settings) = makeController { $0.displayMode = .full }
        let cardAnchor = PanelAnchor.topLeft.point(of: controller.panelFrame)

        controller.setDisplayMode(.collapsed)

        XCTAssertEqual(settings.panelTopLeft, cardAnchor)
        XCTAssertEqual(PanelAnchor.topLeft.point(of: controller.panelFrame), cardAnchor,
                       "完整換收合時左上角不該移動")
    }

    // MARK: - 持久化

    func testModeIsPersistedSoTheNextLaunchStartsThere() {
        let (controller, settings) = makeController { $0.displayMode = .full }
        controller.setDisplayMode(.character)
        XCTAssertEqual(settings.displayMode, .character)
    }

    func testSettingTheSameModeIsANoOp() {
        let (controller, settings) = makeController { $0.displayMode = .full }
        let before = controller.panelFrame
        settings.panelTopLeft = nil

        controller.setDisplayMode(.full)

        XCTAssertEqual(controller.panelFrame, before)
        XCTAssertNil(settings.panelTopLeft, "同模式重設不該觸發位置寫入")
    }

    // MARK: - 畫面外的舊位置

    func testOffscreenSavedCharacterPositionFallsBackToDefault() {
        let (controller, _) = makeController {
            $0.displayMode = .full
            $0.characterTopRight = CGPoint(x: -90_000, y: -90_000)
        }
        controller.setDisplayMode(.character)

        let frame = controller.panelFrame
        XCTAssertTrue(PanelController.isUsable(frame: frame),
                      "畫面外的舊位置應該被丟掉，換成看得到的預設位置")
    }
}
