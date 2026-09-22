import XCTest
@testable import FloatingAgenda

/// 小精靈在正式 App 裡的繪圖路徑。
///
/// 用 `cacheDisplay(in:to:)` 把 `CharacterHostView.draw(_:)` 實際畫出來的內容抓下來檢查——
/// 這是唯一能自動驗證「畫出來長什麼樣」的方法（沒有螢幕錄製權限，
/// 而 `ImageRenderer` 畫不出 `NSViewRepresentable`）。
@MainActor
final class CharacterHostViewTests: XCTestCase {

    private let side = PanelMetrics.characterSize + PanelMetrics.characterPadding * 2

    private func render(mood: Mood = .happy) throws -> NSBitmapImageRep {
        let view = CharacterHostView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.mood = mood
        view.isAnimating = false   // 停在第 0 格，輸出才可重現
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// 把畫面上的某個點換算回格子座標（rep 的 y=0 是最上面那一列）
    private func isOpaque(_ rep: NSBitmapImageRep, gridRow: Int, gridColumn: Int) -> Bool {
        let scale = PanelMetrics.characterSize / CGFloat(PixelSprite.side)
        let x = Int(PanelMetrics.characterPadding + (CGFloat(gridColumn) + 0.5) * scale)
        let y = Int(PanelMetrics.characterPadding + (CGFloat(gridRow) + 0.5) * scale)
        guard let color = rep.colorAt(x: x, y: y) else { return false }
        return color.alphaComponent > 0.5
    }

    /// ⚠️ 本檔最重要的一條：角色**不能上下顛倒**。
    ///
    /// 第一版把 view 設成 `isFlipped = true`，AppKit 會幫 CGContext 套上翻轉變換，
    /// 而 `CGContext.draw(_:in:)` 本身是由下往上畫的，兩者疊起來讓角色整個倒過來
    /// （耳朵在下、腳在上）。讀碼完全看不出來，codex 2026-09-22 指出後實測確認。
    func testCharacterIsNotDrawnUpsideDown() throws {
        let rep = try render(mood: .happy)

        // 第 1 列第 3 欄是耳朵，第 14 列第 4 欄是腳
        XCTAssertTrue(isOpaque(rep, gridRow: 1, gridColumn: 3), "耳朵應該在上面")
        XCTAssertTrue(isOpaque(rep, gridRow: 14, gridColumn: 4), "腳應該在下面")

        // 顛倒的話這兩個位置會反過來：第 1 列第 8 欄（耳朵之間）應該是透明的
        XCTAssertFalse(isOpaque(rep, gridRow: 1, gridColumn: 8), "兩耳之間應該是透明的")
        // 第 0 列與第 15 列整列透明
        XCTAssertFalse(isOpaque(rep, gridRow: 0, gridColumn: 8))
        XCTAssertFalse(isOpaque(rep, gridRow: 15, gridColumn: 8))
    }

    /// 身體中央要是該心情的主色，不是外框色也不是透明
    func testBodyUsesTheMoodColour() throws {
        for mood in Mood.allCases {
            let rep = try render(mood: mood)
            let scale = PanelMetrics.characterSize / CGFloat(PixelSprite.side)
            let x = Int(PanelMetrics.characterPadding + 8.5 * scale)
            let y = Int(PanelMetrics.characterPadding + 4.5 * scale)
            let color = try XCTUnwrap(rep.colorAt(x: x, y: y)).usingColorSpace(.sRGB)!
            let expected = mood.bodyColor.usingColorSpace(.sRGB)!
            XCTAssertEqual(color.redComponent, expected.redComponent, accuracy: 0.02,
                           "\(mood) 的身體顏色不對")
            XCTAssertEqual(color.greenComponent, expected.greenComponent, accuracy: 0.02)
            XCTAssertEqual(color.blueComponent, expected.blueComponent, accuracy: 0.02)
        }
    }

    /// 四種心情畫出來要真的不一樣
    func testMoodsRenderDifferently() throws {
        var rendered: [Data] = []
        for mood in Mood.allCases {
            rendered.append(try XCTUnwrap(render(mood: mood).representation(using: .png,
                                                                           properties: [:])))
        }
        for (index, data) in rendered.enumerated() {
            for other in rendered[(index + 1)...] {
                XCTAssertNotEqual(data, other, "有兩種心情畫出來一模一樣")
            }
        }
    }

    // MARK: - 計時器生命週期

    /// 沒有掛上視窗就不該起計時器（常駐動畫不能在看不見的時候跑）。
    ///
    /// ⚠️ 必須先關再開：`isAnimating` 預設就是 `true`，直接指派 `true`
    /// 會被 `didSet` 的相等性守衛擋掉，`updateTimer()` 根本不會被呼叫——
    /// 那樣這條測試不管實作對錯都會通過（2026-09-22 變異測試發現）
    func testNoTimerWhenNotInAWindow() {
        let view = CharacterHostView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.isAnimating = false
        view.isAnimating = true   // 強制走一次 updateTimer()
        XCTAssertFalse(view.hasRunningTimer, "沒有視窗就不該有計時器")
    }

    /// 從視窗上移除後計時器也要停
    func testTimerStopsWhenRemovedFromWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let view = CharacterHostView(frame: window.contentLayoutRect)
        window.contentView?.addSubview(view)
        XCTAssertTrue(view.hasRunningTimer)

        view.removeFromSuperview()
        XCTAssertFalse(view.hasRunningTimer, "離開視窗後不該繼續跑計時器")
    }

    func testTimerStopsWhenAnimationIsTurnedOff() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let view = CharacterHostView(frame: window.contentLayoutRect)
        window.contentView?.addSubview(view)

        view.isAnimating = true
        XCTAssertTrue(view.hasRunningTimer, "掛上視窗又開著動畫，應該要有計時器")

        view.isAnimating = false
        XCTAssertFalse(view.hasRunningTimer, "關掉動畫就該停掉計時器")
    }
}
