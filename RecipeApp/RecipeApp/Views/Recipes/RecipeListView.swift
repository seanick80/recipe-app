import SwiftData
import SwiftUI

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var recipes: [Recipe]
    @State private var showingAddRecipe = false
    @State private var searchText = ""

    var filteredRecipes: [Recipe] {
        if searchText.isEmpty { return recipes }
        return recipes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredRecipes) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(recipe.name)
                                    .font(.headline)
                                if recipe.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption)
                                }
                            }
                            Text(recipe.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            HStack {
                                Label("\(recipe.totalTimeMinutes) min", systemImage: "clock")
                                if !recipe.cuisine.isEmpty {
                                    Text(recipe.cuisine)
                                }
                                if !recipe.course.isEmpty {
                                    Text(recipe.course)
                                }
                                Spacer()
                                Label("\(recipe.servings) servings", systemImage: "person.2")
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteRecipes)
            }
            .navigationTitle("Recipes")
            .searchable(text: $searchText, prompt: "Search recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddRecipe = true }) {
                        Label("Add Recipe", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddRecipe) {
                RecipeEditView()
            }
            .overlay {
                if recipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes",
                        systemImage: "book",
                        description: Text("Tap + to add your first recipe.")
                    )
                } else if filteredRecipes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private func deleteRecipes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredRecipes[index])
        }
    }
}
