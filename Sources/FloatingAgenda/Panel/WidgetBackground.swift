import AppKit
import SwiftUI

/// 毛玻璃背景。圓角一律走 `NSVisualEffectView.maskImage`，
/// 不要在 SwiftUI 那層用 `.clipShape` 去裁 NSViewRepresentable（會失效或留下鋸齒）。
struct WidgetBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        // 面板永遠不會變成 key window，不設 .active 會一直是灰掉的非作用中外觀
        view.state = .active
        view.maskImage = Self.makeMaskImage(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        if view.maskImage?.size.width != Self.tileEdge(for: cornerRadius) {
            view.maskImage = Self.makeMaskImage(cornerRadius: cornerRadius)
        }
    }

    /// continuous 圓角的曲線會延伸到半徑之外，cap 取 2× 半徑才不會被拉伸破壞形狀
    private static func capInset(for cornerRadius: CGFloat) -> CGFloat { cornerRadius * 2 }
    private static func tileEdge(for cornerRadius: CGFloat) -> CGFloat { capInset(for: cornerRadius) * 2 + 1 }

    private static func makeMaskImage(cornerRadius: CGFloat) -> NSImage {
        let inset = capInset(for: cornerRadius)
        let edge = tileEdge(for: cornerRadius)
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            let path = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
            NSColor.black.setFill()
            NSBezierPath(cgPath: path.cgPath).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        image.resizingMode = .stretch
        return image
    }
}
