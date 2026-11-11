import SwiftUI

/// 排程區（使用者 2026-10-12 要求）：自己設的 launchd 排程，一個一列。
///
/// 沒有排程、還在讀、讀不到時**整塊不存在**——同完整模式的專案區，
/// 沒設過排程的人卡片下面不該多掛一行字。
/// 這個 View 不認識 `ScheduleStore`，狀態與互動都是注入的。
///
/// 2026-11-10 起全部列出（原本最多 4 個），每列分成「觸發規則 · 下次執行」與
/// 「執行狀態（PID／上次結束代碼）」兩行——展開的卡片是看詳情的地方（使用者要求）
struct SchedulesSection: View {

    let state: SectionState<ScheduleItem>
    let now: Date
    /// 有設定點擊指令的排程（`AppSettings.scheduleOpenCommands`）。
    /// 這些列的右邊會多一個箭頭，讓人知道點了會開東西而不是開 log
    var actionableIDs: Set<String> = []
    /// 點一列：有指令跑指令，沒有就開 log。snapshot 傳空實作
    var onOpen: (ScheduleItem) -> Void = { _ in }

    var body: some View {
        if case .loaded(let items, let total) = state, !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // 分隔線跟著整塊一起消失，理由同 ProjectsSection.container
                Divider()
                    .padding(.bottom, 2)
                    .allowsHitTesting(false)
                HStack {
                    Text("排程")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(total) 個")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        ScheduleRow(item: item, now: now,
                                    isActionable: actionableIDs.contains(item.id),
                                    onOpen: { onOpen(item) })
                    }
                }
            }
        }
    }
}

private struct ScheduleRow: View {
    let item: ScheduleItem
    let now: Date
    let isActionable: Bool
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Formatting.scheduleTiming(for: item, now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(Formatting.scheduleRunStatus(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(isFailed ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isActionable {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onOpen)
        .help(isActionable ? "開啟排程資料" : (item.logURL == nil ? "打開設定檔" : "打開 log"))
    }

    private var isFailed: Bool {
        if case .idle(let exit?) = item.run, exit != 0 { return true }
        return false
    }

    private var dotColor: Color {
        switch item.run {
        case .running: .blue
        case .notLoaded: .gray
        case .idle(let exit?) where exit != 0: .red
        case .idle: .green
        }
    }
}

extension Formatting {
    /// 排程列的第二行：
    /// - 執行中 · 平日 16:30
    /// - 上次失敗（代碼 1）· 下次 明天 16:30
    /// - 未載入 · 平日 16:30
    /// - 平日 16:30 · 下次 今天 16:30
    static func scheduleDetail(for item: ScheduleItem, now: Date) -> String {
        let rule = LaunchSchedule.describe(item.trigger)
        let next = LaunchSchedule.nextRun(item.trigger, after: now).map { "下次 \(relativeTime($0, now: now))" }
        switch item.run {
        case .running:
            return "執行中 · \(rule)"
        case .notLoaded:
            return "未載入 · \(rule)"
        case .idle(let exit?) where exit != 0:
            return (["上次失敗（代碼 \(exit)）"] + [next ?? rule]).joined(separator: " · ")
        case .idle:
            return ([rule] + [next].compactMap { $0 }).joined(separator: " · ")
        }
    }

    /// 展開卡片排程列的第二行：觸發規則 · 下次執行
    /// - 平日 16:30 · 下次 今天 16:30
    /// - 不定時
    static func scheduleTiming(for item: ScheduleItem, now: Date) -> String {
        let next = LaunchSchedule.nextRun(item.trigger, after: now).map { "下次 \(relativeTime($0, now: now))" }
        return ([LaunchSchedule.describe(item.trigger)] + [next].compactMap { $0 })
            .joined(separator: " · ")
    }

    /// 展開卡片排程列的第三行：執行狀態
    static func scheduleRunStatus(for item: ScheduleItem) -> String {
        switch item.run {
        case .running(let pid): "執行中 · PID \(pid)"
        case .notLoaded: "未載入（launchd 裡找不到）"
        case .idle(nil): "已載入 · 還沒跑完過"
        case .idle(0?): "上次結束 ✅ 正常"
        case .idle(let exit?): "上次結束 ❌ 失敗（代碼 \(exit)）"
        }
    }

    /// 今天 16:30／明天 16:30／10月14日 16:30
    static func relativeTime(_ date: Date, now: Date) -> String {
        let time = timeString(for: date)
        if calendar.isDate(date, inSameDayAs: now) { return "今天 \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "明天 \(time)" }
        return "\(dateTitle(for: date)) \(time)"
    }
}
