import SwiftUI

struct GroceryItemRow: View {
    @Bindable var item: GroceryItem

    var body: some View {
        HStack {
            Button {
                item.isChecked.toggle()
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? .green : .gray)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading) {
                Text(item.name)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                if item.quantity > 0 {
                    Text("\(item.quantity, specifier: "%.1f") \(item.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
