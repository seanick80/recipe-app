import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageData = recipe.imageData,
                    let uiImage = UIImage(data: imageData)
                {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: 250)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !recipe.summary.isEmpty {
                        Text(recipe.summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 20) {
                        Label("\(recipe.prepTimeMinutes) min prep", systemImage: "clock")
                        Label("\(recipe.cookTimeMinutes) min cook", systemImage: "flame")
                        Label("\(recipe.servings) servings", systemImage: "person.2")
                    }
                    .font(.caption)

                    if !recipe.cuisine.isEmpty || !recipe.course.isEmpty || !recipe.difficulty.isEmpty {
                        HStack(spacing: 12) {
                            if !recipe.cuisine.isEmpty {
                                Label(recipe.cuisine, systemImage: "globe")
                            }
                            if !recipe.course.isEmpty {
                                Label(recipe.course, systemImage: "fork.knife")
                            }
                            if !recipe.difficulty.isEmpty {
                                Label(recipe.difficulty, systemImage: "chart.bar")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if !recipe.tags.isEmpty {
                        Text(recipe.tags)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !recipe.sourceURL.isEmpty {
                        Text("Source: \(recipe.sourceURL)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal)

                if let ingredients = recipe.ingredients, !ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients")
                            .font(.title2)
                            .bold()
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 6, verticalSpacing: 4) {
                            ForEach(ingredients.sorted { $0.displayOrder < $1.displayOrder }) { ingredient in
                                GridRow {
                                    if ingredient.quantity > 0 {
                                        Text(formatQuantityAsFraction(ingredient.quantity))
                                            .bold()
                                            .gridColumnAlignment(.trailing)
                                        Text(ingredient.unit)
                                            .bold()
                                            .foregroundStyle(.secondary)
                                            .gridColumnAlignment(.leading)
                                    } else {
                                        Text("")
                                        Text("")
                                    }
                                    HStack(spacing: 4) {
                                        Text(ingredient.name)
                                        if !ingredient.notes.isEmpty {
                                            Text("(\(ingredient.notes))")
                                                .foregroundStyle(.secondary)
                                                .italic()
                                        }
                                    }
                                    .gridColumnAlignment(.leading)
                                }
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

    private func formatQuantityAsFraction(_ value: Double) -> String {
        if value <= 0 { return "" }
        let whole = Int(value)
        let frac = value - Double(whole)

        let fractionStr: String?
        if abs(frac) < 0.01 {
            fractionStr = nil
        } else if abs(frac - 0.25) < 0.01 {
            fractionStr = "\u{00BC}"
        } else if abs(frac - 1.0 / 3) < 0.04 {
            fractionStr = "\u{2153}"
        } else if abs(frac - 0.5) < 0.01 {
            fractionStr = "\u{00BD}"
        } else if abs(frac - 2.0 / 3) < 0.04 {
            fractionStr = "\u{2154}"
        } else if abs(frac - 0.75) < 0.01 {
            fractionStr = "\u{00BE}"
        } else {
            fractionStr = nil
        }

        if let f = fractionStr {
            return whole > 0 ? "\(whole) \(f)" : f
        }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(whole)"
            : String(format: "%.1f", value)
    }
}
