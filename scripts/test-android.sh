#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
tools_dir=${MMT_TOOLS_DIR:-"$project_dir/../.benro-android-tools"}
if [ -d "$tools_dir" ]; then
tools_dir=$(cd -- "$tools_dir" && pwd)
export JAVA_HOME="$tools_dir/jdk"
export ANDROID_HOME="$tools_dir/android"
export ANDROID_USER_HOME="$tools_dir/android-user"
export GRADLE_USER_HOME="$tools_dir/gradle"
fi
cd "$project_dir/android"
exec ./gradlew :app:testDebugUnitTest "$@"
