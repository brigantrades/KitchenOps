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

## Household grocery push notifications

When someone adds an item to a **household** grocery list, Postgres enqueues a row in `notification_events` (`list_item_added`). The Edge Function [`supabase/functions/deliver-list-item-notification`](supabase/functions/deliver-list-item-notification) sends FCM to other active household members.

1. **Flutter:** Build with `--dart-define=FIREBASE_ENABLED=true` (in addition to your other defines). Ensure Firebase Cloud Messaging is enabled for the app (Android: default FCM setup from `flutterfire configure`; iOS: push capability + APNs as per Firebase docs). The app registers tokens in `user_device_tokens`.
2. **Firebase:** Create a service account with **Firebase Cloud Messaging API** access and download JSON.
3. **Supabase Edge Function:** From the repo root (with [Supabase CLI](https://supabase.com/docs/guides/cli) linked to your project):
   - `supabase secrets set NOTIFICATION_WEBHOOK_SECRET="<random-long-secret>"`
   - `supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(cat /path/to/service-account.json)"`
   - `supabase functions deploy deliver-list-item-notification`
4. **Database webhook:** In the Supabase Dashboard → **Integrations → Database Webhooks**, add a hook on `public.notification_events` **INSERT** (optional filter: `event_type = 'list_item_added'`). Point the URL to `https://<project-ref>.supabase.co/functions/v1/deliver-list-item-notification` and add header `Authorization: Bearer <same NOTIFICATION_WEBHOOK_SECRET>`.
5. **`supabase/config.toml`** sets `verify_jwt = false` for this function so webhook calls are not rejected. If your CLI requires a full config, run `supabase init` and merge that snippet.

Note: bulk inserts (e.g. many planner ingredients) enqueue **one notification per row**.

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

## Discover seeding (curated web dinners)
- Imports public recipes from curated source pages (Downshiftology, Milk Street, Half Baked Harvest, Delish, Food52, Love and Lemons) with `meal_type` **`sauce`** (Discover “Dinner” tab).
- Dry run (writes `tmp/dinner_curated_review.csv`, no database writes):  
  `dart run bin/import_discover_dinner_curated.dart`
- After reviewing the CSV, import:  
  `dart run bin/import_discover_dinner_curated.dart --execute`
- Environment variables: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SEED_USER_ID`
- Optional: `--per-category=25` (default 25 recipes per bucket). `--limit=25` is also supported as an alias.
- The home “Quick & Easy Dinners” strip uses a fixed `api_id` allowlist in code; new imports appear in Discover search and cuisine tiles, not necessarily that strip unless you add their `api_id`s to that list.
