# ai-bits

Personal AI configuration and tooling — agent settings, custom skills, and anything else that makes a new machine feel like home.

## Setup

**Prerequisites:** `git`, `jq`, `curl`

```bash
git clone <your-remote-url> ~/src/ai-bits
cd ~/src/ai-bits
./install.sh
```

The install script creates symlinks from `~/.claude/` into this repo. Existing files are backed up automatically. After it runs, restart your agent.

### Third-party skills

Third-party skills are installed via [`npx skills`](https://github.com/vercel-labs/skills) and are not tracked here. Reinstall them with:

```bash
npx skills add <owner/repo>
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
Edits in the repo immediately take effect without a sync step. On a new machine the install script recreates the links.

**Why `claude/` subfolder instead of flat root?**
Scoped for future tools — `cursor/`, `copilot/`, etc. can live alongside it without polluting the root.

**Why not track third-party skills?**
`npx skills` handles installs from git repositories. Vendoring the skill files would create a maintenance burden with no upside — the source repo is the source of truth.
