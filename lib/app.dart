import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/router/app_router.dart';
import 'package:plateplan/core/router/root_navigation.dart';
import 'package:plateplan/core/services/meal_reminder_notification_service.dart';
import 'package:plateplan/core/services/push_notification_service.dart';
import 'package:plateplan/core/services/share_handler_service.dart';
import 'package:plateplan/core/theme/app_theme.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/core/planner_week_mapping.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/recipes/presentation/import_recipe_preview_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) => PushNotificationService());

class LeckerlyApp extends ConsumerStatefulWidget {
  const LeckerlyApp({super.key});

  @override
  ConsumerState<LeckerlyApp> createState() => _LeckerlyAppState();
}

class _LeckerlyAppState extends ConsumerState<LeckerlyApp>
    with WidgetsBindingObserver {
  bool _wasBackgrounded = false;
  bool _shareInitScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      _resetPlannerIfViewingOtherWeek();
      invalidateActiveGroceryStreams(ref);
      ref.invalidate(recipesProvider);
      ref.invalidate(plannerThreeDayOutlookSlotsProvider);
      if (Env.firebaseEnabled) {
        final uid = ref.read(currentUserProvider)?.id;
        unawaited(ref.read(pushNotificationServiceProvider).initForUser(uid));
      }
    }
  }

  void _resetPlannerIfViewingOtherWeek() {
    final now = DateTime.now();
    final pref = ref.read(effectivePlannerWindowProvider);
    final anchor = anchorDateForWindowContaining(now, pref);
    final viewed = ref.read(weekStartProvider);
    if (plannerDateOnly(viewed) != plannerDateOnly(anchor)) {
      ref.read(weekStartProvider.notifier).state = anchor;
      final dates = calendarDatesForPlannerWindow(anchor, pref);
      final today = plannerDateOnly(now);
      var idx = dates.indexWhere((d) => plannerDateOnly(d) == today);
      if (idx < 0) idx = 0;
      ref.read(selectedPlannerDayProvider.notifier).state =
          idx.clamp(0, pref.dayCount - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final currentUser = ref.watch(currentUserProvider);
    final mealReminders = ref.read(mealReminderNotificationServiceProvider);

    if (!_shareInitScheduled) {
      _shareInitScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(shareImportNotifierProvider.notifier).ensureInitialized();
      });
    }

    ref.listen<User?>(currentUserProvider, (prev, next) {
      if (prev == null && next != null) {
        ref.read(shareImportNotifierProvider.notifier).flushPendingAfterLogin();
      }
      if (Env.firebaseEnabled) {
        if (prev != null && next == null) {
          unawaited(
            ref
                .read(pushNotificationServiceProvider)
                .invalidateLocalPushRegistration(),
          );
        }
        if (next != null && prev?.id != next.id) {
          unawaited(
            ref.read(pushNotificationServiceProvider).initForUser(next.id),
          );
        }
      }
    });
    ref.listen<ShareImportState>(shareImportNotifierProvider, (prev, next) {
      if (next.isLoading && !(prev?.isLoading ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = rootNavigatorKey.currentContext;
          if (c == null) return;
          showDialog<void>(
            context: c,
            barrierDismissible: false,
            builder: (_) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Expanded(child: Text('Importing recipe…')),
                ],
              ),
            ),
          );
        });
      }
      if (!next.isLoading && (prev?.isLoading ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = rootNavigatorKey.currentContext;
          if (c == null) return;
          Navigator.of(c, rootNavigator: true).maybePop();
        });
      }
      if (next.recipeToNavigate != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = rootNavigatorKey.currentContext;
          if (c == null) return;
          GoRouter.of(c).push(
            '/import-recipe-preview',
            extra: ImportRecipePreviewArgs(
              recipe: next.recipeToNavigate!,
              sourcePayload: next.navigationSourcePayload,
            ),
          );
          ref.read(shareImportNotifierProvider.notifier).clearRecipeNavigation();
        });
      }
      if (next.snackMessage != null &&
          next.snackMessage != prev?.snackMessage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = rootNavigatorKey.currentContext;
          if (c == null) return;
          ScaffoldMessenger.of(c).showSnackBar(
            SnackBar(content: Text(next.snackMessage!)),
          );
          ref.read(shareImportNotifierProvider.notifier).clearSnack();
        });
      }
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = rootNavigatorKey.currentContext;
          if (c == null) return;
          ScaffoldMessenger.of(c).showSnackBar(
            SnackBar(
              content: Text(next.errorMessage!),
              action: next.canRetry
                  ? SnackBarAction(
                      label: 'Retry',
                      onPressed: () => ref
                          .read(shareImportNotifierProvider.notifier)
                          .retryLastImport(),
                    )
                  : null,
            ),
          );
        });
      }
    });

    ref.listen<AsyncValue<List<MealPlanSlot>>>(plannerSlotsProvider,
        (prev, next) {
      next.whenData((slots) {
        unawaited(mealReminders.syncFromSlots(slots));
      });
    });
    if (Env.firebaseEnabled) {
      final pushService = ref.watch(pushNotificationServiceProvider);
      pushService.initForUser(currentUser?.id);
    }
    return MaterialApp.router(
      title: 'Leckerly',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
