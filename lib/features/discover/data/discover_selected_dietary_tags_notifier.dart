import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';

/// Session state for Discover dietary filters. Seeded once from [Profile.dietaryRestrictions]
/// when the profile first loads; then only updated by Discover UI or profile saves.
class DiscoverSelectedDietaryTagsNotifier extends Notifier<Set<String>> {
  var _seeded = false;

  @override
  Set<String> build() {
    // Async path: if the profile loads after this notifier builds, seed once.
    ref.listen<AsyncValue<Profile?>>(profileProvider, (previous, next) {
      next.whenData((profile) {
        if (!_seeded) {
          _seeded = true;
          state = profile?.dietaryRestrictions.toSet() ?? {};
        }
      });
    });

    // Sync path: if the profile is already available, use it as the initial state
    // directly in the return value (setting state during build() gets overwritten).
    final existing = ref.read(profileProvider).valueOrNull;
    if (existing != null && !_seeded) {
      _seeded = true;
      return existing.dietaryRestrictions.toSet();
    }

    return {};
  }

  void setTags(Set<String> tags) => state = Set<String>.from(tags);

  void removeTag(String tag) => state = {...state}..remove(tag);

  void clearAll() => state = {};
}
