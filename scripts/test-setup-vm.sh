#!/usr/bin/env bash
# Full setup/recovery integration only in the existing localhost ARM VM.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
export MMT_LAB_DIR=${1:-"$project_dir/../projects/alpaca-pilot-port"}
export MMT_RUNTIME_ARCHIVE=${MMT_RUNTIME_ARCHIVE:-"$project_dir/../local/toolkit-runtime-1.0.0.tar.gz"}
cd "$project_dir"
exec ./scripts/flutter.sh test test_lab/setup_vm_test.dart --reporter expanded
