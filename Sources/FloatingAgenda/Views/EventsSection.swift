import SwiftUI

/// 行程區（PLAN §4.3）。只顯示今天，最多 6 筆，超過在最後一行收斂成「還有 N 個行程」。
struct EventsSection: View {
    /// 最多顯示幾筆
    static let displayLimit = 6

    let state: SectionState<EventItem>
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
        case .loaded(let items, let total):
            if items.isEmpty {
                note("今天沒有行程")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items.prefix(Self.displayLimit)) { event in
                        EventRow(event: event, now: now, onOpen: { onOpen(event) })
                    }
                    if total > Self.displayLimit {
                        note("還有 \(total - Self.displayLimit) 個行程")
                            .padding(.leading, 6)
                    }
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

/// 單一行程列：左側行事曆色條 ＋ 標題 ＋ 時間。滑過變深、點一下開行事曆 App。
private struct EventRow: View {
    let event: EventItem
    let now: Date
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
                Text(Formatting.eventTimeLabel(for: event, now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
