#!/bin/sh
# Builds "Slate Bridge.app" into build/ and signs it.
#
#   scripts/build-app.sh            # for this Mac: the first Apple Development identity
#   SIGN_IDENTITY="…" scripts/build-app.sh
#   scripts/build-app.sh --release  # for GitHub: ad-hoc signed, zipped
#
# For this Mac it is signed with a stable identity (the owner's Personal
# Team) and the hardened runtime, so macOS keeps the Calendars and Contacts
# permissions across rebuilds. A development certificate is named after its
# Apple ID, so --release signs ad hoc instead: no identity in it, for
# attaching to a GitHub release. Not sandboxed: see docs/PLAN.md, decision 8.
set -eu
cd "$(dirname "$0")/.."

RELEASE=no
[ "${1:-}" = "--release" ] && RELEASE=yes

if [ "$RELEASE" = yes ]; then
  IDENTITY="-"
else
  IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
  if [ -z "$IDENTITY" ]; then
    echo "No Apple Development signing identity found (security find-identity -v -p codesigning)." >&2
    echo "Use --release for an ad-hoc signed build." >&2
    exit 1
  fi
fi

# Source paths are compiled into the binary (for Swift's error messages and
# debug info); map this checkout to "." so a build carries no one's home folder.
MAP="-Xswiftc -file-prefix-map -Xswiftc $PWD=. -Xcc -ffile-prefix-map=$PWD=."
# shellcheck disable=SC2086
swift build -c release --product SlateBridge $MAP
# shellcheck disable=SC2086
BIN="$(swift build -c release --product SlateBridge $MAP --show-bin-path)/SlateBridge"

APP="build/Slate Bridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SlateBridge"
# The symbol table's debug entries name the object files by their full
# path; an app has no use for them.
strip -S -x "$APP/Contents/MacOS/SlateBridge"
cp Support/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The icon, drawn from source each build (scripts/make-icon.swift).
rm -rf build/AppIcon.iconset
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --timestamp=none --options runtime \
  --entitlements Support/SlateBridge.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
# Finder caches icons by bundle; a touch makes it look again.
touch "$APP"
echo "Built and signed: $APP"

if [ "$RELEASE" = yes ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)"
  ZIP="build/Slate-Bridge-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "Zipped for a release: $ZIP"
fi
