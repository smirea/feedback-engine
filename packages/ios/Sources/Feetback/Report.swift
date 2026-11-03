import CoreGraphics
import Foundation

/// The text half of a shared report. Item numbers match the boxes on the annotated image.
enum Report {
    static func markdown(_ capture: Capture, items: [FeedbackItem]) -> String {
        var out: [String] = []
        let app = capture.environment.first { $0.name == "App" }?.value ?? "App"
        out.append("# Feedback: \(app)")
        out.append("")
        out.append("The attached image is a screenshot with a numbered box around each item's target.")
        if capture.visible.height < capture.screen.height - 0.5 {
            out.append("It shows the scrolling content at full length. The part on screen when feedback started is y \(format(capture.visible.minY)) to \(format(capture.visible.maxY)).")
        }
        out.append("Frames are in points from the screenshot's top-left corner (\(format(capture.screen.width)) × \(format(capture.screen.height)) pt).")
        out.append("Code locations point at the `.feedback(...)` call inside each component.")
        out.append("")
        for entry in capture.environment { out.append("- \(entry.name): \(entry.value)") }

        var components: [Node.ID] = []
        var itemsUsing: [Node.ID: [Int]] = [:]
        for (index, item) in items.enumerated() {
            let path = capture.path(from: item.target)
            let target = path[0]
            out.append("")
            out.append("## \(index + 1). \(target.title)")
            out.append("")
            out.append(contentsOf: item.text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" })
            out.append("")
            out.append("- Path: " + path.reversed().map(crumb).joined(separator: " › "))
            out.append("- Frame: \(format(target.frame))")
            if case .element(let role) = target.kind {
                out.append("- Element: \(role)" + (target.label.map { " \"\($0)\"" } ?? ""))
            }
            if let component = capture.nearestComponent(from: item.target), let source = component.source {
                out.append("- Code: `\(source.description)` (\(component.name))")
            }
            for node in path where node.source != nil {
                if !components.contains(node.id) { components.append(node.id) }
                itemsUsing[node.id, default: []].append(index + 1)
            }
        }

        let withData = components.compactMap { id -> (node: Node, source: CodeLocation, data: String)? in
            let node = capture.nodes[id]
            guard let source = node.source, let data = node.data else { return nil }
            return (node, source, data)
        }
        if !withData.isEmpty {
            out.append("")
            out.append("## Component data")
            for entry in withData {
                out.append("")
                let numbers = itemsUsing[entry.node.id, default: []].map(String.init).joined(separator: ", ")
                out.append("### \(entry.node.name) · `\(entry.source.description)` · item\(numbers.contains(",") ? "s" : "") \(numbers)")
                out.append("```")
                out.append(entry.data)
                out.append("```")
            }
        }

        if !capture.context.isEmpty {
            out.append("")
            out.append("## App context")
            for entry in capture.context {
                out.append("")
                out.append("### \(entry.name)")
                out.append("```")
                out.append(entry.value)
                out.append("```")
            }
        }

        out.append("")
        out.append("## Screen outline")
        out.append("")
        out.append("```")
        out.append(outline(capture))
        out.append("```")
        return out.joined(separator: "\n")
    }

    static func outline(_ capture: Capture) -> String {
        let depths = capture.depths
        return capture.nodes.map { node in
            let indent = String(repeating: "  ", count: depths[node.id])
            let source = node.source.map { "  \($0.description)" } ?? ""
            return "\(indent)\(node.title)  [\(format(node.frame))]\(source)"
        }.joined(separator: "\n")
    }

    private static func crumb(_ node: Node) -> String {
        node.source.map { "\(node.name) (`\($0.description)`)" } ?? node.title
    }

    static func format(_ rect: CGRect) -> String {
        "x \(format(rect.minX)), y \(format(rect.minY)), \(format(rect.width)) × \(format(rect.height))"
    }

    static func format(_ value: CGFloat) -> String {
        guard value.isFinite else { return "\(value)" }
        return value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(format: "%.1f", Double(value))
    }
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    /// The annotated screenshot plus the markdown report.
    case image
    /// Everything in the report as one JSON document, without the screenshot.
    case json

    var id: Self { self }
    var title: String { self == .image ? "Image" : "JSON" }
}

extension Report {
    static func json(_ capture: Capture, items: [FeedbackItem]) -> String {
        let document = JSONDocument(
            app: capture.environment.first { $0.name == "App" }?.value ?? "App",
            captured: capture.date,
            size: .init(width: rounded(capture.screen.width), height: rounded(capture.screen.height)),
            visible: .init(capture.visible),
            environment: capture.environment.map { .init(name: $0.name, value: $0.value) },
            items: items.enumerated().map { index, item in
                let target = capture.nodes[item.target]
                return .init(
                    number: index + 1, text: item.text, target: item.target, title: target.title,
                    path: capture.path(from: item.target).reversed().map(\.id),
                    code: capture.nearestComponent(from: item.target)?.source?.description
                )
            },
            context: capture.context.map { .init(name: $0.name, value: $0.value) },
            nodes: capture.nodes.map(JSONDocument.TreeNode.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        // Plain structs of strings and numbers, with non-finite numbers handled above, cannot fail to encode.
        return String(decoding: try! encoder.encode(document), as: UTF8.self)
    }

    fileprivate static func rounded(_ value: CGFloat) -> Double { (Double(value) * 10).rounded() / 10 }
}

private struct JSONDocument: Encodable {
    struct Entry: Encodable {
        let name: String
        let value: String
    }

    struct Size: Encodable {
        let width: Double
        let height: Double
    }

    struct Rect: Encodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: CGRect) {
            x = Report.rounded(rect.minX)
            y = Report.rounded(rect.minY)
            width = Report.rounded(rect.width)
            height = Report.rounded(rect.height)
        }
    }

    struct Item: Encodable {
        let number: Int
        let text: String
        let target: Int
        let title: String
        /// Node ids from the screen down to the target.
        let path: [Int]
        let code: String?
    }

    struct TreeNode: Encodable {
        let id: Int
        let parent: Int?
        let layer: Int
        let kind: String
        let name: String
        let label: String?
        let frame: Rect
        let source: String?
        let data: String?

        init(_ node: Node) {
            id = node.id
            parent = node.parent
            layer = node.layer
            kind = switch node.kind {
            case .screen: "screen"
            case .layer: "layer"
            case .component: "component"
            case .element: "element"
            }
            name = node.name
            label = node.label
            frame = Rect(node.frame)
            source = node.source?.description
            data = node.data
        }
    }

    let app: String
    let captured: Date
    let size: Size
    let visible: Rect
    let environment: [Entry]
    let items: [Item]
    let context: [Entry]
    let nodes: [TreeNode]
}
