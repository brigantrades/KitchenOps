import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  PushNotificationService();

  FirebaseMessaging? _messaging;
  bool _initialized = false;

  Future<void> initForUser(String? userId) async {
    if (!Env.firebaseEnabled || userId == null || userId.isEmpty) {
      return;
    }
    if (Firebase.apps.isEmpty) {
      // Firebase is not initialized in this runtime profile.
      return;
    }
    final messaging = _messaging ??= FirebaseMessaging.instance;
    if (!_initialized) {
      await messaging.requestPermission();
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('Push message received: ${message.messageId}');
      });
      messaging.onTokenRefresh.listen((token) {
        _upsertToken(userId, token);
      });
      _initialized = true;
    }
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await _upsertToken(userId, token);
  }

  Future<void> _upsertToken(String userId, String token) async {
    await Supabase.instance.client.from('user_device_tokens').upsert({
      'user_id': userId,
      'platform': defaultTargetPlatform.name,
      'token': token,
      'last_seen_at': DateTime.now().toIso8601String(),
    });
  }
}
