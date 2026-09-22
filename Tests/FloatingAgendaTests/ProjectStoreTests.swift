import XCTest
@testable import FloatingAgenda

/// 掃描與讀檔那一側。
///
/// ⚠️ 每個測試都在 `temporaryDirectory` 底下自己建一棵樹，測完刪掉。
/// **絕不指向使用者真正的 `~/.agent-sessions`**（M9 計畫 §8）。
final class ProjectStoreTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    // MARK: - 建樹用的小工具

    private func makeProject(_ directory: String, _ contents: String) throws {
        let folder = root.appendingPathComponent(directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try contents.write(to: folder.appendingPathComponent("latest.md"),
                           atomically: true, encoding: .utf8)
    }

    private func document(status: String, updated: String, todos: String = "- [ ] 一") -> String {
        """
        # \(status)

        > 最後更新：\(updated)
        > 狀態：\(status)

        ## 進行中

        \(todos)
        """
    }

    /// ⚠️ 掃描沒回傳 `.loaded` 要**失敗**，不能 skip：
    /// 用 `XCTSkip` 的話，掃描全面壞掉變成 `.failed` 時這些測試會靜默略過而不是變紅
    /// （codex 2026-09-22 指出）
    private func loadedItems(file: StaticString = #filePath,
                             line: UInt = #line) throws -> [ProjectItem] {
        let state = ProjectStore.scan(root: root)
        guard case .loaded(let items, let total) = state else {
            XCTFail("預期是 loaded，實際是 \(state)", file: file, line: line)
            struct NotLoaded: Error {}
            throw NotLoaded()
        }
        XCTAssertEqual(total, items.count, "total 應該等於實際筆數", file: file, line: line)
        return items
    }

    // MARK: - 異常狀態

    func testMissingRootReportsFailure() throws {
        let missing = root.appendingPathComponent("不存在", isDirectory: true)
        guard case .failed(let message) = ProjectStore.scan(root: missing) else {
            return XCTFail("資料夾不存在時應該是 failed")
        }
        XCTAssertEqual(message, "找不到 ~/.agent-sessions")
    }

    /// 路徑存在但是個檔案不是資料夾 —— 也要走 failed，不能當成空清單
    func testRootThatIsAFileReportsFailure() throws {
        let file = root.appendingPathComponent("我是檔案")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        guard case .failed = ProjectStore.scan(root: file) else {
            return XCTFail("根路徑是檔案時應該是 failed")
        }
    }

    func testEmptyRootIsLoadedWithNoProjects() throws {
        XCTAssertTrue(try loadedItems().isEmpty)
    }

    // MARK: - 該略過的東西

    /// `~/.agent-sessions` 第一層有 README.md、registry.tsv、hook.log 三個非專案檔案
    func testTopLevelFilesAreNotTreatedAsProjects() throws {
        try makeProject("真的專案", document(status: "🟢 順暢", updated: "2026-09-20 10:00"))
        for name in ["README.md", "registry.tsv", "hook.log"] {
            try "內容".write(to: root.appendingPathComponent(name),
                             atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try loadedItems().map(\.id), ["真的專案"])
    }

    func testDirectoryWithoutLatestFileIsSkipped() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("沒有交接檔", isDirectory: true),
            withIntermediateDirectories: true)
        XCTAssertTrue(try loadedItems().isEmpty)
    }

    func testMigratedProjectIsSkippedByScan() throws {
        try makeProject("留下來的", document(status: "🟢 順暢", updated: "2026-09-20 10:00"))
        try makeProject("搬走的", "# 搬走的（已搬遷 → 請讀 ../留下來的/latest.md）\n")
        XCTAssertEqual(try loadedItems().map(\.id), ["留下來的"])
    }

    /// 超過 256KB 就略過：交接文件不可能那麼大，避免把別的東西整份讀進記憶體
    func testOversizedFileIsSkipped() throws {
        let padding = String(repeating: "填充\n", count: 100_000)
        try makeProject("太大的", "# 太大的\n\n> 狀態：🟢 順暢\n\n\(padding)")
        let size = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("太大的/latest.md").path)[.size] as? Int
        XCTAssertGreaterThan(try XCTUnwrap(size), ProjectStore.maxFileBytes,
                             "樣本必須真的超過上限，否則這個測試沒有鑑別力")
        XCTAssertTrue(try loadedItems().isEmpty)
    }

    /// 剛好在上限以下要讀得到 —— 證明上面那條是被大小擋掉的，不是別的原因
    func testFileJustUnderTheLimitIsRead() throws {
        let padding = String(repeating: "a", count: ProjectStore.maxFileBytes - 200)
        try makeProject("剛好夠小", "# 剛好夠小\n\n> 狀態：🟢 順暢\n\n\(padding)")
        XCTAssertEqual(try loadedItems().map(\.id), ["剛好夠小"])
    }

    func testLatestMdThatIsADirectoryIsSkipped() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("怪東西/latest.md", isDirectory: true),
            withIntermediateDirectories: true)
        XCTAssertTrue(try loadedItems().isEmpty)
    }

    // MARK: - 正常掃描與排序

    func testScanSortsBlockedThenByLight() throws {
        try makeProject("綠色", document(status: "🟢 順暢", updated: "2026-09-21 10:00"))
        try makeProject("黃色", document(status: "🟡 進行中", updated: "2026-09-20 10:00"))
        try makeProject("卡住的", """
        # 卡住的

        > 最後更新：2026-09-01 10:00
        > 狀態：🟢 順暢

        ## 卡住的點

        等對方回覆
        """)

        let items = try loadedItems()
        XCTAssertEqual(items.map(\.id), ["卡住的", "黃色", "綠色"])
        XCTAssertEqual(items.first?.blocker, "等對方回覆")
    }

    func testScanReadsEveryFieldFromDisk() throws {
        try makeProject("專案甲", document(status: "🟡 進行中",
                                          updated: "2026-09-18 15:20",
                                          todos: "- [x] 做完的\n- [ ] 還沒的"))
        let item = try XCTUnwrap(try loadedItems().first)
        XCTAssertEqual(item.id, "專案甲")
        XCTAssertEqual(item.status, .yellow)
        XCTAssertEqual(item.done, 1)
        XCTAssertEqual(item.total, 2)
        XCTAssertEqual(item.openTodos, ["還沒的"])
        XCTAssertEqual(item.updated, Fixture.date(2026, 9, 18, 15, 20))
        XCTAssertEqual(item.fileURL.lastPathComponent, "latest.md")
    }

    // MARK: - 紅線：只讀不寫

    /// 掃描不得改動被讀取的檔案（M9 計畫 §8）。
    ///
    /// 比對 mtime、大小、內容與整棵子路徑清單。
    ///
    /// **atime 刻意不斷言**：讀檔一定會讓系統更新最後存取時間，
    /// 2026-09-22 在本機 APFS 實測 `cat` 一次 atime 就會前進，macOS 沒有 `O_NOATIME`
    /// 可以避免；唯一「修掉」的方法是讀完用 `utimensat` 把 atime 寫回去，
    /// 但那本身就是對 metadata 的寫入，比問題更糟。
    /// 這裡把 atime 印出來留痕，但不當成失敗條件（codex 2026-09-22 提出，已裁決不修）
    func testScanDoesNotModifyAnythingOnDisk() throws {
        try makeProject("專案甲", document(status: "🟢 順暢", updated: "2026-09-20 10:00"))
        let file = root.appendingPathComponent("專案甲/latest.md")

        let manager = FileManager.default
        let before = try manager.attributesOfItem(atPath: file.path)
        let contentsBefore = try String(contentsOf: file, encoding: .utf8)
        let treeBefore = manager.subpaths(atPath: root.path)?.sorted()

        _ = ProjectStore.scan(root: root)

        let after = try manager.attributesOfItem(atPath: file.path)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        XCTAssertEqual(before[.size] as? Int, after[.size] as? Int)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), contentsBefore)
        XCTAssertEqual(manager.subpaths(atPath: root.path)?.sorted(), treeBefore,
                       "掃描不該新增或刪除任何檔案")
        XCTAssertEqual(before[.posixPermissions] as? Int, after[.posixPermissions] as? Int,
                       "掃描不該改變權限")
    }

    // MARK: - 世代守衛

    /// 舊掃描晚回來時**不得**覆蓋新掃描的結果。
    ///
    /// 用注入的 scanner 製造確定性時序：第一次掃描卡在 semaphore 上，
    /// 第二次先回來寫入狀態，然後才放行第一次。
    /// 把 `refresh()` 裡的 `self.generation == generation` 守衛拿掉，這條會失敗
    @MainActor
    func testStaleScanDoesNotOverwriteNewerResult() async throws {
        let gate = DispatchSemaphore(value: 0)
        let calls = NSLock()
        var callCount = 0

        let store = ProjectStore(root: root) { _ in
            calls.lock()
            callCount += 1
            let isFirst = callCount == 1
            calls.unlock()

            if isFirst {
                gate.wait()                       // 第一次卡住，等第二次先完成
                return .loaded(items: [Self.item("舊的")], total: 1)
            }
            return .loaded(items: [Self.item("新的")], total: 1)
        }

        store.refresh()                            // 第一次：卡住
        store.refresh()                            // 第二次：立刻回來
        try await Self.waitUntilLoaded(store)
        XCTAssertEqual(Self.ids(store.state), ["新的"], "第二次的結果應該先寫入")

        gate.signal()                              // 放行第一次
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(Self.ids(store.state), ["新的"],
                       "晚回來的舊結果不得覆蓋新結果")
    }

    /// `start()` 重複呼叫不該疊加 observer 與計時器
    @MainActor
    func testRepeatedStartDoesNotStackObservers() async throws {
        let counter = NSLock()
        var scans = 0
        let store = ProjectStore(root: root) { _ in
            counter.lock(); scans += 1; counter.unlock()
            return .loaded(items: [], total: 0)
        }

        store.start()
        store.start()
        store.start()
        try await Task.sleep(for: .milliseconds(200))

        counter.lock(); let total = scans; counter.unlock()
        XCTAssertEqual(total, 1, "重複 start() 只該觸發一次掃描")
    }

    /// 內容沒變就不要重新指派狀態，否則 60 秒計時器每輪都會讓 UI 白重繪一次
    func testIdenticalStatesCompareEqual() {
        let a = SectionState<ProjectItem>.loaded(items: [Self.item("甲")], total: 1)
        let b = SectionState<ProjectItem>.loaded(items: [Self.item("甲")], total: 1)
        let c = SectionState<ProjectItem>.loaded(items: [Self.item("乙")], total: 1)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, .loading)
        XCTAssertNotEqual(SectionState<ProjectItem>.failed("x"), .failed("y"))
    }

    private static func item(_ id: String) -> ProjectItem {
        ProjectItem(id: id, name: id, status: .green, statusText: "",
                    updated: nil, done: 0, total: 0, openTodos: [],
                    blocker: nil, fileURL: URL(fileURLWithPath: "/tmp/\(id)"))
    }

    private static func ids(_ state: SectionState<ProjectItem>) -> [String] {
        guard case .loaded(let items, _) = state else { return [] }
        return items.map(\.id)
    }

    @MainActor
    private static func waitUntilLoaded(_ store: ProjectStore) async throws {
        for _ in 0..<100 {
            if case .loading = store.state {
                try await Task.sleep(for: .milliseconds(20))
            } else {
                return
            }
        }
    }

    // MARK: - 非同步的那條路徑

    /// `scan` 的結果要真的被送回 MainActor 的 `state`
    @MainActor
    func testRefreshPublishesScanResult() async throws {
        try makeProject("專案甲", document(status: "🟢 順暢", updated: "2026-09-20 10:00"))
        let store = ProjectStore(root: root)

        if case .loading = store.state {} else { XCTFail("初始狀態應該是 loading") }

        store.refresh()
        for _ in 0..<100 {
            if case .loading = store.state {
                try await Task.sleep(for: .milliseconds(20))
            } else {
                break
            }
        }

        guard case .loaded(let items, let total) = store.state else {
            return XCTFail("refresh 之後應該是 loaded，實際是 \(store.state)")
        }
        XCTAssertEqual(items.map(\.id), ["專案甲"])
        XCTAssertEqual(total, 1)
    }
}
