#!/usr/bin/env bash
# Toolchain pin check for CI (add-ci-acceptance-gate).
#
# The workflow declares toolchain versions in its env block, and
# .devcontainer/Dockerfile declares the same versions for the dev image. Nothing
# in CI rebuilds that image, so the only defence against the two definitions
# drifting apart is this check.
#
#   ci-pins.sh declared   the workflow's declared versions appear in the dev
#                         image definition; needs only the checkout, so it runs
#                         before anything is installed
#   ci-pins.sh running    the live flutter and java report those versions
#   ci-pins.sh device     the device stage installed the declared Android
#                         packages; only meaningful after provisioning
#
# Each failure names the offending version, because the answer to a failed pin
# check is "which definition moved", and that is the whole question.
set -euo pipefail

mode=${1:-}
dockerfile=${NATTER_DOCKERFILE:-.devcontainer/Dockerfile}

flutter_version=${FLUTTER_VERSION:?FLUTTER_VERSION must be set}
java_version=${JAVA_VERSION:?JAVA_VERSION must be set}
android_platform=${ANDROID_PLATFORM:?ANDROID_PLATFORM must be set}
build_tools=${ANDROID_BUILD_TOOLS:?ANDROID_BUILD_TOOLS must be set}

say() { printf 'Check toolchain pins: %s\n' "$*" >&2; }
die() { say "$*"; exit 1; }

grep_dockerfile() {
  local needle=$1
  grep -qF -- "$needle" "$dockerfile" || die "declared pin \"$needle\" does not appear in $dockerfile: the CI pin and the dev image pin have drifted apart"
  say "ok: $needle"
}

installed() {
  local needle=$1 manager=${SDKMANAGER:-}
  if [ -z "$manager" ]; then
    if command -v sdkmanager >/dev/null 2>&1; then
      manager=sdkmanager
    else
      manager="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}/cmdline-tools/latest/bin/sdkmanager"
    fi
  fi
  [ -x "$manager" ] || [ "$manager" = sdkmanager ] || die "no sdkmanager to check installed packages with (looked at $manager)"
  "$manager" --list_installed 2>/dev/null | grep -qF -- "$needle" ||
    die "the device stage did not install $needle"
  say "ok: $needle"
}

case "$mode" in
  declared)
    [ -f "$dockerfile" ] || die "no $dockerfile to check the declared pins against"
    grep_dockerfile "Flutter $flutter_version"
    grep_dockerfile "\"$java_version."
    grep_dockerfile "platforms;android-$android_platform"
    grep_dockerfile "build-tools;$build_tools"
    ;;
  running)
    flutter --version | grep -F "Flutter $flutter_version" >/dev/null ||
      die "this build is running a flutter other than $flutter_version: $(flutter --version 2>/dev/null | head -n1)"
    say "ok: Flutter $flutter_version"
    java -version 2>&1 | grep -F "\"$java_version." >/dev/null ||
      die "this build is running a java other than $java_version: $(java -version 2>&1 | head -n1)"
    say "ok: Java $java_version"
    ;;
  device)
    installed "platforms;android-$android_platform"
    installed "build-tools;$build_tools"
    installed "platform-tools"
    ;;
  *)
    die "unknown mode '$mode' (expected declared, running, or device)"
    ;;
esac
