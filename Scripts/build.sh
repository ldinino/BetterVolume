#!/usr/bin/env bash
#
# The repo lives on an SMB share, which breaks SwiftPM's index store (atomic renames) and
# corrupts the Clang module cache. Everything is therefore built into a scratch directory on
# the local disk. Always build through this script.
#
# Usage:
#   Scripts/build.sh build [debug|release]
#   Scripts/build.sh test
#   Scripts/build.sh run
#   Scripts/build.sh app        # assemble and sign BetterVolume.app
#   Scripts/build.sh install    # app + copy into /Applications
#   Scripts/build.sh clean

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="${BETTERVOLUME_SCRATCH:-$HOME/Library/Caches/BetterVolume-build}"
SWIFT_FLAGS=(--package-path "$REPO_ROOT" --scratch-path "$SCRATCH" --disable-index-store)
APP_NAME="BetterVolume"
BUNDLE_ID="com.bettervolume.BetterVolume"
ICON_NAME="AppIcon"
COPYRIGHT="Copyright © 2026 Luciano DiNino. MIT licensed. App icon from the Oxygen icon theme by the Oxygen Team, LGPL v3 — see THIRD-PARTY-NOTICES.md."
# Also on local disk: an SMB share attaches Finder metadata that codesign rejects.
DIST_DIR="${BETTERVOLUME_DIST:-$SCRATCH/dist}"

command="${1:-build}"
configuration="${2:-debug}"

binary_path() {
    swift build "${SWIFT_FLAGS[@]}" -c "$1" --show-bin-path
}

build_app() {
    swift build "${SWIFT_FLAGS[@]}" -c release
    local bin app identity
    bin="$(binary_path release)/$APP_NAME"
    app="$DIST_DIR/$APP_NAME.app"

    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$bin" "$app/Contents/MacOS/$APP_NAME"
    cp "$REPO_ROOT/Resources/$ICON_NAME.icns" "$app/Contents/Resources/$ICON_NAME.icns"
    # LGPL: ship the icon's attribution and licence notice alongside the binary.
    cp "$REPO_ROOT/THIRD-PARTY-NOTICES.md" "$app/Contents/Resources/THIRD-PARTY-NOTICES.md"
    cp "$REPO_ROOT/LICENSE" "$app/Contents/Resources/LICENSE"

    cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>$ICON_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>NSHumanReadableCopyright</key><string>$COPYRIGHT</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

    xattr -cr "$app"

    # Prefer an installed "Developer ID Application" certificate so every rebuild carries the
    # same signature — macOS then keeps granted permissions and the login-item registration
    # instead of treating each build as a new app (which ad-hoc signing causes). Falls back to
    # ad-hoc when no such certificate exists; BETTERVOLUME_SIGN_IDENTITY overrides both.
    identity="${BETTERVOLUME_SIGN_IDENTITY:-}"
    if [[ -z "$identity" ]]; then
        identity="$(security find-identity -v -p codesigning |
            sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' | head -1)"
    fi
    identity="${identity:--}"
    if [[ "$identity" == "-" ]]; then
        codesign --force --sign - "$app"
    else
        codesign --force --options runtime --timestamp --sign "$identity" "$app"
    fi
    codesign --verify --strict --verbose=1 "$app"
    echo "Built $app (identity: $identity)"
}

case "$command" in
build)
    swift build "${SWIFT_FLAGS[@]}" -c "$configuration"
    ;;

test)
    swift test "${SWIFT_FLAGS[@]}"
    ;;

run)
    swift build "${SWIFT_FLAGS[@]}" -c debug
    exec "$(binary_path debug)/$APP_NAME"
    ;;

app)
    build_app
    ;;

install)
    build_app
    target="/Applications/$APP_NAME.app"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "$target"
    ditto "$DIST_DIR/$APP_NAME.app" "$target"
    # Nudge Finder/Dock to re-read the icon rather than serve a stale cached one.
    touch "$target"
    echo "Installed $target"
    ;;

clean)
    rm -rf "$SCRATCH"
    echo "Cleaned $SCRATCH"
    ;;

*)
    echo "Unknown command: $command" >&2
    exit 2
    ;;
esac
