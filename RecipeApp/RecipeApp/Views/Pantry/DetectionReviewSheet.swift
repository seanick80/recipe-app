import SwiftData
import SwiftUI

/// Presented after food detection completes. Shows detected items grouped by
/// confidence triage: auto-added items (high confidence), items needing
/// confirmation (medium), and rejected items (low). Users can confirm, reject,
/// or edit item names before saving to the pantry.
struct DetectionReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var pantryVM: PantryViewModel
    let modelContext: ModelContext

    var body: some View {
        NavigationStack {
            List {
                if !pantryVM.autoAddItems.isEmpty {
                    Section {
                        ForEach(pantryVM.autoAddItems) { item in
                            DetectionItemRow(
                                item: item,
                                onEdit: { newName in
                                    pantryVM.editItemName(id: item.id, newName: newName)
                                },
                                onReject: {
                                    pantryVM.rejectItem(id: item.id)
                                }
                            )
                        }
                    } header: {
                        Label("Auto-Added", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } footer: {
                        Text("High confidence — these will be added automatically.")
                    }
                }

                if !pantryVM.confirmItems.isEmpty {
                    Section {
                        ForEach(pantryVM.confirmItems) { item in
                            DetectionItemRow(
                                item: item,
                                showConfirmButton: true,
                                onConfirm: {
                                    pantryVM.confirmItem(id: item.id)
                                },
                                onEdit: { newName in
                                    pantryVM.editItemName(id: item.id, newName: newName)
                                },
                                onReject: {
                                    pantryVM.rejectItem(id: item.id)
                                }
                            )
                        }
                    } header: {
                        Label("Please Confirm", systemImage: "questionmark.circle.fill")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("Medium confidence — tap the checkmark to confirm or swipe to remove.")
                    }
                }

                if !pantryVM.rejectedItems.isEmpty {
                    Section {
                        ForEach(pantryVM.rejectedItems) { item in
                            HStack {
                                Text(item.name)
                                    .foregroundStyle(.secondary)
                                    .strikethrough()
                                Spacer()
                                Text("\(Int(item.confidence * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                Button {
                                    pantryVM.confirmItem(id: item.id)
                                } label: {
                                    Image(systemName: "arrow.uturn.left")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                            }
                        }
                    } header: {
                        Label("Rejected", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    } footer: {
                        Text("Low confidence — tap the arrow to restore an item.")
                    }
                }

                if pantryVM.autoAddItems.isEmpty && pantryVM.confirmItems.isEmpty
                    && pantryVM.rejectedItems.isEmpty
                {
                    ContentUnavailableView(
                        "No Items Detected",
                        systemImage: "eye.slash",
                        description: Text("Could not detect any food items. Try with better lighting.")
                    )
                }
            }
            .navigationTitle("Detected Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        pantryVM.reset()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save \(pantryVM.itemsToSaveCount) Items") {
                        pantryVM.saveToStore(modelContext: modelContext)
                        dismiss()
                    }
                    .disabled(pantryVM.itemsToSaveCount == 0)
                }
            }
        }
    }
}

// MARK: - Detection Item Row

struct DetectionItemRow: View {
    let item: PantryItemModel
    var showConfirmButton: Bool = false
    var onConfirm: (() -> Void)?
    var onEdit: ((String) -> Void)?
    var onReject: (() -> Void)?

    @State private var isEditing = false
    @State private var editedName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            if showConfirmButton {
                Button {
                    onConfirm?()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField(
                        "Item name",
                        text: $editedName,
                        onCommit: {
                            onEdit?(editedName)
                            isEditing = false
                        }
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                } else {
                    Text(item.name)
                        .font(.body)
                        .onTapGesture {
                            editedName = item.name
                            isEditing = true
                        }
                }

                HStack(spacing: 8) {
                    Text(item.category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.12))
                        .clipShape(Capsule())

                    Text("\(Int(item.confidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(confidenceColor)
                }
            }

            Spacer()

            if !showConfirmButton {
                Button {
                    onReject?()
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onReject?()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if showConfirmButton {
                Button {
                    onConfirm?()
                } label: {
                    Label("Confirm", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
    }

    private var confidenceColor: Color {
        if item.confidence >= 0.85 { return .green }
        if item.confidence >= 0.55 { return .orange }
        return .red
    }
}
