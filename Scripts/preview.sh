#!/usr/bin/env bash
# Record an App Store app-preview video (~20s) by screen-recording the simulator
# while PrivacyLLMUITests/AppStorePreview drives the flow. Output: Marketing/preview/.
# App previews are OPTIONAL; a real-device QuickTime capture looks nicer, but this
# produces an ASC-acceptable clip at the device's native resolution.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 11 Pro Max}"   # 1242 x 2688 — 6.5" app-preview size
MODE="${MODE:-dark}"
SCHEME=PrivacyLLM
PROJECT=PrivacyLLM.xcodeproj
OUT="Marketing/preview"; mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available | grep -m1 "$SIM_NAME (" | grep -oE '[0-9A-Fa-f-]{36}' | head -1)
[ -n "$UDID" ] || { echo "Run Scripts/screenshots.sh first to create the '$SIM_NAME' simulator."; exit 1; }
echo "Simulator: $SIM_NAME ($UDID), appearance: $MODE"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance "$MODE"
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryState discharging --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

# Build first so the recording only covers the actual run.
xcodebuild build-for-testing \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" -skipMacroValidation

VIDEO="$OUT/preview-$MODE.mov"
xcrun simctl io "$UDID" recordVideo --codec hevc --force "$VIDEO" & REC=$!
trap 'kill -INT $REC 2>/dev/null || true' EXIT

TEST_RUNNER_APPSTORE_SHOTS=1 xcodebuild test-without-building \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -only-testing PrivacyLLMUITests/AppStorePreview \
  -parallel-testing-enabled NO -skipMacroValidation

sleep 1
kill -INT $REC 2>/dev/null || true
wait $REC 2>/dev/null || true
trap - EXIT
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
echo "Done -> $VIDEO"
ls -la "$VIDEO"
