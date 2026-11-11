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
    /// 明天的行程，只在今天沒有行程時預告（2026-11-10）。收合模式不用
    var tomorrowEvents: [EventItem] = []
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

    /// 提醒區下方的專案區（M9 計畫 §4.5）。**完整模式與角色模式展開後共用這一個參數**
    /// ——兩邊畫的是同一個 `ProjectsSection`（所有專案一次攤開），
    /// 一邊一個參數就會開始不同步（使用者 2026-09-29 要求）。
    /// 收合模式與角色模式待機一律傳 nil
    var projectsState: SectionState<ProjectItem>?
    /// 點專案卡上的 review 狀態，開啟報告（ADR-032）
    var onOpenReview: (URL) -> Void = { _ in }
    /// 展開的卡片最多多高（不含外圍 padding），超過就捲動（使用者 2026-11-10 同意）。
    /// App 依螢幕可用高度傳入；nil ＝ 不捲動、照內容長高——snapshot 走這條，
    /// `ImageRenderer` 畫 `ScrollView` 只會畫出可視範圍
    var maxContentHeight: CGFloat?
    /// 提醒區與專案區之間的排程區（使用者 2026-10-12 要求）。
    /// 規則同 `projectsState`：完整模式與角色模式展開後共用，其他情況傳 nil
    var schedulesState: SectionState<ScheduleItem>?
    var onOpenSchedule: (ScheduleItem) -> Void = { _ in }
    /// 有設定點擊指令的排程 Label，見 `SchedulesSection.actionableIDs`
    var actionableScheduleIDs: Set<String> = []
    /// 角色模式展開時，標題列最左邊放一個 24pt 的小精靈，點它收回（§4.5）
    var characterMood: Mood?
    /// 標題列那隻 24pt 小精靈要用哪個皮膚（M9 計畫 §4.6）
    var characterSkin: Skin = CharacterAnimation.builtinSkin
    var onCollapseToCharacter: () -> Void = {}
    /// 右上角的收合箭頭要不要出現。
    /// 角色模式展開時傳 false——那裡的收回入口是標題列的小精靈與 Esc，
    /// 留著箭頭會是一顆滑過去就浮現、寫著「收合」卻按了沒反應的按鈕
    /// （codex 2026-09-22 指出）
    var showsCollapseButton = true
    var onOpenProject: (ProjectItem) -> Void = { _ in }
    /// 所有互動都用注入的方式傳進來，View 層完全不認識 AgendaStore。
    /// snapshot 傳空實作 → 結構上不可能誤觸寫入，也不會開啟任何 App
    var onOpenEvent: (EventItem) -> Void = { _ in }
    var onToggleReminder: (ReminderItem) -> Void = { _ in }
    var onOpenReminder: (ReminderItem) -> Void = { _ in }
    var onOpenCalendarSettings: () -> Void = {}
    var onOpenReminderSettings: () -> Void = {}

    @State private var isHoveringCard = false
    /// 展開內容的自然高度，用來決定要不要換成捲動
    @State private var expandedContentHeight: CGFloat = 0

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
            collapsedContent
        } else {
            scrollingIfNeeded(expandedContent)
        }
    }

    /// 放得下就照原樣畫，放不下才包進 `ScrollView`。
    ///
    /// 不一律包：`ScrollView` 會吃掉落在內容上的 mouseDown，
    /// 那些點本來會穿到下層的 `WindowDragArea` 拿來拖面板。
    /// 只在真的超高時才付這個代價（此時還能從外圍 16pt 的邊拖）
    @ViewBuilder
    private func scrollingIfNeeded(_ inner: some View) -> some View {
        let measured = inner.onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            expandedContentHeight = $0
        }
        if let maxContentHeight, expandedContentHeight > maxContentHeight {
            ScrollView(.vertical) {
                measured
            }
            .scrollIndicators(.automatic)
            .frame(height: maxContentHeight)
        } else {
            measured
        }
    }

    /// 收合模式。不經過 `scrollingIfNeeded`：只有兩列，而且它的 snapshot 要與改版前逐位元組相同
    private var collapsedContent: some View {
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
    }

    /// 完整模式與角色模式展開共用同一套排版（2026-11-10 起）。
    ///
    /// 原本完整模式刻意自己寫一份、不共用 `fixedSections`，是為了守住
    /// §7.1「完整模式 snapshot 逐位元組不變」——多一層 VStack 就會讓反鋸齒差 1–2/255。
    /// 改成看詳情的版面時使用者同意換掉那批基準圖，兩份就沒有理由再分開維護。
    /// 唯一的差別：角色模式展開是特地點開來看專案的，讀不到資料要說一句話
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            fixedSections
            if let schedulesState {
                schedulesSection(schedulesState)
            }
            if let projectsState {
                projectsSection(projectsState, showsStatusNotes: characterMood != nil)
            }
        }
    }

    private func projectsSection(_ state: SectionState<ProjectItem>,
                                 showsStatusNotes: Bool) -> some View {
        ProjectsSection(state: state,
                        now: now,
                        showsStatusNotes: showsStatusNotes,
                        onOpen: onOpenProject,
                        onOpenReview: onOpenReview)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func schedulesSection(_ state: SectionState<ScheduleItem>) -> some View {
        SchedulesSection(state: state, now: now,
                         actionableIDs: actionableScheduleIDs,
                         onOpen: onOpenSchedule)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 標題、行程、提醒。三塊都取自己的理想高度，超高時整張卡一起捲（`scrollingIfNeeded`）
    private var fixedSections: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 純顯示的區塊一律關掉 hit testing，讓下層拖曳區吃到點擊；
            // 行程列自己要可點，所以不能整層關
            header
            EventsSection(state: eventsState,
                          tomorrow: tomorrowEvents,
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

    /// 角色模式展開時，標題左邊多一個 24pt 的小精靈當「收回」的入口（§4.5）
    @ViewBuilder
    private var header: some View {
        if let characterMood {
            HStack(alignment: .center, spacing: 10) {
                Button(action: onCollapseToCharacter) {
                    CharacterView(mood: characterMood, skin: characterSkin)
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
