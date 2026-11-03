#if canImport(UIKit)
import SwiftUI
import UIKit

struct EditorView: View {
    @Bindable var session: Session
    let dismiss: () -> Void
    let share: () -> Void
    @State private var showsList = false
    /// The panel's first height. The screenshot's scale stays fixed to it, so the picture does not
    /// jump as the panel grows with a selection or a longer draft.
    @State private var panelHeight: CGFloat = 0
    @State private var panelTop: CGFloat = 0
    @FocusState private var composing: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                ScreenshotCanvas(session: session, panelHeight: panelHeight, panelTop: panelTop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.keyboard)
            TargetPanel(session: session, composing: $composing)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    if panelHeight == 0 { panelHeight = $0.height }
                    panelTop = $0.minY
                }
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsList) {
            ItemsSheet(session: session, share: share)
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("Close", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
            Spacer()
            Text("Feedback").font(.headline)
            Spacer()
            Button {
                composing = false
                showsList = true
            } label: {
                Image(systemName: "list.bullet")
            }
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
            .accessibilityLabel("Feedback list, \(session.items.count) items")
            Button("Share", systemImage: "square.and.arrow.up", action: share)
                .labelStyle(.iconOnly)
                .disabled(session.items.isEmpty)
        }
        .font(.body.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// The screenshot scrolls behind the panel, so a full-length capture can be read end to end and
/// the bottom stays reachable while the keyboard is up. The scale fits the part that was on
/// screen, keeping a normal capture fully in view.
private struct ScreenshotCanvas: View {
    let session: Session
    let panelHeight: CGFloat
    let panelTop: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let capture = session.capture
            let scale = max(min((proxy.size.width - 24) / capture.screen.width, (proxy.size.height - panelHeight - 16) / capture.visible.height), 0.05)
            let size = CGSize(width: capture.screen.width * scale, height: capture.screen.height * scale)
            let bottom = max(proxy.frame(in: .global).maxY - panelTop, panelHeight) + 8
            let hidden = capture.screen.height - capture.visible.height
            ScrollView {
                canvas(size: size, scale: scale)
                    .frame(maxWidth: .infinity, minHeight: max(proxy.size.height - bottom - 8, 0))
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .contentMargins(.bottom, bottom, for: .scrollContent)
            .scrollDismissesKeyboard(.never)
            .scrollBounceBehavior(.basedOnSize)
            .modifier(InitialAnchor(anchor: UnitPoint(x: 0.5, y: hidden > 0 ? capture.visible.minY / hidden : 0)))
        }
    }

    private func canvas(size: CGSize, scale: CGFloat) -> some View {
        let capture = session.capture
        let target = session.target
        return ZStack(alignment: .topLeading) {
            Image(decorative: capture.image, scale: capture.scale)
                .resizable()
                .frame(width: size.width, height: size.height)
            ForEach(session.similar, id: \.self) { id in
                Box(frame: capture.nodes[id].frame, scale: scale, color: .yellow.opacity(0.5), lineWidth: 1, fill: .yellow.opacity(0.08))
            }
            ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                Box(frame: capture.nodes[item.target].frame, scale: scale, color: Palette.color(index), number: index + 1)
            }
            if target.kind != .screen {
                Box(frame: target.frame, scale: scale, color: .yellow, lineWidth: 2)
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
        .accessibilityHint("Tap a component to give it feedback")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

/// Opens at the part that was on screen. From iOS 18 the anchor stops there, so the view does not
/// jump when the keyboard changes the bottom margin.
private struct InitialAnchor: ViewModifier {
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.defaultScrollAnchor(anchor, for: .initialOffset)
        } else {
            content.defaultScrollAnchor(anchor)
        }
    }
}

private struct Box: View {
    let frame: CGRect
    let scale: CGFloat
    let color: Color
    var number: Int?
    var lineWidth: CGFloat = 1.5
    var fill: Color = .clear

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fill)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: [4, 3]))
            .frame(width: max(frame.width * scale, 4), height: max(frame.height * scale, 4))
            .overlay(alignment: .topLeading) {
                if let number {
                    Text("\(number)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(color, in: Circle())
                        .offset(x: -6, y: -6)
                }
            }
            .offset(x: frame.minX * scale, y: frame.minY * scale)
            .allowsHitTesting(false)
    }
}

private struct TargetPanel: View {
    @Bindable var session: Session
    var composing: FocusState<Bool>.Binding

    var body: some View {
        let target = session.target
        VStack(alignment: .leading, spacing: 10) {
            if session.path.count > 1 {
                Chain(session: session)
            } else {
                Text("Tap the screenshot to pick a component.").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let source = session.capture.nearestComponent(from: target.id)?.source {
                    Text(source.description)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                if !session.similar.isEmpty {
                    Text("\(session.similar.count) similar").foregroundStyle(.yellow.opacity(0.7))
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            Text(target.data ?? session.capture.nearestComponent(from: target.id)?.data ?? " ")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Feedback on \(target.name)…", text: $session.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused(composing)
                    .accessibilityLabel("Feedback text")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 18))
                Button("Add feedback", systemImage: "arrow.up.circle.fill") {
                    session.add()
                    composing.wrappedValue = false
                }
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(Color(white: 0.12))
    }
}

/// The target between its parent and its child on the picked path. Stepping to either moves the
/// target, and the neighbors follow.
private struct Chain: View {
    let session: Session

    var body: some View {
        let path = session.path
        let level = min(session.level, path.count - 1)
        HStack(spacing: 8) {
            neighbor(level + 1 < path.count ? path[level + 1] : nil, isParent: true) { session.level = level + 1 }
                .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
            Text(session.target.title)
                .font(.headline)
                .foregroundStyle(.yellow)
                .lineLimit(1)
                .layoutPriority(1)
            neighbor(level > 0 ? path[level - 1] : nil, isParent: false) { session.level = level - 1 }
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

private struct ItemsSheet: View {
    @Bindable var session: Session
    let share: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                                .background(Palette.color(index), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(item.text)
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
                Section {
                    Picker("Export", selection: $session.format) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Export")
                } footer: {
                    Text(session.format == .image
                        ? "One PNG: the screenshot with numbered boxes, each item's text and code location, and the environment."
                        : "Every item, the component tree, and the attached context as JSON, without the screenshot.")
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Share", systemImage: "square.and.arrow.up", action: share)
                    .disabled(session.items.isEmpty)
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
