---
name: colleague-absences
description: Use when the user wants to know who is out of office in the United Internet corporate intranet (InsideNET) — current absences plus planned ones within the next ~2 weeks for a team/department — and wants it via a plain shell script (curl + python3, no browser/Chrome). Use ONLY with United Internet credentials; the public data for colleagues is privacy-restricted to the last two weeks plus upcoming absences.
---

# colleague-absences

Show who is currently away / on business trip / planned to be away in the next two weeks, for a United Internet team (InsideNET org unit). Pure shell: authenticate once via CAS, then fetch the department absence list and render P1 (status table) plus P3 (day timeline).

## Prerequisites

- `curl` and `python3` (stdlib only) on the machine.
- A United Internet (LDAP) account.
- Running inside the corporate network / with appropriate network access.

## Steps

### 1. Authenticate (once per ~8 h session)

Run the login helper; it prompts for your password (masked, never printed or put on the command line) and stores **two** cookie jars: the united-internet.org session and the contacts API session. If your account has a second factor enabled it additionally prompts for the authentication code from your authenticator app before completing the CAS login.

```bash
<skilldir>/colleague-absences-login.sh
# optional: target a specific page instead of the intranet home (default)
<skilldir>/colleague-absences-login.sh "https://united-internet.org/profiles/people/12345678"
```

This performs the CAS flow at `https://login.united-internet.org/ims-sso/login`, follows the redirect back through `/signin/casify/`, and also authenticates to the contacts API. It authenticates with the **current user** (`$USER`) — no personal ID or team ID is hardcoded anywhere.

> **Authentication is checked automatically — only log in if needed.** The main script (`colleague-absences.sh`) does **not** run the login helper for you; instead it *checks first* whether a valid session exists and only suggests logging in when necessary. Detection: an authenticated `GET /vacation/list/personal` returns `200`; an expired or missing session returns `302` (redirect to `/signin/casify`). If the session is missing/expired, the script prints an error and the exact login command to run — it never silently returns an empty absence table.

### 2. Show absences for your team (nothing to pass)

The primary team is resolved **automatically** from the current user via the contacts API (`GET /persons/<username>` → `department_id`), so you don't have to know or provide your own or your team's ID.

```bash
<skilldir>/colleague-absences.sh
```

### 3. Merge multiple teams

A user can be part of more than one team (e.g. an org department plus several functional teams/squads). To show **all** of them in one merged output:

- **Default teams file** (recommended for "all my teams"): the script automatically reads `~/.config/colleague-absences/teams` if it exists — one team id per line. With it, the plain run above already merges every team you belong to, no arguments needed.
- Or pass several team ids explicitly — as arguments, via the comma-separated env var, or via a custom config file:

```bash
# arguments (all teams on one line)
<skilldir>/colleague-absences.sh 21443866 21606142 21681112

# environment (comma separated)
INSIDE_DEPARTMENT_IDS=21443866,21606142,21681112 <skilldir>/colleague-absences.sh

# custom config file (one id per line, or ','/' ' separated)
INSIDE_TEAMS_FILE=/path/to/teams.txt <skilldir>/colleague-absences.sh
```

When more than one team is given, the script fetches each team's absence list and merges them into a **single** P1 + P3 output. Absences of the same person that show up in several team lists (same person, same dates, same reason) are de-duplicated into one row. The single-team forms still work:

```bash
<skilldir>/colleague-absences.sh 21443866
INSIDE_DEPARTMENT_ID=21443866 <skilldir>/colleague-absences.sh
```

Environment overrides:

| var | default | meaning |
|-----|---------|---------|
| `INSIDE_COOKIES` | `/tmp/inside.cookies` | united-internet.org session jar |
| `INSIDE_CONTACTS_COOKIES` | `/tmp/contacts.cookies` | contacts API jar (used for primary-team auto-resolution) |
| `INSIDE_DEPARTMENT_ID` | *(none — auto-resolved)* | single explicit team id override |
| `INSIDE_DEPARTMENT_IDS` | *(none)* | comma-separated team ids to merge |
| `INSIDE_TEAMS_FILE` | `~/.config/colleague-absences/teams` | config file with one team id per line (`' '`/`','` separated) |

Output = **P1**: two sections ("Heute abwesend" and "Kommende 2 Wochen") with columns *Name, Von, Bis, Tage, Grund, Stellvertreter, Team*; followed by **P3**: a day-by-day timeline over the next 14 days.

**The P3 timeline is mandatory output.** Always print it in full, in every answer — never omit, truncate, summarize, or ask whether the user wants it. Do not wait for a follow-up request.

### Under the hood

- Resolves the **primary** team id from the current user: `GET https://contacts.united-internet.org/api/persons/<username>` → `department_id` (contacts jar). If you belong to several teams, the others are not auto-resolved (the person endpoint exposes only one department_id) — list them in `~/.config/colleague-absences/teams` (or pass them explicitly) as described in step 3.
- Fetches `https://united-internet.org/vacation/list/department` (POST with `id=<dept>&start=<today-2d>&end=<today+21d>`) **once per team**, the same server-rendered list the "Abteilungs-Abwesenheiten" page shows.
- Parses the HTML with `colleague_absences_parse.py` (stdlib python3), classifies rows into current (start ≤ today ≤ end) vs upcoming (start > today, ≤ today+14), de-duplicates identical absences across teams, and renders the merged P1 + P3.
- If the response redirects to `/signin/casify` mid-fetch, the session expired between the up-front probe and the request — re-run step 1 (the up-front probe catches this in the common case).

## Pitfalls / limitations

- **Data protection:** for *colleagues* the source only exposes the **last two weeks plus upcoming** absences ("Aus datenschutzrechtlichen Gründen können nur Abwesenheiten der letzten zwei Wochen angezeigt werden"). You can never pull a colleague's full-year history via this tool — that's a privacy boundary, not an endpoint restriction. Your own full history lives in `/vacation/list/personal` (self-service only, `id` parameter is ignored there).
- **"Grund" is coarse:** the department list groups entries into sections (Abwesenheit / Geschäftsreise / zukünftig). It does *not* expose Urlaub vs Krankheit per person. If a finer reason is needed, only your own entries provide it.
- **Session length:** ~8 h (JWT). The script detects an expired session up front (`HTTP 302` on the auth probe) and tells you to re-login — it does not return an empty table. Auto-resolution additionally needs the contacts jar — if it fails with "Could not auto-resolve your team", re-login.
- **2FA accounts:** the login helper prompts for an authenticator code after the password. A `login status: 200` with no `united-internet.org` cookie in the jar means the CAS login stalled (e.g. at the 2FA step or wrong credentials).
- **Passwords never appear on the command line:** the login helper reads the password via `read -s` (masked), sends the CAS form field from a `0600` temp file (`--data-urlencode password@file`) and uses a `0600` temp netrc for the contacts API.
- **No browser needed** — do not fall back to Chrome DevTools for this; the scripts replace it.
- Shell gotcha: **do not name a variable `path` in zsh** (it is tied to `$PATH` and will break command lookup).
- Reason labels are German by default (Urlaub/Krankheit/etc. would only be available for self data; the department list yields Abwesend/Dienstreise/Geplant).
