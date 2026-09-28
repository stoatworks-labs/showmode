#!/bin/bash
# Local release: the universal app, notarised and stapled, inside a signed and
# notarised DMG at dist/release/showmode-<version>-macos-universal.dmg.
#
# Local by design: the Developer ID key never leaves this Mac, and there is no
# other platform to build. Then:
#   gh release create v<version> dist/release/*.dmg --notes-file <notes>
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
VERSION="$(sed -n 's/^let appVersion = "\(.*\)"/\1/p' Sources/ShowMode/Version.swift)"
APP="dist/Show Mode.app"

# release-lib.sh is vendored from stoatworks-backend/release — edit it there.
source scripts/release-lib.sh
rl_init "Show Mode" showmode "$VERSION" com.stoatworks.showmode "$PWD/dist/release"
rl_mac_sign_ready || { echo "no Developer ID configured on this Mac" >&2; exit 1; }

# Both slices, or an Intel Mac downloads an app it cannot run.
archs="$(lipo -archs "$APP/Contents/MacOS/ShowMode")"
[[ "$archs" == *x86_64* && "$archs" == *arm64* ]] || { echo "not universal: $archs" >&2; exit 1; }

rl_mac_notarize "$APP"

stage="$(mktemp -d)"
ditto "$APP" "$stage/Show Mode.app"
rl_dmg macos-universal "$stage" --app "Show Mode.app"
DMG="$RL_OUT/showmode-$VERSION-macos-universal.dmg"
rl_mac_notarize "$DMG"
rm -rf "$stage"

spctl -a -vv -t install "$DMG"
rl_summary
