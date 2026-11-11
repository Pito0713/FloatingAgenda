import SwiftUI

/// 專案區（M9 計畫 §4.5）。
///
/// **完整模式與角色模式展開後用的是這同一個 View**（使用者 2026-09-29 要求）。
///
/// 2026-11-10 由「一次一張、8 秒輪播」改成**所有專案一次攤開**（使用者要求）：
/// 收合模式負責精簡，展開的卡片是看詳情的地方，不該讓人等輪播轉到想看的那一個。
/// 順序沿用 `ProjectStore.order`（有卡住的點 → 🔴 → 🟡 → 🟢），放不下由整張卡捲動。
///
/// 兩個模式唯一的差別是 `showsStatusNotes`——讀不到資料時要不要說一句話。
///
/// **完全唯讀**：打勾圓圈只是顯示，點了沒有反應。
/// 這個 View 不認識 `ProjectStore`，狀態與互動都是注入的（§5.6）。
/// 卡片長什麼樣是 `ProjectCardView` 的事。
struct ProjectsSection: View {
    let state: SectionState<ProjectItem>
    var now: Date = Date()
    /// 讀不到／還在讀／一個專案都沒有時，要不要留一行字說明。
    ///
    /// 角色模式展開是使用者**特地點開來看專案**的，什麼都不講會像壞掉；
    /// 完整模式這一塊是附帶的，沒有交接紀錄的人整塊消失才對——
    /// 否則每個沒用過 `~/.agent-sessions` 的人卡片下面都會掛一行「還沒有任何交接紀錄」
    var showsStatusNotes = true
    /// 點專案名稱。snapshot 傳空實作
    var onOpen: (ProjectItem) -> Void = { _ in }
    /// 點 review 狀態那一列。snapshot 傳空實作
    var onOpenReview: (URL) -> Void = { _ in }

    var body: some View {
        let entries = ProjectTicker.entries(projects: state)
        if !entries.isEmpty {
            container {
                header(count: entries.count)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, project in
                        if index > 0 {
                            // 卡與卡之間的細線比區塊分隔線淡，看得出還是同一區
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 0.5)
                                .allowsHitTesting(false)
                        }
                        ProjectCardView(project: project, now: now,
                                        onOpen: onOpen, onOpenReview: onOpenReview)
                    }
                }
            }
        } else if showsStatusNotes, let message = ProjectTicker.statusNote(for: state) {
            container {
                header(count: 0)
                note(message)
            }
        }
    }

    /// 分隔線畫在這裡而不是 `WidgetView`：沒有專案時整塊消失，分隔線得跟著一起消失，
    /// 否則卡片最下面會多出一條孤零零的線。
    /// 下緣補 2pt，讓它與上面「行程／提醒」之間的 10pt 間距一致
    private func container<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.bottom, 2)
                .allowsHitTesting(false)
            content()
        }
    }

    private func header(count: Int) -> some View {
        HStack {
            Text("專案")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if count > 0 {
                Text("\(count) 個")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
    }

    /// 純顯示文字：關掉 hit testing，讓下層拖曳區吃到點擊
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }
}
