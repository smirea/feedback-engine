import CoreGraphics
import Foundation

/// One position of the scroll view during a full-length capture, read in window coordinates.
struct ScrollStep {
    /// How far the content has moved up the window since the first step.
    let shift: CGFloat
    /// The window's y range where content shows without bars or pinned section footers over it.
    /// After the first step it also starts below a pinned section header.
    var band: ClosedRange<CGFloat>
    let components: [RawScene.Component]
    /// Components inside the scroll view, so they scroll with it.
    let scrolling: Set<UUID>
    /// Elements reached through the scroll view, so they scroll with it.
    let content: [RawScene.Element]
    /// Elements reached some other way. SwiftUI can expose a scroll view's elements from outside
    /// it, so these are content or chrome depending on whether they stay put.
    let elements: [RawScene.Element]
}

enum Stitch {
    /// Lays every step out on one canvas `height` points tall. Content moves down by its step's
    /// shift. Each step keeps only what is inside the scroll view and inside its band, so nothing
    /// hidden under the bars or a pinned header or footer shows up, and content past the end of the
    /// stitched strips is dropped. `viewport` is the first step's band without its pinned footer.
    /// Whatever stays put between the first step and another is chrome, such as bars and floating
    /// buttons: it is read from the first step, and chrome below the content band moves to the
    /// bottom of the canvas. A component of the first step outside the scroll view that spans the
    /// band and ends on screen holds the scroll view, even when its frame changed while scrolling,
    /// so it stretches with the band. `layers` are read at the first step and stretch or move the
    /// same way, so a sheet whose list is captured grows with it and keeps covering the screen.
    static func scene(screen: CGSize, height: CGFloat, viewport: ClosedRange<CGFloat>, layers: [RawScene.Layer], steps: [ScrollStep]) -> RawScene {
        let extra = height - screen.height
        let end = viewport.upperBound + extra
        func spans(_ frame: CGRect) -> Bool {
            frame.minY <= viewport.lowerBound + 0.5 && frame.maxY >= viewport.upperBound - 0.5 && frame.maxY <= screen.height + 0.5
        }
        func chrome(_ frame: CGRect) -> CGRect {
            if frame.minY >= viewport.upperBound - 0.5 { return frame.offsetBy(dx: 0, dy: extra) }
            if spans(frame) { return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + extra) }
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
        func outside(_ frame: CGRect, _ band: ClosedRange<CGFloat>) -> Bool {
            frame.maxY <= band.lowerBound + 0.5 || frame.minY >= band.upperBound - 0.5
        }

        var components: [RawScene.Component] = []
        var seen: Set<UUID> = []
        var elements: [RawScene.Element] = []
        var keys: Set<String> = []
        for (index, step) in steps.enumerated() {
            let reference = index == 0 ? steps.dropFirst().first : steps[0]
            for component in step.components where !seen.contains(component.id) {
                let isScrolling = step.scrolling.contains(component.id)
                // A pinned footer stays put too, but outside the first band it hides content instead of
                // being a bar, and it shows up again in its own place, which can be where it was pinned.
                let isHidden = isScrolling && outside(component.frame, steps[0].band)
                let isChrome = (stays(component, in: reference) && !isHidden) || (index == 0 && !isScrolling && spans(component.frame))
                if isChrome, index > 0 { continue }
                if !isChrome, isScrolling, outside(component.frame, step.band) { continue }
                let frame = isChrome ? chrome(component.frame) : component.frame.offsetBy(dx: 0, dy: step.shift)
                if !isChrome, frame.minY >= end - 0.5 { continue }
                seen.insert(component.id)
                components.append(component.moved(to: frame))
            }
            let found = step.content.map { (element: $0, isChrome: false, isScrolling: true) }
                + step.elements.map { (element: $0, isChrome: stays($0, in: reference), isScrolling: false) }
            for (element, isChrome, isScrolling) in found {
                if isChrome ? index > 0 : (isScrolling || index > 0) && outside(element.frame, step.band) { continue }
                let frame = isChrome ? chrome(element.frame) : element.frame.offsetBy(dx: 0, dy: step.shift)
                if !isChrome, frame.minY >= end - 0.5 { continue }
                let key = "\(element.layer)|\(element.role)|\(element.label)|\([frame.minX, frame.minY, frame.width, frame.height].map { Int($0.rounded()) })"
                if keys.insert(key).inserted { elements.append(element.moved(to: frame)) }
            }
        }
        let layers = layers.map { RawScene.Layer(name: $0.name, frame: chrome($0.frame)) }
        return RawScene(screen: CGSize(width: screen.width, height: height), layers: layers, components: components, elements: elements)
    }

    /// Where a capture that reaches its height limit should end: the lowest y from `floor` down
    /// to `limit` that no frame crosses, so the last row is whole. `nil` when frames cover the
    /// whole range.
    static func cut(atMost limit: CGFloat, after floor: CGFloat, frames: [CGRect]) -> CGFloat? {
        let candidates = [limit] + frames.flatMap { [$0.minY, $0.maxY] }.filter { $0 > floor && $0 < limit }
        return candidates.sorted(by: >).first { y in !frames.contains { $0.minY < y - 0.5 && $0.maxY > y + 0.5 } }
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

