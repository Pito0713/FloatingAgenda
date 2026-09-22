import XCTest
@testable import FloatingAgenda

/// 逐格動畫的選格邏輯與點擊／拖曳的門檻判定。
///
/// 兩者都刻意抽成純函式（`CharacterAnimation.tick`／`isBlinking`、
/// `CharacterHostView.isDrag`），因為真正的動畫與滑鼠事件都測不到。
final class CharacterAnimationTests: XCTestCase {

    // MARK: - 4 fps 的選格

    func testTickAdvancesFourTimesPerSecond() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        XCTAssertEqual(CharacterAnimation.tick(at: start.addingTimeInterval(0.25))
                       - CharacterAnimation.tick(at: start), 1)
        XCTAssertEqual(CharacterAnimation.tick(at: start.addingTimeInterval(1.0))
                       - CharacterAnimation.tick(at: start), 4, "一秒應該前進 4 格")
    }

    /// 同一格區間內的任何時間點都要得到同一格，否則畫面會抖
    func testTickIsStableWithinAFrame() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let base = CharacterAnimation.tick(at: start)
        for offset in [0.0, 0.05, 0.12, 0.24] {
            XCTAssertEqual(CharacterAnimation.tick(at: start.addingTimeInterval(offset)), base)
        }
    }

    /// 用絕對時間算格數：漏掉幾次更新也不會讓動畫偏掉
    func testTickIsDerivedFromAbsoluteTimeNotAccumulated() {
        let a = Date(timeIntervalSinceReferenceDate: 500)
        let b = Date(timeIntervalSinceReferenceDate: 500 + 10)
        XCTAssertEqual(CharacterAnimation.tick(at: b) - CharacterAnimation.tick(at: a), 40)
    }

    // MARK: - 眨眼

    /// 睡著的時候本來就閉著眼，不該再眨
    func testSleepyNeverBlinks() {
        for tick in 0..<400 {
            XCTAssertFalse(CharacterAnimation.isBlinking(tick: tick, mood: .sleepy))
        }
    }

    /// 眨眼要真的會發生，而且間隔落在 3–5 秒（12–20 格）之間
    func testBlinkIntervalIsBetweenThreeAndFiveSeconds() {
        var blinks: [Int] = []
        for tick in 0..<2_000 where CharacterAnimation.isBlinking(tick: tick, mood: .happy) {
            blinks.append(tick)
        }
        XCTAssertGreaterThan(blinks.count, 50, "2000 格內應該眨很多次")

        for (index, tick) in blinks.enumerated().dropFirst() {
            let gap = tick - blinks[index - 1]
            XCTAssertGreaterThanOrEqual(gap, 12, "眨眼間隔不該短於 3 秒（第 \(tick) 格）")
            XCTAssertLessThanOrEqual(gap, 20, "眨眼間隔不該長於 5 秒（第 \(tick) 格）")
        }
    }

    /// 間隔要有變化，不能每次都一樣（看起來會像機械節拍）
    func testBlinkIntervalVaries() {
        var gaps: Set<Int> = []
        var previous: Int?
        for tick in 0..<2_000 where CharacterAnimation.isBlinking(tick: tick, mood: .happy) {
            if let previous { gaps.insert(tick - previous) }
            previous = tick
        }
        XCTAssertGreaterThan(gaps.count, 1, "眨眼間隔應該有變化")
    }

    /// 同一格問兩次要得到同樣的答案，否則重繪時眼睛會亂閃
    func testBlinkIsDeterministic() {
        for tick in 0..<200 {
            XCTAssertEqual(CharacterAnimation.isBlinking(tick: tick, mood: .busy),
                           CharacterAnimation.isBlinking(tick: tick, mood: .busy))
        }
    }

    // MARK: - 拖曳門檻

    func testTinyMovementIsNotADrag() {
        let start = CGPoint(x: 100, y: 100)
        XCTAssertFalse(CharacterHostView.isDrag(from: start, to: start))
        XCTAssertFalse(CharacterHostView.isDrag(from: start,
                                                       to: CGPoint(x: 102, y: 100)))
        XCTAssertFalse(CharacterHostView.isDrag(from: start,
                                                       to: CGPoint(x: 102, y: 102)),
                       "對角線 2.8pt 仍在門檻內")
    }

    func testMovementBeyondThresholdIsADrag() {
        let start = CGPoint(x: 100, y: 100)
        XCTAssertTrue(CharacterHostView.isDrag(from: start,
                                                      to: CGPoint(x: 104, y: 100)))
        XCTAssertTrue(CharacterHostView.isDrag(from: start,
                                                      to: CGPoint(x: 100, y: 96)))
    }

    /// 門檻是距離不是單軸：左右各 3pt 合起來超過門檻
    func testThresholdUsesDistanceNotPerAxis() {
        let start = CGPoint(x: 0, y: 0)
        XCTAssertTrue(CharacterHostView.isDrag(from: start, to: CGPoint(x: 3, y: 3)),
                      "兩軸各 3pt 的距離是 4.24pt，應該算拖曳")
    }

    func testDragIsSymmetric() {
        let a = CGPoint(x: 10, y: 10)
        let b = CGPoint(x: 20, y: 20)
        XCTAssertEqual(CharacterHostView.isDrag(from: a, to: b),
                       CharacterHostView.isDrag(from: b, to: a))
    }
}

/// `fixedFrameIndex`（`--snapshot` 用）的語意
final class CharacterFixedFrameTests: XCTestCase {

    /// 第 0 格剛好是一個眨眼的時間點。指定動畫格時**不該**被眨眼蓋過去，
    /// 否則 snapshot 會畫出閉眼的臉（實測踩到，2026-09-22）
    func testFixedFrameZeroIsNotTheBlinkFrame() throws {
        XCTAssertTrue(CharacterAnimation.isBlinking(tick: 0, mood: .happy),
                      "前提：第 0 格確實是眨眼點，否則這條沒有鑑別力")
        for mood in Mood.allCases {
            XCTAssertEqual(CharacterAnimation.animationFrame(mood: mood, index: 0),
                           BuiltinCharacter.frames(for: mood)[0],
                           "\(mood) 指定第 0 格時應該拿到動畫格，不是眨眼格")
        }
    }

    func testAnimationFrameWrapsAround() {
        for mood in Mood.allCases {
            let frames = BuiltinCharacter.frames(for: mood)
            XCTAssertEqual(CharacterAnimation.animationFrame(mood: mood, index: frames.count),
                           frames[0])
        }
    }

    /// 輪播路徑仍然要會眨眼
    func testAnimatedPathStillBlinks() {
        let blinking = CharacterAnimation.rows(mood: .happy, tick: 0)
        XCTAssertEqual(blinking, BuiltinCharacter.blinkFrame(for: .happy))
    }
}

/// 補 codex 2026-09-22 指出的鑑別力缺口：原本的選格測試只驗 index 0 與循環回 0，
/// `animationFrame` 就算永遠回傳第 0 格也會通過
extension CharacterFixedFrameTests {

    func testAnimationFrameActuallyAdvances() {
        for mood in Mood.allCases {
            let frames = BuiltinCharacter.frames(for: mood)
            for index in 0..<frames.count {
                XCTAssertEqual(CharacterAnimation.animationFrame(mood: mood, index: index),
                               frames[index],
                               "\(mood) 的第 \(index) 格應該拿到對應的格子")
            }
            XCTAssertNotEqual(CharacterAnimation.animationFrame(mood: mood, index: 0),
                              CharacterAnimation.animationFrame(mood: mood, index: 1),
                              "\(mood) 第 0 格與第 1 格不該相同，否則動畫沒有在換格")
        }
    }

    /// 連續的 tick 要真的畫出不同的格子（眨眼之外也要會動）
    func testConsecutiveTicksProduceDifferentFrames() {
        for mood in Mood.allCases {
            let a = CharacterAnimation.rows(mood: mood, tick: 4)
            let b = CharacterAnimation.rows(mood: mood, tick: 5)
            XCTAssertNotEqual(a, b, "\(mood) 連續兩格畫的是同一張圖")
        }
    }
}

/// 外部皮膚宣告的 fps 要真的生效（codex 2026-09-22 指出原本全部強制 4 fps）
@MainActor
final class SkinFPSTests: XCTestCase {

    private func skin(fps: Int) -> Skin {
        Skin(id: "skin.test", name: "測試", frames: CharacterAnimation.builtinSkin.frames,
             blink: nil, fps: fps)
    }

    func testIntervalFollowsTheDeclaredFPS() {
        XCTAssertEqual(CharacterAnimation.interval(for: skin(fps: 4)), 0.25, accuracy: 0.0001)
        XCTAssertEqual(CharacterAnimation.interval(for: skin(fps: 1)), 1.0, accuracy: 0.0001)
        XCTAssertEqual(CharacterAnimation.interval(for: skin(fps: 12)),
                       1.0 / 12, accuracy: 0.0001)
    }

    /// 不同 fps 的皮膚換格速度要真的不一樣
    func testDifferentFPSAdvancesAtDifferentRates() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let later = start.addingTimeInterval(1)
        let fast = CharacterAnimation.tick(at: later, interval: CharacterAnimation.interval(for: skin(fps: 12)))
            - CharacterAnimation.tick(at: start, interval: CharacterAnimation.interval(for: skin(fps: 12)))
        let slow = CharacterAnimation.tick(at: later, interval: CharacterAnimation.interval(for: skin(fps: 1)))
            - CharacterAnimation.tick(at: start, interval: CharacterAnimation.interval(for: skin(fps: 1)))
        XCTAssertEqual(fast, 12, "12 fps 一秒該前進 12 格")
        XCTAssertEqual(slow, 1, "1 fps 一秒該前進 1 格")
    }

    /// 超出 1…12 的值要被夾限，不能讓 interval 變成 0 或負數把計時器搞爆
    func testOutOfRangeFPSIsClamped() {
        XCTAssertEqual(CharacterAnimation.interval(for: skin(fps: 0)), 1.0, accuracy: 0.0001)
        XCTAssertEqual(CharacterAnimation.interval(for: skin(fps: -3)), 1.0, accuracy: 0.0001)
        XCTAssertEqual(CharacterAnimation.interval(for: skin(fps: 999)),
                       1.0 / 12, accuracy: 0.0001)
    }

    func testZeroIntervalDoesNotCrash() {
        XCTAssertNoThrow(_ = CharacterAnimation.tick(at: Date(), interval: 0))
    }
}
