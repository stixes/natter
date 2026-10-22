#!/bin/sh
# Select a Docker-compatible container engine for the devcontainer CLI.
# Usage:  . scripts/with-container-env.sh
#
# Preference order:
#   1. Docker, if a daemon responds.
#   2. Podman via its Docker-compatible API socket, plus a docker->podman
#      shim on PATH (the devcontainer CLI spawns a `docker` binary even
#      when DOCKER_HOST points elsewhere).
# Nothing below branches on the engine; devcontainer artifacts are
# engine-agnostic.

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "container engine: docker (native daemon)"
elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    if [ ! -S "$runtime_dir/podman/podman.sock" ]; then
        if command -v systemctl >/dev/null 2>&1 && systemctl --user start podman.socket; then
            :
        else
            echo "ERROR: podman found but its API socket is unavailable." >&2
            echo "Start it with: systemctl --user start podman.socket" >&2
            return 1 2>/dev/null || exit 1
        fi
    fi
    DOCKER_HOST="unix://$runtime_dir/podman/podman.sock"
    export DOCKER_HOST
    helper_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)
    PATH="$helper_dir/podman-shim:$PATH"
    export PATH
    echo "container engine: podman via Docker-compatible API ($DOCKER_HOST)"
else
    echo "ERROR: no container engine found (tried docker, podman)." >&2
    return 1 2>/dev/null || exit 1
fi
