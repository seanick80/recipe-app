import SwiftUI
import SwiftData

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryList.createdAt, order: .reverse) private var lists: [GroceryList]
    @State private var showingNewList = false
    @State private var newListName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(lists) { list in
                    NavigationLink {
                        GroceryListDetailView(groceryList: list)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(list.name)
                                .font(.headline)
                            Text("\(list.completedCount)/\(list.items.count) items checked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(lists[index])
                    }
                }
            }
            .navigationTitle("Grocery Lists")
            .toolbar {
                Button(action: { showingNewList = true }) {
                    Label("New List", systemImage: "plus")
                }
            }
            .alert("New Grocery List", isPresented: $showingNewList) {
                TextField("List name", text: $newListName)
                Button("Cancel", role: .cancel) { newListName = "" }
                Button("Create") {
                    let list = GroceryList(name: newListName)
                    modelContext.insert(list)
                    newListName = ""
                }
            }
            .overlay {
                if lists.isEmpty {
                    ContentUnavailableView(
                        "No Lists",
                        systemImage: "cart",
                        description: Text("Tap + to create a grocery list.")
                    )
                }
            }
        }
    }
}

struct GroceryListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var groceryList: GroceryList
    @State private var showingAddItem = false

    var categorizedItems: [(String, [GroceryItem])] {
        let grouped = Dictionary(grouping: groceryList.items) { $0.category }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            ForEach(categorizedItems, id: \.0) { category, items in
                Section(category) {
                    ForEach(items) { item in
                        GroceryItemRow(item: item)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(items[index])
                        }
                    }
                }
            }
        }
        .navigationTitle(groceryList.name)
        .toolbar {
            Button(action: { showingAddItem = true }) {
                Label("Add Item", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView(groceryList: groceryList)
        }
    }
}
