import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? ServerConfig.baseURL
        self.session = URLSession.shared
    }

    // MARK: - Recipe CRUD

    func fetchRecipes() async throws -> [RecipeDTO] {
        let url = baseURL.appendingPathComponent("recipes/")
        let data = try await performRequest(authorizedRequest(for: url))
        return try JSONDecoder.apiDecoder.decode([RecipeDTO].self, from: data)
    }

    func fetchRecipeList() async throws -> [RecipeListItemDTO] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("recipes/"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "fields", value: "id,updated_at")]
        let data = try await performRequest(authorizedRequest(for: components.url!))
        return try JSONDecoder.apiDecoder.decode([RecipeListItemDTO].self, from: data)
    }

    func fetchRecipe(id: UUID) async throws -> RecipeDTO {
        let url = baseURL.appendingPathComponent("recipes/\(id.uuidString)")
        let data = try await performRequest(authorizedRequest(for: url))
        return try JSONDecoder.apiDecoder.decode(RecipeDTO.self, from: data)
    }

    func createRecipe(_ recipe: RecipeDTO) async throws -> RecipeDTO {
        let url = baseURL.appendingPathComponent("recipes/")
        var request = authorizedRequest(for: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.apiEncoder.encode(recipe)
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(RecipeDTO.self, from: data)
    }

    func updateRecipe(id: UUID, _ recipe: RecipeDTO) async throws -> RecipeDTO {
        let url = baseURL.appendingPathComponent("recipes/\(id.uuidString)")
        var request = authorizedRequest(for: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.apiEncoder.encode(recipe)
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(RecipeDTO.self, from: data)
    }

    func deleteRecipe(id: UUID) async throws {
        let url = baseURL.appendingPathComponent("recipes/\(id.uuidString)")
        var request = authorizedRequest(for: url)
        request.httpMethod = "DELETE"
        _ = try await performRequest(request)
    }

    // MARK: - Grocery Lists
    //
    // NOTE: the grocery routes are registered WITHOUT a trailing slash (unlike
    // the recipe collection route), so none is added here. Item responses carry
    // no `list_id` — an item is created under a list via the URL and thereafter
    // addressed by its own id; the parent is tracked locally.

    func fetchGroceryListIds() async throws -> [GrocerySyncListItemDTO] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("grocery/lists"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "fields", value: "id,updated_at")]
        let data = try await performRequest(authorizedRequest(for: components.url!))
        return try JSONDecoder.apiDecoder.decode([GrocerySyncListItemDTO].self, from: data)
    }

    func fetchGroceryList(id: UUID) async throws -> GroceryListDTO {
        let url = baseURL.appendingPathComponent("grocery/lists/\(id.uuidString)")
        let data = try await performRequest(authorizedRequest(for: url))
        return try JSONDecoder.apiDecoder.decode(GroceryListDTO.self, from: data)
    }

    func createGroceryList(name: String) async throws -> GroceryListDTO {
        let url = baseURL.appendingPathComponent("grocery/lists")
        var request = authorizedRequest(for: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.apiEncoder.encode(GroceryListCreateDTO(name: name))
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(GroceryListDTO.self, from: data)
    }

    func deleteGroceryList(id: UUID) async throws {
        let url = baseURL.appendingPathComponent("grocery/lists/\(id.uuidString)")
        var request = authorizedRequest(for: url)
        request.httpMethod = "DELETE"
        _ = try await performRequest(request)
    }

    func archiveGroceryList(id: UUID) async throws -> GroceryListDTO {
        let url = baseURL.appendingPathComponent("grocery/lists/\(id.uuidString)/archive")
        var request = authorizedRequest(for: url)
        request.httpMethod = "PATCH"
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(GroceryListDTO.self, from: data)
    }

    func restoreGroceryList(id: UUID) async throws -> GroceryListDTO {
        let url = baseURL.appendingPathComponent("grocery/lists/\(id.uuidString)/restore")
        var request = authorizedRequest(for: url)
        request.httpMethod = "PATCH"
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(GroceryListDTO.self, from: data)
    }

    // MARK: - Grocery Items

    func createItem(listId: UUID, _ input: GroceryItemInput) async throws -> GroceryItemDTO {
        let url = baseURL.appendingPathComponent("grocery/lists/\(listId.uuidString)/items")
        var request = authorizedRequest(for: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.apiEncoder.encode(input)
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(GroceryItemDTO.self, from: data)
    }

    func patchItem(id: UUID, _ patch: GroceryItemPatchDTO) async throws -> GroceryItemDTO {
        let url = baseURL.appendingPathComponent("grocery/items/\(id.uuidString)")
        var request = authorizedRequest(for: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.apiEncoder.encode(patch)
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(GroceryItemDTO.self, from: data)
    }

    func toggleItem(id: UUID) async throws -> GroceryItemDTO {
        let url = baseURL.appendingPathComponent("grocery/items/\(id.uuidString)/toggle")
        var request = authorizedRequest(for: url)
        request.httpMethod = "PATCH"
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(GroceryItemDTO.self, from: data)
    }

    func deleteItem(id: UUID) async throws {
        let url = baseURL.appendingPathComponent("grocery/items/\(id.uuidString)")
        var request = authorizedRequest(for: url)
        request.httpMethod = "DELETE"
        _ = try await performRequest(request)
    }

    // MARK: - Shopping Templates

    func fetchTemplateIds() async throws -> [GrocerySyncListItemDTO] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("grocery/templates"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "fields", value: "id,updated_at")]
        let data = try await performRequest(authorizedRequest(for: components.url!))
        return try JSONDecoder.apiDecoder.decode([GrocerySyncListItemDTO].self, from: data)
    }

    func fetchTemplate(id: UUID) async throws -> TemplateDTO {
        let url = baseURL.appendingPathComponent("grocery/templates/\(id.uuidString)")
        let data = try await performRequest(authorizedRequest(for: url))
        return try JSONDecoder.apiDecoder.decode(TemplateDTO.self, from: data)
    }

    func createTemplate(_ input: TemplateInput) async throws -> TemplateDTO {
        let url = baseURL.appendingPathComponent("grocery/templates")
        var request = authorizedRequest(for: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.apiEncoder.encode(input)
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(TemplateDTO.self, from: data)
    }

    func updateTemplate(id: UUID, _ input: TemplateInput) async throws -> TemplateDTO {
        let url = baseURL.appendingPathComponent("grocery/templates/\(id.uuidString)")
        var request = authorizedRequest(for: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.apiEncoder.encode(input)
        let data = try await performRequest(request)
        return try JSONDecoder.apiDecoder.decode(TemplateDTO.self, from: data)
    }

    func deleteTemplate(id: UUID) async throws {
        let url = baseURL.appendingPathComponent("grocery/templates/\(id.uuidString)")
        var request = authorizedRequest(for: url)
        request.httpMethod = "DELETE"
        _ = try await performRequest(request)
    }

    // MARK: - Request Helpers

    private func authorizedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("RecipeApp-iOS/0.3.0", forHTTPHeaderField: "User-Agent")
        if let token = KeychainService.loadToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func performRequest(
        _ request: URLRequest,
        maxRetries: Int = 3
    ) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    switch http.statusCode {
                    case 200...299:
                        return data
                    case 401:
                        throw APIError.unauthorized
                    case 404:
                        throw APIError.notFound
                    case 429, 500...599:
                        throw APIError.serverError(http.statusCode)
                    default:
                        throw APIError.serverError(http.statusCode)
                    }
                }
                return data
            } catch let error as APIError where !error.isRetryable {
                throw error
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = Double(1 << attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? APIError.serverError(0)
    }
}

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case unauthorized
    case notFound
    case serverError(Int)

    var isRetryable: Bool {
        switch self {
        case .unauthorized, .notFound:
            return false
        case .serverError(let code):
            return code == 429 || code >= 500
        }
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session expired — sign in again"
        case .notFound:
            return "Recipe not found on server"
        case .serverError(let code):
            return "Server error (\(code))"
        }
    }
}

// MARK: - DTOs

struct RecipeDTO: Codable {
    let id: UUID?
    let name: String
    let summary: String
    let instructions: String
    let prepTimeMinutes: Int
    let cookTimeMinutes: Int
    let servings: Int
    let cuisine: String
    let course: String
    let tags: String
    let sourceURL: String
    let difficulty: String
    let isFavorite: Bool
    let isPublished: Bool
    let ingredients: [IngredientDTO]
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, summary, instructions
        case prepTimeMinutes = "prep_time_minutes"
        case cookTimeMinutes = "cook_time_minutes"
        case servings, cuisine, course, tags
        case sourceURL = "source_url"
        case difficulty
        case isFavorite = "is_favorite"
        case isPublished = "is_published"
        case ingredients
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct IngredientDTO: Codable {
    let id: UUID?
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let displayOrder: Int
    let notes: String

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, category
        case displayOrder = "display_order"
        case notes
    }
}

struct RecipeListItemDTO: Codable {
    let id: UUID
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
    }
}

// MARK: - Grocery DTOs

/// Lightweight sync-list row: `GET /grocery/{lists,templates}?fields=id,updated_at`.
/// Shared by both list and template id fetches (same shape as RecipeListItemDTO).
struct GrocerySyncListItemDTO: Codable {
    let id: UUID
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
    }
}

/// A grocery item on the wire (server `GroceryItemResponse`). NOTE: no `list_id`.
struct GroceryItemDTO: Codable {
    let id: UUID
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let isChecked: Bool
    let sourceRecipeName: String
    let sourceRecipeId: String

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, category
        case isChecked = "is_checked"
        case sourceRecipeName = "source_recipe_name"
        case sourceRecipeId = "source_recipe_id"
    }
}

/// A full grocery list on the wire (server `GroceryListResponse`).
struct GroceryListDTO: Codable {
    let id: UUID
    let name: String
    let items: [GroceryItemDTO]
    let createdAt: Date?
    let updatedAt: Date?
    let archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, items
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archivedAt = "archived_at"
    }
}

/// POST body for creating a grocery list.
struct GroceryListCreateDTO: Codable {
    let name: String
}

/// POST body for creating an item under a list.
struct GroceryItemInput: Codable {
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let sourceRecipeName: String
    let sourceRecipeId: String

    enum CodingKeys: String, CodingKey {
        case name, quantity, unit, category
        case sourceRecipeName = "source_recipe_name"
        case sourceRecipeId = "source_recipe_id"
    }
}

/// PATCH body for updating an item. Carries `is_checked` so a combined content +
/// checkbox edit needs only one call.
struct GroceryItemPatchDTO: Codable {
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let isChecked: Bool

    enum CodingKeys: String, CodingKey {
        case name, quantity, unit, category
        case isChecked = "is_checked"
    }
}

/// A template item on the wire (server `TemplateItemResponse`).
struct TemplateItemDTO: Codable {
    let id: UUID
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, category
        case sortOrder = "sort_order"
    }
}

/// A full template on the wire (server `ShoppingTemplateResponse`).
struct TemplateDTO: Codable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let items: [TemplateItemDTO]
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, items
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// POST/PUT body for a template item (aggregate).
struct TemplateItemInput: Codable {
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name, quantity, unit, category
        case sortOrder = "sort_order"
    }
}

/// POST/PUT body for a template (aggregate create / full replace).
struct TemplateInput: Codable {
    let name: String
    let sortOrder: Int
    let items: [TemplateItemInput]

    enum CodingKeys: String, CodingKey {
        case name, items
        case sortOrder = "sort_order"
    }
}

// MARK: - JSON Coders

extension JSONDecoder {
    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = formatter.date(from: string) { return date }
            if let date = fallback.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(string)"
            )
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
