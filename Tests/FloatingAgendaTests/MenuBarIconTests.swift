import XCTest
@testable import FloatingAgenda

@MainActor
final class MenuBarIconTests: XCTestCase {
    /// 狀態點的語意必須跟小精靈的心情同一套，不能各說各話
    func testDotOnlyAppearsWhenThereIsSomethingToDo() {
        XCTAssertEqual(MenuBarIcon.dot(for: .worried), .filled, "逾期／卡住要畫實心點")
        XCTAssertEqual(MenuBarIcon.dot(for: .busy), .hollow, "今天還有事要做，畫空心點")
        XCTAssertNil(MenuBarIcon.dot(for: .happy), "全部清空不該有任何標記")
        XCTAssertNil(MenuBarIcon.dot(for: .sleepy), "讀不到資料時不能宣稱有事")
    }

    func testMaskIsCanvasSized() {
        for mood in Mood.allCases {
            let mask = MenuBarIcon.mask(mood: mood)
            XCTAssertEqual(mask.count, MenuBarIcon.canvasSide)
            XCTAssertEqual(Set(mask.map(\.count)), [MenuBarIcon.canvasSide])
        }
    }

    func testHatAndStarRemainDistinctAtMenuBarSize() throws {
        let silhouette = try XCTUnwrap(MenuBarIcon.silhouette(mood: .happy))
        XCTAssertTrue(silhouette[10][6], "帽身保持實心")
        XCTAssertTrue(silhouette[7][14], "帽尖星飾可見")
        XCTAssertFalse(silhouette[9][11], "帽身與星飾之間留白")
        XCTAssertTrue(silhouette[15][7], "帽緣可見")
    }

    /// 狀態點放在右下角**不需要挖掉角色身體**——這是選 18×18 畫布的理由。
    /// 哪天有人把角色改大或把點挪位置，這條會先失敗
    func testDotDoesNotCollideWithTheCharacter() throws {
        let origin = MenuBarIcon.canvasSide - MenuBarIcon.dotSide
        for mood in Mood.allCases {
            let silhouette = try XCTUnwrap(MenuBarIcon.silhouette(mood: mood))
            for y in origin..<MenuBarIcon.canvasSide where y < silhouette.count {
                for x in origin..<MenuBarIcon.canvasSide where x < silhouette[y].count {
                    XCTAssertFalse(silhouette[y][x],
                                   "\(mood) 的第 \(y) 列第 \(x) 欄撞到狀態點的位置")
                }
            }
        }
    }

    func testMaskCarriesTheDotForBusyMoods() {
        let origin = MenuBarIcon.canvasSide - MenuBarIcon.dotSide
        let worried = MenuBarIcon.mask(mood: .worried)
        XCTAssertTrue(worried[origin + 1][origin + 1], "實心點的中心要是實的")

        let busy = MenuBarIcon.mask(mood: .busy)
        XCTAssertTrue(busy[origin][origin + 1], "空心點的上緣要是實的")
        XCTAssertFalse(busy[origin + 1][origin + 1], "空心點的中心必須是空的")

        let happy = MenuBarIcon.mask(mood: .happy)
        for y in origin..<MenuBarIcon.canvasSide {
            for x in origin..<MenuBarIcon.canvasSide {
                XCTAssertFalse(happy[y][x], "沒事的時候右下角要乾乾淨淨")
            }
        }
    }

    /// 少了 `isTemplate`，深色選單列、桌布染色與選單開啟時的反白都會壞掉
    func testImageIsATemplateAtCanvasSize() {
        let image = MenuBarIcon.image(mood: .busy)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size,
                       NSSize(width: MenuBarIcon.canvasSide, height: MenuBarIcon.canvasSide))
        XCTAssertTrue(MenuBarIcon.image(mood: .busy) === image, "同一種心情要拿到快取的那一張")
    }
}
