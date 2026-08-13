---
name: artifactory-docker-images
description: Use when you need the full inventory of a project's Docker images in the MAM
  Artifactory, starting from either a GitLab repository URL/path or an image name, and want
  it presented as three separate tables (release, staging, snapshot) with cross-reference
  hints between them (e.g. "give me all images of <project>", "which versions were staged?").
---

# Artifactory Docker Image Inventory

Build a three-table inventory (release / staging / snapshot) of all Docker images belonging
to one project in the MAM Artifactory, with cross-reference hints linking the stages.

## Prerequisite: mam-mcp

This skill relies on the MAM MCP server (the `mam-mcp_artifactory_*` tools) to query
Artifactory. If any of these tools is not present/available, **stop immediately** and do
not try to guess or reconstruct the data by any other means; return a clear error message
stating that **mam-mcp is missing** and that the skill cannot run without it.

## Input: image path address

From either of these two pieces of information you can derive the image pull path:

- **GitLab URL / project path**, e.g. `https://git.mam.dev/mf/smartsearch/my-project.git`
  → image path: `internal/mf/smartsearch/my-project`
  (drop `.git`, prepend `internal/`)
- **Image name / path** directly, e.g. `internal/mf/smartsearch/my-project` (fuzzy-matchable)

The pull host is always `cr.mam.dev`.

## Procedure

1. Normalize to an image name (from GitLab URL or given directly).
2. Search Artifactory via mam-mcp: `mam-mcp_artifactory_search_docker` with the image
   name. Results return one row per (repo, tag) with a full pull address and modification
   time.
3. Group results by the three stage repos:
   - `docker-snapshot-local` → per-commit SHA tags
   - `docker-staging-local` → semver tags + `latest`
   - `docker-release-local` → official releases
   Optionally confirm a repo is empty by listing it via
   `mam-mcp_artifactory_list` (`docker-*-local/...`) — a 404 means nothing was ever
   promoted there; keep an empty table rather than dropping it.
4. Render exactly three tables, one per stage, with the pull base
   `cr.mam.dev/<image-path>` shared across all three, and a cross-reference column.

## Table template

Cross-reference chain concept: snapshot `f6dd3555` → staging `0.0.3` → `latest` → release.

**Release (`docker-release-local`)**
| Tag | Modified | Cross-ref |
|---|---|---|
| — | — | *(none — not officially released yet)* |

**Staging (`docker-staging-local`, base: `cr.mam.dev/<image-path>`)** (1)
| Tag | Modified | Cross-ref (source commit) |
|---|---|---|
| `<semver>` | `<ISO date>` | built from `<commit-sha>` (in snapshot) |
| `latest` | `<ISO date>` | points to `<semver>` → `<commit-sha>` |
| `<older semver>` | `<ISO date>` | no matching snapshot found |

(1) Replace `<image-path>` with the actual path; the `<commit-sha>` in this stage's
cross-ref should appear in the snapshot table below.

**Snapshot (`docker-snapshot-local`, base: `cr.mam.dev/<image-path>`)** (2)
| Tag (commit) | Modified | Cross-ref |
|---|---|---|
| `<commit-sha>` | `<ISO date>` | → staged as `<semver>` / `latest` |
| `<commit-sha>` | `<ISO date>` | — |

(2) Only the newest commit SHAs are typically retained; older SHAs of staged versions may
be gone.

## Pitfalls

- Tag namespaces differ per stage: snapshot = commit SHAs, staging = semver + `latest`.
  They are separate tables precisely because there is no shared key.
- Cross-referencing staging → source commit requires knowing which commit a version was
  promoted from; that info lives in the CI log (e.g. "Copying artifact ...
  `<sha>/` to: ...`<version>`"), not in Artifactory. If unknown, write
  "no matching snapshot found" instead of guessing.
- The image-name search is fuzzy; a repo hint from a CI log (e.g.
  `docker-staging-local/...`) helps pick the right stage, but never rely on it alone.
- Never guess the release registry or invent tags; query Artifactory and use only results
  that actually exist.
- Without mam-mcp the skill cannot run — abort with an error, never fabricate data.
