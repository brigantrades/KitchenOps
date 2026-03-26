import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';

class DiscoverShellScaffold extends StatelessWidget {
  const DiscoverShellScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.onNotificationsTap,
    this.trailingActions = const <Widget>[],
    this.leading,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.resizeToAvoidBottomInset,
  });

  final String title;
  final Widget body;
  final Future<void> Function() onNotificationsTap;
  final List<Widget> trailingActions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFC4CFBC),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Row(
                      children: [
                        leading ?? const SizedBox(width: 34),
                        const Spacer(),
                        ...trailingActions,
                        if (trailingActions.isNotEmpty) const SizedBox(width: 8),
                        InkWell(
                          onTap: () => context.push('/profile'),
                          borderRadius: BorderRadius.circular(18),
                          child: const CircleAvatar(
                            radius: 15,
                            backgroundColor: Color(0xFFE7DED1),
                            child: Icon(
                              Icons.person_rounded,
                              color: Color(0xFF4F5B52),
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: onNotificationsTap,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE7DED1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.notifications_none_rounded,
                              color: Color(0xFF4F5B52),
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF3F2E8),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showDiscoverNotificationsDropdown(
  BuildContext context,
  WidgetRef ref,
) async {
  String? actioningHouseholdId;
  var isAccepting = false;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.12),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Consumer(
        builder: (context, ref, _) {
          final invitesAsync = ref.watch(pendingHouseholdInvitesProvider);

          Future<void> rejectInvite(HouseholdInvite invite) async {
            setModalState(() {
              actioningHouseholdId = invite.householdId;
              isAccepting = false;
            });
            try {
              await ref
                  .read(householdRepositoryProvider)
                  .rejectInvite(invite.householdId);
              ref.invalidate(pendingHouseholdInvitesProvider);
              ref.invalidate(householdMembersProvider);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite declined.')),
              );
            } catch (error) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not decline invite: $error')),
              );
            } finally {
              setModalState(() => actioningHouseholdId = null);
            }
          }

          Future<void> acceptInvite(HouseholdInvite invite) async {
            setModalState(() {
              actioningHouseholdId = invite.householdId;
              isAccepting = true;
            });
            try {
              await ref
                  .read(householdRepositoryProvider)
                  .acceptInvite(invite.householdId);
              ref.invalidate(profileProvider);
              ref.invalidate(activeHouseholdProvider);
              ref.invalidate(activeHouseholdIdProvider);
              ref.invalidate(householdMembersProvider);
              ref.invalidate(pendingHouseholdInvitesProvider);
              ref.invalidate(plannerSlotsProvider);
              invalidateActiveGroceryStreams(ref);
              ref.invalidate(listsProvider);
              ref.invalidate(recipesProvider);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Joined household.')),
              );
            } catch (error) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not accept invite: $error')),
              );
            } finally {
              setModalState(() {
                actioningHouseholdId = null;
                isAccepting = false;
              });
            }
          }

          return SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 360,
                margin: const EdgeInsets.only(top: 56, right: 12, left: 12),
                constraints: const BoxConstraints(maxHeight: 460),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F2E8),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppShadows.soft,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    invitesAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Could not load notifications: $error'),
                      ),
                      data: (invites) {
                        if (invites.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('No notifications yet.'),
                          );
                        }
                        return Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: invites.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final invite = invites[index];
                              final isBusy =
                                  actioningHouseholdId == invite.householdId;
                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: AppShadows.soft,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Household invite: ${invite.householdName}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Role: ${invite.role.name}${invite.invitedEmail != null ? '  •  ${invite.invitedEmail}' : ''}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: isBusy
                                                ? null
                                                : () => rejectInvite(invite),
                                            child: isBusy && !isAccepting
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Text('Reject'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: isBusy
                                                ? null
                                                : () => acceptInvite(invite),
                                            child: isBusy && isAccepting
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Text('Accept'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
