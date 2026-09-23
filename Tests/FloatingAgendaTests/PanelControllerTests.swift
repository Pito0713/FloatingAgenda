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
        XCTAssertNil(settings.characterBottomRight)

        controller.setDisplayMode(.character)

        let frame = controller.panelFrame
        XCTAssertEqual(PanelAnchor.bottomRight.point(of: frame),
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
        let original = PanelAnchor.bottomRight.point(of: controller.panelFrame)

        controller.setDisplayMode(.full)
        controller.setDisplayMode(.character)

        XCTAssertEqual(PanelAnchor.bottomRight.point(of: controller.panelFrame), original)
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
        let characterAnchor = try? XCTUnwrap(settings.characterBottomRight)

        XCTAssertNotNil(cardAnchor)
        XCTAssertNotNil(characterAnchor)
        XCTAssertNotEqual(cardAnchor, characterAnchor,
                          "兩個模式的預設位置本來就不同，相等代表存到同一個 key 了")
    }

    /// 只是進入某個模式、還沒離開也沒拖曳過 → 不該憑空寫入位置
    func testEnteringAModeDoesNotWriteItsPositionYet() {
        let (controller, settings) = makeController { $0.displayMode = .full }
        controller.setDisplayMode(.character)
        XCTAssertNil(settings.characterBottomRight,
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

/// 角色模式的展開／收回（M9 計畫 §4.5）
@MainActor
final class CharacterExpansionTests: XCTestCase {

    private func makeController(_ mode: DisplayMode) -> (PanelController, AppSettings) {
        let settings = Fixture.settings()
        settings.displayMode = mode
        return (PanelController(settings: settings), settings)
    }

    /// 重開 App 一律從小精靈開始——展開是暫時狀態
    func testStartsCollapsedToTheCharacter() {
        let (controller, _) = makeController(.character)
        XCTAssertFalse(controller.isCharacterExpanded)
    }

    func testToggleExpandsAndCollapses() {
        let (controller, _) = makeController(.character)
        controller.toggleCharacterExpanded()
        XCTAssertTrue(controller.isCharacterExpanded)
        controller.toggleCharacterExpanded()
        XCTAssertFalse(controller.isCharacterExpanded)
    }

    /// 只有角色模式能展開；在完整／收合模式呼叫應該完全沒有作用
    func testToggleDoesNothingOutsideCharacterMode() {
        for mode in [DisplayMode.full, .collapsed] {
            let (controller, _) = makeController(mode)
            controller.toggleCharacterExpanded()
            XCTAssertFalse(controller.isCharacterExpanded, "\(mode) 不該能展開")
        }
    }

    /// 展開的卡片要有陰影，小精靈沒有（§5.4）
    func testShadowFollowsTheExpandedState() {
        let (controller, _) = makeController(.character)
        XCTAssertFalse(controller.panelHasShadow, "小精靈不該有視窗陰影")
        controller.toggleCharacterExpanded()
        XCTAssertTrue(controller.panelHasShadow, "展開的卡片要有陰影")
        controller.toggleCharacterExpanded()
        XCTAssertFalse(controller.panelHasShadow)
    }

    /// 切到別的顯示模式再切回來，要回到小精靈而不是展開的卡片
    func testSwitchingModeResetsTheExpandedState() {
        let (controller, _) = makeController(.character)
        controller.toggleCharacterExpanded()
        XCTAssertTrue(controller.isCharacterExpanded)

        controller.setDisplayMode(.full)
        XCTAssertFalse(controller.isCharacterExpanded)

        controller.setDisplayMode(.character)
        XCTAssertFalse(controller.isCharacterExpanded, "切回來應該是小精靈")
    }

    /// **刻意不存**：展開狀態不該寫進任何設定（§4.5）。
    ///
    /// ⚠️ 一定要查**注入給 controller 的那個 store**。第一版另外開了一個
    /// `Fixture.settingsWithStore()` 去查，那個 store 根本沒被 controller 用到，
    /// 實作就算錯誤地持久化也照樣會過（codex 2026-09-22 指出）
    func testExpandedStateIsNotPersisted() {
        let (settings, store) = Fixture.settingsWithStore()
        settings.displayMode = .character
        let before = store.allPersistedKeys

        let controller = PanelController(settings: settings)
        controller.toggleCharacterExpanded()
        XCTAssertTrue(controller.isCharacterExpanded, "前提：真的展開了")

        XCTAssertEqual(store.allPersistedKeys, before,
                       "展開不該寫入任何設定，新增的 key："
                       + store.allPersistedKeys.subtracting(before).sorted().joined(separator: ", "))
    }

    /// 展開後面板要變成卡片的寬度，收回後要變回去。
    ///
    /// 注意待機時的寬度**不是** 80pt——泡泡在小精靈左邊，面板要把它一起包進去（§4.2）；
    /// 也不能拿建構完當下的寬度當基準，那還是尚未 layout 的佔位值
    func testPanelWidthFollowsTheExpandedState() {
        let (controller, _) = makeController(.character)

        controller.toggleCharacterExpanded()
        XCTAssertEqual(controller.panelFrame.width, PanelMetrics.width, accuracy: 1,
                       "展開後應該是卡片的寬度")

        controller.toggleCharacterExpanded()
        XCTAssertNotEqual(controller.panelFrame.width, PanelMetrics.width,
                          "收回後不該還是卡片的寬度")
        // 待機時的寬度 ＝ 泡泡 ＋ 間距 ＋ 小精靈。
        // 泡泡在 2026-09-23 放大之後，這個寬度**比卡片還寬**，
        // 所以不能假設「收回一定比較窄」
        XCTAssertGreaterThanOrEqual(
            controller.panelFrame.width,
            PanelMetrics.characterSize + PanelMetrics.characterPadding * 2,
            "收回後至少要容得下小精靈本身")
    }

    /// ⚠️ 展開時若卡片被螢幕邊界往上推，**收回後要回到展開前的位置**。
    ///
    /// 少了這個，小精靈每展開收回一次就往上爬一段，而且下次切換顯示模式
    /// 還會把爬上去的位置存起來（codex 2026-09-22 指出）
    func testCollapsingReturnsToThePositionBeforeExpanding() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let settings = Fixture.settings()
        settings.displayMode = .character
        // 貼著**上緣**放：錨點改成右下角之後，卡片是往上長的，
        // 只有小精靈在畫面頂端時展開才會撞到邊界被往下推
        settings.characterBottomRight = CGPoint(x: screen.maxX - 20, y: screen.maxY - 100)
        let controller = PanelController(settings: settings)
        let before = PanelAnchor.bottomRight.point(of: controller.panelFrame)

        controller.toggleCharacterExpanded()
        XCTAssertNotEqual(PanelAnchor.bottomRight.point(of: controller.panelFrame), before,
                          "前提：展開時確實被螢幕邊界推開了，否則這條沒有鑑別力")

        controller.toggleCharacterExpanded()
        XCTAssertEqual(PanelAnchor.bottomRight.point(of: controller.panelFrame), before,
                       "收回後應該回到展開前的位置")
    }

    /// 被推上去之後收回，也不該把位移過的位置存進設定
    func testPushedUpPositionIsNotPersisted() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let settings = Fixture.settings()
        settings.displayMode = .character
        let saved = CGPoint(x: screen.maxX - 20, y: screen.maxY - 100)
        settings.characterBottomRight = saved
        let controller = PanelController(settings: settings)

        controller.toggleCharacterExpanded()
        controller.toggleCharacterExpanded()
        controller.setDisplayMode(.full)

        XCTAssertEqual(settings.characterBottomRight, saved,
                       "展開再收回之後切換模式，存的應該還是原本的位置")
    }

    /// 展開與收回都以**右上角**為錨點，右緣不該移動（§5.4）。
    ///
    /// 只斷言 x：卡片若會超出螢幕下緣，`constrained` 會把它往上推，
    /// 那時 y 本來就會變——那是規格要求的行為，不是 bug
    func testRightEdgeStaysPutAcrossExpansion() {
        let (controller, _) = makeController(.character)
        let rightEdge = controller.panelFrame.maxX

        controller.toggleCharacterExpanded()
        XCTAssertEqual(controller.panelFrame.maxX, rightEdge, accuracy: 1,
                       "展開時右緣不該移動")

        controller.toggleCharacterExpanded()
        XCTAssertEqual(controller.panelFrame.maxX, rightEdge, accuracy: 1,
                       "收回時右緣也不該移動")
    }
}

/// 專案區只在角色模式展開時出現（M9 計畫 §4.5）。
///
/// ⚠️ 這條規則**單元測試與 snapshot 原本都抓不到**：`--snapshot` 直接渲染
/// `WidgetView`，完全不經過 `PanelRootView`。變異測試（讓完整模式也傳專案區）
/// 兩邊都沒有失敗，才發現這個覆蓋缺口。
@MainActor
final class ProjectsVisibilityTests: XCTestCase {

    func testOnlyExpandedCharacterModeShowsProjects() {
        XCTAssertTrue(PanelRootView.showsProjects(mode: .character, expanded: true))
    }

    func testIdleCharacterDoesNotShowProjects() {
        XCTAssertFalse(PanelRootView.showsProjects(mode: .character, expanded: false),
                       "待機的小精靈旁邊不該掛專案區")
    }

    func testCardModesNeverShowProjects() {
        for mode in [DisplayMode.full, .collapsed] {
            for expanded in [true, false] {
                XCTAssertFalse(PanelRootView.showsProjects(mode: mode, expanded: expanded),
                               "\(mode) 不該顯示專案區（§4.5），expanded=\(expanded)")
            }
        }
    }
}
