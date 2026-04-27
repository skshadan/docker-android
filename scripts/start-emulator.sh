#!/bin/bash

set -e

source ./emulator-monitoring.sh

# The emulator console port.
EMULATOR_CONSOLE_PORT=5554
# The ADB port used to connect to ADB.
ADB_PORT=5555
OPT_MEMORY=${MEMORY:-8192}
OPT_CORES=${CORES:-4}
OPT_SKIP_AUTH=${SKIP_AUTH:-true}
OPT_SNAPSHOT=${SNAPSHOT:-true}
OPT_SCREEN_SIZE=${SCREEN_SIZE:-}
AUTH_FLAG=
SNAPSHOT_FLAGS=()
SCREEN_SIZE_FLAGS=()

function normalize_web_path() {
  local path="${1:-/}"

  if [ -z "$path" ]; then
    path="/"
  fi

  case "$path" in
    /*) ;;
    *) path="/$path" ;;
  esac

  echo "$path"
}

function start_ws_scrcpy() {
  if [ "${SCRCPY_WEB_ENABLED:-false}" != "true" ]; then
    return
  fi

  local web_port="${SCRCPY_WEB_PORT:-8000}"
  local web_path
  web_path=$(normalize_web_path "$SCRCPY_WEB_PATH")
  local public_url="${SCRCPY_WEB_PUBLIC_URL:-http://localhost:${web_port}${web_path}}"
  local config_path="/tmp/ws-scrcpy-config.yaml"

  cat > "$config_path" <<EOF
runGoogTracker: true
announceGoogTracker: true
runApplTracker: false
announceApplTracker: false
server:
  - secure: false
    port: ${web_port}
remoteHostList: []
EOF

  echo "Starting ws-scrcpy web UI ..."
  echo "SCRCPY WEB URL - $public_url"
  write_log "live-url" "$public_url"

  (
    cd /opt/ws-scrcpy/dist
    export WS_SCRCPY_CONFIG="$config_path"
    export WS_SCRCPY_PATHNAME="$web_path"
    export ADB_HOST="${SCRCPY_ADB_HOST:-127.0.0.1}"
    export ADB_PORT="${SCRCPY_ADB_PORT:-5037}"
    node ./index.js
  ) &
}

function wait_for_boot_and_start_ws_scrcpy() {
  wait_for_boot
  start_ws_scrcpy
}

# Start ADB server by listening on all interfaces.
echo "Starting the ADB server ..."
adb -a -P 5037 server nodaemon &

# Detect ip and forward ADB ports from the container's network
# interface to localhost.
LOCAL_IP=$(ip addr list eth0 | grep "inet " | cut -d' ' -f6 | cut -d/ -f1)
socat tcp-listen:"$EMULATOR_CONSOLE_PORT",bind="$LOCAL_IP",fork tcp:127.0.0.1:"$EMULATOR_CONSOLE_PORT" &
socat tcp-listen:"$ADB_PORT",bind="$LOCAL_IP",fork tcp:127.0.0.1:"$ADB_PORT" &

export USER=root

rm -rf /root/.android/avd/running
find "$ANDROID_AVD_HOME" -name "*.lock" -delete 2>/dev/null || true

# Creating the Android Virtual Emulator.
TEST_AVD=$(avdmanager list avd | grep -c "android.avd" || true)
if [ "$TEST_AVD" == "1" ]; then
  echo "Use the exists Android Virtual Emulator ..."
else
  echo "Creating the Android Virtual Emulator ..."
  echo "Using package '$PACKAGE_PATH', ABI '$ABI' and device '$DEVICE_ID' for creating the emulator"
  echo no | avdmanager create avd \
    --force \
    --name android \
    --abi "$ABI" \
    --package "$PACKAGE_PATH" \
    --device "$DEVICE_ID"
fi

if [ "$OPT_SKIP_AUTH" == "true" ]; then
  AUTH_FLAG="-skip-adb-auth"
fi

if [ "$OPT_SNAPSHOT" == "true" ]; then
  SNAPSHOT_FLAGS=(-no-snapshot-save)
else
  SNAPSHOT_FLAGS=(-no-snapshot)
fi

if [ -n "$OPT_SCREEN_SIZE" ]; then
  SCREEN_SIZE_FLAGS=(-skin "$OPT_SCREEN_SIZE")
fi

# If GPU acceleration is enabled, we create a virtual framebuffer
# to be used by the emulator when running with GPU acceleration.
# We also set the GPU mode to `host` to force the emulator to use
# GPU acceleration.
if [ "$GPU_ACCELERATED" == "true" ]; then
  export DISPLAY=":0.0"
  export GPU_MODE="host"
  Xvfb "$DISPLAY" -screen 0 1920x1080x16 -nolisten tcp &
else
  export GPU_MODE="swiftshader_indirect"
fi

# Asynchronously write updates on the standard output
# about the state of the boot sequence.
wait_for_boot_and_start_ws_scrcpy &

# Start the emulator with no audio, no GUI, and no snapshots.
echo "Starting the emulator ..."
echo "OPTIONS:"
echo "SKIP ADB AUTH - $OPT_SKIP_AUTH"
echo "GPU           - $GPU_MODE"
echo "MEMORY        - $OPT_MEMORY"
echo "CORES         - $OPT_CORES"
echo "SNAPSHOT      - $OPT_SNAPSHOT"
echo "SCREEN SIZE   - ${OPT_SCREEN_SIZE:-default}"
emulator \
  -avd android \
  -gpu "$GPU_MODE" \
  -memory "$OPT_MEMORY" \
  -no-boot-anim \
  -no-audio \
  -no-metrics \
  -cores "$OPT_CORES" \
  -ranchu \
  $AUTH_FLAG \
  -no-window \
  "${SCREEN_SIZE_FLAGS[@]}" \
  "${SNAPSHOT_FLAGS[@]}" \
  $EXTRA_FLAGS || update_state "ANDROID_STOPPED"


  # -qemu \
  # -smp 8,sockets=1,cores=4,threads=2,maxcpus=8
