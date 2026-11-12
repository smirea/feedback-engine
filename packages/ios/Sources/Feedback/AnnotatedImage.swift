import CoreGraphics

/// Where the image export puts each item's card. A card sits in the left column, as level with its
/// target as the cards above it allow. It moves to the right column when that makes its line to
/// the target at least `rightColumnPenalty` points shorter, as for a button at the trailing edge.
/// The environment then takes the first gap in the right column that is tall enough, from the top.
enum CardLayout {
    static let margin: CGFloat = 24
    static let column: CGFloat = 280
    static let gutter: CGFloat = 36
    static let spacing: CGFloat = 12
    static let badge: CGFloat = 20
    static let padding: CGFloat = 10
    static let rightColumnPenalty: CGFloat = 80

    struct Card: Equatable {
        var isLeft: Bool
        var origin: CGPoint
    }

    struct Layout: Equatable {
        let shot: CGRect
        let cards: [Card]
        let environment: CGPoint
        let size: CGSize
    }

    /// `targets` are frames in the capture; the layout's frames are in the image.
    static func place(targets: [CGRect], heights: [CGFloat], screen: CGSize, environmentHeight: CGFloat) -> Layout {
        let shot = CGRect(x: margin + column + gutter, y: margin, width: screen.width, height: screen.height)
        let rightX = shot.maxX + gutter
        let targets = targets.map { $0.offsetBy(dx: shot.minX, dy: shot.minY) }
        var cards = targets.map { _ in Card(isLeft: true, origin: .zero) }
        var nextLeft = margin, nextRight = margin
        for index in targets.indices.sorted(by: { (targets[$0].midY, $0) < (targets[$1].midY, $1) }) {
            let desired = max(targets[index].midY - heights[index] / 2, margin)
            let left = Card(isLeft: true, origin: CGPoint(x: margin, y: max(desired, nextLeft)))
            let right = Card(isLeft: false, origin: CGPoint(x: rightX, y: max(desired, nextRight)))
            let card = length(left, to: targets[index]) - length(right, to: targets[index]) >= rightColumnPenalty ? right : left
            cards[index] = card
            if card.isLeft { nextLeft = card.origin.y + heights[index] + spacing } else { nextRight = card.origin.y + heights[index] + spacing }
        }

        var environmentY = margin
        for index in cards.indices.filter({ !cards[$0].isLeft }).sorted(by: { cards[$0].origin.y < cards[$1].origin.y }) {
            if environmentY + environmentHeight + spacing * 2 <= cards[index].origin.y { break }
            environmentY = max(environmentY, cards[index].origin.y + heights[index] + spacing * 2)
        }
        let height = max(shot.maxY, nextLeft - spacing, nextRight - spacing, environmentY + environmentHeight) + margin
        return Layout(
            shot: shot, cards: cards, environment: CGPoint(x: rightX, y: environmentY),
            size: CGSize(width: rightX + column + margin, height: height)
        )
    }

    /// From the card's badge to the nearest side of the target, at the badge's height when the
    /// target spans it.
    static func line(_ card: Card, to target: CGRect) -> (start: CGPoint, end: CGPoint) {
        let start = CGPoint(x: card.isLeft ? card.origin.x + column : card.origin.x, y: card.origin.y + padding + badge / 2)
        let end = CGPoint(x: card.isLeft ? target.minX : target.maxX, y: min(max(start.y, target.minY + 2), target.maxY - 2))
        return (start, end)
    }

    private static func length(_ card: Card, to target: CGRect) -> CGFloat {
        let (start, end) = line(card, to: target)
        return hypot(end.x - start.x, end.y - start.y)
    }
}

#if canImport(UIKit)
import UIKit

/// The image export: the screenshot with numbered boxes, each item's text and code location in a
/// card beside it, a tagged box for each referenced node, and the capture's environment, so the
/// one file is enough on its own.
enum AnnotatedImage {
    private static let column = CardLayout.column
    private static let badge = CardLayout.badge
    private static let padding = CardLayout.padding
    /// Keeps a tall full-length capture shareable: about 160 MB of pixels at most.
    private static let pixelBudget: CGFloat = 40_000_000

    private static let secondary = UIColor(white: 0.42, alpha: 1)
    private static let primary = UIColor(white: 0.08, alpha: 1)

    static func render(_ capture: Capture, _ annotations: Annotations) -> UIImage {
        let environment = environmentText(capture)
        let environmentHeight = measure(environment, width: column)
        let cards = annotations.items.map { item in
            let node = capture.nodes[item.target]
            let text = NSMutableAttributedString()
            for segment in annotations.segments(item.text) {
                if let reference = segment.reference {
                    let color = Palette.uiColor(annotations.colorIndex(of: reference.target))
                    text.append(NSAttributedString(string: "\u{00A0}\(segment.text)\u{00A0}", attributes: [
                        .font: UIFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: UIColor.white, .backgroundColor: color,
                    ]))
                } else {
                    text.append(NSAttributedString(string: segment.text, attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: primary]))
                }
            }
            let footer = NSMutableAttributedString(string: node.title, attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: primary,
            ])
            if let source = capture.nearestComponent(from: item.target)?.source {
                footer.append(NSAttributedString(string: "\n" + source.description, attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: primary,
                ]))
            }
            let body = max(measure(text, width: textWidth), badge) + padding * 2
            let footerHeight = measure(footer, width: column - padding * 2) + footerPadding * 2
            let color = Palette.uiColor(annotations.colorIndex(of: item.target))
            return (
                number: annotations.number(of: item.target), color: color, text: text, footer: footer,
                body: body, height: body + footerHeight, frame: node.frame
            )
        }
        let layout = CardLayout.place(targets: cards.map(\.frame), heights: cards.map(\.height), screen: capture.screen, environmentHeight: environmentHeight)
        let shot = layout.shot
        let size = layout.size

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

            for (card, placement) in zip(cards, layout.cards) {
                let target = card.frame.offsetBy(dx: shot.minX, dy: shot.minY)
                let box = UIBezierPath(roundedRect: target.insetBy(dx: -1, dy: -1), cornerRadius: 4)
                box.lineWidth = 1.5
                box.setLineDash([6, 4], count: 2, phase: 0)
                card.color.withAlphaComponent(0.9).setStroke()
                box.stroke()

                let (start, end) = CardLayout.line(placement, to: target)
                let line = UIBezierPath()
                line.move(to: start)
                line.addLine(to: end)
                line.lineWidth = 1.25
                card.color.withAlphaComponent(0.6).setStroke()
                line.stroke()
                card.color.setFill()
                UIBezierPath(ovalIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)).fill()

                let corner = CGPoint(
                    x: min(max(target.minX, shot.minX + badge / 2 + 2), shot.maxX - badge / 2 - 2),
                    y: min(max(target.minY, shot.minY + badge / 2 + 2), shot.maxY - badge / 2 - 2)
                )
                drawBadge(card.number, color: card.color, center: corner)
            }

            let flagged = Set(annotations.items.map(\.target))
            for reference in annotations.used {
                let color = Palette.uiColor(annotations.colorIndex(of: reference.target))
                let target = capture.nodes[reference.target].frame.offsetBy(dx: shot.minX, dy: shot.minY)
                if !flagged.contains(reference.target) {
                    let box = UIBezierPath(roundedRect: target.insetBy(dx: -1, dy: -1), cornerRadius: 4)
                    box.lineWidth = 1.5
                    box.setLineDash([6, 4], count: 2, phase: 0)
                    color.withAlphaComponent(0.9).setStroke()
                    box.stroke()
                }
                drawTag(reference.tag, color: color, corner: CGPoint(x: target.maxX, y: target.minY), within: shot)
            }

            for (card, placement) in zip(cards, layout.cards) {
                let rect = CGRect(origin: placement.origin, size: CGSize(width: column, height: card.height))
                let background = UIBezierPath(roundedRect: rect, cornerRadius: 10)
                let border = tint(card.color)
                UIColor.white.setFill()
                background.fill()
                context.cgContext.saveGState()
                background.addClip()
                border.setFill()
                context.fill(CGRect(x: rect.minX, y: rect.minY + card.body, width: column, height: card.height - card.body))
                context.cgContext.restoreGState()
                border.setStroke()
                background.lineWidth = 1
                background.stroke()
                drawBadge(card.number, color: card.color, center: CGPoint(x: rect.minX + padding + badge / 2, y: rect.minY + padding + badge / 2))
                card.text.draw(
                    with: CGRect(x: rect.minX + padding * 2 + badge, y: rect.minY + padding, width: textWidth, height: card.body - padding * 2),
                    options: [.usesLineFragmentOrigin], context: nil
                )
                card.footer.draw(
                    with: CGRect(x: rect.minX + padding, y: rect.minY + card.body + footerPadding, width: column - padding * 2, height: card.height - card.body - footerPadding * 2),
                    options: [.usesLineFragmentOrigin], context: nil
                )
            }

            environment.draw(with: CGRect(origin: layout.environment, size: CGSize(width: column, height: environmentHeight)), options: [.usesLineFragmentOrigin], context: nil)
        }
    }

    private static var textWidth: CGFloat { column - padding * 3 - badge }
    private static let footerPadding: CGFloat = 6

    /// The card's border and its footer's fill: the item's color at 45% over white, opaque so the
    /// two match exactly.
    private static func tint(_ color: UIColor) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(red: red * 0.45 + 0.55, green: green * 0.45 + 0.55, blue: blue * 0.45 + 0.55, alpha: 1)
    }

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

    /// A reference's `@N`, in a square centered on the box's top-right corner.
    private static func drawTag(_ tag: String, color: UIColor, corner: CGPoint, within shot: CGRect) {
        let label = NSAttributedString(string: tag, attributes: [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.white])
        let size = label.size()
        let width = max(size.width + 8, badge)
        let center = CGPoint(
            x: min(max(corner.x, shot.minX + width / 2 + 2), shot.maxX - width / 2 - 2),
            y: min(max(corner.y, shot.minY + badge / 2 + 2), shot.maxY - badge / 2 - 2)
        )
        let rect = CGRect(x: center.x - width / 2, y: center.y - badge / 2, width: width, height: badge)
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 3).fill()
        UIColor.white.setStroke()
        let ring = UIBezierPath(roundedRect: rect, cornerRadius: 3)
        ring.lineWidth = 1.5
        ring.stroke()
        label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
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
