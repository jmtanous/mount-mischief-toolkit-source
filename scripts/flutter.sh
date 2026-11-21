#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  exec "$FLUTTER_ROOT/bin/flutter" "$@"
fi
if command -v flutter >/dev/null 2>&1; then
  exec flutter "$@"
fi
printf '%s\n' 'Install Flutter and add it to PATH, or set FLUTTER_ROOT.' >&2
exit 1
