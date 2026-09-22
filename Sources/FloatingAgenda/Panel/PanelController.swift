import AppKit
import EventKit
import SwiftUI

private extension NSRect {
    var area: CGFloat { isEmpty ? 0 : width * height }
}

/// 卡片版面常數（PLAN §4.1、§4.2）
enum PanelMetrics {
    static let width: CGFloat = 320
    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 16
    /// 螢幕邊界留白（預設位置用）
    static let screenInset: CGFloat = 20
    /// 建立面板時的暫定高度，第一次 onGeometryChange 就會被實際內容高度取代
    static let initialHeight: CGFloat = 200
    /// 收合模式頂部的專用拖曳區高度（PLAN §4.10）
    static let collapsedDragStripHeight: CGFloat = 24
    /// 角色模式：小精靈 64×64pt（16×16 像素格，每格 4pt；M9 計畫 §4.2）
    static let characterSize: CGFloat = 64
    /// 角色四周的留白。面板大小＝看得到的內容大小，這段邊距留給角色自己畫的陰影
    static let characterPadding: CGFloat = 8
}

/// 面板用哪個角定位。
///
/// 完整與收合模式用**左上角**：寬度固定，高度隨內容變，使用者拖曳時抓的也是那一角。
/// 角色模式用**右上角**：寬高都會隨內容變（小精靈 → 小精靈加泡泡 → 展開的卡片），
/// 泡泡往左長、卡片往左下長，靠右上角定位小精靈才不會跳（M9 計畫 §5.4）。
enum PanelAnchor {
    case topLeft
    case topRight

    func point(of frame: NSRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: frame.minX, y: frame.maxY)
        case .topRight: CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    func frame(at anchor: CGPoint, size: NSSize) -> NSRect {
        switch self {
        case .topLeft:
            NSRect(x: anchor.x, y: anchor.y - size.height,
                   width: size.width, height: size.height)
        case .topRight:
            NSRect(x: anchor.x - size.width, y: anchor.y - size.height,
                   width: size.width, height: size.height)
        }
    }
}

extension DisplayMode {
    var anchor: PanelAnchor {
        switch self {
        case .full, .collapsed: .topLeft
        case .character: .topRight
        }
    }

    /// 真實內容尺寸回報進來之前的暫定值
    var provisionalSize: NSSize {
        switch self {
        case .full, .collapsed:
            return NSSize(width: PanelMetrics.width, height: PanelMetrics.initialHeight)
        case .character:
            let side = PanelMetrics.characterSize + PanelMetrics.characterPadding * 2
            return NSSize(width: side, height: side)
        }
    }

    /// 角色模式沒有毛玻璃底與邊框，陰影由角色自己畫（計畫 §5.4）
    var wantsWindowShadow: Bool { self != .character }
}

/// 面板的根視圖：依注入的顯示模式決定內容，並把量到的**寬與高**回報給 PanelController。
///
/// 完整與收合模式的寬度固定 320pt、高度隨內容；角色模式兩者都隨內容。
/// 回報 `CGSize` 而不是只回報高度，是角色模式的前提（M9 計畫 §5.4）。
///
/// `mode` 是**注入**的，不是自己去讀 `AppSettings`：顯示模式的唯一擁有者是
/// `PanelController`，卡片右上角的箭頭與選單列的分段控制都必須走它，
/// 否則位置記憶與錨點切換會被繞過（codex 2026-09-22 指出箭頭原本就繞過了）。
struct PanelRootView: View {
    let mode: DisplayMode
    let onToggleCollapsed: () -> Void
    let onSizeChange: (CGSize) -> Void
    /// 角色模式的動畫要不要跑。面板隱藏、螢幕睡眠或鎖定時傳 false（M9 計畫 §5.3）
    var isAnimating = true
    var onCharacterClick: () -> Void = {}
    var characterMenu: () -> NSMenu? = { nil }
    private let store = AgendaStore.shared
    private let projects = ProjectStore.shared

    var body: some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                onSizeChange(size)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .full, .collapsed:
            widget
        case .character:
            character
        }
    }

    /// 小精靈疊在互動層上面：互動層負責吃點擊與拖曳，小精靈自己 `allowsHitTesting(false)`。
    /// 面板大小就等於這一塊的大小，旁邊沒有多餘的透明區域擋住桌面（§5.4）
    private var character: some View {
        CharacterLiveView(mood: Mood.decide(reminders: store.remindersState,
                                            projects: projects.state,
                                            now: Date()),
                          isAnimating: isAnimating,
                          onClick: onCharacterClick,
                          menu: characterMenu)
            .frame(width: PanelMetrics.characterSize + PanelMetrics.characterPadding * 2,
                   height: PanelMetrics.characterSize + PanelMetrics.characterPadding * 2)
    }

    private var widget: some View {
        WidgetView(eventsState: store.eventsState,
                   remindersState: store.remindersState,
                   pendingReminderIDs: store.pendingCompletion,
                   reminderError: store.completionError,
                   background: .blur,
                   isCollapsed: mode == .collapsed,
                   onToggleCollapsed: onToggleCollapsed,
                   onOpenEvent: { store.openInCalendar($0) },
                   onToggleReminder: { store.toggleCompletion($0) },
                   onOpenReminder: { store.openInReminders($0) },
                   onOpenCalendarSettings: { store.openPrivacySettings(for: .event) },
                   onOpenReminderSettings: { store.openPrivacySettings(for: .reminder) })
            .frame(width: PanelMetrics.width)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 顯示／隱藏、尺寸同步、位置記憶、透明度、顯示模式切換。
///
/// **顯示模式的唯一擁有者**：卡片右上角的箭頭與選單列的分段控制都必須走
/// `setDisplayMode`。`@Observable` 讓已經開著的選單能跟著箭頭的切換更新
/// （codex 2026-09-22 指出兩者會不同步）。
@MainActor
@Observable
final class PanelController: NSObject, NSWindowDelegate {
    /// 目前的顯示模式。`AppSettings` 是持久化層，這裡是執行期的單一事實來源
    private(set) var displayMode: DisplayMode

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let panel: FloatingPanel
    @ObservationIgnored private let hostingView: FirstMouseHostingView<PanelRootView>
    /// 程式自己調整 frame 時不要把位置寫回設定（避免尺寸同步被當成使用者拖曳）
    @ObservationIgnored private var isAdjustingFrame = false
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var powerObservers: [NSObjectProtocol] = []
    /// 每個模式上次量到的真實內容尺寸。
    ///
    /// 切換模式時拿它當初始尺寸，**不要**先擺一個佔位尺寸再指望
    /// `onGeometryChange` 修正：那個回報只在量到的值**改變**時才觸發，
    /// 而重新指派同型別的 rootView 會保留 SwiftUI 的視圖識別。
    /// 若連續切換讓尺寸繞回原值，回報就不會再來一次，面板會卡在佔位尺寸上
    /// （codex 2026-09-22 指出）。
    @ObservationIgnored private var lastKnownSize: [DisplayMode: NSSize] = [:]
    /// 暫停動畫的原因。螢幕睡眠與工作階段切換是**各自獨立**的：
    /// 共用一個布林值的話，「切換使用者 → 螢幕睡眠 → 另一個使用者喚醒螢幕」
    /// 會讓原本那個工作階段的動畫在看不見的情況下恢復
    /// （codex 2026-09-22 指出）。要全部解除才恢復
    @ObservationIgnored private var screensAsleep = false
    @ObservationIgnored private var sessionInactive = false
    private var isAnimationActive: Bool { !screensAsleep && !sessionInactive }

    /// settings 預設值不能直接寫 `.shared`：預設引數在 nonisolated 情境求值，
    /// Swift 6 語言模式會直接變成錯誤
    init(settings: AppSettings? = nil) {
        let settings = settings ?? .shared
        self.settings = settings
        let mode = settings.displayMode
        displayMode = mode
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: mode.provisionalSize))
        hostingView = FirstMouseHostingView(
            rootView: PanelRootView(mode: mode, onToggleCollapsed: {}, onSizeChange: { _ in }))
        super.init()

        // 不設成 [] 的話，hosting view 自己的尺寸約束會跟我們的 setFrame 打架
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.delegate = self
        panel.alphaValue = settings.opacity
        panel.hasShadow = mode.wantsWindowShadow
        rebuildRootView()
        restoreFrame(size: startingSize(for: mode))
        observeScreenChanges()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        // 電源與工作階段的通知註冊在 NSWorkspace 自己的 center，
        // 拿去 NotificationCenter.default 移除是無效操作（M2 踩過同一個坑）
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        powerObservers.forEach { workspaceCenter.removeObserver($0) }
    }

    var isVisible: Bool { panel.isVisible }

    /// 以下兩個唯讀屬性存在的唯一理由是**讓測試能驗證面板幾何的整合路徑**
    /// （切換模式時位置存進哪個 key、還原到哪、陰影有沒有跟著換）。
    /// codex 2026-09-22 指出原本的測試全在純函式層，controller 存錯 key
    /// 或切換順序寫反都測不出來。production 不使用這兩個屬性。
    var panelFrame: NSRect { panel.frame }
    var panelHasShadow: Bool { panel.hasShadow }

    /// 用 orderFrontRegardless：面板不搶焦點，也不能讓 App 被啟動起來
    func show() {
        panel.orderFrontRegardless()
        rebuildRootView()   // 隱藏期間動畫是停的，顯示回來要重新接上
    }

    func hide() {
        panel.orderOut(nil)
        rebuildRootView()   // 看不見就不要再畫了
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : hide()
    }

    func setOpacity(_ value: Double) {
        panel.alphaValue = AppSettings.clampOpacity(value)
    }

    // MARK: - 顯示模式

    /// 切換顯示模式。選單列的分段控制與卡片右上角的箭頭都走這裡。
    ///
    /// 順序有意義：**先**把目前模式的位置存起來，再換模式、換陰影、重建畫面，
    /// **量到真實尺寸之後**才擺位置。顛倒過來會把舊位置寫進新模式的 key。
    ///
    /// 特別注意最後一步不能省成「先擺佔位尺寸，等 `onGeometryChange` 再修正」：
    /// `onGeometryChange` 只在量到的值**改變**時才觸發，而重新指派同型別的 rootView
    /// 會保留 SwiftUI 的視圖識別。若連續切換讓尺寸繞回原值，回報就不會再來一次，
    /// 面板會卡在佔位尺寸上（codex 2026-09-22 指出）。
    func setDisplayMode(_ mode: DisplayMode) {
        guard mode != displayMode else { return }

        savePosition(for: displayMode)
        displayMode = mode
        settings.displayMode = mode
        panel.hasShadow = mode.wantsWindowShadow

        rebuildRootView()
        restoreFrame(size: startingSize(for: mode))
        panel.invalidateShadow()
    }

    /// rootView 是值型別，重新指派才會讓 SwiftUI 讀到新的 mode
    private func rebuildRootView() {
        hostingView.rootView = PanelRootView(
            mode: displayMode,
            onToggleCollapsed: { [weak self] in
                guard let self else { return }
                // 卡片右上角那顆箭頭只在完整／收合之間切換，
                // 不把角色模式塞進去（M9 計畫 §4.1）
                setDisplayMode(displayMode == .collapsed ? .full : .collapsed)
            },
            onSizeChange: { [weak self] size in
                self?.setContentSize(size)
            },
            isAnimating: isAnimationActive && panel.isVisible,
            onCharacterClick: {
                // 點小精靈展開成卡片是 M9.4 的範圍。
                // M9.3 先不接行為——做一半的展開比沒有展開更讓人困惑
            },
            characterMenu: { [weak self] in self?.makeCharacterMenu() })
    }

    /// 右鍵選單（M9 計畫 §4.2）。
    /// 「展開」是 M9.4 才有的功能，這一版先不放，不放比放一個按了沒反應的好
    private func makeCharacterMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "重新整理", action: #selector(refreshFromMenu), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "切換成完整模式",
                     action: #selector(switchToFullFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "結束 FloatingAgenda",
                     action: #selector(quitFromMenu), keyEquivalent: "").target = self
        return menu
    }

    @objc private func refreshFromMenu() {
        AgendaStore.shared.refresh()
        ProjectStore.shared.refresh()
    }

    @objc private func switchToFullFromMenu() {
        setDisplayMode(.full)
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    /// 螢幕睡眠／鎖定時停掉動畫，醒來再恢復（§5.3）。
    /// 兩個原因分開記，全部解除才恢復
    private func setPaused(screensAsleep asleep: Bool? = nil,
                           sessionInactive inactive: Bool? = nil) {
        let before = isAnimationActive
        if let asleep { screensAsleep = asleep }
        if let inactive { sessionInactive = inactive }
        guard isAnimationActive != before else { return }
        rebuildRootView()
    }

    /// 切換到某個模式時要用的起始尺寸：優先用上次量到的真實值。
    ///
    /// 試過改用 `hostingView.fittingSize` 同步量測，**實測回傳 (0, 0)**——
    /// `sizingOptions = []` 把 hosting view 的內建尺寸計算關掉了，
    /// 而那個設定是必要的（否則它會跟我們的 `setFrame` 打架）。
    /// 所以改用快取：第一次進某個模式仍走靜態佔位值，但那一次尺寸一定會改變，
    /// `onGeometryChange` 必然觸發；之後每次切換都有真實值可用。
    private func startingSize(for mode: DisplayMode) -> NSSize {
        lastKnownSize[mode] ?? mode.provisionalSize
    }

    // MARK: - 尺寸同步

    /// 面板尺寸跟著內容伸縮，但**目前模式的錨點不動**。
    ///
    /// 完整／收合模式錨在左上角（寬度固定，只有高度會變）；
    /// 角色模式錨在右上角（寬高都會變）。
    private func setContentSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }

        // 先記起來再判斷要不要調整：即使這次不用動 frame，
        // 下次切回這個模式時就有真實尺寸可用
        lastKnownSize[displayMode] = size

        let frame = panel.frame
        guard abs(frame.width - size.width) > 0.5
                || abs(frame.height - size.height) > 0.5 else { return }

        let anchor = displayMode.anchor
        let target = anchor.frame(at: anchor.point(of: frame), size: size)

        isAdjustingFrame = true
        // 保持錨點不動是規則，但若那會讓面板長到畫面外就必須夾回來——
        // 實際會遇到的情境是「把收合的卡片拖到螢幕底部，再展開」
        panel.setFrame(Self.constrained(target, anchor: anchor), display: true, animate: false)
        isAdjustingFrame = false
        // 透明視窗的陰影不會自己跟著內容更新
        panel.invalidateShadow()
    }

    // MARK: - 位置記憶

    /// 執行期間拔掉外接螢幕、改顯示配置後，面板可能被留在畫面外，
    /// 只在 init 檢查一次不夠（PLAN §4.1）
    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue 指定 .main，所以這裡確定在主執行緒上
            MainActor.assumeIsolated {
                self?.recoverIfOffscreen()
            }
        }
        observePowerAndSession()
    }

    /// 螢幕睡著或使用者切換帳號／鎖定時，常駐動畫沒有理由繼續跑
    private func observePowerAndSession() {
        let center = NSWorkspace.shared.notificationCenter
        let events: [(NSNotification.Name, Bool, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true, true),
            (NSWorkspace.screensDidWakeNotification, true, false),
            (NSWorkspace.sessionDidResignActiveNotification, false, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, false, false),
        ]
        for (name, isScreens, paused) in events {
            powerObservers.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    if isScreens {
                        self?.setPaused(screensAsleep: paused)
                    } else {
                        self?.setPaused(sessionInactive: paused)
                    }
                }
            })
        }
    }

    private func recoverIfOffscreen() {
        let mode = displayMode
        let anchor = mode.anchor
        guard !Self.isUsable(frame: panel.frame) else {
            // 還看得到但可能有一部分超出邊界 → 夾回來就好，不必跳回預設位置
            let fitted = Self.constrained(panel.frame, anchor: anchor)
            if fitted != panel.frame {
                isAdjustingFrame = true
                panel.setFrame(fitted, display: true, animate: false)
                isAdjustingFrame = false
                savePosition(for: mode)
            }
            return
        }
        let size = panel.frame.size
        applyAnchor(Self.defaultAnchorPoint(for: mode, size: size), size: size, mode: mode)
        // applyAnchor 期間 windowDidMove 被 isAdjustingFrame 擋掉，位置要自己寫回去
        savePosition(for: mode)
    }

    private func restoreFrame(size: NSSize) {
        let mode = displayMode
        let target = Self.resolveAnchorPoint(for: mode,
                                             saved: savedAnchorPoint(for: mode),
                                             size: size)
        // 尺寸已經是量到的真實值，所以水平垂直都可以當場夾限。
        // （舊版在這裡用佔位高度，垂直夾限會把卡片推到錯的地方——實測存 y=200 會變成 286——
        //   所以當時只夾水平，把垂直交給 setContentSize。現在不需要那個妥協了。）
        applyAnchor(target, size: size, mode: mode)
    }

    /// 還原時要用哪個錨點：存過而且還看得到就用存的，否則回預設位置。
    ///
    /// 抽成 static 純函式是為了可測——模式切換時「舊模式存什麼、新模式還原到哪」
    /// 是最容易寫錯的地方
    static func resolveAnchorPoint(for mode: DisplayMode,
                                   saved: CGPoint?,
                                   size: NSSize) -> CGPoint {
        if let saved, isUsable(frame: mode.anchor.frame(at: saved, size: size)) {
            return saved
        }
        return defaultAnchorPoint(for: mode, size: size)
    }

    private func savedAnchorPoint(for mode: DisplayMode) -> CGPoint? {
        switch mode {
        case .full, .collapsed: settings.panelTopLeft
        case .character: settings.characterTopRight
        }
    }

    private func savePosition(for mode: DisplayMode) {
        let point = mode.anchor.point(of: panel.frame)
        switch mode {
        case .full, .collapsed: settings.panelTopLeft = point
        case .character: settings.characterTopRight = point
        }
    }

    private func applyAnchor(_ point: CGPoint, size: NSSize, mode: DisplayMode) {
        let desired = Self.constrained(mode.anchor.frame(at: point, size: size),
                                       anchor: mode.anchor)
        isAdjustingFrame = true
        panel.setFrame(desired, display: true)
        isAdjustingFrame = false
    }

    /// 存的位置還能不能用。
    ///
    /// 只檢查錨點那一個點是不夠的（2026-09-18 code review 第 3 條）：
    /// 面板尺寸會隨內容變動，錨點在畫面內、整個面板卻大半在畫面外是做得到的。
    /// 這裡要求面板與某個螢幕的可視範圍有足夠的交集，否則就回預設位置。
    ///
    /// 高度門檻取 `min(40, 面板高度)`：角色模式的面板只有 80pt 見方，
    /// 寫死 40 對它仍然成立，但若之後有更小的內容，寫死值會讓它永遠判為不可用。
    static func isUsable(frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= frame.width / 2
                && overlap.height >= min(40, frame.height)
        }
    }

    /// 夾限要以哪個螢幕為基準。
    ///
    /// 用**目前模式的錨點**選，而不是用「交集面積最大」：上下排列的雙螢幕上，
    /// 卡片變高會讓下方螢幕的交集變大，依面積選就會把原本完整在上方螢幕的卡片
    /// 整個搬到下面去（codex 2026-09-21 指出）。錨點是使用者拖曳時定位的那個角，
    /// 也是尺寸伸縮時保持不動的點，拿它當基準最穩定。
    private static func anchorScreen(for frame: NSRect, anchor: PanelAnchor) -> NSScreen? {
        // 往內縮 1pt，避免面板上緣剛好貼齊 visibleFrame.maxY 時 contains 判為 false
        let point = anchor.point(of: frame)
        let probe = CGPoint(x: anchor == .topLeft ? point.x + 1 : point.x - 1,
                            y: point.y - 1)
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(probe) }) {
            return screen
        }
        // 錨點不在任何螢幕上（例如面板大部分已在畫面外）才退回看交集
        return NSScreen.screens
            .filter { $0.visibleFrame.intersects(frame) }
            .max { $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area }
    }

    static func constrained(_ frame: NSRect, anchor: PanelAnchor) -> NSRect {
        guard let screen = anchorScreen(for: frame, anchor: anchor) else {
            return frame   // 完全不在任何螢幕上，交給 recoverIfOffscreen 處理
        }

        let visible = screen.visibleFrame
        var result = frame
        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width }
        if result.minX < visible.minX { result.origin.x = visible.minX }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }
        if result.minY < visible.minY { result.origin.y = visible.minY }
        // 比螢幕還高時貼齊上緣——寧可露出上半部，日期與最近的行程都在上面
        if result.height > visible.height { result.origin.y = visible.maxY - result.height }
        return result
    }

    /// 只夾水平方向。完整／收合模式的寬度固定 320pt，不像高度會隨內容變動，隨時夾都安全。
    private static func constrainedX(_ frame: NSRect, anchor: PanelAnchor) -> CGFloat {
        guard let screen = anchorScreen(for: frame, anchor: anchor) else { return frame.origin.x }
        let visible = screen.visibleFrame
        if frame.maxX > visible.maxX { return visible.maxX - frame.width }
        if frame.minX < visible.minX { return visible.minX }
        return frame.origin.x
    }

    /// 預設位置。
    ///
    /// 「主螢幕」取 `NSScreen.screens.first`（有選單列的主要顯示器），
    /// 不是 `NSScreen.main`——後者是「目前有鍵盤焦點的螢幕」，多螢幕時會把面板丟到副螢幕。
    ///
    /// 完整／收合模式放右上角；角色模式放**右下角**（計畫 §5.4），
    /// 這樣泡泡往左長、卡片往左上長都還在畫面內。
    static func defaultAnchorPoint(for mode: DisplayMode, size: NSSize) -> CGPoint {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else {
            return CGPoint(x: PanelMetrics.screenInset + size.width,
                           y: size.height + PanelMetrics.screenInset)
        }
        let visible = screen.visibleFrame
        let inset = PanelMetrics.screenInset
        switch mode {
        case .full, .collapsed:
            return CGPoint(x: visible.maxX - size.width - inset, y: visible.maxY - inset)
        case .character:
            return CGPoint(x: visible.maxX - inset, y: visible.minY + inset + size.height)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        savePosition(for: displayMode)
    }
}
