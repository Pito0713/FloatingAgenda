import Foundation

/// 選單列「快速啟動」的一項（`AppSettings.quickLaunchItems`）。
/// `command` 的第一個元素是執行檔的絕對路徑，其餘是參數
struct QuickLaunchItem: Equatable {
    var name: String
    var command: [String]
}

/// 快速啟動選了一個檔案之後，要怎麼執行它。純函式，方便測試
enum QuickLaunchCommand {
    /// `.command` 用 `open` 開——在「終端機」視窗裡跑，等同在 Finder 雙擊。
    /// 快速啟動放的多半是 TUI（例如 SwarmTide），背景的 `/bin/bash` 沒有終端機就跑不起來。
    ///
    /// 其他副檔名照排程點擊動作的規則（`ScheduleCommand.command(forFile:)`）。
    /// 排程那邊的 `.command` 仍是 `/bin/bash` 背景跑，兩邊刻意不同
    static func command(forFile url: URL,
                        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile)
        -> [String] {
        if url.pathExtension.lowercased() == "command" {
            return ["/usr/bin/open", url.path]
        }
        return ScheduleCommand.command(forFile: url, isExecutable: isExecutable)
    }

    /// 新增時的預設名稱：檔名去掉副檔名
    static func defaultName(forFile url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
