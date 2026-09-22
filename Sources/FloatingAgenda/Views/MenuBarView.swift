import SwiftUI

/// 選單列彈出內容（PLAN §4.5）。
struct MenuBarView: View {
    /// 資料由外部傳入，`--snapshot` 才能用 mock 渲染這個選單
    var calendars: [CalendarInfo]
    var reminderLists: [CalendarInfo]
    /// snapshot 模式傳 nil：沒有面板可以操作
    var delegate: AppDelegate?
    /// `ImageRenderer` 畫不出 ScrollView 的內容，snapshot 時傳 false 直接攤平渲染
    var scrollable = true

    private let settings = AppSettings.shared
    private let store = AgendaStore.shared

    /// 只用來在寫入設定後觸發重繪。
    /// getter 一律直接讀 `settings`，不保留鏡像狀態，這樣就不會顯示過期值
    @State private var revision = 0

    var body: some View {
        // 讀取 revision 建立重繪依賴。**不要用 `.id(revision)`**——透明度滑桿拖曳時
        // 每次變動都會 bump revision，`.id` 會在拖曳中途把 Slider 整個換掉，
        // 可能中斷連續拖曳並重設選單捲動位置（2026-09-18 code review）
        let _ = revision
        return VStack(alignment: .leading, spacing: 10) {
            Text("懸浮行程")
                .font(.system(size: 13, weight: .semibold))

            Toggle("顯示懸浮窗", isOn: Binding(
                get: { settings.panelVisible },
                set: { newValue in
                    settings.panelVisible = newValue
                    delegate?.panelController?.setVisible(newValue)
                    revision += 1
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            displayModeRow

            // 只有角色模式看得到泡泡，其他模式顯示這個開關只會讓人困惑
            if (delegate?.panelController?.displayMode ?? settings.displayMode) == .character {
                Toggle("顯示對話泡泡", isOn: Binding(
                    get: { settings.showBubble },
                    set: { newValue in
                        settings.showBubble = newValue
                        delegate?.panelController?.reloadPanelContent()
                        revision += 1
                    }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)

                characterSkinRow
            }

            opacityRow

            Divider()

            // 行事曆與清單可能很多，兩個區段一起包在固定高度上限的 ScrollView 裡
            if scrollable {
                ScrollView { filterSections }
                    .frame(maxHeight: 320)
            } else {
                filterSections
            }

            Divider()

            Button("重新整理") { store.refresh() }
            Button("結束 FloatingAgenda") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    /// 顯示模式三選一（M9 計畫 §4.1）。
    ///
    /// 讀寫都走 `PanelController`：它是顯示模式的唯一擁有者，負責存舊模式的位置、
    /// 換錨點、換陰影、還原新模式的位置。直接寫 `settings` 會讓面板幾何錯亂。
    /// 它是 `@Observable`，所以選單開著時若使用者按了卡片上的收合箭頭，
    /// 這裡會跟著更新（codex 2026-09-22 指出兩者原本會不同步）。
    ///
    /// snapshot 沒有 delegate，退回直接讀設定。
    private var displayModeRow: some View {
        Picker("顯示模式", selection: Binding(
            get: { delegate?.panelController?.displayMode ?? settings.displayMode },
            set: { newValue in
                delegate?.panelController?.setDisplayMode(newValue)
                revision += 1
            }
        )) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
    }

    /// 角色皮膚下拉選單（M9 計畫 §4.6）。
    ///
    /// 皮膚只在**打開這個選單時**重新掃描，不監聽資料夾——
    /// 使用者放進新皮膚後只要關掉再打開選單就會看到
    private var characterSkinRow: some View {
        HStack(spacing: 6) {
            Text("角色")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { delegate?.panelController?.activeSkin.id ?? BuiltinCharacter.id },
                set: { newValue in
                    delegate?.panelController?.selectSkin(newValue)
                    revision += 1
                }
            )) {
                ForEach(delegate?.panelController?.availableSkins ?? []) { skin in
                    Text(skin.name).tag(skin.id)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            Button("打開皮膚資料夾…") {
                delegate?.panelController?.openSkinsFolder()
            }
            .controlSize(.small)
        }
        .onAppear { delegate?.panelController?.reloadSkins() }
    }

    private var filterSections: some View {
        VStack(alignment: .leading, spacing: 10) {
            filterSection(title: "行事曆",
                          items: calendars,
                          setHidden: { store.setCalendarHidden($0, $1) })
            filterSection(title: "提醒事項清單",
                          items: reminderLists,
                          setHidden: { store.setReminderListHidden($0, $1) })
        }
    }

    private var opacityRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("透明度")
                    .font(.system(size: 12))
                Spacer()
                Text("\(Int((settings.opacity * 100).rounded()))%")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: Binding(
                get: { settings.opacity },
                set: { newValue in
                    settings.opacity = newValue
                    // 拖曳時即時生效
                    delegate?.panelController?.setOpacity(newValue)
                    revision += 1
                }
            ), in: AppSettings.opacityRange)
            .controlSize(.small)
        }
    }

    /// 照來源分組列出，每一列是色點 ＋ 名稱 ＋ 開關。
    /// 開關代表「顯示」，關掉就是加進隱藏清單。
    @ViewBuilder
    private func filterSection(title: String,
                               items: [CalendarInfo],
                               setHidden: @escaping (String, Bool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("（沒有可用的項目）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ForEach(groups(of: items), id: \.source) { group in
                if groups(of: items).count > 1 {
                    Text(group.source)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                ForEach(group.items) { item in
                    Toggle(isOn: Binding(
                        get: { !item.isHidden },
                        set: { setHidden(item.id, !$0) }
                    )) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(nsColor: item.color))
                                .frame(width: 8, height: 8)
                            Text(item.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                }
            }
        }
    }

    private struct SourceGroup: Identifiable {
        let source: String
        let items: [CalendarInfo]
        var id: String { source }
    }

    /// 同名的行事曆（實測有兩個都叫「Family」）必須用 id 當次要排序鍵：
    /// `sorted` 在 Swift 沒有穩定性保證，否則每次重讀後兩者可能互換位置，
    /// 使用者就會切到錯的那一個
    private static func byTitleThenID(_ lhs: CalendarInfo, _ rhs: CalendarInfo) -> Bool {
        switch lhs.title.localizedStandardCompare(rhs.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }

    /// 照來源分組，來源與名稱都用在地化比較排序（不要用 ASCII 序，
    /// 否則 `user-b@example.com` 會排在 `iCloud` 前面）
    private func groups(of items: [CalendarInfo]) -> [SourceGroup] {
        Dictionary(grouping: items, by: \.sourceTitle)
            .map { source, items in
                SourceGroup(source: source,
                            items: items.sorted(by: Self.byTitleThenID))
            }
            .sorted { $0.source.localizedStandardCompare($1.source) == .orderedAscending }
    }
}
