import 'package:plateplan/features/discover/data/discover_repository.dart';

class BrowseCategory {
  const BrowseCategory({
    required this.id,
    required this.label,
    required this.keywords,
    required this.mealScope,
    this.graphicUrl,
    this.excludedByDiets = const {},
  });

  final String id;
  final String label;
  final List<String> keywords;
  final DiscoverMealType mealScope;
  final String? graphicUrl;
  final Set<String> excludedByDiets;
}

const _twemoji = 'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72';

const kBrowseCategories = <BrowseCategory>[
  // ── Dinner ──────────────────────────────────────────────────────────
  BrowseCategory(
    id: 'dinner-italian',
    label: 'Italian',
    keywords: ['italian', 'pasta', 'spaghetti', 'penne', 'linguine', 'risotto', 'gnocchi'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f35d.png',
  ),
  BrowseCategory(
    id: 'dinner-mexican',
    label: 'Mexican',
    keywords: ['mexican', 'taco', 'burrito', 'enchilada', 'fajita', 'quesadilla', 'tamale'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f32e.png',
  ),
  BrowseCategory(
    id: 'dinner-chinese',
    label: 'Chinese',
    keywords: ['chinese', 'stir-fry', 'stir fry', 'lo mein', 'fried rice', 'kung pao', 'szechuan', 'wok'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f961.png',
  ),
  BrowseCategory(
    id: 'dinner-thai',
    label: 'Thai',
    keywords: ['thai', 'pad thai', 'coconut curry', 'lemongrass', 'thai curry', 'thai basil'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f35b.png',
  ),
  BrowseCategory(
    id: 'dinner-indian',
    label: 'Indian',
    keywords: ['indian', 'tikka', 'masala', 'korma', 'curry', 'dal', 'biryani', 'naan', 'tandoori'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f35b.png',
  ),
  BrowseCategory(
    id: 'dinner-mediterranean',
    label: 'Mediterranean',
    keywords: ['mediterranean', 'greek', 'orzo', 'falafel', 'hummus', 'tzatziki', 'pita', 'shawarma'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f9c6.png',
  ),
  BrowseCategory(
    id: 'dinner-japanese',
    label: 'Japanese',
    keywords: ['japanese', 'ramen', 'teriyaki', 'sushi', 'miso', 'udon', 'soba', 'tempura'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f35c.png',
  ),
  BrowseCategory(
    id: 'dinner-korean',
    label: 'Korean',
    keywords: ['korean', 'bibimbap', 'kimchi', 'bulgogi', 'gochujang', 'japchae'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f35c.png',
  ),
  BrowseCategory(
    id: 'dinner-american',
    label: 'American Classics',
    keywords: ['american', 'burger', 'meatloaf', 'mac and cheese', 'bbq', 'grilled'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f354.png',
  ),
  BrowseCategory(
    id: 'dinner-southern',
    label: 'Southern & Cajun',
    keywords: ['southern', 'cajun', 'gumbo', 'grits', 'biscuit', 'fried', 'jambalaya', 'creole'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f372.png',
  ),
  BrowseCategory(
    id: 'dinner-one-pan',
    label: 'One-Pan & Sheet Pan',
    keywords: ['one-pan', 'one pan', 'sheet pan', 'sheet-pan', 'skillet'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f373.png',
  ),
  BrowseCategory(
    id: 'dinner-soups',
    label: 'Soups & Stews',
    keywords: ['soup', 'stew', 'chowder', 'bisque', 'chili', 'broth'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f35c.png',
  ),

  // ── Breakfast ───────────────────────────────────────────────────────
  BrowseCategory(
    id: 'breakfast-eggs',
    label: 'Eggs & Omelets',
    keywords: ['egg', 'omelet', 'omelette', 'frittata', 'scramble', 'quiche'],
    mealScope: DiscoverMealType.entree,
    graphicUrl: '$_twemoji/1f373.png',
    excludedByDiets: {'vegan'},
  ),
  BrowseCategory(
    id: 'breakfast-pancakes',
    label: 'Pancakes & Waffles',
    keywords: ['pancake', 'waffle', 'crepe', 'hotcake', 'french toast'],
    mealScope: DiscoverMealType.entree,
    graphicUrl: '$_twemoji/1f95e.png',
  ),
  BrowseCategory(
    id: 'breakfast-oats',
    label: 'Oats & Granola',
    keywords: ['oat', 'overnight oats', 'granola', 'porridge', 'muesli'],
    mealScope: DiscoverMealType.entree,
    graphicUrl: '$_twemoji/1f963.png',
  ),
  BrowseCategory(
    id: 'breakfast-smoothies',
    label: 'Smoothies & Bowls',
    keywords: ['smoothie', 'acai', 'bowl', 'shake', 'blend'],
    mealScope: DiscoverMealType.entree,
    graphicUrl: '$_twemoji/1f964.png',
  ),
  BrowseCategory(
    id: 'breakfast-savory',
    label: 'Savory Breakfasts',
    keywords: ['hash', 'breakfast casserole', 'breakfast burrito', 'breakfast sandwich', 'avocado toast'],
    mealScope: DiscoverMealType.entree,
    graphicUrl: '$_twemoji/1f96a.png',
  ),
  BrowseCategory(
    id: 'breakfast-healthy',
    label: 'Healthy & Light',
    keywords: ['healthy', 'clean', 'nourishing', 'protein', 'whole30', 'paleo'],
    mealScope: DiscoverMealType.entree,
    graphicUrl: '$_twemoji/1f957.png',
  ),

  // ── Lunch ───────────────────────────────────────────────────────────
  BrowseCategory(
    id: 'lunch-salads',
    label: 'Salads',
    keywords: ['salad', 'vinaigrette', 'greens', 'caesar', 'grain bowl'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f96c.png',
  ),
  BrowseCategory(
    id: 'lunch-sandwiches',
    label: 'Sandwiches & Wraps',
    keywords: ['sandwich', 'wrap', 'panini', 'melt', 'hoagie', 'sub', 'pita'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f96a.png',
  ),
  BrowseCategory(
    id: 'lunch-soups',
    label: 'Soups & Bowls',
    keywords: ['soup', 'bowl', 'chili', 'stew', 'ramen', 'pho'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f35c.png',
  ),
  BrowseCategory(
    id: 'lunch-mexican',
    label: 'Mexican',
    keywords: ['mexican', 'taco', 'burrito', 'quesadilla', 'tostada'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f32e.png',
  ),
  BrowseCategory(
    id: 'lunch-mediterranean',
    label: 'Mediterranean',
    keywords: ['mediterranean', 'greek', 'falafel', 'hummus', 'shawarma'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f9c6.png',
  ),
  BrowseCategory(
    id: 'lunch-asian',
    label: 'Asian',
    keywords: ['asian', 'noodle', 'rice bowl', 'stir-fry', 'dumpling', 'bao'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f961.png',
  ),
  BrowseCategory(
    id: 'lunch-meal-prep',
    label: 'Meal Prep',
    keywords: ['meal prep', 'batch', 'make ahead', 'weekly'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f371.png',
  ),

  // ── Appetizers & Snacks ─────────────────────────────────────────────
  BrowseCategory(
    id: 'snack-dips',
    label: 'Dips & Spreads',
    keywords: ['dip', 'hummus', 'guacamole', 'salsa', 'tzatziki', 'tapenade', 'muhammara'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f95f.png',
  ),
  BrowseCategory(
    id: 'snack-finger-foods',
    label: 'Finger Foods',
    keywords: ['bites', 'skewer', 'roll', 'taquito', 'dumpling', 'poppers', 'spring roll'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f96f.png',
  ),
  BrowseCategory(
    id: 'snack-boards',
    label: 'Boards & Platters',
    keywords: ['board', 'platter', 'charcuterie', 'crudite', 'mezze', 'nachos'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f9c0.png',
    excludedByDiets: {'vegan'},
  ),
  BrowseCategory(
    id: 'snack-crispy',
    label: 'Crispy Snacks',
    keywords: ['fries', 'onion rings', 'chips', 'popcorn', 'fried pickles', 'fritters'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f35f.png',
  ),
  BrowseCategory(
    id: 'snack-healthy',
    label: 'Healthy Snacks',
    keywords: ['veggie', 'nuts', 'seeds', 'energy balls', 'fruit', 'yogurt', 'edamame'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f96c.png',
  ),
  BrowseCategory(
    id: 'snack-seafood',
    label: 'Seafood Bites',
    keywords: ['shrimp', 'prawns', 'ceviche', 'smoked salmon', 'crab cake'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f990.png',
    excludedByDiets: {'vegetarian', 'vegan'},
  ),
  BrowseCategory(
    id: 'snack-wings-meaty',
    label: 'Wings & Meaty Bites',
    keywords: ['wings', 'meatballs', 'sausage', 'buffalo', 'chicken', 'bacon'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f357.png',
    excludedByDiets: {'vegetarian', 'vegan', 'pescatarian'},
  ),

  // ── Desserts ────────────────────────────────────────────────────────
  BrowseCategory(
    id: 'dessert-chocolate',
    label: 'Chocolate',
    keywords: ['chocolate', 'brownie', 'mousse', 'cacao', 'fudge'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f36b.png',
  ),
  BrowseCategory(
    id: 'dessert-cookies',
    label: 'Cookies & Bars',
    keywords: ['cookie', 'bars', 'shortbread', 'snickerdoodle', 'biscotti'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f36a.png',
  ),
  BrowseCategory(
    id: 'dessert-cakes',
    label: 'Cakes & Cupcakes',
    keywords: ['cake', 'cupcake', 'layer cake', 'pound cake', 'bundt'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f370.png',
  ),
  BrowseCategory(
    id: 'dessert-pies',
    label: 'Pies & Tarts',
    keywords: ['pie', 'cobbler', 'crisp', 'crumble', 'tart', 'galette'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f967.png',
  ),
  BrowseCategory(
    id: 'dessert-fruit',
    label: 'Fruit Desserts',
    keywords: ['fruit', 'berries', 'strawberry', 'peach', 'apple', 'cherry', 'compote'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f352.png',
  ),
  BrowseCategory(
    id: 'dessert-frozen',
    label: 'Frozen & Creamy',
    keywords: ['ice cream', 'pudding', 'panna cotta', 'sorbet', 'custard', 'gelato'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f366.png',
  ),
  BrowseCategory(
    id: 'dessert-no-bake',
    label: 'No-Bake',
    keywords: ['no-bake', 'energy balls', 'truffles', 'protein balls'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f95c.png',
  ),
  BrowseCategory(
    id: 'dessert-breads',
    label: 'Muffins & Quick Breads',
    keywords: ['muffin', 'banana bread', 'zucchini bread', 'quick bread', 'scone'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f9c1.png',
  ),
];

/// Look up a [BrowseCategory] by its [id]. Returns `null` if not found.
BrowseCategory? browseCategoryById(String id) {
  for (final cat in kBrowseCategories) {
    if (cat.id == id) return cat;
  }
  return null;
}

/// Return candidate categories for a [mealScope] after removing those
/// excluded by any of [activeDiets].
List<BrowseCategory> browseCategoriesForMeal(
  DiscoverMealType mealScope,
  Set<String> activeDiets,
) {
  return kBrowseCategories.where((cat) {
    if (cat.mealScope != mealScope) return false;
    if (activeDiets.isNotEmpty &&
        cat.excludedByDiets.intersection(activeDiets).isNotEmpty) {
      return false;
    }
    return true;
  }).toList();
}
