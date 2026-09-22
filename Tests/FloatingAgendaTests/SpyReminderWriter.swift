import Foundation
@testable import FloatingAgenda

/// 只記錄呼叫、絕不真的寫入的 `ReminderWriter` 替身。
///
/// 存在的理由：`PLAN.md` §8 禁止在開發與驗證過程中寫入使用者的行事曆或提醒資料。
/// 有了它，「什麼情況下該寫、什麼情況下絕對不能寫」就能被測試直接驗證，
/// 而不必真的去動任何一筆真實提醒。
final class SpyReminderWriter: ReminderWriter {
    /// 被要求標記完成的 id，依呼叫順序
    private(set) var markedIDs: [String] = []
    /// 設了就讓 `markCompleted` 丟這個錯誤，用來測寫入失敗的處理
    var errorToThrow: Error?

    var didWriteAnything: Bool { !markedIDs.isEmpty }

    func markCompleted(id: String) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        markedIDs.append(id)
    }
}
