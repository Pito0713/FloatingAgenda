import EventKit
import Foundation

/// `AgendaStore` 把提醒標記為已完成所需的最小介面。
///
/// 抽出這層的唯一理由是**讓勾選這條路徑能被測試**。它是整個專案唯一會寫入使用者資料
/// 的地方，而它周邊的取消與清理邏輯已經有過四次漏洞
/// （見 `docs/code-review-20260918.md`：M4 一次、全專案 review 兩條、複審一條）。
/// `PLAN.md` §8 禁止在開發與驗證過程中寫入使用者的行事曆或提醒資料，
/// 所以測試注入一個只記錄呼叫的替身，真實寫入完全不會發生。
protocol ReminderWriter {
    /// 把提醒標記為已完成。找不到該筆時丟 `ReminderWriteError.notFound`。
    func markCompleted(id: String) throws
}

enum ReminderWriteError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: "找不到這筆提醒，可能已被刪除"
        }
    }
}

/// ⚠️ **這是整個專案唯一會寫入使用者資料的型別。**
///
/// 刻意做得極小且不含任何判斷邏輯——要不要寫入、什麼時候寫入，全部由
/// `AgendaStore.toggleCompletion` / `commitCompletion` 的守衛決定，那些才是有測試保護的部分。
struct EventKitReminderWriter: ReminderWriter {
    let store: EKEventStore

    func markCompleted(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw ReminderWriteError.notFound
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }
}
