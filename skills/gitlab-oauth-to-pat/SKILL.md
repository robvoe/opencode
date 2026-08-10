---
name: gitlab-oauth-to-pat
description: Use when git operations against a GitLab instance keep opening a browser for OAuth approval on every command — e.g. the user says the browser "asks every time", they must approve authorization on each git pull/push/fetch/clone, the git-credential-oauth / credential.helper oauth browser prompt keeps nagging, or git shows "error during OAuth token refresh ... invalid_grant". Also use when the stored OAuth token/refresh token in the OS keychain is expired or rejected and the user wants to stop approving authentication repeatedly by switching the GitLab host to a Personal Access Token (PAT) stored in the OS keychain. Requires the mam-mcp MCP server (GitLab toolset) to be installed and reachable — the skill checks for it before running. Use ONLY when the fix involves replacing git-credential-oauth with a stored PAT for a GitLab host.
---

# Switch GitLab git auth from OAuth to PAT

Stops the browser from popping up on every `git pull`/`git push`/`git fetch` for a GitLab host that uses `git-credential-oauth`. The usual cause: the stored OAuth refresh token is rejected by GitLab (`invalid_grant`), so the helper cannot refresh silently and falls back to a full browser authorization on every operation.

## Preflight — mam-mcp must be installed (REQUIRED)

Do not run the git/keychain steps until the environment is verified through mam-mcp:

1. Check that the mam-mcp MCP server is installed and reachable. The agent must have the GitLab toolset from `mam-mcp` available (e.g. `mam-mcp_gitlab_user_info`, `mam-mcp_gitlab_get_user`).
2. Confirm the configured user, e.g. call `mam-mcp_gitlab_user_info` and note the returned username so you can cross-check against the user who owns the PAT.
3. If the `mam-mcp` tools are NOT available (the call fails with "tool not found" / "MCP server not installed", or returns an error about a missing/disabled MCP server):
   - STOP. Do NOT proceed with storage or config changes.
   - Tell the user the mam-mcp MCP server is not installed/configured and ask them to set it up (or re-run the environment where it is available) before this skill can run.
4. If available, use mam-mcp GitLab calls for GitLab-side lookups (identify the user, the host, the project if known) instead of raw REST API calls.

## Verify the diagnosis first

1. Confirm the helper chain and that OAuth is last:
   ```sh
   git config --get-all credential.helper
   git --version          # needs >= 2.45 for OAuth refresh-token support
   git-credential-oauth version
   ```
2. Confirm the browser prompt is caused by a failed refresh, not something else:
   ```sh
   GIT_TERMINAL_PROMPT=0 GIT_TRACE=1 git credential fill <<'EOF'
   protocol=https
   host=<your-gitlab-host>

   EOF
   ```
   Look for `error during OAuth token refresh ... invalid_grant`.
3. Check whether the currently stored token is still valid — look at when the stored credential was written and whether the access token is already expired:
   ```sh
   security find-internet-password -a oauth2 -s <your-gitlab-host>   # macOS; mdate
   ```
   A stale `mdate` or an expired access token is a strong hint the refresh will fail.
4. Actually test the stored token against the GitLab API (read-only), not just its expiry. Read the stored password from the keychain without printing it, then call the user endpoint:
   ```sh
   TOKEN=$(printf "protocol=https\nhost=<your-gitlab-host>\n\n" | git credential fill | sed -n 's/^password=//p')
   curl -s -o /tmp/me.json -w "%{http_code}" -H "Authorization: Bearer $TOKEN" \
     "https://<your-gitlab-host>/api/v4/user"
   # 200 = token valid (username in me.json); 401 = token invalid/expired
   ```
   Report whether the stored token is still valid so the user can decide: refresh the OAuth token or (as this skill does) switch to a PAT.

## Procedure

1. Ask the user to create a PAT in the GitLab UI — it cannot be created via the API with a `read_api`-scoped token:
   - URL: `https://<your-gitlab-host>/-/user_settings/personal_access_tokens`
   - Name it, e.g. `git-credential-pat`.
   - Scopes: `read_api`, `read_repository`, `write_repository` (choose only what's needed).
   - Set an expiry so it is not done more often than necessary.
   - Have the user paste the token (it is only shown once).
   - NEVER print or log the token; treat it as a secret.
2. Cross-check the PAT's owner via mam-mcp: look up the user with `mam-mcp_gitlab_get_user` (or `mam-mcp_gitlab_user_info`) and confirm it matches the account the user created the token for. If you cannot positively confirm the account, ask the user instead of guessing.
3. Store the PAT in the OS keychain (replaces the OAuth credential):
   ```sh
   printf "protocol=https\nhost=<your-gitlab-host>\nusername=oauth2\npassword=<THE_PAT>\n\n" | git credential approve
   ```
4. Validate the new PAT immediately — confirm the token is accepted and returns the expected user before relying on it:
   ```sh
   PAT=$(printf "protocol=https\nhost=<your-gitlab-host>\nusername=oauth2\npassword=<THE_PAT>\n\n" | git credential fill | sed -n 's/^password=//p')
   curl -s -o /tmp/pat_me.json -w "%{http_code}\n" -H "Authorization: Bearer $PAT" \
     "https://<your-gitlab-host>/api/v4/user"
   # expect 200 and the username matching the account in /tmp/pat_me.json; 401 => token rejected, STOP and ask the user for a correct PAT
   ```
   If the new PAT is rejected, do NOT proceed — tell the user the token is invalid and ask them to re-create it.
5. Remove the OAuth helper and its per-host config:
   ```sh
   git config --global --unset-all credential.helper oauth
   # drop the per-host oauth* keys that git-credential-oauth added, e.g.:
   git config --global --unset-all credential.https://<your-gitlab-host>.oauthClientId
   git config --global --unset-all credential.https://<your-gitlab-host>.oauthClientSecret
   git config --global --unset-all credential.https://<your-gitlab-host>.oauthScopes
   git config --global --unset-all credential.https://<your-gitlab-host>.oauthAuthURL
   git config --global --unset-all credential.https://<your-gitlab-host>.oauthTokenURL
   ```
5. Verify locally — no OAuth helper should run and no browser should open:
   ```sh
   git config --get-all credential.helper   # osxkeychain (or wincred/libsecret) + optional cache only
   GIT_TERMINAL_PROMPT=0 printf "protocol=https\nhost=<your-gitlab-host>\n\n" | git credential fill
   GIT_TRACE=1 GIT_TERMINAL_PROMPT=0 git fetch   # trace shows only the storage helper, not oauth
   git ls-remote origin HEAD
   ```
   The `git fetch` trace should list only e.g. `git credential-osxkeychain get` — never `git credential-oauth`.
6. Verify via mam-mcp that the GitLab-side identity still works (a user-info call succeeding through the MCP toolset also confirms the environment is healthy): call `mam-mcp_gitlab_user_info` and confirm it returns a user.

## Smoke test — make sure everything actually runs

Run all of these and confirm each succeeds with no browser prompt. If any fails, STOP and report the failing step rather than calling the fix done.

1. Credential resolution returns a token (and never an OAuth authorize URL):
   ```sh
   GIT_TERMINAL_PROMPT=0 printf "protocol=https\nhost=<your-gitlab-host>\n\n" | git credential fill
   # must print password + username, with NO "oauth/authorize" URL on stderr
   ```
2. Read-only API authentication through the stored token:
   ```sh
   TOKEN=$(printf "protocol=https\nhost=<your-gitlab-host>\n\n" | git credential fill | sed -n 's/^password=//p')
   curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOKEN" "https://<your-gitlab-host>/api/v4/user"
   # expect 200
   ```
3. Real git operations against the remote (in a checked-out repo):
   ```sh
   GIT_TERMINAL_PROMPT=0 git ls-remote origin HEAD     # no prompt, exit 0
   GIT_TERMINAL_PROMPT=0 git fetch origin              # no prompt, exit 0
   GIT_TERMINAL_PROMPT=0 git pull --ff-only origin     # no prompt, no conflict, exit 0
   ```
4. Confirm the helper chain no longer contains `oauth`:
   ```sh
   git config --get-all credential.helper   # storage + optional cache only
   GIT_TRACE=1 GIT_TERMINAL_PROMPT=0 git fetch 2>&1 | grep -i credential   # never git-credential-oauth
   ```
5. mam-mcp still healthy: `mam-mcp_gitlab_user_info` returns the expected user.

Only after every smoke-test step passes, report the switch as complete.

## Notes / pitfalls

- mam-mcp is REQUIRED before running; if the `mam-mcp` MCP tools are not installed or not connected, stop and ask the user to enable/install them rather than proceeding blind.
- Use mam-mcp GitLab calls for user/host/project identification; use local git + OS commands for the actual credential stores.
- The PAT can also be used for GitLab API calls; prefer the mam-mcp tools over raw REST where they cover the need.
- Do not put real hostnames, tokens, or client IDs in any public artifact.
- If the machine has no keychain (Linux server), prefer `git credential-libsecret` or `git credential-store` instead of `osxkeychain`; the principle is identical.
- The OAuth helper must always be configured last in the chain; after this fix it is removed entirely, so ordering no longer matters.
- If a PAT expires, the user will be prompted for a password via the keychain — that is expected and only on expiry, not on every operation.
