import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/profile/presentation/profile_form.dart';

class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in required')),
      );
    }

    final profileRepo = ref.watch(profileRepositoryProvider);
    final profileAsync = ref.watch(profileProvider);
    final pendingInvitesAsync = ref.watch(pendingHouseholdInvitesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: () async {
              try {
                await ref.read(authRepositoryProvider).signOut();
                if (!context.mounted) return;
                context.go('/auth');
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not log out. Try again.')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.groups_2_outlined),
            tooltip: 'Household',
            onPressed: () => context.push('/household'),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => context.go('/'),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load profile: $error')),
        data: (profile) => ProfileForm(
          topSections: [
            pendingInvitesAsync.when(
              loading: () => const SectionCard(
                title: 'Household Invites',
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => SectionCard(
                title: 'Household Invites',
                child: Text('Could not load invites: $error'),
              ),
              data: (invites) {
                if (invites.isEmpty) {
                  return const SizedBox.shrink();
                }
                return SectionCard(
                  title: invites.length == 1
                      ? 'Household Invite'
                      : 'Household Invites',
                  subtitle: 'Accept or reject without leaving the app.',
                  child: Column(
                    children: invites
                        .map(
                          (invite) => Container(
                            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  invite.householdName,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Role: ${invite.role.name}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () async {
                                          try {
                                            await ref
                                                .read(householdRepositoryProvider)
                                                .rejectInvite(invite.householdId);
                                            ref.invalidate(
                                                pendingHouseholdInvitesProvider);
                                            ref.invalidate(
                                                householdMembersProvider);
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Invite declined.'),
                                              ),
                                            );
                                          } catch (error) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Could not decline invite: $error',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () async {
                                          try {
                                            await ref
                                                .read(householdRepositoryProvider)
                                                .acceptInvite(invite.householdId);
                                            ref.invalidate(profileProvider);
                                            ref.invalidate(
                                                activeHouseholdProvider);
                                            ref.invalidate(
                                                activeHouseholdIdProvider);
                                            ref.invalidate(
                                                householdMembersProvider);
                                            ref.invalidate(
                                                pendingHouseholdInvitesProvider);
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Joined household.'),
                                              ),
                                            );
                                          } catch (error) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Could not accept invite: $error',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: const Text('Accept'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ],
          initialName: profile?.name ?? '',
          initialPrimaryGoal: profile?.goals.firstOrNull ?? 'more_veg',
          initialDietaryRestrictions: profile?.dietaryRestrictions ?? const [],
          initialPreferredCuisines: profile?.preferredCuisines ?? const [],
          initialDislikedIngredients: profile?.dislikedIngredients ?? const [],
          initialHouseholdServings: profile?.householdServings ?? 2,
          submitLabel: 'Save changes',
          onSubmit: (form) async {
            await profileRepo.upsertProfile(
              Profile(
                id: user.id,
                name: form.name,
                goals: [form.primaryGoal],
                dietaryRestrictions: form.dietaryRestrictions,
                preferredCuisines: form.preferredCuisines,
                dislikedIngredients: form.dislikedIngredients,
                householdServings: form.householdServings,
                householdId: profile?.householdId,
              ),
            );
            ref.invalidate(profileProvider);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile updated')),
            );
            context.go('/');
          },
        ),
      ),
    );
  }
}
