import SwiftUI

/// 行程區（PLAN §4.3）。只顯示今天，**全部列出**。
///
/// 2026-11-10 起展開的卡片是「看詳情」的地方（收合模式才負責精簡，使用者要求）：
/// 拿掉 6 筆上限、每列多顯示長度與行事曆名稱；今天沒有行程時預告明天的行程。
/// 放不下就整張卡捲動（`WidgetView.maxContentHeight`）
struct EventsSection: View {
    let state: SectionState<EventItem>
    /// 明天的行程，只在今天沒有行程時顯示
    var tomorrow: [EventItem] = []
    let now: Date
    let onOpen: (EventItem) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        switch state {
        case .loading:
            note("載入中…")
        case .needsPermission:
            PermissionPrompt(message: "需要行事曆存取權限", openSettings: onOpenSettings)
        case .failed(let message):
            note(message)
        case .loaded(let items, _):
            if items.isEmpty {
                emptyToday
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { event in
                        EventRow(event: event, now: now, onOpen: { onOpen(event) })
                    }
                }
            }
        }
    }

    /// 今天空著時先講明天：晚上打開卡片，最想知道的通常是明天第一件事幾點
    @ViewBuilder
    private var emptyToday: some View {
        if tomorrow.isEmpty {
            note("今天沒有行程")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                note("今天沒有行程 · 明天 \(tomorrow.count) 個行程")
                ForEach(tomorrow) { event in
                    EventRow(event: event, now: now, dayPrefix: "明天",
                             onOpen: { onOpen(event) })
                        .opacity(0.75)
                }
            }
        }
    }

    /// 純顯示文字：關掉 hit testing，讓下層的拖曳區吃到點擊
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }
}

/// 單一行程列：左側行事曆色條 ＋ 標題 ＋ 時間 · 長度 · 行事曆。滑過變深、點一下開行事曆 App。
private struct EventRow: View {
    let event: EventItem
    let now: Date
    /// 明天的行程在時間前面加「明天」，免得跟今天的搞混
    var dayPrefix: String?
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(nsColor: event.color))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text([dayPrefix, Formatting.eventDetail(for: event, now: now)]
                        .compactMap { $0 }.joined(separator: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: event.color).opacity(isHovering ? 0.22 : 0.12))
        )
        // 整列都可點，不是只有文字
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onOpen)
    }
}
