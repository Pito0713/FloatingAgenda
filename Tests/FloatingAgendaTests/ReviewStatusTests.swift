import XCTest
@testable import FloatingAgenda

/// project-review 的 `status.json`（ADR-032）：解析、顯示哪一句、從磁碟讀進 `ProjectItem`。
///
/// ⚠️ 讀磁碟的測試一律在 `temporaryDirectory` 底下自己建樹，
/// **不會讀到使用者真正的 `~/.agent-reports`**
final class ReviewStatusTests: XCTestCase {

    private let ranAt = "2026-11-10T09:00:08+08:00"

    private func json(overall: String = "ok",
                      ranAt: String? = nil,
                      l1: String = "pass",
                      failed: [String] = [],
                      carried: Bool = false,
                      l2Findings: Int = 0,
                      l3Findings: Int = 0,
                      handoff: String = #"{ "updatedAt": "2026-11-06 11:09", "lagCommits": 1 }"#,
                      errors: [String] = []) -> Data {
        let failedJSON = failed.map { "\"\($0)\"" }.joined(separator: ",")
        let errorsJSON = errors.map { "\"\($0)\"" }.joined(separator: ",")
        return Data("""
        { "schema": 1, "project": "Floating", "ranAt": "\(ranAt ?? self.ranAt)", "commit": "c12549d",
          "changed": true,
          "l1": { "result": "\(l1)", "checks": {"test":"\(l1)"}, "failed": [\(failedJSON)], "carried": \(carried) },
          "l2": { "result": "ok", "newFindings": \(l2Findings), "highSeverity": 0 },
          "l3": { "result": "skipped", "newFindings": \(l3Findings), "highSeverity": 0 },
          "handoff": \(handoff),
          "reportPath": "/tmp/report.md",
          "errors": [\(errorsJSON)],
          "overall": "\(overall)" }
        """.utf8)
    }

    // MARK: - 解析

    func testParsesTheDocumentedExample() throws {
        let status = try XCTUnwrap(ReviewStatusParser.parse(json()))
        XCTAssertEqual(status.overall, .ok)
        XCTAssertEqual(status.ranAt, ReviewStatusParser.date(from: ranAt))
        XCTAssertEqual(status.l1Result, "pass")
        XCTAssertEqual(status.lagCommits, 1)
        XCTAssertEqual(status.reportURL, URL(fileURLWithPath: "/tmp/report.md"))
        XCTAssertNil(status.firstError)
    }

    func testFindingsAreSummedAcrossL2AndL3() throws {
        let status = try XCTUnwrap(ReviewStatusParser.parse(json(l2Findings: 2, l3Findings: 3)))
        XCTAssertEqual(status.newFindings, 5)
    }

    func testNullHandoffAndNullLagAreAccepted() throws {
        XCTAssertNil(try XCTUnwrap(ReviewStatusParser.parse(json(handoff: "null"))).lagCommits)
        XCTAssertNil(try XCTUnwrap(ReviewStatusParser.parse(
            json(handoff: #"{ "updatedAt": null, "lagCommits": null }"#))).lagCommits)
    }

    func testUnknownOverallOrBadDateIsRejected() {
        // 壞掉的報告不顯示那一行，比顯示一句錯的話好
        XCTAssertNil(ReviewStatusParser.parse(json(overall: "mystery")))
        XCTAssertNil(ReviewStatusParser.parse(json(ranAt: "昨天")))
        XCTAssertNil(ReviewStatusParser.parse(Data("not json".utf8)))
    }

    func testFractionalSecondsAreAccepted() {
        XCTAssertNotNil(ReviewStatusParser.date(from: "2026-11-10T09:00:08.123+08:00"))
    }

    // MARK: - 顯示哪一句

    private func status(_ data: Data) throws -> ReviewStatus {
        try XCTUnwrap(ReviewStatusParser.parse(data))
    }

    private var justAfter: Date {
        ReviewStatusParser.date(from: ranAt)!.addingTimeInterval(3600)
    }

    func testFailureNamesTheFailedChecks() throws {
        let line = ReviewStatusDisplay.line(
            for: try status(json(overall: "fail", l1: "fail", failed: ["test"], handoff: "null")),
            now: justAfter)
        XCTAssertTrue(line.text.hasPrefix("🔴 測試失敗（test）"), line.text)
        XCTAssertEqual(line.tone, .failure)
    }

    func testCrashShowsTheFirstError() throws {
        let line = ReviewStatusDisplay.line(
            for: try status(json(overall: "crash", handoff: "null", errors: ["swift 找不到"])),
            now: justAfter)
        XCTAssertTrue(line.text.hasPrefix("💥 review 執行失敗：swift 找不到"), line.text)
    }

    func testStaleAfter36HoursOutranksWarnAndOk() throws {
        let stale = ReviewStatusParser.date(from: ranAt)!.addingTimeInterval(37 * 3600)
        for overall in ["warn", "ok", "idle"] {
            let line = ReviewStatusDisplay.line(for: try status(json(overall: overall, handoff: "null")),
                                                now: stale)
            XCTAssertEqual(line.text, "⏳ 上次 review 1 天前", overall)
        }
    }

    func testNotStaleJustUnder36Hours() throws {
        let fresh = ReviewStatusParser.date(from: ranAt)!.addingTimeInterval(35 * 3600)
        let line = ReviewStatusDisplay.line(for: try status(json(handoff: "null")), now: fresh)
        XCTAssertTrue(line.text.hasPrefix("✅"), line.text)
    }

    func testFailureIsNotHiddenByStaleness() throws {
        // 失敗比過期嚴重：三天前的失敗仍然要講失敗
        let old = ReviewStatusParser.date(from: ranAt)!.addingTimeInterval(72 * 3600)
        let line = ReviewStatusDisplay.line(
            for: try status(json(overall: "fail", l1: "fail", handoff: "null")), now: old)
        XCTAssertTrue(line.text.hasPrefix("🔴"), line.text)
    }

    func testWarnDescribesFlakyAndFindings() throws {
        let line = ReviewStatusDisplay.line(
            for: try status(json(overall: "warn", l1: "flaky", l2Findings: 2, handoff: "null")),
            now: justAfter)
        XCTAssertTrue(line.text.hasPrefix("⚠️ 測試不穩定、2 新發現"), line.text)
        XCTAssertEqual(line.tone, .warning)
    }

    func testCarriedOkSaysItReusedTheLastResult() throws {
        let line = ReviewStatusDisplay.line(for: try status(json(carried: true, handoff: "null")),
                                            now: justAfter)
        XCTAssertTrue(line.text.contains("沿用上次"), line.text)
    }

    func testHandoffLagIsAppendedOnlyWhenPositive() throws {
        XCTAssertTrue(ReviewStatusDisplay.line(for: try status(json()), now: justAfter)
            .text.hasSuffix("· 交接落後 1 commits"))
        let zero = try status(json(handoff: #"{ "updatedAt": "x", "lagCommits": 0 }"#))
        XCTAssertFalse(ReviewStatusDisplay.line(for: zero, now: justAfter).text.contains("交接落後"))
    }

    // MARK: - 從磁碟讀

    func testScanAttachesReviewOnlyWhenAReviewRootIsGiven() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviewStatusTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let sessions = base.appendingPathComponent("sessions", isDirectory: true)
        let reviews = base.appendingPathComponent("reviews", isDirectory: true)
        for name in ["有報告", "沒報告"] {
            let dir = sessions.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("# \(name)\n> 狀態：🟢 順暢\n".utf8)
                .write(to: dir.appendingPathComponent("latest.md"))
        }
        let reviewDir = reviews.appendingPathComponent("有報告", isDirectory: true)
        try FileManager.default.createDirectory(at: reviewDir, withIntermediateDirectories: true)
        let statusFile = reviewDir.appendingPathComponent("status.json")
        try json().write(to: statusFile)
        let before = try FileManager.default.attributesOfItem(atPath: statusFile.path)

        guard case .loaded(let withReview, _) = ProjectStore.scan(root: sessions, reviewRoot: reviews),
              case .loaded(let withoutRoot, _) = ProjectStore.scan(root: sessions) else {
            return XCTFail("掃描應該成功")
        }
        XCTAssertEqual(withReview.first { $0.id == "有報告" }?.review?.overall, .ok)
        XCTAssertNil(withReview.first { $0.id == "沒報告" }?.review, "沒有 status.json 就不顯示那一行")
        XCTAssertTrue(withoutRoot.allSatisfy { $0.review == nil })

        // 唯讀：內容與修改時間都不能變
        let after = try FileManager.default.attributesOfItem(atPath: statusFile.path)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        XCTAssertEqual(try Data(contentsOf: statusFile), json())
    }

    func testOversizedStatusFileIsIgnored() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviewStatusTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.appendingPathComponent("P", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var data = json()
        data.append(Data(repeating: 0x20, count: ReviewStatusParser.maxFileBytes))
        try data.write(to: dir.appendingPathComponent("status.json"))

        XCTAssertNil(ReviewStatusParser.read(projectID: "P", root: base))
    }
}
