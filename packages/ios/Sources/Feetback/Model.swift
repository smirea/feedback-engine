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
    /// Size of the whole capture. Taller than the device screen when a scroll view was captured
    /// at full length.
    let screen: CGSize
    /// The part of the capture that was on screen when it was taken.
    let visible: CGRect
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

    /// Nodes that play the same part as `id` in sibling components: the same button in every
    /// row of a list. Siblings are components with the same tag as the node's nearest component
    /// and the same enclosing component, so rows wrapped one by one in a `NavigationLink` still
    /// match. Inside each, the node is found by walking down the same kinds at the same positions.
    func similar(to id: Node.ID) -> [Node.ID] {
        let path = path(from: id)
        guard let anchor = path.firstIndex(where: { $0.source != nil }) else { return [] }
        let component = path[anchor]
        let context = enclosing(component.id)
        let children = children
        let steps = path[..<anchor].map { node in
            (kind: node.kind, index: children[node.parent!].filter { nodes[$0].kind == node.kind }.firstIndex(of: node.id)!)
        }
        return nodes.filter { $0.id != component.id && $0.kind == component.kind && enclosing($0.id) == context }.compactMap { sibling in
            steps.reversed().reduce(Optional(sibling.id)) { current, step in
                guard let current else { return nil }
                let matching = children[current].filter { nodes[$0].kind == step.kind }
                return step.index < matching.count ? matching[step.index] : nil
            }
        }
    }

    /// The nearest component, layer, or screen above a node.
    private func enclosing(_ id: Node.ID) -> Node.ID? {
        path(from: id).dropFirst().first { $0.source != nil || $0.kind == .layer || $0.kind == .screen }?.id
    }

    func nearestComponent(from id: Node.ID) -> Node? {
        path(from: id).first { $0.source != nil }
    }

    var children: [[Node.ID]] {
        var children = Array(repeating: [Node.ID](), count: nodes.count)
        for node in nodes { if let parent = node.parent { children[parent].append(node.id) } }
        return children
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
