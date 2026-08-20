---
name: conventional-commit-message
description: Use when the user asks for a commit message or signals intent to check in finished work (e.g. "give me a commit message", "make a commit", "check this in", "what should the commit message be"), or wants a guided loop that drafts conventional commit messages and commits them one by one or all at once. Drafts against the project's rule set and offers git add/commit/push only with explicit user consent. Use ONLY for conventional commit messages and their commit flow, not for other git operations.
---

# conventional-commit-message

Interactive commit-message drafting against the project's rule set in
`<skilldir>/CONVENTIONAL-COMMITS.md`, wrapped in a commit-loop you drive with short
agreements. Never stages, commits or pushes without explicit user consent.

## When to use me

Triggered by commit-intent signals: "give me a commit message", "make a commit",
"check this in", "what should the commit message be", or any phrase indicating
finished work is about to be committed.

Use ONLY for conventional commit messages and their add/commit/push flow — not for
other git operations, and not when the user explicitly wants to bypass the convention.

## Procedure (iterative loop)

### 1. Inspect what changed

- `git status` for staged, unstaged and untracked files.
- `git diff` (unstaged) and `git diff --cached` (staged); consider them together.
- Read the actual hunks so the messages reflect real content, not just filenames.
- Split the changes into **logical topics** (one topic may touch several files).
  Leave unrelated untracked junk (build artifacts, big binaries, secrets) out and
  say so. Present the proposed split and let the user adjust it.

### 2. Ask how to build the messages

Ask the user to choose between (list the one-commit option **first** and mark it
default/recommended):

- **(B) One message for everything — default/recommended** — a single combined commit.
- **(A) One message per logical change** — an iterative loop; the code is committed
  change by change, as you go.

Generate messages only after the user picks.

### 3. Draft the message(s)

For each change (or the whole set in mode B), produce in this order:

- **Shorthand** — subject only: `<type>(<optional scope>): <description>`
- **Longhand** — shorthand, blank line, body, footer.

Body: the motivation — why the change is made, contrasting with previous behavior.
Footer: issue references and/or `BREAKING CHANGE: ...` when applicable.

Consult `<skilldir>/CONVENTIONAL-COMMITS.md` for:

- Types: `feat`, `fix`, `refactor`, `perf`, `style`, `test`, `docs`, `build`,
  `chore`. **No `ops` type** — pick the type matching the actual change, even in
  ops/deployment/CI repos.
- Subject: imperative present tense, lower-case start, no trailing period. Use a
  scope only if it adds context (component name); never use issue identifiers as scope.

### 4. Offer to commit (consent-gated)

Ask which message to use (or whether to edit the wording first). At the moment of
asking whether to stage/commit/push, ALWAYS show the exact file report with this
**fixed layout** — so the user knows precisely what is being done:

```
To commit:

  staged (<n> files):
    added:     <new file>, <new file>
    modified:  <tracked file>
               <tracked file>

  left out (<n>):
    - <untracked/irrelevant file>      (reason)
    - <untracked/irrelevant file>      (reason)

  message: <proposed shorthand subject>
  steps:   git add <the staged files> → commit → push

OK to proceed?
```

- `staged` — the files you will add, grouped by `added` / `modified`; stage only the
  files belonging to the commit, never a blind `git add .`
- `left out` — untracked/irrelevant files (junk, big binaries, secrets, API keys),
  one line each, with a short reason in parentheses
- `message` / `steps` — the chosen commit message and the exact commands that will run

Then offer:

1. `git add <the staged files>`
2. `git commit -m <chosen message>`
3. `git push` (to the branch's remote)

Do **not** run any of these until the user agrees to the offer. Each offer is a
prompt, not a mandate.

### 5. Next iteration (mode A only)

After the change is committed — or the user explicitly defers it — check whether
more logical changes remain. If so, ask whether to continue with the next one and
loop back to step 3. If the user declines further messages, stop.

## Guardrails

- Commit/push only with explicit consent; the offer is a question, not an action.
- Always show the fixed file report (staged vs left out) at the moment of the
  stage/commit/push offer — never ask without reporting which files are involved.
- Mode A commits as you go; mode B (default) uses a single add/commit/push at the end.
- Leave unrelated files out of commits and tell the user they were skipped.
- Don't rewrite history (no amend / force-push) unless the user explicitly asks.
- If the user says "bypass the convention", stop the skill.
