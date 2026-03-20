# ForkFlow Release Checklist

## Firebase
- Run `flutterfire configure` for Android + iOS.
- Replace placeholders in `lib/firebase_options.dart`.
- Enable Firebase Analytics and Crashlytics dashboards.
- For household grocery push: enable FCM; release builds use `--dart-define=FIREBASE_ENABLED=true`; service account JSON for Edge Function (see README).

## Supabase
- Apply migrations in `supabase/migrations`.
- Configure OAuth providers: Google + Apple.
- Add storage bucket for recipe photos.
- Deploy `deliver-list-item-notification` Edge Function; set secrets `NOTIFICATION_WEBHOOK_SECRET`, `FIREBASE_SERVICE_ACCOUNT_JSON`; create Database Webhook on `notification_events` INSERT with `Authorization: Bearer …` (see README).

## Android (Google Play)
- Set app id, app name, icons, and splash.
- Configure signing and upload key.
- Test production build: `flutter build appbundle --release`.

## iOS (App Store)
- Set bundle id, team signing, app icons.
- Add Sign in with Apple and privacy usage strings.
- Test archive from Xcode.

## QA
- Auth signup/signin/signout.
- Two accounts, same household: add grocery item → other device gets push; tap opens grocery list.
- Planner to grocery ingredient transfer.
- Discover AI generation and save behavior.
- Cooking mode navigation and TTS.
- Offline read from cached recipes + grocery list.
