import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Feedback

private let screen = CGSize(width: 400, height: 800)
private let screenLayer = RawScene.Layer(name: "Screen", frame: CGRect(origin: .zero, size: screen))
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

private func outline(_ capture: Capture) -> String {
    let depths = capture.depths
    return capture.nodes.map { node in
        let frame = [node.frame.minX, node.frame.minY].map(Report.format).joined(separator: ", y ")
        let size = "\(Report.format(node.frame.width)) × \(Report.format(node.frame.height))"
        let source = node.source.map { "  \($0.description)" } ?? ""
        return "\(String(repeating: "  ", count: depths[node.id]))\(node.title)  [x \(frame), \(size)]\(source)"
    }.joined(separator: "\n")
}

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
            shift: 0, band: 100...720, components: [screenComponent(), row(rowA, y: 600)], scrolling: [rowA],
            content: [text("Milk", y: 630), text("Delete", y: 630, x: 280)],
            elements: [tabBar, back, .init(layer: 0, role: "Header", label: "Groceries", frame: CGRect(x: 16, y: 100, width: 200, height: 40))]
        ),
        // The step scrolls exactly six rows, so this row's Delete sits where the first one did.
        ScrollStep(
            shift: 600, band: 94...720, components: [screenComponent(), row(rowB, y: 600)], scrolling: [rowB],
            content: [text("Milk", y: 30), text("Eggs", y: 630), text("Delete", y: 630, x: 280), text("Past the end", y: 720)],
            elements: [tabBar, back, .init(layer: 0, role: "Header", label: "Groceries", frame: CGRect(x: 100, y: 55, width: 200, height: 30))]
        ),
    ]
    let capture = capture(Stitch.scene(screen: screen, height: 1400, viewport: 100...720, layers: [screenLayer], steps: steps))
    #expect(outline(capture) == """
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

@Test func jsonExportHoldsTheItemsAndTheWholeTree() throws {
    let list = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [component("ListScreen", CGRect(x: 0, y: 100, width: 400, height: 600), id: list, data: "filter: open")],
        elements: [.init(layer: 0, role: "Button", label: "Mark done", frame: CGRect(x: 20, y: 210.25, width: 24, height: 24))]
    )
    let capture = capture(scene)
    let button = capture.hitTest(CGPoint(x: 30, y: 220))
    var annotations = Annotations()
    annotations.submit("Make it bigger", on: button)
    let json = Report.json(capture, annotations)
    let document = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(document["app"] as? String == "Demo")
    #expect(document["items"] as? NSArray == [
        ["number": 1, "text": "Make it bigger", "target": 2, "title": "Button \"Mark done\"", "path": [0, 1, 2], "code": "App/Screen.swift:100"],
    ])
    #expect(document["nodes"] as? NSArray == [
        ["id": 0, "layer": 0, "kind": "screen", "name": "Screen", "frame": ["x": 0, "y": 0, "width": 400, "height": 800]],
        ["id": 1, "parent": 0, "layer": 0, "kind": "component", "name": "ListScreen", "frame": ["x": 0, "y": 100, "width": 400, "height": 600], "source": "App/Screen.swift:100", "data": "filter: open"],
        ["id": 2, "parent": 1, "layer": 0, "kind": "element", "name": "Button", "label": "Mark done", "frame": ["x": 20, "y": 210.3, "width": 24, "height": 24]],
    ])
    #expect(document["context"] as? NSArray == [["name": "Store", "value": "Store(count: 2)"]])
}

@Test func aButtonWrappingAComponentBecomesItsParent() {
    let screenID = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [
            component("ListsScreen", CGRect(origin: .zero, size: screen), id: screenID),
            component("ListRow", CGRect(x: 32, y: 329, width: 316, height: 32), parent: screenID),
            RawScene.Component(id: UUID(), parent: screenID, layer: 0, name: "ListRow", source: source(329), frame: CGRect(x: 32, y: 379, width: 316, height: 32), data: nil),
        ],
        elements: [
            .init(layer: 0, role: "Button", label: "Work, 3", frame: CGRect(x: 16, y: 320, width: 368, height: 50)),
            .init(layer: 0, role: "Button", label: "Home, 1", frame: CGRect(x: 16, y: 370, width: 368, height: 50)),
            .init(layer: 0, role: "Header", label: "My Lists", frame: CGRect(x: 32, y: 290, width: 100, height: 20)),
        ]
    )
    let capture = capture(scene)
    #expect(titles(capture.path(from: capture.hitTest(CGPoint(x: 100, y: 340)))) == ["ListRow", "Button \"Work, 3\"", "ListsScreen", "Screen"])
    #expect(titles(capture.path(from: capture.hitTest(CGPoint(x: 370, y: 340)))) == ["Button \"Work, 3\"", "ListsScreen", "Screen"])
    #expect(capture.similar(to: capture.hitTest(CGPoint(x: 100, y: 340))).map { capture.nodes[$0].frame.minY } == [379])
}

@Test func imageCardsGoBesideTheSideTheirTargetIsOnAndTheEnvironmentFillsAGap() {
    let layout = CardLayout.place(
        targets: [
            CGRect(x: 0, y: 50, width: 60, height: 44),
            CGRect(x: 350, y: 50, width: 44, height: 44),
            CGRect(x: 0, y: 600, width: 400, height: 100),
        ],
        heights: [60, 60, 60],
        screen: screen,
        environmentHeight: 150
    )
    #expect(layout.shot == CGRect(x: 340, y: 24, width: 400, height: 800))
    #expect(layout.cards == [
        .init(isLeft: true, origin: CGPoint(x: 24, y: 66)),
        .init(isLeft: false, origin: CGPoint(x: 776, y: 66)),
        .init(isLeft: true, origin: CGPoint(x: 24, y: 644)),
    ])
    #expect(layout.environment == CGPoint(x: 776, y: 150))
    #expect(layout.size == CGSize(width: 1080, height: 848))
}

@Test func theEnvironmentStaysAtTheTopWhenTheRightColumnHasRoom() {
    let layout = CardLayout.place(
        targets: [CGRect(x: 360, y: 700, width: 30, height: 30)], heights: [50], screen: screen, environmentHeight: 200
    )
    #expect(layout.cards == [.init(isLeft: false, origin: CGPoint(x: 776, y: 714))])
    #expect(layout.environment == CGPoint(x: 776, y: 24))
}

private func rowScene() -> RawScene {
    let row = UUID()
    return RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [component("Row", CGRect(x: 0, y: 200, width: 400, height: 60), id: row)],
        elements: [
            .init(layer: 0, role: "Text", label: "Milk", frame: CGRect(x: 16, y: 210, width: 200, height: 40)),
            .init(layer: 0, role: "Button", label: "Delete", frame: CGRect(x: 340, y: 210, width: 40, height: 40)),
        ]
    )
}

@MainActor @Test func unsharedItemsAreTheOnesNoCompletedShareIncluded() {
    let session = Session(capture: capture(rowScene()))
    for (point, text) in [(CGPoint(x: 50, y: 220), "Bigger title"), (CGPoint(x: 350, y: 220), "Wrong color")] {
        session.pick(at: point)
        session.text = text
        session.submit()
    }
    #expect(session.unshared.map(\.text) == ["Bigger title", "Wrong color"])
    session.shared.formUnion(session.items)
    session.remove(session.items[1].id)
    session.pick(at: CGPoint(x: 350, y: 220))
    session.text = "Typo"
    session.submit()
    session.pick(at: CGPoint(x: 50, y: 220))
    session.text = "Huge title"
    session.submit()
    #expect(session.unshared.map(\.text) == ["Huge title", "Typo"])
}

@MainActor @Test func tappingAnItemsBoxEditsItsFeedbackAndOtherLevelsKeepTheirOwn() {
    let session = Session(capture: capture(rowScene()))
    let milk = CGPoint(x: 50, y: 220)
    session.pick(at: milk)
    session.step(to: 1)
    session.text = "Row is too tall"
    session.submit()

    session.text = "Note on the whole screen"
    session.pick(at: milk)
    #expect(session.target.title == "Row")
    #expect(session.text == "Row is too tall")
    session.text = "Row is too tall and grey"
    #expect(session.isTyping)

    session.step(to: 0)
    #expect(session.target.title == "Text \"Milk\"")
    #expect(session.editing == nil)
    #expect(session.text == "Note on the whole screen")

    session.step(to: 1)
    #expect(session.text == "Row is too tall")
    #expect(!session.canSubmit)

    session.pick(at: milk)
    #expect(session.target.title == "Text \"Milk\"")
    session.pick(at: CGPoint(x: 350, y: 220))
    #expect(session.target.title == "Row")
    session.text = "Row is too short"
    session.pick(at: milk)
    #expect(session.target.title == "Row")
    #expect(session.text == "Row is too short")
    session.submit()
    #expect(session.items.map(\.text) == ["Row is too short"])
    #expect(session.text == "Note on the whole screen")
}

@MainActor @Test func typingAtPicksANodeToReferenceWithoutMovingTheTarget() throws {
    let session = Session(capture: capture(rowScene()))
    let delete = CGPoint(x: 350, y: 220)
    session.pick(at: CGPoint(x: 50, y: 220))
    session.text = "Too close to @"
    #expect(session.isReferencing)
    #expect(session.referenceTarget == nil)

    session.pick(at: delete)
    #expect(session.target.title == "Text \"Milk\"")
    #expect(session.referenceTarget?.title == "Button \"Delete\"")
    session.stepReference(to: 1)
    #expect(session.referenceTarget?.title == "Row")
    session.stepReference(to: 0)
    session.insertReference()
    #expect(session.text == "Too close to @1_Button ")
    #expect(!session.isReferencing)

    session.text += "and @"
    session.pick(at: CGPoint(x: 100, y: 255))
    session.insertReference()
    session.text += "below @"
    session.pick(at: delete)
    session.insertReference()
    #expect(session.text == "Too close to @1_Button and @2_Row below @1_Button ")
    session.text += "x"
    session.pick(at: delete)
    #expect(session.target.title == "Button \"Delete\"")

    session.pick(at: CGPoint(x: 50, y: 220))
    session.text = "email@"
    #expect(!session.isReferencing)
}

@MainActor @Test func referencesShareNumbersAndColorsWithItemsInTheOrderTheirNodesWereFirstUsed() throws {
    let session = Session(capture: capture(rowScene()))
    session.pick(at: CGPoint(x: 50, y: 220))
    session.text = "Align with @"
    session.pick(at: CGPoint(x: 350, y: 220))
    session.insertReference()
    session.submit()
    session.pick(at: CGPoint(x: 350, y: 220))
    session.text = "Smaller"
    session.submit()
    let milk = session.items[0].target, delete = session.items[1].target
    #expect([milk, delete].map(session.colorIndex) == [1, 0])
    #expect(session.annotations.segments(session.items[0].text).map { [$0.text, $0.reference?.tag ?? ""] } == [
        ["Align with ", ""], ["@1_Button", "@1"],
    ])

    let document = try #require(JSONSerialization.jsonObject(with: Data(session.json.utf8)) as? [String: Any])
    #expect(document["references"] as? NSArray == [
        ["number": 1, "token": "@1_Button", "target": 3, "title": "Button \"Delete\"", "path": [0, 1, 3], "code": "App/Screen.swift:200"],
    ])
    #expect((document["items"] as? [[String: Any]])?.map { $0["number"] as? Int } == [2, 1])

    session.remove(session.items[1].id)
    session.pick(at: CGPoint(x: 50, y: 300))
    session.text = "Too empty"
    session.submit()
    let after = try #require(JSONSerialization.jsonObject(with: Data(session.json.utf8)) as? [String: Any])
    #expect((after["items"] as? [[String: Any]])?.map { $0["number"] as? Int } == [2, 3])
}

@Test func onlyExactTokensOfKnownReferencesAreReferences() {
    let scene = rowScene()
    let capture = capture(scene)
    var annotations = Annotations()
    let row = annotations.reference(capture.nodes[1])
    let again = annotations.reference(capture.nodes[1])
    #expect(row == again)
    #expect(annotations.segments("@1_Row, @1_Rows and @2_Row").map { [$0.text, $0.reference?.token ?? ""] } == [
        ["@1_Row", "@1_Row"], [", @1_Rows and @2_Row", ""],
    ])
    #expect(annotations.used.isEmpty)
}

private struct ChartValues: DynamicProperty {
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) var scheme
}

private struct ChartContext: DynamicProperty {
    @Environment(\.calendar) private var calendar
    let range: String
}

private struct DashboardCard<Chart: View>: View {
    let title: String
    let value: String?
    let weight: Double
    let goal: Double?
    var values = ChartValues()
    var context = ChartContext(range: "30d")
    @ViewBuilder let chart: Chart

    var body: some View { chart }
}

@MainActor private func card() -> DashboardCard<some View> {
    DashboardCard(title: "Weight", value: "181.6", weight: 72.57477920000001, goal: nil) {
        ProgressView().progressViewStyle(.linear)
    }
}

@Test @MainActor func genericComponentsAreNamedWithoutTheirTypeArguments() {
    #expect(Describer.typeName(card()) == "DashboardCard")
    #expect(Describer.typeName([1]) == "Array")
}

@Test @MainActor func swiftUIWrappersInsideHelperStructsAreSkippedAndValuesReadPlainly() {
    #expect(Describer.describeProperties(of: card()) == "title: Weight\nvalue: 181.6\nweight: 72.575\ngoal: nil\ncontext: ChartContext(range: \"30d\")")
}

@propertyWrapper
private struct Observe<Value> {
    let query: String
    var wrappedValue: Value

    init(wrappedValue: Value, _ query: String) {
        self.query = query
        self.wrappedValue = wrappedValue
    }
}

extension Observe: FeedbackRepresentable {
    var feedbackValue: Any { wrappedValue }
}

@propertyWrapper
private struct Unreported<Value> {
    var wrappedValue: Value
}

private struct WeightRow: View {
    @Observe("latest") var weight: Double? = 81.60000000000001
    @Observe("goal") var goal: Double? = nil
    @Observe("entries") var entries = [Entry(kg: 0.12345, note: nil)]
    @Unreported var token = "secret"

    var body: some View { Text("Weight") }
}

private struct Entry {
    let kg: Double
    let note: String?
}

@Test @MainActor func appPropertyWrappersReportTheirValueThroughFeedbackRepresentable() {
    #expect(Describer.describeProperties(of: WeightRow()) == "weight: 81.6\ngoal: nil\nentries: [Entry(kg: 0.123, note: nil)]")
}

private final class Link {
    var name = "a"
    var next: Link?
}

private enum Phase {
    case idle
    case lifting(set: Int, weight: Double)
    case resting(Double)
}

@Test func nestedValuesStayReadableAndBounded() {
    let link = Link()
    link.next = link
    #expect(Describer.describe(link) == "Link(name: \"a\", next: Link(name: \"a\", next: Link(name: \"a\", next: Link(…))))")
    #expect(Describer.describe(Array(1...12)) == "[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, … 2 more]")
    #expect(Describer.describe(Optional("181.6") as Any) == "181.6")
    #expect(Describer.describe(String?.none as Any) == "nil")
    #expect(Describer.describe([Phase.idle, .lifting(set: 2, weight: 60.00000000001), .resting(90)]) == "[idle, lifting(set: 2, weight: 60), resting(90)]")
    #expect(Describer.describe((number: 1, logged: true, 0.5)) == "(number: 1, logged: true, 0.5)")
    #expect(Describer.describe([Float(0.1), -0.0000004, 3]) == "[0.1, -0.0000004, 3]")
    #expect(Describer.describe(["kg": 72.57477920000001]) == "[\"kg\": 72.575]")
    #expect(Describer.describe(3) == "3")
}

@Test func elementsNestUnderTheInnermostOfComponentsWithTheSameFrame() {
    let homeID = UUID()
    var components = [component("Home", CGRect(origin: .zero, size: screen), id: homeID)]
    var elements: [RawScene.Element] = []
    for index in 0..<12 {
        let card = UUID()
        let frame = CGRect(x: 16, y: CGFloat(index) * 60 + 20, width: 368, height: 50)
        components.append(RawScene.Component(id: card, parent: homeID, layer: 0, name: "Card", source: source(10), frame: frame, data: nil))
        components.append(RawScene.Component(id: UUID(), parent: card, layer: 0, name: "Insight", source: source(20), frame: frame, data: nil))
        elements.append(.init(layer: 0, role: "Text", label: "Value \(index)", frame: frame.insetBy(dx: 10, dy: 10)))
    }
    let capture = capture(RawScene(screen: screen, layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))], components: components, elements: elements))
    let paths = (0..<12).map { titles(capture.path(from: capture.hitTest(CGPoint(x: 100, y: CGFloat($0) * 60 + 45)))) }
    #expect(paths == (0..<12).map { ["Text \"Value \($0)\"", "Insight", "Card", "Home", "Screen"] })
}

@Test func anElementStickingOutOfItsComponentStaysWithIt() throws {
    let homeID = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [
            component("DashboardHome", CGRect(origin: .zero, size: screen), id: homeID),
            component("CycleFocus", CGRect(x: 16, y: 100, width: 368, height: 200), parent: homeID),
            component("Badge", CGRect(x: 200, y: 150.33, width: 60, height: 20.33), parent: homeID),
            component("Streak", CGRect(x: 300, y: 400, width: 60, height: 20), parent: homeID),
        ],
        elements: [
            .init(layer: 0, role: "Text", label: "Week 3", frame: CGRect(x: 32, y: 280, width: 120, height: 22.5)),
            .init(layer: 0, role: "Button", label: "Open cycle", frame: CGRect(x: 0, y: 240, width: 400, height: 100)),
            .init(layer: 0, role: "Text", label: "Badge", frame: CGRect(x: 200, y: 150, width: 60, height: 21)),
            .init(layer: 0, role: "Text", label: "12 days", frame: CGRect(x: 298, y: 400, width: 64, height: 20)),
        ]
    )
    let capture = capture(scene)
    #expect(titles(capture.path(from: capture.hitTest(CGPoint(x: 60, y: 290)))) == ["Text \"Week 3\"", "CycleFocus", "DashboardHome", "Screen"])
    #expect(titles(capture.path(from: capture.hitTest(CGPoint(x: 8, y: 320)))) == ["Button \"Open cycle\"", "DashboardHome", "Screen"])
    let badge = try #require(capture.nodes.first { $0.label == "Badge" })
    #expect(titles(capture.path(from: badge.id)) == ["Text \"Badge\"", "Badge", "DashboardHome", "Screen"])
    let streak = try #require(capture.nodes.first { $0.label == "12 days" })
    #expect(titles(capture.path(from: streak.id)) == ["Text \"12 days\"", "Streak", "DashboardHome", "Screen"])
}

@Test func similarFindsTheSamePartWhenTheRepeatedComponentWrapsTheTaggedOne() {
    let pageID = UUID()
    var components = [component("DayPage", CGRect(origin: .zero, size: screen), id: pageID)]
    var elements: [RawScene.Element] = []
    for index in 0..<3 {
        let entry = UUID()
        let y = 100 + CGFloat(index) * 80
        components.append(RawScene.Component(id: entry, parent: pageID, layer: 0, name: "EntryRow", source: source(30), frame: CGRect(x: 0, y: y, width: 400, height: 70), data: nil))
        components.append(RawScene.Component(id: UUID(), parent: entry, layer: 0, name: "FoodRow", source: source(60), frame: CGRect(x: 60, y: y + 5, width: 300, height: 60), data: nil))
        elements.append(.init(layer: 0, role: "Text", label: "Food \(index)", frame: CGRect(x: 70, y: y + 10, width: 200, height: 20)))
        elements.append(.init(layer: 0, role: "Text", label: "08:0\(index)", frame: CGRect(x: 8, y: y + 10, width: 40, height: 20)))
    }
    let capture = capture(RawScene(screen: screen, layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))], components: components, elements: elements))
    let food = capture.hitTest(CGPoint(x: 100, y: 120))
    #expect(titles(capture.path(from: food)) == ["Text \"Food 0\"", "FoodRow", "EntryRow", "DayPage", "Screen"])
    #expect(capture.similar(to: food).map { capture.nodes[$0].title } == ["Text \"Food 1\"", "Text \"Food 2\""])
    #expect(capture.similar(to: capture.path(from: food)[1].id).map { capture.nodes[$0].frame.minY } == [185, 265])
    #expect(capture.similar(to: capture.hitTest(CGPoint(x: 20, y: 120))).map { capture.nodes[$0].title } == ["Text \"08:01\"", "Text \"08:02\""])
}

@Test func aFullScreenLayerHidesTheLayersUnderIt() throws {
    let base = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [
            .init(name: "Screen", frame: CGRect(origin: .zero, size: screen)),
            .init(name: "Sheet", frame: CGRect(x: 0, y: 400, width: 400, height: 400)),
            .init(name: "Full-screen cover", frame: CGRect(origin: .zero, size: screen)),
        ],
        components: [
            component("HistoryScreen", CGRect(origin: .zero, size: screen), id: base),
            component("Row", CGRect(x: 0, y: 100, width: 400, height: 40), parent: base),
            component("Picker", CGRect(x: 0, y: 400, width: 400, height: 400), layer: 1),
            component("Summary", CGRect(origin: .zero, size: screen), layer: 2),
        ],
        elements: [
            .init(layer: 0, role: "Text", label: "Upper", frame: CGRect(x: 16, y: 110, width: 100, height: 20)),
            .init(layer: 2, role: "Button", label: "Done", frame: CGRect(x: 300, y: 60, width: 80, height: 44)),
        ]
    )
    let capture = capture(scene)
    let document = try #require(JSONSerialization.jsonObject(with: Data(Report.json(capture, Annotations()).utf8)) as? [String: Any])
    #expect((document["nodes"] as? [[String: Any]])?.map { "\($0["kind"]!) \($0["name"]!)" } == [
        "screen Screen", "layer Full-screen cover", "component Summary", "element Button",
    ])
}

@Test func aSheetLeavesOutOnlyWhatItCompletelyCovers() {
    let base = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [
            .init(name: "Screen", frame: CGRect(origin: .zero, size: screen)),
            .init(name: "Sheet", frame: CGRect(x: 0, y: 400, width: 400, height: 400)),
        ],
        components: [
            component("ListScreen", CGRect(origin: .zero, size: screen), id: base),
            component("Row", CGRect(x: 0, y: 100, width: 400, height: 40), parent: base),
            component("Row", CGRect(x: 0, y: 500, width: 400, height: 40), parent: base),
            component("DetailSheet", CGRect(x: 0, y: 400, width: 400, height: 400), layer: 1),
        ],
        elements: [.init(layer: 0, role: "Text", label: "Behind", frame: CGRect(x: 16, y: 510, width: 100, height: 20))]
    )
    #expect(outline(capture(scene)) == """
    Screen  [x 0, y 0, 400 × 800]
      ListScreen  [x 0, y 0, 400 × 800]  App/Screen.swift:1
        Row  [x 0, y 100, 400 × 40]  App/Screen.swift:100
      Sheet  [x 0, y 400, 400 × 400]
        DetailSheet  [x 0, y 400, 400 × 400]  App/Screen.swift:400
    """)
}

@Test func framesAreClippedToTheCapture() {
    let scroller = UUID()
    let scene = RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [
            component("Scroller", CGRect(x: 0, y: -200, width: 400, height: 1400), id: scroller),
            component("Row", CGRect(x: 0, y: 780, width: 400, height: 60), parent: scroller),
        ],
        elements: [.init(layer: 0, role: "Header", label: "Top", frame: CGRect(x: 16, y: -17, width: 200, height: 40))]
    )
    #expect(outline(capture(scene)) == """
    Screen  [x 0, y 0, 400 × 800]
      Scroller  [x 0, y 0, 400 × 800]  App/Screen.swift:-200
        Header "Top"  [x 16, y 0, 200 × 23]
        Row  [x 0, y 780, 400 × 20]  App/Screen.swift:780
    """)
}

/// A plain `List` under a nav bar and a filter bar, captured from partway down. The band starts at
/// 200 below the bars, and the large title collapses once it scrolls. Step 0 has rows hidden above
/// the band; the capturer starts later bands below the pinned "Free Weights" header.
@Test func stitchingKeepsOneHeaderPerSectionAndNothingUnderTheTopBars() {
    let screenID = UUID(), browserID = UUID()
    let screenComponent = RawScene.Component(id: screenID, parent: nil, layer: 0, name: "LibraryScreen", source: source(1), frame: CGRect(origin: .zero, size: screen), data: nil)
    func browser(y: CGFloat) -> RawScene.Component {
        RawScene.Component(id: browserID, parent: screenID, layer: 0, name: "Browser", source: source(5), frame: CGRect(x: 0, y: y, width: 400, height: 720 - y), data: nil)
    }
    func row(_ id: UUID, y: CGFloat) -> RawScene.Component {
        RawScene.Component(id: id, parent: browserID, layer: 0, name: "Row", source: source(9), frame: CGRect(x: 0, y: y, width: 400, height: 80), data: nil)
    }
    func text(_ label: String, y: CGFloat, role: String = "Text") -> RawScene.Element {
        .init(layer: 0, role: role, label: label, frame: CGRect(x: 16, y: y, width: 100, height: 20))
    }
    let tabBar = RawScene.Element(layer: 0, role: "Tab bar", label: "Tabs", frame: CGRect(x: 0, y: 720, width: 400, height: 80))
    let filter = RawScene.Element(layer: 0, role: "Button", label: "Filter", frame: CGRect(x: 16, y: 150, width: 80, height: 30))
    let above = UUID(), rowA = UUID(), rowB = UUID(), rowC = UUID()
    let steps = [
        ScrollStep(
            shift: 0, band: 200...720,
            components: [screenComponent, browser(y: 100), row(above, y: 100), row(rowA, y: 400)], scrolling: [above, rowA],
            content: [text("Free Weights", y: 210, role: "Header"), text("Squat", y: 130), text("Hidden", y: -17), text("Press", y: 420)],
            elements: [tabBar, filter, text("Exercises", y: 60, role: "Header")]
        ),
        ScrollStep(
            shift: 400, band: 244...720,
            components: [screenComponent, browser(y: 60), row(rowA, y: 0), row(rowB, y: 500), row(rowC, y: 640)], scrolling: [rowA, rowB, rowC],
            content: [text("Free Weights", y: 210, role: "Header"), text("Press", y: 20), text("Machines", y: 450, role: "Header"), text("Row", y: 520), text("Leg Press", y: 660)],
            elements: [tabBar, filter, text("Exercises", y: 50, role: "Header")]
        ),
    ]
    let capture = capture(Stitch.scene(screen: screen, height: 1200, viewport: 200...720, layers: [screenLayer], steps: steps))
    #expect(outline(capture) == """
    Screen  [x 0, y 0, 400 × 1200]
      LibraryScreen  [x 0, y 0, 400 × 1200]  App/Screen.swift:1
        Header "Exercises"  [x 16, y 60, 100 × 20]
        Browser  [x 0, y 100, 400 × 1020]  App/Screen.swift:5
          Button "Filter"  [x 16, y 150, 80 × 30]
          Header "Free Weights"  [x 16, y 210, 100 × 20]
          Row  [x 0, y 400, 400 × 80]  App/Screen.swift:9
            Text "Press"  [x 16, y 420, 100 × 20]
          Header "Machines"  [x 16, y 850, 100 × 20]
          Row  [x 0, y 900, 400 × 80]  App/Screen.swift:9
            Text "Row"  [x 16, y 920, 100 × 20]
          Row  [x 0, y 1040, 400 × 80]  App/Screen.swift:9
            Text "Leg Press"  [x 16, y 1060, 100 × 20]
        Tab bar "Tabs"  [x 0, y 1120, 400 × 80]
    """)
}

/// A sheet over a list screen, with its own list scrolled by 500 points between steps. The screen
/// shows only above the sheet, and the sheet grows with its content.
@Test func stitchingASheetKeepsTheScreenBehindItAndStretchesTheSheet() {
    let screenID = UUID(), sheetID = UUID(), rowA = UUID(), rowB = UUID(), hidden = UUID()
    let screenComponent = RawScene.Component(id: screenID, parent: nil, layer: 0, name: "ListScreen", source: source(1), frame: CGRect(origin: .zero, size: screen), data: nil)
    let behind = RawScene.Component(id: hidden, parent: screenID, layer: 0, name: "Row", source: source(9), frame: CGRect(x: 0, y: 300, width: 400, height: 80), data: nil)
    let sheetComponent = RawScene.Component(id: sheetID, parent: nil, layer: 1, name: "DetailSheet", source: source(60), frame: CGRect(x: 0, y: 60, width: 400, height: 740), data: nil)
    func row(_ id: UUID, y: CGFloat) -> RawScene.Component {
        RawScene.Component(id: id, parent: sheetID, layer: 1, name: "Option", source: source(70), frame: CGRect(x: 0, y: y, width: 400, height: 80), data: nil)
    }
    func text(_ label: String, y: CGFloat, layer: Int = 1) -> RawScene.Element {
        .init(layer: layer, role: "Text", label: label, frame: CGRect(x: 16, y: y, width: 100, height: 20))
    }
    let chrome = [
        RawScene.Element(layer: 0, role: "Button", label: "Back", frame: CGRect(x: 0, y: 10, width: 60, height: 40)),
        text("Milk", y: 320, layer: 0),
        RawScene.Element(layer: 1, role: "Button", label: "Done", frame: CGRect(x: 320, y: 70, width: 60, height: 40)),
    ]
    let steps = [
        ScrollStep(
            shift: 0, band: 120...760, components: [screenComponent, behind, sheetComponent, row(rowA, y: 600)], scrolling: [rowA],
            content: [text("First", y: 630)], elements: chrome
        ),
        ScrollStep(
            shift: 500, band: 120...760, components: [screenComponent, behind, sheetComponent, row(rowA, y: 100), row(rowB, y: 640)], scrolling: [rowA, rowB],
            content: [text("First", y: 130), text("Last", y: 670)], elements: chrome
        ),
    ]
    let layers = [screenLayer, RawScene.Layer(name: "Sheet", frame: CGRect(x: 0, y: 60, width: 400, height: 740))]
    let capture = capture(Stitch.scene(screen: screen, height: 1300, viewport: 120...760, layers: layers, steps: steps))
    #expect(outline(capture) == """
    Screen  [x 0, y 0, 400 × 1300]
      ListScreen  [x 0, y 0, 400 × 1300]  App/Screen.swift:1
        Button "Back"  [x 0, y 10, 60 × 40]
      Sheet  [x 0, y 60, 400 × 1240]
        DetailSheet  [x 0, y 60, 400 × 1240]  App/Screen.swift:60
          Button "Done"  [x 320, y 70, 60 × 40]
          Option  [x 0, y 600, 400 × 80]  App/Screen.swift:70
            Text "First"  [x 16, y 630, 100 × 20]
          Option  [x 0, y 1140, 400 × 80]  App/Screen.swift:70
            Text "Last"  [x 16, y 1170, 100 × 20]
    """)
    #expect(capture.path(from: capture.hitTest(CGPoint(x: 30, y: 1180))).map(\.title) == ["Text \"Last\"", "Option", "DetailSheet", "Sheet", "Screen"])
}

@Test func aCappedCaptureEndsBetweenRows() {
    let rows = [CGRect(x: 0, y: 100, width: 400, height: 80), CGRect(x: 0, y: 180, width: 400, height: 80), CGRect(x: 0, y: 260, width: 400, height: 80)]
    let texts = [CGRect(x: 16, y: 270, width: 100, height: 20), CGRect(x: 16, y: 300, width: 100, height: 20)]
    #expect(Stitch.cut(atMost: 300, after: 120, frames: rows + texts) == 260)
    #expect(Stitch.cut(atMost: 340, after: 120, frames: rows + texts) == 340)
    #expect(Stitch.cut(atMost: 250, after: 190, frames: rows) == nil)
}

private indirect enum Chain {
    case end
    case next(Chain)
}

@Test func everyKindOfNestingStopsAtTheDepthLimitAndTinyNumbersKeepTheirDigits() {
    #expect(Describer.describe([[[[[1]]]], [[[]]]]) == "[[[[…]]], [[[]]]]")
    #expect(Describer.describe(Chain.next(.next(.next(.next(.end))))) == "next(next(next(next(…))))")
    #expect(Describer.describe([[["k": (1, 2)]]]) == "[[[\"k\": (…)]]]")
    #expect(Describer.describe([1.2345e-16, -0.0004, 0]) == "[1.23e-16, -0.0004, 0]")
}

@Test func contextValuesNestDeeperThanComponentData() {
    let nested = [[[[[1]]]]]
    #expect(Describer.describe(nested) == "[[[[…]]]]")
    #expect(Describer.describe(nested, limit: 8000) == "[[[[[1]]]]]")
}

/// A `LazyVStack` with pinned headers and footers under a 100-point bar and over a tab bar at 700.
/// Section B's footer is pinned at the bottom of the first two steps, so the capturer ends their
/// bands above it, and it reaches its own place on the last step, where it was pinned on the first.
@Test func stitchingKeepsPinnedFootersOutUntilTheirSectionEnds() {
    let screenID = UUID(), headerA = UUID(), headerB = UUID(), footerB = UUID()
    let screenComponent = RawScene.Component(id: screenID, parent: nil, layer: 0, name: "WeekScreen", source: source(1), frame: CGRect(origin: .zero, size: screen), data: nil)
    func header(_ id: UUID, y: CGFloat) -> RawScene.Component {
        RawScene.Component(id: id, parent: screenID, layer: 0, name: "SectionHeader", source: source(20), frame: CGRect(x: 0, y: y, width: 400, height: 40), data: nil)
    }
    let footer = RawScene.Component(id: footerB, parent: screenID, layer: 0, name: "SectionFooter", source: source(30), frame: CGRect(x: 0, y: 680, width: 400, height: 20), data: nil)
    func text(_ label: String, y: CGFloat) -> RawScene.Element {
        .init(layer: 0, role: "Text", label: label, frame: CGRect(x: 16, y: y, width: 100, height: 20))
    }
    let bars = [
        RawScene.Element(layer: 0, role: "Tab bar", label: "Tabs", frame: CGRect(x: 0, y: 700, width: 400, height: 100)),
        RawScene.Element(layer: 0, role: "Header", label: "Week", frame: CGRect(x: 16, y: 50, width: 100, height: 20)),
    ]
    let steps = [
        ScrollStep(
            shift: 0, band: 100...680,
            components: [screenComponent, header(headerA, y: 100), header(headerB, y: 360), footer], scrolling: [headerA, headerB, footerB],
            content: [text("A", y: 110), text("A1", y: 170), text("A2", y: 270), text("A footer", y: 340), text("B", y: 370), text("B1", y: 430), text("B2", y: 530), text("B3", y: 630), text("B total", y: 680)],
            elements: bars
        ),
        ScrollStep(
            shift: 540, band: 140...680,
            components: [screenComponent, header(headerB, y: 100), footer], scrolling: [headerB, footerB],
            content: [text("B", y: 110), text("B3", y: 90), text("B4", y: 190), text("B5", y: 290), text("B6", y: 390), text("B7", y: 490), text("B8", y: 590), text("B9", y: 690), text("B total", y: 680)],
            elements: bars
        ),
        ScrollStep(
            shift: 720, band: 140...700,
            components: [screenComponent, header(headerB, y: 100), footer], scrolling: [headerB, footerB],
            content: [text("B", y: 110), text("B8", y: 410), text("B9", y: 510), text("B10", y: 610), text("B total", y: 680)],
            elements: bars
        ),
    ]
    let capture = capture(Stitch.scene(screen: screen, height: 1520, viewport: 100...700, layers: [screenLayer], steps: steps))
    #expect(outline(capture) == """
    Screen  [x 0, y 0, 400 × 1520]
      WeekScreen  [x 0, y 0, 400 × 1520]  App/Screen.swift:1
        Header "Week"  [x 16, y 50, 100 × 20]
        SectionHeader  [x 0, y 100, 400 × 40]  App/Screen.swift:20
          Text "A"  [x 16, y 110, 100 × 20]
        Text "A1"  [x 16, y 170, 100 × 20]
        Text "A2"  [x 16, y 270, 100 × 20]
        Text "A footer"  [x 16, y 340, 100 × 20]
        SectionHeader  [x 0, y 360, 400 × 40]  App/Screen.swift:20
          Text "B"  [x 16, y 370, 100 × 20]
        Text "B1"  [x 16, y 430, 100 × 20]
        Text "B2"  [x 16, y 530, 100 × 20]
        Text "B3"  [x 16, y 630, 100 × 20]
        Text "B4"  [x 16, y 730, 100 × 20]
        Text "B5"  [x 16, y 830, 100 × 20]
        Text "B6"  [x 16, y 930, 100 × 20]
        Text "B7"  [x 16, y 1030, 100 × 20]
        Text "B8"  [x 16, y 1130, 100 × 20]
        Text "B9"  [x 16, y 1230, 100 × 20]
        Text "B10"  [x 16, y 1330, 100 × 20]
        SectionFooter  [x 0, y 1400, 400 × 20]  App/Screen.swift:30
          Text "B total"  [x 16, y 1400, 100 × 20]
        Tab bar "Tabs"  [x 0, y 1420, 400 × 100]
    """)
}

@Test func aTaskTitleCountsTheChangesUntilTheModelSummarizesThem() throws {
    let scene = RawScene(
        screen: screen,
        layers: [.init(name: "Screen", frame: CGRect(origin: .zero, size: screen))],
        components: [component("ListScreen", CGRect(x: 0, y: 100, width: 400, height: 600))],
        elements: [.init(layer: 0, role: "Button", label: "Mark done", frame: CGRect(x: 20, y: 210, width: 24, height: 24))]
    )
    var capture = capture(scene)
    let button = capture.hitTest(CGPoint(x: 30, y: 220))
    let one = TaskTitle(capture, items: [FeedbackItem(target: button, text: "Make it\nbigger")])
    #expect(one.placeholder == "Demo Feedback: 1 change")
    #expect(one.prompt == "- On Button \"Mark done\": Make it bigger")

    capture.screenName = "Groceries"
    let two = TaskTitle(capture, items: [FeedbackItem(target: button, text: "Make it bigger"), FeedbackItem(target: 0, text: "Too dark")])
    #expect(two.placeholder == "Groceries Feedback: 2 changes")
    #expect(two.prompt == "- On Button \"Mark done\": Make it bigger\n- On Screen: Too dark")
    #expect(two.summarized("\"Bigger done button, lighter screen.\"\nThat covers both.") == "2 Groceries Feedback: Bigger done button, lighter screen")
    #expect(two.summarized(" \n") == nil)
    #expect(try JSONDecoder().decode(TaskTitle.self, from: JSONEncoder().encode(two)) == two)
}

/// `spec/fixtures/capture.json`: one built tree with the answers every platform must give for it.
/// The web package's `fixtures.test.ts` reads the same file.
private struct Fixture: Decodable {
    struct Rect: Decodable {
        let x, y, width, height: CGFloat
        var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    struct Point: Decodable {
        let x, y: CGFloat
    }

    struct Size: Decodable {
        let width, height: CGFloat
    }

    struct Entry: Decodable {
        let name, value: String
    }

    struct TreeNode: Decodable {
        let id: Int
        let parent: Int?
        let layer: Int
        let kind, name: String
        let label, source, data: String?
        let frame: Rect
    }

    struct Step: Decodable {
        let submit: String?
        let on: Int?
        let reference: Int?
    }

    struct Cards: Decodable {
        let targets: [Rect]
        let heights: [CGFloat]
        let environmentHeight: CGFloat
    }

    struct Layout: Decodable {
        struct Card: Decodable {
            let isLeft: Bool
            let origin: Point
        }

        let shot: Rect
        let cards: [Card]
        let environment: Point
        let size: Size
    }

    struct Title: Decodable {
        let placeholder, prompt, summarized: String
    }

    struct Expected: Decodable {
        let hitTests: [Int]
        let similar: [[Int]]
        let colorIndexes: [Int]
        let cards: Layout
        let taskTitle: Title
    }

    let captured: Date
    let size: Size
    let visible: Rect
    let screenName: String
    let environment, context: [Entry]
    let nodes: [TreeNode]
    let annotate: [Step]
    let hitTests: [[CGFloat]]
    let similar: [Int]
    let segments: String
    let cards: Cards
    let summary: String
    let expected: Expected
}

@Test func theSharedFixtureGivesTheSameAnswersAsOnTheWeb() throws {
    let url = URL(fileURLWithPath: #filePath).appending(path: "../../../../../spec/fixtures/capture.json").standardized
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let fixture = try decoder.decode(Fixture.self, from: data)
    let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let expected = try #require(raw["expected"] as? [String: Any])

    let nodes = fixture.nodes.map { node in
        let kind: Node.Kind = switch node.kind {
        case "screen": .screen
        case "layer": .layer
        case "component":
            {
                let parts = node.source!.split(separator: ":")
                return .component(CodeLocation(file: String(parts[0]), line: Int(parts[1])!))
            }()
        default: .element(role: node.name)
        }
        return Node(id: node.id, parent: node.parent, layer: node.layer, kind: kind, name: node.name, label: node.label, frame: node.frame.cgRect, data: node.data)
    }
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let screen = CGSize(width: fixture.size.width, height: fixture.size.height)
    let capture = Capture(
        date: fixture.captured, screen: screen, visible: fixture.visible.cgRect, scale: 1, image: context.makeImage()!, nodes: nodes,
        environment: fixture.environment.map { ContextEntry(name: $0.name, value: $0.value) },
        context: fixture.context.map { ContextEntry(name: $0.name, value: $0.value) },
        screenName: fixture.screenName
    )

    var annotations = Annotations()
    for step in fixture.annotate {
        if let text = step.submit, let target = step.on {
            annotations.submit(text, on: target)
        } else if let node = step.reference {
            _ = annotations.reference(nodes[node])
        }
    }

    #expect(fixture.hitTests.map { capture.hitTest(CGPoint(x: $0[0], y: $0[1])) } == fixture.expected.hitTests)
    #expect(fixture.similar.map { capture.similar(to: $0) } == fixture.expected.similar)
    #expect(nodes.map { annotations.colorIndex(of: $0.id) } == fixture.expected.colorIndexes)
    let segments = annotations.segments(fixture.segments).map { [$0.text, $0.reference?.number ?? 0] as NSArray }
    #expect(segments as NSArray == expected["segments"] as? NSArray)

    let report = try #require(JSONSerialization.jsonObject(with: Data(Report.json(capture, annotations).utf8)) as? NSDictionary)
    #expect(report == expected["report"] as? NSDictionary)

    let layout = CardLayout.place(targets: fixture.cards.targets.map(\.cgRect), heights: fixture.cards.heights, screen: screen, environmentHeight: fixture.cards.environmentHeight)
    let wanted = fixture.expected.cards
    #expect(layout.shot == wanted.shot.cgRect)
    #expect(layout.cards == wanted.cards.map { .init(isLeft: $0.isLeft, origin: CGPoint(x: $0.origin.x, y: $0.origin.y)) })
    #expect(layout.environment == CGPoint(x: wanted.environment.x, y: wanted.environment.y))
    #expect(layout.size == CGSize(width: wanted.size.width, height: wanted.size.height))

    let title = TaskTitle(capture, items: annotations.items)
    #expect(title.placeholder == fixture.expected.taskTitle.placeholder)
    #expect(title.prompt == fixture.expected.taskTitle.prompt)
    #expect(title.summarized(fixture.summary) == fixture.expected.taskTitle.summarized)
}

@Test func aFailedRequestKeepsWhatWasSentAndWhatCameBack() throws {
    let url = URL(string: "https://procrastimate.stf.lol/api/images?id=abc&size=full")!
    let refused = Problem.request("PUT", url, status: 413, body: Data(#"{"message":"A part is at most 1500000 bytes"}"#.utf8), error: CocoaError(.fileWriteOutOfSpace))
    let posted = refused.with(before: [.init(label: "Step", value: "Uploading the image")], after: [.init(label: "App", value: "Demo")])
    #expect(posted.message == CocoaError(.fileWriteOutOfSpace).localizedDescription)
    #expect(posted.facts.map(\.label) == ["Step", "Request", "Status", "Response", "Error", "App"])
    #expect(posted.details.hasPrefix("""
        Step: Uploading the image
        Request: PUT https://procrastimate.stf.lol/api/images?id=abc&size=full
        Status: 413
        Response: {"message":"A part is at most 1500000 bytes"}
        Error: 
        """))
    #expect(posted.text == "\(posted.message)\n\n\(posted.details)")
    #expect(!posted.retryable)
    #expect(posted.status == 413)
    #expect([401, 408, 429, 500, 502].allSatisfy { Problem.request("PUT", url, status: $0, body: nil, error: CocoaError(.fileNoSuchFile)).retryable })
    #expect([400, 403, 404, 413].allSatisfy { !Problem.request("PUT", url, status: $0, body: nil, error: CocoaError(.fileNoSuchFile)).retryable })

    let offline = Problem.request("GET", url, status: nil, body: nil, error: URLError(.timedOut))
    #expect(offline.facts.map(\.label) == ["Request", "Error"])
    #expect(offline.facts[1].value.contains("-1001"))
    #expect(offline.retryable)
    #expect(try JSONDecoder().decode(Problem.self, from: JSONEncoder().encode(offline)) == offline)
    #expect(Problem(offline) == offline)

    let plain = Problem(CocoaError(.fileNoSuchFile))
    #expect(plain.facts.map(\.label) == ["Error"])
    #expect(Problem(message: "Nothing else").text == "Nothing else")
}
