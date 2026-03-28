// Curated dinner discover import (~12 buckets × per-category recipes).
//
// Prerequisites: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SEED_USER_ID
//
// 1) Dry run (parses recipes, writes tmp/dinner_curated_review.csv, no DB writes):
//    dart run bin/import_discover_dinner_curated.dart
// 2) Import:
//    dart run bin/import_discover_dinner_curated.dart --execute
//
// Options:
//   --per-category=25  (default 25) recipes per bucket
//   --limit=25         alias for --per-category
//   --execute          upsert into Supabase
//
// "Quick & Easy Dinners" on Discover uses a fixed api_id list in discover_repository.dart;
// imported recipes appear in the main catalog and cuisine tiles, not necessarily that strip.

import 'dart:io';

import 'package:http/http.dart' as http;

import 'import_discover_dinner_common.dart';

Future<void> main(List<String> args) async {
  final supabaseUrl = envOrNull('SUPABASE_URL');
  final serviceRole = envOrNull('SUPABASE_SERVICE_ROLE_KEY');
  final seedUserId = envOrNull('SEED_USER_ID');
  final execute = args.contains('--execute');
  final perCategory = parsePerCategoryArg(args) ?? 25;

  if (supabaseUrl == null || serviceRole == null || seedUserId == null) {
    stderr.writeln(
      'Missing env vars. Required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SEED_USER_ID',
    );
    exitCode = 64;
    return;
  }

  final client = http.Client();
  final allRows = <ReviewRow>[];
  var totalSuccess = 0;
  var totalFailed = 0;

  try {
    for (final config in _dinnerBuckets) {
      stdout.writeln('\n=== ${config.apiPrefix} (${config.sourceName}) ===');
      try {
        final result = await runDinnerBucketImport(
          client,
          args: args,
          config: config,
          limit: perCategory,
          supabaseUrl: supabaseUrl,
          serviceRole: serviceRole,
          seedUserId: seedUserId,
        );
        allRows.addAll(result.rows);
        totalSuccess += result.successCount;
        totalFailed += result.failedCount;
      } catch (error, stack) {
        stderr.writeln('Bucket failed: $error');
        stderr.writeln('$stack');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    final path = await writeDinnerReviewCsv(
      'tmp/dinner_curated_review.csv',
      allRows,
    );
    stdout.writeln('\nReview CSV: $path');
    if (!execute) {
      stdout.writeln(
        'Dry run complete. Re-run with --execute to import recipes.',
      );
    }
    stdout.writeln(
      'Totals — success: $totalSuccess, failed: $totalFailed, rows logged: ${allRows.length}',
    );
  } finally {
    client.close();
  }
}

const List<DinnerImportConfig> _dinnerBuckets = <DinnerImportConfig>[
  DinnerImportConfig(
    sourcePages: <String>[
      'https://downshiftology.com/ingredient/chicken/',
    ],
    apiPrefix: 'dinner_chicken_ds',
    sourceName: 'downshiftology',
    cuisineTags: <String>['Chicken', 'Dinner'],
    includeKeywords: <String>['chicken', 'poultry'],
    discoveryKind: DinnerUrlDiscoveryKind.downshiftology,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://downshiftology.com/ingredient/beef/',
    ],
    apiPrefix: 'dinner_beef_ds',
    sourceName: 'downshiftology',
    cuisineTags: <String>['Beef', 'Dinner'],
    includeKeywords: <String>['beef', 'steak', 'brisket'],
    discoveryKind: DinnerUrlDiscoveryKind.downshiftology,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://www.177milkstreet.com/stories/01-2025-27-best-pasta-recipes-any-night',
    ],
    apiPrefix: 'dinner_pasta_milkstreet',
    sourceName: '177_milk_street',
    cuisineTags: <String>['Pasta', 'Dinner', 'Italian'],
    includeKeywords: <String>[
      'pasta',
      'noodle',
      'spaghetti',
      'linguine',
      'fettuccine',
      'penne',
      'rigatoni',
      'orzo',
      'ravioli',
      'lasagna',
      'carbonara',
      'pesto',
    ],
    discoveryKind: DinnerUrlDiscoveryKind.generic,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://downshiftology.com/ingredient/pork/',
    ],
    apiPrefix: 'dinner_pork_ds',
    sourceName: 'downshiftology',
    cuisineTags: <String>['Pork', 'Dinner'],
    includeKeywords: <String>['pork', 'bacon', 'ham', 'sausage'],
    discoveryKind: DinnerUrlDiscoveryKind.downshiftology,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://downshiftology.com/diet/vegetarian-recipes/',
    ],
    apiPrefix: 'dinner_vegetarian_ds',
    sourceName: 'downshiftology',
    cuisineTags: <String>['Vegetarian', 'Dinner', 'Plant-Based'],
    includeKeywords: <String>[
      'vegetarian',
      'veggie',
      'vegetable',
      'plant',
      'tofu',
      'mushroom',
      'salad',
    ],
    discoveryKind: DinnerUrlDiscoveryKind.downshiftology,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://downshiftology.com/ingredient/salmon/',
      'https://downshiftology.com/ingredient/shrimp/',
    ],
    apiPrefix: 'dinner_seafood_ds',
    sourceName: 'downshiftology',
    cuisineTags: <String>['Seafood', 'Dinner'],
    includeKeywords: <String>[
      'salmon',
      'shrimp',
      'seafood',
      'fish',
      'scallop',
      'cod',
      'tuna',
    ],
    discoveryKind: DinnerUrlDiscoveryKind.downshiftology,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://www.halfbakedharvest.com/one-pan-dinners-everyone-is-making/',
    ],
    apiPrefix: 'dinner_one_pan_hbh',
    sourceName: 'half_baked_harvest',
    cuisineTags: <String>['One-Pan', 'Sheet Pan', 'Dinner'],
    includeKeywords: <String>[
      'one',
      'pan',
      'sheet',
      'skillet',
      'tray',
      'bake',
      'dinner',
      'chicken',
      'pasta',
      'rice',
    ],
    discoveryKind: DinnerUrlDiscoveryKind.generic,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://www.delish.com/cooking/g1823/southern-inspired-recipes/',
    ],
    apiPrefix: 'dinner_southern_delish',
    sourceName: 'delish',
    cuisineTags: <String>['Southern', 'Comfort', 'Dinner'],
    includeKeywords: <String>[
      'southern',
      'comfort',
      'grits',
      'biscuit',
      'fried',
      'cajun',
      'bbq',
      'casserole',
    ],
    discoveryKind: DinnerUrlDiscoveryKind.generic,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://www.halfbakedharvest.com/comforting-crockpot-recipes/',
    ],
    apiPrefix: 'dinner_crockpot_hbh',
    sourceName: 'half_baked_harvest',
    cuisineTags: <String>['Crockpot', 'Slow Cooker', 'Dinner'],
    includeKeywords: <String>[
      'slow',
      'cooker',
      'crock',
      'pot',
      'simmer',
      'stew',
      'chili',
      'soup',
    ],
    discoveryKind: DinnerUrlDiscoveryKind.generic,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://food52.com/story/23189-best-instant-pot-recipes',
    ],
    apiPrefix: 'dinner_instant_pot_f52',
    sourceName: 'food52',
    cuisineTags: <String>['Instant Pot', 'Dinner'],
    includeKeywords: <String>[
      'instant',
      'pot',
      'pressure',
      'cooker',
      'rice',
      'bean',
      'stew',
      'curry',
    ],
    discoveryKind: DinnerUrlDiscoveryKind.generic,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://downshiftology.com/easy-grilling-recipes/',
    ],
    apiPrefix: 'dinner_grill_ds',
    sourceName: 'downshiftology',
    cuisineTags: <String>['Grill', 'Dinner'],
    includeKeywords: <String>[
      'grill',
      'grilled',
      'bbq',
      'skewer',
      'kebab',
      'steak',
      'chicken',
      'salmon',
      'burger',
    ],
    discoveryKind: DinnerUrlDiscoveryKind.downshiftology,
  ),
  DinnerImportConfig(
    sourcePages: <String>[
      'https://www.loveandlemons.com/soup-recipes/',
    ],
    apiPrefix: 'dinner_soup_lal',
    sourceName: 'love_and_lemons',
    cuisineTags: <String>['Soup', 'Dinner'],
    includeKeywords: <String>[
      'soup',
      'stew',
      'chili',
      'bisque',
      'broth',
      'chowder',
      'minestrone',
      'lentil',
    ],
    discoveryKind: DinnerUrlDiscoveryKind.loveAndLemons,
  ),
];
