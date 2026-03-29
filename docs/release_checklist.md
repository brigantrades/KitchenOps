# ForkFlow Release Checklist

## App version (Firebase / Play / App Store)

Firebase Crashlytics, Analytics, and App Distribution read **`versionName`** and **`versionCode`** from your build. In Flutter those come from `pubspec.yaml`:

`version: 0.1.1+2` → name **0.1.1**, build **2** (Android `versionName` / `versionCode`).

- **Same marketing version, new upload** (e.g. another internal build of 0.1.1): bump only the build number:

  `dart run tool/bump_version.dart build`

- **New version string in Firebase** (e.g. you want the console to show 0.1.2, not always 0.1.1): bump patch (and build):

  `dart run tool/bump_version.dart patch`

  Or use the wrapper script (bumps patch + builds release **APK** in one step — matches App Distribution uploads):

  `./tool/deploy_firebase_build.sh --dart-define-from-file=env/dev.json`

  If you run `flutter build apk` yourself, you **must** run `dart run tool/bump_version.dart patch` **before** the build. Otherwise the APK still embeds the old `pubspec.yaml` version and Firebase will keep showing the same label (e.g. **0.1.2 (5)**).

  Use `minor` or `major` when you mean a larger release.

Commit the updated `pubspec.yaml`, then build and upload to Firebase.

**CI without editing files:** you can override at build time (values must still increase for Play):

`flutter build appbundle --release --build-name=0.1.1 --build-number=$(git rev-list --count HEAD)`

## Firebase
- Run `flutterfire configure` for Android + iOS.
- Replace placeholders in `lib/firebase_options.dart`.
- Enable Firebase Analytics and Crashlytics dashboards.
- **Household grocery push** requires FCM token registration in the client. Without `--dart-define=FIREBASE_ENABLED=true`, [`Env.firebaseEnabled`](../lib/core/config/env.dart) stays false: Firebase is not initialized and **no rows are written to `user_device_tokens`**, so the Edge Function has nothing to send to.
- Examples (always include the define on **every** release artifact testers or production users install):
  - `./tool/deploy_firebase_build.sh --dart-define-from-file=env/dev.json` (appends `FIREBASE_ENABLED=true` automatically).
  - `flutter build appbundle --release --dart-define-from-file=env/prod.json --dart-define=FIREBASE_ENABLED=true`
  - `flutter build ipa --release --dart-define-from-file=env/prod.json --dart-define=FIREBASE_ENABLED=true`
- If `Firebase.initializeApp` throws at startup (wrong `google-services` / `GoogleService-Info.plist`), the app still runs but `Firebase.apps` stays empty and push registration is skipped—check device logs for `Firebase initialize failed`.
- Service account JSON for the `deliver-list-item-notification` Edge Function (see README).

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
