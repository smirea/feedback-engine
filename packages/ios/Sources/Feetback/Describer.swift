import Foundation
import SwiftUI

/// A value that Feetback describes as `feedbackValue` in its place, at any depth of a component's data.
///
/// Conform your own property wrappers so `.feedback(self)` reports what they hold:
///
/// ```swift
/// extension Observe: FeedbackRepresentable {
///     var feedbackValue: Any { wrappedValue }
/// }
/// ```
public protocol FeedbackRepresentable {
    var feedbackValue: Any { get }
}

/// The SwiftUI wrappers Feetback reads. `nil` means the value can't be read safely.
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

#if compiler(>=6.4)
/// What `@State private var` expands to from the Xcode 27 SDK on, reflected as `__name`.
extension LazyState: FeedbackUnwrappable {
    var feedbackValue: Any? { Describer.isInstalled(self) ? wrappedValue : nil }
}
#endif

enum Describer {
    static let limit = 1500
    private static let maxDepth = 3
    private static let maxElements = 10

    /// Describes a view's stored properties. Of the property wrappers, only `@State`, `@Binding`, `@Bindable`
    /// and `FeedbackRepresentable` ones are read: `@Environment` and the rest hold app-wide objects, not this view's data.
    static func describeProperties(of view: Any) -> String? {
        let lines = fields(of: Mirror(reflecting: view), depth: 0).map { "\($0.label): \($0.text)" }
        return lines.isEmpty ? nil : truncate(lines.joined(separator: "\n"))
    }

    static func isInstalled(_ state: Any) -> Bool {
        guard let location = Mirror(reflecting: state).children.first(where: { $0.label == "_location" })?.value else { return false }
        return Mirror(reflecting: location).children.first != nil
    }

    static func describe(_ value: Any, limit: Int = limit) -> String {
        truncate(render(value, depth: 0) ?? typeName(value), limit: limit)
    }

    static func typeName(_ value: Any) -> String {
        let name = String(describing: Swift.type(of: value))
        return String(name.prefix { $0 != "<" })
    }

    /// `nil` hides the value: it is a closure, SwiftUI or Combine plumbing, unreadable, or a struct made only of those.
    /// Strings are quoted below the top level so they stand apart from the punctuation around them.
    private static func render(_ value: Any, depth: Int) -> String? {
        guard let value = unwrapped(value), !isOpaque(value) else { return nil }
        if let number = number(value) { return number }
        let mirror = Mirror(reflecting: value)
        let deep = depth >= maxDepth && mirror.children.first != nil
        switch mirror.displayStyle {
        case .optional:
            guard let some = mirror.children.first else { return "nil" }
            return render(some.value, depth: depth)
        case .collection, .set:
            if deep { return "[…]" }
            return "[\(list(mirror.children.map(\.value), depth: depth + 1))]"
        case .dictionary:
            if deep { return "[…]" }
            let pairs = mirror.children.map { pair -> String in
                let parts = Mirror(reflecting: pair.value).children.map { render($0.value, depth: depth + 1) ?? "…" }
                return parts.joined(separator: ": ")
            }
            return pairs.isEmpty ? "[:]" : "[\(limited(pairs))]"
        case .tuple:
            if deep { return "(…)" }
            let parts = mirror.children.compactMap { child -> String? in
                guard let text = render(child.value, depth: depth + 1) else { return nil }
                guard let label = child.label, !label.hasPrefix(".") else { return text }
                return "\(label): \(text)"
            }
            return "(\(parts.joined(separator: ", ")))"
        case .enum:
            guard !(value is CustomStringConvertible), let payload = mirror.children.first, let label = payload.label else { return String(describing: value) }
            let text = deep ? "…" : render(payload.value, depth: depth + 1) ?? "…"
            return text.hasPrefix("(") ? label + text : "\(label)(\(text))"
        case .struct where value is CustomStringConvertible:
            return String(describing: value)
        case .struct, .class:
            if deep { return "\(typeName(value))(…)" }
            let fields = fields(of: mirror, depth: depth + 1)
            if fields.isEmpty && mirror.children.first != nil { return nil }
            return "\(typeName(value))(\(fields.map { "\($0.label): \($0.text)" }.joined(separator: ", ")))"
        default:
            return depth > 0 && value is any StringProtocol ? String(reflecting: value) : String(describing: value)
        }
    }

    /// A leading underscore marks a property wrapper's storage in a struct and plain storage in an `@Observable` class.
    private static func fields(of mirror: Mirror, depth: Int) -> [(label: String, text: String)] {
        mirror.children.compactMap { child in
            guard var label = child.label, !label.hasPrefix("_$") else { return nil }
            if label.hasPrefix("_") {
                guard mirror.displayStyle == .class || child.value is FeedbackUnwrappable || child.value is FeedbackRepresentable else { return nil }
                label = String(label.drop { $0 == "_" })
            }
            return render(child.value, depth: depth).map { (label, $0) }
        }
    }

    private static func unwrapped(_ value: Any) -> Any? {
        if let value = value as? FeedbackRepresentable { return value.feedbackValue }
        if let value = value as? FeedbackUnwrappable { return value.feedbackValue }
        return value
    }

    private static func list(_ values: [Any], depth: Int) -> String {
        limited(values.compactMap { render($0, depth: depth) })
    }

    private static func limited(_ parts: [String]) -> String {
        guard parts.count > maxElements else { return parts.joined(separator: ", ") }
        return (parts.prefix(maxElements) + ["… \(parts.count - maxElements) more"]).joined(separator: ", ")
    }

    /// Binary floating point turns 72.575 into 72.57477920000001, so floats keep 3 decimals, or 3 significant
    /// digits below 1, switching to exponent notation where that would take more than 15 decimals.
    private static func number(_ value: Any) -> String? {
        let double: Double
        switch value {
        case let value as Double: double = value
        case let value as Float: double = Double(value)
        case let value as CGFloat: double = Double(value)
        default: return nil
        }
        guard double.isFinite else { return String(describing: double) }
        let magnitude = abs(double)
        let decimals = magnitude >= 1 || magnitude == 0 ? 3 : 2 - Int(log10(magnitude).rounded(.down))
        if decimals > 15 { return String(format: "%.3g", double) }
        var text = String(format: "%.\(decimals)f", double)
        if text.contains(".") {
            text = String(text.reversed().drop { $0 == "0" }.reversed())
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    private static func isOpaque(_ value: Any) -> Bool {
        let type = String(reflecting: Swift.type(of: value))
        return type.contains("->") || ["SwiftUI.", "Combine.", "Swift.Optional<SwiftUI.", "Swift.Optional<Combine."].contains { type.hasPrefix($0) }
    }

    private static func truncate(_ text: String, limit: Int = limit) -> String {
        text.count > limit ? text.prefix(limit) + "… (truncated)" : text
    }
}
