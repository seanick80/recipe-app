import GoogleSignInSwift
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "book.closed.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            Text("Recipe App")
                .font(.largeTitle.bold())

            Text("Sign in to sync your recipes")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if authService.isLoading {
                ProgressView("Signing in…")
            } else {
                GoogleSignInButton(scheme: .dark, style: .wide) {
                    authService.login()
                }
                .padding(.horizontal, 40)
            }

            if let error = authService.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Continue without signing in") {
                authService.skipLogin()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()
            Spacer()
        }
    }
}
