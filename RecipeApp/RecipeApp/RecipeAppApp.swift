import SwiftData
import SwiftUI

@main
struct RecipeAppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authService = AuthService()

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
            Group {
                if authService.isAuthenticated {
                    ContentView()
                        .onAppear { importService.checkForPendingImports() }
                        .onChange(of: scenePhase) { _, newPhase in
                            if newPhase == .active {
                                importService.checkForPendingImports()
                            }
                        }
                        .sheet(isPresented: $importService.showingImportReview) {
                            if let recipe = importService.pendingRecipe {
                                ImportReviewView(recipe: recipe, importService: importService)
                            }
                        }
                } else {
                    LoginView()
                }
            }
            .environmentObject(authService)
        }
        .modelContainer(sharedModelContainer)
    }
}
