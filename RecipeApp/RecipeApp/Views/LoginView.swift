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
                Button(action: { authService.login() }) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text("Sign in with Google")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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

            Spacer()
            Spacer()
        }
    }
}
