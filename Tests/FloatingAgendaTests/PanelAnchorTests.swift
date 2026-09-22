import XCTest
@testable import FloatingAgenda

/// 面板幾何。M9 計畫 §9 把「動態改面板寬度」列為最高風險項，
/// 這裡把可以用純函式表達的部分全部釘住：錨點換算、尺寸改變時錨點不動。
@MainActor
final class PanelAnchorTests: XCTestCase {

    private let frame = NSRect(x: 100, y: 200, width: 320, height: 480)

    // MARK: - 錨點換算

    func testTopLeftPointIsLeftAndTop() {
        XCTAssertEqual(PanelAnchor.topLeft.point(of: frame), CGPoint(x: 100, y: 680))
    }

    func testTopRightPointIsRightAndTop() {
        XCTAssertEqual(PanelAnchor.topRight.point(of: frame), CGPoint(x: 420, y: 680))
    }

    /// point → frame → point 要回到原點，否則每次尺寸同步都會累積偏移
    func testRoundTripIsLossless() {
        for anchor in [PanelAnchor.topLeft, .topRight] {
            let point = anchor.point(of: frame)
            let rebuilt = anchor.frame(at: point, size: frame.size)
            XCTAssertEqual(rebuilt, frame, "\(anchor) 的 point/frame 換算不對稱")
        }
    }

    // MARK: - 尺寸改變時錨點不動（這是整個 M9.2 的核心保證）

    /// 完整／收合模式：高度變了，**左上角**不能動
    func testTopLeftStaysPutWhenHeightChanges() {
        let anchor = PanelAnchor.topLeft
        let before = anchor.point(of: frame)
        let grown = anchor.frame(at: before, size: NSSize(width: 320, height: 900))

        XCTAssertEqual(anchor.point(of: grown), before)
        XCTAssertEqual(grown.minX, frame.minX, "左緣不該移動")
        XCTAssertEqual(grown.maxY, frame.maxY, "上緣不該移動")
        XCTAssertLessThan(grown.minY, frame.minY, "應該是往下長")
    }

    /// 角色模式：寬高都變了，**右上角**不能動。
    /// 泡泡往左長、卡片往左下長，小精靈才不會跳（計畫 §5.4）
    func testTopRightStaysPutWhenBothDimensionsChange() {
        let anchor = PanelAnchor.topRight
        let small = NSRect(x: 1000, y: 100, width: 80, height: 80)
        let before = anchor.point(of: small)
        let expanded = anchor.frame(at: before, size: NSSize(width: 320, height: 620))

        XCTAssertEqual(anchor.point(of: expanded), before)
        XCTAssertEqual(expanded.maxX, small.maxX, "右緣不該移動")
        XCTAssertEqual(expanded.maxY, small.maxY, "上緣不該移動")
        XCTAssertLessThan(expanded.minX, small.minX, "應該是往左長")
        XCTAssertLessThan(expanded.minY, small.minY, "應該是往下長")
    }

    /// 反過來也要成立：從展開的卡片收回小精靈，右上角同樣不動
    func testTopRightStaysPutWhenShrinking() {
        let anchor = PanelAnchor.topRight
        let big = NSRect(x: 700, y: 100, width: 320, height: 620)
        let before = anchor.point(of: big)
        let shrunk = anchor.frame(at: before, size: NSSize(width: 80, height: 80))

        XCTAssertEqual(anchor.point(of: shrunk), before)
        XCTAssertEqual(shrunk.maxX, big.maxX)
        XCTAssertEqual(shrunk.maxY, big.maxY)
    }

    /// 如果角色模式錯用左上角當錨點，右緣就會跟著寬度跑掉——
    /// 這條就是在擋那個錯誤
    func testUsingTopLeftForCharacterWouldMoveTheRightEdge() {
        let small = NSRect(x: 1000, y: 100, width: 80, height: 80)
        let wrong = PanelAnchor.topLeft.frame(at: PanelAnchor.topLeft.point(of: small),
                                              size: NSSize(width: 320, height: 620))
        XCTAssertNotEqual(wrong.maxX, small.maxX,
                          "用左上角當錨點時右緣必然移動；若這裡相等代表換算邏輯有問題")
    }

    // MARK: - 模式對應

    func testCardModesAnchorTopLeftAndCharacterAnchorsTopRight() {
        XCTAssertEqual(DisplayMode.full.anchor, .topLeft)
        XCTAssertEqual(DisplayMode.collapsed.anchor, .topLeft)
        XCTAssertEqual(DisplayMode.character.anchor, .topRight)
    }

    func testOnlyCharacterModeDropsTheWindowShadow() {
        XCTAssertTrue(DisplayMode.full.wantsWindowShadow)
        XCTAssertTrue(DisplayMode.collapsed.wantsWindowShadow)
        XCTAssertFalse(DisplayMode.character.wantsWindowShadow,
                       "角色模式的陰影由角色自己畫，視窗不能再加一層")
    }

    /// 角色模式的暫定尺寸就是 64pt 見方加上兩側邊距，而且是正方形
    func testCharacterProvisionalSizeIsSpritePlusPadding() {
        let expected = PanelMetrics.characterSize + PanelMetrics.characterPadding * 2
        XCTAssertEqual(DisplayMode.character.provisionalSize,
                       NSSize(width: expected, height: expected))
    }

    func testCardProvisionalSizeUsesFixedWidth() {
        for mode in [DisplayMode.full, .collapsed] {
            XCTAssertEqual(mode.provisionalSize.width, PanelMetrics.width)
            XCTAssertEqual(mode.provisionalSize.height, PanelMetrics.initialHeight)
        }
    }

    // MARK: - 可用性判定

    /// 角色模式的面板只有 80pt 見方。高度門檻若寫死 40 對它仍成立，
    /// 但取 `min(40, 高度)` 才不會在內容更小時永遠判為不可用
    func testSmallPanelFullyOnScreenIsUsable() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let side = DisplayMode.character.provisionalSize
        let frame = NSRect(x: screen.midX, y: screen.midY,
                           width: side.width, height: side.height)
        XCTAssertTrue(PanelController.isUsable(frame: frame))
    }

    func testPanelFarOffScreenIsNotUsable() {
        let frame = NSRect(x: -100_000, y: -100_000, width: 320, height: 480)
        XCTAssertFalse(PanelController.isUsable(frame: frame))
    }

    /// 只露出一小角不算可用：使用者看不到也抓不到。
    ///
    /// ⚠️ 位置要挑**最右邊那個螢幕**的右緣，不能用 `screens.first`：
    /// 多螢幕時 `screens.first` 的右邊可能還有另一個螢幕，
    /// 那一小角其實整片落在鄰居螢幕上，判定為可用是正確的
    /// （使用者 2026-09-22 接上第二個螢幕後這條就紅了，程式沒錯，是測試的假設錯）
    func testPanelWithOnlyASliverOnScreenIsNotUsable() throws {
        let rightmost = try XCTUnwrap(
            NSScreen.screens.max { $0.visibleFrame.maxX < $1.visibleFrame.maxX }).visibleFrame
        let frame = NSRect(x: rightmost.maxX - 10, y: rightmost.midY, width: 320, height: 480)
        XCTAssertFalse(PanelController.isUsable(frame: frame),
                       "只有 10pt 在畫面內不該算可用")
    }

    /// 反過來：橫跨兩個相鄰螢幕的面板**是**可用的，不該被判成畫面外
    func testPanelSpanningTwoAdjacentScreensIsUsable() throws {
        let screens = NSScreen.screens.map(\.visibleFrame).sorted { $0.minX < $1.minX }
        try XCTSkipUnless(screens.count >= 2, "需要兩個螢幕才測得到")
        let left = screens[0]
        // 跨在兩個螢幕的交界上
        let frame = NSRect(x: left.maxX - 160, y: left.midY, width: 320, height: 200)
        XCTAssertTrue(PanelController.isUsable(frame: frame))
    }

    // MARK: - 預設位置

    func testCardDefaultIsTopRightOfScreen() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let size = DisplayMode.full.provisionalSize
        let point = PanelController.defaultAnchorPoint(for: .full, size: size)

        XCTAssertEqual(point.y, screen.maxY - PanelMetrics.screenInset, accuracy: 0.5,
                       "卡片預設貼上緣")
        XCTAssertEqual(point.x + size.width, screen.maxX - PanelMetrics.screenInset,
                       accuracy: 0.5, "卡片預設靠右")
    }

    /// 角色預設在**右下角**（計畫 §5.4），泡泡往左長、卡片往左上長都還在畫面內
    func testCharacterDefaultIsBottomRightOfScreen() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let size = DisplayMode.character.provisionalSize
        let point = PanelController.defaultAnchorPoint(for: .character, size: size)
        let frame = PanelAnchor.topRight.frame(at: point, size: size)

        XCTAssertEqual(frame.maxX, screen.maxX - PanelMetrics.screenInset, accuracy: 0.5,
                       "角色預設靠右")
        XCTAssertEqual(frame.minY, screen.minY + PanelMetrics.screenInset, accuracy: 0.5,
                       "角色預設貼下緣")
        XCTAssertTrue(PanelController.isUsable(frame: frame), "預設位置必須是可用的")
    }

    /// 預設位置算出來的 frame 一定要完整落在螢幕內，否則一開機就看不到
    func testDefaultFramesAreFullyOnScreen() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        for mode in DisplayMode.allCases {
            let size = mode.provisionalSize
            let frame = mode.anchor.frame(
                at: PanelController.defaultAnchorPoint(for: mode, size: size), size: size)
            XCTAssertTrue(screen.contains(frame), "\(mode) 的預設位置超出螢幕：\(frame)")
        }
    }

    // MARK: - 夾限

    /// 錨點還在螢幕上、但面板有一部分超出去 → 夾回來
    func testConstrainedPullsAPartlyOverflowingPanelBack() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let overflowing = NSRect(x: screen.maxX - 100, y: screen.midY, width: 320, height: 200)
        let fitted = PanelController.constrained(overflowing, anchor: .topLeft)
        XCTAssertLessThanOrEqual(fitted.maxX, screen.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(fitted.minX, screen.minX - 0.5)
    }

    /// 完全不在任何螢幕上時**刻意原樣回傳**，交給 `recoverIfOffscreen` 送回預設位置。
    /// 在這裡硬夾會把面板黏到某個螢幕邊緣，反而看不出「它跑掉了」
    func testConstrainedLeavesACompletelyOffscreenPanelUntouched() {
        let lost = NSRect(x: -100_000, y: -100_000, width: 320, height: 200)
        XCTAssertEqual(PanelController.constrained(lost, anchor: .topLeft), lost)
    }

    /// 比螢幕還高的面板貼齊上緣——寧可露出上半部，日期與最近的行程都在上面
    func testPanelTallerThanScreenSticksToTheTop() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let tall = NSRect(x: screen.midX, y: screen.minY,
                          width: 320, height: screen.height + 400)
        let fitted = PanelController.constrained(tall, anchor: .topLeft)
        XCTAssertEqual(fitted.maxY, screen.maxY, accuracy: 0.5)
    }

    func testConstrainedLeavesAnAlreadyFittingPanelAlone() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let inside = NSRect(x: screen.midX, y: screen.midY, width: 200, height: 200)
        XCTAssertEqual(PanelController.constrained(inside, anchor: .topLeft), inside)
        XCTAssertEqual(PanelController.constrained(inside, anchor: .topRight), inside)
    }
}

/// 還原位置的決策：存過且看得到就用存的，否則回預設。
/// 這是模式切換時最容易出錯的地方（存錯 key、還原到別的模式的位置）
@MainActor
final class PanelRestoreTests: XCTestCase {

    func testNeverSavedFallsBackToDefault() {
        for mode in DisplayMode.allCases {
            let size = mode.provisionalSize
            XCTAssertEqual(PanelController.resolveAnchorPoint(for: mode, saved: nil, size: size),
                           PanelController.defaultAnchorPoint(for: mode, size: size))
        }
    }

    func testSavedAndVisiblePositionIsUsed() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        for mode in DisplayMode.allCases {
            let size = mode.provisionalSize
            // 放在螢幕正中央，一定看得到
            let saved = mode.anchor.point(of: NSRect(x: screen.midX - size.width / 2,
                                                     y: screen.midY - size.height / 2,
                                                     width: size.width, height: size.height))
            XCTAssertEqual(PanelController.resolveAnchorPoint(for: mode, saved: saved, size: size),
                           saved, "\(mode) 存過且看得到的位置應該被沿用")
        }
    }

    func testSavedButOffscreenPositionFallsBackToDefault() {
        let lost = CGPoint(x: -50_000, y: -50_000)
        for mode in DisplayMode.allCases {
            let size = mode.provisionalSize
            XCTAssertEqual(PanelController.resolveAnchorPoint(for: mode, saved: lost, size: size),
                           PanelController.defaultAnchorPoint(for: mode, size: size),
                           "\(mode) 畫面外的舊位置應該被丟掉")
        }
    }

    /// 同一個座標值對卡片與角色模式代表**不同的角**，所以還原出的 frame 必須不同。
    /// 若兩者共用同一套錨點邏輯，這條會失敗
    func testSameSavedPointMeansDifferentFramesPerMode() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        let point = CGPoint(x: screen.midX, y: screen.midY)
        let cardSize = NSSize(width: 320, height: 200)

        let card = DisplayMode.full.anchor.frame(at: point, size: cardSize)
        let character = DisplayMode.character.anchor.frame(at: point, size: cardSize)

        XCTAssertEqual(card.minX, point.x, "卡片：該點是左上角")
        XCTAssertEqual(character.maxX, point.x, "角色：該點是右上角")
        XCTAssertNotEqual(card, character)
    }
}
