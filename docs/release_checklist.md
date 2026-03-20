# ForkFlow Release Checklist

## App version (Firebase / Play / App Store)

Firebase Crashlytics, Analytics, and App Distribution read **`versionName`** and **`versionCode`** from your build. In Flutter those come from `pubspec.yaml`:

`version: 0.1.1+2` → name **0.1.1**, build **2** (Android `versionName` / `versionCode`).

- **Same marketing version, new upload** (e.g. another internal build of 0.1.1): bump only the build number:

  `dart run tool/bump_version.dart build`

- **New version string in Firebase** (e.g. you want the console to show 0.1.2, not always 0.1.1): bump patch (and build):

  `dart run tool/bump_version.dart patch`

  Use `minor` or `major` when you mean a larger release.

Commit the updated `pubspec.yaml`, then build and upload to Firebase.

**CI without editing files:** you can override at build time (values must still increase for Play):

`flutter build appbundle --release --build-name=0.1.1 --build-number=$(git rev-list --count HEAD)`

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
