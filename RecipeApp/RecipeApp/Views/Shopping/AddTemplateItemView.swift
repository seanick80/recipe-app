import SwiftData
import SwiftUI

/// Form for adding a new item to the weekly staples template.
struct AddTemplateItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let template: ShoppingTemplate

    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = ""
    @State private var category = "Other"

    let categories = ShoppingViewModel.categoryOrder

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $name)
                HStack {
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                    UnitPicker(unit: $unit)
                }
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
            }
            .navigationTitle("Add Staple")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let nextSortOrder = (template.items ?? [])
                            .filter { $0.category == category }
                            .count
                        let item = TemplateItem(
                            name: name,
                            quantity: Double(quantity) ?? 1,
                            unit: unit,
                            category: category,
                            sortOrder: nextSortOrder
                        )
                        item.template = template
                        modelContext.insert(item)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
