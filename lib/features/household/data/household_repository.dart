import 'package:plateplan/core/models/app_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:convert';

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
  static const String _debugLogPath =
      '/Users/brigan/Personal Development/KitchenOps/.cursor/debug-e663ae.log';

  // #region agent log
  void _debugLog({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, dynamic> data,
  }) {
    try {
      Directory(_debugLogPath.substring(0, _debugLogPath.lastIndexOf('/')))
          .createSync(recursive: true);
      final payload = <String, dynamic>{
        'sessionId': 'e663ae',
        'runId': runId,
        'hypothesisId': hypothesisId,
        'location': location,
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      File(_debugLogPath).writeAsStringSync(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
      // #region agent log
      void postTo(String url) {
        final client = HttpClient();
        client.postUrl(Uri.parse(url)).then((request) {
          request.headers.set('Content-Type', 'application/json');
          request.headers.set('X-Debug-Session-Id', 'e663ae');
          request.add(utf8.encode(jsonEncode(payload)));
          return request.close();
        }).then((response) {
          response.drain<void>();
          client.close();
        }).catchError((_) {
          client.close(force: true);
        });
      }

      postTo(
          'http://127.0.0.1:7665/ingest/8958ce1e-f127-4a23-8040-af744424700a');
      postTo(
          'http://10.0.2.2:7665/ingest/8958ce1e-f127-4a23-8040-af744424700a');
      postTo(
          'http://localhost:7665/ingest/8958ce1e-f127-4a23-8040-af744424700a');
      // #endregion
    } catch (_) {
      // no-op in production paths
    }
  }
  // #endregion

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

  /// Emits the current household, then re-fetches when this row changes in Realtime.
  Stream<Household?> streamActiveHousehold(String userId) async* {
    final initial = await fetchActiveHousehold(userId);
    yield initial;
    final hid = initial?.id;
    if (hid == null || hid.isEmpty) {
      return;
    }

    yield* _client
        .from('households')
        .stream(primaryKey: ['id'])
        .asyncExpand((rawRows) async* {
          final rows = rawRows.whereType<Map<String, dynamic>>();
          final touched = rows.any((r) => r['id']?.toString() == hid);
          if (touched) {
            yield await fetchActiveHousehold(userId);
          }
        });
  }

  Future<List<HouseholdMember>> listMembers(String householdId) async {
    final rows = await _client
        .from('household_members')
        .select('household_id,user_id,role,status,invited_email,profiles(name)')
        .eq('household_id', householdId)
        .order('created_at');
    final mapped = (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(HouseholdMember.fromJson)
        .toList();
    // #region agent log
    _debugLog(
      runId: 'initial',
      hypothesisId: 'H1_H2_H3_H5',
      location: 'household_repository.dart:listMembers',
      message: 'listMembers payload and parsed names',
      data: {
        'householdId': householdId,
        'rowCount': (rows as List).length,
        'sample': (rows)
            .whereType<Map<String, dynamic>>()
            .take(3)
            .map((r) => {
                  'user_id': r['user_id']?.toString(),
                  'profiles_type': r['profiles']?.runtimeType.toString(),
                  'profiles_value': r['profiles'],
                })
            .toList(),
        'parsedSample': mapped
            .take(3)
            .map((m) => {
                  'userId': m.userId,
                  'name': m.name,
                  'displayName': m.displayName,
                  'status': m.status.name,
                })
            .toList(),
        'unknownCount': mapped.where((m) => m.displayName == 'Unknown user').length,
      },
    );
    // #endregion
    return mapped;
  }

  Stream<List<HouseholdMember>> streamMembers(String householdId) {
    return _client
        .from('household_members')
        .stream(primaryKey: ['household_id', 'user_id'])
        .order('created_at')
        .asyncMap((rawRows) async {
      // #region agent log
      _debugLog(
        runId: 'initial',
        hypothesisId: 'H4',
        location: 'household_repository.dart:streamMembers',
        message: 'streamMembers realtime event',
        data: {
          'householdId': householdId,
          'rawCount': rawRows.length,
          'firstHouseholdId': rawRows.isNotEmpty
              ? rawRows.first['household_id']?.toString()
              : null,
        },
      );
      // #endregion
      return listMembers(householdId);
    });
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

  Future<void> updateHouseholdPlannerWindow({
    required String householdId,
    required int plannerStartDay,
    required int plannerDayCount,
  }) async {
    await _client.from('households').update({
      'planner_start_day': plannerStartDay,
      'planner_day_count': plannerDayCount,
    }).eq('id', householdId);
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
        params: {'invite_email': email},
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
        .select(
          'household_id,invited_email,invited_by_email,role,status,households(name)',
        )
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

  /// Promotes an active member to co-owner (caller must be an owner).
  Future<void> promoteMemberToOwner(String memberUserId) async {
    await _client.rpc(
      'promote_household_member_to_owner',
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
