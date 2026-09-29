import Foundation

/// `AppSettings` 需要的 UserDefaults 子集。
///
/// 抽成 protocol 的唯一理由是**讓測試能用記憶體實作**：`UserDefaults(suiteName:)`
/// 會在 `~/Library/Preferences` 產生實體 plist，而且行程結束時 cfprefsd 會重新 flush
/// 回去，`removePersistentDomain` 清不掉，等於每跑一次測試就在使用者系統留一個檔案。
/// `UserDefaults` 本身已經有全部這些方法，所以擴充是空的。
protocol SettingsStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
    func register(defaults registrationDictionary: [String: Any])
    func bool(forKey defaultName: String) -> Bool
    func stringArray(forKey defaultName: String) -> [String]?
}

extension UserDefaults: SettingsStore {}

/// 三種顯示模式（M9 計畫 §4.1）。舊版只有「展開／收合」兩態，遷移規則見 `AppSettings`
enum DisplayMode: String, CaseIterable {
    case full, collapsed, character

    var label: String {
        switch self {
        case .full: "完整"
        case .collapsed: "收合"
        case .character: "角色"
        }
    }
}

/// UserDefaults 包裝（PLAN §5.5）。
/// 存的是「被隱藏的」ID，之後新增的行事曆才會預設顯示。
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    static let opacityRange: ClosedRange<Double> = 0.3...1.0

    private enum Key {
        static let panelVisible = "panelVisible"
        static let panelCollapsed = "panelCollapsed"
        static let opacity = "opacity"
        static let hiddenCalendarIDs = "hiddenCalendarIDs"
        static let hiddenReminderListIDs = "hiddenReminderListIDs"
        static let panelTopLeftX = "panelTopLeftX"
        static let panelTopLeftY = "panelTopLeftY"
        static let displayMode = "displayMode"
        static let characterTopRightX = "characterTopRightX"
        static let characterTopRightY = "characterTopRightY"
        static let characterBottomRightX = "characterBottomRightX"
        static let characterBottomRightY = "characterBottomRightY"
        static let showBubble = "showBubble"
        static let characterSkinID = "characterSkinID"
        static let showProjectTicker = "showProjectTicker"
    }

    private let defaults: any SettingsStore

    init(defaults: any SettingsStore = UserDefaults.standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.panelVisible: true,
            Key.opacity: 1.0,
            Key.showBubble: true,
            Key.showProjectTicker: true,
        ])
        Self.migrateDisplayMode(in: defaults)
    }

    /// 舊版只有 `panelCollapsed` 兩態。第一次跑到有 `displayMode` 的版本時做一次轉換。
    ///
    /// **不用 `register(defaults:)`**：那只提供讀取時的後備值，不會真的寫進去，
    /// 舊的 `panelCollapsed = true` 就會被無聲忽略、使用者的收合狀態憑空消失。
    ///
    /// `panelCollapsed` 刻意**保留不刪**，這樣使用者退回舊版還是能用。
    /// 但新程式碼一律只讀寫 `displayMode`（計畫 §5.5），所以兩者之後會各走各的——
    /// 退回舊版拿到的是「遷移當下」的收合狀態，不是最新的
    private static func migrateDisplayMode(in defaults: any SettingsStore) {
        guard defaults.object(forKey: Key.displayMode) == nil else { return }
        let migrated: DisplayMode = defaults.bool(forKey: Key.panelCollapsed) ? .collapsed : .full
        defaults.set(migrated.rawValue, forKey: Key.displayMode)
    }

    var panelVisible: Bool {
        get { defaults.bool(forKey: Key.panelVisible) }
        set { defaults.set(newValue, forKey: Key.panelVisible) }
    }

    /// 收合模式（PLAN §4.10）。預設展開
    var panelCollapsed: Bool {
        get { defaults.bool(forKey: Key.panelCollapsed) }
        set { defaults.set(newValue, forKey: Key.panelCollapsed) }
    }

    var opacity: Double {
        get {
            // 只有「真的存了數字」才夾限。缺值或型別不對（例如被寫成字串）
            // 一律回預設全不透明，不要把 double(forKey:) 的 0.0 誤當成使用者選的透明度
            guard let stored = defaults.object(forKey: Key.opacity) as? NSNumber else {
                return Self.opacityRange.upperBound
            }
            return Self.clampOpacity(stored.doubleValue)
        }
        set { defaults.set(Self.clampOpacity(newValue), forKey: Key.opacity) }
    }

    var hiddenCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.hiddenCalendarIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.hiddenCalendarIDs) }
    }

    var hiddenReminderListIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.hiddenReminderListIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.hiddenReminderListIDs) }
    }

    /// 顯示模式。讀到不認得的值（例如使用者用 `defaults write` 塞了錯字）一律回 `.full`
    var displayMode: DisplayMode {
        get {
            guard let raw = defaults.object(forKey: Key.displayMode) as? String,
                  let mode = DisplayMode(rawValue: raw) else { return .full }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.displayMode) }
    }

    /// 完整模式的卡片要不要顯示專案輪播（使用者 2026-09-29 要求）。
    ///
    /// 預設開：沒有 `~/.agent-sessions` 的人本來就看不到那一塊
    ///（`ProjectsSection` 沒有內容時整塊不存在），不需要再多一道開關才看得到
    var showProjectTicker: Bool {
        get { defaults.bool(forKey: Key.showProjectTicker) }
        set { defaults.set(newValue, forKey: Key.showProjectTicker) }
    }

    /// 角色模式要不要顯示對話泡泡（M9 計畫 §4.4）。關掉只剩小精靈，心情照樣會變
    var showBubble: Bool {
        get { defaults.bool(forKey: Key.showBubble) }
        set { defaults.set(newValue, forKey: Key.showBubble) }
    }

    /// 使用者選的皮膚（M9 計畫 §4.6）。
    /// 啟動時找不到那個皮膚就退回內建角色——這個退回由 `PanelController` 處理，
    /// 設定本身只忠實保存使用者選過什麼，不要幫他改掉
    var characterSkinID: String {
        get { (defaults.object(forKey: Key.characterSkinID) as? String) ?? BuiltinCharacter.id }
        set { defaults.set(newValue, forKey: Key.characterSkinID) }
    }

    /// 角色模式的面板**右下角**（2026-09-23 起）。
    ///
    /// 泡泡在小精靈左邊、底部對齊小精靈中線，所以小精靈的右下角就是面板的右下角——
    /// 錨在這裡小精靈才會釘在定點，不會隨泡泡換行而上下跑。
    /// 舊的 `characterTopRight` 保留不刪，第一次啟動新版時由 `PanelController` 換算過來
    var characterBottomRight: CGPoint? {
        get {
            guard let x = defaults.object(forKey: Key.characterBottomRightX) as? Double,
                  let y = defaults.object(forKey: Key.characterBottomRightY) as? Double else {
                return nil
            }
            return CGPoint(x: x, y: y)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.characterBottomRightX)
                defaults.removeObject(forKey: Key.characterBottomRightY)
                return
            }
            defaults.set(Double(newValue.x), forKey: Key.characterBottomRightX)
            defaults.set(Double(newValue.y), forKey: Key.characterBottomRightY)
        }
    }

    /// 角色模式的面板右上角（**舊版遺留**，2026-09-23 起改存右下角）。
    ///
    /// 與 `panelTopLeft` 分開存（計畫 §5.5）：角色模式的面板寬高都會隨內容變，
    /// 靠右上角定位泡泡往左長、卡片往左下長，小精靈才不會跳。
    /// 兩個座標缺一即視為沒有記錄。
    var characterTopRight: CGPoint? {
        get {
            guard let x = defaults.object(forKey: Key.characterTopRightX) as? Double,
                  let y = defaults.object(forKey: Key.characterTopRightY) as? Double else {
                return nil
            }
            return CGPoint(x: x, y: y)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.characterTopRightX)
                defaults.removeObject(forKey: Key.characterTopRightY)
                return
            }
            defaults.set(Double(newValue.x), forKey: Key.characterTopRightX)
            defaults.set(Double(newValue.y), forKey: Key.characterTopRightY)
        }
    }

    /// 面板左上角。兩個座標缺一即視為沒有記錄（回預設位置）。
    var panelTopLeft: CGPoint? {
        get {
            guard let x = defaults.object(forKey: Key.panelTopLeftX) as? Double,
                  let y = defaults.object(forKey: Key.panelTopLeftY) as? Double else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.panelTopLeftX)
                defaults.removeObject(forKey: Key.panelTopLeftY)
                return
            }
            defaults.set(Double(newValue.x), forKey: Key.panelTopLeftX)
            defaults.set(Double(newValue.y), forKey: Key.panelTopLeftY)
        }
    }

    /// 讀寫都夾限，外部（含 defaults write）塞進超範圍的值也不會讓面板看不見。
    /// NaN 一定要先擋掉——`min`/`max` 對 NaN 的比較全是 false，會讓 NaN 原封不動穿過去。
    static func clampOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return opacityRange.upperBound }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }
}
