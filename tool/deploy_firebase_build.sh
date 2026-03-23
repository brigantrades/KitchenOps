#!/usr/bin/env bash
set -euo pipefail

# Bump marketing version for Firebase labels, then build release artifact.
# Usage:
#   ./tool/deploy_firebase_build.sh
#   ./tool/deploy_firebase_build.sh --dart-define=FIREBASE_ENABLED=true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Bumping patch version in pubspec.yaml..."
dart run tool/bump_version.dart patch

echo "Building Android app bundle..."
flutter build appbundle --release "$@"

echo
echo "Build complete with incremented version."
echo "Commit pubspec.yaml, then upload:"
echo "firebase appdistribution:distribute build/app/outputs/bundle/release/app-release.aab --app <app_id> --groups <tester_groups>"
