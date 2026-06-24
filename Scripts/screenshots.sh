#!/usr/bin/env bash
# Capture App Store screenshots (dark + light) on a 6.9" iPhone simulator.
# Drives PrivacyLLMUITests/AppStoreScreenshots; PNGs land in Marketing/screenshots/.
set -euo pipefail
cd "$(dirname "$0")/.."

# iPhone 11 Pro Max = 1242 x 2688, the 6.5" set App Store Connect asks for.
SIM_NAME="${SIM_NAME:-iPhone 11 Pro Max}"
SCHEME=PrivacyLLM
PROJECT=PrivacyLLM.xcodeproj
OUT="Marketing/screenshots"
WORK="$(mktemp -d)"

# `|| true`: a no-match grep is expected (device may not exist yet) and must not
# trip `set -e`.
UDID=$(xcrun simctl list devices available | grep -m1 "$SIM_NAME (" | grep -oE '[0-9A-Fa-f-]{36}' | head -1 || true)
if [ -z "$UDID" ]; then
  # Any of these produces an App Store 6.5" size: 1242x2688 (Pro Max / Xs Max)
  # or 1284x2778 (Plus). Pick the first device type that's installed.
  DT=""
  for cand in "$SIM_NAME" "iPhone 11 Pro Max" "iPhone Xs Max" "iPhone 14 Plus" "iPhone 13 Pro Max" "iPhone 12 Pro Max" "iPhone 15 Plus"; do
    DT=$(xcrun simctl list devicetypes | grep -m1 "$cand (" | grep -oE 'com\.apple[^)]*' || true)
    if [ -n "$DT" ]; then SIM_NAME="$cand"; break; fi
  done
  [ -n "$DT" ] || { echo "No 6.5\" device type installed"; exit 1; }
  RT=$(xcrun simctl list runtimes | grep -E 'iOS .* \(' | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | sort -V | tail -1 || true)
  [ -n "$RT" ] || { echo "No iOS runtime installed"; exit 1; }
  echo "Creating '$SIM_NAME'..."
  UDID=$(xcrun simctl create "$SIM_NAME" "$DT" "$RT")
fi
echo "Simulator: $SIM_NAME ($UDID)"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# Force English-only locale + a single English keyboard, then respring. A fresh
# sim inherits the Mac's languages; with two keyboard languages iOS shows a
# one-time "Type in two languages" intro and non-English predictions that land
# in the shots. (|| true: best-effort, never abort the run.)
xcrun simctl spawn "$UDID" defaults write "Apple Global Domain" AppleLanguages -array "en-US" 2>/dev/null || true
xcrun simctl spawn "$UDID" defaults write "Apple Global Domain" AppleLocale -string "en_US" 2>/dev/null || true
xcrun simctl spawn "$UDID" defaults write -g AppleKeyboards -array "en_US@hw=US;sw=QWERTY" 2>/dev/null || true
xcrun simctl shutdown "$UDID" 2>/dev/null || true
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# Marketing status bar: 9:41, full battery/signal (Apple convention).
xcrun simctl status_bar "$UDID" override \
  --time "9:41" --batteryState discharging --batteryLevel 100 \
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
