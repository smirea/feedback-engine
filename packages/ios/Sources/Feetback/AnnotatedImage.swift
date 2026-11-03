#if canImport(UIKit)
import UIKit

/// The image export: the screenshot with numbered boxes, each item's text and code location in a
/// card beside it, and the capture's environment, so the one file is enough on its own. Cards go
/// in the left column at their target's height; one only moves to the right column, under the
/// environment, when that keeps it much closer.
enum AnnotatedImage {
    private static let margin: CGFloat = 24
    private static let column: CGFloat = 280
    private static let gutter: CGFloat = 36
    private static let spacing: CGFloat = 12
    private static let badge: CGFloat = 20
    private static let padding: CGFloat = 10
    private static let rightColumnPenalty: CGFloat = 80
    /// Keeps a tall full-length capture shareable: about 160 MB of pixels at most.
    private static let pixelBudget: CGFloat = 40_000_000

    private static let secondary = UIColor(white: 0.42, alpha: 1)
    private static let primary = UIColor(white: 0.08, alpha: 1)

    private struct Card {
        let number: Int
        let color: UIColor
        let text: NSAttributedString
        let height: CGFloat
        let target: CGRect
        var origin = CGPoint.zero
        var isLeft = true
    }

    static func render(_ capture: Capture, items: [FeedbackItem]) -> UIImage {
        let shot = CGRect(x: margin + column + gutter, y: margin, width: capture.screen.width, height: capture.screen.height)
        let rightX = shot.maxX + gutter
        let width = rightX + column + margin
        let environment = environmentText(capture)
        let environmentHeight = measure(environment, width: column)

        var cards = items.enumerated().map { index, item in
            let node = capture.nodes[item.target]
            let text = NSMutableAttributedString(string: node.title + "\n", attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: secondary,
            ])
            if let source = capture.nearestComponent(from: item.target)?.source {
                text.append(NSAttributedString(string: source.description + "\n", attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 10.5, weight: .regular), .foregroundColor: secondary,
                ]))
            }
            text.append(NSAttributedString(string: item.text, attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: primary]))
            let height = max(measure(text, width: textWidth), badge) + padding * 2
            return Card(number: index + 1, color: Palette.uiColor(index), text: text, height: height, target: node.frame.offsetBy(dx: shot.minX, dy: shot.minY))
        }
        var nextLeft = margin
        var nextRight = margin + environmentHeight + spacing * 2
        for index in cards.indices.sorted(by: { cards[$0].target.midY < cards[$1].target.midY }) {
            let desired = max(cards[index].target.midY - cards[index].height / 2, margin)
            let left = max(desired, nextLeft), right = max(desired, nextRight)
            cards[index].isLeft = left <= right + rightColumnPenalty
            cards[index].origin = CGPoint(x: cards[index].isLeft ? margin : rightX, y: cards[index].isLeft ? left : right)
            if cards[index].isLeft { nextLeft = left + cards[index].height + spacing } else { nextRight = right + cards[index].height + spacing }
        }

        let size = CGSize(width: width, height: max(shot.maxY, nextLeft - spacing, nextRight - spacing) + margin)
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(capture.scale, (pixelBudget / (size.width * size.height)).squareRoot())
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.95, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let frame = UIBezierPath(roundedRect: shot, cornerRadius: 12)
            context.cgContext.saveGState()
            frame.addClip()
            UIImage(cgImage: capture.image, scale: capture.scale, orientation: .up).draw(in: shot)
            context.cgContext.restoreGState()
            UIColor(white: 0.8, alpha: 1).setStroke()
            frame.lineWidth = 1
            frame.stroke()

            for card in cards {
                let box = UIBezierPath(roundedRect: card.target.insetBy(dx: -1, dy: -1), cornerRadius: 4)
                box.lineWidth = 1.5
                box.setLineDash([6, 4], count: 2, phase: 0)
                card.color.withAlphaComponent(0.9).setStroke()
                box.stroke()

                let start = CGPoint(x: card.isLeft ? card.origin.x + column : card.origin.x, y: card.origin.y + padding + badge / 2)
                let end = CGPoint(
                    x: card.isLeft ? card.target.minX : card.target.maxX,
                    y: min(max(start.y, card.target.minY + 2), card.target.maxY - 2)
                )
                let line = UIBezierPath()
                line.move(to: start)
                line.addLine(to: end)
                line.lineWidth = 1.25
                card.color.withAlphaComponent(0.6).setStroke()
                line.stroke()
                card.color.setFill()
                UIBezierPath(ovalIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)).fill()

                let corner = CGPoint(
                    x: min(max(card.target.minX, shot.minX + badge / 2 + 2), shot.maxX - badge / 2 - 2),
                    y: min(max(card.target.minY, shot.minY + badge / 2 + 2), shot.maxY - badge / 2 - 2)
                )
                drawBadge(card.number, color: card.color, center: corner)
            }

            for card in cards {
                let rect = CGRect(origin: card.origin, size: CGSize(width: column, height: card.height))
                let background = UIBezierPath(roundedRect: rect, cornerRadius: 10)
                UIColor.white.setFill()
                background.fill()
                card.color.withAlphaComponent(0.45).setStroke()
                background.lineWidth = 1
                background.stroke()
                drawBadge(card.number, color: card.color, center: CGPoint(x: rect.minX + padding + badge / 2, y: rect.minY + padding + badge / 2))
                card.text.draw(
                    with: CGRect(x: rect.minX + padding * 2 + badge, y: rect.minY + padding, width: textWidth, height: card.height - padding * 2),
                    options: [.usesLineFragmentOrigin], context: nil
                )
            }

            environment.draw(with: CGRect(x: rightX, y: margin, width: column, height: environmentHeight), options: [.usesLineFragmentOrigin], context: nil)
        }
    }

    private static var textWidth: CGFloat { column - padding * 3 - badge }

    private static func environmentText(_ capture: Capture) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        let app = capture.environment.first { $0.name == "App" }?.value ?? "App"
        let text = NSMutableAttributedString(string: "Feedback: \(app)\n", attributes: [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold), .foregroundColor: primary, .paragraphStyle: paragraph,
        ])
        for entry in capture.environment where entry.name != "App" {
            text.append(NSAttributedString(string: entry.name.uppercased() + "\n", attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: secondary, .kern: 0.5,
            ]))
            text.append(NSAttributedString(string: entry.value + "\n", attributes: [
                .font: UIFont.systemFont(ofSize: 12.5), .foregroundColor: primary, .paragraphStyle: paragraph,
            ]))
        }
        return text
    }

    private static func measure(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height)
    }

    private static func drawBadge(_ number: Int, color: UIColor, center: CGPoint) {
        let circle = CGRect(x: center.x - badge / 2, y: center.y - badge / 2, width: badge, height: badge)
        color.setFill()
        UIBezierPath(ovalIn: circle).fill()
        UIColor.white.setStroke()
        let ring = UIBezierPath(ovalIn: circle)
        ring.lineWidth = 1.5
        ring.stroke()
        let label = NSAttributedString(string: "\(number)", attributes: [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.white])
        let size = label.size()
        label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }
}
#endif
