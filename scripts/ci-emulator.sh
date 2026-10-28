#!/usr/bin/env bash
# Ephemeral CI device for the acceptance gate (add-ci-acceptance-gate).
#
# Provisions a throwaway Android emulator inside a CI runner and leaves it
# running, so the next step can point the release gate at it:
#
#   scripts/ci-emulator.sh                                    # provision
#   NATTER_ACCEPT_DEVICE=$(cat "$NATTER_CI_EVIDENCE/device-serial") scripts/accept.sh
#   scripts/ci-emulator.sh teardown                           # stop it, list evidence
#
# Versions come from the workflow's env block, which mirrors the pins declared
# in .devcontainer/Dockerfile. Nothing here reads a secret or an endpoint: the
# acceptance suite serves its own endpoint on the device's loopback.
#
# Every message is prefixed with the stage name, because the stage names in the
# workflow are what make a CI verdict readable: a failure here says "the device
# could not be provisioned", not "this build is not releasable".
set -euo pipefail

mode=${1:-provision}
case "$mode" in
  provision) stage="Provision device" ;;
  teardown) stage="Tear down device" ;;
  *) printf '%s: unknown mode %s (expected provision or teardown)\n' "ci-emulator" "$mode" >&2; exit 2 ;;
esac

say() { printf '%s: %s\n' "$stage" "$*" >&2; }
die() {
  say "$*"
  cleanup_partial
  exit 1
}

# Evidence that survives the run, uploaded by the workflow when a stage fails.
evidence=${NATTER_CI_EVIDENCE:-build/ci-evidence}
avd=${AVD_NAME:-natter-ci}
boot_timeout=${NATTER_BOOT_TIMEOUT:-420}

platform=${ANDROID_PLATFORM:-}
build_tools=${ANDROID_BUILD_TOOLS:-}
system_image() { printf 'system-images;android-%s;google_apis;x86_64' "$platform"; }

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}
sdkman="$sdk/cmdline-tools/latest/bin/sdkmanager"
avdmanager="$sdk/cmdline-tools/latest/bin/avdmanager"
emulator_bin="$sdk/emulator/emulator"

# adb is not reliably on PATH in a CI runner shell even when the SDK is present,
# and every device interaction after provisioning goes through it.
resolve_adb() {
  if [ -x "$sdk/platform-tools/adb" ]; then
    printf '%s' "$sdk/platform-tools/adb"
  elif command -v adb >/dev/null 2>&1; then
    printf 'adb'
  fi
}
adb_bin=$(resolve_adb)

logcat_pid_file=$evidence/logcat.pid
emulator_pid_file=$evidence/emulator.pid
cleaned_up=no

stop_logcat() {
  if [ -f "$logcat_pid_file" ]; then
    kill "$(cat "$logcat_pid_file")" 2>/dev/null || true
    rm -f "$logcat_pid_file"
  fi
}

stop_emulator() {
  if [ -f "$emulator_pid_file" ]; then
    local pid
    pid=$(cat "$emulator_pid_file")
    if [ -n "$adb_bin" ]; then
      "$adb_bin" -s "$(cat "$evidence/device-serial" 2>/dev/null || true)" emu kill >/dev/null 2>&1 || true
    fi
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 2
    done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$emulator_pid_file"
  fi
}

# Only reachable from failure paths: a provisioned device that the gate never
# got to use is dead weight, and a half-started one is worse. Reachable both
# from an unexpected command failure and from an explicit die() below.
cleanup_partial() {
  [ "$cleaned_up" = yes ] && return 0
  cleaned_up=yes
  stop_logcat
  stop_emulator
}
trap cleanup_partial ERR

list_evidence() {
  say "evidence in $evidence:"
  find "$evidence" -maxdepth 1 -type f -printf '  %f (%s bytes)\n' 2>/dev/null | sort >&2
}

# Preflight before anything is downloaded: a machine without KVM has no business
# pulling a gigabyte of system image first and failing afterwards. The dev
# container is exactly such a machine, so this is also the guard that keeps the
# emulator out of it.
preflight() {
  [ -e /dev/kvm ] || die "no /dev/kvm on this machine; a CI runner needs hardware acceleration (the dev container deliberately has no emulator)"
  [ -r /dev/kvm ] && [ -w /dev/kvm ] || die "/dev/kvm exists but is not readable and writable; open its permissions before provisioning (on a GitHub-hosted runner the workflow does this with a udev rule)"
  [ -n "$platform" ] && [ -n "$build_tools" ] || die "ANDROID_PLATFORM and ANDROID_BUILD_TOOLS must be set (they come from the workflow env block)"
  [ -x "$sdkman" ] || command -v sdkmanager >/dev/null 2>&1 || die "no sdkmanager under $sdk; the runner image is expected to carry the Android SDK"
  [ -n "$adb_bin" ] || die "no adb under $sdk/platform-tools and none on PATH; the device stage cannot talk to a device without it"
}

install_packages() {
  local manager packages
  manager=$([ -x "$sdkman" ] && printf '%s' "$sdkman" || printf 'sdkmanager')
  packages=(
    "platforms;android-$platform"
    "build-tools;$build_tools"
    "platform-tools"
    "emulator"
    "$(system_image)"
  )
  # A bounded stream of confirmations rather than `yes |`: sdkmanager stops
  # reading before its input is exhausted, and `yes` then dies on a broken pipe,
  # which leaves a confusing line in the log for a step that succeeded.
  printf 'y\n%.0s' $(seq 1 60) | "$manager" --licenses >/dev/null 2>&1 || true
  say "installing: ${packages[*]}"
  # A log file rather than the step's own output: an install that half-succeeds
  # is diagnosable only from what sdkmanager actually said.
  "$manager" --install "${packages[@]}" >"$evidence/sdk-install.log" 2>&1 || {
    tail -n 25 "$evidence/sdk-install.log" >&2
    die "the Android SDK packages above could not be installed (full output in $evidence/sdk-install.log)"
  }
}

device_profile() {
  # A named hardware profile is nicer, but the id list moves between
  # command-line tool revisions, and an unsupported --device is a hard failure
  # in a stage that otherwise works. So: take the first profile this revision
  # knows about, newest first, and let avdmanager use its default profile if
  # none of them are known. avdmanager prints ids as `id: 17 or "pixel"`.
  local tool=$1 want
  for want in ${AVD_DEVICE:-pixel_8 pixel_6 pixel}; do
    if "$tool" list device 2>/dev/null | grep -qF "or \"$want\""; then
      printf '%s' "$want"
      return 0
    fi
  done
}

create_avd() {
  [ -x "$avdmanager" ] || command -v avdmanager >/dev/null 2>&1 || die "no avdmanager under $sdk"
  local tool profile args
  tool=$([ -x "$avdmanager" ] && printf '%s' "$avdmanager" || printf 'avdmanager')
  profile=$(device_profile "$tool")
  args=(--name "$avd" --package "$(system_image)" --force)
  if [ -n "$profile" ]; then
    say "creating avd $avd on $(system_image), device $profile"
    args+=(--device "$profile")
  else
    say "creating avd $avd on $(system_image), default hardware profile (${AVD_DEVICE:-pixel_8} is not a known device id in this command-line tools revision)"
  fi
  printf 'no\n' | "$tool" create avd "${args[@]}" >"$evidence/avd-create.log" 2>&1 || {
    tail -n 25 "$evidence/avd-create.log" >&2
    die "avdmanager could not create the avd (full output in $evidence/avd-create.log)"
  }
  # The emulator resolves an avd by name through its own search path, which is
  # not guaranteed to be where avdmanager just wrote it. Catching that here says
  # "the avd is not where the emulator will look", instead of letting it surface
  # later as an emulator that refuses to boot.
  local bin
  bin=$([ -x "$emulator_bin" ] && printf '%s' "$emulator_bin" || printf 'emulator')
  "$bin" -list-avds 2>/dev/null | grep -qx "$avd" ||
    die "the avd $avd was created but the emulator cannot see it (avdmanager output in $evidence/avd-create.log; avd home: ${ANDROID_AVD_HOME:-$HOME/.android/avd})"
  say "avd $avd visible to the emulator"
}

launch_emulator() {
  local bin
  bin=$([ -x "$emulator_bin" ] && printf '%s' "$emulator_bin" || printf 'emulator')
  say "launching emulator (log: $evidence/emulator.log)"
  nohup "$bin" "@$avd" \
    -no-window -no-audio -no-boot-anim -no-snapshot \
    -gpu swiftshader_indirect -accel on -cores 2 \
    -ports 5554,5555 \
    >>"$evidence/emulator.log" 2>&1 &
  echo $! >"$emulator_pid_file"
}

resolve_serial() {
  local serial
  serial=$("$adb_bin" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')
  [ -n "$serial" ] || die "no emulator device appeared in adb devices"
  printf '%s\n' "$serial" >"$evidence/device-serial"
  say "device serial $serial"
}

wait_for_boot() {
  local serial deadline
  serial=$(cat "$evidence/device-serial")
  deadline=$((SECONDS + boot_timeout))
  say "waiting for boot (limit ${boot_timeout}s)"
  while [ "$SECONDS" -lt "$deadline" ]; do
    local completed
    completed=$("$adb_bin" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
    if [ "$completed" = "1" ]; then
      "$adb_bin" -s "$serial" shell settings put global window_animation_scale 0 >/dev/null 2>&1 || true
      "$adb_bin" -s "$serial" shell settings put global transition_animation_scale 0 >/dev/null 2>&1 || true
      "$adb_bin" -s "$serial" shell settings put global animator_duration_scale 0 >/dev/null 2>&1 || true
      say "booted in ${SECONDS}s"
      return 0
    fi
    sleep 5
  done
  die "emulator did not boot within ${boot_timeout}s"
}

capture_logcat() {
  local serial
  serial=$(cat "$evidence/device-serial")
  "$adb_bin" -s "$serial" logcat -v time >"$evidence/logcat.txt" 2>&1 &
  echo $! >"$logcat_pid_file"
}

mkdir -p "$evidence"

if [ "$mode" = teardown ]; then
  stop_logcat
  stop_emulator
  list_evidence
  exit 0
fi

preflight
install_packages
create_avd
launch_emulator
resolve_serial
wait_for_boot
capture_logcat

say "device ready: $(cat "$evidence/device-serial")"
cat "$evidence/device-serial"
