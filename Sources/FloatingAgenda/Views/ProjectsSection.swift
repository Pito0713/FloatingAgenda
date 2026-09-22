import SwiftUI

/// 展開卡片裡的專案區（M9 計畫 §4.5）。
///
/// **完全唯讀**：打勾圓圈只是顯示，點了沒有反應。
/// 只有專案名稱可以點，用來開啟該專案的 `latest.md`。
/// 這個 View 不認識 `ProjectStore`，狀態與互動都是注入的（§5.6）。
struct ProjectsSection: View {
    let state: SectionState<ProjectItem>
    /// 點專案名稱。snapshot 傳空實作
    var onOpen: (ProjectItem) -> Void = { _ in }

    /// 最多顯示幾個專案（§4.5）
    static let displayLimit = 4
    /// 每個專案最多列幾項待辦
    static let todoLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("專案")
                .font(.system(size: 13, weight: .semibold))
                .allowsHitTesting(false)
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            note("讀取中…")
        case .needsPermission:
            // 讀檔不需要 TCC 權限，這個分支理論上到不了，列出來只為了窮盡所有狀態
            note("需要存取權限")
        case .failed(let message):
            note(message)
        case .loaded(let items, let total):
            if items.isEmpty {
                note("還沒有任何交接紀錄")
            } else {
                ForEach(items.prefix(Self.displayLimit)) { project in
                    row(project)
                }
                if total > Self.displayLimit {
                    note("還有 \(total - Self.displayLimit) 個專案")
                }
            }
        }
    }

    private func row(_ project: ProjectItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(project.statusText.isEmpty ? "⚪️" : project.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            // 只有名稱那一列可點：點了用預設的 .md 編輯器開啟 latest.md（§4.5）
            .contentShape(Rectangle())
            .onTapGesture { onOpen(project) }

            progressBar(project)
                .allowsHitTesting(false)

            if let updated = project.updated {
                Text("\(Formatting.dateTitle(for: updated)) \(Formatting.timeString(for: updated)) 更新")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }

            if let blocker = project.blocker {
                Text("⚠️ \(blocker)")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .allowsHitTesting(false)
            }

            ForEach(Array(project.openTodos.prefix(Self.todoLimit)), id: \.self) { todo in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(todo)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // 打勾圓圈只是顯示，點了沒有反應（§4.5）
                .allowsHitTesting(false)
            }
            if project.openTodos.count > Self.todoLimit {
                Text("＋\(project.openTodos.count - Self.todoLimit) 項")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 14)
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 2)
    }

    private func progressBar(_ project: ProjectItem) -> some View {
        HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: proxy.size.width * fraction(project))
                }
            }
            .frame(height: 5)
            Text("\(project.done)/\(project.total)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// 沒有任何項目時不要顯示成 100%——那會讓「還沒開始」看起來像「做完了」
    private func fraction(_ project: ProjectItem) -> CGFloat {
        guard project.total > 0 else { return 0 }
        return CGFloat(project.done) / CGFloat(project.total)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }
}
