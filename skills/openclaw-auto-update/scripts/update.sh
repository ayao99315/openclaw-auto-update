#!/bin/bash
# openclaw-auto-update/scripts/update.sh
# Automatically updates OpenClaw and installed skills.
# Detects npm/pnpm, handles conflicts, respects skiplist, sends notifications.
#
# Usage:
#   ./update.sh [--dry-run] [--config /path/to/config.json]
#
# Config file (JSON): See references/config-schema.md for all options.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${OPENCLAW_UPDATE_CONFIG:-$HOME/.openclaw/workspace/skills/openclaw-auto-update/config.json}"
LOG_FILE="/tmp/openclaw-auto-update.log"
DRY_RUN=false

# ── Parse args ───────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --config=*) CONFIG_FILE="${arg#--config=}" ;;
    --config) shift; CONFIG_FILE="${1:-}" ;;
  esac
done

# ── Logging ──────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
log_section() { log ""; log "═══ $* ═══"; }

# ── Load config ──────────────────────────────────────────────────────────────
load_config() {
  python3 - << EOF
import json, os, sys
default = {
    "skipSkills": [],
    "skipPreRelease": True,
    "restartGateway": True,
    "notify": True,
    "dryRun": False,
    "notifyTarget": None
}
cfg = default.copy()
config_path = os.path.expanduser("${CONFIG_FILE}")
if os.path.exists(config_path):
    try:
        with open(config_path) as f:
            user = json.load(f)
        cfg.update(user)
    except Exception as e:
        print(f"WARN: Failed to load config: {e}", file=sys.stderr)
for k, v in cfg.items():
    print(f"{k}={json.dumps(v)}")
EOF
}

# Parse config into shell variables
eval "$(load_config | python3 -c "
import sys, json
for line in sys.stdin:
    k, _, v = line.partition('=')
    v = v.strip()
    val = json.loads(v)
    if isinstance(val, list):
        print(f'CONFIG_{k.upper()}=({\" \".join(map(str, val))})')
    elif isinstance(val, bool):
        print(f'CONFIG_{k.upper()}={\"true\" if val else \"false\"}')
    else:
        print(f'CONFIG_{k.upper()}={val if val is not None else \"\"}')
" 2>/dev/null)"

# CLI --dry-run overrides config
[[ "$DRY_RUN" == "true" ]] && CONFIG_DRYRUN=true

# ── Detect package manager ────────────────────────────────────────────────────
detect_pm() {
  # 1. Check how openclaw binary was installed
  local openclaw_bin
  openclaw_bin=$(command -v openclaw 2>/dev/null || true)
  if [[ -z "$openclaw_bin" ]]; then
    echo "npm"  # fallback
    return
  fi

  # Follow symlinks to find actual location
  local real_path
  real_path=$(python3 -c "import os; print(os.path.realpath('$openclaw_bin'))" 2>/dev/null || echo "$openclaw_bin")

  if echo "$real_path" | grep -q "pnpm"; then
    echo "pnpm"
  elif echo "$real_path" | grep -q "yarn"; then
    echo "yarn"
  else
    # Check if pnpm exists and manages global packages
    if command -v pnpm &>/dev/null && pnpm list -g openclaw &>/dev/null 2>&1; then
      echo "pnpm"
    else
      echo "npm"
    fi
  fi
}

# ── Notify helper ─────────────────────────────────────────────────────────────
notify() {
  local msg="$1"
  [[ "$CONFIG_NOTIFY" != "true" ]] && return 0
  local target="${CONFIG_NOTIFYTARGET:-}"
  if [[ -n "$target" ]]; then
    openclaw message send --target "$target" -m "$msg" 2>/dev/null || true
  else
    openclaw system event --text "$msg" --mode now 2>/dev/null || true
  fi
}

# ── Check if skill is in skiplist ─────────────────────────────────────────────
is_skipped() {
  local skill="$1"
  for skip in "${CONFIG_SKIPSKILLS[@]:-}"; do
    [[ "$skill" == "$skip" ]] && return 0
  done
  return 1
}

# ── Detect locally modified skills ───────────────────────────────────────────
is_locally_modified() {
  local skill_dir="$1"
  # If skill dir is inside a git repo with uncommitted changes, skip it
  if git -C "$skill_dir" rev-parse --git-dir &>/dev/null 2>&1; then
    if [[ -n "$(git -C "$skill_dir" status --porcelain 2>/dev/null)" ]]; then
      return 0  # modified
    fi
  fi
  return 1  # not modified
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  log_section "OpenClaw Auto Update"
  [[ "$CONFIG_DRYRUN" == "true" ]] && log "⚠️  DRY RUN MODE — no changes will be made"

  local PM
  PM=$(detect_pm)
  log "Package manager: $PM"

  local openclaw_version_before
  openclaw_version_before=$(openclaw --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  log "Current OpenClaw version: $openclaw_version_before"

  # ── Update OpenClaw ───────────────────────────────────────────────────────
  log_section "Updating OpenClaw"
  local update_ok=true
  local new_version="$openclaw_version_before"

  if [[ "$CONFIG_DRYRUN" == "true" ]]; then
    log "[DRY RUN] Would run: $PM install -g openclaw"
  else
    local install_output=""
    if [[ "$PM" == "pnpm" ]]; then
      install_output=$(pnpm add -g openclaw 2>&1) || { log "❌ openclaw update failed"; update_ok=false; }
    elif [[ "$PM" == "yarn" ]]; then
      install_output=$(yarn global add openclaw 2>&1) || { log "❌ openclaw update failed"; update_ok=false; }
    else
      install_output=$(npm install -g openclaw 2>&1) || { log "❌ openclaw update failed"; update_ok=false; }
    fi
    log "$install_output"

    new_version=$(openclaw --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    if [[ "$new_version" != "$openclaw_version_before" ]]; then
      log "✅ OpenClaw updated: $openclaw_version_before → $new_version"
    else
      log "✅ OpenClaw already up to date ($new_version)"
    fi
  fi

  # ── Update Skills ─────────────────────────────────────────────────────────
  log_section "Updating Skills"
  local skills_updated=0
  local skills_skipped=0
  local skills_failed=0
  local skills_modified=0
  local skill_summary=""

  # Update skills via clawhub sync (handles both lockfile-installed and workspace skills)
  # clawhub sync --all auto-detects all skill roots including OpenClaw workspace
  if [[ "$CONFIG_DRYRUN" == "true" ]]; then
    log "[DRY RUN] Would run: clawhub sync --all --bump patch"
    # Show what would be updated
    local sync_preview
    sync_preview=$(clawhub sync --dry-run 2>/dev/null || true)
    log "$sync_preview"
    skill_summary="[Dry run — see log for details]"
  else
    # Build skip args
    local skip_args=""
    # clawhub update supports per-slug update; sync updates all
    # We update slugs one by one to respect skiplist and modified check

    # Get all known slugs from sync dry-run
    local all_slugs=()
    while IFS= read -r line; do
      local slug
      slug=$(echo "$line" | grep -oE '^- [a-z0-9-]+' | sed 's/^- //' || true)
      [[ -n "$slug" ]] && all_slugs+=("$slug")
    done < <(clawhub sync --dry-run 2>/dev/null | grep "^- " || true)

    if [[ ${#all_slugs[@]} -eq 0 ]]; then
      log "All skills already up to date (or no skills found)"
    fi

    for slug in "${all_slugs[@]}"; do
      # Skiplist check
      if is_skipped "$slug"; then
        log "⏭️  Skipping $slug (in skiplist)"
        ((skills_skipped++)) || true
        skill_summary+="⏭️ $slug (skipped)\n"
        continue
      fi

      # Pre-release check
      if [[ "$CONFIG_SKIPPRERELEASE" == "true" ]]; then
        local latest
        latest=$(clawhub inspect "$slug" 2>/dev/null | grep -i "version" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+.*' | head -1 || true)
        if echo "$latest" | grep -qE 'alpha|beta|rc|next|canary'; then
          log "⏭️  Skipping $slug (pre-release: $latest)"
          ((skills_skipped++)) || true
          skill_summary+="⏭️ $slug (pre-release)\n"
          continue
        fi
      fi

      log "🔄 Updating $slug..."
      if clawhub update "$slug" --no-input 2>&1 | tee -a "$LOG_FILE"; then
        log "✅ $slug updated"
        ((skills_updated++)) || true
        skill_summary+="✅ $slug\n"
      else
        log "❌ $slug update failed"
        ((skills_failed++)) || true
        skill_summary+="❌ $slug (failed)\n"
      fi
    done

    # Also run sync to catch any workspace skills not in lockfile
    log "Running clawhub sync for workspace skills..."
    clawhub sync --all --bump patch --no-input 2>&1 | tee -a "$LOG_FILE" || true
  fi

  # ── Restart Gateway ───────────────────────────────────────────────────────
  if [[ "$CONFIG_RESTARTGATEWAY" == "true" ]] && [[ "$CONFIG_DRYRUN" != "true" ]]; then
    # Only restart if openclaw was actually updated
    if [[ "$new_version" != "$openclaw_version_before" ]]; then
      log_section "Restarting Gateway"
      log "Restarting OpenClaw gateway..."
      openclaw gateway restart 2>&1 | tee -a "$LOG_FILE" || log "⚠️  Gateway restart failed (may need manual restart)"
      sleep 3
      log "✅ Gateway restarted"
    else
      log "Gateway restart skipped (no version change)"
    fi
  fi

  # ── Summary ───────────────────────────────────────────────────────────────
  log_section "Summary"
  local summary_msg

  if [[ "$CONFIG_DRYRUN" == "true" ]]; then
    summary_msg="🔍 [Dry Run] OpenClaw auto-update preview complete"
  else
    summary_msg="✅ OpenClaw auto-update complete"
    [[ "$new_version" != "$openclaw_version_before" ]] && \
      summary_msg+=" | OpenClaw: $openclaw_version_before → $new_version"
    summary_msg+=" | Skills: ✅${skills_updated} ⏭️${skills_skipped} ❌${skills_failed}"
    [[ $skills_modified -gt 0 ]] && summary_msg+=" ⚠️${skills_modified} modified"
  fi

  log "$summary_msg"

  # Send notification
  if [[ $skills_failed -gt 0 ]]; then
    notify "⚠️ OpenClaw auto-update: $skills_failed skill(s) failed to update. Check log: $LOG_FILE"
  else
    notify "$summary_msg"
  fi
}

main "$@"
