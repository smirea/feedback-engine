import Feedback
import SwiftUI

@main
struct TodoDemoApp: App {
    @State private var store: TodoStore

    init() {
        let store = TodoStore.sample()
        _store = State(initialValue: store)
        Feedback.enable()
        Feedback.context("TodoStore") { store }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Lists", systemImage: "checklist") {
                NavigationStack { ListsScreen() }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsScreen() }
            }
        }
    }
}
