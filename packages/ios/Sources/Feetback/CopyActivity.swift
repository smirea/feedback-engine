#if canImport(UIKit)
import UIKit

/// Writes the export to the pasteboard, one item per file, ready to paste into a chat with an agent.
final class CopyActivity: UIActivity {
    /// Pasteboard items, each keyed by type identifier.
    private let items: [[String: Any]]

    init(items: [[String: Any]]) {
        self.items = items
    }

    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("feetback.copy") }
    override var activityTitle: String? { "Copy Feedback" }
    override var activityImage: UIImage? { UIImage(systemName: "doc.on.clipboard") }
    override class var activityCategory: UIActivity.Category { .action }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

    override func perform() {
        UIPasteboard.general.setItems(items)
        activityDidFinish(true)
    }
}
#endif
