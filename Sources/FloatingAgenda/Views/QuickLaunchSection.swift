import SwiftUI

/// 選單列「快速啟動」區塊（使用者 2026-10-27 要求）：點一下就啟動常用工具。
///
/// 跟「排程點擊動作」分開：那邊綁的是 launchd `local.*` 排程，這裡放的是沒有排程的工具。
/// 只能**選一個檔案**新增，不提供自由輸入的指令列，理由同排程點擊動作——
/// 選單不要變成一個可以跑任意 shell 字串的地方。
///
/// 本身不讀寫設定：項目與增刪由 `MenuBarView` 傳進來，`--snapshot` 才能用假資料渲染
struct QuickLaunchSection: View {
    var items: [QuickLaunchItem]
    var onRun: (QuickLaunchItem) -> Void = { _ in }
    var onAdd: (QuickLaunchItem) -> Void = { _ in }
    var onRemove: (Int) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("快速啟動")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            // 同一個檔案可以加兩次，名稱也可能重複，只有位置是唯一的
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.command.joined(separator: " "))
                    Spacer(minLength: 4)
                    Button("執行") { onRun(item) }
                        .controlSize(.small)
                    Button("移除") { onRemove(index) }
                        .controlSize(.small)
                }
            }
            Button("新增…") { chooseFile() }
                .controlSize(.small)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "選擇要加進快速啟動的檔案"
        panel.message = ".command 會在終端機視窗執行；.py／.sh 在背景執行；其他檔案用預設的 App 打開"
        panel.prompt = "新增"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        // accessory App 不先 activate 的話，選檔視窗會開在其他 App 後面
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onAdd(QuickLaunchItem(name: QuickLaunchCommand.defaultName(forFile: url),
                              command: QuickLaunchCommand.command(forFile: url)))
    }
}
