import SwiftUI

/// 一個專案的卡片：名稱 ＋ 燈號 ＋ 進度條 ＋ review 狀態 ＋ 更新時間 ＋ 卡住的點 ＋ 待辦清單。
///
/// **角色模式展開後與完整模式的專案區用的是這同一個 View**（使用者 2026-09-29 要求）。
/// 兩邊各畫一份的話，改了其中一邊另一邊就會跟著走鐘——這個檔案存在的唯一理由
/// 就是讓那件事不可能發生。上層只決定「要顯示哪些專案」，不決定長什麼樣。
///
/// **高度跟著內容走**（2026-11-10）：原本固定 90pt 是為了輪播換卡時面板不跳，
/// 使用者改成所有專案一次攤開、看詳情之後就沒有輪播了，固定高度跟著拿掉——
/// 待辦全部列出、卡住的點最多 3 行，放不下由整張卡捲動
///
/// **完全唯讀**：打勾圓圈只是顯示，點了沒有反應。
/// 可以點的只有兩列：專案名稱開啟該專案的 `latest.md`（§4.5），
/// review 狀態那一列開啟 project-review 的報告（ADR-032）
struct ProjectCardView: View {
    let project: ProjectItem
    var now: Date = Date()
    /// 點專案名稱。snapshot 傳空實作
    var onOpen: (ProjectItem) -> Void = { _ in }
    /// 點 review 狀態那一列，帶的是報告的路徑。snapshot 傳空實作
    var onOpenReview: (URL) -> Void = { _ in }

    var body: some View {
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
            // 名稱那一列可點：點了用預設的 .md 編輯器開啟 latest.md（§4.5）
            .contentShape(Rectangle())
            .onTapGesture { onOpen(project) }

            progressBar
                .allowsHitTesting(false)

            if let review = project.review {
                reviewRow(review)
            }

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
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
            }

            ForEach(Array(project.openTodos.enumerated()), id: \.offset) { _, todo in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(todo)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 打勾圓圈只是顯示，點了沒有反應（§4.5）
                .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 2)
    }

    /// review 狀態（ADR-032）。燈號與進度條照舊只看 latest.md，這一列不會蓋掉它們
    private func reviewRow(_ review: ReviewStatus) -> some View {
        let line = ReviewStatusDisplay.line(for: review, now: now)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(line.text)
                .font(.system(size: 11))
                .foregroundStyle(color(for: line.tone))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if review.reportURL != nil {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = review.reportURL { onOpenReview(url) }
        }
        .help(review.reportURL == nil ? "" : "打開 review 報告")
    }

    private func color(for tone: ReviewStatusDisplay.Tone) -> Color {
        switch tone {
        case .failure: .red
        case .warning: .orange
        case .normal: .secondary
        }
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
