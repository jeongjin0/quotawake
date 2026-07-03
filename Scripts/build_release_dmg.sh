#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_ENV="${ROOT_DIR}/version.env"
LOCAL_ENV="${ROOT_DIR}/.release.local.env"
ENV_VERSION="${VERSION:-}"
CONFIGURATION="release"
CAPTURE_DIR=""
OUTPUT_PATH=""
IDENTITY="${QUOTAWAKE_DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${QUOTAWAKE_NOTARY_PROFILE:-}"
SKIP_TESTS=0
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: Scripts/build_release_dmg.sh [options]

Build the release app, Developer ID sign it, create the public DMG, then sign,
notarize, staple, Gatekeeper-check, and checksum the final DMG.

Options:
  --capture-dir <path>      Evidence capture directory.
  --output <path>           Final DMG path.
  --identity <name>         Developer ID signing identity.
  --notary-profile <name>   notarytool keychain profile.
  --skip-tests              Do not run swift test.
  --skip-build              Re-sign/package the existing QuotaWake.app.
  -h, --help                Show this help.
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

if [[ -f "${VERSION_ENV}" ]]; then
  source "${VERSION_ENV}"
fi
if [[ -f "${LOCAL_ENV}" ]]; then
  source "${LOCAL_ENV}"
fi
if [[ -n "${ENV_VERSION}" ]]; then
  VERSION="${ENV_VERSION}"
fi

VERSION="${VERSION:-0.0.0}"
IDENTITY="${QUOTAWAKE_DEVELOPER_ID_APPLICATION:-${IDENTITY}}"
NOTARY_PROFILE="${QUOTAWAKE_NOTARY_PROFILE:-${NOTARY_PROFILE}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --capture-dir)
      require_value "$@"
      CAPTURE_DIR="$2"
      shift 2
      ;;
    --output)
      require_value "$@"
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --identity)
      require_value "$@"
      IDENTITY="$2"
      shift 2
      ;;
    --notary-profile)
      require_value "$@"
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
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

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid VERSION '${VERSION}': expected MAJOR.MINOR.PATCH, for example 0.0.0" >&2
  exit 65
fi

if [[ -z "${CAPTURE_DIR}" ]]; then
  CAPTURE_DIR="${ROOT_DIR}/.qa-captures/$(date +%Y%m%d)-release-${VERSION}"
fi
if [[ -z "${OUTPUT_PATH}" ]]; then
  OUTPUT_PATH="${ROOT_DIR}/dist/QuotaWake-${VERSION}.dmg"
fi

if [[ -z "${IDENTITY}" ]]; then
  echo "Missing QUOTAWAKE_DEVELOPER_ID_APPLICATION for Developer ID signing." >&2
  exit 78
fi
if [[ -z "${NOTARY_PROFILE}" && ( -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ) ]]; then
  echo "Missing notarization credentials: set QUOTAWAKE_NOTARY_PROFILE or all App Store Connect API variables." >&2
  exit 78
fi

cd "${ROOT_DIR}"

echo "Release version: ${VERSION}"
echo "DMG output: ${OUTPUT_PATH}"
echo "Capture dir: ${CAPTURE_DIR}"

if [[ "${SKIP_TESTS}" -eq 0 ]]; then
  swift test
fi

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  swift build -c "${CONFIGURATION}"
  ./Scripts/package_app.sh "${CONFIGURATION}"
fi

./Scripts/sign-and-notarize.sh \
  --app "${ROOT_DIR}/QuotaWake.app" \
  --identity "${IDENTITY}"

./Scripts/create_dmg.sh \
  --app "${ROOT_DIR}/QuotaWake.app" \
  --output "${OUTPUT_PATH}" \
  --capture-dir "${CAPTURE_DIR}"

notary_args=(--app "${ROOT_DIR}/QuotaWake.app" --dmg "${OUTPUT_PATH}" --identity "${IDENTITY}")
if [[ -n "${NOTARY_PROFILE}" ]]; then
  notary_args+=(--notary-profile "${NOTARY_PROFILE}")
fi
./Scripts/sign-and-notarize.sh "${notary_args[@]}"

codesign --verify --deep --strict --verbose=2 "${ROOT_DIR}/QuotaWake.app"
codesign --verify --verbose=2 "${OUTPUT_PATH}"
xcrun stapler validate "${OUTPUT_PATH}"
spctl -a -t open --context context:primary-signature -vv "${OUTPUT_PATH}"
./Scripts/verify_dmg_presentation.sh --dmg "${OUTPUT_PATH}" --capture-dir "${CAPTURE_DIR}"
shasum -a 256 "${OUTPUT_PATH}"

echo "Release DMG ready: ${OUTPUT_PATH}"
