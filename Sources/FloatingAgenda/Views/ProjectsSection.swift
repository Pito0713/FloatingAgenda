import Combine
import SwiftUI

/// 專案區（M9 計畫 §4.5，2026-09-29 由捲動清單改成輪播）。
///
/// **完整模式與角色模式展開後用的是這同一個 View**（使用者 2026-09-29 要求）：
/// 一次顯示一個專案，每 8 秒換下一個。原本角色模式是一次攤開 4 張卡、裝在
/// 有高度上限的 `ScrollView` 裡，使用者不要捲動，改成與完整模式一樣的輪播。
///
/// 兩個模式唯一的差別是 `showsStatusNotes`——讀不到資料時要不要說一句話。
///
/// **完全唯讀**：打勾圓圈只是顯示，點了沒有反應。
/// 只有專案名稱可以點，用來開啟該專案的 `latest.md`。
/// 這個 View 不認識 `ProjectStore`，狀態與互動都是注入的（§5.6）。
/// 卡片長什麼樣是 `ProjectCardView` 的事。
struct ProjectsSection: View {
    let state: SectionState<ProjectItem>
    /// 面板隱藏、螢幕睡眠、snapshot 時傳 false，計時器就不會建立（同泡泡的作法）
    var isAnimating = true
    /// 讀不到／還在讀／一個專案都沒有時，要不要留一行字說明。
    ///
    /// 角色模式展開是使用者**特地點開來看專案**的，什麼都不講會像壞掉；
    /// 完整模式這一塊是附帶的，沒有交接紀錄的人整塊消失才對——
    /// 否則每個沒用過 `~/.agent-sessions` 的人卡片下面都會掛一行「還沒有任何交接紀錄」
    var showsStatusNotes = true
    /// 點專案名稱。snapshot 傳空實作
    var onOpen: (ProjectItem) -> Void = { _ in }

    /// 輪播位置。只記 id，不記清單——理由見 `ProjectTicker.Cursor`
    @State private var cursor = ProjectTicker.Cursor()
    /// 滑鼠停在卡片上時暫停輪播
    @State private var isHovering = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let entries = ProjectTicker.entries(projects: state)
        if let project = cursor.current(in: entries) {
            container {
                header(entries: entries)
                ProjectCardView(project: project, onOpen: onOpen)
                    // `.id` 讓換頁被當成「換一張卡」而不是「同一張卡改文字」，
                    // 淡入淡出才會發生
                    .id(project.id)
                    .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: project.id)
            .onReceive(timer(count: entries.count)) { _ in
                // 滑鼠停在卡片上時暫停：使用者正在讀，換掉等於把字抽走
                guard !isHovering else { return }
                cursor.advance(in: entries)
            }
            .onHover { isHovering = $0 }
        } else if showsStatusNotes, let message = ProjectTicker.statusNote(for: state) {
            container {
                header(entries: [])
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

    /// 右邊的「第幾個／共幾個」：一次只看得到一張卡，
    /// 不講的話不知道後面還有幾個專案在排隊
    private func header(entries: [ProjectItem]) -> some View {
        HStack {
            Text("專案")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !entries.isEmpty {
                Text("\(cursor.position(in: entries))/\(entries.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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

    /// 只有**真的會換頁**時才建立計時器：只有一個專案、面板隱藏、snapshot 都不該有東西在跳
    /// （codex 2026-09-22 對泡泡計時器的同一條指摘）
    private func timer(count: Int) -> AnyPublisher<Date, Never> {
        guard isAnimating, count > 1 else {
            return Empty<Date, Never>(completeImmediately: false).eraseToAnyPublisher()
        }
        return Timer.publish(every: ProjectTicker.interval, on: .main, in: .common)
            .autoconnect()
            .eraseToAnyPublisher()
    }
}
