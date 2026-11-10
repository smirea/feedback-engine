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

    /// Turns on shake-to-feedback: shaking shows a button that captures the screen and opens
    /// the editor.
    /// Call it once at launch, for example in `App.init`.
    public static func enable() {
        isShakeEnabled = true
    }

    /// Registers app state to attach to every capture, read when the capture is taken.
    /// Registering a name again replaces the earlier provider.
    public static func context(_ name: String, _ value: @escaping @MainActor () -> Any) {
        providers.removeAll { $0.name == name }
        providers.append((name, value))
    }

    /// Captures the active screen and opens the editor. Does nothing while the editor is open.
    public static func present() {
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

enum ShareTarget: CaseIterable {
    case image
    case json
    /// `feedback.png` and `feedback.json` in one `feedback.zip`.
    case zip
    case procrastimate

    var title: String {
        switch self {
        case .image: "Image"
        case .json: "JSON"
        case .zip: "Image and JSON (ZIP)"
        case .procrastimate: "ProcrastiMate"
        }
    }

    var systemImage: String {
        switch self {
        case .image: "photo"
        case .json: "curlybraces"
        case .zip: "doc.zipper"
        case .procrastimate: "checklist"
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

