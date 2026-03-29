import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({super.key});

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  ProviderSubscription<User?>? _userSubscription;
  Future<void> _routeForUser(User user) async {
    if (!mounted) return;
    try {
      final repo = ref.read(profileRepositoryProvider);
      final profile = await repo.fetchProfile(user.id);
      if (!mounted) return;
      final needsOnboarding =
          profile == null || profile.name.trim().isEmpty;
      context.go(needsOnboarding ? '/onboarding' : '/');
    } catch (_) {
      if (!mounted) return;
      // Still leave the auth screen so OAuth users are not stuck if profile
      // fetch fails transiently; shell/home can retry profile.
      context.go('/');
    }
  }

  @override
  void dispose() {
    _userSubscription?.close();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _validateInputs() {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    if (email.isEmpty || password.isEmpty) {
      return 'Enter email and password.';
    }
    if (!email.contains('@')) {
      return 'Enter a valid email address.';
    }
    if (password.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _userSubscription = ref.listenManual<User?>(currentUserProvider, (_, next) {
      if (next == null || !mounted) return;
      _routeForUser(next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        _routeForUser(user);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authRepo = ref.watch(authRepositoryProvider);
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _routeForUser(user);
      });
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.45),
              scheme.surface,
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              'assets/images/branding/leckerly_logo_mark.png',
                              width: 260,
                              height: 142,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              isAntiAlias: true,
                              semanticLabel: 'Leckerly logo',
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                radius: 48,
                                backgroundColor: scheme.primaryContainer,
                                child: Icon(
                                  Icons.restaurant_menu_rounded,
                                  size: 46,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Leckerly',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Plan meals together, build lists, and stay synced with your household.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final inputError = _validateInputs();
                                  if (inputError != null) {
                                    _showMessage(inputError);
                                    return;
                                  }
                                  setState(() => _busy = true);
                                  try {
                                    final typedEmail =
                                        _emailCtrl.text.trim().toLowerCase();
                                    final existingUser =
                                        ref.read(currentUserProvider);
                                    final existingEmail =
                                        existingUser?.email?.toLowerCase();
                                    if (existingUser != null &&
                                        existingEmail != typedEmail) {
                                      await authRepo.signOut();
                                    }
                                    final signedInUser =
                                        await authRepo.signInWithEmail(
                                      _emailCtrl.text.trim(),
                                      _passwordCtrl.text.trim(),
                                    );
                                    if (!context.mounted) return;
                                    if (signedInUser == null) {
                                      _showMessage(
                                        'Sign in failed. Please try again.',
                                      );
                                      return;
                                    }
                                    final signedInEmail =
                                        signedInUser.email?.toLowerCase();
                                    if (signedInEmail != null &&
                                        signedInEmail != typedEmail) {
                                      await authRepo.signOut();
                                      if (!context.mounted) return;
                                      _showMessage(
                                        'Signed into a different account than requested. Please try again.',
                                      );
                                      return;
                                    }
                                    await _routeForUser(signedInUser);
                                  } on AuthException catch (error) {
                                    _showMessage(error.message);
                                  } catch (_) {
                                    _showMessage(
                                        'Sign in failed. Please try again.');
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Sign in'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    await authRepo.signInWithGoogle();
                                    _showMessage('Opening Google sign-in...');
                                  } on AuthException catch (error) {
                                    _showMessage(error.message);
                                  } catch (_) {
                                    _showMessage(
                                      'Google sign-in failed. Please try again.',
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() => _busy = false);
                                    }
                                  }
                                },
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('Continue with Google'),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  final inputError = _validateInputs();
                                  if (inputError != null) {
                                    _showMessage(inputError);
                                    return;
                                  }
                                  setState(() => _busy = true);
                                  try {
                                    await authRepo.signUpWithEmail(
                                      _emailCtrl.text.trim(),
                                      _passwordCtrl.text.trim(),
                                    );
                                    if (!context.mounted) return;
                                    final signedInUser =
                                        ref.read(currentUserProvider);
                                    if (signedInUser != null) {
                                      await _routeForUser(signedInUser);
                                    } else {
                                      context.go('/onboarding');
                                    }
                                  } on AuthException catch (error) {
                                    _showMessage(error.message);
                                  } catch (_) {
                                    _showMessage(
                                      'Account creation failed. Please try again.',
                                    );
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                          child: const Text('Create account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
