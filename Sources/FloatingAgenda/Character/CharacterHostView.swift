import AppKit
import SwiftUI

/// 小精靈在**正式 App** 裡的實作：一個自己畫圖、自己驅動計時器、自己處理滑鼠的 NSView。
///
/// ## 為什麼不是純 SwiftUI
///
/// M9 計畫 §5.3 指定用 `TimelineView(.periodic(by: 0.25))` 驅動 4 fps，
/// 理由是「不要用 `repeatForever` 的 SwiftUI 動畫，那會用螢幕更新率一直重繪」。
/// 方向是對的，但 **`TimelineView` 也沒過 §7.1 的 CPU 預算**：
///
/// ```
/// 完整模式（無動畫）                    0.03%
/// TimelineView 4 fps                    3.15%   ← 超過 §7.1 的 2% 上限
/// TimelineView 4 fps ＋ 拿掉位移        3.25%   ← 不是位移的成本
/// TimelineView 4 fps ＋ 每格畫同一張圖  2.96%   ← 也不是換圖的成本
/// TimelineView 1 fps                    0.05%
/// ```
///
/// 成本是 `TimelineView` 每秒 4 次讓 SwiftUI 重新求值整個視圖樹本身。
/// §7.1 的 CPU 上限是硬性驗收條件，所以改由 NSView 直接繪圖：
/// 計時器只做 `setNeedsDisplay`，`draw(_:)` 把一張 16×16 的 CGImage 以最近鄰放大。
///
/// ## 滑鼠（§5.4）
///
/// 同一塊區域要能**點**、能**拖**、能**右鍵**，三者不能互相吃掉：
/// - `mouseDown` 記下起點，先不做任何事
/// - `mouseDragged` 超過 3pt 才呼叫 `performDrag`，這之後就不算點擊
/// - `mouseUp` 時若從未超過門檻，就當成點一下
///
/// 刻意不用 SwiftUI 的 `DragGesture` ＋ `onTapGesture`：
/// 在 nonactivating 的面板上，第一下點擊常常被系統吃掉（M1、M3 都踩過）。
final class CharacterHostView: NSView {
    var mood: Mood = .happy {
        didSet { if mood != oldValue { needsDisplay = true } }
    }
    /// 要用哪個皮膚畫（M9 計畫 §4.6）
    var skin: Skin = CharacterAnimation.builtinSkin {
        didSet {
            guard skin != oldValue else { return }
            needsDisplay = true
            updateTimer()   // 每個皮膚的 fps 可能不同
        }
    }
    /// 面板隱藏、螢幕睡眠或鎖定時設成 false，計時器就會停掉（§5.3）
    var isAnimating = true {
        didSet { if isAnimating != oldValue { updateTimer() } }
    }
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private var timer: Timer?

    /// 測試用：計時器是不是真的在跑。常駐動畫的生命週期只能這樣驗
    var hasRunningTimer: Bool { timer?.isValid == true }
    private var currentTick = 0
    private var mouseDownLocation: CGPoint?
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未支援") }

    deinit { timer?.invalidate() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }

    // MARK: - 計時器

    private func updateTimer() {
        timer?.invalidate()
        timer = nil
        // 沒有視窗（還沒掛上或已經移除）就不要跑計時器
        guard isAnimating, window != nil else { return }

        let interval = CharacterAnimation.interval(for: skin)
        currentTick = CharacterAnimation.tick(at: Date(), interval: interval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTick = CharacterAnimation.tick(
                    at: Date(), interval: CharacterAnimation.interval(for: self.skin))
                self.needsDisplay = true
            }
        }
        // 容忍度讓系統可以把喚醒合併到別的計時器上，省電
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        needsDisplay = true
    }

    // MARK: - 繪圖

    /// ⚠️ **不要設 `isFlipped = true`**。
    ///
    /// 翻轉的 NSView 會讓 AppKit 幫 CGContext 套上一層上下翻轉的變換，
    /// 而 `CGContext.draw(_:in:)` 本身是由下往上畫的——兩者疊起來的結果是
    /// **角色上下顛倒**（耳朵跑到下面、腳跑到上面）。
    /// 這個 bug 用讀碼看不出來，是 codex 2026-09-22 指出後用 `cacheDisplay`
    /// 實際把畫面抓下來驗才確認的，`CharacterHostViewTests` 已把它釘住。
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let tick = isAnimating ? currentTick : 0
        guard let image = CharacterAnimation.image(skin: skin, mood: mood, tick: tick) else {
            return   // 皮膚壞掉也不要畫出奇怪的東西
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let offset = isAnimating
            ? CharacterAnimation.offset(mood: mood, tick: tick, reduceMotion: reduceMotion)
            : 0

        let side = PanelMetrics.characterSize
        let padding = PanelMetrics.characterPadding
        // 未翻轉的座標系是**由下往上**，而 offset 沿用 SwiftUI 的慣例（負值代表往上），
        // 所以這裡要減不是加
        let rect = NSRect(x: padding, y: padding - offset, width: side, height: side)

        // 像素要銳利
        context.interpolationQuality = .none
        context.draw(image, in: rect)
    }

    // MARK: - 滑鼠

    /// 面板不搶焦點，沒有這個第一下點擊會被系統吃掉
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, !didDrag else { return }
        guard CharacterHostView.isDrag(from: start, to: event.locationInWindow) else { return }
        didDrag = true
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            didDrag = false
        }
        guard mouseDownLocation != nil, !didDrag else { return }
        onClick?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    /// 超過這個距離就算拖曳，不算點擊
    static let dragThreshold: CGFloat = 3

    /// 判定純函式化，才能用單元測試釘住門檻行為
    static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        let dx = current.x - start.x
        let dy = current.y - start.y
        return (dx * dx + dy * dy).squareRoot() > dragThreshold
    }
}

/// 把 `CharacterHostView` 接進 SwiftUI。
struct CharacterLiveView: NSViewRepresentable {
    let mood: Mood
    var skin: Skin = CharacterAnimation.builtinSkin
    var isAnimating = true
    var onClick: () -> Void = {}
    var menu: () -> NSMenu? = { nil }

    func makeNSView(context: Context) -> CharacterHostView {
        let view = CharacterHostView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: CharacterHostView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: CharacterHostView) {
        view.mood = mood
        view.skin = skin
        view.isAnimating = isAnimating
        view.onClick = onClick
        view.menuProvider = menu
    }
}
