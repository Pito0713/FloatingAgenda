import AppKit
import SwiftUI

/// `--snapshot <前綴>`：用 mock 資料輸出 `<前綴>-light.png` 與 `<前綴>-dark.png`（scale 2）。
/// ImageRenderer 畫不出 NSVisualEffectView，所以背景改用不透明底色（PLAN §5.7）。
@MainActor
enum DevSnapshot {
    static func run(outputPrefix: String?) async -> Int32 {
        guard let outputPrefix, !outputPrefix.isEmpty else {
            fail("--snapshot 需要輸出路徑前綴，例如：--snapshot /tmp/fa")
            return 2
        }

        // ImageRenderer 底下的 AppKit 繪圖需要 NSApplication 實例存在（不需要 run）
        _ = NSApplication.shared

        let prefix = (outputPrefix as NSString).expandingTildeInPath
        let cases: [(suffix: String, scheme: ColorScheme, appearance: NSAppearance.Name)] = [
            ("light", .light, .aqua),
            ("dark", .dark, .darkAqua),
        ]

        for item in cases {
            guard let appearance = NSAppearance(named: item.appearance) else {
                fail("找不到外觀：\(item.appearance.rawValue)")
                return 1
            }

            let events = MockData.events()
            let reminders = MockData.reminders()

            // 收合模式變體（PLAN §4.10）
            for variant in MockData.collapsedVariants() {
                let card = WidgetView(eventsState: variant.events,
                                      remindersState: variant.reminders,
                                      background: .opaque,
                                      now: MockData.referenceDate(),
                                      isCollapsed: true)
                    .frame(width: PanelMetrics.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.colorScheme, item.scheme)

                var collapsedImage: CGImage?
                appearance.performAsCurrentDrawingAppearance {
                    let renderer = ImageRenderer(content: card)
                    renderer.scale = 2
                    collapsedImage = renderer.cgImage
                }
                guard let collapsedCG = collapsedImage else {
                    fail("ImageRenderer 產不出 \(variant.name) \(item.suffix) 圖")
                    return 1
                }
                let collapsedPath = "\(prefix)-\(variant.name)-\(item.suffix).png"
                guard writePNG(collapsedCG, scale: 2, to: collapsedPath) else { return 1 }
                print("✅ \(collapsedPath)  \(collapsedCG.width)×\(collapsedCG.height)px")
            }

            // 異常狀態變體（PLAN §4.6）：沒有這些圖，權限與失敗畫面就只能靠讀程式碼
            for variant in MockData.stateVariants(reminders: reminders) {
                let card = WidgetView(eventsState: variant.events,
                                      remindersState: variant.reminders,
                                      reminderError: variant.reminderError,
                                      background: .opaque,
                                      now: MockData.referenceDate())
                    .frame(width: PanelMetrics.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.colorScheme, item.scheme)

                var variantImage: CGImage?
                appearance.performAsCurrentDrawingAppearance {
                    let renderer = ImageRenderer(content: card)
                    renderer.scale = 2
                    variantImage = renderer.cgImage
                }
                guard let variantCG = variantImage else {
                    fail("ImageRenderer 產不出 \(variant.name) \(item.suffix) 圖")
                    return 1
                }
                let variantPath = "\(prefix)-\(variant.name)-\(item.suffix).png"
                guard writePNG(variantCG, scale: 2, to: variantPath) else { return 1 }
                print("✅ \(variantPath)  \(variantCG.width)×\(variantCG.height)px")
            }

            // 刻意讓一筆處於「勾選中」狀態，驗證圓圈填滿＋刪除線的樣子。
            // onToggle / onOpen 不傳 → 用預設的空實作，snapshot 不可能寫入任何資料
            let content = WidgetView(eventsState: .loaded(items: events, total: events.count),
                                     remindersState: .loaded(items: reminders, total: reminders.count),
                                     pendingReminderIDs: MockData.pendingReminderIDs,
                                     background: .opaque,
                                     now: MockData.referenceDate())
                .frame(width: PanelMetrics.width)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.colorScheme, item.scheme)

            var image: CGImage?
            // Color(nsColor:) 這類 AppKit 衍生色是看 NSAppearance.current 決定的，
            // 光設 SwiftUI 的 colorScheme 不夠，兩邊都要設
            appearance.performAsCurrentDrawingAppearance {
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                image = renderer.cgImage
            }

            guard let cgImage = image else {
                fail("ImageRenderer 產不出 \(item.suffix) 圖")
                return 1
            }

            let path = "\(prefix)-\(item.suffix).png"
            guard writePNG(cgImage, scale: 2, to: path) else { return 1 }
            print("✅ \(path)  \(cgImage.width)×\(cgImage.height)px")

            // 選單列（PLAN §4.5）。delegate 傳 nil → 沒有面板可操作，純渲染
            let menu = MenuBarView(calendars: MockData.calendars(),
                                   reminderLists: MockData.reminderLists(),
                                   delegate: nil,
                                   scrollable: false)
                .fixedSize()
                // 實際 App 的背景由 MenuBarExtra 的系統彈出視窗提供，
                // snapshot 沒有那層，不補背景的話深色模式的白字會畫在透明底上看不見
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, item.scheme)

            var menuImage: CGImage?
            appearance.performAsCurrentDrawingAppearance {
                let renderer = ImageRenderer(content: menu)
                renderer.scale = 2
                menuImage = renderer.cgImage
            }
            guard let menuCG = menuImage else {
                fail("ImageRenderer 產不出 \(item.suffix) 選單圖")
                return 1
            }
            let menuPath = "\(prefix)-menu-\(item.suffix).png"
            guard writePNG(menuCG, scale: 2, to: menuPath) else { return 1 }
            print("✅ \(menuPath)  \(menuCG.width)×\(menuCG.height)px")

            // 角色模式：四種心情各一張（M9 計畫 §5.7）。
            // 固定在第 0 格，輸出才可重現
            for mood in Mood.allCases {
                let character = CharacterView(mood: mood)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, item.scheme)
                guard let image = render(character, appearance: appearance) else {
                    fail("ImageRenderer 產不出 \(mood) 的角色圖")
                    return 1
                }
                let path = "\(prefix)-char-\(mood.rawValue)-\(item.suffix).png"
                guard writePNG(image, scale: 2, to: path) else { return 1 }
                print("✅ \(path)  \(image.width)×\(image.height)px")
            }

            // 小精靈加一則兩行的泡泡（§5.7）
            let bubble = HStack(alignment: .center, spacing: 6) {
                BubbleView(text: "⏰ 逾期：把這一則寫長一點，讓泡泡換到第二行", background: .opaque)
                CharacterView(mood: .worried)
            }
            .fixedSize()
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, item.scheme)
            guard let bubbleImage = render(bubble, appearance: appearance) else {
                fail("ImageRenderer 產不出泡泡圖")
                return 1
            }
            let bubblePath = "\(prefix)-char-bubble-\(item.suffix).png"
            guard writePNG(bubbleImage, scale: 2, to: bubblePath) else { return 1 }
            print("✅ \(bubblePath)  \(bubbleImage.width)×\(bubbleImage.height)px")

            // 展開的卡片：完整卡片 ＋ 專案區（§4.5、§5.7）
            let mockProjects = MockData.projects()
            let expanded = WidgetView(
                eventsState: .loaded(items: events, total: events.count),
                remindersState: .loaded(items: reminders, total: reminders.count),
                pendingReminderIDs: MockData.pendingReminderIDs,
                background: .opaque,
                now: MockData.referenceDate(),
                projectsState: .loaded(items: mockProjects, total: mockProjects.count),
                characterMood: .worried,
                projectsScrollable: false)
                .frame(width: PanelMetrics.width)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.colorScheme, item.scheme)
            guard let expandedImage = render(expanded, appearance: appearance) else {
                fail("ImageRenderer 產不出展開的卡片")
                return 1
            }
            let expandedPath = "\(prefix)-char-expanded-\(item.suffix).png"
            guard writePNG(expandedImage, scale: 2, to: expandedPath) else { return 1 }
            print("✅ \(expandedPath)  \(expandedImage.width)×\(expandedImage.height)px")
        }

        // 所有動畫格排成一張放大 8 倍的圖，方便逐格檢查像素（§5.7）
        guard let sheet = renderSpriteSheet() else {
            fail("產不出 sprite sheet")
            return 1
        }
        let sheetPath = "\(prefix)-char-sprites.png"
        guard writePNG(sheet, scale: 1, to: sheetPath) else { return 1 }
        print("✅ \(sheetPath)  \(sheet.width)×\(sheet.height)px")

        return 0
    }

    private static func render(_ content: some View, appearance: NSAppearance) -> CGImage? {
        var image: CGImage?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            image = renderer.cgImage
        }
        return image
    }

    /// 每一列是一種心情，依序是各動畫格與眨眼格，整張放大 8 倍。
    /// 直接用 CoreGraphics 拼，不走 ImageRenderer——像素放大要最近鄰，
    /// 而且這張圖是給人逐格檢查用的，不需要跟著深淺色模式變
    private static func renderSpriteSheet() -> CGImage? {
        let zoom = 8
        let cell = PixelSprite.side * zoom
        let gap = zoom
        let columns = Mood.allCases.map { mood -> Int in
            BuiltinCharacter.frames(for: mood).count
                + (BuiltinCharacter.blinkFrame(for: mood) == nil ? 0 : 1)
        }.max() ?? 1
        let width = columns * cell + (columns + 1) * gap
        let height = Mood.allCases.count * cell + (Mood.allCases.count + 1) * gap

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // 中灰底：這張圖是給人逐格檢查像素用的，深色的外框與淺色的眼白
        // 都必須看得見。用深色底會讓外框色的部位整個消失
        context.setFillColor(NSColor(srgbRed: 0.45, green: 0.45, blue: 0.48, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none

        for (row, mood) in Mood.allCases.enumerated() {
            var frames = BuiltinCharacter.frames(for: mood)
            if let blink = BuiltinCharacter.blinkFrame(for: mood) { frames.append(blink) }
            let palette = PixelSprite.Palette(body: mood.bodyColor)

            for (column, rows) in frames.enumerated() {
                guard let grid = try? PixelSprite.Grid(rows),
                      let image = PixelSprite.image(grid, palette: palette) else { continue }
                // CGContext 原點在左下，第 0 列要畫在最上面
                let y = height - gap - (row + 1) * cell - row * gap
                let x = gap + column * (cell + gap)
                context.draw(image, in: CGRect(x: x, y: y, width: cell, height: cell))
            }
        }
        return context.makeImage()
    }

    private static func writePNG(_ cgImage: CGImage, scale: CGFloat, to path: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fail("PNG 編碼失敗：\(path)")
            return false
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            fail("寫檔失敗：\(path) — \(error.localizedDescription)")
            return false
        }
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
