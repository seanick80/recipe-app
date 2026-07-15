import SwiftData
import SwiftUI

struct ArchivedListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // NB: filter only — do NOT add `sort: \GroceryList.archivedAt` here.
    // `@Query(sort:)` on an optional key path (`archivedAt` is `Date?`) crashes
    // SwiftData when the view appears. We sort in memory below instead.
    @Query(
        filter: #Predicate<GroceryList> { $0.archivedAt != nil && $0.locallyDeleted == false }
    ) private var archivedLists: [GroceryList]

    var viewModel: ShoppingViewModel

    /// Most-recently-archived first. Sorted in memory to avoid the optional
    /// key-path `@Query` sort crash.
    private var sortedArchivedLists: [GroceryList] {
        archivedLists.sorted {
            ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast)
        }
    }

    var body: some View {
        // Presented as a .sheet, so it owns its own NavigationStack (matching
        // the sibling menu sheets like TemplateEditorView / MergeListsView).
        // It is deliberately NOT pushed via `.navigationDestination(isPresented:)`
        // from the toolbar Menu — that combination wedges SwiftUI navigation and
        // hangs the UI when the menu dismisses.
        NavigationStack {
            List {
                if sortedArchivedLists.isEmpty {
                    ContentUnavailableView(
                        "No Archived Lists",
                        systemImage: "archivebox",
                        description: Text("Lists you archive will appear here.")
                    )
                } else {
                    ForEach(sortedArchivedLists) { list in
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
                            let list = sortedArchivedLists[index]
                            list.locallyDeleted = true
                            list.pendingRemoteDelete = true
                            list.deletedAt = Date()
                        }
                    }
                }
            }
            .navigationTitle("Archived Lists")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
