#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${CLIMATE_BUILD_DIR:-$ROOT/.build/portable-release}"
DEST="${CLIMATE_RELEASE_DIR:-$ROOT/.build/releases}"
mkdir -p "$DEST"
xcodebuild -project "$ROOT/ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj" \
    -scheme ClimateLiberator -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" build
APP="$DERIVED/Build/Products/Release/ClimateLiberator.app"
/usr/bin/python3 "$ROOT/scripts/verify_portable_app.py" "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$DEST/Climate-Liberator-$(uname -m).zip"
echo "Package: $DEST/Climate-Liberator-$(uname -m).zip"
echo "Internal ad-hoc build unless a Developer ID signing identity was supplied. Not notarized."
