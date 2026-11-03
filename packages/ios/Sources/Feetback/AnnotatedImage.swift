#if canImport(UIKit)
import UIKit

/// The image half of a shared report: the screenshot with numbered boxes, and a legend
/// underneath so the image still reads on its own when the text gets separated from it.
enum AnnotatedImage {
    static func render(_ capture: Capture, items: [FeedbackItem]) -> UIImage {
        let width = capture.screen.width
        let padding: CGFloat = 16
        let badge: CGFloat = 22
        let textWidth = width - padding * 3 - badge
        let legend = items.enumerated().map { index, item in
            let target = capture.nodes[item.target]
            let text = NSMutableAttributedString(string: target.title + "\n", attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.secondaryLabel.resolvedColor(with: .init(userInterfaceStyle: .light)),
            ])
            text.append(NSAttributedString(string: item.text, attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.black]))
            let height = ceil(text.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height)
            return (index: index, text: text, height: max(height, badge))
        }
        let legendHeight = legend.reduce(padding) { $0 + $1.height + padding }

        let format = UIGraphicsImageRendererFormat()
        format.scale = capture.scale
        let size = CGSize(width: width, height: capture.screen.height + legendHeight)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: capture.image, scale: capture.scale, orientation: .up).draw(in: CGRect(origin: .zero, size: capture.screen))

            for (index, item) in items.enumerated() {
                let color = Palette.uiColor(index)
                let frame = capture.nodes[item.target].frame.insetBy(dx: -1, dy: -1)
                let box = UIBezierPath(roundedRect: frame, cornerRadius: 4)
                color.withAlphaComponent(0.12).setFill()
                box.fill()
                color.setStroke()
                box.lineWidth = 2.5
                box.stroke()
                let center = CGPoint(
                    x: min(max(frame.minX, badge / 2 + 2), width - badge / 2 - 2),
                    y: min(max(frame.minY, badge / 2 + 2), capture.screen.height - badge / 2 - 2)
                )
                drawBadge(index + 1, color: color, center: center, diameter: badge)
            }

            var y = capture.screen.height + padding
            for line in legend {
                drawBadge(line.index + 1, color: Palette.uiColor(line.index), center: CGPoint(x: padding + badge / 2, y: y + badge / 2), diameter: badge)
                line.text.draw(with: CGRect(x: padding * 2 + badge, y: y, width: textWidth, height: line.height), options: [.usesLineFragmentOrigin], context: nil)
                y += line.height + padding
            }
        }
    }

    private static func drawBadge(_ number: Int, color: UIColor, center: CGPoint, diameter: CGFloat) {
        let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        color.setFill()
        UIBezierPath(ovalIn: circle).fill()
        UIColor.white.setStroke()
        let ring = UIBezierPath(ovalIn: circle)
        ring.lineWidth = 1.5
        ring.stroke()
        let label = NSAttributedString(string: "\(number)", attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: UIColor.white])
        let size = label.size()
        label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }
}
#endif
