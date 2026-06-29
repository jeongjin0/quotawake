#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${ROOT_DIR}/QuotaWake.app"
DMG_PATH=""
DRY_RUN=0
IDENTITY="${QUOTAWAKE_DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${QUOTAWAKE_NOTARY_PROFILE:-}"
ASC_KEY_P8="${APP_STORE_CONNECT_API_KEY_P8:-}"
ASC_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
ASC_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"

usage() {
  cat <<'EOF'
Usage: Scripts/sign-and-notarize.sh [--app <path>] [--dmg <path>] [--dry-run]

App-only mode signs and verifies the app bundle. It does not submit a raw .app
to notarization because notarytool accepts archive formats such as dmg, pkg, or
zip. Pass --dmg <path> after DMG creation to sign, notarize, staple, and verify
the distributable installer.

Real signing requires QUOTAWAKE_DEVELOPER_ID_APPLICATION. DMG notarization also
requires either QUOTAWAKE_NOTARY_PROFILE or APP_STORE_CONNECT_API_KEY_P8,
APP_STORE_CONNECT_KEY_ID, and APP_STORE_CONNECT_ISSUER_ID.
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
    --dmg)
      require_value "$@"
      DMG_PATH="$2"
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
  echo "Dry run: no signing, notarization, stapling, or Gatekeeper checks were performed."
  echo "App bundle path: ${APP_PATH}"
  if [[ -d "${APP_PATH}" ]]; then
    echo "App bundle exists: yes"
  else
    echo "App bundle exists: no (required for a real signing run)"
  fi
  if [[ -n "${IDENTITY}" ]]; then
    echo "Developer ID identity: configured"
  else
    echo "Developer ID identity: missing (required for a real signing run)"
  fi
  echo "Would sign app bundle: ${APP_PATH}"
  if [[ -n "${DMG_PATH}" ]]; then
    echo "DMG path: ${DMG_PATH}"
    if [[ -f "${DMG_PATH}" ]]; then
      echo "DMG exists: yes"
    else
      echo "DMG exists: no (required for a real notarization run)"
    fi
    if [[ -n "${NOTARY_PROFILE}" ]]; then
      echo "Notarization credentials: keychain profile configured"
    elif [[ -n "${ASC_KEY_P8}" && -n "${ASC_KEY_ID}" && -n "${ASC_ISSUER_ID}" ]]; then
      echo "Notarization credentials: App Store Connect API credentials configured"
    else
      echo "Notarization credentials: missing (required for a real DMG notarization run)"
    fi
    echo "Would sign DMG: ${DMG_PATH}"
    echo "Would submit DMG archive to Apple notarization: ${DMG_PATH}"
  else
    echo "App-only mode is sign-only."
    echo "Would not submit raw .app to notarytool; create a DMG and rerun with --dmg for notarization."
  fi
  exit 0
fi

if [[ -z "${IDENTITY}" ]]; then
  echo "Missing QUOTAWAKE_DEVELOPER_ID_APPLICATION for Developer ID signing." >&2
  exit 78
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Missing app bundle: ${APP_PATH}" >&2
  exit 66
fi

if [[ -n "${DMG_PATH}" && ! -f "${DMG_PATH}" ]]; then
  echo "Missing DMG: ${DMG_PATH}" >&2
  exit 66
fi

notary_args=()
if [[ -n "${DMG_PATH}" ]]; then
  if [[ -n "${NOTARY_PROFILE}" ]]; then
    notary_args=(--keychain-profile "${NOTARY_PROFILE}")
  else
    if [[ -z "${ASC_KEY_P8}" || -z "${ASC_KEY_ID}" || -z "${ASC_ISSUER_ID}" ]]; then
      echo "Missing notarization credentials: set QUOTAWAKE_NOTARY_PROFILE or all App Store Connect API variables." >&2
      exit 78
    fi
    notary_args=(--key "${ASC_KEY_P8}" --key-id "${ASC_KEY_ID}" --issuer "${ASC_ISSUER_ID}")
  fi
fi

find "${APP_PATH}/Contents" -type f -perm -111 -print0 | while IFS= read -r -d '' executable; do
  codesign --force --timestamp --options runtime --sign "${IDENTITY}" "${executable}"
done

codesign --force --timestamp --options runtime --deep --sign "${IDENTITY}" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

if [[ -z "${DMG_PATH}" ]]; then
  echo "Signed and verified app only. Notarization was not run because no --dmg archive was provided."
  exit 0
fi

if [[ -n "${DMG_PATH}" ]]; then
  codesign --force --timestamp --sign "${IDENTITY}" "${DMG_PATH}"
fi

xcrun notarytool submit "${DMG_PATH}" "${notary_args[@]}" --wait
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
spctl -a -t open --context context:primary-signature -vv "${DMG_PATH}"
