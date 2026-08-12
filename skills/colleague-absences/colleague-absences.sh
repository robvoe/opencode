#!/usr/bin/env bash
# colleague-absences.sh
# Show who is out of office for a United Internet team/department:
#   - current absences (today incl. overlap)  -> "Heute abwesend"
#   - planned absences within the next 2 weeks -> "Kommende 2 Wochen"
# plus a day-by-day timeline (P3).
#
# The team is resolved AUTOMATICALLY from the current user ($USER) via the
# contacts API — you don't have to pass or know any team/personal ID. An
# optional DEPARTMENT_ID argument (or INSIDE_DEPARTMENT_ID env) overrides it.
#
# Usage:
#   colleague-absences.sh [DEPARTMENT_ID]
#
# Environment:
#   INSIDE_COOKIES           ui session jar (default /tmp/inside.cookies)
#   INSIDE_CONTACTS_COOKIES  contacts API jar (default /tmp/contacts.cookies)
#
# Requires: curl, python3 (stdlib). No browser.
set -euo pipefail

COOKIES="${INSIDE_COOKIES:-/tmp/inside.cookies}"
CONTACTS="${INSIDE_CONTACTS_COOKIES:-/tmp/contacts.cookies}"
DEPT="${1:-${INSIDE_DEPARTMENT_ID:-}}"

if [ -z "$DEPT" ]; then
  if [ ! -f "$CONTACTS" ]; then
    echo "No contacts session ($CONTACTS). Run colleague-absences-login.sh first." >&2
    exit 1
  fi
  DEPT="$(curl -sS --max-time 20 -b "$CONTACTS" \
    "https://contacts.united-internet.org/api/persons/${USER:?}" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("department_id") or "")
except Exception:
    print("")')"
  if [ -z "$DEPT" ]; then
    echo "Could not auto-resolve your team (contacts session expired?). Re-run colleague-absences-login.sh or pass a DEPARTMENT_ID." >&2
    exit 1
  fi
fi

if [ ! -f "$COOKIES" ]; then
  echo "No session found in $COOKIES. Run colleague-absences-login.sh first." >&2
  exit 1
fi

URL="https://united-internet.org/vacation/list/department"
START="$(python3 -c 'import datetime; print((datetime.date.today()-datetime.timedelta(days=2)).strftime("%d.%m.%Y"))')"
END="$(python3 -c 'import datetime; print((datetime.date.today()+datetime.timedelta(days=21)).strftime("%d.%m.%Y"))')"

HTML="$(curl -sS --max-time 30 -b "$COOKIES" \
  --data-urlencode "id=${DEPT}" \
  --data-urlencode "start=${START}" \
  --data-urlencode "end=${END}" \
  "$URL")"

if printf '%s' "$HTML" | grep -q 'signin/casify'; then
  echo "Session expired — run colleague-absences-login.sh again." >&2
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf '%s' "$HTML" | python3 "$DIR/colleague_absences_parse.py" "${DEPT}"
