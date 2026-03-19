---
name: openclaw-updater
description: Automatically update OpenClaw and all installed skills on a schedule. Use when: (1) setting up automatic updates for OpenClaw or skills, (2) running a manual update check, (3) configuring update schedule, skip lists, or pre-release filtering, (4) user says "auto update", "schedule updates", "keep openclaw updated", "update skills automatically". Handles npm/pnpm/yarn detection, locally-modified skill protection, conflict avoidance, and Telegram notifications on completion or failure.
---

# OpenClaw Auto Update

Keeps OpenClaw and installed ClawHub skills up to date automatically.

## Quick Start

### 1. Install cron job (runs daily at 2 AM by default)

```bash
bash ~/.openclaw/workspace/skills/openclaw-auto-update/scripts/install-cron.sh
```

### 2. Run manually now

```bash
bash ~/.openclaw/workspace/skills/openclaw-auto-update/scripts/update.sh
```

### 3. Preview what would be updated (no changes)

```bash
bash ~/.openclaw/workspace/skills/openclaw-auto-update/scripts/update.sh --dry-run
```

## Configuration

Create `~/.openclaw/workspace/skills/openclaw-auto-update/config.json`:

```json
{
  "schedule": "0 2 * * *",
  "skipSkills": [],
  "skipPreRelease": true,
  "restartGateway": true,
  "notify": true,
  "notifyTarget": null
}
```

See `references/config-schema.md` for all options and examples.

## What It Does

1. **Detects package manager** — auto-detects npm / pnpm / yarn by tracing the `openclaw` binary path
2. **Updates OpenClaw** — runs `<pm> install -g openclaw`
3. **Updates skills** — runs `clawhub update <slug>` for each installed skill
4. **Protects local changes** — skips skills with uncommitted git changes
5. **Respects skip list** — never touches skills in `skipSkills`
6. **Filters pre-releases** — skips alpha/beta/rc versions when `skipPreRelease: true`
7. **Restarts gateway** — only if OpenClaw version actually changed
8. **Notifies** — sends Telegram message on completion or failure

## Change Schedule

```bash
# Change to 3 AM weekly on Sunday
bash ~/.openclaw/workspace/skills/openclaw-auto-update/scripts/install-cron.sh --schedule "0 3 * * 0"

# Uninstall cron job
bash ~/.openclaw/workspace/skills/openclaw-auto-update/scripts/install-cron.sh --uninstall
```

## Logs

```bash
tail -f /tmp/openclaw-auto-update.log
```

## Skip a Specific Skill Permanently

Add to `config.json`:
```json
{ "skipSkills": ["my-custom-skill", "work-internal"] }
```
