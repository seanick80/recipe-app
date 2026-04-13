import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecipeListView()
                .tabItem {
                    Label("Recipes", systemImage: "book")
                }

            ShoppingListTab()
                .tabItem {
                    Label("Shopping", systemImage: "cart.fill")
                }

            GroceryListView()
                .tabItem {
                    Label("Lists", systemImage: "list.bullet")
                }
        }
    }
}

#Preview {
    ContentView()
}
