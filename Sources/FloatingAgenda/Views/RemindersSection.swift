import SwiftUI

/// 提醒區（PLAN §4.4）。只顯示逾期與今天到期，最多 6 筆。
///
/// 勾選與開啟都用 callback 注入，View 本身不認識 AgendaStore——
/// 這讓 `--snapshot` 能傳空實作，**結構上不可能誤觸寫入路徑**。
struct RemindersSection: View {
    static let displayLimit = EventsSection.displayLimit

    let state: SectionState<ReminderItem>
    /// 顯示為已勾選的提醒，涵蓋緩衝期與寫入成功後等待 refresh 移除的期間
    let pendingIDs: Set<String>
    /// 單筆勾選寫入失敗的訊息。顯示在清單上方，清單本身保留——
    /// 否則其他還在緩衝期的提醒會連取消入口一起消失
    var errorMessage: String?
    let now: Date
    let onToggle: (ReminderItem) -> Void
    let onOpen: (ReminderItem) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .allowsHitTesting(false)
            }
            content
        }
        // 動畫掛在最外層：最後一筆被勾掉時是「清單分支 → 空狀態分支」的切換，
        // 掛在清單分支內部的動畫會跟著那個分支一起被移除，最後一列就不會淡出
        .animation(.easeOut(duration: 0.25), value: visibleIDs)
    }

    /// 目前畫面上那幾列的 id，當作動畫的觸發值
    private var visibleIDs: [String] {
        guard case .loaded(let items, _) = state else { return [] }
        return items.prefix(Self.displayLimit).map(\.id)
    }

    private var header: some View {
        HStack {
            Text("提醒事項")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if case .loaded(_, let total) = state {
                // 是符合範圍的全部數量，不是畫面上那 6 筆
                Text("\(total)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            note("載入中…")
        case .needsPermission:
            PermissionPrompt(message: "需要提醒事項存取權限", openSettings: onOpenSettings)
        case .failed(let message):
            note(message)
        case .loaded(let items, let total):
            if items.isEmpty {
                note("今天沒有待辦事項 🎉")
            } else {
                let shown = Array(items.prefix(Self.displayLimit))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { reminder in
                        ReminderRow(reminder: reminder,
                                    isPending: pendingIDs.contains(reminder.id),
                                    now: now,
                                    onToggle: { onToggle(reminder) },
                                    onOpen: { onOpen(reminder) })
                            .transition(.opacity)
                    }
                    if total > Self.displayLimit {
                        note("還有 \(total - Self.displayLimit) 項")
                            .padding(.leading, 30)
                    }
                }

            }
        }
    }

    /// 純顯示文字：關掉 hit testing，讓下層拖曳區吃到點擊
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }
}

/// 單一提醒列：圓圈按鈕 ＋ 標題 ＋ 到期。
/// 點圓圈＝勾選（延遲寫入），點標題＝開提醒事項 App。
private struct ReminderRow: View {
    let reminder: ReminderItem
    let isPending: Bool
    let now: Date
    let onToggle: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isPending ? "inset.filled.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(nsColor: reminder.color))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isPending ? "已勾選（僅緩衝期間可再點一次取消）" : "標記完成")

            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title)
                    .font(.system(size: 13))
                    .strikethrough(isPending)
                    .foregroundStyle(isPending ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if let due = Formatting.reminderDueLabel(for: reminder, now: now) {
                    Text(due)
                        .font(.system(size: 11))
                        .foregroundStyle(Formatting.isOverdue(reminder, now: now)
                                         ? Color.red : Color.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .onHover { isHovering = $0 }
    }
}
