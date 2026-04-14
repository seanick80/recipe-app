import Foundation

// MARK: - Grocery Categorizer Tests

func testBasicProduce() {
    checkEqual(categorizeGroceryItem("apple"), "Produce", "apple -> Produce")
    checkEqual(categorizeGroceryItem("Banana"), "Produce", "Banana -> Produce")
    checkEqual(categorizeGroceryItem("spinach"), "Produce", "spinach -> Produce")
    checkEqual(categorizeGroceryItem("Garlic"), "Produce", "Garlic -> Produce")
    checkEqual(categorizeGroceryItem("avocado"), "Produce", "avocado -> Produce")
    checkEqual(categorizeGroceryItem("broccoli"), "Produce", "broccoli -> Produce")
    checkEqual(categorizeGroceryItem("mushroom"), "Produce", "mushroom -> Produce")
}

func testBasicDairy() {
    checkEqual(categorizeGroceryItem("milk"), "Dairy", "milk -> Dairy")
    checkEqual(categorizeGroceryItem("Cheese"), "Dairy", "Cheese -> Dairy")
    checkEqual(categorizeGroceryItem("yogurt"), "Dairy", "yogurt -> Dairy")
    checkEqual(categorizeGroceryItem("butter"), "Dairy", "butter -> Dairy")
    checkEqual(categorizeGroceryItem("eggs"), "Dairy", "eggs -> Dairy")
}

func testBasicMeat() {
    checkEqual(categorizeGroceryItem("chicken"), "Meat", "chicken -> Meat")
    checkEqual(categorizeGroceryItem("salmon"), "Meat", "salmon -> Meat")
    checkEqual(categorizeGroceryItem("bacon"), "Meat", "bacon -> Meat")
    checkEqual(categorizeGroceryItem("shrimp"), "Meat", "shrimp -> Meat")
}

func testBasicBakery() {
    checkEqual(categorizeGroceryItem("bread"), "Bakery", "bread -> Bakery")
    checkEqual(categorizeGroceryItem("bagel"), "Bakery", "bagel -> Bakery")
    checkEqual(categorizeGroceryItem("croissant"), "Bakery", "croissant -> Bakery")
}

func testBasicDryCanned() {
    checkEqual(categorizeGroceryItem("rice"), "Dry & Canned", "rice -> Dry & Canned")
    checkEqual(categorizeGroceryItem("pasta"), "Dry & Canned", "pasta -> Dry & Canned")
    checkEqual(categorizeGroceryItem("cereal"), "Dry & Canned", "cereal -> Dry & Canned")
    checkEqual(categorizeGroceryItem("flour"), "Dry & Canned", "flour -> Dry & Canned")
}

func testBasicBeverages() {
    checkEqual(categorizeGroceryItem("coffee"), "Beverages", "coffee -> Beverages")
    checkEqual(categorizeGroceryItem("water"), "Beverages", "water -> Beverages")
    checkEqual(categorizeGroceryItem("juice"), "Beverages", "juice -> Beverages")
}

func testBasicSnacks() {
    checkEqual(categorizeGroceryItem("chips"), "Snacks", "chips -> Snacks")
    checkEqual(categorizeGroceryItem("cookies"), "Snacks", "cookies -> Snacks")
    checkEqual(categorizeGroceryItem("crackers"), "Snacks", "crackers -> Snacks")
}

func testBasicCondiments() {
    checkEqual(categorizeGroceryItem("ketchup"), "Condiments", "ketchup -> Condiments")
    checkEqual(categorizeGroceryItem("mustard"), "Condiments", "mustard -> Condiments")
    checkEqual(categorizeGroceryItem("mayo"), "Condiments", "mayo -> Condiments")
}

func testBasicHousehold() {
    checkEqual(categorizeGroceryItem("soap"), "Household", "soap -> Household")
    checkEqual(categorizeGroceryItem("detergent"), "Household", "detergent -> Household")
    checkEqual(categorizeGroceryItem("sponge"), "Household", "sponge -> Household")
}

// MARK: - Compound Items (override rules)

func testCompoundBrothStock() {
    checkEqual(
        categorizeGroceryItem("turkey broth"),
        "Dry & Canned",
        "turkey broth -> Dry & Canned (not Meat)"
    )
    checkEqual(
        categorizeGroceryItem("chicken stock"),
        "Dry & Canned",
        "chicken stock -> Dry & Canned (not Meat)"
    )
    checkEqual(
        categorizeGroceryItem("chicken broth"),
        "Dry & Canned",
        "chicken broth -> Dry & Canned (not Meat)"
    )
    checkEqual(
        categorizeGroceryItem("beef stock"),
        "Dry & Canned",
        "beef stock -> Dry & Canned (not Meat)"
    )
    checkEqual(
        categorizeGroceryItem("vegetable broth"),
        "Dry & Canned",
        "vegetable broth -> Dry & Canned"
    )
    checkEqual(
        categorizeGroceryItem("bone broth"),
        "Dry & Canned",
        "bone broth -> Dry & Canned"
    )
}

func testCompoundSoupMix() {
    checkEqual(
        categorizeGroceryItem("chicken soup"),
        "Dry & Canned",
        "chicken soup -> Dry & Canned (not Meat)"
    )
    checkEqual(
        categorizeGroceryItem("onion soup mix"),
        "Dry & Canned",
        "onion soup mix -> Dry & Canned (not Produce)"
    )
    checkEqual(
        categorizeGroceryItem("cake mix"),
        "Dry & Canned",
        "cake mix -> Dry & Canned (not Bakery)"
    )
    checkEqual(
        categorizeGroceryItem("pancake mix"),
        "Dry & Canned",
        "pancake mix -> Dry & Canned"
    )
}

func testCompoundFrozen() {
    checkEqual(
        categorizeGroceryItem("frozen pizza"),
        "Frozen",
        "frozen pizza -> Frozen"
    )
    checkEqual(
        categorizeGroceryItem("frozen vegetables"),
        "Frozen",
        "frozen vegetables -> Frozen"
    )
    checkEqual(
        categorizeGroceryItem("frozen chicken"),
        "Frozen",
        "frozen chicken -> Frozen (not Meat)"
    )
    checkEqual(
        categorizeGroceryItem("frozen berries"),
        "Frozen",
        "frozen berries -> Frozen (not Produce)"
    )
}

func testCompoundSauces() {
    checkEqual(
        categorizeGroceryItem("hot sauce"),
        "Condiments",
        "hot sauce -> Condiments"
    )
    checkEqual(
        categorizeGroceryItem("soy sauce"),
        "Condiments",
        "soy sauce -> Condiments"
    )
    checkEqual(
        categorizeGroceryItem("pasta sauce"),
        "Dry & Canned",
        "pasta sauce -> Dry & Canned (multi-word match)"
    )
    checkEqual(
        categorizeGroceryItem("marinara sauce"),
        "Dry & Canned",
        "marinara sauce -> Dry & Canned (multi-word match)"
    )
}

// MARK: - Plurals

func testPlurals() {
    checkEqual(
        categorizeGroceryItem("berries"),
        "Produce",
        "berries -> Produce (plural of berry)"
    )
    checkEqual(
        categorizeGroceryItem("potatoes"),
        "Produce",
        "potatoes -> Produce (plural of potato)"
    )
    checkEqual(
        categorizeGroceryItem("tomatoes"),
        "Produce",
        "tomatoes -> Produce (plural of tomato)"
    )
    checkEqual(
        categorizeGroceryItem("carrots"),
        "Produce",
        "carrots -> Produce (plural of carrot)"
    )
    checkEqual(
        categorizeGroceryItem("onions"),
        "Produce",
        "onions -> Produce (plural of onion)"
    )
    checkEqual(
        categorizeGroceryItem("lemons"),
        "Produce",
        "lemons -> Produce (plural of lemon)"
    )
    checkEqual(
        categorizeGroceryItem("cherries"),
        "Produce",
        "cherries -> Produce (plural of cherry)"
    )
    checkEqual(
        categorizeGroceryItem("peaches"),
        "Produce",
        "peaches -> Produce (plural of peach)"
    )
}

// MARK: - Items the old system missed

func testPreviouslyMissedItems() {
    checkEqual(
        categorizeGroceryItem("ginger"),
        "Produce",
        "ginger -> Produce (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("berries"),
        "Produce",
        "berries -> Produce (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("kale"),
        "Produce",
        "kale -> Produce (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("zucchini"),
        "Produce",
        "zucchini -> Produce (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("shallot"),
        "Produce",
        "shallot -> Produce (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("leek"),
        "Produce",
        "leek -> Produce (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("parsnip"),
        "Produce",
        "parsnip -> Produce (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("mozzarella"),
        "Dairy",
        "mozzarella -> Dairy (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("feta"),
        "Dairy",
        "feta -> Dairy (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("lamb"),
        "Meat",
        "lamb -> Meat (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("tilapia"),
        "Meat",
        "tilapia -> Meat (was Other)"
    )
    checkEqual(
        categorizeGroceryItem("lobster"),
        "Meat",
        "lobster -> Meat (was Other)"
    )
}

// MARK: - Edge Cases

func testEdgeCases() {
    checkEqual(
        categorizeGroceryItem("ice cream"),
        "Frozen",
        "ice cream -> Frozen"
    )
    checkEqual(
        categorizeGroceryItem("Ice Cream"),
        "Frozen",
        "Ice Cream -> Frozen (case insensitive)"
    )
    checkEqual(
        categorizeGroceryItem("  Milk  "),
        "Dairy",
        "whitespace trimmed: Milk -> Dairy"
    )
    checkEqual(
        categorizeGroceryItem("CHICKEN"),
        "Meat",
        "CHICKEN -> Meat (all caps)"
    )
    checkEqual(
        categorizeGroceryItem(""),
        "Other",
        "empty string -> Other"
    )
    checkEqual(
        categorizeGroceryItem("xyzzy"),
        "Other",
        "unknown item -> Other"
    )
}

func testMultiWordProduce() {
    checkEqual(
        categorizeGroceryItem("bell pepper"),
        "Produce",
        "bell pepper -> Produce"
    )
    checkEqual(
        categorizeGroceryItem("sweet potato"),
        "Produce",
        "sweet potato -> Produce"
    )
    checkEqual(
        categorizeGroceryItem("green onion"),
        "Produce",
        "green onion -> Produce"
    )
    checkEqual(
        categorizeGroceryItem("baby spinach"),
        "Produce",
        "baby spinach -> Produce"
    )
}

func testMultiWordDairy() {
    checkEqual(
        categorizeGroceryItem("cream cheese"),
        "Dairy",
        "cream cheese -> Dairy"
    )
    checkEqual(
        categorizeGroceryItem("sour cream"),
        "Dairy",
        "sour cream -> Dairy"
    )
    checkEqual(
        categorizeGroceryItem("greek yogurt"),
        "Dairy",
        "greek yogurt -> Dairy"
    )
}

func testMultiWordMeat() {
    checkEqual(
        categorizeGroceryItem("ground beef"),
        "Meat",
        "ground beef -> Meat"
    )
    checkEqual(
        categorizeGroceryItem("chicken breast"),
        "Meat",
        "chicken breast -> Meat"
    )
    checkEqual(
        categorizeGroceryItem("pork chop"),
        "Meat",
        "pork chop -> Meat"
    )
}

func testMultiWordHousehold() {
    checkEqual(
        categorizeGroceryItem("paper towels"),
        "Household",
        "paper towels -> Household"
    )
    checkEqual(
        categorizeGroceryItem("trash bags"),
        "Household",
        "trash bags -> Household"
    )
    checkEqual(
        categorizeGroceryItem("dish soap"),
        "Household",
        "dish soap -> Household"
    )
}

func testCondimentOils() {
    checkEqual(
        categorizeGroceryItem("olive oil"),
        "Condiments",
        "olive oil -> Condiments"
    )
    checkEqual(
        categorizeGroceryItem("coconut oil"),
        "Condiments",
        "coconut oil -> Condiments"
    )
    checkEqual(
        categorizeGroceryItem("cooking spray"),
        "Condiments",
        "cooking spray -> Condiments"
    )
}

func testDryCannedSpecific() {
    checkEqual(
        categorizeGroceryItem("peanut butter"),
        "Dry & Canned",
        "peanut butter -> Dry & Canned"
    )
    checkEqual(
        categorizeGroceryItem("baking soda"),
        "Dry & Canned",
        "baking soda -> Dry & Canned"
    )
    checkEqual(
        categorizeGroceryItem("canned tuna"),
        "Dry & Canned",
        "canned tuna -> Dry & Canned"
    )
    checkEqual(
        categorizeGroceryItem("coconut milk"),
        "Dry & Canned",
        "coconut milk -> Dry & Canned (shelf-stable)"
    )
}

// MARK: - Test Runner

func runGroceryCategorizerTests() -> Bool {
    print("\n=== Grocery Categorizer Tests ===")

    testBasicProduce()
    testBasicDairy()
    testBasicMeat()
    testBasicBakery()
    testBasicDryCanned()
    testBasicBeverages()
    testBasicSnacks()
    testBasicCondiments()
    testBasicHousehold()
    testCompoundBrothStock()
    testCompoundSoupMix()
    testCompoundFrozen()
    testCompoundSauces()
    testPlurals()
    testPreviouslyMissedItems()
    testEdgeCases()
    testMultiWordProduce()
    testMultiWordDairy()
    testMultiWordMeat()
    testMultiWordHousehold()
    testCondimentOils()
    testDryCannedSpecific()

    return printTestSummary("Grocery Categorizer Tests")
}
