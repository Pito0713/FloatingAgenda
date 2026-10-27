import XCTest
@testable import FloatingAgenda

/// 選單列快速啟動的項目設定
@MainActor
final class QuickLaunchItemsTests: XCTestCase {
    func testDefaultIsEmpty() {
        XCTAssertEqual(Fixture.settings().quickLaunchItems, [])
    }

    /// 順序要照存進去的樣子，重複的名稱與指令也要保留
    func testRoundTripKeepsOrder() {
        let (settings, store) = Fixture.settingsWithStore()
        let items = [QuickLaunchItem(name: "b", command: ["/usr/bin/open", "/x/b.command"]),
                     QuickLaunchItem(name: "a", command: ["/usr/bin/python3", "/x/a.py"]),
                     QuickLaunchItem(name: "b", command: ["/usr/bin/open", "/x/b.command"])]
        settings.quickLaunchItems = items
        XCTAssertEqual(settings.quickLaunchItems, items)
        XCTAssertNotNil(store.persistedObject(forKey: "quickLaunchItems"))
    }

    func testAppendAndRemove() {
        let settings = Fixture.settings()
        settings.quickLaunchItems.append(QuickLaunchItem(name: "a", command: ["/bin/echo"]))
        settings.quickLaunchItems.append(QuickLaunchItem(name: "b", command: ["/bin/echo"]))
        settings.quickLaunchItems.remove(at: 0)
        XCTAssertEqual(settings.quickLaunchItems.map(\.name), ["b"])
    }

    /// 壞掉的那幾項丟掉，其他項照常可用、順序不變
    func testDropsInvalidEntriesOnly() {
        let (settings, store) = Fixture.settingsWithStore()
        store.set([["name": "first", "command": ["/bin/echo"]],
                   ["name": "relative", "command": ["python3", "x.py"]],
                   ["name": "empty", "command": [String]()],
                   ["name": "", "command": ["/bin/echo"]],
                   ["command": ["/bin/echo"]],
                   ["name": "wrongType", "command": "/bin/echo"],
                   "not a dict",
                   ["name": "last", "command": ["/usr/bin/open", "/x/a.command"]]] as [Any],
                  forKey: "quickLaunchItems")
        XCTAssertEqual(settings.quickLaunchItems.map(\.name), ["first", "last"])
    }

    func testWrongTopLevelTypeIsEmpty() {
        let (settings, store) = Fixture.settingsWithStore()
        store.set("oops", forKey: "quickLaunchItems")
        XCTAssertEqual(settings.quickLaunchItems, [])
    }
}

/// 快速啟動選了檔案之後推出來的指令
final class QuickLaunchCommandTests: XCTestCase {
    private func command(_ path: String, executable: Bool = false) -> [String] {
        QuickLaunchCommand.command(forFile: URL(fileURLWithPath: path),
                                   isExecutable: { _ in executable })
    }

    /// .command 要在終端機視窗跑（TUI 需要終端機），就算可執行也一樣
    func testCommandFileOpensInTerminal() {
        XCTAssertEqual(command("/x/swarmtide.command", executable: true),
                       ["/usr/bin/open", "/x/swarmtide.command"])
        XCTAssertEqual(command("/x/start.COMMAND"), ["/usr/bin/open", "/x/start.COMMAND"])
    }

    /// 其他副檔名照排程點擊動作的規則
    func testOtherFilesFollowScheduleRules() {
        XCTAssertEqual(command("/x/a.py"), ["/usr/bin/python3", "/x/a.py"])
        XCTAssertEqual(command("/x/a.sh"), ["/bin/bash", "/x/a.sh"])
        XCTAssertEqual(command("/x/tool", executable: true), ["/x/tool"])
        XCTAssertEqual(command("/x/report.html"), ["/usr/bin/open", "/x/report.html"])
    }

    /// 排程那邊的 .command 行為不能被這次改動影響
    func testScheduleCommandFileStillRunsInBackground() {
        XCTAssertEqual(ScheduleCommand.command(forFile: URL(fileURLWithPath: "/x/a.command"),
                                               isExecutable: { _ in true }),
                       ["/bin/bash", "/x/a.command"])
    }

    func testDefaultNameDropsExtension() {
        XCTAssertEqual(QuickLaunchCommand.defaultName(forFile: URL(fileURLWithPath: "/x/swarmtide.command")),
                       "swarmtide")
        XCTAssertEqual(QuickLaunchCommand.defaultName(forFile: URL(fileURLWithPath: "/x/tool")), "tool")
    }
}
