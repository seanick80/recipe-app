import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:8000/api/v1")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    func fetchRecipes() async throws -> [RecipeDTO] {
        let url = baseURL.appendingPathComponent("recipes")
        let (data, _) = try await session.data(for: authorizedRequest(for: url))
        return try JSONDecoder().decode([RecipeDTO].self, from: data)
    }

    func createRecipe(_ recipe: RecipeDTO) async throws -> RecipeDTO {
        let url = baseURL.appendingPathComponent("recipes")
        var request = authorizedRequest(for: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(recipe)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(RecipeDTO.self, from: data)
    }

    private func authorizedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = KeychainService.loadToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

struct RecipeDTO: Codable {
    let id: UUID?
    let name: String
    let summary: String
    let instructions: String
    let prepTimeMinutes: Int
    let cookTimeMinutes: Int
    let servings: Int
    let ingredients: [IngredientDTO]
}

struct IngredientDTO: Codable {
    let id: UUID?
    let name: String
    let quantity: Double
    let unit: String
}
