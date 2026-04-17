import Foundation

// MARK: - RecipeSchemaParser Tests

func testParseValidJSONLD() {
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
            {"@type": "HowToStep", "text": "Preheat oven to 375°F."},
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
    switch result {
    case .success(let recipe):
        checkEqual(recipe.title, "Classic Chocolate Chip Cookies", "JSON-LD: title")
        checkEqual(recipe.ingredients.count, 4, "JSON-LD: ingredient count")
        checkEqual(recipe.instructions.count, 3, "JSON-LD: instruction count")
        checkEqual(recipe.servings, 4, "JSON-LD: servings (extracted number)")
        checkEqual(recipe.prepTimeMinutes, 15, "JSON-LD: prep time")
        checkEqual(recipe.cookTimeMinutes, 11, "JSON-LD: cook time")
        checkEqual(recipe.totalTimeMinutes, 26, "JSON-LD: total time")
        checkEqual(recipe.cuisine, "American", "JSON-LD: cuisine")
        checkEqual(recipe.course, "Dessert", "JSON-LD: course")
        checkEqual(recipe.sourceURL, "https://example.com/cookies", "JSON-LD: source URL")
        checkEqual(recipe.imageURL, "https://example.com/cookies.jpg", "JSON-LD: image URL")
    case .failure(let error):
        check(false, "JSON-LD parse should succeed, got \(error)")
    }
}

func testParseGraphWrappedRecipe() {
    let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@graph": [
            {"@type": "WebPage", "name": "My Blog"},
            {
              "@type": "Recipe",
              "name": "Garlic Bread",
              "recipeIngredient": ["1 baguette", "4 cloves garlic", "2 tbsp butter"],
              "recipeInstructions": "Slice bread. Spread garlic butter. Bake at 400F for 10 minutes."
            }
          ]
        }
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html)
    switch result {
    case .success(let recipe):
        checkEqual(recipe.title, "Garlic Bread", "@graph: title")
        checkEqual(recipe.ingredients.count, 3, "@graph: ingredients")
        check(!recipe.instructions.isEmpty, "@graph: has instructions")
    case .failure(let error):
        check(false, "@graph parse should succeed, got \(error)")
    }
}

func testParseArrayOfJSONLD() {
    let html = """
        <html><head>
        <script type="application/ld+json">
        [
          {"@type": "WebSite", "name": "Food Blog"},
          {
            "@type": "Recipe",
            "name": "Simple Salad",
            "recipeIngredient": ["1 head lettuce", "2 tomatoes", "1 cucumber"]
          }
        ]
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html)
    switch result {
    case .success(let recipe):
        checkEqual(recipe.title, "Simple Salad", "Array JSON-LD: title")
        checkEqual(recipe.ingredients.count, 3, "Array JSON-LD: ingredients")
    case .failure(let error):
        check(false, "Array JSON-LD should succeed, got \(error)")
    }
}

func testParseInstructionsFormats() {
    // String array format
    let cases: [(String, String, Int)] = [
        (
            """
            "recipeInstructions": ["Step one.", "Step two.", "Step three."]
            """, "string array", 3
        ),
        (
            """
            "recipeInstructions": "Mix ingredients.\\nBake at 350.\\nServe warm."
            """, "newline string", 3
        ),
    ]
    for (jsonFragment, desc, expectedCount) in cases {
        let html = """
            <html><head>
            <script type="application/ld+json">
            {
              "@type": "Recipe",
              "name": "Test",
              "recipeIngredient": ["1 cup flour"],
              \(jsonFragment)
            }
            </script>
            </head><body></body></html>
            """
        let result = parseRecipeFromHTML(html)
        if case .success(let recipe) = result {
            checkEqual(recipe.instructions.count, expectedCount, "Instructions \(desc): count")
        } else {
            check(false, "Instructions \(desc): should succeed")
        }
    }
}

func testParseDurations() {
    let cases: [(String, Int?, String)] = [
        ("PT30M", 30, "30 minutes"),
        ("PT1H", 60, "1 hour"),
        ("PT1H30M", 90, "1.5 hours"),
        ("PT2H15M", 135, "2h15m"),
        ("PT0M", nil, "0 minutes -> nil"),
        ("", nil, "empty string"),
    ]
    for (input, expected, desc) in cases {
        let result = parseDuration(input.isEmpty ? nil : input)
        if let expected = expected {
            checkEqual(result ?? -1, expected, "Duration \(desc)")
        } else {
            check(result == nil, "Duration \(desc) -> nil")
        }
    }
}

func testHTMLEntities() {
    checkEqual(decodeHTMLEntities("Mac &amp; Cheese"), "Mac & Cheese", "Decode &amp;")
    checkEqual(decodeHTMLEntities("5 &lt; 10"), "5 < 10", "Decode &lt;")
    checkEqual(decodeHTMLEntities("Bob&#39;s"), "Bob's", "Decode &#39;")
    checkEqual(decodeHTMLEntities("No entities"), "No entities", "No entities unchanged")
}

func testStripHTMLTags() {
    checkEqual(stripHTMLTags("<b>Bold</b> text"), "Bold text", "Strip bold tags")
    checkEqual(stripHTMLTags("<a href=\"url\">Link</a>"), "Link", "Strip anchor tags")
    checkEqual(stripHTMLTags("No tags here"), "No tags here", "No tags unchanged")
}

// MARK: - Error Cases

func testEmptyHTML() {
    let result = parseRecipeFromHTML("")
    if case .failure(let error) = result {
        checkEqual(error, .noHTML, "Empty HTML returns .noHTML")
    } else {
        check(false, "Empty HTML should fail")
    }
}

func testWhitespaceOnlyHTML() {
    let result = parseRecipeFromHTML("   \n\t  ")
    if case .failure(let error) = result {
        checkEqual(error, .noHTML, "Whitespace HTML returns .noHTML")
    } else {
        check(false, "Whitespace HTML should fail")
    }
}

func testNoRecipeInHTML() {
    let html = "<html><body><h1>About Us</h1><p>We are a company.</p></body></html>"
    let result = parseRecipeFromHTML(html)
    if case .failure(let error) = result {
        checkEqual(error, .noRecipeFound, "Non-recipe page returns .noRecipeFound")
    } else {
        check(false, "Non-recipe page should fail")
    }
}

func testNonRecipeJSONLD() {
    let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@type": "Article",
          "name": "10 Best Restaurants in NYC",
          "author": "Food Critic"
        }
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html)
    if case .failure(let error) = result {
        checkEqual(error, .noRecipeFound, "Article JSON-LD returns .noRecipeFound")
    } else {
        check(false, "Article JSON-LD should fail")
    }
}

func testRecipeWithNoTitle() {
    let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@type": "Recipe",
          "name": "",
          "recipeIngredient": ["1 cup flour"]
        }
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html)
    if case .failure(let error) = result {
        checkEqual(error, .missingTitle, "Empty title returns .missingTitle")
    } else {
        check(false, "Empty title should fail")
    }
}

func testRecipeWithNoIngredients() {
    let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@type": "Recipe",
          "name": "Mystery Dish",
          "recipeIngredient": []
        }
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html)
    if case .failure(let error) = result {
        checkEqual(error, .missingIngredients, "No ingredients returns .missingIngredients")
    } else {
        check(false, "No ingredients should fail")
    }
}

func testMalformedJSON() {
    let html = """
        <html><head>
        <script type="application/ld+json">
        { this is not valid json at all!!!
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html)
    if case .failure(let error) = result {
        checkEqual(error, .noRecipeFound, "Malformed JSON returns .noRecipeFound")
    } else {
        check(false, "Malformed JSON should fail")
    }
}

func testHTMLHeuristicFallback() {
    let html = """
        <html><body>
        <h1>Quick Pasta</h1>
        <ul>
          <li>1 lb spaghetti</li>
          <li>2 cups marinara sauce</li>
          <li>1/2 cup parmesan cheese</li>
        </ul>
        </body></html>
        """
    let result = parseRecipeFromHTML(html, sourceURL: "https://example.com/pasta")
    switch result {
    case .success(let recipe):
        checkEqual(recipe.title, "Quick Pasta", "Heuristic: title from h1")
        checkEqual(recipe.ingredients.count, 3, "Heuristic: 3 ingredients")
        checkEqual(recipe.sourceURL, "https://example.com/pasta", "Heuristic: source URL")
    case .failure(let error):
        check(false, "Heuristic should succeed, got \(error)")
    }
}

func testHTMLFallbackNonRecipePage() {
    let html = """
        <html><body>
        <h1>Contact Us</h1>
        <ul>
          <li>Email: hello@example.com</li>
          <li>Phone: 555-1234</li>
        </ul>
        </body></html>
        """
    let result = parseRecipeFromHTML(html)
    if case .failure(.noRecipeFound) = result {
        check(true, "Non-recipe list items correctly rejected")
    } else {
        check(false, "Non-recipe list items should fail")
    }
}

func testMultipleJSONLDBlocks() {
    let html = """
        <html><head>
        <script type="application/ld+json">
        {"@type": "WebSite", "name": "Food Blog"}
        </script>
        <script type="application/ld+json">
        {
          "@type": "Recipe",
          "name": "Found In Second Block",
          "recipeIngredient": ["1 egg"]
        }
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html)
    if case .success(let recipe) = result {
        checkEqual(recipe.title, "Found In Second Block", "Multiple blocks: finds recipe in second")
    } else {
        check(false, "Multiple blocks should find recipe")
    }
}

func testHTMLEntitiesInRecipe() {
    let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@type": "Recipe",
          "name": "Mac &amp; Cheese",
          "recipeIngredient": ["2 cups elbow macaroni", "1 cup cheddar cheese"],
          "recipeInstructions": [{"@type": "HowToStep", "text": "Boil pasta &amp; drain."}]
        }
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html)
    if case .success(let recipe) = result {
        checkEqual(recipe.title, "Mac & Cheese", "HTML entities decoded in title")
        check(recipe.instructions[0].contains("&"), "HTML entities decoded in instructions")
    } else {
        check(false, "HTML entities recipe should succeed")
    }
}

func testRecipeTypeAsArray() {
    let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@type": ["Recipe", "HowTo"],
          "name": "Multi-Type Recipe",
          "recipeIngredient": ["1 cup rice"]
        }
        </script>
        </head><body></body></html>
        """
    let result = parseRecipeFromHTML(html)
    if case .success(let recipe) = result {
        checkEqual(recipe.title, "Multi-Type Recipe", "Array @type: parsed correctly")
    } else {
        check(false, "Array @type should succeed")
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

func testServingsFormats() {
    let cases: [(String, String, Int?)] = [
        ("\"recipeYield\": 6", "plain int", 6),
        ("\"recipeYield\": \"4 servings\"", "string with text", 4),
        ("\"recipeYield\": [\"8\"]", "array", 8),
    ]
    for (fragment, desc, expected) in cases {
        let html = """
            <html><head>
            <script type="application/ld+json">
            { "@type": "Recipe", "name": "T", "recipeIngredient": ["1 egg"], \(fragment) }
            </script>
            </head><body></body></html>
            """
        if case .success(let recipe) = parseRecipeFromHTML(html) {
            if let expected = expected {
                checkEqual(recipe.servings ?? -1, expected, "Servings \(desc)")
            } else {
                check(recipe.servings == nil, "Servings \(desc) -> nil")
            }
        }
    }
}

func testImageFormats() {
    // image as object with url
    let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@type": "Recipe",
          "name": "T",
          "recipeIngredient": ["1 egg"],
          "image": {"@type": "ImageObject", "url": "https://example.com/photo.jpg"}
        }
        </script>
        </head><body></body></html>
        """
    if case .success(let recipe) = parseRecipeFromHTML(html) {
        checkEqual(recipe.imageURL, "https://example.com/photo.jpg", "Image as object: URL extracted")
    }
}

// MARK: - Test Runner

func runRecipeSchemaParserTests() -> Bool {
    print("\n=== RecipeSchemaParser Tests ===")

    testParseValidJSONLD()
    testParseGraphWrappedRecipe()
    testParseArrayOfJSONLD()
    testParseInstructionsFormats()
    testParseDurations()
    testHTMLEntities()
    testStripHTMLTags()
    testEmptyHTML()
    testWhitespaceOnlyHTML()
    testNoRecipeInHTML()
    testNonRecipeJSONLD()
    testRecipeWithNoTitle()
    testRecipeWithNoIngredients()
    testMalformedJSON()
    testHTMLHeuristicFallback()
    testHTMLFallbackNonRecipePage()
    testMultipleJSONLDBlocks()
    testHTMLEntitiesInRecipe()
    testRecipeTypeAsArray()
    testImportedRecipeCodable()
    testServingsFormats()
    testImageFormats()

    return printTestSummary("RecipeSchemaParser Tests")
}
