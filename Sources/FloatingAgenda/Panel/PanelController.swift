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
}

/// 面板的根視圖：固定寬度、高度由內容決定，並把量到的高度回報給 PanelController。
struct PanelRootView: View {
    let onHeightChange: (CGFloat) -> Void
    private let store = AgendaStore.shared
    private let settings = AppSettings.shared
    /// 只用來觸發重繪；收合狀態一律直接讀 settings，不保留鏡像
    /// （與 M5 修正 MenuBarView 時採用的同一個模式）
    @State private var revision = 0

    var body: some View {
        // 讀取 revision 建立重繪依賴。**不要用 `.id(revision)`**——那會把整個子樹
        // 連同內部狀態一起丟棄重建，實際後果是點「展開」後 WidgetView 的
        // isHoveringCard 被重設，游標還在卡片上但收合箭頭卻消失（2026-09-18 code review）
        let _ = revision
        return WidgetView(eventsState: store.eventsState,
                   remindersState: store.remindersState,
                   pendingReminderIDs: store.pendingCompletion,
                   reminderError: store.completionError,
                   background: .blur,
                   isCollapsed: settings.panelCollapsed,
                   onToggleCollapsed: {
                       settings.panelCollapsed.toggle()
                       revision += 1
                   },
                   onOpenEvent: { store.openInCalendar($0) },
                   onToggleReminder: { store.toggleCompletion($0) },
                   onOpenReminder: { store.openInReminders($0) },
                   onOpenCalendarSettings: { store.openPrivacySettings(for: .event) },
                   onOpenReminderSettings: { store.openPrivacySettings(for: .reminder) })
            .frame(width: PanelMetrics.width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                onHeightChange(height)
            }
    }
}

/// 顯示／隱藏、高度同步、位置記憶、透明度。
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let panel: FloatingPanel
    private let hostingView: FirstMouseHostingView<PanelRootView>
    /// 程式自己調整 frame 時不要把位置寫回設定（避免高度同步被當成使用者拖曳）
    private var isAdjustingFrame = false
    private var screenObserver: NSObjectProtocol?

    /// settings 預設值不能直接寫 `.shared`：預設引數在 nonisolated 情境求值，
    /// Swift 6 語言模式會直接變成錯誤
    init(settings: AppSettings? = nil) {
        self.settings = settings ?? .shared
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0,
                                                  width: PanelMetrics.width,
                                                  height: PanelMetrics.initialHeight))
        hostingView = FirstMouseHostingView(rootView: PanelRootView(onHeightChange: { _ in }))
        super.init()

        hostingView.rootView = PanelRootView(onHeightChange: { [weak self] height in
            self?.setContentHeight(height)
        })
        // 不設成 [] 的話，hosting view 自己的尺寸約束會跟我們的 setFrame 打架
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.delegate = self
        panel.alphaValue = self.settings.opacity
        restoreFrame()
        observeScreenChanges()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    var isVisible: Bool { panel.isVisible }

    /// 用 orderFrontRegardless：面板不搶焦點，也不能讓 App 被啟動起來
    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : hide()
    }

    func setOpacity(_ value: Double) {
        panel.alphaValue = AppSettings.clampOpacity(value)
    }

    /// 高度跟著內容伸縮，但**上緣位置不動**
    private func setContentHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }

        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height

        isAdjustingFrame = true
        // 保持上緣不動是 PLAN §4.1 的規則，但若那會讓卡片長到畫面外就必須夾回來——
        // 實際會遇到的情境是「把收合的卡片拖到螢幕底部，再展開」
        panel.setFrame(Self.constrained(frame), display: true, animate: false)
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
    }

    private func recoverIfOffscreen() {
        let size = NSSize(width: PanelMetrics.width, height: panel.frame.height)
        let topLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        guard !Self.isUsable(topLeft: topLeft, size: size) else {
            // 還看得到但可能有一部分超出邊界 → 夾回來就好，不必跳回預設位置
            let fitted = Self.constrained(panel.frame)
            if fitted != panel.frame {
                isAdjustingFrame = true
                panel.setFrame(fitted, display: true, animate: false)
                isAdjustingFrame = false
                settings.panelTopLeft = CGPoint(x: fitted.minX, y: fitted.maxY)
            }
            return
        }
        let target = Self.defaultTopLeft(size: size)
        applyTopLeft(target, size: size)
        // applyTopLeft 期間 windowDidMove 被 isAdjustingFrame 擋掉，位置要自己寫回去
        settings.panelTopLeft = target
    }

    private func restoreFrame() {
        let size = NSSize(width: PanelMetrics.width, height: panel.frame.height)
        if let saved = settings.panelTopLeft, Self.isUsable(topLeft: saved, size: size) {
            applyTopLeft(saved, size: size)
        } else {
            applyTopLeft(Self.defaultTopLeft(size: size), size: size)
        }
    }

    /// 存的位置還能不能用。
    ///
    /// 只檢查左上角那一個點是不夠的（2026-09-18 code review 第 3 條）：
    /// 卡片高度會隨內容變動，左上角在畫面內、整張卡片卻大半在畫面外是做得到的。
    /// 這裡要求卡片與某個螢幕的可視範圍有足夠的交集，否則就回預設位置。
    private static func isUsable(topLeft: CGPoint, size: NSSize) -> Bool {
        let frame = NSRect(x: topLeft.x, y: topLeft.y - size.height,
                           width: size.width, height: size.height)
        return NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            // 至少要露出卡片寬度的一半、以及上緣附近的一小段高度，
            // 否則使用者等於看不到也抓不到它
            return overlap.width >= size.width / 2 && overlap.height >= 40
        }
    }

    /// 把 frame 夾回某個螢幕的可視範圍內。
    ///
    /// 選「交集面積最大」的那個螢幕當基準，多螢幕時才不會跳到奇怪的地方。
    /// 卡片比螢幕還高時貼齊上緣——寧可露出上半部，因為日期與最近的行程在上面。
    /// 夾限要以哪個螢幕為基準。
    ///
    /// 用**左上角**選，而不是用「交集面積最大」：上下排列的雙螢幕上，卡片變高會讓
    /// 下方螢幕的交集變大，依面積選就會把原本完整在上方螢幕的卡片整個搬到下面去
    /// （codex 2026-09-21 指出）。左上角是使用者拖曳時定位的那個角，也是高度伸縮時
    /// 保持不動的錨點，拿它當基準最穩定。
    private static func anchorScreen(for frame: NSRect) -> NSScreen? {
        // 往內縮 1pt，避免卡片上緣剛好貼齊 visibleFrame.maxY 時 contains 判為 false
        let anchor = CGPoint(x: frame.minX + 1, y: frame.maxY - 1)
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(anchor) }) {
            return screen
        }
        // 左上角不在任何螢幕上（例如卡片大部分已在畫面外）才退回看交集
        return NSScreen.screens
            .filter { $0.visibleFrame.intersects(frame) }
            .max { $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area }
    }

    private static func constrained(_ frame: NSRect) -> NSRect {
        guard let screen = anchorScreen(for: frame) else {
            return frame   // 完全不在任何螢幕上，交給 recoverIfOffscreen 處理
        }

        let visible = screen.visibleFrame
        var result = frame
        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width }
        if result.minX < visible.minX { result.origin.x = visible.minX }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }
        if result.minY < visible.minY { result.origin.y = visible.minY }
        if result.height > visible.height { result.origin.y = visible.maxY - result.height }
        return result
    }

    /// 預設位置：主螢幕右上角，往內留 20pt。
    /// 「主螢幕」取 `NSScreen.screens.first`（有選單列的主要顯示器），
    /// 不是 `NSScreen.main`——後者是「目前有鍵盤焦點的螢幕」，多螢幕時會把卡片丟到副螢幕。
    private static func defaultTopLeft(size: NSSize) -> CGPoint {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else {
            return CGPoint(x: PanelMetrics.screenInset, y: size.height + PanelMetrics.screenInset)
        }
        let visible = screen.visibleFrame
        return CGPoint(x: visible.maxX - size.width - PanelMetrics.screenInset,
                       y: visible.maxY - PanelMetrics.screenInset)
    }

    private func applyTopLeft(_ topLeft: CGPoint, size: NSSize) {
        // 這裡**刻意不做垂直夾限**：還原位置時高度還是 PanelMetrics.initialHeight 的佔位值，
        // 依它夾限會把卡片推到錯的地方（實測存 y=200 會變成 286）。
        // 垂直方向交給 setContentHeight 在真實高度出來之後處理。
        var desired = NSRect(x: topLeft.x, y: topLeft.y - size.height,
                             width: size.width, height: size.height)
        desired.origin.x = Self.constrainedX(desired)
        isAdjustingFrame = true
        panel.setFrame(desired, display: false)
        isAdjustingFrame = false
    }

    /// 只夾水平方向。寬度是固定的 320pt，不像高度會隨內容變動，隨時夾都安全。
    private static func constrainedX(_ frame: NSRect) -> CGFloat {
        guard let screen = anchorScreen(for: frame) else { return frame.origin.x }
        let visible = screen.visibleFrame
        if frame.maxX > visible.maxX { return visible.maxX - frame.width }
        if frame.minX < visible.minX { return visible.minX }
        return frame.origin.x
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isAdjustingFrame else { return }
        settings.panelTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }
}
