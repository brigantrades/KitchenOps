import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/app.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/firebase_options.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LocalCache.init();

  if (Env.firebaseEnabled) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  }

  if (Env.hasSupabase) {
    await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  }

  runApp(const ProviderScope(child: ForkFlowApp()));
}
