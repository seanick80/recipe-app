import SwiftData
import SwiftUI

struct GroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(GrocerySyncService.self) private var grocerySyncService
    @Query(sort: \GroceryList.createdAt, order: .reverse) private var lists: [GroceryList]
    @State private var showingNewList = false
    @State private var showingGenerateFromRecipes = false
    @State private var newListName = ""
    @State private var renamingList: GroceryList?
    @State private var renameText = ""
    @State private var isSelectingForMerge = false
    @State private var selectedForMerge: Set<PersistentIdentifier> = []
    @State private var viewModel = ShoppingViewModel()

    /// Soft-deleted lists are hidden from the UI (they linger for the 30-day
    /// purge window while their DELETE is pushed to the server).
    private var visibleLists: [GroceryList] {
        lists.filter { !$0.locallyDeleted }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleLists) { list in
                    if isSelectingForMerge {
                        Button {
                            if selectedForMerge.contains(list.persistentModelID) {
                                selectedForMerge.remove(list.persistentModelID)
                            } else {
                                selectedForMerge.insert(list.persistentModelID)
                            }
                        } label: {
                            HStack {
                                Image(
                                    systemName: selectedForMerge.contains(list.persistentModelID)
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundStyle(
                                    selectedForMerge.contains(list.persistentModelID)
                                        ? Color.accentColor : .gray
                                )
                                VStack(alignment: .leading) {
                                    Text(list.name).font(.headline)
                                    Text("\(list.completedCount)/\(list.items?.count ?? 0) items checked")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
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
                                softDelete(list)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    guard !isSelectingForMerge else { return }
                    for index in offsets {
                        softDelete(visibleLists[index])
                    }
                }
            }
            .refreshable { await grocerySyncService.sync() }
            .navigationTitle("Grocery Lists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isSelectingForMerge {
                        Button("Cancel") {
                            isSelectingForMerge = false
                            selectedForMerge = []
                        }
                    } else {
                        Button(action: { showingNewList = true }) {
                            Label("New List", systemImage: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    if !isSelectingForMerge {
                        Button(action: { showingGenerateFromRecipes = true }) {
                            Label("From Recipes", systemImage: "book")
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    if !isSelectingForMerge && visibleLists.count >= 2 {
                        Button {
                            isSelectingForMerge = true
                            selectedForMerge = []
                        } label: {
                            Label("Select to Merge", systemImage: "arrow.triangle.merge")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectingForMerge {
                    HStack {
                        Spacer()
                        Button {
                            mergeLists()
                        } label: {
                            Text("Merge (\(selectedForMerge.count))")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedForMerge.count < 2)
                        .padding(.horizontal)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
            .alert("New Grocery List", isPresented: $showingNewList) {
                TextField("List name", text: $newListName)
                Button("Cancel", role: .cancel) { newListName = "" }
                Button("Create") {
                    let list = GroceryList(name: newListName)
                    modelContext.insert(list)
                    list.markDirty()
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
                    renamingList?.markDirty()
                    renamingList = nil
                }
            }
            .overlay {
                if visibleLists.isEmpty {
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

    private func mergeLists() {
        let sources = visibleLists.filter { selectedForMerge.contains($0.persistentModelID) }
        guard sources.count >= 2, let target = sources.first else { return }
        viewModel.mergeLists(sources, into: target, context: modelContext)
        isSelectingForMerge = false
        selectedForMerge = []
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
        copy.markDirty()
    }

    /// Converts a direct delete into a soft-delete queued for a server DELETE.
    /// The record lingers (hidden) for the 30-day purge window; the sync service
    /// pushes the DELETE and then hard-deletes it locally.
    private func softDelete(_ list: GroceryList) {
        list.locallyDeleted = true
        list.pendingRemoteDelete = true
        list.deletedAt = Date()
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
                        groceryList.markDirty()
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
                    groceryList.markDirty()
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
                groceryList.markDirty()
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
        groceryList.markDirty()
    }
}
