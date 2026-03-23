import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_week_mapping.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlannerRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// True when API reports [meal_plan_slots.grocery_draft_lines] is missing (migration not applied).
  static bool _isGroceryDraftColumnMissing(PostgrestException e) {
    return e.code == 'PGRST204' && e.message.contains('grocery_draft_lines');
  }

  static bool _isSideItemsColumnMissing(PostgrestException e) {
    return e.code == 'PGRST204' && e.message.contains('side_items');
  }

  /// True when API reports assignment relation is missing (migration not applied).
  static bool _isSlotMembersTableMissing(PostgrestException e) {
    final message = '${e.message} ${e.details ?? ''}'.toLowerCase();
    return message.contains('meal_plan_slot_members');
  }

  Future<List<String>> _activeMemberIdsForHousehold(String householdId) async {
    final rows = await _client
        .from('household_members')
        .select('user_id')
        .eq('household_id', householdId)
        .eq('status', HouseholdMemberStatus.active.name);
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map((row) => row['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> _sanitizeAssignedUserIds(List<String> ids) {
    return ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _syncSlotMembers(
      String slotId, List<String> assignedUserIds) async {
    final sanitized = _sanitizeAssignedUserIds(assignedUserIds);
    if (sanitized.isEmpty) return;
    try {
      await _client
          .from('meal_plan_slot_members')
          .delete()
          .eq('slot_id', slotId);
      await _client.from('meal_plan_slot_members').upsert([
        for (final userId in sanitized)
          {
            'slot_id': slotId,
            'user_id': userId,
          }
      ]);
    } on PostgrestException catch (e) {
      if (_isSlotMembersTableMissing(e)) return;
      rethrow;
    }
  }

  Future<List<MealPlanSlot>> _hydrateSlotsWithAssignments(
    List<MealPlanSlot> slots,
  ) async {
    if (slots.isEmpty) return slots;
    try {
      final ids = slots.map((s) => s.id).toList();
      final rows = await _client
          .from('meal_plan_slot_members')
          .select('slot_id,user_id')
          .inFilter('slot_id', ids);
      final bySlot = <String, List<String>>{};
      for (final row in (rows as List).whereType<Map<String, dynamic>>()) {
        final slotId = row['slot_id']?.toString();
        final userId = row['user_id']?.toString();
        if (slotId == null ||
            slotId.isEmpty ||
            userId == null ||
            userId.isEmpty) {
          continue;
        }
        (bySlot[slotId] ??= <String>[]).add(userId);
      }
      return slots
          .map((slot) => slot.copyWith(
                assignedUserIds:
                    _sanitizeAssignedUserIds(bySlot[slot.id] ?? const []),
              ))
          .toList();
    } on PostgrestException catch (e) {
      if (_isSlotMembersTableMissing(e)) return slots;
      rethrow;
    }
  }

  Future<void> _ensureProfileRow(String userId) async {
    try {
      await _client.from('profiles').insert({'id': userId});
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
    }
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
    final slots = (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(MealPlanSlot.fromJson)
        .toList();
    return _hydrateSlotsWithAssignments(slots);
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
        .asyncMap((rows) async {
          final slots = rows
              .whereType<Map<String, dynamic>>()
              .where((row) =>
                  row['household_id']?.toString() == householdId &&
                  row['week_start']?.toString() == date)
              .map(MealPlanSlot.fromJson)
              .toList();
          return _hydrateSlotsWithAssignments(slots);
        });
  }

  /// Slots whose calendar dates fall in the planner window starting at [anchorDate].
  Future<List<MealPlanSlot>> listPlannerWindowSlots(
    String userId,
    DateTime anchorDate,
    PlannerWindowPreference pref,
  ) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return [];
    final allowed = calendarDatesForPlannerWindow(anchorDate, pref)
        .map(plannerDateOnly)
        .toSet();
    final buckets = weekStartMondaysForWindow(anchorDate, pref);
    final byId = <String, MealPlanSlot>{};
    final slotLists = await Future.wait(
      buckets.map((mon) => listSlots(userId, mon)),
    );
    for (final slots in slotLists) {
      for (final s in slots) {
        if (allowed.contains(plannerDateOnly(calendarDateForSlot(s)))) {
          byId[s.id] = s;
        }
      }
    }
    return byId.values.toList();
  }

  Stream<List<MealPlanSlot>> streamPlannerWindowSlots(
    String userId,
    DateTime anchorDate,
    PlannerWindowPreference pref,
  ) async* {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) {
      yield const [];
      return;
    }
    final initial = await listPlannerWindowSlots(userId, anchorDate, pref);
    yield initial;
    final allowed = calendarDatesForPlannerWindow(anchorDate, pref)
        .map(plannerDateOnly)
        .toSet();
    final mondays = weekStartMondaysForWindow(anchorDate, pref);
    final mondayStrs = mondays
        .map((m) => m.toIso8601String().split('T').first)
        .toSet();

    yield* _client
        .from('meal_plan_slots')
        .stream(primaryKey: ['id'])
        .order('slot_order')
        .asyncMap((rows) async {
          final slots = rows
              .whereType<Map<String, dynamic>>()
              .where((row) {
                if (row['household_id']?.toString() != householdId) {
                  return false;
                }
                final ws = row['week_start']?.toString();
                return mondayStrs.contains(ws);
              })
              .map(MealPlanSlot.fromJson)
              .where(
                (s) => allowed.contains(plannerDateOnly(calendarDateForSlot(s))),
              )
              .toList();
          return _hydrateSlotsWithAssignments(slots);
        });
  }

  Future<void> ensureDefaultSlots(String userId, DateTime weekStart) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return;
    final defaultMemberIds = await _activeMemberIdsForHousehold(householdId);
    final existing = await listSlots(userId, weekStart);
    const targetSlotsPerDay = 3;

    for (var day = 0; day < 7; day++) {
      final daySlots = existing.where((s) => s.dayOfWeek == day).toList();
      final usedOrders = daySlots.map((s) => s.slotOrder).toSet();
      final needed = targetSlotsPerDay - daySlots.length;
      if (needed <= 0) continue;

      for (var n = 0; n < needed; n++) {
        var order = 0;
        while (usedOrders.contains(order)) {
          order += 1;
        }
        usedOrders.add(order);
        try {
          final inserted = await _client
              .from('meal_plan_slots')
              .insert({
                'user_id': userId,
                'household_id': householdId,
                'week_start': weekStart.toIso8601String().split('T').first,
                'day_of_week': day,
                'meal_type': 'meal',
                'slot_order': order,
                'recipe_id': null,
                'servings_used': 1,
              })
              .select('id')
              .single();
          final slotId = inserted['id']?.toString();
          if (slotId != null && slotId.isNotEmpty) {
            await _syncSlotMembers(slotId, defaultMemberIds);
          }
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
    String? sideRecipeId,
    String? sideText,
    List<PlannerSlotSideItem>? sideItems,
    String? sauceRecipeId,
    String? sauceText,
    int servings = 1,
    List<String>? assignedUserIds,
  }) async {
    final normalizedSideItems = sideItems?.where((e) => !e.isEmpty).toList() ??
        const <PlannerSlotSideItem>[];
    final firstSide =
        normalizedSideItems.isEmpty ? null : normalizedSideItems.first;
    final payload = <String, dynamic>{
      'recipe_id': recipeId,
      'meal_text': mealText?.trim().isEmpty == true ? null : mealText?.trim(),
      'side_recipe_id': firstSide?.recipeId ?? sideRecipeId,
      'side_text': firstSide?.text ?? sideText?.trim(),
      'side_items': PlannerSlotSideItem.toJsonList(normalizedSideItems),
      'sauce_recipe_id': sauceRecipeId,
      'sauce_text':
          sauceText?.trim().isEmpty == true ? null : sauceText?.trim(),
      'servings_used': servings,
      if (recipeId != null) 'grocery_draft_lines': [],
    };
    if (slotId != null) {
      try {
        await _client.from('meal_plan_slots').update(payload).eq('id', slotId);
        if (assignedUserIds != null) {
          await _syncSlotMembers(slotId, assignedUserIds);
        }
      } on PostgrestException catch (e) {
        if (_isGroceryDraftColumnMissing(e)) {
          final without = Map<String, dynamic>.from(payload)
            ..remove('grocery_draft_lines');
          await _client
              .from('meal_plan_slots')
              .update(without)
              .eq('id', slotId);
          if (assignedUserIds != null) {
            await _syncSlotMembers(slotId, assignedUserIds);
          }
          return;
        }
        if (_isSideItemsColumnMissing(e)) {
          final without = Map<String, dynamic>.from(payload)
            ..remove('side_items');
          await _client
              .from('meal_plan_slots')
              .update(without)
              .eq('id', slotId);
          if (assignedUserIds != null) {
            await _syncSlotMembers(slotId, assignedUserIds);
          }
          return;
        }
        rethrow;
      }
      return;
    }
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return;
    final effectiveAssignedUserIds = assignedUserIds == null
        ? await _activeMemberIdsForHousehold(householdId)
        : _sanitizeAssignedUserIds(assignedUserIds);
    if (effectiveAssignedUserIds.isEmpty) {
      effectiveAssignedUserIds.add(userId);
    }
    final insertRow = <String, dynamic>{
      'user_id': userId,
      'household_id': householdId,
      'week_start': weekStart.toIso8601String().split('T').first,
      'day_of_week': dayOfWeek,
      'meal_type': mealLabel,
      'slot_order': slotOrder,
      ...payload,
    };
    try {
      final inserted = await _client
          .from('meal_plan_slots')
          .insert(insertRow)
          .select('id')
          .single();
      final newSlotId = inserted['id']?.toString();
      if (newSlotId != null && newSlotId.isNotEmpty) {
        await _syncSlotMembers(newSlotId, effectiveAssignedUserIds);
      }
    } on PostgrestException catch (e) {
      if (_isGroceryDraftColumnMissing(e)) {
        insertRow.remove('grocery_draft_lines');
        final inserted = await _client
            .from('meal_plan_slots')
            .insert(insertRow)
            .select('id')
            .single();
        final newSlotId = inserted['id']?.toString();
        if (newSlotId != null && newSlotId.isNotEmpty) {
          await _syncSlotMembers(newSlotId, effectiveAssignedUserIds);
        }
        return;
      }
      if (_isSideItemsColumnMissing(e)) {
        insertRow.remove('side_items');
        final inserted = await _client
            .from('meal_plan_slots')
            .insert(insertRow)
            .select('id')
            .single();
        final newSlotId = inserted['id']?.toString();
        if (newSlotId != null && newSlotId.isNotEmpty) {
          await _syncSlotMembers(newSlotId, effectiveAssignedUserIds);
        }
        return;
      }
      rethrow;
    }
  }

  Future<void> unassignSlot({
    required String slotId,
  }) async {
    final withDraft = <String, dynamic>{
      'recipe_id': null,
      'meal_text': null,
      'side_recipe_id': null,
      'side_text': null,
      'side_items': [],
      'sauce_recipe_id': null,
      'sauce_text': null,
      'servings_used': 1,
      'grocery_draft_lines': [],
    };
    try {
      await _client.from('meal_plan_slots').update(withDraft).eq('id', slotId);
    } on PostgrestException catch (e) {
      if (_isGroceryDraftColumnMissing(e)) {
        withDraft.remove('grocery_draft_lines');
        await _client
            .from('meal_plan_slots')
            .update(withDraft)
            .eq('id', slotId);
        return;
      }
      if (_isSideItemsColumnMissing(e)) {
        withDraft.remove('side_items');
        await _client
            .from('meal_plan_slots')
            .update(withDraft)
            .eq('id', slotId);
        return;
      }
      rethrow;
    }
  }

  Future<void> updateSlotGroceryDraft(
    String slotId,
    List<PlannerGroceryDraftLine> lines,
  ) async {
    try {
      await _client.from('meal_plan_slots').update({
        'grocery_draft_lines': lines.map((e) => e.toJson()).toList(),
      }).eq('id', slotId);
    } on PostgrestException catch (e) {
      if (_isGroceryDraftColumnMissing(e)) {
        return;
      }
      rethrow;
    }
  }

  Future<void> updateSlotReminder({
    required String slotId,
    DateTime? reminderAt,
    String? message,
  }) {
    final trimmed = message?.trim();
    return _client.from('meal_plan_slots').update({
      'reminder_at': reminderAt?.toUtc().toIso8601String(),
      'reminder_message': trimmed == null || trimmed.isEmpty ? null : trimmed,
    }).eq('id', slotId);
  }

  Future<void> addSlot({
    required String userId,
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealLabel,
    required int slotOrder,
    List<String>? assignedUserIds,
  }) {
    return _addSlotWithRetry(
      userId: userId,
      weekStart: weekStart,
      dayOfWeek: dayOfWeek,
      mealLabel: mealLabel,
      slotOrder: slotOrder,
      attempt: 0,
      assignedUserIds: assignedUserIds,
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
    if (orderedSlots.isEmpty) return;
    // Phase 1: move to temporary range to avoid unique collisions (parallel).
    await Future.wait([
      for (var i = 0; i < orderedSlots.length; i++)
        _client
            .from('meal_plan_slots')
            .update({'slot_order': 1000 + i}).eq('id', orderedSlots[i].id),
    ]);
    // Phase 2: set final compact ordering (parallel).
    await Future.wait([
      for (var i = 0; i < orderedSlots.length; i++)
        _client
            .from('meal_plan_slots')
            .update({'slot_order': i}).eq('id', orderedSlots[i].id),
    ]);
  }

  Future<void> _addSlotWithRetry({
    required String userId,
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealLabel,
    required int slotOrder,
    required int attempt,
    List<String>? assignedUserIds,
  }) async {
    try {
      final householdId = await _householdForUser(userId);
      if (householdId == null || householdId.isEmpty) return;
      final effectiveAssignedUserIds = assignedUserIds == null
          ? await _activeMemberIdsForHousehold(householdId)
          : _sanitizeAssignedUserIds(assignedUserIds);
      if (effectiveAssignedUserIds.isEmpty) {
        effectiveAssignedUserIds.add(userId);
      }
      final inserted = await _client
          .from('meal_plan_slots')
          .insert({
            'user_id': userId,
            'household_id': householdId,
            'week_start': weekStart.toIso8601String().split('T').first,
            'day_of_week': dayOfWeek,
            'meal_type': mealLabel,
            'slot_order': slotOrder,
            'recipe_id': null,
            'meal_text': null,
            'side_recipe_id': null,
            'side_text': null,
            'side_items': [],
            'sauce_recipe_id': null,
            'sauce_text': null,
            'servings_used': 1,
          })
          .select('id')
          .single();
      final slotId = inserted['id']?.toString();
      if (slotId != null && slotId.isNotEmpty) {
        await _syncSlotMembers(slotId, effectiveAssignedUserIds);
      }
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
        assignedUserIds: assignedUserIds,
      );
    }
  }
}

final plannerRepositoryProvider =
    Provider<PlannerRepository>((ref) => PlannerRepository());

/// Effective window: household settings when in a household, else app default.
final effectivePlannerWindowProvider = Provider<PlannerWindowPreference>((ref) {
  final household = ref.watch(activeHouseholdProvider).valueOrNull;
  return PlannerWindowPreference.resolve(household: household);
});

/// First calendar day of the visible planner window (not always Monday).
final weekStartProvider = StateProvider<DateTime>((ref) {
  return anchorDateForWindowContaining(
    DateTime.now(),
    PlannerWindowPreference.appDefault,
  );
});

/// Selected strip index 0 .. dayCount-1 for the current window.
final selectedPlannerDayProvider = StateProvider<int>((ref) {
  return 0;
});

final plannerSlotsProvider = StreamProvider<List<MealPlanSlot>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final anchor = ref.watch(weekStartProvider);
  final pref = ref.watch(effectivePlannerWindowProvider);
  if (user == null) {
    yield const [];
    return;
  }
  final repo = ref.watch(plannerRepositoryProvider);
  final mondays = weekStartMondaysForWindow(anchor, pref);
  // Do not block the first stream emission on default-slot creation (many round-trips).
  // [streamPlannerWindowSlots] yields list data immediately; defaults fill in via this
  // background work + realtime updates.
  unawaited(
    Future.wait(
      mondays.map((m) => repo.ensureDefaultSlots(user.id, m)),
    ),
  );
  yield* repo.streamPlannerWindowSlots(user.id, anchor, pref);
});
