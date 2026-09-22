import Foundation

/// 內建的原創像素角色，皮膚 ID `builtin.pixel`（M9 計畫 §4.6）。
///
/// **設計說明（§5.3 的版權底線）**：造型是一隻有**兩隻方耳朵**、**兩條分開的短腿**、
/// 帶腮紅與嘴巴的圓身小生物。刻意與既有遊戲角色區隔：
/// Pac-Man 的鬼是圓頂無耳、底部是連續的波浪裙、沒有嘴巴也沒有腮紅；
/// Pac-Man 本體是無五官的扇形；太空侵略者是左右對稱的節肢剪影、沒有臉。
/// 本角色的辨識特徵（耳朵、分開的雙腿、腮紅、會變的嘴型）在那些角色身上都不存在。
///
/// 每一格都是 16×16 的字元格，字元表見 `PixelSprite.Ink`。
/// 格子若寫壞，`PixelSprite.Grid` 的建構會丟錯，由 `PixelSpriteTests` 在測試階段擋下。
enum BuiltinCharacter {
    static let id = "builtin.pixel"
    static let name = "小方"

    /// 身體輪廓（所有心情共用）。臉與特效那幾列由各心情覆寫
    private enum Row {
        static let blank      = "................"
        static let earsTop    = "...DD......DD..."
        static let ears       = "..DBBD....DBBD.."
        static let headTop    = ".DBBBBDDDDBBBBD."
        static let body       = ".DBBBBBBBBBBBBD."
        static let eyesOpen   = ".DBWWBBBBBBWWBD."
        static let pupils     = ".DBWKBBBBBBKWBD."
        static let pupilsOut  = ".DBKWBBBBBBWKBD."
        static let eyesClosed = ".DBKKBBBBBBKKBD."
        static let browsDown  = ".DBKBBBBBBBBKBD."
        static let mouthFlat  = ".DBBBBKKKKBBBBD."
        static let smileTop   = ".DPBBKBBBBKBBPD."
        static let smileWide  = ".DBBBKKKKKKBBBD."
        static let frownLow   = ".DPBBKBBBBKBBPD."
        static let mouthSmall = ".DBBBBBKKBBBBBD."
        static let shade1     = ".DSBBBBBBBBBBSD."
        static let shade2     = ".DSSBBBBBBBBSSD."
        static let feetTop    = ".DDSSSSSSSSSSDD."
        /// 腳用陰影色而不是外框色：外框色在深色桌面上會跟背景融成一片，
        /// 腳整個消失（實測在 sprite sheet 上看不見）。陰影色是主色調暗 25%，
        /// 深淺背景都看得出來
        static let feet       = "....SS....SS...."
        /// 頭頂上方的特效（汗滴／z）兩個高度
        static let effectLow  = "..DBBD.XX.DBBD.."
        static let effectHigh = "...DD..XX..DD..."
    }

    /// 依序是第 0…15 列
    private static func rows(ears: String,
                            earsTop: String = Row.earsTop,
                            row4: String = Row.body,
                            row5: String = Row.body,
                            eyes: String,
                            pupils: String,
                            row9: String,
                            row10: String) -> [String] {
        [Row.blank, earsTop, ears, Row.headTop,
         row4, row5, eyes, pupils,
         Row.body, row9, row10, Row.shade1,
         Row.shade2, Row.feetTop, Row.feet, Row.blank]
    }

    // MARK: - 各心情的格子

    /// 微笑；第二格嘴巴張大，像在笑出聲
    static let happy: [[String]] = [
        rows(ears: Row.ears, eyes: Row.eyesOpen, pupils: Row.pupils,
             row9: Row.smileTop, row10: Row.mouthFlat),
        rows(ears: Row.ears, eyes: Row.eyesOpen, pupils: Row.pupils,
             row9: Row.smileTop, row10: Row.smileWide),
    ]

    /// 平嘴；第二格眼珠往外看，像在忙別的事
    static let busy: [[String]] = [
        rows(ears: Row.ears, eyes: Row.eyesOpen, pupils: Row.pupils,
             row9: Row.body, row10: Row.mouthFlat),
        rows(ears: Row.ears, eyes: Row.eyesOpen, pupils: Row.pupilsOut,
             row9: Row.body, row10: Row.mouthFlat),
    ]

    /// 眉毛下垂、嘴角往下、頭上有汗滴；兩格的汗滴高度不同
    static let worried: [[String]] = [
        rows(ears: Row.effectLow, row5: Row.browsDown,
             eyes: Row.eyesOpen, pupils: Row.pupils,
             row9: Row.mouthFlat, row10: Row.frownLow),
        rows(ears: Row.ears, earsTop: Row.effectHigh, row5: Row.browsDown,
             eyes: Row.eyesOpen, pupils: Row.pupils,
             row9: Row.mouthFlat, row10: Row.frownLow),
    ]

    /// 閉眼、小嘴、頭上有 z；兩格的 z 高度不同
    static let sleepy: [[String]] = [
        rows(ears: Row.effectLow, eyes: Row.body, pupils: Row.eyesClosed,
             row9: Row.body, row10: Row.mouthSmall),
        rows(ears: Row.ears, earsTop: Row.effectHigh,
             eyes: Row.body, pupils: Row.eyesClosed,
             row9: Row.body, row10: Row.mouthSmall),
    ]

    static func frames(for mood: Mood) -> [[String]] {
        switch mood {
        case .happy: happy
        case .busy: busy
        case .worried: worried
        case .sleepy: sleepy
        }
    }

    /// 眨眼格：拿該心情的第 0 格，把眼睛那兩列換成閉眼。
    ///
    /// 用推導而不是再寫四份格子，嘴型與特效才不會跟第 0 格對不上。
    /// `sleepy` 本來就閉著眼，不需要眨眼
    static func blinkFrame(for mood: Mood) -> [String]? {
        guard mood != .sleepy else { return nil }
        var frame = frames(for: mood)[0]
        frame[6] = Row.body
        frame[7] = Row.eyesClosed
        return frame
    }
}
