#!/usr/bin/env python3
"""Harvest KPI reports from every Koha instance into kpi.sqlite.

Logs into each instance's staff client with the MBD service account
(KOHA_USER / KOHA_PASS env vars), resolves report names to ids from the
saved-reports list, runs each KPI_*/WIDGET_* report via the svc JSON
endpoint, and stores rows in SQLite tagged with campus + fetch time.

    KOHA_USER=MBD KOHA_PASS=... python3 harvest.py
    KOHA_USER=MBD KOHA_PASS=... python3 harvest.py --only kjsit,sksac,svu

Stdlib only. Run nightly via cron/launchd.
"""
import csv
import os
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

from koha_client import KohaSession

HERE = Path(__file__).parent
DB = HERE / "kpi.sqlite"
INSTANCES = HERE / "instances.csv"

REPORTS = [
    "KPI_SNAPSHOT",
    "KPI_DAILY_CIRC",
    "KPI_MONTHLY_CIRC",
    "KPI_TOP_TITLES_MONTH",
    "KPI_CIRC_BY_CATEGORY",
    "KPI_COLLECTION_BY_ITYPE",
    "KPI_NEW_ITEMS_MONTHLY",
    "WIDGET_NEW_ARRIVALS",
    "WIDGET_MOST_BORROWED",
    "WIDGET_GLANCE",
    "KPI_SNAPSHOT_BR",
    "KPI_MONTHLY_CIRC_BR",
    "KPI_DAILY_CIRC_BR",
    "KPI_TOP_TITLES_MONTH_BR",
    "KPI_CIRC_BY_CATEGORY_BR",
    "KPI_COLLECTION_BY_ITYPE_BR",
    "KPI_NEW_ITEMS_MONTHLY_BR",
]


def ensure_table(con, report, columns):
    cols = ", ".join(f'"{c}" TEXT' for c in columns)
    con.execute(f'CREATE TABLE IF NOT EXISTS "{report}" (campus TEXT, fetched_at TEXT, {cols})')
    existing = {r[1] for r in con.execute(f'PRAGMA table_info("{report}")')}
    for c in columns:
        if c not in existing:
            con.execute(f'ALTER TABLE "{report}" ADD COLUMN "{c}" TEXT')


def main():
    user = os.environ.get("KOHA_USER")
    password = os.environ.get("KOHA_PASS")
    if not (user and password):
        sys.exit("set KOHA_USER and KOHA_PASS environment variables")
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))

    with open(INSTANCES) as f:
        instances = [r for r in csv.DictReader(f) if not only or r["slug"] in only]

    con = sqlite3.connect(DB)
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    ok = fail = 0

    for inst in instances:
        s = KohaSession(inst["base_url"])
        try:
            s.login(user, password)
            name_to_id = s.saved_reports()
        except Exception as e:
            print(f"! {inst['slug']}: {e}")
            fail += len(REPORTS)
            continue
        for report in REPORTS:
            rid = name_to_id.get(report)
            if rid is None:
                print(f"  ! {inst['slug']} {report}: not deployed")
                fail += 1
                continue
            try:
                rows = s.run_report(rid)
            except Exception as e:
                print(f"  ! {inst['slug']} {report}: {e}")
                fail += 1
                continue
            if not rows:
                ok += 1
                continue
            if isinstance(rows[0], list):  # non-annotated fallback
                rows = [{f"col{j}": v for j, v in enumerate(r)} for r in rows]
            columns = list(rows[0].keys())
            ensure_table(con, report, columns)
            colnames = ", ".join(f'"{c}"' for c in columns)
            placeholders = ", ".join(["?"] * (2 + len(columns)))
            con.executemany(
                f'INSERT INTO "{report}" (campus, fetched_at, {colnames}) VALUES ({placeholders})',
                [[inst["slug"], now] + [None if r.get(c) is None else str(r.get(c)) for c in columns] for r in rows],
            )
            ok += 1
        print(f"  ✓ {inst['slug']} harvested")

    con.commit()
    con.close()
    print(f"done: {ok} report-fetches stored, {fail} failed → {DB}")


if __name__ == "__main__":
    main()
