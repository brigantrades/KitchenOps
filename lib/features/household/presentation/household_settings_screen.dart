import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_week_mapping.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/household/data/household_repository.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';

const _householdRecipeSharingPrivacyNote =
    'Recipes shared with your household are only visible to members of '
    'this household. They are not published and are not shown to people '
    'outside your household.';

class _HouseholdRecipePrivacyCallout extends StatelessWidget {
  const _HouseholdRecipePrivacyCallout();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lock_person_outlined,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            _householdRecipeSharingPrivacyNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}

class HouseholdSettingsScreen extends ConsumerStatefulWidget {
  const HouseholdSettingsScreen({super.key});

  @override
  ConsumerState<HouseholdSettingsScreen> createState() =>
      _HouseholdSettingsScreenState();
}

class _HouseholdSettingsScreenState
    extends ConsumerState<HouseholdSettingsScreen> {
  final _householdNameCtrl = TextEditingController();
  final _inviteEmailCtrl = TextEditingController();
  bool _sharePlannerOnCreate = false;
  bool _shareGroceryOnCreate = false;
  _RecipeShareMode _createRecipeShareMode = _RecipeShareMode.none;
  final Set<String> _createSelectedRecipeIds = {};
  List<Recipe> _createPersonalRecipes = const [];
  String? _loadedCreateRecipesForUserId;
  bool _loadingCreateRecipes = false;
  bool? _lastAppliedSharePlanner;
  bool? _lastAppliedShareGrocery;
  bool _working = false;

  /// Emails where we sent a sign-up OTP but there is no `household_members` row yet.
  final List<String> _pendingSignupEmails = [];

  String _normalizeEmail(String value) => value.trim().toLowerCase();

  @override
  void dispose() {
    _householdNameCtrl.dispose();
    _inviteEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _createHousehold() async {
    final name = _householdNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _working = true);
    try {
      final repo = ref.read(householdRepositoryProvider);
      await repo.createHousehold(name);
      final sharingFailures = <String>[];

      if (_sharePlannerOnCreate) {
        try {
          await repo.migratePlannerToHousehold();
        } catch (_) {
          sharingFailures.add('planner');
        }
      }
      if (_shareGroceryOnCreate) {
        try {
          await repo.migrateGroceryToHousehold();
        } catch (_) {
          sharingFailures.add('grocery');
        }
      }
      if (_createRecipeShareMode == _RecipeShareMode.all) {
        try {
          await repo.shareAllPersonalRecipes();
        } catch (_) {
          sharingFailures.add('recipes');
        }
      } else if (_createRecipeShareMode == _RecipeShareMode.select &&
          _createSelectedRecipeIds.isNotEmpty) {
        try {
          await repo.shareSelectedRecipes(_createSelectedRecipeIds.toList());
        } catch (_) {
          sharingFailures.add('recipes');
        }
      }

      ref.invalidate(activeHouseholdProvider);
      ref.invalidate(activeHouseholdIdProvider);
      ref.invalidate(householdMembersProvider);
      ref.invalidate(recipesProvider);
      _lastAppliedSharePlanner = _sharePlannerOnCreate;
      _lastAppliedShareGrocery = _shareGroceryOnCreate;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sharingFailures.isEmpty
                ? 'Household created.'
                : 'Household created. Some sharing updates failed (${sharingFailures.join(', ')}). You can edit household sharing later.',
          ),
        ),
      );
      _householdNameCtrl.clear();
      _createSelectedRecipeIds.clear();
      _createRecipeShareMode = _RecipeShareMode.none;
      _sharePlannerOnCreate = false;
      _shareGroceryOnCreate = false;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create household: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _inviteMember() async {
    final email = _inviteEmailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _working = true);
    try {
      final result =
          await ref.read(householdRepositoryProvider).inviteByEmail(email);
      final norm = _normalizeEmail(email);
      if (result == HouseholdInviteResult.invitedExistingMember) {
        ref.invalidate(householdMembersProvider);
        setState(() {
          _pendingSignupEmails.removeWhere((e) => _normalizeEmail(e) == norm);
        });
      } else if (result == HouseholdInviteResult.sentSignupInvite) {
        setState(() {
          if (!_pendingSignupEmails.any((e) => _normalizeEmail(e) == norm)) {
            _pendingSignupEmails.add(email.trim());
          }
        });
      }
      _inviteEmailCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == HouseholdInviteResult.invitedExistingMember
                ? 'Invite sent. They can accept in their app profile.'
                : 'No account found yet. Sign-up invite email sent.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add member: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openMigrationWizard() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final repo = ref.read(householdRepositoryProvider);
    final personalRecipes =
        await ref.read(recipesRepositoryProvider).listPersonalForUser(user.id);
    final sharingStatus = await repo.fetchSharingStatus();
    if (!mounted) return;
    final result = await showModalBottomSheet<_AppliedSharingState>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HouseholdMigrationWizard(
        personalRecipes: personalRecipes,
        initialSharePlanner:
            _lastAppliedSharePlanner ?? sharingStatus.plannerShared,
        initialShareGrocery:
            _lastAppliedShareGrocery ?? sharingStatus.groceryShared,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _lastAppliedSharePlanner = result.sharePlanner;
        _lastAppliedShareGrocery = result.shareGrocery;
      });
    }
  }

  Future<void> _editHouseholdName(String currentName) async {
    var draftName = currentName;
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit household name'),
        content: TextFormField(
          initialValue: currentName,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (value) => draftName = value,
          onFieldSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          decoration: const InputDecoration(
            labelText: 'Household name',
            hintText: 'e.g. The Smith Home',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(draftName.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (nextName == null || nextName.trim().isEmpty) return;

    // Let dialog teardown finish before mutating parent widget state.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    setState(() => _working = true);
    try {
      await ref
          .read(householdRepositoryProvider)
          .updateActiveHouseholdName(nextName);
      ref.invalidate(activeHouseholdProvider);
      ref.invalidate(activeHouseholdIdProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Household name updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update household name: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editHouseholdPlannerWindow(Household household) async {
    var startDay = household.plannerStartDay;
    var dayCount = household.plannerDayCount;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
                left: 16,
                right: 16,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Household planner default',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Everyone in this household shares this planner window.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: startDay.clamp(0, 6),
                    decoration: const InputDecoration(
                      labelText: 'Start day',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Monday')),
                      DropdownMenuItem(value: 1, child: Text('Tuesday')),
                      DropdownMenuItem(value: 2, child: Text('Wednesday')),
                      DropdownMenuItem(value: 3, child: Text('Thursday')),
                      DropdownMenuItem(value: 4, child: Text('Friday')),
                      DropdownMenuItem(value: 5, child: Text('Saturday')),
                      DropdownMenuItem(value: 6, child: Text('Sunday')),
                    ],
                    onChanged: (v) {
                      if (v != null) setModal(() => startDay = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: dayCount.clamp(1, 14),
                    decoration: const InputDecoration(
                      labelText: 'Number of days',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var n = 1; n <= 14; n++)
                        DropdownMenuItem(
                          value: n,
                          child: Text('$n day${n == 1 ? '' : 's'}'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setModal(() => dayCount = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (ctx) {
                      final range = plannerWindowRangeLabel(
                        startDay.clamp(0, 6),
                        dayCount.clamp(1, 14),
                      );
                      if (range.isEmpty) return const SizedBox.shrink();
                      return Text(
                        'Shown as: $range',
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      setState(() => _working = true);
                      try {
                        await ref
                            .read(householdRepositoryProvider)
                            .updateHouseholdPlannerWindow(
                              householdId: household.id,
                              plannerStartDay: startDay,
                              plannerDayCount: dayCount,
                            );
                        ref.invalidate(activeHouseholdProvider);
                        ref.invalidate(profileProvider);
                        ref.invalidate(plannerSlotsProvider);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Household planner default saved.'),
                          ),
                        );
                      } catch (error) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Could not save: $error'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _working = false);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _loadCreatePersonalRecipesIfNeeded(String? userId) {
    if (userId == null ||
        userId.isEmpty ||
        _loadingCreateRecipes ||
        _loadedCreateRecipesForUserId == userId) {
      return;
    }
    _loadingCreateRecipes = true;
    ref
        .read(recipesRepositoryProvider)
        .listPersonalForUser(userId)
        .then((recipes) {
      if (!mounted) return;
      setState(() {
        _createPersonalRecipes = recipes;
        _loadedCreateRecipesForUserId = userId;
        _loadingCreateRecipes = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _loadingCreateRecipes = false);
    });
  }

  Future<void> _removeMember(HouseholdMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          'Remove ${member.displayName} from this household?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      await ref.read(householdRepositoryProvider).removeMember(member.userId);
      ref.invalidate(householdMembersProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove member: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _promoteMemberToOwner(HouseholdMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make owner?'),
        content: Text(
          '${member.displayName} will be able to edit household settings, '
          'the planner window, and manage members like you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Make owner'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      await ref
          .read(householdRepositoryProvider)
          .promoteMemberToOwner(member.userId);
      ref.invalidate(householdMembersProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${member.displayName} is now an owner.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not promote member: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _leaveHousehold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave household?'),
        content: const Text(
          'You will lose shared access to this household planner, recipes, and grocery list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      await ref.read(householdRepositoryProvider).leaveHousehold();
      ref.invalidate(activeHouseholdProvider);
      ref.invalidate(activeHouseholdIdProvider);
      ref.invalidate(householdMembersProvider);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left the household.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not leave household: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final householdAsync = ref.watch(activeHouseholdProvider);
    final membersAsync = ref.watch(householdMembersProvider);
    final hasHousehold = householdAsync.valueOrNull != null;
    final user = ref.watch(currentUserProvider);
    final members = membersAsync.valueOrNull ?? const <HouseholdMember>[];
    final currentMember = user == null
        ? null
        : members.firstWhereOrNull((m) => m.userId == user.id);
    final isCurrentOwner = currentMember?.role == HouseholdRole.owner;
    final canLeave = currentMember?.role == HouseholdRole.member &&
        currentMember?.status == HouseholdMemberStatus.active;

    return Scaffold(
      appBar: AppBar(title: const Text('Household')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          householdAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => SectionCard(
              title: 'Household',
              child: Text('Error: $error'),
            ),
            data: (household) {
              if (household != null) {
                return SectionCard(
                  title: 'Current Household',
                  subtitle: household.name,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: ${household.id}'),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: _working ? null : _openMigrationWizard,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Edit household sharing'),
                      ),
                      if (isCurrentOwner) ...[
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _working
                              ? null
                              : () => _editHouseholdName(household.name),
                          icon: const Icon(Icons.edit_rounded),
                          label: const Text('Edit household name'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _working
                              ? null
                              : () => _editHouseholdPlannerWindow(household),
                          icon: const Icon(Icons.calendar_view_week_outlined),
                          label: const Text('Household planner default'),
                        ),
                      ],
                      if (canLeave) ...[
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _working ? null : _leaveHousehold,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Leave household'),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return SectionCard(
                title: 'Create Household',
                subtitle: 'Set up shared planning with your spouse.',
                child: Column(
                  children: [
                    TextField(
                      controller: _householdNameCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Household name',
                        hintText: 'e.g. The Smith Home',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _working ? null : _createHousehold,
                      icon: const Icon(Icons.home_rounded),
                      label: const Text('Create household'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose what to share now. You can edit household sharing later and share more anytime.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Share planner now'),
                      value: _sharePlannerOnCreate,
                      onChanged: _working
                          ? null
                          : (value) =>
                              setState(() => _sharePlannerOnCreate = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Share grocery list now'),
                      value: _shareGroceryOnCreate,
                      onChanged: _working
                          ? null
                          : (value) =>
                              setState(() => _shareGroceryOnCreate = value),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recipes',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const _HouseholdRecipePrivacyCallout(),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<_RecipeShareMode>(
                        segments: _RecipeShareMode.values
                            .map(
                              (mode) => ButtonSegment(
                                value: mode,
                                label: Text(mode.shortLabel),
                              ),
                            )
                            .toList(),
                        selected: <_RecipeShareMode>{_createRecipeShareMode},
                        onSelectionChanged: _working
                            ? null
                            : (selected) {
                                if (selected.isEmpty) return;
                                setState(() {
                                  _createRecipeShareMode = selected.first;
                                });
                                if (selected.first == _RecipeShareMode.select) {
                                  _loadCreatePersonalRecipesIfNeeded(user?.id);
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _createRecipeShareMode.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_createRecipeShareMode == _RecipeShareMode.select) ...[
                      if (_loadingCreateRecipes)
                        const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: CircularProgressIndicator(),
                        )
                      else if (_createPersonalRecipes.isEmpty)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No personal recipes to share yet.'),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: ListView(
                            shrinkWrap: true,
                            children: _createPersonalRecipes.map((recipe) {
                              final selected =
                                  _createSelectedRecipeIds.contains(recipe.id);
                              return CheckboxListTile(
                                value: selected,
                                title: Text(recipe.title),
                                onChanged: _working
                                    ? null
                                    : (value) {
                                        setState(() {
                                          if (value == true) {
                                            _createSelectedRecipeIds
                                                .add(recipe.id);
                                          } else {
                                            _createSelectedRecipeIds
                                                .remove(recipe.id);
                                          }
                                        });
                                      },
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Invite Member',
            subtitle: hasHousehold
                ? 'Add your spouse by account email.'
                : 'Create a household first to invite others.',
            child: Column(
              children: [
                TextField(
                  controller: _inviteEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  enabled: hasHousehold,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'name@example.com',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: _working || !hasHousehold ? null : _inviteMember,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add to household'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Members',
            child: membersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
              error: (error, _) => Text('Could not load members: $error'),
              data: (members) {
                final activeMembers = members
                    .where(
                      (m) => m.status == HouseholdMemberStatus.active,
                    )
                    .toList();
                final invitedMembers = members
                    .where(
                      (m) => m.status == HouseholdMemberStatus.invited,
                    )
                    .toList();
                final invitedEmails = invitedMembers
                    .map((m) => _normalizeEmail(m.invitedEmail ?? ''))
                    .where((e) => e.isNotEmpty)
                    .toSet();
                final signupOnlyPending = _pendingSignupEmails
                    .where(
                      (e) => !invitedEmails.contains(_normalizeEmail(e)),
                    )
                    .toList();
                final hasPending =
                    invitedMembers.isNotEmpty || signupOnlyPending.isNotEmpty;

                if (activeMembers.isEmpty && !hasPending) {
                  return const Text('No members yet.');
                }

                String invitedTitle(HouseholdMember m) {
                  final em = m.invitedEmail?.trim() ?? '';
                  if (em.isNotEmpty) return em;
                  return m.displayName;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...activeMembers.map(
                      (member) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          member.role.name == 'owner'
                              ? Icons.shield_outlined
                              : Icons.person_outline_rounded,
                        ),
                        title: Text(member.displayName),
                        subtitle: Text(
                          member.role == HouseholdRole.owner
                              ? 'Owner'
                              : 'Member',
                        ),
                        trailing: isCurrentOwner &&
                                user != null &&
                                member.userId != user.id &&
                                member.role != HouseholdRole.owner
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Make owner',
                                    onPressed: _working
                                        ? null
                                        : () =>
                                            _promoteMemberToOwner(member),
                                    icon: const Icon(
                                      Icons.workspace_premium_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove member',
                                    onPressed: _working
                                        ? null
                                        : () => _removeMember(member),
                                    icon: const Icon(
                                      Icons.person_remove_alt_1_rounded,
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                    if (hasPending) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Pending invites',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'These people have not joined the household yet.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...invitedMembers.map(
                        (member) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.mark_email_unread_outlined),
                          title: Text(invitedTitle(member)),
                          subtitle: const Text('Waiting to accept in the app'),
                          trailing: isCurrentOwner &&
                                  user != null &&
                                  member.userId != user.id
                              ? IconButton(
                                  tooltip: 'Revoke invite',
                                  onPressed: _working
                                      ? null
                                      : () => _removeMember(member),
                                  icon: const Icon(Icons.close_rounded),
                                )
                              : null,
                        ),
                      ),
                      ...signupOnlyPending.map(
                        (email) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.forward_to_inbox_outlined),
                          title: Text(email),
                          subtitle: const Text(
                            'Sign-up invite sent — no account yet',
                          ),
                          trailing: IconButton(
                            tooltip: 'Dismiss',
                            onPressed: () {
                              setState(() {
                                _pendingSignupEmails.removeWhere(
                                  (e) => _normalizeEmail(e) == _normalizeEmail(email),
                                );
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseholdMigrationWizard extends ConsumerStatefulWidget {
  const _HouseholdMigrationWizard({
    required this.personalRecipes,
    required this.initialSharePlanner,
    required this.initialShareGrocery,
  });

  final List<Recipe> personalRecipes;
  final bool initialSharePlanner;
  final bool initialShareGrocery;

  @override
  ConsumerState<_HouseholdMigrationWizard> createState() =>
      _HouseholdMigrationWizardState();
}

class _HouseholdMigrationWizardState
    extends ConsumerState<_HouseholdMigrationWizard> {
  late bool _sharePlanner;
  late bool _shareGrocery;
  _RecipeShareMode _recipeShareMode = _RecipeShareMode.none;
  final Set<String> _selectedRecipeIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sharePlanner = widget.initialSharePlanner;
    _shareGrocery = widget.initialShareGrocery;
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(householdRepositoryProvider);
      if (_sharePlanner) {
        await repo.migratePlannerToHousehold();
      }
      if (_shareGrocery) {
        await repo.migrateGroceryToHousehold();
      }
      if (_recipeShareMode == _RecipeShareMode.all) {
        await repo.shareAllPersonalRecipes();
      } else if (_recipeShareMode == _RecipeShareMode.select &&
          _selectedRecipeIds.isNotEmpty) {
        await repo.shareSelectedRecipes(_selectedRecipeIds.toList());
      }
      ref.invalidate(recipesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sharing changes applied.')),
      );
      Navigator.of(context).pop(
        _AppliedSharingState(
          sharePlanner: _sharePlanner,
          shareGrocery: _shareGrocery,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not apply sharing changes: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit household sharing',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              title: const Text('Share planner into household'),
              value: _sharePlanner,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _sharePlanner = value),
            ),
            SwitchListTile(
              title: const Text('Share grocery list into household'),
              value: _shareGrocery,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _shareGrocery = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Recipes'),
            const SizedBox(height: AppSpacing.xs),
            const _HouseholdRecipePrivacyCallout(),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_RecipeShareMode>(
                segments: _RecipeShareMode.values
                    .map(
                      (mode) => ButtonSegment(
                        value: mode,
                        label: Text(mode.shortLabel),
                      ),
                    )
                    .toList(),
                selected: <_RecipeShareMode>{_recipeShareMode},
                onSelectionChanged: _saving
                    ? null
                    : (selected) {
                        if (selected.isEmpty) return;
                        setState(() => _recipeShareMode = selected.first);
                      },
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _recipeShareMode.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_recipeShareMode == _RecipeShareMode.select)
              const Text('Choose personal recipes to share'),
            const SizedBox(height: AppSpacing.xs),
            if (_recipeShareMode == _RecipeShareMode.select)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: widget.personalRecipes.map((recipe) {
                    final selected = _selectedRecipeIds.contains(recipe.id);
                    return CheckboxListTile(
                      value: selected,
                      title: Text(recipe.title),
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedRecipeIds.add(recipe.id);
                                } else {
                                  _selectedRecipeIds.remove(recipe.id);
                                }
                              });
                            },
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _saving ? null : _apply,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Apply sharing changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppliedSharingState {
  const _AppliedSharingState({
    required this.sharePlanner,
    required this.shareGrocery,
  });

  final bool sharePlanner;
  final bool shareGrocery;
}

enum _RecipeShareMode {
  none,
  all,
  select,
}

extension _RecipeShareModeX on _RecipeShareMode {
  String get shortLabel => switch (this) {
        _RecipeShareMode.none => 'None',
        _RecipeShareMode.all => 'All',
        _RecipeShareMode.select => 'Select',
      };

  String get label => switch (this) {
        _RecipeShareMode.none => 'Do not share recipes now',
        _RecipeShareMode.all => 'Share all personal recipes',
        _RecipeShareMode.select => 'Choose individual recipes',
      };
}
