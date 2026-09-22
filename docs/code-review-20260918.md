# 全專案 Code Review — 2026-09-18

> 審查範圍：`Sources/` 22 檔 2,247 行 ＋ `Package.swift` ＋ `Resources/Info.plist`
> 交叉驗證：Claude 初審 ＋ codex-cli 0.154.0 冷啟動複審
> 時機：M0–M8 全部 CLOSE 之後。此前每個里程碑只審過**當輪的 diff**，
> 這是第一次以全專案為單位審查，目的正是抓出單一 diff 看不出來的跨檔案／跨里程碑問題。

## 方法

依 `code-review` skill 的 Phase 5 鐵律：**reviewer 不得看到初審報告**，避免錨定偏誤。
執行順序是先把 codex 派出去（只給原始碼路徑與六個審查維度，不給我的任何結論），
我再同時做自己的初審，最後逐條比對。

codex 用 `-s read-only` 在唯讀 sandbox 內自己讀檔（而非餵 diff），因為這次要審的是
跨檔案一致性，diff 沒有那個資訊。

## 結果總覽

| 嚴重度 | 數量 | 來源分布 |
|--------|------|---------|
| HIGH | 1 | codex 獨有 |
| MEDIUM | 6 | codex 2、Claude 3、雙方各自發現同一根因 1 |
| LOW | 7 | codex 3、Claude 4 |

**codex 共 10 條，我全部查證：8 條 CONFIRMED、2 條降級（見爭議項目）。
我獨有 7 條。雙方獨立發現同一個根因 1 條（`.id(revision)`）。**

---

## 🟠 HIGH

### 1. 緩衝期內隱藏清單或權限被撤，提醒會被靜默標記完成

`AgendaStore.swift:194-201`　來源：**codex 獨有**

`loadReminders` 的兩個同步提前 `return`（權限不足、全部清單被隱藏）都沒有清掉
`pendingCompletion`、也沒取消 `completionTasks`。而 `commitCompletion` 的守衛只檢查
`pendingCompletion.contains(id)`——集合還在，寫入照走。

重現：點圓圈 → 1.2 秒內從選單列關掉該清單 → 該列從卡片消失、失去取消入口 → 1.2 秒到，
`isCompleted = true` 寫進使用者的提醒事項。

**為什麼 M4 的驗證沒攔到**：M4 時 codex 抓到的第一條 HIGH 是同一類問題，但當時只修了
**非同步 callback** 那條路徑（`subtracting(ids)` 的清理）。兩個同步 return 沒被想到，
而 M4 的 diff 審查看的是那次的改動，不會回頭質疑「還有沒有別的路徑」。
**這正是全專案審查的價值所在。**

---

## 🟡 MEDIUM

### 2. `.id(revision)` 會摧毀並重建整個子樹

`PanelController.swift`（`PanelRootView`）、`MenuBarView.swift:88`
來源：**雙方確認**（codex 指滑桿、Claude 指 hover 狀態）

`AppSettings` 不是 `@Observable`，所以用 `@State private var revision` 觸發重繪是必要的；
但 `.id()` 是錯的工具——**`@State` 變動本身就會讓 body 重新計算**，`.id()` 額外做的是把子樹
連同內部狀態丟棄重建。

- 透明度 Slider：拖曳中每次變動都 bump revision → 控制項被替換 → 可能中斷連續拖曳
- 收合圖示：點展開後 `isHoveringCard` 重設為 false → 游標還在卡片上但箭頭消失

### 3. 位置檢查只看左上角一個點

`PanelController.swift:165`　來源：codex

`isOnVisibleScreen` 只驗左上角。實際可觸發：把收合的卡片（142pt）拖到接近螢幕底部 → 展開（583pt）
→ 高度同步保持上緣不動往下長 → 大半張卡片在畫面外。
PLAN §4.1 的字面只要求檢查「位置」，但使用者會遇到。

### 4. 最關鍵檔案的檔頭註解是錯的

`AgendaStore.swift:5-8`　來源：**Claude 獨有**

檔頭仍寫「**唯讀**：本型別不包含任何寫入使用者行事曆或提醒的路徑。勾選完成（唯一的寫入點）
在 M4 才加入」——M4 早已加入，寫入點就在第 326-327 行。接手的人若信了這句話去改這個檔案，風險很高。

### 5. `eventIdentifier` 為 nil 時產生每次都不同的隨機 id

`AgendaStore.swift:164`　來源：**Claude 獨有**

`event.eventIdentifier ?? UUID().uuidString` 讓 `EventItem.id` 每次重讀都變 →
SwiftUI `ForEach` 識別漂移（列重建、淡出動畫失準），`openInCalendar` 也會送出假 identifier。
**目前不會發作**（實測今天 5 筆事件都有 id），但使用者有 Birthdays 與訂閱行事曆，
那類來源是已知可能沒有 identifier 的。

### 6. `completionError` 永遠不會自動清除

`AgendaStore.swift:335-338`　來源：**Claude 獨有**

只在 `toggleCompletion` 開頭清。一次寫入失敗後紅字會一直留在卡片上，直到使用者下次點某個圓圈；
`refresh()` 不會清它。

### 7. 零測試 target

`Package.swift`　來源：codex（原為兩條，合併）

PLAN 從未要求測試（驗證靠 `--dump`／`--snapshot` ＋ codex 逐輪審查），這個取捨當時合理。
但**本次的 HIGH 就是反證**：那個函式在 M4 已被 codex 專門審過，同類漏洞仍留了一條路徑。

值得注意的是**最該測的東西現在就能測，不需要任何重構**——以下全是純函式：
`Formatting.reminderDueLabel` / `isOverdue`、`AgendaStore.eventOrder` / `reminderOrder`、
`CollapsedCardView.inProgressEvent`。日期邊界（跨午夜、DST、整天、只有日期的到期日、
剛好等於 `now`）也全是純邏輯。

---

## 🟢 LOW

| # | 位置 | 描述 | 來源 |
|---|------|------|------|
| 8 | `AgendaStore.swift:182` | 排序先比日期再比整天，昨天開始跨午夜的定時行程會排在今天的整天行程之前。需求改成「只有今天」後，按日期排序其實是 7 天版的遺留，可簡化 | codex |
| 9 | `AgendaStore.swift:215` | 沒保存／取消 `fetchReminders` 的 fetch id，過期查詢仍跑完整個讀取與排序才被世代編號丟掉。白做工，不影響正確性 | codex |
| 10 | 多處 | 取消入口可能消失但寫入照走（完整模式勾選第 2 筆後立刻收合、或該筆掉出前 6 筆）。**由 codex 的 HIGH／MEDIUM 降級**，理由見爭議項目 | codex |
| 11 | `AgendaStore.swift:256-270` | `reminderOrder` 處理 `due == nil` 的兩個分支已是死碼（`items(from:)` 已濾掉無到期日的），且其註解「沒有到期日的放後面」與 §4.4「不顯示」矛盾 | Claude |
| 12 | `RemindersSection.swift` / `CollapsedCardView.swift` | `.help("再點一次取消")` 在寫入已送出後仍這樣顯示，但那時點了不會有反應 | Claude |
| 13 | `WidgetView.swift:37-44` | `body` 縮排斷掉（`.frame` 之後的修飾子沒對齊） | Claude |
| 14 | `AgendaStore.swift:23` | 註解說「以下三個」，實際有五個 `nonisolated(unsafe)` 屬性 | Claude |

---

## ✅ 通過項目

- **紅線：只有一個寫入點** — 全檔搜尋確認只有 `commitCompletion` 的兩行；
  `setCalendarHidden` 等只寫 App 自己的 UserDefaults
- **零網路、零第三方依賴** — 皆無命中，`Package.swift` 無 `dependencies`
- **安全性** — URL 只由系統產生的 identifier 組成並做 percent-encoding，使用者可控的標題與備註
  完全沒有進入 URL；`AgendaStore` 沒有任何 log；`opacity` 有讀寫雙向夾限與型別檢查
- **併發** — `fetchReminders` 的背景 callback 先在原地轉值型別再切 MainActor、世代編號、
  `nonisolated static` 的隔離宣告都正確；observer 連同註冊的 center 一起記錄，`deinit` 完整收尾
- **Git 衛生** — 39 個追蹤檔案，無 `build/`、`.env`、log、`.DS_Store`；commit message 都說明 why

---

## ⚖️ 爭議項目

**codex 把「取消入口消失但寫入照走」判為 HIGH／MEDIUM，Orchestrator 降為 LOW。**

- codex：使用者失去取消機會、延遲寫入仍執行 → 高風險
- Claude：這裡**使用者自己點了圓圈**，寫入是他要求的行為；1.2 秒取消窗是便利性而非保證。
  收合或捲出視野只是拿掉 undo 入口，不是「未經同意的寫入」
- **最終採用 Claude 的判斷**。理由是與第 1 條有本質差異：第 1 條裡使用者做的是**與該筆提醒
  無關的操作**（隱藏清單），卻導致那筆被完成，那才是資料完整性問題。
  但 codex 指出的現象本身成立，故保留在 LOW。

**2026-09-21 使用者裁定：維持現狀，不修。**

這是產品手感判斷，最終決定權在使用者。記錄在此是為了讓之後的 review
（不論是人或 codex）不要再把它當成待修的 bug 重開——它是**知情後刻意保留**的行為，
不是遺漏。若未來要改，要連帶考慮「點完圓圈就切走」這個正常操作會失效。

---

## 結論與處置

**建議修改後再繼續開發。**

使用者裁定修 **1、2、4、6**，並指派 executor 實作、Orchestrator 驗證（角色與 M0–M8 相反：
M0–M8 是我寫、codex 驗；這次是 executor 寫、我驗）。

| # | 處置 |
|---|------|
| 1 | ✅ **已修**（改成單一漏斗，見下節） |
| 2 | ✅ 已修：移除兩處 `.id(revision)`，改用 `let _ = revision` 建立重繪依賴 |
| 4 | ✅ 已修：檔頭改為明示「含整個專案唯一的寫入點」並指向 PLAN §8；連同 #14 的過時數量 |
| 6 | ✅ 已修：`setCompletionError` 搭配 6 秒後自動清除的可取消 Task |
| 3、5 | ✅ **已修**（2026-09-21），見文末 |
| 7 | ✅ **已處理**：61 個單元測試，含 EventKit seam 與勾選路徑的完整覆蓋，全部用變異測試驗證過。見文末兩節 |
| 8、9、11、12、13 | ✅ **已修**（2026-09-21，由 codex 提出修補、Orchestrator 套用並驗證） |
| 10 | ✅ **使用者裁定維持現狀**（2026-09-21）。刻意不修，理由見下方爭議項目 |

---

## 修復過程：第 1 條實際上有五條路徑，前四次都是「逐個補」而失敗

這一條值得單獨記錄，因為它連續騙過了三輪驗證。

| 輪次 | 誰發現 | 漏掉的路徑 |
|------|--------|-----------|
| M4 | codex 審 M4 diff | 非同步成功回來後未取消 stale Task（當時只補了這條） |
| 本次 review | codex 冷啟動全專案審查 | `loadReminders` 兩個**同步**提前 return（權限不足、全部清單被隱藏） |
| 修復第一輪 | codex 複審我的修正 | 非同步**失敗**路徑（`guard let items else` 設 `.failed` 後 return） |
| 修復第一輪 | Orchestrator 自查 | `cutoff` 日期計算失敗的 `.failed` |

**教訓**：「在每個出口記得清理」這種要求，被證明四次都會漏。第二輪改成結構性防線——
新增 `setRemindersState(_:)` 漏斗，**所有**對 `remindersState` 的寫入都必須經過它，
由它依新狀態決定 prune 的可見集合（`.loaded` 保留清單內的 id；`.loading` /
`.needsPermission` / `.failed` 一律傳空集合）。

實測確認：`grep -n "remindersState = "` 只剩漏斗內部一行，五個出口全部走漏斗。
codex 第二輪複審回報「未發現問題」。

這也是「寫的人不驗收自己寫的東西」最有力的一次證據：我在第一輪的 prompt 裡**明確問了**
「還有沒有第四條路徑被漏掉」，codex 就找到了一條。


---

## 補測試（2026-09-18，針對第 7 條）

新增 `Tests/FloatingAgendaTests/` 與 49 個測試，`swift test` 約 0.02 秒跑完。

### 變異測試：證明這些測試不是裝飾品

「測試全綠」本身沒有意義，所以把四個曾經真實存在或可能退化的規則暫時破壞，確認測試會失敗：

| 變異 | 結果 |
|------|------|
| `isOverdue` 改回「只有日期也跟 `now` 比」（M2／M3 的真實 bug） | ✅ `testDateOnlyDueTodayIsNotOverdue` 失敗 |
| `inProgressEvent` 改成單純取第一筆 | ✅ `testTimedEventWinsOverAllDay` 失敗 |
| `clampOpacity` 移除 `isFinite` 守衛（M1 的真實 bug，NaN 穿透 `min`/`max`） | ✅ `testOpacityRejectsNonFiniteValues` 失敗 |
| `eventOrder` 移除「同日整天優先」那一行 | ✅ `testAllDayRuleIsActuallyExercised` 失敗 |

每個變異都只被**對應的那一個**測試抓到，還原後 49/0。

### codex 審查測試本身，抓到 4 條（含一個「測了卻測不到」）

把測試 diff 交給 codex 冷啟動審查，回報 4 條 LOW，全部查證成立並修正：

| 發現 | 處理 |
|------|------|
| **整天優先的測試不具鑑別力**——那個整天行程的 `start` 是 00:00，剛好也比定時行程早，所以就算把規則整個拿掉、退回純比 `start`，測試照樣通過 | 新增 `testAllDayRuleIsActuallyExercised`：兩者 `start` 相同、標題順序與期望結果相反，規則在→true、規則沒了→落到標題比較→false。上表第 4 個變異就是驗證它 |
| `eventTimeLabel` 的「進行中」邊界沒被測（它與 `inProgressEvent` 是兩份獨立實作） | 補三個測試：`start == now`、`end == now`、已結束 |
| `AppSettings.opacity` 的 **setter** 沒被測，儲存鍵寫錯或寫入不夾限都不會被發現 | 補 `testOpacitySetterClampsAndPersistsUnderExpectedKey`，同時斷言鍵名 |
| `InMemorySettingsStore.bool` 只用 `as? Bool`，與 `UserDefaults` 對數字／布林字串的轉換語意不一致 | 改為對齊：Bool 直接用、`NSNumber` 取 `boolValue`、字串照 `YES`／`true`／`1` 判定 |

第一條最值得記錄：**我寫的測試通過了，但它證明不了任何事**。這是「測試覆蓋率」與
「測試有效性」的差別，而且只有讓另一個獨立的審查者去看測試本身才會被抓出來。

### 兩個為可測性而做的 production 改動

1. `AgendaStore.eventOrder` / `reminderOrder`：`private` → `internal`。純函式無副作用。
2. `AppSettings` 抽出 `SettingsStore` protocol（`UserDefaults` 原本就有全部方法，擴充是空的）。
   **這不是為了漂亮**：第一版測試用 `UserDefaults(suiteName:)`，結果在
   `~/Library/Preferences` 留下 8 個 plist，而且 `removePersistentDomain` 清不掉——
   行程結束時 cfprefsd 會把它們寫回去。改用記憶體實作後測試完全不碰檔案系統。
   （那 8 個殘留已手動清除，並確認連跑兩次測試都不再產生。）

### 尚未覆蓋（目前最重要的缺口）

`pendingCompletion` 的清理漏斗與 `commitCompletion` 的取消邏輯——也就是本次 review
最嚴重那條 bug 所在的地方，而且那條 bug 連續騙過了四輪驗證。

測它需要實例化 `AgendaStore`（會建立 `EKEventStore`、可能在測試行程觸發 TCC 授權），
而 PLAN §8 禁止在開發與驗證過程中寫入使用者資料。要測它得先為 EventKit 做一層 seam
（把 `calendarItem(withIdentifier:)` 與 `save(_:commit:)` 抽成 protocol），
那是獨立的設計改動，不適合夾在「補測試」裡順手做。

**已於同日完成，見下節。**


---

## EventKit seam 與勾選路徑測試（2026-09-18）

補完上一節指出的缺口。測試從 49 增加到 61。

### seam 設計

原本 `commitCompletion` 直接呼叫 `store.calendarItem(withIdentifier:)`、
`reminder.isCompleted = true`、`store.save(_:commit:)`。現在抽成：

```
ReminderWriter（protocol，只有一個 markCompleted(id:) throws）
├── EventKitReminderWriter   production。整個專案唯一碰寫入 API 的型別，5 行、零判斷
└── SpyReminderWriter        測試。只記錄被要求標記的 id，可設定拋出錯誤
```

`AgendaStore` 只保留「**要不要寫、什麼時候寫**」的判斷——那才是出過四次漏洞、需要測試保護的部分。
緩衝時間也改成可注入（預設仍是 1.2 秒，測試用 60ms），測試才不必每個案例都等 1.2 秒。

紅線稽核的結果也變好了：`grep -rn "isCompleted\|store.save("` 現在只命中
`ReminderWriter.swift` 那兩行，寫入面積從「一個 400 行的檔案」收斂到「一個 5 行的型別」。

### 12 個勾選路徑測試

基本時序 5 個：緩衝期內不寫入、期滿才寫入且只寫一次、期內再點完全取消、
寫入送出後再點不假裝取消、兩筆提醒互不影響。

`setRemindersState` 漏斗 5 個（**這就是騙過四輪驗證的地方**）：權限被撤、清單全隱藏、
讀取失敗、該筆離開今天範圍——四種情況都必須不寫入；外加一個反面案例：
仍然看得到的 pending **不可以**被誤清，否則使用者點了卻不會完成。

寫入失敗 2 個：失敗要顯示原因且不卡在勾選中、單筆失敗不得讓整個清單消失。

### 變異測試：六個變異

| 變異（把歷史 bug 改回去） | 結果 |
|---|---|
| 漏斗只在 `.loaded` 時 prune（＝「逐個出口補」的漏洞形態） | ✅ 4 個測試失敗 |
| 取消分支不檢查 Task 是否還存活（假裝取消成功） | ✅ `testTapAfterWriteDoesNotFakeCancellation` 失敗 |
| 單筆失敗把整個 `remindersState` 設成 `.failed`（M4 的 bug） | ✅ 2 個測試失敗 |
| 把 `init` 的預設緩衝時間改成 0 | ✅ `testDefaultBufferMatchesSpec` 失敗（**這條測試是被這個變異逼出來的**——原本所有測試都傳入明確的 delay，改預設值不會被察覺，所以把 1.2 秒抽成具名常數並加測試鎖住） |
| 移除 `commitCompletion` 的 `guard pendingCompletion.contains(id)` | ❌ 沒有測試失敗 |
| 漏斗只清標記、不取消 Task | ❌ 沒有測試失敗 |

最後兩條要一起讀才有意義：**這兩層是真正互為備援的**。
拿掉任何一層，行為都仍然正確（所以測試不該失敗）；只有兩層同時失效才會誤寫使用者資料。
這是縱深防禦的正常結果，不是測試薄弱——單獨拿掉一個冗餘守衛而行為不變，
本來就不該有測試失敗。變異 F（漏斗不取消 Task）能確認第二層 guard **不是死碼**。

### 為可測性放寬的第三處可見性，以及一個順帶修掉的警告

`setRemindersState` 從 `private` 放寬為 `internal`。它是整個專案最安全關鍵的一條不變式
（「使用者看不到的提醒不准被寫入」），值得被單元測試直接驗證而不是只能間接推論。

另外 `defaultCompletionDelay` 必須標 `nonisolated`：它被用作 `init` 的預設引數，
而預設引數在 nonisolated 情境求值，不標的話 Swift 6 語言模式會直接變成錯誤。
這與 M1 的 `AppSettings.shared` 預設引數是同一個坑。

### codex 審查測試本身，抓到 3 條

| 發現 | 處理 |
|------|------|
| 用固定 `sleep 200ms` 判定 60ms 的 Task 已完成，機器忙碌時會偶發失敗 | 改成輪詢到期限的 `waitUntil`；負面測試（斷言「沒寫入」）改用 **sentinel** ——在狀態變更後再排一筆，等它真的被寫入才證明緩衝期已過，這時斷言「那一筆沒被寫」才有意義。連跑三次皆 63/0，耗時也從 2.35s 降到 1.16s |
| `testTapDoesNotWriteImmediately` 是同步斷言，delay 改成 0 也會通過 → 沒有驗證緩衝期存在 | 新增 `testBufferActuallyDelaysTheWrite`（400ms 緩衝、60ms 時檢查）。後續變異測試又發現這樣仍鎖不住**預設值**，因此再加 `testDefaultBufferMatchesSpec` |
| 「找不到提醒」的測試只斷言 `completionError != nil`，沒比對文案 | 補上完整文案斷言。**這條抓到我一個沒察覺的行為變更**：seam 重構把 notFound 從固定字串改成走通用 catch，訊息因此多了「勾選失敗：」前綴。判斷保留（更清楚說明是什麼動作失敗），並用測試把它固定下來 |


---

## 修復第 3、5 條（2026-09-21）

### 5. `eventIdentifier` 為 nil 時的不穩定 id

`EventItem.eventIdentifier` 改成 `String?`。缺值時用「行事曆 ID ＋ 標題 ＋ 起訖時間」組出
**在重讀之間穩定**的 key，不再用 `UUID()`。`openInCalendar` 在 nil 時直接開 Calendar.app，
不送假的 identifier。新增 `EventItemTests`（5 個），並用變異測試驗證——
把 fallback 改回 `UUID()` 會讓 `testIDIsStableAcrossReloadsWhenIdentifierIsMissing` 失敗。

**刻意不修的殘留限制**：行事曆、標題、起訖時間**完全相同**的兩筆仍會撞號
（例如同名聯絡人同一天生日）。codex 第二輪指出這點，Orchestrator **駁回**：
要再區分只剩「在陣列中的位置」可用，而陣列順序在重讀之間不保證穩定，
那會讓 id 又變回不穩定——正是這次要修掉的問題，等於用更糟的 bug 換掉較輕的。
而且這兩筆在畫面上每個欄位都一樣，合成一列不會誤導使用者。取捨已寫進程式碼註解。

### 3. 位置檢查只看左上角一個點

- `isUsable` 改成檢查整張卡片與螢幕可視範圍的交集（寬度一半以上、高度 40 以上）
- 新增 `constrained(_:)` 把 frame 夾回螢幕；卡片比螢幕高時貼齊上緣
- `setContentHeight` 在伸縮後套用夾限
- `recoverIfOffscreen` 改成「還看得到就只夾回來、完全看不到才回預設位置」

**實測**：存 y=200、收合 130pt → 卡片被夾到上緣 216（= 可視下緣 86 + 130），
存的設定維持 200 不變（那是使用者拖曳的真實意圖，夾限只是顯示時的調整）。

**途中修掉一個自己引入的副作用**：`applyTopLeft` 原本也做垂直夾限，但還原位置時高度
還是 `PanelMetrics.initialHeight` 的佔位值（200），依它夾限會把卡片推到錯處
（實測存 y=200 變成 286）。改成還原時只夾水平，垂直交給 `setContentHeight` 在真實高度出來後處理。

**codex 指出的螢幕選擇問題**：原本用「交集面積最大」選螢幕，上下排列的雙螢幕上，
卡片變高會讓下方螢幕的交集變大，於是原本完整在上方螢幕的卡片會整個跳到下面。
改用**左上角**（高度伸縮時保持不動的錨點）選螢幕，左上角不在任何螢幕上時才退回看交集。
使用者的螢幕是左右排列碰不到這情況，但邏輯本身錯了。

### 同時診斷出（尚未修）：`start()` 把所有東西排在權限請求後面

修復過程中反覆遇到「重建後第一次啟動卡在『載入中』數分鐘」，這次把根因查清楚了：

```swift
func start() async {
    await requestAccessIfNeeded()   // ← 卡在這裡
    refresh()                       // 資料
    observeChanges()                // 變更監聽
    startPeriodicRefresh()          // 60 秒重讀
}
```

ad-hoc 簽章每次重建都讓 cdhash 改變 → TCC 視為新 App → `authorizationStatus` 回
`.notDetermined` → `requestFullAccessToEvents()` 等 TCC 重新評估。實測那個 await
**要 30 秒到 4 分鐘以上**才回來，期間畫面上也沒有授權對話框。

在那段期間：**沒有資料、沒有 observer、連 60 秒計時器都還沒建立**，沒有任何機制能重試。
卡片只能顯示「載入中…」。這也解釋了為什麼 M7 加的「缺權限每 3 秒重試」救不了——
那個輪詢是在 `refresh()` 裡排的，而 `refresh()` 還沒執行。

本次工作期間重現四次，行為一致：重建後首次啟動必中，同一 binary 且授權已建立時則是數秒內完成。

**建議修法**（五行）：把順序倒過來——先 `observeChanges()`、`startPeriodicRefresh()`、
`refresh()`（此時會顯示「需要 X 存取權限」＋按鈕，比空白的「載入中」清楚得多，
3 秒輪詢也會開始跑），最後才 `await requestAccessIfNeeded()`，回來再 `refresh()` 一次。


---

## 修復 8、9、11、12、13 ＋ `start()`（2026-09-21）

使用者指派：`start()` 由 Orchestrator 修，其餘交 codex。

**執行方式的調整**：`cli-delegate` 鐵律是 codex 一律 `-s read-only`、不放寬權限，
所以 codex 產出具體修補，Orchestrator 逐條審查後套用並驗證。既照指派，也不破壞安全邊界。

### `start()`：把重試機制排到權限請求之前

```swift
// 修改前                          修改後
await requestAccessIfNeeded()      observeChanges()
refresh()                          startPeriodicRefresh()
observeChanges()                   refresh()
startPeriodicRefresh()             await requestAccessIfNeeded()
                                   refresh()
```

ad-hoc 簽章每次重建都讓 cdhash 改變 → TCC 視為新 App 重新評估 →
`requestFullAccessToEvents()` 這個 await 實測要 30 秒到 4 分鐘以上才回來，
期間畫面上也不一定有授權對話框。舊版把所有東西排在它後面，那幾分鐘內
**連重試的機器都還沒造出來**（M7 的 3 秒輪詢也救不了，它是在 `refresh()` 裡排的）。

**實測前後對照（同為重建後首次啟動）**：

| | 舊版 | 新版 |
|---|---|---|
| t=0.5s | 空白卡片「載入中…」102pt | 權限提示 **186pt**，含「打開系統設定」按鈕 |
| 之後 | 毫無變化、無重試機制 | 3 秒輪詢持續重試，權限到手自動補資料 |

186pt 與 M6 產出的權限畫面 snapshot（`m6b-permission-light`，372÷2）完全一致，
可確定卡片顯示的就是那個狀態。

**誠實揭露**：這次重建後觀察 4 分鐘，TCC 始終沒有授權、卡片停在權限提示。
那是 PLAN §9 的 ad-hoc 簽章風險本身，不是這次修改能解決的——
但使用者現在**看得到發生什麼事、也有按鈕可以按**，而不是對著空白卡片乾等。

### 五條 LOW

| # | 修法 | 備註 |
|---|------|------|
| 8 | `eventOrder` 拿掉開始日期比較，整天一律優先 | 那是「顯示 7 天」時代的遺留。連帶把原本**鎖住舊行為**的測試改成驗證新規格，並用變異測試確認移除整天優先會被**兩個**測試抓到 |
| 9 | 保存 `fetchReminders` 的 identifier，發新查詢前 `cancelFetchRequest` | 世代檢查保留——取消不保證 callback 不會來。identifier 只由當代 callback 清除，避免誤清較新查詢的 |
| 11 | 保留 nil 排序分支，修正註解 | codex 的理由我採納：`ReminderItem.due` 型別上仍是 Optional，刪掉分支卻不收緊型別反而要另訂 nil 政策。註解改成明確標示「這是防禦性契約，不代表允許顯示無到期日的提醒」 |
| 12 | `.help` 改成「已勾選（僅緩衝期間可再點一次取消）」 | 寫入送出後再點不會有反應，舊文案在那個階段是錯的。同時修正三處把 pending 等同於緩衝期的註解 |
| 13 | `WidgetView.body` 的 modifier chain 對齊 | 純格式 |

### 第 10 條未處理

爭議項目（codex 判 HIGH、Orchestrator 降為 LOW）。「修」它等於改成「看不到就不寫」，
會讓「點完圓圈就切走」這個正常操作失效。屬產品手感判斷，已交使用者裁決。
