import CoreGraphics

/// Where the image export puts each item's card. Cards go in the column whose path to the target
/// costs least: its length, `rightColumnPenalty` points for the right column, and `crossingPenalty`
/// for each other box or earlier path it crosses, as level with the target as the cards above
/// allow. The environment sits at the top of the right column, and right-column cards start below
/// it. When one column holds the environment and every card with no crossing and no taller image,
/// the image drops the other column and keeps only a margin on that side. A tall capture is cut
/// half the height that was on screen below the lowest box or card, and never shorter than that
/// height, and `shot` is the part that is drawn.
enum CardLayout {
    static let margin: CGFloat = 24
    static let column: CGFloat = 280
    static let gutter: CGFloat = 36
    static let spacing: CGFloat = 12
    static let badge: CGFloat = 20
    static let padding: CGFloat = 10
    static let rightColumnPenalty: CGFloat = 80
    static let crossingPenalty: CGFloat = 500

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

    struct Curve: Equatable {
        let start, control1, control2, end: CGPoint
    }

    private enum Columns { case both, left, right }

    /// `targets` and `references` are frames in the capture; the layout's frames are in the image.
    static func place(
        targets: [CGRect], heights: [CGFloat], screen: CGSize, environmentHeight: CGFloat, viewport: CGFloat, references: [CGRect] = []
    ) -> Layout {
        let build = { (columns: Columns) in
            arrange(columns, targets: targets, heights: heights, screen: screen, environmentHeight: environmentHeight, viewport: viewport, references: references)
        }
        let both = build(.both)
        let single = [build(.left), build(.right)]
            .filter { $0.crossings == 0 && $0.layout.size.height <= both.layout.size.height }
            .reduce(nil as Arrangement?) { chosen, option in
                if let chosen, chosen.cost <= option.cost { return chosen }
                return option
            }
        return (single ?? both).layout
    }

    /// An S curve from the card's badge to the nearest side of the target, at the badge's height
    /// when the target spans it. It leaves the card and meets the target level.
    static func connector(_ card: Card, to target: CGRect) -> Curve {
        let start = CGPoint(x: card.isLeft ? card.origin.x + column : card.origin.x, y: card.origin.y + padding + badge / 2)
        let end = CGPoint(x: card.isLeft ? target.minX : target.maxX, y: min(max(start.y, target.minY + 2), target.maxY - 2))
        let bend = (end.x - start.x) / 2
        return Curve(start: start, control1: CGPoint(x: start.x + bend, y: start.y), control2: CGPoint(x: end.x - bend, y: end.y), end: end)
    }

    private struct Arrangement {
        let layout: Layout
        let cost: CGFloat
        let crossings: Int
    }

    private static func arrange(
        _ columns: Columns, targets: [CGRect], heights: [CGFloat], screen: CGSize, environmentHeight: CGFloat, viewport: CGFloat, references: [CGRect]
    ) -> Arrangement {
        var shot = CGRect(x: columns == .right ? margin : margin + column + gutter, y: margin, width: screen.width, height: screen.height)
        let rightX = shot.maxX + gutter
        let moved = targets.map { $0.offsetBy(dx: shot.minX, dy: shot.minY) }
        let boxes = moved + references.map { $0.offsetBy(dx: shot.minX, dy: shot.minY) }
        var cards = moved.map { _ in Card(isLeft: true, origin: .zero) }
        var paths: [[CGPoint]] = []
        let underEnvironment = margin + environmentHeight + spacing * 2
        var nextLeft = columns == .left ? underEnvironment : margin, nextRight = underEnvironment
        var cost: CGFloat = 0, crossed = 0
        for index in moved.indices.sorted(by: { (moved[$0].midY, $0) < (moved[$1].midY, $1) }) {
            let target = moved[index]
            let desired = max(target.midY - heights[index] / 2, margin)
            var options: [Card] = []
            if columns != .right { options.append(Card(isLeft: true, origin: CGPoint(x: margin, y: max(desired, nextLeft)))) }
            if columns != .left { options.append(Card(isLeft: false, origin: CGPoint(x: rightX, y: max(desired, nextRight)))) }
            let scored = options.map { card in
                let curve = connector(card, to: target)
                let path = polyline(curve)
                let count = crossings(path, target: target, boxes: boxes, earlier: paths)
                let penalty = columns == .both && !card.isLeft ? rightColumnPenalty : 0
                let length = hypot(curve.end.x - curve.start.x, curve.end.y - curve.start.y)
                return (card: card, path: path, count: count, cost: length + penalty + CGFloat(count) * crossingPenalty)
            }
            let best = scored.dropFirst().reduce(scored[0]) { chosen, option in option.cost <= chosen.cost ? option : chosen }
            cards[index] = best.card
            paths.append(best.path)
            cost += best.cost
            crossed += best.count
            if best.card.isLeft { nextLeft = best.card.origin.y + heights[index] + spacing } else { nextRight = best.card.origin.y + heights[index] + spacing }
        }

        let bottoms = (targets + references).map(\.maxY) + cards.indices.map { cards[$0].origin.y + heights[$0] - shot.minY }
        let lowest = max(0, bottoms.max() ?? 0)
        shot.size.height = min(screen.height, max(viewport, lowest + viewport / 2))
        let height = max(shot.maxY, nextLeft - spacing, nextRight - spacing) + margin
        let layout = Layout(
            shot: shot, cards: cards, environment: CGPoint(x: columns == .left ? margin : rightX, y: margin),
            size: CGSize(width: columns == .left ? shot.maxX + margin : rightX + column + margin, height: height)
        )
        return Arrangement(layout: layout, cost: cost, crossings: crossed)
    }

    private static let samples = 16

    private static func polyline(_ curve: Curve) -> [CGPoint] {
        (0...samples).map { step in
            let t = CGFloat(step) / CGFloat(samples)
            let u = 1 - t
            func at(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
            }
            return CGPoint(
                x: at(curve.start.x, curve.control1.x, curve.control2.x, curve.end.x),
                y: at(curve.start.y, curve.control1.y, curve.control2.y, curve.end.y)
            )
        }
    }

    /// Boxes the path passes through, other than its target and the boxes around it, plus the
    /// earlier paths it crosses.
    private static func crossings(_ path: [CGPoint], target: CGRect, boxes: [CGRect], earlier: [[CGPoint]]) -> Int {
        let end = path[path.count - 1]
        let pairs = zip(path, path.dropFirst()).map { ($0, $1) }
        let box = boxes.filter { box in
            !contains(box, end) && box != target && pairs.contains { segment($0.0, $0.1, crosses: box) }
        }.count
        let lines = earlier.filter { other in
            zip(other, other.dropFirst()).contains { c, d in pairs.contains { segmentsCross($0.0, $0.1, c, d) } }
        }.count
        return box + lines
    }

    private static func contains(_ box: CGRect, _ point: CGPoint) -> Bool {
        point.x >= box.minX && point.x <= box.maxX && point.y >= box.minY && point.y <= box.maxY
    }

    private static func segment(_ a: CGPoint, _ b: CGPoint, crosses box: CGRect) -> Bool {
        var low: CGFloat = 0, high: CGFloat = 1
        let dx = b.x - a.x, dy = b.y - a.y
        for (direction, distance) in [(-dx, a.x - box.minX), (dx, box.maxX - a.x), (-dy, a.y - box.minY), (dy, box.maxY - a.y)] {
            if direction == 0 {
                if distance < 0 { return false }
                continue
            }
            let t = distance / direction
            if direction < 0 { low = max(low, t) } else { high = min(high, t) }
            if low > high { return false }
        }
        return true
    }

    private static func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Int {
        let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        return cross > 0 ? 1 : cross < 0 ? -1 : 0
    }

    private static func segmentsCross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        turn(a, b, c) * turn(a, b, d) < 0 && turn(c, d, a) * turn(c, d, b) < 0
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
        let environment = environmentText(capture, annotations)
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
        let layout = CardLayout.place(
            targets: cards.map(\.frame), heights: cards.map(\.height), screen: capture.screen, environmentHeight: environmentHeight,
            viewport: capture.visible.height, references: annotations.used.map { capture.nodes[$0.target].frame }
        )
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
            UIImage(cgImage: capture.image, scale: capture.scale, orientation: .up).draw(in: CGRect(origin: shot.origin, size: capture.screen))
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

                let curve = CardLayout.connector(placement, to: target)
                let end = curve.end
                let line = UIBezierPath()
                line.move(to: curve.start)
                line.addCurve(to: end, controlPoint1: curve.control1, controlPoint2: curve.control2)
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

    /// The app's name, then one `Name: value` line per entry, then one `@N file:line title` line per
    /// reference that has no card of its own.
    private static func environmentText(_ capture: Capture, _ annotations: Annotations) -> NSAttributedString {
        let title = NSMutableParagraphStyle()
        title.paragraphSpacing = 8
        let entry = NSMutableParagraphStyle()
        entry.paragraphSpacing = 4
        let app = capture.environment.first { $0.name == "App" }?.value ?? "App"
        let text = NSMutableAttributedString(string: "Feedback: \(app)", attributes: [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold), .foregroundColor: primary, .paragraphStyle: title,
        ])
        for item in capture.environment where item.name != "App" {
            text.append(NSAttributedString(string: "\n\(item.name): ", attributes: [
                .font: UIFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: secondary, .paragraphStyle: entry,
            ]))
            text.append(NSAttributedString(string: item.value, attributes: [
                .font: UIFont.systemFont(ofSize: 12.5), .foregroundColor: primary, .paragraphStyle: entry,
            ]))
        }
        let flagged = Set(annotations.items.map(\.target))
        for reference in annotations.used where !flagged.contains(reference.target) {
            text.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: 12.5), .paragraphStyle: entry]))
            text.append(NSAttributedString(string: "\u{00A0}\(reference.tag)\u{00A0}", attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.white,
                .backgroundColor: Palette.uiColor(annotations.colorIndex(of: reference.target)), .paragraphStyle: entry,
            ]))
            if let source = capture.nearestComponent(from: reference.target)?.source {
                text.append(NSAttributedString(string: " \(source.description)", attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: primary, .paragraphStyle: entry,
                ]))
            }
            text.append(NSAttributedString(string: " \(capture.nodes[reference.target].title)", attributes: [
                .font: UIFont.systemFont(ofSize: 12.5), .foregroundColor: primary, .paragraphStyle: entry,
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
