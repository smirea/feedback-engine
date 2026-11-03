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
        date: .now, screen: scene.screen, visible: CGRect(origin: .zero, size: screen), scale: 1, image: context.makeImage()!, nodes: TreeBuilder.build(scene),
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

@Test func similarFindsTheSamePartInSiblingComponents() {
    let list = UUID(), first = UUID(), second = UUID(), third = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [
            component("ListScreen", CGRect(x: 0, y: 0, width: 400, height: 800), id: list),
            RawScene.Component(id: first, parent: list, layer: 0, name: "Row", source: source(40), frame: CGRect(x: 0, y: 100, width: 400, height: 44), data: nil),
            RawScene.Component(id: second, parent: list, layer: 0, name: "Row", source: source(40), frame: CGRect(x: 0, y: 150, width: 400, height: 44), data: nil),
            RawScene.Component(id: third, parent: list, layer: 0, name: "Row", source: source(40), frame: CGRect(x: 0, y: 200, width: 400, height: 44), data: nil),
            component("Footer", CGRect(x: 0, y: 700, width: 400, height: 44), parent: list),
        ],
        elements: [
            .init(layer: 0, role: "Button", label: "Done", frame: CGRect(x: 10, y: 110, width: 24, height: 24)),
            .init(layer: 0, role: "Button", label: "Info", frame: CGRect(x: 360, y: 110, width: 24, height: 24)),
            .init(layer: 0, role: "Button", label: "Done", frame: CGRect(x: 10, y: 160, width: 24, height: 24)),
            .init(layer: 0, role: "Button", label: "Info", frame: CGRect(x: 360, y: 160, width: 24, height: 24)),
            .init(layer: 0, role: "Button", label: "Done", frame: CGRect(x: 10, y: 210, width: 24, height: 24)),
        ]
    )
    let capture = capture(scene)
    let info = capture.hitTest(CGPoint(x: 370, y: 120))
    #expect(capture.similar(to: info).map { capture.nodes[$0].frame.minY } == [160])
    let done = capture.hitTest(CGPoint(x: 20, y: 120))
    #expect(capture.similar(to: done).map { capture.nodes[$0].frame.minY } == [160, 210])
    #expect(capture.similar(to: capture.path(from: done)[1].id).map { capture.nodes[$0].frame.minY } == [150, 200])
    #expect(capture.similar(to: capture.hitTest(CGPoint(x: 200, y: 720))) == [])
}

@Test func stitchingMovesContentByItsScrollAndKeepsBarsInPlace() {
    let screenID = UUID(), rowA = UUID(), rowB = UUID()
    func screenComponent() -> RawScene.Component {
        RawScene.Component(id: screenID, parent: nil, layer: 0, name: "ListScreen", source: source(1), frame: CGRect(origin: .zero, size: screen), data: nil)
    }
    func row(_ id: UUID, y: CGFloat) -> RawScene.Component {
        RawScene.Component(id: id, parent: screenID, layer: 0, name: "Row", source: source(9), frame: CGRect(x: 0, y: y, width: 400, height: 100), data: nil)
    }
    func text(_ label: String, y: CGFloat, x: CGFloat = 16) -> RawScene.Element {
        .init(layer: 0, role: "Text", label: label, frame: CGRect(x: x, y: y, width: 100, height: 20))
    }
    let tabBar = RawScene.Element(layer: 0, role: "Tab bar", label: "Tabs", frame: CGRect(x: 0, y: 720, width: 400, height: 80))
    let back = RawScene.Element(layer: 0, role: "Button", label: "Back", frame: CGRect(x: 0, y: 50, width: 60, height: 44))
    let steps = [
        ScrollStep(
            shift: 0, band: 100...720, components: [screenComponent(), row(rowA, y: 600)],
            content: [text("Milk", y: 630), text("Delete", y: 630, x: 280)],
            elements: [tabBar, back, .init(layer: 0, role: "Header", label: "Groceries", frame: CGRect(x: 16, y: 100, width: 200, height: 40))]
        ),
        // The step scrolls exactly six rows, so this row's Delete sits where the first one did.
        ScrollStep(
            shift: 600, band: 94...720, components: [screenComponent(), row(rowB, y: 600)],
            content: [text("Milk", y: 30), text("Eggs", y: 630), text("Delete", y: 630, x: 280), text("Past the end", y: 720)],
            elements: [tabBar, back, .init(layer: 0, role: "Header", label: "Groceries", frame: CGRect(x: 100, y: 55, width: 200, height: 30))]
        ),
    ]
    let capture = capture(Stitch.scene(screen: screen, height: 1400, steps: steps))
    #expect(Report.outline(capture) == """
    Screen  [x 0, y 0, 400 × 1400]
      ListScreen  [x 0, y 0, 400 × 1400]  App/Screen.swift:1
        Button "Back"  [x 0, y 50, 60 × 44]
        Header "Groceries"  [x 16, y 100, 200 × 40]
        Row  [x 0, y 600, 400 × 100]  App/Screen.swift:9
          Text "Milk"  [x 16, y 630, 100 × 20]
          Text "Delete"  [x 280, y 630, 100 × 20]
        Row  [x 0, y 1200, 400 × 100]  App/Screen.swift:9
          Text "Eggs"  [x 16, y 1230, 100 × 20]
          Text "Delete"  [x 280, y 1230, 100 × 20]
        Tab bar "Tabs"  [x 0, y 1320, 400 × 80]
    """)
}
