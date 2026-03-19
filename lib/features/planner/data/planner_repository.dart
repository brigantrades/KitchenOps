import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlannerRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> _ensureProfileRow(String userId) async {
    await _client.from('profiles').upsert({
      'id': userId,
      'name': 'Leckerly User',
    });
  }

  Future<String?> _householdForUser(String userId) async {
    await _ensureProfileRow(userId);
    final profile = await _client
        .from('profiles')
        .select('household_id')
        .eq('id', userId)
        .maybeSingle();
    final profileHouseholdId = profile?['household_id']?.toString();
    if (profileHouseholdId != null && profileHouseholdId.isNotEmpty) {
      return profileHouseholdId;
    }

    final membership = await _client
        .from('household_members')
        .select('household_id')
        .eq('user_id', userId)
        .eq('status', HouseholdMemberStatus.active.name)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final membershipHouseholdId = membership?['household_id']?.toString();
    if (membershipHouseholdId != null && membershipHouseholdId.isNotEmpty) {
      try {
        await _client
            .from('profiles')
            .update({'household_id': membershipHouseholdId})
            .eq('id', userId)
            .isFilter('household_id', null);
      } catch (_) {
        // Ignore profile sync failures; recovered membership still works.
      }
      return membershipHouseholdId;
    }

    final pendingInvite = await _client
        .from('household_members')
        .select('household_id')
        .eq('user_id', userId)
        .eq('status', HouseholdMemberStatus.invited.name)
        .limit(1)
        .maybeSingle();
    if (pendingInvite != null) {
      return null;
    }

    try {
      final created = await _client.rpc(
        'create_household_with_member',
        params: {'name': 'My Household'},
      );
      final createdHouseholdId = created?.toString();
      if (createdHouseholdId != null && createdHouseholdId.isNotEmpty) {
        return createdHouseholdId;
      }
    } catch (_) {
      // Fall through and return null so callers can handle gracefully.
    }
    return null;
  }

  Future<List<MealPlanSlot>> listSlots(
      String userId, DateTime weekStart) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return [];
    final rows = await _client
        .from('meal_plan_slots')
        .select()
        .eq('household_id', householdId)
        .eq('week_start', weekStart.toIso8601String().split('T').first)
        .order('slot_order');
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(MealPlanSlot.fromJson)
        .toList();
  }

  Stream<List<MealPlanSlot>> streamSlots(
      String userId, DateTime weekStart) async* {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) {
      yield const [];
      return;
    }
    final date = weekStart.toIso8601String().split('T').first;
    final initial = await listSlots(userId, weekStart);
    yield initial;
    yield* _client
        .from('meal_plan_slots')
        .stream(primaryKey: ['id'])
        .order('slot_order')
        .map((rows) => rows
            .whereType<Map<String, dynamic>>()
            .where((row) =>
                row['household_id']?.toString() == householdId &&
                row['week_start']?.toString() == date)
            .map(MealPlanSlot.fromJson)
            .toList());
  }

  Future<void> ensureDefaultSlots(String userId, DateTime weekStart) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return;
    final existing = await listSlots(userId, weekStart);
    final existingKeys = existing
        .map((s) => '${s.dayOfWeek}:${s.mealLabel.toLowerCase()}')
        .toSet();
    const defaults = ['entree', 'side', 'sauce'];

    for (var day = 0; day < 7; day++) {
      final daySlots = existing.where((s) => s.dayOfWeek == day).toList();
      final usedOrders = daySlots.map((s) => s.slotOrder).toSet();
      for (var i = 0; i < defaults.length; i++) {
        final label = defaults[i];
        final key = '$day:$label';
        if (existingKeys.contains(key)) continue;
        var order = i;
        while (usedOrders.contains(order)) {
          order += 1;
        }
        usedOrders.add(order);
        try {
          await _client.from('meal_plan_slots').insert({
            'user_id': userId,
            'household_id': householdId,
            'week_start': weekStart.toIso8601String().split('T').first,
            'day_of_week': day,
            'meal_type': label,
            'slot_order': order,
            'recipe_id': null,
            'servings_used': 1,
          });
        } on PostgrestException catch (error) {
          if (error.code != '23505') rethrow;
        }
      }
    }
  }

  Future<void> assignSlot({
    required String userId,
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealLabel,
    required int slotOrder,
    String? slotId,
    String? recipeId,
    String? mealText,
    String? sauceRecipeId,
    String? sauceText,
    int servings = 1,
  }) async {
    final payload = <String, dynamic>{
      'recipe_id': recipeId,
      'meal_text': mealText?.trim().isEmpty == true ? null : mealText?.trim(),
      'sauce_recipe_id': sauceRecipeId,
      'sauce_text':
          sauceText?.trim().isEmpty == true ? null : sauceText?.trim(),
      'servings_used': servings,
    };
    if (slotId != null) {
      return _client.from('meal_plan_slots').update(payload).eq('id', slotId);
    }
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return;
    return _client.from('meal_plan_slots').insert({
      'user_id': userId,
      'household_id': householdId,
      'week_start': weekStart.toIso8601String().split('T').first,
      'day_of_week': dayOfWeek,
      'meal_type': mealLabel,
      'slot_order': slotOrder,
      ...payload,
    });
  }

  Future<void> unassignSlot({
    required String slotId,
  }) {
    return _client.from('meal_plan_slots').update({
      'recipe_id': null,
      'meal_text': null,
      'sauce_recipe_id': null,
      'sauce_text': null,
      'servings_used': 1,
    }).eq('id', slotId);
  }

  Future<void> addSlot({
    required String userId,
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealLabel,
    required int slotOrder,
  }) {
    return _addSlotWithRetry(
      userId: userId,
      weekStart: weekStart,
      dayOfWeek: dayOfWeek,
      mealLabel: mealLabel,
      slotOrder: slotOrder,
      attempt: 0,
    );
  }

  Future<void> removeSlot({
    required String slotId,
  }) {
    return _client.from('meal_plan_slots').delete().eq('id', slotId);
  }

  Future<int> nextSlotOrder({
    required String userId,
    required DateTime weekStart,
    required int dayOfWeek,
  }) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return 0;
    final rows = await _client
        .from('meal_plan_slots')
        .select('slot_order')
        .eq('household_id', householdId)
        .eq('week_start', weekStart.toIso8601String().split('T').first)
        .eq('day_of_week', dayOfWeek)
        .order('slot_order');
    final orders = (rows as List)
        .whereType<Map<String, dynamic>>()
        .map((e) => (e['slot_order'] as num?)?.toInt() ?? 0)
        .toList();
    if (orders.isEmpty) return 0;
    return (orders.last + 1);
  }

  Future<void> updateSlotOrder(String slotId, int slotOrder) {
    return _client
        .from('meal_plan_slots')
        .update({'slot_order': slotOrder}).eq('id', slotId);
  }

  Future<void> reorderSlots(List<MealPlanSlot> orderedSlots) async {
    // Phase 1: move to temporary range to avoid unique collisions.
    for (var i = 0; i < orderedSlots.length; i++) {
      await _client
          .from('meal_plan_slots')
          .update({'slot_order': 1000 + i}).eq('id', orderedSlots[i].id);
    }
    // Phase 2: set final compact ordering.
    for (var i = 0; i < orderedSlots.length; i++) {
      await _client
          .from('meal_plan_slots')
          .update({'slot_order': i}).eq('id', orderedSlots[i].id);
    }
  }

  Future<void> _addSlotWithRetry({
    required String userId,
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealLabel,
    required int slotOrder,
    required int attempt,
  }) async {
    try {
      final householdId = await _householdForUser(userId);
      if (householdId == null || householdId.isEmpty) return;
      await _client.from('meal_plan_slots').insert({
        'user_id': userId,
        'household_id': householdId,
        'week_start': weekStart.toIso8601String().split('T').first,
        'day_of_week': dayOfWeek,
        'meal_type': mealLabel,
        'slot_order': slotOrder,
        'recipe_id': null,
        'meal_text': null,
        'sauce_recipe_id': null,
        'sauce_text': null,
        'servings_used': 1,
      });
    } on PostgrestException catch (error) {
      if (error.code != '23505' || attempt >= 4) rethrow;
      final next = await nextSlotOrder(
        userId: userId,
        weekStart: weekStart,
        dayOfWeek: dayOfWeek,
      );
      final retryOrder = next + attempt + 1;
      await _addSlotWithRetry(
        userId: userId,
        weekStart: weekStart,
        dayOfWeek: dayOfWeek,
        mealLabel: mealLabel,
        slotOrder: retryOrder,
        attempt: attempt + 1,
      );
    }
  }
}

final plannerRepositoryProvider =
    Provider<PlannerRepository>((ref) => PlannerRepository());

final weekStartProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return now.subtract(Duration(days: now.weekday - 1));
});

final plannerSlotsProvider = StreamProvider<List<MealPlanSlot>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final weekStart = ref.watch(weekStartProvider);
  if (user == null) {
    yield const [];
    return;
  }
  final repo = ref.watch(plannerRepositoryProvider);
  final current = await repo.listSlots(user.id, weekStart);
  if (current.isEmpty) {
    await repo.ensureDefaultSlots(user.id, weekStart);
  }
  yield* repo.streamSlots(user.id, weekStart);
});
