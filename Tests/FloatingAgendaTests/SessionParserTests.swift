import XCTest
@testable import FloatingAgenda

/// `SessionParser` 是純函式，這裡的樣本全部用字串字面值，不碰檔案系統。
/// 讀檔那一側由 `ProjectStoreTests` 用暫存目錄驗。
final class SessionParserTests: XCTestCase {

    private let file = URL(fileURLWithPath: "/tmp/does-not-matter/latest.md")

    private func parse(_ text: String, directory: String = "專案A") -> ProjectItem? {
        SessionParser.parse(directoryName: directory, text: text, fileURL: file)
    }

    /// 交接文件的標準格式（handoff skill 產出的樣子）
    private let canonical = """
    # 專案甲

    > 路徑：~/專案甲
    > 最後更新：2026-09-18 15:20
    > 寫入者：claude
    > 觸發來源：handoff
    > 狀態：🟢 順暢

    ## 當前焦點

    做一個東西

    ## 進行中

    - [x] 第一階段
    - [x] 第二階段
    - [ ] 第三階段
    - [ ] 第四階段

    ## 下一步

    1. 繼續

    ## 卡住的點

    無

    ## 本輪決策

    - 用 A 不用 B
    """

    // MARK: - 標準格式

    func testParsesCanonicalDocument() throws {
        let item = try XCTUnwrap(parse(canonical))
        XCTAssertEqual(item.id, "專案A")
        XCTAssertEqual(item.name, "專案甲")
        XCTAssertEqual(item.status, .green)
        XCTAssertEqual(item.statusText, "🟢 順暢")
        XCTAssertEqual(item.done, 2)
        XCTAssertEqual(item.total, 4)
        XCTAssertEqual(item.openTodos, ["第三階段", "第四階段"])
        XCTAssertNil(item.blocker)
        XCTAssertEqual(item.updated, Fixture.date(2026, 9, 18, 15, 20))
    }

    // MARK: - 已搬遷

    func testMigratedProjectIsSkipped() {
        let text = "# 舊名稱（已搬遷 → 請讀 ../新名稱/latest.md）\n\n> 狀態：🟢 順暢\n"
        XCTAssertNil(parse(text))
    }

    /// 只有標題那行的「已搬遷」才算。出現在正文裡不該讓整個專案消失
    func testMigratedKeywordInBodyDoesNotSkipProject() throws {
        let text = "# 專案甲\n\n## 本輪決策\n\n- 討論過要不要已搬遷，結論是不搬\n"
        let item = try XCTUnwrap(parse(text))
        XCTAssertEqual(item.name, "專案甲")
    }

    // MARK: - 燈號

    func testStatusLights() {
        XCTAssertEqual(parse("> 狀態：🟢 順暢")?.status, .green)
        XCTAssertEqual(parse("> 狀態：🟡 進行中")?.status, .yellow)
        XCTAssertEqual(parse("> 狀態：🔴 卡住")?.status, .red)
    }

    func testStatusWithoutEmojiIsUnknown() throws {
        let item = try XCTUnwrap(parse("> 狀態：進行中"))
        XCTAssertEqual(item.status, .unknown)
        XCTAssertEqual(item.statusText, "進行中")
    }

    func testMissingStatusIsUnknownWithEmptyText() throws {
        let item = try XCTUnwrap(parse("# 專案甲\n"))
        XCTAssertEqual(item.status, .unknown)
        XCTAssertEqual(item.statusText, "")
    }

    /// 同時出現多個燈號時取最嚴重的：紅燈專案不該在清單裡看起來沒事
    func testMostSevereLightWins() {
        XCTAssertEqual(parse("> 狀態：🟢 順暢，但有一項 🔴")?.status, .red)
        XCTAssertEqual(parse("> 狀態：🟢 順暢，一項 🟡")?.status, .yellow)
    }

    // MARK: - 欄位容錯

    func testFieldToleratesHalfWidthColonAndSurroundingSpaces() throws {
        let item = try XCTUnwrap(parse("  >   狀態 : 🟡 進行中  \n  > 最後更新 : 2026-01-02 03:04\n"))
        XCTAssertEqual(item.status, .yellow)
        XCTAssertEqual(item.updated, Fixture.date(2026, 1, 2, 3, 4))
    }

    func testMalformedTimestampIsNil() {
        XCTAssertNil(parse("> 最後更新：昨天下午")?.updated)
        XCTAssertNil(parse("> 最後更新：2026/09/18 15:20")?.updated)
    }

    func testTimestampWithTrailingNoteStillParses() throws {
        let item = try XCTUnwrap(parse("> 最後更新：2026-09-18 15:20（補寫）"))
        XCTAssertEqual(item.updated, Fixture.date(2026, 9, 18, 15, 20))
    }

    // MARK: - 打勾項目

    /// 計畫 §5.2：打勾只算「進行中」這一段。
    /// 這個樣本在「進行中」以外刻意放了 3 個打勾項，算進去就會得到 4/6
    func testOnlyCountsCheckboxesInProgressSection() throws {
        let text = """
        # 專案甲

        ## 待處理

        - [ ] 不該被算到的 A
        - [x] 不該被算到的 B

        ## 進行中

        - [x] 算得到的一
        - [ ] 算得到的二

        ## 本輪決策

        - [x] 不該被算到的 C
        """
        let item = try XCTUnwrap(parse(text))
        XCTAssertEqual(item.done, 1)
        XCTAssertEqual(item.total, 2)
        XCTAssertEqual(item.openTodos, ["算得到的二"])
    }

    /// 沒有「進行中」這個區段時才退回整份檔案
    func testFallsBackToWholeFileWhenNoProgressSection() throws {
        let text = "# 專案甲\n\n## 待處理\n\n- [x] 一\n- [ ] 二\n- [ ] 三\n"
        let item = try XCTUnwrap(parse(text))
        XCTAssertEqual(item.done, 1)
        XCTAssertEqual(item.total, 3)
    }

    func testIndentedSubItemsAreCounted() throws {
        let text = "## 進行中\n\n- [ ] 上層\n    - [x] 子項\n        - [ ] 孫項\n"
        let item = try XCTUnwrap(parse(text))
        XCTAssertEqual(item.done, 1)
        XCTAssertEqual(item.total, 3)
        XCTAssertEqual(item.openTodos, ["上層", "孫項"])
    }

    func testUppercaseCheckmarkCountsAsDone() throws {
        let item = try XCTUnwrap(parse("## 進行中\n\n- [X] 大寫\n- [ ] 未完\n"))
        XCTAssertEqual(item.done, 1)
        XCTAssertEqual(item.total, 2)
    }

    func testAsteriskBulletIsAlsoAccepted() throws {
        let item = try XCTUnwrap(parse("## 進行中\n\n* [x] 一\n* [ ] 二\n"))
        XCTAssertEqual(item.total, 2)
    }

    func testNonCheckboxBulletsAreIgnored() throws {
        let item = try XCTUnwrap(parse("## 進行中\n\n- 普通項目\n- [ ] 真的待辦\n- [y] 壞掉的標記\n"))
        XCTAssertEqual(item.total, 1)
        XCTAssertEqual(item.openTodos, ["真的待辦"])
    }

    /// UI 上不該出現星號與反引號
    func testTodoTextStripsBoldAndCodeMarkers() throws {
        let item = try XCTUnwrap(parse("## 進行中\n\n- [ ] **重要**的 `PLAN.md` §4.9\n"))
        XCTAssertEqual(item.openTodos, ["重要的 PLAN.md §4.9"])
    }

    func testOpenTodosKeepOriginalOrder() throws {
        let item = try XCTUnwrap(parse("## 進行中\n\n- [ ] 丙\n- [x] 甲\n- [ ] 乙\n- [ ] 丁\n"))
        XCTAssertEqual(item.openTodos, ["丙", "乙", "丁"])
    }

    // MARK: - 卡住的點

    func testNoBlockerVariants() {
        for text in ["無", "無。", "無（上述收合高度疑點是待查證，不是卡住）", "無 ", "無(沒有)"] {
            XCTAssertNil(parse("## 卡住的點\n\n\(text)\n")?.blocker,
                         "「\(text)」應該算沒有卡住")
        }
    }

    /// ⚠️ 這條是刻意偏離計畫 §5.2 字面規則的地方，也是本檔最重要的一條測試。
    /// 計畫寫「以『無』開頭 → nil」，照字面實作會把「無法…」誤判成沒卡住。
    /// 把 `isNoBlocker` 換回字面規則，這個測試必須失敗
    func testBlockerStartingWithTheNoCharacterIsStillABlocker() throws {
        let item = try XCTUnwrap(parse("## 卡住的點\n\n無法連線到 API，等對方開通\n"))
        XCTAssertEqual(item.blocker, "無法連線到 API，等對方開通")
    }

    /// 括號只在緊接著「無」時才是補充說明。
    /// 早期版本砍掉「第一個括號之後的全部內容」，會讓這一句變成空字串而誤判成沒卡住
    func testLeadingBracketDoesNotSwallowTheBlocker() throws {
        let item = try XCTUnwrap(parse("## 卡住的點\n\n（後端）API 無法連線\n"))
        XCTAssertEqual(item.blocker, "（後端）API 無法連線")
    }

    /// 真實交接檔出現過的寫法：開頭是「無」但後面接了真正待處理的事
    func testNoTechnicalBlockerButSomethingPendingIsStillABlocker() throws {
        let text = "## 卡住的點\n\n無技術卡點，但有一項流程偏差待使用者裁決\n"
        let item = try XCTUnwrap(parse(text))
        XCTAssertEqual(item.blocker, "無技術卡點，但有一項流程偏差待使用者裁決")
    }

    func testBlockerTakesFirstParagraphOnly() throws {
        let text = """
        ## 卡住的點

        第一段第一行
        第一段第二行

        第二段不該被帶進來

        ## 本輪決策
        """
        let item = try XCTUnwrap(parse(text))
        XCTAssertEqual(item.blocker, "第一段第一行 第一段第二行")
    }

    /// 下一個標題**緊接在**卡住原因後面，中間沒有空行。
    /// 這樣才真的在測「區段擷取有沒有在下一個 `## ` 停下來」——
    /// 中間留空行的話，段落迴圈本來就會停，測試不管 `section()` 對錯都會通過
    /// （codex 2026-09-22 指出原本那版沒有鑑別力）
    func testBlockerStopsAtNextSection() throws {
        let item = try XCTUnwrap(parse("## 卡住的點\n\n卡住原因\n## 本輪決策\n不該出現\n"))
        XCTAssertEqual(item.blocker, "卡住原因")
    }

    func testMissingBlockerSectionIsNil() {
        XCTAssertNil(parse("# 專案甲\n\n## 進行中\n\n- [ ] 一\n")?.blocker)
    }

    func testEmptyBlockerSectionIsNil() {
        XCTAssertNil(parse("## 卡住的點\n\n\n## 本輪決策\n")?.blocker)
    }

    // MARK: - 髒輸入

    func testHandlesCRLFLineEndings() throws {
        let text = "# 專案甲\r\n\r\n> 狀態：🟡 進行中\r\n\r\n## 進行中\r\n\r\n- [x] 一\r\n- [ ] 二\r\n"
        let item = try XCTUnwrap(parse(text))
        XCTAssertEqual(item.name, "專案甲")
        XCTAssertEqual(item.status, .yellow)
        XCTAssertEqual(item.done, 1)
        XCTAssertEqual(item.total, 2)
    }

    func testHandlesLeadingByteOrderMark() throws {
        let item = try XCTUnwrap(parse("\u{FEFF}# 專案甲\n\n> 狀態：🔴 卡住\n"))
        XCTAssertEqual(item.name, "專案甲")
        XCTAssertEqual(item.status, .red)
    }

    /// 完全空白的檔案要回傳全預設值的 ProjectItem，名稱用目錄名稱（§5.2）
    func testBlankFileYieldsDefaultsNamedAfterDirectory() throws {
        let item = try XCTUnwrap(parse("   \n\n \n", directory: "空專案"))
        XCTAssertEqual(item.id, "空專案")
        XCTAssertEqual(item.name, "空專案")
        XCTAssertEqual(item.status, .unknown)
        XCTAssertEqual(item.statusText, "")
        XCTAssertNil(item.updated)
        XCTAssertEqual(item.done, 0)
        XCTAssertEqual(item.total, 0)
        XCTAssertTrue(item.openTodos.isEmpty)
        XCTAssertNil(item.blocker)
    }

    func testMissingHeadingFallsBackToDirectoryName() throws {
        let item = try XCTUnwrap(parse("> 狀態：🟢 順暢\n", directory: "沒有標題"))
        XCTAssertEqual(item.name, "沒有標題")
    }

    /// `#標題`（少了空白）不是 markdown 標題，不該被當成名稱
    func testHashWithoutSpaceIsNotAHeading() throws {
        let item = try XCTUnwrap(parse("#不是標題\n", directory: "目錄名"))
        XCTAssertEqual(item.name, "目錄名")
    }

    // MARK: - 排序

    /// id 同樣刻意與預期順序相反
    func testBlockedProjectSortsBeforeEverythingElse() {
        let blockedGreen = make(id: "zzz", status: .green, blocker: "卡住了")
        let red = make(id: "aaa", status: .red, blocker: nil)
        XCTAssertTrue(ProjectStore.order(blockedGreen, red))
        XCTAssertFalse(ProjectStore.order(red, blockedGreen))
    }

    /// ⚠️ id 刻意設成**與預期順序相反**（排前面的拿 "z"、排後面的拿 "a"）。
    /// 兩邊都用 "x"/"y" 那種遞增 id 的話，就算把燈號排序整個拿掉、只按 id 比，
    /// 測試照樣會通過（codex 2026-09-22 指出）
    func testLightsSortRedYellowGreenUnknown() {
        let order: [ProjectStatus] = [.red, .yellow, .green, .unknown]
        for (index, earlier) in order.enumerated() {
            for later in order[(index + 1)...] {
                XCTAssertTrue(ProjectStore.order(make(id: "zzz", status: earlier),
                                                 make(id: "aaa", status: later)),
                              "\(earlier) 應該排在 \(later) 前面")
            }
        }
    }

    /// id 同樣刻意與預期順序相反
    func testSameLightSortsByUpdatedDescending() {
        let newer = make(id: "zzz", status: .green, updated: Fixture.date(2026, 9, 20, 10, 0))
        let older = make(id: "aaa", status: .green, updated: Fixture.date(2026, 9, 19, 10, 0))
        XCTAssertTrue(ProjectStore.order(newer, older))
        XCTAssertFalse(ProjectStore.order(older, newer))
    }

    /// id 同樣刻意與預期順序相反
    func testProjectsWithoutTimestampSortLast() {
        let dated = make(id: "zzz", status: .green, updated: Fixture.date(2026, 9, 1, 0, 0))
        let undated = make(id: "aaa", status: .green, updated: nil)
        XCTAssertTrue(ProjectStore.order(dated, undated))
        XCTAssertFalse(ProjectStore.order(undated, dated))
    }

    /// 少了 id 決勝，同級同時間的兩筆順序在重讀之間不穩定
    func testTieBreaksOnIDForStableOrder() {
        let same = Fixture.date(2026, 9, 20, 10, 0)
        XCTAssertTrue(ProjectStore.order(make(id: "aaa", status: .green, updated: same),
                                         make(id: "bbb", status: .green, updated: same)))
        XCTAssertFalse(ProjectStore.order(make(id: "bbb", status: .green, updated: same),
                                          make(id: "aaa", status: .green, updated: same)))
    }

    private func make(id: String,
                      status: ProjectStatus,
                      blocker: String? = nil,
                      updated: Date? = nil) -> ProjectItem {
        ProjectItem(id: id, name: id, status: status, statusText: "",
                    updated: updated, done: 0, total: 0, openTodos: [],
                    blocker: blocker, fileURL: file)
    }
}
