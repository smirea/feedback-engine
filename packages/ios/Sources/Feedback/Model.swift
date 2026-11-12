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
    /// The topmost navigation title, or the selected tab's when no bar has one.
    var screenName: String? = nil

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
    /// row of a list. Siblings are components with the same tag as a component on the node's path
    /// and the same enclosing component, so rows wrapped one by one in a `NavigationLink` still
    /// match. Inside each, the node is found by walking down the same kinds at the same positions.
    /// The nearest component with siblings wins, so a tagged view inside a repeated row matches
    /// its copies in the other rows.
    func similar(to id: Node.ID) -> [Node.ID] {
        let path = path(from: id)
        let children = children
        for anchor in path.indices where path[anchor].source != nil {
            let component = path[anchor]
            let context = enclosing(component.id)
            let steps = path[..<anchor].map { node in
                (kind: node.kind, index: children[node.parent!].filter { nodes[$0].kind == node.kind }.firstIndex(of: node.id)!)
            }
            let matches = nodes.filter { $0.id != component.id && $0.kind == component.kind && enclosing($0.id) == context }.compactMap { sibling in
                steps.reversed().reduce(Optional(sibling.id)) { current, step in
                    guard let current else { return nil }
                    let matching = children[current].filter { nodes[$0].kind == step.kind }
                    return step.index < matching.count ? matching[step.index] : nil
                }
            }
            if !matches.isEmpty { return matches }
        }
        return []
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

/// A node that feedback text points at with a token such as `@1_Dialog`.
struct Reference: Hashable, Sendable {
    let number: Int
    let target: Node.ID
    let token: String

    var tag: String { "@\(number)" }
}

/// Everything a share exports besides the capture. Items and references share one count: a node
/// takes the next number and color the first time it is flagged or referenced, and keeps them for
/// the capture, so no two boxes show the same number. Removing an item leaves its number unused,
/// since tokens in other texts may still name it.
struct Annotations: Sendable {
    private(set) var items: [FeedbackItem] = []
    private(set) var references: [Reference] = []
    private var marked: [Node.ID] = []

    func colorIndex(of node: Node.ID) -> Int { marked.firstIndex(of: node) ?? marked.count }

    /// The node's number, or the one it would take next.
    func number(of node: Node.ID) -> Int { colorIndex(of: node) + 1 }

    /// Updates the target's item, or adds one.
    mutating func submit(_ text: String, on target: Node.ID) {
        if let index = items.firstIndex(where: { $0.target == target }) {
            items[index].text = text
        } else {
            items.append(FeedbackItem(target: target, text: text))
            mark(target)
        }
    }

    mutating func remove(_ id: FeedbackItem.ID) {
        items.removeAll { $0.id == id }
    }

    /// The node's reference. A node referenced again gets the same one.
    mutating func reference(_ node: Node) -> Reference {
        if let reference = references.first(where: { $0.target == node.id }) { return reference }
        let words = node.name.split { !($0.isLetter || $0.isNumber) }.joined(separator: "_")
        mark(node.id)
        let number = number(of: node.id)
        let reference = Reference(number: number, target: node.id, token: "@\(number)_\(words.isEmpty ? "Node" : words)")
        references.append(reference)
        return reference
    }

    private mutating func mark(_ node: Node.ID) {
        if !marked.contains(node) { marked.append(node) }
    }

    /// The references some item's text names, by number.
    var used: [Reference] { references(in: items.map(\.text)) }

    func references(in texts: [String]) -> [Reference] {
        let tokens = Set(texts.flatMap { segments($0).compactMap(\.reference?.token) })
        return references.filter { tokens.contains($0.token) }.sorted { $0.number < $1.number }
    }

    /// The text split into plain runs and reference tokens. A token followed by more letters is
    /// plain text, since it names nothing.
    func segments(_ text: String) -> [(text: String, reference: Reference?)] {
        var segments: [(text: String, reference: Reference?)] = []
        func plain(_ text: Substring) {
            guard !text.isEmpty else { return }
            if let last = segments.last, last.reference == nil {
                segments[segments.count - 1].text += text
            } else {
                segments.append((String(text), nil))
            }
        }
        var rest = text[...]
        while let match = rest.firstMatch(of: /@\d+_\w+/) {
            if let reference = references.first(where: { $0.token == match.output }) {
                plain(rest[..<match.range.lowerBound])
                segments.append((reference.token, reference))
            } else {
                plain(rest[..<match.range.upperBound])
            }
            rest = rest[match.range.upperBound...]
        }
        plain(rest)
        return segments
    }
}
