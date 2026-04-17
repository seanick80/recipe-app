import SwiftData
import SwiftUI

@main
struct RecipeAppApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            Ingredient.self,
            GroceryList.self,
            GroceryItem.self,
            ShoppingTemplate.self,
            TemplateItem.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.seanick80.recipeapp")
        )
        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var importService = PendingImportService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { importService.checkForPendingImports() }
                .sheet(isPresented: $importService.showingImportReview) {
                    if let recipe = importService.pendingRecipe {
                        ImportReviewView(recipe: recipe, importService: importService)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
