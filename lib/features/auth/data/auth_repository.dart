import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:plateplan/core/config/env.dart';

class AuthRepository {
  static const _mobileAuthRedirect = 'leckerly://login-callback/';

  SupabaseClient get _client {
    if (!Env.hasSupabase) {
      throw StateError(
        'Supabase is not configured. Start the app with --dart-define-from-file=env/dev.json.',
      );
    }
    return Supabase.instance.client;
  }

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> authChanges() => _client.auth.onAuthStateChange;

  Future<void> signInWithEmail(String email, String password) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUpWithEmail(String email, String password) {
    return _client.auth.signUp(email: email, password: password);
  }

  Future<void> signInWithGoogle() {
    return _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _mobileAuthRedirect,
    );
  }

  Future<void> signOut() => _client.auth.signOut();
}
