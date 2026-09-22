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
        }

        return 0
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
