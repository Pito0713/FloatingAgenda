import AppKit
import Combine
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
    /// 角色模式展開後整張卡片的高度上限（M9 計畫 §4.5）
    static let expandedMaxHeight: CGFloat = 620
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
    /// 要用哪個皮膚畫小精靈（M9 計畫 §4.6）
    var skin: Skin = CharacterAnimation.builtinSkin
    /// 角色模式的動畫要不要跑。面板隱藏、螢幕睡眠或鎖定時傳 false（M9 計畫 §5.3）
    var isAnimating = true
    /// 角色模式是不是展開成卡片了。**暫時狀態，不存**（§4.5）
    var isExpanded = false
    var onToggleExpanded: () -> Void = {}
    var characterMenu: () -> NSMenu? = { nil }
    private let store = AgendaStore.shared
    private let projects = ProjectStore.shared
    private let settings = AppSettings.shared

    /// 輪播用。滑鼠停在泡泡上時暫停（§4.2）
    @State private var rotation = BubbleRotation()
    @State private var isHoveringBubble = false

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
            if isExpanded { expandedCard } else { idleCharacter }
        }
    }

    /// 專案區只在**角色模式展開時**出現。完整與收合模式一律不顯示（M9 計畫 §4.5）。
    ///
    /// 抽成 static 純函式並讓兩個分支共用同一個來源，是為了讓這條規則可以被測試釘住——
    /// 分散在兩個分支裡寫的話，「完整模式不小心也傳了專案區」這種錯誤
    /// 單元測試與 snapshot 都抓不到（`--snapshot` 直接渲染 `WidgetView`，
    /// 根本不經過 `PanelRootView`）
    static func showsProjects(mode: DisplayMode, expanded: Bool) -> Bool {
        mode == .character && expanded
    }

    private var visibleProjectsState: SectionState<ProjectItem>? {
        Self.showsProjects(mode: mode, expanded: isExpanded) ? projects.state : nil
    }

    private var mood: Mood {
        Mood.decide(reminders: store.remindersState, projects: projects.state, now: Date())
    }

    // MARK: - 完整／收合模式（M9 之前就有的畫面，一個字都不能動）

    private var widget: some View {
        WidgetView(eventsState: store.eventsState,
                   remindersState: store.remindersState,
                   pendingReminderIDs: store.pendingCompletion,
                   reminderError: store.completionError,
                   background: .blur,
                   isCollapsed: mode == .collapsed,
                   onToggleCollapsed: onToggleCollapsed,
                   projectsState: visibleProjectsState,
                   onOpenEvent: { store.openInCalendar($0) },
                   onToggleReminder: { store.toggleCompletion($0) },
                   onOpenReminder: { store.openInReminders($0) },
                   onOpenCalendarSettings: { store.openPrivacySettings(for: .event) },
                   onOpenReminderSettings: { store.openPrivacySettings(for: .reminder) })
            .frame(width: PanelMetrics.width)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 角色模式：待機

    /// 泡泡在小精靈**左邊**、垂直置中（§4.2）。
    /// 沒有泡泡時，面板大小就等於小精靈的大小——點擊穿透靠的就是這件事（§5.4）
    private var idleCharacter: some View {
        HStack(alignment: .center, spacing: 6) {
            if settings.showBubble, let line = rotation.current {
                BubbleView(text: line.text) { isHoveringBubble = $0 }
                    // 點泡泡的效果跟點小精靈一樣（§4.2）
                    .onTapGesture(perform: onToggleExpanded)
                    .transition(.opacity)
                    .id(line.id)
            }
            characterSprite
        }
        // **一定要 fixedSize**：沒有它，這一塊會撐滿被提議的寬度
        // （例如剛從展開的卡片收回來時是 320pt），面板就會比看得到的內容大一圈，
        // 旁邊多出一片看不見卻擋住桌面的區域——那正是 §5.4 的點擊穿透要避免的
        .fixedSize()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: rotation.current?.id)
        .onAppear { rebuildLines() }
        .onChange(of: store.remindersState) { rebuildLines() }
        .onChange(of: projects.state) { rebuildLines() }
        // 每則顯示 8 秒。滑鼠停在泡泡上時暫停（§4.2、§4.4）。
        //
        // 計時器只在**真的看得到泡泡**時才建立：關掉「顯示對話泡泡」、
        // 面板隱藏、螢幕睡眠時都不該有東西在跳（codex 2026-09-22 指出
        // 原本的訂閱不受這些條件控制）
        .onReceive(bubbleTimer) { _ in
            guard !isHoveringBubble else { return }
            rotation.advance()
        }
    }

    private var characterSprite: some View {
        CharacterLiveView(mood: mood,
                          skin: skin,
                          isAnimating: isAnimating,
                          onClick: onToggleExpanded,
                          menu: characterMenu)
            .frame(width: PanelMetrics.characterSize + PanelMetrics.characterPadding * 2,
                   height: PanelMetrics.characterSize + PanelMetrics.characterPadding * 2)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 看不到泡泡時給一個永遠不發訊號的 publisher，等於沒有計時器
    private var bubbleTimer: AnyPublisher<Date, Never> {
        guard settings.showBubble, isAnimating else {
            return Empty<Date, Never>(completeImmediately: false).eraseToAnyPublisher()
        }
        return Timer.publish(every: BubbleRotation.interval, on: .main, in: .common)
            .autoconnect()
            .eraseToAnyPublisher()
    }

    private func rebuildLines() {
        rotation.update(lines: BubbleComposer.lines(reminders: store.remindersState,
                                                    projects: projects.state,
                                                    now: Date()))
    }

    // MARK: - 角色模式：展開

    /// 展開的卡片 ＝ 完整卡片 ＋ 專案區（§4.5）。
    /// 所有既有互動都跟完整模式一樣，只是多了標題列的小精靈與下方的專案區
    private var expandedCard: some View {
        WidgetView(eventsState: store.eventsState,
                   remindersState: store.remindersState,
                   pendingReminderIDs: store.pendingCompletion,
                   reminderError: store.completionError,
                   background: .blur,
                   projectsState: visibleProjectsState,
                   characterMood: mood,
                   characterSkin: skin,
                   onCollapseToCharacter: onToggleExpanded,
                   showsCollapseButton: false,
                   onOpenProject: { NSWorkspace.shared.open($0.fileURL) },
                   onOpenEvent: { store.openInCalendar($0) },
                   onToggleReminder: { store.toggleCompletion($0) },
                   onOpenReminder: { store.openInReminders($0) },
                   onOpenCalendarSettings: { store.openPrivacySettings(for: .event) },
                   onOpenReminderSettings: { store.openPrivacySettings(for: .reminder) })
            .frame(width: PanelMetrics.width)
            // 高度上限由 WidgetView 內部的專案區自己吸收（§4.5），
            // 這裡照常取理想高度
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
    @ObservationIgnored private var escapeMonitor: Any?
    /// 每個模式上次量到的真實內容尺寸。
    ///
    /// 切換模式時拿它當初始尺寸，**不要**先擺一個佔位尺寸再指望
    /// `onGeometryChange` 修正：那個回報只在量到的值**改變**時才觸發，
    /// 而重新指派同型別的 rootView 會保留 SwiftUI 的視圖識別。
    /// 若連續切換讓尺寸繞回原值，回報就不會再來一次，面板會卡在佔位尺寸上
    /// （codex 2026-09-22 指出）。
    @ObservationIgnored private var lastKnownSize: [SizeKey: NSSize] = [:]

    /// 角色模式有兩種尺寸（小精靈與展開的卡片），所以快取的 key 要同時帶上展開狀態
    private struct SizeKey: Hashable {
        let mode: DisplayMode
        let expanded: Bool
    }

    private var currentSizeKey: SizeKey {
        SizeKey(mode: displayMode, expanded: isCharacterExpanded)
    }
    /// 角色模式是不是展開成卡片了。
    ///
    /// **暫時狀態，刻意不存**（M9 計畫 §4.5）：重開 App 一律從小精靈開始。
    /// `@Observable` 追蹤它，選單列與右鍵選單才會跟著顯示「展開」或「收回」
    private(set) var isCharacterExpanded = false
    /// 展開前小精靈的右上角。
    ///
    /// 展開時若卡片會超出螢幕下緣，`constrained` 會把它往上推——
    /// 收回時若直接用「被推上去之後」的右上角，小精靈就回不到原位，
    /// 而且下次切換模式還會把這個位移過的位置存起來，等於小精靈會一路往上爬
    /// （codex 2026-09-22 指出）
    @ObservationIgnored private var anchorBeforeExpand: CGPoint?

    /// 目前可用的皮膚（內建 ＋ 掃描到的外部皮膚）與被拒絕的清單。
    /// 只在**啟動時**與**打開角色選單時**重新掃描，不監聽資料夾（§4.6）
    @ObservationIgnored private var skinGeneration = 0
    private(set) var availableSkins: [Skin] = []
    private(set) var rejectedSkins: [SkinRejection] = []

    /// 目前生效的皮膚。選的那個不見了就退回內建角色
    var activeSkin: Skin {
        availableSkins.first { $0.id == settings.characterSkinID }
            ?? CharacterAnimation.builtinSkin
    }

    /// 重新掃描皮膚資料夾。啟動時與打開角色選單時呼叫
    func reloadSkins() {
        skinGeneration += 1
        let generation = skinGeneration
        let directory = SkinLoader.defaultDirectory()
        // 掃描要讀 JSON、解 PNG、建 CGImage，皮膚多或磁碟慢時會拖住主執行緒，
        // 連常駐動畫一起卡住（codex 2026-09-22 指出）。丟到背景，結果再切回來
        Task.detached(priority: .utility) {
            let result = SkinLoader.scan(directory: directory)
            await MainActor.run { [weak self] in
                guard let self, self.skinGeneration == generation else { return }
                self.availableSkins = [CharacterAnimation.builtinSkin] + result.skins
                self.rejectedSkins = result.rejected
                self.rebuildRootView()
            }
        }
    }

    /// 選一個皮膚
    func selectSkin(_ id: String) {
        guard settings.characterSkinID != id else { return }
        settings.characterSkinID = id
        rebuildRootView()
    }

    /// 打開皮膚資料夾。**不存在就先建立**——這是整個專案唯一會建立目錄的地方，
    /// 而且只在使用者主動按下這一項時才會發生（§8 明文允許）
    func openSkinsFolder() {
        let directory = SkinLoader.defaultDirectory()
        SkinLoader.ensureDirectoryExists(directory)
        NSWorkspace.shared.open(directory)
    }
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
        restoreFrame(size: startingSize(mode: mode, expanded: false))
        availableSkins = [CharacterAnimation.builtinSkin]
        reloadSkins()
        observeScreenChanges()
        observeEscape()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        // 電源與工作階段的通知註冊在 NSWorkspace 自己的 center，
        // 拿去 NotificationCenter.default 移除是無效操作（M2 踩過同一個坑）
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        powerObservers.forEach { workspaceCenter.removeObserver($0) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
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
        // 離開角色模式時把展開狀態收掉，下次回來才會從小精靈開始（§4.5）
        isCharacterExpanded = false
        anchorBeforeExpand = nil
        panel.hasShadow = mode.wantsWindowShadow

        rebuildRootView()
        restoreFrame(size: startingSize(mode: mode, expanded: false))
        panel.invalidateShadow()
    }

    /// rootView 是值型別，重新指派才會讓 SwiftUI 讀到新的 mode
    private func rebuildRootView() {
        let key = currentSizeKey
        hostingView.rootView = PanelRootView(
            mode: displayMode,
            onToggleCollapsed: { [weak self] in
                guard let self else { return }
                // 卡片右上角那顆箭頭只在完整／收合之間切換，
                // 不把角色模式塞進去（M9 計畫 §4.1）
                setDisplayMode(displayMode == .collapsed ? .full : .collapsed)
            },
            onSizeChange: { [weak self] size in
                // 帶上這個 rootView 是為哪個狀態建的：切換狀態時，
                // 舊內容的最後一次回報可能晚一步才到，不擋掉會被算到新狀態的快取上
                self?.setContentSize(size, from: key)
            },
            skin: activeSkin,
            isAnimating: isAnimationActive && panel.isVisible,
            isExpanded: isCharacterExpanded,
            onToggleExpanded: { [weak self] in self?.toggleCharacterExpanded() },
            characterMenu: { [weak self] in self?.makeCharacterMenu() })
    }

    /// 右鍵選單（M9 計畫 §4.2）
    private func makeCharacterMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: isCharacterExpanded ? "收回" : "展開",
                     action: #selector(toggleExpandedFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "重新整理", action: #selector(refreshFromMenu), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "切換成完整模式",
                     action: #selector(switchToFullFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "結束 FloatingAgenda",
                     action: #selector(quitFromMenu), keyEquivalent: "").target = self
        return menu
    }

    @objc private func toggleExpandedFromMenu() {
        toggleCharacterExpanded()
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

    /// 設定改了（例如「顯示對話泡泡」）之後讓面板重畫。
    /// rootView 是值型別，重新指派才會讓 SwiftUI 重新求值
    func reloadPanelContent() {
        rebuildRootView()
    }

    /// 點小精靈或泡泡展開成卡片，再點標題列的小精靈或按 Esc 收回（§4.5）。
    ///
    /// 錨點不變（角色模式一律右上角），所以卡片會往**左下**長，小精靈原本的位置不動。
    /// 真實尺寸稍後由 onSizeChange 補正；若卡片會超出螢幕下緣，
    /// `constrained` 會把它往上推（§5.4），而**存起來的小精靈位置不受影響**——
    /// `savePosition` 只在切換顯示模式與使用者拖曳時才呼叫
    func toggleCharacterExpanded() {
        guard displayMode == .character else { return }
        if isCharacterExpanded {
            // 收回：回到展開前的位置，不要用被螢幕邊界推上去之後的位置
            isCharacterExpanded = false
            panel.hasShadow = false
            rebuildRootView()
            let size = startingSize(mode: displayMode, expanded: false)
            if let anchor = anchorBeforeExpand {
                applyAnchor(anchor, size: size, mode: displayMode)
                anchorBeforeExpand = nil
            } else {
                setContentSize(size)
            }
            panel.invalidateShadow()
            return
        }

        anchorBeforeExpand = displayMode.anchor.point(of: panel.frame)
        isCharacterExpanded = true
        // 展開的卡片要有毛玻璃與陰影，收回小精靈時再拿掉
        panel.hasShadow = true
        rebuildRootView()
        // 立刻套上目標尺寸，不要停在舊尺寸等 onGeometryChange 來救——
        // 那個回報只在值**改變**時才觸發（M9.2 踩過同一個坑）。
        // 用 setContentSize 而不是 restoreFrame：展開要以**目前**的右上角為錨點，
        // 不是跳回存起來的位置
        setContentSize(startingSize(mode: displayMode, expanded: isCharacterExpanded))
        panel.invalidateShadow()
    }

    /// Esc 收回小精靈（§4.5）。
    ///
    /// ⚠️ **實測在一般情況下不會生效**，這是刻意接受的限制：
    /// 面板是 `.nonactivatingPanel` 且 `canBecomeKey = false`，點它不會讓 App 變成作用中
    /// （實測 `NSApp.isActive == false`、`keyWindow == nil`），
    /// 所以 local monitor 收不到鍵盤事件。
    ///
    /// 要讓它可靠運作只有兩條路，兩條都不划算：
    /// 讓面板可以成為 key window（等於點一下小精靈就搶走使用者當前 App 的焦點，
    /// 與整個懸浮視窗的設計前提相反），或改用 global monitor
    /// （需要輔助使用權限，而且會攔截整個系統的 Esc）。
    ///
    /// 保留這段是因為它在 App 剛好是作用中時仍然有效（例如剛開過選單列）；
    /// 可靠的收回入口是**標題列的小精靈**與**右鍵選單的「收回」**，兩者都不需要焦點。
    /// UI 上已經不再宣傳 Esc（codex 2026-09-22 指出，實測確認）
    private func observeEscape() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }   // 53 = Esc
            guard displayMode == .character, isCharacterExpanded else { return event }
            toggleCharacterExpanded()
            return nil
        }
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
    private func startingSize(mode: DisplayMode, expanded: Bool) -> NSSize {
        lastKnownSize[SizeKey(mode: mode, expanded: expanded)]
            ?? (expanded ? DisplayMode.full.provisionalSize : mode.provisionalSize)
    }

    // MARK: - 尺寸同步

    /// 面板尺寸跟著內容伸縮，但**目前模式的錨點不動**。
    ///
    /// 完整／收合模式錨在左上角（寬度固定，只有高度會變）；
    /// 角色模式錨在右上角（寬高都會變）。
    private func setContentSize(_ size: CGSize, from key: SizeKey? = nil) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        // 過期的回報（來自已經被換掉的 rootView）一律丟掉
        if let key, key != currentSizeKey { return }

        // 先記起來再判斷要不要調整：即使這次不用動 frame，
        // 下次切回這個狀態時就有真實尺寸可用
        lastKnownSize[currentSizeKey] = size

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
