import CoreGraphics
import Foundation

struct CodeLocation: Hashable, Sendable {
    let file: String
    let line: Int

    var description: String { "\(file):\(line)" }
}

struct Node: Identifiable, Hashable, Sendable {
    typealias ID = Int

    enum Kind: Hashable, Sendable {
        case screen
        case layer
        case component(CodeLocation)
        case element(role: String)
    }

    let id: ID
    let parent: ID?
    let layer: Int
    let kind: Kind
    let name: String
    /// Visible text of an element: its accessibility label and value.
    let label: String?
    let frame: CGRect
    let data: String?

    var source: CodeLocation? {
        if case .component(let source) = kind { source } else { nil }
    }

    var title: String {
        guard let label, !label.isEmpty else { return name }
        return "\(name) \"\(label)\""
    }
}

struct ContextEntry: Hashable, Sendable {
    let name: String
    let value: String
}

struct Capture: @unchecked Sendable {
    let date: Date
    let screen: CGSize
    let scale: CGFloat
    let image: CGImage
    /// Indexed by `Node.ID`; node 0 is the whole screen.
    let nodes: [Node]
    let environment: [ContextEntry]
    let context: [ContextEntry]

    var root: Node { nodes[0] }

    /// The node and its ancestors, from the node itself up to the screen.
    func path(from id: Node.ID) -> [Node] {
        var path: [Node] = []
        var current: Node.ID? = id
        while let id = current {
            path.append(nodes[id])
            current = nodes[id].parent
        }
        return path
    }

    /// Picks the most specific node under a point: only the topmost layer covering the point
    /// competes, so a sheet hides the screen it covers.
    func hitTest(_ point: CGPoint) -> Node.ID {
        let layers = nodes.filter { $0.kind == .layer && $0.frame.contains(point) }
        let layer = layers.map(\.layer).max() ?? 0
        let depth = depths
        let candidates = nodes.filter { $0.layer == layer && $0.frame.contains(point) && $0.kind != .screen }
        let best = candidates.min { a, b in
            let areaA = a.frame.width * a.frame.height, areaB = b.frame.width * b.frame.height
            return areaA != areaB ? areaA < areaB : depth[a.id] > depth[b.id]
        }
        return best?.id ?? 0
    }

    func nearestComponent(from id: Node.ID) -> Node? {
        path(from: id).first { $0.source != nil }
    }

    var depths: [Int] {
        var depths = Array(repeating: 0, count: nodes.count)
        for node in nodes { if let parent = node.parent { depths[node.id] = depths[parent] + 1 } }
        return depths
    }
}

struct FeedbackItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let target: Node.ID
    var text: String

    init(id: UUID = UUID(), target: Node.ID, text: String) {
        self.id = id
        self.target = target
        self.text = text
    }
}
