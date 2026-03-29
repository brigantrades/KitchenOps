#!/usr/bin/env bash
set -euo pipefail

# Bump patch version in pubspec.yaml, then build a release APK for App Distribution.
# Firebase shows versionName/versionCode from the built binary — you must bump before
# every upload or the console will keep showing the same "0.1.2 (5)".
#
# Usage (from repo root):
#   ./tool/deploy_firebase_build.sh --dart-define-from-file=env/dev.json
#
# Any extra args are passed through to `flutter build apk` before the trailing
# FIREBASE_ENABLED define. `--dart-define=FIREBASE_ENABLED=true` is always
# appended so App Distribution / tester builds register FCM tokens in
# user_device_tokens. For a build without FCM, run `flutter build apk` directly.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Bumping patch version in pubspec.yaml..."
dart run tool/bump_version.dart patch

echo "Building Android release APK (FIREBASE_ENABLED=true appended)..."
flutter build apk --release "$@" --dart-define=FIREBASE_ENABLED=true

echo
echo "Build complete with new version from pubspec.yaml."
echo "Commit pubspec.yaml, then upload:"
echo "firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk --app <your_android_app_id> --groups <tester_groups>"
