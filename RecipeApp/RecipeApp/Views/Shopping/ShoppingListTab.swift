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
    @State private var showingStartNewWeek = false
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
                            showingStartNewWeek = true
                        } label: {
                            Label("Start New Week", systemImage: "arrow.clockwise")
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
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingTemplateEditor) {
                TemplateEditorView()
            }
            .alert("Start New Week", isPresented: $showingStartNewWeek) {
                Button("Cancel", role: .cancel) {}
                Button("Start") {
                    startNewWeek()
                }
            } message: {
                if activeList != nil {
                    Text("This will archive your current list and create a new one from your staples template.")
                } else {
                    Text("Create a new shopping list from your staples template.")
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Shopping List", systemImage: "cart")
        } description: {
            if templates.isEmpty {
                Text("Set up your weekly staples first, then start a new week.")
            } else {
                Text("Tap the menu to start a new week from your staples.")
            }
        } actions: {
            if templates.isEmpty {
                Button("Edit Staples") {
                    showingTemplateEditor = true
                }
            } else {
                Button("Start New Week") {
                    startNewWeek()
                }
            }
        }
    }

    private func startNewWeek() {
        if let current = activeList {
            viewModel.archive(current)
        }
        if let template = templates.first {
            _ = viewModel.stampList(from: template, name: nil, context: modelContext)
        }
    }

    @State private var showingAddItem = false

    private func addManualItem() {
        showingAddItem = true
    }
}
