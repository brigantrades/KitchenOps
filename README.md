# ForkFlow

ForkFlow is a Flutter mobile app for weekly meal planning, recipe discovery, grocery automation, and guided cooking.

## Stack
- Flutter + Riverpod + GoRouter
- Supabase (Auth, Postgres, Storage)
- Spoonacular API
- Gemini API
- Firebase Analytics + Crashlytics

## Quick start
1. Install Flutter 3.24+.
2. Add API keys through `--dart-define`:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SPOONACULAR_API_KEY`
   - `GEMINI_API_KEY`
3. Configure Firebase for Android/iOS (`flutterfire configure`).
4. Run SQL migrations in `supabase/migrations`.
5. Run:
   - `flutter pub get`
   - `flutter run`

## Discover seeding (Spoonacular dinners)
- Create and apply migration: `supabase/migrations/2026_discover_spoonacular.sql`
- Seed discover recipes once:
  - `dart run bin/seed_discover_dinners_spoonacular.dart`
- The script accepts placeholder constants or environment variables:
  - `SPOONACULAR_API_KEY`
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY` (preferred for inserts/upserts)
  - `SEED_USER_ID` (UUID of the owner row for imported public recipes)
- The script imports up to 10 dinner recipes for each category:
  - `chicken`, `beef`, `vegetarian`, `pasta`, `pork`
- It waits 1000ms between category requests and stops if Spoonacular quota is hit.
