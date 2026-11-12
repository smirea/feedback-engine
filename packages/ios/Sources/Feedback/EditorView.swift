#if canImport(UIKit)
import SwiftUI
import UIKit

struct EditorView: View {
    /// Past this size the header wraps and the panel leaves no room for the screenshot.
    static let largestTextSize = DynamicTypeSize.xxxLarge

    @Bindable var session: Session
    let dismiss: () -> Void
    let share: (ShareTarget) -> Void
    @State private var showsList = false
    @State private var confirmsClose = false
    /// The panel's first height. The screenshot's scale stays fixed to it, so the picture does not
    /// jump as the panel grows with a selection or a longer draft.
    @State private var panelHeight: CGFloat = 0
    @State private var panelTop: CGFloat = 0
    /// The editor's height above the keyboard, which the feedback field grows into up to 60%.
    @State private var height: CGFloat = 0
    @FocusState private var composing: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                ScreenshotCanvas(session: session, panelHeight: panelHeight, panelTop: panelTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        if let toast = session.toast {
                            Button {
                                if let link = toast.link { UIApplication.shared.open(link) }
                                session.toast = nil
                            } label: {
                                HStack(spacing: 6) {
                                    Label(toast.text, systemImage: "checkmark.circle.fill")
                                    if toast.link != nil { Image(systemName: "arrow.up.forward.app").accessibilityHidden(true) }
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.green.opacity(0.9), in: Capsule())
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(toast.link == nil ? "" : "Opens the link")
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .task(id: toast) {
                                UIAccessibility.post(notification: .announcement, argument: toast.text)
                                try? await Task.sleep(for: .seconds(toast.link == nil ? 3 : 5))
                                session.toast = nil
                            }
                        }
                    }
                    .animation(.snappy, value: session.toast)
            }
            .ignoresSafeArea(.keyboard)
            TargetPanel(session: session, composing: $composing, maxFieldHeight: height * 0.6)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    if panelHeight == 0 { panelHeight = $0.height }
                    panelTop = $0.minY
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...EditorView.largestTextSize)
        .alert("Discard feedback?", isPresented: $confirmsClose) {
            Button("Discard", role: .destructive, action: dismiss)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            let count = session.unshared.count
            Text(count == 0 ? "Closing discards the feedback you're typing." : "Closing discards \(Self.items(count)) you haven't shared.")
        }
        .sheet(isPresented: $showsList) {
            ItemsSheet(session: session, share: share)
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("Close", systemImage: "xmark") {
                if session.isTyping || !session.unshared.isEmpty { confirmsClose = true } else { dismiss() }
            }
                .labelStyle(.iconOnly)
            Spacer()
            Text("Feedback").font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            Button {
                composing = false
                showsList = true
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Feedback list, \(Self.items(session.items.count))")
            .overlay(alignment: .topTrailing) {
                if !session.items.isEmpty {
                    Text("\(session.items.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.red, in: Capsule())
                        .offset(x: 4, y: -4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            ShareMenu(share: share)
                .labelStyle(.iconOnly)
                .disabled(session.items.isEmpty)
        }
        .font(.body.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private static func items(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

/// The screenshot scrolls behind the panel, so a full-length capture can be read end to end and
/// the bottom stays reachable while the keyboard is up. The scale fits the part that was on
/// screen, keeping a normal capture fully in view, and a pinch zooms in on small targets.
private struct ScreenshotCanvas: View {
    let session: Session
    let panelHeight: CGFloat
    let panelTop: CGFloat
    @State private var zoom = ZoomLevel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let capture = session.capture
            let widthFit = (proxy.size.width - 24) / capture.screen.width
            // Smaller than half the width, the screenshot is too small to tap. It scrolls behind
            // the panel instead.
            let scale = max(min(widthFit, (proxy.size.height - panelHeight - 16) / capture.visible.height), widthFit / 2, 0.05)
            let size = CGSize(width: capture.screen.width * scale, height: capture.screen.height * scale)
            let bottom = max(proxy.frame(in: .global).maxY - panelTop, panelHeight) + 8
            ZoomableScroll(
                contentSize: size, top: 8, bottom: bottom, initialOffset: capture.visible.minY * scale, zoom: zoom,
                content: canvas(size: size, scale: scale).dynamicTypeSize(dynamicTypeSize)
            )
        }
    }

    private func canvas(size: CGSize, scale: CGFloat) -> some View {
        let capture = session.capture
        let target = session.target
        let zoom = zoom.scale
        return ZStack(alignment: .topLeading) {
            Image(decorative: capture.image, scale: capture.scale)
                .resizable()
                .frame(width: size.width, height: size.height)
            ForEach(session.similar, id: \.self) { id in
                Box(frame: capture.nodes[id].frame, scale: scale, zoom: zoom, color: .yellow.opacity(0.5), lineWidth: 1, fill: .yellow.opacity(0.08))
            }
            ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                Box(frame: capture.nodes[item.target].frame, scale: scale, zoom: zoom, color: Palette.color(session.colorIndex(of: item.target)), number: index + 1)
            }
            ForEach(session.visibleReferences, id: \.self) { reference in
                Box(frame: capture.nodes[reference.target].frame, scale: scale, zoom: zoom, color: Palette.color(session.colorIndex(of: reference.target)), tag: reference.tag)
            }
            if target.kind != .screen {
                Box(frame: target.frame, scale: scale, zoom: zoom, color: .yellow, lineWidth: 2)
            }
            if let reference = session.referenceTarget {
                Box(frame: reference.frame, scale: scale, zoom: zoom, color: .cyan, lineWidth: 2, fill: .cyan.opacity(0.12))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { location in
            session.pick(at: CGPoint(x: location.x / scale, y: location.y / scale))
        }
        .accessibilityElement()
        .accessibilityLabel("Screenshot")
        .accessibilityHint("Tap a component to give it feedback. Pinch to zoom.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

/// The zoom the boxes divide their strokes by, so outlines stay thin when zoomed in. It updates
/// when a pinch ends, not on every frame of it.
@MainActor @Observable
private final class ZoomLevel {
    var scale: CGFloat = 1
}

/// A `UIScrollView`, because SwiftUI's `ScrollView` can't zoom around the pinch. The SwiftUI
/// canvas is hosted at its unzoomed size, so tap locations stay in screenshot coordinates.
private struct ZoomableScroll<Content: View>: UIViewRepresentable {
    let contentSize: CGSize
    let top: CGFloat
    let bottom: CGFloat
    let initialOffset: CGFloat
    let zoom: ZoomLevel
    let content: Content

    func makeCoordinator() -> Coordinator { Coordinator(host: UIHostingController(rootView: content), zoom: zoom) }

    func makeUIView(context: Context) -> CanvasScrollView {
        let scroll = CanvasScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.keyboardDismissMode = .none
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.pendingOffset = initialOffset
        let host = context.coordinator.host
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        scroll.addSubview(host.view)
        scroll.canvas = host.view
        return scroll
    }

    func updateUIView(_ scroll: CanvasScrollView, context: Context) {
        let host = context.coordinator.host
        host.rootView = content
        if scroll.baseSize != contentSize {
            let zoom = scroll.zoomScale
            scroll.zoomScale = 1
            host.view.frame = CGRect(origin: .zero, size: contentSize)
            scroll.contentSize = contentSize
            scroll.baseSize = contentSize
            scroll.zoomScale = zoom
        }
        scroll.margins = (top, bottom)
        scroll.setNeedsLayout()
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let host: UIHostingController<Content>
        let zoom: ZoomLevel

        init(host: UIHostingController<Content>, zoom: ZoomLevel) {
            self.host = host
            self.zoom = zoom
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { scrollView.setNeedsLayout() }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            zoom.scale = scale
        }
    }
}

/// Centres the canvas when it is smaller than the view, keeps the margins above and below it, and
/// opens at the part of the capture that was on screen.
private final class CanvasScrollView: UIScrollView {
    weak var canvas: UIView?
    var baseSize = CGSize.zero
    var margins: (top: CGFloat, bottom: CGFloat) = (0, 0)
    var pendingOffset: CGFloat?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let canvas, bounds.height > 0 else { return }
        let size = canvas.frame.size
        let room = bounds.height - margins.top - margins.bottom
        let inset = UIEdgeInsets(
            top: margins.top + max((room - size.height) / 2, 0),
            left: max((bounds.width - size.width) / 2, 0),
            bottom: margins.bottom,
            right: max((bounds.width - size.width) / 2, 0)
        )
        if contentInset != inset { contentInset = inset }
        if let offset = pendingOffset, size.height > 0 {
            pendingOffset = nil
            let highest = max(size.height + inset.bottom - bounds.height, -inset.top)
            contentOffset = CGPoint(x: -inset.left, y: min(max(offset - inset.top, -inset.top), highest))
        }
    }
}

private struct Box: View {
    let frame: CGRect
    let scale: CGFloat
    var zoom: CGFloat = 1
    let color: Color
    var number: Int?
    var tag: String?
    var lineWidth: CGFloat = 1.5
    var fill: Color = .clear

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fill)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth / zoom, dash: [4 / zoom, 3 / zoom]))
            .frame(width: max(frame.width * scale, 4), height: max(frame.height * scale, 4))
            .overlay(alignment: .topLeading) {
                if let number {
                    Text("\(number)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(color, in: Circle())
                        .scaleEffect(1 / zoom, anchor: .topLeading)
                        .offset(x: -6 / zoom, y: -6 / zoom)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let tag {
                    Text(tag)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .fixedSize()
                        .padding(.horizontal, 3)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(color, in: RoundedRectangle(cornerRadius: 3))
                        .scaleEffect(1 / zoom, anchor: .topTrailing)
                        .offset(x: 6 / zoom, y: -6 / zoom)
                }
            }
            .offset(x: frame.minX * scale, y: frame.minY * scale)
            .allowsHitTesting(false)
    }
}

private struct TargetPanel: View {
    @Bindable var session: Session
    var composing: FocusState<Bool>.Binding
    let maxFieldHeight: CGFloat
    @ScaledMetric(relativeTo: .body) private var lineHeight = UIFont.preferredFont(
        forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
    ).lineHeight

    var body: some View {
        let target = session.target
        VStack(alignment: .leading, spacing: 10) {
            if session.path.count > 1 {
                Chain(session: session)
            } else {
                Text("Tap the screenshot to pick a component.").font(.subheadline).foregroundStyle(.secondary)
            }
            if session.isReferencing {
                ReferencePicker(session: session)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if let editing = session.editing, let index = session.items.firstIndex(of: editing) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Palette.color(session.colorIndex(of: editing.target)), in: Circle())
                        .padding(.bottom, 8)
                        .accessibilityLabel("Editing item \(index + 1)")
                }
                TextField("Feedback on \(target.name)…", text: $session.text, axis: .vertical)
                    .lineLimit(1...max(Int((maxFieldHeight - 16) / lineHeight), 1))
                    .focused(composing)
                    .accessibilityLabel("Feedback text")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 18))
                Button(
                    session.editing == nil ? "Add feedback" : "Save feedback",
                    systemImage: session.editing == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill"
                ) {
                    session.submit()
                    composing.wrappedValue = false
                }
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .disabled(!session.canSubmit)
            }
        }
        .padding(16)
        .background(Color(white: 0.12))
    }
}

/// Shown while the text ends in `@`: a hint until a tap picks a node, then that node with buttons to
/// move up or down its path and to insert it.
private struct ReferencePicker: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            if let node = session.referenceTarget {
                let path = session.referencePath
                let level = min(session.referenceLevel, path.count - 1)
                Button("Select parent", systemImage: "chevron.up") { session.stepReference(to: level + 1) }
                    .labelStyle(.iconOnly)
                    .disabled(level + 1 >= path.count)
                Button("Select child", systemImage: "chevron.down") { session.stepReference(to: level - 1) }
                    .labelStyle(.iconOnly)
                    .disabled(level == 0)
                Text(node.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Insert") { session.insertReference() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.cyan)
                    .font(.subheadline.weight(.semibold))
            } else {
                Label("Tap an element to reference it", systemImage: "at")
                    .font(.subheadline)
                    .foregroundStyle(.cyan)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .frame(minHeight: 34)
    }
}

/// The target between its parent and its child on the picked path. Stepping to either moves the
/// target, and the neighbors follow.
private struct Chain: View {
    let session: Session
    @State private var showsInfo = false

    var body: some View {
        let path = session.path
        let level = min(session.level, path.count - 1)
        HStack(spacing: 8) {
            neighbor(level + 1 < path.count ? path[level + 1] : nil, isParent: true) { session.step(to: level + 1) }
                .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
            Button { showsInfo = true } label: {
                Text(session.target.title)
                    .font(.headline)
                    .foregroundStyle(.yellow)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows its source and data")
            .layoutPriority(1)
            .popover(isPresented: $showsInfo, arrowEdge: .bottom) {
                TargetInfo(session: session)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Color(white: 0.17))
            }
            neighbor(level > 0 ? path[level - 1] : nil, isParent: false) { session.step(to: level - 1) }
                .frame(minWidth: 90, maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func neighbor(_ node: Node?, isParent: Bool, action: @escaping () -> Void) -> some View {
        if let node {
            Button(action: action) {
                HStack(spacing: 3) {
                    if isParent { Image(systemName: "chevron.left").font(.caption2.bold()) }
                    Text(node.name).lineLimit(1)
                    if !isParent { Image(systemName: "chevron.right").font(.caption2.bold()) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(white: 0.2), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(isParent ? "parent" : "child"), \(node.title)")
        } else {
            Color.clear.frame(height: 1)
        }
    }
}

/// The target's code location, how many sibling parts match it, and its data, kept out of the
/// panel so the field has the room.
private struct TargetInfo: View {
    let session: Session

    var body: some View {
        let target = session.target
        let component = session.capture.nearestComponent(from: target.id)
        let data = target.data ?? component?.data
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if component?.source != nil || !session.similar.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        if let source = component?.source {
                            Text(source.description)
                        }
                        Spacer(minLength: 0)
                        if !session.similar.isEmpty {
                            Text("\(session.similar.count) similar").foregroundStyle(.yellow.opacity(0.7))
                        }
                    }
                    .font(.caption.monospaced())
                }
                if let data {
                    Text(data).font(.caption2.monospaced())
                }
                if component?.source == nil && session.similar.isEmpty && data == nil {
                    Text("No source or data").font(.caption)
                }
            }
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: 360, maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...EditorView.largestTextSize)
    }
}

private struct ShareMenu: View {
    let share: (ShareTarget) -> Void

    var body: some View {
        Menu {
            ForEach(ShareTarget.available, id: \.self) { target in
                Button(target.title, systemImage: target.systemImage) { share(target) }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
    }
}

private struct ItemsSheet: View {
    @Bindable var session: Session
    let share: (ShareTarget) -> Void
    @Environment(\.dismiss) private var dismiss

    private func styled(_ text: String) -> AttributedString {
        session.annotations.segments(text).reduce(into: AttributedString()) { result, segment in
            if let reference = segment.reference {
                var token = AttributedString("\u{00A0}\(segment.text)\u{00A0}")
                token.backgroundColor = Palette.color(session.colorIndex(of: reference.target))
                token.foregroundColor = .white
                result += token
            } else {
                result += AttributedString(segment.text)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Feedback") {
                    if session.items.isEmpty {
                        Text("No feedback yet. Tap a component, type, and press the arrow.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                        let target = session.capture.nodes[item.target]
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Palette.color(session.colorIndex(of: item.target)), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(styled(item.text))
                            }
                            Spacer()
                            Button("Remove", systemImage: "trash", role: .destructive) { session.remove(item.id) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            session.select(item.target)
                            dismiss()
                        }
                    }
                    .onDelete { offsets in offsets.map { session.items[$0].id }.forEach(session.remove) }
                }
                Section("Attached context") {
                    ForEach(session.capture.environment + session.capture.context, id: \.self) { entry in
                        DisclosureGroup(entry.name) {
                            Text(entry.value).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .dynamicTypeSize(...EditorView.largestTextSize)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareMenu(share: share).disabled(session.items.isEmpty)
                }
            }
        }
    }
}

enum Palette {
    static let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemPink, .systemTeal, .systemIndigo]

    static func uiColor(_ index: Int) -> UIColor { colors[index % colors.count] }
    static func color(_ index: Int) -> Color { Color(uiColor: uiColor(index)) }
}
#endif
