#if canImport(UIKit)
import SwiftUI
import UIKit

/// Somewhere the Share menu posts feedback as one titled entry in a container the user picks, such
/// as a ProcrastiMate project or a GitHub repository.
@MainActor
protocol Destination {
    /// Names the cached containers and the last pick in `UserDefaults`.
    var key: String { get }
    var sheetTitle: String { get }
    var containerTitle: String { get }
    /// Picks offered before the loaded containers, such as ProcrastiMate's Inbox.
    var fixedOptions: [PostOption] { get }
    func options() async throws -> [PostOption]
    /// Posts and returns the confirmation to show.
    func post(_ post: Post, to option: PostOption) async throws -> String
}

struct PostOption: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var systemImage: String?
}

struct Post {
    let title: String
    let items: [FeedbackItem]
    let capture: Capture
    let json: String
    let image: UIImage
}

/// Picks the container, and the entry's name when there is more than one item, then posts.
struct PostSheet: View {
    let session: Session
    let destination: any Destination
    let close: () -> Void
    @State private var options: [PostOption]
    @State private var selection: String?
    @State private var name = ""
    @State private var loading = true
    @State private var loadError: String?
    @State private var postError: String?
    @State private var posting = false
    @FocusState private var naming: Bool

    init(session: Session, destination: any Destination, close: @escaping () -> Void) {
        self.session = session
        self.destination = destination
        self.close = close
        let cached = UserDefaults.standard.data(forKey: Self.optionsKey(destination)).flatMap { try? JSONDecoder().decode([PostOption].self, from: $0) } ?? []
        _options = State(initialValue: cached)
        let last = UserDefaults.standard.string(forKey: Self.lastKey(destination))
        _selection = State(initialValue: last ?? destination.fixedOptions.first?.id)
    }

    static func controller(session: Session, destination: any Destination) -> UIViewController {
        let host = UIHostingController<PostSheet?>(rootView: nil)
        host.rootView = PostSheet(session: session, destination: destination) { [weak host] in host?.dismiss(animated: true) }
        host.overrideUserInterfaceStyle = .dark
        host.sheetPresentationController?.detents = [.medium(), .large()]
        return host
    }

    private static func optionsKey(_ destination: any Destination) -> String { "feetback.\(destination.key).options" }
    private static func lastKey(_ destination: any Destination) -> String { "feetback.\(destination.key).last" }

    private var title: String {
        session.items.count == 1 ? session.items[0].text : name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var choices: [PostOption] { destination.fixedOptions + options }
    private var selected: PostOption? { choices.first { $0.id == selection } }

    var body: some View {
        NavigationStack {
            Form {
                if session.items.count > 1 {
                    Section("Name") {
                        TextField("Name", text: $name)
                            .focused($naming)
                            .submitLabel(.done)
                    }
                } else {
                    Section("Title") { Text(title).lineLimit(3) }
                }
                Section {
                    Picker(destination.containerTitle, selection: $selection) {
                        ForEach(choices) { option in
                            Group {
                                if let systemImage = option.systemImage {
                                    Label(option.name, systemImage: systemImage)
                                } else {
                                    Text(option.name)
                                }
                            }
                            .tag(Optional(option.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    HStack {
                        Text(destination.containerTitle)
                        if loading { ProgressView().controlSize(.mini) }
                    }
                } footer: {
                    if let loadError { Text(loadError).foregroundStyle(.red) }
                }
                if let postError {
                    Section { Text(postError).foregroundStyle(.red) }
                }
            }
            .navigationTitle(destination.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
                ToolbarItem(placement: .confirmationAction) {
                    if posting {
                        ProgressView()
                    } else {
                        Button("Add", action: post).disabled(title.isEmpty || selected == nil)
                    }
                }
            }
            .disabled(posting)
        }
        .dynamicTypeSize(...EditorView.largestTextSize)
        .interactiveDismissDisabled(posting)
        .task { await load() }
        .onAppear { naming = session.items.count > 1 }
    }

    private func load() async {
        defer { loading = false }
        do {
            let loaded = try await destination.options()
            options = loaded
            UserDefaults.standard.set(try? JSONEncoder().encode(loaded), forKey: Self.optionsKey(destination))
            if selected == nil { selection = destination.fixedOptions.first?.id }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func post() {
        guard let option = selected else { return }
        posting = true
        postError = nil
        let items = session.items
        let post = Post(
            title: title, items: items, capture: session.capture, json: session.json,
            image: AnnotatedImage.render(session.capture, items: items)
        )
        Task {
            do {
                let toast = try await destination.post(post, to: option)
                UserDefaults.standard.set(option.id, forKey: Self.lastKey(destination))
                session.shared.formUnion(items)
                session.toast = toast
                close()
            } catch {
                postError = error.localizedDescription
                posting = false
            }
        }
    }
}
#endif
