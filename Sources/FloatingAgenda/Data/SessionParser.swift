import Foundation

/// `latest.md` → `ProjectItem`。
///
/// **純函式，不碰檔案系統**：讀檔是 `ProjectStore` 的事，這裡只處理字串。
/// 這樣切開是為了讓格式容錯的每一條規則都能用單元測試釘住，不必準備真實檔案。
///
/// 交接文件由 handoff skill 產生，格式之後可能漂移（M9 計畫 §9），
/// 所以每個欄位缺少時都有預設值，**絕不讓整個專案從清單裡消失**——
/// 唯一會回傳 `nil` 的情況是標題標示「已搬遷」。
enum SessionParser {

    /// - Returns: 標題含「已搬遷」時回 `nil`（那個目錄要整個略過）
    static func parse(directoryName: String, text: String, fileURL: URL) -> ProjectItem? {
        let lines = normalizedLines(text)
        let heading = headingText(in: lines)

        // 已搬遷的專案整份略過（實例：FloatingAgenda → Floating）
        if let heading, heading.contains("已搬遷") { return nil }

        let statusText = field("狀態", in: lines) ?? ""
        let counted = todos(in: lines)

        return ProjectItem(id: directoryName,
                           name: heading?.isEmpty == false ? heading! : directoryName,
                           status: status(from: statusText),
                           statusText: statusText,
                           updated: updatedDate(from: field("最後更新", in: lines)),
                           done: counted.done,
                           total: counted.total,
                           openTodos: counted.open,
                           blocker: blocker(in: lines),
                           fileURL: fileURL)
    }

    // MARK: - 前處理

    /// 去掉開頭的 BOM、把 CRLF 與單獨的 CR 都收斂成 LF，再切行。
    /// 這三件事不做的話，`hasPrefix("# ")` 之類的比對會在真實檔案上莫名失敗。
    private static func normalizedLines(_ text: String) -> [String] {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        body = body.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")
        return body.components(separatedBy: "\n")
    }

    private static func headingText(in lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("# ") else { continue }
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// 取 `> <label>：<值>`。容許 `>` 前後有空白，也容許用半形 `:`（§5.2）
    private static func field(_ label: String, in lines: [String]) -> String? {
        for line in lines {
            var rest = line.trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix(">") else { continue }
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix(label) else { continue }
            rest = String(rest.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("：") || rest.hasPrefix(":") else { continue }
            let value = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    // MARK: - 各欄位

    /// 同時出現多個燈號時取最嚴重的那個——寧可把狀況講得比實際嚴重，
    /// 也不要讓一個紅燈專案在清單裡看起來沒事
    private static func status(from text: String) -> ProjectStatus {
        if text.contains("🔴") { return .red }
        if text.contains("🟡") { return .yellow }
        if text.contains("🟢") { return .green }
        return .unknown
    }

    /// 只認 `yyyy-MM-dd HH:mm`，用目前時區解析。
    /// 用搜尋而非整串比對，這樣「2026-09-18 15:20（補寫）」這種也讀得到
    private static func updatedDate(from text: String?) -> Date? {
        guard let text else { return nil }
        guard let match = text.range(of: #"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}"#,
                                     options: .regularExpression) else { return nil }
        let stamp = text[match].replacingOccurrences(of: "T", with: " ")
        return updatedFormatter.date(from: stamp)
    }

    /// `en_US_POSIX` 是刻意的：格式字串是固定的機器格式，
    /// 不能讓使用者的地區設定（例如民國年）改變解析結果
    private static let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// 打勾項目只算 `## 進行中` 這一段；找不到這段才退回整份檔案（§5.2）
    private static func todos(in lines: [String]) -> (done: Int, total: Int, open: [String]) {
        let scope = section("進行中", in: lines) ?? lines
        var done = 0
        var open: [String] = []
        for line in scope {
            guard let box = checkbox(line) else { continue }
            if box.done { done += 1 } else { open.append(box.text) }
        }
        return (done, done + open.count, open)
    }

    /// `- [x]` / `- [X]` 算完成，`- [ ]` 算未完成。縮排的子項目也算（先 trim）。
    /// 清單符號同時接受 `-` 與 `*`：格式漂移時不該讓整份待辦歸零
    private static func checkbox(_ line: String) -> (done: Bool, text: String)? {
        var rest = line.trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("- ") || rest.hasPrefix("* ") else { return nil }
        rest = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard rest.count >= 3, rest.hasPrefix("[") else { return nil }

        let mark = rest[rest.index(rest.startIndex, offsetBy: 1)]
        guard rest[rest.index(rest.startIndex, offsetBy: 2)] == "]" else { return nil }
        let text = clean(String(rest.dropFirst(3)))

        switch mark {
        case "x", "X": return (true, text)
        case " ": return (false, text)
        default: return nil
        }
    }

    /// 拿掉 markdown 的粗體與 code 符號，UI 上才不會出現星號和反引號
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func blocker(in lines: [String]) -> String? {
        guard let scope = section("卡住的點", in: lines) else { return nil }

        // 取第一段（連續的非空行），支援 §4.5 的「最多 2 行」顯示
        var paragraph: [String] = []
        for line in scope {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if paragraph.isEmpty { continue } else { break }
            }
            paragraph.append(trimmed)
        }
        guard !paragraph.isEmpty else { return nil }

        let text = clean(paragraph.joined(separator: " "))
        return isNoBlocker(text) ? nil : text
    }

    /// 「無」、「無。」、「無（上述…是待查證，不是卡住）」都算沒有卡住。
    ///
    /// ⚠️ 計畫 §5.2 的字面規則是「以『無』開頭 → nil」，但那會把
    /// **「無法連線到 API」這種真的卡住的描述誤判成沒卡住**。
    /// 「無○○，但還有一件事要處理」這種寫法在實務上很常見，
    /// 照字面規則會讓它整條消失。
    ///
    /// 所以判準是：整段**以「無」開頭**，而且「無」後面除了括號裡的補充說明
    /// 與結尾標點之外**什麼都不剩**，才算沒有卡住。
    ///
    /// 括號只在緊接著「無」時才視為補充說明。早期版本是「砍掉第一個括號之後的全部內容」，
    /// 那會讓「（後端）API 無法連線」整句被砍成空字串而誤判成沒卡住
    /// （codex 2026-09-22 指出）。
    private static func isNoBlocker(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        guard trimmed.hasPrefix("無") else { return false }

        var rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("（") || rest.hasPrefix("(") { rest = "" }
        rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " 　。.、,;；!！~～-—"))
        return rest.isEmpty
    }

    /// 取 `## <name>` 到下一個 `## ` 之間的內容。找不到這個區段回 `nil`
    private static func section(_ name: String, in lines: [String]) -> [String]? {
        guard let start = lines.firstIndex(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("## ")
                && String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces) == name
        }) else { return nil }

        var body: [String] = []
        for line in lines[(start + 1)...] {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("## ") { break }
            body.append(line)
        }
        return body
    }
}
