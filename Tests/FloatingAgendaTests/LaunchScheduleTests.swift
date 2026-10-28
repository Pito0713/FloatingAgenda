import XCTest
@testable import FloatingAgenda

/// 排程區的解析、下次執行時間、文案與掃描。
///
/// ⚠️ 掃描一律指向 `temporaryDirectory` 底下自己建的資料夾，`launchctl` 也換成假的。
/// **絕不讀使用者真正的 `~/Library/LaunchAgents`，也不跑真的 launchctl**。
final class LaunchScheduleTests: XCTestCase {

    private let plistURL = URL(fileURLWithPath: "/tmp/x.plist")

    // MARK: - plist

    func testOnlyLocalPrefixCounts() {
        XCTAssertNil(LaunchSchedule.parse(plist: ["Label": "com.google.keystone.agent"],
                                          plistURL: plistURL))
        XCTAssertNil(LaunchSchedule.parse(plist: [:], plistURL: plistURL))
        XCTAssertNotNil(LaunchSchedule.parse(plist: ["Label": "local.a"], plistURL: plistURL))
    }

    func testCalendarIntervalAsArrayAndAsSingleDict() {
        let array = LaunchSchedule.parse(plist: [
            "Label": "local.a",
            "StartCalendarInterval": [["Weekday": 1, "Hour": 16, "Minute": 30],
                                      ["Weekday": 2, "Hour": 16, "Minute": 30]],
        ], plistURL: plistURL)
        XCTAssertEqual(array?.trigger, .calendar([CalendarSlot(weekday: 1, hour: 16, minute: 30),
                                                  CalendarSlot(weekday: 2, hour: 16, minute: 30)]))

        let single = LaunchSchedule.parse(plist: [
            "Label": "local.a",
            "StartCalendarInterval": ["Hour": 2, "Minute": 0],
        ], plistURL: plistURL)
        XCTAssertEqual(single?.trigger, .calendar([CalendarSlot(hour: 2, minute: 0)]))
    }

    func testIntervalNoneAndLogPath() {
        let interval = LaunchSchedule.parse(plist: [
            "Label": "local.a", "StartInterval": 600, "StandardErrorPath": "/tmp/err.log",
        ], plistURL: plistURL)
        XCTAssertEqual(interval?.trigger, .interval(600))
        // 沒有 StandardOutPath 時退回 StandardErrorPath
        XCTAssertEqual(interval?.logURL?.path, "/tmp/err.log")

        let none = LaunchSchedule.parse(plist: ["Label": "local.a", "RunAtLoad": true],
                                        plistURL: plistURL)
        XCTAssertEqual(none?.trigger, ScheduleTrigger.none)
        XCTAssertNil(none?.logURL)
    }

    // MARK: - launchctl print

    func testRunStateRunning() {
        let text = """
        gui/501/local.a = {
        \tstate = running
        \tenvironment = {
        \t\tpid => 1
        \t}
        \tpid = 93824
        }
        """
        XCTAssertEqual(LaunchSchedule.parseRunState(printOutput: text), .running(pid: 93824))
    }

    func testRunStateLastExit() {
        XCTAssertEqual(LaunchSchedule.parseRunState(
            printOutput: "\tstate = not running\n\tlast exit code = 0\n"), .idle(lastExit: 0))
        XCTAssertEqual(LaunchSchedule.parseRunState(
            printOutput: "\tstate = not running\n\tlast exit code = 78: Function not implemented\n"),
            .idle(lastExit: 78))
        XCTAssertEqual(LaunchSchedule.parseRunState(
            printOutput: "\tstate = not running\n\tlast exit code = (never exited)\n"),
            .idle(lastExit: nil))
    }

    /// 巢狀區塊（兩個 tab）裡的同名字不能被當成最外層的值
    func testNestedKeysAreIgnored() {
        let text = "\tstate = not running\n\t\tlast exit code = 9\n"
        XCTAssertEqual(LaunchSchedule.parseRunState(printOutput: text), .idle(lastExit: nil))
    }

    // MARK: - 下次執行

    private var weekdays: ScheduleTrigger {
        .calendar((1...5).map { CalendarSlot(weekday: $0, hour: 16, minute: 30) })
    }

    func testNextRunSameDay() {
        // 2026-10-12 是星期一
        let next = LaunchSchedule.nextRun(weekdays, after: Fixture.date(2026, 10, 12, 16, 0))
        XCTAssertEqual(next, Fixture.date(2026, 10, 12, 16, 30))
    }

    /// 星期五跑完之後，下一次是星期一——驗 launchd 的星期（1＝一）有正確換成 Foundation 的
    func testNextRunSkipsWeekend() {
        let next = LaunchSchedule.nextRun(weekdays, after: Fixture.date(2026, 10, 16, 17, 0))
        XCTAssertEqual(next, Fixture.date(2026, 10, 19, 16, 30))
    }

    /// launchd 的 0 與 7 都是星期日
    func testSundayAsZeroAndSeven() {
        let after = Fixture.date(2026, 10, 12)
        let sunday = Fixture.date(2026, 10, 18, 9, 0)
        for value in [0, 7] {
            let trigger = ScheduleTrigger.calendar([CalendarSlot(weekday: value, hour: 9, minute: 0)])
            XCTAssertEqual(LaunchSchedule.nextRun(trigger, after: after), sunday, "Weekday=\(value)")
        }
    }

    func testIntervalHasNoNextRun() {
        XCTAssertNil(LaunchSchedule.nextRun(.interval(60), after: Date()))
    }

    // MARK: - 文案

    func testDescribe() {
        XCTAssertEqual(LaunchSchedule.describe(weekdays), "平日 16:30")
        XCTAssertEqual(LaunchSchedule.describe(.calendar([CalendarSlot(hour: 8, minute: 5)])),
                       "每天 08:05")
        XCTAssertEqual(LaunchSchedule.describe(.calendar([
            CalendarSlot(weekday: 7, hour: 9, minute: 0),
            CalendarSlot(weekday: 6, hour: 9, minute: 0),
        ])), "週末 09:00")
        XCTAssertEqual(LaunchSchedule.describe(.calendar([
            CalendarSlot(weekday: 0, hour: 9, minute: 0),
            CalendarSlot(weekday: 3, hour: 9, minute: 0),
            CalendarSlot(weekday: 1, hour: 9, minute: 0),
        ])), "每週一、三、日 09:00")
        XCTAssertEqual(LaunchSchedule.describe(.calendar([
            CalendarSlot(hour: 9, minute: 0), CalendarSlot(hour: 21, minute: 0),
        ])), "2 個時段")
        XCTAssertEqual(LaunchSchedule.describe(.interval(3600)), "每 1 小時")
        XCTAssertEqual(LaunchSchedule.describe(.interval(900)), "每 15 分鐘")
    }

    func testDetailText() {
        let now = Fixture.date(2026, 10, 12, 16, 0)
        func item(_ run: ScheduleRunState) -> ScheduleItem {
            ScheduleItem(id: "local.a", name: "a", trigger: weekdays, run: run,
                         logURL: nil, plistURL: plistURL)
        }
        let time = Formatting.timeString(for: Fixture.date(2026, 10, 12, 16, 30))
        XCTAssertEqual(Formatting.scheduleDetail(for: item(.idle(lastExit: 0)), now: now),
                       "平日 16:30 · 下次 今天 \(time)")
        XCTAssertEqual(Formatting.scheduleDetail(for: item(.running(pid: 1)), now: now),
                       "執行中 · 平日 16:30")
        XCTAssertEqual(Formatting.scheduleDetail(for: item(.idle(lastExit: 2)), now: now),
                       "上次失敗（代碼 2） · 下次 今天 \(time)")
        XCTAssertEqual(Formatting.scheduleDetail(for: item(.notLoaded), now: now),
                       "未載入 · 平日 16:30")
    }

    // MARK: - 掃描

    func testScanFiltersSortsAndUsesInjectedRunState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchScheduleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func write(_ name: String, _ plist: [String: Any]) throws {
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml, options: 0)
            try data.write(to: directory.appendingPathComponent(name))
        }
        try write("com.vendor.agent.plist", ["Label": "com.vendor.agent", "StartInterval": 60])
        try write("local.ok.plist", ["Label": "local.ok", "StartInterval": 60])
        try write("local.bad.plist", ["Label": "local.bad", "StartInterval": 60])
        try "不是 plist".write(to: directory.appendingPathComponent("local.broken.plist"),
                             atomically: true, encoding: .utf8)

        let state = ScheduleStore.scan(directory: directory, now: Date()) { label in
            label == "local.bad" ? .idle(lastExit: 1) : .idle(lastExit: 0)
        }
        guard case .loaded(let items, let total) = state else {
            return XCTFail("應該讀得到：\(state)")
        }
        XCTAssertEqual(total, 2)
        // 失敗的排最前面；vendor 與壞掉的 plist 都不出現
        XCTAssertEqual(items.map(\.id), ["local.bad", "local.ok"])
        XCTAssertEqual(items.map(\.name), ["bad", "ok"])
    }

    func testMissingDirectoryIsEmptyNotFailure() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        XCTAssertEqual(ScheduleStore.scan(directory: missing, now: Date()) { _ in .notLoaded },
                       .loaded(items: [], total: 0))
    }

    // MARK: - 哪些模式看得到

    func testShowsSchedules() {
        XCTAssertTrue(PanelRootView.showsSchedules(mode: .full, expanded: false, enabled: true))
        XCTAssertTrue(PanelRootView.showsSchedules(mode: .character, expanded: true, enabled: true))
        XCTAssertFalse(PanelRootView.showsSchedules(mode: .character, expanded: false, enabled: true))
        XCTAssertFalse(PanelRootView.showsSchedules(mode: .collapsed, expanded: false, enabled: true))
        XCTAssertFalse(PanelRootView.showsSchedules(mode: .full, expanded: false, enabled: false))
    }
}

/// 排程列的點擊指令設定
@MainActor
final class ScheduleOpenCommandsTests: XCTestCase {
    func testDefaultIsEmpty() {
        XCTAssertEqual(Fixture.settings().scheduleOpenCommands, [:])
    }

    func testRoundTripPerLabel() {
        let settings = Fixture.settings()
        let commands = ["local.a": ["/usr/bin/python3", "/x/open_dashboard.py"],
                        "local.b": ["/bin/echo"]]
        settings.scheduleOpenCommands = commands
        XCTAssertEqual(settings.scheduleOpenCommands, commands)
    }

    /// 相對路徑、空陣列、型別不對的那一條丟掉，其他條照常可用
    func testDropsInvalidEntriesOnly() {
        let (settings, store) = Fixture.settingsWithStore()
        store.set(["local.ok": ["/bin/echo"],
                   "local.relative": ["python3", "x.py"],
                   "local.empty": [String](),
                   "local.wrongType": "/bin/echo"] as [String: Any],
                  forKey: "scheduleOpenCommands")
        XCTAssertEqual(settings.scheduleOpenCommands, ["local.ok": ["/bin/echo"]])
    }
}

/// 選單列選了檔案之後推出來的指令
final class ScheduleCommandTests: XCTestCase {
    private func command(_ path: String, executable: Bool = false) -> [String] {
        ScheduleCommand.command(forFile: URL(fileURLWithPath: path),
                                isExecutable: { _ in executable })
    }

    func testScriptsRunWithTheirInterpreter() {
        XCTAssertEqual(command("/x/open_dashboard.py"), ["/usr/bin/python3", "/x/open_dashboard.py"])
        XCTAssertEqual(command("/x/a.SH"), ["/bin/bash", "/x/a.SH"])
        XCTAssertEqual(command("/x/a.command"), ["/bin/bash", "/x/a.command"])
        XCTAssertEqual(command("/x/a.zsh"), ["/bin/zsh", "/x/a.zsh"])
    }

    /// .app 是資料夾、會被當成可執行，但一定要用 open 開
    func testAppIsOpenedEvenIfExecutable() {
        XCTAssertEqual(command("/Applications/X.app", executable: true),
                       ["/usr/bin/open", "/Applications/X.app"])
    }

    func testPlainExecutableAndDocuments() {
        XCTAssertEqual(command("/x/tool", executable: true), ["/x/tool"])
        XCTAssertEqual(command("/x/report.html"), ["/usr/bin/open", "/x/report.html"])
    }

    func testSummaryIsFileName() {
        XCTAssertEqual(ScheduleCommand.summary(["/usr/bin/python3", "/x/open_dashboard.py"]),
                       "open_dashboard.py")
    }
}

/// 選單取消勾選的排程不出現在卡片上
@MainActor
final class HiddenSchedulesTests: XCTestCase {
    private func item(_ label: String) -> ScheduleItem {
        ScheduleItem(id: label, name: label, trigger: .none, run: .notLoaded,
                     logURL: nil, plistURL: URL(fileURLWithPath: "/x/\(label).plist"))
    }

    func testDefaultHidesNothing() {
        XCTAssertEqual(Fixture.settings().hiddenScheduleLabels, [])
    }

    func testRoundTripUnderExpectedKey() {
        let (settings, store) = Fixture.settingsWithStore()
        settings.hiddenScheduleLabels = ["local.wakawaka"]
        XCTAssertEqual(settings.hiddenScheduleLabels, ["local.wakawaka"])
        XCTAssertEqual(store.persistedObject(forKey: "hiddenScheduleLabels") as? [String],
                       ["local.wakawaka"])
    }

    func testFilterKeepsOrderAndRecountsTotal() {
        let state = SectionState.loaded(items: [item("local.a"), item("local.b"), item("local.c")],
                                        total: 3)
        XCTAssertEqual(PanelRootView.hidingSchedules(state, labels: ["local.b"]),
                       .loaded(items: [item("local.a"), item("local.c")], total: 2))
    }

    /// 全部隱藏 → 空清單，排程區整塊不出現
    func testHidingAllLeavesEmptyList() {
        let state = SectionState.loaded(items: [item("local.a")], total: 1)
        XCTAssertEqual(PanelRootView.hidingSchedules(state, labels: ["local.a"]),
                       .loaded(items: [], total: 0))
    }

    /// 已經不存在的排程留在隱藏清單裡也沒關係；非 loaded 的狀態原樣傳回
    func testUnknownLabelsAndOtherStatesPassThrough() {
        let state = SectionState.loaded(items: [item("local.a")], total: 1)
        XCTAssertEqual(PanelRootView.hidingSchedules(state, labels: ["local.gone"]), state)
        XCTAssertEqual(PanelRootView.hidingSchedules(.loading, labels: ["local.a"]), .loading)
    }
}
