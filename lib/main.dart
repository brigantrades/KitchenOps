import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/app.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/services/meal_reminder_notification_service.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/firebase_options.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LocalCache.init();

  await initMealReminderNotifications();

  if (Env.firebaseEnabled) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
    } catch (error, stack) {
      // Keep app bootable in release even if Firebase setup mismatches.
      debugPrint('Firebase initialize failed: $error');
      debugPrint('$stack');
    }
  }

  if (Env.hasSupabase) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
    } catch (error, stack) {
      debugPrint('Supabase initialize failed: $error');
      debugPrint('$stack');
    }
  }

  runApp(const ProviderScope(child: LeckerlyApp()));
}
