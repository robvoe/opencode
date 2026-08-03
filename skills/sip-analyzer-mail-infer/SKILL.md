---
name: sip-analyzer-mail-infer
description: Send mail content to the analyzer's POST /predict endpoint and get a prediction. Use this skill when John wants to submit a mail (subject, sender, recipient, body text) to the analyzer for prediction/classification. The skill always sends the content in BOTH body.plain and body.html. The analyzer endpoint (host/port) is inferred from John's instruction, defaulting to http://localhost:8080. Covers the request schema, the dual-body rule, media types, and a helper script (send.sh).
compatibility: Requires jq and curl. Network access to the analyzer endpoint (inferred from John's instruction; default http://localhost:8080). No auth headers required.
---

# Analyzer Mail Skill

Send mail content to the analyzer and get a prediction back.

> **Endpoint is inferred from John's instruction.** If John names a host/port/URL,
> use it (`--url` / `ANALYZER_URL`). Otherwise default to `http://localhost:8080`.

## Endpoint

- **Method / path**: `POST /predict` (V1 API only — `/estimation` and
  `/filterpreconditions` are 404)
- **Content-Type** (request): `application/vnd.ui.trinity.message.textual-v1+json`
- **Accept** (response): `application/vnd.mam.sip.prediction.list-v1+json`

Discover options at any time:

```bash
curl -s -X OPTIONS "$ANALYZER_URL/predict" -v
```

## ⭐ Core Rule: Always Send Both Plain and HTML

Every request populates **both** `body.plain` and `body.html` with the same
content. When John supplies only plain text, wrap it into minimal HTML and mirror
it into the html block. The `body.html` object requires **all three** fields:

```
body.html.mediaType     "text/html"
body.html.contentPlain  <plain-text mirror>   (REQUIRED)
body.html.contentHtml   <html markup>         (REQUIRED)
```

## Helper Script

`send.sh` builds the JSON (via `jq`, so escaping is safe) and POSTs it.

```bash
# Minimal — plain text only; html is auto-generated and both bodies are sent
./send.sh --plain "Sehr geehrte Frau MUSTERMANN, wir freuen uns."

# Full example, endpoint inferred from instruction
./send.sh \
  --url http://localhost:8080 \
  --system webde \
  --subject "Ihre De-Mail-Bestellung" \
  --from kundenservice@1und1.de --from-name "WEB.DE Kundenservice" \
  --to testuser@web.de \
  --date "Mon, 29 Jun 2020 16:50:09 +0200" \
  --plain "Sehr geehrte Frau MUSTERMANN, wir freuen uns, Sie als neuen Kunden zu begrüßen." \
  --html '<html><body><p>Sehr geehrte Frau MUSTERMANN, wir freuen uns.</p></body></html>'

# Inspect the JSON without sending
./send.sh --plain "test body" --dry-run

# Read body from a file
./send.sh --plain-file ./mail.txt --html-file ./mail.html
```

The base URL can also come from the environment:

```bash
export ANALYZER_URL="http://analyzer.internal:8080"
./send.sh --plain "..."
```

Run `./send.sh --help` for all flags (subject, from/from-name, to, date, plain,
html, url, system, source, version, and `id.*` overrides).

## Request Schema

### Required fields

```
id.mailId          string
id.surrogateId     string
id.system          enum: "gmx" | "webde"
id.resourceType    string (e.g. "mailbox")
id.resourceId      string
id.objectType      string (e.g. "mail")
id.objectId        string
meta.type          string (the content type)
meta.source        string (e.g. "incoming")
meta.version       string (e.g. "1")
headers            object (from / to / subject, etc.)
body.plain.mediaType     "text/plain"
body.plain.contentPlain  the plain text
body.html.mediaType      "text/html"      (this skill always sends html)
body.html.contentPlain   plain-text mirror
body.html.contentHtml    the html markup
```

### Optional fields

```
headers.date, headers.returnPath, headers.messageId, headers.from[].personal
attributes   object (charsets, languages, ...)
attachments  object
```

### Raw curl fallback

```bash
curl -s -X POST "$ANALYZER_URL/predict" \
  -H "Accept: application/vnd.mam.sip.prediction.list-v1+json" \
  -H "Content-Type: application/vnd.ui.trinity.message.textual-v1+json" \
  --max-time 120 \
  -d '{
    "id": {"mailId":"test-001","surrogateId":"acct-001","system":"webde",
           "resourceType":"mailbox","resourceId":"12345",
           "objectType":"mail","objectId":"67890"},
    "meta": {"type":"application/vnd.ui.trinity.message.textual-v1+json",
             "source":"incoming","version":"1"},
    "headers": {"from":[{"address":"sender@example.com","domain":"example.com"}],
                "to":[{"address":"recipient@web.de","domain":"web.de"}],
                "subject":"Test email"},
    "body": {
      "plain": {"mediaType":"text/plain","contentPlain":"This is a test email body."},
      "html":  {"mediaType":"text/html",
                "contentPlain":"This is a test email body.",
                "contentHtml":"<html><body><p>This is a test email body.</p></body></html>"}
    },
    "attachments": {}
  }'
```

## Notes & Gotchas

- `id.system` accepts only `gmx` or `webde`.
- If `body.html` is present, both `contentPlain` and `contentHtml` are mandatory —
  omitting either returns `400`. The script always sets both.
- A malformed request returns `400` with a precise "Field required" message —
  useful for iterating on the schema.
- **Known caveat:** valid requests may currently return `500`
  (`urn:problem:mam.sip:prediction-error`) due to an internal analyzer bug
  (model loading, etc.), not a request-format problem. A `500` after a `200`
  OPTIONS usually means the request was well-formed.
 
