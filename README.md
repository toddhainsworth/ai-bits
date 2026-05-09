# ai-bits

Personal AI configuration and tooling — Claude Code settings, custom skills, and anything else that makes a new machine feel like home.

## Setup

**Prerequisites:** `git`, `jq`, `curl`

```bash
git clone <your-remote-url> ~/src/ai-bits
cd ~/src/ai-bits
./install.sh
```

The install script creates symlinks from `~/.claude/` into this repo. Existing files are backed up automatically. After it runs, restart Claude Code.

### Third-party skills

Skills from external registries (e.g. Matt Pocock's skill pack) are managed by Claude Code's own skill manager and are not tracked here. Reinstall them with:

```bash
claude skills install mattpocock/skills
```

Refer to the [Skills](#skills) section below for the current list.

---

## What's in here

### `claude/`

| File | Target | Purpose |
|---|---|---|
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | Global instructions for every Claude Code session — coding standards, workflow rules, communication preferences. |
| `settings.json` | `~/.claude/settings.json` | Claude Code settings — permissions, env vars, status line config, experimental features. |
| `statusline.sh` | `~/.claude/statusline.sh` | Custom status line script. Shows model, plan usage with time-to-reset, context window %, and git branch with a clickable repo link. |

### `skills/`

Custom skills written for personal use. Each skill lives in its own subdirectory following the standard `SKILL.md` structure.

None yet.

---

## Decision log

**Why symlinks instead of copying files?**
Edits in the repo immediately take effect in Claude Code without a sync step. On a new machine the install script recreates the links.

**Why `claude/` subfolder instead of flat root?**
Scoped for future tools — `cursor/`, `copilot/`, etc. can live alongside it without polluting the root.

**Why not track third-party skills?**
Claude Code's skill manager handles installs and updates via a lock file (`~/.agents/.skill-lock.json`). Vendoring the skill files would create a maintenance burden with no upside — the registry is the source of truth.
