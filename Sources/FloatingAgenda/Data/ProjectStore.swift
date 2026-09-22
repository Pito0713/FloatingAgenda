import AppKit
import Observation

/// 掃描 `~/.agent-sessions/*/latest.md`，把各專案的交接進度變成 `ProjectItem`。
///
/// ⚠️ **唯讀**：這個型別只會列目錄與讀檔，不含任何 `write`、`createFile`、
/// `removeItem`、`moveItem`（M9 計畫 §8 的紅線，§7.1 會用 grep 稽核）。
///
/// **一個誠實的例外**：讀檔會讓系統更新該檔案的 **atime（最後存取時間）**。
/// 2026-09-22 在本機 APFS 實測確認 `cat` 一次就會讓 atime 前進，這是檔案系統行為，
/// macOS 沒有 `O_NOATIME` 可以避免。唯一「修掉」的方法是讀完用 `utimensat` 把 atime 寫回去，
/// 但那本身就是對 metadata 的寫入，比問題更糟，所以**刻意不做**。
/// 內容、mtime、大小、權限都不會被改動，`ProjectStoreTests` 有對應的斷言。
@MainActor
@Observable
final class ProjectStore {
    static let shared = ProjectStore()

    private(set) var state: SectionState<ProjectItem> = .loading

    /// 交接文件不可能這麼大。超過就略過那一份，避免把別的東西誤當成交接文件整份讀進記憶體
    nonisolated static let maxFileBytes = 256 * 1024

    /// 可注入是為了測試：測試一律指向 `temporaryDirectory` 底下自己建的樹，
    /// **不會讀到使用者真正的 `~/.agent-sessions`**
    @ObservationIgnored private let root: URL

    /// 掃描動作本身也可注入。抽這道縫只為了一件事：讓「舊結果不得覆蓋新結果」的
    /// 世代守衛能被**確定性地**測到——測試可以讓第一次掃描卡住、第二次先回來，
    /// 再放行第一次。用真實檔案系統無法穩定製造這個時序（codex 2026-09-22 指出
    /// 這條守衛原本沒有任何測試覆蓋）。沿用 `ReminderWriter` 的同一套注入模式
    @ObservationIgnored private let scanner: @Sendable (URL) -> SectionState<ProjectItem>

    /// 非 UI 狀態。`deinit` 是 nonisolated，要標 `nonisolated(unsafe)` 才能在裡面收尾
    @ObservationIgnored nonisolated(unsafe)
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    @ObservationIgnored nonisolated(unsafe) private var refreshTimer: Timer?
    /// 掃描是非同步的，用世代編號丟掉過期結果（沿用 AgendaStore 的作法）
    @ObservationIgnored private var generation = 0

    init(root: URL? = nil,
         scanner: (@Sendable (URL) -> SectionState<ProjectItem>)? = nil) {
        // 不寫死 `~`：`NSString.expandingTildeInPath` 在沙盒或換使用者時會給錯的路徑
        self.root = root ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-sessions", isDirectory: true)
        self.scanner = scanner ?? { Self.scan(root: $0) }
    }

    deinit {
        observers.forEach { $0.center.removeObserver($0.token) }
        refreshTimer?.invalidate()
    }

    func start() {
        // 重複呼叫不該疊加 observer 與計時器：舊 token 要到 deinit 才移除，
        // 疊加後一次喚醒會觸發多次並行掃描
        guard observers.isEmpty else { return }
        observeChanges()
        startPeriodicRefresh()
        refresh()
    }

    /// 重讀。呼叫端：啟動、60 秒計時、睡眠喚醒、角色模式展開、選單列「重新整理」
    func refresh() {
        generation += 1
        let generation = self.generation
        let root = self.root
        let scanner = self.scanner
        Task.detached(priority: .utility) {
            let result = scanner(root)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                // `@Observable` 不比對相等性，指派同樣的內容也會發出變更通知。
                // 少了這道守衛，60 秒計時器每輪都會讓整個專案區白重繪一次
                // （M7 在 AgendaStore 的清單上踩過同一個坑）
                guard self.state != result else { return }
                self.state = result
            }
        }
    }

    // MARK: - 掃描

    /// `nonisolated` 是刻意標出來的：這個方法在背景執行緒跑。
    /// 不標的話它會繼承 `@MainActor`，宣告與實際執行環境不符（M2 踩過同一個坑）。
    ///
    /// 不標 `private` 是為了讓測試直接驗掃描結果，不必輪詢非同步狀態
    nonisolated static func scan(root: URL) -> SectionState<ProjectItem> {
        let manager = FileManager.default

        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failed("找不到 ~/.agent-sessions")
        }

        let entries: [URL]
        do {
            entries = try manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        } catch {
            return .failed("讀取失敗：\(error.localizedDescription)")
        }

        var items: [ProjectItem] = []
        for entry in entries {
            // 第一層只看資料夾：`README.md`、`registry.tsv`、`hook.log` 不是專案
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            if let item = read(directory: entry) { items.append(item) }
        }

        items.sort(by: order)
        return .loaded(items: items, total: items.count)
    }

    nonisolated static func read(directory: URL) -> ProjectItem? {
        let file = directory.appendingPathComponent("latest.md", isDirectory: false)

        // 先擋掉資料夾等非一般檔案，錯誤訊息才明確
        let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { return nil }

        // 大小上限用「開一次檔、最多讀 maxFileBytes + 1 個位元組」來保證，
        // 而不是先 stat 再整份讀：後者在 stat 與讀取之間檔案若被換掉或長大，
        // 上限就形同虛設（codex 2026-09-22 指出的 TOCTOU）。
        // 多讀 1 個位元組是為了能分辨「剛好等於上限」與「超過上限」
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxFileBytes + 1),
              data.count <= maxFileBytes else { return nil }
        // 交接文件應該是 UTF-8；真的壞了也不要整個專案消失，改用寬鬆解碼
        let text = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)

        return SessionParser.parse(directoryName: directory.lastPathComponent,
                                   text: text,
                                   fileURL: file)
    }

    /// 有卡住的點 → 🔴 → 🟡 → 🟢 → 其他；同一級照「最後更新」由新到舊（§4.5）。
    /// 最後用 id 決勝：`sort` 在 Swift 沒有穩定性保證，少了這一項，
    /// 同級同時間的兩個專案會在每次重讀後互換位置
    nonisolated static func order(_ lhs: ProjectItem, _ rhs: ProjectItem) -> Bool {
        if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
        switch (lhs.updated, rhs.updated) {
        case let (left?, right?) where left != right: return left > right
        case (nil, .some): return false   // 沒有時間的排後面
        case (.some, nil): return true
        default: break
        }
        return lhs.id < rhs.id
    }

    // MARK: - 重讀時機

    private func observeChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((workspaceCenter,
                          workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                      object: nil,
                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }))
    }

    /// 60 秒重讀。計畫 §5.2 寫的是「跟著 AgendaStore 現有的 60 秒計時一起」，
    /// 這裡改成自己持有同週期的計時器——讓資料層不必互相認識，
    /// 效果一樣而且 `ProjectStore` 可以單獨測試（自行決定事項）
    private func startPeriodicRefresh() {
        refreshTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        refreshTimer = timer
    }
}
