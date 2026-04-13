import SwiftUI

/// Context in which units are being selected, determining which preset list
/// the picker offers.
enum UnitPickerContext {
    case recipe
    case shopping
}

/// Units shown when editing recipe ingredients — precision matters.
let recipeUnits = [
    "", "tsp", "tbsp", "cup", "oz", "fl oz", "lb", "g", "kg", "ml", "l",
    "pinch", "dash", "whole", "large", "medium", "small",
    "clove", "slice", "piece", "bunch", "head", "stalk", "sprig", "stick",
    "can", "jar", "bottle",
]

/// Units shown when adding shopping list / template items — purchase quantities.
let shoppingUnits = [
    "", "lb", "oz", "g", "kg",
    "gal", "qt", "pt", "fl oz", "l", "ml",
    "dozen", "pack", "bag", "box", "can", "jar",
    "bottle", "carton", "container", "loaf", "bunch",
    "head", "case",
]

/// A compact `Menu`-based unit selector. Shows a context-appropriate list and
/// an "Other…" option that lets the user type a custom unit.
struct UnitPicker: View {
    @Binding var unit: String
    var context: UnitPickerContext = .recipe
    @State private var showCustomField = false

    private var unitList: [String] {
        switch context {
        case .recipe: return recipeUnits
        case .shopping: return shoppingUnits
        }
    }

    var body: some View {
        if showCustomField || (!unit.isEmpty && !unitList.contains(unit)) {
            TextField("Unit", text: $unit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            Menu {
                ForEach(unitList, id: \.self) { u in
                    Button(u.isEmpty ? "(none)" : u) {
                        unit = u
                        showCustomField = false
                    }
                }
                Divider()
                Button("Other\u{2026}") {
                    showCustomField = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(unit.isEmpty ? "Unit" : unit)
                        .foregroundStyle(unit.isEmpty ? .secondary : .primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
