#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Execute este script num Mac com Xcode instalado.'; exit 1; }
mkdir -p docs/snapshots
SIMULATOR_ID="${SIMULATOR_ID:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for devices in d["devices"].values() for v in devices if "iPhone" in v["name"]))')}"
RESULT_PATH="$(mktemp -d -t ciranda-validation)/Tests.xcresult"
xcodebuild -project Ciranda.xcodeproj -scheme Ciranda -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath build/DerivedData -resultBundlePath "$RESULT_PATH" CODE_SIGNING_ALLOWED=NO test
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" build/DerivedData/Build/Products/Debug-iphonesimulator/Ciranda.app
xcrun simctl launch "$SIMULATOR_ID" org.ciranda.prototype
sleep 3
xcrun simctl io "$SIMULATOR_ID" screenshot docs/snapshots/01-teclado.png
printf 'Resultados: %s\nCaptura: docs/snapshots/01-teclado.png\n' "$RESULT_PATH"
