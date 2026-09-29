import AppKit

/// 07 垂星巫師帽：簡化的實心帽身與星飾，由系統套用選單列前景色。
@MainActor
enum MenuBarIcon {
    static let canvasSide = 18
    static let dotSide = 4

    enum Dot { case filled, hollow }

    static func dot(for mood: Mood) -> Dot? {
        switch mood {
        case .worried: .filled
        case .busy: .hollow
        case .happy, .sleepy: nil
        }
    }

    static func dotMask(_ dot: Dot) -> [[Bool]] {
        let rows = dot == .filled
            ? [".##.", "####", "####", ".##."]
            : [".##.", "#..#", "#..#", ".##."]
        return rows.map { $0.map { $0 == "#" } }
    }

    /// 07 垂星巫師帽：實心帽身與寬帽緣，帽尖懸掛一顆大星星。
    private static func outline() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3.1, y: 13.5))
        path.curve(to: NSPoint(x: 11.7, y: 1.2), controlPoint1: NSPoint(x: 3.3, y: 6.3),
                   controlPoint2: NSPoint(x: 6.9, y: 0.5))
        path.curve(to: NSPoint(x: 14.6, y: 3.8), controlPoint1: NSPoint(x: 13.4, y: 1.2),
                   controlPoint2: NSPoint(x: 14.6, y: 2.3))
        path.curve(to: NSPoint(x: 13.4, y: 4.1), controlPoint1: NSPoint(x: 14.7, y: 4.5),
                   controlPoint2: NSPoint(x: 13.7, y: 4.6))
        path.curve(to: NSPoint(x: 10.5, y: 4.1), controlPoint1: NSPoint(x: 12.8, y: 2.8),
                   controlPoint2: NSPoint(x: 11.7, y: 3.1))
        path.curve(to: NSPoint(x: 11.8, y: 13.5), controlPoint1: NSPoint(x: 8.6, y: 6.5),
                   controlPoint2: NSPoint(x: 10.2, y: 11.6))
        path.curve(to: NSPoint(x: 13.3, y: 15.2), controlPoint1: NSPoint(x: 13.3, y: 14),
                   controlPoint2: NSPoint(x: 13.5, y: 14.7))
        path.curve(to: NSPoint(x: 0.8, y: 15.2), controlPoint1: NSPoint(x: 11.5, y: 17.2),
                   controlPoint2: NSPoint(x: 2.3, y: 17.1))
        path.curve(to: NSPoint(x: 3.1, y: 13.5), controlPoint1: NSPoint(x: -0.2, y: 14.6),
                   controlPoint2: NSPoint(x: 1.5, y: 13.9))
        path.close()
        return path
    }

    private static func drawCharacter() {
        NSColor.black.setFill()
        outline().fill()
        // 五角星使用足夠寬的內半徑，縮小時不會只剩細線。
        let star = NSBezierPath()
        for index in 0..<10 {
            let angle = Double(index) * .pi / 5 - .pi / 2
            let radius = index.isMultiple(of: 2) ? 2.8 : 1.4
            let point = NSPoint(x: 14.3 + cos(angle) * radius,
                                y: 7.5 + sin(angle) * radius)
            if index == 0 { star.move(to: point) } else { star.line(to: point) }
        }
        star.close()
        star.fill()
        NSBezierPath(roundedRect: NSRect(x: 13.8, y: 3.8, width: 1, height: 1.8),
                     xRadius: 0.5, yRadius: 0.5).fill()
    }

    static func image(mood: Mood) -> NSImage {
        if let cached = cache[mood] { return cached }
        let image = NSImage(size: NSSize(width: canvasSide, height: canvasSide), flipped: true) { _ in
            NSGraphicsContext.current?.shouldAntialias = true
            drawCharacter()
            if let dot = dot(for: mood) {
                NSColor.black.setFill()
                NSColor.black.setStroke()
                let circle = NSBezierPath(ovalIn: NSRect(x: 14.5, y: 14.5, width: 3, height: 3))
                circle.lineWidth = 1
                if dot == .filled { circle.fill() } else { circle.stroke() }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "懸浮行程：垂星巫師帽"
        cache[mood] = image
        return image
    }

    /// 保留開發預覽的 18×18 遮罩介面；正式 icon 使用上方向量 renderer。
    static func mask(mood: Mood) -> [[Bool]] {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvasSide,
            pixelsHigh: canvasSide, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image(mood: mood).draw(in: NSRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
        NSGraphicsContext.restoreGraphicsState()
        return (0..<canvasSide).map { y in
            (0..<canvasSide).map { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
        }
    }

    static func silhouette(mood: Mood) -> [[Bool]]? { mask(mood: .happy) }
    private static var cache: [Mood: NSImage] = [:]
}
