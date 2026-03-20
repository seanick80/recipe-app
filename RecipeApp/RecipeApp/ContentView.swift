import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecipeListView()
                .tabItem {
                    Label("Recipes", systemImage: "book")
                }

            GroceryListView()
                .tabItem {
                    Label("Grocery", systemImage: "cart")
                }
        }
    }
}

#Preview {
    ContentView()
}
