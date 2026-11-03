#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
public enum Feetback {
    private(set) static var isShakeEnabled = false

    private enum State {
        case idle
        case capturing
        case editing(overlay: UIWindow, previousKey: UIWindow?)
    }

    private static var providers: [(name: String, value: @MainActor () -> Any)] = []
    private static var state = State.idle

    /// Turns on shake-to-feedback: shaking captures the screen and opens the editor.
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
        state = .capturing
        Task { await open(in: scene) }
    }

    private static func open(in scene: UIWindowScene) async {
        let context = providers.map { ContextEntry(name: $0.name, value: Describer.describe($0.value(), limit: 8000)) }
        guard let capture = await Capturer.capture(scene: scene, context: context) else {
            state = .idle
            return
        }
        scene.windows.forEach { $0.endEditing(true) }

        let previousKey = scene.keyWindow
        let session = Session(capture: capture)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: EditorView(session: session, dismiss: dismiss, share: { share(session) }))
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        window.makeKeyAndVisible()
        state = .editing(overlay: window, previousKey: previousKey)
    }

    private static func share(_ session: Session) {
        guard case .editing(let overlay, _) = state, var presenter = overlay.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let activityItems: [Any]
        let pasteboard: [[String: Any]]
        switch session.format {
        case .image:
            let image = AnnotatedImage.render(session.capture, items: session.items)
            let markdown = session.markdown
            activityItems = [image, markdown]
            pasteboard = (image.pngData().map { [[UTType.png.identifier: $0]] } ?? []) + [[UTType.utf8PlainText.identifier: markdown]]
        case .json:
            let json = session.json
            let file = FileManager.default.temporaryDirectory.appending(path: "feedback.json")
            activityItems = (try? Data(json.utf8).write(to: file)) != nil ? [file] : [json]
            pasteboard = [[UTType.json.identifier: Data(json.utf8), UTType.utf8PlainText.identifier: json]]
        }
        let sheet = UIActivityViewController(activityItems: activityItems, applicationActivities: [CopyActivity(items: pasteboard)])
        sheet.excludedActivityTypes = [.copyToPasteboard]
        sheet.popoverPresentationController?.sourceView = presenter.view
        presenter.present(sheet, animated: true)
    }

    static func dismiss() {
        if case .editing(let overlay, let previousKey) = state {
            overlay.isHidden = true
            previousKey?.makeKey()
        }
        state = .idle
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake, Feetback.isShakeEnabled {
            Feetback.present()
            return
        }
        super.motionEnded(motion, with: event)
    }
}
#endif

