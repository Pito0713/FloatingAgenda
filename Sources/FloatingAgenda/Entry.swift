import AppKit
import Foundation

/// 程式入口。先看有沒有開發旗標（§5.7），沒有才啟動 SwiftUI App。
/// `FloatingAgendaApp` 因此不能標 `@main`。
@main
enum Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        guard let flag = args.first, flag.hasPrefix("-") else {
            FloatingAgendaApp.main()
            return
        }

        switch flag {
        case "--dump":
            runDevCommand { await DevDump.run() }
        case "--snapshot":
            let prefix = args.count > 1 ? args[1] : nil
            runDevCommand { await DevSnapshot.run(outputPrefix: prefix) }
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            FileHandle.standardError.write(Data("未知旗標：\(flag)\n\n".utf8))
            printUsage()
            exit(2)
        }
    }

    /// 開發旗標一律跑在 main actor 上，跑完直接結束行程（不啟動 App）。
    private static func runDevCommand(_ body: @escaping @MainActor () async -> Int32) -> Never {
        Task { @MainActor in
            let code = await body()
            exit(code)
        }
        dispatchMain()
    }

    private static func printUsage() {
        print("""
        FloatingAgenda — 懸浮行事曆與提醒事項卡片

        用法：
          FloatingAgenda              啟動 App（選單列圖示 + 懸浮卡片）
          FloatingAgenda --dump       印出行事曆／提醒清單與近 7 天資料（唯讀）
          FloatingAgenda --snapshot <輸出路徑前綴>
                                      用 mock 資料輸出 <前綴>-light.png 與 <前綴>-dark.png
          FloatingAgenda --help       顯示本說明
        """)
    }
}
