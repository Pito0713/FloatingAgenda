import AppKit
import SwiftUI

/// 懸浮面板本體。浮在一般視窗上、不搶焦點、不出現在 Dock（LSUIElement）。
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        // App 是 accessory，不設這個切走就會整張消失
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        // 刻意不設 .canJoinAllSpaces：使用者沒有選「每個桌面空間都顯示」
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 沒有這個，面板在非作用中時第一下點擊會被系統吃掉，勾選要點兩次。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未支援")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
