#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

/// Puts the image and the text on the pasteboard as two separate items, so pasting into a chat
/// with an agent brings both.
final class CopyActivity: UIActivity {
    private let image: UIImage
    private let text: String

    init(image: UIImage, text: String) {
        self.image = image
        self.text = text
    }

    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("feetback.copy") }
    override var activityTitle: String? { "Copy Feedback" }
    override var activityImage: UIImage? { UIImage(systemName: "doc.on.clipboard") }
    override class var activityCategory: UIActivity.Category { .action }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

    override func perform() {
        var items: [[String: Any]] = [[UTType.utf8PlainText.identifier: text]]
        if let png = image.pngData() { items.insert([UTType.png.identifier: png], at: 0) }
        UIPasteboard.general.setItems(items)
        activityDidFinish(true)
    }
}
#endif
