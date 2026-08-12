#!/usr/bin/env bash
# colleague-absences-login.sh
# Log in to the United Internet intranet and store session cookies:
#   - united-internet.org (CAS SSO)  -> ui session jar   (INSIDE_COOKIES)
#   - contacts API (basic auth)      -> contacts API jar (INSIDE_CONTACTS_COOKIES)
# The contacts jar is used later to auto-resolve the current user's team.
#
# The CAS flow prompts for the password AND, if enabled on the account, a
# second factor (authentication code from the authenticator app).
#
# Usage:
#   colleague-absences-login.sh [TARGET_URL]
#
# Environment:
#   INSIDE_COOKIES           ui session jar (default /tmp/inside.cookies)
#   INSIDE_CONTACTS_COOKIES  contacts API jar (default /tmp/contacts.cookies)
set -euo pipefail

COOKIES="${INSIDE_COOKIES:-/tmp/inside.cookies}"
CONTACTS="${INSIDE_CONTACTS_COOKIES:-/tmp/contacts.cookies}"
TARGET="${1:-https://united-internet.org/}"

LOGIN="https://login.united-internet.org/ims-sso/login"
CONTACTS_API="https://contacts.united-internet.org/api/checkAuth"

urlencode() { python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

SERVICE_URL="https://united-internet.org/signin/casify/?__project_id=0&__server=${TARGET}"
LOGIN_URL="${LOGIN}?service=$(urlencode "${SERVICE_URL}")"

rm -f "$COOKIES" "$CONTACTS"

WORK="$(mktemp -d)"
chmod 700 "$WORK"

# 1) initial login page -> capture session + CAS flow execution token
HTML="$(curl -sS --max-time 20 -c "$COOKIES" "$LOGIN_URL")"
EXECUTION="$(printf '%s' "$HTML" | sed -n 's/.*name="execution" value="\([^"]*\)".*/\1/p' | head -1)"
if [ -z "$EXECUTION" ]; then
  echo "ERROR: could not find CAS execution token on login page" >&2
  exit 1
fi

# 2) password (masked, from a 0600 file so it never appears on argv)
read -rsp "Password for ${USER:-your-user}: " INSIDE_PASSWORD
echo >&2
printf '%s' "$INSIDE_PASSWORD" > "$WORK/pw"
chmod 600 "$WORK/pw"

# 3) submit username+password (single hop, inspect response before following)
curl -sS --max-time 30 \
  -b "$COOKIES" -c "$COOKIES" \
  --data-urlencode "username=${USER:-}" \
  --data-urlencode "password@${WORK}/pw" \
  --data-urlencode "execution=${EXECUTION}" \
  --data-urlencode "_eventId=submit" \
  -D "$WORK/s1.headers" -o "$WORK/s1.html" \
  "$LOGIN_URL" || { echo "ERROR: credential submission failed" >&2; exit 1; }

# 4) if the account has a second factor enabled, the response is a token form
FINAL_HEADERS="$WORK/s1.headers"
if grep -q 'name="token"' "$WORK/s1.html"; then
  read -rsp "Auth code (authenticator app): " OTP
  echo >&2
  printf '%s' "$OTP" > "$WORK/otp"
  chmod 600 "$WORK/otp"
  unset OTP
  EX2="$(sed -n 's/.*name="execution" value="\([^"]*\)".*/\1/p' "$WORK/s1.html" | head -1)"
  [ -n "$EX2" ] || { echo "ERROR: could not find 2FA execution token" >&2; exit 1; }
  curl -sS --max-time 30 \
    -b "$COOKIES" -c "$COOKIES" \
    --data-urlencode "token@${WORK}/otp" \
    --data-urlencode "execution=${EX2}" \
    --data-urlencode "geolocation=" \
    --data-urlencode "_eventId=submit" \
    -D "$WORK/s2.headers" -o "$WORK/s2.html" \
    "$LOGIN_URL" || { echo "ERROR: 2FA submission failed" >&2; exit 1; }
  FINAL_HEADERS="$WORK/s2.headers"
fi
rm -f "$WORK/pw" "$WORK/otp"

# 5) follow the CAS redirect chain (-> casify -> target) to establish the
#    united-internet.org session cookie
LOCATION="$(sed -n 's/^[Ll]ocation:[[:space:]]*//p' "$FINAL_HEADERS" | head -1 | tr -d '\r')"
if [ -n "$LOCATION" ]; then
  curl -sS -L --max-redirs 10 --max-time 30 \
    -b "$COOKIES" -c "$COOKIES" \
    -o /dev/null \
    "$LOCATION"
fi

# 6) Contacts API: same credentials via a 0600 netrc (password stays off argv)
printf 'machine contacts.united-internet.org\nlogin %s\npassword %s\n' "${USER:-}" "${INSIDE_PASSWORD}" > "$WORK/netrc"
chmod 600 "$WORK/netrc"
unset INSIDE_PASSWORD
curl -sS --max-time 30 -n --netrc-file "$WORK/netrc" -o /dev/null -w "contacts status: %{http_code}\n" "$CONTACTS_API" -c "$CONTACTS"

rm -rf "$WORK"

[ -s "$COOKIES" ] || { echo "ERROR: no ui session stored." >&2; exit 1; }
[ -s "$CONTACTS" ] || { echo "WARNING: no contacts API cookie stored; team auto-resolution will not work." >&2; }

echo "Session cookies stored in: $COOKIES (ui) and $CONTACTS (contacts API)"
