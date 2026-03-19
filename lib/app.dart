import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/router/app_router.dart';
import 'package:plateplan/core/services/push_notification_service.dart';
import 'package:plateplan/core/theme/app_theme.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) => PushNotificationService());

class LeckerlyApp extends ConsumerWidget {
  const LeckerlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    if (Env.firebaseEnabled) {
      final pushService = ref.watch(pushNotificationServiceProvider);
      ref.listen(currentUserProvider, (_, next) {
        pushService.initForUser(next?.id);
      });
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
