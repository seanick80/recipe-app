import SwiftData
import SwiftUI

/// Displays the active shopping list grouped by store-aisle category order.
/// Checked items sink to the bottom of their category.
struct ShoppingListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var groceryList: GroceryList
    var viewModel: ShoppingViewModel
    @State private var showingAddItem = false

    var body: some View {
        List {
            ForEach(viewModel.categorizedItems(from: groceryList), id: \.0) { category, items in
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
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingAddItem = true
                } label: {
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
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView(groceryList: groceryList)
        }
        .overlay {
            if (groceryList.items ?? []).isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "cart",
                    description: Text("Tap + to add items or edit your staples template.")
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
