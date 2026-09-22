import SwiftUI

/// 收合模式的放大尺寸（使用者 2026-09-18 要求「收合時 item 放大 1.25 倍」）。
///
/// 刻意用「把字級與尺寸乘上倍率」而不是 `.scaleEffect(1.25)`：
/// 後者會把已排版好的內容再縮放，文字容易落在非整數像素上而發虛。
/// 乘完取整數則是以該字級重新排版，維持銳利。
/// 完整模式不受影響，仍用原本的尺寸。
private enum CollapsedMetrics {
    static let scale: CGFloat = 1.25

    private static func scaled(_ base: CGFloat) -> CGFloat { (base * scale).rounded() }

    static let titleSize = scaled(13)       // 13 → 16
    static let detailSize = scaled(11)      // 11 → 14
    static let circleSize = scaled(16)      // 16 → 20
    static let barWidth = scaled(3)         // 3 → 4
    static let rowCorner = scaled(6)        // 6 → 8
    static let hSpacing = scaled(8)         // 8 → 10
    static let rowVPadding = scaled(4)      // 4 → 5
    static let rowHPadding = scaled(6)      // 6 → 8
    static let reminderVPadding = scaled(3) // 3 → 4
    static let rowSpacing = scaled(6)       // 6 → 8
    static let sectionLabel = scaled(10)    // 10 → 13：區塊標題，比內容小一階
    static let labelGap = scaled(2)         // 標題與該列之間
    static let sectionGap = scaled(12)      // 行程區塊與提醒之間的區隔
    static let textSpacing = scaled(1)      // 1 → 1
}

/// 收合模式那一列行程的狀態。
enum FeaturedEvent: Equatable {
    case inProgress(EventItem)
    case upcoming(EventItem)

    var event: EventItem {
        switch self {
        case .inProgress(let event), .upcoming(let event): event
        }
    }

    /// 區塊標題。收合後只有一列，要讓使用者一眼看出是「現在」還是「等一下」
    var label: String {
        switch self {
        case .inProgress: "正在進行中"
        case .upcoming: "即將到來"
        }
    }
}

/// 收合模式的內容（PLAN §4.10）：只有「正在進行的行程」與「第一筆提醒」兩列。
///
/// 跟完整模式一樣不認識 `AgendaStore`，所有互動都是注入的 closure。
struct CollapsedCardView: View {
    let eventsState: SectionState<EventItem>
    let remindersState: SectionState<ReminderItem>
    let pendingIDs: Set<String>
    /// 勾選寫入失敗的訊息。收合模式共用同一條 1.2 秒延遲寫入路徑，
    /// 不顯示失敗原因的話使用者會分不清是寫入失敗還是自己取消了
    var errorMessage: String?
    let now: Date
    let onOpenEvent: (EventItem) -> Void
    let onToggleReminder: (ReminderItem) -> Void
    let onOpenReminder: (ReminderItem) -> Void
    let onOpenCalendarSettings: () -> Void
    let onOpenReminderSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CollapsedMetrics.sectionGap) {
            eventRow
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: CollapsedMetrics.detailSize))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .allowsHitTesting(false)
            }
            reminderRow
        }
    }

    // MARK: - 行程那一列

    @ViewBuilder
    private var eventRow: some View {
        switch eventsState {
        case .loading:
            note("載入中…")
        case .needsPermission:
            PermissionPrompt(message: "需要行事曆存取權限",
                             fontSize: CollapsedMetrics.detailSize,
                             openSettings: onOpenCalendarSettings)
        case .failed(let message):
            note(message)
        case .loaded(let items, _):
            if let featured = Self.featured(in: items, now: now) {
                VStack(alignment: .leading, spacing: CollapsedMetrics.labelGap) {
                    sectionLabel(featured.label)
                    CollapsedEventRow(event: featured.event,
                                      now: now,
                                      onOpen: { onOpenEvent(featured.event) })
                }
            } else {
                note("今天沒有行程")
            }
        }
    }

    /// 區塊標題。純顯示，關掉 hit testing 讓下層拖曳區吃到點擊
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: CollapsedMetrics.sectionLabel, weight: .semibold))
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }

    /// 收合模式那一列要顯示哪一筆行程，以及它是什麼狀態（PLAN §4.10）。
    ///
    /// 先找正在進行的；沒有就退而顯示今天接下來最近的一筆。
    /// 2026-09-21 需求變更前，沒有進行中的行程時只顯示「目前沒有行程」，
    /// 但行程之間的空檔佔了一天大半時間，那樣等於浪費掉兩列中的一列。
    ///
    /// 回傳列舉而非單純的 `EventItem`，是因為標題要據此顯示「正在進行中」或「即將到來」——
    /// 收合後只有一列，不標示的話使用者看不出那是現在還是等一下（使用者 2026-09-21 回報）。
    static func featured(in items: [EventItem], now: Date) -> FeaturedEvent? {
        if let ongoing = inProgressEvent(in: items, now: now) {
            return .inProgress(ongoing)
        }
        if let upcoming = upcomingEvent(in: items, now: now) {
            return .upcoming(upcoming)
        }
        return nil
    }

    /// 現在正在進行的行程。同時有多筆時，有時間的優先於整天行程——
    /// 使用者要的是「當前時間區間」，整天行程沒有那個語意。
    static func inProgressEvent(in items: [EventItem], now: Date) -> EventItem? {
        let ongoing = items.filter { $0.start <= now && now < $0.end }
        return ongoing.first { !$0.isAllDay } ?? ongoing.first
    }

    /// 今天接下來最近的一筆。
    ///
    /// `items` 已由 `AgendaStore` 依開始時間排序，所以取第一筆符合的就是最近的。
    /// 涵蓋 `now` 的整天行程會先被 `inProgressEvent` 取走，不會走到這裡。
    static func upcomingEvent(in items: [EventItem], now: Date) -> EventItem? {
        items.filter { $0.start > now }.min { $0.start < $1.start }
    }

    // MARK: - 提醒那一列

    @ViewBuilder
    private var reminderRow: some View {
        switch remindersState {
        case .loading:
            note("載入中…")
        case .needsPermission:
            PermissionPrompt(message: "需要提醒事項存取權限",
                             fontSize: CollapsedMetrics.detailSize,
                             openSettings: onOpenReminderSettings)
        case .failed(let message):
            note(message)
        case .loaded(let items, _):
            if let reminder = items.first {
                CollapsedReminderRow(reminder: reminder,
                                     isPending: pendingIDs.contains(reminder.id),
                                     now: now,
                                     onToggle: { onToggleReminder(reminder) },
                                     onOpen: { onOpenReminder(reminder) })
            } else {
                note("今天沒有待辦事項 🎉")
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: CollapsedMetrics.detailSize))
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }
}

/// 收合模式的行程列。外觀與完整模式一致，只是不受 6 筆上限與分組影響。
private struct CollapsedEventRow: View {
    let event: EventItem
    let now: Date
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: CollapsedMetrics.hSpacing) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(nsColor: event.color))
                .frame(width: CollapsedMetrics.barWidth)
            VStack(alignment: .leading, spacing: CollapsedMetrics.textSpacing) {
                Text(event.title)
                    .font(.system(size: CollapsedMetrics.titleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(Formatting.eventTimeLabel(for: event, now: now))
                    .font(.system(size: CollapsedMetrics.detailSize))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, CollapsedMetrics.rowVPadding)
        .padding(.horizontal, CollapsedMetrics.rowHPadding)
        .background(
            RoundedRectangle(cornerRadius: CollapsedMetrics.rowCorner, style: .continuous)
                .fill(Color(nsColor: event.color).opacity(isHovering ? 0.22 : 0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: CollapsedMetrics.rowCorner, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onOpen)
    }
}

/// 收合模式的提醒列。勾選行為與完整模式共用同一條路徑（1.2 秒延遲寫入）。
private struct CollapsedReminderRow: View {
    let reminder: ReminderItem
    let isPending: Bool
    let now: Date
    let onToggle: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: CollapsedMetrics.hSpacing) {
            Button(action: onToggle) {
                Image(systemName: isPending ? "inset.filled.circle" : "circle")
                    .font(.system(size: CollapsedMetrics.circleSize))
                    .foregroundStyle(Color(nsColor: reminder.color))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isPending ? "已勾選（僅緩衝期間可再點一次取消）" : "標記完成")

            VStack(alignment: .leading, spacing: CollapsedMetrics.textSpacing) {
                Text(reminder.title)
                    .font(.system(size: CollapsedMetrics.titleSize))
                    .strikethrough(isPending)
                    .foregroundStyle(isPending ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if let due = Formatting.reminderDueLabel(for: reminder, now: now) {
                    Text(due)
                        .font(.system(size: CollapsedMetrics.detailSize))
                        .foregroundStyle(Formatting.isOverdue(reminder, now: now)
                                         ? Color.red : Color.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Spacer(minLength: 0)
        }
        .padding(.vertical, CollapsedMetrics.reminderVPadding)
        .padding(.horizontal, CollapsedMetrics.rowHPadding)
        .background(
            RoundedRectangle(cornerRadius: CollapsedMetrics.rowCorner, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .onHover { isHovering = $0 }
    }
}
