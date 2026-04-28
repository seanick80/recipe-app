import Foundation
import GoogleSignIn

struct AuthUser: Codable, Sendable {
    let email: String
    let name: String
    let role: String
}

struct TokenResponse: Codable, Sendable {
    let token: String
    let email: String
    let name: String
    let role: String
}

@MainActor
final class AuthService: ObservableObject {
    @Published var currentUser: AuthUser?
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL: URL

    @Published var skippedLogin = false

    var isAuthenticated: Bool { currentUser != nil || skippedLogin }
    var token: String? { KeychainService.loadToken() }

    private static let iosClientID =
        "972511622379-mak8qoj1corsaria7f2k8ainq715al7u.apps.googleusercontent.com"

    init(baseURL: URL = URL(string: "https://recipe-api-972511622379.us-west1.run.app/api/v1/auth")!) {
        self.baseURL = baseURL
        configureGoogleSignIn()
        restoreSession()
    }

    // MARK: - Google Sign-In Configuration

    private func configureGoogleSignIn() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Self.iosClientID)
    }

    // MARK: - Native Google Sign-In

    func login() {
        isLoading = true
        error = nil

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootViewController = windowScene.windows.first?.rootViewController
        else {
            isLoading = false
            error = "Cannot find root view controller"
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, signInError in
            Task { @MainActor in
                guard let self else { return }

                if let signInError {
                    self.isLoading = false
                    let nsError = signInError as NSError
                    if nsError.code == GIDSignInError.canceled.rawValue {
                        return
                    }
                    self.error = signInError.localizedDescription
                    return
                }

                guard let idToken = result?.user.idToken?.tokenString else {
                    self.isLoading = false
                    self.error = "No ID token from Google"
                    return
                }

                await self.exchangeGoogleToken(idToken)
            }
        }
    }

    // MARK: - Token Exchange

    private func exchangeGoogleToken(_ idToken: String) async {
        let url = baseURL.appendingPathComponent("mobile/google")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["id_token": idToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                isLoading = false
                error = "Invalid server response"
                return
            }

            if httpResponse.statusCode == 200 {
                let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                KeychainService.saveToken(tokenResponse.token)
                currentUser = AuthUser(
                    email: tokenResponse.email,
                    name: tokenResponse.name,
                    role: tokenResponse.role
                )
            } else if httpResponse.statusCode == 403 {
                error = "Not authorized -- ask Nick for an invite"
            } else {
                error = "Authentication failed (status \(httpResponse.statusCode))"
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Fetch Current User

    func fetchMe() async {
        guard let token = KeychainService.loadToken() else {
            currentUser = nil
            return
        }

        let url = baseURL.appendingPathComponent("me")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 200 {
                currentUser = try JSONDecoder().decode(AuthUser.self, from: data)
            } else if httpResponse.statusCode == 401 {
                let refreshed = await refreshToken()
                if !refreshed {
                    logout()
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Token Refresh

    @discardableResult
    func refreshToken() async -> Bool {
        guard let token = KeychainService.loadToken() else { return false }

        let url = baseURL.appendingPathComponent("refresh")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else { return false }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            KeychainService.saveToken(tokenResponse.token)
            currentUser = AuthUser(
                email: tokenResponse.email,
                name: tokenResponse.name,
                role: tokenResponse.role
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Logout

    func skipLogin() {
        skippedLogin = true
    }

    func logout() {
        GIDSignIn.sharedInstance.signOut()
        KeychainService.deleteToken()
        currentUser = nil
        skippedLogin = false
        error = nil
    }

    // MARK: - Session Restore

    private func restoreSession() {
        guard KeychainService.loadToken() != nil else { return }
        isLoading = true
        Task {
            await fetchMe()
            isLoading = false
        }
    }

    // MARK: - URL Handling

    func handleURL(_ url: URL) {
        GIDSignIn.sharedInstance.handle(url)
    }
}
