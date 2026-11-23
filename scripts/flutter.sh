#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
if [ -n "${FLUTTER_ROOT:-}" ]; then
    exec "$FLUTTER_ROOT/bin/flutter" "$@"
fi
tools_dir=${MMT_TOOLS_DIR:-"$project_dir/../.benro-android-tools"}
if [ ! -x "$tools_dir/flutter/bin/flutter" ]; then
    if command -v flutter >/dev/null 2>&1; then exec flutter "$@"; fi
    echo 'Set FLUTTER_ROOT, install flutter on PATH, or set MMT_TOOLS_DIR.' >&2
    exit 1
fi
tools_dir=$(cd -- "$tools_dir" && pwd)
export XDG_CONFIG_HOME="$tools_dir/config"
export ANALYZER_STATE_LOCATION_OVERRIDE="$tools_dir/analyzer-state"
export PUB_CACHE="$tools_dir/pub-cache"
export FLUTTER_SUPPRESS_ANALYTICS=true
export JAVA_HOME="$tools_dir/jdk"
export ANDROID_HOME="$tools_dir/android"
export ANDROID_USER_HOME="$tools_dir/android-user"
export GRADLE_USER_HOME="$tools_dir/gradle"
exec "$tools_dir/flutter/bin/flutter" "$@"
