#if canImport(UIKit)
import UIKit

/// Writes the export to the pasteboard as one item, ready to paste into a chat with an agent.
final class CopyActivity: UIActivity {
    /// One pasteboard item, keyed by type identifier.
    private let item: [String: Any]

    init(item: [String: Any]) {
        self.item = item
    }

    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("feetback.copy") }
    override var activityTitle: String? { "Copy Feedback" }
    override var activityImage: UIImage? { UIImage(systemName: "doc.on.clipboard") }
    override class var activityCategory: UIActivity.Category { .action }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

    override func perform() {
        UIPasteboard.general.setItems([item])
        activityDidFinish(true)
    }
}
#endif
