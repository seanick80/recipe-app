/**
 * Comprehensive text-based grocery item categorizer.
 *
 * Uses multiple matching strategies — exact word matching, suffix/compound
 * handling, and override rules — to assign grocery items to store aisle
 * categories. Designed to be replaced by a text classifier later.
 *
 * Ported from `SharedLogic/GroceryCategorizer.swift` (the SwiftUI app's
 * categorizer); behavior — including the test suite — is kept identical.
 */

export type GroceryCategory =
  | 'Produce'
  | 'Dairy'
  | 'Meat'
  | 'Bakery'
  | 'Dry & Canned'
  | 'Frozen'
  | 'Snacks'
  | 'Beverages'
  | 'Condiments'
  | 'Spices'
  | 'Household'
  | 'Other';

// MARK: - Public API

/**
 * Categorize a grocery item name into a store aisle category.
 */
export function categorizeGroceryItem(name: string): GroceryCategory {
  const lower = name.toLowerCase();
  const words = tokenize(lower);

  // Phase 1: Multi-word exact matches (highest priority, checked first)
  const multiWord = matchMultiWord(lower);
  if (multiWord !== null) {
    // Still allow compound overrides to take precedence
    const override = matchCompoundOverride(words);
    if (override !== null) {
      return override;
    }
    return multiWord;
  }

  // Phase 2: Compound/context overrides — "broth", "stock", "soup", "mix"
  // override even if another keyword would match.
  const override = matchCompoundOverride(words);
  if (override !== null) {
    return override;
  }

  // Phase 3: Suffix-based matching (e.g., "berries" -> Produce)
  const suffix = matchSuffix(lower);
  if (suffix !== null) {
    return suffix;
  }

  // Phase 4: Exact single-word matching with category priority.
  // Collect ALL matching categories, then pick highest priority.
  // This fixes "cloves garlic" → Produce (garlic outranks clove).
  const exact = matchExactWordWithPriority(words);
  if (exact !== null) {
    return exact;
  }

  return 'Other';
}

// MARK: - Tokenization

/** Split input into lowercase word tokens, stripping common punctuation. */
function tokenize(input: string): string[] {
  const result: string[] = [];
  let current = '';
  for (const ch of input) {
    if (/[\p{L}\p{N}]/u.test(ch) || ch === "'" || ch === '-') {
      current += ch;
    } else if (current !== '') {
      result.push(current);
      current = '';
    }
  }
  if (current !== '') {
    result.push(current);
  }
  return result;
}

// MARK: - Multi-Word Matches

/** Check for multi-word phrases that need to match as a unit. */
function matchMultiWord(lower: string): GroceryCategory | null {
  for (const [phrases, category] of multiWordEntries) {
    for (const phrase of phrases) {
      if (lower.includes(phrase)) {
        return category;
      }
    }
  }
  return null;
}

const multiWordEntries: [string[], GroceryCategory][] = [
  // Frozen
  [
    [
      'ice cream', 'frozen yogurt', 'frozen vegetable', 'frozen fruit',
      'frozen dinner', 'frozen pizza', 'frozen waffle', 'frozen burrito',
      'frozen fries', 'frozen fish', 'frozen shrimp', 'frozen chicken',
      'frozen pie', 'frozen meal', 'tv dinner', 'ice pop', 'popsicle',
      'frozen corn', 'frozen peas', 'frozen broccoli', 'frozen berries',
      'frozen meatball',
    ],
    'Frozen',
  ],

  // Condiments
  [
    [
      'hot sauce', 'soy sauce', 'fish sauce', 'worcestershire sauce',
      'teriyaki sauce', 'bbq sauce', 'barbecue sauce', 'steak sauce',
      'cocktail sauce', 'tartar sauce', 'buffalo sauce',
      'salad dressing', 'ranch dressing',
      'olive oil', 'vegetable oil', 'canola oil', 'coconut oil',
      'sesame oil', 'avocado oil', 'peanut oil', 'cooking spray',
    ],
    'Condiments',
  ],

  // Dry & Canned
  [
    [
      'chicken broth', 'turkey broth', 'beef broth', 'vegetable broth',
      'chicken stock', 'beef stock', 'vegetable stock', 'bone broth',
      'tomato paste', 'tomato sauce', 'pasta sauce', 'marinara sauce',
      'canned tomato', 'canned bean', 'canned corn', 'canned tuna',
      'canned salmon', 'canned chicken', 'canned fruit', 'canned soup',
      'baking soda', 'baking powder', 'cream of tartar',
      'cake mix', 'brownie mix', 'pancake mix', 'muffin mix',
      'bread crumb', 'panko', 'cornstarch', 'corn starch',
      'powdered sugar', 'brown sugar', 'confectioner',
      'mac and cheese', 'mac & cheese', 'ramen noodle',
      'instant oatmeal', 'instant rice', 'minute rice',
      'peanut butter', 'almond butter', 'sunflower butter',
      'dried bean', 'dried lentil', 'dried pasta',
      'coconut milk', 'condensed milk', 'evaporated milk',
    ],
    'Dry & Canned',
  ],

  // Dairy
  [
    [
      'cream cheese', 'sour cream', 'whipped cream', 'heavy cream',
      'half and half', 'half & half', 'cottage cheese',
      'string cheese', 'shredded cheese', 'sliced cheese',
      'american cheese', 'swiss cheese', 'cheddar cheese',
      'greek yogurt', 'almond milk', 'oat milk', 'soy milk',
    ],
    'Dairy',
  ],

  // Meat
  [
    [
      'ground beef', 'ground turkey', 'ground pork', 'ground chicken',
      'chicken breast', 'chicken thigh', 'chicken wing', 'chicken leg',
      'chicken tender', 'chicken drumstick',
      'pork chop', 'pork loin', 'pork tenderloin', 'pork shoulder',
      'pork belly', 'pork roast',
      'beef steak', 'beef roast', 'beef tenderloin',
      'deli meat', 'lunch meat', 'deli turkey', 'deli ham',
      'hot dog', 'italian sausage', 'breakfast sausage',
      'baby back rib', 'spare rib',
    ],
    'Meat',
  ],

  // Produce
  [
    [
      'bell pepper', 'green pepper', 'red pepper', 'jalapeno pepper',
      'sweet potato', 'russet potato', 'red potato', 'gold potato',
      'baby carrot', 'baby spinach', 'romaine lettuce', 'iceberg lettuce',
      'green onion', 'red onion', 'yellow onion', 'white onion',
      'green bean', 'snap pea', 'snow pea',
      'cherry tomato', 'grape tomato', 'roma tomato',
      'fresh herb', 'fresh basil', 'fresh cilantro', 'fresh parsley',
      'fresh dill', 'fresh mint', 'fresh rosemary', 'fresh thyme',
      'brussels sprout', 'bok choy', 'collard green',
      'acorn squash', 'butternut squash', 'spaghetti squash',
      'portobello mushroom',
    ],
    'Produce',
  ],

  // Bakery
  [
    [
      'hamburger bun', 'hot dog bun', 'english muffin', 'dinner roll',
      'french bread', 'italian bread', 'sourdough bread', 'wheat bread',
      'white bread', 'rye bread', 'pita bread', 'naan bread',
      'banana bread', 'garlic bread', 'texas toast',
      'tortilla chip',
    ],
    'Bakery',
  ],

  // Household
  [
    [
      'paper towel', 'toilet paper', 'trash bag', 'garbage bag',
      'dish soap', 'laundry detergent', 'fabric softener',
      'aluminum foil', 'plastic wrap', 'parchment paper',
      'sandwich bag', 'freezer bag', 'storage bag',
      'dryer sheet', 'cleaning spray', 'all purpose cleaner',
      'hand soap', 'body wash',
    ],
    'Household',
  ],

  // Beverages
  [
    [
      'orange juice', 'apple juice', 'grape juice', 'cranberry juice',
      'tomato juice', 'lemon juice', 'lime juice',
      'sparkling water', 'mineral water', 'coconut water',
      'energy drink', 'sports drink', 'protein shake',
      'iced tea', 'green tea', 'black tea', 'herbal tea',
      'hot chocolate', 'hot cocoa',
    ],
    'Beverages',
  ],

  // Snacks
  [
    [
      'potato chip', 'tortilla chip', 'pita chip',
      'granola bar', 'protein bar', 'energy bar', 'snack bar',
      'trail mix', 'mixed nut', 'rice cake', 'rice crispy',
      'fruit snack', 'fruit leather', 'beef jerky',
      'popcorn kernel',
    ],
    'Snacks',
  ],

  // Spices (multi-word)
  [
    [
      'garam masala', 'chili powder', 'garlic powder', 'onion powder',
      'curry powder', 'cocoa powder', 'chili flake', 'red pepper flake',
      'bay leaf', 'bay leaves', 'fennel seed', 'mustard seed',
      'celery seed', 'caraway seed', 'poppy seed', 'sesame seed',
      'five spice', 'chinese five spice', 'lemon pepper',
      'italian seasoning', 'poultry seasoning', 'cajun seasoning',
      'taco seasoning', 'ranch seasoning', 'everything bagel seasoning',
      'old bay', 'herbs de provence', 'herbes de provence',
      'vanilla extract', 'almond extract', 'peppermint extract',
      'cream of tartar',
    ],
    'Spices',
  ],

  // Dry & Canned (specific powder/flour entries that were over-matched before)
  [
    [
      'baking powder', 'baking soda', 'powdered sugar',
      'all purpose flour', 'self raising flour', 'self rising flour',
      'bread flour', 'cake flour', 'whole wheat flour',
      'corn starch', 'cornstarch', 'arrowroot starch',
      'tapioca starch',
    ],
    'Dry & Canned',
  ],
];

// MARK: - Compound Override Rules

/**
 * If any of these words appear anywhere in the token list, force the category
 * regardless of other matches. This handles items like "turkey broth" which
 * should be "Dry & Canned" not "Meat".
 */
function matchCompoundOverride(words: string[]): GroceryCategory | null {
  // Note: "powder", "seasoning", "flour", "starch" removed — they were too
  // aggressive (e.g. "chili powder" → Dry & Canned instead of Spices). Those
  // items are now handled by specific multi-word entries.
  const dryCannedOverrides = new Set(['broth', 'stock', 'soup', 'bouillon', 'mix']);
  const frozenOverrides = new Set(['frozen']);
  const condimentOverrides = new Set(['dressing', 'marinade']);

  for (const word of words) {
    if (frozenOverrides.has(word)) return 'Frozen';
  }
  for (const word of words) {
    if (dryCannedOverrides.has(word)) return 'Dry & Canned';
  }
  for (const word of words) {
    if (condimentOverrides.has(word)) return 'Condiments';
  }
  return null;
}

// MARK: - Suffix Matching

/** Match word endings for natural groupings (berries -> berry -> Produce). */
function matchSuffix(lower: string): GroceryCategory | null {
  const words = tokenize(lower);
  for (const word of words) {
    for (const [suffixes, category] of suffixRules) {
      for (const suffix of suffixes) {
        if (word.endsWith(suffix) && word.length > suffix.length) {
          return category;
        }
      }
    }
  }
  return null;
}

const suffixRules: [string[], GroceryCategory][] = [
  // Produce
  [
    ['berry', 'berries', 'apple', 'apples', 'melon', 'lettuce', 'greens', 'herb', 'herbs'],
    'Produce',
  ],
  // Dairy
  [['cheese', 'yogurt'], 'Dairy'],
];

// MARK: - Exact Word Matching

/**
 * Match individual tokens against keyword sets, collecting ALL matches across
 * all tokens. If multiple categories match (e.g. "cloves garlic" matches both
 * Spices and Produce), the highest-priority category wins.
 *
 * Priority order: Produce > Meat > Dairy > Bakery > Frozen > Dry & Canned >
 * Beverages > Snacks > Condiments > Spices > Household
 */
function matchExactWordWithPriority(words: string[]): GroceryCategory | null {
  const matched = new Set<GroceryCategory>();
  for (const word of words) {
    for (const candidate of normalizePluralCandidates(word)) {
      const cat = exactWordLookup.get(candidate);
      if (cat !== undefined) {
        matched.add(cat);
      }
    }
  }
  if (matched.size === 0) return null;
  if (matched.size === 1) return matched.values().next().value ?? null;
  // Multiple categories matched — pick highest priority (lowest number).
  let best: GroceryCategory | null = null;
  for (const cat of matched) {
    if (best === null || categoryPriority(cat) < categoryPriority(best)) {
      best = cat;
    }
  }
  return best;
}

/**
 * Lower number = higher priority. Produce and Meat win over Spices/Condiments
 * so that "5 cloves garlic" → Produce, not Spices.
 */
function categoryPriority(category: GroceryCategory): number {
  switch (category) {
    case 'Produce':
      return 0;
    case 'Meat':
      return 1;
    case 'Dairy':
      return 2;
    case 'Bakery':
      return 3;
    case 'Frozen':
      return 4;
    case 'Dry & Canned':
      return 5;
    case 'Beverages':
      return 6;
    case 'Snacks':
      return 7;
    case 'Condiments':
      return 8;
    case 'Spices':
      return 9;
    case 'Household':
      return 10;
    default:
      return 99;
  }
}

/**
 * Generate plural normalization candidates. Returns the original word plus one
 * or more de-pluralized forms, ordered from most specific to least. Multiple
 * candidates handle English irregularities (e.g., "cookies" could be "cooky"
 * via ies->y or "cookie" via just dropping s).
 */
function normalizePluralCandidates(word: string): string[] {
  const candidates = [word];

  if (word.endsWith('ies') && word.length > 4) {
    // berries -> berry, cherries -> cherry
    candidates.push(word.slice(0, -3) + 'y');
    // Also try: cookies -> cookie (drop just the s)
    candidates.push(word.slice(0, -1));
  } else if (word.endsWith('ves') && word.length > 4) {
    // loaves -> loaf
    candidates.push(word.slice(0, -3) + 'f');
  } else if (word.endsWith('oes') && word.length > 4) {
    // potatoes -> potato, tomatoes -> tomato
    candidates.push(word.slice(0, -2));
  } else if (
    word.endsWith('shes') ||
    word.endsWith('ches') ||
    word.endsWith('xes') ||
    word.endsWith('zes') ||
    word.endsWith('ses')
  ) {
    if (word.length > 4) {
      candidates.push(word.slice(0, -2));
    }
  } else if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) {
    candidates.push(word.slice(0, -1));
  }

  return candidates;
}

/** Flat lookup table: word -> category. */
const exactWordLookup: Map<string, GroceryCategory> = (() => {
  const table = new Map<string, GroceryCategory>();

  const entries: [string[], GroceryCategory][] = [
    // ---- Produce ----
    [
      [
        'apple', 'apricot', 'artichoke', 'arugula', 'asparagus',
        'avocado', 'banana', 'basil', 'beet', 'berry',
        'blueberry', 'blackberry', 'raspberry', 'strawberry', 'cranberry',
        'broccoli', 'cabbage', 'cantaloupe', 'carrot', 'cauliflower',
        'celery', 'chard', 'cherry', 'chive', 'cilantro',
        'clementine', 'coconut', 'collard', 'corn', 'cucumber',
        'dill', 'eggplant', 'endive', 'fennel', 'fig',
        'garlic', 'ginger', 'grape', 'grapefruit', 'guava',
        'honeydew', 'jalapeno', 'jicama', 'kale', 'kiwi',
        'kohlrabi', 'kumquat', 'leek', 'lemon', 'lemongrass',
        'lettuce', 'lime', 'mandarin', 'mango', 'melon',
        'mint', 'mushroom', 'nectarine', 'okra', 'onion',
        'orange', 'oregano', 'papaya', 'parsley', 'parsnip',
        'peach', 'pear', 'pea', 'pepper', 'persimmon',
        'pineapple', 'plantain', 'plum', 'pomegranate', 'potato',
        'pumpkin', 'radicchio', 'radish', 'rhubarb', 'rosemary',
        'rutabaga', 'sage', 'scallion', 'shallot', 'spinach',
        'sprout', 'squash', 'tangelo', 'tangerine', 'tarragon',
        'thyme', 'tomato', 'turnip', 'watercress', 'watermelon',
        'yam', 'zucchini',
      ],
      'Produce',
    ],

    // ---- Dairy ----
    [
      [
        'milk', 'cheese', 'yogurt', 'butter', 'cream',
        'egg', 'buttermilk', 'kefir', 'ghee',
        'mozzarella', 'parmesan', 'provolone', 'ricotta',
        'brie', 'gouda', 'cheddar', 'feta', 'colby',
        'gruyere', 'havarti', 'muenster', 'swiss',
        'mascarpone', 'neufchatel', 'camembert',
        'margarine', 'whey', 'casein',
      ],
      'Dairy',
    ],

    // ---- Meat ----
    [
      [
        'chicken', 'beef', 'pork', 'fish', 'salmon',
        'shrimp', 'bacon', 'sausage', 'turkey', 'lamb',
        'veal', 'venison', 'bison', 'duck', 'goose',
        'quail', 'rabbit', 'ham', 'prosciutto', 'salami',
        'pepperoni', 'chorizo', 'bratwurst', 'kielbasa',
        'steak', 'ribs', 'roast', 'brisket', 'tenderloin',
        'sirloin', 'ribeye', 'filet', 'flank',
        'tilapia', 'cod', 'halibut', 'tuna', 'trout',
        'catfish', 'swordfish', 'mahi', 'snapper', 'bass',
        'perch', 'walleye', 'haddock', 'pollock', 'sardine',
        'anchovy', 'crab', 'lobster', 'scallop', 'mussel',
        'clam', 'oyster', 'calamari', 'squid', 'octopus',
        'crawfish', 'crayfish', 'prawn',
      ],
      'Meat',
    ],

    // ---- Bakery ----
    [
      [
        'bread', 'bagel', 'muffin', 'roll', 'bun',
        'croissant', 'baguette', 'brioche', 'focaccia',
        'ciabatta', 'sourdough', 'pretzel', 'scone',
        'biscuit', 'cornbread', 'flatbread', 'naan',
        'pita', 'tortilla', 'wrap', 'crumpet',
        'donut', 'doughnut', 'danish', 'pastry', 'strudel',
        'cake', 'cupcake', 'pie', 'tart', 'eclair',
        'cannoli', 'cronut',
      ],
      'Bakery',
    ],

    // ---- Dry & Canned ----
    [
      [
        'rice', 'pasta', 'noodle', 'spaghetti', 'penne',
        'macaroni', 'fettuccine', 'linguine', 'rigatoni',
        'orzo', 'couscous', 'quinoa', 'barley', 'bulgur',
        'farro', 'millet', 'polenta', 'grits',
        'flour', 'sugar', 'salt', 'oil',
        'cereal', 'oatmeal', 'oat', 'granola',
        'bean', 'lentil', 'chickpea',
        'broth', 'stock', 'bouillon',
        'sauce', 'salsa', 'paste',
        'can', 'canned',
        'honey', 'syrup', 'molasses', 'agave',
        'jam', 'jelly', 'preserve', 'marmalade',
        'vinegar', 'extract', 'vanilla',
        'yeast', 'gelatin', 'pectin',
        'raisin', 'crouton', 'stuffing',
        'breadcrumb', 'panko',
        'cornmeal', 'cornstarch',
        'taco', 'tortellini', 'ravioli', 'lasagna',
      ],
      'Dry & Canned',
    ],

    // ---- Frozen ----
    [['frozen', 'popsicle'], 'Frozen'],

    // ---- Snacks ----
    [
      [
        'chip', 'cookie', 'cracker', 'candy', 'chocolate',
        'snack', 'nut', 'almond', 'cashew', 'walnut',
        'pecan', 'pistachio', 'macadamia', 'hazelnut',
        'pretzel', 'popcorn', 'jerky',
        'gummy', 'licorice', 'taffy', 'caramel',
        'brownie', 'marshmallow',
      ],
      'Snacks',
    ],

    // ---- Beverages ----
    [
      [
        'water', 'juice', 'soda', 'coffee', 'tea',
        'drink', 'beer', 'wine', 'lemonade', 'cider',
        'champagne', 'vodka', 'whiskey', 'rum', 'gin',
        'tequila', 'brandy', 'bourbon', 'ale', 'lager',
        'stout', 'porter', 'mead', 'sake',
        'kombucha', 'smoothie', 'milkshake',
        'espresso', 'cappuccino', 'latte',
        'punch', 'sangria', 'margarita',
        'cocoa',
      ],
      'Beverages',
    ],

    // ---- Condiments ----
    [
      [
        'ketchup', 'mustard', 'mayo', 'mayonnaise',
        'relish', 'horseradish', 'wasabi',
        'sriracha', 'tabasco', 'sambal',
        'hummus', 'guacamole', 'tzatziki',
        'chutney', 'aioli', 'pesto',
        'dressing', 'marinade', 'glaze',
        'gravy',
      ],
      'Condiments',
    ],

    // ---- Spices ----
    [
      [
        'spice', 'seasoning', 'cumin', 'paprika',
        'turmeric', 'cinnamon', 'nutmeg', 'clove',
        'allspice', 'cardamom', 'coriander',
        'cayenne', 'chili', 'curry', 'masala',
        'saffron', 'sumac', "za'atar", 'zaatar',
        'anise', 'star-anise', 'juniper',
        'fenugreek', 'tamarind', 'mace',
        'mustard-seed', 'celery-seed',
        'peppercorn', 'pepper-flake',
      ],
      'Spices',
    ],

    // ---- Household ----
    [
      [
        'paper', 'towel', 'soap', 'detergent', 'sponge',
        'cleaner', 'bleach', 'disinfectant',
        'napkin', 'tissue', 'wipe',
        'foil', 'wrap', 'bag',
        'battery', 'lightbulb', 'candle',
        'mop', 'broom', 'brush',
        'glove', 'apron',
        'filter', 'charcoal',
      ],
      'Household',
    ],
  ];

  for (const [entryWords, category] of entries) {
    for (const word of entryWords) {
      table.set(word, category);
    }
  }
  return table;
})();
