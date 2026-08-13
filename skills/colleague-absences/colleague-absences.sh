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
      echo "No contacts session ($CONTACTS). Run colleague-absences-login.sh first." >&2
      exit 1
    fi
    primary="$(resolve_primary)"
    if [ -z "$primary" ]; then
      echo "Could not auto-resolve your team (contacts session expired?). Re-run colleague-absences-login.sh or pass one or more DEPARTMENT_IDs." >&2
      exit 1
    fi
    ids+=("$primary")
  fi
  printf '%s\n' "${ids[@]}"
}

if [ ! -f "$COOKIES" ]; then
  echo "No session found in $COOKIES. Run colleague-absences-login.sh first." >&2
  exit 1
fi

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
