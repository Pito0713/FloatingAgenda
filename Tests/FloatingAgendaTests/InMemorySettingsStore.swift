import Foundation
@testable import FloatingAgenda

/// 純記憶體的 `SettingsStore`，測試專用。
///
/// 存在的理由：`UserDefaults(suiteName:)` 會在 `~/Library/Preferences` 留下實體 plist，
/// 而且行程結束時會被重新寫回去、`removePersistentDomain` 清不掉。
/// 用這個實作，測試完全不觸碰檔案系統，也絕不可能動到使用者真實的 App 設定。
///
/// 語意刻意對齊 `UserDefaults`：`register(defaults:)` 是 fallback 層，
/// 明確寫入的值優先，兩層都沒有時 `bool(forKey:)` 回 `false`。
final class InMemorySettingsStore: SettingsStore {
    private var storage: [String: Any] = [:]
    private var registered: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName] ?? registered[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        if let value {
            storage[defaultName] = value
        } else {
            storage.removeValue(forKey: defaultName)
        }
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }

    func register(defaults registrationDictionary: [String: Any]) {
        registered.merge(registrationDictionary) { _, new in new }
    }

    /// 對齊 `UserDefaults.bool(forKey:)` 的轉換語意：Bool 直接用、數字取 `boolValue`、
    /// 字串照 `"YES"`／`"true"`／`"1"` 判定。不做這層轉換的話，
    /// 測試替身在儲存型別不是 Bool 時會與 production 行為分歧。
    func bool(forKey defaultName: String) -> Bool {
        switch object(forKey: defaultName) {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return ["yes", "true", "1"].contains(value.lowercased())
        default:
            return false
        }
    }

    func stringArray(forKey defaultName: String) -> [String]? {
        object(forKey: defaultName) as? [String]
    }
}
