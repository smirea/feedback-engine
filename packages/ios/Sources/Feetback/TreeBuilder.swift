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
        var entries: [Entry] = [Entry(parent: nil, layer: 0, kind: .screen, name: "Screen", label: nil, frame: screen, data: nil)]
        var layerEntry = [0]
        for (index, layer) in scene.layers.enumerated().dropFirst() {
            guard usable(layer.frame) else {
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
            parentOf[index] = smallest(in: components.indices, containing: component.frame, layer: component.layer, of: components, excluding: index)
        }
        breakCycles(&parentOf)

        var keep = Array(repeating: false, count: components.count)
        for (index, component) in components.enumerated() where component.frame.intersects(screen) {
            var current: Int? = index
            while let node = current, !keep[node] {
                keep[node] = true
                current = parentOf[node]
            }
        }

        var componentEntry: [Int: Int] = [:]
        for (index, component) in components.enumerated() where keep[index] {
            componentEntry[index] = entries.count
            entries.append(Entry(
                parent: nil, layer: component.layer, kind: .component(component.source),
                name: component.name, label: nil, frame: component.frame, data: component.data
            ))
        }
        for (index, entry) in componentEntry {
            entries[entry].parent = parentOf[index].flatMap { componentEntry[$0] } ?? layerEntry[components[index].layer]
        }

        let kept = componentEntry.keys.map { $0 }
        for element in scene.elements where usable(element.frame) && element.frame.intersects(screen) {
            let container = smallest(in: kept, containing: element.frame.insetBy(dx: 1, dy: 1), layer: element.layer, of: components, excluding: nil)
                ?? smallest(in: kept, containing: CGRect(origin: CGPoint(x: element.frame.midX, y: element.frame.midY), size: .zero), layer: element.layer, of: components, excluding: nil)
            entries.append(Entry(
                parent: container.flatMap { componentEntry[$0] } ?? layerEntry[element.layer],
                layer: element.layer, kind: .element(role: element.role), name: element.role,
                label: element.label, frame: element.frame, data: nil
            ))
        }

        return ordered(entries)
    }

    /// Accessibility frames can be empty, infinite, or `.null` for elements that aren't laid out.
    private static func usable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isEmpty && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite && abs($0) < 100_000 }
    }

    private static func smallest(
        in candidates: some Sequence<Int>, containing frame: CGRect, layer: Int, of components: [RawScene.Component], excluding: Int?
    ) -> Int? {
        let area = frame.width * frame.height
        return candidates
            .filter { index in
                let candidate = components[index]
                guard index != excluding, candidate.layer == layer, candidate.frame.contains(frame) else { return false }
                return excluding == nil || candidate.frame.width * candidate.frame.height > area
            }
            .min { components[$0].frame.width * components[$0].frame.height < components[$1].frame.width * components[$1].frame.height }
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
    private static func ordered(_ entries: [Entry]) -> [Node] {
        var children = Array(repeating: [Int](), count: entries.count)
        for (index, entry) in entries.enumerated() { if let parent = entry.parent { children[parent].append(index) } }
        var nodes: [Node] = []
        func visit(_ index: Int, parent: Node.ID?) {
            let entry = entries[index]
            let id = nodes.count
            nodes.append(Node(
                id: id, parent: parent, layer: entry.layer, kind: entry.kind, name: entry.name,
                label: entry.label, frame: entry.frame, data: entry.data
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
