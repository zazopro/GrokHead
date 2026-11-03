#!/usr/bin/env bash
set -euo pipefail

APP_NAME="GrokHead"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DIST_DIR="dist"

echo "==> Building ${APP_NAME} (Pure AppKit + Core Animation, Command Line Tools compatible)..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"

echo "==> Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}" "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${DIST_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "GrokHead/Info.plist" "${CONTENTS_DIR}/Info.plist"

echo "==> Building AppIcon.icns..."
ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz GrokHead/AppIcon-1024.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) GrokHead/AppIcon-1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "${RESOURCES_DIR}/AppIcon.icns"

echo "==> Ad-hoc signing ${APP_BUNDLE}..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Packaging GitHub Release archive ${DIST_DIR}/${APP_BUNDLE}.zip..."
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${DIST_DIR}/${APP_BUNDLE}.zip"

mkdir -p ~/Downloads/grokhead/archive

echo ""
echo "Done:"
echo "  App:     $(pwd)/${APP_BUNDLE}"
echo "  Release: $(pwd)/${DIST_DIR}/${APP_BUNDLE}.zip"
echo ""
echo "Launch: open ${APP_BUNDLE}"
