import SwiftUI

/// 一個專案的卡片：名稱 ＋ 燈號 ＋ 進度條 ＋ 更新時間 ＋ 卡住的點 ＋ 待辦清單。
///
/// **角色模式展開後的專案區（`ProjectsSection`）與完整模式的專案輪播
/// （`ProjectTickerView`）用的是這同一個 View**（使用者 2026-09-29 要求）。
/// 兩邊各畫一份的話，改了其中一邊另一邊就會跟著走鐘——這個檔案存在的唯一理由
/// 就是讓那件事不可能發生。上層只決定「要顯示幾個專案、怎麼挑」，不決定長什麼樣。
///
/// **完全唯讀**：打勾圓圈只是顯示，點了沒有反應。
/// 只有專案名稱那一列可以點，用來開啟該專案的 `latest.md`（§4.5）。
struct ProjectCardView: View {
    let project: ProjectItem
    /// 點專案名稱。snapshot 傳空實作
    var onOpen: (ProjectItem) -> Void = { _ in }

    /// 每個專案最多列幾項待辦
    static let todoLimit = 3

    /// 卡片固定高度（使用者 2026-09-29 決定 90pt）。
    ///
    /// **這是為了不抖動**：每張卡的內容長度都不一樣（實測使用者真實的 5 個專案
    /// 是 52 / 86 / 86 / 86 / 150pt），輪播每 8 秒換一張，整個面板就會跟著上下跳
    /// 最多 98pt。固定高度 ＋ 靠上對齊之後，換卡只有淡入淡出，面板不動。
    ///
    /// 90pt ＝ 中位數那一檔：五張卡有四張剛好放得下，只有「有卡住的點又有一堆待辦」
    /// 的那種會被收斂。內容放不下時是**先算再少列**（`visibleTodoCount`），
    /// 不是畫出來再裁掉——裁切只留作最後的保險
    static let fixedHeight: CGFloat = 90

    /// 下面這些是實測值，不是估的：用 `NSHostingView.fittingSize` 量真實卡片，
    /// 再從四張高度不同的卡反推出每一列各佔多少（含 `VStack` 的 3pt 間距）。
    /// 改字級或間距時這幾個數字要跟著重量，`ProjectCardHeightTests` 會抓到不一致
    private static let baseHeight: CGFloat = 36      // 上下 padding ＋ 名稱列 ＋ 進度條
    private static let updatedRowHeight: CGFloat = 16
    private static let blockerRowHeight: CGFloat = 17
    private static let todoRowHeight: CGFloat = 17

    /// 這張卡列得下幾項待辦。
    ///
    /// 純算術、不碰 View，所以「會不會超過 `fixedHeight`」這件事可以被單元測試釘住
    static func visibleTodoCount(for project: ProjectItem) -> Int {
        var remaining = fixedHeight - baseHeight
        if project.updated != nil { remaining -= updatedRowHeight }
        if project.blocker != nil { remaining -= blockerRowHeight }
        let fits = Int((remaining / todoRowHeight).rounded(.down))
        return max(0, min(min(fits, todoLimit), project.openTodos.count))
    }

    var body: some View {
        card
            // 靠上對齊：內容比較短的卡把空白留在下面，名稱列才會永遠在同一個位置。
            // `clipped()` 是保險——真的有人把字級調大時寧可切掉一點，也不要又開始抖
            .frame(height: Self.fixedHeight, alignment: .top)
            .clipped()
    }

    /// 不套固定高度的內容本身。
    ///
    /// 非 private 是為了讓 `ProjectCardHeightTests` 量得到**自然高度**——
    /// 「內容有沒有超過 `fixedHeight`（＝有沒有被 `clipped()` 切到）」
    /// 只有量這一層才驗得出來，量外面那層永遠是 90
    var card: some View {
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

            progressBar
                .allowsHitTesting(false)

            if let updated = project.updated {
                Text("\(Formatting.dateTitle(for: updated)) \(Formatting.timeString(for: updated)) 更新")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }

            if let blocker = project.blocker {
                // 只給一行：兩行會多吃 14pt，那正好是一項待辦的位置（§固定高度）
                Text("⚠️ \(blocker)")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }

            let shown = Array(project.openTodos.prefix(Self.visibleTodoCount(for: project)))
            let hidden = project.openTodos.count - shown.count
            ForEach(Array(shown.enumerated()), id: \.element) { index, todo in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(todo)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // 「還有幾項」掛在最後一列的行尾，不自己佔一列——
                    // 獨立一列要多 16pt，90pt 的卡放不下（使用者 2026-09-29 定案）
                    if hidden > 0, index == shown.count - 1 {
                        Text("＋\(hidden)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .layoutPriority(1)
                    }
                }
                // 打勾圓圈只是顯示，點了沒有反應（§4.5）
                .allowsHitTesting(false)
            }
            // 一項都列不下時還是要講有幾項，否則那個專案看起來像沒事做
            if shown.isEmpty, hidden > 0 {
                Text("＋\(hidden) 項")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 14)
                    .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 2)
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: proxy.size.width * fraction)
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
    private var fraction: CGFloat {
        guard project.total > 0 else { return 0 }
        return CGFloat(project.done) / CGFloat(project.total)
    }
}
