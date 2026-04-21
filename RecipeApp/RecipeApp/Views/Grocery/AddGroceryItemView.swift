import SwiftData
import SwiftUI

struct AddGroceryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let groceryList: GroceryList

    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = ""

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
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let category = categorizeGroceryItem(name)
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
