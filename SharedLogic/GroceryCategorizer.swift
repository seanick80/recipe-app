import Foundation

/// Comprehensive text-based grocery item categorizer.
///
/// Uses multiple matching strategies — exact word matching, suffix/compound
/// handling, and override rules — to assign grocery items to store aisle
/// categories. Designed to be replaced by a CoreML text classifier later.
///
/// Pure Swift with no Apple-specific frameworks beyond Foundation.

// MARK: - Public API

/// Categorize a grocery item name into a store aisle category.
///
/// Returns one of: "Produce", "Dairy", "Meat", "Bakery", "Dry & Canned",
/// "Frozen", "Snacks", "Beverages", "Condiments", "Spices", "Household",
/// "Other".
func categorizeGroceryItem(_ name: String) -> String {
    let lower = name.lowercased()
    let words = tokenize(lower)

    // Phase 1: Multi-word exact matches (highest priority, checked first)
    if let category = matchMultiWord(lower) {
        // Still allow compound overrides to take precedence
        if let override = matchCompoundOverride(words) {
            return override
        }
        return category
    }

    // Phase 2: Compound/context overrides — "broth", "stock", "soup", "mix"
    // override even if another keyword would match.
    if let override = matchCompoundOverride(words) {
        return override
    }

    // Phase 3: Suffix-based matching (e.g., "berries" -> Produce)
    if let category = matchSuffix(lower) {
        return category
    }

    // Phase 4: Exact single-word matching with category priority.
    // Collect ALL matching categories, then pick highest priority.
    // This fixes "cloves garlic" → Produce (garlic outranks clove).
    if let category = matchExactWordWithPriority(words) {
        return category
    }

    return "Other"
}

// MARK: - Tokenization

/// Split input into lowercase word tokens, stripping common punctuation.
private func tokenize(_ input: String) -> [String] {
    var result: [String] = []
    var current = ""
    for ch in input {
        if ch.isLetter || ch.isNumber || ch == "'" || ch == "-" {
            current.append(ch)
        } else {
            if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
    }
    if !current.isEmpty {
        result.append(current)
    }
    return result
}

// MARK: - Multi-Word Matches

/// Check for multi-word phrases that need to match as a unit.
private func matchMultiWord(_ lower: String) -> String? {
    for (phrases, category) in multiWordEntries {
        for phrase in phrases {
            if lower.contains(phrase) {
                return category
            }
        }
    }
    return nil
}

private let multiWordEntries: [([String], String)] = [
    // Frozen
    (
        [
            "ice cream", "frozen yogurt", "frozen vegetable", "frozen fruit",
            "frozen dinner", "frozen pizza", "frozen waffle", "frozen burrito",
            "frozen fries", "frozen fish", "frozen shrimp", "frozen chicken",
            "frozen pie", "frozen meal", "tv dinner", "ice pop", "popsicle",
            "frozen corn", "frozen peas", "frozen broccoli", "frozen berries",
            "frozen meatball",
        ], "Frozen"
    ),

    // Condiments
    (
        [
            "hot sauce", "soy sauce", "fish sauce", "worcestershire sauce",
            "teriyaki sauce", "bbq sauce", "barbecue sauce", "steak sauce",
            "cocktail sauce", "tartar sauce", "buffalo sauce",
            "salad dressing", "ranch dressing",
            "olive oil", "vegetable oil", "canola oil", "coconut oil",
            "sesame oil", "avocado oil", "peanut oil", "cooking spray",
        ], "Condiments"
    ),

    // Dry & Canned
    (
        [
            "chicken broth", "turkey broth", "beef broth", "vegetable broth",
            "chicken stock", "beef stock", "vegetable stock", "bone broth",
            "tomato paste", "tomato sauce", "pasta sauce", "marinara sauce",
            "canned tomato", "canned bean", "canned corn", "canned tuna",
            "canned salmon", "canned chicken", "canned fruit", "canned soup",
            "baking soda", "baking powder", "cream of tartar",
            "cake mix", "brownie mix", "pancake mix", "muffin mix",
            "bread crumb", "panko", "cornstarch", "corn starch",
            "powdered sugar", "brown sugar", "confectioner",
            "mac and cheese", "mac & cheese", "ramen noodle",
            "instant oatmeal", "instant rice", "minute rice",
            "peanut butter", "almond butter", "sunflower butter",
            "dried bean", "dried lentil", "dried pasta",
            "coconut milk", "condensed milk", "evaporated milk",
        ], "Dry & Canned"
    ),

    // Dairy
    (
        [
            "cream cheese", "sour cream", "whipped cream", "heavy cream",
            "half and half", "half & half", "cottage cheese",
            "string cheese", "shredded cheese", "sliced cheese",
            "american cheese", "swiss cheese", "cheddar cheese",
            "greek yogurt", "almond milk", "oat milk", "soy milk",
        ], "Dairy"
    ),

    // Meat
    (
        [
            "ground beef", "ground turkey", "ground pork", "ground chicken",
            "chicken breast", "chicken thigh", "chicken wing", "chicken leg",
            "chicken tender", "chicken drumstick",
            "pork chop", "pork loin", "pork tenderloin", "pork shoulder",
            "pork belly", "pork roast",
            "beef steak", "beef roast", "beef tenderloin",
            "deli meat", "lunch meat", "deli turkey", "deli ham",
            "hot dog", "italian sausage", "breakfast sausage",
            "baby back rib", "spare rib",
        ], "Meat"
    ),

    // Produce
    (
        [
            "bell pepper", "green pepper", "red pepper", "jalapeno pepper",
            "sweet potato", "russet potato", "red potato", "gold potato",
            "baby carrot", "baby spinach", "romaine lettuce", "iceberg lettuce",
            "green onion", "red onion", "yellow onion", "white onion",
            "green bean", "snap pea", "snow pea",
            "cherry tomato", "grape tomato", "roma tomato",
            "fresh herb", "fresh basil", "fresh cilantro", "fresh parsley",
            "fresh dill", "fresh mint", "fresh rosemary", "fresh thyme",
            "brussels sprout", "bok choy", "collard green",
            "acorn squash", "butternut squash", "spaghetti squash",
            "portobello mushroom",
        ], "Produce"
    ),

    // Bakery
    (
        [
            "hamburger bun", "hot dog bun", "english muffin", "dinner roll",
            "french bread", "italian bread", "sourdough bread", "wheat bread",
            "white bread", "rye bread", "pita bread", "naan bread",
            "banana bread", "garlic bread", "texas toast",
            "tortilla chip",
        ], "Bakery"
    ),

    // Household
    (
        [
            "paper towel", "toilet paper", "trash bag", "garbage bag",
            "dish soap", "laundry detergent", "fabric softener",
            "aluminum foil", "plastic wrap", "parchment paper",
            "sandwich bag", "freezer bag", "storage bag",
            "dryer sheet", "cleaning spray", "all purpose cleaner",
            "hand soap", "body wash",
        ], "Household"
    ),

    // Beverages
    (
        [
            "orange juice", "apple juice", "grape juice", "cranberry juice",
            "tomato juice", "lemon juice", "lime juice",
            "sparkling water", "mineral water", "coconut water",
            "energy drink", "sports drink", "protein shake",
            "iced tea", "green tea", "black tea", "herbal tea",
            "hot chocolate", "hot cocoa",
        ], "Beverages"
    ),

    // Snacks
    (
        [
            "potato chip", "tortilla chip", "pita chip",
            "granola bar", "protein bar", "energy bar", "snack bar",
            "trail mix", "mixed nut", "rice cake", "rice crispy",
            "fruit snack", "fruit leather", "beef jerky",
            "popcorn kernel",
        ], "Snacks"
    ),

    // Spices (multi-word)
    (
        [
            "garam masala", "chili powder", "garlic powder", "onion powder",
            "curry powder", "cocoa powder", "chili flake", "red pepper flake",
            "bay leaf", "bay leaves", "fennel seed", "mustard seed",
            "celery seed", "caraway seed", "poppy seed", "sesame seed",
            "five spice", "chinese five spice", "lemon pepper",
            "italian seasoning", "poultry seasoning", "cajun seasoning",
            "taco seasoning", "ranch seasoning", "everything bagel seasoning",
            "old bay", "herbs de provence", "herbes de provence",
            "vanilla extract", "almond extract", "peppermint extract",
            "cream of tartar",
        ], "Spices"
    ),

    // Dry & Canned (specific powder/flour entries that were over-matched before)
    (
        [
            "baking powder", "baking soda", "powdered sugar",
            "all purpose flour", "self raising flour", "self rising flour",
            "bread flour", "cake flour", "whole wheat flour",
            "corn starch", "cornstarch", "arrowroot starch",
            "tapioca starch",
        ], "Dry & Canned"
    ),
]

// MARK: - Compound Override Rules

/// If any of these words appear anywhere in the token list, force the category
/// regardless of other matches. This handles items like "turkey broth" which
/// should be "Dry & Canned" not "Meat".
private func matchCompoundOverride(_ words: [String]) -> String? {
    // Note: "powder", "seasoning", "flour", "starch" removed — they were
    // too aggressive (e.g. "chili powder" → Dry & Canned instead of Spices).
    // Those items are now handled by specific multi-word entries.
    let dryCannedOverrides: Set<String> = [
        "broth", "stock", "soup", "bouillon", "mix",
    ]
    let frozenOverrides: Set<String> = ["frozen"]
    let condimentOverrides: Set<String> = ["dressing", "marinade"]

    for word in words {
        if frozenOverrides.contains(word) { return "Frozen" }
    }
    for word in words {
        if dryCannedOverrides.contains(word) { return "Dry & Canned" }
    }
    for word in words {
        if condimentOverrides.contains(word) { return "Condiments" }
    }
    return nil
}

// MARK: - Suffix Matching

/// Match word endings for natural groupings (berries -> berry -> Produce).
private func matchSuffix(_ lower: String) -> String? {
    let words = tokenize(lower)
    for word in words {
        for (suffixes, category) in suffixRules {
            for suffix in suffixes {
                if word.hasSuffix(suffix) && word.count > suffix.count {
                    return category
                }
            }
        }
    }
    return nil
}

private let suffixRules: [([String], String)] = [
    // Produce
    (
        [
            "berry", "berries", "apple", "apples", "melon",
            "lettuce", "greens", "herb", "herbs",
        ], "Produce"
    ),
    // Dairy
    (["cheese", "yogurt"], "Dairy"),
]

// MARK: - Exact Word Matching

/// Match individual tokens against keyword sets, collecting ALL matches across
/// all tokens. If multiple categories match (e.g. "cloves garlic" matches both
/// Spices and Produce), the highest-priority category wins.
///
/// Priority order: Produce > Meat > Dairy > Bakery > Frozen > Dry & Canned >
/// Beverages > Snacks > Condiments > Spices > Household
private func matchExactWordWithPriority(_ words: [String]) -> String? {
    var matched: Set<String> = []
    for word in words {
        let candidates = normalizePluralCandidates(word)
        for candidate in candidates {
            if let cat = exactWordLookup[candidate] {
                matched.insert(cat)
            }
        }
    }
    if matched.isEmpty { return nil }
    if matched.count == 1 { return matched.first }
    // Multiple categories matched — pick highest priority
    return matched.min { categoryPriority($0) < categoryPriority($1) }
}

/// Lower number = higher priority. Produce and Meat win over Spices/Condiments
/// so that "5 cloves garlic" → Produce, not Spices.
private func categoryPriority(_ category: String) -> Int {
    switch category {
    case "Produce": return 0
    case "Meat": return 1
    case "Dairy": return 2
    case "Bakery": return 3
    case "Frozen": return 4
    case "Dry & Canned": return 5
    case "Beverages": return 6
    case "Snacks": return 7
    case "Condiments": return 8
    case "Spices": return 9
    case "Household": return 10
    default: return 99
    }
}

/// Generate plural normalization candidates. Returns the original word plus
/// one or more de-pluralized forms, ordered from most specific to least.
/// Multiple candidates handle English irregularities (e.g., "cookies" could
/// be "cooky" via ies->y or "cookie" via just dropping s).
private func normalizePluralCandidates(_ word: String) -> [String] {
    var candidates = [word]

    if word.hasSuffix("ies") && word.count > 4 {
        // berries -> berry, cherries -> cherry
        candidates.append(String(word.dropLast(3)) + "y")
        // Also try: cookies -> cookie (drop just the s)
        candidates.append(String(word.dropLast(1)))
    } else if word.hasSuffix("ves") && word.count > 4 {
        // loaves -> loaf
        candidates.append(String(word.dropLast(3)) + "f")
    } else if word.hasSuffix("oes") && word.count > 4 {
        // potatoes -> potato, tomatoes -> tomato
        candidates.append(String(word.dropLast(2)))
    } else if word.hasSuffix("shes") || word.hasSuffix("ches") || word.hasSuffix("xes") || word.hasSuffix("zes")
        || word.hasSuffix("ses")
    {
        if word.count > 4 {
            candidates.append(String(word.dropLast(2)))
        }
    } else if word.hasSuffix("s") && !word.hasSuffix("ss") && word.count > 3 {
        candidates.append(String(word.dropLast(1)))
    }

    return candidates
}

/// Flat lookup table: word -> category.
private let exactWordLookup: [String: String] = {
    var table: [String: String] = [:]

    let entries: [([String], String)] = [
        // ---- Produce ----
        (
            [
                "apple", "apricot", "artichoke", "arugula", "asparagus",
                "avocado", "banana", "basil", "beet", "berry",
                "blueberry", "blackberry", "raspberry", "strawberry", "cranberry",
                "broccoli", "cabbage", "cantaloupe", "carrot", "cauliflower",
                "celery", "chard", "cherry", "chive", "cilantro",
                "clementine", "coconut", "collard", "corn", "cucumber",
                "dill", "eggplant", "endive", "fennel", "fig",
                "garlic", "ginger", "grape", "grapefruit", "guava",
                "honeydew", "jalapeno", "jicama", "kale", "kiwi",
                "kohlrabi", "kumquat", "leek", "lemon", "lemongrass",
                "lettuce", "lime", "mandarin", "mango", "melon",
                "mint", "mushroom", "nectarine", "okra", "onion",
                "orange", "oregano", "papaya", "parsley", "parsnip",
                "peach", "pear", "pea", "pepper", "persimmon",
                "pineapple", "plantain", "plum", "pomegranate", "potato",
                "pumpkin", "radicchio", "radish", "rhubarb", "rosemary",
                "rutabaga", "sage", "scallion", "shallot", "spinach",
                "sprout", "squash", "tangelo", "tangerine", "tarragon",
                "thyme", "tomato", "turnip", "watercress", "watermelon",
                "yam", "zucchini",
            ], "Produce"
        ),

        // ---- Dairy ----
        (
            [
                "milk", "cheese", "yogurt", "butter", "cream",
                "egg", "buttermilk", "kefir", "ghee",
                "mozzarella", "parmesan", "provolone", "ricotta",
                "brie", "gouda", "cheddar", "feta", "colby",
                "gruyere", "havarti", "muenster", "swiss",
                "mascarpone", "neufchatel", "camembert",
                "margarine", "whey", "casein",
            ], "Dairy"
        ),

        // ---- Meat ----
        (
            [
                "chicken", "beef", "pork", "fish", "salmon",
                "shrimp", "bacon", "sausage", "turkey", "lamb",
                "veal", "venison", "bison", "duck", "goose",
                "quail", "rabbit", "ham", "prosciutto", "salami",
                "pepperoni", "chorizo", "bratwurst", "kielbasa",
                "steak", "ribs", "roast", "brisket", "tenderloin",
                "sirloin", "ribeye", "filet", "flank",
                "tilapia", "cod", "halibut", "tuna", "trout",
                "catfish", "swordfish", "mahi", "snapper", "bass",
                "perch", "walleye", "haddock", "pollock", "sardine",
                "anchovy", "crab", "lobster", "scallop", "mussel",
                "clam", "oyster", "calamari", "squid", "octopus",
                "crawfish", "crayfish", "prawn",
            ], "Meat"
        ),

        // ---- Bakery ----
        (
            [
                "bread", "bagel", "muffin", "roll", "bun",
                "croissant", "baguette", "brioche", "focaccia",
                "ciabatta", "sourdough", "pretzel", "scone",
                "biscuit", "cornbread", "flatbread", "naan",
                "pita", "tortilla", "wrap", "crumpet",
                "donut", "doughnut", "danish", "pastry", "strudel",
                "cake", "cupcake", "pie", "tart", "eclair",
                "cannoli", "cronut",
            ], "Bakery"
        ),

        // ---- Dry & Canned ----
        (
            [
                "rice", "pasta", "noodle", "spaghetti", "penne",
                "macaroni", "fettuccine", "linguine", "rigatoni",
                "orzo", "couscous", "quinoa", "barley", "bulgur",
                "farro", "millet", "polenta", "grits",
                "flour", "sugar", "salt", "oil",
                "cereal", "oatmeal", "oat", "granola",
                "bean", "lentil", "chickpea",
                "broth", "stock", "bouillon",
                "sauce", "salsa", "paste",
                "can", "canned",
                "honey", "syrup", "molasses", "agave",
                "jam", "jelly", "preserve", "marmalade",
                "vinegar", "extract", "vanilla",
                "yeast", "gelatin", "pectin",
                "raisin", "crouton", "stuffing",
                "breadcrumb", "panko",
                "cornmeal", "cornstarch",
                "taco", "tortellini", "ravioli", "lasagna",
            ], "Dry & Canned"
        ),

        // ---- Frozen ----
        (
            [
                "frozen", "popsicle",
            ], "Frozen"
        ),

        // ---- Snacks ----
        (
            [
                "chip", "cookie", "cracker", "candy", "chocolate",
                "snack", "nut", "almond", "cashew", "walnut",
                "pecan", "pistachio", "macadamia", "hazelnut",
                "pretzel", "popcorn", "jerky",
                "gummy", "licorice", "taffy", "caramel",
                "brownie", "marshmallow",
            ], "Snacks"
        ),

        // ---- Beverages ----
        (
            [
                "water", "juice", "soda", "coffee", "tea",
                "drink", "beer", "wine", "lemonade", "cider",
                "champagne", "vodka", "whiskey", "rum", "gin",
                "tequila", "brandy", "bourbon", "ale", "lager",
                "stout", "porter", "mead", "sake",
                "kombucha", "smoothie", "milkshake",
                "espresso", "cappuccino", "latte",
                "punch", "sangria", "margarita",
                "cocoa",
            ], "Beverages"
        ),

        // ---- Condiments ----
        (
            [
                "ketchup", "mustard", "mayo", "mayonnaise",
                "relish", "horseradish", "wasabi",
                "sriracha", "tabasco", "sambal",
                "hummus", "guacamole", "tzatziki",
                "chutney", "aioli", "pesto",
                "dressing", "marinade", "glaze",
                "gravy",
            ], "Condiments"
        ),

        // ---- Spices ----
        (
            [
                "spice", "seasoning", "cumin", "paprika",
                "turmeric", "cinnamon", "nutmeg", "clove",
                "allspice", "cardamom", "coriander",
                "cayenne", "chili", "curry", "masala",
                "saffron", "sumac", "za'atar", "zaatar",
                "anise", "star-anise", "juniper",
                "fenugreek", "tamarind", "mace",
                "mustard-seed", "celery-seed",
                "peppercorn", "pepper-flake",
            ], "Spices"
        ),

        // ---- Household ----
        (
            [
                "paper", "towel", "soap", "detergent", "sponge",
                "cleaner", "bleach", "disinfectant",
                "napkin", "tissue", "wipe",
                "foil", "wrap", "bag",
                "battery", "lightbulb", "candle",
                "mop", "broom", "brush",
                "glove", "apron",
                "filter", "charcoal",
            ], "Household"
        ),
    ]

    for (words, category) in entries {
        for word in words {
            table[word] = category
        }
    }
    return table
}()
