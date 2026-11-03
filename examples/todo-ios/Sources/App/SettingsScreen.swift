import Feetback
import SwiftUI

struct SettingsScreen: View {
    @Environment(TodoStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Display") {
                Toggle("Show completed", isOn: $store.showCompleted)
                Picker("Sort by", selection: $store.sortOrder) {
                    ForEach(SortOrder.allCases) { Text($0.rawValue.capitalized) }
                }
            }
            Section("Feedback") {
                Button("Send Feedback", systemImage: "bubble.left.and.text.bubble.right") { Feetback.present() }
                Text("Or shake the device on any screen.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Examples") {
                NavigationLink("Exercise Catalog") { CatalogScreen() }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                LabeledContent("Lists", value: "\(store.lists.count)")
            }
        }
        .navigationTitle("Settings")
        .feedback("SettingsScreen", data: (showCompleted: store.showCompleted, sortOrder: store.sortOrder))
    }
}
