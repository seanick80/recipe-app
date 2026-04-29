import Foundation

enum ServerConfig {
    #if DEBUG
        static let baseURL = URL(string: "http://localhost:8000/api/v1")!
    #else
        static let baseURL = URL(string: "https://recipe-api-972511622379.us-west1.run.app/api/v1")!
    #endif
}
