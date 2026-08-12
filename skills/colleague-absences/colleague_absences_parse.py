#!/usr/bin/env python3
"""Parse the InsideNET department absence list (HTML on stdin) and render:

  P1  "Heute abwesend" (start <= today <= end) and "Kommende 2 Wochen"
      (start > today and start <= today+14) status table
  P3  day-by-day timeline over the next 14 days

Reason labels are German. Depends only on the stdlib.
"""
import re
import sys
import datetime
from html import unescape

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

TODAY = datetime.date.today()
WINDOW_DAYS = 14
END_WINDOW = TODAY + datetime.timedelta(days=WINDOW_DAYS)

# section heading -> (Grund label, kind: current|future)
SECTION_MAP = {
    "Aktuelle Abwesenheiten": ("Abwesend", "current"),
    "Aktuelle Geschäftsreisen": ("Dienstreise", "current"),
    "Zukünftige Abwesenheiten": ("Geplant", "future"),
}


def parse_date(s):
    try:
        d, m, y = map(int, s.split("."))
        return datetime.date(y, m, d)
    except (ValueError, TypeError):
        return None


def clean(s):
    s = unescape(s or "")
    s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"\s+", " ", s).strip()


def parse_rows(html):
    entries = []
    section = "unknown"
    for m in re.finditer(r"<tr([^>]*)>([\s\S]*?)</tr>", html, re.S):
        tr_attrs, tr = m.group(1), m.group(2)
        h3 = re.search(r"<h3>([^<]+)</h3>", tr)
        if h3:
            section = clean(h3.group(1))
            continue
        if 'class="row' not in tr_attrs:
            continue
        # name = first person-link with text before the "Stellvertreter:" marker
        before_sub = tr.split("Stellvertreter:", 1)[0]
        nm = re.search(r'<a href="/network/people/view\?\d+">([^<]+)</a>', before_sub)
        if not nm:
            continue
        name = clean(nm.group(1))
        dates = [d for d in (parse_date(x) for x in re.findall(r"\b(\d{2}\.\d{2}\.\d{4})\b", tr)) if d]
        if not dates:
            continue
        start, end = dates[0], dates[-1]
        days_m = re.search(r"\((\d+)\s*Tage\)", tr)
        days = int(days_m.group(1)) if days_m else (end - start).days + 1
        subm = re.search(r"Stellvertreter:\s*<br\s*/?\s*>([\s\S]*?)(?:</td>|$)", tr)
        sub = clean(subm.group(1)) if subm else "-"
        if sub in ("nicht gesetzt", "nicht angegeben") or not sub:
            sub = "-"
        org_m = re.search(r'<a href="/network/people/browse/org\?\d+">([^<]+)</a>', tr)
        org = clean(org_m.group(1)) if org_m else ""
        grund, kind = SECTION_MAP.get(section, (section, "current"))
        entries.append({
            "name": name, "start": start, "end": end, "days": days,
            "grund": grund, "sub": sub, "org": org,
        })
    return entries


def classify(e):
    if e["start"] <= TODAY <= e["end"]:
        return "current"
    if e["start"] > TODAY and e["start"] <= END_WINDOW:
        return "future"
    return None


def fmt_date(d):
    return d.strftime("%d.%m")


def render(entries, dept_id):
    cur = [e for e in entries if classify(e) == "current"]
    fut = [e for e in entries if classify(e) == "future"]

    print(f"Abwesenheiten für Team-ID {dept_id} (Stand: {TODAY:%d.%m.%Y})\n")

    def table(rows, title):
        print(title)
        if not rows:
            print("  (keine)")
            return
        rows = sorted(rows, key=lambda e: (e["start"], e["name"]))
        w = {"name": max(22, max(len(e["name"]) for e in rows)),
             "org": max(10, max(len(e["org"]) for e in rows))}
        hdr = f"{'Name':<{w['name']}}  {'Von':<10}  {'Bis':<10}  {'Tage':<4}  {'Grund':<10}  {'Stellvertreter':<18}  {'Team':<{w['org']}}"
        print(hdr)
        print("-" * len(hdr))
        for e in rows:
            print(f"{e['name']:<{w['name']}}  {fmt_date(e['start']):<10}  {fmt_date(e['end']):<10}  {e['days']:<4}  {e['grund']:<10}  {e['sub']:<18}  {e['org']:<{w['org']}}")
        print()

    table(cur, "HEUTE ABWESEND")
    table(fut, "KOMMENDE 2 WOCHEN")

    # P3 timeline (merged per person)
    print("TIMELINE (nächste 14 Tage)\n")
    days = [TODAY + datetime.timedelta(days=i) for i in range(WINDOW_DAYS)]
    lbl = "".join(f" {d.strftime('%a')[:2]} {d.day:<2}" for d in days)
    merged = {}
    for e in entries:
        if classify(e) is None:
            continue
        key = e["name"]
        if key not in merged:
            merged[key] = [e["start"], e["end"]]
        else:
            merged[key][0] = min(merged[key][0], e["start"])
            merged[key][1] = max(merged[key][1], e["end"])
    print(f"{'Name':<24}{lbl}")
    for name in sorted(merged):
        s, en = merged[name]
        chars = []
        for d in days:
            chars.append("▓▓" if s <= d <= en else "··")
        print(f"{name:<24}{''.join(col + ' ' for col in chars)}")
    print()


def main():
    html = sys.stdin.buffer.read().decode("iso-8859-1")
    dept_id = sys.argv[1] if len(sys.argv) > 1 else "?"
    render(parse_rows(html), dept_id)


if __name__ == "__main__":
    main()
