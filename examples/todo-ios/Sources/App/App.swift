import Feetback
import SwiftUI

@main
struct TodoDemoApp: App {
    @State private var store: TodoStore

    init() {
        let store = TodoStore.sample()
        _store = State(initialValue: store)
        Feetback.enable()
        Feetback.context("TodoStore") { store }
        Feetback.procrastimate(Self.procrastimateLink)
        if let token = UserDefaults.standard.string(forKey: "githubToken") { Feetback.github(token: token) }
    }

    /// This demo is not in the team's shared keychain group, so it posts with a personal token when
    /// one is set: `defaults write com.stefan.tododemo procrastimateURL <origin>`, and the same
    /// for `procrastimateToken`. GitHub Issue appears once `githubToken` holds a token, such as
    /// the output of `gh auth token`.
    private static var procrastimateLink: Procrastimate.Link {
        let defaults = UserDefaults.standard
        guard let url = defaults.string(forKey: "procrastimateURL").flatMap(URL.init(string:)),
              let token = defaults.string(forKey: "procrastimateToken")
        else { return .shared() }
        return .token(apiURL: url, token: token)
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
