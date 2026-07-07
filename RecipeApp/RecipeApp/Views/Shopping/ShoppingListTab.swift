import SwiftData
import SwiftUI

/// Main tab view for the weekly shopping list workflow.
/// Shows the active (non-archived) grocery list if one exists,
/// otherwise prompts to start a new week from a template.
struct ShoppingListTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<GroceryList> { $0.archivedAt == nil },
        sort: \GroceryList.createdAt,
        order: .reverse
    ) private var activeLists: [GroceryList]
    @Query(sort: \ShoppingTemplate.sortOrder) private var templates: [ShoppingTemplate]

    @State private var showingTemplateEditor = false
    @State private var showingStaplesPicker = false
    @State private var showingMergeLists = false
    @State private var showingArchivedLists = false
    @State private var viewModel = ShoppingViewModel()

    private var activeList: GroceryList? { activeLists.first }

    var body: some View {
        NavigationStack {
            Group {
                if let list = activeList {
                    ShoppingListDetailView(groceryList: list, viewModel: viewModel)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Shopping")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            addStaplesTapped()
                        } label: {
                            Label("Add Staples", systemImage: "cart.badge.plus")
                        }
                        .disabled(templates.isEmpty)

                        Button {
                            showingTemplateEditor = true
                        } label: {
                            Label("Edit Staples", systemImage: "pencil.line")
                        }

                        if activeList != nil {
                            Button {
                                addManualItem()
                            } label: {
                                Label("Add Item", systemImage: "plus")
                            }
                        }

                        if activeLists.count > 1 {
                            Button {
                                showingMergeLists = true
                            } label: {
                                Label("Merge Lists", systemImage: "arrow.triangle.merge")
                            }
                        }

                        Button {
                            showingArchivedLists = true
                        } label: {
                            Label("Archived Lists", systemImage: "archivebox")
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingTemplateEditor) {
                TemplateEditorView()
            }
            .confirmationDialog("Add Staples", isPresented: $showingStaplesPicker, titleVisibility: .visible) {
                ForEach(templates) { template in
                    Button(template.name) { addStaples(from: template) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Add items from a staples template to your list. Items already on the list are skipped.")
            }
            .sheet(isPresented: $showingMergeLists) {
                MergeListsView(
                    lists: activeLists,
                    viewModel: viewModel
                )
            }
            .sheet(isPresented: $showingArchivedLists) {
                ArchivedListsView(viewModel: viewModel)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Shopping List", systemImage: "cart")
        } description: {
            if templates.isEmpty {
                Text("Set up your staples first, then add them to your list.")
            } else {
                Text("Tap the menu to add your staples.")
            }
        } actions: {
            if templates.isEmpty {
                Button("Edit Staples") {
                    showingTemplateEditor = true
                }
            } else {
                Button("Add Staples") {
                    addStaplesTapped()
                }
            }
        }
    }

    // "Add Staples" entry point. With a single template, apply it directly;
    // with several, let the user pick which staples to add.
    private func addStaplesTapped() {
        if templates.count == 1 {
            addStaples(from: templates[0])
        } else if !templates.isEmpty {
            showingStaplesPicker = true
        }
    }

    // Adds a template's staples to the current list WITHOUT overwriting it —
    // items already on the list are skipped (see ShoppingViewModel.addStaples).
    // If there's no active list yet, create one seeded from the template.
    private func addStaples(from template: ShoppingTemplate) {
        if let current = activeList {
            viewModel.addStaples(from: template, to: current, context: modelContext)
        } else {
            _ = viewModel.stampList(from: template, name: nil, context: modelContext)
        }
    }

    @State private var showingAddItem = false

    private func addManualItem() {
        showingAddItem = true
    }
}
