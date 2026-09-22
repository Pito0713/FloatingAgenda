# FloatingAgenda 驗證計畫（Tech Lead Mode）

> 建立：2026-09-16｜Orchestrator：Claude Opus 5｜Reviewer：codex-cli 0.154.0（gpt 系，異模型）
> 制度依據：`~/Agent_skill/skills/tech-lead-mode`、`~/Agent_skill/skills/cli-delegate` 模式 C
> 需求正本：`PLAN.md`（不得為了讓驗證通過而刪減規格，§8）

---

## 0. 角色分工（不可混淆）

| 角色 | 由誰擔任 | 負責 | 不負責 |
|------|---------|------|--------|
| Orchestrator | Claude（本 session） | 切里程碑工單、定驗收條件、寫實作、仲裁 codex 發現、跑 Close Gate | 決定風險可不可接受 |
| Reviewer | `codex exec -s read-only`（異模型） | 挑 diff 的邏輯漏洞／邊界條件／安全風險／是否偏離驗收條件 | 決定要不要修、直接改 code |
| 客觀裁判 | 編譯器、`plutil`、`pgrep`、`grep`、`--dump`、`--snapshot` | 提供不可辯駁的證據 | — |
| 人類終審 | 使用者 | ESCALATE 裁決、§7.2 手動驗收（含所有寫入行為） | 盯每一行 diff |

**鐵律**：寫的人不驗收自己寫的東西 → 每個里程碑的 diff 一律過 codex，Orchestrator 不得以「我檢查過了」代替。

---

## 1. 每個里程碑的四道關卡（缺一不 commit）

```
Gate 1 機器驗證  → Gate 2 codex 對抗式審查 → Gate 3 Orchestrator 仲裁 → Gate 4 Close Gate → commit
                                                      ↑ CONFIRMED 有缺口就回 Gate 1 重跑（窄修）
```

### Gate 1：機器驗證（客觀證據，一律貼實際輸出）

全里程碑共通：

```bash
rm -rf .build build && bash scripts/build.sh      # 必須 exit 0
plutil -lint Resources/Info.plist                  # 必須 OK
grep -rnE "URLSession|http://|https://" Sources/    # 必須無結果（零網路）
git status --short                                  # 確認沒有動到禁區
```

各里程碑額外項目見 §2 對照表。**不接受「應該會過」，只接受貼出來的實際輸出。**

### Gate 2：codex 對抗式審查（每個里程碑強制）

```bash
git diff HEAD | codex exec -s read-only -c project_doc_max_bytes=0 "審查 <stdin> 的 diff，僅回報問題，不提供修改方案。

審查維度：邏輯漏洞、邊界條件缺失、安全風險、是否偏離下方驗收條件

驗收條件：<貼入本里程碑的驗收條件>
專案禁區：不得有網路呼叫、不得有第三方套件、不得寫入使用者的行事曆或提醒資料

每個問題格式：
[嚴重度] 位置：描述 → 潛在影響
嚴重度：CRITICAL / HIGH / MEDIUM / LOW
無問題時輸出：「未發現問題」
繁體中文。"
```

- 首個 commit 前（M0）沒有 HEAD，改用 `git diff --no-index /dev/null <檔案>` 或 `git add -A && git diff --cached`
- Bash timeout 設 570000 ms；不用 `timeout` 包裝（macOS 沒有該指令）
- codex 不可用時，**不得跳過**，改走冷啟動 Claude subagent fallback 並在回報標示獨立性較低

### Gate 3：Orchestrator 仲裁（逐條查證，不照單全收）

對 codex 每一條發現，必須讀實際程式碼後三選一：

```
[CONFIRMED] <描述> → 已加入 Close Gate 待處理
[REJECTED]  <描述> → 原因：<一句話，須指出實際程式碼為什麼不成立>
[ESCALATE]  <描述> → 需要使用者判斷：<問題>
```

已知偏誤：codex 對測試檔與 UI 樣式的假陽性偏高；對併發、生命週期、權限流程的發現命中率較高。

### Gate 4：Close Gate（讀 diff 本身，不讀完工報告）

```
[ ] git diff --name-only 全部落在本里程碑宣告範圍內，禁區未被觸碰
[ ] 該里程碑驗收條件逐條有 diff 或輸出佐證
[ ] Gate 3 的 CONFIRMED 全部已修，且修正本身重跑一次 Gate 1
[ ] 結果三選一：✅ CLOSE ／ 🔁 REOPEN（開窄工單只處理缺口）／ 🔴 ESCALATE
```

**禁止第四種結果**：「大致完成，剩下之後再說」。

### commit 規範

`feat(M<n>): <一句話>`，一個里程碑一個 commit，commit 前更新 README 版本紀錄表（M7 前 README 可只有該表）。

---

## 2. 里程碑 × 驗收證據對照表

| # | 里程碑 | Gate 1 額外證據 | codex 審查重點 |
|---|--------|----------------|---------------|
| M0 | 專案骨架 | `open build/FloatingAgenda.app` 後 5 秒 `pgrep -x FloatingAgenda` 有結果；`grep -c UsageDescription Resources/Info.plist` ≥ 4；`LSUIElement` 為 true | build.sh 正確性、Info.plist 欄位齊全、ad-hoc 簽章、有沒有多餘依賴 |
| M1 | 懸浮面板 | `--snapshot` 產出 light/dark PNG（假資料）；Orchestrator **實際打開圖片看過** | NSPanel 旗標（`hidesOnDeactivate`、`canBecomeKey`）、`acceptsFirstMouse`、高度同步時上緣不動的座標運算、位置記憶的螢幕範圍檢查 |
| M2 | 資料層 | `--dump` 輸出含 PLAN §2 的 3 個提醒清單與主要行事曆名稱 | EventKit callback 的背景 queue 切回 MainActor、權限狀態判定、debounce、計時器洩漏、**是否有任何寫入路徑** |
| M3 | 行程區 UI | snapshot 對照 §4.2／§4.3 逐項 | 分組邏輯、整天／進行中判定、上限 6 筆與「還有 N 個」、空狀態、重複行程的 id 組合 |
| M4 | 提醒區 UI | snapshot 含「勾選中」那一筆的樣子 | 1.2 秒延遲勾選的取消競態、Task 取消、過期判定、計數用全部而非畫面上的數量 |
| M5 | 選單列 | 用 `defaults write` 改隱藏 ID 後 `--dump` 的「是否隱藏」欄位跟著變 | 存「隱藏 ID」而非「顯示 ID」的語意、透明度 0.3–1.0 夾限、同名行事曆用 identifier 當 key |
| M6 | 權限與異常 | mock 的 needsPermission／failed 狀態能被 snapshot 畫出來 | 各授權狀態（含 writeOnly）的分支、深層連結字串、失敗不 crash |
| M7 | 打磨交付 | PLAN §7.1 七條全綠 | README 完整性、殘留 TODO、深淺色模式 |

---

## 3. 全程紅線（任一觸犯即停止並回報使用者）

1. **不得寫入使用者的行事曆／提醒資料**（新增、修改、勾選、刪除皆禁止）。勾選寫入路徑只寫 code，驗證交使用者（PLAN §7.2 第 8 點）。每個里程碑用 `grep -rn "save(\|remove(\|isCompleted = true" Sources/` 確認寫入點只存在於 M4 的勾選函式內。
2. **不得碰 `~/Floating` 以外的任何目錄**（含 `~/Agent_skill`、其他專案）。
3. **不得自行執行 `tccutil reset`**；需要時寫進回報請使用者決定。
4. **不得有網路呼叫或第三方套件**（`ical://`、`x-apple…` scheme 不算網路）。
5. 同一個問題重試兩輪失敗 → 停下，帶失敗軌跡升級或問使用者（全域鐵律 3）。
6. codex 一律 `-s read-only`，絕不使用 `--dangerously-bypass-approvals-and-sandbox`。

---

## 4. 驗證紀錄

每個里程碑的四道關卡結果附在 `docs/verification/M<n>.md`，主對話只回報結論與證據摘要。

> **commit 欄位的說明**：這些是開發當下逐里程碑提交的 hash。專案在公開前把開發歷史
> 壓成單一 initial commit（移除了散落在紀錄中的個人行事曆／提醒內容），因此這一欄的
> hash 在目前的 repo 裡查不到，僅作為「每個里程碑都有獨立提交」的歷史佐證保留。
> `docs/verification/M7.md` 的 git log 節錄同理。

| # | Gate 1 | Gate 2 codex | Gate 3 仲裁 | Gate 4 | commit |
|---|--------|--------------|------------|--------|--------|
| M0 | ✅ 10 項全通過 | 1×LOW | CONFIRMED 1／已修 | ✅ CLOSE | `1edec5c` |
| M1 | ✅ 建置＋幾何＋透明度＋snapshot 全通過 | 3×MEDIUM | CONFIRMED 3／已修 | ✅ CLOSE | `b868a7e` |
| M2 | ✅ dump／排序／紅線全通過（即時更新 3 路徑未驗） | 2×HIGH 1×MEDIUM | CONFIRMED 3／已修 | ✅ CLOSE | `cef634b` |
| M3 | ✅ snapshot 6 筆上限＋深層連結實測通過 | 未發現問題 | 自補查 3 點皆無問題 | ✅ CLOSE | `626318c` |
| M4 | ✅ snapshot 全項＋寫入點稽核＋深層連結 | 2×HIGH 2×MEDIUM 1×LOW | CONFIRMED 4／已修，ESCALATE 1 | ✅ CLOSE | `9ea10ef` |
| M5 | ✅ 篩選實測＋選單列 snapshot 逐項 | 1×MEDIUM 1×LOW | CONFIRMED 2／已修 | ✅ CLOSE | `3c2ab47` |
| M6 | ✅ 三個狀態變體＋深層連結實測 | 未發現問題 | 自查 4 點名風險皆通過 | ✅ CLOSE | `0569af7` |
| M8 | ✅ 兩變體 snapshot＋收合高度與位置實測 | 1×MEDIUM | CONFIRMED 1／已修，自行發現 2／已修 | ✅ CLOSE | `ec1f444` |
| M7 | ✅ §7.1 七條全通過 | 未發現問題 | 自查 5 點名風險通過，自行發現 1 項已修 | ✅ CLOSE | `a7fe814` |
