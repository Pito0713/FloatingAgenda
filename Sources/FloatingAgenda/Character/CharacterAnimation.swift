import AppKit

/// 逐格動畫的純計算：第幾格、要不要眨眼、位移多少。
///
/// 抽出來的理由有兩個：真正的動畫測不到，而這些規則要能被單元測試釘住；
/// 以及繪圖端（`CharacterHostView`）與 snapshot 端（`CharacterSpriteView`）都要用。
enum CharacterAnimation {
    /// 4 fps（M9 計畫 §5.3）
    static let frameInterval: TimeInterval = 0.25

    /// 每格像素放大成 4pt，位移一律是**整格**，像素感才不會糊掉
    static let pixelScale = PanelMetrics.characterSize / CGFloat(PixelSprite.side)

    /// 從時間算出第幾格。用絕對時間而不是累加狀態，
    /// 就算漏掉幾次更新也不會讓動畫偏掉
    static func tick(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / frameInterval)
    }

    /// 眨眼的時間點（§4.3：每 3–5 秒一次、持續 1 格）。
    ///
    /// 做法是把 12–20 格（＝3–5 秒）的間隔排成一個**固定循環表**，
    /// 總長 125 格（約 31 秒）之後重複。
    ///
    /// 不用「每次算一個亂數」也不用累加狀態：
    /// 同一個 tick 永遠得到同一個答案，畫面不會因為重繪而閃動，測試也能重現；
    /// 而且間隔由表保證落在規格範圍內——第一版用 `tick % (12 + hash)` 算，
    /// 實測會跑出 7 格與 26 格的間隔（`CharacterAnimationTests` 抓到的）。
    private static let blinkIntervals = [12, 17, 14, 20, 15, 13, 18, 16]

    private static let blinkCycle = blinkIntervals.reduce(0, +)

    private static let blinkOffsets: Set<Int> = {
        var offsets: Set<Int> = []
        var running = 0
        for interval in blinkIntervals {
            offsets.insert(running)
            running += interval
        }
        return offsets
    }()

    static func isBlinking(tick: Int, mood: Mood) -> Bool {
        guard mood != .sleepy else { return false }   // 本來就閉著眼
        // Swift 的 % 對負數會給負值，要再補一次
        let position = ((tick % blinkCycle) + blinkCycle) % blinkCycle
        return blinkOffsets.contains(position)
    }

    /// 純動畫格，不含眨眼。
    /// `--snapshot` 指定第幾格時走這裡——它的語意是「我要看第 n 格長什麼樣」，
    /// 若讓眨眼蓋過去會剛好撞上眨眼格而畫出閉眼的臉（實測踩到）
    static func animationFrame(mood: Mood, index: Int) -> [String] {
        let frames = BuiltinCharacter.frames(for: mood)
        return frames[abs(index) % frames.count]
    }

    /// 某個 tick 實際要畫的格子
    static func rows(mood: Mood, tick: Int) -> [String] {
        if isBlinking(tick: tick, mood: mood), let blink = BuiltinCharacter.blinkFrame(for: mood) {
            return blink
        }
        return animationFrame(mood: mood, index: tick)
    }

    /// 垂直位移。位移一律是整格（1 格像素 ＝ 4pt），不是平滑位移
    static func offset(mood: Mood, tick: Int, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, mood.isAnimated else { return 0 }
        if mood.shakes {
            // 每 5 秒左右抖一下：20 格 ＝ 5 秒，只有其中 2 格有位移
            let phase = ((tick % 20) + 20) % 20
            if phase == 0 { return -pixelScale }
            if phase == 1 { return pixelScale }
            return 0
        }
        // 上下彈跳：兩格一循環
        return tick.isMultiple(of: 2) ? 0 : -pixelScale
    }

    /// 格子轉 CGImage 每格都重算太浪費，而且會讓常駐動畫一直配置記憶體。
    /// 格子資料是固定的，快取起來
    @MainActor private static var cache: [String: CGImage] = [:]

    @MainActor
    static func image(rows: [String], mood: Mood) -> CGImage {
        let key = "\(mood.rawValue)|\(rows.joined())"
        if let hit = cache[key] { return hit }
        // 格子資料在 PixelSpriteTests 驗過，這裡走不到失敗分支；
        // 真的失敗就給一張空圖，絕不讓常駐的角色把 App 打掛
        let image = (try? PixelSprite.Grid(rows))
            .flatMap { PixelSprite.image($0, palette: .init(body: mood.bodyColor)) }
            ?? blankImage()
        cache[key] = image
        return image
    }

    private static func blankImage() -> CGImage {
        let context = CGContext(data: nil, width: PixelSprite.side, height: PixelSprite.side,
                                bitsPerComponent: 8, bytesPerRow: PixelSprite.side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context!.makeImage()!
    }
}
