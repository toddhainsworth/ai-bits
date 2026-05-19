# Ralph

Ralph is an autonomous, PRD-driven implementation loop. Given the issue number of a PRD that has been broken into `ready-for-agent` sub-tasks, Ralph picks each eligible sub-task in turn, implements it with TDD, reviews the result against the project's conventions, and closes the issue — all without human intervention until something warrants it.

```
/ralph <PRD-issue-number>
```

Ralph operates only in PRD mode. There is no standard / per-issue mode. To prepare a PRD for Ralph, draft it with `/to-prd` and break it into sub-tasks with `/to-issues` (each sub-task needs `## Parent #<PRD>` in its body and the `ready-for-agent` label).

---

## Layout

```
claude/
  commands/
    ralph.md                # /ralph entry point — orchestrator instructions
  ralph/                    # prompt templates (NOT under commands/ on purpose)
    implementer.md          # template for Implementer sub-agents
    reviewer.md             # template for slice-level Reviewer
    prd-reviewer.md         # template for the cumulative PRD Reviewer
```

The templates live **outside** `commands/` on purpose. Claude Code auto-discovers any `.md` file under `~/.claude/commands/` as a slash command — if the templates were nested in there, they would appear as bogus `/ralph:implementer`, `/ralph:reviewer`, `/ralph:prd-reviewer` commands.

Placeholder substitution happens in one place only — the prompt templates use `{{X}}` markers (e.g. `{{NUMBER}}`), and the Orchestrator does plain string replacement before spawning each sub-agent. Anywhere else you see `<X>` notation (in this README or in `ralph.md`'s bash snippets) it's prose convention — "the actual value goes here" — not a formal substitution.

## Install

Symlink the entry point and the templates directory into `~/.claude/`:

```bash
ln -s "$(pwd)/claude/commands/ralph.md" ~/.claude/commands/ralph.md
ln -s "$(pwd)/claude/ralph"             ~/.claude/ralph
```

Run from the repo root. After install, `/ralph <PRD#>` is available from any project, and the orchestrator resolves templates at `~/.claude/ralph/<template>.md`.

If you ever see `/ralph:implementer`, `/ralph:reviewer`, or `/ralph:prd-reviewer` show up in your slash-command list with broken descriptions, the templates symlink landed under `~/.claude/commands/` by mistake — move it to `~/.claude/ralph` and the bogus entries will disappear.

---

## Dependencies

Ralph is designed alongside [Matt Pocock's agent skills](https://github.com/mattpocock/skills/) — particularly `/to-prd`, `/to-issues`, and `/triage`, which produce the PRD and sub-task structure Ralph consumes. Run `/setup-matt-pocock-skills` in the target project before using Ralph there.

The Implementer agent inlines the same red-green-refactor loop as the `/tdd` skill; the acceptance criteria from the issue stand in for the interactive planning phase that `/tdd` would normally run with a human.

---

## The per-slice pipeline

For each eligible sub-task, the Orchestrator runs:

1. **Find next eligible sub-task.** Scan all `ready-for-agent` issues (open + closed) whose body references `## Parent #<PRD>` — closed children from a prior partial run are captured so they can be skipped explicitly. A candidate is eligible when its state is `OPEN` and every `## Blocked by` reference resolves to `CLOSED`.
2. **Pre-screen.** Hybrid check: four structural criteria (acceptance present, scope bounded, blockers explicit, no ambiguous ownership) plus a domain ambiguity check. Failure → comment on the issue, append to `skipped`, move on.
3. **Capture `SLICE_BASE`.** The diff anchor for this slice. Every downstream gate uses `git diff $SLICE_BASE` to see only this slice's changes.
4. **Spawn Implementer.** TDD red-green-refactor, grounded in `CONTEXT.md` and `docs/adr/`. The Implementer does not commit, close, or branch.
5. **Verify gate.** Orchestrator independently re-runs the project's test/lint/format commands. Catches hallucinated "all green."
6. **Cursory fitness review.** Orchestrator reads the slice diff and asks one question: *does this address what the issue asked for?* Direction check, not detail check.
7. **Spawn Reviewer.** Two-pillar review (requirements coverage + codebase/tooling best-practice) with priority-tiered findings.
8. **Commit + close.** Orchestrator commits with `<type>: <subject>` + `Closes #N` trailer, then runs `gh issue close <N>`.

After every sub-task closes, the Orchestrator spawns a **PRD-Reviewer** to validate the *cumulative* diff against the PRD body. Gaps are auto-fixed by a fresh Implementer (capped attempts).

---

## Gate caps

Each gate that can re-engage the Implementer has its own 2-attempt cap:

- **Verify gate** — up to 2 fix attempts on test/lint/format failures.
- **Cursory fitness** — up to 2 attempts to redirect the Implementer to the right scope.
- **Reviewer findings** — up to 2 attempts to address Critical and High findings.

Cap-exceed in any gate **stops the loop**. The loop also stops if any sub-agent returns `BLOCKED`.

**Why stop on a single failed slice?** Ralph operates on a dependency graph of sub-tasks. If a foundational slice (one that other slices depend on) is abandoned, the downstream slices end up building on missing ground — even though they may individually still pass their own gates, the resulting branch is incoherent. Stopping cleanly preserves the partial work and lets you fix the foundation manually before re-invoking. When you re-invoke `/ralph <PRD#>`, Setup detects the existing branch and resumes from where the previous run left off (closed children are skipped automatically; in-flight changes from the stopped slice have already been reset).

### Re-engagement strategy

On the first re-engagement of a slice, the Orchestrator uses `SendMessage` to the existing Implementer agent (preserves context). On the second, it spawns a fresh Implementer via `Agent` (clean context to break out of any accumulated confusion).

---

## Priority tiers

Both Reviewers grade findings on four tiers:

| Tier | Behaviour |
|------|-----------|
| **Critical** | Acceptance criterion missing, project "sin" introduced, regression visible. Blocks commit. |
| **High** | Should be fixed before this slice lands. Blocks commit. |
| **Medium** | Significant but not blocking. Surfaced at end-of-session as an offer to create a follow-up issue. |
| **Low** | Style / nit. Fed into retrospective as pattern signal only. |

Medium findings produce an interactive `AskUserQuestion` multi-select prompt when the loop finishes, so the user can pick which to turn into new GitHub issues (each parented to the original PRD).

### A note on "sins"

When the project's CLAUDE.md lists hard rules (e.g. "never use `any` in TypeScript"), the slice Reviewer treats every occurrence as Critical. If a slice has a legitimate need to violate one of those rules (e.g. a third-party type gap that genuinely requires `any`), the Reviewer will still flag it — surfaced as Critical so the orchestrator stops and surfaces it to you. There is no silent-approve escape hatch by design; the trade-off is that you get a clean signal, but a slice that "needs" a sin will require manual unstuck.

---

## End of session

The Orchestrator prints a retrospective:

```
## Ralph session complete

### Closed
- #N: Title

### Skipped at pre-screen          (omitted if empty)
- #N: Title — <criterion that failed>

### Blocked or abandoned           (omitted if empty)
- #N: Title — <reason>

### PRD validation
APPROVED   (or)   ISSUES — N findings, see medium offers below   (or)   SKIPPED — loop stopped early

### Observations                    (each sub-section omitted if empty)
**Ralph loop improvements** — pre-screen / prompt / gate issues
**Agent oddities** — unexpected sub-agent behaviour
**Low-priority pattern signal** — themes from accumulated low-priority findings
```

If every observations sub-section is empty, the line `No observations this session.` replaces the body.

It then prompts for medium-finding triage (issue creation) and prints a suggested `gh pr create` for the human to run when ready. Ralph itself never opens a PR.

---

## Improving Ralph

Ralph is a prompt, not compiled code. The orchestrator lives in `ralph.md`; the sub-agent prompts live in `ralph/*.md`. Improvements are edits to those files.

When a retrospective surfaces a recurring pattern:

1. Read the relevant section of `ralph.md` (loop logic) or `ralph/*.md` (sub-agent prompt).
2. Edit the pre-screen criteria, gate logic, or agent prompt to address the root cause.
3. Commit and run another session to verify the fix holds.

This is the feedback loop: Ralph observes → retrospective records → human edits prompt → Ralph improves.
