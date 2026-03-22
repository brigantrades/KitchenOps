import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

final authStateProvider = StreamProvider<AuthState>((ref) {
  if (!Env.hasSupabase) return const Stream<AuthState>.empty();
  return ref.watch(authRepositoryProvider).authChanges();
});

/// Prefer the synchronous session user first so Riverpod never treats the user
/// as logged out while [authStateProvider] is still loading or between stream
/// emissions (otherwise recipes/grocery/planner all resolve to empty data).
final currentUserProvider = Provider<User?>((ref) {
  if (!Env.hasSupabase) return null;
  try {
    final sync = Supabase.instance.client.auth.currentUser;
    if (sync != null) return sync;
  } catch (_) {}
  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user;
});
