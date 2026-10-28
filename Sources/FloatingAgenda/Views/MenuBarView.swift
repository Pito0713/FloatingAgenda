import SwiftUI

/// 選單列彈出內容（PLAN §4.5）。
struct MenuBarView: View {
    /// 資料由外部傳入，`--snapshot` 才能用 mock 渲染這個選單
    var calendars: [CalendarInfo]
    var reminderLists: [CalendarInfo]
    /// 自己設的排程，用來設定每一列點了要執行什麼。snapshot 用 mock
    var schedules: [ScheduleItem] = []
    /// 只給 snapshot 用的快速啟動假資料，實際 App 一律讀設定（見 `quickLaunchItems`）
    var snapshotQuickLaunchItems: [QuickLaunchItem]?
    /// snapshot 模式傳 nil：沒有面板可以操作
    var delegate: AppDelegate?
    /// `ImageRenderer` 畫不出 ScrollView 的內容，snapshot 時傳 false 直接攤平渲染
    var scrollable = true

    private let settings = AppSettings.shared
    private let store = AgendaStore.shared

    /// 只用來在寫入設定後觸發重繪。
    /// getter 一律直接讀 `settings`，不保留鏡像狀態，這樣就不會顯示過期值
    @State private var revision = 0
    /// 篩選區內容的自然高度，用來決定 ScrollView 要多高
    @State private var filterSectionsHeight: CGFloat = 0
    /// 篩選區預設收起來：設一次就很少再動，攤開會把選單撐得很長（使用者 2026-10-28 回報）
    @State private var filtersCollapsed = true

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

            // 專案輪播只出現在完整模式（`PanelRootView.showsProjectTicker`），
            // 其他模式顯示這個開關會讓人以為打開就看得到
            if (delegate?.panelController?.displayMode ?? settings.displayMode) == .full {
                Toggle("顯示專案待辦", isOn: Binding(
                    get: { settings.showProjectTicker },
                    set: { newValue in
                        settings.showProjectTicker = newValue
                        delegate?.panelController?.reloadPanelContent()
                        revision += 1
                    }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }

            // 排程區只在完整模式與角色模式展開後出現（`PanelRootView.showsSchedules`）；
            // 收合模式看不到，就不顯示這個開關
            if (delegate?.panelController?.displayMode ?? settings.displayMode) != .collapsed {
                Toggle("顯示排程", isOn: Binding(
                    get: { settings.showSchedules },
                    set: { newValue in
                        settings.showSchedules = newValue
                        delegate?.panelController?.reloadPanelContent()
                        revision += 1
                    }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }

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

            filterHeader

            // 行事曆與清單可能很多，兩個區段一起包在高度上限 240pt 的 ScrollView 裡。
            //
            // ⚠️ 一定要給**明確高度**，不能只用 `maxHeight`：
            // ScrollView 的理想高度接近 0，只給上限的話外層一擠它就縮成一條線，
            // 篩選區會變成一段被裁掉的文字（使用者 2026-09-23 回報，
            // M5 的使用者驗收第 2 項一直沒被驗到）。
            // 先量內容的自然高度，再取 min(自然高度, 240)
            if filtersShown, scrollable {
                ScrollView {
                    filterSections
                        // 內容要撐滿寬度，否則捲動條會貼在內容的右緣
                        // 而不是選單的右緣，看起來像浮在中間（使用者 2026-09-23 回報）
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            filterSectionsHeight = height
                        }
                }
                .frame(height: min(max(filterSectionsHeight, 44), 240))
                .scrollIndicators(.automatic)
            } else if filtersShown {
                filterSections
            }

            if settings.showSchedules, !schedules.isEmpty {
                Divider()
                ScheduleActionsSection(
                    schedules: schedules,
                    commands: settings.scheduleOpenCommands,
                    hiddenLabels: settings.hiddenScheduleLabels,
                    onSetHidden: setScheduleHidden,
                    onSetCommand: { setCommand($1, for: $0) }
                )
            }

            if let quickLaunchItems {
                Divider()
                QuickLaunchSection(
                    items: quickLaunchItems,
                    onRun: { ScheduleCommandLauncher.run($0.command) },
                    onAdd: { settings.quickLaunchItems.append($0); revision += 1 },
                    onRemove: { settings.quickLaunchItems.remove(at: $0); revision += 1 }
                )
            }

            Divider()

            // 兩顆放同一列，選單少一行（使用者 2026-10-28 回報選單太長）
            HStack {
                Button("重新整理") {
                    store.refresh()
                    ScheduleStore.shared.refresh()
                }
                Spacer()
                Button("結束") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .help("結束 FloatingAgenda")
            }
            .controlSize(.small)
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
        // 版面跟「透明度」那一列一致：標題自己一行靠左，控制項在下面撐滿寬度。
        // 用 Picker 內建的 label 會讓標題與控制項擠在同一行且右對齊，
        // 與上下其他列對不齊（使用者 2026-09-23 回報）
        VStack(alignment: .leading, spacing: 4) {
            Text("皮膚")
                .font(.system(size: 12))
            HStack(spacing: 6) {
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
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                Button("打開資料夾…") {
                    delegate?.panelController?.openSkinsFolder()
                }
                .controlSize(.small)
            }
        }
        .onAppear { delegate?.panelController?.reloadSkins() }
    }

    /// 實際 App 讀設定；snapshot（沒有 delegate）只畫傳進來的假資料、沒傳就整塊不畫，
    /// 選單圖才不會跟著跑 snapshot 那台機器的設定變
    private var quickLaunchItems: [QuickLaunchItem]? {
        delegate == nil ? snapshotQuickLaunchItems : settings.quickLaunchItems
    }

    private func setScheduleHidden(_ item: ScheduleItem, _ hidden: Bool) {
        if hidden {
            settings.hiddenScheduleLabels.insert(item.id)
        } else {
            settings.hiddenScheduleLabels.remove(item.id)
        }
        delegate?.panelController?.reloadPanelContent()
        revision += 1
    }

    private func setCommand(_ command: [String]?, for item: ScheduleItem) {
        var commands = settings.scheduleOpenCommands
        commands[item.id] = command
        settings.scheduleOpenCommands = commands
        delegate?.panelController?.reloadPanelContent()
        revision += 1
    }

    /// snapshot 一律攤開：那張圖是用來檢查篩選區內容的
    private var filtersShown: Bool { !scrollable || !filtersCollapsed }

    /// 篩選區的標題列，點了展開／收起。收起時顯示隱藏了幾個，才知道卡片上少了東西
    private var filterHeader: some View {
        let hiddenCount = (calendars + reminderLists).filter(\.isHidden).count
        return Button { filtersCollapsed.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(filtersShown ? 90 : 0))
                MenuSectionHeader(title: "行事曆與提醒篩選",
                                  note: hiddenCount > 0 ? "已隱藏 \(hiddenCount) 個" : nil)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
