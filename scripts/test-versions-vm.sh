#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
export MMT_LAB_DIR=${1:-"$project_dir/../projects/alpaca-pilot-port"}
export MMT_RUNTIME_ARCHIVE=${MMT_RUNTIME_ARCHIVE:-"$project_dir/../local/toolkit-runtime-1.0.0.tar.gz"}
export MMT_BETA8_ARCHIVE=${MMT_BETA8_ARCHIVE:-"$project_dir/assets/runtime/pilot.tar.gz"}
export MMT_PILOT220_ARCHIVE=${MMT_PILOT220_ARCHIVE:-"$MMT_LAB_DIR/workspace/python/out/releases/2.2.0/benro-alpaca-pilot-2.2.0-port.0.2.0-rc.1-sd-fat.tar.gz"}
cd "$project_dir"
exec ./scripts/flutter.sh test test_lab/versions_vm_test.dart --reporter expanded
