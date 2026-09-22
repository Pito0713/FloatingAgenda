// 懸浮小人 demo：讀 ~/.agent-sessions/*/latest.md，顯示專案進度與待辦
// 執行：swift Buddy.swift   （右鍵小人 → 結束）
import AppKit
import SwiftUI

// MARK: - 資料

struct Project: Identifiable {
    let id: String
    let name: String
    let status: String      // 🟢 順暢 / 🟡 進行中 / 🔴 …
    let updated: String
    let done: Int
    let total: Int
    let todos: [String]
    let blocked: String?

    var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

enum SessionReader {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-sessions")

    static func load() -> [Project] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return dirs.sorted().compactMap { dir in
            let file = root.appendingPathComponent(dir).appendingPathComponent("latest.md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            if text.contains("已搬遷") { return nil }
            return parse(id: dir, text: text)
        }
    }

    static func parse(id: String, text: String) -> Project {
        var status = "⚪️ 未知", updated = "", done = 0, total = 0
        var todos: [String] = [], section = "", blockedLines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") { section = String(line.dropFirst(3)); continue }
            if let v = value(line, "狀態：") { status = v }
            if let v = value(line, "最後更新：") { updated = v }
            if line.hasPrefix("- [x]") || line.hasPrefix("- [X]") { done += 1; total += 1 }
            if line.hasPrefix("- [ ]") {
                total += 1
                todos.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
            if section.hasPrefix("卡住"), !line.isEmpty { blockedLines.append(line) }
        }
        let blocked = blockedLines.joined(separator: " ")
        let isBlocked = !blocked.isEmpty && !blocked.hasPrefix("無")
        return Project(id: id, name: id, status: status, updated: updated,
                       done: done, total: total, todos: todos,
                       blocked: isBlocked ? blocked : nil)
    }

    private static func value(_ line: String, _ key: String) -> String? {
        guard let r = line.range(of: key) else { return nil }
        return String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 狀態

enum Mood { case happy, busy, worried }

final class BuddyModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var expanded = false { didSet { onResize?() } }
    @Published var bubble: String?
    @Published var blink = false
    var onResize: (() -> Void)?
    private var bubbleIndex = 0
    private var timers: [Timer] = []

    var mood: Mood {
        if projects.contains(where: { $0.blocked != nil || $0.status.contains("🔴") }) { return .worried }
        if projects.contains(where: { !$0.todos.isEmpty }) { return .busy }
        return .happy
    }

    var bubbleLines: [String] {
        var lines: [String] = []
        for p in projects {
            if let b = p.blocked { lines.append("⚠️ \(p.name) 卡住了：\(b)") }
            if let t = p.todos.first { lines.append("📌 \(p.name)：\(t)") }
        }
        let open = projects.reduce(0) { $0 + $1.todos.count }
        lines.insert(open == 0 ? "今天都清空了，讚 ✨" : "還有 \(open) 件待辦喔～點我看看", at: 0)
        return lines
    }

    func start() {
        reload()
        timers.append(Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.reload() })
        timers.append(Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            self?.blink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.blink = false }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in self?.nextBubble() })
        nextBubble()
    }

    func reload() { projects = SessionReader.load() }

    func nextBubble() {
        guard !expanded else { bubble = nil; return }
        let lines = bubbleLines
        withAnimation(.spring(response: 0.35)) {
            bubble = lines[bubbleIndex % lines.count]
        }
        bubbleIndex += 1
    }
}

// MARK: - 畫面

struct Character: View {
    let mood: Mood
    let blink: Bool
    @State private var bob = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.18))
                .frame(width: 62, height: 10)
                .offset(y: 46)
                .scaleEffect(bob ? 0.85 : 1)
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(LinearGradient(colors: bodyColors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 78, height: 72)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                HStack(spacing: 18) { eye; eye }.offset(y: -6)
                HStack(spacing: 38) { cheek; cheek }.offset(y: 6)
                mouth.offset(y: 14)
                if mood == .worried {
                    Text("💦").font(.system(size: 14)).offset(x: 34, y: -30)
                }
            }
            .offset(y: bob ? -5 : 2)
        }
        .frame(width: 100, height: 104)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    private var bodyColors: [Color] {
        switch mood {
        case .happy:   return [Color(red: 0.62, green: 0.90, blue: 0.70), Color(red: 0.35, green: 0.75, blue: 0.52)]
        case .busy:    return [Color(red: 0.72, green: 0.82, blue: 1.00), Color(red: 0.45, green: 0.58, blue: 0.95)]
        case .worried: return [Color(red: 1.00, green: 0.80, blue: 0.62), Color(red: 0.96, green: 0.58, blue: 0.42)]
        }
    }

    private var eye: some View {
        Capsule().fill(Color(white: 0.12))
            .frame(width: 8, height: blink ? 1.5 : 11)
    }

    private var cheek: some View {
        Circle().fill(Color.pink.opacity(0.35)).frame(width: 10, height: 10)
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .happy:
            Circle().trim(from: 0.05, to: 0.45).stroke(Color(white: 0.12), lineWidth: 2)
                .frame(width: 16, height: 16).offset(y: -6)
        case .busy:
            Capsule().fill(Color(white: 0.12)).frame(width: 9, height: 2.5)
        case .worried:
            Circle().trim(from: 0.55, to: 0.95).stroke(Color(white: 0.12), lineWidth: 2)
                .frame(width: 14, height: 14).offset(y: 6)
        }
    }
}

struct Bubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(3)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.25)))
            .frame(maxWidth: 230)
    }
}

struct ProjectRow: View {
    let p: Project
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(p.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(p.status).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ProgressView(value: p.progress).tint(p.blocked != nil ? .orange : .accentColor)
            HStack {
                Text("\(p.done)/\(p.total) 完成").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(p.updated).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            if let b = p.blocked {
                Text("⚠️ \(b)").font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
            }
            ForEach(p.todos.prefix(3), id: \.self) { t in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "circle").font(.system(size: 9)).padding(.top, 2)
                    Text(t).font(.system(size: 11)).lineLimit(2)
                }
                .foregroundStyle(.primary.opacity(0.85))
            }
            if p.todos.count > 3 {
                Text("＋\(p.todos.count - 3) 項").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Card: View {
    @ObservedObject var model: BuddyModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("專案進度").font(.system(size: 15, weight: .bold))
                Spacer()
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 8) { ForEach(model.projects) { ProjectRow(p: $0) } }
            }
        }
        .padding(14)
        .frame(width: 300, height: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.2)))
    }
}

struct BuddyView: View {
    @ObservedObject var model: BuddyModel
    let drag: (CGPoint) -> Void
    let dragEnd: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Spacer(minLength: 0)
            if model.expanded {
                Card(model: model).transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
            } else if let b = model.bubble {
                Bubble(text: b).id(b).transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
            }
            Character(mood: model.mood, blink: model.blink)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { _ in drag(NSEvent.mouseLocation) }
                    .onEnded { _ in dragEnd() })
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.expanded.toggle() }
                }
                .contextMenu {
                    Button("重新整理") { model.reload() }
                    Button("結束") { NSApp.terminate(nil) }
                }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

// MARK: - 視窗

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: Panel!
    let model = BuddyModel()
    var dragOffset: CGPoint?

    func applicationDidFinishLaunching(_ note: Notification) {
        let size = NSSize(width: 330, height: 500)
        let screen = NSScreen.screens.first!.visibleFrame
        let origin = NSPoint(x: screen.maxX - size.width - 20, y: screen.minY + 20)
        panel = Panel(contentRect: NSRect(origin: origin, size: size),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = BuddyView(model: model,
            drag: { [weak self] mouse in self?.drag(to: mouse) },
            dragEnd: { [weak self] in self?.dragOffset = nil })
        let host = NSHostingView(rootView: view)
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = false
        model.start()
        startClickThrough()
    }

    func drag(to mouse: CGPoint) {
        if dragOffset == nil {
            dragOffset = CGPoint(x: mouse.x - panel.frame.origin.x, y: mouse.y - panel.frame.origin.y)
        }
        guard let o = dragOffset else { return }
        panel.setFrameOrigin(NSPoint(x: mouse.x - o.x, y: mouse.y - o.y))
    }

    // 透明區域讓滑鼠穿透：只有滑鼠在小人／泡泡／卡片上才接事件
    func startClickThrough() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.dragOffset == nil else { return }
            let m = NSEvent.mouseLocation, f = self.panel.frame
            let local = CGPoint(x: m.x - f.minX, y: m.y - f.minY)
            let hot: CGRect
            if self.model.expanded {
                hot = CGRect(x: f.width - 318, y: 0, width: 318, height: 490)
            } else {
                hot = CGRect(x: f.width - 250, y: 0, width: 250, height: 190)
            }
            self.panel.ignoresMouseEvents = !hot.contains(local)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 不出現在 Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
