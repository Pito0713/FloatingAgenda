import Foundation

/// Agent_skill 的 project-review 排程寫出來的結果（ADR-032）。
///
/// 來源是 `~/.agent-reports/project-review/<專案>/status.json`，`<專案>` 等於
/// `ProjectItem.id`。排程每天跑一次、整份覆蓋（先寫暫存檔再 rename）。
///
/// ⚠️ **唯讀**：Floating 只讀這個檔，不寫、不搬、不刪。
/// 只留卡片用得到的欄位，其餘欄位（`commit`、`errors` 以外的細節）忽略
struct ReviewStatus: Hashable, Sendable {
    enum Overall: String, Sendable {
        case fail, crash, warn, ok, idle
    }

    let overall: Overall
    let ranAt: Date
    /// L1（test／lint）的結果原文：pass／fail／flaky／crash／none
    let l1Result: String?
    /// L1 失敗的檢查名稱，例如 `["test"]`
    let failedChecks: [String]
    /// 沒有新 commit，沿用上次的結果
    let carried: Bool
    /// L2 ＋ L3 的新發現數
    let newFindings: Int
    /// 交接檔落後幾個 commit；沒有交接檔或算不出來是 nil
    let lagCommits: Int?
    let reportURL: URL?
    /// 第一則錯誤訊息，crash 時顯示
    let firstError: String?
}

/// 卡片上那一行 review 狀態要顯示什麼。純函式，規則見 ADR-032 的 P1.5
enum ReviewStatusDisplay {
    /// `ranAt` 距今超過這麼久就當成排程沒跑（使用者 2026-11-10 選 36 小時）
    static let staleAfter: TimeInterval = 36 * 3600

    enum Tone: Equatable {
        case failure, warning, normal
    }

    struct Line: Equatable {
        let text: String
        let tone: Tone
    }

    /// 優先序：失敗 → 執行錯誤 → 過期 → 注意 → 正常 → 無變更。
    /// 只顯示最嚴重的一個，交接落後附在最後
    static func line(for review: ReviewStatus, now: Date) -> Line {
        let when = Formatting.relativeTime(review.ranAt, now: now)
        let base: Line
        switch review.overall {
        case .fail:
            let checks = review.failedChecks.isEmpty
                ? "" : "（\(review.failedChecks.joined(separator: "、"))）"
            let what = review.l1Result == "fail" ? "測試失敗" : "review 失敗"
            base = Line(text: "🔴 \(what)\(checks) · \(when)", tone: .failure)
        case .crash:
            let detail = review.firstError.map { "：\($0)" } ?? ""
            base = Line(text: "💥 review 執行失敗\(detail) · \(when)", tone: .failure)
        case _ where now.timeIntervalSince(review.ranAt) > staleAfter:
            base = Line(text: "⏳ 上次 review \(ago(review.ranAt, now: now))", tone: .warning)
        case .warn:
            var parts: [String] = []
            if review.l1Result == "flaky" { parts.append("測試不穩定") }
            if review.newFindings > 0 { parts.append("\(review.newFindings) 新發現") }
            if parts.isEmpty { parts.append("需要注意") }
            base = Line(text: "⚠️ \(parts.joined(separator: "、")) · \(when)", tone: .warning)
        case .ok:
            let carried = review.carried ? "（沒有新 commit，沿用上次）" : ""
            base = Line(text: "✅ review 正常\(carried) · \(when)", tone: .normal)
        case .idle:
            base = Line(text: "💤 沒有變更 · \(when)", tone: .normal)
        }
        guard let lag = review.lagCommits, lag > 0 else { return base }
        return Line(text: "\(base.text) · 交接落後 \(lag) commits", tone: base.tone)
    }

    /// 3 天前／5 小時前
    static func ago(_ date: Date, now: Date) -> String {
        let hours = Int(now.timeIntervalSince(date) / 3600)
        return hours >= 24 ? "\(hours / 24) 天前" : "\(max(hours, 0)) 小時前"
    }
}

/// 解析 `status.json`。**唯讀**，任何一個必要欄位缺了或格式不對就回 nil（卡片不顯示那一行），
/// 不讓一份壞掉的報告拖垮整個專案區
enum ReviewStatusParser {
    /// status.json 不可能這麼大，超過就略過（同 `ProjectStore.maxFileBytes` 的理由）
    static let maxFileBytes = 64 * 1024

    static func url(for projectID: String, root: URL) -> URL {
        root.appendingPathComponent(projectID, isDirectory: true)
            .appendingPathComponent("status.json", isDirectory: false)
    }

    static func read(projectID: String, root: URL) -> ReviewStatus? {
        let file = url(for: projectID, root: root)
        let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxFileBytes + 1),
              data.count <= maxFileBytes else { return nil }
        return parse(data)
    }

    private struct Raw: Decodable {
        struct Level: Decodable {
            let result: String?
            let failed: [String]?
            let carried: Bool?
            let newFindings: Int?
        }
        struct Handoff: Decodable {
            let lagCommits: Int?
        }
        let ranAt: String?
        let overall: String?
        let l1: Level?
        let l2: Level?
        let l3: Level?
        let handoff: Handoff?
        let reportPath: String?
        let errors: [String]?
    }

    static func parse(_ data: Data) -> ReviewStatus? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data),
              let overall = raw.overall.flatMap(ReviewStatus.Overall.init(rawValue:)),
              let ranAt = raw.ranAt.flatMap(date(from:)) else { return nil }
        return ReviewStatus(
            overall: overall,
            ranAt: ranAt,
            l1Result: raw.l1?.result,
            failedChecks: raw.l1?.failed ?? [],
            carried: raw.l1?.carried ?? false,
            newFindings: (raw.l2?.newFindings ?? 0) + (raw.l3?.newFindings ?? 0),
            lagCommits: raw.handoff?.lagCommits,
            reportURL: raw.reportPath.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
            firstError: raw.errors?.first.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// `2026-11-10T10:30:08+08:00`，也接受帶小數秒的寫法
    static func date(from text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
