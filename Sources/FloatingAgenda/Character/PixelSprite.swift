import AppKit

/// 內建像素角色：用字元格定義，程式裡轉成 `CGImage`，**不放圖檔**（M9 計畫 §5.3）。
///
/// 格子壞掉（列數不對、某列長度不對、用了未定義的字元）一律在**建構時**丟錯，
/// 由 `PixelSpriteTests` 在測試階段擋下來，不會等到執行時才發現。
enum PixelSprite {
    /// 16×16 像素格，每格 4pt → 64pt
    static let side = 16

    /// 字元對應的用途（計畫 §5.3 的字元表）
    enum Ink: Character {
        /// 透明
        case clear = "."
        /// 外框（深色，每種心情共用）
        case outline = "D"
        /// 身體主色，依心情換色
        case body = "B"
        /// 身體陰影，主色調暗 25%
        case shade = "S"
        /// 眼白
        case eyeWhite = "W"
        /// 瞳孔與嘴巴
        case ink = "K"
        /// 腮紅
        case blush = "P"
        /// 特效（汗滴、z），淺藍
        case effect = "X"
    }

    enum GridError: Error, CustomStringConvertible {
        case wrongRowCount(Int)
        case wrongRowLength(row: Int, length: Int)
        case unknownCharacter(row: Int, column: Int, character: Character)

        var description: String {
            switch self {
            case .wrongRowCount(let count):
                "格子必須剛好 \(PixelSprite.side) 列，實際 \(count) 列"
            case .wrongRowLength(let row, let length):
                "第 \(row) 列必須剛好 \(PixelSprite.side) 個字元，實際 \(length) 個"
            case .unknownCharacter(let row, let column, let character):
                "第 \(row) 列第 \(column) 欄出現未定義的字元「\(character)」"
            }
        }
    }

    /// 一張 16×16 的格子圖
    struct Grid {
        let pixels: [[Ink]]

        init(_ rows: [String]) throws {
            guard rows.count == PixelSprite.side else {
                throw GridError.wrongRowCount(rows.count)
            }
            var parsed: [[Ink]] = []
            for (y, row) in rows.enumerated() {
                let characters = Array(row)
                guard characters.count == PixelSprite.side else {
                    throw GridError.wrongRowLength(row: y, length: characters.count)
                }
                var line: [Ink] = []
                for (x, character) in characters.enumerated() {
                    guard let ink = Ink(rawValue: character) else {
                        throw GridError.unknownCharacter(row: y, column: x, character: character)
                    }
                    line.append(ink)
                }
                parsed.append(line)
            }
            pixels = parsed
        }
    }

    /// 一種心情的配色。`outline`／`eyeWhite`／`ink`／`effect` 所有心情共用
    struct Palette {
        let body: NSColor

        static let outline = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.16, alpha: 1)
        static let eyeWhite = NSColor.white
        static let ink = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.16, alpha: 1)
        static let blush = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.58, alpha: 1)
        static let effect = NSColor(srgbRed: 0.60, green: 0.85, blue: 1.0, alpha: 1)

        /// 主色調暗 25%（計畫 §5.3 的 `S`）
        var shade: NSColor {
            let base = body.usingColorSpace(.sRGB) ?? body
            return NSColor(srgbRed: base.redComponent * 0.75,
                           green: base.greenComponent * 0.75,
                           blue: base.blueComponent * 0.75,
                           alpha: base.alphaComponent)
        }

        func color(for ink: Ink) -> NSColor? {
            switch ink {
            case .clear: nil
            case .outline: Self.outline
            case .body: body
            case .shade: shade
            case .eyeWhite: Self.eyeWhite
            case .ink: Self.ink
            case .blush: Self.blush
            case .effect: Self.effect
            }
        }
    }

    /// 把格子畫成 16×16 的 `CGImage`。放大交給 View 做最近鄰插值，這裡不放大
    static func image(_ grid: Grid, palette: Palette) -> CGImage? {
        let side = PixelSprite.side
        guard let context = CGContext(data: nil,
                                      width: side,
                                      height: side,
                                      bitsPerComponent: 8,
                                      bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.setShouldAntialias(false)
        for (y, row) in grid.pixels.enumerated() {
            for (x, ink) in row.enumerated() {
                guard let color = palette.color(for: ink),
                      let srgb = color.usingColorSpace(.sRGB) else { continue }
                context.setFillColor(srgb.cgColor)
                // 格子的第 0 列在上面，CGContext 的原點在左下，所以要翻轉 y
                context.fill(CGRect(x: x, y: side - 1 - y, width: 1, height: 1))
            }
        }
        return context.makeImage()
    }
}
