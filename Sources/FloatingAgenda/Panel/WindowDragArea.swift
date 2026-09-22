import AppKit
import SwiftUI

/// 拖曳移動面板。
/// 用 `performDrag` 而不是 `isMovableByWindowBackground`——後者會跟按鈕搶點擊。
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
