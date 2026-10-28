import SwiftUI

/// 選單列的排程區：每個排程一列，勾選＝顯示在卡片上（使用者 2026-10-28 要求），
/// 右邊是點了要執行的檔案（使用者 2026-10-12 要求，取代手打 `defaults write`）。
///
/// 一個排程只佔一列（使用者 2026-10-28 回報原本兩列一組太長太擠）：
/// 檔名本身就是「選擇…」按鈕，有設定時旁邊多一個清除的 ×。
///
/// 只能**選一個檔案**，指令由副檔名推出來（`ScheduleCommand.command(forFile:)`）：
/// 不提供自由輸入的指令列，免得選單變成一個可以跑任意 shell 字串的地方。
///
/// 本身不讀寫設定，理由同 `QuickLaunchSection`
struct ScheduleActionsSection: View {
    var schedules: [ScheduleItem]
    var commands: [String: [String]]
    var hiddenLabels: Set<String>
    var onSetHidden: (ScheduleItem, Bool) -> Void = { _, _ in }
    var onSetCommand: (ScheduleItem, [String]?) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MenuSectionHeader(title: "排程", note: "勾選的顯示在卡片上")
            ForEach(schedules) { item in
                row(item, command: commands[item.id])
            }
        }
    }

    private func row(_ item: ScheduleItem, command: [String]?) -> some View {
        HStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { !hiddenLabels.contains(item.id) },
                set: { onSetHidden(item, !$0) }
            )) {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .layoutPriority(1)

            Spacer(minLength: 6)

            // `.plain` 自己畫：`.borderless` 之類的 AppKit 按鈕 ImageRenderer 畫不出來
            Button { chooseFile(for: item, current: command) } label: {
                HStack(spacing: 3) {
                    Text(command.map(ScheduleCommand.summary) ?? "開 log")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "folder")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 110, alignment: .trailing)
            .help(command.map { "點了執行：\($0.joined(separator: " "))\n按一下改選其他檔案" }
                  ?? "沒設定，點卡片上這一列會開 log。按一下選擇要執行的檔案")

            if command != nil {
                Button { onSetCommand(item, nil) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除，改回點了開 log")
            }
        }
    }

    private func chooseFile(for item: ScheduleItem, current: [String]?) {
        let panel = NSOpenPanel()
        panel.title = "選擇「\(item.name)」點了要開的檔案"
        panel.message = "腳本（.py／.sh）會在背景執行；其他檔案用預設的 App 打開"
        panel.prompt = "選擇"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if let path = current?.last {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        // accessory App 不先 activate 的話，選檔視窗會開在其他 App 後面
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onSetCommand(item, ScheduleCommand.command(forFile: url))
    }
}

/// 選單各區塊的小標題，右邊可以帶一句淡色說明
struct MenuSectionHeader: View {
    var title: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if let note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
