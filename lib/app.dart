import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/router/app_router.dart';
import 'package:plateplan/core/services/meal_reminder_notification_service.dart';
import 'package:plateplan/core/services/push_notification_service.dart';
import 'package:plateplan/core/theme/app_theme.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/core/planner_week_mapping.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';

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
