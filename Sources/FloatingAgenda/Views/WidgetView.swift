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
    /// 所有互動都用注入的方式傳進來，View 層完全不認識 AgendaStore。
    /// snapshot 傳空實作 → 結構上不可能誤觸寫入，也不會開啟任何 App
    var onOpenEvent: (EventItem) -> Void = { _ in }
    var onToggleReminder: (ReminderItem) -> Void = { _ in }
    var onOpenReminder: (ReminderItem) -> Void = { _ in }
    var onOpenCalendarSettings: () -> Void = {}
    var onOpenReminderSettings: () -> Void = {}

    @State private var isHoveringCard = false

    var body: some View {
        content
            .overlay(alignment: .topTrailing) { collapseButton }
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
