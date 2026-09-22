import AppKit

/// 一個可以用來畫小精靈的皮膚（M9 計畫 §4.6）。
///
/// 內建角色與外部皮膚都收斂成這個型別，`CharacterHostView` 只認得它。
struct Skin: Identifiable, Equatable {
    let id: String
    let name: String
    /// 每種心情的動畫格，至少 1 格
    let frames: [Mood: [CGImage]]
    /// 眨眼格。沒有就不眨眼
    let blink: CGImage?
    let fps: Int

    static func == (lhs: Skin, rhs: Skin) -> Bool { lhs.id == rhs.id }

    /// 取某種心情的第 n 格。心情缺格時退回 `.busy`，再不行就給第一個有的
    func image(mood: Mood, index: Int) -> CGImage? {
        let list = frames[mood] ?? frames[.busy] ?? frames.values.first
        guard let list, !list.isEmpty else { return nil }
        return list[abs(index) % list.count]
    }
}

/// 被拒絕的皮膚與原因。`--dump` 會列出來，讓使用者知道自己的皮膚哪裡不合格
struct SkinRejection: Equatable {
    let folder: String
    let reason: String
}

/// 外部皮膚的掃描、解析與驗證（M9 計畫 §4.6）。
///
/// ⚠️ **只讀**：這個型別不寫入任何檔案。唯一的例外是 `ensureDirectoryExists`，
/// 只有使用者按「打開皮膚資料夾…」時才會被呼叫（§8 明文允許）。
enum SkinLoader {
    static let manifestName = "skin.json"
    static let maxManifestBytes = 64 * 1024
    static let maxImageBytes = 256 * 1024
    static let maxImages = 64
    /// 一次最多載入幾個皮膚。每個皮膚最多 64 張 64×64 的圖（約 1MB），
    /// 沒有總量上限的話，放一堆合法皮膚就能讓記憶體一直長（codex 2026-09-22 指出）
    static let maxSkins = 32
    static let pixelSizeRange = 8...64
    static let fpsRange = 1...12
    static let supportedFormatVersion = 1

    /// `~/Library/Application Support/FloatingAgenda/Skins`
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("FloatingAgenda", isDirectory: true)
            .appendingPathComponent("Skins", isDirectory: true)
    }

    /// 掃描資料夾。資料夾不存在就回空結果，不算錯誤——大多數使用者不會有自製皮膚
    static func scan(directory: URL) -> (skins: [Skin], rejected: [SkinRejection]) {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let entries = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return ([], []) }

        var skins: [Skin] = []
        var rejected: [SkinRejection] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            guard skins.count < maxSkins else {
                rejected.append(SkinRejection(folder: entry.lastPathComponent,
                                              reason: "\(SkinError.tooManySkins(maxSkins))"))
                continue
            }
            do {
                skins.append(try load(folder: entry))
            } catch {
                rejected.append(SkinRejection(folder: entry.lastPathComponent,
                                              reason: "\(error)"))
            }
        }
        return (skins, rejected)
    }

    /// 讀一個皮膚資料夾。任何一條驗證不過就丟錯，**絕不讓壞皮膚把 App 打掛**（§4.6）
    static func load(folder: URL) throws -> Skin {
        // manifest 也要走同一套檔名／範圍驗證，不能因為名稱是固定的就跳過
        // （codex 2026-09-22 指出原本 skin.json 可以是指到資料夾外的 symlink）
        let manifestURL = try resolvedFile(named: manifestName, in: folder)
        let data = try readFile(manifestURL, limit: maxManifestBytes, what: manifestName)

        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw SkinError.badManifest
        }

        guard manifest.formatVersion == supportedFormatVersion else {
            throw SkinError.unsupportedFormatVersion(manifest.formatVersion)
        }
        guard pixelSizeRange.contains(manifest.pixelSize) else {
            throw SkinError.pixelSizeOutOfRange(manifest.pixelSize)
        }
        guard fpsRange.contains(manifest.fps) else {
            throw SkinError.fpsOutOfRange(manifest.fps)
        }

        var fileNames: [String] = manifest.frames.values.flatMap { $0 }
        if let blink = manifest.blink { fileNames.append(blink) }
        guard fileNames.count <= maxImages else {
            throw SkinError.tooManyImages(fileNames.count)
        }

        var frames: [Mood: [CGImage]] = [:]
        for mood in Mood.allCases {
            guard let names = manifest.frames[mood.rawValue], !names.isEmpty else {
                throw SkinError.missingMood(mood.rawValue)
            }
            frames[mood] = try names.map {
                try image(named: $0, in: folder, pixelSize: manifest.pixelSize)
            }
        }
        let blink = try manifest.blink.map {
            try image(named: $0, in: folder, pixelSize: manifest.pixelSize)
        }

        let name = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Skin(id: "skin.\(folder.lastPathComponent)",
                    name: name.isEmpty ? folder.lastPathComponent : name,
                    frames: frames,
                    blink: blink,
                    fps: manifest.fps)
    }

    /// 只有使用者按「打開皮膚資料夾…」時才呼叫（§8 明文允許的唯一寫入）
    @discardableResult
    static func ensureDirectoryExists(_ directory: URL) -> Bool {
        (try? FileManager.default.createDirectory(at: directory,
                                                  withIntermediateDirectories: true)) != nil
            || FileManager.default.fileExists(atPath: directory.path)
    }

    // MARK: - 內部

    private struct Manifest: Decodable {
        let formatVersion: Int
        let name: String
        let pixelSize: Int
        let fps: Int
        let frames: [String: [String]]
        let blink: String?
    }

    private static func image(named name: String,
                              in folder: URL,
                              pixelSize: Int) throws -> CGImage {
        let url = try resolvedFile(named: name, in: folder)
        let data = try readFile(url, limit: maxImageBytes, what: name)

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) == "public.png" as CFString,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SkinError.notAPNG(name)
        }
        guard image.width == pixelSize, image.height == pixelSize else {
            throw SkinError.wrongImageSize(name: name,
                                           width: image.width,
                                           height: image.height,
                                           expected: pixelSize)
        }
        return image
    }

    /// 檔名只能指到**同一個資料夾裡**的檔案：不接受路徑分隔、`..`，
    /// 也不跟隨指向資料夾外面的 symlink（§4.6）
    private static func resolvedFile(named name: String, in folder: URL) throws -> URL {
        guard !name.isEmpty,
              !name.contains("/"),
              !name.contains("\\"),
              name != ".", name != ".." else {
            throw SkinError.unsafeFileName(name)
        }
        let candidate = folder.appendingPathComponent(name, isDirectory: false)
        let resolvedFolder = folder.resolvingSymlinksInPath().standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.deletingLastPathComponent().standardizedFileURL.path
                == resolvedFolder.path else {
            throw SkinError.escapesFolder(name)
        }
        // 回傳**解析後**的路徑，之後就用它開檔。
        // 回傳原始的 candidate 會讓「驗證的對象」與「開啟的對象」是兩次獨立的
        // 路徑解析，中間被抽換就會讀到驗證時不存在的檔案（codex 指出的 TOCTOU）。
        // 殘留的時間窗無法完全消除——皮膚資料夾是使用者自己的，
        // 威脅模型是「放錯東西」而不是「有人在旁邊競爭」，這個程度的收斂足夠
        return resolved
    }

    private static func readFile(_ url: URL, limit: Int, what: String) throws -> Data {
        // ⚠️ 一定要先確認是**一般檔案**再開。
        // FIFO（具名管道）開起來或讀起來會**永遠阻塞**，位元組上限擋不住「等待」，
        // 而掃描目前在背景執行也不代表可以無限期卡住（codex 2026-09-22 指出）
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SkinError.missingFile(what)
        }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
            throw SkinError.notARegularFile(what)
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw SkinError.missingFile(what)
        }
        defer { try? handle.close() }
        // 多讀 1 個位元組才分得出「剛好等於上限」與「超過上限」
        guard let data = try? handle.read(upToCount: limit + 1) else {
            throw SkinError.missingFile(what)
        }
        guard data.count <= limit else { throw SkinError.fileTooLarge(what) }
        return data
    }
}

enum SkinError: Error, CustomStringConvertible, Equatable {
    case missingFile(String)
    case notARegularFile(String)
    case fileTooLarge(String)
    case badManifest
    case unsupportedFormatVersion(Int)
    case pixelSizeOutOfRange(Int)
    case fpsOutOfRange(Int)
    case missingMood(String)
    case tooManyImages(Int)
    case tooManySkins(Int)
    case notAPNG(String)
    case wrongImageSize(name: String, width: Int, height: Int, expected: Int)
    case unsafeFileName(String)
    case escapesFolder(String)

    var description: String {
        switch self {
        case .missingFile(let name): "找不到 \(name)"
        case .notARegularFile(let name): "\(name) 不是一般檔案"
        case .fileTooLarge(let name): "\(name) 太大"
        case .badManifest: "skin.json 格式不正確"
        case .unsupportedFormatVersion(let version):
            "formatVersion 必須是 \(SkinLoader.supportedFormatVersion)，實際是 \(version)"
        case .pixelSizeOutOfRange(let size):
            "pixelSize 必須在 \(SkinLoader.pixelSizeRange.lowerBound)…\(SkinLoader.pixelSizeRange.upperBound)，實際是 \(size)"
        case .fpsOutOfRange(let fps):
            "fps 必須在 \(SkinLoader.fpsRange.lowerBound)…\(SkinLoader.fpsRange.upperBound)，實際是 \(fps)"
        case .missingMood(let mood): "缺少心情「\(mood)」的動畫格"
        case .tooManyImages(let count):
            "圖片太多（\(count) 張，上限 \(SkinLoader.maxImages) 張）"
        case .tooManySkins(let limit): "皮膚數量超過上限（\(limit) 個），這一個被略過"
        case .notAPNG(let name): "\(name) 不是 PNG"
        case .wrongImageSize(let name, let width, let height, let expected):
            "\(name) 的尺寸是 \(width)×\(height)，應該是 \(expected)×\(expected)"
        case .unsafeFileName(let name): "檔名不安全：\(name)"
        case .escapesFolder(let name): "\(name) 指到皮膚資料夾外面"
        }
    }
}
