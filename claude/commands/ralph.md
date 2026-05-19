---
description: "Autonomous PRD-driven implementation loop via orchestrated sub-agents"
argument-hint: "<PRD-issue-number>"
---

# Ralph

You are the Ralph Orchestrator. Drive a PRD-driven, AFK implementation loop:

1. Read the PRD and discover its `ready-for-agent` sub-tasks.
2. For each eligible sub-task, run the per-slice pipeline (pre-screen → Implementer → verify → cursory fitness → Reviewer → commit + close).
3. After all sub-tasks close, validate the cumulative diff against the PRD.
4. Surface findings to the user.

You handle orchestration, git, GitHub, and final reporting. Sub-agents handle implementation and review.

---

## Setup

### Parse argument

`$ARGUMENTS` is a single integer: the PRD issue number. If it is empty, non-numeric, or names an issue that does not exist on the current GitHub repo, stop and tell the user what went wrong — do not proceed.

Initialise:

- `PRD_NUMBER` = the parsed argument
- `closed_slices` = empty list of `{number, title}` for the retrospective
- `skipped` = empty list of `{number, title, reason}`
- `blocked_or_abandoned` = empty list of `{number, title, reason}`
- `retrospective_observations` = empty list (low-priority findings + agent oddities)
- `medium_findings` = empty list (gathered from Reviewer + PRD-Reviewer)

### Cache default branch

```bash
DEFAULT=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
```

If this command fails (no `gh` auth, no GitHub remote, network error): stop and tell the user the gh CLI is not reachable. Ralph cannot run without it.

### Identify verification commands

Inspect the project CLAUDE.md (already in your context) for test, lint, and format commands. Record them as `VERIFY_COMMANDS` (e.g. `yarn test`, `yarn lint --fix`). If none are documented, set `VERIFY_COMMANDS` to empty — the verify gate becomes a no-op.

Sub-agents you spawn inherit your working directory and load CLAUDE.md themselves. You do not need to inject conventions into their prompts.

### Fetch the PRD

```bash
gh issue view "$PRD_NUMBER" --json number,title,body
```

Capture the result as `PRD_ISSUE`. The `body` is the source of truth the PRD-Reviewer will validate against later.

### Discover child sub-tasks

Find all open `ready-for-agent` issues whose body contains a `## Parent #<PRD_NUMBER>` section, sorted by number ascending:

```bash
gh issue list --state all --label ready-for-agent \
  --limit 200 \
  --json number,title,body,state \
  --jq "[.[] | select(.body | test(\"(?i)##\\\\s*Parent\\\\s+#${PRD_NUMBER}\\\\b\"))] | sort_by(.number)"
```

Capture the result as `CHILD_ISSUES`. The work queue is the entries with `state: OPEN`. Already-closed children from a prior partial run are skipped automatically.

If `CHILD_ISSUES` is empty: stop and tell the user no eligible sub-tasks were found.

### Create or resume the shared branch

Derive a short, lowercase, hyphen-separated slug from the PRD title — capture the subject in 3–5 words, drop type prefixes (feat, fix, chore, etc.), drop articles and filler. Use it as `<SLUG>`. The branch name is `feature/${PRD_NUMBER}_<SLUG>`.

Check whether the branch already exists locally (from a prior partial run):

```bash
git show-ref --verify --quiet "refs/heads/feature/${PRD_NUMBER}_<SLUG>"
```

If it exists: check it out and continue from where the previous run left off. Do **not** reset or rebase — prior closed slices are committed work.

```bash
git checkout "feature/${PRD_NUMBER}_<SLUG>"
```

If it does not exist: create it fresh from the default branch.

```bash
git checkout "$DEFAULT" && git pull
git checkout -b "feature/${PRD_NUMBER}_<SLUG>"
```

In either case, before entering the main loop, verify the working tree is clean (`git status --porcelain` is empty). If not, stop and tell the user — Ralph cannot proceed on a dirty tree.

---

## Main loop

Repeat until every open child sub-task has been processed (closed, skipped, or stopped on BLOCKED / cap-exceed).

---

### Step 1 — Find the next eligible sub-task

Iterate `CHILD_ISSUES` in ascending number order. Skip any whose `state` is `CLOSED` or whose number is in `skipped` or `blocked_or_abandoned`.

For each remaining candidate, parse `## Blocked by` from its body to collect referenced issue numbers. Resolve blocker state:

1. Any blocker whose number appears in `CHILD_ISSUES` with `state: OPEN` means the candidate is still blocked — skip without a network call.
2. For unknown blockers (not in `CHILD_ISSUES`), fire `gh issue view <N> --json state` calls for all of them in parallel, then read results together.

A candidate is **eligible** when it has no `## Blocked by` section, or every blocker resolves to `CLOSED`.

If no candidate is eligible: proceed to **PRD validation**.

---

### Step 2 — Pre-screen

Use the body already captured in `CHILD_ISSUES` (do not re-fetch). Apply both checks:

**Structural criteria** — all four must hold:

1. **Acceptance criteria present** — a verifiable definition of done exists (not just a description of the problem).
2. **Scope is bounded** — implementation requires no decisions outside the codebase (no "discuss with team", "figure out the right approach").
3. **Blockers explicit** — any dependencies are captured in `## Blocked by`, not buried in prose.
4. **No ambiguous ownership** — not a meta-task, discussion thread, or spike.

**Domain ambiguity check** — using your reading of the project (CONTEXT.md, ADRs in `docs/adr/` if present, the codebase you've seen so far), does the issue reference any concept, module, or behaviour that is ambiguous given the project's domain vocabulary? For example: "add caching" when the project has two existing cache layers and the issue doesn't say which.

If any structural criterion fails or the domain check surfaces ambiguity:

```bash
gh issue comment <NUMBER> --body "Ralph skipped #<NUMBER>: <specific gap>"
```

Append to `skipped`. Return to Step 1 to find the next eligible candidate.

If everything passes, record a brief reading: the acceptance criteria in your own words, the scope boundary, any non-obvious constraints. This is `PRESCREEN_ANALYSIS` — it is passed to the Implementer.

---

### Step 3 — Capture slice base

```bash
SLICE_BASE=$(git rev-parse HEAD)
```

This is the diff anchor for the rest of the per-slice pipeline. Every gate (verify, cursory, Reviewer) uses `git diff $SLICE_BASE` to look at only this slice's changes.

Initialise per-gate counters for this slice:

- `verify_attempts = 0`
- `cursory_attempts = 0`
- `reviewer_attempts = 0`

Each cap is **2 attempts per gate**. Cap-exceed in any gate stops the entire loop (see **Stop the loop** below).

---

### Step 4 — Spawn the Implementer

Read the Implementer prompt template:

```bash
cat ~/.claude/ralph/implementer.md
```

Substitute placeholders:

- `{{NUMBER}}` — the sub-task number
- `{{TITLE}}` — the sub-task title
- `{{PRESCREEN_ANALYSIS}}` — your pre-screen reading
- `{{FULL_ISSUE_BODY}}` — the body from `CHILD_ISSUES`

Spawn an Agent with `subagent_type: general-purpose`, a stable name (e.g. `implementer-<NUMBER>`), and the filled prompt. Remember the agent name — re-engagement uses it.

If the Implementer returns `BLOCKED`: see **Stop the loop**.

---

### Step 5 — Verify gate

Run every command in `VERIFY_COMMANDS`. If empty, skip this step.

If every command exits 0: proceed to Step 6.

If any command fails: capture stdout+stderr of the failing command(s) as `VERIFY_FAILURES`.

- Increment `verify_attempts`.
- If `verify_attempts > 2`: **Stop the loop** (cap exceeded in verify).
- Otherwise: re-engage the Implementer (see **Re-engagement**) with the failures as the directive: *"The verification commands failed. Fix the issues below and re-run all verification commands. {{VERIFY_FAILURES}}"*. After it returns `DONE`, return to Step 5.

---

### Step 6 — Orchestrator cursory fitness review

Read the diff for this slice with surrounding context:

```bash
git diff -U20 "$SLICE_BASE"
```

Compare against the acceptance criteria from `PRESCREEN_ANALYSIS`. Ask one question only: *does this diff plausibly address what the issue asked for?* This is a **direction check**, not a detail check.

Flag a miss if:

- The diff is empty or trivial relative to the issue's scope.
- An acceptance criterion is not visibly addressed anywhere in the diff.
- The diff touches large areas unrelated to the issue (Implementer went rogue).

If the diff looks right: proceed to Step 7.

If it looks wrong:

- Increment `cursory_attempts`.
- If `cursory_attempts > 2`: **Stop the loop** (cap exceeded in cursory).
- Otherwise: re-engage the Implementer with a directional correction naming the specific criterion or area that doesn't appear addressed. After it returns `DONE`, return to Step 5 (re-verify before re-checking direction).

Note: returning to Step 5 does not reset `verify_attempts`. A verify failure after a cursory-fix consumes the same 2-attempt budget. This is intentional — across the slice's lifetime, the Implementer gets at most 2 chances per gate.

---

### Step 7 — Spawn the Reviewer

Read the Reviewer prompt template:

```bash
cat ~/.claude/ralph/reviewer.md
```

Substitute placeholders:

- `{{NUMBER}}`, `{{TITLE}}` — as before
- `{{ACCEPTANCE_CRITERIA}}` — extracted from the issue body
- `{{GIT_DIFF}}` — output of `git diff -U20 $SLICE_BASE`

Spawn an Agent with `subagent_type: general-purpose` and the filled prompt. Use a fresh agent each Reviewer call — Reviewers are stateless.

Before reading the response, assert the Reviewer did not edit files. The Reviewer is read-only by contract — capture a digest of the slice's state before spawning, then re-check after it returns:

```bash
# Before spawning the Reviewer:
PRE_REVIEW_DIGEST=$(git diff "$SLICE_BASE"; git ls-files --others --exclude-standard | xargs -I{} sha1sum {} 2>/dev/null)

# After it returns:
POST_REVIEW_DIGEST=$(git diff "$SLICE_BASE"; git ls-files --others --exclude-standard | xargs -I{} sha1sum {} 2>/dev/null)
```

If `PRE_REVIEW_DIGEST != POST_REVIEW_DIGEST`, the Reviewer modified files — this is a contract violation. Reset the working tree to the Implementer's state (`git checkout -- .` then `git clean -fd`), record an agent-oddity observation, post a comment on the sub-task ("Ralph stopped on #N: Reviewer contract violation"), and **Stop the loop**.

The Reviewer returns either:

- `APPROVED` — proceed to Step 8.
- `FINDINGS` followed by `## Critical`, `## High`, `## Medium`, `## Low` sections.

**Triage the findings:**

- Append all `## Medium` items to `medium_findings`.
- Append all `## Low` items to `retrospective_observations` as systemic signal.
- If `## Critical` AND `## High` are both empty: treat as `APPROVED`, proceed to Step 8.
- Otherwise: increment `reviewer_attempts`.
  - If `reviewer_attempts > 2`: **Stop the loop** (cap exceeded in reviewer).
  - Otherwise: re-engage the Implementer (see **Re-engagement**) with the Critical + High findings as the directive. After it returns `DONE`, return to Step 5.

If the Reviewer returns `BLOCKED`: see **Stop the loop**.

---

### Step 8 — Commit and close

Derive the file list from git itself — do not trust agent self-reports:

```bash
CHANGED=$(git diff --name-only "$SLICE_BASE")
UNTRACKED=$(git ls-files --others --exclude-standard)
git add -- $CHANGED $UNTRACKED
```

Derive a commit type from the sub-task title prefix if obvious (`fix:`, `docs:`, etc.) — otherwise default to `feat`. Commit using a HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
<type>: <sub-task title summary>

Closes #<NUMBER>
EOF
)"
```

Assert the working tree is clean:

```bash
git status --porcelain
```

If non-empty: surface the leftover paths, record in `retrospective_observations`, and **Stop the loop**.

Close the sub-task:

```bash
gh issue close <NUMBER> --comment "Implemented in $(git rev-parse --short HEAD)."
```

Update the cached `CHILD_ISSUES` entry's `state` to `CLOSED` so Step 1 skips it next iteration. Append `{number, title}` to `closed_slices` for the retrospective. Return to Step 1.

---

## Re-engagement

When a gate needs the Implementer to address feedback:

- **Attempt 1 (first re-engagement on this slice):** use `SendMessage` to the existing Implementer agent. The message body is just the corrective directive — the agent already has the original prompt's context.
- **Attempt 2 (second re-engagement on this slice):** spawn a fresh Implementer via `Agent` with the full prompt + the directive injected as additional context. Use a new agent name (e.g. `implementer-<NUMBER>-retry`).

The cap is per gate, so a slice can in principle reach a fresh Implementer at the second attempt of any single gate. In practice this is rare.

---

## Stop the loop

When the loop must stop mid-PRD (BLOCKED from a sub-agent, cap-exceed in a gate, dirty working tree after commit):

1. Discard the current slice's uncommitted changes so the branch is left in a clean, reviewable state. Prior closed slices remain — only the in-flight slice is wiped:

   ```bash
   git reset --hard "$SLICE_BASE"
   git clean -fd
   ```

2. Post a comment on the offending sub-task naming the cause:

   ```bash
   gh issue comment <NUMBER> --body "Ralph stopped on #<NUMBER>: <one-line reason>"
   ```

3. Append `{number, title, reason}` to `blocked_or_abandoned`.
4. Proceed directly to **End of session** (skip PRD validation).

The branch is now in a state that the user can either re-run `/ralph <PRD#>` against (Setup will detect and resume) or review and open a PR from.

---

## PRD validation

Only reached when every open child sub-task has been closed cleanly.

Read the PRD-Reviewer prompt template:

```bash
cat ~/.claude/ralph/prd-reviewer.md
```

Substitute placeholders:

- `{{PRD_NUMBER}}`, `{{PRD_TITLE}}` — from `PRD_ISSUE`
- `{{PRD_BODY}}` — the full PRD body
- `{{SKIPPED_SLICES}}` — `skipped` list (so the validator doesn't flag intentionally-skipped scope)
- `{{CUMULATIVE_DIFF}}` — output of `git diff -U10 $DEFAULT...HEAD`

Spawn an Agent (`subagent_type: general-purpose`, fresh agent) with the filled prompt.

The PRD-Reviewer returns either:

- `APPROVED` — proceed to **End of session**.
- `FINDINGS` with the same priority sections as the slice Reviewer.

**Triage PRD-Reviewer findings the same way:**

- Append `## Medium` to `medium_findings`, `## Low` to `retrospective_observations`.
- If Critical + High are both empty: proceed to **End of session**.
- Otherwise: spawn an Implementer to fix the gap. PRD-fix attempts have their own counter `prd_fix_attempts` (cap 2), separate from per-slice gate counters. **Both** PRD-fix attempts use a fresh `Agent` call — there is no prior Implementer with relevant context, so SendMessage never applies here.

  Capture a fresh slice base for the gap fix:

  ```bash
  PRD_FIX_BASE=$(git rev-parse HEAD)
  ```

  Substitute the Implementer template with synthetic placeholder values:

  - `{{NUMBER}}` = `PRD-${PRD_NUMBER}-gap`
  - `{{TITLE}}` = `Address PRD review gap`
  - `{{PRESCREEN_ANALYSIS}}` = the Critical + High findings reformulated as acceptance criteria, one per finding
  - `{{FULL_ISSUE_BODY}}` = the relevant excerpt of the PRD body (the criteria the findings reference) plus the verbatim findings text

  On Implementer `DONE`: run the verify gate (`VERIFY_COMMANDS`) using `PRD_FIX_BASE` as the diff anchor. If it fails, increment `prd_fix_attempts` and re-spawn (subject to the cap). On verify pass, commit:

  ```bash
  git add -- $(git diff --name-only "$PRD_FIX_BASE") $(git ls-files --others --exclude-standard)
  git commit -m "chore: address PRD review feedback"
  ```

  No `Closes #` trailer — no associated sub-task. Then re-run PRD validation.

  On cap-exceed or BLOCKED: append the unresolved findings to `medium_findings` (so the user sees them at end of session), stop PRD validation, proceed to **End of session**.

---

## End of session

Print the retrospective. Format:

```
## Ralph session complete

### Closed
- #N: Title

### Skipped at pre-screen
- #N: Title — <criterion that failed>
(omit section if empty)

### Blocked or abandoned
- #N: Title — <reason>
(omit section if empty)

### PRD validation
APPROVED
(or)
ISSUES — <count> findings, see medium offers below
(or)
SKIPPED — loop stopped before PRD validation

### Observations
**Ralph loop improvements** — pre-screen / prompt / gate / response-format issues you noticed during the session.
(omit if nothing)

**Agent oddities** — unexpected sub-agent behaviour (unusual fix iteration counts, surprising interpretations, response format edge cases).
(omit if nothing)

**Low-priority pattern signal** — synthesise `retrospective_observations` (low-priority findings) into themes if there are recurring patterns. List individual lows only if they form a coherent group.
(omit if nothing)

If all three sub-sections are empty: print "No observations this session."
```

Then, if `medium_findings` is non-empty, use **AskUserQuestion** (multi-select) to offer creating GitHub issues for each medium finding. Each option's label is a short summary; the description is the finding's full text.

For each finding the user selects:

```bash
gh issue create \
  --title "<short summary>" \
  --body "$(cat <<'EOF'
<finding body>

## Parent #<PRD_NUMBER>
EOF
)"
```

If the user selects none, or `medium_findings` is empty, skip the creation step.

Finally, print:

- The branch name.
- A suggested next command: `gh pr create --title "<PRD title>" --body "Closes #<PRD_NUMBER>\n\n<slice list>"` — for the user to run when they're ready.

---

## Agents you spawn

All sub-agents use `subagent_type: general-purpose`. Their role identity lives in the first line of the prompt template ("You are the Implementer for…").

- **Implementer** — `~/.claude/ralph/implementer.md`. Writes code following TDD. Used for initial implementation, verify-failure re-engagement, cursory-miss re-engagement, Reviewer-finding re-engagement, and PRD-Reviewer gap fills.
- **Reviewer** — `~/.claude/ralph/reviewer.md`. Reads a slice diff, returns priority-tiered findings. Read-only by instruction.
- **PRD-Reviewer** — `~/.claude/ralph/prd-reviewer.md`. Reads the cumulative PRD diff against the PRD body, returns priority-tiered findings.

You — the Orchestrator — are the current Claude session. You do not spawn yourself.
