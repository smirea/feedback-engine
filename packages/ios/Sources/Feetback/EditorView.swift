#if canImport(UIKit)
import SwiftUI
import UIKit

struct EditorView: View {
    @Bindable var session: Session
    let dismiss: () -> Void
    let share: () -> Void
    @State private var showsList = false
    @State private var panelHeight: CGFloat = 0
    @FocusState private var composing: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                ScreenshotCanvas(session: session)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, panelHeight + 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.keyboard)
            TargetPanel(session: session, composing: $composing)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
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

private struct ScreenshotCanvas: View {
    let session: Session

    var body: some View {
        GeometryReader { proxy in
            let screen = session.capture.screen
            let scale = min(proxy.size.width / screen.width, proxy.size.height / screen.height)
            let size = CGSize(width: screen.width * scale, height: screen.height * scale)
            ZStack(alignment: .topLeading) {
                Image(decorative: session.capture.image, scale: session.capture.scale)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                    Box(frame: session.capture.nodes[item.target].frame, scale: scale, color: Palette.color(index), number: index + 1, emphasized: false)
                }
                if session.target.kind != .screen {
                    Box(frame: session.target.frame, scale: scale, color: .yellow, number: nil, emphasized: true)
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
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

private struct Box: View {
    let frame: CGRect
    let scale: CGFloat
    let color: Color
    let number: Int?
    let emphasized: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(emphasized ? 0.18 : 0.1))
            .stroke(color, lineWidth: emphasized ? 2.5 : 1.5)
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
        let path = session.path
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(target.title).font(.headline).lineLimit(1)
                Spacer()
                if let source = session.capture.nearestComponent(from: target.id)?.source {
                    Text(source.description)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "scope").foregroundStyle(.secondary).accessibilityHidden(true)
                Slider(
                    value: Binding(get: { Double(session.level) }, set: { session.level = Int($0.rounded()) }),
                    in: 0...Double(max(path.count - 1, 1)), step: 1
                )
                .disabled(path.count < 2)
                .accessibilityLabel("Hierarchy level")
                .accessibilityValue(target.title)
                Image(systemName: "rectangle.dashed").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            if path.count > 1 {
                Breadcrumbs(path: path, level: $session.level)
            } else {
                Text("Tap the screenshot to pick a component.").font(.caption).foregroundStyle(.secondary)
            }
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

private struct Breadcrumbs: View {
    let path: [Node]
    @Binding var level: Int

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(path.enumerated().reversed()), id: \.element.id) { index, node in
                        Button(node.name) { level = index }
                            .font(.caption.weight(index == level ? .bold : .regular))
                            .foregroundStyle(index == level ? Color.yellow : Color.secondary)
                            .id(node.id)
                        if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    }
                }
            }
            .onChange(of: [level, path[0].id], initial: true) { reader.scrollTo(path[min(level, path.count - 1)].id, anchor: .center) }
        }
    }
}

private struct ItemsSheet: View {
    let session: Session
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
