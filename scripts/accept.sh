#!/usr/bin/env bash
# Acceptance gate for the release check (add-acceptance-suite).
#
# Run from the devcontainer at /workspaces/natter: the flutter toolchain and
# the adb client both live there (see .devcontainer/README.md). Angle brackets
# below are placeholders; real host and device ids are in the git-ignored
# local notes.
#
# Target device: set NATTER_ACCEPT_DEVICE to the adb device id - typically
# `emulator-5554` on the always-on emulator on <dev-box>, or a physical
# <device>. With NATTER_ACCEPT_DEVICE unset, the script uses the single
# device that `adb devices` reports.
#
# Exit code is the gate's verdict: 0 means every acceptance scenario
# confirmed on the device; non-zero names the failing scenario.
set -euo pipefail

cd "$(dirname "$0")/.."

package=dev.natter.app

device=${NATTER_ACCEPT_DEVICE:-}
if [ -z "$device" ]; then
  devices=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
  if [ "$(printf '%s\n' "$devices" | grep -c . || true)" -ne 1 ]; then
    echo "accept: no single target device; set NATTER_ACCEPT_DEVICE." >&2
    adb devices >&2
    exit 2
  fi
  device=$devices
fi

echo "accept: clearing app state on $device"
# Tolerated: a fresh device has no install to clear; flutter test installs
# its own debug build right after.
adb -s "$device" shell pm clear "$package" >/dev/null || true

echo "accept: running integration_test/accept on $device"
flutter test integration_test/accept -d "$device"
