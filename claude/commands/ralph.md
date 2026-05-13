---
description: "Autonomous GitHub issue loop via orchestrated sub-agents"
argument-hint: "[max-issues | prd <issue-number>]"
---

# Ralph

You are the Ralph orchestrator. Autonomously select, pre-screen, implement, review, and close `ready-for-agent` GitHub issues using sub-agents. You handle orchestration, git, and GitHub — sub-agents handle implementation and review.

---

## Setup

### Parse arguments

`$ARGUMENTS` is one of:

- Empty or an integer N — **standard mode**, process up to N issues (0 or absent = no limit).
- `prd <number>` — **PRD mode**, process all child issues of the named PRD issue on a single shared branch.

Initialise:
- `closed` counter = 0
- `max_issues` = N (or 0 for unlimited)
- `mode` = `standard` or `prd`
- `retrospective` = empty list of observations

### Read project conventions

Read the project's `CLAUDE.md` if present:

```bash
cat CLAUDE.md 2>/dev/null || cat ~/.claude/CLAUDE.md
```

Store this as `PROJECT_CONVENTIONS`. Inject it into every sub-agent prompt.

### PRD mode: discover child issues and create shared branch

If `mode = prd`:

1. Fetch the PRD issue:

```bash
gh issue view <PRD_NUMBER> --json number,title,body
```

2. Find child issues by scanning all issues for a `## Parent` section referencing the PRD:

```bash
gh issue list --state all --label ready-for-agent \
  --limit 200 \
  --json number,title,body,state \
  --jq '[.[] | select(.body | test("(?i)##\\s*Parent\\s+#<PRD_NUMBER>"))] | sort_by(.number)'
```

Set `max_issues` to the number of child issues returned. The work queue is the child issues with `state: OPEN`, sorted by number ascending. Already-closed children (from a prior partial run) are skipped automatically in the loop.

3. Determine the default branch and create the shared feature branch from it:

```bash
DEFAULT=$(gh repo view --json defaultBranchRef --jq -r '.defaultBranchRef.name')
git checkout "$DEFAULT" && git pull
```

Derive a short, lowercase, hyphen-separated slug from the PRD title — capture the subject in 3–5 words, drop type prefixes (feat, fix, chore, etc.), drop articles and filler. Use that as `<SLUG>`.

```bash
git checkout -b "feature/<PRD_NUMBER>_<SLUG>"
```

---

## Main loop

Repeat until `closed` reaches `max_issues` (if set) or no eligible issue is found.

---

### Step 1 — Find the next eligible issue

**Standard mode:** query open `ready-for-agent` issues:

```bash
gh issue list --state open --label ready-for-agent \
  --json number,title,body \
  --jq '[.[] | {number, title, body}] | sort_by(.number)'
```

**PRD mode:** use the pre-discovered child issue queue in ascending number order, skipping any already `CLOSED`.

For each candidate, parse its `## Blocked by` section. For each `#X` listed:

```bash
gh issue view X --json state --jq '.state'
```

An issue is eligible when all blockers are `CLOSED`, or no `## Blocked by` section exists.

If no eligible issue is found: proceed to the **On completion** section.

---

### Step 2 — Pre-screen the issue

Fetch the full issue body and evaluate it against all four criteria:

1. **Acceptance criteria present** — a verifiable definition of done exists (not just a description of the problem).
2. **Scope is bounded** — implementation requires no decisions outside the codebase (no "discuss with team", "figure out the right approach").
3. **Blockers explicit** — any dependencies are captured in `## Blocked by`, not buried in prose.
4. **No ambiguous ownership** — not a meta-task, discussion thread, or spike.

If any criterion fails: post a comment naming the specific gap, record the skip in `retrospective`, and move to the next issue.

```bash
gh issue comment <NUMBER> --body "Ralph skipped #<NUMBER>: <specific criterion that failed>"
```

If all criteria pass: record a brief summary of your reading — the acceptance criteria in your own words, the apparent scope boundary, any non-obvious constraints you noticed. This becomes `PRESCREEEN_ANALYSIS` and is passed to the implementation agent.

---

### Step 3 — Create a feature branch (standard mode only)

```bash
DEFAULT=$(gh repo view --json defaultBranchRef --jq -r '.defaultBranchRef.name')
git checkout "$DEFAULT" && git pull
```

Derive a short, lowercase, hyphen-separated slug from the issue title — capture the subject in 3–5 words, drop type prefixes (feat, fix, chore, etc.), drop articles and filler. Use that as `<SLUG>`.

```bash
git checkout -b "feature/<NUMBER>_<SLUG>"
```

In PRD mode the orchestrator already created the shared feature branch during setup — skip this step.

---

### Step 4 — Spawn the implementation agent

Record the current HEAD so the review agent can diff only this slice's changes:

```bash
SLICE_BASE=$(git rev-parse HEAD)
```

Fetch the full issue: `gh issue view <NUMBER>`

Spawn an Agent with this prompt (fill all placeholders before spawning):

```
You are implementing GitHub issue #NUMBER: "TITLE".

## Orchestrator analysis

PRESCREEN_ANALYSIS

## Issue

FULL_ISSUE_BODY

## Project conventions

PROJECT_CONVENTIONS

## Steps

1. Implement the issue following the project conventions above.
2. Run any test, lint, and format commands described in the project conventions.
3. All checks must pass before responding.

Do NOT commit. Do NOT close the issue. Do NOT create branches.

## Response format

If complete:
DONE
Files: <space-separated relative paths of every file you created or modified>

If you need human direction and cannot proceed:
BLOCKED
Reason: <one concise sentence>
```

**If the agent returns `BLOCKED`:**

```bash
gh issue comment <NUMBER> --body "Ralph blocked on #NUMBER: <reason>"
```

Record in `retrospective`. Then stop the loop.

---

### Step 5 — Spawn the review agent

Get the diff for this slice only:

```bash
git diff $SLICE_BASE
```

Extract the acceptance criteria from the issue body.

Spawn an Agent with this prompt:

```
Review the following changes for GitHub issue #NUMBER: "TITLE".

## Acceptance criteria

ACCEPTANCE_CRITERIA

## Diff

GIT_DIFF

## What to check

1. Every acceptance criterion is addressed.
2. No deeply nested code or large functions.
3. No unnecessary comments — only where the WHY is non-obvious.
4. Code is self-documenting (well-named identifiers, no redundant comments).
5. No regressions visible in the diff.
6. Documentation health — if the changes affect behaviour, configuration, interfaces, or concepts referenced in CONTEXT.md, README, or inline docs, flag whether those docs need updating. Label doc-only gaps as (low-priority) if functionality is otherwise correct.

Note any issues that are minor / low-priority but not blockers — label them clearly as (low-priority).

## Response format

If the changes are acceptable:
APPROVED

If there are issues that must be fixed before committing:
ISSUES
- <issue 1>
- <issue 2>
```

If `APPROVED`: proceed to Step 6.

If `ISSUES`: proceed to Step 5a. Record any `(low-priority)` observations in `retrospective`.

---

### Step 5a — Spawn the fix agent (up to 2 attempts)

Maintain a `fix_attempts` counter per issue, starting at 0. Each time review returns `ISSUES`, increment it.

If `fix_attempts` exceeds 2:

```bash
gh issue comment <NUMBER> --body "Ralph could not resolve review feedback on #NUMBER after 2 fix attempts. Outstanding issues:\n<REVIEW_ISSUES>"
```

Record in `retrospective`. Abandon the branch (standard mode: `git checkout "$DEFAULT"`). Move to the next issue.

Otherwise, spawn an Agent with this prompt:

```
Fix the following review issues for GitHub issue #NUMBER: "TITLE".

## Files to look at

FILES_FROM_IMPLEMENTATION_AGENT

## Issues to fix

REVIEW_ISSUES

## Project conventions

PROJECT_CONVENTIONS

## Steps

1. Fix each issue listed.
2. Run any test, lint, and format commands described in the project conventions.
3. All checks must pass before responding.

Do NOT commit. Do NOT close the issue.

## Response format

If all issues are resolved:
DONE

If you need human direction:
BLOCKED
Reason: <one concise sentence>
```

**If the fix agent returns `BLOCKED`:**

```bash
gh issue comment <NUMBER> --body "Ralph blocked on review feedback for #NUMBER: <reason>"
```

Record in `retrospective`. Stop the loop.

After `DONE`: return to Step 5 to re-run the review agent.

---

### Step 6 — Commit

Stage only the files listed by the implementation (or fix) agent:

```bash
git add <file1> <file2> ...
```

Commit following the project's commit convention from `PROJECT_CONVENTIONS`. If no convention is documented, use:

```
feat: TITLE

Closes #NUMBER
```

---

### Step 7 — Open PR (standard mode)

```bash
git push -u origin "$(git branch --show-current)"
gh pr create \
  --title "<TITLE>" \
  --body "Closes #<NUMBER>"
```

The `Closes #<NUMBER>` trailer will close the issue automatically when the PR is merged — do not close it manually.

Return to the default branch for the next iteration:

```bash
git checkout "$DEFAULT"
```

Increment `closed`. If `closed` equals `max_issues`, proceed to **On completion**.

---

### Step 7 (PRD mode) — Close slice and advance

Close the child issue immediately so it is excluded from subsequent loop iterations:

```bash
gh issue close <NUMBER> --comment "Implemented in $(git rev-parse --short HEAD)."
```

Increment `closed`. If `closed` equals `max_issues`, proceed to PRD wrap-up. Otherwise continue the loop.

---

### PRD wrap-up

Push the shared branch and open one PR:

```bash
git push -u origin "$(git branch --show-current)"
gh pr create \
  --title "<PRD_TITLE>" \
  --body "$(cat <<'EOF'
Implements all vertical slices for #PRD_NUMBER.

## Slices

- #CHILD_1: CHILD_1_TITLE
- #CHILD_2: CHILD_2_TITLE
...

Closes #CHILD_1
Closes #CHILD_2
...
EOF
)"
```

Post a summary comment on the PRD issue:

```bash
gh issue comment <PRD_NUMBER> --body "All slices implemented. PR: <PR_URL>"
```

---

## On completion

Print the session retrospective to the terminal.

### Retrospective format

```
## Ralph session complete

### Closed
- #N: Title

### Skipped
- #N: Title — <reason>

### Observations

<Synthesise everything recorded in `retrospective` during the session. Group into three sections:>

**Ralph loop improvements**
Things about the loop mechanics, pre-screening, or agent prompts that could be better.
If nothing, omit this section.

**Project improvements**
Low-priority review findings that accumulated. Systemic gaps in issue quality (e.g. "3 issues lacked acceptance criteria"). Recurring patterns in what agents got wrong.
If nothing, omit this section.

**Agent oddities**
Unexpected behaviour from sub-agents — unusual number of fix iterations, surprising interpretations, edge cases in the response format.
If nothing, omit this section.

If there are no observations across all three sections, print: "No observations this session."
```
