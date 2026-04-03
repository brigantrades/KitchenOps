import 'package:plateplan/features/discover/data/discover_repository.dart';

class BrowseCategory {
  const BrowseCategory({
    required this.id,
    required this.label,
    required this.keywords,
    required this.mealScope,
    this.graphicUrl,
    this.excludedByDiets = const {},
    this.hiddenFromBrowse = false,
  });

  final String id;
  final String label;
  final List<String> keywords;
  final DiscoverMealType mealScope;
  final String? graphicUrl;
  final Set<String> excludedByDiets;

  /// When true, omitted from Discover cuisine tiles (see [browseCategoriesForMeal]).
  final bool hiddenFromBrowse;
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
    graphicUrl: '$_twemoji/1f9c8.png',
  ),
  BrowseCategory(
    id: 'dinner-mediterranean',
    label: 'Mediterranean',
    keywords: ['mediterranean', 'greek', 'orzo', 'falafel', 'hummus', 'tzatziki', 'pita', 'shawarma'],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f9c6.png',
    hiddenFromBrowse: true,
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
    id: 'dinner-spanish',
    label: 'Spanish',
    keywords: [
      'spanish',
      'paella',
      'tapas',
      'gazpacho',
      'chorizo',
      'manchego',
      'patatas',
      'sangria',
    ],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f377.png',
  ),
  BrowseCategory(
    id: 'dinner-french',
    label: 'French',
    keywords: [
      'french',
      'ratatouille',
      'bourguignon',
      'quiche',
      'gratin',
      'coq au vin',
      'bistro',
      'cassoulet',
    ],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f956.png',
  ),
  BrowseCategory(
    id: 'dinner-latin-american',
    label: 'Latin American',
    keywords: [
      'latin american',
      'ceviche',
      'empanada',
      'pernil',
      'sofrito',
      'gallo pinto',
      'moqueca',
      'pupusa',
    ],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f32d.png',
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
    id: 'dinner-instant-pot',
    label: 'Instant Pot',
    keywords: [
      'instant pot',
      'instant-pot',
      'pressure cooker',
      'electric pressure',
      'multicooker',
      'instapot',
    ],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f372.png',
  ),
  BrowseCategory(
    id: 'dinner-crock-pot',
    label: 'Crock Pot',
    keywords: [
      'crock pot',
      'crockpot',
      'crock-pot',
      'slow cooker',
      'slow-cooker',
    ],
    mealScope: DiscoverMealType.sauce,
    graphicUrl: '$_twemoji/1f958.png',
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
    label: 'Burritos & Sandwiches',
    keywords: [
      'burrito',
      'breakfast burrito',
      'sandwich',
      'breakfast sandwich',
      'wrap',
      'panini',
      'melt',
      'stromboli',
      'chimichanga',
      'croque',
    ],
    mealScope: DiscoverMealType.entree,
    graphicUrl: '$_twemoji/1f96a.png',
  ),
  BrowseCategory(
    id: 'breakfast-casseroles',
    label: 'Casseroles',
    keywords: [
      'casserole',
      'breakfast casserole',
      'strata',
      'egg bake',
      'breakfast bake',
      'french toast casserole',
      'hash brown',
      'tater tot',
    ],
    mealScope: DiscoverMealType.entree,
    graphicUrl: '$_twemoji/1f958.png',
  ),
  BrowseCategory(
    id: 'breakfast-healthy',
    label: 'Healthy & Light',
    keywords: ['healthy', 'clean', 'nourishing', 'whole30', 'paleo'],
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
    id: 'lunch-five-ingredients',
    label: '5 Ingredients or Less',
    keywords: [
      '5 ingredients or less',
      'five ingredients or less',
      '5-ingredient',
      'five-ingredient',
      '5 ingredient',
      'five ingredient',
    ],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f4dd.png',
  ),
  BrowseCategory(
    id: 'lunch-school',
    label: 'School Lunch',
    keywords: [
      'school lunch',
      'lunchbox',
      'kids lunch',
      'school lunch ideas',
      'bento',
    ],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f392.png',
  ),
  BrowseCategory(
    id: 'lunch-quick-easy',
    label: 'Quick & Easy',
    keywords: [
      'quick & easy',
      'quick and easy',
      'easy lunch',
      'quick lunch',
      '20 minute',
      '20 minutes',
    ],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/26a1.png',
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
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'lunch-mediterranean',
    label: 'Mediterranean',
    keywords: ['mediterranean', 'greek', 'falafel', 'hummus', 'shawarma'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f9c6.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'lunch-asian',
    label: 'Asian',
    keywords: ['asian', 'noodle', 'rice bowl', 'stir-fry', 'dumpling', 'bao'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f961.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'lunch-meal-prep',
    label: 'Meal Prep',
    keywords: ['meal prep', 'batch', 'make ahead', 'weekly'],
    mealScope: DiscoverMealType.side,
    graphicUrl: '$_twemoji/1f371.png',
    hiddenFromBrowse: true,
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
    id: 'snack-cheese-balls',
    label: 'Cheese Balls',
    keywords: [
      'cheese ball',
      'cheeseball',
      'cream cheese',
      'cheddar',
      'goat cheese',
      'pecan',
    ],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f37d.png',
  ),
  BrowseCategory(
    id: 'snack-crowd-favorites',
    label: 'Crowd Favorites',
    keywords: [
      'crowd favorites',
      'for a crowd',
      'potluck',
      'party',
      'entertaining',
    ],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f389.png',
  ),
  BrowseCategory(
    id: 'snack-finger-foods',
    label: 'Finger Foods',
    keywords: ['bites', 'skewer', 'roll', 'taquito', 'dumpling', 'poppers', 'spring roll'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f96f.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'snack-boards',
    label: 'Boards & Platters',
    keywords: ['board', 'platter', 'charcuterie', 'crudite', 'mezze', 'nachos'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f9c0.png',
    excludedByDiets: {'vegan'},
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'snack-crispy',
    label: 'Crispy Snacks',
    keywords: ['fries', 'onion rings', 'chips', 'popcorn', 'fried pickles', 'fritters'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f35f.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'snack-healthy',
    label: 'Healthy Snacks',
    keywords: ['veggie', 'nuts', 'seeds', 'energy balls', 'fruit', 'yogurt', 'edamame'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f96c.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'snack-seafood',
    label: 'Seafood Bites',
    keywords: ['shrimp', 'prawns', 'ceviche', 'smoked salmon', 'crab cake'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f990.png',
    excludedByDiets: {'vegetarian', 'vegan'},
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'snack-wings-meaty',
    label: 'Wings & Meaty Bites',
    keywords: ['wings', 'meatballs', 'sausage', 'buffalo', 'chicken', 'bacon'],
    mealScope: DiscoverMealType.snack,
    graphicUrl: '$_twemoji/1f357.png',
    excludedByDiets: {'vegetarian', 'vegan', 'pescatarian'},
    hiddenFromBrowse: true,
  ),

  // ── Desserts ────────────────────────────────────────────────────────
  BrowseCategory(
    id: 'dessert-sweet-bites',
    label: 'Sweet Bites',
    keywords: [
      'sweet bites',
      'finger food',
      'mini',
      'small bite',
      'bite-sized',
    ],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f36c.png',
  ),
  BrowseCategory(
    id: 'dessert-summer-delights',
    label: 'Summer Delights',
    keywords: [
      'summer delights',
      'summer pie',
      'cobbler',
      'crisp',
      'berry',
      'peach',
      'strawberry',
    ],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f31e.png',
  ),
  BrowseCategory(
    id: 'dessert-jello',
    label: 'Jello',
    keywords: [
      'jello',
      'jell-o',
      'gelatin',
      'gelatine',
      'rainbow',
    ],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f36d.png',
  ),
  BrowseCategory(
    id: 'dessert-chocolate',
    label: 'Chocolate',
    keywords: ['chocolate', 'brownie', 'mousse', 'cacao', 'fudge'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f36b.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'dessert-cookies',
    label: 'Cookies & Bars',
    keywords: ['cookie', 'bars', 'shortbread', 'snickerdoodle', 'biscotti'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f36a.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'dessert-cakes',
    label: 'Cakes & Cupcakes',
    keywords: ['cake', 'cupcake', 'layer cake', 'pound cake', 'bundt'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f370.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'dessert-pies',
    label: 'Pies & Tarts',
    keywords: ['pie', 'cobbler', 'crisp', 'crumble', 'tart', 'galette'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f967.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'dessert-fruit',
    label: 'Fruit Desserts',
    keywords: ['fruit', 'berries', 'strawberry', 'peach', 'apple', 'cherry', 'compote'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f352.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'dessert-frozen',
    label: 'Frozen & Creamy',
    keywords: ['ice cream', 'pudding', 'panna cotta', 'sorbet', 'custard', 'gelato'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f366.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'dessert-no-bake',
    label: 'No-Bake',
    keywords: ['no-bake', 'energy balls', 'truffles', 'protein balls'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f95c.png',
    hiddenFromBrowse: true,
  ),
  BrowseCategory(
    id: 'dessert-breads',
    label: 'Muffins & Quick Breads',
    keywords: ['muffin', 'banana bread', 'zucchini bread', 'quick bread', 'scone'],
    mealScope: DiscoverMealType.dessert,
    graphicUrl: '$_twemoji/1f9c1.png',
    hiddenFromBrowse: true,
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
    if (cat.hiddenFromBrowse) return false;
    if (activeDiets.isNotEmpty &&
        cat.excludedByDiets.intersection(activeDiets).isNotEmpty) {
      return false;
    }
    return true;
  }).toList();
}
