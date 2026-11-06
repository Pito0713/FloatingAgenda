import AppKit
import EventKit
import Foundation

/// `--events-to-reminders`：手動跑一次「今天的行程 → 提醒」。
/// ⚠️ 不加 `--dry-run` 會**真的寫入**提醒事項。
@MainActor
enum EventsToReminders {
    static func run(dryRun: Bool) async -> Int32 {
        _ = NSApplication.shared
        let sync = EventKitEventReminderSync(store: EKEventStore(), settings: .shared)
        do {
            let result = try await sync.run(dryRun: dryRun)
            let verb = dryRun ? "將建立" : "已建立"
            print("\(verb) \(result.created.count) 筆提醒到「\(result.listTitle)」，略過已轉過的 \(result.skipped) 筆")
            for draft in result.created {
                let due = draft.due.hour == nil
                    ? "整天"
                    : String(format: "%02d:%02d", draft.due.hour ?? 0, draft.due.minute ?? 0)
                print("  · [\(due)]　\(draft.title)")
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("❌ \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
