#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_SCRIPT="$SCRIPT_DIR/update.sh"
INSTALL_CRON_SCRIPT="$SCRIPT_DIR/install-cron.sh"

declare -a CHECK_NAMES=()
declare -a CHECK_RESULTS=()
declare -a CHECK_DETAILS=()

record_result() {
  local name="$1"
  local result="$2"
  local detail="${3:-}"

  CHECK_NAMES+=("$name")
  CHECK_RESULTS+=("$result")
  CHECK_DETAILS+=("$detail")
}

first_non_empty_line() {
  local input="$1"
  local line

  while IFS= read -r line; do
    if [[ -n "${line//[[:space:]]/}" ]]; then
      if [[ "$line" =~ ^\[[^]]+\][[:space:]]*$ ]]; then
        continue
      fi
      printf '%s\n' "$line"
      return 0
    fi
  done <<< "$input"

  return 1
}

check_command() {
  local cmd="$1"
  local resolved

  if resolved="$(command -v "$cmd" 2>/dev/null)"; then
    record_result "tool: $cmd" "PASS" "$resolved"
  else
    record_result "tool: $cmd" "FAIL" "not found"
  fi
}

run_check() {
  local name="$1"
  shift

  local output=""
  local status=0
  local detail=""
  local snippet=""

  if output="$("$@" 2>&1)"; then
    detail="exit 0"
    if snippet="$(first_non_empty_line "$output")"; then
      detail+="; $snippet"
    fi
    record_result "$name" "PASS" "$detail"
    return 0
  fi

  status=$?
  detail="exit $status"
  if snippet="$(first_non_empty_line "$output")"; then
    detail+="; $snippet"
  fi
  record_result "$name" "FAIL" "$detail"
  return 1
}

print_summary() {
  local failures=0
  local i

  printf 'Smoke Test Summary\n'
  printf '==================\n'

  for i in "${!CHECK_NAMES[@]}"; do
    printf '%-4s %s' "${CHECK_RESULTS[$i]}" "${CHECK_NAMES[$i]}"
    if [[ -n "${CHECK_DETAILS[$i]}" ]]; then
      printf ': %s' "${CHECK_DETAILS[$i]}"
    fi
    printf '\n'

    if [[ "${CHECK_RESULTS[$i]}" == "FAIL" ]]; then
      failures=$((failures + 1))
    fi
  done

  if [[ $failures -eq 0 ]]; then
    printf 'OVERALL PASS\n'
    return 0
  fi

  printf 'OVERALL FAIL (%d failed)\n' "$failures"
  return 1
}

check_command "clawhub"
check_command "openclaw"
check_command "python3"
check_command "crontab"

run_check "update.sh --dry-run" bash "$UPDATE_SCRIPT" --dry-run
run_check "bash -n update.sh" bash -n "$UPDATE_SCRIPT"
run_check "bash -n install-cron.sh" bash -n "$INSTALL_CRON_SCRIPT"

print_summary
