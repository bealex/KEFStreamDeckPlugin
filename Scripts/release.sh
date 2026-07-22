#!/usr/bin/env bash
# Builds KEFControlMenu in Release and installs it into ~/Applications, replacing the copy that is there.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../KEFControlMenu"
PROJECT="$PROJECT_DIR/KEFControlMenu.xcodeproj"
SCHEME="KEFControlMenu"
CONFIGURATION="Release"
APP_NAME="KEFControlMenu.app"
BUNDLE_ID="com.lonelybytes.KEFControlMenu"
DESTINATION_DIR="$HOME/Applications"
DESTINATION="$DESTINATION_DIR/$APP_NAME"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -d "$PROJECT" ]] || fail "can't find $PROJECT"
[[ -d "$DESTINATION_DIR" ]] || fail "can't find $DESTINATION_DIR"

BUILD_LOG="$(mktemp -t kefcontrol-release)"

echo "==> Building $SCHEME ($CONFIGURATION)"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" build >"$BUILD_LOG" 2>&1; then
  grep -E "error:" "$BUILD_LOG" | head -20 >&2 || true
  fail "build failed, full log in $BUILD_LOG"
fi
rm -f "$BUILD_LOG"

build_settings() {
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null |
    awk -v key="$1" '$1 == key { print $3 }'
}

PRODUCTS_DIR="$(build_settings BUILT_PRODUCTS_DIR)"
[[ -n "$PRODUCTS_DIR" ]] || fail "can't work out the build products directory"

BUILT_APP="$PRODUCTS_DIR/$APP_NAME"
[[ -d "$BUILT_APP" ]] || fail "build produced no app at $BUILT_APP"

codesign --verify --deep --strict "$BUILT_APP" || fail "the built app is not signed correctly"

WAS_RUNNING=false
if pgrep -f "$DESTINATION/Contents/MacOS/" >/dev/null 2>&1; then
  WAS_RUNNING=true
  echo "==> Quitting the running app"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  # Menu bar apps do not always answer the Apple event, so make sure the process is really gone.
  for _ in {1..10}; do
    pgrep -f "$DESTINATION/Contents/MacOS/" >/dev/null 2>&1 || break
    sleep 0.5
  done
  pkill -f "$DESTINATION/Contents/MacOS/" >/dev/null 2>&1 || true
fi

echo "==> Installing into $DESTINATION_DIR"
rm -rf "$DESTINATION"
cp -R "$BUILT_APP" "$DESTINATION"

VERSION="$(defaults read "$DESTINATION/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
BUILD="$(defaults read "$DESTINATION/Contents/Info" CFBundleVersion 2>/dev/null || echo "?")"
echo "==> Installed $APP_NAME $VERSION ($BUILD)"

if [[ "$WAS_RUNNING" == true ]]; then
  echo "==> Relaunching"
  open "$DESTINATION"
fi
