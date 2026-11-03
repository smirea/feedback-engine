import Feetback
import SwiftUI

struct TodoDetailSheet: View {
    @State var item: TodoItem
    let listID: TodoList.ID
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $item.title)
                    TextField("Notes", text: $item.notes, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Toggle("Due date", isOn: Binding(get: { item.due != nil }, set: { item.due = $0 ? .now : nil }))
                    if let due = item.due {
                        DatePicker("Due", selection: Binding(get: { due }, set: { item.due = $0 }), displayedComponents: .date)
                    }
                    Picker("Priority", selection: $item.priority) {
                        ForEach(Priority.allCases) { Text($0.rawValue.capitalized) }
                    }
                }
                Section {
                    Button("Delete Todo", role: .destructive) {
                        store.delete(item.id, from: listID)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.update(item, in: listID)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .feedback(self)
    }
}
