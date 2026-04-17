import SwiftData
import SwiftUI

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var recipes: [Recipe]
    @State private var showingAddRecipe = false
    @State private var searchText = ""
    @State private var filterCuisine: String?
    @State private var filterCourse: String?
    @State private var filterFavoritesOnly = false

    private var availableCuisines: [String] {
        Array(Set(recipes.compactMap { $0.cuisine.isEmpty ? nil : $0.cuisine })).sorted()
    }

    private var availableCourses: [String] {
        Array(Set(recipes.compactMap { $0.course.isEmpty ? nil : $0.course })).sorted()
    }

    var filteredRecipes: [Recipe] {
        recipes.filter { recipe in
            if !searchText.isEmpty
                && !recipe.name.localizedCaseInsensitiveContains(searchText)
                && !recipe.tags.localizedCaseInsensitiveContains(searchText)
            {
                return false
            }
            if filterFavoritesOnly && !recipe.isFavorite { return false }
            if let cuisine = filterCuisine, recipe.cuisine != cuisine { return false }
            if let course = filterCourse, recipe.course != course { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !availableCuisines.isEmpty || !availableCourses.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip(
                                    label: "Favorites",
                                    isActive: filterFavoritesOnly,
                                    systemImage: "star.fill"
                                ) {
                                    filterFavoritesOnly.toggle()
                                }
                                ForEach(availableCuisines, id: \.self) { cuisine in
                                    FilterChip(
                                        label: cuisine,
                                        isActive: filterCuisine == cuisine
                                    ) {
                                        filterCuisine = filterCuisine == cuisine ? nil : cuisine
                                    }
                                }
                                ForEach(availableCourses, id: \.self) { course in
                                    FilterChip(
                                        label: course,
                                        isActive: filterCourse == course
                                    ) {
                                        filterCourse = filterCourse == course ? nil : course
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
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

private struct FilterChip: View {
    let label: String
    let isActive: Bool
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                }
                Text(label)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
