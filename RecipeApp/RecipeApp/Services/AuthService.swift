import AuthenticationServices
import Foundation

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

    init(baseURL: URL = URL(string: "http://localhost:8000/api/v1/auth")!) {
        self.baseURL = baseURL
        restoreSession()
    }

    // MARK: - OAuth Login

    func login() {
        isLoading = true
        error = nil

        let loginURL = baseURL.appendingPathComponent("mobile/login")
        let scheme = "recipeapp"

        let session = ASWebAuthenticationSession(
            url: loginURL,
            callbackURLScheme: scheme
        ) { [weak self] callbackURL, authError in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false

                if let authError {
                    if (authError as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        return
                    }
                    self.error = authError.localizedDescription
                    return
                }

                guard let callbackURL,
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
                else {
                    self.error = "Invalid callback URL"
                    return
                }

                if let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value {
                    self.error = errorParam.replacingOccurrences(of: "_", with: " ")
                    return
                }

                guard let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
                    self.error = "No token received"
                    return
                }

                KeychainService.saveToken(token)
                await self.fetchMe()
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = PresentationContextProvider.shared
        session.start()
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
}

// MARK: - Presentation Context

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = scene.windows.first
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}
