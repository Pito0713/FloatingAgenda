import Foundation

/// 使用者自己設的 launchd 排程（使用者 2026-10-12 要求）。
///
/// **哪些算「自己的」**：`~/Library/LaunchAgents` 底下、Label 以 `local.` 開頭的那些。
/// App 自動安裝的項目一律用自家的反向網域（`com.google.…`、`com.epicgames.…`），
/// 不會用 `local.`，所以這個前綴就是「我自己設的」的約定。之後新增排程照這個前綴命名就會出現。
///
/// **唯讀**：只讀 plist、只跑 `launchctl print`。不 load、不 kickstart、不改任何檔案。
struct ScheduleItem: Identifiable, Hashable, Sendable {
    /// launchd 的 Label，例如 `local.tw-stock-tracker.update`
    let id: String
    /// 去掉 `local.` 前綴的 Label，UI 直接顯示
    let name: String
    let trigger: ScheduleTrigger
    let run: ScheduleRunState
    /// `StandardOutPath`（沒有就用 `StandardErrorPath`）。點一列時打開它
    let logURL: URL?
    let plistURL: URL
}

/// plist 裡寫的觸發方式
enum ScheduleTrigger: Hashable, Sendable {
    /// `StartCalendarInterval`，一個 slot 對應 plist 裡的一個 dict
    case calendar([CalendarSlot])
    /// `StartInterval`，單位秒
    case interval(Int)
    /// 沒有定時（只有 RunAtLoad、WatchPaths 之類）
    case none
}

/// `StartCalendarInterval` 的一組欄位。缺的欄位在 launchd 裡代表「每一個」。
/// `weekday` 保留 launchd 的原值：0 與 7 都是星期日、1 是星期一
struct CalendarSlot: Hashable, Sendable {
    var month: Int?
    var day: Int?
    var weekday: Int?
    var hour: Int?
    var minute: Int?
}

/// `launchctl print` 讀出來的執行狀態
enum ScheduleRunState: Hashable, Sendable {
    /// launchd 裡找不到這個 Label：plist 在，但沒有被 load
    case notLoaded
    case running(pid: Int)
    /// `lastExit == nil` 代表載入後還沒有跑完過
    case idle(lastExit: Int?)
}

enum LaunchSchedule {
    static let labelPrefix = "local."

    // MARK: - plist

    /// 不是 `local.` 開頭、或沒有 Label 的 plist 回 nil
    static func parse(plist: [String: Any], plistURL: URL)
        -> (label: String, trigger: ScheduleTrigger, logURL: URL?)? {
        guard let label = plist["Label"] as? String, label.hasPrefix(labelPrefix) else {
            return nil
        }
        let trigger: ScheduleTrigger
        if let one = plist["StartCalendarInterval"] as? [String: Any] {
            trigger = .calendar([slot(one)])
        } else if let many = plist["StartCalendarInterval"] as? [[String: Any]], !many.isEmpty {
            trigger = .calendar(many.map(slot))
        } else if let seconds = plist["StartInterval"] as? Int, seconds > 0 {
            trigger = .interval(seconds)
        } else {
            trigger = .none
        }
        let logPath = (plist["StandardOutPath"] as? String) ?? (plist["StandardErrorPath"] as? String)
        return (label, trigger, logPath.map { URL(fileURLWithPath: $0) })
    }

    private static func slot(_ dict: [String: Any]) -> CalendarSlot {
        CalendarSlot(month: dict["Month"] as? Int,
                     day: dict["Day"] as? Int,
                     weekday: dict["Weekday"] as? Int,
                     hour: dict["Hour"] as? Int,
                     minute: dict["Minute"] as? Int)
    }

    // MARK: - launchctl print

    /// 只看最外層（一個 tab 縮排）的 `state`、`pid`、`last exit code`。
    /// 巢狀區塊（`environment = { … }`）裡也可能有同名的字，所以縮排要剛好一層
    static func parseRunState(printOutput text: String) -> ScheduleRunState {
        var state: String?
        var pid: Int?
        var lastExit: Int?
        for line in text.components(separatedBy: "\n") {
            guard line.hasPrefix("\t"), !line.hasPrefix("\t\t") else { continue }
            let parts = line.dropFirst().components(separatedBy: " = ")
            guard parts.count >= 2 else { continue }
            let value = parts[1...].joined(separator: " = ")
            switch parts[0] {
            case "state": state = value
            case "pid": pid = Int(value)
            // 「0」「1」「(never exited)」，也看過「78: Function not implemented」
            case "last exit code": lastExit = Int(value.prefix { $0 == "-" || $0.isNumber })
            default: break
            }
        }
        if state == "running", let pid { return .running(pid: pid) }
        return .idle(lastExit: lastExit)
    }

    // MARK: - 下次執行

    /// 找所有 slot 裡最早的下一次。interval 型的排程沒有固定時刻，回 nil
    static func nextRun(_ trigger: ScheduleTrigger, after date: Date,
                        calendar: Calendar = Formatting.calendar) -> Date? {
        guard case .calendar(let slots) = trigger else { return nil }
        return slots.compactMap { slot in
            calendar.nextDate(after: date,
                              matching: components(slot),
                              matchingPolicy: .nextTime)
        }.min()
    }

    /// launchd 的星期（0/7＝日、1＝一）換成 Foundation 的（1＝日、2＝一）。
    /// 缺 Minute 在 launchd 是「那個小時的每一分鐘」，這裡只算得出整點那一次——
    /// 自己設的排程都會寫分鐘，不為這個少見情況多寫一套比對
    static func components(_ slot: CalendarSlot) -> DateComponents {
        DateComponents(month: slot.month,
                       day: slot.day,
                       hour: slot.hour,
                       minute: slot.minute ?? 0,
                       second: 0,
                       weekday: slot.weekday.map { $0 % 7 + 1 })
    }

    // MARK: - 文案

    /// 「平日 16:30」「每天 08:00」「每週一、三 09:00」「每 60 分鐘」。
    /// 每個 slot 的時刻不同、或有指定月／日時，退回「N 個時段」
    static func describe(_ trigger: ScheduleTrigger) -> String {
        switch trigger {
        case .none:
            return "不定時"
        case .interval(let seconds):
            if seconds % 3600 == 0 { return "每 \(seconds / 3600) 小時" }
            if seconds % 60 == 0 { return "每 \(seconds / 60) 分鐘" }
            return "每 \(seconds) 秒"
        case .calendar(let slots):
            guard let first = slots.first, let hour = first.hour,
                  slots.allSatisfy({ $0.hour == hour && $0.minute == first.minute
                                     && $0.month == nil && $0.day == nil }) else {
                return "\(slots.count) 個時段"
            }
            let time = String(format: "%02d:%02d", hour, first.minute ?? 0)
            let days = slots.map(\.weekday)
            if days.contains(where: { $0 == nil }) { return "每天 \(time)" }
            let set = Set(days.compactMap { $0 }.map { $0 % 7 })   // 7 併進 0
            switch set {
            case Set(0...6): return "每天 \(time)"
            case Set(1...5): return "平日 \(time)"
            case [0, 6]: return "週末 \(time)"
            default:
                let names = ["日", "一", "二", "三", "四", "五", "六"]
                // 星期一排前面、星期日排最後，跟台灣的週曆習慣一致
                let ordered = set.sorted { ($0 + 6) % 7 < ($1 + 6) % 7 }
                return "每週" + ordered.map { names[$0] }.joined(separator: "、") + " \(time)"
            }
        }
    }

    /// 失敗、執行中排前面，其餘照下次執行時間；都一樣用 id 決勝（`sort` 不穩定）
    static func order(_ lhs: ScheduleItem, _ rhs: ScheduleItem, now: Date) -> Bool {
        func rank(_ item: ScheduleItem) -> Int {
            switch item.run {
            case .idle(let exit?) where exit != 0: 0
            case .running: 1
            default: 2
            }
        }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        switch (nextRun(lhs.trigger, after: now), nextRun(rhs.trigger, after: now)) {
        case let (left?, right?) where left != right: return left < right
        case (nil, .some): return false
        case (.some, nil): return true
        default: return lhs.id < rhs.id
        }
    }
}
