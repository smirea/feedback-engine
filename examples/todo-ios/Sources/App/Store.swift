import Foundation
import Observation
import SwiftUI

enum Priority: String, CaseIterable, Identifiable {
    case none, low, medium, high
    var id: Self { self }
}

enum ListColor: String, CaseIterable {
    case blue, green, orange, purple

    var color: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        }
    }
}

struct TodoItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var notes = ""
    var isDone = false
    var due: Date?
    var priority = Priority.none
}

struct TodoList: Identifiable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
    var color: ListColor
    var items: [TodoItem]

    var remaining: Int { items.filter { !$0.isDone }.count }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case manual, dueDate = "due date", priority
    var id: Self { self }
}

@MainActor @Observable
final class TodoStore {
    var lists: [TodoList]
    var showCompleted = true
    var sortOrder = SortOrder.manual

    init(lists: [TodoList]) {
        self.lists = lists
    }

    func list(_ id: TodoList.ID) -> TodoList? { lists.first { $0.id == id } }

    func update(_ item: TodoItem, in listID: TodoList.ID) {
        guard let l = lists.firstIndex(where: { $0.id == listID }), let i = lists[l].items.firstIndex(where: { $0.id == item.id }) else { return }
        lists[l].items[i] = item
    }

    func add(_ title: String, to listID: TodoList.ID) {
        guard let l = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[l].items.append(TodoItem(id: UUID(), title: title))
    }

    func delete(_ itemID: TodoItem.ID, from listID: TodoList.ID) {
        guard let l = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[l].items.removeAll { $0.id == itemID }
    }

    func addList(named name: String) {
        lists.append(TodoList(id: UUID(), name: name, symbol: "list.bullet", color: ListColor.allCases[lists.count % 4], items: []))
    }

    static func sample() -> TodoStore {
        let day: TimeInterval = 86_400
        let now = Calendar.current.startOfDay(for: .now)
        return TodoStore(lists: [
            TodoList(id: UUID(), name: "Groceries", symbol: "cart", color: .green, items: [
                TodoItem(id: UUID(), title: "Oat milk", priority: .high),
                TodoItem(id: UUID(), title: "Sourdough bread", isDone: true),
                TodoItem(id: UUID(), title: "Bananas", notes: "Not too ripe", due: now + day),
                TodoItem(id: UUID(), title: "Coffee beans", due: now + 2 * day, priority: .medium),
                TodoItem(id: UUID(), title: "Olive oil", isDone: true),
            ] + ["Eggs", "Spinach", "Greek yogurt", "Lemons", "Rice", "Black beans", "Tortillas", "Avocados", "Cheddar", "Tomatoes", "Garlic", "Pasta", "Parmesan", "Apples"].map {
                TodoItem(id: UUID(), title: $0)
            }),
            TodoList(id: UUID(), name: "Work", symbol: "briefcase", color: .blue, items: [
                TodoItem(id: UUID(), title: "Review Q4 roadmap", due: now, priority: .high),
                TodoItem(id: UUID(), title: "Reply to design feedback", notes: "Mention the spacing issue"),
                TodoItem(id: UUID(), title: "Book flights for offsite", due: now + 5 * day, priority: .low),
            ]),
            TodoList(id: UUID(), name: "Home", symbol: "house", color: .orange, items: [
                TodoItem(id: UUID(), title: "Fix leaky faucet", priority: .medium),
                TodoItem(id: UUID(), title: "Water plants", isDone: true),
            ]),
        ])
    }
}
