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
    final payload = profile.toJson();
    if (profile.householdId == null) {
      payload.remove('household_id');
    }
    await _client.from('profiles').upsert(payload);
  }
}
