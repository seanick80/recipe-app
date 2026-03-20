import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    let recipe: Recipe
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageData = recipe.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: 250)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        Label("\(recipe.prepTimeMinutes) min prep", systemImage: "clock")
                        Label("\(recipe.cookTimeMinutes) min cook", systemImage: "flame")
                        Label("\(recipe.servings) servings", systemImage: "person.2")
                    }
                    .font(.caption)
                }
                .padding(.horizontal)

                if !recipe.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients")
                            .font(.title2)
                            .bold()
                        ForEach(recipe.ingredients) { ingredient in
                            HStack {
                                Text("•")
                                if ingredient.quantity > 0 {
                                    Text("\(formatQuantity(ingredient.quantity)) \(ingredient.unit)")
                                        .bold()
                                }
                                Text(ingredient.name)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions")
                        .font(.title2)
                        .bold()
                    Text(recipe.instructions)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(recipe.name)
        .toolbar {
            Button("Edit") { showingEdit = true }
        }
        .sheet(isPresented: $showingEdit) {
            RecipeEditView(recipe: recipe)
        }
    }

    private func formatQuantity(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
