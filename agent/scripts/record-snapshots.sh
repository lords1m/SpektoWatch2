#!/usr/bin/env bash
# Re-record Point-Free snapshot baselines for the Snapshots test plan.
# Usage: ./agent/scripts/record-snapshots.sh [destination]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${1:-platform=iOS Simulator,name=iPhone 15 Pro}"

export RECORD_SNAPSHOTS=YES

xcodebuild test \
  -project "$ROOT/SpektoWatch2.xcodeproj" \
  -scheme SpektoWatch2 \
  -testPlan snapshots \
  -destination "$DEST" \
  -resultBundlePath "$ROOT/TestResults/Snapshots-record.xcresult" \
  CODE_SIGNING_ALLOWED=NO

echo "Baselines written under SpektoWatch2Tests/__Snapshots__ — review and commit."
