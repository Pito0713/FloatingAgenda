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
    }

    private let defaults: any SettingsStore

    init(defaults: any SettingsStore = UserDefaults.standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.panelVisible: true,
            Key.opacity: 1.0,
        ])
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
