import AppKit

/// 建立 PanelController 並依設定決定要不要顯示面板。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PanelController()
        panelController = controller
        controller.setVisible(AppSettings.shared.panelVisible)

        // 權限請求與第一次讀取；之後由 AgendaStore 自己監聽變更
        Task { await AgendaStore.shared.start() }
    }
}
