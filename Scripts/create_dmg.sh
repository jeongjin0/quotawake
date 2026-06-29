#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_ENV="${ROOT_DIR}/version.env"
ENV_VERSION="${VERSION:-}"
APP_PATH="${ROOT_DIR}/QuotaWake.app"
OUTPUT_PATH=""
CAPTURE_DIR=""
DRY_RUN=0

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
  echo "Volume name: QuotaWake"
  echo "Staging contents: QuotaWake.app, Applications symlink"
  echo "Finder presentation: not applied or measured by this script"
  echo "Release gate: mount the final DMG and record Finder measurements separately"
  exit 0
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Missing app bundle: ${APP_PATH}" >&2
  exit 66
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quotawake-dmg.XXXXXX")"
STAGE_DIR="${WORK_DIR}/stage"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${STAGE_DIR}" "$(dirname "${OUTPUT_PATH}")"
ditto "${APP_PATH}" "${STAGE_DIR}/QuotaWake.app"
ln -s /Applications "${STAGE_DIR}/Applications"

rm -f "${OUTPUT_PATH}"
hdiutil create \
  -volname "QuotaWake" \
  -srcfolder "${STAGE_DIR}" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${OUTPUT_PATH}" >/dev/null

if [[ -n "${CAPTURE_DIR}" ]]; then
  mkdir -p "${CAPTURE_DIR}"
  {
    echo "volume=QuotaWake"
    echo "output=${OUTPUT_PATH}"
    echo "contents=QuotaWake.app,Applications"
    echo "finder_presentation_applied_by_script=false"
    echo "finder_presentation_measured_by_script=false"
    echo "release_gate=mount the final DMG and record Finder window measurements separately"
  } > "${CAPTURE_DIR}/dmg-build-evidence.txt"
  {
    echo "finder_presentation_applied_by_script=false"
    echo "finder_presentation_measured_by_script=false"
    echo "manual_measurement_required=true"
    echo "source=Scripts/create_dmg.sh"
  } > "${CAPTURE_DIR}/finder-presentation.txt"
fi

shasum -a 256 "${OUTPUT_PATH}"
echo "Created ${OUTPUT_PATH}"
