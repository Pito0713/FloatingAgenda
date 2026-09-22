# FloatingAgenda 開發計畫書（懸浮行事曆＋提醒事項）

> 撰寫：Claude（規劃 session，2026-09-15）
> 執行者：接手的 coding agent
> 狀態：規劃完成，尚未開始實作（目錄內目前只有本檔）
> 派工格式：依 `~/Agent_skill/governance/delegation-templates.md` T2（實作）

---

## 0. 給執行 agent 的開場說明（先讀這段）

- 這份文件就是完整需求。§3 的使用者決策已經定案，**不要重新詢問或更改**。
- 如果你是在**非互動 session**（例如 `codex exec` 或 CLI one-shot）執行：沒有人能回覆你，**不要停下來等確認**，照 §6 的里程碑一路做完，最後依 §10 回報。
- 遇到本文件沒寫到的細節，自己選最接近「macOS 原生小工具外觀與行為」的做法，並在回報的「自行決定事項」列出來。
- 同一個問題試兩輪都失敗，就停下來，把失敗過程寫進回報（全域鐵律 3）。
- 開工先執行 `git status`（這個目錄還不是 git repo，M0 會做 `git init`）。

---

## 1. 目標

做一個 macOS 常駐小 App：一張**浮在所有視窗最上層**的卡片，同時顯示「行事曆行程」和「未完成的提醒事項」，外觀要跟 macOS 原生桌面小工具一致。

**動機**：原生小工具（WidgetKit）只能放桌面或通知中心，會被視窗蓋住，而且不能懸浮。使用者想要一張隨時看得到、跟原生小工具長得一樣、而且行程和待辦合在一起的卡片。

**做法**：用 SwiftUI 加 AppKit 的 `NSPanel`（floating level）寫一般 App，**不走 WidgetKit**。資料用 EventKit 讀，跟系統的行事曆、提醒事項 App 即時雙向同步。

---

## 2. 已確認的環境（規劃 session 實測）

| 項目 | 值 |
|------|----|
| 機器 | Apple Silicon（arm64） |
| macOS | 27.0（Build 26A428） |
| Xcode | `/Applications/Xcode.app`（已安裝，`xcode-select -p` 正常） |
| Swift | 6.3.3 |
| 程式碼簽章憑證 | **沒有**（`security find-identity -v -p codesigning` → 0 valid identities），只能用 ad-hoc 簽章 |
| 使用者資料 | 用 osascript 可以讀到 16 個行事曆（個人、工作、學習、煮飯、副業、工作專案、Holidays in Taiwan、Family ×2、生日、台灣節日、台灣的節慶假日、已排程的提醒事項、Siri建議，另有兩個用 Gmail 帳號命名的 Google 行事曆），以及 3 個提醒清單（每日清單、待辦事項、購物清單） |

注意：
- 行事曆裡有**兩個同名的「Family」**，所以設定一律用 `calendarIdentifier` 當 key，**不能用名稱**。
- 「已排程的提醒事項」這個行事曆可能會讓提醒重複出現在行程區，處理方式見 §5.3。

---

## 3. 使用者已定案的決策（不可更改）

| 決策點 | 選擇 | 備註 |
|--------|------|------|
| 版面 | **單張卡片、上下排**：上半部是行程，下半部是提醒事項 | 見 §4 線框 |
| 互動 | **勾選＋點開**：可以直接勾選完成提醒；點行程或提醒會打開原生 App | 不做快速新增 |
| 懸浮行為 | **可調透明度**、**選單列圖示** | 使用者**沒有**選「每個桌面空間都顯示」和「快捷鍵顯示/隱藏」，這兩項不做 |
| 外觀 | 跟原版 macOS 小工具一樣 | 圓角、毛玻璃、系統字體、跟隨深淺色模式 |

---

## 4. 功能規格

### 4.1 懸浮面板

- 永遠浮在一般視窗上面（`NSPanel`，`level = .floating`）
- **不搶焦點**：點面板時，原本正在用的 App 不會失去焦點（`.nonactivatingPanel`）
- **不出現在 Dock**（`LSUIElement = true`），只有選單列圖示
- 拖曳面板空白處或標題可以移動位置；**位置要記住**，重開 App 後回到原位；如果螢幕配置變了、原位置已經不在畫面內，就回到預設位置（主螢幕右上角，往內留 20pt）
- 寬度固定 **320pt**；**高度跟著內容自動伸縮**，伸縮時**上緣位置不動**
- 透明度可以調（`alphaValue`），範圍 30%–100%，預設 100%，拖滑桿時即時生效並記住

### 4.2 卡片外觀（仿原生小工具）

```
╭──────────────────────────────╮   ← 圓角 22pt（continuous）、毛玻璃、細邊框
│ 星期二                        │   ← 紅色，12pt semibold
│ 9月15日                       │   ← 22pt bold
│                              │
│ ▍工作會議                     │   ← 左邊 3pt 色條＝行事曆顏色
│ ▍10:00 – 11:00               │     列背景＝行事曆顏色 12% 透明度、圓角 6
│ ▍煮飯                         │
│ ▍14:00 – 15:00               │
│ 明天                          │   ← 日期分組標籤，11pt semibold secondary
│ ▍學習                         │
│ ▍09:30 – 10:30               │
│ 還有 2 個行程                  │
│──────────────────────────────│   ← Divider
│ 提醒事項                    3 │   ← 13pt semibold；右邊是總數
│ ○ 買牛奶                      │   ← 圓圈 16pt；勾選後填滿成清單顏色
│ ○ 回覆訊息                 │
│   今天 14:00                  │   ← 到期時間 11pt；已過期顯示紅色
│ ○ 購物清單…               │
╰──────────────────────────────╯
```

- 內距 16pt。字體一律用系統字體（SF），顏色用 semantic color（`.primary`、`.secondary`），深淺色模式自動切換
- 背景用 `NSVisualEffectView`（`.popover` material、`.behindWindow`、`state = .active`），詳見 §5.4
- 滑鼠移到可點的列上時顯示淡淡的底色（`.onHover`），跟原生一樣

### 4.3 行程區

- 範圍：**只有今天**（今天 00:00 到今天結束）
  > 2026-09-16 需求變更：原本是 7 天，使用者實測後改成只看當天。
  > 連帶取消「明天／之後」的日期分組（畫面上只會有今天的行程）。
- **已經結束的行程不顯示**（`endDate <= now` 的過濾掉）；今天的整天行程保留
- 排序：開始時間由早到晚；整天行程排最前面
- 每一列：標題（13pt semibold，最多一行）＋時間（11pt secondary）
  - 一般行程：`10:00 – 11:00`（時間格式跟隨系統的 12/24 小時制設定）
  - 整天：`整天`
  - 正在進行中：`進行中 · 至 11:00`
- 最多顯示 **6 筆**，超過的在最後一行顯示「還有 N 個行程」
- 沒有行程時顯示「今天沒有行程」（secondary）
- **點一下行程 → 打開行事曆 App 到那一筆**（深層連結見 §5.6）

### 4.4 提醒事項區

- 抓所有**已勾選要顯示的清單**中「未完成」且**到期日在今天結束之前**的提醒
  （＝逾期 ＋ 今天到期；沒有設到期日的不顯示）
  > 2026-09-16 需求變更：原本是全部未完成提醒，使用者實測後改成只看今天。
  > 「今天」的語意由使用者定案為「逾期 ＋ 今天到期」，與提醒事項 App 的「今天」智慧清單一致。
- 排序：照到期時間由早到晚（逾期的自然排最前面）
- 每一列：圓圈按鈕＋標題（13pt，最多一行）＋到期（11pt，有才顯示）
  - 到期顯示：今天到期 → `今天 14:00`；逾期 → `9月14日 14:00`。只有日期沒有時間的就只顯示日期
  - 已過期顯示紅色
- 標題右邊顯示總數（是符合上述範圍的「全部」數量，不是只算畫面上那 6 筆）
- 最多顯示 **6 筆**，超過的顯示「還有 N 項」
- 沒有提醒時顯示「今天沒有待辦事項 🎉」（secondary）
- **勾選行為（模仿原生）**：
  1. 點圓圈 → 圓圈立刻填滿成清單顏色、標題加刪除線，**先不寫入**
  2. 1.2 秒內再點一次 → 取消，恢復原狀
  3. 1.2 秒到了 → 寫入 `isCompleted = true`，然後這一列淡出消失
  > **刻意保留的行為（2026-09-21 使用者裁定）**：若在 1.2 秒內把卡片收合、
  > 或該筆因重新整理而掉出畫面上的 6 筆，取消入口會消失但寫入仍會執行。
  > 這是因為**寫入是使用者自己點圓圈要求的**，1.2 秒取消窗是便利性而非保證。
  > 改成「看不到就不寫」會讓「點完就切走」這個正常操作失效。
  > （注意：這與「使用者做了**與該筆無關的操作**（隱藏清單、權限被撤）卻導致被寫入」
  > 是兩回事——那個是資料完整性問題，已於 2026-09-18 修正並有測試保護。）
- **點標題 → 打開提醒事項 App 到那一筆**（見 §5.6）

### 4.5 選單列圖示（MenuBarExtra，`.window` 樣式）

圖示用 SF Symbol `calendar`。點開後由上到下：

1. 標題「懸浮行程」
2. Toggle「顯示懸浮窗」（記住狀態）
3. Slider「透明度」30%–100%，旁邊顯示百分比
4. 區段「行事曆」：列出所有行事曆，照來源（iCloud、Google 等，`source.title`）分組；每一列是色點＋名稱＋Toggle
5. 區段「提醒事項清單」：同上
6. 按鈕「重新整理」
7. 按鈕「結束 FloatingAgenda」

- 行事曆和清單很多時，第 4、5 區段包在 `ScrollView` 裡，最大高度 320pt
- **設定存的是「被隱藏的」ID 集合**，這樣之後新增的行事曆預設會顯示

### 4.6 權限與異常狀態

| 狀態 | 卡片顯示 |
|------|---------|
| 第一次啟動（notDetermined） | 自動跳系統授權視窗，行事曆和提醒事項各一次 |
| 被拒絕（denied / restricted / writeOnly） | 那個區塊顯示「需要行事曆存取權限」＋按鈕「打開系統設定」 |
| 讀取失敗 | 那個區塊顯示「讀取失敗」＋錯誤訊息（secondary），不能 crash |

系統設定的深層連結：
- 行事曆：`x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`
- 提醒事項：`x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders`

### 4.7 即時更新

- 收到 `.EKEventStoreChanged` → 等 0.3 秒 debounce 後重新讀取（在行事曆或提醒事項 App 裡改東西，卡片要在 2 秒內更新）
- 每 60 秒重讀一次（把結束的行程移掉、更新「進行中」標示）
- 收到 `.NSCalendarDayChanged`（過午夜）和 `NSWorkspace.didWakeNotification`（從睡眠醒來）→ 立刻重讀

### 4.8 不在範圍內（不要做）

WidgetKit、每個桌面空間都顯示、全域快捷鍵、快速新增行程/提醒、開機自動啟動、通知、多張面板、任何網路請求或遙測、上架 App Store。

→ 做完後可以在回報的「未來可加」列出來，但**不要實作**。

### 4.10 收合模式（M8，2026-09-18 新增需求）

卡片右上角一個小圖示，點一下在「完整」與「收合」之間切換。收合狀態要記住（重開 App 後維持）。

**收合後只顯示兩列：**

```
╭──────────────────────────────╮
│                          ⌃   │   ← 收合／展開圖示（收合時常駐、完整模式滑過才浮現）
│ 正在進行中                     │   ← 區塊標題：「正在進行中」或「即將到來」
│ ▍工作會議                     │
│ ▍進行中 · 至 11:00            │
│                              │   ← 區隔（sectionGap）
│ ○ 買牛奶                      │   ← 排序後的第一筆提醒（逾期最優先、其次最早到期）
│   今天                        │
╰──────────────────────────────╯
```

> 2026-09-21 追加：行程列上方要有**區塊標題**，依狀態顯示「正在進行中」或「即將到來」。
> 收合後只有一列，不標示的話使用者看不出那是現在還是等一下（使用者實際使用後回報）。
> 沒有任何行程時不顯示標題，只顯示「今天沒有行程」。
> 行程區塊與提醒之間要有明顯的區隔間距。

- **行程那一列**，依序取：
  1. 「現在正在進行」的行程（`start <= now < end`）。同時有多筆時，
     有時間的優先於整天行程（使用者要的是「當前時間區間」）
  2. 沒有進行中的 → **今天接下來最近的一筆**（`start > now` 的第一筆）
  3. 兩者皆無（今天的行程都結束了）→ 顯示「今天沒有行程」

  > 2026-09-21 需求變更：原本定案是「沒有進行中就顯示『目前沒有行程』」，
  > 使用者實際使用後改為顯示即將到來的那一筆——行程之間的空檔佔了一天大半時間，
  > 那一列若只說「沒有行程」等於浪費掉收合卡片兩列中的一列。
- **提醒那一列**：展開時最上面那一筆（＝§4.4 排序後的第一筆）。沒有提醒時顯示「今天沒有待辦事項 🎉」
- 收合模式**不顯示**日期標題、不顯示「還有 N 個」、不顯示提醒總數
- **兩列的字級與尺寸放大 1.25 倍**（使用者 2026-09-18 要求：收合後內容要更明顯）。
  完整模式維持原尺寸不變。做法是把字級與尺寸乘上倍率後取整，不用 `.scaleEffect`
  （後者會把排版好的內容再縮放導致文字發虛）
- 兩列的互動與完整模式一致：點行程開行事曆 App、點提醒圓圈勾選、點提醒標題開提醒事項 App
- 寬度維持 320pt；高度照既有機制隨內容伸縮且**上緣不動**，所以收合是往上收
- **頂部有一塊 24pt 的專用拖曳區**（無視覺元素，右上角的箭頭在這一列裡）：
  收合後兩列都會吃掉點擊，沒有這塊幾乎沒有地方可以拖
  （2026-09-18 使用者實測「收合後很難拖」後追加；一度加了可見的小握把，
  同日使用者回報「有點醜」後移除，只保留拖曳面積）

**驗收條件**

- [ ] `--snapshot` 產出收合模式的 light／dark 圖，內容符合上方線框
- [ ] 三種情況都要有 snapshot：有進行中的行程、只有即將到來的行程、今天已經沒有行程
- [ ] 收合狀態存在 `panelCollapsed`，用 `defaults write` 改後啟動即為該狀態
- [ ] 收合後面板實測高度明顯小於完整模式，且上緣座標不變

---

### 4.9 後續優化項目（已確認要做，但不在 M0–M7 範圍）

使用者確認的後續需求，**M7 收尾前不要動手**，等基本功能穩定後再開新的里程碑：

| # | 項目 | 說明 | 提出日 |
|---|------|------|--------|
| 1 | 依分類篩選顯示 | 提醒事項（以及行程）能依分類／清單挑選要顯示哪些。目前 §4.5 的選單列篩選是「整個行事曆或整份清單」的開關，這一項要的是更細的分類維度 | 2026-09-16 |
| 2 | 顯示範圍可調 | 現在寫死「只看今天」。之後可讓使用者選今天／本週 | 2026-09-16 |
| 3 | 角色模式（M9） | 第三種顯示模式：像素小精靈＋對話泡泡，展開後多一個專案進度區（讀 `~/.agent-sessions`），可自製皮膚。**完整規格在 `docs/PLAN-M9-character.md`** | 2026-09-21 |

---

## 5. 技術設計

### 5.1 專案結構（SwiftPM，不用 .xcodeproj，讓 CLI agent 也能建置）

```
~/Floating/
├── PLAN.md                      # 本檔
├── README.md                    # M7 產出：用途、建置、安裝、權限、版本紀錄表
├── .gitignore                   # .build/  build/  .DS_Store
├── Package.swift
├── Resources/
│   └── Info.plist
├── scripts/
│   ├── build.sh                 # swift build → 組 .app → ad-hoc 簽章
│   └── install.sh               # 複製到 ~/Applications 並啟動
└── Sources/FloatingAgenda/
    ├── Entry.swift              # @main：處理 --dump / --snapshot，否則啟動 App
    ├── FloatingAgendaApp.swift  # SwiftUI App + MenuBarExtra
    ├── AppDelegate.swift        # 建立 PanelController、開關面板
    ├── Panel/
    │   ├── FloatingPanel.swift      # NSPanel 子類別 + FirstMouseHostingView
    │   ├── PanelController.swift    # 顯示/隱藏、高度同步、位置記憶、透明度
    │   ├── WidgetBackground.swift   # NSVisualEffectView + 圓角遮罩
    │   └── WindowDragArea.swift     # 拖曳移動
    ├── Data/
    │   ├── AgendaStore.swift        # EventKit 權限、讀取、監聽、勾選、開啟
    │   ├── Models.swift             # EventItem / ReminderItem / SectionState（純值型別）
    │   └── AppSettings.swift        # UserDefaults 包裝
    ├── Views/
    │   ├── WidgetView.swift         # 卡片根視圖
    │   ├── HeaderView.swift
    │   ├── EventsSection.swift
    │   ├── RemindersSection.swift
    │   ├── PermissionPrompt.swift
    │   └── MenuBarView.swift
    ├── Support/
    │   └── Formatting.swift         # 日期、時間、分組標籤（跟隨 Locale.autoupdatingCurrent）
    └── Dev/
        ├── DevDump.swift            # --dump
        └── DevSnapshot.swift        # --snapshot（mock 資料）
```

### 5.2 Package.swift 與 Info.plist

- `// swift-tools-version: 6.0`，`platforms: [.macOS(.v15)]`，一個 `executableTarget` 叫 `FloatingAgenda`
- **`swiftLanguageModes: [.v5]`**：EventKit 的型別不是 Sendable，用 Swift 6 嚴格併發模式會卡一堆和功能無關的警告和錯誤。所有 UI 和 store 程式碼標 `@MainActor`
- Info.plist 必要欄位：

| Key | 值 |
|-----|----|
| CFBundleIdentifier | `io.github.pito0713.floatingagenda` |
| CFBundleExecutable | `FloatingAgenda` |
| CFBundleName / CFBundleDisplayName | `FloatingAgenda` / `懸浮行程` |
| CFBundlePackageType | `APPL` |
| CFBundleShortVersionString / CFBundleVersion | `0.1.0` / `1` |
| LSMinimumSystemVersion | `15.0` |
| LSUIElement | `true` |
| NSCalendarsFullAccessUsageDescription | `顯示你的行程在懸浮卡片上` |
| NSRemindersFullAccessUsageDescription | `顯示並勾選你的提醒事項` |
| NSCalendarsUsageDescription / NSRemindersUsageDescription | 同上（舊版相容） |

- `scripts/build.sh` 流程：

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/FloatingAgenda.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FloatingAgenda "$APP/Contents/MacOS/FloatingAgenda"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier|Signature'
echo "✅ built $APP"
```

### 5.3 資料層（AgendaStore）

- `@MainActor @Observable final class AgendaStore`，用 `static let shared`，整個 App 只有**一個** `EKEventStore`
- 對外公開的狀態都是**純值型別**（`Models.swift`），View 完全不碰 EKEvent / EKReminder，這樣 `--snapshot` 才能用 mock 資料渲染：

```swift
struct EventItem: Identifiable, Hashable {
    let id: String            // eventIdentifier + "|" + startDate.timeIntervalSince1970（重複行程共用 eventIdentifier，一定要加上開始時間）
    let eventIdentifier: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
}
struct ReminderItem: Identifiable, Hashable {
    let id: String            // calendarItemIdentifier
    let title: String
    let due: Date?
    let dueHasTime: Bool      // dueDateComponents 有沒有 hour
    let color: NSColor        // 所屬清單顏色
    let created: Date?
}
enum SectionState<T> { case loading, needsPermission, failed(String), loaded(items: [T], total: Int) }
```

- 權限：`EKEventStore.authorizationStatus(for:)`，只有 `.fullAccess` 算通過；要權限時用 `requestFullAccessToEvents()` 和 `requestFullAccessToReminders()`（async）
- 行程：`predicateForEvents(withStart:end:calendars:)`，calendars 放「沒被隱藏的」；過濾和排序照 §4.3
- 提醒：`predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars:)` 搭配 `fetchReminders(matching:)`。**這個 callback 會在背景 queue 回來**，要切回 MainActor 再寫入狀態
- 勾選：先在 `pendingCompletion: Set<String>` 做本地標記，1.2 秒後用 `calendarItem(withIdentifier:)` 把 reminder 拿回來，設 `isCompleted = true` 再 `save(_:commit: true)`；失敗就把本地標記拿掉，並在區塊顯示錯誤
- **「已排程的提醒事項」行事曆**：先用 `--dump` 確認它會不會出現在 `calendars(for: .event)` 裡。會的話，**預設就把它加進隱藏清單**，免得提醒在行程區又出現一次；把結果寫進回報
- 「Siri建議」、「生日」這類特殊行事曆照一般行事曆處理，使用者可以自己在選單列關掉

### 5.4 面板實作重點（容易踩坑，照做）

```swift
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false        // App 是 accessory，一定要設，不然切走就消失
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        // 不設 .canJoinAllSpaces（使用者沒選「每個桌面空間都顯示」）
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// 沒有這個，面板在非作用中時第一下點擊會被吃掉，勾選要點兩次
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

- **毛玻璃圓角**：不要用 SwiftUI `.clipShape` 去裁 NSViewRepresentable。改用 `NSVisualEffectView.maskImage`，餵一張可拉伸的圓角圖（`capInsets` 設成半徑、`resizingMode = .stretch`）。`state` **一定要設成 `.active`**，因為面板永遠不會變成 key window，不設的話會一直是灰色的非作用中外觀
- **邊框**：在 SwiftUI 那層疊一個 `RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)`
- **拖曳**：寫一個 `NSViewRepresentable`，它的 NSView 覆寫 `mouseDown` 去呼叫 `window?.performDrag(with:)`，同時 `acceptsFirstMouse` 回傳 `true`。圖層順序是：背景毛玻璃 → 拖曳區 → 內容。實測如果 SwiftUI 文字擋住拖曳，就對純顯示的文字加 `.allowsHitTesting(false)`。**不要用 `isMovableByWindowBackground`**，它會跟按鈕搶點擊
- **高度同步**：`hostingView.sizingOptions = []`（不然 hosting view 自己的尺寸約束會跟你打架）。根視圖加 `.frame(width: 320).fixedSize(horizontal: false, vertical: true)`，再用 `.onGeometryChange(for: CGFloat.self)` 把高度回報給 PanelController：

```swift
func setContentHeight(_ h: CGFloat) {
    var f = panel.frame
    let top = f.maxY
    f.size.height = h
    f.origin.y = top - h          // 保持上緣不動
    panel.setFrame(f, display: true, animate: false)
    panel.invalidateShadow()      // 透明視窗的陰影要跟著內容更新
}
```

- **位置記憶**：面板移動後（`windowDidMove`）把**左上角**（`x`, `maxY`）存進 UserDefaults；啟動時先檢查這個點在不在任何 `NSScreen.visibleFrame` 裡面，不在就用預設位置

### 5.5 設定（AppSettings）

UserDefaults 的 key：`panelVisible`（Bool，預設 true）、`opacity`（Double，預設 1.0，限制在 0.3…1.0）、`hiddenCalendarIDs`（[String]）、`hiddenReminderListIDs`（[String]）、`panelTopLeftX` / `panelTopLeftY`（Double，可以沒有）。

### 5.6 打開原生 App（深層連結，**沒有官方文件，一定要實測**）

| 對象 | 先試這個 | 失敗時的替代 |
|------|---------|-------------|
| 行程 | `ical://ekevent/<eventIdentifier>?method=show&options=more` | 用 `NSWorkspace` 打開 `/System/Applications/Calendar.app` |
| 提醒 | `x-apple-reminderkit://REMCDReminder/<calendarItemIdentifier>` | 打開 `/System/Applications/Reminders.app` |

- `eventIdentifier` 或 identifier 裡如果有特殊字元，要先做 percent-encoding
- 在 macOS 27 上實測哪個有用，寫進回報。如果兩個都只能開 App、沒辦法跳到那一筆，就用替代方案，並在回報寫「只能開 App」
- **不要改用 AppleScript**：那需要額外的 Automation 權限，體驗比較差

### 5.7 開發輔助指令（讓 agent 不用點畫面也能自己驗證）

- `FloatingAgenda --dump`：用跟 App 一樣的 store 邏輯，把「行事曆清單（ID、名稱、來源、是否隱藏）」、「提醒清單」、「7 天內的行程」、「未完成提醒」印成純文字，然後結束。**只讀，不寫入**
- `FloatingAgenda --snapshot <輸出路徑前綴>`：用內建的 mock 資料（照 §4.2 線框：3 筆行程含整天和明天、4 筆提醒含一筆過期、一筆勾選中），用 `ImageRenderer` 輸出 `<前綴>-light.png` 和 `<前綴>-dark.png`（scale 2）。`ImageRenderer` 畫不出 NSVisualEffectView，所以 snapshot 模式的背景改用 `Color(nsColor: .windowBackgroundColor)`
- `Entry.swift` 的做法：`@main enum Entry { static func main() }` 先看 `CommandLine.arguments`。有開發旗標就執行 `Task { @MainActor in …; exit(0) }` 再呼叫 `dispatchMain()`；沒有就呼叫 `FloatingAgendaApp.main()`（這時 `FloatingAgendaApp` **不要**加 `@main`）
- 注意：從終端機直接跑 `build/FloatingAgenda.app/Contents/MacOS/FloatingAgenda --dump` 時，TCC 可能把權限算在終端機 App 頭上，第一次會跳出授權視窗。這是正常現象，寫進回報就好

---

## 6. 開發步驟（里程碑）

每個里程碑做完：`bash scripts/build.sh` 要通過 → 用 version-log 的方式更新 README 版本紀錄表（M7 之前 README 可以先只有這張表）→ **一個里程碑一個 commit**（`feat(M<n>): …`）。

| # | 里程碑 | 內容 | 這個階段完成的判準 |
|---|--------|------|----------------|
| M0 | 專案骨架 | `git init`、`.gitignore`、Package.swift、Info.plist、build.sh、install.sh；App 啟動後只有選單列圖示和「結束」 | build.sh 成功；`open build/FloatingAgenda.app` 之後 `pgrep -x FloatingAgenda` 找得到；`plutil -lint Resources/Info.plist` OK |
| M1 | 懸浮面板 | FloatingPanel、FirstMouseHostingView、WidgetBackground、WindowDragArea、PanelController；內容先放假資料；位置記憶；透明度（先寫死 0.9 測試） | build 成功；`--snapshot` 能輸出 PNG（先用假資料） |
| M2 | 資料層 | Models、AgendaStore（權限、讀取、監聽、60 秒計時、午夜和喚醒重讀）、AppSettings、`--dump` | `--dump` 印出的行事曆和清單名稱，跟 §2 列的一致（貼輸出） |
| M3 | 行程區 UI | HeaderView、EventsSection：分組、整天、進行中、上限 6 筆、空狀態、點擊開啟 | `--snapshot` 圖裡的行程區符合 §4.2、§4.3 |
| M4 | 提醒區 UI | RemindersSection：排序、到期、過期紅字、計數、1.2 秒延遲勾選和取消、淡出、點擊開啟 | `--snapshot` 圖裡的提醒區符合 §4.4（含勾選中那一筆的樣子） |
| M5 | 選單列 | MenuBarView：顯示開關、透明度滑桿、行事曆和清單篩選（照來源分組、存隱藏 ID）、重新整理、結束 | 改篩選後 `--dump` 的「是否隱藏」欄位有跟著變（用 `defaults write` 模擬，貼輸出） |
| M6 | 權限和異常 | PermissionPrompt、各區塊的 needsPermission 和 failed 狀態、系統設定深層連結 | 在 mock 裡加 needsPermission 狀態，snapshot 能畫出來 |
| M7 | 打磨和交付 | 深色模式檢查、hover 效果、README（用途、建置、安裝、權限、疑難排解、版本紀錄）、`scripts/install.sh` | §7 所有條件達成 |

---

## 7. 驗收條件

### 7.1 agent 自己驗證（全部達成才算完成，缺一條就回報「進行中」）

- [ ] `bash scripts/build.sh` 從乾淨狀態（先 `rm -rf .build build`）跑到成功，**貼完整輸出的最後 20 行**
- [ ] `plutil -lint Resources/Info.plist` 顯示 OK，而且 `grep -c UsageDescription Resources/Info.plist` ≥ 4，貼輸出
- [ ] `--dump` 輸出包含 §2 列的 3 個提醒清單名稱和主要行事曆名稱，**貼輸出**（使用者的個人行程內容可以只貼前 5 筆）
- [ ] `--snapshot /tmp/fa`（或 scratchpad 路徑）產生 light 和 dark 兩張 PNG，**你自己要打開圖片看過**，逐項對照 §4.2 線框，回報哪些一致、哪些有差
- [ ] App 啟動 5 秒後 `pgrep -x FloatingAgenda` 還在（沒 crash），貼輸出
- [ ] `git log --oneline` 顯示 M0 到 M7 的 commit，貼輸出
- [ ] `grep -rnE "URLSession|http://|https://" Sources/` 沒有結果（沒有任何網路呼叫；`x-apple…` 和 `ical://` 這類 scheme 不算），貼輸出

### 7.2 需要使用者手動驗收（agent 整理成清單附在回報裡，不用自己做）

1. 第一次開啟會跳出行事曆和提醒事項授權，按允許後卡片出現資料
2. 切到其他 App（例如 Safari 全螢幕以外的一般視窗），卡片還是浮在最上層
3. 點卡片不會讓目前的 App 失去焦點
4. 拖曳可以移動卡片；結束再重開，卡片回到原位
5. 選單列的透明度滑桿可以即時調整
6. 關掉某個行事曆，那個行事曆的行程立刻消失
7. 在行事曆 App 新增一筆今天的行程，2 秒內出現在卡片上
8. **用一筆自己新建的測試提醒**勾選：1.2 秒後消失，提醒事項 App 裡顯示已完成；1.2 秒內再點一次可以取消
9. 點行程會開行事曆 App，點提醒會開提醒事項 App（有沒有跳到那一筆，看 §5.6 的實測結果）
10. 切換深色和淺色模式，卡片外觀正確
11. Dock 上沒有這個 App 的圖示

---

## 8. 範圍和禁區

- **可以修改**：`~/Floating/` 底下的所有檔案
- **禁區**：
  - 其他任何目錄（包含 `~/Agent_skill`、其他專案）
  - **使用者的行事曆和提醒資料**：開發和驗證過程中**不能新增、修改、勾選、刪除任何行程或提醒**。所有寫入路徑的驗證都交給使用者（§7.2 第 8 點）
  - 系統 TCC 資料庫：**不要**自己執行 `tccutil reset`；需要的話寫進回報，讓使用者決定
- **不允許**：做 §4.8 列的功能、加任何網路呼叫或第三方套件（只能用 Apple 的 framework）、為了讓驗收通過而刪減規格

---

## 9. 已知風險（先告訴你，遇到了不用慌）

| 風險 | 說明 | 處理方式 |
|------|------|---------|
| ad-hoc 簽章讓權限失效 | 沒有簽章憑證，每次重新建置的 cdhash 都不一樣，系統可能**重新跳授權**，或者在系統設定裡看起來有開、實際上讀不到 | 寫進 README 疑難排解：`tccutil reset Calendar io.github.pito0713.floatingagenda` 和 `tccutil reset Reminders io.github.pito0713.floatingagenda`，然後重開 App。長期解法是用「鑰匙圈存取」建一張自簽的程式碼簽章憑證，改用它簽章（寫進 README，**不用實作**） |
| 深層連結沒有文件 | `ical://`、`x-apple-reminderkit://` 可能在 macOS 27 上不能用 | §5.6 已經有替代方案 |
| 第一下點擊被吃掉 | nonactivating panel 很常見的問題 | §5.4 的 FirstMouseHostingView |
| 毛玻璃變灰 | 非 key window 的 NSVisualEffectView 會變成非作用中外觀 | `state = .active` |
| 提醒重複出現在行程區 | 「已排程的提醒事項」行事曆 | §5.3 |
| 透明度太低看不清楚 | — | 下限 30% |
| macOS 27 很新 | API 行為可能跟文件不一樣 | 部署目標設 15.0，遇到行為差異寫進回報 |

---

## 10. 回報格式（做完交給使用者）

1. **plan**：你實際怎麼做的（5 行內），跟本計畫不一樣的地方要特別標出來
2. `git log --oneline` 和 `git diff --stat <第一個 commit>..HEAD`
3. §7.1 每一條驗收條件的證據（**實際貼上輸出**，不能只寫「已通過」）
4. snapshot 圖檔路徑，以及跟線框對照的結果
5. §5.3「已排程的提醒事項」和 §5.6 深層連結的實測結果
6. 自行決定事項（本文件沒寫、你自己選的做法）
7. §7.2 使用者手動驗收清單（直接複製過來）
8. 剩餘風險和未來可加的功能（沒有也要寫「無」）

---

## 11. 規劃 session 的背景紀錄

- 使用者一開始問 Claude 能不能讀到 Mac 的行事曆和提醒事項 → 用 osascript 實測可以（名稱清單見 §2）
- Claude 說明 WidgetKit 沒辦法懸浮，提出「NSPanel 仿小工具外觀」的方案，使用者接受
- 使用者透過選擇題定案 §3 的三個決策（版面、互動、懸浮行為）
- Claude 在確認環境時被使用者中斷，使用者改成要一份計畫書交給其他 agent 執行，所以目前**還沒有任何程式碼**
