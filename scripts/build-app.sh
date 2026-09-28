#!/bin/sh
# Builds "Slate Bridge.app" into build/ and signs it.
#
#   scripts/build-app.sh            # the first Apple Development identity
#   SIGN_IDENTITY="…" scripts/build-app.sh
#
# Signed with a stable identity (the owner's Personal Team) and the hardened
# runtime, so macOS keeps the Calendars and Contacts permissions across
# rebuilds. Not sandboxed: see docs/PLAN.md, decision 8.
set -eu
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$IDENTITY" ]; then
  echo "No Apple Development signing identity found (security find-identity -v -p codesigning)." >&2
  exit 1
fi

swift build -c release --product SlateBridge
BIN="$(swift build -c release --product SlateBridge --show-bin-path)/SlateBridge"

APP="build/Slate Bridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SlateBridge"
cp Support/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --timestamp=none --options runtime \
  --entitlements Support/SlateBridge.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built and signed: $APP"
