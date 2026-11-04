import CoreGraphics
import Foundation

/// The JSON export: everything the capture knows except the image.
enum Report {
    static func format(_ value: CGFloat) -> String {
        guard value.isFinite else { return "\(value)" }
        return value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(format: "%.1f", Double(value))
    }
}

extension Report {
    static func json(_ capture: Capture, items: [FeedbackItem], pretty: Bool = true) -> String {
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
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
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
