import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[
        'https://www.loveandlemons.com/healthy-lunch-ideas/',
      ],
      csvPath: 'tmp/quick_lunch_ideas_review.csv',
      apiPrefix: 'quick_lunch_ideas',
      sourceName: 'love_and_lemons',
      cuisineTags: <String>['Quick & Easy Lunch Ideas'],
      includeKeywords: <String>[
        'lunch',
        'quick',
        'easy',
        'meal prep',
      ],
    ),
  );
}
