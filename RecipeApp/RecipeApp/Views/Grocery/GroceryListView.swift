import SwiftUI
import SwiftData

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryList.createdAt, order: .reverse) private var lists: [GroceryList]
    @State private var showingNewList = false
    @State private var showingGenerateFromRecipes = false
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
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewList = true }) {
                        Label("New List", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: { showingGenerateFromRecipes = true }) {
                        Label("From Recipes", systemImage: "book")
                    }
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
            .sheet(isPresented: $showingGenerateFromRecipes) {
                GenerateGroceryListView()
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
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddItem = true }) {
                    Label("Add Item", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    removeCheckedItems()
                } label: {
                    Label("Remove Checked", systemImage: "trash")
                }
                .disabled(groceryList.items.filter(\.isChecked).isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    for item in groceryList.items {
                        item.isChecked = false
                    }
                } label: {
                    Label("Uncheck All", systemImage: "arrow.uturn.backward")
                }
                .disabled(groceryList.items.filter(\.isChecked).isEmpty)
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView(groceryList: groceryList)
        }
        .overlay {
            if groceryList.items.isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "cart",
                    description: Text("Tap + to add items to this list.")
                )
            }
        }
    }

    private func removeCheckedItems() {
        let checked = groceryList.items.filter(\.isChecked)
        for item in checked {
            modelContext.delete(item)
        }
    }
}
