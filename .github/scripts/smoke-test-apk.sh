#!/usr/bin/env bash
set -euo pipefail

: "${API_LEVEL:?API_LEVEL is required}"
: "${APK_URL:?APK_URL is required}"
: "${APK_SHA256:?APK_SHA256 is required}"
: "${PACKAGE_NAME:?PACKAGE_NAME is required}"
: "${ACTIVITY_NAME:?ACTIVITY_NAME is required}"
: "${EXPECTED_TEXT:?EXPECTED_TEXT is required}"

artifact_dir="smoke-artifacts/api-${API_LEVEL}"
apk_path="${RUNNER_TEMP}/duanju.apk"
mkdir -p "${artifact_dir}"

curl --fail --location --retry 3 --retry-all-errors \
  --output "${apk_path}" \
  "${APK_URL}"

printf '%s  %s\n' "${APK_SHA256}" "${apk_path}" | sha256sum --check --strict
adb install --no-incremental -r "${apk_path}" 2>&1 | tee "${artifact_dir}/install.txt"

adb logcat --clear
adb shell am force-stop "${PACKAGE_NAME}"
adb shell am start -W -n "${PACKAGE_NAME}/${ACTIVITY_NAME}" \
  | tee "${artifact_dir}/activity-start.txt"

# Let the first Compose frame and asynchronous startup work settle before inspection.
sleep 8

adb shell uiautomator dump /sdcard/duanju-window.xml || true
adb pull /sdcard/duanju-window.xml "${artifact_dir}/window.xml" || true
adb exec-out screencap -p > "${artifact_dir}/screenshot.png" || true
adb logcat -d -v threadtime > "${artifact_dir}/logcat.txt"
adb shell dumpsys activity activities > "${artifact_dir}/activities.txt"

failure=0
pid="$(adb shell pidof "${PACKAGE_NAME}" | tr -d '\r' || true)"
if [[ -z "${pid}" ]]; then
  echo "ERROR: ${PACKAGE_NAME} is not running after launch." >&2
  failure=1
fi

if grep -A 20 -F "FATAL EXCEPTION" "${artifact_dir}/logcat.txt" \
  | grep -Fq "Process: ${PACKAGE_NAME},"; then
  echo "ERROR: AndroidRuntime recorded a fatal exception for ${PACKAGE_NAME}." >&2
  failure=1
fi

if [[ ! -s "${artifact_dir}/window.xml" ]] \
  || ! grep -Fq "${EXPECTED_TEXT}" "${artifact_dir}/window.xml"; then
  echo "ERROR: Expected first-screen text was not found: ${EXPECTED_TEXT}" >&2
  failure=1
fi

{
  echo "### APK smoke test — API ${API_LEVEL}"
  echo
  echo "- Package: \`${PACKAGE_NAME}\`"
  echo "- Process: \`${pid:-not running}\`"
  echo "- Expected text: \`${EXPECTED_TEXT}\`"
  echo "- Result: $([[ ${failure} -eq 0 ]] && echo PASS || echo FAIL)"
} >> "${GITHUB_STEP_SUMMARY}"

exit "${failure}"
