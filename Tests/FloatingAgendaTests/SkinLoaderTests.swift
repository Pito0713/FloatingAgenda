import XCTest
@testable import FloatingAgenda

/// 外部皮膚的載入與驗證（M9 計畫 §4.6）。
///
/// ⚠️ 每個測試都在 `temporaryDirectory` 底下自己建皮膚，測完刪掉。
/// **絕不寫進使用者真正的 `~/Library/Application Support/FloatingAgenda/Skins`**（§8）。
final class SkinLoaderTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    // MARK: - 建樣本

    /// 產一張指定尺寸的 PNG
    private func png(_ side: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side,
                                              bitsPerComponent: 8, bytesPerRow: side * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemPink.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try XCTUnwrap(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func manifest(formatVersion: Int = 1,
                          name: String = "測試皮膚",
                          pixelSize: Int = 16,
                          fps: Int = 4,
                          frames: [String: [String]]? = nil,
                          blink: String? = "blink.png") -> String {
        let defaultFrames: [String: [String]] = [
            "happy": ["happy-0.png"], "busy": ["busy-0.png"],
            "worried": ["worried-0.png"], "sleepy": ["sleepy-0.png"],
        ]
        let used = frames ?? defaultFrames
        let framesJSON = used.map { "\"\($0.key)\": [\($0.value.map { "\"\($0)\"" }.joined(separator: ", "))]" }
            .sorted().joined(separator: ", ")
        let blinkJSON = blink.map { ", \"blink\": \"\($0)\"" } ?? ""
        return """
        { "formatVersion": \(formatVersion), "name": "\(name)", "pixelSize": \(pixelSize),
          "fps": \(fps), "frames": { \(framesJSON) }\(blinkJSON) }
        """
    }

    /// 建一個預設就合法的皮膚，`configure` 可以再把它弄壞
    @discardableResult
    private func makeSkin(_ folderName: String = "my-skin",
                          manifestJSON: String? = nil,
                          imageSide: Int = 16,
                          images: [String]? = nil) throws -> URL {
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try (manifestJSON ?? manifest()).write(
            to: folder.appendingPathComponent("skin.json"), atomically: true, encoding: .utf8)
        let names = images ?? ["happy-0.png", "busy-0.png", "worried-0.png",
                               "sleepy-0.png", "blink.png"]
        let data = try png(imageSide)
        for name in names {
            try data.write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    private func loadError(_ folder: URL) -> SkinError? {
        do {
            _ = try SkinLoader.load(folder: folder)
            return nil
        } catch let error as SkinError {
            return error
        } catch {
            return nil
        }
    }

    // MARK: - 合法的皮膚

    func testLoadsAValidSkin() throws {
        let folder = try makeSkin()
        let skin = try SkinLoader.load(folder: folder)

        XCTAssertEqual(skin.id, "skin.my-skin")
        XCTAssertEqual(skin.name, "測試皮膚")
        XCTAssertEqual(skin.fps, 4)
        XCTAssertNotNil(skin.blink)
        for mood in Mood.allCases {
            XCTAssertEqual(skin.frames[mood]?.count, 1, "\(mood) 應該有 1 格")
        }
    }

    /// `blink` 是選用的，沒有就不眨眼
    func testBlinkIsOptional() throws {
        let folder = try makeSkin(manifestJSON: manifest(blink: nil),
                                  images: ["happy-0.png", "busy-0.png",
                                           "worried-0.png", "sleepy-0.png"])
        let skin = try SkinLoader.load(folder: folder)
        XCTAssertNil(skin.blink)
    }

    /// 名稱是空白時退回資料夾名稱，選單才不會出現空白項目
    func testEmptyNameFallsBackToFolderName() throws {
        let folder = try makeSkin("cat", manifestJSON: manifest(name: "   "))
        XCTAssertEqual(try SkinLoader.load(folder: folder).name, "cat")
    }

    // MARK: - §4.6 每一條驗證規則的反例

    func testRejectsMissingManifest() throws {
        let folder = root.appendingPathComponent("no-manifest", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertEqual(loadError(folder), .missingFile("skin.json"))
    }

    func testRejectsMalformedManifest() throws {
        let folder = try makeSkin(manifestJSON: "{ 這不是 JSON")
        XCTAssertEqual(loadError(folder), .badManifest)
    }

    func testRejectsWrongFormatVersion() throws {
        let folder = try makeSkin(manifestJSON: manifest(formatVersion: 2))
        XCTAssertEqual(loadError(folder), .unsupportedFormatVersion(2))
    }

    /// pixelSize 必須在 8…64
    func testRejectsPixelSizeOutOfRange() throws {
        for size in [7, 65, 0, -1] {
            let folder = try makeSkin("size-\(size)",
                                      manifestJSON: manifest(pixelSize: size))
            XCTAssertEqual(loadError(folder), .pixelSizeOutOfRange(size), "pixelSize \(size)")
        }
    }

    func testAcceptsPixelSizeAtBothBounds() throws {
        for size in [8, 64] {
            let folder = try makeSkin("ok-\(size)",
                                      manifestJSON: manifest(pixelSize: size),
                                      imageSide: size)
            XCTAssertNoThrow(try SkinLoader.load(folder: folder), "pixelSize \(size) 應該合法")
        }
    }

    /// fps 必須在 1…12
    func testRejectsFPSOutOfRange() throws {
        for fps in [0, 13, -5] {
            let folder = try makeSkin("fps-\(fps)", manifestJSON: manifest(fps: fps))
            XCTAssertEqual(loadError(folder), .fpsOutOfRange(fps), "fps \(fps)")
        }
    }

    func testAcceptsFPSAtBothBounds() throws {
        for fps in [1, 12] {
            let folder = try makeSkin("fpsok-\(fps)", manifestJSON: manifest(fps: fps))
            XCTAssertNoThrow(try SkinLoader.load(folder: folder), "fps \(fps) 應該合法")
        }
    }

    /// 四種心情都要至少 1 格
    func testRejectsMissingMood() throws {
        for missing in Mood.allCases {
            var frames: [String: [String]] = [:]
            for mood in Mood.allCases where mood != missing {
                frames[mood.rawValue] = ["\(mood.rawValue)-0.png"]
            }
            let folder = try makeSkin("missing-\(missing.rawValue)",
                                      manifestJSON: manifest(frames: frames))
            XCTAssertEqual(loadError(folder), .missingMood(missing.rawValue))
        }
    }

    func testRejectsEmptyFrameList() throws {
        var frames: [String: [String]] = [:]
        for mood in Mood.allCases { frames[mood.rawValue] = ["\(mood.rawValue)-0.png"] }
        frames["happy"] = []
        let folder = try makeSkin(manifestJSON: manifest(frames: frames))
        XCTAssertEqual(loadError(folder), .missingMood("happy"))
    }

    /// 圖片尺寸必須剛好等於 pixelSize
    func testRejectsWrongImageSize() throws {
        let folder = try makeSkin(manifestJSON: manifest(pixelSize: 16), imageSide: 32)
        guard case .wrongImageSize(_, let width, let height, let expected) = loadError(folder) else {
            return XCTFail("應該回報尺寸不符")
        }
        XCTAssertEqual([width, height, expected], [32, 32, 16])
    }

    func testRejectsNonPNG() throws {
        let folder = try makeSkin("not-png")
        try Data("我不是圖片".utf8).write(to: folder.appendingPathComponent("happy-0.png"))
        XCTAssertEqual(loadError(folder), .notAPNG("happy-0.png"))
    }

    func testRejectsMissingImage() throws {
        let folder = try makeSkin("missing-image")
        try FileManager.default.removeItem(at: folder.appendingPathComponent("busy-0.png"))
        XCTAssertEqual(loadError(folder), .missingFile("busy-0.png"))
    }

    /// 檔名不接受路徑分隔與 `..`
    func testRejectsUnsafeFileNames() throws {
        for unsafe in ["../outside.png", "sub/inner.png", "..", "."] {
            var frames: [String: [String]] = [:]
            for mood in Mood.allCases { frames[mood.rawValue] = ["\(mood.rawValue)-0.png"] }
            frames["happy"] = [unsafe]
            let folder = try makeSkin("unsafe-\(abs(unsafe.hashValue))",
                                      manifestJSON: manifest(frames: frames))
            guard case .unsafeFileName = loadError(folder) else {
                return XCTFail("「\(unsafe)」應該被擋下")
            }
        }
    }

    /// 不跟隨指向資料夾外面的 symlink
    func testRejectsSymlinkEscapingTheFolder() throws {
        let outside = root.appendingPathComponent("outside.png")
        try png(16).write(to: outside)
        let folder = try makeSkin("symlink")
        let link = folder.appendingPathComponent("happy-0.png")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        guard case .escapesFolder = loadError(folder) else {
            return XCTFail("指到資料夾外面的 symlink 應該被擋下")
        }
    }

    /// 指向**同一個資料夾內**的 symlink 是可以的
    func testAllowsSymlinkInsideTheFolder() throws {
        let folder = try makeSkin("inner-symlink")
        let link = folder.appendingPathComponent("happy-0.png")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: folder.appendingPathComponent("busy-0.png"))
        XCTAssertNoThrow(try SkinLoader.load(folder: folder))
    }

    /// skin.json 上限 64KB
    func testRejectsOversizedManifest() throws {
        let padding = String(repeating: "x", count: SkinLoader.maxManifestBytes)
        let folder = try makeSkin(manifestJSON: manifest(name: padding))
        XCTAssertEqual(loadError(folder), .fileTooLarge("skin.json"))
    }

    /// 單張圖片上限 256KB
    func testRejectsOversizedImage() throws {
        let folder = try makeSkin("big-image")
        let big = Data(repeating: 0x89, count: SkinLoader.maxImageBytes + 1)
        try big.write(to: folder.appendingPathComponent("happy-0.png"))
        XCTAssertEqual(loadError(folder), .fileTooLarge("happy-0.png"))
    }

    /// 一個皮膚最多 64 張圖
    func testRejectsTooManyImages() throws {
        var frames: [String: [String]] = [:]
        for mood in Mood.allCases { frames[mood.rawValue] = ["\(mood.rawValue)-0.png"] }
        frames["happy"] = (0..<70).map { "happy-\($0).png" }
        let folder = try makeSkin("too-many", manifestJSON: manifest(frames: frames))
        guard case .tooManyImages = loadError(folder) else {
            return XCTFail("超過 64 張應該被擋下")
        }
    }

    // MARK: - 掃描

    /// 壞掉的皮膚不能讓整個掃描失敗，好的還是要載得到
    func testScanKeepsGoodSkinsAndReportsBadOnes() throws {
        try makeSkin("good")
        try makeSkin("bad", manifestJSON: manifest(formatVersion: 99))

        let result = SkinLoader.scan(directory: root)
        XCTAssertEqual(result.skins.map(\.id), ["skin.good"])
        XCTAssertEqual(result.rejected.map(\.folder), ["bad"])
        XCTAssertTrue(result.rejected[0].reason.contains("formatVersion"),
                      "原因要說得出是哪裡不合格：\(result.rejected[0].reason)")
    }

    /// 資料夾不存在不算錯誤——大多數使用者不會有自製皮膚
    func testScanningAMissingDirectoryIsNotAnError() {
        let missing = root.appendingPathComponent("nope", isDirectory: true)
        let result = SkinLoader.scan(directory: missing)
        XCTAssertTrue(result.skins.isEmpty)
        XCTAssertTrue(result.rejected.isEmpty)
    }

    /// 第一層的散檔不是皮膚
    func testScanIgnoresLooseFiles() throws {
        try makeSkin("good")
        try Data("x".utf8).write(to: root.appendingPathComponent("README.txt"))
        XCTAssertEqual(SkinLoader.scan(directory: root).skins.map(\.id), ["skin.good"])
    }

    func testScanIsSortedForStableMenuOrder() throws {
        for name in ["zeta", "alpha", "middle"] { try makeSkin(name) }
        XCTAssertEqual(SkinLoader.scan(directory: root).skins.map(\.name),
                       ["測試皮膚", "測試皮膚", "測試皮膚"])
        XCTAssertEqual(SkinLoader.scan(directory: root).skins.map(\.id),
                       ["skin.alpha", "skin.middle", "skin.zeta"])
    }

    // MARK: - 內建角色

    @MainActor
    func testBuiltinSkinIsAlwaysAvailable() {
        let skin = CharacterAnimation.builtinSkin
        XCTAssertEqual(skin.id, BuiltinCharacter.id)
        for mood in Mood.allCases {
            XCTAssertFalse(skin.frames[mood]?.isEmpty ?? true, "\(mood) 要有動畫格")
        }
    }

    /// 內建角色的 id 不能跟外部皮膚撞號（外部一律加 `skin.` 前綴）
    @MainActor
    func testBuiltinIDCannotCollideWithExternalSkins() throws {
        let folder = try makeSkin("pixel")
        XCTAssertNotEqual(try SkinLoader.load(folder: folder).id,
                          CharacterAnimation.builtinSkin.id)
    }
}

/// codex 2026-09-22 指出的幾條安全性與正確性問題的回歸測試
extension SkinLoaderTests {

    /// ⚠️ FIFO（具名管道）開起來或讀起來會**永遠阻塞**。
    /// 沒有「先確認是一般檔案」這道檢查，一個異常皮膚就能讓掃描卡死
    func testRejectsFIFOInsteadOfBlockingForever() throws {
        let folder = try makeSkin("fifo")
        let target = folder.appendingPathComponent("happy-0.png")
        try FileManager.default.removeItem(at: target)
        XCTAssertEqual(mkfifo(target.path, 0o644), 0, "建不出 FIFO 就測不到這條")

        // 若這裡卡住，代表回歸了——測試會逾時而不是失敗，這也是一種訊號
        XCTAssertEqual(loadError(folder), .notARegularFile("happy-0.png"))
    }

    /// `skin.json` 也要受資料夾隔離規則保護，不能因為名稱固定就跳過驗證
    func testRejectsManifestSymlinkEscapingTheFolder() throws {
        let outside = root.appendingPathComponent("outside.json")
        try manifest().write(to: outside, atomically: true, encoding: .utf8)

        let folder = root.appendingPathComponent("manifest-symlink", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("skin.json"), withDestinationURL: outside)

        guard case .escapesFolder = loadError(folder) else {
            return XCTFail("指到資料夾外面的 skin.json 應該被擋下")
        }
    }

    /// 皮膚總數有上限，超過的被略過並說明原因
    func testScanCapsTheNumberOfSkins() throws {
        for index in 0..<(SkinLoader.maxSkins + 3) {
            try makeSkin(String(format: "skin-%03d", index))
        }
        let result = SkinLoader.scan(directory: root)
        XCTAssertEqual(result.skins.count, SkinLoader.maxSkins)
        XCTAssertEqual(result.rejected.count, 3)
        XCTAssertTrue(result.rejected[0].reason.contains("上限"),
                      "要說明是因為數量上限：\(result.rejected[0].reason)")
    }

    /// ⚠️ 非 PNG 的反例要用**真的能被 ImageIO 讀的其他格式**。
    /// 用純文字測不出「PNG 限制被拿掉」——那種資料本來就建不出 image source
    /// （codex 2026-09-22 指出）
    func testRejectsJPEGEvenThoughItIsAValidImage() throws {
        let folder = try makeSkin("jpeg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16,
                                              bitsPerComponent: 8, bytesPerRow: 16 * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        let jpeg = try XCTUnwrap(rep.representation(using: .jpeg, properties: [:]))
        try jpeg.write(to: folder.appendingPathComponent("happy-0.png"))

        XCTAssertEqual(loadError(folder), .notAPNG("happy-0.png"),
                       "副檔名叫 .png 但內容是 JPEG，應該被擋下")
    }
}
