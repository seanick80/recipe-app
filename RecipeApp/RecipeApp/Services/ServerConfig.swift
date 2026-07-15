import Foundation

enum ServerConfig {
    #if DEBUG
        static let baseURL = URL(string: "http://localhost:8000/api/v1")!
    #else
        static let baseURL = URL(string: "https://recipe-api-972511622379.us-west1.run.app/api/v1")!
    #endif

    /// User-facing web origin where a synced, published recipe is viewable at
    /// `/recipes/{serverId}`. Always the production domain — a shared link must
    /// work for a recipient regardless of the build's API `baseURL`.
    static let webBaseURL = URL(string: "https://recipes.ouryearofwander.com")!
}
