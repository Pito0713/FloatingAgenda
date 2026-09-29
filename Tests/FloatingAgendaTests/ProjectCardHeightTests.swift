import AppKit
import SwiftUI
import XCTest
@testable import FloatingAgenda

/// 專案卡固定高度（使用者 2026-09-29 決定 90pt）。
///
/// 輪播每 8 秒換一張卡，卡片高度只要不一樣，整個面板就會跟著上下跳——
/// 使用者實際回報的就是這個抖動（實測真實資料落差 98pt）。
/// 這裡用 `NSHostingView` 量真實的排版結果，兩件事各驗一次：
/// 外層永遠 90pt（不抖），內容不超過 90pt（沒被 `clipped()` 切到）。
@MainActor
final class ProjectCardHeightTests: XCTestCase {

    /// 卡片在面板裡的實際可用寬度
    private let width = PanelMetrics.width - PanelMetrics.padding * 2

    /// 會遇到的所有形狀：有沒有更新時間 × 有沒有卡住的點 × 待辦 0…6 項
    private var shapes: [ProjectItem] {
        var items: [ProjectItem] = []
        for hasUpdated in [true, false] {
            for blocker in [nil,
                            "等對方回覆",
                            String(repeating: "很長的卡住描述，", count: 12)] {
                for todoCount in 0...6 {
                    items.append(project(todoCount: todoCount,
                                         blocker: blocker,
                                         updated: hasUpdated ? Date() : nil))
                }
            }
        }
        return items
    }

    func testEveryCardIsExactlyTheSameHeight() {
        for project in shapes {
            XCTAssertEqual(height(of: ProjectCardView(project: project)),
                           ProjectCardView.fixedHeight,
                           "卡片高度不一致就會抖動：待辦 \(project.openTodos.count) 項、"
                           + "卡住 \(project.blocker == nil ? "無" : "有")、"
                           + "更新時間 \(project.updated == nil ? "無" : "有")")
        }
    }

    func testContentNeverOverflowsTheFixedHeight() {
        for project in shapes {
            let natural = height(of: ProjectCardView(project: project).card)
            XCTAssertLessThanOrEqual(natural, ProjectCardView.fixedHeight,
                                     "內容 \(natural)pt 超過 \(ProjectCardView.fixedHeight)pt，"
                                     + "會被 clipped() 切掉半列；"
                                     + "待辦 \(project.openTodos.count) 項、"
                                     + "卡住 \(project.blocker == nil ? "無" : "有")")
        }
    }

    /// 少列幾項是**算出來**的，不是畫出來再裁。這條釘住那個算術
    func testTodoCountShrinksWhenThereIsABlocker() {
        let withBlocker = project(todoCount: 5, blocker: "卡住了", updated: Date())
        let without = project(todoCount: 5, blocker: nil, updated: Date())

        XCTAssertEqual(ProjectCardView.visibleTodoCount(for: withBlocker), 1)
        XCTAssertEqual(ProjectCardView.visibleTodoCount(for: without), 2)
    }

    func testNeverShowsMoreThanTheProjectHas() {
        let one = project(todoCount: 1, blocker: nil, updated: nil)
        XCTAssertEqual(ProjectCardView.visibleTodoCount(for: one), 1)

        let none = project(todoCount: 0, blocker: nil, updated: nil)
        XCTAssertEqual(ProjectCardView.visibleTodoCount(for: none), 0)
    }

    func testStillCappedByTodoLimitWhenThereIsPlentyOfRoom() {
        // 沒有更新時間也沒有卡住的點時空間最多，但一張卡最多就是列 3 項
        let roomy = project(todoCount: 9, blocker: nil, updated: nil)
        XCTAssertEqual(ProjectCardView.visibleTodoCount(for: roomy), ProjectCardView.todoLimit)
    }

    // MARK: - 工具

    private func height(of view: some View) -> CGFloat {
        let hosting = NSHostingView(rootView: view
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    private func project(todoCount: Int, blocker: String?, updated: Date?) -> ProjectItem {
        ProjectItem(id: "P",
                    name: "測試專案",
                    status: .yellow,
                    statusText: "🟡 進行中",
                    updated: updated,
                    done: 3,
                    total: 8,
                    openTodos: (0..<todoCount).map { "第 \($0 + 1) 項待辦，寫長一點看看會不會換行" },
                    blocker: blocker,
                    fileURL: URL(fileURLWithPath: "/tmp/P/latest.md"))
    }
}
