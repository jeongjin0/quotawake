#!/usr/bin/env bash
set -euo pipefail

SCENARIO="popover-settings"
FAKE_CLI_ROOT=""
EVIDENCE_DIR=""
UPDATE_FIXTURE=""
CLAUDE_PATH=""
CODEX_PATH=""

usage() {
  cat <<'EOF'
Usage: Scripts/ui_qa.sh --evidence-dir <dir> [options]

Options:
  --scenario <name>       popover-settings|missing-cli|first-run|
                          run-now|broken-codex|live-run-now|
                          tool-toggle|normal-launch|
                          reset-due-active|reset-due-idle|
                          unknown-quota|quota-unavailable|
                          limit-reset-observed|
                          migrated-old-settings|
                          update-available|update-error|full
  --fake-cli-root <dir>   Fake CLI root for non-live scenarios.
  --claude-path <path>    Explicit Claude CLI path for live-run-now.
  --codex-path <path>     Explicit Codex CLI path for live-run-now.
  --update-fixture <file> Release fixture for update scenarios.
  --help                  Show this help.
EOF
}

fail_usage() {
  echo "error: $1" >&2
  echo "Run with --help for usage." >&2
  exit 64
}

need_value() {
  if [[ $# -lt 2 || -z "${2:-}" ]]; then
    fail_usage "$1 requires a value"
  fi
}

valid_scenario() {
  case "$1" in
    popover-settings|missing-cli|first-run|run-now|broken-codex|live-run-now|tool-toggle|normal-launch|update-available|update-error|reset-due-active|reset-due-idle|unknown-quota|quota-unavailable|limit-reset-observed|migrated-old-settings|full)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      need_value "$@"
      SCENARIO="$2"
      shift 2
      ;;
    --fake-cli-root)
      need_value "$@"
      FAKE_CLI_ROOT="$2"
      shift 2
      ;;
    --evidence-dir)
      need_value "$@"
      EVIDENCE_DIR="$2"
      shift 2
      ;;
    --update-fixture)
      need_value "$@"
      UPDATE_FIXTURE="$2"
      shift 2
      ;;
    --claude-path)
      need_value "$@"
      CLAUDE_PATH="$2"
      shift 2
      ;;
    --codex-path)
      need_value "$@"
      CODEX_PATH="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail_usage "unknown argument: $1"
      ;;
  esac
done

if [[ -z "${EVIDENCE_DIR}" ]]; then
  usage >&2
  exit 64
fi

if ! valid_scenario "${SCENARIO}"; then
  fail_usage "invalid --scenario: ${SCENARIO}"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/QuotaWake.app"
APP_BIN="${APP_DIR}/Contents/MacOS/QuotaWake"
mkdir -p "${EVIDENCE_DIR}"

if [[ "${SCENARIO}" == "live-run-now" ]]; then
  if [[ -z "${CLAUDE_PATH}" ]]; then
    fail_usage "--claude-path is required for live-run-now"
  fi
  if [[ -z "${CODEX_PATH}" ]]; then
    fail_usage "--codex-path is required for live-run-now"
  fi
  if [[ ! -x "${CLAUDE_PATH}" ]]; then
    fail_usage "--claude-path is not executable: ${CLAUDE_PATH}"
  fi
  if [[ ! -x "${CODEX_PATH}" ]]; then
    fail_usage "--codex-path is not executable: ${CODEX_PATH}"
  fi
fi

if [[ "${SCENARIO}" == "full" ]]; then
  "${ROOT_DIR}/Scripts/package_app.sh" debug >/dev/null
  FAKE_CLI_ROOT="${FAKE_CLI_ROOT:-${ROOT_DIR}/.build/fake-cli}"
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}" --scenario popover-settings
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}" --scenario missing-cli
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}" --scenario first-run
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}" --scenario run-now
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}/reset-due-active" --scenario reset-due-active
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}/reset-due-idle" --scenario reset-due-idle
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}/unknown-quota" --scenario unknown-quota
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}/quota-unavailable" --scenario quota-unavailable
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}/limit-reset-observed" --scenario limit-reset-observed
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}/migrated-old-settings" --scenario migrated-old-settings
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}" --scenario broken-codex
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}" --scenario tool-toggle
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}/normal-launch" --scenario normal-launch
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}" --scenario update-available --update-fixture "${ROOT_DIR}/Tests/Fixtures/releases/latest-newer.json"
  "${BASH_SOURCE[0]}" --fake-cli-root "${FAKE_CLI_ROOT}" --evidence-dir "${EVIDENCE_DIR}" --scenario update-error --update-fixture "${ROOT_DIR}/Tests/Fixtures/releases/latest-malformed.json"
  echo "UI QA scenario full complete"
  exit 0
fi

"${ROOT_DIR}/Scripts/package_app.sh" debug >/dev/null

if [[ -n "${FAKE_CLI_ROOT}" ]]; then
  mkdir -p "${FAKE_CLI_ROOT}"
fi

TRANSCRIPT="${EVIDENCE_DIR}/${SCENARIO}-uiqa.txt"
if [[ "${SCENARIO}" == "normal-launch" ]]; then
  mkdir -p "${EVIDENCE_DIR}"
  QUOTAWAKE_NORMAL_QA_DIR="${EVIDENCE_DIR}" \
    QUOTAWAKE_FAKE_CLI_ROOT="${FAKE_CLI_ROOT:-${EVIDENCE_DIR}/fake-cli}" \
    "${APP_BIN}" >"${TRANSCRIPT}" 2>&1
  plutil -extract LSUIElement raw -o - "${APP_DIR}/Contents/Info.plist" >"${EVIDENCE_DIR}/dock-check.txt"
  pgrep -x "QuotaWake" >"${EVIDENCE_DIR}/process.txt" || true
  test -s "${EVIDENCE_DIR}/normal-launch.json"
  rg -q '"normalLaunch" : true' "${EVIDENCE_DIR}/normal-launch.json"
  rg -q '"statusItemReady" : true' "${EVIDENCE_DIR}/normal-launch.json"
  rg -q '"popoverShown" : true' "${EVIDENCE_DIR}/normal-launch.json"
  rg -q '"settingsWindowShown" : true' "${EVIDENCE_DIR}/normal-launch.json"
  rg -q '"runLogCount" : 0' "${EVIDENCE_DIR}/normal-launch.json"
  echo "UI QA scenario ${SCENARIO} complete"
  exit 0
fi

APP_ARGS=(
  --ui-qa
  --scenario "${SCENARIO}"
  --evidence-dir "${EVIDENCE_DIR}"
)
if [[ -n "${FAKE_CLI_ROOT}" ]]; then
  APP_ARGS+=(--fake-cli-root "${FAKE_CLI_ROOT}")
fi
if [[ -n "${UPDATE_FIXTURE}" ]]; then
  APP_ARGS+=(--update-fixture "${UPDATE_FIXTURE}")
fi
if [[ -n "${CLAUDE_PATH}" ]]; then
  APP_ARGS+=(--claude-path "${CLAUDE_PATH}")
fi
if [[ -n "${CODEX_PATH}" ]]; then
  APP_ARGS+=(--codex-path "${CODEX_PATH}")
fi

set +e
"${APP_BIN}" "${APP_ARGS[@]}" >"${TRANSCRIPT}" 2>&1
APP_STATUS=$?
set -e

plutil -extract LSUIElement raw -o - "${APP_DIR}/Contents/Info.plist" >"${EVIDENCE_DIR}/dock-check.txt"
if [[ "${SCENARIO}" == "live-run-now" ]]; then
  if ! pgrep -x "QuotaWake" >"${EVIDENCE_DIR}/process-before-cleanup.txt"; then
    echo "none" >"${EVIDENCE_DIR}/process-before-cleanup.txt"
  fi
  if [[ "$(<"${EVIDENCE_DIR}/process-before-cleanup.txt")" != "none" ]]; then
    while IFS= read -r pid; do
      kill "${pid}" 2>/dev/null || true
    done <"${EVIDENCE_DIR}/process-before-cleanup.txt"
    sleep 1
  fi
  if ! pgrep -x "QuotaWake" >"${EVIDENCE_DIR}/process-after-cleanup.txt"; then
    echo "none" >"${EVIDENCE_DIR}/process-after-cleanup.txt"
  fi
  cp "${EVIDENCE_DIR}/process-after-cleanup.txt" "${EVIDENCE_DIR}/process.txt"
  if [[ "$(<"${EVIDENCE_DIR}/process-after-cleanup.txt")" != "none" ]]; then
    echo "QuotaWake process left running after cleanup" >&2
    exit 1
  fi
else
  if ! pgrep -fl "QuotaWake" >"${EVIDENCE_DIR}/process.txt"; then
    echo "none" >"${EVIDENCE_DIR}/process.txt"
  fi
fi

if [[ "${APP_STATUS}" -ne 0 ]]; then
  echo "UI QA app exited ${APP_STATUS}; transcript: ${TRANSCRIPT}" >&2
  exit "${APP_STATUS}"
fi

case "${SCENARIO}" in
  popover-settings)
    test -s "${EVIDENCE_DIR}/popover.png"
    test -s "${EVIDENCE_DIR}/settings.png"
    test -s "${EVIDENCE_DIR}/settings-tools.png"
    test -s "${EVIDENCE_DIR}/settings-readiness.png"
    test -s "${EVIDENCE_DIR}/settings-prompt.png"
    test -s "${EVIDENCE_DIR}/settings-logs.png"
    ;;
  missing-cli)
    test -s "${EVIDENCE_DIR}/missing-cli.png"
    ;;
  first-run)
    test -s "${EVIDENCE_DIR}/01-welcome.png"
    test -s "${EVIDENCE_DIR}/02-detect-tools.png"
    test -s "${EVIDENCE_DIR}/03-window-readiness.png"
    test -s "${EVIDENCE_DIR}/04-test-run.png"
    test -s "${EVIDENCE_DIR}/setup-complete.json"
    ;;
  run-now)
    test -s "${EVIDENCE_DIR}/run-now.png"
    test -s "${EVIDENCE_DIR}/fake-success.jsonl"
    test -s "${EVIDENCE_DIR}/captures/claude.args"
    test -s "${EVIDENCE_DIR}/captures/codex.args"
    rg -q '"status":"sent"' "${EVIDENCE_DIR}/fake-success.jsonl"
    rg -q '"tool":"claude"' "${EVIDENCE_DIR}/fake-success.jsonl"
    rg -q '"tool":"codex"' "${EVIDENCE_DIR}/fake-success.jsonl"
    ;;
  broken-codex)
    test -s "${EVIDENCE_DIR}/broken-codex.png"
    test -s "${EVIDENCE_DIR}/broken-codex-settings-tools.png"
    test -s "${EVIDENCE_DIR}/broken-codex.jsonl"
    test -s "${EVIDENCE_DIR}/broken-codex-summary.txt"
    test -s "${EVIDENCE_DIR}/local-resolution-failure.txt"
    test -s "${EVIDENCE_DIR}/captures/codex.probe"
    test ! -e "${EVIDENCE_DIR}/captures/codex.args"
    test ! -e "${EVIDENCE_DIR}/captures/claude.args"
    rg -q '"status":"failed"' "${EVIDENCE_DIR}/broken-codex.jsonl"
    rg -q '"tool":"codex"' "${EVIDENCE_DIR}/broken-codex.jsonl"
    rg -q '"errorSummary":"CLI resolution status: brokenExecutable"' "${EVIDENCE_DIR}/broken-codex.jsonl"
    if rg -q '"status":"sent"' "${EVIDENCE_DIR}/broken-codex.jsonl"; then
      echo "Broken Codex fixture should not record sent" >&2
      exit 1
    fi
    rg -q 'resolutionStatus: brokenExecutable' "${EVIDENCE_DIR}/local-resolution-failure.txt"
    rg -q 'sentCount: 0' "${EVIDENCE_DIR}/local-resolution-failure.txt"
    rg -q 'promptExecutionRecorded: false' "${EVIDENCE_DIR}/local-resolution-failure.txt"
    ;;
  live-run-now)
    test -s "${EVIDENCE_DIR}/live-run-now.png"
    test -s "${EVIDENCE_DIR}/live-run-now.jsonl"
    test -s "${EVIDENCE_DIR}/live-run-now-summary.txt"
    test -s "${EVIDENCE_DIR}/billing-env-policy.txt"
    test -s "${EVIDENCE_DIR}/dock-check.txt"
    test -s "${EVIDENCE_DIR}/process-after-cleanup.txt"
    if [[ "$(<"${EVIDENCE_DIR}/process-after-cleanup.txt")" != "none" ]]; then
      echo "QuotaWake process left running" >&2
      exit 1
    fi
    rg -q '"tool":"claude"' "${EVIDENCE_DIR}/live-run-now.jsonl"
    rg -q '"tool":"codex"' "${EVIDENCE_DIR}/live-run-now.jsonl"
    rg -q '"status":"sent".*"tool":"claude"|\"tool\":\"claude\".*\"status\":\"sent\"' "${EVIDENCE_DIR}/live-run-now.jsonl"
    rg -q '"status":"sent".*"tool":"codex"|\"tool\":\"codex\".*\"status\":\"sent\"' "${EVIDENCE_DIR}/live-run-now.jsonl"
    rg -q 'valuesRecorded: false' "${EVIDENCE_DIR}/billing-env-policy.txt"
    rg -q 'anthropicApiKeyPassedToClaude: false' "${EVIDENCE_DIR}/billing-env-policy.txt"
    ;;
  tool-toggle)
    test -s "${EVIDENCE_DIR}/tool-toggle.png"
    test -s "${EVIDENCE_DIR}/tool-toggle.jsonl"
    test -s "${EVIDENCE_DIR}/captures/claude.args"
    test ! -e "${EVIDENCE_DIR}/captures/codex.args"
    rg -q '"status":"sent"' "${EVIDENCE_DIR}/tool-toggle.jsonl"
    rg -q '"tool":"claude"' "${EVIDENCE_DIR}/tool-toggle.jsonl"
    if rg -q '"tool":"codex"' "${EVIDENCE_DIR}/tool-toggle.jsonl"; then
      echo "Codex should not run when disabled" >&2
      exit 1
    fi
    ;;
  reset-due-active)
    test -s "${EVIDENCE_DIR}/popover.png"
    test -s "${EVIDENCE_DIR}/settings-readiness.png"
    test -s "${EVIDENCE_DIR}/reset-due-active.jsonl"
    test -s "${EVIDENCE_DIR}/reset-due-active-summary.txt"
    test -s "${EVIDENCE_DIR}/quota-window-states.json"
    test -s "${EVIDENCE_DIR}/scenario-receipt.txt"
    test -s "${EVIDENCE_DIR}/captures/claude.args"
    test -s "${EVIDENCE_DIR}/captures/codex.args"
    rg -q '"status":"sent"' "${EVIDENCE_DIR}/reset-due-active.jsonl"
    rg -q '"quotaConfidence":"exactReset"' "${EVIDENCE_DIR}/reset-due-active.jsonl"
    rg -q 'sentCount: 2' "${EVIDENCE_DIR}/scenario-receipt.txt"
    ;;
  reset-due-idle)
    test -s "${EVIDENCE_DIR}/popover.png"
    test -s "${EVIDENCE_DIR}/settings-readiness.png"
    test -s "${EVIDENCE_DIR}/reset-due-idle.jsonl"
    test -s "${EVIDENCE_DIR}/reset-due-idle-summary.txt"
    test -s "${EVIDENCE_DIR}/quota-window-states.json"
    test -s "${EVIDENCE_DIR}/scenario-receipt.txt"
    test ! -e "${EVIDENCE_DIR}/captures/claude.args"
    test ! -e "${EVIDENCE_DIR}/captures/codex.args"
    rg -q '"skipReason":"idle"' "${EVIDENCE_DIR}/reset-due-idle.jsonl"
    rg -q '"decisionSource":"activityGate"' "${EVIDENCE_DIR}/reset-due-idle.jsonl"
    rg -q 'sentCount: 0' "${EVIDENCE_DIR}/scenario-receipt.txt"
    ;;
  unknown-quota)
    test -s "${EVIDENCE_DIR}/popover.png"
    test -s "${EVIDENCE_DIR}/settings-readiness.png"
    test -s "${EVIDENCE_DIR}/unknown-quota.jsonl"
    test -s "${EVIDENCE_DIR}/unknown-quota-summary.txt"
    test -s "${EVIDENCE_DIR}/quota-window-states.json"
    test -s "${EVIDENCE_DIR}/scenario-receipt.txt"
    test ! -e "${EVIDENCE_DIR}/captures/claude.args"
    test ! -e "${EVIDENCE_DIR}/captures/codex.args"
    rg -q '"quotaConfidence":"unknown"' "${EVIDENCE_DIR}/unknown-quota.jsonl"
    rg -q '"skipReason":"unknown_quota"' "${EVIDENCE_DIR}/unknown-quota.jsonl"
    rg -q '"confidence" : "unknown"' "${EVIDENCE_DIR}/quota-window-states.json"
    ;;
  quota-unavailable)
    test -s "${EVIDENCE_DIR}/popover.png"
    test -s "${EVIDENCE_DIR}/settings-readiness.png"
    test -s "${EVIDENCE_DIR}/quota-unavailable.jsonl"
    test -s "${EVIDENCE_DIR}/quota-unavailable-summary.txt"
    test -s "${EVIDENCE_DIR}/quota-window-states.json"
    test -s "${EVIDENCE_DIR}/scenario-receipt.txt"
    test ! -e "${EVIDENCE_DIR}/captures/claude.args"
    test ! -e "${EVIDENCE_DIR}/captures/codex.args"
    rg -q '"skipReason":"quota_observe_unavailable"' "${EVIDENCE_DIR}/quota-unavailable.jsonl"
    rg -q '"quotaUnavailable"' "${EVIDENCE_DIR}/quota-window-states.json"
    rg -q 'sentCount: 0' "${EVIDENCE_DIR}/scenario-receipt.txt"
    ;;
  limit-reset-observed)
    test -s "${EVIDENCE_DIR}/popover.png"
    test -s "${EVIDENCE_DIR}/settings-readiness.png"
    test -s "${EVIDENCE_DIR}/limit-reset-observed.jsonl"
    test -s "${EVIDENCE_DIR}/limit-reset-observed-summary.txt"
    test -s "${EVIDENCE_DIR}/quota-window-states.json"
    test -s "${EVIDENCE_DIR}/scenario-receipt.txt"
    test ! -e "${EVIDENCE_DIR}/captures/claude.args"
    test ! -e "${EVIDENCE_DIR}/captures/codex.args"
    rg -q '"confidence" : "observedLocalQuota"' "${EVIDENCE_DIR}/quota-window-states.json"
    rg -q '"skipReason":"reset_not_due"' "${EVIDENCE_DIR}/limit-reset-observed.jsonl"
    rg -q 'sentCount: 0' "${EVIDENCE_DIR}/scenario-receipt.txt"
    ;;
  migrated-old-settings)
    test -s "${EVIDENCE_DIR}/popover.png"
    test -s "${EVIDENCE_DIR}/settings-readiness.png"
    test -s "${EVIDENCE_DIR}/migrated-old-settings-summary.txt"
    test -s "${EVIDENCE_DIR}/legacy-settings.json"
    test -s "${EVIDENCE_DIR}/migrated-settings.json"
    test -s "${EVIDENCE_DIR}/migrated-old-settings.jsonl"
    test -s "${EVIDENCE_DIR}/quota-window-states.json"
    test -s "${EVIDENCE_DIR}/scenario-receipt.txt"
    test ! -e "${EVIDENCE_DIR}/captures/claude.args"
    test ! -e "${EVIDENCE_DIR}/captures/codex.args"
    rg -q '"schemaVersion" : 2' "${EVIDENCE_DIR}/migrated-settings.json"
    if rg -q '"schedule"|"wake"' "${EVIDENCE_DIR}/migrated-settings.json"; then
      echo "Migrated settings should not persist schedule or wake keys" >&2
      exit 1
    fi
    rg -q '"skipReason":"migration_verified"' "${EVIDENCE_DIR}/migrated-old-settings.jsonl"
    ;;
  update-available)
    test -s "${EVIDENCE_DIR}/settings-update-available.png"
    test -s "${EVIDENCE_DIR}/opened-url.txt"
    ;;
  update-error)
    test -s "${EVIDENCE_DIR}/settings-update-error.png"
    test ! -e "${EVIDENCE_DIR}/opened-url.txt"
    ;;
esac

echo "UI QA scenario ${SCENARIO} complete"
