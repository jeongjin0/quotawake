#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_ENV="${ROOT_DIR}/version.env"
ENV_VERSION="${VERSION:-}"
APP_PATH="${ROOT_DIR}/QuotaWake.app"
OUTPUT_PATH=""
CAPTURE_DIR=""
DRY_RUN=0
VOLUME_NAME="QuotaWake"

if [[ -f "${VERSION_ENV}" ]]; then
  source "${VERSION_ENV}"
fi
if [[ -n "${ENV_VERSION}" ]]; then
  VERSION="${ENV_VERSION}"
fi
VERSION="${VERSION:-0.0.0}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid VERSION '${VERSION}': expected MAJOR.MINOR.PATCH, for example 0.0.0" >&2
  exit 65
fi

OUTPUT_PATH="${ROOT_DIR}/dist/QuotaWake-${VERSION}.dmg"

usage() {
  cat <<'EOF'
Usage: Scripts/create_dmg.sh [--app <path>] [--output <path>] [--capture-dir <path>] [--dry-run]
EOF
}

usage_error() {
  echo "Error: $1" >&2
  usage >&2
  exit 64
}

require_value() {
  local option="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
    usage_error "${option} requires a value."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      require_value "$@"
      APP_PATH="$2"
      shift 2
      ;;
    --output)
      require_value "$@"
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --capture-dir)
      require_value "$@"
      CAPTURE_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage_error "Unknown option: $1"
      ;;
  esac
done

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "VERSION=${VERSION}"
  echo "DMG output: ${OUTPUT_PATH}"
  echo "Volume name: ${VOLUME_NAME}"
  echo "Staging contents: QuotaWake.app, Applications symlink, .background/background.png"
  echo "Finder presentation: bounds 160,120,760,500; icon size 128; text size 16"
  echo "Release gate: final DMG Finder presentation is measured by Scripts/verify_dmg_presentation.sh"
  exit 0
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Missing app bundle: ${APP_PATH}" >&2
  exit 66
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quotawake-dmg.XXXXXX")"
STAGE_DIR="${WORK_DIR}/stage"
RW_DMG="${WORK_DIR}/quotawake-rw.dmg"
COMPRESSED_DMG="${WORK_DIR}/$(basename "${OUTPUT_PATH}")"
MOUNT_POINT=""

cleanup() {
  if [[ -n "${MOUNT_POINT}" && -d "${MOUNT_POINT}" ]]; then
    hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
  fi
  hdiutil detach "/Volumes/${VOLUME_NAME}" >/dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

create_background() {
  local icon_png="${WORK_DIR}/background-icon.png"
  local seed_png="${WORK_DIR}/background-seed.png"
  mkdir -p "${STAGE_DIR}/.background"
  sips -s format png "${ROOT_DIR}/Resources/QuotaWake.icns" --out "${icon_png}" >/dev/null
  sips --cropToHeightWidth 1 1 "${icon_png}" --out "${seed_png}" >/dev/null
  sips --padToHeightWidth 380 600 --padColor F7F4EF "${seed_png}" --out "${STAGE_DIR}/.background/background.png" >/dev/null
}

mount_readwrite_dmg() {
  local attach_output
  hdiutil detach "/Volumes/${VOLUME_NAME}" >/dev/null 2>&1 || true
  attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}")"
  MOUNT_POINT="$(awk -v volume="/Volumes/${VOLUME_NAME}" '$0 ~ volume { print substr($0, index($0, volume)); exit }' <<<"${attach_output}")"
  if [[ -z "${MOUNT_POINT}" || ! -d "${MOUNT_POINT}" ]]; then
    echo "Failed to mount DMG at /Volumes/${VOLUME_NAME}" >&2
    echo "${attach_output}" >&2
    exit 70
  fi
}

apply_finder_presentation() {
  osascript <<'OSA'
tell application "Finder"
  activate
  set targetDisk to disk "QuotaWake"
  open targetDisk
  delay 1
  set w to container window of targetDisk
  set current view of w to icon view
  set toolbar visible of w to false
  set statusbar visible of w to false
  set bounds of w to {160, 120, 760, 500}
  set arrangement of icon view options of w to not arranged
  set icon size of icon view options of w to 128
  set text size of icon view options of w to 16
  try
    set background picture of icon view options of w to file "QuotaWake:.background:background.png"
  end try
  set position of item "QuotaWake.app" of w to {180, 170}
  set position of item "Applications" of w to {480, 170}
  update targetDisk without registering applications
  delay 3
end tell
OSA
  sync
  sleep 1
}

mkdir -p "${STAGE_DIR}" "$(dirname "${OUTPUT_PATH}")"
ditto "${APP_PATH}" "${STAGE_DIR}/QuotaWake.app"
ln -s /Applications "${STAGE_DIR}/Applications"
create_background

rm -f "${OUTPUT_PATH}"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -fs HFS+ \
  -fsargs '-c c=64,a=16,e=16' \
  -format UDRW \
  -size 32m \
  "${RW_DMG}" >/dev/null
mount_readwrite_dmg
apply_finder_presentation
hdiutil detach "${MOUNT_POINT}" >/dev/null
MOUNT_POINT=""
hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${COMPRESSED_DMG}" >/dev/null
cp "${COMPRESSED_DMG}" "${OUTPUT_PATH}"
verify_args=(--dmg "${OUTPUT_PATH}")
if [[ -n "${CAPTURE_DIR}" ]]; then
  verify_args+=(--capture-dir "${CAPTURE_DIR}")
fi
./Scripts/verify_dmg_presentation.sh "${verify_args[@]}"

if [[ -n "${CAPTURE_DIR}" ]]; then
  mkdir -p "${CAPTURE_DIR}"
  {
    echo "volume=${VOLUME_NAME}"
    echo "output=${OUTPUT_PATH}"
    echo "contents=QuotaWake.app,Applications,.background/background.png"
    echo "finder_presentation_applied_by_script=true"
    echo "finder_presentation_measured_by_script=true"
    echo "release_gate=Scripts/verify_dmg_presentation.sh"
  } > "${CAPTURE_DIR}/dmg-build-evidence.txt"
fi

shasum -a 256 "${OUTPUT_PATH}"
echo "Created ${OUTPUT_PATH}"
