import 'package:plateplan/core/models/app_models.dart';

const String _foodIconBasePath = 'assets/images/food_icons/openmoji/';

const List<({String needle, String assetName})> _keywordAssetPairs = [
  // Common multi-word phrases first for better matching.
  (needle: 'olive oil', assetName: 'olive'),
  (needle: 'orange juice', assetName: 'tropical_drink'),
  (needle: 'apple juice', assetName: 'cup_with_straw'),
  (needle: 'grape juice', assetName: 'cup_with_straw'),
  (needle: 'vegetable oil', assetName: 'olive'),
  (needle: 'black pepper', assetName: 'salt_shaker'),
  (needle: 'red pepper flakes', assetName: 'hot_pepper'),
  (needle: 'bell pepper', assetName: 'bell_pepper'),
  (needle: 'sweet potato', assetName: 'sweet_potato'),
  (needle: 'green apple', assetName: 'green_apple'),
  (needle: 'curry powder', assetName: 'curry_rice'),
  (needle: 'soy sauce', assetName: 'takeout_box'),
  (needle: 'chicken breast', assetName: 'poultry'),
  (needle: 'ground beef', assetName: 'meat'),
  (needle: 'chicken thigh', assetName: 'poultry'),
  (needle: 'fish sauce', assetName: 'fish'),
  (needle: 'rice noodle', assetName: 'ramen'),
  (needle: 'rice paper', assetName: 'rice_bowl'),
  (needle: 'whole wheat', assetName: 'wheat'),
  (needle: 'oat milk', assetName: 'bottle_milk'),
  (needle: 'almond milk', assetName: 'bottle_milk'),
  (needle: 'coconut milk', assetName: 'coconut'),
  (needle: 'baby spinach', assetName: 'leafy_greens'),
  (needle: 'leafy greens', assetName: 'leafy_greens'),
  (needle: 'spring mix', assetName: 'salad'),
  (needle: 'mixed greens', assetName: 'salad'),
  (needle: 'salad mix', assetName: 'salad'),
  (needle: 'pizza dough', assetName: 'pizza'),
  (needle: 'bread crumbs', assetName: 'bread_loaf'),

  // Produce.
  (needle: 'bell pepper', assetName: 'bell_pepper'),
  (needle: 'strawberr', assetName: 'strawberry'),
  (needle: 'banana', assetName: 'banana'),
  (needle: 'blueberr', assetName: 'blueberries'),
  (needle: 'blackberr', assetName: 'blueberries'),
  (needle: 'raspberr', assetName: 'blueberries'),
  (needle: 'cherr', assetName: 'cherries'),
  (needle: 'grape', assetName: 'grapes'),
  (needle: 'apple', assetName: 'apple'),
  (needle: 'pear', assetName: 'pear'),
  (needle: 'peach', assetName: 'peach'),
  (needle: 'watermelon', assetName: 'watermelon'),
  (needle: 'melon', assetName: 'melon'),
  (needle: 'pineapple', assetName: 'pineapple'),
  (needle: 'mango', assetName: 'mango'),
  (needle: 'kiwi', assetName: 'kiwi'),
  (needle: 'orange', assetName: 'tangerine'),
  (needle: 'tangerine', assetName: 'tangerine'),
  (needle: 'lemon', assetName: 'lemon'),
  (needle: 'lime', assetName: 'lemon'),
  (needle: 'avocado', assetName: 'avocado'),
  (needle: 'broccoli', assetName: 'broccoli'),
  (needle: 'corn', assetName: 'corn'),
  (needle: 'mushroom', assetName: 'mushroom'),
  (needle: 'pepper', assetName: 'hot_pepper'),
  (needle: 'spinach', assetName: 'leafy_greens'),
  (needle: 'lettuce', assetName: 'leafy_greens'),
  (needle: 'kale', assetName: 'leafy_greens'),
  (needle: 'greens', assetName: 'leafy_greens'),
  (needle: 'cabbage', assetName: 'leafy_greens'),
  (needle: 'arugula', assetName: 'leafy_greens'),
  (needle: 'zucchini', assetName: 'cucumber'),
  (needle: 'cucumber', assetName: 'cucumber'),
  (needle: 'carrot', assetName: 'carrot'),
  (needle: 'potato', assetName: 'potato'),
  (needle: 'yam', assetName: 'sweet_potato'),
  (needle: 'tomato', assetName: 'tomato'),
  (needle: 'onion', assetName: 'onion'),
  (needle: 'garlic', assetName: 'garlic'),
  (needle: 'olive', assetName: 'olive'),
  (needle: 'coconut', assetName: 'coconut'),
  (needle: 'salad', assetName: 'salad'),

  // Dairy / eggs.
  (needle: 'milk', assetName: 'milk'),
  (needle: 'cream', assetName: 'milk'),
  (needle: 'yogurt', assetName: 'milk'),
  (needle: 'yoghurt', assetName: 'milk'),
  (needle: 'mozzarella', assetName: 'cheese'),
  (needle: 'cheddar', assetName: 'cheese'),
  (needle: 'parmesan', assetName: 'cheese'),
  (needle: 'cheese', assetName: 'cheese'),
  (needle: 'butter', assetName: 'butter'),
  (needle: 'egg', assetName: 'egg'),

  // Protein / seafood.
  (needle: 'chicken', assetName: 'poultry'),
  (needle: 'turkey', assetName: 'poultry'),
  (needle: 'duck', assetName: 'poultry'),
  (needle: 'salmon', assetName: 'fish'),
  (needle: 'tuna', assetName: 'fish'),
  (needle: 'cod', assetName: 'fish'),
  (needle: 'tilapia', assetName: 'fish'),
  (needle: 'sardine', assetName: 'fish'),
  (needle: 'anchovy', assetName: 'fish'),
  (needle: 'shrimp', assetName: 'shrimp'),
  (needle: 'prawn', assetName: 'shrimp'),
  (needle: 'crab', assetName: 'crab'),
  (needle: 'squid', assetName: 'squid'),
  (needle: 'oyster', assetName: 'oyster'),
  (needle: 'bacon', assetName: 'meat_bone'),
  (needle: 'pork', assetName: 'meat'),
  (needle: 'ham', assetName: 'meat'),
  (needle: 'steak', assetName: 'meat'),
  (needle: 'fish', assetName: 'fish'),
  (needle: 'beef', assetName: 'meat'),

  // Pantry / grains / baked.
  (needle: 'rice', assetName: 'rice'),
  (needle: 'noodle', assetName: 'ramen'),
  (needle: 'ramen', assetName: 'ramen'),
  (needle: 'pasta', assetName: 'spaghetti'),
  (needle: 'spaghetti', assetName: 'spaghetti'),
  (needle: 'curry', assetName: 'curry_rice'),
  (needle: 'dumpling', assetName: 'dumpling'),
  (needle: 'taco', assetName: 'taco'),
  (needle: 'burrito', assetName: 'burrito'),
  (needle: 'sandwich', assetName: 'sandwich'),
  (needle: 'burger', assetName: 'burger'),
  (needle: 'hot dog', assetName: 'hotdog'),
  (needle: 'pizza', assetName: 'pizza'),
  (needle: 'fries', assetName: 'fries'),
  (needle: 'chip', assetName: 'fries'),
  (needle: 'bread', assetName: 'bread'),
  (needle: 'bagel', assetName: 'bagel'),
  (needle: 'croissant', assetName: 'croissant'),
  (needle: 'pretzel', assetName: 'pretzel'),
  (needle: 'waffle', assetName: 'waffle'),
  (needle: 'pancake', assetName: 'pancakes'),
  (needle: 'baguette', assetName: 'baguette'),
  (needle: 'flour tortilla', assetName: 'burrito'),
  (needle: 'tortilla', assetName: 'taco'),
  (needle: 'cracker', assetName: 'rice_cracker'),
  (needle: 'oats', assetName: 'wheat'),
  (needle: 'oat', assetName: 'wheat'),
  (needle: 'flour', assetName: 'wheat'),
  (needle: 'grain', assetName: 'wheat'),
  (needle: 'wheat', assetName: 'wheat'),
  (needle: 'barley', assetName: 'wheat'),
  (needle: 'quinoa', assetName: 'wheat'),
  (needle: 'lentil', assetName: 'pot_food'),
  (needle: 'bean', assetName: 'pot_food'),
  (needle: 'chickpea', assetName: 'pot_food'),
  (needle: 'soup', assetName: 'pot_food'),
  (needle: 'stew', assetName: 'pot_food'),
  (needle: 'broth', assetName: 'pot_food'),
  (needle: 'stock', assetName: 'pot_food'),
  (needle: 'salt', assetName: 'salt'),
  (needle: 'sugar', assetName: 'honey_pot'),
  (needle: 'jam', assetName: 'honey_pot'),
  (needle: 'honey', assetName: 'honey_pot'),
  (needle: 'cookie', assetName: 'cookie'),
  (needle: 'chocolate', assetName: 'chocolate'),
  (needle: 'candy', assetName: 'candy'),
  (needle: 'cupcake', assetName: 'cupcake'),
  (needle: 'peanut', assetName: 'peanuts'),
  (needle: 'nut', assetName: 'peanuts'),
  (needle: 'can', assetName: 'canned_food'),
  (needle: 'canned', assetName: 'canned_food'),

  // Beverages.
  (needle: 'coffee', assetName: 'hot_beverage'),
  (needle: 'tea', assetName: 'tea'),
  (needle: 'boba', assetName: 'cup_with_straw'),
  (needle: 'smoothie', assetName: 'cup_with_straw'),
  (needle: 'soda', assetName: 'cup_with_straw'),
  (needle: 'cola', assetName: 'cup_with_straw'),
  (needle: 'beer', assetName: 'beer'),
  (needle: 'wine', assetName: 'wine'),
  (needle: 'cocktail', assetName: 'cocktail'),
  (needle: 'sake', assetName: 'sake'),
  (needle: 'juice', assetName: 'tropical_drink'),
];

const Map<GroceryCategory, String> _categoryFallbacks = {
  GroceryCategory.produce: 'leafy_greens',
  GroceryCategory.meatFish: 'fish',
  GroceryCategory.dairyEggs: 'milk',
  GroceryCategory.pantryGrains: 'wheat',
  GroceryCategory.bakery: 'bread',
  GroceryCategory.other: 'shopping_bag',
};

String? foodIconAssetForName(String name, {GroceryCategory? category}) {
  final normalized = _normalize(name);
  if (normalized.isNotEmpty) {
    for (final pair in _keywordAssetPairs) {
      if (normalized.contains(pair.needle)) {
        return '$_foodIconBasePath${pair.assetName}.png';
      }
    }
  }
  final fallback = category == null ? null : _categoryFallbacks[category];
  return fallback == null ? null : '$_foodIconBasePath$fallback.png';
}

String _normalize(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final code in lower.codeUnits) {
    final isNumber = code >= 48 && code <= 57;
    final isLetter = code >= 97 && code <= 122;
    buffer.writeCharCode(isNumber || isLetter ? code : 32);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
