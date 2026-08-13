#!/usr/bin/env bash
# colleague-absences.sh
# Show who is out of office for one or more United Internet teams/departments:
#   - current absences (today incl. overlap)  -> "Heute abwesend"
#   - planned absences within the next 2 weeks -> "Kommende 2 Wochen"
# plus a day-by-day timeline (P3).
#
# The primary team is resolved AUTOMATICALLY from the current user ($USER) via
# the contacts API. Additional teams can be given as arguments, via the
# INSIDE_DEPARTMENT_ID / INSIDE_DEPARTMENT_IDS env vars, or via a config file
# (INSIDE_TEAMS_FILE). When more than one team is present the results are
# MERGED into a single combined output (duplicate entries across teams are
# de-duplicated per person).
#
# Usage:
#   colleague-absences.sh [DEPARTMENT_ID ...]
#   colleague-absences.sh 21443866 21606142 21681112
#
# Environment:
#   INSIDE_COOKIES           ui session jar (default /tmp/inside.cookies)
#   INSIDE_CONTACTS_COOKIES  contacts API jar (default /tmp/contacts.cookies)
#   INSIDE_DEPARTMENT_ID     single explicit team id override
#   INSIDE_DEPARTMENT_IDS    comma-separated team ids override
#   INSIDE_TEAMS_FILE        file with one team id per line (or ',' or ' ' separated)
#
# Requires: curl, python3 (stdlib). No browser.
set -euo pipefail

COOKIES="${INSIDE_COOKIES:-/tmp/inside.cookies}"
CONTACTS="${INSIDE_CONTACTS_COOKIES:-/tmp/contacts.cookies}"
DEFAULT_TEAMS_FILE="${INSIDE_TEAMS_FILE:-${HOME}/.config/colleague-absences/teams}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGIN_HELPER="$DIR/colleague-absences-login.sh"

# Tell the user how to authenticate (the login helper is interactive, so we
# never run it for them — we only point them to it).
suggest_login() {
  echo "To log in, run:" >&2
  echo "  ${LOGIN_HELPER}" >&2
  echo "(you will be prompted for your password and, if enabled, an authenticator code)." >&2
}

# Verify the ui session BEFORE doing any work. An unauthenticated or expired
# session must never silently produce an empty absence table. Detection: an
# authenticated GET on /vacation/list/personal returns 200; without a valid
# session the server 302-redirects to /signin/casify (curl -sS without -L
# reports that as HTTP 302 rather than following it).
ensure_ui_session() {
  if [ ! -s "$COOKIES" ]; then
    echo "ERROR: no session found in ${COOKIES} — you are not logged in." >&2
    suggest_login
    exit 1
  fi
  local code
  code="$(curl -sS -o /dev/null --max-time 20 -b "$COOKIES" -w '%{http_code}' \
    "https://united-internet.org/vacation/list/personal")" || {
      echo "ERROR: could not reach united-internet.org to verify the session." >&2
      exit 1
    }
  if [ "$code" != "200" ]; then
    echo "ERROR: the session in ${COOKIES} is expired or not authenticated (HTTP ${code})." >&2
    suggest_login
    exit 1
  fi
}

resolve_primary() {
  curl -sS --max-time 20 -b "$CONTACTS" \
    "https://contacts.united-internet.org/api/persons/${USER:?}" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("department_id") or "")
except Exception:
    print("")'
}

collect_departments() {
  # returns team ids, one per line, in order
  local ids=()
  if [ "$#" -gt 0 ]; then
    ids+=("$@")
  elif [ -n "${INSIDE_DEPARTMENT_IDS:-}" ]; then
    IFS=',' read -r -a ids <<< "$INSIDE_DEPARTMENT_IDS"
  elif [ -n "${INSIDE_DEPARTMENT_ID:-}" ]; then
    ids+=("$INSIDE_DEPARTMENT_ID")
  elif [ -f "$DEFAULT_TEAMS_FILE" ]; then
    # shellcheck disable=SC2016
    while IFS=' ,' read -r -a line || [ -n "${line[*]:-}" ]; do
      for id in "${line[@]:-}"; do
        [ -n "$id" ] && ids+=("$id")
      done
    done < "$DEFAULT_TEAMS_FILE"
  else
    local primary
    if [ ! -f "$CONTACTS" ]; then
      echo "No contacts API session ($CONTACTS); cannot auto-resolve your team." >&2
      suggest_login
      exit 1
    fi
    primary="$(resolve_primary)"
    if [ -z "$primary" ]; then
      echo "Could not auto-resolve your team (contacts session expired?)." >&2
      suggest_login
      exit 1
    fi
    ids+=("$primary")
  fi
  printf '%s\n' "${ids[@]}"
}

# Check authentication first — only proceed if the session is actually valid.
ensure_ui_session

DEPTS=()
while IFS= read -r dep; do
  # skip blank lines
  [ -n "$dep" ] && DEPTS+=("$dep")
done < <(collect_departments "$@")
if [ "${#DEPTS[@]}" -eq 0 ]; then
  echo "No departments resolved." >&2
  exit 1
fi

URL="https://united-internet.org/vacation/list/department"
START="$(python3 -c 'import datetime; print((datetime.date.today()-datetime.timedelta(days=2)).strftime("%d.%m.%Y"))')"
END="$(python3 -c 'import datetime; print((datetime.date.today()+datetime.timedelta(days=21)).strftime("%d.%m.%Y"))')"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ARGS=()
for dept in "${DEPTS[@]}"; do
  [ -n "$dept" ] || continue
  f="$WORK/${dept}.html"
  HTML="$(curl -sS --max-time 30 -b "$COOKIES" \
    --data-urlencode "id=${dept}" \
    --data-urlencode "start=${START}" \
    --data-urlencode "end=${END}" \
    "$URL")"
  if printf '%s' "$HTML" | grep -q 'signin/casify'; then
    echo "Session expired — run colleague-absences-login.sh again." >&2
    exit 1
  fi
  printf '%s' "$HTML" > "$f"
  ARGS+=("${dept}=${f}")
done

python3 "$DIR/colleague_absences_parse.py" "${ARGS[@]}"
