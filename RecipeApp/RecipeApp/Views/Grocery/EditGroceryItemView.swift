import SwiftUI

struct EditGroceryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: GroceryItem

    @State private var name: String = ""
    @State private var quantity: String = ""
    @State private var unit: String = ""
    @State private var category: String = ""

    let categories = ShoppingViewModel.categoryOrder

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
