import 'import_discover_lunch_common.dart';

const _fallbackLoveAndLemonsVegetarianLunchUrls = <String>[
  'https://www.loveandlemons.com/quinoa-salad/',
  'https://www.loveandlemons.com/lentil-salad/',
  'https://www.loveandlemons.com/mediterranean-chickpea-salad/',
  'https://www.loveandlemons.com/black-bean-salad/',
  'https://www.loveandlemons.com/couscous-salad/',
  'https://www.loveandlemons.com/farro-salad/',
  'https://www.loveandlemons.com/vegan-pasta-salad/',
];

Future<void> main(List<String> args) {
  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[
        'https://www.eatingwell.com/high-fiber-make-ahead-vegetarian-lunch-recipes-11908137',
        'https://www.loveandlemons.com/healthy-lunch-ideas/',
      ],
      csvPath: 'tmp/lunch_vegetarian_review.csv',
      apiPrefix: 'lunch_vegetarian',
      sourceName: 'eatingwell',
      cuisineTags: <String>['Vegetarian'],
      includeKeywords: <String>[
        'vegetarian',
        'veggie',
        'meatless',
        'lunch',
      ],
      fallbackRecipeUrls: _fallbackLoveAndLemonsVegetarianLunchUrls,
    ),
  );
}
