import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';

void main() {
  GroceryItem item(String id) => GroceryItem(
        id: id,
        name: id,
        category: GroceryCategory.other,
      );

  test('merge uses pending order when stream order differs', () {
    final a = item('a');
    final b = item('b');
    final c = item('c');
    final stream = [a, b, c];
    final pending = [c, a, b];
    final r = mergeGroceryDisplayWithPendingReorder(
      streamItems: stream,
      sortMode: GroceryItemsSortMode.asAdded,
      pending: pending,
      pendingListId: 'list-1',
      reorderEditModeActive: false,
    );
    expect(r, isNotNull);
    expect(r!.displayItems.map((e) => e.id).toList(), ['c', 'a', 'b']);
    expect(r.scheduleClearPending, false);
  });

  test(
      'when stream sequence already matches pending, defer clear while reorder UI active',
      () {
    final a = item('a');
    final b = item('b');
    final c = item('c');
    final stream = [c, a, b];
    final pending = [c, a, b];

    final whileEditing = mergeGroceryDisplayWithPendingReorder(
      streamItems: stream,
      sortMode: GroceryItemsSortMode.asAdded,
      pending: pending,
      pendingListId: 'list-1',
      reorderEditModeActive: true,
    );
    expect(whileEditing!.scheduleClearPending, false);

    final afterEdit = mergeGroceryDisplayWithPendingReorder(
      streamItems: stream,
      sortMode: GroceryItemsSortMode.asAdded,
      pending: pending,
      pendingListId: 'list-1',
      reorderEditModeActive: false,
    );
    expect(afterEdit!.scheduleClearPending, true);
  });

  test('returns null when sort mode is not asAdded', () {
    final r = mergeGroceryDisplayWithPendingReorder(
      streamItems: [item('a')],
      sortMode: GroceryItemsSortMode.alphabetical,
      pending: [item('a')],
      pendingListId: 'L',
      reorderEditModeActive: false,
    );
    expect(r, isNull);
  });
}
