import SwiftData
import SwiftUI

struct MergeListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let lists: [GroceryList]
    var viewModel: ShoppingViewModel

    @State private var selected: Set<PersistentIdentifier> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select lists to merge. Items will be combined into the first selected list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Active Lists") {
                    ForEach(lists) { list in
                        Button {
                            if selected.contains(list.persistentModelID) {
                                selected.remove(list.persistentModelID)
                            } else {
                                selected.insert(list.persistentModelID)
                            }
                        } label: {
                            HStack {
                                Image(
                                    systemName: selected.contains(list.persistentModelID)
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundStyle(
                                    selected.contains(list.persistentModelID) ? .blue : .gray
                                )
                                VStack(alignment: .leading) {
                                    Text(list.name)
                                        .foregroundStyle(.primary)
                                    Text("\(list.items?.count ?? 0) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Merge Lists")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") { merge() }
                        .disabled(selected.count < 2)
                }
            }
        }
    }

    private func merge() {
        let chosen = lists.filter { selected.contains($0.persistentModelID) }
        guard let target = chosen.first else { return }
        let sources = Array(chosen.dropFirst())
        viewModel.mergeLists(sources, into: target, context: modelContext)
        dismiss()
    }
}
