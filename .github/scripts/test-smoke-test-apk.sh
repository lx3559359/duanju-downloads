#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
smoke_script="${script_dir}/smoke-test-apk.sh"

required_fragments=(
  'settings put global hide_error_dialogs 1'
  'for attempt in 1 2 3'
  'expected_package_marker="package=\"${PACKAGE_NAME}\""'
  'ANR in ${PACKAGE_NAME}'
)

for fragment in "${required_fragments[@]}"; do
  if ! grep -Fq "${fragment}" "${smoke_script}"; then
    echo "missing required smoke-test guard" >&2
    exit 1
  fi
done

echo 'PASS: APK smoke test retries system-dialog interference without weakening app checks.'
