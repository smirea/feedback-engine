#if canImport(UIKit)
import SwiftUI
import UIKit

extension Feedback {
    /// GitHub's mark, for a webhook that files issues.
    public static let githubIcon = Image(uiImage: GitHubIcon.image)
}

enum GitHubIcon {
    /// The web package's `githubIcon` has the same path (`dom/webhook.ts`): 16 points square, with only
    /// absolute `M`, `L`, `C`, and `Z` commands and a space between numbers.
    static let path = "M6.766 11.328C4.703 11.078 3.25 9.594 3.25 7.672C3.25 6.891 3.531 6.047 4 5.484C3.797 4.969 3.828 3.875 4.063 3.422C4.688 3.344 5.531 3.672 6.031 4.125C6.625 3.938 7.25 3.844 8.016 3.844C8.781 3.844 9.406 3.938 9.969 4.109C10.453 3.672 11.313 3.344 11.938 3.422C12.156 3.844 12.188 4.937 11.984 5.469C12.484 6.062 12.75 6.859 12.75 7.672C12.75 9.594 11.297 11.047 9.203 11.312C9.734 11.656 10.093 12.406 10.093 13.266L10.093 14.891C10.093 15.359 10.484 15.625 10.953 15.438C13.781 14.359 16 11.53 16 8.03C16 3.61 12.406 0 7.984 0C3.563 0 0 3.61 0 8.031C-0.009 11.347 2.058 14.314 5.172 15.453C5.594 15.609 6 15.328 6 14.906L6 13.656C5.781 13.75 5.5 13.812 5.25 13.812C4.219 13.812 3.61 13.25 3.172 12.203C3 11.781 2.812 11.531 2.453 11.484C2.266 11.469 2.203 11.391 2.203 11.297C2.203 11.109 2.516 10.969 2.828 10.969C3.281 10.969 3.672 11.25 4.078 11.829C4.391 12.281 4.718 12.484 5.109 12.484C5.5 12.484 5.75 12.344 6.109 11.984C6.375 11.719 6.579 11.484 6.766 11.328Z"

    /// The mark at 16 points square.
    static var outline: UIBezierPath {
        let outline = UIBezierPath()
        for command in path.matches(of: /([MLCZ])([^MLCZ]*)/) {
            let numbers = command.2.split(separator: " ").compactMap { Double($0) }
            func point(_ index: Int) -> CGPoint { CGPoint(x: numbers[index], y: numbers[index + 1]) }
            switch command.1 {
            case "M": outline.move(to: point(0))
            case "L": outline.addLine(to: point(0))
            case "C": outline.addCurve(to: point(4), controlPoint1: point(0), controlPoint2: point(2))
            default: outline.close()
            }
        }
        return outline
    }

    /// A template image, so a menu draws it in its own text color.
    static var image: UIImage {
        let outline = outline
        let side: CGFloat = 22
        outline.apply(CGAffineTransform(scaleX: side / 16, y: side / 16))
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            UIColor.black.setFill()
            outline.fill()
        }.withRenderingMode(.alwaysTemplate)
    }
}
#endif
