#if canImport(UIKit)
import SwiftUI
import UIKit

/// Adds a webhook to the Share menu, or opens one added before to send the feedback to it, change it,
/// or delete it.
struct WebhookForm: View {
    let webhook: SavedWebhook?
    let taken: [String]
    /// Saves a new webhook, or saves an edited one and sends the feedback to it.
    let submit: (SavedWebhook) -> Void
    let delete: () -> Void
    let close: () -> Void
    @State private var draft: WebhookDraft
    @State private var errors = WebhookDraft.Errors()
    /// Return moves to the next field and leaves the last one, since the keyboard covers the button.
    @FocusState private var focus: Field?
    private let id: String

    init(webhook: SavedWebhook?, taken: [String], submit: @escaping (SavedWebhook) -> Void, delete: @escaping () -> Void, close: @escaping () -> Void) {
        self.webhook = webhook
        self.taken = taken
        self.submit = submit
        self.delete = delete
        self.close = close
        _draft = State(initialValue: webhook.map(WebhookDraft.init) ?? WebhookDraft())
        id = webhook?.id ?? UUID().uuidString.lowercased()
    }

    static func controller(webhook: SavedWebhook?, taken: [String], submit: @escaping (SavedWebhook) -> Void, delete: @escaping () -> Void) -> UIViewController {
        let host = UIHostingController<WebhookForm?>(rootView: nil)
        let close: () -> Void = { [weak host] in host?.dismiss(animated: true) }
        host.rootView = WebhookForm(webhook: webhook, taken: taken, submit: { saved in
            close()
            submit(saved)
        }, delete: {
            close()
            delete()
        }, close: close)
        host.overrideUserInterfaceStyle = .dark
        // The sheet's own background is drawn outside the controller's view, so it needs the style too.
        host.sheetPresentationController?.traitOverrides.userInterfaceStyle = .dark
        host.sheetPresentationController?.detents = [.large()]
        return host
    }

    var body: some View {
        NavigationStack {
            Form {
                field(.name, text: $draft.name, prompt: "Agent", error: errors.name)
                field(.url, text: $draft.url, prompt: "https://hooks.example.com/feedback", error: errors.url)
                field(.header, text: $draft.header, prompt: "Authorization: Bearer key", error: errors.header)
                Section {
                    Toggle("Attach JSON", isOn: $draft.feedback)
                    Toggle("Attach image", isOn: $draft.image.animation())
                    if draft.image {
                        LabeledContent("Image format") {
                            Picker("Image format", selection: $draft.format.animation()) {
                                Text("PNG").tag(WebhookDraft.Format.png)
                                Text("JPEG").tag(WebhookDraft.Format.jpeg)
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        if draft.format == .jpeg {
                            LabeledContent("Compression") {
                                Picker("Compression", selection: $draft.compression) {
                                    ForEach(ImageEncoding.Compression.allCases, id: \.self) { level in
                                        Text(level.rawValue.capitalized).tag(level)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .fixedSize()
                            }
                        }
                    }
                } footer: {
                    Text("\(draft.note) This app keeps the webhook, header included, on this device.")
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(webhook?.name ?? "New Webhook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if webhook != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Delete Webhook", systemImage: "trash", role: .destructive, action: delete).tint(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Close", systemImage: "xmark", action: close) }
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    Button(webhook == nil ? "Save" : "Send") {
                        switch draft.read(id: id, taken: taken) {
                        case .success(let saved): submit(saved)
                        case .failure(let found): errors = found
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .fontWeight(.semibold)
                }
            }
        }
        .dynamicTypeSize(...EditorView.largestTextSize)
    }

    private enum Field: String, CaseIterable {
        case name = "Name"
        case url = "URL"
        case header = "Header (optional)"
    }

    private func field(_ field: Field, text: Binding<String>, prompt: String, error: String?) -> some View {
        let next = Field.allCases.drop { $0 != field }.dropFirst().first
        return Section {
            TextField(field.rawValue, text: text, prompt: Text(prompt))
                .focused($focus, equals: field)
                .submitLabel(next == nil ? .done : .next)
                .onSubmit { focus = next }
                .keyboardType(field == .url ? .URL : .default)
                .textInputAutocapitalization(field == .name ? .words : .never)
                .autocorrectionDisabled(field != .name)
        } header: {
            Text(field.rawValue)
        } footer: {
            if let error { Text(error).foregroundStyle(.red) }
        }
    }
}
#endif
