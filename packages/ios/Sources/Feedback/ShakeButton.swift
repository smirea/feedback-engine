#if canImport(UIKit)
import UIKit

/// A shake drops this button in at the top center instead of opening the editor, so an
/// accidental shake costs nothing: left alone, the button dissolves after five seconds.
@MainActor
enum ShakeButton {
    private static var window: PassthroughWindow?
    private static var dismissal: Task<Void, Never>?
    private static var backgroundObserver: NSObjectProtocol?

    /// Another shake replaces the button, which restarts the timer and catches a shake that lands
    /// while the button is dissolving.
    static func show(in scene: UIWindowScene) {
        hide()
        dismissal = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { dissolve() }
        }
        // Locking the phone or leaving the app clears the button, so it never waits on return.
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIScene.didEnterBackgroundNotification, object: scene, queue: .main) { _ in
            MainActor.assumeIsolated { hide() }
        }

        let controller = ButtonController()
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
        controller.materialize()
        UIAccessibility.post(notification: .layoutChanged, argument: controller.button)
    }

    /// Hides the button at once, so a capture taken right after doesn't include it.
    static func hide() {
        dismissal?.cancel()
        backgroundObserver.map(NotificationCenter.default.removeObserver)
        backgroundObserver = nil
        window?.isHidden = true
        window = nil
    }

    private static func dissolve() {
        guard let window, let controller = window.rootViewController as? ButtonController else { return }
        controller.dematerialize {
            if self.window === window { hide() }
        }
    }

    fileprivate static func tapped() {
        hide()
        Feedback.present()
    }
}

private final class PassthroughWindow: UIWindow {
    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self || view === rootViewController?.view ? nil : view
    }
}

private final class ButtonController: UIViewController {
    /// The engine's mark from `docs/assets/icon.svg`: two chamfered speech bubbles on a 256 grid.
    /// The stroke is a bit heavier than the SVG's 12 so it holds up at 22 pt.
    private static let mark = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { context in
        context.cgContext.scaleBy(x: 22.0 / 256, y: 22.0 / 256)
        let bubbles: [(color: UIColor, points: [(CGFloat, CGFloat)])] = [
            (UIColor(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255, alpha: 1),
             [(38, 28), (142, 28), (158, 44), (158, 88), (142, 104), (86, 104), (50, 130), (50, 104), (38, 104), (22, 88), (22, 44)]),
            (UIColor(red: 0x06 / 255, green: 0x49 / 255, blue: 0xDC / 255, alpha: 1),
             [(114, 134), (218, 134), (234, 150), (234, 194), (218, 210), (206, 210), (206, 236), (170, 210), (114, 210), (98, 194), (98, 150)]),
        ]
        for bubble in bubbles {
            let path = UIBezierPath()
            for (index, point) in bubble.points.enumerated() {
                let point = CGPoint(x: point.0, y: point.1)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.close()
            path.lineWidth = 16
            path.lineJoinStyle = .miter
            bubble.color.setStroke()
            path.stroke()
        }
    }

    private let background = UIVisualEffectView()
    let button = UIButton(configuration: .plain())

    private var effect: UIVisualEffect {
        if #available(iOS 26, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            return glass
        }
        return UIBlurEffect(style: .systemThinMaterial)
    }

    /// The pill grows out of, and shrinks back into, a capsule the size of the Dynamic Island
    /// centered in the status bar. Animating the glass view's frame, not its transform, is what
    /// makes the glass reflow like liquid instead of scaling as a picture.
    private lazy var tucked = [
        background.centerYAnchor.constraint(equalTo: view.topAnchor),
        background.widthAnchor.constraint(equalToConstant: 126),
        background.heightAnchor.constraint(equalToConstant: 37),
    ]
    private lazy var shown = [
        background.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        background.widthAnchor.constraint(equalTo: button.widthAnchor),
        background.heightAnchor.constraint(equalTo: button.heightAnchor),
    ]

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        background.translatesAutoresizingMaskIntoConstraints = false
        background.clipsToBounds = true
        if #available(iOS 26, *) { background.cornerConfiguration = .capsule() }
        view.addSubview(background)

        var configuration = UIButton.Configuration.plain()
        configuration.image = Self.mark.withRenderingMode(.alwaysOriginal)
        configuration.imagePadding = 8
        configuration.title = "Add Feedback"
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold), maximumPointSize: 22)
            return attributes
        }
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 18)
        button.configuration = configuration
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { _ in ShakeButton.tapped() }, for: .primaryActionTriggered)
        background.contentView.addSubview(button)

        NSLayoutConstraint.activate([
            background.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ] + tucked)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tucked[0].constant = view.safeAreaInsets.top / 2
        if #unavailable(iOS 26) { background.layer.cornerRadius = background.bounds.height / 2 }
    }

    /// Animating a visual effect view's `effect` from nil is what makes glass materialize. It
    /// materializes quickly over the island so the whole morph down to the pill stays visible.
    func materialize() {
        view.layoutIfNeeded()
        button.alpha = 0
        NSLayoutConstraint.deactivate(tucked)
        NSLayoutConstraint.activate(shown)
        UIView.animate(withDuration: 0.15) { self.background.effect = self.effect }
        UIView.animate(springDuration: 0.6, bounce: 0.3) { self.view.layoutIfNeeded() }
        UIView.animate(withDuration: 0.25, delay: 0.22, options: .curveEaseOut) { self.button.alpha = 1 }
    }

    func dematerialize(completion: @escaping @MainActor () -> Void) {
        UIView.animate(withDuration: 0.12) { self.button.alpha = 0 }
        NSLayoutConstraint.deactivate(shown)
        NSLayoutConstraint.activate(tucked)
        UIView.animate(springDuration: 0.45, bounce: 0, delay: 0.05, options: [], animations: {
            self.view.layoutIfNeeded()
        }, completion: { _ in
            UIView.animate(withDuration: 0.15, animations: { self.background.effect = nil }, completion: { _ in
                MainActor.assumeIsolated { completion() }
            })
        })
    }
}
#endif
