---
name: fix-ssl-cert-error
description: Fix Python TLS certificate verification failures against self-signed internal gateways by pointing requests at a trusted CA bundle via the REQUESTS_CA_BUNDLE environment variable. Use when a Python traceback or error shows SSLCertVerificationError, CERTIFICATE_VERIFY_FAILED, "unable to get local issuer certificate", requests.exceptions.SSLError, or urllib3 "MaxRetryError ... SSLError", or when a pydantic Settings validation error appears with "Extra inputs are not permitted" / requests_ca_bundle after REQUESTS_CA_BUNDLE was (misguidedly) added to .env. The skill prints the exact fix for PyCharm, VS Code and the shell with a default CA bundle path, offers (but never performs) to edit the IDE run configuration, and lists the pitfalls (not .env, SSL_CERT_FILE/CURL_CA_BUNDLE ignored, bundle must contain the internal CA, restart needed).
compatibility: macOS with a Homebrew CA bundle (/opt/homebrew/etc/ca-certificates/cert.pem) and an internal/self-signed gateway (e.g. the ASSIST .mf-mesh... server.lan hosts); applies to any process using requests/urllib3 (including inference_sdk).
---

# Fix SSL Certificate Verification Error

Fix Python TLS certificate verification failures (`CERTIFICATE_VERIFY_FAILED` /
`unable to get local issuer certificate`) against self-signed internal gateways by
trusting the internal CA via the `REQUESTS_CA_BUNDLE` environment variable. The
skill detects the failure, resolves the CA bundle path, and prints the exact install
instructions; it never edits config files on its own.

## 1. Detect the trigger

The skill activates on either of these error signatures:

- **Primary — TLS verify failure** (any Python process using `requests`, which
  also covers `inference_sdk`): traceback or error containing
  - `SSLCertVerificationError` / `[SSL: CERTIFICATE_VERIFY_FAILED]`
  - `certificate verify failed: unable to get local issuer certificate`
  - `requests.exceptions.SSLError`
  - `urllib3.exceptions.MaxRetryError` ... `(Caused by SSLError(...))`
- **Secondary — `.env` misplacement**: a pydantic `Settings` validation error with
  `extra_forbidden` / `Extra inputs are not permitted` naming `requests_ca_bundle`,
  i.e. the user added `REQUESTS_CA_BUNDLE` to `.env`.

## 2. Diagnose in one line

The target is an internal gateway with a self-signed certificate. `requests`
(`verify=True` default) verifies against the `certifi`/system CA store, which does
not trust that certificate, so TLS verification fails. The same applies to
`inference_sdk` (Roboflow YOLO calls to the gateway), because it uses `requests`
internally. The fix is to make `requests` trust the internal CA, not to disable
verification.

## 3. Resolve the CA bundle path

- Default path (this notebook): `/opt/homebrew/etc/ca-certificates/cert.pem`
  (Homebrew's OpenSSL bundle, verified to exist with ~200 CAs).
- Verify it exists: `ls` the path; if it is missing (different machine/setup), ask
  the user where their internal CA bundle lives and use that instead.

## 4. Give the fix

Set `REQUESTS_CA_BUNDLE=<resolved path>` in the **process environment** (not `.env`),
then restart the run/debug session. Present all three variants:

- **PyCharm:** Run ▸ Edit Configurations… → select the run configuration →
  **Environment variables** (field or dialog) → add
  `REQUESTS_CA_BUNDLE=/opt/homebrew/etc/ca-certificates/cert.pem`
  (or the resolved path).
- **VS Code:** in `.vscode/launch.json`, add to the Python debug configuration:
  `"env": {"REQUESTS_CA_BUNDLE": "/opt/homebrew/etc/ca-certificates/cert.pem"}`.
- **Shell:** `export REQUESTS_CA_BUNDLE=/opt/homebrew/etc/ca-certificates/cert.pem`
  (or inline: `REQUESTS_CA_BUNDLE=/opt/homebrew/etc/ca-certificates/cert.pem python -m ...`).

## 5. Offer, never apply

After printing the instructions, offer (as a question, never automatically) whether
the user wants the env var written into the IDE run configuration, e.g. PyCharm
(`.idea/*.run.xml`) or VS Code (`.vscode/launch.json`).

## 6. Pitfalls

- **Not `.env`:** pydantic-settings reads `.env` into the `Settings` model and does
  not export values to `os.environ`; `requests` reads the real environment. A
  `REQUESTS_CA_BUNDLE` in `.env` causes an `extra_forbidden` error and never reaches
  `requests`. (This is also the skill's secondary trigger above.)
- **`SSL_CERT_FILE` and `CURL_CA_BUNDLE` are ignored** by this requests/urllib3 stack
  (verified empirically) — do not suggest them.
- **Bundle must contain the internal CA:** if verification still fails with the var
  set, the bundle does not include the CA that signed the gateway certificate; the
  internal CA must be appended or pointed to.
- **Restart needed:** env vars are read at process start; the PyCharm/VS Code/shell
  session must be restarted after the change.
