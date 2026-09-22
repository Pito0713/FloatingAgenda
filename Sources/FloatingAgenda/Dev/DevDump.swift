import AppKit
import EventKit
import Foundation

/// `--dump`：用跟 App 一樣的 store 邏輯把資料印成純文字。
/// **只讀，不寫入任何行事曆或提醒。**
@MainActor
enum DevDump {
    static func run() async -> Int32 {
        _ = NSApplication.shared

        let store = AgendaStore()
        await store.start()

        print("授權狀態")
        print("  行事曆　　：\(describe(EKEventStore.authorizationStatus(for: .event)))")
        print("  提醒事項　：\(describe(EKEventStore.authorizationStatus(for: .reminder)))")
        print("")

        printCalendarSection("行事曆（\(store.calendars.count)）", store.calendars)
        printCalendarSection("提醒清單（\(store.reminderLists.count)）", store.reminderLists)

        print("今天的行程")
        switch store.eventsState {
        case .loading:
            print("  （尚未載入）")
        case .needsPermission:
            print("  ⚠️ 需要行事曆存取權限")
        case .failed(let message):
            print("  ❌ \(message)")
        case .loaded(let items, let total):
            print("  共 \(total) 筆")
            for item in items {
                let day = Formatting.dateTitle(for: item.start)
                let time = Formatting.eventTimeLabel(for: item, now: Date())
                print("  · \(day) \(time)　\(item.title)")
                print("      eventIdentifier=\(item.eventIdentifier ?? "（無，無法深層連結）")")
            }
        }
        print("")

        print("今天的提醒（逾期 ＋ 今天到期）")
        // fetchReminders 是非同步回來的，start() 之後可能還沒到
        await waitForReminders(store)
        switch store.remindersState {
        case .loading:
            print("  （等待逾時，尚未載入）")
        case .needsPermission:
            print("  ⚠️ 需要提醒事項存取權限")
        case .failed(let message):
            print("  ❌ \(message)")
        case .loaded(let items, let total):
            print("  共 \(total) 筆")
            for item in items {
                let due: String
                if let date = item.due {
                    due = item.dueHasTime
                        ? "\(Formatting.dateTitle(for: date)) \(Formatting.timeString(for: date))"
                        : Formatting.dateTitle(for: date)
                } else {
                    due = "無到期日"
                }
                print("  · [\(due)]　\(item.title)")
                print("      calendarItemIdentifier=\(item.id)")
            }
        }

        return 0
    }

    private static func printCalendarSection(_ title: String, _ infos: [CalendarInfo]) {
        print(title)
        if infos.isEmpty {
            print("  （沒有資料，可能是沒有權限）")
        }
        for info in infos {
            let hidden = info.isHidden ? "隱藏" : "顯示"
            print("  · [\(hidden)] \(info.title)　來源=\(info.sourceTitle)　id=\(info.id)")
        }
        print("")
    }

    /// 最多等 5 秒
    private static func waitForReminders(_ store: AgendaStore) async {
        for _ in 0..<50 {
            if case .loading = store.remindersState {
                try? await Task.sleep(for: .milliseconds(100))
            } else {
                return
            }
        }
    }

    private static func describe(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "尚未詢問"
        case .restricted: "受限制"
        case .denied: "已拒絕"
        case .fullAccess: "完整存取 ✅"
        case .writeOnly: "僅可寫入（等同沒有讀取權限）"
        @unknown default: "未知（\(status.rawValue)）"
        }
    }
}
