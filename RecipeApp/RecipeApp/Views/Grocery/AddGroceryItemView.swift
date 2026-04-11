import SwiftData
import SwiftUI

struct AddGroceryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let groceryList: GroceryList

    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = ""
    @State private var category = "Other"

    let categories = [
        "Produce", "Dairy", "Meat", "Bakery", "Frozen", "Canned", "Snacks", "Beverages", "Condiments", "Other",
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item name", text: $name)
                HStack {
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                    TextField("Unit (oz, lbs, etc.)", text: $unit)
                }
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let item = GroceryItem(
                            name: name,
                            quantity: Double(quantity) ?? 1,
                            unit: unit,
                            category: category
                        )
                        item.groceryList = groceryList
                        modelContext.insert(item)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
