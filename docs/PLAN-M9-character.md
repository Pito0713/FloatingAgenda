# M9 角色模式開發計畫書（像素小精靈＋專案進度＋待辦提醒）

> 撰寫：Claude（規劃 session，2026-09-21）
> 執行者：接手的 coding agent（另開 session）
> 狀態：規劃完成，尚未開始實作
> 上層文件：`PLAN.md`（M0–M8 的需求正本）、`VERIFICATION.md`（四道關卡）。本檔只寫 M9 新增或變更的部分，沒寫到的一律沿用 PLAN.md
> 派工格式：依 `~/Agent_skill/governance/delegation-templates.md` T2（實作）

---

## 0. 給執行 agent 的開場說明（先讀這段）

- 開工先依序讀：`~/.agent-sessions/Floating/latest.md` → 本檔 → `PLAN.md` §5（技術設計）→ `VERIFICATION.md`。
- §3 的使用者決策已經定案，**不要重新詢問或更改**。
- 非互動 session（`codex exec`、CLI one-shot）：沒有人能回覆你，**不要停下來等確認**，照 §6 一路做完，最後依 §10 回報。
- 本文件沒寫到的細節，自己選最接近「macOS 原生外觀＋8-bit 街機手感」的做法，並在回報的「自行決定事項」列出來。
- 同一個問題試兩輪都失敗，就停下來，把失敗過程寫進回報（全域鐵律 3）。
- 開工先執行 `git status`。這個 repo 常有其他 session 並行修改，**看到不是你改的東西不要動、不要 commit 進你的里程碑**。
- 可以參考 `docs/m9/Buddy-demo.swift`：這是規劃 session 做的單檔 demo，使用者看過並認可了「方向」。它是**一次性的原型**，架構不能照搬，理由見 §5.8。

---

## 1. 目標

在現有兩種顯示模式（完整／收合）之外，新增第三種**角色模式**：桌面上平常只有一隻會動的**像素小精靈**，旁邊的對話泡泡輪流講今天的待辦和各專案的下一步，身體顏色和表情反映目前的狀態。點小精靈就展開成完整卡片，卡片多了一個「專案」區；再點一下就收回小精靈。

**動機**：使用者想要一個不佔空間、又能一眼看出「今天有沒有事、哪個專案卡住了」的桌面常駐物。完整卡片資訊多但面積大，收合模式小但沒有專案資訊。

**資料來源**：
1. 待辦：沿用現有 `AgendaStore` 的提醒事項（逾期＋今天到期），**不新增 EventKit 權限或寫入點**
2. 專案進度：唯讀掃描 `~/.agent-sessions/*/latest.md`（各專案的交接文件，格式見 §5.2）

---

## 2. 已確認的環境（規劃 session 實測，2026-09-21）

| 項目 | 值 |
|------|----|
| repo 最新 commit | `feat: 收合模式加上區塊標題與區隔`（squash 前的最後一筆），README 版本紀錄最新是 **0.10.1** |
| 現有測試 | `swift test`，63 個以上（`Tests/FloatingAgendaTests/`） |
| `~/.agent-sessions/` 內容 | 目錄：`Floating`、`FloatingAgenda`，以及使用者其他專案各一個目錄，各有一份 `latest.md`；另有 `README.md`、`registry.tsv`、`hook.log` 三個**檔案**（不是專案，要略過） |
| 已搬遷的專案 | `FloatingAgenda/latest.md` 標題是「# FloatingAgenda（已搬遷 → 請讀 ../Floating/latest.md）」→ 要略過 |
| demo 驗證 | 單檔 SwiftUI＋NSPanel 的 demo 能編譯、能在 macOS 27 上執行並讀到上述資料 |

---

## 3. 使用者已定案的決策（不可更改）

| 決策點 | 選擇 | 備註 |
|--------|------|------|
| 模式關係 | **第三種顯示模式**：完整／收合／角色三選一 | 角色模式平常只有小精靈加泡泡；點小精靈展開完整卡片（多了專案區），再點收回。同一時間只有**一個面板** |
| 外觀 | **像素風的街機小精靈**當預設，**之後可以讓使用者自己擴充** | 內建一隻原創像素角色，同時做好外部皮膚的載入機制（§4.6） |
| 提醒強度 | **只換表情和冒泡泡** | 不發系統通知、不出聲音（跟 PLAN §4.8「不做通知」一致） |
| 專案區資訊 | **燈號＋進度＋待辦＋卡住** | 每個專案顯示燈號、完成比例進度條、最後更新時間、前 3 項待辦，有卡住的點就用橘字標出來。**不做**「交接落後」偵測（不跑 git） |

---

## 4. 功能規格

### 4.1 顯示模式切換

- 設定改成三選一的 `displayMode`：`full`／`collapsed`／`character`（§5.5 有舊設定怎麼遷移）
- **切換入口**：
  - 選單列新增「顯示模式」分段控制（完整／收合／角色），放在「顯示懸浮窗」開關下面
  - 完整和收合模式右上角那顆收合箭頭**維持原本行為**（只在完整、收合之間切換），不要把角色模式塞進去
- 切換模式時，面板**右上角**保持不動（角色模式靠右上角定位，理由見 §5.4）

### 4.2 角色模式：待機（平常的樣子）

```
                 ╭──────────────────────────╮
                 │ 📌 還有 3 件待辦，點我看看  │ ← 對話泡泡（在小精靈左邊）
                 ╰─────────────────────────▷╯
                                       ▄██▄
                                      █▀██▀█     ← 像素小精靈（64×64pt）
                                      ██████
                                      ▀▀  ▀▀
```

- 小精靈固定 **64×64pt**（16×16 像素格，每格 4pt）。泡泡在小精靈**左邊**、垂直置中，最寬 220pt，最多 3 行，超過就截斷加「…」
- **沒有泡泡時，面板大小就是小精靈的大小**，桌面其他地方不能被透明區域擋住點擊（§5.4）
- 拖曳小精靈可以移動整個面板；位置要記住（跟完整和收合模式**分開存**，§5.5）
- 右鍵小精靈跳出選單：「展開」、「重新整理」、「切換成完整模式」、「結束 FloatingAgenda」
- 滑鼠停在泡泡上時，暫停輪播；點泡泡的效果跟點小精靈一樣（展開）

### 4.3 心情與動畫

| 心情 | 什麼時候 | 身體主色 | 表情與動作 |
|------|---------|---------|-----------|
| `worried` 😰 | 有**逾期**的提醒，或任一專案有卡住的點，或燈號是 🔴 | 橘 | 眉毛下垂、嘴巴往下、頭上有汗滴像素；每 5 秒左右抖一下 |
| `busy` 🙂 | 沒有上面那些，但有今天到期的提醒，或任一專案還有沒做的待辦 | 藍 | 平的嘴巴；上下彈跳 |
| `happy` 😄 | 全部清空 | 綠 | 笑臉；上下彈跳，偶爾原地跳一下 |
| `sleepy` 😴 | 提醒和專案**都讀不到**（沒權限，而且 `~/.agent-sessions` 不存在或讀取失敗） | 灰 | 閉眼、頭上有 z 像素；不彈跳 |

- 判定順序由上往下，第一個符合的就是答案。寫成**純函式** `Mood.decide(reminders:projects:now:)`，要有單元測試
- **動畫一律是逐格像素動畫**：每種心情 2–4 格，播放速度 **4 fps**（街機手感，也比較省電）。眨眼：每 3–5 秒隨機一次、持續 1 格
- 系統設定開啟「減少動態效果」（`accessibilityReduceMotion`）時：不彈跳、不抖，只保留換心情和眨眼
- 面板隱藏、螢幕鎖定或睡眠時，**動畫計時器要停**（§5.3）

### 4.4 對話泡泡

輪播清單照以下優先順序組成（同一級依原本的排序）：

1. 逾期提醒：`⏰ 逾期：<標題>`（全部列出）
2. 今天到期的提醒：`📌 今天：<標題>`（最多 3 則）
3. 卡住的專案：`⚠️ <專案> 卡住了：<卡住的點第一行>`
4. 每個專案的下一件待辦：`🔧 <專案>：<第一個還沒打勾的項目>`
5. 最後一則固定是總結：有待辦 →「今天還有 N 件事，點我看看」；全部清空 →「今天都清空了 ✨」

- 每則顯示 **8 秒**，換下一則時有淡入淡出（「減少動態效果」開啟時直接換）；輪完一圈從頭開始
- 資料一更新就**重建清單**，但**不要打斷**正在顯示的那一則；如果那一則已經不在新清單裡，才立刻換下一則
- 選單列新增「顯示對話泡泡」開關（預設開）。關掉時只剩小精靈，心情照樣會變
- 清單的組成寫成純函式 `BubbleComposer.lines(reminders:projects:now:)`，要有單元測試

### 4.5 角色模式：展開

- 點小精靈（或點泡泡）→ 面板展開成**完整卡片**，小精靈縮小成 24pt 放在卡片標題列最左邊（表示「目前在角色模式」），點這個小圖示或按 `Esc` 就收回小精靈
- 展開的卡片 = 現有的完整卡片（行程＋提醒，**所有互動都跟原本一樣**），在提醒區下方多一個 **專案區**：

```
├──────────────────────────────┤
│ 專案                       ↻ │
│ Floating            🟢 順暢  │
│ ████████████░░░░  8/12       │
│ 9月18日 15:20 更新            │
│ ○ PLAN §4.9 後續優化…        │
│ ○ PLAN §7.2 的 12 項手動…     │
│ ○ M4 的 ESCALATE 未決…       │
│ ＋1 項                       │
│                              │
│ 另一個專案           🟡 進行中 │
│ ⚠️ 卡住的原因（橘字）          │ ← 卡住的點（橘字，最多 2 行）
│ …                            │
╰──────────────────────────────╯
```

- 專案排序：有卡住的點 → 🔴 → 🟡 → 🟢 → 其他；同一級照「最後更新」由新到舊
- 專案區最多 **4 個專案**，超過就顯示「還有 N 個專案」。整張卡片最高 **620pt**，專案區超過的部分在區內捲動（行程區和提醒區不捲）
- 專案**完全是唯讀的**：打勾圓圈只是顯示，**點了沒有反應**（不能寫回 latest.md）。點專案名稱 → 用 Finder 打開 `~/.agent-sessions/<專案>/latest.md`（`NSWorkspace.shared.open`，會用使用者預設的 .md 編輯器開）
- 專案區的狀態：讀取中／沒有任何專案（「還沒有任何交接紀錄」）／`~/.agent-sessions` 不存在（「找不到 ~/.agent-sessions」）／讀取失敗（顯示原因）。**任何一種都不能讓整張卡片出錯**
- **完整模式和收合模式都不顯示專案區**（避免影響已經驗收的 M0–M8 畫面）
- 展開與否是暫時狀態，**不要存**。重開 App 一律從小精靈開始

### 4.6 皮膚擴充（使用者之後自己做角色）

- 內建一隻原創像素角色，皮膚 ID 是 `builtin.pixel`，**永遠存在、不能刪**
- 外部皮膚放在 `~/Library/Application Support/FloatingAgenda/Skins/<皮膚資料夾>/`，一個資料夾就是一個皮膚：

```
Skins/my-cat/
├── skin.json
├── happy-0.png  happy-1.png
├── busy-0.png   busy-1.png
├── worried-0.png worried-1.png
├── sleepy-0.png
└── blink.png          # 選用；沒有就不眨眼
```

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

- 驗證規則（任一條不符合 → 那個皮膚不出現在選單裡，並在 `--dump` 列出原因；**App 不能 crash**）：
  - `formatVersion` 必須是 1；`pixelSize` 在 8…64 之間；`fps` 在 1…12 之間
  - 四種心情都要至少 1 格；每張圖都是 PNG，尺寸剛好 `pixelSize × pixelSize`
  - 檔名只能是同一個資料夾裡的檔案：不接受 `/`、`..`，也不跟隨指向資料夾外面的 symlink
  - `skin.json` 最大 64KB、單張圖片最大 256KB、一個皮膚最多 64 張圖
- 渲染一律**最近鄰插值**（`.interpolation(.none)`），放大到 64pt，像素要銳利
- 選單列新增「角色」下拉選單：列出內建角色和所有有效的外部皮膚，再加一項「打開皮膚資料夾…」（資料夾不存在就先建立再打開）
- 使用者選的皮膚存 `characterSkinID`；啟動時找不到那個皮膚就退回 `builtin.pixel`
- 皮膚只在**啟動時**和**打開角色選單時**重新掃描，不用監聽資料夾
- README 新增一節「自製角色」，寫清楚上面的格式（M9.5 產出）

### 4.7 不在範圍內（不要做）

系統通知、音效、交接落後偵測（跑 git）、寫回 latest.md、點專案待辦打勾、網路下載皮膚、GIF／Lottie 格式的皮膚、多隻角色同時出現、角色在桌面上自己走來走去、角色模式的全域快捷鍵。

→ 做完後可以列在回報的「未來可加」，但**不要實作**。

---

## 5. 技術設計

### 5.1 新增和修改的檔案

```
Sources/FloatingAgenda/
├── Data/
│   ├── ProjectStore.swift        # 新增：掃描 ~/.agent-sessions、60 秒重讀、狀態
│   ├── SessionParser.swift       # 新增：latest.md → ProjectItem（純函式）
│   ├── Models.swift              # 修改：加 ProjectItem、ProjectStatus
│   └── AppSettings.swift         # 修改：displayMode、角色位置、showBubble、characterSkinID
├── Character/                    # 新增資料夾
│   ├── Mood.swift                # Mood 列舉 + Mood.decide（純函式）
│   ├── BubbleComposer.swift      # 泡泡清單（純函式）
│   ├── PixelSprite.swift         # 16×16 字元格 → CGImage；內建角色的格子資料
│   ├── SkinLoader.swift          # 外部皮膚掃描與驗證
│   ├── CharacterView.swift       # 小精靈（逐格動畫、減少動態效果）
│   └── BubbleView.swift          # 對話泡泡與輪播
├── Views/
│   ├── ProjectsSection.swift     # 新增：展開卡片的專案區
│   ├── WidgetView.swift          # 修改：可選的專案區、角色模式的標題列小圖示
│   └── MenuBarView.swift         # 修改：顯示模式、對話泡泡開關、角色選單
├── Panel/PanelController.swift   # 修改：角色模式的尺寸與右上角定位
└── Dev/
    ├── DevDump.swift             # 修改：加專案和皮膚區段
    ├── DevSnapshot.swift         # 修改：加角色模式變體
    └── MockData.swift            # 修改：加 mock 專案

Tests/FloatingAgendaTests/
├── SessionParserTests.swift
├── MoodTests.swift
├── BubbleComposerTests.swift
├── PixelSpriteTests.swift
├── SkinLoaderTests.swift         # 用暫存資料夾，測完刪掉
├── DisplayModeMigrationTests.swift
└── Fixtures/sessions/…           # latest.md 樣本（見 §5.2）
```

### 5.2 資料層：SessionParser 與 ProjectStore

**latest.md 的格式**（實際樣本，由 `~/Agent_skill` 的 handoff skill 產生）：

```markdown
# Floating

> 路徑：~/Floating
> 最後更新：2026-09-18 15:20
> 寫入者：claude
> 觸發來源：handoff
> 狀態：🟢 順暢

## 當前焦點
…
## 進行中

- [x] M0 專案骨架（…）
- [ ] PLAN §4.9 後續優化：…

## 下一步
1. …
## 卡住的點

無（上述收合高度疑點是待查證，不是卡住）

## 本輪決策
…
```

```swift
enum ProjectStatus: Hashable { case green, yellow, red, unknown }   // 由狀態字串裡的 🟢🟡🔴 判斷

struct ProjectItem: Identifiable, Hashable {
    let id: String              // 目錄名稱
    let name: String            // 「# 」後面的標題；沒有就用目錄名稱
    let status: ProjectStatus
    let statusText: String      // 「🟢 順暢」原文，UI 直接顯示
    let updated: Date?          // 「最後更新：yyyy-MM-dd HH:mm」，用目前時區解析；格式不對就 nil
    let done: Int
    let total: Int
    let openTodos: [String]     // 還沒打勾的項目，保留原本順序
    let blocker: String?        // 「卡住的點」區段；空的或以「無」開頭 → nil
    let fileURL: URL
}
```

解析規則（`SessionParser.parse(directoryName:text:fileURL:) -> ProjectItem?`，**純函式，不碰檔案系統**）：

- 第一個 `# ` 標題裡有「已搬遷」→ 回傳 `nil`（整個專案略過）
- `> 狀態：`、`> 最後更新：` 這兩行容許前後有空白，也容許全形冒號以外的 `:`
- 打勾項目**只算 `## 進行中` 這個區段**；找不到這個區段才改算整份檔案。`- [x]`、`- [X]` 算完成，`- [ ]` 算未完成；縮排的子項目也算
- 打勾項目的文字要拿掉 markdown 的粗體和 code 符號（`**`、`` ` ``），UI 才不會出現星號
- 「卡住的點」取到下一個 `## ` 為止的第一段非空文字；`無`、`無。`、`無（…）` 都算沒有卡住
- 要能處理 CRLF 換行、檔案開頭的 BOM、完全空白的檔案（回傳一個全部是預設值的 ProjectItem，名稱用目錄名稱）

`ProjectStore`（`@MainActor @Observable final class`，`static let shared`，跟 AgendaStore 同一套寫法）：

- 狀態：`SectionState<ProjectItem>`（沿用現有的 loading／failed／loaded；「資料夾不存在」用 `failed` 加上專用訊息）
- 掃描：`~/.agent-sessions` 底下**第一層的資料夾**，每個讀 `latest.md`；檔案超過 **256KB 就略過**（交接文件不可能那麼大，避免誤讀）。在背景讀檔，讀完再切回 MainActor 寫入狀態
- 重讀時機：啟動時、跟著 AgendaStore 現有的 60 秒計時一起、睡眠喚醒時、角色模式**展開時**、選單列按「重新整理」時。**不用** FSEvents
- 路徑用 `FileManager.default.homeDirectoryForCurrentUser`，**不要寫死 `~`**
- **只讀不寫**：這個檔案裡不能出現任何 `write`、`createFile`、`removeItem`（§7.1 會 grep 檢查）

### 5.3 小精靈與動畫

**內建角色的畫法**：用字元格定義，程式裡轉成 `CGImage`，**不用放圖檔**。一個字元代表一格像素：

| 字元 | 意思 |
|------|------|
| `.` | 透明 |
| `D` | 外框（深色，每種心情共用） |
| `B` | 身體主色（依心情換色，§4.3） |
| `S` | 身體陰影（主色調暗 25%） |
| `W` | 眼白 |
| `K` | 瞳孔、嘴巴 |
| `P` | 腮紅 |
| `X` | 特效（汗滴、z），淺藍 |

參考底稿（`happy` 第 0 格，16×16）。**這只是起點，可以自己調整**，但成品一定要是**原創角色**：

```
................
.....DDDDDD.....
...DDBBBBBBDD...
..DBBBBBBBBBBD..
.DBBBBBBBBBBBBD.
.DBBWWBBBBWWBBD.
.DBBWKBBBBWKBBD.
.DBBWKBBBBWKBBD.
.DBPBBBBBBBBPBD.
.DBBBBKBBKBBBBD.
.DBBBBBKKBBBBBD.
.DSBBBBBBBBBBSD.
.DSSBBBBBBBBSSD.
..DSSDSSSSDSSD..
...DD.DDDD.DD...
................
```

- **版權底線**：可以是「8-bit 街機風格」，但**不能**照抄 Pac-Man 本體、它的四隻鬼、太空侵略者，或任何既有遊戲角色的造型和配色。回報裡要附一句設計說明，講清楚跟這些角色哪裡不一樣
- `PixelSprite` 要驗證：每一列都剛好 16 個字元、共 16 列、只能用上表的字元。**格子資料壞掉就在測試階段失敗**，不要等到執行時才發現
- 每種心情至少 2 格（`sleepy` 可以只有 1 格）＋1 格眨眼。眨眼格可以直接把眼睛那幾列換成 `D` 橫線
- 動畫用 `TimelineView(.periodic(from:by: 0.25))` 驅動 4 fps。**不要用 `repeatForever` 的 SwiftUI 動畫**：那個會用螢幕更新率一直重繪，CPU 比較高（demo 就是這樣寫的）
- 彈跳是**整格位移**（每次移 4pt，也就是 1 格像素），不是平滑位移，要維持像素感
- 面板隱藏時不要渲染 `CharacterView`；收到 `NSWorkspace.screensDidSleepNotification`／`sessionDidResignActiveNotification` 就暫停，醒來再恢復

### 5.4 面板：角色模式的尺寸與點擊穿透

現在的 `PanelController` 是**寬度固定 320、上緣固定、高度跟著內容**。角色模式要改成：

- **錨點是右上角**：角色模式下，面板的右上角固定不動，寬和高都跟著內容變（小精靈、小精靈加泡泡、展開的卡片）。泡泡往左長、卡片往左下長，小精靈的位置就不會跳
- 根視圖用 `.fixedSize()`，再用 `.onGeometryChange(for: CGSize.self)` 把**寬和高**都回報給 PanelController，套用方式跟現有的 `setContentHeight` 一樣（`isAdjustingFrame` 防遞迴、`invalidateShadow()`）
- **點擊穿透一律靠「面板大小剛好等於看得到的內容」**，也就是說沒有泡泡時，面板就是 64×64 加上邊距。**禁止**用計時器輪詢滑鼠位置、切換 `ignoresMouseEvents`（demo 是這樣做的，那是原型才用的偷懶做法）
- 角色模式的面板**不要有陰影**（`hasShadow = false`），也不要有毛玻璃底和邊框。小精靈和泡泡自己畫陰影；展開成卡片時再恢復成原本的樣子
- 拖曳：小精靈用現有的 `WindowDragArea` 方式（`performDrag`），但這樣會吃掉點擊。解法是讓 `mouseDown` 記下位置，`mouseDragged` 移動超過 3pt 才呼叫 `performDrag`，`mouseUp` 時沒有拖曳過就當作「點一下」，透過 closure 通知 SwiftUI。右鍵選單用 `menu(for:)` 回傳 `NSMenu`
- 位置記憶：角色模式存**右上角**（`characterTopRightX/Y`），跟現有的 `panelTopLeft` 分開；螢幕範圍檢查沿用 `isUsable`，不在畫面內就回預設位置（主螢幕 `visibleFrame` 右下角往內 20pt，泡泡要能完整顯示在畫面內）
- 展開成卡片時，如果卡片會超出螢幕下緣，就往上推到剛好放得下（不改存起來的小精靈位置）
- 注意：現有程式很多地方寫死 `PanelMetrics.width`，角色模式展開後的卡片寬度一樣是 320，但**小精靈和泡泡的狀態下不能被這個值鎖住**。改之前先 `grep -n "PanelMetrics.width" Sources/` 把每個用到的地方看過一遍

### 5.5 設定（AppSettings）

新增的 key：

| Key | 型別 | 預設 | 說明 |
|-----|------|------|------|
| `displayMode` | String | 見下方遷移規則 | `full`／`collapsed`／`character`；讀到不認得的值 → `full` |
| `showBubble` | Bool | `true` | |
| `characterSkinID` | String | `builtin.pixel` | 外部皮膚用 `skin.<資料夾名稱>` |
| `characterTopRightX` / `characterTopRightY` | Double | 沒有 | 兩個缺一就當作沒有 |

**遷移規則**：`displayMode` 不存在時，看舊的 `panelCollapsed`：`true` → `collapsed`，其他 → `full`，然後寫入 `displayMode`。`panelCollapsed` **保留不刪**（這樣退回舊版還能用），但新程式碼只讀寫 `displayMode`。遷移要有單元測試（用現有的 `InMemorySettingsStore`）。

### 5.6 View 層原則（沿用 M6 的做法，不能破壞）

- `CharacterView`、`BubbleView`、`ProjectsSection` 都**不認識** `ProjectStore`、`AgendaStore`，資料和互動一律從外面注入。這樣 `--snapshot` 才能用 mock 資料渲染，而且結構上不可能寫入任何東西
- 泡泡和專案區的文字是純顯示的，要加 `.allowsHitTesting(false)`，拖曳才不會被擋住

### 5.7 開發輔助指令

- `--dump`：在最後加兩個區段
  - `== Projects ==`：每個專案一行 `id | 燈號 | done/total | 更新時間 | 有沒有卡住`，再列出前 3 項待辦
  - `== Skins ==`：每個皮膚一行 `id | 名稱 | 有效／無效（原因）`
- `--snapshot <前綴>`：新增下面這些輸出（light／dark 各一張，scale 2）
  - `<前綴>-char-happy`、`-char-busy`、`-char-worried`、`-char-sleepy`：只有小精靈
  - `<前綴>-char-bubble`：小精靈加一則兩行的泡泡
  - `<前綴>-char-expanded`：展開的卡片（mock：3 個專案，其中一個卡住、一個超過 3 項待辦）
  - `<前綴>-char-sprites`：把內建角色**所有動畫格**排成一張放大 8 倍的圖，方便檢查像素

### 5.8 為什麼 demo 的寫法不能照搬

`docs/m9/Buddy-demo.swift` 只是讓使用者看感覺的原型，下面這些是刻意偷懶的地方，正式版一定要換掉：

| demo 的做法 | 問題 | 正式版 |
|------------|------|--------|
| 每 0.05 秒輪詢滑鼠位置、切換 `ignoresMouseEvents` | 一直喚醒 CPU；熱區是寫死的矩形 | §5.4：面板大小剛好等於內容 |
| `repeatForever` 的平滑彈跳 | 用螢幕更新率重繪、沒有像素感 | §5.3：4 fps 逐格動畫 |
| 用 SwiftUI 形狀畫圓糰子 | 不是使用者選的像素風 | §5.3：字元格畫的像素角色 |
| `.canJoinAllSpaces` | 使用者在 PLAN §3 沒選「每個桌面空間都顯示」 | 沿用 `FloatingPanel` 現有的設定 |
| 待辦從 latest.md 的 `- [ ]` 抓 | 那是專案待辦，不是使用者的提醒事項 | §4.4：提醒來自 AgendaStore，專案待辦分開列 |
| 整份檔案的 `- [ ]` 都算 | 跟「進行中」以外的區段混在一起 | §5.2：只算 `## 進行中` |

---

## 6. 開發步驟（里程碑）

每個子里程碑都要跑完 `VERIFICATION.md` 的**四道關卡**（Gate 1 機器驗證 → Gate 2 codex 審查 → Gate 3 仲裁 → Gate 4 Close Gate），**一個子里程碑一個 commit**（`feat(M9.<n>): …`），commit 前更新 README 版本紀錄表（M9.1 是 0.11.0，之後每個 +0.0.1，M9.5 是 0.12.0）。驗證紀錄寫在 `docs/verification/M9.<n>.md`，並在 `VERIFICATION.md` §2、§4 的表格加上 M9 的列。

| # | 里程碑 | 內容 | 這個階段完成的判準 |
|---|--------|------|------------------|
| M9.1 | 專案資料層 | `ProjectItem`、`SessionParser`、`ProjectStore`、`--dump` 的 Projects 區段、fixtures 和 `SessionParserTests` | `swift test` 全綠；`--dump` 列出 `~/.agent-sessions` 底下所有未標示「已搬遷」的專案，**沒有** 標示已搬遷的目錄，也**沒有**那三個非專案檔案（貼輸出） |
| M9.2 | 顯示模式 | `displayMode` 和遷移、選單列的分段控制、PanelController 的右上角錨點和寬高同步（角色模式先放一個 64×64 的色塊） | 遷移測試全綠；用 `defaults write io.github.pito0713.floatingagenda displayMode character` 啟動，實測面板是 64pt 見方加邊距，而且 5 秒後 `pgrep` 還在；切回 full 後卡片跟 M8 的 snapshot 一模一樣 |
| M9.3 | 像素小精靈 | `PixelSprite`、內建角色的全部格子、`Mood.decide`、`CharacterView`（4 fps、眨眼、減少動態效果、暫停）、點擊與拖曳的判斷、右鍵選單 | `PixelSpriteTests`、`MoodTests` 全綠；`-char-*` 四種心情和 `-char-sprites` 的 snapshot **自己打開看過**；§7.1 的 CPU 量測通過 |
| M9.4 | 泡泡與展開 | `BubbleComposer`、`BubbleView` 輪播、「顯示對話泡泡」開關、展開成卡片、`ProjectsSection`、展開後往上推的邏輯 | `BubbleComposerTests` 全綠；`-char-bubble`、`-char-expanded` 的 snapshot 對照 §4.2、§4.5 逐項；完整和收合模式的 snapshot 跟 M9 開工前**一模一樣**（證明沒有影響到舊畫面） |
| M9.5 | 皮膚擴充與交付 | `SkinLoader`、選單列的角色選單、「打開皮膚資料夾…」、`--dump` 的 Skins 區段、README「自製角色」一節、§7.1 總驗收 | `SkinLoaderTests` 全綠（含 §4.6 每一條驗證規則的反例）；§7.1 全部通過 |

---

## 7. 驗收條件

### 7.1 agent 自己驗證（全部達成才算完成，缺一條就回報「進行中」）

- [ ] `rm -rf .build build && bash scripts/build.sh` 成功，貼最後 20 行
- [ ] `swift test` 全綠，貼測試總數（要比 M9 開工前多），以及新增的測試檔清單
- [ ] `--dump` 的 Projects 和 Skins 區段，貼輸出
- [ ] §5.7 列的所有 `-char-*` snapshot 都有產生，而且**你自己打開看過**，逐項對照 §4.2、§4.3、§4.5，回報哪些一致、哪些有差
- [ ] M9 開工前後，完整和收合模式的 snapshot **逐位元組一樣**（`cmp` 兩張圖，貼輸出）。M9 開工第一件事就是先把這幾張存到 scratchpad 當基準
- [ ] **CPU**：用 `displayMode character` 啟動，等 10 秒後每秒取一次 `ps -o %cpu= -p <pid>`，連續取 30 秒，**平均 < 2%**，貼數字
- [ ] 零網路：`grep -rnE "URLSession|http://|https://" Sources/` 沒有結果
- [ ] 寫入點稽核：`grep -rn "save(\|remove(\|isCompleted = true" Sources/` 跟 M9 開工前一樣，只出現在既有的勾選路徑
- [ ] 檔案唯讀稽核：`grep -rnE "write\(|createFile|removeItem|moveItem" Sources/FloatingAgenda/Data/ProjectStore.swift Sources/FloatingAgenda/Data/SessionParser.swift Sources/FloatingAgenda/Character/` 沒有結果。唯一的例外是「打開皮膚資料夾…」裡的 `createDirectory`，要在回報裡說明
- [ ] 沒有寫死路徑：`grep -rn "$HOME" Sources/` 沒有結果（shell 會代換成執行者自己的家目錄，等於檢查有沒有人把絕對路徑寫死）
- [ ] `git log --oneline` 顯示 M9.1 到 M9.5 共 5 個 commit

### 7.2 需要使用者手動驗收（agent 整理成清單附在回報裡，不用自己做）

1. 選單列切到「角色」：卡片變成小精靈，位置在原本卡片的右上角附近
2. 小精靈旁邊的**透明區域可以直接點到後面的視窗**（例如點後面的 Finder 圖示）
3. 泡泡大約每 8 秒換一則，內容有你真實的提醒和專案下一步；滑鼠停在泡泡上會暫停
4. 拖曳小精靈可以移動；結束再重開，小精靈回到原位；切回完整模式，卡片也回到**卡片自己的**舊位置
5. 點小精靈展開成卡片：行程、提醒可以照常點和勾選，專案區顯示正確；點標題列的小精靈圖示或按 Esc 收回
6. 點專案名稱，會用你預設的編輯器打開那個 latest.md
7. 去改某個專案的 latest.md（例如把一項打勾），60 秒內小精靈的心情或泡泡跟著變（或按「重新整理」立刻變）
8. 系統設定 → 輔助使用 → 顯示 → 開啟「減少動態效果」：小精靈不彈跳，但還是會眨眼、會換心情
9. 照 README「自製角色」的說明做一個兩格的皮膚，放進資料夾，打開角色選單就看得到，選了之後會換成它
10. 故意把 `skin.json` 寫壞：選單裡不出現那個皮膚，App 也沒有 crash
11. 深色和淺色模式下，小精靈、泡泡、專案區都看得清楚
12. 完整模式和收合模式看起來、用起來都跟 M9 之前一樣

---

## 8. 範圍和禁區

- **可以修改**：`~/Floating/` 底下的所有檔案
- **只能讀**：`~/.agent-sessions/`（**不能**新增、修改、刪除裡面任何東西，也不能改變權限或時間戳記）
- **可以建立**：`~/Library/Application Support/FloatingAgenda/Skins/`（只有使用者按「打開皮膚資料夾…」時才建立）。測試用的皮膚一律放在 `FileManager.default.temporaryDirectory` 底下，測完刪掉，**不能**寫進使用者真正的皮膚資料夾
- **禁區**：沿用 PLAN §8 和 VERIFICATION §3 的全部紅線。特別注意：
  - 不能寫入使用者的行事曆和提醒資料
  - 不能碰 `~/Agent_skill` 和其他專案的 repo（包括不能「順便」修 latest.md 的格式）
  - 不能自己執行 `tccutil reset`
  - 不能有網路呼叫和第三方套件
- **不允許**：做 §4.7 列的功能、為了讓驗收通過而刪減規格、改動完整和收合模式的畫面或行為

---

## 9. 已知風險

| 風險 | 說明 | 處理方式 |
|------|------|---------|
| 動態改面板寬度 | 現有程式假設寬度固定 320，改成寬高都會變，可能讓位置記憶、畫面外回收、陰影出錯 | §5.4：角色模式用獨立的錨點和位置 key，完整和收合模式的程式路徑盡量不動；M9.2 用 snapshot 比對確認舊模式沒被影響 |
| 點擊和拖曳搶事件 | 同一個小精靈要能點、能拖、能右鍵 | §5.4：自己在 NSView 判斷 3pt 門檻，不要用 SwiftUI 的 `DragGesture` 加 `onTapGesture`（在 nonactivating panel 上第一下常常被吃掉） |
| latest.md 格式漂移 | handoff skill 之後可能改格式 | 解析器容錯：欄位缺少就用預設值，不能讓整個專案消失。fixtures 要涵蓋缺欄位的情況 |
| 動畫耗電 | 常駐的動畫最容易在背景一直耗 CPU | §5.3 的 4 fps 和暫停條件；§7.1 的 CPU 量測 |
| 像素角色的版權 | 「街機小精靈」很容易畫成 Pac-Man 或它的鬼 | §5.3 的版權底線；回報裡附設計說明 |
| 其他 session 並行修改 | 這個 repo 同一天常有別的 session 在改收合模式 | 開工和每次 commit 前都 `git status`，只 commit 自己的檔案；衝突就停下來回報 |

---

## 10. 回報格式（做完交給使用者）

1. **plan**：實際怎麼做的（5 行內），跟本計畫不一樣的地方要特別標出來
2. `git log --oneline` 和 `git diff --stat <M9.1 前一個 commit>..HEAD`
3. §7.1 每一條的證據（**實際貼上輸出**，不能只寫「已通過」）
4. snapshot 圖檔路徑，以及跟 §4 線框對照的結果
5. 內建角色的設計說明（包括跟既有遊戲角色哪裡不一樣）
6. 自行決定事項
7. §7.2 使用者手動驗收清單（直接複製過來）
8. 剩餘風險和未來可加的功能（沒有也要寫「無」）

---

## 11. 規劃 session 的背景紀錄

- 使用者問能不能在 Mac 桌面做一個懸浮小人，用來看專案進度和待辦提醒
- Claude 發現使用者已經有 `~/Floating`（M0–M8 已完成），也有 `~/.agent-sessions/*/latest.md` 可以當專案進度的資料，所以建議做成 Floating 的 M9，不另開 app
- 使用者要先看 demo → Claude 在 scratchpad 寫了單檔的 `Buddy.swift`（SwiftUI 圓糰子、泡泡輪播、點擊展開專案卡片），編譯後在使用者桌面上執行。使用者回覆「這功能不錯」。這份原型已經複製到 `docs/m9/Buddy-demo.swift` 供參考
- 使用者透過選擇題定案 §3 的四個決策。外觀那一題，使用者沒選提供的兩個選項，而是自己填「先用像素的街機小精靈當預設，後續可以讓使用者去擴充」→ 變成 §4.6 的皮膚機制
