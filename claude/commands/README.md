# Ralph

Ralph is an autonomous GitHub issue loop. It selects `ready-for-agent` issues, implements them via sub-agents, reviews the output, and closes the loop — all without human intervention until something warrants it.

```
/ralph          # process all ready-for-agent issues
/ralph 3        # cap at 3 issues
/ralph prd 42   # process all child issues of PRD #42 on a shared branch
```

---

## Dependencies

Ralph is designed to be used alongside [Matt Pocock's agent skills](https://github.com/mattpocock/skills/). Those skills provide the sub-agent capabilities (issue tracking, triage, domain context) that Ralph's orchestration layer coordinates. Run `/setup-matt-pocock-skills` in the target project before using Ralph there.

The implementation agent follows the `/tdd` skill's red-green-refactor loop inline — the full workflow is embedded in the agent prompt, with the acceptance criteria standing in for the interactive planning phase that `/tdd` would normally run with a human.

---

## Design philosophy

Ralph is not just an implementation loop — it is a quality loop. Every session is an opportunity to improve both the code and the process that produced it. The two mechanisms that enforce this are the **review phase** and the **retrospective**.

---

## Review phase

After implementation, Ralph spawns a dedicated review agent before touching git. This is not optional and cannot be bypassed.

### What the review agent checks

1. **Acceptance criteria coverage** — every criterion in the issue is addressed, not just the happy path.
2. **Project conventions** — the project's `CLAUDE.md` is injected into the review prompt; any "sins" it calls out (e.g. `any` in TS, deep nesting, oversized functions, redundant comments) are flagged.
3. **Code quality** — no deeply nested code, no large functions, no unnecessary comments.
4. **Documentation health** — if behaviour, configuration, or interfaces changed, does the relevant doc (README, CONTEXT.md, inline docs) reflect it? Doc-only gaps are flagged as `(low-priority)` if functionality is otherwise correct.
5. **Regressions** — anything in the diff that breaks existing contracts.

### Iterative fix loop

If the review returns `ISSUES`, Ralph spawns a fix agent and re-runs the review. This repeats up to **two fix attempts**. If the issue still isn't resolved after two attempts, Ralph posts a comment on the GitHub issue, records the outcome in the retrospective, and moves on rather than committing broken work.

Low-priority findings that don't block the commit are noted but not acted on immediately — they accumulate in the retrospective for systemic review.

### Verification gate

Even after the review approves, Ralph re-runs the project's test, lint, and format commands from the orchestrator before committing. The implementation and fix agents claim they ran these — Ralph verifies, since a hallucinated "all green" would otherwise land on the branch. A failure here re-enters the fix loop and shares the same two-attempt cap.

After commit, Ralph asserts `git status --porcelain` is clean. If the agent touched files that weren't picked up by the stage, the loop stops rather than silently shipping a partial commit.

---

## Retrospective

At the end of every session, Ralph synthesises everything it observed into a structured report. This is the mechanism that closes the feedback loop on the loop itself.

### What gets recorded

Throughout the session, Ralph accumulates observations whenever something is notable:

- An issue was skipped at pre-screening (and why)
- A fix agent was blocked and couldn't proceed
- A low-priority review finding was deferred
- An agent behaved unexpectedly or took more iterations than expected

### Report structure

```
## Ralph session complete

### Closed
- #N: Title

### Skipped
- #N: Title — <reason>

### Observations

**Ralph loop improvements**
Problems with the loop itself — pre-screening criteria, agent prompts, response formats, edge cases in the workflow.

**Project improvements**
Systemic gaps in issue quality or recurring patterns in what agents got wrong.
Accumulated low-priority findings that warrant a cleanup pass.

**Agent oddities**
Unexpected sub-agent behaviour — unusual fix iteration counts, surprising interpretations, response format edge cases.
```

### Why this matters

The retrospective is the primary feedback mechanism for improving Ralph. If a pre-screening criterion keeps missing a class of bad issues, the retrospective surfaces it. If agent prompts consistently produce a particular kind of mistake, that pattern shows up here before it becomes a habit.

Treat the retrospective output as a signal: recurring observations in **Ralph loop improvements** are candidates to fold back into `ralph.md` itself. Recurring observations in **Project improvements** are candidates for a dedicated cleanup issue.

---

## Improving Ralph

Ralph is a prompt, not compiled code. Improvements are edits to `claude/commands/ralph.md`.

When a retrospective surfaces a pattern worth fixing:

1. Read the relevant section of `ralph.md`.
2. Edit the pre-screening criteria, agent prompt, or loop logic to address the root cause.
3. Commit and run another session to verify the fix holds.

This creates a tight loop: Ralph observes → retrospective records → human edits prompt → Ralph improves.
