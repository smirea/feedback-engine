import Feedback
import SwiftUI

@main
struct TodoDemoApp: App {
    @State private var store: TodoStore

    init() {
        let store = TodoStore.sample()
        _store = State(initialValue: store)
        Feedback.enable()
        // Set by the launch environment, such as `SIMCTL_CHILD_FEEDBACK_WEBHOOK_URL` for `simctl launch`.
        let environment = ProcessInfo.processInfo.environment
        if let url = environment["FEEDBACK_WEBHOOK_URL"].flatMap(URL.init(string:)) {
            Feedback.webhooks = [
                FeedbackWebhook(
                    name: "GitHub Issue",
                    url: url,
                    image: Feedback.githubIcon,
                    // Closures run when the post is made, as an app that reads its session there needs.
                    headers: { ["Authorization": "Bearer \(environment["FEEDBACK_WEBHOOK_KEY"] ?? "")"] },
                    query: { ["labels": "feedback"] }
                ),
            ]
        }
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
