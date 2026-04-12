import SwiftUI

/// Common cooking/grocery units offered as picker choices.
let commonUnits = [
    "", "tsp", "tbsp", "cup", "oz", "fl oz", "lb", "g", "kg", "ml", "l",
    "pinch", "dash", "whole", "clove", "slice", "piece", "bunch", "can",
    "bag", "box", "bottle", "jar", "packet",
]

/// A compact `Menu`-based unit selector. Shows the common list and an
/// "Other…" option that lets the user type a custom unit.
struct UnitPicker: View {
    @Binding var unit: String
    @State private var showCustomField = false

    var body: some View {
        if showCustomField || (!unit.isEmpty && !commonUnits.contains(unit)) {
            TextField("Unit", text: $unit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } else {
            Menu {
                ForEach(commonUnits, id: \.self) { u in
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
