#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
public enum Feedback {
    private(set) static var isShakeEnabled = false

    private enum State {
        case idle
        case capturing
        case editing(Editing)
    }

    /// What closing the editor puts back.
    private struct Editing {
        let overlay: UIWindow
        let previousKey: UIWindow?
        weak var responder: UIResponder?
        let accessibilityHidden: [(window: UIWindow, wasHidden: Bool)]
    }

    private static var providers: [(name: String, value: @MainActor () -> Any)] = []
    private static var state = State.idle
    private static var isPosting = false

    /// The webhooks the Share menu lists after its own entries. Choosing one posts the image export
    /// and the JSON export to its `url`, with nothing more to fill in.
    public static var webhooks: [FeedbackWebhook] = []

    /// Turns on shake-to-feedback: shaking shows a button that captures the screen and opens
    /// the editor.
    /// Call it once at launch, for example in `App.init`. It also sends ProcrastiMate posts an
    /// earlier run left in the outbox.
    public static func enable() {
        isShakeEnabled = true
        // On the next turn: `App.init` can run before the app can start background work.
        Task { @MainActor in Outbox.shared.start() }
    }

    /// Registers app state to attach to every capture, read when the capture is taken.
    /// Registering a name again replaces the earlier provider.
    public static func context(_ name: String, _ value: @escaping @MainActor () -> Any) {
        providers.removeAll { $0.name == name }
        providers.append((name, value))
    }

    /// Captures the active screen and opens the editor. Does nothing while the editor is open.
    public static func present() {
        Outbox.shared.start()
        guard case .idle = state, let scene = activeScene else { return }
        ShakeButton.hide()
        state = .capturing
        Task { await open(in: scene) }
    }

    private static func open(in scene: UIWindowScene) async {
        let context = providers.map { ContextEntry(name: $0.name, value: Describer.describe($0.value(), limit: 8000)) }
        guard let capture = await Capturer.capture(scene: scene, context: context) else {
            state = .idle
            return
        }
        let responder = scene.windows.lazy.compactMap { firstResponder(in: $0) }.first
        scene.windows.forEach { $0.endEditing(true) }

        let previousKey = scene.keyWindow
        let session = Session(capture: capture)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: EditorView(session: session, dismiss: dismiss, share: { share(session, as: $0) }))
        // `accessibilityViewIsModal` only hides siblings in the same window, so the app's windows
        // are hidden from VoiceOver and UI automation one by one. The keyboard's windows stay
        // visible for the editor's own text field.
        let hidden = scene.windows.filter { $0 !== window && !Capturer.isSystemWindow($0) }.map { ($0, $0.accessibilityElementsHidden) }
        hidden.forEach { $0.0.accessibilityElementsHidden = true }
        Outbox.shared.onEvent = { [weak session] event in
            switch event {
            case .sent(let post):
                // ProcrastiMate opens `procrastimate://task/<id>` on the task, as it does Notouroboros's links.
                session?.toast = Toast(text: "Added to \(post.destination) in ProcrastiMate", link: URL(string: "procrastimate://task/\(post.id)"))
            case .waiting(let post) where post.attempts == 1:
                session?.toast = Toast(text: "Saved. It goes to ProcrastiMate once the connection is back.")
            case .waiting:
                break
            case .failed:
                session?.toast = Toast(text: "Couldn't add to ProcrastiMate. Share › ProcrastiMate says why.")
            }
        }
        window.makeKeyAndVisible()
        state = .editing(Editing(overlay: window, previousKey: previousKey, responder: responder, accessibilityHidden: hidden))
        UIAccessibility.post(notification: .screenChanged, argument: window)
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        return view.subviews.lazy.compactMap { firstResponder(in: $0) }.first
    }

    private static func share(_ session: Session, as target: ShareTarget) {
        guard case .editing(let editing) = state, var presenter = editing.overlay.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        if target == .procrastimate {
            presenter.present(ProcrastimateSheet.controller(session: session), animated: true)
            return
        }
        if case .webhook(let index) = target {
            post(session, to: webhooks[index])
            return
        }
        var files: [(name: String, data: Data)] = []
        var pasteboard: [[String: Any]] = []
        if target != .json {
            let png = AnnotatedImage.render(session.capture, session.annotations).pngData() ?? Data()
            files.append(("feedback.png", png))
            pasteboard.append([UTType.png.identifier: png])
        }
        if target != .image {
            let json = session.json
            files.append(("feedback.json", Data(json.utf8)))
            pasteboard.append([UTType.json.identifier: Data(json.utf8), UTType.utf8PlainText.identifier: json])
        }
        let file = try? target == .zip ? zip(files) : write(files[0])
        let sheet = UIActivityViewController(activityItems: [file ?? files[0].data], applicationActivities: [CopyActivity(items: pasteboard)])
        sheet.excludedActivityTypes = [.copyToPasteboard]
        let items = session.items
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            if completed { session.shared.formUnion(items) }
        }
        sheet.popoverPresentationController?.sourceView = presenter.view
        presenter.present(sheet, animated: true)
    }

    /// Sends the feedback to a webhook. A failure opens a sheet with the reason and **Retry**, which
    /// sends the same post again.
    private static func post(_ session: Session, to webhook: FeedbackWebhook, retrying earlier: WebhookPost? = nil) {
        guard !isPosting else { return }
        isPosting = true
        let items = session.items
        session.toast = Toast(text: "Sending to \(webhook.name)…")
        let post = earlier ?? WebhookPost(
            id: UUID().uuidString.lowercased(),
            title: TaskTitle(session.capture, items: items).placeholder,
            image: AnnotatedImage.render(session.capture, session.annotations).pngData() ?? Data(),
            report: Data(session.compactJSON.utf8)
        )
        let started = Date.now
        Task {
            defer { isPosting = false }
            var step = "Reading the headers and the query"
            do {
                let request = try await webhook.request(post)
                step = "Sending to \(webhook.name)"
                let link = try await FeedbackWebhook.send(request, name: webhook.name)
                session.shared.formUnion(items)
                session.toast = Toast(text: "Sent to \(webhook.name)", link: link)
            } catch {
                session.toast = nil
                let problem = Problem(error).with(
                    before: [
                        .init(label: "Step", value: step),
                        .init(label: "Elapsed", value: "\(String(format: "%.1f", Date.now.timeIntervalSince(started))) s"),
                    ],
                    after: [
                        .init(label: "Post", value: post.id),
                        .init(label: "Image", value: "\(post.image.count) bytes"),
                        .init(label: "Report", value: "\(post.report.count) bytes"),
                    ] + session.capture.environment.map { .init(label: $0.name, value: $0.value) }
                )
                guard case .editing(let editing) = state, var presenter = editing.overlay.rootViewController else { return }
                while let presented = presenter.presentedViewController { presenter = presented }
                presenter.present(WebhookFailureSheet.controller(name: webhook.name, problem: problem) {
                    self.post(session, to: webhook, retrying: post)
                }, animated: true)
            }
        }
    }

    private static func write(_ file: (name: String, data: Data)) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: file.name)
        try file.data.write(to: url)
        return url
    }

    /// Foundation has no zip writer, but coordinating a read of a folder `forUploading` hands over
    /// a zip of it.
    private static func zip(_ files: [(name: String, data: Data)]) throws -> URL {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appending(path: "feedback")
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files { try file.data.write(to: folder.appending(path: file.name)) }
        let zip = manager.temporaryDirectory.appending(path: "feedback.zip")
        var coordination: NSError?
        var copy: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordination) { zipped in
            do {
                try? manager.removeItem(at: zip)
                try manager.copyItem(at: zipped, to: zip)
            } catch {
                copy = error
            }
        }
        if let error = coordination ?? copy { throw error }
        return zip
    }

    static func dismiss() {
        Outbox.shared.onEvent = nil
        if case .editing(let editing) = state {
            editing.overlay.isHidden = true
            for (window, wasHidden) in editing.accessibilityHidden { window.accessibilityElementsHidden = wasHidden }
            editing.previousKey?.makeKey()
            editing.responder?.becomeFirstResponder()
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        state = .idle
    }

    static func shaken() {
        guard case .idle = state, let scene = activeScene else { return }
        ShakeButton.show(in: scene)
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

@MainActor
enum ShareTarget: Hashable {
    case image
    case json
    /// `feedback.png` and `feedback.json` in one `feedback.zip`.
    case zip
    case procrastimate
    /// One of `Feedback.webhooks`, by its place in the list.
    case webhook(Int)

    /// What the Share menu lists. ProcrastiMate is there only in an app that can reach it, and the
    /// app's webhooks come last.
    static var available: [ShareTarget] {
        [.image, .json, .zip] + (Procrastimate.isAvailable ? [.procrastimate] : []) + Feedback.webhooks.indices.map { .webhook($0) }
    }

    var title: String {
        switch self {
        case .image: "Image"
        case .json: "JSON"
        case .zip: "Image and JSON (ZIP)"
        case .procrastimate: "ProcrastiMate"
        case .webhook(let index): Feedback.webhooks[index].name
        }
    }

    /// The icon of an entry without an image of its own.
    var systemImage: String {
        switch self {
        case .image: "photo"
        case .json: "curlybraces"
        case .zip: "doc.zipper"
        case .procrastimate: "checklist"
        case .webhook: "paperplane"
        }
    }
}

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake, Feedback.isShakeEnabled {
            Feedback.shaken()
            return
        }
        super.motionEnded(motion, with: event)
    }
}
#endif

