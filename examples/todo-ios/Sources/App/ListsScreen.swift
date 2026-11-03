import Feetback
import SwiftUI

struct ListsScreen: View {
    @Environment(TodoStore.self) private var store
    @State private var isAddingList = false
    @State private var newListName = ""

    var body: some View {
        List {
            Section {
                SummaryCard(lists: store.lists)
            }
            Section("My Lists") {
                ForEach(store.lists) { list in
                    NavigationLink(value: list.id) { ListRow(list: list) }
                }
            }
        }
        .navigationTitle("Lists")
        .navigationDestination(for: TodoList.ID.self) { ListDetailScreen(listID: $0) }
        .toolbar {
            Button("New List", systemImage: "plus") { isAddingList = true }
        }
        .alert("New List", isPresented: $isAddingList) {
            TextField("Name", text: $newListName)
            Button("Add") {
                store.addList(named: newListName)
                newListName = ""
            }
            Button("Cancel", role: .cancel) {}
        }
        .feedback(self)
    }
}

struct SummaryCard: View {
    let lists: [TodoList]

    var body: some View {
        let open = lists.reduce(0) { $0 + $1.remaining }
        let today = lists.flatMap(\.items).filter { !$0.isDone && $0.due.map(Calendar.current.isDateInToday) == true }.count
        HStack(spacing: 12) {
            Stat(value: open, label: "Open", color: .blue)
            Stat(value: today, label: "Due today", color: .red)
            Stat(value: lists.count, label: "Lists", color: .gray)
        }
        .padding(.vertical, 4)
        .feedback(self)
    }
}

struct Stat: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .feedback(self)
    }
}

struct ListRow: View {
    let list: TodoList

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: list.symbol)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(list.color.color, in: Circle())
            Text(list.name)
            Spacer()
            Text("\(list.remaining)").foregroundStyle(.secondary)
        }
        .feedback("ListRow", data: (name: list.name, remaining: list.remaining, total: list.items.count))
    }
}
