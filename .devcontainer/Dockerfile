# Natter dev environment: Flutter SDK first, Android toolchain already
# layered in the base image. Every version is pinned by tag and re-checked
# in the verification RUN below, so a base refresh that changes the
# toolchain breaks the build loudly instead of drifting silently.
#
# Provided by ghcr.io/cirruslabs/flutter:3.29.3 (verified below):
#   Flutter 3.29.3, OpenJDK 21.0.6 (JDK 21 per stack rules),
#   Android cmdline-tools 11076708, platforms;android-35,
#   build-tools;35.0.0, platform-tools 35.0.2, git.
# Deliberately absent: emulator (stack rule: on-device testing via
# host-forwarded adb). CI provisions its own throwaway device instead, in
# scripts/ci-emulator.sh, and .github/workflows/ci.yml mirrors the pins above
# in its env block - the workflow's first step fails if the two drift apart.

FROM ghcr.io/cirruslabs/flutter:3.29.3

# Fail the build if any pin moved out from under us.
RUN set -eux; \
    flutter --version | grep -F 'Flutter 3.29.3'; \
    java -version 2>&1 | grep -F '"21.'; \
    sdkmanager --list_installed | grep -F 'platforms;android-35'; \
    sdkmanager --list_installed | grep -F 'build-tools;35.0.0'; \
    sdkmanager --list_installed | grep -F 'platform-tools'; \
    test ! -d /opt/android-sdk-linux/emulator

# Accept all Android SDK licenses so flutter doctor's Android toolchain
# is green out of the box (base image only pre-accepts a subset).
RUN set -eux; \
    yes | sdkmanager --licenses > /dev/null; \
    sdkmanager --list_installed | grep -F 'platforms;android-35'

ENV PUB_CACHE=/root/.pub-cache \
    GRADLE_USER_HOME=/root/.gradle
