import 'package:plateplan/core/models/app_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<Profile?> fetchProfile(String userId) async {
    final data = await _client.from('profiles').select().eq('id', userId).maybeSingle();
    if (data == null) return null;
    return Profile.fromJson(data);
  }

  Future<void> upsertProfile(Profile profile) async {
    final authUserId = _client.auth.currentUser?.id;
    if (authUserId == null) {
      throw StateError('Sign in required.');
    }
    final payload = profile.toJson();
    // RLS on profiles is scoped to auth.uid() = id; always write as current user.
    payload['id'] = authUserId;
    if (profile.householdId == null) {
      payload.remove('household_id');
    }
    payload.remove('grocery_list_order');
    final updatePayload = Map<String, dynamic>.from(payload)..remove('id');
    final updated = await _client
        .from('profiles')
        .update(updatePayload)
        .eq('id', authUserId)
        .select('id')
        .maybeSingle();
    if (updated != null) return;
    await _client.from('profiles').insert(payload);
  }

  Future<void> updateGroceryListOrder(
    String userId,
    GroceryListOrder order,
  ) async {
    await _client.from('profiles').update({
      'grocery_list_order': order.toJsonColumn(),
    }).eq('id', userId);
  }

  /// Appends [listId] to the saved order for [scope] if missing (e.g. after creating a list).
  Future<void> appendGroceryListId(
    String userId,
    ListScope scope,
    String listId,
  ) async {
    final row = await _client
        .from('profiles')
        .select('grocery_list_order')
        .eq('id', userId)
        .maybeSingle();
    final current = GroceryListOrder.fromJson(row?['grocery_list_order']);
    final ids = List<String>.from(current.idsFor(scope));
    if (!ids.contains(listId)) {
      ids.add(listId);
    }
    await updateGroceryListOrder(userId, current.withIdsFor(scope, ids));
  }

  /// Removes [listId] from the saved order for [scope] (e.g. after deleting a list).
  Future<void> removeGroceryListId(
    String userId,
    ListScope scope,
    String listId,
  ) async {
    final row = await _client
        .from('profiles')
        .select('grocery_list_order')
        .eq('id', userId)
        .maybeSingle();
    final current = GroceryListOrder.fromJson(row?['grocery_list_order']);
    final ids = List<String>.from(current.idsFor(scope))
      ..removeWhere((id) => id == listId);
    await updateGroceryListOrder(userId, current.withIdsFor(scope, ids));
  }
}
