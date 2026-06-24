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

RAW="$OUT/.raw-$MODE.mov"   # kept so the trim can be re-run without re-recording
xcrun simctl io "$UDID" recordVideo --codec hevc --force "$RAW" & REC=$!
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

# Native recording is 1242x2688; the App Store 6.5" preview slot wants 886x1920.
# The XCUITest runner shows ~15s of home screen up front, and the app flow runs
# at the END (recording stops right after it), so take the LAST 24s with -sseof.
# Downscale (same aspect), H.264, 30fps, with a silent stereo track (some ASC
# checks reject previews that carry no audio track).
VIDEO="$OUT/preview-${MODE}-886x1920.mov"
# XCUITest tears the app down at test end, leaving a variable-length home-screen
# tail before the recording stops. That dark-chat -> bright-home switch is a big
# scene change, so anchor the clip's end just before the LAST large scene change
# and take the ~20s before it (robust to runner-startup/teardown jitter).
END=$(ffprobe -v error -f lavfi -i "movie=${RAW},select=gt(scene\,0.3)" \
  -show_entries frame=pts_time -of csv=p=0 2>/dev/null | tail -1)
if [ -n "$END" ]; then
  ENDTRIM=$(echo "$END - 0.4" | bc -l)
  # ~17s window: skips the post-send model-load + keyboard-dismiss opening, ends
  # just before teardown. Long enough (>15s) and well under 30s.
  START=$(echo "s=$ENDTRIM-16.6; if (s<0) 0 else s" | bc -l)
  DUR=$(echo "$ENDTRIM - $START" | bc -l)
  SEEK=(-ss "$START" -t "$DUR")
  echo "trim: scene-anchored [$START, $ENDTRIM]"
else
  SEEK=(-sseof -33 -t 22)
  echo "trim: fallback (no scene change detected)"
fi
ffmpeg -y "${SEEK[@]}" -i "$RAW" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -vf "scale=886:1920:flags=lanczos,fps=30,format=yuv420p" \
  -map 0:v:0 -map 1:a:0 -shortest \
  -c:v libx264 -profile:v high -crf 20 -c:a aac -b:a 128k \
  -movflags +faststart "$VIDEO"
echo "Done -> $VIDEO"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$VIDEO" 2>/dev/null
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$VIDEO" 2>/dev/null
ls -la "$VIDEO"
