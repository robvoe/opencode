---
name: koopa-manifest-store-upstream-url
description: Use when the user wants the deployment/upstream/internal URLs of a service in the koopa Kubernetes environment, e.g. "give me the upstream URL of X", "where is X reachable", "the internal URL of X", a bare deployment/artifact name like product-detection-vlm, or any mention of koopa manifest store. Looks up the rendered DeploymentInstance manifests in the portal-platform/koopa-manifest-store GitLab group via mam-mcp to build internal (svc.cluster.local) and upstream (mf-mesh) URLs plus a live reachability check.
---

# koopa-manifest-store-upstream-url

Look up the deployment URLs (internal + upstream/mesh) of a deployed service in the koopa Kubernetes environment, based on the rendered manifests in the `portal-platform/koopa-manifest-store` GitLab group.

## Automated invocation

This skill runs automatically: you don't need to call it by name. As soon as the user says something that implies they want deployment/service URLs in the koopa environment — e.g. "give me the upstream URL of X", "where is X reachable", "the internal URL of X", a bare deployment/artifact name like `product-detection-vlm`, or any mention of koopa manifest store — invoke this skill. If you keep the skill loaded, simply continue with the lookup based on the deployment name already present in the conversation. Ask the user for the deployment name only if it is genuinely not derivable from context.

## Prerequisite: mam-mcp availability

Before doing anything, check that the `mam-mcp` MCP server is available (i.e. the `mam-mcp_gitlab_*` tools are callable). If `mam-mcp` is not available, do NOT continue: inform the user that `mam-mcp` is required for this skill and abort immediately.

## Goal

Given a deployment/artifact name (e.g. `product-detection-vlm`), produce, for every manifest match, two fully-qualified URLs:

- **internal**: `http://<instance>.<namespace>.svc.cluster.local:<port>`
- **upstream**: `https://<instance>.mf-mesh.<cluster>.<dc>.poinfra.server.lan` (istio mesh gateway, port 443)

plus a live reachability annotation from `curl -ikX`. Everything is done via `mam-mcp` GitLab APIs — no repository checkout, no local clone, no workdir needed.

## Steps

1. **Find the manifest(s).** Search GitLab Advanced Search:
   `mam-mcp_gitlab_search_code` with query `<deployment-name> filename:*.yml` (limit high enough, e.g. 50).
   Filter the results down to actual manifests: basename/path ends in `.yml`, path has the shape `<infoSystem>/<artifactId>/<cluster>/<name>.yml` (at least 3 directory segments), and the file content starts with `kind: DeploymentInstance`. Ignore noise hits like `.gitlab-ci.yml`, `README.md`, `pom.xml`, `helm-values/*.yml`.
   Multiple matches are expected and normal — the same deployment can be rendered into several tenants/clusters/stages.

2. **Read each manifest.** For each candidate use `mam-mcp_gitlab_repo_read_text_file` with:
   - project = `portal-platform/koopa-manifest-store/<tenant>` (derive the tenant repo from the match; the default branch is `main`, not `master`)
   - ref = `main`
   - path = the manifest path from the search result.
   Read the whole file (it contains multiple `---`-separated resources). Use the `filter` parameter to grep for the key fields if the file is large.

3. **Construct the full URLs** from these manifest fields:
   - `instance` = `metadata.name` of the `DeploymentInstance` (e.g. `smartsearch-backend-product-detection-vlm-any-live`)
   - `namespace` = `metadata.namespace` (or `spec.namespace`)
   - internal host = `DestinationRule.spec.host` (already fully qualified, e.g. `<instance>.<namespace>.svc.cluster.local`)
   - internal port = `Service.spec.ports[0].port` (e.g. `8000`; the same port number is used in the VirtualService destinations)
   - upstream host = the `spec.hosts` entry of the `VirtualService` whose name ends in `-istio` that is NOT a `*.svc.cluster.local` entry (e.g. `<instance>.mf-mesh.be-prod-iz2-bap.poinfra.server.lan`). The domain suffix is `<cluster>.<dc>.poinfra.server.lan`, where `<dc>` is the datacenter code (e.g. `bap`, `bs`).
   Build:
   - internal = `http://<internal-host>:<internal-port>`
   - upstream = `https://<upstream-host>` (HTTPS on default port 443; the upstream host CNAMEs to an `istio-ingressgateway-...poinfra.server.lan` address)

4. **Live reachability check** with `curl -ikX`:
   `curl -ikX GET --max-time 12 --connect-timeout 8 https://<upstream-host>/v1/models`
   - an HTTP response below 500 (including 404, HTTP/2 status is fine) means the mesh gateway answered → **reachable**.
   - if `/v1/models` returns 404 or the endpoint is not a model server, fall back to the root path:
     `curl -ikX GET --max-time 12 --connect-timeout 8 https://<upstream-host>/`
   - if both `/v1/models` and root are NOT reachable (connection refused, timeout, no TLS response), still report the match and its unchecked URLs — do NOT silently drop the match. Show the URL(s) and let the user decide whether to use them. (Reachability can fail for many reasons: service scaled to zero, LB/tenant restrictions, network path, etc.)
   - the internal `svc.cluster.local` URL is cluster-internal and will not resolve from outside the cluster; do not curl it — mark it as in-cluster only.

5. **Output a compact table**, one row per match:
   tenant / informationSystem / cluster / stage / namespace / internal URL / upstream URL / reachability (reachable via /v1/models, reachable via root, unreachable — shown as-is for user decision).

## Pitfalls

- Default branch of every tenant repo is `main`, not `master`.
- `koopa-manifest-store` is a GROUP containing ~34 per-tenant repositories (mf, mamqa, p3, ams, mf, obe, dso, ...), not a single repo. Rely on group-wide Advanced Search rather than cloning.
- The upstream mesh host (`.mf-mesh.<cluster>.<dc>.poinfra.server.lan`) is an istio ingress gateway and only answers HTTPS on port 443 — the manifest's port (8000) is the internal Service port and is NOT exposed on the mesh host.
- The port for the internal URL is the `Service.spec.ports[0].port` (ClusterIP), not `targetPort`.
- A deployment name usually corresponds to one or a few manifests; a name like `test-data-conductor-server` also appears in unrelated source repos — filter strictly by the manifest path shape + `kind: DeploymentInstance`.
