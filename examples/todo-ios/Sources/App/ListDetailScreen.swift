import Feetback
import SwiftUI

enum Filter: String, CaseIterable, Identifiable {
    case all = "All", open = "Open", done = "Done"
    var id: Self { self }
}

struct ListDetailScreen: View {
    let listID: TodoList.ID
    @Environment(TodoStore.self) private var store
    @State private var filter = Filter.all
    @State private var editing: TodoItem?

    var body: some View {
        if let list = store.list(listID) {
            List {
                Section {
                    ProgressHeader(list: list)
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(visible(list)) { item in
                        TodoRow(item: item) { store.update($0, in: listID) }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = item }
                    }
                    .onDelete { offsets in
                        let items = visible(list)
                        offsets.forEach { store.delete(items[$0].id, from: listID) }
                    }
                }
            }
            .navigationTitle(list.name)
            .safeAreaInset(edge: .bottom) { AddTodoBar { store.add($0, to: listID) } }
            .sheet(item: $editing) { item in
                TodoDetailSheet(item: item, listID: listID)
            }
            .feedback(self)
        }
    }

    private func visible(_ list: TodoList) -> [TodoItem] {
        let items = list.items.filter {
            switch filter {
            case .all: store.showCompleted || !$0.isDone
            case .open: !$0.isDone
            case .done: $0.isDone
            }
        }
        switch store.sortOrder {
        case .manual: return items
        case .dueDate: return items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        case .priority: return items.sorted { Priority.allCases.firstIndex(of: $0.priority)! > Priority.allCases.firstIndex(of: $1.priority)! }
        }
    }
}

struct ProgressHeader: View {
    let list: TodoList

    var body: some View {
        let done = list.items.count - list.remaining
        let fraction = list.items.isEmpty ? 0 : Double(done) / Double(list.items.count)
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(list.color.color.opacity(0.2), lineWidth: 8)
                Circle().trim(from: 0, to: fraction).stroke(list.color.color, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(fraction, format: .percent.precision(.fractionLength(0))).font(.caption.bold().monospacedDigit())
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading) {
                Text("\(done) of \(list.items.count) done").font(.headline)
                Text(list.remaining == 0 ? "All clear" : "\(list.remaining) to go").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .feedback("ProgressHeader", data: (done: done, total: list.items.count))
    }
}

struct TodoRow: View {
    let item: TodoItem
    let onChange: (TodoItem) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(item.isDone ? "Mark not done" : "Mark done", systemImage: item.isDone ? "checkmark.circle.fill" : "circle") {
                var updated = item
                updated.isDone.toggle()
                onChange(updated)
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(item.isDone ? Color.green : Color.secondary)
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).strikethrough(item.isDone).foregroundStyle(item.isDone ? .secondary : .primary)
                if !item.notes.isEmpty {
                    Text(item.notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let due = item.due {
                    Label(due.formatted(.relative(presentation: .named)), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(Calendar.current.isDateInToday(due) ? .red : .secondary)
                }
            }
            Spacer()
            if item.priority != .none {
                Image(systemName: "flag.fill")
                    .foregroundStyle(item.priority == .high ? .red : item.priority == .medium ? .orange : .gray)
                    .accessibilityLabel("\(item.priority.rawValue) priority")
            }
        }
        .padding(.vertical, 6)
        .feedback(self)
    }
}

struct AddTodoBar: View {
    let onAdd: (String) -> Void
    @State private var title = ""

    var body: some View {
        HStack {
            TextField("New todo", text: $title)
                .onSubmit(submit)
            Button("Add", systemImage: "plus.circle.fill", action: submit)
                .labelStyle(.iconOnly)
                .font(.title2)
                .disabled(title.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .feedback(self)
    }

    private func submit() {
        guard !title.isEmpty else { return }
        onAdd(title)
        title = ""
    }
}
