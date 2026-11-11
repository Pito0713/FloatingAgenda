import XCTest
@testable import FloatingAgenda

/// 專案區要顯示哪些專案（2026-11-10 起所有專案一次攤開，不再輪播）。
///
/// 挑誰是純函式，所以這裡全部直接驗值，不需要渲染任何 View。
/// 卡片**長什麼樣**不在這裡驗——那是 `ProjectCardView`，
/// 兩個模式共用同一個型別，由 `ProjectCardSharingTests` 守住。
final class ProjectTickerTests: XCTestCase {

    // MARK: - 挑哪些專案

    func testKeepsStoreOrderAndDoesNotReorder() {
        // 排序是 ProjectStore.order 的事（卡住的點 → 🔴 → 🟡 → 🟢），這裡不能再排一次
        let entries = ProjectTicker.entries(projects: loaded([
            project("後面的"), project("前面的"),
        ]))

        XCTAssertEqual(entries.map(\.id), ["後面的", "前面的"])
    }

    func testNoDisplayLimit() {
        // 展開的卡片是看詳情的地方，放不下由整張卡捲動，不限數量
        let projects = (1...10).map { project("P\($0)") }

        XCTAssertEqual(ProjectTicker.entries(projects: loaded(projects)).count, 10)
    }

    func testNonLoadedStatesProduceNothing() {
        for state in [SectionState<ProjectItem>.loading,
                      .needsPermission,
                      .failed("讀取失敗"),
                      .loaded(items: [], total: 0)] {
            XCTAssertTrue(ProjectTicker.entries(projects: state).isEmpty,
                          "沒有內容時整塊要消失，不能留一個空殼")
        }
    }

    // MARK: - 工具

    private func loaded(_ items: [ProjectItem]) -> SectionState<ProjectItem> {
        .loaded(items: items, total: items.count)
    }

    private func project(_ id: String,
                         blocker: String? = nil) -> ProjectItem {
        ProjectItem(id: id,
                    name: id,
                    status: .yellow,
                    statusText: "🟡 進行中",
                    updated: nil,
                    done: 1,
                    total: 4,
                    openTodos: ["待辦一", "待辦二"],
                    blocker: blocker,
                    fileURL: URL(fileURLWithPath: "/tmp/\(id)/latest.md"))
    }
}

/// 兩個模式共用同一個專案區（使用者 2026-09-29 要求「不要兩邊不同步」）。
///
/// ⚠️ SwiftUI 的 View 結構沒辦法在單元測試裡比對，所以這裡守的是**下一個人會踩的那一步**：
/// 想改樣式時先看到「卡片與挑選規則各只有一個來源」。真正逐像素的比對在
/// `--snapshot` 的 `-char-expanded-*.png` 與 `-ticker-*.png` 兩張圖。
@MainActor
final class ProjectCardSharingTests: XCTestCase {

    func testStatusNotesAreTheOnlyDifferenceBetweenTheTwoModes() {
        // 角色模式展開是「特地點開來看專案」，讀不到要講話；
        // 完整模式沒有交接紀錄的人整塊要消失，不能掛一行字
        XCTAssertEqual(ProjectTicker.statusNote(for: .loading), "讀取中…")
        XCTAssertEqual(ProjectTicker.statusNote(for: .needsPermission), "需要存取權限")
        XCTAssertEqual(ProjectTicker.statusNote(for: .failed("讀取失敗")), "讀取失敗")
        XCTAssertEqual(ProjectTicker.statusNote(for: .loaded(items: [], total: 0)),
                       "還沒有任何交接紀錄")
    }

    func testNoStatusNoteWhenThereIsACardToShow() {
        let project = ProjectItem(id: "A", name: "A", status: .green, statusText: "🟢",
                                  updated: nil, done: 0, total: 1, openTodos: [], blocker: nil,
                                  fileURL: URL(fileURLWithPath: "/tmp/A/latest.md"))
        XCTAssertNil(ProjectTicker.statusNote(for: .loaded(items: [project], total: 1)),
                     "有卡片就不必說話")
    }
}

/// 完整模式的專案輪播歸「顯示專案待辦」開關管（使用者 2026-09-29 要求）。
///
/// ⚠️ 與 `ProjectsVisibilityTests` 同一個理由：`--snapshot` 直接渲染 `WidgetView`，
/// 不經過 `PanelRootView`，這條規則只有這裡驗得到。
@MainActor
final class ProjectTickerVisibilityTests: XCTestCase {

    func testOnlyFullModeShowsTicker() {
        XCTAssertTrue(PanelRootView.showsProjectTicker(mode: .full, enabled: true))
    }

    func testOtherModesNeverShowTicker() {
        for mode in [DisplayMode.collapsed, .character] {
            XCTAssertFalse(PanelRootView.showsProjectTicker(mode: mode, enabled: true),
                           "\(mode) 不該出現專案輪播")
        }
    }

    func testSettingOff() {
        XCTAssertFalse(PanelRootView.showsProjectTicker(mode: .full, enabled: false))
    }

    func testDefaultsToOn() {
        XCTAssertTrue(Fixture.settings().showProjectTicker,
                      "預設要開——沒有交接紀錄的人本來就看不到那一塊")
    }

    func testSettingRoundTrips() {
        let settings = Fixture.settings()
        settings.showProjectTicker = false
        XCTAssertFalse(settings.showProjectTicker)
        settings.showProjectTicker = true
        XCTAssertTrue(settings.showProjectTicker)
    }
}
