import SwiftData
import SwiftUI

struct ArchivedListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<GroceryList> { $0.archivedAt != nil },
        sort: \GroceryList.archivedAt,
        order: .reverse
    ) private var archivedLists: [GroceryList]

    var viewModel: ShoppingViewModel

    var body: some View {
        List {
            if archivedLists.isEmpty {
                ContentUnavailableView(
                    "No Archived Lists",
                    systemImage: "archivebox",
                    description: Text("Lists you archive will appear here.")
                )
            } else {
                ForEach(archivedLists) { list in
                    NavigationLink {
                        ArchivedListDetailView(groceryList: list, viewModel: viewModel)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.name)
                            HStack(spacing: 12) {
                                Text("\(list.items?.count ?? 0) items")
                                if let archived = list.archivedAt {
                                    Text(archived, style: .date)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(archivedLists[index])
                    }
                }
            }
        }
        .navigationTitle("Archived Lists")
    }
}

struct ArchivedListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let groceryList: GroceryList
    var viewModel: ShoppingViewModel

    var body: some View {
        List {
            ForEach(viewModel.categorizedItems(from: groceryList), id: \.0) { category, items in
                Section(category) {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isChecked ? .green : .gray)
                            Text(item.name)
                            Spacer()
                            if item.quantity > 0 {
                                Text("\(item.quantity, specifier: "%g") \(item.unit)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(groceryList.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    viewModel.restore(groceryList)
                    dismiss()
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
}
