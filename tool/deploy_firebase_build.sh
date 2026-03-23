#!/usr/bin/env bash
set -euo pipefail

# Bump patch version in pubspec.yaml, then build a release APK for App Distribution.
# Firebase shows versionName/versionCode from the built binary — you must bump before
# every upload or the console will keep showing the same "0.1.2 (5)".
#
# Usage (from repo root):
#   ./tool/deploy_firebase_build.sh --dart-define-from-file=env/dev.json
#
# Any extra args are passed to `flutter build apk` (after --release).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Bumping patch version in pubspec.yaml..."
dart run tool/bump_version.dart patch

echo "Building Android release APK..."
flutter build apk --release "$@"

echo
echo "Build complete with new version from pubspec.yaml."
echo "Commit pubspec.yaml, then upload:"
echo "firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk --app <your_android_app_id> --groups <tester_groups>"
