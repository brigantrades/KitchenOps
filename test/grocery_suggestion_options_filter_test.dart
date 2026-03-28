import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/features/grocery/presentation/grocery_item_suggestions_grid.dart';

void main() {
  group('filterGrocerySuggestionOptionsForDisplay', () {
    test('keeps create row when label equals typed query', () {
      final out = filterGrocerySuggestionOptionsForDisplay(
        suggestionOptions: [
          (label: 'newitem', isCreate: true),
          (label: 'apple', isCreate: false),
        ],
        normalizedTypedQuery: 'newitem',
      );
      expect(out.length, 2);
      expect(out.any((o) => o.isCreate && o.label == 'newitem'), isTrue);
    });

    test('keeps catalog row that exactly matches typed query when no create row',
        () {
      final out = filterGrocerySuggestionOptionsForDisplay(
        suggestionOptions: [
          (label: 'chicken', isCreate: false),
          (label: 'chicken breast', isCreate: false),
        ],
        normalizedTypedQuery: 'chicken',
      );
      expect(out.length, 2);
      expect(out.map((o) => o.label).toList(), ['chicken', 'chicken breast']);
    });

    test('keeps lone catalog chip that exactly matches query (no create row)', () {
      final out = filterGrocerySuggestionOptionsForDisplay(
        suggestionOptions: [
          (label: 'milk', isCreate: false),
        ],
        normalizedTypedQuery: 'milk',
      );
      expect(out.single.label, 'milk');
    });

    test('drops catalog when create row covers same normalized query', () {
      final out = filterGrocerySuggestionOptionsForDisplay(
        suggestionOptions: [
          (label: 'Milk', isCreate: false),
          (label: 'milk', isCreate: true),
        ],
        normalizedTypedQuery: 'milk',
      );
      expect(out.length, 1);
      expect(out.single.isCreate, isTrue);
    });
  });
}
