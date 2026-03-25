import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/household/data/household_repository.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';

final householdRepositoryProvider =
    Provider<HouseholdRepository>((ref) => HouseholdRepository());

final activeHouseholdProvider = StreamProvider<Household?>((ref) async* {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    yield null;
    return;
  }
  final repo = ref.watch(householdRepositoryProvider);
  yield* repo.streamActiveHousehold(user.id);
});

final activeHouseholdIdProvider = Provider<String?>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  final byProfile = profile?.householdId;
  if (byProfile != null && byProfile.isNotEmpty) return byProfile;
  return ref.watch(activeHouseholdProvider).valueOrNull?.id;
});

final householdMembersProvider =
    StreamProvider<List<HouseholdMember>>((ref) async* {
  final householdId = ref.watch(activeHouseholdIdProvider);
  if (householdId == null || householdId.isEmpty) {
    yield const [];
    return;
  }
  final repo = ref.watch(householdRepositoryProvider);
  final initial = await repo.listMembers(householdId);
  yield initial;
  yield* repo.streamMembers(householdId);
});

final pendingHouseholdInvitesProvider =
    StreamProvider<List<HouseholdInvite>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    yield const [];
    return;
  }
  final repo = ref.watch(householdRepositoryProvider);
  final initial = await repo.listPendingInvites();
  yield initial;
  yield* repo.streamPendingInvites();
});

final hasSharedHouseholdProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final members = await ref.watch(householdMembersProvider.future);
  return members.any(
    (member) =>
        member.userId != user.id &&
        member.status == HouseholdMemberStatus.active,
  );
});
