import SwiftUI

/// SwiftUI App 本體。入口在 `Entry.swift`，所以這裡不標 `@main`。
struct FloatingAgendaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let store = AgendaStore.shared

    var body: some Scene {
        MenuBarExtra("懸浮行程", systemImage: "calendar") {
            MenuBarView(calendars: store.calendars,
                        reminderLists: store.reminderLists,
                        delegate: appDelegate)
        }
        .menuBarExtraStyle(.window)
    }
}
