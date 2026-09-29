import Foundation

/// 完整模式卡片下方那一塊專案輪播的內容（使用者 2026-09-29 要求）。
///
/// 一次顯示**一個專案**——就是角色模式展開後專案區裡的那張卡（`ProjectCardView`），
/// 只是完整模式一次只放得下一張，所以改成輪播。
///
/// **純函式**：不碰檔案系統、不碰全域狀態，也不管什麼時候換下一個。
enum ProjectTicker {

    /// 每個專案顯示幾秒。比泡泡的 10 秒短：泡泡要念一整句，這裡是掃一眼進度
    static let interval: TimeInterval = 8

    /// 要輪播哪些專案。
    ///
    /// 順序沿用 `ProjectStore.order`（有卡住的點 → 🔴 → 🟡 → 🟢），這裡不再排一次；
    /// 也**不設數量上限**——`ProjectsSection` 一次攤開所有卡片所以要限 4 個，
    /// 輪播一次只顯示一個，多幾個專案只是多輪幾圈。
    static func entries(projects: SectionState<ProjectItem>) -> [ProjectItem] {
        guard case .loaded(let items, _) = projects else { return [] }
        return items
    }

    /// 沒有卡可以顯示時要說的那一句話；`nil` 代表「有卡片，不必說話」。
    ///
    /// 抽成純函式是為了讓文案能被測試釘住——這幾句是使用者唯一會看到的
    /// 「讀不到資料」線索，寫在 View 裡就只剩渲染才驗得到
    static func statusNote(for projects: SectionState<ProjectItem>) -> String? {
        switch projects {
        case .loading:
            "讀取中…"
        case .needsPermission:
            // 讀檔不需要 TCC 權限，這個分支理論上到不了，列出來只為了窮盡所有狀態
            "需要存取權限"
        case .failed(let message):
            message
        case .loaded(let items, _):
            items.isEmpty ? "還沒有任何交接紀錄" : nil
        }
    }

    /// 輪播游標。
    ///
    /// **只記「現在顯示的是哪一個的 id」，不記清單本身**——這一點與泡泡的
    /// `BubbleRotation` 不同，是刻意的：
    ///
    /// 1. 資料更新時不需要另外寫「不要打斷正在顯示的那一個」的合併邏輯，
    ///    id 還在就還在，不在就自然退回第一個。
    /// 2. 沒有需要在 `onAppear` 灌初值的狀態。`ImageRenderer`（`--snapshot`）
    ///    不保證跑 `onAppear`，靠它初始化的話 snapshot 會渲染出一塊空白。
    struct Cursor: Equatable {
        /// nil ＝ 還沒換過，顯示第一個
        var showingID: String?

        init(showingID: String? = nil) {
            self.showingID = showingID
        }

        /// 正在顯示的那一個。找不到（例如那個專案的交接紀錄被刪了）就退回第一個
        func current(in entries: [ProjectItem]) -> ProjectItem? {
            guard let showingID,
                  let match = entries.first(where: { $0.id == showingID }) else {
                return entries.first
            }
            return match
        }

        /// 目前是第幾個（從 1 開始，給標題列顯示用）。空清單回 0
        func position(in entries: [ProjectItem]) -> Int {
            guard let current = current(in: entries),
                  let index = entries.firstIndex(of: current) else { return 0 }
            return index + 1
        }

        /// 時間到，換下一個；輪完一圈從頭開始
        mutating func advance(in entries: [ProjectItem]) {
            guard !entries.isEmpty else {
                showingID = nil
                return
            }
            let index = current(in: entries).flatMap { entries.firstIndex(of: $0) } ?? 0
            showingID = entries[(index + 1) % entries.count].id
        }
    }
}
