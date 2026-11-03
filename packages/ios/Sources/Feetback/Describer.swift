import Foundation
import SwiftUI

/// Lets `.feedback(self)` report a wrapper's current value instead of the wrapper itself.
/// `nil` means the value can't be read safely.
protocol FeedbackUnwrappable {
    var feedbackValue: Any? { get }
}

extension Binding: FeedbackUnwrappable {
    var feedbackValue: Any? { wrappedValue }
}

extension Bindable: FeedbackUnwrappable {
    var feedbackValue: Any? { wrappedValue }
}

/// State traps when read before SwiftUI installs its storage, which happens for a view value
/// that never made it into a hierarchy. The storage shows up as a non-nil `_location`.
extension State: FeedbackUnwrappable {
    var feedbackValue: Any? { Describer.isInstalled(self) ? wrappedValue : nil }
}

/// What `@State private var` expands to in the Swift 6.2+ SDKs, reflected as `__name`.
extension LazyState: FeedbackUnwrappable {
    var feedbackValue: Any? { Describer.isInstalled(self) ? wrappedValue : nil }
}

enum Describer {
    static let limit = 1500

    /// Describes a view's stored properties. Of the property wrappers, only `@State`, `@Binding`
    /// and `@Bindable` are read: `@Environment` and the rest hold app-wide objects, not this view's data.
    static func describeProperties(of view: Any) -> String? {
        let lines = Mirror(reflecting: view).children.compactMap { child -> String? in
            guard var label = child.label else { return nil }
            var value = child.value
            if label.hasPrefix("_") {
                guard let wrapped = (value as? FeedbackUnwrappable)?.feedbackValue else { return nil }
                label = String(label.drop { $0 == "_" })
                value = wrapped
            }
            if isOpaque(value) { return nil }
            return "\(label): \(describe(value))"
        }
        return lines.isEmpty ? nil : truncate(lines.joined(separator: "\n"))
    }

    static func isInstalled(_ state: Any) -> Bool {
        guard let location = Mirror(reflecting: state).children.first(where: { $0.label == "_location" })?.value else { return false }
        return Mirror(reflecting: location).children.first != nil
    }

    static func describe(_ value: Any, limit: Int = limit) -> String {
        truncate(render(value, depth: 0), limit: limit)
    }

    private static func render(_ value: Any, depth: Int) -> String {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .class, depth < 2 else { return String(describing: value) }
        let fields = mirror.children.compactMap { child -> String? in
            guard var label = child.label, !label.hasPrefix("_$"), !isOpaque(child.value) else { return nil }
            if label.hasPrefix("_") { label.removeFirst() }
            return "\(label): \(render(child.value, depth: depth + 1))"
        }
        return "\(typeName(value))(\(fields.joined(separator: ", ")))"
    }

    private static func isOpaque(_ value: Any) -> Bool {
        let type = String(reflecting: Swift.type(of: value))
        return type.contains("->") || type.hasPrefix("SwiftUI.") || type.hasPrefix("Swift.Optional<SwiftUI.")
    }

    static func typeName(_ value: Any) -> String {
        String(describing: Swift.type(of: value))
    }

    private static func truncate(_ text: String, limit: Int = limit) -> String {
        text.count > limit ? text.prefix(limit) + "… (truncated)" : text
    }
}
