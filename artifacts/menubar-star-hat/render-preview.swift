import AppKit

enum Mood: CaseIterable { case happy, busy, worried, sleepy }

@main struct Preview {
    @MainActor static func main() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720, pixelsHigh: 260,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for row in 0..<2 {
            (row == 0 ? NSColor.white : NSColor(white: 0.15, alpha: 1)).setFill()
            NSRect(x: 0, y: row * 130, width: 720, height: 130).fill()
            for (column, mood) in Mood.allCases.enumerated() {
                let image = MenuBarIcon.image(mood: mood).copy() as! NSImage
                image.isTemplate = false
                let tint = NSImage(size: image.size, flipped: false) { rect in
                    image.draw(in: rect)
                    (row == 0 ? NSColor.black : NSColor.white).setFill()
                    rect.fill(using: .sourceIn)
                    return true
                }
                tint.draw(in: NSRect(x: column * 180 + 30, y: row * 130 + 28, width: 72, height: 72))
                tint.draw(in: NSRect(x: column * 180 + 125, y: row * 130 + 50, width: 18, height: 18))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "artifacts/menubar-star-hat/preview.png"))
        for row in MenuBarIcon.mask(mood: .happy) { print(row.map { $0 ? "#" : "." }.joined()) }
    }
}
