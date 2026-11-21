#!/usr/bin/env bash
# Build a Release copy of Climate Liberator and install it in Applications,
# replacing the old copy, so opening the app from Finder, the Dock, Launchpad or
# Spotlight runs the latest code (Xcode's Run uses a separate Debug build).
#
#   bash scripts/install_macos.sh            # build, verify, install, open
#   SKIP_VERIFY=1 bash scripts/install_macos.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${CLIMATE_BUILD_DIR:-$ROOT/.build/portable-release}"
BUNDLE_ID="com.afnan.ClimateLiberator.ClimateLiberator"
APP_NAME="ClimateLiberator.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ -w /Applications ]]; then DEST_DIR="/Applications"; else DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; fi
TARGET="$DEST_DIR/$APP_NAME"

echo "Building Release (this takes a minute)…"
xcodebuild -project "$ROOT/ClimateLiberatorApp/ClimateLiberator/ClimateLiberator.xcodeproj" \
    -scheme ClimateLiberator -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" -quiet build
APP="$DERIVED/Build/Products/Release/$APP_NAME"
[[ -d "$APP" ]] || { echo "Build product not found: $APP" >&2; exit 1; }

if [[ "${SKIP_VERIFY:-0}" != "1" ]]; then
    /usr/bin/python3 "$ROOT/scripts/verify_portable_app.py" "$APP"
fi

# Quit a running copy (it asks to save unsaved inventories first), then wait for it.
if pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null; then
    echo "Quitting the running copy…"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null || break; sleep 1; done
    if pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null; then
        echo "Climate Liberator is still open. Quit it, then run this script again." >&2
        exit 1
    fi
fi

# Copy beside the old app first, then swap, so a failed copy never leaves you with nothing.
STAGING="$DEST_DIR/.$APP_NAME.installing"
rm -rf "$STAGING"
/usr/bin/ditto "$APP" "$STAGING"
rm -rf "$TARGET"
mv "$STAGING" "$TARGET"
"$LSREGISTER" -f "$TARGET" >/dev/null 2>&1 || true
echo "Installed: $TARGET ($(date '+%Y-%m-%d %H:%M'))"

# Other copies that Finder or Spotlight could still open.
OTHERS="$(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null \
    | grep -v -e "^$TARGET$" -e "/DerivedData/" -e "/.build/" -e "/Build/Products/" || true)"
if [[ -n "$OTHERS" ]]; then
    echo
    echo "Older copies found — delete them so they are not opened by mistake:"
    echo "$OTHERS" | sed 's/^/  /'
fi

open "$TARGET"
