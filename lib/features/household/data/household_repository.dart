import 'package:plateplan/core/models/app_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum HouseholdInviteResult {
  invitedExistingMember,
  sentSignupInvite,
}

class HouseholdSharingStatus {
  const HouseholdSharingStatus({
    required this.plannerShared,
    required this.groceryShared,
  });

  final bool plannerShared;
  final bool groceryShared;
}

class HouseholdRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<Household?> fetchActiveHousehold(String userId) async {
    final profile = await _client
        .from('profiles')
        .select('household_id')
        .eq('id', userId)
        .maybeSingle();
    final householdId = profile?['household_id']?.toString();
    if (householdId == null || householdId.isEmpty) return null;
    final household = await _client
        .from('households')
        .select()
        .eq('id', householdId)
        .maybeSingle();
    if (household == null) return null;
    return Household.fromJson(household);
  }

  Future<List<HouseholdMember>> listMembers(String householdId) async {
    final rows = await _client
        .from('household_members')
        .select('household_id,user_id,role,status,invited_email,profiles(name)')
        .eq('household_id', householdId)
        .order('created_at');
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(HouseholdMember.fromJson)
        .toList();
  }

  Stream<List<HouseholdMember>> streamMembers(String householdId) {
    return _client
        .from('household_members')
        .stream(primaryKey: ['household_id', 'user_id'])
        .order('created_at')
        .map((rows) => rows
            .whereType<Map<String, dynamic>>()
            .where((row) => row['household_id']?.toString() == householdId)
            .map(HouseholdMember.fromJson)
            .toList());
  }

  Future<String> createHousehold(String name) async {
    final response = await _client.rpc(
      'create_household_with_member',
      params: {'name': name},
    );
    return response.toString();
  }

  Future<int> shareAllPersonalRecipes() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Not authenticated.');
    }
    final profile = await _client
        .from('profiles')
        .select('household_id')
        .eq('id', user.id)
        .maybeSingle();
    final householdId = profile?['household_id']?.toString();
    if (householdId == null || householdId.isEmpty) {
      throw StateError('No active household.');
    }
    final rows = await _client
        .from('recipes')
        .update({
          'visibility': RecipeVisibility.household.name,
          'household_id': householdId,
        })
        .eq('user_id', user.id)
        .eq('visibility', RecipeVisibility.personal.name)
        .select('id');
    return (rows as List).length;
  }

  Future<void> updateActiveHouseholdName(String name) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Not authenticated.');
    }
    final nextName = name.trim();
    if (nextName.isEmpty) {
      throw StateError('Household name is required.');
    }
    final profile = await _client
        .from('profiles')
        .select('household_id')
        .eq('id', user.id)
        .maybeSingle();
    final householdId = profile?['household_id']?.toString();
    if (householdId == null || householdId.isEmpty) {
      throw StateError('No active household.');
    }
    await _client
        .from('households')
        .update({'name': nextName}).eq('id', householdId);
  }

  Future<HouseholdSharingStatus> fetchSharingStatus() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const HouseholdSharingStatus(
        plannerShared: false,
        groceryShared: false,
      );
    }

    final profile = await _client
        .from('profiles')
        .select('household_id')
        .eq('id', user.id)
        .maybeSingle();
    final householdId = profile?['household_id']?.toString();
    if (householdId == null || householdId.isEmpty) {
      return const HouseholdSharingStatus(
        plannerShared: false,
        groceryShared: false,
      );
    }

    final plannerOutsideRows = await _client
        .from('meal_plan_slots')
        .select('id')
        .eq('user_id', user.id)
        .neq('household_id', householdId)
        .limit(1);
    final plannerShared = (plannerOutsideRows as List).isEmpty;

    final groceryOutsideRows = await _client
        .from('grocery_items')
        .select('id')
        .eq('user_id', user.id)
        .neq('household_id', householdId)
        .limit(1);
    final hasHouseholdGroceryList = await _client
        .from('lists')
        .select('id')
        .eq('owner_user_id', user.id)
        .eq('kind', 'grocery')
        .eq('scope', ListScope.household.name)
        .eq('household_id', householdId)
        .limit(1);
    final groceryShared = (groceryOutsideRows as List).isEmpty ||
        (hasHouseholdGroceryList as List).isNotEmpty;

    return HouseholdSharingStatus(
      plannerShared: plannerShared,
      groceryShared: groceryShared,
    );
  }

  Future<HouseholdInviteResult> inviteByEmail(String email) async {
    try {
      await _client.rpc(
        'invite_household_member',
        params: {'email': email},
      );
      return HouseholdInviteResult.invitedExistingMember;
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('no account found for that email')) {
        await _client.auth.signInWithOtp(
          email: email,
          shouldCreateUser: true,
        );
        return HouseholdInviteResult.sentSignupInvite;
      }
      rethrow;
    }
  }

  Future<List<HouseholdInvite>> listPendingInvites() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('household_members')
        .select('household_id,invited_email,role,status,households(name)')
        .eq('user_id', user.id)
        .eq('status', HouseholdMemberStatus.invited.name)
        .order('created_at', ascending: false);
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(HouseholdInvite.fromJson)
        .toList();
  }

  Stream<List<HouseholdInvite>> streamPendingInvites() {
    final user = _client.auth.currentUser;
    if (user == null) return Stream.value(const []);
    return _client
        .from('household_members')
        .stream(primaryKey: ['household_id', 'user_id'])
        .order('created_at', ascending: false)
        .map((rows) => rows
            .whereType<Map<String, dynamic>>()
            .where((row) =>
                row['user_id']?.toString() == user.id &&
                row['status']?.toString() == HouseholdMemberStatus.invited.name)
            .map(HouseholdInvite.fromJson)
            .toList());
  }

  Future<void> acceptInvite(String householdId) async {
    try {
      await _client.rpc(
        'accept_household_invite',
        params: {'household_uuid': householdId},
      );
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (!message.contains('already in another household')) {
        rethrow;
      }
      await _client.rpc(
        'accept_household_invite_with_switch',
        params: {'household_uuid': householdId},
      );
    }
  }

  Future<void> rejectInvite(String householdId) async {
    await _client.rpc(
      'reject_household_invite',
      params: {'household_uuid': householdId},
    );
  }

  Future<void> removeMember(String memberUserId) async {
    await _client.rpc(
      'remove_household_member',
      params: {'member_user_id': memberUserId},
    );
  }

  Future<void> leaveHousehold() async {
    await _client.rpc('leave_household');
  }

  Future<int> migratePlannerToHousehold() async {
    final response = await _client.rpc(
      'migrate_planner_to_household',
      params: {'confirm': true},
    );
    return (response as num?)?.toInt() ?? 0;
  }

  Future<int> migrateGroceryToHousehold() async {
    final response = await _client.rpc(
      'migrate_grocery_to_household',
      params: {'confirm': true},
    );
    return (response as num?)?.toInt() ?? 0;
  }

  Future<int> shareSelectedRecipes(List<String> recipeIds) async {
    if (recipeIds.isEmpty) return 0;
    final response = await _client.rpc(
      'share_selected_recipes',
      params: {'recipe_ids': recipeIds},
    );
    return (response as num?)?.toInt() ?? 0;
  }
}
