import SwiftData
import SwiftUI

struct EditGroceryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: GroceryItem

    @Query(sort: \ShoppingTemplate.sortOrder) private var templates: [ShoppingTemplate]

    @State private var name: String = ""
    @State private var quantity: String = ""
    @State private var unit: String = ""
    @State private var category: String = ""
    @State private var addToStaples: Bool = false

    let categories = ShoppingViewModel.categoryOrder

    private var isAlreadyStaple: Bool {
        guard let template = templates.first else { return false }
        return template.items?.contains { $0.name == item.name } ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $name)
                HStack {
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                    UnitPicker(unit: $unit, context: .shopping)
                }
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0) }
                }

                if !templates.isEmpty {
                    Section {
                        if isAlreadyStaple {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Already in staples")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Toggle("Add to weekly staples", isOn: $addToStaples)
                        }
                    }
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.name = name
                        item.quantity = Double(quantity) ?? 1
                        item.unit = unit
                        item.category = category
                        if addToStaples, let template = templates.first {
                            let nextOrder = (template.items?.count ?? 0)
                            let templateItem = TemplateItem(
                                name: name,
                                quantity: Double(quantity) ?? 1,
                                unit: unit,
                                category: category,
                                sortOrder: nextOrder
                            )
                            templateItem.template = template
                            modelContext.insert(templateItem)
                        }
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                name = item.name
                quantity = formatQuantity(item.quantity)
                unit = item.unit
                category = item.category
            }
        }
    }

    private func formatQuantity(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
