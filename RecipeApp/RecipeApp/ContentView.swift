import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService

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

            PantryTabView()
                .tabItem {
                    Label("Pantry", systemImage: "refrigerator")
                }

            GroceryListView()
                .tabItem {
                    Label("Lists", systemImage: "list.bullet")
                }
        }
        .safeAreaInset(edge: .top) {
            if authService.needsReauth {
                ReauthBanner()
            }
        }
    }
}

/// Non-blocking banner shown when the cached session can no longer be validated
/// with the server. Local and CloudKit data remain fully accessible; only cloud
/// sync is paused until the user signs back in.
private struct ReauthBanner: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(.white)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Log back in to sync cloud data")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Your local data is safe and won't be lost.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()

            Button("Log In") {
                authService.login()
            }
            .font(.subheadline.bold())
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.orange)
        }
        .padding(12)
        .background(.orange)
    }
}

#Preview {
    ContentView()
}
