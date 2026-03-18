# ForkFlow Release Checklist

## Firebase
- Run `flutterfire configure` for Android + iOS.
- Replace placeholders in `lib/firebase_options.dart`.
- Enable Firebase Analytics and Crashlytics dashboards.

## Supabase
- Apply migrations in `supabase/migrations`.
- Configure OAuth providers: Google + Apple.
- Add storage bucket for recipe photos.

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
- Planner to grocery ingredient transfer.
- Discover AI generation and save behavior.
- Cooking mode navigation and TTS.
- Offline read from cached recipes + grocery list.
