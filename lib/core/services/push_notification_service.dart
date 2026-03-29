import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/debug/agent_session_log.dart';
import 'package:plateplan/core/router/root_navigation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  PushNotificationService();

  FirebaseMessaging? _messaging;
  bool _initialized = false;
  String? _activeUserId;
  String? _lastSyncedUserId;
  String? _lastSyncedToken;

  /// Clears in-memory sync flags after sign-out so the next session always
  /// re-fetches the FCM token and re-upserts to [user_device_tokens].
  void clearRegistrationState() {
    _lastSyncedUserId = null;
    _lastSyncedToken = null;
  }

  static void _openGroceryFromPayload(RemoteMessage message) {
    final type = message.data['type'];
    if (type != 'list_item_added') return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ctx.go('/grocery');
  }

  Future<void> initForUser(String? userId) async {
    // #region agent log
    agentSessionLog(
      hypothesisId: 'H-A',
      location: 'push_notification_service.dart:initForUser',
      message: 'entry',
      data: {
        'firebaseEnabled': Env.firebaseEnabled,
        'hasUserId': userId != null && userId.isNotEmpty,
        'userIdPrefix': (userId != null && userId.length >= 8)
            ? userId.substring(0, 8)
            : userId,
        'firebaseAppsCount': Firebase.apps.length,
      },
    );
    // #endregion
    if (!Env.firebaseEnabled || userId == null || userId.isEmpty) {
      // #region agent log
      agentSessionLog(
        hypothesisId: 'H-A',
        location: 'push_notification_service.dart:initForUser',
        message: 'early_exit_disabled_or_no_user',
        data: {'firebaseEnabled': Env.firebaseEnabled},
      );
      // #endregion
      return;
    }
    if (Firebase.apps.isEmpty) {
      // #region agent log
      agentSessionLog(
        hypothesisId: 'H-A',
        location: 'push_notification_service.dart:initForUser',
        message: 'early_exit_firebase_apps_empty',
        data: const {},
      );
      // #endregion
      // Firebase is not initialized in this runtime profile.
      return;
    }
    try {
      await _initForUserImpl(userId);
    } catch (e, st) {
      // #region agent log
      agentSessionLog(
        hypothesisId: 'H-A',
        location: 'push_notification_service.dart:initForUser',
        message: 'init_caught_exception',
        data: {
          'err': e.toString().length > 220
              ? e.toString().substring(0, 220)
              : e.toString(),
        },
      );
      // #endregion
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
      messaging.onTokenRefresh.listen((token) async {
        final activeUserId = _activeUserId;
        if (activeUserId == null || activeUserId.isEmpty) return;
        try {
          await _upsertToken(activeUserId, token);
          _lastSyncedUserId = activeUserId;
          _lastSyncedToken = token;
        } catch (e, st) {
          debugPrint('PushNotificationService onTokenRefresh upsert failed: $e\n$st');
        }
      });
      _initialized = true;
    }
    if (_lastSyncedUserId == userId && _lastSyncedToken != null) {
      // #region agent log
      agentSessionLog(
        hypothesisId: 'H-B',
        location: 'push_notification_service.dart:_initForUserImpl',
        message: 'skip_already_synced_in_memory',
        data: {
          'userIdPrefix':
              userId.length >= 8 ? userId.substring(0, 8) : userId,
          'tokenLen': _lastSyncedToken!.length,
        },
      );
      // #endregion
      return;
    }
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) {
      // #region agent log
      agentSessionLog(
        hypothesisId: 'H-A',
        location: 'push_notification_service.dart:_initForUserImpl',
        message: 'getToken_null_or_empty',
        data: const {},
      );
      // #endregion
      return;
    }
    // #region agent log
    agentSessionLog(
      hypothesisId: 'H-A',
      location: 'push_notification_service.dart:_initForUserImpl',
      message: 'getToken_ok_before_upsert',
      data: {
        'userIdPrefix': userId.length >= 8 ? userId.substring(0, 8) : userId,
        'tokenLen': token.length,
      },
    );
    // #endregion
    // Only mark in-memory sync after Supabase accepts the row; otherwise retries
    // (login, resume, next build) can run again.
    await _upsertToken(userId, token);
    _lastSyncedUserId = userId;
    _lastSyncedToken = token;
  }

  Future<void> _upsertToken(String userId, String token) async {
    // Table has unique(token), not unique(id) in payload — must merge on token
    // or every register inserts a new row and hits 23505 on hot restart.
    // #region agent log
    agentSessionLog(
      hypothesisId: 'H-A',
      location: 'push_notification_service.dart:_upsertToken',
      message: 'upsert_start',
      data: {
        'userIdPrefix': userId.length >= 8 ? userId.substring(0, 8) : userId,
        'tokenLen': token.length,
      },
    );
    // #endregion
    try {
      await Supabase.instance.client.from('user_device_tokens').upsert(
            {
              'user_id': userId,
              'platform': defaultTargetPlatform.name,
              'token': token,
              'last_seen_at': DateTime.now().toIso8601String(),
            },
            onConflict: 'token',
          );
      // #region agent log
      agentSessionLog(
        hypothesisId: 'H-A',
        location: 'push_notification_service.dart:_upsertToken',
        message: 'upsert_ok',
        data: {
          'userIdPrefix': userId.length >= 8 ? userId.substring(0, 8) : userId,
        },
      );
      // #endregion
    } catch (e) {
      // #region agent log
      agentSessionLog(
        hypothesisId: 'H-A',
        location: 'push_notification_service.dart:_upsertToken',
        message: 'upsert_error',
        data: {
          'err': e.toString().length > 220
              ? e.toString().substring(0, 220)
              : e.toString(),
        },
      );
      // #endregion
      rethrow;
    }
  }
}
