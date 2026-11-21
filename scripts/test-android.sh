#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../android"
if [[ ! -x ./gradlew ]]; then
  printf '%s\n' 'Generate the Android Gradle wrapper with flutter build apk --debug first.' >&2
  exit 1
fi
exec ./gradlew :app:testDebugUnitTest "$@"
