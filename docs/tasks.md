# ayao-updater Task Breakdown

## AYAO-T001 — Fix `clawhub sync` misuse: replace with `clawhub update --all`

- **name**: Replace `clawhub sync --all` (push) with `clawhub update` (pull) for skill updates
- **files**: `skills/ayao-updater/scripts/update.sh`
- **agent**: codex
- **review_level**: full
- **depends_on**: []
- **details**:
  - Line 245: `clawhub sync --all --bump patch --no-input` pushes local skills to ClawHub — must be removed entirely.
  - Line 186-191: dry-run preview also uses `clawhub sync --dry-run` — replace with `clawhub update --all --dry-run` or equivalent.
  - The per-slug `clawhub update "$slug"` on line 232 is correct and should be kept.

## AYAO-T002 — Fix skill slug discovery: replace `clawhub sync --dry-run` parsing

- **name**: Use `clawhub list` (or equivalent) to enumerate installed skills instead of `clawhub sync --dry-run`
- **files**: `skills/ayao-updater/scripts/update.sh`
- **agent**: codex
- **review_level**: full
- **depends_on**: [AYAO-T001]
- **details**:
  - Lines 200-204: slug discovery parses `clawhub sync --dry-run` output with `grep -oE '^- [a-z0-9-]+'` — fragile and semantically wrong (`sync` is a push command).
  - Replace with `clawhub list` or `clawhub list --format json` if available.
  - If `clawhub list` output format is unknown, add a fallback that scans `~/.openclaw/workspace/skills/` directories.

## AYAO-T003 — Wire up `is_locally_modified()` — defined but never called

- **name**: Actually call `is_locally_modified` in the skill update loop to skip dirty skills
- **files**: `skills/ayao-updater/scripts/update.sh`
- **agent**: codex
- **review_level**: scan
- **depends_on**: [AYAO-T002]
- **details**:
  - `is_locally_modified()` is defined at line 125-134 but never invoked in the `for slug` loop (line 210-241).
  - `skills_modified` counter (line 273) is referenced in summary but never incremented.
  - Add the check inside the loop: resolve the skill directory path, call `is_locally_modified`, increment `skills_modified`, and `continue` if dirty.

## AYAO-T004 — Fix `--config` arg parsing in `update.sh`

- **name**: Fix broken `--config <value>` (space-separated) argument parsing
- **files**: `skills/ayao-updater/scripts/update.sh`
- **agent**: codex
- **review_level**: scan
- **depends_on**: []
- **details**:
  - Line 23-24: `--config) shift; CONFIG_FILE="${1:-}" ;;` — `shift` inside a `for arg in "$@"` loop has no effect; the loop variable `arg` doesn't advance.
  - Only the `--config=value` form works currently.
  - Fix: switch from `for arg` to a `while [[ $# -gt 0 ]]` loop with explicit `shift`.

## AYAO-T005 — Fix `install-cron.sh` arg parsing

- **name**: Fix schedule arg parsing and positional arg collision in `install-cron.sh`
- **files**: `skills/ayao-updater/scripts/install-cron.sh`
- **agent**: codex
- **review_level**: scan
- **depends_on**: []
- **details**:
  - Line 8: `SCHEDULE="${1:-0 2 * * *}"` blindly takes the first positional arg — could be `--uninstall` or `--schedule=...`.
  - `--schedule` with space-separated value (`--schedule "0 3 * * 0"`) doesn't work in the `for arg` loop (same `shift` issue as T004).
  - Fix: use `while [[ $# -gt 0 ]]` loop; only set `SCHEDULE` from `--schedule` flag or config, not from `$1`.

## AYAO-T006 — Harden config loading (path injection & empty array)

- **name**: Fix shell-variable-in-Python-heredoc fragility and empty `CONFIG_SKIPSKILLS` array edge case
- **files**: `skills/ayao-updater/scripts/update.sh`
- **agent**: codex
- **review_level**: scan
- **depends_on**: []
- **details**:
  - Lines 33-54: `${CONFIG_FILE}` is interpolated inside a Python heredoc — paths with quotes, spaces, or `$` will break the Python code.
  - Fix: pass `CONFIG_FILE` as an env var or Python arg instead of string interpolation.
  - Line 118: `${CONFIG_SKIPSKILLS[@]:-}` — when `CONFIG_SKIPSKILLS=()` (empty array), behavior varies across bash versions; some versions of bash 4 treat it as unset under `set -u`. Guard with `[[ ${#CONFIG_SKIPSKILLS[@]} -eq 0 ]]` check.

## AYAO-T007 — Validate `clawhub inspect` and pre-release version parsing

- **name**: Verify `clawhub inspect <slug>` output format; add fallback for pre-release detection
- **files**: `skills/ayao-updater/scripts/update.sh`
- **agent**: codex
- **review_level**: scan
- **depends_on**: [AYAO-T002]
- **details**:
  - Lines 221-228: `clawhub inspect "$slug"` piped through `grep -i "version"` assumes a specific text output format.
  - If `clawhub inspect` supports `--json`, use `jq` or `python3 -c` to extract version reliably.
  - If the command doesn't exist, fall back to checking the skill's `package.json` or `SKILL.md` metadata.

## AYAO-T008 — macOS/Linux compatibility audit

- **name**: Audit and fix cross-platform issues (python3 dep check, crontab edge cases)
- **files**: `skills/ayao-updater/scripts/update.sh`, `skills/ayao-updater/scripts/install-cron.sh`
- **agent**: codex
- **review_level**: scan
- **depends_on**: []
- **details**:
  - Add `python3` availability check at script start — it's used for config loading and realpath resolution.
  - `crontab -l` on a fresh system with no crontab returns exit code 1 on some Linux distros — the `|| true` on line 32 of `install-cron.sh` handles this, but `printf '%s\n%s\n'` may insert a blank line if `$EXISTING` is empty. Use `{ echo "$NEW_CRON"; } | crontab -` when existing is empty.
  - No `sed -i` issue found (not used), but document the `python3` requirement in SKILL.md prerequisites.

## AYAO-T009 — Fix cron entry formatting edge cases

- **name**: Prevent blank lines in crontab when no prior entries exist
- **files**: `skills/ayao-updater/scripts/install-cron.sh`
- **agent**: codex
- **review_level**: skip
- **depends_on**: [AYAO-T005]
- **details**:
  - Line 42: `printf '%s\n%s\n' "$EXISTING" "$NEW_CRON"` adds a blank line when `$EXISTING` is empty.
  - Fix: only prepend `$EXISTING` if non-empty.

## AYAO-T010 — Add smoke test script

- **name**: Create `scripts/smoke-test.sh` to validate config loading, arg parsing, PM detection, and dry-run
- **files**: new `skills/ayao-updater/scripts/smoke-test.sh`
- **agent**: codex
- **review_level**: full
- **depends_on**: [AYAO-T001, AYAO-T002, AYAO-T004, AYAO-T005, AYAO-T006]
- **details**:
  - Test cases:
    1. Config loading with valid JSON → verify `CONFIG_*` variables are set
    2. Config loading with missing file → verify defaults apply
    3. Config loading with malformed JSON → verify graceful fallback
    4. `--dry-run` flag → verify `CONFIG_DRYRUN=true`
    5. `--config=/path` flag → verify custom config path used
    6. PM detection → verify one of npm/pnpm/yarn returned
    7. `is_skipped` with populated skiplist → verify correct behavior
    8. `is_locally_modified` with clean/dirty git dir → verify detection
    9. Full dry-run execution → verify no side effects, exit code 0
  - Use `bash -x` mode for debugging output.
  - Exit non-zero on first failure.

## AYAO-T011 — Update SKILL.md to document prerequisites and correct CLI commands

- **name**: Add python3 prerequisite; fix any stale CLI references in SKILL.md
- **files**: `skills/ayao-updater/SKILL.md`
- **agent**: codex
- **review_level**: skip
- **depends_on**: [AYAO-T001, AYAO-T008]
- **details**:
  - Add "Prerequisites" section listing: bash ≥ 4.0, python3, jq (if added in T007), openclaw CLI, clawhub CLI.
  - Verify all example commands in SKILL.md still match actual script behavior after fixes.
