#!/usr/bin/env python3
"""Deploy the KPI/WIDGET report pack to Koha instances via the staff client.

Uses the MBD service account (reports-only writes; Koha reports are SELECT-only).
Credentials come from environment variables KOHA_USER / KOHA_PASS.

    KOHA_USER=MBD KOHA_PASS=... python3 deploy_reports.py --only kjsit,sksac,svu

Per instance: log in, read the saved-reports list, create any missing
KPI_*/WIDGET_* reports (public=1, cache 300s), verify against the list again.
Safe to re-run — existing names are skipped. Stdlib only.
"""
import csv
import os
import re
import sys
from pathlib import Path

from koha_client import KohaSession

HERE = Path(__file__).parent
SQL_FILE = HERE / "sql" / "kpi-reports.sql"
INSTANCES = HERE / "instances.csv"


def parse_reports(path: Path):
    """Parse kpi-reports.sql into (name, notes, sql) blocks."""
    blocks = []
    name = notes = None
    sql_lines = []

    def flush():
        nonlocal name, notes, sql_lines
        sql = "\n".join(sql_lines).strip().rstrip(";").strip()
        if name and sql:
            blocks.append((name, notes or "", sql))
        name = notes = None
        sql_lines = []

    for line in path.read_text().splitlines():
        stripped = line.strip()
        m = re.match(r"--\s*Name:\s*(\S+)", stripped)
        if m:
            flush()
            name = m.group(1)
            continue
        mn = re.match(r"--\s*Notes:\s*(.+)", stripped)
        if mn:
            notes = mn.group(1).strip()
            continue
        if stripped.startswith("--"):
            continue
        sql_lines.append(line)
    flush()
    return blocks


def deploy(inst, user, password, reports):
    base = inst["base_url"]
    print(f"\n=== {inst['slug']} ({base})")
    s = KohaSession(base)
    try:
        s.login(user, password)
    except Exception as e:
        print(f"  ! login failed: {e}")
        return 0
    existing = s.saved_reports()
    created = 0
    for name, notes, sql in reports:
        if name in existing:
            print(f"  = {name} already exists (id {existing[name]})")
            continue
        form_html = s.get("/cgi-bin/koha/reports/guided_reports.pl?op=add_form_sql")
        s.post("/cgi-bin/koha/reports/guided_reports.pl", {
            "csrf_token": s.csrf(form_html), "op": "cud-save",
            "reportname": name, "notes": notes, "sql": sql,
            "select_or_create_group": "select", "group": "", "groupdesc": "",
            "select_or_create_subgroup": "select", "subgroup": "", "subgroupdesc": "",
            "public": "1", "cache_expiry": "300", "cache_expiry_units": "seconds",
        })
        created += 1
    after = s.saved_reports()
    missing = [n for n, _, _ in reports if n not in after]
    if missing:
        print(f"  ! NOT created: {', '.join(missing)}")
    else:
        print(f"  ✓ all {len(reports)} reports present ({created} newly created)")
    return created


def main():
    user = os.environ.get("KOHA_USER")
    password = os.environ.get("KOHA_PASS")
    if not (user and password):
        sys.exit("set KOHA_USER and KOHA_PASS environment variables")
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    reports = parse_reports(SQL_FILE)
    print(f"{len(reports)} reports parsed from {SQL_FILE.name}")
    with open(INSTANCES) as f:
        instances = [r for r in csv.DictReader(f) if not only or r["slug"] in only]
    total = 0
    for inst in instances:
        total += deploy(inst, user, password, reports)
    print(f"\ndone — {total} reports created")


if __name__ == "__main__":
    main()
