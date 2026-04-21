import Foundation

/// Result of parsing a recipe from a web page's HTML.
struct ImportedRecipe: Codable, Equatable {
    var title: String
    var ingredients: [String]
    var instructions: [String]
    var servings: Int?
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var totalTimeMinutes: Int?
    var cuisine: String
    var course: String
    var sourceURL: String
    var imageURL: String
    /// Normalizations applied to ingredient strings during import cleaning.
    /// Empty if all ingredients were already clean.
    var ingredientNormalizations: [IngredientNormalization] = []

    /// Custom decoder: tolerates missing `ingredientNormalizations` key so
    /// pending-import JSON files written before this field existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        ingredients = try c.decode([String].self, forKey: .ingredients)
        instructions = try c.decode([String].self, forKey: .instructions)
        servings = try c.decodeIfPresent(Int.self, forKey: .servings)
        prepTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .prepTimeMinutes)
        cookTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .cookTimeMinutes)
        totalTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .totalTimeMinutes)
        cuisine = try c.decode(String.self, forKey: .cuisine)
        course = try c.decode(String.self, forKey: .course)
        sourceURL = try c.decode(String.self, forKey: .sourceURL)
        imageURL = try c.decode(String.self, forKey: .imageURL)
        ingredientNormalizations =
            try c.decodeIfPresent(
                [IngredientNormalization].self,
                forKey: .ingredientNormalizations
            ) ?? []
    }

    /// Memberwise init (keeps existing call sites working).
    init(
        title: String,
        ingredients: [String],
        instructions: [String],
        servings: Int? = nil,
        prepTimeMinutes: Int? = nil,
        cookTimeMinutes: Int? = nil,
        totalTimeMinutes: Int? = nil,
        cuisine: String,
        course: String,
        sourceURL: String,
        imageURL: String,
        ingredientNormalizations: [IngredientNormalization] = []
    ) {
        self.title = title
        self.ingredients = ingredients
        self.instructions = instructions
        self.servings = servings
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.totalTimeMinutes = totalTimeMinutes
        self.cuisine = cuisine
        self.course = course
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.ingredientNormalizations = ingredientNormalizations
    }
}

/// Errors that can occur during recipe import.
enum RecipeImportError: Error, Equatable {
    case noRecipeFound
    case noHTML
    case missingTitle
    case missingIngredients
}

/// Extracts a structured recipe from HTML by parsing JSON-LD Schema.org Recipe markup.
/// Falls back to basic HTML heuristics if no structured data is present.
/// Pure Swift — no Apple frameworks beyond Foundation.
func parseRecipeFromHTML(_ html: String, sourceURL: String = "") -> Result<ImportedRecipe, RecipeImportError> {
    if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .failure(.noHTML)
    }

    // Try JSON-LD first (covers ~80% of recipe sites)
    if let recipe = extractJSONLDRecipe(html, sourceURL: sourceURL) {
        return validate(recipe)
    }

    // Fallback: look for microdata or basic HTML structure
    if let recipe = extractFromHTMLHeuristic(html, sourceURL: sourceURL) {
        return validate(recipe)
    }

    return .failure(.noRecipeFound)
}

/// Validates that an imported recipe has the minimum required fields.
private func validate(_ recipe: ImportedRecipe) -> Result<ImportedRecipe, RecipeImportError> {
    if recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .failure(.missingTitle)
    }
    if recipe.ingredients.isEmpty {
        return .failure(.missingIngredients)
    }
    return .success(recipe)
}

// MARK: - JSON-LD Extraction

/// Finds and parses `<script type="application/ld+json">` blocks containing Recipe schema.
private func extractJSONLDRecipe(_ html: String, sourceURL: String) -> ImportedRecipe? {
    let blocks = extractJSONLDBlocks(html)
    for block in blocks {
        if let recipe = parseRecipeJSON(block, sourceURL: sourceURL) {
            return recipe
        }
    }
    return nil
}

/// Extracts all JSON-LD script block contents from HTML.
func extractJSONLDBlocks(_ html: String) -> [String] {
    var blocks: [String] = []
    let tag = "application/ld+json"
    var searchRange = html.startIndex..<html.endIndex

    while let tagRange = html.range(of: tag, options: .caseInsensitive, range: searchRange) {
        // Find the closing > of the <script> tag
        guard let openEnd = html.range(of: ">", range: tagRange.upperBound..<html.endIndex) else { break }
        // Find the closing </script>
        guard
            let closeTag = html.range(
                of: "</script>",
                options: .caseInsensitive,
                range: openEnd.upperBound..<html.endIndex
            )
        else { break }
        let jsonContent = String(html[openEnd.upperBound..<closeTag.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !jsonContent.isEmpty {
            blocks.append(jsonContent)
        }
        searchRange = closeTag.upperBound..<html.endIndex
    }
    return blocks
}

/// Parses a JSON string as a Schema.org Recipe, handling both single objects and @graph arrays.
func parseRecipeJSON(_ json: String, sourceURL: String) -> ImportedRecipe? {
    guard let data = json.data(using: .utf8) else { return nil }
    guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return nil }

    // Could be a single object or an array
    if let dict = parsed as? [String: Any] {
        return recipeFromDict(dict, sourceURL: sourceURL)
    }
    if let array = parsed as? [[String: Any]] {
        for item in array {
            if let recipe = recipeFromDict(item, sourceURL: sourceURL) {
                return recipe
            }
        }
    }
    return nil
}

/// Converts a JSON dictionary to an ImportedRecipe if it represents a Schema.org Recipe.
private func recipeFromDict(_ dict: [String: Any], sourceURL: String) -> ImportedRecipe? {
    // Check @graph pattern (common on WordPress sites)
    if let graph = dict["@graph"] as? [[String: Any]] {
        for item in graph {
            if let recipe = recipeFromDict(item, sourceURL: sourceURL) {
                return recipe
            }
        }
        return nil
    }

    // Must be a Recipe type
    let typeValue = dict["@type"]
    let isRecipe: Bool
    if let typeStr = typeValue as? String {
        isRecipe = typeStr.lowercased() == "recipe"
    } else if let typeArr = typeValue as? [String] {
        isRecipe = typeArr.contains { $0.lowercased() == "recipe" }
    } else {
        isRecipe = false
    }
    guard isRecipe else { return nil }

    let title = dict["name"] as? String ?? ""
    let ingredients = extractStringArray(dict["recipeIngredient"])
    let instructions = extractInstructions(dict["recipeInstructions"])
    let servings = extractServings(dict["recipeYield"])
    let prepTime = parseDuration(dict["prepTime"] as? String)
    let cookTime = parseDuration(dict["cookTime"] as? String)
    let totalTime = parseDuration(dict["totalTime"] as? String)
    let cuisine = extractFirstString(dict["recipeCuisine"])
    let course = extractFirstString(dict["recipeCategory"])
    let imageURL = extractImageURL(dict["image"])

    var allNormalizations: [IngredientNormalization] = []
    let cleanedIngredients = ingredients.map { raw -> String in
        let decoded = decodeHTMLEntities(raw)
        let result = cleanIngredientText(decoded)
        allNormalizations.append(contentsOf: result.normalizations)
        return result.text
    }

    return ImportedRecipe(
        title: decodeHTMLEntities(title),
        ingredients: cleanedIngredients,
        instructions: instructions.map { decodeHTMLEntities($0) },
        servings: servings,
        prepTimeMinutes: prepTime,
        cookTimeMinutes: cookTime,
        totalTimeMinutes: totalTime,
        cuisine: cuisine,
        course: course,
        sourceURL: sourceURL,
        imageURL: imageURL,
        ingredientNormalizations: allNormalizations
    )
}

// MARK: - HTML Heuristic Fallback

/// Basic heuristic extraction when no JSON-LD is present.
private func extractFromHTMLHeuristic(_ html: String, sourceURL: String) -> ImportedRecipe? {
    let title = extractHTMLTitle(html)
    if title.isEmpty { return nil }

    // Look for ingredient-like list items
    let listItems = extractListItems(html)
    let ingredients = listItems.filter { looksLikeIngredient($0) }
    if ingredients.isEmpty { return nil }

    var allNormalizations: [IngredientNormalization] = []
    let cleanedIngredients = ingredients.map { raw -> String in
        let result = cleanIngredientText(raw)
        allNormalizations.append(contentsOf: result.normalizations)
        return result.text
    }

    return ImportedRecipe(
        title: title,
        ingredients: cleanedIngredients,
        instructions: [],
        servings: nil,
        prepTimeMinutes: nil,
        cookTimeMinutes: nil,
        totalTimeMinutes: nil,
        cuisine: "",
        course: "",
        sourceURL: sourceURL,
        imageURL: "",
        ingredientNormalizations: allNormalizations
    )
}

/// Extracts the page title from <title> or <h1>.
private func extractHTMLTitle(_ html: String) -> String {
    // Try <h1> first (more likely to be the recipe name)
    if let h1 = extractTagContent(html, tag: "h1") {
        return decodeHTMLEntities(stripHTMLTags(h1))
    }
    if let title = extractTagContent(html, tag: "title") {
        return decodeHTMLEntities(stripHTMLTags(title))
    }
    return ""
}

/// Extracts content between an opening and closing tag.
private func extractTagContent(_ html: String, tag: String) -> String? {
    let openPattern = "<\(tag)[^>]*>"
    guard let openRange = html.range(of: openPattern, options: [.regularExpression, .caseInsensitive]) else {
        return nil
    }
    let closeTag = "</\(tag)>"
    guard
        let closeRange = html.range(
            of: closeTag,
            options: .caseInsensitive,
            range: openRange.upperBound..<html.endIndex
        )
    else { return nil }
    return String(html[openRange.upperBound..<closeRange.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Extracts text content from <li> elements.
private func extractListItems(_ html: String) -> [String] {
    var items: [String] = []
    var search = html.startIndex
    while let openRange = html.range(of: "<li", options: .caseInsensitive, range: search..<html.endIndex) {
        guard let tagEnd = html.range(of: ">", range: openRange.upperBound..<html.endIndex) else { break }
        guard
            let closeRange = html.range(
                of: "</li>",
                options: .caseInsensitive,
                range: tagEnd.upperBound..<html.endIndex
            )
        else { break }
        let content = stripHTMLTags(String(html[tagEnd.upperBound..<closeRange.lowerBound]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty {
            items.append(content)
        }
        search = closeRange.upperBound
    }
    return items
}

/// Heuristic: does this string look like a recipe ingredient?
private func looksLikeIngredient(_ text: String) -> Bool {
    let lower = text.lowercased()
    // Must be short-ish (ingredients are typically < 100 chars)
    if text.count > 120 { return false }
    // Starts with a number or fraction
    if let first = text.unicodeScalars.first,
        (first >= "0" && first <= "9") || first == "½" || first == "¼" || first == "¾"
    {
        return true
    }
    // Contains common measurement words
    let measurements = [
        "cup", "tablespoon", "teaspoon", "tbsp", "tsp", "oz", "ounce", "pound", "lb", "gram", "kg", "ml",
    ]
    for m in measurements {
        if lower.contains(m) { return true }
    }
    return false
}

// MARK: - JSON Helper Extractors

/// Extracts a string array from various JSON representations.
private func extractStringArray(_ value: Any?) -> [String] {
    if let arr = value as? [String] {
        return arr.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    if let str = value as? String {
        return [str]
    }
    return []
}

/// Extracts instructions from various Schema.org formats.
private func extractInstructions(_ value: Any?) -> [String] {
    if let arr = value as? [String] {
        return arr.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    if let str = value as? String {
        // Could be HTML or plain text
        let cleaned = stripHTMLTags(str)
        return cleaned.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    if let arr = value as? [[String: Any]] {
        // HowToStep or HowToSection objects
        return arr.compactMap { step in
            if let text = step["text"] as? String {
                return stripHTMLTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let name = step["name"] as? String {
                return stripHTMLTags(name).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // HowToSection with itemListElement
            if let items = step["itemListElement"] as? [[String: Any]] {
                return items.compactMap { $0["text"] as? String }
                    .map { stripHTMLTags($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .joined(separator: "\n")
            }
            return nil
        }.filter { !$0.isEmpty }
    }
    return []
}

/// Extracts servings count from recipeYield.
private func extractServings(_ value: Any?) -> Int? {
    if let num = value as? Int { return num }
    if let str = value as? String {
        // "4 servings" or just "4"
        let digits = str.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits)
    }
    if let arr = value as? [Any], let first = arr.first {
        return extractServings(first)
    }
    return nil
}

/// Extracts first string from a string or array.
private func extractFirstString(_ value: Any?) -> String {
    if let str = value as? String { return str }
    if let arr = value as? [String], let first = arr.first { return first }
    return ""
}

/// Extracts image URL from various formats.
private func extractImageURL(_ value: Any?) -> String {
    if let str = value as? String { return str }
    if let dict = value as? [String: Any], let url = dict["url"] as? String { return url }
    if let arr = value as? [Any], let first = arr.first {
        return extractImageURL(first)
    }
    return ""
}

// MARK: - ISO 8601 Duration Parser

/// Parses ISO 8601 duration (e.g. "PT30M", "PT1H15M") to minutes.
func parseDuration(_ iso: String?) -> Int? {
    guard let iso = iso, iso.uppercased().hasPrefix("PT") else { return nil }
    let upper = iso.uppercased()
    var hours = 0
    var minutes = 0

    // Extract hours
    if let hRange = upper.range(of: #"(\d+)H"#, options: .regularExpression) {
        let match = upper[hRange].dropLast()
        hours = Int(match) ?? 0
    }
    // Extract minutes
    if let mRange = upper.range(of: #"(\d+)M"#, options: .regularExpression) {
        let match = upper[mRange].dropLast()
        minutes = Int(match) ?? 0
    }

    let total = hours * 60 + minutes
    return total > 0 ? total : nil
}

// MARK: - Ingredient Cleaning

/// A normalization applied to an ingredient string during import cleaning.
struct IngredientNormalization: Codable, Equatable {
    var type: String  // e.g. "dual_units", "leading_comma_parens", "double_parens"
    var original: String  // text before this normalization
    var cleaned: String  // text after this normalization
}

/// Result of cleaning an ingredient string: the final text plus any normalizations applied.
struct CleanedIngredient: Equatable {
    var text: String
    var normalizations: [IngredientNormalization]
}

/// Applies all ingredient normalizations in sequence. Returns the cleaned text
/// and a log of every transformation applied (empty if the input was already clean).
func cleanIngredientText(_ raw: String) -> CleanedIngredient {
    var text = raw
    var normalizations: [IngredientNormalization] = []

    let steps: [(String, (String) -> String?)] = [
        (
            "dual_units",
            { s in
                let r = stripDualUnits(s)
                return r == s ? nil : r
            }
        ),
        (
            "double_parens",
            { s in
                let r = collapseDoubleParens(s)
                return r == s ? nil : r
            }
        ),
        (
            "leading_comma_parens",
            { s in
                let r = stripLeadingCommaInParens(s)
                return r == s ? nil : r
            }
        ),
        (
            "empty_parens",
            { s in
                let r = removeEmptyParens(s)
                return r == s ? nil : r
            }
        ),
        (
            "excess_whitespace",
            { s in
                let r = collapseWhitespace(s)
                return r == s ? nil : r
            }
        ),
    ]

    for (type, transform) in steps {
        if let cleaned = transform(text) {
            normalizations.append(
                IngredientNormalization(
                    type: type,
                    original: text,
                    cleaned: cleaned
                )
            )
            text = cleaned
        }
    }

    return CleanedIngredient(text: text, normalizations: normalizations)
}

/// Strips dual-unit patterns: "50 g / 3 1/2 tbsp butter" → "3 1/2 tbsp butter".
func stripDualUnits(_ ingredient: String) -> String {
    let trimmed = ingredient.trimmingCharacters(in: .whitespaces)
    let pattern = #"^\d+(?:\.\d+)?\s+(?:g|kg|mg|ml|l)\s*/\s*(.+)$"#
    guard let range = trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
        return ingredient
    }
    guard let slashRange = trimmed.range(of: "/", range: range) else {
        return ingredient
    }
    let afterSlash = trimmed[slashRange.upperBound...]
        .trimmingCharacters(in: .whitespaces)
    return afterSlash.isEmpty ? ingredient : afterSlash
}

/// Collapses double parentheses: "((full fat preferred))" → "(full fat preferred)".
func collapseDoubleParens(_ text: String) -> String {
    var result = text
    // Repeatedly collapse (( ... )) → ( ... ) until stable
    while let open = result.range(of: "((") {
        // Find matching ))
        if let close = result.range(of: "))", range: open.upperBound..<result.endIndex) {
            result.replaceSubrange(close, with: ")")
            result.replaceSubrange(open, with: "(")
        } else {
            break
        }
    }
    return result
}

/// Strips leading comma inside parentheses: "(, shredded)" → "(shredded)".
func stripLeadingCommaInParens(_ text: String) -> String {
    var result = text
    // Pattern: "(" followed by optional spaces, comma, optional spaces → "("
    while let range = result.range(of: #"\(\s*,\s*"#, options: .regularExpression) {
        result.replaceSubrange(range, with: "(")
    }
    return result
}

/// Removes empty parentheses (with optional whitespace inside): "flour () here" → "flour here".
func removeEmptyParens(_ text: String) -> String {
    var result = text
    while let range = result.range(of: #"\s*\(\s*\)"#, options: .regularExpression) {
        result.replaceSubrange(range, with: "")
    }
    return result.trimmingCharacters(in: .whitespaces)
}

/// Collapses multiple spaces into one.
func collapseWhitespace(_ text: String) -> String {
    var result = text
    while let range = result.range(of: "  ") {
        result.replaceSubrange(range, with: " ")
    }
    return result.trimmingCharacters(in: .whitespaces)
}

// MARK: - HTML Utilities

/// Strips HTML tags from a string.
func stripHTMLTags(_ html: String) -> String {
    var result = html
    // Remove tags
    while let openRange = result.range(of: "<"),
        let closeRange = result.range(of: ">", range: openRange.upperBound..<result.endIndex)
    {
        result.removeSubrange(openRange.lowerBound...closeRange.lowerBound)
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Decodes common HTML entities.
func decodeHTMLEntities(_ text: String) -> String {
    var result = text
    let entities: [(String, String)] = [
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&#39;", "'"),
        ("&apos;", "'"),
        ("&#x27;", "'"),
        ("&nbsp;", " "),
        ("&#8217;", "\u{2019}"),
        ("&#8211;", "\u{2013}"),
        ("&#8212;", "\u{2014}"),
    ]
    for (entity, replacement) in entities {
        result = result.replacingOccurrences(of: entity, with: replacement)
    }
    // Numeric entities: &#NNN;
    while let start = result.range(of: "&#") {
        guard let end = result.range(of: ";", range: start.upperBound..<result.endIndex) else { break }
        let numStr = String(result[start.upperBound..<end.lowerBound])
        if let num = Int(numStr), let scalar = Unicode.Scalar(num) {
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: String(scalar))
        } else {
            break
        }
    }
    return result
}
