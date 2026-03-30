import 'dart:async';

import 'package:collection/collection.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PantryRepository {
  PantryRepository(this._client);

  final SupabaseClient _client;

  Future<List<PantryItem>> fetchItems(String householdId) async {
    if (householdId.isEmpty) return const [];
    final rows = await _client
        .from('pantry_items')
        .select()
        .eq('household_id', householdId)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(PantryItem.fromJson)
        .toList();
  }

  /// Live updates via Realtime; refetches on each change (RLS scopes rows).
  Stream<List<PantryItem>> streamItems(String householdId) {
    if (householdId.isEmpty) {
      return Stream.value(const []);
    }
    return Stream<List<PantryItem>>.multi((multi) {
      RealtimeChannel? channel;
      final topic =
          'public:pantry_items:hh=$householdId:${DateTime.now().microsecondsSinceEpoch}';

      Future<void> pushFresh() async {
        if (multi.isClosed) return;
        final items = await fetchItems(householdId);
        if (!multi.isClosed) {
          multi.add(items);
        }
      }

      var sawSubscribedOnce = false;

      Future<void> setup() async {
        await pushFresh();
        if (multi.isClosed) return;
        channel = _client.channel(topic);
        channel!
            .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pantry_items',
          callback: (_) {
            unawaited(pushFresh());
          },
        )
            .subscribe((RealtimeSubscribeStatus status, Object? error) {
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              if (sawSubscribedOnce) {
                unawaited(pushFresh());
              }
              sawSubscribedOnce = true;
              break;
            case RealtimeSubscribeStatus.timedOut:
            case RealtimeSubscribeStatus.channelError:
              unawaited(pushFresh());
              break;
            case RealtimeSubscribeStatus.closed:
              break;
          }
        });
      }

      unawaited(setup());

      multi.onCancel = () {
        unawaited(channel?.unsubscribe());
      };
    });
  }

  Future<void> insertItem({
    required String householdId,
    required String userId,
    required String name,
    GroceryCategory? category,
    double currentQuantity = 0,
    String unit = 'g',
    double? bufferThreshold,
    int? fdcId,
  }) async {
    await _client.from('pantry_items').insert({
      'household_id': householdId,
      'name': name.trim(),
      'category': (category ?? GroceryCategory.other).dbValue,
      'current_quantity': currentQuantity,
      'unit': unit.trim().isEmpty ? 'g' : unit.trim(),
      if (bufferThreshold != null) 'buffer_threshold': bufferThreshold,
      if (fdcId != null) 'fdc_id': fdcId,
      'created_by': userId,
    });
  }

  Future<void> updateItem({
    required String id,
    double? currentQuantity,
    String? unit,
    double? bufferThreshold,
    String? name,
    GroceryCategory? category,
    DateTime? lastAuditAt,
  }) async {
    final row = <String, dynamic>{};
    if (currentQuantity != null) row['current_quantity'] = currentQuantity;
    if (unit != null) row['unit'] = unit;
    if (bufferThreshold != null) row['buffer_threshold'] = bufferThreshold;
    if (name != null) row['name'] = name;
    if (category != null) row['category'] = category.dbValue;
    if (lastAuditAt != null) {
      row['last_audit_at'] = lastAuditAt.toUtc().toIso8601String();
    }
    if (row.isEmpty) return;
    await _client.from('pantry_items').update(row).eq('id', id);
  }

  Future<void> deleteItem(String id) async {
    await _client.from('pantry_items').delete().eq('id', id);
  }

  Future<void> markAllAuditedNow(String householdId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _client
        .from('pantry_items')
        .update({'last_audit_at': now}).eq('household_id', householdId);
  }

  Future<void> applyPurchaseToPantryIfMatched({
    required String householdId,
    required String itemName,
    required String? quantityStr,
    String? unit,
  }) async {
    final items = await fetchItems(householdId);
    final norm = normalizeGroceryItemName(itemName);
    final match = items.firstWhereOrNull(
      (p) => normalizeGroceryItemName(p.name) == norm,
    );
    if (match == null) return;

    final add = _parseQuantityString(quantityStr ?? '1');
    final pantryUnit = match.unit.trim().toLowerCase();
    final lineUnit = (unit ?? '').trim().toLowerCase();
    if (lineUnit.isNotEmpty && pantryUnit.isNotEmpty && lineUnit != pantryUnit) {
      return;
    }
    await updateItem(
      id: match.id,
      currentQuantity: match.currentQuantity + add,
    );
  }

  double _parseQuantityString(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 1;
    final n = double.tryParse(t.replaceAll(',', '.'));
    return n ?? 1;
  }
}
