import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/household/data/household_repository.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';

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
  bool _working = false;

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
      await ref.read(householdRepositoryProvider).createHousehold(name);
      ref.invalidate(activeHouseholdProvider);
      ref.invalidate(activeHouseholdIdProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Household created.')),
      );
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
      if (result == HouseholdInviteResult.invitedExistingMember) {
        ref.invalidate(householdMembersProvider);
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
    final personalRecipes =
        await ref.read(recipesRepositoryProvider).listPersonalForUser(user.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HouseholdMigrationWizard(
        personalRecipeIds: personalRecipes.map((r) => r.id).toList(),
        personalRecipeTitles: {
          for (final recipe in personalRecipes) recipe.id: recipe.title,
        },
      ),
    );
  }

  Future<void> _removeMember(HouseholdMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          'Remove ${member.name?.trim().isNotEmpty == true ? member.name : (member.invitedEmail ?? member.userId)} from this household?',
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
                        label: const Text('Run sharing migration wizard'),
                      ),
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
                if (members.isEmpty) {
                  return const Text('No members yet.');
                }
                return Column(
                  children: members
                      .map(
                        (member) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            member.role.name == 'owner'
                                ? Icons.shield_outlined
                                : Icons.person_outline_rounded,
                          ),
                          title: Text(member.name?.trim().isNotEmpty == true
                              ? member.name!
                              : (member.invitedEmail ?? member.userId)),
                          subtitle: Text(
                            '${member.role.name} • ${member.status.name}',
                          ),
                          trailing: isCurrentOwner &&
                                  user != null &&
                                  member.userId != user.id &&
                                  member.role != HouseholdRole.owner
                              ? IconButton(
                                  tooltip: 'Remove member',
                                  onPressed: _working
                                      ? null
                                      : () => _removeMember(member),
                                  icon: const Icon(
                                      Icons.person_remove_alt_1_rounded),
                                )
                              : null,
                        ),
                      )
                      .toList(),
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
    required this.personalRecipeIds,
    required this.personalRecipeTitles,
  });

  final List<String> personalRecipeIds;
  final Map<String, String> personalRecipeTitles;

  @override
  ConsumerState<_HouseholdMigrationWizard> createState() =>
      _HouseholdMigrationWizardState();
}

class _HouseholdMigrationWizardState
    extends ConsumerState<_HouseholdMigrationWizard> {
  bool _sharePlanner = false;
  bool _shareGrocery = false;
  final Set<String> _selectedRecipeIds = {};
  bool _saving = false;

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
      if (_selectedRecipeIds.isNotEmpty) {
        await repo.shareSelectedRecipes(_selectedRecipeIds.toList());
      }
      ref.invalidate(recipesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Migration applied.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Migration failed: $error')),
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
              'Household Migration Wizard',
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
            const Text('Choose personal recipes to share'),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.personalRecipeIds.map((id) {
                  final selected = _selectedRecipeIds.contains(id);
                  return CheckboxListTile(
                    value: selected,
                    title: Text(widget.personalRecipeTitles[id] ?? 'Recipe'),
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                _selectedRecipeIds.add(id);
                              } else {
                                _selectedRecipeIds.remove(id);
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
              label: const Text('Apply migration choices'),
            ),
          ],
        ),
      ),
    );
  }
}
