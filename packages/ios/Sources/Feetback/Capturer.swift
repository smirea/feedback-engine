#if canImport(UIKit)
import UIKit

@MainActor
enum Capturer {
    private struct LayerSource {
        let view: UIView
        let name: String
        /// Root views of extra windows, such as toasts, often span the whole screen while showing
        /// a small banner, so their layer covers only what they actually contain.
        let fitsContent: Bool
    }

    /// The screenshot and tags are read synchronously, at the moment of the trigger. Accessibility
    /// elements come after: SwiftUI only builds them once automation accessibility is on.
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
        for (index, window) in windows.enumerated() {
            var controller = window.rootViewController
            var isRoot = true
            while let current = controller {
                controller = current.presentedViewController
                defer { isRoot = false }
                guard let view = current.viewIfLoaded, view.window != nil else { continue }
                let name = sources.isEmpty ? "Screen" : layerName(current)
                sources.append(LayerSource(view: view, name: name, fitsContent: index > 0 && isRoot))
                let titles = navigationTitles(in: view)
                navigation += sources.count == 1 ? titles : ["(\(name))"] + titles
            }
        }

        var raw = RawScene(screen: bounds.size, layers: [], components: [], elements: [])
        for (layer, source) in sources.enumerated() {
            collectMarkers(in: source.view, layer: layer, space: space, into: &raw.components)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = reference.screen.scale
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            for window in windows { window.drawHierarchy(in: window.convert(window.bounds, to: space), afterScreenUpdates: false) }
        }
        guard let cgImage = image.cgImage else { return nil }

        raw.elements = await AutomationAccessibility.whileEnabled {
            await settledElements(in: sources.map(\.view), to: reference)
        }
        raw.layers = sources.enumerated().map { layer, source in
            guard layer > 0 else { return RawScene.Layer(name: source.name, frame: bounds) }
            guard source.fitsContent else { return RawScene.Layer(name: source.name, frame: source.view.convert(source.view.bounds, to: space)) }
            let frames = raw.components.filter { $0.layer == layer }.map(\.frame) + raw.elements.filter { $0.layer == layer }.map(\.frame)
            return RawScene.Layer(name: source.name, frame: frames.reduce(CGRect.null) { $0.union($1) })
        }
        if raw.layers.isEmpty { raw.layers.append(RawScene.Layer(name: "Screen", frame: bounds)) }

        return Capture(
            date: .now,
            screen: bounds.size,
            scale: reference.screen.scale,
            image: cgImage,
            nodes: TreeBuilder.build(raw),
            environment: environment(window: reference, scene: scene, navigation: navigation),
            context: context
        )
    }

    /// Polls until the element count holds steady. The first capture in a process stalls the main
    /// thread for about a second while UIKit loads its accessibility support; the bars' elements
    /// only appear after that, so a single early read would miss them.
    private static func settledElements(in layers: [UIView], to window: UIWindow) async -> [RawScene.Element] {
        let start = ContinuousClock.now
        var previous: [RawScene.Element] = []
        while true {
            var elements: [RawScene.Element] = []
            for (layer, view) in layers.enumerated() { collectElements(view, layer: layer, depth: 0, into: &elements) }
            elements = deduplicated(elements).map { element in
                RawScene.Element(layer: element.layer, role: element.role, label: element.label, frame: window.convert(element.frame, from: window.screen.coordinateSpace))
            }
            let elapsed = ContinuousClock.now - start
            if elapsed > .seconds(3) || (elapsed > .milliseconds(120) && elements.count == previous.count) {
                return elements
            }
            previous = elements
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// The same element is often reachable twice, through a container's `accessibilityElements`
    /// and through the view tree, and titles are exposed as both text and header.
    private static func deduplicated(_ elements: [RawScene.Element]) -> [RawScene.Element] {
        var best: [String: RawScene.Element] = [:]
        var order: [String] = []
        for element in elements {
            let key = "\(element.layer)|\(element.label)|\(element.frame.integral)"
            guard let existing = best[key] else {
                best[key] = element
                order.append(key)
                continue
            }
            if rank(element.role) < rank(existing.role) { best[key] = element }
        }
        return order.compactMap { best[$0] }
    }

    private static func isSystemWindow(_ window: UIWindow) -> Bool {
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

    private static func collectElements(_ object: NSObject, layer: Int, depth: Int, into elements: inout [RawScene.Element]) {
        guard depth < 64 else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        if object.isAccessibilityElement {
            let parts = [object.accessibilityLabel, object.accessibilityValue].compactMap { $0 }.filter { !$0.isEmpty }
            elements.append(RawScene.Element(
                layer: layer, role: role(object.accessibilityTraits), label: parts.joined(separator: ", "),
                frame: object.accessibilityFrame
            ))
            return
        }
        if let children = object.accessibilityElements as? [NSObject], !children.isEmpty {
            for child in children { collectElements(child, layer: layer, depth: depth + 1, into: &elements) }
        } else if let view = object as? UIView {
            for subview in view.subviews { collectElements(subview, layer: layer, depth: depth + 1, into: &elements) }
        }
    }

    /// Ordered by how specific a role is: when an element has several traits, the first wins.
    private static let roles: [(UIAccessibilityTraits, String)] = [
        (.button, "Button"), (.link, "Link"), (.searchField, "Search field"), (.adjustable, "Adjustable"),
        (.header, "Header"), (.image, "Image"), (.tabBar, "Tab bar"), (.staticText, "Text"),
    ]

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
