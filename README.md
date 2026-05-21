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

---

## What's in here

### `claude/`

| File | Target | Purpose |
|---|---|---|
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | Global instructions for every Claude Code session — coding standards, workflow rules, communication preferences. |
| `settings.json` | `~/.claude/settings.json` | Claude Code settings — permissions, env vars, status line config, experimental features. |
| `statusline.sh` | `~/.claude/statusline.sh` | Custom status line script. Shows current model, plan usage with time-to-reset, context window % + total input tokens. |
| `commands/` | `~/.claude/commands/` | Custom slash commands available in every Claude Code session. |
| `skills/` | `~/.claude/skills/` | Custom skills written for personal use. |

### Commands

Custom slash commands. Each command is a markdown file in `claude/commands/` and becomes available as `/<name>` in Claude Code.

| Command | Description |
|---|---|
| `/ralph` | Autonomous GitHub issue loop — selects, implements, reviews, and closes `ready-for-agent` issues via orchestrated sub-agents. Supports `[N]` to cap the number of issues or `prd <issue>` to process all child issues of a PRD on a shared branch. See [the Ralph design notes](claude/commands/README.md) for details. |

---

## Decision log

**Why symlinks instead of copying files?**
Edits in the repo immediately take effect without a sync step. On a new machine the install script recreates the links.

**Why `claude/` subfolder instead of flat root?**
Scoped for future tools — `cursor/`, `copilot/`, etc. can live alongside it without polluting the root.

**Why not track third-party skills?**
`npx skills` handles installs from git repositories. Vendoring the skill files would create a maintenance burden with no upside — the source repo is the source of truth.
