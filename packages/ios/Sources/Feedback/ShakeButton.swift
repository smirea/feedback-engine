#if canImport(UIKit)
import UIKit

/// A shake shows this button in the top-right corner instead of opening the editor, so an
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
    private static let size: CGFloat = 52

    /// Built apps list their icon's PNG in `CFBundleIconFiles`. Apps without an icon get a symbol.
    private static let appIcon: UIImage? = {
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let names = (primary?["CFBundleIconFiles"] as? [String] ?? []).reversed() + [primary?["CFBundleIconName"] as? String].compactMap { $0 }
        return names.lazy.compactMap { UIImage(named: $0) }.first
    }()

    private let background = UIVisualEffectView()
    private let icon = UIImageView()
    let button = UIButton(type: .custom)

    private var effect: UIVisualEffect {
        if #available(iOS 26, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            return glass
        }
        return UIBlurEffect(style: .systemThinMaterial)
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        background.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26, *) {
            background.cornerConfiguration = .capsule()
        } else {
            background.layer.cornerRadius = Self.size / 2
            background.clipsToBounds = true
        }
        view.addSubview(background)

        let iconSize = Self.size - 16
        icon.translatesAutoresizingMaskIntoConstraints = false
        if let appIcon = Self.appIcon {
            icon.image = appIcon
            icon.layer.cornerRadius = iconSize * 0.225
            icon.layer.cornerCurve = .continuous
            icon.clipsToBounds = true
        } else {
            icon.image = UIImage(systemName: "exclamationmark.bubble.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
            icon.contentMode = .center
            icon.tintColor = .label
        }
        background.contentView.addSubview(icon)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Send feedback"
        button.addAction(UIAction { _ in ShakeButton.tapped() }, for: .primaryActionTriggered)
        background.contentView.addSubview(button)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            background.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            background.widthAnchor.constraint(equalToConstant: Self.size),
            background.heightAnchor.constraint(equalToConstant: Self.size),
            icon.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: iconSize),
            icon.heightAnchor.constraint(equalToConstant: iconSize),
            button.topAnchor.constraint(equalTo: background.topAnchor),
            button.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        ])
    }

    /// Animating a visual effect view's `effect` from nil is what makes glass materialize.
    func materialize() {
        view.layoutIfNeeded()
        icon.alpha = 0
        background.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
            self.background.effect = self.effect
            self.background.transform = .identity
            self.icon.alpha = 1
        }
    }

    func dematerialize(completion: @escaping @MainActor () -> Void) {
        UIView.animate(withDuration: 0.4, animations: {
            self.background.effect = nil
            self.background.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            self.icon.alpha = 0
        }, completion: { _ in MainActor.assumeIsolated { completion() } })
    }
}
#endif
