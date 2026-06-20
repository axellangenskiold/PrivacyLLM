#!/usr/bin/env bash
# Picks an available iPhone simulator and exposes its UDID.
#
# Usage: pick-simulator.sh [iOS-major-version]
#   With no argument, selects the newest available iPhone runtime.
#   With e.g. "18", restricts to iOS 18.x (used for the deployment-floor job).
#
# Prints the chosen UDID and, when running under GitHub Actions, appends
# `udid=<udid>` to $GITHUB_OUTPUT. Exits non-zero if nothing matches so the
# caller can decide whether to install a runtime.
set -euo pipefail

MAJOR="${1:-}"

UDID="$(
  xcrun simctl list devices available --json | MAJOR="$MAJOR" python3 -c '
import json, os, re, sys

major = os.environ.get("MAJOR", "")
devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devs in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    if major and str(version[0]) != major:
        continue
    for device in devs:
        if device.get("isAvailable") and "iPhone" in device["name"]:
            candidates.append((version, device["udid"]))
candidates.sort(reverse=True)
if candidates:
    print(candidates[0][1])
'
)"

if [ -z "${UDID}" ]; then
  echo "No available iPhone simulator${MAJOR:+ for iOS ${MAJOR}.x}." >&2
  exit 1
fi

echo "Selected simulator ${UDID}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "udid=${UDID}" >> "${GITHUB_OUTPUT}"
fi
