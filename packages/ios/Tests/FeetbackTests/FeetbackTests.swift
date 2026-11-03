import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Feetback

private let screen = CGSize(width: 400, height: 800)
private func source(_ line: Int) -> CodeLocation { CodeLocation(file: "App/Screen.swift", line: line) }

private func component(_ name: String, _ frame: CGRect, id: UUID = UUID(), parent: UUID? = nil, layer: Int = 0, data: String? = nil) -> RawScene.Component {
    RawScene.Component(id: id, parent: parent, layer: layer, name: name, source: source(frame.minY == 0 ? 1 : Int(frame.minY)), frame: frame, data: data)
}

private func capture(_ scene: RawScene) -> Capture {
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return Capture(
        date: .now, screen: scene.screen, scale: 1, image: context.makeImage()!, nodes: TreeBuilder.build(scene),
        environment: [ContextEntry(name: "App", value: "Demo")], context: [ContextEntry(name: "Store", value: "Store(count: 2)")]
    )
}

private func titles(_ path: [Node]) -> [String] { path.map(\.title) }

@Test func tapPicksDeepestElementAndPathWalksUpThroughTaggedComponents() {
    let list = UUID(), row = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [
            component("ListScreen", CGRect(x: 0, y: 100, width: 400, height: 600), id: list),
            component("Row", CGRect(x: 16, y: 200, width: 368, height: 44), id: row, parent: list),
        ],
        elements: [
            .init(layer: 0, role: "Button", label: "Mark done", frame: CGRect(x: 20, y: 210, width: 24, height: 24)),
            .init(layer: 0, role: "Tab bar", label: "Tabs", frame: CGRect(x: 0, y: 750, width: 400, height: 50)),
        ]
    )
    let capture = capture(scene)
    let picked = capture.hitTest(CGPoint(x: 30, y: 220))
    #expect(titles(capture.path(from: picked)) == ["Button \"Mark done\"", "Row", "ListScreen", "Screen"])
    #expect(titles(capture.path(from: capture.hitTest(CGPoint(x: 200, y: 775)))) == ["Tab bar \"Tabs\"", "Screen"])
    #expect(capture.hitTest(CGPoint(x: 200, y: 50)) == 0)
}

@Test func presentedSheetHidesTheScreenUnderIt() {
    let base = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [
            .init(name: "Screen", frame: CGRect(origin: .zero, size: screen)),
            .init(name: "Sheet", frame: CGRect(x: 0, y: 400, width: 400, height: 400)),
        ],
        components: [
            component("ListScreen", CGRect(x: 0, y: 0, width: 400, height: 800), id: base),
            component("Row", CGRect(x: 0, y: 450, width: 400, height: 40), parent: base),
            component("DetailSheet", CGRect(x: 0, y: 400, width: 400, height: 400), parent: base, layer: 1),
        ],
        elements: []
    )
    let capture = capture(scene)
    #expect(titles(capture.path(from: capture.hitTest(CGPoint(x: 100, y: 460)))) == ["DetailSheet", "Sheet", "Screen"])
    #expect(titles(capture.path(from: capture.hitTest(CGPoint(x: 100, y: 100)))) == ["ListScreen", "Screen"])
}

@Test func offscreenComponentsAreDroppedUnlessAVisibleChildNeedsThem() {
    let outer = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [
            component("Scroller", CGRect(x: 0, y: -200, width: 400, height: 1400), id: outer),
            component("Visible", CGRect(x: 0, y: 10, width: 400, height: 40), parent: outer),
            component("Below", CGRect(x: 0, y: 1000, width: 400, height: 40), parent: outer),
        ],
        elements: []
    )
    #expect(capture(scene).nodes.map(\.name) == ["Screen", "Scroller", "Visible"])
}

@Test func reportNumbersItemsAndListsEachComponentsDataOnce() {
    let list = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [
            component("ListScreen", CGRect(x: 0, y: 100, width: 400, height: 600), id: list, data: "filter: open"),
            component("Row", CGRect(x: 16, y: 200, width: 368, height: 44), parent: list, data: "title: Milk"),
        ],
        elements: [.init(layer: 0, role: "Button", label: "Mark done", frame: CGRect(x: 20, y: 210, width: 24, height: 24))]
    )
    let capture = capture(scene)
    let button = capture.hitTest(CGPoint(x: 30, y: 220))
    let row = capture.path(from: button)[1].id
    let markdown = Report.markdown(capture, items: [
        FeedbackItem(target: button, text: "Make it bigger"),
        FeedbackItem(target: row, text: "Too tight\nAdd padding"),
    ])
    #expect(markdown.contains("""
    ## 1. Button "Mark done"

    > Make it bigger

    - Path: Screen › ListScreen (`App/Screen.swift:100`) › Row (`App/Screen.swift:200`) › Button "Mark done"
    - Frame: x 20, y 210, 24 × 24
    - Element: Button "Mark done"
    - Code: `App/Screen.swift:200` (Row)
    """))
    #expect(markdown.contains("## 2. Row\n\n> Too tight\n> Add padding\n"))
    #expect(markdown.components(separatedBy: "### Row · `App/Screen.swift:200` · items 1, 2\n```\ntitle: Milk\n```").count == 2)
    #expect(markdown.contains("### ListScreen · `App/Screen.swift:100` · items 1, 2\n```\nfilter: open\n```"))
    #expect(markdown.contains("### Store\n```\nStore(count: 2)\n```"))
}

private struct Row: View {
    let title: String
    @Binding var isDone: Bool
    @State private var isEditing = true
    let onTap: () -> Void

    var body: some View { Text(title) }
}

@Test func viewPropertiesIncludeBindingsButNotClosuresOrUninstalledState() {
    var done = false
    let row = Row(title: "Milk", isDone: Binding(get: { done }, set: { done = $0 }), onTap: {})
    done = true
    #expect(Describer.describeProperties(of: row) == "title: Milk\nisDone: true")
}

@MainActor @Observable
private final class Store {
    var count = 2
    var names = ["a"]
}

@Test @MainActor func observableObjectsAreDescribedByTheirFields() {
    #expect(Describer.describe(Store()) == "Store(count: 2, names: [\"a\"])")
}

@Test func unusableFramesAndEmptyOverlayLayersAreIgnored() {
    let scene = RawScene(
        screen: screen,
        layers: [
            .init(name: "Screen", frame: CGRect(origin: .zero, size: screen)),
            .init(name: "Toast", frame: .null),
        ],
        components: [component("ListScreen", CGRect(x: 0, y: 0, width: 400, height: 800))],
        elements: [
            .init(layer: 0, role: "Element", label: "Offscreen", frame: .infinite),
            .init(layer: 0, role: "Text", label: "Title", frame: CGRect(x: 10, y: 10, width: 100, height: 20)),
        ]
    )
    let capture = capture(scene)
    #expect(capture.nodes.map(\.title) == ["Screen", "ListScreen", "Text \"Title\""])
    #expect(titles(capture.path(from: capture.hitTest(CGPoint(x: 20, y: 15)))) == ["Text \"Title\"", "ListScreen", "Screen"])
    #expect(Report.markdown(capture, items: [FeedbackItem(target: 2, text: "ok")]).contains("- Frame: x 10, y 10, 100 × 20"))
}
