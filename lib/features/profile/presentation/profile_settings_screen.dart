import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/profile/presentation/profile_form.dart';

class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in required')),
      );
    }

    final profileRepo = ref.watch(profileRepositoryProvider);
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: () async {
              try {
                await ref.read(authRepositoryProvider).signOut();
                if (!context.mounted) return;
                context.go('/auth');
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not log out. Try again.')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.groups_2_outlined),
            tooltip: 'Household',
            onPressed: () => context.push('/household'),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => context.go('/'),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load profile: $error')),
        data: (profile) => ProfileForm(
          initialName: profile?.name ?? '',
          initialPrimaryGoal: profile?.goals.firstOrNull ?? 'more_veg',
          initialDietaryRestrictions: profile?.dietaryRestrictions ?? const [],
          initialPreferredCuisines: profile?.preferredCuisines ?? const [],
          initialDislikedIngredients: profile?.dislikedIngredients ?? const [],
          initialHouseholdServings: profile?.householdServings ?? 2,
          submitLabel: 'Save changes',
          onSubmit: (form) async {
            await profileRepo.upsertProfile(
              Profile(
                id: user.id,
                name: form.name,
                goals: [form.primaryGoal],
                dietaryRestrictions: form.dietaryRestrictions,
                preferredCuisines: form.preferredCuisines,
                dislikedIngredients: form.dislikedIngredients,
                householdServings: form.householdServings,
                householdId: profile?.householdId,
              ),
            );
            ref.invalidate(profileProvider);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile updated')),
            );
            context.go('/');
          },
        ),
      ),
    );
  }
}
