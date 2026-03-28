import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/core/ui/measurement_system_toggle.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  TextEditingController? _nameCtrl;
  String? _nameCtrlUserId;
  bool _savingName = false;
  @override
  void dispose() {
    _nameCtrl?.dispose();
    super.dispose();
  }

  void _syncNameController(String userId, String name) {
    if (_nameCtrlUserId != userId || _nameCtrl == null) {
      _nameCtrl?.dispose();
      _nameCtrl = TextEditingController(text: name);
      _nameCtrlUserId = userId;
    }
  }

  static const _householdTooltip =
      'A household lets you share your planner, grocery lists, and recipes '
      'with family or roommates.';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in required')),
      );
    }

    final profileRepo = ref.watch(profileRepositoryProvider);
    final profileAsync = ref.watch(profileProvider);
    final pendingInvitesAsync = ref.watch(pendingHouseholdInvitesProvider);
    final householdAsync = ref.watch(activeHouseholdProvider);

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
                  const SnackBar(
                      content: Text('Could not log out. Try again.')),
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
        error: (error, _) =>
            Center(child: Text('Could not load profile: $error')),
        data: (profile) {
          _syncNameController(user.id, profile?.name ?? '');
          final ctrl = _nameCtrl!;

          Future<void> saveName() async {
            final trimmed = ctrl.text.trim();
            if (trimmed.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('First name cannot be empty.')),
              );
              return;
            }
            setState(() => _savingName = true);
            FocusScope.of(context).unfocus();
            try {
              final toSave = profile != null
                  ? profile.copyWith(name: trimmed)
                  : Profile(
                      id: user.id,
                      name: trimmed,
                      goals: const [],
                      dietaryRestrictions: const [],
                      preferredCuisines: const [],
                      dislikedIngredients: const [],
                      householdServings: 2,
                      householdId: null,
                      groceryListOrder: GroceryListOrder.empty,
                    );
              await profileRepo.upsertProfile(toSave);
              ref.invalidate(profileProvider);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('First name updated')),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not save: $e')),
              );
            } finally {
              if (mounted) setState(() => _savingName = false);
            }
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
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
                              margin: const EdgeInsets.only(
                                  bottom: AppSpacing.sm),
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Role: ${invite.role.name}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () async {
                                            try {
                                              await ref
                                                  .read(
                                                      householdRepositoryProvider)
                                                  .rejectInvite(
                                                      invite.householdId);
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
                                                  .read(
                                                      householdRepositoryProvider)
                                                  .acceptInvite(
                                                      invite.householdId);
                                              ref.invalidate(profileProvider);
                                              ref.invalidate(
                                                  activeHouseholdProvider);
                                              ref.invalidate(
                                                  activeHouseholdIdProvider);
                                              ref.invalidate(
                                                  householdMembersProvider);
                                              ref.invalidate(
                                                  pendingHouseholdInvitesProvider);
                                              ref.invalidate(
                                                  plannerSlotsProvider);
                                              invalidateActiveGroceryStreams(
                                                  ref);
                                              ref.invalidate(listsProvider);
                                              ref.invalidate(recipesProvider);
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content:
                                                      Text('Joined household.'),
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
              SectionCard(
                title: 'Account',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email ?? 'Not available',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SectionCard(
                title: 'First Name',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: ctrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Your first name',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton(
                      onPressed: _savingName ? null : saveName,
                      child: _savingName
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Save first name'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SectionCard(
                title: 'Recipe ingredients',
                subtitle:
                    'Units for new ingredients and for viewing amounts. Saved recipes keep their values; display converts. US customary volumes (cup, fl oz).',
                child: const MeasurementSystemToggle(),
              ),
              const SizedBox(height: AppSpacing.sm),
              SectionCard(
                title: 'Household',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.info_outline_rounded),
                        tooltip: _householdTooltip,
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            builder: (ctx) => Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 0, 20, 24),
                              child: Text(
                                _householdTooltip,
                                style: Theme.of(ctx).textTheme.bodyLarge,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    householdAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Text('Could not load household: $e'),
                      data: (household) {
                        if (household != null) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                household.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You can share planner, grocery lists, and recipes with your household.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    context.push('/household'),
                                icon: const Icon(Icons.groups_2_outlined),
                                label: const Text('Manage household'),
                              ),
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Create a household to plan and shop together.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            FilledButton.icon(
                              onPressed: () => context.push('/household'),
                              icon: const Icon(Icons.add_home_outlined),
                              label: const Text('Create a household'),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
