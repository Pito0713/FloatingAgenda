import SwiftUI

enum CardBackground {
    /// App 內：NSVisualEffectView 毛玻璃
    case blur
    /// snapshot：ImageRenderer 畫不出 NSVisualEffectView，改用不透明底色
    case opaque
}

/// 卡片根視圖：標題 ＋ 行程區 ＋ 提醒區（PLAN §4.2）。
struct WidgetView: View {
    let eventsState: SectionState<EventItem>
    let remindersState: SectionState<ReminderItem>
    /// 顯示為已勾選的提醒，涵蓋緩衝期與寫入成功後等待 refresh 移除的期間
    var pendingReminderIDs: Set<String> = []
    /// 單筆勾選寫入失敗的訊息
    var reminderError: String?
    let background: CardBackground
    var now: Date = Date()
    /// 收合模式（PLAN §4.10）
    var isCollapsed = false
    var onToggleCollapsed: () -> Void = {}

    /// 角色模式展開時才傳：提醒區下方多一個專案區（M9 計畫 §4.5）。
    /// 完整與收合模式一律傳 nil，畫面與 M9 之前完全一樣
    var projectsState: SectionState<ProjectItem>?
    /// 角色模式展開時，標題列最左邊放一個 24pt 的小精靈，點它收回（§4.5）
    var characterMood: Mood?
    var onCollapseToCharacter: () -> Void = {}
    /// 右上角的收合箭頭要不要出現。
    /// 角色模式展開時傳 false——那裡的收回入口是標題列的小精靈與 Esc，
    /// 留著箭頭會是一顆滑過去就浮現、寫著「收合」卻按了沒反應的按鈕
    /// （codex 2026-09-22 指出）
    var showsCollapseButton = true
    var onOpenProject: (ProjectItem) -> Void = { _ in }
    /// `ImageRenderer` 畫不出 ScrollView 的內容，snapshot 傳 false 直接攤平渲染
    /// （與 M5 的 `MenuBarView.scrollable` 同一個理由）
    var projectsScrollable = true
    /// 所有互動都用注入的方式傳進來，View 層完全不認識 AgendaStore。
    /// snapshot 傳空實作 → 結構上不可能誤觸寫入，也不會開啟任何 App
    var onOpenEvent: (EventItem) -> Void = { _ in }
    var onToggleReminder: (ReminderItem) -> Void = { _ in }
    var onOpenReminder: (ReminderItem) -> Void = { _ in }
    var onOpenCalendarSettings: () -> Void = {}
    var onOpenReminderSettings: () -> Void = {}

    @State private var isHoveringCard = false
    /// 標題＋行程＋提醒那一塊的實際高度，用來算專案區還剩多少空間可用
    @State private var fixedSectionsHeight: CGFloat = 0

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                if showsCollapseButton { collapseButton }
            }
            .padding(PanelMetrics.padding)
            .frame(width: PanelMetrics.width, alignment: .leading)
            .background(alignment: .center) { backgroundLayer }
            .overlay {
                RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .onHover { isHoveringCard = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if isCollapsed {
            VStack(alignment: .leading, spacing: 4) {
                collapsedDragStrip
                CollapsedCardView(eventsState: eventsState,
                                  remindersState: remindersState,
                                  pendingIDs: pendingReminderIDs,
                                  errorMessage: reminderError,
                                  now: now,
                                  onOpenEvent: onOpenEvent,
                                  onToggleReminder: onToggleReminder,
                                  onOpenReminder: onOpenReminder,
                                  onOpenCalendarSettings: onOpenCalendarSettings,
                                  onOpenReminderSettings: onOpenReminderSettings)
            }
        } else {
            if let projectsState {
                VStack(alignment: .leading, spacing: 10) {
                    fixedSections
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            fixedSectionsHeight = height
                        }
                    Divider()
                        .allowsHitTesting(false)
                    projectsArea(projectsState)
                }
            } else {
                // ⚠️ 這個分支與 M9 之前**逐字相同**，不要改成共用 `fixedSections`。
                // 多一層 VStack 或多一個 `.onGeometryChange` 都會讓文字的
                // 反鋸齒差上 1–2/255——肉眼看不出來，但 §7.1 要求
                // 完整與收合模式的 snapshot 逐位元組不變（實測踩到）
                VStack(alignment: .leading, spacing: 10) {
                    // 純顯示的區塊一律關掉 hit testing，讓下層拖曳區吃到點擊；
                    // 行程列自己要可點，所以不能整層關
                    HeaderView(date: now)
                        .allowsHitTesting(false)
                    EventsSection(state: eventsState,
                                  now: now,
                                  onOpen: onOpenEvent,
                                  onOpenSettings: onOpenCalendarSettings)
                    Divider()
                        .allowsHitTesting(false)
                    RemindersSection(state: remindersState,
                                     pendingIDs: pendingReminderIDs,
                                     errorMessage: reminderError,
                                     now: now,
                                     onToggle: onToggleReminder,
                                     onOpen: onOpenReminder,
                                     onOpenSettings: onOpenReminderSettings)
                }
            }
        }
    }

    /// 標題、行程、提醒。§4.5 規定這三塊**不捲**，所以它們一律取自己的理想高度
    private var fixedSections: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 純顯示的區塊一律關掉 hit testing，讓下層拖曳區吃到點擊；
            // 行程列自己要可點，所以不能整層關
            header
            EventsSection(state: eventsState,
                          now: now,
                          onOpen: onOpenEvent,
                          onOpenSettings: onOpenCalendarSettings)
            Divider()
                .allowsHitTesting(false)
            RemindersSection(state: remindersState,
                             pendingIDs: pendingReminderIDs,
                             errorMessage: reminderError,
                             now: now,
                             onToggle: onToggleReminder,
                             onOpen: onOpenReminder,
                             onOpenSettings: onOpenReminderSettings)
        }
    }

    /// 專案區：只有這一塊會捲（§4.5）。
    ///
    /// 高度上限是「620 減掉上面那三塊實際用掉的高度」算出來的，不是寫死的值——
    /// 先量再算是唯一可靠的做法：對整張卡片用 `.frame(maxHeight:)` 只會**裁切**
    /// （實測連標題都被切掉），不會讓專案區去吸收多出來的高度。
    @ViewBuilder
    private func projectsArea(_ state: SectionState<ProjectItem>) -> some View {
        let section = ProjectsSection(state: state, onOpen: onOpenProject)
            .frame(maxWidth: .infinity, alignment: .leading)
        if projectsScrollable {
            ScrollView(.vertical) { section }
                .frame(maxHeight: projectsBudget)
        } else {
            section
        }
    }

    /// 專案區還剩多少高度可用。
    ///
    /// **不設下限**：第一版留了 120pt 的下限，想保證專案區不會被壓到看不見，
    /// 但那會讓整張卡片超過 §4.5 的 620pt 上限——而卡片一旦高過螢幕，
    /// 行程與提醒區又不捲，下面的內容就**永遠捲不到**（codex 2026-09-22 指出）。
    /// 寧可讓專案區在忙碌的日子縮到很小（標題仍在，清單自己捲），
    /// 也不要讓內容跑到畫面外拿不到。
    private var projectsBudget: CGFloat {
        let used = fixedSectionsHeight + PanelMetrics.padding * 2 + 24
        return max(0, PanelMetrics.expandedMaxHeight - used)
    }

    /// 角色模式展開時，標題左邊多一個 24pt 的小精靈當「收回」的入口（§4.5）
    @ViewBuilder
    private var header: some View {
        if let characterMood {
            HStack(alignment: .center, spacing: 10) {
                Button(action: onCollapseToCharacter) {
                    CharacterView(mood: characterMood)
                        .scaleEffect(24.0 / PanelMetrics.characterSize)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("收回小精靈")
                HeaderView(date: now)
                    .allowsHitTesting(false)
            }
        } else {
            HeaderView(date: now)
                .allowsHitTesting(false)
        }
    }

    /// 收合模式的專用拖曳區。
    ///
    /// 收合後卡片只有兩列、兩列都會吃掉點擊，沒有這一塊幾乎沒有地方可以拖。
    /// 刻意關閉 hit testing，讓下層的 `WindowDragArea` 吃到 mouseDown。
    ///
    /// 原本中間有一個可見的小握把，使用者 2026-09-18 回報「有點醜」後移除；
    /// 拖曳面積保留，只是不再有視覺提示（右上角的箭頭仍在這一列裡）。
    private var collapsedDragStrip: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: PanelMetrics.collapsedDragStripHeight)
            .allowsHitTesting(false)
    }

    /// 收合時常駐，完整模式只在滑過卡片時浮現（跟原生小工具一樣）
    private var isVisible: Bool { isCollapsed || isHoveringCard }

    private var collapseButton: some View {
        Button(action: onToggleCollapsed) {
            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(Color.primary.opacity(isHoveringCard ? 0.08 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        // .opacity(0) 不會關閉 hit testing：不加這行，完整模式下右上角會有一個
        // 看不見但可點、而且擋住拖曳的按鈕
        .allowsHitTesting(isVisible)
        .help(isCollapsed ? "展開" : "收合")
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch background {
        case .blur:
            ZStack {
                WidgetBackground(cornerRadius: PanelMetrics.cornerRadius)
                // 圖層順序：毛玻璃 → 拖曳區 → 內容
                WindowDragArea()
            }
        case .opaque:
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }
}
