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
    private static let webClientID =
        "972511622379-s2ivecpg4492gg7dbq21c3ev3slqeukp.apps.googleusercontent.com"

    init(baseURL: URL = ServerConfig.baseURL.appendingPathComponent("auth")) {
        self.baseURL = baseURL
        configureGoogleSignIn()
        restoreSession()
        restoreGoogleSignIn()
    }

    // MARK: - Restore Previous Google Sign-In

    private func restoreGoogleSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let error {
                print("[AuthService] restorePreviousSignIn: \(error.localizedDescription)")
            } else if user != nil {
                print("[AuthService] Google session restored")
            }
        }
    }

    // MARK: - Google Sign-In Configuration

    private func configureGoogleSignIn() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: Self.iosClientID,
            serverClientID: Self.webClientID
        )
    }

    // MARK: - Native Google Sign-In

    func login() {
        isLoading = true
        error = nil

        // Pre-flight: verify the reversed-client-ID URL scheme is registered
        // in the built app bundle. GIDSignIn crashes (NSException) if missing.
        let expectedScheme = "com.googleusercontent.apps.972511622379-mak8qoj1corsaria7f2k8ainq715al7u"
        let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let registeredSchemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        if !registeredSchemes.contains(expectedScheme) {
            isLoading = false
            error =
                "Google Sign-In misconfigured: reversed client ID URL scheme missing from app bundle. "
                + "Registered schemes: \(registeredSchemes)"
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootVC = windowScene.windows.first?.rootViewController
        else {
            isLoading = false
            error = "Cannot find root view controller"
            return
        }

        // Walk to the topmost presented VC (sheets, alerts, etc.)
        var presentingVC = rootVC
        while let presented = presentingVC.presentedViewController {
            presentingVC = presented
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC) { [weak self] result, signInError in
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
