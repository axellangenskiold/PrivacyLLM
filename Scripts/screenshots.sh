#!/usr/bin/env bash
# Capture App Store screenshots (dark + light) on a 6.9" iPhone simulator.
# Drives PrivacyLLMUITests/AppStoreScreenshots; PNGs land in Marketing/screenshots/.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${SIM_NAME:-iPhone 17 Pro Max}"   # 6.9" — the one required iPhone size
SCHEME=PrivacyLLM
PROJECT=PrivacyLLM.xcodeproj
OUT="Marketing/screenshots"
WORK="$(mktemp -d)"

UDID=$(xcrun simctl list devices available | grep -m1 "$SIM_NAME (" | grep -oE '[0-9A-Fa-f-]{36}')
[ -n "$UDID" ] || { echo "No available simulator named '$SIM_NAME'"; exit 1; }
echo "Simulator: $SIM_NAME ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# Marketing status bar: 9:41, full battery/signal (Apple convention).
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 --dataNetwork wifi 2>/dev/null || true

capture() {
  local mode="$1"
  echo "=== $mode ==="
  xcrun simctl ui "$UDID" appearance "$mode"
  local result="$WORK/$mode.xcresult"; rm -rf "$result"
  TEST_RUNNER_APPSTORE_SHOTS=1 xcodebuild test \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -only-testing PrivacyLLMUITests/AppStoreScreenshots \
    -parallel-testing-enabled NO \
    -resultBundlePath "$result" \
    -skipMacroValidation
  local raw="$WORK/${mode}_raw"; rm -rf "$raw"
  xcrun xcresulttool export attachments --path "$result" --output-path "$raw"
  local dest="$OUT/$mode"; rm -rf "$dest"
  python3 Scripts/_rename_shots.py "$raw" "$dest"
}

capture dark
capture light
xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
echo "Done -> $OUT/{dark,light}"
