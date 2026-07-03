#!/usr/bin/env bash
set -euo pipefail

DMG_PATH=""
CAPTURE_DIR=""
VOLUME_NAME="QuotaWake"
MOUNT_POINT=""
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quotawake-dmg-verify.XXXXXX")"

usage() {
  cat <<'EOF'
Usage: Scripts/verify_dmg_presentation.sh --dmg <path> [--capture-dir <path>]
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
    --dmg)
      require_value "$@"
      DMG_PATH="$2"
      shift 2
      ;;
    --capture-dir)
      require_value "$@"
      CAPTURE_DIR="$2"
      shift 2
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

if [[ -z "${DMG_PATH}" ]]; then
  usage_error "--dmg is required."
fi
if [[ ! -f "${DMG_PATH}" ]]; then
  echo "Missing DMG: ${DMG_PATH}" >&2
  exit 66
fi

cleanup() {
  if [[ -n "${MOUNT_POINT}" && -d "${MOUNT_POINT}" ]]; then
    hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
  fi
  hdiutil detach "/Volumes/${VOLUME_NAME}" >/dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

hdiutil detach "/Volumes/${VOLUME_NAME}" >/dev/null 2>&1 || true
ATTACH_OUTPUT="$(hdiutil attach -readonly -noverify -noautoopen "${DMG_PATH}")"
MOUNT_POINT="$(awk -v volume="/Volumes/${VOLUME_NAME}" '$0 ~ volume { print substr($0, index($0, volume)); exit }' <<<"${ATTACH_OUTPUT}")"
if [[ -z "${MOUNT_POINT}" || ! -d "${MOUNT_POINT}" ]]; then
  echo "Failed to mount DMG at /Volumes/${VOLUME_NAME}" >&2
  echo "${ATTACH_OUTPUT}" >&2
  exit 70
fi

open -a Finder "${MOUNT_POINT}"
sleep 2

SCRIPT_PATH="${WORK_DIR}/measure-finder.applescript"
cat > "${SCRIPT_PATH}" <<'OSA'
tell application "Finder"
  activate
  set targetDisk to disk "QuotaWake"
  open targetDisk
  delay 1
  set w to container window of targetDisk
  set current view of w to icon view
  set opts to icon view options of w
  set oldDelimiters to AppleScript's text item delimiters
  set AppleScript's text item delimiters to ","
  set boundsText to (bounds of w as list) as text
  set appPositionText to (position of item "QuotaWake.app" of w as list) as text
  set applicationsPositionText to (position of item "Applications" of w as list) as text
  set itemText to (name of every item of w) as text
  set AppleScript's text item delimiters to oldDelimiters
  set out to "bounds=" & boundsText & linefeed
  set out to out & "icon_size=" & (icon size of opts as text) & linefeed
  set out to out & "text_size=" & (text size of opts as text) & linefeed
  set out to out & "quotawake_position=" & appPositionText & linefeed
  set out to out & "applications_position=" & applicationsPositionText & linefeed
  set out to out & "visible_items=" & itemText & linefeed
  out
end tell
OSA

PRESENTATION="$(osascript "${SCRIPT_PATH}")"
if [[ -f "${MOUNT_POINT}/.background/background.png" ]]; then
  PRESENTATION="${PRESENTATION}"$'\n'"background_asset=present:${MOUNT_POINT}/.background/background.png"
else
  PRESENTATION="${PRESENTATION}"$'\n'"background_asset=missing:${MOUNT_POINT}/.background/background.png"
fi

printf '%s\n' "${PRESENTATION}"

if [[ -n "${CAPTURE_DIR}" ]]; then
  mkdir -p "${CAPTURE_DIR}"
  printf '%s\n' "${PRESENTATION}" > "${CAPTURE_DIR}/finder-presentation.txt"
  osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
  osascript -e 'tell application "Finder" to set selection to {}' >/dev/null 2>&1 || true
  osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
  screencapture -x "${CAPTURE_DIR}/dmg-finder-window.png"
fi

grep -q '^bounds=160,120,760,500$' <<<"${PRESENTATION}"
grep -q '^icon_size=128$' <<<"${PRESENTATION}"
grep -q '^text_size=16$' <<<"${PRESENTATION}"
grep -q '^quotawake_position=180,170$' <<<"${PRESENTATION}"
grep -q '^applications_position=480,170$' <<<"${PRESENTATION}"
grep -q '^visible_items=Applications,QuotaWake.app$' <<<"${PRESENTATION}"
grep -q '^background_asset=present:/Volumes/QuotaWake/.background/background.png$' <<<"${PRESENTATION}"

echo "DMG Finder presentation verified: ${DMG_PATH}"
