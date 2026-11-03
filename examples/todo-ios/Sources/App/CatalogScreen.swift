import Feetback
import SwiftUI

/// A long plain list with pinned section headers, a bar above it, and tagged views nested in
/// repeated rows: the shapes that full-length captures and similar highlights have to handle.
struct CatalogScreen: View {
    @State private var query = ""
    @State private var equipment = "All"

    private static let sections = ["Free Weights", "Machines", "Cables", "Bodyweight", "Bands", "Kettlebells", "Cardio", "Mobility"]
    private static let movements = ["Squat", "Bench Press", "Deadlift", "Overhead Press", "Row", "Curl", "Lunge", "Pulldown", "Fly", "Raise", "Extension", "Shrug"]

    var body: some View {
        List {
            ForEach(Self.sections, id: \.self) { section in
                Section {
                    ForEach(Self.movements.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { movement in
                        Button {} label: { CatalogRow(name: "\(section) \(movement)", detail: movement.count.isMultiple(of: 2) ? "Glutes, Quads, Adductors • Lower Back" : "Chest") }
                            .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(section).font(.headline)
                        Spacer()
                        Button("See \(section.count * 7) More") {}.font(.footnote).underline()
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top) {
            Picker("Equipment", selection: $equipment) {
                ForEach(["All", "Barbell", "Dumbbell", "Machine"], id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Catalog")
        .feedback("CatalogScreen", data: (query: query, equipment: equipment))
    }
}

private struct CatalogRow: View {
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Initials(name: name)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .feedback(self)
    }
}

private struct Initials: View {
    let name: String

    var body: some View {
        Text(name.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined())
            .font(.caption.weight(.bold))
            .frame(width: 36, height: 36)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .feedback(self)
    }
}
