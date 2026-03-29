import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/router/root_navigation.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/features/auth/presentation/auth_gate_screen.dart';
import 'package:plateplan/features/cooking_mode/presentation/cooking_mode_screen.dart';
import 'package:plateplan/features/discover/presentation/discover_screen.dart';
import 'package:plateplan/features/grocery/presentation/grocery_screen.dart';
import 'package:plateplan/features/home/presentation/home_screen.dart';
import 'package:plateplan/features/household/presentation/household_settings_screen.dart';
import 'package:plateplan/features/planner/presentation/planner_screen.dart';
import 'package:plateplan/features/profile/presentation/onboarding_screen.dart';
import 'package:plateplan/features/profile/presentation/profile_settings_screen.dart';
import 'package:plateplan/features/recipes/presentation/import_recipe_preview_screen.dart';
import 'package:plateplan/features/recipes/presentation/instagram_import_test_screen.dart';
import 'package:plateplan/features/recipes/presentation/recipe_creation_guard.dart';
import 'package:plateplan/features/recipes/presentation/recipes_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notifies [GoRouter] when Supabase auth session changes (e.g. OAuth return)
/// so [redirect] runs again. Without this, users can stay on `/auth` until a
/// full restart even though `auth.currentUser` is already set.
final class _GoRouterAuthRefresh extends ChangeNotifier {
  _GoRouterAuthRefresh(this._client) {
    _sub = _client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final observers = Env.firebaseEnabled
      ? <NavigatorObserver>[
          FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)
        ]
      : const <NavigatorObserver>[];
  _GoRouterAuthRefresh? authRefresh;
  if (Env.hasSupabase) {
    authRefresh = _GoRouterAuthRefresh(Supabase.instance.client);
    ref.onDispose(authRefresh.dispose);
  }
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/auth',
    observers: observers,
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final loggedIn =
          !Env.hasSupabase || Supabase.instance.client.auth.currentUser != null;
      final atAuth = state.matchedLocation == '/auth';
      final atOnboarding = state.matchedLocation == '/onboarding';
      final atImportPreview = state.matchedLocation == '/import-recipe-preview';
      final atInstagramImportTest =
          state.matchedLocation == '/instagram-import-test';

      if (!loggedIn && (atImportPreview || atInstagramImportTest)) {
        return '/auth';
      }
      if (!loggedIn && !atAuth) return '/auth';
      if (loggedIn && atAuth) return '/';
      if (!loggedIn && atOnboarding) return '/auth';
      return null;
    },
    routes: [
      GoRoute(
          path: '/auth', builder: (context, state) => const AuthGateScreen()),
      GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen()),
      GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileSettingsScreen()),
      GoRoute(
          path: '/household',
          builder: (context, state) => const HouseholdSettingsScreen()),
      ShellRoute(
        builder: (context, state, child) => _AppScaffold(child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(
              path: '/recipes',
              builder: (context, state) => const RecipesScreen()),
          GoRoute(
              path: '/planner',
              builder: (context, state) => const PlannerScreen()),
          GoRoute(
              path: '/grocery',
              builder: (context, state) => const GroceryScreen()),
          GoRoute(
              path: '/discover',
              builder: (context, state) => const DiscoverScreen()),
        ],
      ),
      GoRoute(
        path: '/cooking/:recipeId',
        builder: (context, state) => CookingModeScreen(
          recipeId: state.pathParameters['recipeId']!,
        ),
      ),
      GoRoute(
        path: '/import-recipe-preview',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! ImportRecipePreviewArgs) {
            return const _ImportRecipeMissingScreen();
          }
          return ImportRecipePreviewScreen(args: extra);
        },
      ),
      GoRoute(
        path: '/instagram-import-test',
        builder: (context, state) => const InstagramImportTestScreen(),
      ),
    ],
  );
});

class _ImportRecipeMissingScreen extends StatelessWidget {
  const _ImportRecipeMissingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import recipe')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No import data found.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/recipes'),
                child: const Text('Go to Recipes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppScaffold extends ConsumerWidget {
  const _AppScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final items = <String>[
      '/',
      '/recipes',
      '/planner',
      '/grocery',
      '/discover'
    ];
    final labels = <String>[
      'Home',
      'Recipes',
      'Planner',
      'Lists',
      'Discover'
    ];
    final icons = <IconData>[
      Icons.home_outlined,
      Icons.menu_book_outlined,
      Icons.calendar_today_outlined,
      Icons.shopping_basket_outlined,
      Icons.auto_awesome_outlined,
    ];
    final selectedIcons = <IconData>[
      Icons.home,
      Icons.menu_book,
      Icons.calendar_today,
      Icons.shopping_basket,
      Icons.auto_awesome,
    ];
    final currentIndex = items.indexWhere(
        (item) => item == '/' ? location == '/' : location.startsWith(item));
    final recipeGuard = ref.watch(recipeCreationGuardProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: child,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.98),
            borderRadius: AppRadius.lg,
            boxShadow: AppShadows.floating,
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final selected = (currentIndex < 0 ? 0 : currentIndex) == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () async {
                    if (index == currentIndex) return;
                    final shouldPrompt =
                        recipeGuard.isOpen && recipeGuard.stepIndex >= 1;
                    if (!shouldPrompt) {
                      context.go(items[index]);
                      return;
                    }

                    final leave = await showModalBottomSheet<bool>(
                      context: context,
                      showDragHandle: true,
                      builder: (context) => BrandedSheetScaffold(
                        title: 'Recipe in progress',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Do you want to save your progress and keep editing, or cancel this recipe and leave?',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonal(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Keep editing'),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('Discard'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );

                    if (leave != true) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Progress saved. Continue editing your recipe.')),
                        );
                      }
                      return;
                    }

                    if (!context.mounted) return;
                    await Navigator.of(context, rootNavigator: true).maybePop();
                    ref.read(recipeCreationGuardProvider.notifier).close();
                    if (context.mounted) {
                      context.go(items[index]);
                    }
                  },
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.md,
                      color: selected
                          ? scheme.primary.withValues(alpha: 0.14)
                          : Colors.transparent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? selectedIcons[index] : icons[index],
                          size: 20,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          labels[index],
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: selected
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
