import SwiftUI

/// SwiftUI App 本體。入口在 `Entry.swift`，所以這裡不標 `@main`。
struct FloatingAgendaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let store = AgendaStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(calendars: store.calendars,
                        reminderLists: store.reminderLists,
                        delegate: appDelegate)
        } label: {
            MenuBarIconLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// 選單列上的圖示。
///
/// 拆成獨立的 `View` 而不是把 `Image` 直接寫在 `MenuBarExtra` 的 label 裡，
/// 是為了讓 `@Observable` 的追蹤有一個 body 可以掛：心情變了圖示才會跟著換。
///
/// 心情用 `Mood.decide` 算，跟面板上那隻小精靈同一個來源（見 `PanelRootView.mood`）。
private struct MenuBarIconLabel: View {
    private let store = AgendaStore.shared
    private let projects = ProjectStore.shared

    var body: some View {
        let mood = Mood.decide(reminders: store.remindersState,
                               projects: projects.state,
                               now: Date())
        Image(nsImage: MenuBarIcon.image(mood: mood))
            .accessibilityLabel("懸浮行程")
    }
}
