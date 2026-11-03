#if canImport(UIKit)
import UIKit

@MainActor
enum Capturer {
    /// An element and whether the walk reached it through the scroll view being captured.
    private struct Found {
        var element: RawScene.Element
        var inScrollView: Bool
    }

    private struct LayerSource {
        let view: UIView
        let name: String
        /// Root views of extra windows, such as toasts, often span the whole screen while showing
        /// a small banner, so their layer covers only what they actually contain.
        let fitsContent: Bool
    }

    /// The screenshot and tags are read synchronously, at the moment of the trigger. Accessibility
    /// elements come after: SwiftUI only builds them once automation accessibility is on. A screen
    /// with a scrolling list is read again at every scroll step of a full-length capture.
    /// Everything is in the coordinates of the app's main window, which on iPad may be smaller
    /// than the screen.
    static func capture(scene: UIWindowScene, context: [ContextEntry]) async -> Capture? {
        let windows = scene.windows
            .filter { !$0.isHidden && $0.alpha > 0 && !isSystemWindow($0) }
            .sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
        guard let reference = windows.first else { return nil }
        let space = reference as any UICoordinateSpace
        let bounds = reference.bounds

        var sources: [LayerSource] = []
        var navigation: [String] = []
        func add(_ source: LayerSource) {
            sources.append(source)
            let titles = navigationTitles(in: source.view)
            navigation += sources.count == 1 ? titles : ["(\(source.name))"] + titles
        }
        for (index, window) in windows.enumerated() {
            var controller = window.rootViewController
            var isRoot = true
            while let current = controller {
                controller = current.presentedViewController
                defer { isRoot = false }
                // A menu presents an empty placeholder controller and draws its items in a container
                // view added straight to the window, which is collected below.
                guard !isContextMenu(current), let view = current.viewIfLoaded, view.window != nil else { continue }
                add(LayerSource(view: view, name: sources.isEmpty ? "Screen" : layerName(current), fitsContent: index > 0 && isRoot))
            }
            for view in window.subviews where !view.isHidden && isContextMenu(view) {
                add(LayerSource(view: view, name: "Menu", fitsContent: true))
            }
        }
        let keyboard = keyboardFrame(in: scene, space: space)

        let format = UIGraphicsImageRendererFormat()
        format.scale = reference.screen.scale
        let shot = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            for window in windows { window.drawHierarchy(in: window.convert(window.bounds, to: space), afterScreenUpdates: false) }
            if let keyboard { drawKeyboard(in: keyboard, context: context.cgContext, traits: reference.traitCollection) }
        }
        let environment = environment(window: reference, scene: scene, navigation: navigation)

        if sources.count == 1, keyboard == nil, let scrollView = mainScrollView(in: sources[0].view, space: space) {
            let cover = coverWindow(scene: scene, frame: reference.frame, image: shot)
            defer { cover.isHidden = true }
            let full = await AutomationAccessibility.whileEnabled {
                await fullLength(scrollView, root: sources[0].view, windows: windows, reference: reference, format: format)
            }
            guard let image = full.image.cgImage else { return nil }
            return Capture(
                date: .now, screen: full.scene.screen, visible: full.visible, scale: format.scale, image: image,
                nodes: TreeBuilder.build(full.scene), environment: environment, context: context
            )
        }

        var raw = RawScene(screen: bounds.size, layers: [], components: [], elements: [])
        for (layer, source) in sources.enumerated() {
            collectMarkers(in: source.view, layer: layer, space: space, into: &raw.components)
        }
        guard let cgImage = shot.cgImage else { return nil }

        raw.elements = await AutomationAccessibility.whileEnabled {
            await settledElements(in: sources.map(\.view), to: reference, minimum: .milliseconds(120)).map(\.element)
        }
        raw.layers = sources.enumerated().map { layer, source in
            guard layer > 0 else { return RawScene.Layer(name: source.name, frame: bounds) }
            guard source.fitsContent else { return RawScene.Layer(name: source.name, frame: source.view.convert(source.view.bounds, to: space)) }
            let frames = raw.components.filter { $0.layer == layer }.map(\.frame) + raw.elements.filter { $0.layer == layer }.map(\.frame)
            return RawScene.Layer(name: source.name, frame: frames.reduce(CGRect.null) { $0.union($1) })
        }
        if raw.layers.isEmpty { raw.layers.append(RawScene.Layer(name: "Screen", frame: bounds)) }
        if let keyboard { raw.layers.append(RawScene.Layer(name: "Keyboard", frame: keyboard)) }

        return Capture(
            date: .now,
            screen: bounds.size,
            visible: bounds,
            scale: format.scale,
            image: cgImage,
            nodes: TreeBuilder.build(raw),
            environment: environment,
            context: context
        )
    }

    private static func isContextMenu(_ object: NSObject) -> Bool {
        String(describing: type(of: object)).contains("ContextMenu")
    }

    /// The keyboard is drawn by another process, so `drawHierarchy` leaves its area empty and the
    /// bars that sit on it seem to float. Its frame comes from the in-process placeholder view.
    private static func keyboardFrame(in scene: UIWindowScene, space: any UICoordinateSpace) -> CGRect? {
        var best: CGRect?
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            let name = String(describing: type(of: view))
            if name.contains("KeyboardPlaceholderView") || name.contains("InputSetHostView") {
                let frame = view.convert(view.bounds, to: space).intersection(space.bounds)
                if !frame.isNull, frame.height > 40, frame.height > best?.height ?? 0 { best = frame }
                return
            }
            view.subviews.forEach(visit)
        }
        scene.windows.filter { !$0.isHidden && isSystemWindow($0) }.forEach(visit)
        return best
    }

    private static func drawKeyboard(in frame: CGRect, context: CGContext, traits: UITraitCollection) {
        let dark = traits.userInterfaceStyle == .dark
        UIColor(white: dark ? 0.17 : 0.82, alpha: 1).setFill()
        context.fill(frame)
        let label = NSAttributedString(string: "Keyboard", attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: UIColor(white: dark ? 0.55 : 0.45, alpha: 1),
        ])
        let size = label.size()
        label.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }

    /// The largest scroll view that covers at least half the screen and has more content than
    /// fits. Screens with a presented sheet or the keyboard up are captured as they look instead.
    private static func mainScrollView(in root: UIView, space: any UICoordinateSpace) -> UIScrollView? {
        let screen = space.bounds
        var best: (view: UIScrollView, area: CGFloat)?
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let scroll = view as? UIScrollView, !(scroll is UITextView), scroll.isScrollEnabled {
                let frame = scroll.convert(scroll.bounds, to: space).intersection(screen)
                let inset = scroll.adjustedContentInset
                let overflow = scroll.contentSize.height + inset.top + inset.bottom - scroll.bounds.height
                if overflow > 1, frame.height >= screen.height / 2, frame.width * frame.height > best?.area ?? 0 {
                    best = (scroll, frame.width * frame.height)
                }
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return best?.view
    }

    /// Hides the scrolling a full-length capture does. Not key, so the app keeps its focus.
    private static func coverWindow(scene: UIWindowScene, frame: CGRect, image: UIImage) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.windowLevel = .alert + 1
        let imageView = UIImageView(image: image)
        imageView.frame = window.bounds
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.backgroundColor = UIColor(white: 0, alpha: 0.6)
        spinner.layer.cornerRadius = 12
        spinner.frame = CGRect(x: window.bounds.midX - 22, y: window.bounds.midY - 22, width: 44, height: 44)
        spinner.startAnimating()
        imageView.addSubview(spinner)
        let controller = UIViewController()
        controller.view = imageView
        window.rootViewController = controller
        window.isHidden = false
        return window
    }

    /// Scrolls to the top, or partway down when the content is longer than the limit, then one
    /// viewport at a time to the end, keeping the newly revealed strip of each step. Lazy
    /// containers only build rows near the viewport, so each step reads its own components and
    /// elements. Strips span only the scroll view's width, so a sidebar beside it is drawn once.
    /// The first step supplies the bars above the content, the last the bars below.
    private static func fullLength(
        _ scrollView: UIScrollView, root: UIView, windows: [UIWindow], reference: UIWindow, format: UIGraphicsImageRendererFormat
    ) async -> (image: UIImage, scene: RawScene, visible: CGRect) {
        let space = reference as any UICoordinateSpace
        let bounds = reference.bounds
        let original = scrollView.contentOffset
        let showsIndicator = scrollView.showsVerticalScrollIndicator
        scrollView.showsVerticalScrollIndicator = false
        defer { scrollView.showsVerticalScrollIndicator = showsIndicator }
        // Above about 16k pixels Core Animation stops drawing an image, which would blank the editor.
        let limit = (16_000 / format.scale).rounded(.down)

        func band() -> ClosedRange<CGFloat> {
            let frame = scrollView.convert(scrollView.bounds, to: space)
            let inset = scrollView.adjustedContentInset
            let lower = max(frame.minY + inset.top, 0)
            return lower...max(min(frame.maxY - inset.bottom, bounds.height), lower + 1)
        }
        func maxOffset() -> CGFloat {
            scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        }
        func scroll(to y: CGFloat) {
            scrollView.setContentOffset(CGPoint(x: original.x, y: y), animated: false)
            scrollView.layoutIfNeeded()
        }
        func render(_ rect: CGRect, scrollViewOnTop: Bool) -> UIImage {
            UIGraphicsImageRenderer(bounds: rect, format: format).image { _ in
                for window in windows { window.drawHierarchy(in: window.convert(window.bounds, to: space), afterScreenUpdates: true) }
                if scrollViewOnTop { scrollView.drawHierarchy(in: scrollView.convert(scrollView.bounds, to: space), afterScreenUpdates: true) }
            }
        }
        func observe(shift: CGFloat, band: ClosedRange<CGFloat>, minimum: Duration = .milliseconds(80)) async -> ScrollStep {
            let found = await settledElements(in: [root], to: reference, minimum: minimum, scrollView: scrollView)
            var components: [RawScene.Component] = []
            collectMarkers(in: root, layer: 0, space: space, into: &components)
            return ScrollStep(
                shift: shift, band: band, components: components,
                content: found.filter(\.inScrollView).map(\.element), elements: found.filter { !$0.inScrollView }.map(\.element)
            )
        }

        // Content past the limit is left out, so a deep scroll position starts the capture partway
        // down with the part on screen near its middle.
        let reach = limit - bounds.height
        let lowest = -scrollView.adjustedContentInset.top
        if maxOffset() - lowest > reach, original.y - lowest > reach / 2 {
            scroll(to: min(original.y - reach / 2, maxOffset() - reach))
            try? await Task.sleep(for: .milliseconds(150))
        } else {
            // A large title grows when the list reaches the top, which changes the inset to scroll to.
            for _ in 0..<3 {
                let top = -scrollView.adjustedContentInset.top
                if abs(scrollView.contentOffset.y - top) < 0.5 { break }
                scroll(to: top)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        let top = scrollView.contentOffset.y
        let first = band()
        let columns = scrollView.convert(scrollView.bounds, to: space).intersection(bounds)
        var steps = [await observe(shift: 0, band: first, minimum: .milliseconds(120))]
        let firstImage = render(bounds, scrollViewOnTop: false)
        var strips: [(image: UIImage, y: CGFloat)] = []
        var covered = first.upperBound
        var offset = top
        while offset < maxOffset() - 0.5, covered < limit - (bounds.height - first.upperBound) {
            let current = band()
            scroll(to: min(offset + current.upperBound - current.lowerBound - 1, maxOffset()))
            let shift = scrollView.contentOffset.y - top
            let now = band()
            let start = max(covered - shift, now.lowerBound)
            guard scrollView.contentOffset.y > offset + 0.5, now.upperBound > start + 0.5 else { break }
            offset = scrollView.contentOffset.y
            let step = await observe(shift: shift, band: now)
            strips.append((render(CGRect(x: columns.minX, y: start, width: columns.width, height: now.upperBound - start), scrollViewOnTop: true), start + shift))
            steps.append(step)
            covered = min(now.upperBound + shift, limit - (bounds.height - first.upperBound))
        }
        // The bars over the bottom are translucent; drawing them from the last step shows the end
        // of the content behind them, as the real screen does when scrolled to the end.
        let lastImage = strips.isEmpty ? firstImage : render(bounds, scrollViewOnTop: false)
        scroll(to: original.y)

        let height = covered + bounds.height - first.upperBound
        let size = CGSize(width: bounds.width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            (scrollView.backgroundColor ?? .systemBackground).resolvedColor(with: reference.traitCollection).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.clip(to: CGRect(x: 0, y: 0, width: size.width, height: first.upperBound))
            firstImage.draw(at: .zero)
            context.cgContext.restoreGState()
            for strip in strips { strip.image.draw(at: CGPoint(x: columns.minX, y: strip.y)) }
            context.cgContext.clip(to: CGRect(x: 0, y: covered, width: size.width, height: height - covered))
            lastImage.draw(at: CGPoint(x: 0, y: covered - first.upperBound))
        }
        let visible = CGRect(x: 0, y: min(max(original.y - top, 0), height - bounds.height), width: bounds.width, height: bounds.height)
        return (image, Stitch.scene(screen: bounds.size, height: height, steps: steps), visible)
    }

    /// Polls until the element count holds steady. The first capture in a process stalls the main
    /// thread for about a second while UIKit loads its accessibility support; the bars' elements
    /// only appear after that, so a single early read would miss them.
    private static func settledElements(
        in layers: [UIView], to window: UIWindow, minimum: Duration, scrollView: UIScrollView? = nil
    ) async -> [Found] {
        let start = ContinuousClock.now
        var previous: [Found] = []
        while true {
            var elements: [Found] = []
            for (layer, view) in layers.enumerated() {
                collectElements(view, layer: layer, depth: 0, scrollView: scrollView, inScrollView: false, into: &elements)
            }
            elements = deduplicated(elements).map { found in
                let element = found.element
                let frame = window.convert(element.frame, from: window.screen.coordinateSpace)
                return Found(element: RawScene.Element(layer: element.layer, role: element.role, label: element.label, frame: frame), inScrollView: found.inScrollView)
            }
            let elapsed = ContinuousClock.now - start
            if elapsed > .seconds(3) || (elapsed > minimum && elements.count == previous.count) {
                return elements
            }
            previous = elements
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// The same element is often reachable twice, through a container's `accessibilityElements`
    /// and through the view tree, and titles are exposed as both text and header.
    private static func deduplicated(_ elements: [Found]) -> [Found] {
        var best: [String: Found] = [:]
        var order: [String] = []
        for found in elements {
            let element = found.element
            let key = "\(element.layer)|\(element.label)|\(element.frame.integral)"
            guard let existing = best[key] else {
                best[key] = found
                order.append(key)
                continue
            }
            if rank(element.role) < rank(existing.element.role) { best[key]?.element = element }
            if found.inScrollView { best[key]?.inScrollView = true }
        }
        return order.compactMap { best[$0] }
    }

    static func isSystemWindow(_ window: UIWindow) -> Bool {
        let name = String(describing: type(of: window))
        return name.contains("Keyboard") || name.contains("TextEffects")
    }

    private static func layerName(_ controller: UIViewController) -> String {
        switch controller.modalPresentationStyle {
        case .popover: "Popover"
        case .fullScreen, .overFullScreen: "Full-screen cover"
        default: controller is UIAlertController ? "Alert" : "Sheet"
        }
    }

    private static func collectMarkers(in view: UIView, layer: Int, space: any UICoordinateSpace, into components: inout [RawScene.Component]) {
        guard !view.isHidden, view.alpha > 0.01 else { return }
        if let marker = view as? MarkerView, let info = marker.info {
            components.append(RawScene.Component(
                id: info.id, parent: info.parent, layer: layer, name: info.name, source: info.source,
                frame: marker.convert(marker.bounds, to: space), data: info.payload.description
            ))
        }
        for subview in view.subviews { collectMarkers(in: subview, layer: layer, space: space, into: &components) }
    }

    private static func collectElements(
        _ object: NSObject, layer: Int, depth: Int, scrollView: UIScrollView?, inScrollView: Bool, into elements: inout [Found]
    ) {
        guard depth < 64 else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        let inScrollView = inScrollView || (scrollView != nil && object === scrollView)
        if object.isAccessibilityElement {
            var parts = [object.accessibilityLabel, object.accessibilityValue].compactMap { $0 }.filter { !$0.isEmpty }
            if parts.isEmpty, let placeholder = (object as? UITextField)?.placeholder, !placeholder.isEmpty { parts = [placeholder] }
            elements.append(Found(
                element: RawScene.Element(layer: layer, role: role(object.accessibilityTraits), label: parts.joined(separator: ", "), frame: object.accessibilityFrame),
                inScrollView: inScrollView
            ))
            return
        }
        let children = (object.accessibilityElements as? [NSObject]).flatMap { $0.isEmpty ? nil : $0 } ?? (object as? UIView)?.subviews ?? []
        for child in children {
            collectElements(child, layer: layer, depth: depth + 1, scrollView: scrollView, inScrollView: inScrollView, into: &elements)
        }
    }

    /// Ordered by how specific a role is: when an element has several traits, the first wins.
    private static let roles: [(UIAccessibilityTraits, String)] = [
        (.searchField, "Search field"), (textEntry, "Text field"), (.toggleButton, "Switch"), (.button, "Button"), (.link, "Link"),
        (.adjustable, "Adjustable"), (.keyboardKey, "Key"), (.header, "Header"), (.image, "Image"), (.tabBar, "Tab bar"),
        (.staticText, "Text"),
    ]

    /// UIKit's private trait for editable text, set on every `UITextField` and `UITextView`,
    /// including the ones in alerts and behind SwiftUI's `TextField`.
    private static let textEntry = UIAccessibilityTraits(rawValue: 1 << 18)

    private static func role(_ traits: UIAccessibilityTraits) -> String {
        roles.first { traits.contains($0.0) }?.1 ?? "Element"
    }

    private static func rank(_ role: String) -> Int {
        roles.firstIndex { $0.1 == role } ?? roles.count
    }

    /// Tab and navigation titles, such as `["Lists tab", "Lists", "Groceries"]`.
    private static func navigationTitles(in view: UIView) -> [String] {
        var tab: String?
        var titles: [String]?
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let bar = view as? UITabBar, tab == nil { tab = bar.selectedItem?.title }
            if let bar = view as? UINavigationBar, titles == nil, let items = bar.items, !items.isEmpty {
                titles = items.compactMap { $0.title ?? $0.backButtonTitle }.filter { !$0.isEmpty }
            }
            view.subviews.forEach(visit)
        }
        visit(view)
        return (tab.map { ["\($0) tab"] } ?? []) + (titles ?? [])
    }

    private static func environment(window: UIWindow, scene: UIWindowScene, navigation: [String]) -> [ContextEntry] {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "App"
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let traits = scene.traitCollection
        let device = UIDevice.current
        var entries = [
            ContextEntry(name: "App", value: name),
            ContextEntry(name: "Version", value: "\(version) (\(build)) · \(Bundle.main.bundleIdentifier ?? "?")"),
            ContextEntry(name: "Device", value: "\(deviceModel()) · \(device.systemName) \(device.systemVersion)"),
            ContextEntry(name: "Display", value: "\(Report.format(window.bounds.width)) × \(Report.format(window.bounds.height)) pt @\(Report.format(window.screen.scale))x · \(traits.userInterfaceStyle == .dark ? "dark" : "light") mode · text size \(traits.preferredContentSizeCategory.rawValue.replacingOccurrences(of: "UICTContentSizeCategory", with: ""))"),
            ContextEntry(name: "Captured", value: Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted))),
            ContextEntry(name: "Locale", value: Locale.current.identifier),
        ]
        if !navigation.isEmpty { entries.insert(ContextEntry(name: "Location", value: navigation.joined(separator: " › ")), at: 1) }
        return entries
    }

    private static func deviceModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? simulated) + " (Simulator)"
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
#endif
