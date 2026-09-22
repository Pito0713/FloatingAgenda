import XCTest
@testable import FloatingAgenda

/// 像素格子的驗證與內建角色的資料完整性。
///
/// 計畫 §5.3：「格子資料壞掉就在測試階段失敗，不要等到執行時才發現」——
/// 這個檔案就是那道關卡。
final class PixelSpriteTests: XCTestCase {

    private func grid(_ rows: [String]) throws -> PixelSprite.Grid {
        try PixelSprite.Grid(rows)
    }

    private func validRows(_ fill: Character = ".") -> [String] {
        Array(repeating: String(repeating: String(fill), count: PixelSprite.side),
              count: PixelSprite.side)
    }

    // MARK: - 格子驗證

    func testAcceptsAWellFormedGrid() throws {
        XCTAssertNoThrow(try grid(validRows()))
    }

    func testRejectsWrongRowCount() {
        XCTAssertThrowsError(try grid(Array(validRows().dropLast()))) { error in
            guard case PixelSprite.GridError.wrongRowCount(let count) = error else {
                return XCTFail("錯誤型別不對：\(error)")
            }
            XCTAssertEqual(count, PixelSprite.side - 1)
        }
    }

    func testRejectsTooManyRows() {
        XCTAssertThrowsError(try grid(validRows() + [validRows()[0]]))
    }

    func testRejectsShortRow() {
        var rows = validRows()
        rows[5] = String(rows[5].dropLast())
        XCTAssertThrowsError(try grid(rows)) { error in
            guard case PixelSprite.GridError.wrongRowLength(let row, let length) = error else {
                return XCTFail("錯誤型別不對：\(error)")
            }
            XCTAssertEqual(row, 5)
            XCTAssertEqual(length, PixelSprite.side - 1)
        }
    }

    func testRejectsLongRow() {
        var rows = validRows()
        rows[0] += "."
        XCTAssertThrowsError(try grid(rows))
    }

    func testRejectsUnknownCharacter() {
        var rows = validRows()
        var line = Array(rows[3])
        line[7] = "Z"
        rows[3] = String(line)
        XCTAssertThrowsError(try grid(rows)) { error in
            guard case PixelSprite.GridError.unknownCharacter(let row, let column, let character) = error else {
                return XCTFail("錯誤型別不對：\(error)")
            }
            XCTAssertEqual(row, 3)
            XCTAssertEqual(column, 7)
            XCTAssertEqual(character, "Z")
        }
    }

    /// 字元表裡的每個字元都要能被接受
    func testEveryDefinedInkCharacterIsAccepted() throws {
        for ink in ["." , "D", "B", "S", "W", "K", "P", "X"] {
            XCTAssertNoThrow(try grid(validRows(Character(ink))), "「\(ink)」應該是合法字元")
        }
    }

    // MARK: - 內建角色的資料完整性

    /// 每一種心情的每一格都要能建起來。寫壞的格子在這裡就會爆
    func testEveryBuiltinFrameParses() throws {
        for mood in Mood.allCases {
            let frames = BuiltinCharacter.frames(for: mood)
            for (index, rows) in frames.enumerated() {
                XCTAssertNoThrow(try grid(rows), "\(mood) 第 \(index) 格的格子資料有問題")
            }
        }
    }

    func testEveryMoodHasAtLeastTwoFrames() {
        for mood in Mood.allCases {
            XCTAssertGreaterThanOrEqual(BuiltinCharacter.frames(for: mood).count, 2,
                                        "\(mood) 至少要有 2 格（計畫 §5.3）")
        }
    }

    /// 同一種心情的兩格必須真的不一樣，否則動畫等於沒動
    func testFramesWithinAMoodDiffer() {
        for mood in Mood.allCases {
            let frames = BuiltinCharacter.frames(for: mood)
            XCTAssertNotEqual(frames[0], frames[1], "\(mood) 的兩格長得一模一樣，動畫看不出來")
        }
    }

    /// 眨眼格：非睡著的心情都要有，而且要跟第 0 格不同
    func testBlinkFrameExistsForAwakeMoods() throws {
        for mood in Mood.allCases where mood != .sleepy {
            let blink = try XCTUnwrap(BuiltinCharacter.blinkFrame(for: mood),
                                      "\(mood) 應該要有眨眼格")
            XCTAssertNoThrow(try grid(blink))
            XCTAssertNotEqual(blink, BuiltinCharacter.frames(for: mood)[0])
        }
    }

    /// 睡著本來就閉著眼，不需要眨眼
    func testSleepyHasNoBlinkFrame() {
        XCTAssertNil(BuiltinCharacter.blinkFrame(for: .sleepy))
    }

    /// 眨眼格只該動到眼睛那兩列，嘴型與特效要跟第 0 格一致
    func testBlinkFrameOnlyChangesTheEyeRows() throws {
        for mood in Mood.allCases where mood != .sleepy {
            let base = BuiltinCharacter.frames(for: mood)[0]
            let blink = try XCTUnwrap(BuiltinCharacter.blinkFrame(for: mood))
            for row in 0..<PixelSprite.side where row != 6 && row != 7 {
                XCTAssertEqual(blink[row], base[row], "\(mood) 的眨眼格不該動到第 \(row) 列")
            }
        }
    }

    // MARK: - 每種心情都要看得出區別

    /// 四種心情的顏色不能重複，否則使用者分不出狀態
    func testMoodColoursAreDistinct() {
        let colors = Mood.allCases.map { $0.bodyColor.usingColorSpace(.sRGB)! }
        for (index, color) in colors.enumerated() {
            for other in colors[(index + 1)...] {
                XCTAssertFalse(color.redComponent == other.redComponent
                               && color.greenComponent == other.greenComponent
                               && color.blueComponent == other.blueComponent,
                               "有兩種心情用了同一個顏色")
            }
        }
    }

    /// 四種心情的第 0 格必須彼此不同（不能只靠顏色區分）
    func testMoodsLookDifferentBeyondColour() {
        let firstFrames = Mood.allCases.map { BuiltinCharacter.frames(for: $0)[0] }
        for (index, frame) in firstFrames.enumerated() {
            for other in firstFrames[(index + 1)...] {
                XCTAssertNotEqual(frame, other, "有兩種心情的格子一模一樣，只差顏色")
            }
        }
    }

    // MARK: - 陰影色

    /// `S` 是主色調暗 25%
    func testShadeIs25PercentDarkerThanBody() {
        let palette = PixelSprite.Palette(body: NSColor(srgbRed: 0.8, green: 0.4, blue: 0.2, alpha: 1))
        let shade = palette.shade.usingColorSpace(.sRGB)!
        XCTAssertEqual(shade.redComponent, 0.6, accuracy: 0.001)
        XCTAssertEqual(shade.greenComponent, 0.3, accuracy: 0.001)
        XCTAssertEqual(shade.blueComponent, 0.15, accuracy: 0.001)
    }

    // MARK: - 繪製

    func testRendersA16x16Image() throws {
        let rows = BuiltinCharacter.frames(for: .happy)[0]
        let image = try XCTUnwrap(PixelSprite.image(try grid(rows),
                                                    palette: .init(body: Mood.happy.bodyColor)))
        XCTAssertEqual(image.width, PixelSprite.side)
        XCTAssertEqual(image.height, PixelSprite.side)
    }

    /// 透明格子要真的是透明的，不能畫成黑色方塊
    func testTransparentPixelsStayTransparent() throws {
        let image = try XCTUnwrap(PixelSprite.image(try grid(validRows()),
                                                    palette: .init(body: .red)))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let corner = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0))
        XCTAssertEqual(corner.alphaComponent, 0, accuracy: 0.01, "全透明的格子不該有顏色")
    }

    /// 第 0 列畫在圖的**上方**（CGContext 原點在左下，程式要翻轉 y）
    func testFirstRowIsDrawnAtTheTop() throws {
        var rows = validRows()
        rows[0] = String(repeating: "B", count: PixelSprite.side)
        let image = try XCTUnwrap(PixelSprite.image(try grid(rows),
                                                    palette: .init(body: .red)))
        let bitmap = NSBitmapImageRep(cgImage: image)
        // NSBitmapImageRep 的 y=0 也是最上面那一列
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 8, y: 0)).alphaComponent, 1,
                       accuracy: 0.01, "第 0 列應該在圖的最上方")
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 8, y: PixelSprite.side - 1)).alphaComponent,
                       0, accuracy: 0.01, "最後一列應該還是透明的")
    }
}
