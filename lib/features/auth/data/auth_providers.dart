import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

final authStateProvider = StreamProvider<AuthState>((ref) {
  if (!Env.hasSupabase) return const Stream<AuthState>.empty();
  return ref.watch(authRepositoryProvider).authChanges();
});

final currentUserProvider = Provider<User?>((ref) {
  if (!Env.hasSupabase) return null;
  final authState = ref.watch(authStateProvider).valueOrNull;
  if (authState?.session?.user != null) return authState!.session!.user;
  try {
    return Supabase.instance.client.auth.currentUser;
  } catch (_) {
    return null;
  }
});
