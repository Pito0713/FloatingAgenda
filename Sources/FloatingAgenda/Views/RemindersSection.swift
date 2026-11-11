import SwiftUI

/// 提醒區（PLAN §4.4）。只顯示逾期與今天到期，**全部列出**，分成「逾期」「今天」兩組。
///
/// 2026-11-10 起展開的卡片是看詳情的地方（使用者要求）：拿掉 6 筆上限，
/// 每列多顯示清單名稱、優先順序、相對時間（逾期 3 天）與備註第一行。
///
/// 勾選與開啟都用 callback 注入，View 本身不認識 AgendaStore——
/// 這讓 `--snapshot` 能傳空實作，**結構上不可能誤觸寫入路徑**。
struct RemindersSection: View {
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
        return items.map(\.id)
    }

    private var header: some View {
        HStack {
            Text("提醒事項")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if case .loaded(_, let total) = state, total > 0 {
                Text("\(total) 項")
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
        case .loaded(let items, _):
            if items.isEmpty {
                note("今天沒有待辦事項 🎉")
            } else {
                let overdue = items.filter { Formatting.isOverdue($0, now: now) }
                let today = items.filter { !Formatting.isOverdue($0, now: now) }
                VStack(alignment: .leading, spacing: 6) {
                    group("逾期", overdue, tint: .red)
                    group("今天", today, tint: .secondary)
                }
            }
        }
    }

    /// 一組（逾期／今天）。空的那組整個不畫，連小標題一起
    @ViewBuilder
    private func group(_ title: String, _ items: [ReminderItem], tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(title) \(items.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
                ForEach(items) { reminder in
                    ReminderRow(reminder: reminder,
                                isPending: pendingIDs.contains(reminder.id),
                                now: now,
                                onToggle: { onToggle(reminder) },
                                onOpen: { onOpen(reminder) })
                        .transition(.opacity)
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

/// 單一提醒列：圓圈按鈕 ＋ 標題（優先順序、清單名稱）＋ 到期 · 相對時間 ＋ 備註。
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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let mark = Formatting.priorityMark(reminder.priority) {
                        Text(mark)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(nsColor: reminder.color))
                    }
                    Text(reminder.title)
                        .font(.system(size: 13))
                        .strikethrough(isPending)
                        .foregroundStyle(isPending ? Color.secondary : Color.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if !reminder.listTitle.isEmpty {
                        Text(reminder.listTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: reminder.color))
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }
                if let due = dueText {
                    Text(due)
                        .font(.system(size: 11))
                        .foregroundStyle(Formatting.isOverdue(reminder, now: now)
                                         ? Color.red : Color.secondary)
                }
                if let note = reminder.note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
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

    /// 11月7日 14:30 · 逾期 3 天
    private var dueText: String? {
        let parts = [Formatting.reminderDueLabel(for: reminder, now: now),
                     Formatting.reminderRelative(for: reminder, now: now)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
