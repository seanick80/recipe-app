import SwiftData
import SwiftUI

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryList.createdAt, order: .reverse) private var lists: [GroceryList]
    @State private var showingNewList = false
    @State private var showingGenerateFromRecipes = false
    @State private var newListName = ""
    @State private var renamingList: GroceryList?
    @State private var renameText = ""

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
                            Text("\(list.completedCount)/\(list.items?.count ?? 0) items checked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button {
                            renameText = list.name
                            renamingList = list
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button {
                            duplicateList(list)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            modelContext.delete(list)
                        } label: {
                            Label("Delete", systemImage: "trash")
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
            .alert(
                "Rename List",
                isPresented: Binding(
                    get: { renamingList != nil },
                    set: { if !$0 { renamingList = nil } }
                )
            ) {
                TextField("List name", text: $renameText)
                Button("Cancel", role: .cancel) { renamingList = nil }
                Button("Rename") {
                    renamingList?.name = renameText
                    renamingList = nil
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

    private func duplicateList(_ source: GroceryList) {
        let copy = GroceryList(name: "\(source.name) (Copy)")
        modelContext.insert(copy)
        for item in source.items ?? [] {
            let newItem = GroceryItem(
                name: item.name,
                quantity: item.quantity,
                unit: item.unit,
                category: item.category
            )
            newItem.groceryList = copy
            modelContext.insert(newItem)
        }
    }
}

struct GroceryListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var groceryList: GroceryList
    @State private var showingAddItem = false
    @State private var editingItem: GroceryItem?
    @State private var showingClearAllConfirm = false

    var categorizedItems: [(String, [GroceryItem])] {
        let allItems = groceryList.items ?? []
        let grouped = Dictionary(grouping: allItems) { $0.category }
        let sortedKeys = grouped.keys.sorted {
            ShoppingViewModel.categorySortIndex($0) < ShoppingViewModel.categorySortIndex($1)
        }
        return sortedKeys.map { key in
            let items = grouped[key]!.sorted { a, b in
                if a.isChecked != b.isChecked { return !a.isChecked }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return (key, items)
        }
    }

    var body: some View {
        List {
            ForEach(categorizedItems, id: \.0) { category, items in
                Section(category) {
                    ForEach(items) { item in
                        GroceryItemRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingItem = item
                            }
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
                .disabled((groceryList.items ?? []).filter(\.isChecked).isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    for item in groceryList.items ?? [] {
                        item.isChecked = false
                    }
                } label: {
                    Label("Uncheck All", systemImage: "arrow.uturn.backward")
                }
                .disabled((groceryList.items ?? []).filter(\.isChecked).isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    showingClearAllConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash.slash")
                }
                .disabled((groceryList.items ?? []).isEmpty)
            }
        }
        .confirmationDialog(
            "Clear all items from \(groceryList.name)?",
            isPresented: $showingClearAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All Items", role: .destructive) {
                for item in groceryList.items ?? [] {
                    modelContext.delete(item)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every item in the list. The list itself stays.")
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView(groceryList: groceryList)
        }
        .sheet(item: $editingItem) { item in
            EditGroceryItemView(item: item)
        }
        .overlay {
            if (groceryList.items ?? []).isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "cart",
                    description: Text("Tap + to add items to this list.")
                )
            }
        }
    }

    private func removeCheckedItems() {
        let checked = (groceryList.items ?? []).filter(\.isChecked)
        for item in checked {
            modelContext.delete(item)
        }
    }
}
