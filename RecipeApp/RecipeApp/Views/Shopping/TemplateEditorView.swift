import SwiftData
import SwiftUI

/// Editor for the weekly staples template. Users can add, remove, and
/// reorder items that form the base of each week's shopping list.
struct TemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShoppingTemplate.sortOrder) private var templates: [ShoppingTemplate]

    @State private var showingAddItem = false

    /// Gets or creates the default template.
    private var template: ShoppingTemplate {
        if let existing = templates.first {
            return existing
        }
        let newTemplate = ShoppingTemplate(name: "Weekly Staples")
        modelContext.insert(newTemplate)
        return newTemplate
    }

    private var sortedItems: [TemplateItem] {
        (template.items ?? []).sorted { a, b in
            let catA = ShoppingViewModel.categorySortIndex(a.category)
            let catB = ShoppingViewModel.categorySortIndex(b.category)
            if catA != catB { return catA < catB }
            return a.sortOrder < b.sortOrder
        }
    }

    private var groupedItems: [(String, [TemplateItem])] {
        let items = template.items ?? []
        let grouped = Dictionary(grouping: items) { $0.category }
        let sortedKeys = grouped.keys.sorted {
            ShoppingViewModel.categorySortIndex($0) < ShoppingViewModel.categorySortIndex($1)
        }
        return sortedKeys.map { key in
            let sorted = grouped[key]!.sorted { $0.sortOrder < $1.sortOrder }
            return (key, sorted)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedItems, id: \.0) { category, items in
                    Section(category) {
                        ForEach(items) { item in
                            TemplateItemRow(item: item)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                modelContext.delete(items[index])
                            }
                        }
                    }
                }

                if (template.items ?? []).isEmpty {
                    Section {
                        Text("No staples yet. Tap + to add items you buy every week.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Staples")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddItem = true
                    } label: {
                        Label("Add Staple", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddTemplateItemView(template: template)
            }
        }
    }
}

struct TemplateItemRow: View {
    @Bindable var item: TemplateItem

    var body: some View {
        VStack(alignment: .leading) {
            Text(item.name)
                .font(.body)
            if item.quantity > 0 {
                Text("\(formatQuantity(item.quantity)) \(item.unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatQuantity(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
