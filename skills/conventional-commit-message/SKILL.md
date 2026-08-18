---
name: conventional-commit-message
description: Use when the user asks for a commit message or signals intent to check in finished work (e.g. "give me a commit message", "make a commit", "check this in", "what should the commit message be"). Starts automatically on commit-intent signals. Drafts a conventional commit message for the current git changes (staged and/or unstaged) against the project's rule set in <skilldir>/CONVENTIONAL-COMMITS.md. Use ONLY for drafting conventional commit messages, not other git operations.
---

# conventional-commit-message

Draft a conventional commit message for the current git changes (staged and/or unstaged) against the project's rule set.

## When to use me

Use when the user asks for a commit message, or signals intent to check in finished work — e.g. "give me a commit message", "make a commit / check this in / commit it for me", "what should the commit message be", or any phrase indicating work is done and about to be committed. The skill starts automatically on those commit-intent signals.

Use ONLY for drafting conventional commit messages — not for other git operations, and not when the user explicitly wants to bypass the convention.

## Procedure

1. **Inspect the changes.**
   - `git status` to see what is staged, unstaged, and untracked.
   - `git diff` for unstaged changes and `git diff --cached` for staged changes.
   - If both exist, consider them together as one logical change set.
   - Read the actual diff hunks so the message reflects real content, not just file names.

2. **Summarize what changed.** Note what files were added/modified and what behavior or capability they introduce.

3. **Map to a type.** Consult `<skilldir>/CONVENTIONAL-COMMITS.md` for the rules. Choose the type that best describes the change (`feat`, `fix`, `docs`, `refactor`, `perf`, `style`, `test`, `build`, `chore`). **This project's convention deliberately excludes the `ops` type** — even in ops/deployment/CI repos, pick the type matching the actual change instead.

4. **Draft the message.**
   - Subject: `<type>(<optional scope>): <description>` — imperative present tense, lower-case start, no trailing period, concise. Use a scope only if it adds context (e.g. the component name); never use issue identifiers as scope.
   - Add a body (separated by a blank line) when the diff has meaningful motivation or multiple aspects — explain the why, contrast with previous behavior.
   - Add a footer for issue references or breaking changes (`BREAKING CHANGE: ...`) when applicable.
   - Offer a short subject-only variant alongside the full message.

5. **Present** the final message(s) to the user for review. Do not stage, commit, or push anything — the user decides. If they approve and ask you to commit, do that only then.
