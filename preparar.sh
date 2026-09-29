#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
dart tool/setup.dart
flutter analyze --no-fatal-infos
flutter test
