import AppKit
import Observation

/// 掃描 `~/Library/LaunchAgents/*.plist`，把 `local.` 開頭的排程變成 `ScheduleItem`。
///
/// ⚠️ **唯讀**：只列目錄、讀 plist、跑 `launchctl print`。
/// 不 load／unload／kickstart，也不碰 plist 與 log——規則同 `ProjectStore`。
@MainActor
@Observable
final class ScheduleStore {
    static let shared = ScheduleStore()

    private(set) var state: SectionState<ScheduleItem> = .loading

    /// LaunchAgent 的 plist 不可能這麼大
    nonisolated static let maxFileBytes = 64 * 1024

    /// 可注入是為了測試：測試指向自己建的暫存目錄，
    /// 並換掉 `launchctl`，**不會讀到使用者真正的排程**
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let runState: @Sendable (String) -> ScheduleRunState

    @ObservationIgnored nonisolated(unsafe)
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    @ObservationIgnored nonisolated(unsafe) private var refreshTimer: Timer?
    @ObservationIgnored private var generation = 0

    init(directory: URL? = nil,
         runState: (@Sendable (String) -> ScheduleRunState)? = nil) {
        self.directory = directory ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        self.runState = runState ?? { Self.launchctlRunState(label: $0) }
    }

    deinit {
        observers.forEach { $0.center.removeObserver($0.token) }
        refreshTimer?.invalidate()
    }

    func start() {
        guard observers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter,
                          workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                      object: nil,
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }))
        // 60 秒重讀：執行中 → 跑完的狀態變化要看得到，同 ProjectStore 的週期
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        refreshTimer = timer
        refresh()
    }

    func refresh() {
        generation += 1
        let generation = self.generation
        let directory = self.directory
        let runState = self.runState
        Task.detached(priority: .utility) {
            let result = Self.scan(directory: directory, now: Date(), runState: runState)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                // 相等性守衛：見 ProjectStore.refresh
                guard self.state != result else { return }
                self.state = result
            }
        }
    }

    // MARK: - 掃描

    nonisolated static func scan(directory: URL,
                                 now: Date,
                                 runState: (String) -> ScheduleRunState)
        -> SectionState<ScheduleItem> {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            // 沒有 LaunchAgents 資料夾就是沒有排程，不是錯誤
            return .loaded(items: [], total: 0)
        }

        var items: [ScheduleItem] = []
        for url in entries where url.pathExtension == "plist" {
            guard let plist = readPlist(url),
                  let parsed = LaunchSchedule.parse(plist: plist, plistURL: url) else { continue }
            items.append(ScheduleItem(
                id: parsed.label,
                name: String(parsed.label.dropFirst(LaunchSchedule.labelPrefix.count)),
                trigger: parsed.trigger,
                run: runState(parsed.label),
                logURL: parsed.logURL,
                plistURL: url))
        }
        items.sort { LaunchSchedule.order($0, $1, now: now) }
        return .loaded(items: items, total: items.count)
    }

    /// 大小上限的作法同 `ProjectStore.read`：開一次檔、最多讀上限 + 1 個位元組
    nonisolated static func readPlist(_ url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxFileBytes + 1),
              data.count <= maxFileBytes else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil))
            as? [String: Any]
    }

    /// `launchctl print gui/<uid>/<label>`。找不到服務時 launchctl 以非 0 結束
    nonisolated static func launchctlRunState(label: String) -> ScheduleRunState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .notLoaded
        }
        // 先讀完再等：輸出塞滿 pipe 緩衝區時，先 wait 會互相卡死
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .notLoaded }
        return LaunchSchedule.parseRunState(printOutput: String(decoding: data, as: UTF8.self))
    }
}

/// 選單列「排程點擊動作」選了一個檔案之後，要怎麼執行它。純函式，方便測試
enum ScheduleCommand {
    static func command(forFile url: URL,
                        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile)
        -> [String] {
        let path = url.path
        switch url.pathExtension.lowercased() {
        case "py": return ["/usr/bin/python3", path]
        case "sh", "bash", "command": return ["/bin/bash", path]
        case "zsh": return ["/bin/zsh", path]
        // .app 也是資料夾，`isExecutableFile` 會回 true，要排在下面那條之前
        case "app": return ["/usr/bin/open", path]
        default:
            // 沒有副檔名的執行檔直接跑；其他（.html、.numbers…）交給預設的 App 打開
            return isExecutable(path) ? [path] : ["/usr/bin/open", path]
        }
    }

    /// 選單上顯示的簡短說明：選到的那個檔案的名稱
    static func summary(_ command: [String]) -> String {
        URL(fileURLWithPath: command.last ?? "").lastPathComponent
    }
}

/// 執行排程列的點擊指令（`AppSettings.scheduleOpenCommands`）。
///
/// **不等它結束**：`Process.run()` 送出去就回來，UI 不會卡住。
/// 失敗的提示由被呼叫的腳本自己處理（台股儀表板的 `open_dashboard.py` 會跳 macOS 通知），
/// 這裡只把結束碼記到 Console，不另外彈視窗
enum ScheduleCommandLauncher {
    static func run(_ command: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            if finished.terminationStatus != 0 {
                NSLog("排程點擊指令結束碼 \(finished.terminationStatus)：\(command.joined(separator: " "))")
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("排程點擊指令無法執行：\(error.localizedDescription)")
        }
    }
}
