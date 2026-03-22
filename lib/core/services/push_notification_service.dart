import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/router/root_navigation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  PushNotificationService();

  FirebaseMessaging? _messaging;
  bool _initialized = false;
  String? _activeUserId;
  String? _lastSyncedUserId;
  String? _lastSyncedToken;

  static void _openGroceryFromPayload(RemoteMessage message) {
    final type = message.data['type'];
    if (type != 'list_item_added') return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ctx.go('/grocery');
  }

  Future<void> initForUser(String? userId) async {
    if (!Env.firebaseEnabled || userId == null || userId.isEmpty) {
      return;
    }
    if (Firebase.apps.isEmpty) {
      // Firebase is not initialized in this runtime profile.
      return;
    }
    try {
      await _initForUserImpl(userId);
    } catch (e, st) {
      // FCM / Installations often fails on emulators or without Play Services;
      // must not affect Supabase-backed app data.
      debugPrint('PushNotificationService.initForUser skipped: $e\n$st');
    }
  }

  Future<void> _initForUserImpl(String userId) async {
    final messaging = _messaging ??= FirebaseMessaging.instance;
    _activeUserId = userId;
    if (!_initialized) {
      await messaging.requestPermission();
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('Push message received: ${message.messageId}');
        // Foreground: FCM does not show a system banner by default; surface
        // something in-app so emulator/device tests are obvious.
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          final title = message.notification?.title ?? 'Notification';
          final body = message.notification?.body ?? message.data['name'] ?? '';
          final text = body.isNotEmpty ? '$title: $body' : title;
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
            SnackBar(content: Text(text)),
          );
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_openGroceryFromPayload);
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openGroceryFromPayload(initial);
        });
      }
      messaging.onTokenRefresh.listen((token) {
        final activeUserId = _activeUserId;
        if (activeUserId == null || activeUserId.isEmpty) return;
        _lastSyncedUserId = activeUserId;
        _lastSyncedToken = token;
        _upsertToken(activeUserId, token);
      });
      _initialized = true;
    }
    if (_lastSyncedUserId == userId && _lastSyncedToken != null) {
      return;
    }
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    _lastSyncedUserId = userId;
    _lastSyncedToken = token;
    await _upsertToken(userId, token);
  }

  Future<void> _upsertToken(String userId, String token) async {
    // Table has unique(token), not unique(id) in payload — must merge on token
    // or every register inserts a new row and hits 23505 on hot restart.
    await Supabase.instance.client.from('user_device_tokens').upsert(
          {
            'user_id': userId,
            'platform': defaultTargetPlatform.name,
            'token': token,
            'last_seen_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'token',
        );
  }
}
