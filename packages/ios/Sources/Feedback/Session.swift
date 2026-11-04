import CoreGraphics
import Foundation
import Observation

@MainActor @Observable
final class Session {
    let capture: Capture
    private(set) var picked: Node.ID = 0
    /// How far up from the picked node the target sits: 0 is the picked node itself.
    var level = 0
    var draft = ""
    /// A short confirmation the editor shows over the screenshot, such as a finished post.
    var toast: Toast?
    private(set) var items: [FeedbackItem] = []
    /// Every item that was in a completed share.
    var shared: Set<FeedbackItem> = []
    /// Closing asks first when it would lose these, or a draft.
    var unshared: [FeedbackItem] { items.filter { !shared.contains($0) } }

    init(capture: Capture) {
        self.capture = capture
    }

    var path: [Node] { capture.path(from: picked) }
    var target: Node { path[min(level, path.count - 1)] }
    var similar: [Node.ID] { target.kind == .screen ? [] : capture.similar(to: target.id) }

    func pick(at point: CGPoint) {
        select(capture.hitTest(point))
    }

    func select(_ id: Node.ID) {
        picked = id
        level = 0
    }

    func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        items.append(FeedbackItem(target: target.id, text: text))
        draft = ""
        select(0)
    }

    func remove(_ id: FeedbackItem.ID) {
        items.removeAll { $0.id == id }
    }

    var json: String { Report.json(capture, items: items) }
    var compactJSON: String { Report.json(capture, items: items, pretty: false) }
}

/// Tapping a toast with a link opens it, such as the task a post created.
struct Toast: Equatable {
    let text: String
    var link: URL?
}
