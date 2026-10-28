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
        VStack(alignment: .leading, spacing: 4) {
            MenuSectionHeader(title: "快速啟動", note: "點名稱執行")
            // 同一個檔案可以加兩次，名稱也可能重複，只有位置是唯一的
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                // 一項一列、不用兩顆有框的按鈕（使用者 2026-10-28 回報選單太擠）。
                // `.plain` 自己畫：`.borderless` 之類的 AppKit 按鈕 ImageRenderer 畫不出來
                HStack(spacing: 4) {
                    Button { onRun(item) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.accentColor)
                            Text(item.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("執行：\(item.command.joined(separator: " "))")
                    Button { onRemove(index) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("從快速啟動移除")
                }
            }
            Button { chooseFile() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("新增…")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
