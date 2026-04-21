import Foundation

// MARK: - RecipeSchemaParser Tests

func testJSONLDParsingVariants() {
    // Standard JSON-LD with all fields
    let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Recipe",
          "name": "Classic Chocolate Chip Cookies",
          "recipeIngredient": [
            "2 1/4 cups all-purpose flour",
            "1 cup butter, softened",
            "3/4 cup sugar",
            "2 large eggs"
          ],
          "recipeInstructions": [
            {"@type": "HowToStep", "text": "Preheat oven to 375\u{00B0}F."},
            {"@type": "HowToStep", "text": "Mix flour, baking soda, and salt."},
            {"@type": "HowToStep", "text": "Bake for 9 to 11 minutes."}
          ],
          "recipeYield": "4 dozen",
          "prepTime": "PT15M",
          "cookTime": "PT11M",
          "totalTime": "PT26M",
          "recipeCuisine": "American",
          "recipeCategory": "Dessert",
          "image": "https://example.com/cookies.jpg"
        }
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html, sourceURL: "https://example.com/cookies")
    if case .success(let recipe) = result {
        checkEqual(recipe.title, "Classic Chocolate Chip Cookies", "JSON-LD: title")
        checkEqual(recipe.ingredients.count, 4, "JSON-LD: ingredient count")
        checkEqual(recipe.instructions.count, 3, "JSON-LD: instruction count")
        checkEqual(recipe.servings, 4, "JSON-LD: servings")
        checkEqual(recipe.prepTimeMinutes, 15, "JSON-LD: prep time")
        checkEqual(recipe.cookTimeMinutes, 11, "JSON-LD: cook time")
        checkEqual(recipe.cuisine, "American", "JSON-LD: cuisine")
        checkEqual(recipe.imageURL, "https://example.com/cookies.jpg", "JSON-LD: image URL")
    } else {
        check(false, "JSON-LD parse should succeed")
    }
}

func testJSONLDStructuralVariants() {
    // @graph-wrapped recipe
    let graphHTML = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":"WebPage","name":"Blog"},
          {"@type":"Recipe","name":"Garlic Bread",
           "recipeIngredient":["1 baguette","4 cloves garlic"],
           "recipeInstructions":"Slice bread. Spread butter. Bake."}
        ]}
        </script></head><body></body></html>
        """
    if case .success(let r) = parseRecipeFromHTML(graphHTML) {
        checkEqual(r.title, "Garlic Bread", "@graph: title")
    } else {
        check(false, "@graph should succeed")
    }

    // Array of JSON-LD blocks
    let arrayHTML = """
        <html><head>
        <script type="application/ld+json">
        [{"@type":"WebSite","name":"Blog"},
         {"@type":"Recipe","name":"Salad","recipeIngredient":["lettuce","tomato"]}]
        </script></head><body></body></html>
        """
    if case .success(let r) = parseRecipeFromHTML(arrayHTML) {
        checkEqual(r.title, "Salad", "Array JSON-LD: title")
    } else {
        check(false, "Array JSON-LD should succeed")
    }

    // Multiple script blocks — recipe in second
    let multiHTML = """
        <html><head>
        <script type="application/ld+json">{"@type":"WebSite","name":"Blog"}</script>
        <script type="application/ld+json">
        {"@type":"Recipe","name":"Found Second","recipeIngredient":["1 egg"]}
        </script></head><body></body></html>
        """
    if case .success(let r) = parseRecipeFromHTML(multiHTML) {
        checkEqual(r.title, "Found Second", "Multiple blocks: finds recipe in second")
    } else {
        check(false, "Multiple blocks should find recipe")
    }

    // @type as array
    let typeArrayHTML = """
        <html><head>
        <script type="application/ld+json">
        {"@type":["Recipe","HowTo"],"name":"Multi-Type","recipeIngredient":["1 cup rice"]}
        </script></head><body></body></html>
        """
    if case .success(let r) = parseRecipeFromHTML(typeArrayHTML) {
        checkEqual(r.title, "Multi-Type", "Array @type: parsed")
    } else {
        check(false, "Array @type should succeed")
    }
}

func testErrorCases() {
    // (input, expected error, description)
    let cases: [(String, RecipeImportError, String)] = [
        ("", .noHTML, "Empty HTML"),
        ("   \n\t  ", .noHTML, "Whitespace HTML"),
        ("<html><body><h1>About</h1></body></html>", .noRecipeFound, "No recipe"),
    ]
    for (html, expected, desc) in cases {
        if case .failure(let error) = parseRecipeFromHTML(html) {
            checkEqual(error, expected, desc)
        } else {
            check(false, "\(desc) should fail")
        }
    }

    // Non-Recipe JSON-LD
    let articleHTML = """
        <html><head><script type="application/ld+json">
        {"@type":"Article","name":"NYC Restaurants"}
        </script></head><body></body></html>
        """
    if case .failure(let e) = parseRecipeFromHTML(articleHTML) {
        checkEqual(e, .noRecipeFound, "Article JSON-LD")
    } else {
        check(false, "Article should fail")
    }

    // Missing title
    let noTitleHTML = """
        <html><head><script type="application/ld+json">
        {"@type":"Recipe","name":"","recipeIngredient":["1 cup flour"]}
        </script></head><body></body></html>
        """
    if case .failure(let e) = parseRecipeFromHTML(noTitleHTML) {
        checkEqual(e, .missingTitle, "Empty title")
    } else {
        check(false, "Empty title should fail")
    }

    // Missing ingredients
    let noIngHTML = """
        <html><head><script type="application/ld+json">
        {"@type":"Recipe","name":"Mystery","recipeIngredient":[]}
        </script></head><body></body></html>
        """
    if case .failure(let e) = parseRecipeFromHTML(noIngHTML) {
        checkEqual(e, .missingIngredients, "No ingredients")
    } else {
        check(false, "No ingredients should fail")
    }

    // Malformed JSON
    let badJSON = """
        <html><head><script type="application/ld+json">
        { this is not valid json!!! }
        </script></head><body></body></html>
        """
    if case .failure(let e) = parseRecipeFromHTML(badJSON) {
        checkEqual(e, .noRecipeFound, "Malformed JSON")
    } else {
        check(false, "Malformed JSON should fail")
    }
}

func testHTMLHeuristicAndEntities() {
    // Heuristic fallback
    let heuristicHTML = """
        <html><body><h1>Quick Pasta</h1>
        <ul><li>1 lb spaghetti</li><li>2 cups sauce</li></ul>
        </body></html>
        """
    if case .success(let r) = parseRecipeFromHTML(heuristicHTML) {
        checkEqual(r.title, "Quick Pasta", "Heuristic: title")
        checkEqual(r.ingredients.count, 2, "Heuristic: ingredients")
    } else {
        check(false, "Heuristic should succeed")
    }

    // Non-recipe heuristic rejected
    let contactHTML = """
        <html><body><h1>Contact</h1>
        <ul><li>Email: a@b.com</li><li>Phone: 555</li></ul>
        </body></html>
        """
    if case .failure(.noRecipeFound) = parseRecipeFromHTML(contactHTML) {
        check(true, "Non-recipe heuristic rejected")
    } else {
        check(false, "Non-recipe heuristic should fail")
    }

    // HTML entities decoded
    checkEqual(decodeHTMLEntities("Mac &amp; Cheese"), "Mac & Cheese", "Decode &amp;")
    checkEqual(decodeHTMLEntities("Bob&#39;s"), "Bob's", "Decode &#39;")
    checkEqual(stripHTMLTags("<b>Bold</b> text"), "Bold text", "Strip HTML tags")
}

func testDualUnitStripping() {
    // Data-driven: (input, expected, description)
    let cases: [(String, String, String)] = [
        ("50 g / 3 1/2 tbsp butter", "3 1/2 tbsp butter", "g -> tbsp"),
        ("500 ml / 2 cups water", "2 cups water", "ml -> cups"),
        ("2.5 kg / 5 lb chicken", "5 lb chicken", "decimal kg -> lb"),
        ("50 G / 3 tbsp butter", "3 tbsp butter", "uppercase G"),
        ("2 cups flour", "2 cups flour", "non-dual unchanged"),
        ("Salt and pepper", "Salt and pepper", "no quantity unchanged"),
    ]
    for (input, expected, desc) in cases {
        checkEqual(stripDualUnits(input), expected, "Dual: \(desc)")
    }
}

func testIngredientTextCleaning() {
    // Individual helpers
    checkEqual(
        collapseDoubleParens("milk ((full fat))"),
        "milk (full fat)",
        "Double parens collapsed"
    )
    checkEqual(
        stripLeadingCommaInParens("macaroni (, uncooked)"),
        "macaroni (uncooked)",
        "Leading comma stripped"
    )
    checkEqual(
        removeEmptyParens("flour () here"),
        "flour here",
        "Empty parens removed"
    )
    checkEqual(
        collapseWhitespace("  flour   sifted  "),
        "flour sifted",
        "Whitespace collapsed"
    )

    // Full pipeline integration
    let r1 = cleanIngredientText("250 g / 2 1/2 cups elbow macaroni (, uncooked)")
    checkEqual(r1.text, "2 1/2 cups elbow macaroni (uncooked)", "Full pipeline: dual + comma")
    check(r1.normalizations.count >= 2, "Full pipeline: multiple normalizations")

    // Already clean
    let r2 = cleanIngredientText("2 cups flour")
    checkEqual(r2.normalizations.count, 0, "Already clean: no normalizations")

    // Normalization tracking
    let r3 = cleanIngredientText("50 g / 3 1/2 tbsp butter (, softened)")
    let types = r3.normalizations.map { $0.type }
    check(types.contains("dual_units"), "Tracked: dual_units present")
    check(types.contains("leading_comma_parens"), "Tracked: leading_comma present")
}

func testDualUnitsInJSONLDImport() {
    let html = """
        <html><head><script type="application/ld+json">
        {"@type":"Recipe","name":"Mac",
         "recipeIngredient":["50 g / 3 tbsp butter (, softened)","2 cups flour"]}
        </script></head><body></body></html>
        """
    if case .success(let recipe) = parseRecipeFromHTML(html) {
        checkEqual(recipe.ingredients[0], "3 tbsp butter (softened)", "JSON-LD: cleaned")
        checkEqual(recipe.ingredients[1], "2 cups flour", "JSON-LD: clean unchanged")
        check(!recipe.ingredientNormalizations.isEmpty, "JSON-LD: normalizations populated")
    } else {
        check(false, "JSON-LD dual unit should parse")
    }
}

func testDurationParsing() {
    let cases: [(String?, Int?, String)] = [
        ("PT30M", 30, "30 minutes"),
        ("PT1H30M", 90, "1h30m"),
        ("PT0M", nil, "0 minutes -> nil"),
        (nil, nil, "nil input"),
    ]
    for (input, expected, desc) in cases {
        let result = parseDuration(input)
        if let expected = expected {
            checkEqual(result ?? -1, expected, "Duration \(desc)")
        } else {
            check(result == nil, "Duration \(desc) -> nil")
        }
    }
}

func testServingsAndImageFormats() {
    // Servings: plain int, string, array
    let servingsCases: [(String, Int)] = [
        ("\"recipeYield\": 6", 6),
        ("\"recipeYield\": \"4 servings\"", 4),
        ("\"recipeYield\": [\"8\"]", 8),
    ]
    for (fragment, expected) in servingsCases {
        let html = """
            <html><head><script type="application/ld+json">
            {"@type":"Recipe","name":"T","recipeIngredient":["1 egg"],\(fragment)}
            </script></head><body></body></html>
            """
        if case .success(let r) = parseRecipeFromHTML(html) {
            checkEqual(r.servings ?? -1, expected, "Servings: \(expected)")
        }
    }

    // Image as object
    let imgHTML = """
        <html><head><script type="application/ld+json">
        {"@type":"Recipe","name":"T","recipeIngredient":["1 egg"],
         "image":{"@type":"ImageObject","url":"https://x.com/photo.jpg"}}
        </script></head><body></body></html>
        """
    if case .success(let r) = parseRecipeFromHTML(imgHTML) {
        checkEqual(r.imageURL, "https://x.com/photo.jpg", "Image object URL")
    }
}

func testImportedRecipeCodable() {
    let recipe = ImportedRecipe(
        title: "Test",
        ingredients: ["1 cup flour"],
        instructions: ["Mix well"],
        servings: 4,
        prepTimeMinutes: 10,
        cookTimeMinutes: 20,
        totalTimeMinutes: 30,
        cuisine: "Italian",
        course: "Dinner",
        sourceURL: "https://example.com",
        imageURL: "https://example.com/img.jpg"
    )
    checkCodableRoundTrip(recipe, "ImportedRecipe Codable round-trip")
}

// MARK: - Test Runner

func runRecipeSchemaParserTests() -> Bool {
    print("\n=== RecipeSchemaParser Tests ===")

    testJSONLDParsingVariants()
    testJSONLDStructuralVariants()
    testErrorCases()
    testHTMLHeuristicAndEntities()
    testDualUnitStripping()
    testIngredientTextCleaning()
    testDualUnitsInJSONLDImport()
    testDurationParsing()
    testServingsAndImageFormats()
    testImportedRecipeCodable()

    return printTestSummary("RecipeSchemaParser Tests")
}
