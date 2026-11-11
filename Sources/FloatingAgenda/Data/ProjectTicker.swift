import Foundation

/// 專案區要顯示的內容（`ProjectsSection`）。
///
/// 名字沿用 2026-09-29 的「專案輪播」；2026-11-10 改成所有專案一次攤開之後，
/// 輪播游標與計時器都拿掉了，剩下「顯示哪些」與「沒東西時說什麼」兩條規則。
///
/// **純函式**：不碰檔案系統、不碰全域狀態。
enum ProjectTicker {

    /// 要顯示哪些專案。
    ///
    /// 順序沿用 `ProjectStore.order`（有卡住的點 → 🔴 → 🟡 → 🟢），這裡不再排一次；
    /// **不設數量上限**——展開的卡片是看詳情的地方，放不下由整張卡捲動。
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
}
