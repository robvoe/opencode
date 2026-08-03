#!/usr/bin/env bash
#
# send.sh — Send mail content to the analyzer POST /predict endpoint.
#
# Builds a valid `application/vnd.ui.trinity.message.textual-v1+json` request and
# ALWAYS populates BOTH body.plain and body.html with the supplied content.
# The plain text is auto-wrapped into minimal HTML when no explicit --html is given.
#
# Requires: jq, curl
#
set -euo pipefail

# ---- Defaults -----------------------------------------------------------------
BASE_URL="${ANALYZER_URL:-http://localhost:8080}"
PATH_PREDICT="/predict"

SYSTEM="webde"            # enum: gmx | webde
SOURCE="incoming"
VERSION="1"

FROM_ADDR="sender@example.com"
FROM_NAME=""
TO_ADDR="recipient@web.de"
SUBJECT="Test email"
DATE=""

PLAIN=""                  # plain body text (required)
HTML=""                   # optional explicit HTML; auto-generated from PLAIN if empty

# id.* defaults
MAIL_ID="test-001"
SURROGATE_ID="acct-001"
RESOURCE_TYPE="mailbox"
RESOURCE_ID="12345"
OBJECT_TYPE="mail"
OBJECT_ID="67890"

DRY_RUN="false"
MAX_TIME="120"

usage() {
  cat <<'EOF'
Usage: send.sh [options]

Content options:
  --subject <s>       Mail subject                      (default: "Test email")
  --from <addr>       Sender address                    (default: sender@example.com)
  --from-name <s>     Sender personal/display name      (optional)
  --to <addr>         Recipient address                 (default: recipient@web.de)
  --date <s>          RFC date header                   (optional)
  --plain <text>      Plain body text (REQUIRED)
  --plain-file <path> Read plain body text from a file
  --html <html>       Explicit HTML body (optional; auto-wrapped from plain if omitted)
  --html-file <path>  Read HTML body from a file

Routing / meta:
  --url <base>        Analyzer base URL (inferred from your instruction).
                      Default: $ANALYZER_URL or http://localhost:8080
  --system <s>        id.system enum: gmx | webde        (default: webde)
  --source <s>        meta.source                        (default: incoming)
  --version <s>       meta.version                       (default: 1)

id.* overrides:
  --mail-id, --surrogate-id, --resource-type, --resource-id,
  --object-type, --object-id

Behaviour:
  --dry-run           Print the JSON body only; do not send
  --max-time <sec>    curl --max-time                    (default: 120)
  -h, --help          Show this help

The request always sends BOTH body.plain and body.html.
EOF
}

# ---- Parse args ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subject)        SUBJECT="$2"; shift 2 ;;
    --from)           FROM_ADDR="$2"; shift 2 ;;
    --from-name)      FROM_NAME="$2"; shift 2 ;;
    --to)             TO_ADDR="$2"; shift 2 ;;
    --date)           DATE="$2"; shift 2 ;;
    --plain)          PLAIN="$2"; shift 2 ;;
    --plain-file)     PLAIN="$(cat "$2")"; shift 2 ;;
    --html)           HTML="$2"; shift 2 ;;
    --html-file)      HTML="$(cat "$2")"; shift 2 ;;
    --url)            BASE_URL="$2"; shift 2 ;;
    --system)         SYSTEM="$2"; shift 2 ;;
    --source)         SOURCE="$2"; shift 2 ;;
    --version)        VERSION="$2"; shift 2 ;;
    --mail-id)        MAIL_ID="$2"; shift 2 ;;
    --surrogate-id)   SURROGATE_ID="$2"; shift 2 ;;
    --resource-type)  RESOURCE_TYPE="$2"; shift 2 ;;
    --resource-id)    RESOURCE_ID="$2"; shift 2 ;;
    --object-type)    OBJECT_TYPE="$2"; shift 2 ;;
    --object-id)      OBJECT_ID="$2"; shift 2 ;;
    --dry-run)        DRY_RUN="true"; shift ;;
    --max-time)       MAX_TIME="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

# ---- Validate -----------------------------------------------------------------
if [[ -z "$PLAIN" ]]; then
  echo "Error: --plain (or --plain-file) is required." >&2
  exit 2
fi
case "$SYSTEM" in
  gmx|webde) ;;
  *) echo "Error: --system must be 'gmx' or 'webde' (got '$SYSTEM')." >&2; exit 2 ;;
esac

# Derive from-domain / to-domain from addresses.
FROM_DOMAIN="${FROM_ADDR##*@}"
TO_DOMAIN="${TO_ADDR##*@}"

# Auto-wrap plain text into minimal HTML when no explicit HTML provided.
if [[ -z "$HTML" ]]; then
  ESCAPED_PLAIN="$(printf '%s' "$PLAIN" \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
  HTML="<html><body><p>${ESCAPED_PLAIN}</p></body></html>"
fi

CONTENT_TYPE="application/vnd.ui.trinity.message.textual-v1+json"
ACCEPT="application/vnd.mam.sip.prediction.list-v1+json"

# ---- Build JSON (jq for safe escaping) ---------------------------------------
BODY="$(jq -n \
  --arg mailId "$MAIL_ID" \
  --arg surrogateId "$SURROGATE_ID" \
  --arg system "$SYSTEM" \
  --arg resourceType "$RESOURCE_TYPE" \
  --arg resourceId "$RESOURCE_ID" \
  --arg objectType "$OBJECT_TYPE" \
  --arg objectId "$OBJECT_ID" \
  --arg ctype "$CONTENT_TYPE" \
  --arg source "$SOURCE" \
  --arg version "$VERSION" \
  --arg fromAddr "$FROM_ADDR" \
  --arg fromDomain "$FROM_DOMAIN" \
  --arg fromName "$FROM_NAME" \
  --arg toAddr "$TO_ADDR" \
  --arg toDomain "$TO_DOMAIN" \
  --arg subject "$SUBJECT" \
  --arg date "$DATE" \
  --arg plain "$PLAIN" \
  --arg html "$HTML" \
  '
  {
    id: {
      mailId: $mailId,
      surrogateId: $surrogateId,
      system: $system,
      resourceType: $resourceType,
      resourceId: $resourceId,
      objectType: $objectType,
      objectId: $objectId
    },
    meta: {
      type: $ctype,
      source: $source,
      version: $version
    },
    headers: (
      {
        from: [ ( { address: $fromAddr, domain: $fromDomain }
                  + (if $fromName == "" then {} else { personal: $fromName } end) ) ],
        to: [ { address: $toAddr, domain: $toDomain } ],
        subject: $subject
      }
      + (if $date == "" then {} else { date: $date } end)
    ),
    body: {
      plain: {
        mediaType: "text/plain",
        contentPlain: $plain
      },
      html: {
        mediaType: "text/html",
        contentPlain: $plain,
        contentHtml: $html
      }
    },
    attachments: {}
  }
  ')"

if [[ "$DRY_RUN" == "true" ]]; then
  printf '%s\n' "$BODY"
  exit 0
fi

# ---- Send ---------------------------------------------------------------------
URL="${BASE_URL%/}${PATH_PREDICT}"
echo "POST $URL" >&2
curl -sS -X POST "$URL" \
  -H "Accept: ${ACCEPT}" \
  -H "Content-Type: ${CONTENT_TYPE}" \
  --max-time "$MAX_TIME" \
  -d "$BODY"
 
