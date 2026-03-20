// Bump app version in pubspec.yaml for release builds (Firebase, Play, etc.).
//
// Usage (from repo root):
//   dart run tool/bump_version.dart build   # 0.1.1+2 -> 0.1.1+3  (same user-facing version)
//   dart run tool/bump_version.dart patch   # 0.1.1+2 -> 0.1.2+3  (new version string in Firebase)
//   dart run tool/bump_version.dart minor   # 0.1.1+2 -> 0.2.0+3
//   dart run tool/bump_version.dart major   # 0.1.1+2 -> 1.0.0+3
//
// Default is `build` if no argument is passed.

import 'dart:io';

void main(List<String> args) {
  final mode = args.isEmpty ? 'build' : args.first;
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found. Run from the project root.');
    exit(1);
  }

  final lines = pubspec.readAsLinesSync();
  final idx = lines.indexWhere((l) => l.trimLeft().startsWith('version:'));
  if (idx < 0) {
    stderr.writeln('No version: line found in pubspec.yaml');
    exit(1);
  }

  final value = lines[idx].split(':').skip(1).join(':').trim();
  final re = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$');
  final m = re.firstMatch(value);
  if (m == null) {
    stderr.writeln(
      'Expected pubspec version like 0.1.1+2 (semver+build), got: $value',
    );
    exit(1);
  }

  var major = int.parse(m.group(1)!);
  var minor = int.parse(m.group(2)!);
  var patch = int.parse(m.group(3)!);
  var build = int.parse(m.group(4)!);

  if (mode == 'build') {
    build++;
  } else if (mode == 'patch') {
    patch++;
    build++;
  } else if (mode == 'minor') {
    minor++;
    patch = 0;
    build++;
  } else if (mode == 'major') {
    major++;
    minor = 0;
    patch = 0;
    build++;
  } else {
    stderr.writeln(
      'Usage: dart run tool/bump_version.dart [build|patch|minor|major]',
    );
    exit(1);
  }

  lines[idx] = 'version: $major.$minor.$patch+$build';
  pubspec.writeAsStringSync('${lines.join('\n')}\n');
  stdout.writeln('Updated to version: $major.$minor.$patch+$build');
}
