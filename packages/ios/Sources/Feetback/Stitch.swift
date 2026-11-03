import CoreGraphics
import Foundation

/// One position of the scroll view during a full-length capture, read in window coordinates.
struct ScrollStep {
    /// How far the content has scrolled since the first step.
    let shift: CGFloat
    /// The window's y range where content shows without bars over it.
    let band: ClosedRange<CGFloat>
    let components: [RawScene.Component]
    /// Elements reached through the scroll view, so they scroll with it.
    let content: [RawScene.Element]
    /// Elements reached some other way. SwiftUI can expose a scroll view's elements from outside
    /// it, so these are content or chrome depending on whether they stay put.
    let elements: [RawScene.Element]
}

enum Stitch {
    /// Lays every step out on one canvas `height` points tall. Content moves down by its step's
    /// shift, and content past the end of the stitched strips is dropped. Whatever stays put
    /// between the first step and another is chrome, such as bars and floating buttons: it is read
    /// from the first step, chrome below the content band moves to the bottom of the canvas, and
    /// containers spanning the band stretch with it.
    static func scene(screen: CGSize, height: CGFloat, steps: [ScrollStep]) -> RawScene {
        let extra = height - screen.height
        let viewport = steps[0].band
        let end = viewport.upperBound + extra
        func chrome(_ frame: CGRect) -> CGRect {
            if frame.minY >= viewport.upperBound - 0.5 { return frame.offsetBy(dx: 0, dy: extra) }
            if frame.minY <= viewport.lowerBound + 0.5, frame.maxY >= viewport.upperBound - 0.5 {
                return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + extra)
            }
            return frame
        }
        func same(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
        }
        func stays(_ component: RawScene.Component, in step: ScrollStep?) -> Bool {
            step?.components.contains { $0.id == component.id && same($0.frame, component.frame) } ?? false
        }
        func stays(_ element: RawScene.Element, in step: ScrollStep?) -> Bool {
            step?.elements.contains { $0.role == element.role && $0.label == element.label && same($0.frame, element.frame) } ?? false
        }

        var components: [RawScene.Component] = []
        var seen: Set<UUID> = []
        var elements: [RawScene.Element] = []
        var keys: Set<String> = []
        for (index, step) in steps.enumerated() {
            let reference = index == 0 ? steps.dropFirst().first : steps[0]
            for component in step.components where !seen.contains(component.id) {
                let isChrome = stays(component, in: reference)
                if isChrome, index > 0 { continue }
                let frame = isChrome ? chrome(component.frame) : component.frame.offsetBy(dx: 0, dy: step.shift)
                if !isChrome, frame.minY >= end { continue }
                seen.insert(component.id)
                components.append(component.moved(to: frame))
            }
            let found = step.content.map { (element: $0, isChrome: false) }
                + step.elements.map { (element: $0, isChrome: stays($0, in: reference)) }
            for (element, isChrome) in found {
                if index > 0, isChrome || element.frame.maxY < step.band.lowerBound || element.frame.minY > step.band.upperBound { continue }
                let frame = isChrome ? chrome(element.frame) : element.frame.offsetBy(dx: 0, dy: step.shift)
                if !isChrome, frame.minY >= end { continue }
                let key = "\(element.role)|\(element.label)|\([frame.minX, frame.minY, frame.width, frame.height].map { Int($0.rounded()) })"
                if keys.insert(key).inserted { elements.append(element.moved(to: frame)) }
            }
        }
        let size = CGSize(width: screen.width, height: height)
        return RawScene(screen: size, layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: size))], components: components, elements: elements)
    }
}

private extension RawScene.Component {
    func moved(to frame: CGRect) -> Self {
        .init(id: id, parent: parent, layer: layer, name: name, source: source, frame: frame, data: data)
    }
}

private extension RawScene.Element {
    func moved(to frame: CGRect) -> Self {
        .init(layer: layer, role: role, label: label, frame: frame)
    }
}
