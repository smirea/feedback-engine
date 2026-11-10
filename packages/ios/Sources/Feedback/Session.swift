import CoreGraphics
import Foundation
import Observation

@MainActor @Observable
final class Session {
    let capture: Capture
    private(set) var picked: Node.ID = 0
    /// How far up from the picked node the target sits: 0 is the picked node itself.
    private(set) var level = 0
    /// A new item's text. It survives visits to targets that already have feedback.
    var draft = ""
    /// Unsaved changes to the target's existing feedback, dropped when the target changes.
    private var revision: String?
    /// A short confirmation the editor shows over the screenshot, such as a finished post.
    var toast: Toast?
    private(set) var annotations = Annotations()
    var items: [FeedbackItem] { annotations.items }
    /// What a tap picks while the text ends in `@`, and how far up from it the reference sits.
    private var referencePick: Node.ID?
    private(set) var referenceLevel = 0
    /// Every item that was in a completed share.
    var shared: Set<FeedbackItem> = []
    /// Closing asks first when it would lose these, or a draft.
    var unshared: [FeedbackItem] { items.filter { !shared.contains($0) } }

    init(capture: Capture) {
        self.capture = capture
    }

    var path: [Node] { capture.path(from: picked) }
    var target: Node { path[min(level, path.count - 1)] }
    var similar: [Node.ID] { target.kind == .screen || isReferencing ? [] : capture.similar(to: target.id) }

    /// The item on the target itself. Its parent's or child's feedback belongs to that level.
    var editing: FeedbackItem? { items.first { $0.target == target.id } }

    var text: String {
        get { editing.map { revision ?? $0.text } ?? draft }
        set {
            if editing != nil { revision = newValue } else { draft = newValue }
            if !isReferencing { referencePick = nil }
        }
    }

    /// Typing `@` at the start of a word makes the next tap pick a node to reference instead of
    /// moving the target. Typing anything else leaves the mode.
    var isReferencing: Bool {
        let text = text
        guard text.last == "@" else { return false }
        return text.dropLast().last.map(\.isWhitespace) ?? true
    }

    var referencePath: [Node] {
        guard isReferencing, let referencePick else { return [] }
        return capture.path(from: referencePick)
    }

    var referenceTarget: Node? {
        let path = referencePath
        return path.isEmpty ? nil : path[min(referenceLevel, path.count - 1)]
    }

    /// The references the items and the text being typed name, so their boxes show while typing.
    var visibleReferences: [Reference] { annotations.references(in: items.map(\.text) + [text]) }

    func colorIndex(of node: Node.ID) -> Int { annotations.colorIndex(of: node) }

    func stepReference(to level: Int) {
        referenceLevel = level
    }

    /// Replaces the `@` with the reference target's token.
    func insertReference() {
        guard let node = referenceTarget else { return }
        let reference = annotations.reference(node)
        text = String(text.dropLast()) + reference.token + " "
    }

    var canSubmit: Bool {
        let text = trimmed(text)
        return !text.isEmpty && text != editing?.text
    }

    /// Closing would lose a new item's text or changes to an existing one.
    var isTyping: Bool {
        !trimmed(draft).isEmpty || (editing != nil && canSubmit)
    }

    /// A tap inside an item's box selects that item, so its feedback comes back. Tapping the same
    /// spot again drills down to the most specific node; the chain still reaches every level.
    /// Screens and layers cover everything, so their feedback never captures a tap.
    func pick(at point: CGPoint) {
        let id = capture.hitTest(point)
        if isReferencing {
            referencePick = id
            referenceLevel = 0
            return
        }
        let flagged = Set(items.map(\.target))
        let level = capture.path(from: id).firstIndex { flagged.contains($0.id) && $0.kind != .screen && $0.kind != .layer } ?? 0
        let drillsDown = id == picked && self.level == level
        retarget {
            picked = id
            self.level = drillsDown ? 0 : level
        }
    }

    func select(_ id: Node.ID) {
        retarget {
            picked = id
            level = 0
        }
    }

    func step(to level: Int) {
        retarget { self.level = level }
    }

    /// Unsaved changes stay while the same node remains the target, such as a second tap on it.
    private func retarget(_ change: () -> Void) {
        let before = target.id
        change()
        if target.id != before { revision = nil }
        if !isReferencing { referencePick = nil }
    }

    func submit() {
        let text = trimmed(text)
        guard !text.isEmpty else { return }
        if editing == nil { draft = "" }
        annotations.submit(text, on: target.id)
        select(0)
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    func remove(_ id: FeedbackItem.ID) {
        annotations.remove(id)
    }

    var json: String { Report.json(capture, annotations) }
    var compactJSON: String { Report.json(capture, annotations, pretty: false) }
}

/// Tapping a toast with a link opens it, such as the task a post created.
struct Toast: Equatable {
    let text: String
    var link: URL?
}
