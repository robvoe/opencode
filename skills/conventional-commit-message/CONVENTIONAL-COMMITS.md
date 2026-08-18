# Conventional Commit Messages

See how a minor change to your commit message style can make a difference.

```
git commit -m"<type>(<optional scope>): <description>" \
  -m"<optional body>" \
  -m"<optional footer>"
```

Note: This cheatsheet is opinionated, however it does not violate the specification of conventional commits.

## Commit Message Formats

### General Commit

```
<type>(<optional scope>): <description>
empty line as separator
<optional body>
empty line as separator
<optional footer>
```

### Initial Commit

```
chore: init
```

### Merge Commit

```
Merge branch '<branch name>'
```

Follows default git merge message.

### Revert Commit

```
Revert "<reverted commit subject line>"
```

Follows default git revert message.

## Types

- Changes relevant to the API or UI:
  - `feat` Commits that add, adjust or remove a feature to/of/from the API or UI
  - `fix` Commits that fix an API or UI bug of a preceded `feat` commit
- `refactor` Commits that rewrite or restructure code without altering API or UI behavior
  - `perf` Commits are special type of refactor commits that specifically improve performance
- `style` Commits that address code style (e.g., white-space, formatting, missing semi-colons) and do not affect application behavior
- `test` Commits that add missing tests or correct existing ones
- `docs` Commits that exclusively affect documentation
- `build` Commits that affect build-related components such as build tools, dependencies, project version, ...
- `chore` Commits that represent tasks like initial commit, modifying .gitignore, ...

> Note: There is intentionally **no `ops` type** in this project's convention. This repository lies in the ops realm (infrastructure / deployment / CI-CD), so using `ops` as a type is redundant. Map the change to the type that best describes the actual change (`feat`, `fix`, `docs`, `refactor`, `build`, `chore`, ...) even if it touches infrastructure.

## Scopes

- The scope provides additional contextual information.
- The scope is an optional part.
- Allowed scopes vary and are typically defined by the specific project.
- Do not use issue identifiers as scopes.

## Breaking Changes Indicator

- A commit that introduces breaking changes must be indicated by an `!` before the `:` in the subject line, e.g. `feat(api)!: remove status endpoint`.
- Breaking changes should be described in the commit footer section, if the commit description isn't sufficiently informative.

## Description

- The description contains a concise description of the change.
- The description is a mandatory part.
- Use the imperative, present tense: "change" not "changed" nor "changes".
  - Think of "This commit will..." or "This commit should...".
- Do not capitalize the first letter.
- Do not end the description with a period.
- In case of breaking changes also see Breaking Changes Indicator.

## Body

- The body should include the motivation for the change and contrast this with previous behavior.
- The body is an optional part.
- Use the imperative, present tense: "change" not "changed" nor "changes".

## Footer

- The footer should contain issue references and information about Breaking Changes.
- The footer is an optional part, except if the commit introduces breaking changes.
- Optionally reference issue identifiers (e.g., `Closes #123`, `Fixes JIRA-456`).
- Breaking Changes must start with the word `BREAKING CHANGE:`
  - For a single line description just add a space after `BREAKING CHANGE:`
  - For a multi line description add two new lines after `BREAKING CHANGE:`

## Versioning

- If your next release contains commit with...
  - Breaking Changes incremented the major version
  - API relevant changes (`feat` or `fix`) incremented the minor version
- Else increment the patch version

## Examples

- `feat: add email notifications on new direct messages`
- `feat(shopping cart): add the amazing button`
- `feat!: remove ticket list endpoint`
  - refers to JIRA-1337
  - `BREAKING CHANGE: ticket endpoints no longer supports list all entities.`
- `fix(shopping-cart): prevent order an empty shopping cart`
- `fix(api): fix wrong calculation of request body checksum`
- `fix: add missing parameter to service call`
  - The error occurred due to <reasons>.
- `perf: decrease memory footprint for determine unique visitors by using HyperLogLog`
- `build: update dependencies`
- `build(release): bump version to 1.0.0`
- `refactor: implement fibonacci number calculation as recursion`
- `style: remove empty line`

## Source

This document is adapted from a public gist: https://gist.github.com/qoomon/5dfcdf8eec66a051ecd85625518cfd13

For documentation/provenance purposes only. Do NOT fetch or browse this URL during skill execution — it is only referenced so humans know where the convention came from.
