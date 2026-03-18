import 'package:plateplan/core/models/app_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum HouseholdInviteResult {
  addedExistingMember,
  sentSignupInvite,
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

  Future<String> createHousehold(String name) async {
    final response = await _client.rpc(
      'create_household_with_member',
      params: {'name': name},
    );
    return response.toString();
  }

  Future<HouseholdInviteResult> inviteByEmail(String email) async {
    try {
      await _client.rpc(
        'invite_household_member',
        params: {'email': email},
      );
      return HouseholdInviteResult.addedExistingMember;
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
