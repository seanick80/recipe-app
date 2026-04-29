import SwiftData
import SwiftUI

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var recipes: [Recipe]
    @State private var showingAddRecipe = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var filterCuisine: String?
    @State private var filterCourse: String?
    @State private var filterFavoritesOnly = false

    private var visibleRecipes: [Recipe] {
        recipes.filter { !$0.locallyDeleted }
    }

    private var availableCuisines: [String] {
        Array(Set(visibleRecipes.compactMap { $0.cuisine.isEmpty ? nil : $0.cuisine })).sorted()
    }

    private var availableCourses: [String] {
        Array(Set(visibleRecipes.compactMap { $0.course.isEmpty ? nil : $0.course })).sorted()
    }

    var filteredRecipes: [Recipe] {
        recipes.filter { recipe in
            if recipe.locallyDeleted { return false }
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
            .refreshable { await syncService.sync() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Button(action: { showingSettings = true }) {
                            Label("Settings", systemImage: "gearshape")
                        }
                        if syncService.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddRecipe = true }) {
                        Label("Add Recipe", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let error = syncService.lastSyncError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                        Spacer()
                    }
                    .font(.caption)
                    .padding(8)
                    .background(.yellow.opacity(0.3))
                }
                if syncService.conflictCount > 0 {
                    HStack {
                        Image(systemName: "doc.on.doc.fill")
                        Text(
                            "\(syncService.conflictCount) conflict\(syncService.conflictCount == 1 ? "" : "s") resolved — check conflicted copies"
                        )
                        Spacer()
                    }
                    .font(.caption)
                    .padding(8)
                    .background(.orange.opacity(0.3))
                }
            }
            .sheet(isPresented: $showingAddRecipe) {
                RecipeEditView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .overlay {
                if visibleRecipes.isEmpty {
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
            let recipe = filteredRecipes[index]
            recipe.locallyDeleted = true
            recipe.deletedAt = Date()
            recipe.needsSync = true
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
