#if canImport(UIKit)
import SwiftUI
import UIKit

extension View {
    /// Names this view in feedback captures. `data` is described when a capture is taken.
    public func feedback(_ name: String, data: Any? = nil, file: String = #fileID, line: Int = #line) -> some View {
        modifier(FeedbackTag(name: name, payload: data.map(Payload.value) ?? .none, source: CodeLocation(file: file, line: line)))
    }

    /// Names this view after the type of `view` and reports its stored properties and bindings.
    /// Call it as `.feedback(self)` at the end of a view's body.
    public func feedback<V: View>(_ view: V, file: String = #fileID, line: Int = #line) -> some View {
        modifier(FeedbackTag(name: Describer.typeName(view), payload: .properties(view), source: CodeLocation(file: file, line: line)))
    }
}

enum Payload {
    case none
    case value(Any)
    case properties(Any)

    var description: String? {
        switch self {
        case .none: nil
        case .value(let value): Describer.describe(value)
        case .properties(let view): Describer.describeProperties(of: view)
        }
    }
}

private struct FeedbackParentKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var feedbackParent: UUID? {
        get { self[FeedbackParentKey.self] }
        set { self[FeedbackParentKey.self] = newValue }
    }
}

struct FeedbackTag: ViewModifier {
    let name: String
    let payload: Payload
    let source: CodeLocation
    @State private var id = UUID()
    @Environment(\.feedbackParent) private var parent

    func body(content: Content) -> some View {
        content
            .environment(\.feedbackParent, id)
            .background(Marker(info: MarkerInfo(id: id, parent: parent, name: name, source: source, payload: payload)))
    }
}

struct MarkerInfo {
    let id: UUID
    let parent: UUID?
    let name: String
    let source: CodeLocation
    let payload: Payload
}

/// A plain UIView sized to the tagged view. Captures find these by walking the view hierarchy,
/// so tagging costs nothing per frame: no geometry callbacks, no shared registry.
final class MarkerView: UIView {
    var info: MarkerInfo?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct Marker: UIViewRepresentable {
    let info: MarkerInfo

    func makeUIView(context: Context) -> MarkerView { MarkerView() }

    func updateUIView(_ view: MarkerView, context: Context) { view.info = info }
}
#endif
