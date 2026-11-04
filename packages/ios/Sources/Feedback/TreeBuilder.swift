import CoreGraphics
import Foundation

/// What the capturer reads off the live app, before it becomes a `Capture` tree.
struct RawScene {
    struct Layer {
        let name: String
        let frame: CGRect
    }

    struct Component {
        let id: UUID
        let parent: UUID?
        let layer: Int
        let name: String
        let source: CodeLocation
        let frame: CGRect
        let data: String?
    }

    struct Element {
        let layer: Int
        let role: String
        let label: String
        let frame: CGRect
    }

    let screen: CGSize
    /// Index 0 is the base screen; later layers are presented on top of earlier ones.
    var layers: [Layer]
    var components: [Component]
    var elements: [Element]
}

enum TreeBuilder {
    private struct Entry {
        var parent: Int?
        let layer: Int
        let kind: Node.Kind
        let name: String
        let label: String?
        let frame: CGRect
        let data: String?
    }

    static func build(_ scene: RawScene) -> [Node] {
        let screen = CGRect(origin: .zero, size: scene.screen)
        let covers = scene.layers.enumerated().dropFirst().filter { usable($0.element.frame) }.map { (layer: $0.offset, frame: $0.element.frame) }
        /// No tap can reach what a higher layer covers completely, so the tree leaves it out.
        func shown(_ frame: CGRect, layer: Int) -> Bool {
            frame.intersects(screen) && !covers.contains { $0.layer > layer && $0.frame.contains(frame) }
        }

        var entries: [Entry] = [Entry(parent: nil, layer: 0, kind: .screen, name: "Screen", label: nil, frame: screen, data: nil)]
        var layerEntry = [0]
        for (index, layer) in scene.layers.enumerated().dropFirst() {
            guard usable(layer.frame), shown(layer.frame, layer: index) else {
                layerEntry.append(0)
                continue
            }
            layerEntry.append(entries.count)
            entries.append(Entry(parent: 0, layer: index, kind: .layer, name: layer.name, label: nil, frame: layer.frame, data: nil))
        }

        let components = scene.components.filter { usable($0.frame) }
        let byID = Dictionary(components.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var parentOf: [Int?] = components.map { component in
            if let parent = component.parent, let index = byID[parent], components[index].layer == component.layer { return index }
            return nil
        }
        for (index, component) in components.enumerated() where parentOf[index] == nil {
            parentOf[index] = smallest(
                in: components.indices.filter { area(components[$0].frame) > area(component.frame) },
                containing: component.frame, layer: component.layer, of: components, depth: { _ in 0 }
            )
        }
        breakCycles(&parentOf)
        var depthOf: [Int: Int] = [:]
        func depth(_ index: Int) -> Int {
            if let known = depthOf[index] { return known }
            let value = parentOf[index].map { depth($0) + 1 } ?? 0
            depthOf[index] = value
            return value
        }

        var keep = Array(repeating: false, count: components.count)
        for (index, component) in components.enumerated() where shown(component.frame, layer: component.layer) {
            var current: Int? = index
            while let node = current, !keep[node] {
                keep[node] = true
                current = parentOf[node]
            }
        }

        var componentEntry: [Int: Int] = [:]
        let kept = components.indices.filter { keep[$0] }
        for index in kept {
            let component = components[index]
            componentEntry[index] = entries.count
            entries.append(Entry(
                parent: nil, layer: component.layer, kind: .component(component.source),
                name: component.name, label: nil, frame: component.frame, data: component.data
            ))
        }
        for index in kept {
            entries[componentEntry[index]!].parent = parentOf[index].flatMap { componentEntry[$0] } ?? layerEntry[components[index].layer]
        }

        for element in scene.elements where usable(element.frame) && shown(element.frame, layer: element.layer) {
            let container = container(of: element, in: kept, of: components, depth: depth)
            entries.append(Entry(
                parent: container.flatMap { componentEntry[$0] } ?? layerEntry[element.layer],
                layer: element.layer, kind: .element(role: element.role), name: element.role,
                label: element.label, frame: element.frame, data: nil
            ))
        }

        wrapInElements(&entries, components: kept.map { componentEntry[$0]! })
        return ordered(entries, clippedTo: screen)
    }

    /// The smallest component that contains the element. An element can stick out a little past
    /// the component it belongs to, such as text with a shadow or negative padding, so a smaller
    /// component holding its centre and most of its area wins over a larger one that contains it
    /// completely. A component that a button or link encloses with room to spare is never its
    /// container: the button wraps the component.
    private static func container(of element: RawScene.Element, in candidates: [Int], of components: [RawScene.Component], depth: (Int) -> Int) -> Int? {
        let frame = element.frame
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        let around = candidates.filter { index in
            let candidate = components[index].frame
            let encloses = wrappingRoles.contains(element.role) && frame.insetBy(dx: -1, dy: -1).contains(candidate)
                && (frame.width > candidate.width + 2 || frame.height > candidate.height + 2)
            return candidate.contains(centre) && !encloses
        }
        return smallest(in: around.filter { area(components[$0].frame.intersection(frame)) >= area(frame) * 0.75 }, containing: centre, layer: element.layer, of: components, depth: depth)
            ?? smallest(in: around, containing: centre, layer: element.layer, of: components, depth: depth)
    }

    /// Controls that merge their content into one accessibility element.
    private static let wrappingRoles: Set<String> = ["Button", "Link", "Switch"]

    /// A button or link merges its content into one accessibility element, so a component inside a
    /// `NavigationLink` shows up next to the link's element instead of under it. Moving the
    /// component under the smallest sibling element that encloses it restores the real nesting.
    private static func wrapInElements(_ entries: inout [Entry], components: [Int]) {
        let elements = entries.indices.filter {
            if case .element(let role) = entries[$0].kind { wrappingRoles.contains(role) } else { false }
        }
        for index in components {
            let component = entries[index]
            let wrapper = elements
                .filter { element in
                    let candidate = entries[element]
                    return candidate.parent == component.parent && candidate.layer == component.layer
                        && candidate.frame.insetBy(dx: -1, dy: -1).contains(component.frame) && area(candidate.frame) > area(component.frame)
                }
                .min { area(entries[$0].frame) < area(entries[$1].frame) }
            if let wrapper { entries[index].parent = wrapper }
        }
    }

    /// Accessibility frames can be empty, infinite, or `.null` for elements that aren't laid out.
    private static func usable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isEmpty && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite && abs($0) < 100_000 }
    }

    private static func area(_ frame: CGRect) -> CGFloat { frame.isNull ? 0 : frame.width * frame.height }

    /// Among candidates of equal size, the deepest wins, so content lands in the innermost of two
    /// components that share a frame, such as a card wrapping another tagged view.
    private static func smallest(
        in candidates: [Int], containing point: CGPoint, layer: Int, of components: [RawScene.Component], depth: (Int) -> Int
    ) -> Int? {
        smallest(in: candidates, containing: CGRect(origin: point, size: .zero), layer: layer, of: components, depth: depth)
    }

    private static func smallest(
        in candidates: [Int], containing frame: CGRect, layer: Int, of components: [RawScene.Component], depth: (Int) -> Int
    ) -> Int? {
        candidates
            .filter { components[$0].layer == layer && components[$0].frame.contains(frame) }
            .min { a, b in
                let areaA = area(components[a].frame), areaB = area(components[b].frame)
                if areaA != areaB { return areaA < areaB }
                return depth(a) != depth(b) ? depth(a) > depth(b) : a > b
            }
    }

    private static func breakCycles(_ parentOf: inout [Int?]) {
        for start in parentOf.indices {
            var seen: Set<Int> = [start]
            var current = start
            while let parent = parentOf[current] {
                if seen.contains(parent) {
                    parentOf[current] = nil
                    break
                }
                seen.insert(parent)
                current = parent
            }
        }
    }

    /// Renumbers depth-first in reading order, so every parent precedes its children.
    /// Frames are clipped to the capture, so nothing reports a position outside the image.
    private static func ordered(_ entries: [Entry], clippedTo bounds: CGRect) -> [Node] {
        var children = Array(repeating: [Int](), count: entries.count)
        for (index, entry) in entries.enumerated() { if let parent = entry.parent { children[parent].append(index) } }
        var nodes: [Node] = []
        func visit(_ index: Int, parent: Node.ID?) {
            let entry = entries[index]
            let id = nodes.count
            nodes.append(Node(
                id: id, parent: parent, layer: entry.layer, kind: entry.kind, name: entry.name,
                label: entry.label, frame: entry.frame.intersects(bounds) ? entry.frame.intersection(bounds) : entry.frame, data: entry.data
            ))
            let sorted = children[index].sorted { a, b in
                let fa = entries[a].frame, fb = entries[b].frame
                if entries[a].layer != entries[b].layer { return entries[a].layer < entries[b].layer }
                return abs(fa.minY - fb.minY) > 0.5 ? fa.minY < fb.minY : fa.minX < fb.minX
            }
            for child in sorted { visit(child, parent: id) }
        }
        visit(0, parent: nil)
        return nodes
    }
}
