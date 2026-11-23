#!/usr/bin/env bash
# Isolated test AVD; adb always targets this emulator, never a USB device.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
tools_dir=$(cd -- "$project_dir/../.benro-android-tools" && pwd)
export JAVA_HOME="$tools_dir/jdk"
export ANDROID_HOME="$tools_dir/android"
export ANDROID_USER_HOME="$tools_dir/android-user"
export ANDROID_EMULATOR_HOME="$tools_dir/android-user"
export ANDROID_AVD_HOME="$tools_dir/avd"
export XDG_CONFIG_HOME="$tools_dir/config"
export ADB_MDNS_AUTO_CONNECT=''
case "${1:-}" in
  create)
    mkdir -p "$ANDROID_AVD_HOME"
    exec "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd \
      --name mount-mischief-api36 --package 'system-images;android-36;google_apis;x86_64' --device pixel_6
    ;;
  start)
    exec "$ANDROID_HOME/emulator/emulator" -avd mount-mischief-api36 \
      -port 5580 -no-window -no-snapshot -no-boot-anim -gpu swiftshader \
      -memory 2048 -cores 2
    ;;
  adb)
    shift
    exec "$ANDROID_HOME/platform-tools/adb" -s emulator-5580 "$@"
    ;;
  *)
    printf '%s\n' 'Usage: scripts/emulator.sh create | start | adb <arguments>' >&2
    exit 2
    ;;
esac
