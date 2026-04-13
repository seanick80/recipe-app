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

            ScannerTabView()
                .tabItem {
                    Label("Scan", systemImage: "barcode.viewfinder")
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
