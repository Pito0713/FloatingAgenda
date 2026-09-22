# FloatingAgenda（懸浮行程）

一張浮在所有視窗最上層的 macOS 卡片，同時顯示**今天的行事曆行程**與**今天的提醒事項**，
外觀仿原生桌面小工具。

原生小工具（WidgetKit）只能放在桌面或通知中心、會被視窗蓋住，這個 App 用
SwiftUI ＋ AppKit 的 `NSPanel`（floating level）做一般 App，所以能真的懸浮。
資料用 EventKit 讀，跟系統的行事曆與提醒事項 App 即時同步。

- 需求正本：[`PLAN.md`](PLAN.md)
- 驗證計畫與逐輪紀錄：[`VERIFICATION.md`](VERIFICATION.md)、[`docs/verification/`](docs/verification/)

## 功能

| 區塊 | 內容 |
|------|------|
| 標題 | 紅色星期 ＋ 粗體日期，跨午夜自動換 |
| 行程 | **只有今天**、已結束的不顯示、整天行程排最前面、進行中顯示「進行中 · 至 HH:mm」、最多 6 筆 |
| 提醒 | **逾期 ＋ 今天到期**（沒設到期日的不顯示）、逾期紅字、最多 6 筆 |
| 互動 | 點行程開行事曆 App、點提醒標題開提醒事項 App、點圓圈勾選完成（1.2 秒內可取消） |
| 面板 | 固定寬 320pt、高度隨內容伸縮且上緣不動、可拖曳且記住位置、透明度 30–100% |
| 選單列 | 顯示開關、透明度滑桿、依來源分組的行事曆與清單篩選、重新整理、結束 |
| 收合 | 右上角圖示可收合成兩列：行程（標題顯示「正在進行中」或「即將到來」）＋ 第一筆提醒，字級放大 1.25 倍。狀態會記住 |

不做的事：沒有網路連線、沒有第三方套件、不會蒐集或傳送任何資料。

## 建置與安裝

需要 macOS 15 以上，以及 **Swift 6.0 以上的工具鏈**（Xcode 16＋或對應的 Command Line Tools）。
用 `swift --version` 確認；版本太舊會在 `swift build` 一開始就失敗。

```bash
bash scripts/build.sh     # swift build → 組成 .app → ad-hoc 簽章，產物在 build/
bash scripts/install.sh   # 關掉舊行程 → 複製到 ~/Applications → 啟動
```

App 是 accessory（`LSUIElement`），**Dock 不會有圖示**，只有選單列的日曆圖示。
要結束就從選單列選「結束 FloatingAgenda」。

### 用自己的 bundle identifier

預設是 `io.github.pito0713.floatingagenda`。要換成自己的：

```bash
BUNDLE_ID=com.yourname.floatingagenda bash scripts/build.sh
```

`build.sh` 只改建置產物裡的那一份，`Resources/Info.plist` 不動，所以不會有本機修改
卡在 git 裡。**換 ID 等於換身分**：macOS 會重新詢問行事曆與提醒事項的授權，
UserDefaults 也會換一個 domain（面板位置、透明度、篩選設定回到預設值）。
下面疑難排解與「設定項目」那兩節的指令，請把 ID 換成你建置時用的那一個。

## 測試

```bash
swift test      # 76 個單元測試，約 1.2 秒
```

完全不觸碰真實 EventKit 資料、不碰真實 `UserDefaults`：

| 測試檔 | 涵蓋 |
|--------|------|
| `FormattingTests` | 逾期判定（只有日期 vs 有時間、剛好等於 `now`）、到期文案分支、行程時間文案的兩端邊界 |
| `OrderingTests` | 行程排序（整天優先、同時間用標題決勝、跨午夜的現況）、提醒排序 |
| `InProgressEventTests` | 收合模式挑哪一筆（進行中的兩端邊界、有時間優先於整天、沒有進行中時退而取最近的一筆） |
| `AppSettingsTests` | 透明度夾限（含 NaN／±∞／型別不對）與 setter、各項設定讀寫、面板位置缺一座標視為無記錄 |
| `CompletionTests` | **勾選完成的整條路徑**：緩衝期確實存在且預設為規格的 1.2 秒、期內不寫入、期滿才寫入、期內再點完全取消、寫入送出後不假裝取消、多筆互不影響、以及權限被撤／清單全隱藏／讀取失敗／離開今天範圍時一律不准寫入 |

兩個為可測性而做的改動：`AgendaStore.eventOrder` / `reminderOrder` 從 `private` 放寬為
`internal`（純函式、無副作用）；`AppSettings` 抽出 `SettingsStore` protocol，測試用
`InMemorySettingsStore`——`UserDefaults(suiteName:)` 會在 `~/Library/Preferences` 留下
plist 且行程結束時會被 cfprefsd 寫回去，清不掉。

為了能測勾選路徑，EventKit 的寫入抽出了 `ReminderWriter` protocol：production 用
`EventKitReminderWriter`（**整個專案唯一碰寫入 API 的型別**，只有 5 行、不含任何判斷），
測試注入 `SpyReminderWriter` 只記錄呼叫。緩衝時間也改成可注入（預設仍是 1.2 秒），
測試用 60ms。因此測試**從未實例化 `EKEventStore`，不可能寫入任何真實提醒**。

**尚未覆蓋**：`commitCompletion` 裡 `guard pendingCompletion.contains(id)` 這道第二層保險。
變異測試證明移除它不會讓任何測試失敗——因為漏斗會先取消 Task，讓它在現有路徑下無法被觸及。
它是防未來有人新增繞過漏斗的路徑用的縱深防禦，保留但無測試覆蓋。

### 開發輔助指令

```bash
build/FloatingAgenda.app/Contents/MacOS/FloatingAgenda --dump
# 唯讀印出：授權狀態、行事曆與提醒清單（含 ID／來源／是否隱藏）、今天的行程、今天的提醒，
# 以及 ~/.agent-sessions 底下各專案的進度（名稱、待辦、卡住原因）
#
# ⚠️ 輸出包含你真實的行程、提醒與專案內容，**不會自動去識別化**。
#    貼到 issue、聊天室或任何公開的地方之前請先自行檢查

build/FloatingAgenda.app/Contents/MacOS/FloatingAgenda --snapshot /tmp/fa
# 用 mock 資料輸出 PNG（scale 2），不讀取也不寫入任何真實資料：
#   /tmp/fa-light.png            卡片（淺色）
#   /tmp/fa-dark.png             卡片（深色）
#   /tmp/fa-menu-light|dark.png  選單列
#   /tmp/fa-collapsed-*.png          收合模式（有進行中的行程）
#   /tmp/fa-collapsed-upcoming-*.png 收合模式（只有即將到來的行程）
#   /tmp/fa-collapsed-empty-*.png    收合模式（今天已經沒有行程）
#   /tmp/fa-permission-*.png     缺權限的畫面
#   /tmp/fa-failed-*.png         讀取失敗的畫面
#   /tmp/fa-writefail-*.png      勾選寫入失敗的畫面
```

## 權限

第一次啟動會分別要求「行事曆」與「提醒事項」的存取權。兩者都需要**完整存取**：
只給「僅新增」（write-only）等於沒有讀取權限，卡片會顯示「需要行事曆存取權限」。

要事後調整：**系統設定 → 隱私權與安全性 → 行事曆／提醒事項**。
改完不必重開 App，卡片最多 3 秒就會自己載入資料。

## 專案進度（可選）

App 會唯讀掃描 `~/.agent-sessions/<專案>/latest.md` 這種交接文件，把各專案的燈號、
完成比例與待辦顯示出來。這是作者自己的工作流程慣例，**完全是可選的**：

- 沒有這個目錄是正常的，不是安裝失敗。`--dump` 會印「❌ 找不到 ~/.agent-sessions」，
  App 的其他功能（行程、提醒）完全不受影響
- 掃描**只讀不寫**：不會新增、修改或刪除那些檔案，也不會改變它們的權限
- 每個專案讀 `latest.md`，超過 256KB 的檔案會被略過；標題含「已搬遷」的專案會被忽略

格式是一般的 markdown：`# 標題`、`> 狀態：🟢 順暢`、`> 最後更新：2026-09-18 15:20`、
`## 進行中` 底下的 `- [x]` / `- [ ]` 清單、`## 卡住的點` 區段。缺欄位不會壞，會用預設值。

## 自製角色

角色模式的小精靈可以換成自己畫的。皮膚放在：

```
~/Library/Application Support/FloatingAgenda/Skins/<你的皮膚名稱>/
```

從選單列 →「打開皮膚資料夾…」可以直接開啟（資料夾不存在會先建立）。

### 資料夾結構

```
Skins/my-cat/
├── skin.json
├── happy-0.png    happy-1.png
├── busy-0.png     busy-1.png
├── worried-0.png  worried-1.png
├── sleepy-0.png
└── blink.png          # 選用；沒有就不眨眼
```

### skin.json

```json
{
  "formatVersion": 1,
  "name": "我的貓",
  "pixelSize": 16,
  "fps": 4,
  "frames": {
    "happy":   ["happy-0.png", "happy-1.png"],
    "busy":    ["busy-0.png", "busy-1.png"],
    "worried": ["worried-0.png", "worried-1.png"],
    "sleepy":  ["sleepy-0.png"]
  },
  "blink": "blink.png"
}
```

四種心情的意思：`worried` 有逾期的事或專案卡住、`busy` 今天還有事、
`happy` 全部清空、`sleepy` 讀不到資料。

### 規則

| 項目 | 限制 |
|------|------|
| `formatVersion` | 必須是 `1` |
| `pixelSize` | 8–64。每張圖的尺寸要**剛好**是 `pixelSize × pixelSize` |
| `fps` | 1–12 |
| `frames` | 四種心情都要有，每種至少 1 格 |
| 圖片格式 | PNG |
| 檔名 | 只能是同一個資料夾裡的檔案。不接受 `/`、`..`，也不跟隨指到資料夾外面的捷徑 |
| 大小 | `skin.json` 最大 64KB、單張圖片最大 256KB、一個皮膚最多 64 張圖 |

**任何一條不符合，那個皮膚就不會出現在選單裡，App 不會因此出錯。**
用 `--dump` 的 `== Skins ==` 區段可以看到每個皮膚是有效還是無效、以及無效的原因。

皮膚只在**啟動時**與**打開選單列的角色下拉選單時**重新掃描。
放進新皮膚後把選單關掉再打開就會看到。

渲染一律用最近鄰插值放大到 64pt，所以像素會是銳利的方塊，不會被模糊化。

## 疑難排解

### 重建後卡片變空白、或又跳出授權視窗

**這是預期行為。** 本機沒有 Apple 開發者簽章憑證，只能用 ad-hoc 簽章
（`codesign --sign -`），而 ad-hoc 簽章的 cdhash 每次重建都不一樣，
macOS 會把重建後的 App 當成另一個程式，重新詢問授權。

按下「允許」就好。如果沒有跳出視窗、系統設定裡看起來有開但實際讀不到資料，
把這個 App 的授權記錄清掉再重開：

```bash
tccutil reset Calendar io.github.pito0713.floatingagenda
tccutil reset Reminders io.github.pito0713.floatingagenda
```

**長期解法**（本專案未實作，需要時自行處理）：用「鑰匙圈存取」建立一張自簽的
程式碼簽章憑證，把 `scripts/build.sh` 裡的 `codesign --sign -` 改成
`codesign --sign "<憑證名稱>"`。同一張憑證簽出來的 cdhash 穩定，授權就不會每次重設。

### 卡片不見了

1. 選單列 →「顯示懸浮窗」是否被關掉
2. 透明度是否被拉到很低（下限是 30%，不會完全透明）
3. 卡片可能被拖到已經拔掉的外接螢幕上——螢幕配置變更時會自動移回主螢幕右上角，
   若仍找不到，清掉記住的位置再重開：

```bash
defaults delete io.github.pito0713.floatingagenda
```

### 卡片拖不動

行程列與提醒列會吃掉點擊（因為要能點開原生 App 與勾選）。
**完整模式**請從標題區、卡片邊緣的留白、或提醒區的空白處拖曳。
**收合模式**頂部有一條專用拖曳條（中間有小握把），從那裡拖。

### 想改顯示範圍或篩選

行事曆與清單的篩選在選單列。顯示範圍目前寫死「只有今天」，
可調範圍與更細的分類篩選列在 `PLAN.md` §4.9 的後續優化項目。

## 設定項目（UserDefaults，domain `io.github.pito0713.floatingagenda`）

| Key | 型別 | 預設 | 說明 |
|-----|------|------|------|
| `panelVisible` | Bool | `true` | 是否顯示懸浮卡片 |
| `displayMode` | String | `full` | `full`／`collapsed`／`character`；不認得的值一律回 `full` |
| `panelCollapsed` | Bool | `false` | **舊版遺留**。首次啟動新版時會轉成 `displayMode` 並保留不刪（方便退回舊版），之後新程式碼只讀寫 `displayMode` |
| `characterSkinID` | String | `builtin.pixel` | 選用的角色皮膚。外部皮膚是 `skin.<資料夾名稱>`；找不到就退回內建角色 |
| `showBubble` | Bool | `true` | 角色模式要不要顯示對話泡泡 |
| `characterTopRightX` / `characterTopRightY` | Double | 無 | 角色模式的面板**右上角**，與卡片的位置分開存。兩個缺一即視為沒有記錄 |
| `opacity` | Double | `1.0` | 透明度，讀寫都夾限在 0.3–1.0 |
| `hiddenCalendarIDs` | [String] | `[]` | **被隱藏的**行事曆 ID（所以新增的行事曆預設顯示） |
| `hiddenReminderListIDs` | [String] | `[]` | 被隱藏的提醒清單 ID |
| `panelTopLeftX` / `panelTopLeftY` | Double | 無 | 卡片左上角座標，兩者缺一即視為沒有記錄 |

## 專案結構

```
Floating/
├── PLAN.md                  需求正本（§4 功能規格、§5 技術設計、§7 驗收、§4.9 後續項目）
├── VERIFICATION.md          驗證計畫（四道關卡的定義）＋ M0–M8 結果總表
├── README.md                本檔
├── Package.swift            SwiftPM，macOS 15+，零第三方依賴
├── Resources/Info.plist     LSUIElement、bundle id、4 個權限說明
├── scripts/
│   ├── build.sh             swift build → 組 .app → ad-hoc 簽章
│   └── install.sh           關舊行程 → 複製到 ~/Applications → 啟動
├── docs/verification/       M0–M8 每個里程碑的逐條驗證紀錄
├── docs/code-review-*.md    全專案 code review 報告
├── Tests/FloatingAgendaTests/  76 個單元測試（純函式、設定層、勾選路徑）
└── Sources/FloatingAgenda/  約 2,250 行
```

### Sources/FloatingAgenda

| 檔案 | 職責 |
|------|------|
| `Entry.swift` | `@main`。先看 `--dump` / `--snapshot` / `--help`，都沒有才啟動 App |
| `FloatingAgendaApp.swift` | SwiftUI `App` ＋ `MenuBarExtra`。scene body 讀 store，所以清單變動時選單會更新 |
| `AppDelegate.swift` | 建立 `PanelController`、依設定決定是否顯示、啟動 `AgendaStore` |
| **Panel/** | |
| `FloatingPanel.swift` | `NSPanel` 子類（borderless ＋ nonactivating ＋ `.floating`）＋ `FirstMouseHostingView` |
| `PanelController.swift` | 顯示／隱藏、高度同步（上緣不動）、位置記憶、透明度、螢幕配置變更救援。另含 `PanelMetrics` 與 `PanelRootView` |
| `WidgetBackground.swift` | `NSVisualEffectView` ＋ 圓角遮罩（`maskImage`，capInsets 取 2× 半徑） |
| `WindowDragArea.swift` | 覆寫 `mouseDown` 呼叫 `performDrag` 的拖曳層 |
| **Data/** | |
| `AgendaStore.swift` | EventKit 權限與讀取、變更監聽、篩選、開啟原生 App、**唯一的寫入點**（勾選完成） |
| `Models.swift` | `EventItem` / `ReminderItem` / `CalendarInfo` / `SectionState`，全部是值型別 |
| `AppSettings.swift` | UserDefaults 包裝（可見性、收合、透明度、隱藏 ID、面板位置） |
| **Views/** | |
| `WidgetView.swift` | 卡片根視圖，分派完整／收合模式，右上角收合圖示 |
| `HeaderView.swift` | 紅色星期 ＋ 粗體日期 |
| `EventsSection.swift` | 完整模式的行程區（6 筆上限、「還有 N 個」） |
| `RemindersSection.swift` | 完整模式的提醒區（6 筆上限、勾選、錯誤行） |
| `CollapsedCardView.swift` | 收合模式的兩列（進行中的行程 ＋ 第一筆提醒），字級放大 1.25 倍 |
| `PermissionPrompt.swift` | 「需要 X 存取權限」＋「打開系統設定」 |
| `MenuBarView.swift` | 選單列：顯示開關、透明度滑桿、依來源分組的篩選、重新整理、結束 |
| **Support/** | |
| `Formatting.swift` | 日期／時間／到期文字、逾期判定。跟隨系統的 12/24 小時制與 Locale |
| **Dev/** | |
| `DevDump.swift` | `--dump`，唯讀 |
| `DevSnapshot.swift` | `--snapshot`，用 mock 出 10 張 PNG |
| `MockData.swift` | 假資料與各種狀態變體 |

### 三個貫穿整個專案的設計原則

1. **View 層不認識 `AgendaStore`**（唯一例外是 `MenuBarView` 的篩選）。所有互動都是注入的
   closure，`--snapshot` 傳空實作 → **結構上不可能寫入使用者資料**。
2. **只有一個寫入點**：`AgendaStore.commitCompletion`，private，唯一呼叫端是可被取消的
   1.2 秒 Task，進入時再確認本地標記仍成立。其餘所有 EventKit 呼叫都是唯讀。
3. **純顯示的文字一律 `.allowsHitTesting(false)`**，否則會蓋住下層的 `WindowDragArea`
   讓卡片拖不動。可點的列（行程、提醒、按鈕）才保留 hit testing。

## 版本紀錄

| 版本 | 日期 | 里程碑 | 變更摘要 |
|------|------|--------|---------|
| 0.12.0 | 2026-09-22 | M9.5 皮膚擴充與交付 | 小精靈可以換成自己畫的：`~/Library/Application Support/FloatingAgenda/Skins/` 底下放 skin.json ＋ PNG，選單列「角色」下拉選單切換、「打開皮膚資料夾…」；不合格的皮膚不會出現在選單裡，`--dump` 的 Skins 區段會說明原因。M9 §7.1 十一條總驗收全部通過 |
| 0.11.3 | 2026-09-22 | M9.4 泡泡與展開 | 小精靈左邊出現對話泡泡（逾期 → 今天到期 → 卡住的專案 → 專案待辦 → 總結，每則 8 秒、滑鼠停住暫停），選單列可關閉；點小精靈或泡泡展開成完整卡片，提醒區下方多一個唯讀的專案區（燈號、進度、更新時間、卡住原因、前 3 項待辦），點標題列的小精靈收回 |
| 0.11.2 | 2026-09-22 | M9.3 像素小精靈 | 角色模式換成 16×16 的原創像素角色「小方」：四種心情（有逾期或卡住→橘、今天有事→藍、全部清空→綠、讀不到→灰）、4 fps 逐格動畫與眨眼、支援「減少動態效果」、面板隱藏與螢幕睡眠時停止動畫、3pt 門檻區分點擊與拖曳、右鍵選單。常駐 CPU 實測 0.4% |
| 0.11.1 | 2026-09-22 | M9.2 顯示模式 | 「展開／收合」兩態改成**完整／收合／角色**三態：選單列新增顯示模式分段控制、舊 `panelCollapsed` 自動遷移成 `displayMode`、面板改為錨點感知（卡片錨左上角、角色錨右上角且寬高都隨內容、無視窗陰影），兩者的位置分開記憶；角色模式目前是 64×64 佔位色塊 |
| 0.11.0 | 2026-09-22 | M9.1 專案資料層 | 唯讀掃描 `~/.agent-sessions/<專案>/latest.md`：`SessionParser`（純函式，容錯 BOM／CRLF／空檔／格式漂移）、`ProjectStore`（60 秒重讀、睡眠喚醒重讀、256KB 上限、世代守衛、相等性守衛）、`--dump` 新增 `== Projects ==` 區段；測試 76 → 128 |
| 0.10.1 | 2026-09-21 | 收合區塊標題 | 行程列上方加動態標題（正在進行中／即將到來），並拉開行程與提醒之間的區隔 |
| 0.10.0 | 2026-09-21 | 收合顯示即將到來 | 收合模式沒有進行中的行程時，改為顯示今天接下來最近的一筆；今天都結束了才顯示「今天沒有行程」 |
| 0.9.1 | 2026-09-18 | EventKit seam | 抽出 `ReminderWriter` protocol（寫入面積收斂到 5 行的 `EventKitReminderWriter`），補 13 個勾選路徑測試共 63 個；緩衝時間可注入且預設值由測試鎖住 |
| 0.9.0 | 2026-09-18 | 補測試 | 新增 testTarget 與 49 個單元測試（逾期判定／到期文案／排序／收合挑選／設定夾限），用變異測試驗證抓得到原始 bug；為可測性放寬兩個排序函式的可見性、AppSettings 抽出 SettingsStore protocol |
| 0.8.2 | 2026-09-18 | 收合放大 | 收合模式的兩列字級與尺寸放大 1.25 倍（13→16／11→14／圓圈 16→20），完整模式維持原狀；移除拖曳條的可見握把 |
| 0.8.1 | 2026-09-18 | 收合拖曳條 | 使用者實測回報收合後難拖：頂部改成 24pt 專用拖曳條，中間有常駐握把，頂部共 40pt 全寬可拖 |
| 0.8.0 | 2026-09-18 | M8 收合模式 | 卡片右上角圖示可收合成兩列（正在進行的行程 ＋ 第一筆提醒）；沒有進行中的行程時顯示「目前沒有行程」；狀態存在 `panelCollapsed` |
| 0.7.1 | 2026-09-18 | M7 打磨交付 | 完整 README（用途／建置／安裝／權限／疑難排解）、缺權限時每 3 秒快速重試（原本最慢要等 60 秒）、PLAN §7.1 總驗收 |
| 0.7.0 | 2026-09-17 | M6 權限與異常 | PermissionPrompt：權限不足時顯示說明與「打開系統設定」（Privacy_Calendars／Privacy_Reminders 深層連結，實測可用）；讀取失敗顯示原因不 crash；View 層改為全注入；`--snapshot` 新增 permission／failed／writefail 三個狀態變體 |
| 0.6.0 | 2026-09-16 | M5 選單列 | MenuBarView：顯示懸浮窗開關、透明度滑桿（30–100% 即時生效）、行事曆與提醒清單依來源分組的篩選（存被隱藏的 ID）、重新整理、結束；`--snapshot` 加輸出選單列圖 |
| 0.5.0 | 2026-09-16 | M4 提醒區 | RemindersSection：上限 6 筆與「還有 N 項」、到期文案（今天／逾期／只有日期）、逾期紅字、總數顯示、1.2 秒延遲勾選與取消、淡出過場、點標題用 `x-apple-reminderkit://` 開提醒事項 App（實測 macOS 27 可用）|
| 0.4.0 | 2026-09-16 | M3 行程區 | EventsSection：上限 6 筆與「還有 N 個行程」、「今天沒有行程」空狀態、hover 加深底色、點一列用 `ical://ekevent/` 開行事曆 App（實測 macOS 27 可用，失敗退回只開 App）；hit testing 改為逐區塊控制以保留拖曳 |
| 0.3.1 | 2026-09-16 | 需求變更 | 顯示範圍縮成只有今天：行程今天 00:00–24:00、提醒為逾期 ＋ 今天到期（無到期日不顯示）；修正只有日期沒有時間的提醒被誤判逾期 |
| 0.3.0 | 2026-09-16 | M2 資料層 | AgendaStore（EventKit 唯讀：權限判定、7 天行程、未完成提醒、0.3 秒 debounce 變更監聽、60 秒重讀、過午夜與睡眠喚醒重讀）、CalendarInfo 值型別、`--dump` 唯讀輸出；面板接上真實資料 |
| 0.2.0 | 2026-09-16 | M1 懸浮面板 | NSPanel 懸浮卡片（floating／nonactivating／不搶焦點）、NSVisualEffectView 毛玻璃圓角遮罩、拖曳移動與位置記憶（畫面外自動回主螢幕右上角）、高度跟內容伸縮且上緣不動、透明度 0.3–1.0 夾限、`--snapshot` 輸出 light／dark PNG |
| 0.1.0 | 2026-09-16 | M0 專案骨架 | SwiftPM 專案、Info.plist（LSUIElement + 4 個權限說明）、build.sh／install.sh（ad-hoc 簽章）、Entry 旗標分派、選單列圖示與「結束」 |
