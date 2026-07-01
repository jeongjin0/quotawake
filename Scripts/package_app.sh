#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-debug}"
case "${CONFIGURATION}" in
  debug|release) ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 64
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="QuotaWake"
APP_ICON_NAME="QuotaWake"
APP_ICON_FILE="${APP_ICON_NAME}.icns"
APP_DIR="${ROOT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
VERSION_ENV="${ROOT_DIR}/version.env"
ENV_VERSION="${VERSION:-}"
ENV_RELEASES_LATEST_API_URL="${RELEASES_LATEST_API_URL:-}"

if [[ -f "${VERSION_ENV}" ]]; then
  source "${VERSION_ENV}"
fi

if [[ -n "${ENV_VERSION}" ]]; then
  VERSION="${ENV_VERSION}"
fi
if [[ -n "${ENV_RELEASES_LATEST_API_URL}" ]]; then
  RELEASES_LATEST_API_URL="${ENV_RELEASES_LATEST_API_URL}"
fi
VERSION="${VERSION:-0.0.0}"
RELEASES_LATEST_API_URL="${RELEASES_LATEST_API_URL:-}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid VERSION '${VERSION}': expected MAJOR.MINOR.PATCH, for example 0.0.0" >&2
  exit 65
fi

cd "${ROOT_DIR}"
swift build -c "${CONFIGURATION}"
BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod 755 "${MACOS_DIR}/${APP_NAME}"
if [[ -d "${ROOT_DIR}/Resources" ]]; then
  ditto "${ROOT_DIR}/Resources" "${RESOURCES_DIR}"
fi
if [[ ! -s "${RESOURCES_DIR}/${APP_ICON_FILE}" ]]; then
  echo "Missing app icon resource: ${RESOURCES_DIR}/${APP_ICON_FILE}" >&2
  exit 66
fi

UPDATE_METADATA=""
if [[ -n "${RELEASES_LATEST_API_URL}" ]]; then
  UPDATE_METADATA="  <key>QuotaWakeReleasesLatestAPIURL</key>
  <string>${RELEASES_LATEST_API_URL}</string>"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.jeongjin.quotawake.menubar</string>
  <key>CFBundleIconFile</key>
  <string>${APP_ICON_NAME}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
${UPDATE_METADATA}
</dict>
</plist>
PLIST

plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null
if [[ "${CONFIGURATION}" == "debug" ]]; then
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null
fi
echo "Created ${APP_DIR}"
