#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

CLAUDE_PATH=""
CODEX_PATH=""
PROMPT="hi"
EVIDENCE_DIR="../.omo/evidence/quotawake-phase2-live-cli-tests/task-3"
TIMEOUT_SECONDS=120
BILLING_MODE="subscription-only"
SELF_TEST=0

GUARD_KEYS=(
  "ANTHROPIC_API_KEY"
  "ANTHROPIC_AUTH_TOKEN"
  "ANTHROPIC_BASE_URL"
  "ANTHROPIC_CUSTOM_HEADERS"
  "OPENAI_API_KEY"
  "OPENAI_BASE_URL"
  "OPENAI_API_BASE"
  "OPENAI_API_HOST"
  "OPENAI_ORGANIZATION"
  "OPENAI_ORG_ID"
  "OPENAI_PROJECT"
  "CLAUDE_CODE_USE_BEDROCK"
  "CLAUDE_CODE_USE_VERTEX"
  "CLAUDE_CODE_USE_ANTHROPIC_AWS"
  "CLAUDE_CODE_USE_FOUNDRY"
  "AWS_PROFILE"
  "AWS_ACCESS_KEY_ID"
  "AWS_SECRET_ACCESS_KEY"
  "AWS_SESSION_TOKEN"
  "GOOGLE_APPLICATION_CREDENTIALS"
  "AZURE_API_KEY"
  "AZURE_OPENAI_API_KEY"
  "AZURE_OPENAI_ENDPOINT"
  "AZURE_CLIENT_ID"
  "AZURE_CLIENT_SECRET"
  "AZURE_TENANT_ID"
  "AZURE_SUBSCRIPTION_ID"
  "AZURE_FOUNDRY_API_KEY"
  "AZURE_AI_FOUNDRY_API_KEY"
  "AZURE_INFERENCE_ENDPOINT"
  "AZURE_AUTHORITY_HOST"
  "FOUNDRY_API_KEY"
  "FOUNDRY_ENDPOINT"
)

TOOL_JSONS=()
FAILURE_JSONS=()
BLOCKED_KEYS=()
CLAUDE_CANDIDATES=()
CODEX_CANDIDATES=()
TRANSCRIPT=""
JSON_OUT=""

usage() {
  cat <<'EOF'
Usage: Scripts/live_cli_smoke.sh [options]

Billing-safe direct smoke test for installed Claude and Codex CLIs.

Options:
  --claude-path <path>          Explicit Claude CLI path.
  --codex-path <path>           Explicit Codex CLI path.
  --prompt <text>               Prompt to send. Default: hi.
  --evidence-dir <dir>          Directory for live-cli-smoke.json/.txt.
  --timeout-seconds <seconds>   Per-provider command timeout. Default: 120.
  --billing-mode <mode>         subscription-only|allow-api-key.
                                Default subscription-only fails closed when
                                Anthropic/OpenAI/API gateway billing env is present.
                                allow-api-key is diagnostic only and records
                                API-billed-risk/api_key_auth_mode evidence.
  --self-test                   Run fake CLI fixtures; never calls live CLIs.
  --help                        Show this help.

Classifications:
  missing_cli, broken_symlink, auth_required, usage_limit,
  api_billing_env_present, api_key_auth_mode, timeout, nonzero_exit,
  empty_output, unexpected_output

Reset signal confidence:
  sent/unknown, limitReached/exactReset, usageLimitNoReset/blocked,
  unknownFailure/unknown. Live smoke does not claim observed local quota because
  it exercises direct readiness prompts, not local quota probes.

QuotaWake command templates under test:
  Claude: claude --print --output-format text --no-session-persistence <prompt>
  Codex:  codex exec --sandbox read-only --skip-git-repo-check --ephemeral \
--ignore-rules --color never -C <repo-or-run-dir> <prompt>
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

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --prompt)
      need_value "$@"
      PROMPT="$2"
      shift 2
      ;;
    --evidence-dir)
      need_value "$@"
      EVIDENCE_DIR="$2"
      shift 2
      ;;
    --timeout-seconds)
      need_value "$@"
      TIMEOUT_SECONDS="$2"
      case "${TIMEOUT_SECONDS}" in
        ''|*[!0-9]*)
          fail_usage "--timeout-seconds must be a positive integer"
          ;;
      esac
      if [[ "${TIMEOUT_SECONDS}" -lt 1 ]]; then
        fail_usage "--timeout-seconds must be at least 1"
      fi
      shift 2
      ;;
    --billing-mode)
      need_value "$@"
      BILLING_MODE="$2"
      case "${BILLING_MODE}" in
        subscription-only|allow-api-key)
          ;;
        *)
          fail_usage "bad billing mode: ${BILLING_MODE}"
          ;;
      esac
      shift 2
      ;;
    --self-test)
      SELF_TEST=1
      shift
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

json_escape() {
  local s="${1-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "${s}"
}

json_string() {
  printf '"%s"' "$(json_escape "${1-}")"
}

json_string_array() {
  local first=1
  local item
  printf '['
  for item in "$@"; do
    if [[ "${first}" -eq 0 ]]; then
      printf ','
    fi
    first=0
    json_string "${item}"
  done
  printf ']'
}

append_failure() {
  local tool="$1"
  local classification="$2"
  local detail="$3"
  FAILURE_JSONS+=("{\"tool\":$(json_string "${tool}"),\"classification\":$(json_string "${classification}"),\"detail\":$(json_string "${detail}")}")
}

json_blocked_keys() {
  if [[ "${#BLOCKED_KEYS[@]}" -eq 0 ]]; then
    printf '[]'
  else
    json_string_array "${BLOCKED_KEYS[@]}"
  fi
}

sanitize_summary_file() {
  local file="$1"
  if [[ ! -s "${file}" ]]; then
    printf ''
    return 0
  fi
  LC_ALL=C tr '\r\n\t' '   ' <"${file}" \
    | sed -E \
      -e 's/(sk-ant-[A-Za-z0-9._-]+)/[REDACTED]/g' \
      -e 's/(sk-[A-Za-z0-9._-]{12,})/[REDACTED]/g' \
      -e 's/(session id:[[:space:]]*)[A-Za-z0-9._-]+/\1[REDACTED]/Ig' \
      -e 's/((Authorization|Bearer|Token|Password|Secret)[^ ]*[:=][[:space:]]*)[^ ]+/\1[REDACTED]/Ig' \
      -e 's/((API|AUTH|TOKEN|SECRET|KEY|PASSWORD)[A-Z0-9_ -]*=)[^ ]+/\1[REDACTED]/Ig' \
    | cut -c 1-700
}

lower_summary_file() {
  local file="$1"
  if [[ ! -s "${file}" ]]; then
    printf ''
    return 0
  fi
  LC_ALL=C tr '\r\n\t' '   ' <"${file}" | tr '[:upper:]' '[:lower:]' | cut -c 1-1200
}

combined_output_file() {
  local stdout_file="$1"
  local stderr_file="$2"
  local out_file="$3"
  : >"${out_file}"
  if [[ -s "${stdout_file}" ]]; then
    cat "${stdout_file}" >>"${out_file}"
    printf '\n' >>"${out_file}"
  fi
  if [[ -s "${stderr_file}" ]]; then
    cat "${stderr_file}" >>"${out_file}"
    printf '\n' >>"${out_file}"
  fi
}

is_unexpected_success_output() {
  local stdout_file="$1"
  local stderr_file="$2"
  local lower

  lower="$(lower_summary_file "${stdout_file}") $(lower_summary_file "${stderr_file}")"
  case "${lower}" in
    *"quotawake-self-test-unexpected-output"*|*"provider-incompatible output"*|*"unexpected provider response"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

quota_signal_json() {
  local classification="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local observed_epoch="$4"
  local combined_file
  local raw
  local lower
  local reset_at=""
  local confidence="unknown"
  local source_classification="unknownFailure"
  local reset_epoch=""

  combined_file="$(mktemp "${TMPDIR:-/tmp}/quotawake-quota-signal.XXXXXX")"
  combined_output_file "${stdout_file}" "${stderr_file}" "${combined_file}"
  raw="$(LC_ALL=C tr '\r\n\t' '   ' <"${combined_file}" | cut -c 1-1200)"
  lower="$(lower_summary_file "${combined_file}")"

  if [[ "${raw}" =~ (20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z) ]]; then
    reset_at="${BASH_REMATCH[1]}"
  fi
  if [[ -n "${reset_at}" ]]; then
    reset_epoch="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${reset_at}" +%s 2>/dev/null || true)"
    if [[ -z "${reset_epoch}" ]]; then
      reset_epoch="$(date -u -j -f "%Y-%m-%dT%H:%M:%S.%NZ" "${reset_at}" +%s 2>/dev/null || true)"
    fi
  fi

  if [[ -z "${reset_at}" && "${lower}" =~ ([0-9]+)[[:space:]]*(h|hr|hrs|hour|hours) ]]; then
    reset_epoch=$((observed_epoch + (${BASH_REMATCH[1]} * 3600)))
  fi
  if [[ -z "${reset_at}" && "${lower}" =~ ([0-9]+)[[:space:]]*(m|min|mins|minute|minutes) ]]; then
    reset_epoch=$((reset_epoch > 0 ? reset_epoch : observed_epoch))
    reset_epoch=$((reset_epoch + (${BASH_REMATCH[1]} * 60)))
  fi
  if [[ -z "${reset_at}" && "${lower}" =~ ([0-9]+)[[:space:]]*(s|sec|secs|second|seconds) ]]; then
    reset_epoch=$((reset_epoch > 0 ? reset_epoch : observed_epoch))
    reset_epoch=$((reset_epoch + ${BASH_REMATCH[1]}))
  fi
  if [[ -z "${reset_at}" && -n "${reset_epoch}" && "${reset_epoch}" -gt "${observed_epoch}" ]]; then
    reset_at="$(date -u -r "${reset_epoch}" +"%Y-%m-%dT%H:%M:%SZ")"
  fi

  case "${classification}" in
    "")
      confidence="unknown"
      source_classification="sent"
      ;;
    usage_limit)
      if [[ -n "${reset_at}" ]]; then
        confidence="exactReset"
        source_classification="limitReached"
      else
        confidence="blocked"
        source_classification="usageLimitNoReset"
      fi
      ;;
    auth_required)
      confidence="blocked"
      source_classification="authRequired"
      ;;
    api_billing_env_present|api_key_auth_mode)
      confidence="blocked"
      source_classification="apiBillingEnvPresent"
      ;;
    timeout|nonzero_exit|empty_output|unexpected_output|broken_symlink|missing_cli)
      confidence="unknown"
      source_classification="unknownFailure"
      ;;
  esac

  rm -f "${combined_file}"
  printf '{"confidence":%s,"sourceClassification":%s,"resetAt":%s}' \
    "$(json_string "${confidence}")" \
    "$(json_string "${source_classification}")" \
    "$(if [[ -n "${reset_at}" ]]; then json_string "${reset_at}"; else printf 'null'; fi)"
}

append_transcript() {
  printf '%s\n' "$*" >>"${TRANSCRIPT}"
}

absolute_path() {
  local path="$1"
  local dir
  local base
  case "${path}" in
    /*)
      printf '%s' "${path}"
      ;;
    *)
      dir="$(dirname "${path}")"
      base="$(basename "${path}")"
      if [[ -d "${dir}" ]]; then
        printf '%s/%s' "$(cd "${dir}" && pwd -P)" "${base}"
      else
        printf '%s/%s' "$(pwd -P)" "${path}"
      fi
      ;;
  esac
}

collect_candidates() {
  local tool="$1"
  local explicit="$2"
  local command_v=""
  local line
  local -a candidates=()

  if [[ -n "${explicit}" ]]; then
    candidates+=("explicit: $(absolute_path "${explicit}")")
  fi

  command_v="$(command -v "${tool}" 2>/dev/null || true)"
  if [[ -n "${command_v}" ]]; then
    candidates+=("command -v ${tool}: ${command_v}")
  else
    candidates+=("command -v ${tool}: <missing>")
  fi

  if command -v which >/dev/null 2>&1; then
    while IFS= read -r line; do
      if [[ -n "${line}" ]]; then
        candidates+=("which -a ${tool}: ${line}")
      fi
    done < <(which -a "${tool}" 2>/dev/null || true)
  else
    candidates+=("which -a ${tool}: <which unavailable>")
  fi

  if [[ "${tool}" == "claude" ]]; then
    CLAUDE_CANDIDATES=("${candidates[@]}")
  else
    CODEX_CANDIDATES=("${candidates[@]}")
  fi
}

select_path() {
  local tool="$1"
  local explicit="$2"
  local found=""
  if [[ -n "${explicit}" ]]; then
    absolute_path "${explicit}"
    return 0
  fi
  found="$(command -v "${tool}" 2>/dev/null || true)"
  if [[ -n "${found}" ]]; then
    printf '%s' "${found}"
  else
    printf ''
  fi
}

path_classification() {
  local path="$1"
  if [[ -z "${path}" ]]; then
    printf 'missing_cli'
  elif [[ -L "${path}" && ! -e "${path}" ]]; then
    printf 'broken_symlink'
  elif [[ ! -e "${path}" ]]; then
    printf 'missing_cli'
  elif [[ ! -x "${path}" ]]; then
    printf 'missing_cli'
  else
    printf ''
  fi
}

detect_billing_keys() {
  local key
  BLOCKED_KEYS=()
  for key in "${GUARD_KEYS[@]}"; do
    if [[ -n "$(printenv "${key}" 2>/dev/null || true)" ]]; then
      BLOCKED_KEYS+=("${key}")
    fi
  done
}

collect_descendant_pids() {
  local parent="$1"
  local child
  if ! command -v pgrep >/dev/null 2>&1; then
    return 0
  fi
  while IFS= read -r child; do
    [[ -n "${child}" ]] || continue
    collect_descendant_pids "${child}"
    printf '%s\n' "${child}"
  done < <(pgrep -P "${parent}" 2>/dev/null || true)
}

signal_descendants() {
  local signal="$1"
  local parent="$2"
  local child
  collect_descendant_pids "${parent}" | while IFS= read -r child; do
    [[ -n "${child}" ]] || continue
    kill "-${signal}" "${child}" 2>/dev/null || true
  done
}

signal_process_tree() {
  local signal="$1"
  local pid="$2"
  local process_group="$3"
  if [[ "${process_group}" -eq 1 ]]; then
    kill "-${signal}" -- "-${pid}" 2>/dev/null || true
  fi
  signal_descendants "${signal}" "${pid}"
  kill "-${signal}" "${pid}" 2>/dev/null || true
}

run_with_timeout() {
  local timeout="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  shift 3
  local pid
  local process_group=0
  local start
  local now
  local status

  start="$(date +%s)"
  set +e
  if command -v perl >/dev/null 2>&1; then
    perl -MPOSIX=setsid -e 'setsid or die "setsid failed: $!"; exec @ARGV or die "exec failed: $!"' -- "$@" >"${stdout_file}" 2>"${stderr_file}" &
    process_group=1
  else
    "$@" >"${stdout_file}" 2>"${stderr_file}" &
  fi
  pid=$!
  while kill -0 "${pid}" 2>/dev/null; do
    now="$(date +%s)"
    if [[ $((now - start)) -ge "${timeout}" ]]; then
      signal_process_tree TERM "${pid}" "${process_group}"
      sleep 1
      signal_process_tree KILL "${pid}" "${process_group}"
      wait "${pid}" 2>/dev/null || true
      set -e
      return 124
    fi
    sleep 0.2
  done
  wait "${pid}"
  status=$?
  set -e
  return "${status}"
}

metadata_summary() {
  local path="$1"
  local temp_dir="$2"
  local stdout_file="${temp_dir}/metadata.stdout"
  local stderr_file="${temp_dir}/metadata.stderr"
  local status=0

  mkdir -p "${temp_dir}"
  : >"${stdout_file}"
  : >"${stderr_file}"
  run_with_timeout 8 "${stdout_file}" "${stderr_file}" "${path}" "--version" || status=$?
  if [[ "${status}" -ne 0 && ! -s "${stdout_file}" && ! -s "${stderr_file}" ]]; then
    run_with_timeout 8 "${stdout_file}" "${stderr_file}" "${path}" "version" || true
  fi
  if [[ ! -s "${stdout_file}" && ! -s "${stderr_file}" ]]; then
    run_with_timeout 8 "${stdout_file}" "${stderr_file}" "${path}" "--help" || true
  fi

  local out
  local err
  out="$(sanitize_summary_file "${stdout_file}")"
  err="$(sanitize_summary_file "${stderr_file}")"
  if [[ -n "${out}" ]]; then
    printf '%s' "${out}"
  elif [[ -n "${err}" ]]; then
    printf 'stderr: %s' "${err}"
  else
    printf '<no version/help output>'
  fi
}

classify_result() {
  local exit_code="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local lower

  if [[ "${exit_code}" -eq 124 ]]; then
    printf 'timeout'
    return 0
  fi

  if [[ "${exit_code}" -ne 0 ]]; then
    lower="$(lower_summary_file "${stdout_file}") $(lower_summary_file "${stderr_file}")"
    if [[ "${lower}" == *"enoent"* || "${lower}" == *"no such file or directory"* ]]; then
      printf 'broken_symlink'
    elif [[ "${lower}" == *"not logged in"* || "${lower}" == *"not authenticated"* || "${lower}" == *"authentication required"* || "${lower}" == *"auth required"* || "${lower}" == *"please log in"* || "${lower}" == *"login required"* || "${lower}" == *"api key required"* ]]; then
      printf 'auth_required'
    elif [[ "${lower}" == *"usage limit"* || "${lower}" == *"rate limit"* || "${lower}" == *"quota exceeded"* || "${lower}" == *"quota exhausted"* || "${lower}" == *"limit reached"* ]]; then
      printf 'usage_limit'
    else
      printf 'nonzero_exit'
    fi
    return 0
  fi

  if [[ ! -s "${stdout_file}" ]]; then
    printf 'empty_output'
    return 0
  fi

  if is_unexpected_success_output "${stdout_file}" "${stderr_file}"; then
    printf 'unexpected_output'
    return 0
  fi

  printf ''
}

argv_json_without_exe() {
  shift
  json_string_array "$@"
}

add_tool_json() {
  local tool="$1"
  local selected_path="$2"
  local version_summary="$3"
  local invocation_json="$4"
  local exit_code="$5"
  local duration_ms="$6"
  local status="$7"
  local classification="$8"
  local stdout_summary="$9"
  local stderr_summary="${10}"
  local billing_status="${11}"
  local quota_signal="${12}"

  TOOL_JSONS+=("{\"tool\":$(json_string "${tool}"),\"selectedPath\":$(json_string "${selected_path}"),\"versionSummary\":$(json_string "${version_summary}"),\"invocation\":${invocation_json},\"exitCode\":${exit_code},\"durationMs\":${duration_ms},\"status\":$(json_string "${status}"),\"classification\":$(json_string "${classification}"),\"quotaSignal\":${quota_signal},\"billingMode\":$(json_string "${BILLING_MODE}"),\"billingStatus\":$(json_string "${billing_status}"),\"blockedEnvironmentKeys\":$(json_blocked_keys),\"stdoutSummary\":$(json_string "${stdout_summary}"),\"stderrSummary\":$(json_string "${stderr_summary}")}")
}

write_json() {
  local started_at="$1"
  local ended_at="$2"
  local billing_status="$3"
  local overall_status="$4"
  local first=1
  {
    printf '{\n'
    printf '  "schemaVersion": 1,\n'
    printf '  "script": %s,\n' "$(json_string "Scripts/live_cli_smoke.sh")"
    printf '  "prompt": %s,\n' "$(json_string "${PROMPT}")"
    printf '  "startedAt": %s,\n' "$(json_string "${started_at}")"
    printf '  "endedAt": %s,\n' "$(json_string "${ended_at}")"
    printf '  "timeoutSeconds": %s,\n' "${TIMEOUT_SECONDS}"
    printf '  "billingMode": %s,\n' "$(json_string "${BILLING_MODE}")"
    printf '  "billingStatus": %s,\n' "$(json_string "${billing_status}")"
    printf '  "overallStatus": %s,\n' "$(json_string "${overall_status}")"
    printf '  "runDirectory": %s,\n' "$(json_string "${ROOT_DIR}")"
    printf '  "blockedEnvironmentKeys": %s,\n' "$(json_blocked_keys)"
    printf '  "candidateDetection": {\n'
    printf '    "claude": %s,\n' "$(json_string_array "${CLAUDE_CANDIDATES[@]}")"
    printf '    "codex": %s\n' "$(json_string_array "${CODEX_CANDIDATES[@]}")"
    printf '  },\n'
    printf '  "tools": ['
    first=1
    local item
    if [[ "${#TOOL_JSONS[@]}" -gt 0 ]]; then
      for item in "${TOOL_JSONS[@]}"; do
        if [[ "${first}" -eq 0 ]]; then
          printf ','
        fi
        first=0
        printf '\n    %s' "${item}"
      done
    fi
    if [[ "${#TOOL_JSONS[@]}" -gt 0 ]]; then
      printf '\n  '
    fi
    printf '],\n'
    printf '  "failures": ['
    first=1
    if [[ "${#FAILURE_JSONS[@]}" -gt 0 ]]; then
      for item in "${FAILURE_JSONS[@]}"; do
        if [[ "${first}" -eq 0 ]]; then
          printf ','
        fi
        first=0
        printf '\n    %s' "${item}"
      done
    fi
    if [[ "${#FAILURE_JSONS[@]}" -gt 0 ]]; then
      printf '\n  '
    fi
    printf ']\n'
    printf '}\n'
  } >"${JSON_OUT}"
}

run_tool() {
  local tool="$1"
  local path="$2"
  local temp_dir="$3"
  local billing_status="$4"
  local version_summary="$5"
  local stdout_file="${temp_dir}/${tool}.stdout"
  local stderr_file="${temp_dir}/${tool}.stderr"
  local start_s
  local end_s
  local exit_code=0
  local duration_ms
  local classification
  local status
  local stdout_summary
  local stderr_summary
  local quota_signal
  local -a argv

  if [[ "${tool}" == "claude" ]]; then
    argv=("${path}" "--print" "--output-format" "text" "--no-session-persistence" "${PROMPT}")
  else
    argv=("${path}" "exec" "--sandbox" "read-only" "--skip-git-repo-check" "--ephemeral" "--ignore-rules" "--color" "never" "-C" "${ROOT_DIR}" "${PROMPT}")
  fi

  append_transcript "invoke ${tool}: $(argv_json_without_exe "${argv[@]}")"
  start_s="$(date +%s)"
  run_with_timeout "${TIMEOUT_SECONDS}" "${stdout_file}" "${stderr_file}" "${argv[@]}" || exit_code=$?
  end_s="$(date +%s)"
  duration_ms=$(((end_s - start_s) * 1000))
  classification="$(classify_result "${exit_code}" "${stdout_file}" "${stderr_file}")"
  stdout_summary="$(sanitize_summary_file "${stdout_file}")"
  stderr_summary="$(sanitize_summary_file "${stderr_file}")"
  quota_signal="$(quota_signal_json "${classification}" "${stdout_file}" "${stderr_file}" "${start_s}")"

  if [[ -z "${classification}" ]]; then
    status="sent"
  else
    status="failed"
    append_failure "${tool}" "${classification}" "provider command did not satisfy live smoke"
  fi

  add_tool_json "${tool}" "${path}" "${version_summary}" "$(argv_json_without_exe "${argv[@]}")" "${exit_code}" "${duration_ms}" "${status}" "${classification}" "${stdout_summary}" "${stderr_summary}" "${billing_status}" "${quota_signal}"
  append_transcript "${tool} status=${status} exitCode=${exit_code} durationMs=${duration_ms} classification=${classification:-none}"
}

run_smoke() {
  local started_at
  local ended_at
  local temp_dir
  local claude_selected
  local codex_selected
  local claude_path_failure
  local codex_path_failure
  local claude_version=""
  local codex_version=""
  local billing_status="subscription_or_cli_login"
  local overall_status="pass"
  local exit_status=0

  mkdir -p "${EVIDENCE_DIR}"
  TRANSCRIPT="${EVIDENCE_DIR}/live-cli-smoke.txt"
  JSON_OUT="${EVIDENCE_DIR}/live-cli-smoke.json"
  : >"${TRANSCRIPT}"
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/quotawake-live-cli.XXXXXX")"
  trap 'rm -rf "${temp_dir}"' RETURN

  started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  append_transcript "QuotaWake live CLI smoke"
  append_transcript "startedAt=${started_at}"
  append_transcript "billingMode=${BILLING_MODE}"
  append_transcript "promptLength=${#PROMPT}"
  append_transcript "timeoutSeconds=${TIMEOUT_SECONDS}"
  append_transcript "runDirectory=${ROOT_DIR}"

  collect_candidates "claude" "${CLAUDE_PATH}"
  collect_candidates "codex" "${CODEX_PATH}"
  append_transcript "candidate detection:"
  printf '  %s\n' "${CLAUDE_CANDIDATES[@]}" >>"${TRANSCRIPT}"
  printf '  %s\n' "${CODEX_CANDIDATES[@]}" >>"${TRANSCRIPT}"

  claude_selected="$(select_path "claude" "${CLAUDE_PATH}")"
  codex_selected="$(select_path "codex" "${CODEX_PATH}")"
  append_transcript "selected claude=${claude_selected:-<missing>}"
  append_transcript "selected codex=${codex_selected:-<missing>}"

  detect_billing_keys
  if [[ "${#BLOCKED_KEYS[@]}" -gt 0 && "${BILLING_MODE}" == "subscription-only" ]]; then
    billing_status="blocked"
    overall_status="fail"
    append_failure "cli-smoke" "api_billing_env_present" "subscription-only mode blocks Anthropic/OpenAI/API gateway billing environment keys"
    append_transcript "blockedEnvironmentKeys=$(json_string_array "${BLOCKED_KEYS[@]}")"
    append_transcript "classification=api_billing_env_present"
    ended_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    write_json "${started_at}" "${ended_at}" "${billing_status}" "${overall_status}"
    echo "api_billing_env_present: refusing to run Claude/Codex with billing env present. See ${JSON_OUT}" >&2
    return 1
  fi

  if [[ "${#BLOCKED_KEYS[@]}" -gt 0 && "${BILLING_MODE}" == "allow-api-key" ]]; then
    billing_status="API-billed-risk"
    append_failure "cli-smoke" "api_key_auth_mode" "allow-api-key is diagnostic only and not a release pass"
    append_transcript "WARNING: API-billed-risk; blocked key names present: $(json_string_array "${BLOCKED_KEYS[@]}")"
    echo "WARNING: API-billed-risk; allow-api-key is diagnostic only." >&2
  fi

  claude_path_failure="$(path_classification "${claude_selected}")"
  codex_path_failure="$(path_classification "${codex_selected}")"
  if [[ -n "${claude_path_failure}" ]]; then
    append_failure "claude" "${claude_path_failure}" "selected Claude path is not executable"
    add_tool_json "claude" "${claude_selected:-}" "" "$(json_string_array "--print" "--output-format" "text" "--no-session-persistence" "${PROMPT}")" 127 0 "not_run" "${claude_path_failure}" "" "" "${billing_status}" '{"confidence":"unknown","sourceClassification":"unknownFailure","resetAt":null}'
  fi
  if [[ -n "${codex_path_failure}" ]]; then
    append_failure "codex" "${codex_path_failure}" "selected Codex path is not executable"
    add_tool_json "codex" "${codex_selected:-}" "" "$(json_string_array "exec" "--sandbox" "read-only" "--skip-git-repo-check" "--ephemeral" "--ignore-rules" "--color" "never" "-C" "${ROOT_DIR}" "${PROMPT}")" 127 0 "not_run" "${codex_path_failure}" "" "" "${billing_status}" '{"confidence":"unknown","sourceClassification":"unknownFailure","resetAt":null}'
  fi
  if [[ -n "${claude_path_failure}" || -n "${codex_path_failure}" ]]; then
    overall_status="fail"
    append_transcript "path preflight failed"
    ended_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    write_json "${started_at}" "${ended_at}" "${billing_status}" "${overall_status}"
    echo "missing or broken CLI path. See ${JSON_OUT}" >&2
    return 1
  fi

  claude_version="$(metadata_summary "${claude_selected}" "${temp_dir}/claude-meta")"
  codex_version="$(metadata_summary "${codex_selected}" "${temp_dir}/codex-meta")"
  append_transcript "claude version/help summary=${claude_version}"
  append_transcript "codex version/help summary=${codex_version}"

  run_tool "claude" "${claude_selected}" "${temp_dir}" "${billing_status}" "${claude_version}"
  run_tool "codex" "${codex_selected}" "${temp_dir}" "${billing_status}" "${codex_version}"

  if [[ "${#FAILURE_JSONS[@]}" -gt 0 ]]; then
    overall_status="fail"
    exit_status=1
  fi

  ended_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  append_transcript "endedAt=${ended_at}"
  append_transcript "overallStatus=${overall_status}"
  write_json "${started_at}" "${ended_at}" "${billing_status}" "${overall_status}"
  if [[ "${exit_status}" -eq 0 ]]; then
    echo "live CLI smoke passed; evidence: ${JSON_OUT}"
  else
    echo "live CLI smoke failed; evidence: ${JSON_OUT}" >&2
  fi
  return "${exit_status}"
}

write_fake_cli() {
  local path="$1"
  local mode="$2"
  cat >"${path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
mode="${mode}"
case "\${1:-}" in
  --version)
    echo "\$(basename "\$0") fake 1.0"
    exit 0
    ;;
  --help)
    echo "\$(basename "\$0") fake help"
    exit 0
    ;;
esac
case "\${mode}" in
  success)
    echo "hi"
    exit 0
    ;;
  auth)
    echo "Authentication required. Please log in." >&2
    exit 1
    ;;
  usage)
    echo "Usage limit reached for this account." >&2
    exit 1
    ;;
  usage_reset_iso)
    echo "Usage limit reached. Reset at 2026-06-29T05:30:00Z." >&2
    exit 1
    ;;
  usage_reset_relative)
    echo "Usage limit reached. Try again in 1 hour 15 minutes." >&2
    exit 1
    ;;
  timeout)
    sleep 5
    echo "late"
    exit 0
    ;;
  timeout_child)
    if [[ -z "\${QUOTAWAKE_SELF_TEST_CHILD_PID_FILE:-}" ]]; then
      echo "missing child pid file" >&2
      exit 2
    fi
    bash -c 'trap "" TERM; printf "%s\n" "\$\$" > "\$1"; sleep 30' quotawake-live-smoke-child "\${QUOTAWAKE_SELF_TEST_CHILD_PID_FILE}" &
    for _ in {1..50}; do
      [[ -s "\${QUOTAWAKE_SELF_TEST_CHILD_PID_FILE}" ]] && break
      sleep 0.02
    done
    sleep 30
    echo "late"
    exit 0
    ;;
  empty)
    exit 0
    ;;
  unexpected)
    echo "QUOTAWAKE-SELF-TEST-UNEXPECTED-OUTPUT provider-incompatible output"
    exit 0
    ;;
  *)
    echo "unknown fake mode" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "${path}"
}

self_test_case() {
  local name="$1"
  local expected="$2"
  local claude_fake="$3"
  local codex_fake="$4"
  local timeout="$5"
  local api_env_key="$6"
  local expected_confidence="${7:-none}"
  local child_pid_file="${8:-}"
  local case_dir="${EVIDENCE_DIR}/${name}"
  local rc=0
  mkdir -p "${case_dir}"

  if [[ "${api_env_key}" != "none" ]]; then
    set +e
    env -i PATH="$(dirname "${claude_fake}"):/usr/bin:/bin" HOME="${case_dir}/home" "${api_env_key}=self-test-secret" \
      "${SCRIPT_PATH}" --claude-path "${claude_fake}" --codex-path "${codex_fake}" --prompt hi --timeout-seconds "${timeout}" --billing-mode subscription-only --evidence-dir "${case_dir}" \
      >"${case_dir}/runner.out" 2>"${case_dir}/runner.err"
    rc=$?
    set -e
  elif [[ -n "${child_pid_file}" ]]; then
    set +e
    env -i PATH="$(dirname "${claude_fake}"):/usr/bin:/bin" HOME="${case_dir}/home" QUOTAWAKE_SELF_TEST_CHILD_PID_FILE="${child_pid_file}" \
      "${SCRIPT_PATH}" --claude-path "${claude_fake}" --codex-path "${codex_fake}" --prompt hi --timeout-seconds "${timeout}" --billing-mode subscription-only --evidence-dir "${case_dir}" \
      >"${case_dir}/runner.out" 2>"${case_dir}/runner.err"
    rc=$?
    set -e
  else
    set +e
    env -i PATH="$(dirname "${claude_fake}"):/usr/bin:/bin" HOME="${case_dir}/home" \
      "${SCRIPT_PATH}" --claude-path "${claude_fake}" --codex-path "${codex_fake}" --prompt hi --timeout-seconds "${timeout}" --billing-mode subscription-only --evidence-dir "${case_dir}" \
      >"${case_dir}/runner.out" 2>"${case_dir}/runner.err"
    rc=$?
    set -e
  fi

  if [[ ! -s "${case_dir}/runner.out" ]]; then
    echo "(no stdout)" >"${case_dir}/runner.out"
  fi
  if [[ ! -s "${case_dir}/runner.err" ]]; then
    echo "(no stderr)" >"${case_dir}/runner.err"
  fi

  if [[ "${rc}" -eq 0 ]]; then
    echo "self-test ${name}: expected nonzero exit" >&2
    return 1
  fi
  if [[ ! -s "${case_dir}/live-cli-smoke.json" || ! -s "${case_dir}/live-cli-smoke.txt" ]]; then
    echo "self-test ${name}: missing evidence" >&2
    return 1
  fi
  if ! rg -q "\"classification\":\"${expected}\"|\"classification\": \"${expected}\"" "${case_dir}/live-cli-smoke.json"; then
    echo "self-test ${name}: expected classification ${expected}" >&2
    return 1
  fi
  if [[ "${expected_confidence}" != "none" ]] && ! rg -q "\"confidence\":\"${expected_confidence}\"|\"confidence\": \"${expected_confidence}\"" "${case_dir}/live-cli-smoke.json"; then
    echo "self-test ${name}: expected quota confidence ${expected_confidence}" >&2
    return 1
  fi
  if rg -q "self-test-secret" "${case_dir}/live-cli-smoke.json" "${case_dir}/live-cli-smoke.txt" "${case_dir}/runner.out" "${case_dir}/runner.err"; then
    echo "self-test ${name}: leaked API env value" >&2
    return 1
  fi
  if [[ "${expected}" == "api_billing_env_present" ]] && ! rg -q '"tools": \[\]' "${case_dir}/live-cli-smoke.json"; then
    echo "self-test ${name}: expected no tool invocations" >&2
    return 1
  fi
  if [[ -n "${child_pid_file}" ]]; then
    local child_pid=""
    if [[ -s "${child_pid_file}" ]]; then
      child_pid="$(tr -dc '0-9' <"${child_pid_file}")"
    fi
    if [[ -z "${child_pid}" ]]; then
      echo "self-test ${name}: missing child pid" >&2
      return 1
    fi
    local deadline=$((SECONDS + 3))
    while kill -0 "${child_pid}" 2>/dev/null && [[ "${SECONDS}" -lt "${deadline}" ]]; do
      sleep 0.1
    done
    if kill -0 "${child_pid}" 2>/dev/null; then
      kill -9 "${child_pid}" 2>/dev/null || true
      echo "self-test ${name}: leaked child pid ${child_pid}" >&2
      return 1
    fi
  fi
  printf '{"case":%s,"expectedClassification":%s,"exitCode":%s,"evidence":%s}\n' \
    "$(json_string "${name}")" "$(json_string "${expected}")" "${rc}" "$(json_string "${case_dir}/live-cli-smoke.json")" \
    >>"${EVIDENCE_DIR}/self-test-summary.jsonl"
  echo "self-test ${name}: ${expected}"
}

run_self_test() {
  local fake_root
  local success_claude
  local success_codex
  local auth_claude
  local usage_codex
  local usage_reset_iso_codex
  local usage_reset_relative_codex
  local timeout_claude
  local timeout_child_claude
  local timeout_child_pid_file
  local empty_claude
  local unexpected_claude
  local broken_claude
  mkdir -p "${EVIDENCE_DIR}"
  : >"${EVIDENCE_DIR}/self-test-summary.jsonl"
  fake_root="$(mktemp -d "${TMPDIR:-/tmp}/quotawake-live-cli-selftest.XXXXXX")"
  trap 'rm -rf "${fake_root}"' RETURN

  mkdir -p "${fake_root}/bin" "${fake_root}/missing"
  success_claude="${fake_root}/bin/claude-success"
  success_codex="${fake_root}/bin/codex-success"
  auth_claude="${fake_root}/bin/claude-auth"
  usage_codex="${fake_root}/bin/codex-usage"
  usage_reset_iso_codex="${fake_root}/bin/codex-usage-reset-iso"
  usage_reset_relative_codex="${fake_root}/bin/codex-usage-reset-relative"
  timeout_claude="${fake_root}/bin/claude-timeout"
  timeout_child_claude="${fake_root}/bin/claude-timeout-child"
  timeout_child_pid_file="${EVIDENCE_DIR}/timeout-child-cleanup/child.pid"
  empty_claude="${fake_root}/bin/claude-empty"
  unexpected_claude="${fake_root}/bin/claude-unexpected"
  broken_claude="${fake_root}/bin/claude-broken"

  write_fake_cli "${success_claude}" "success"
  write_fake_cli "${success_codex}" "success"
  write_fake_cli "${auth_claude}" "auth"
  write_fake_cli "${usage_codex}" "usage"
  write_fake_cli "${usage_reset_iso_codex}" "usage_reset_iso"
  write_fake_cli "${usage_reset_relative_codex}" "usage_reset_relative"
  write_fake_cli "${timeout_claude}" "timeout"
  write_fake_cli "${timeout_child_claude}" "timeout_child"
  write_fake_cli "${empty_claude}" "empty"
  write_fake_cli "${unexpected_claude}" "unexpected"
  ln -s "${fake_root}/missing/claude" "${broken_claude}"

  self_test_case "broken-symlink" "broken_symlink" "${broken_claude}" "${success_codex}" 2 "none"
  self_test_case "auth-required" "auth_required" "${auth_claude}" "${success_codex}" 2 "none"
  self_test_case "usage-limit" "usage_limit" "${success_claude}" "${usage_codex}" 2 "none" "blocked"
  self_test_case "usage-limit-exact-reset-iso" "usage_limit" "${success_claude}" "${usage_reset_iso_codex}" 2 "none" "exactReset"
  self_test_case "usage-limit-exact-reset-relative" "usage_limit" "${success_claude}" "${usage_reset_relative_codex}" 2 "none" "exactReset"
  self_test_case "anthropic-api-billing-env-present" "api_billing_env_present" "${success_claude}" "${success_codex}" 2 "ANTHROPIC_API_KEY"
  self_test_case "openai-api-billing-env-present" "api_billing_env_present" "${success_claude}" "${success_codex}" 2 "OPENAI_API_KEY"
  self_test_case "timeout" "timeout" "${timeout_claude}" "${success_codex}" 1 "none"
  self_test_case "timeout-child-cleanup" "timeout" "${timeout_child_claude}" "${success_codex}" 1 "none" "none" "${timeout_child_pid_file}"
  self_test_case "empty-output" "empty_output" "${empty_claude}" "${success_codex}" 2 "none"
  self_test_case "unexpected-output" "unexpected_output" "${unexpected_claude}" "${success_codex}" 2 "none"

  {
    printf '{\n'
    printf '  "schemaVersion": 1,\n'
    printf '  "selfTest": true,\n'
    printf '  "status": "pass",\n'
    printf '  "cases": ["broken_symlink","auth_required","usage_limit","usage_limit_exact_reset_iso","usage_limit_exact_reset_relative","anthropic_api_billing_env_present","openai_api_billing_env_present","timeout","timeout_child_cleanup","empty_output","unexpected_output"],\n'
    printf '  "summaryJsonl": %s,\n' "$(json_string "${EVIDENCE_DIR}/self-test-summary.jsonl")"
    printf '  "fixtureRootRemoved": true\n'
    printf '}\n'
  } >"${EVIDENCE_DIR}/self-test-summary.json"
  echo "self-test passed; evidence: ${EVIDENCE_DIR}/self-test-summary.json"
}

if [[ "${SELF_TEST}" -eq 1 ]]; then
  run_self_test
else
  run_smoke
fi
