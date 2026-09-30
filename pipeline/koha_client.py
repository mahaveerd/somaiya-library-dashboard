"""Minimal Koha staff-client HTTP session (CSRF-aware), shared by
deploy_reports.py and harvest.py. Stdlib only.

Credentials always come from env vars KOHA_USER / KOHA_PASS.
"""
import http.cookiejar
import json
import re
import ssl
import urllib.parse
import urllib.request

# somaiya.edu Koha hosts serve a chain with a self-signed CA python rejects;
# traffic stays TLS-encrypted.
CTX = ssl._create_unverified_context()


class KohaSession:
    def __init__(self, base_url: str):
        self.base = base_url.rstrip("/")
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar),
            urllib.request.HTTPSHandler(context=CTX),
        )

    def get(self, path: str) -> str:
        with self.opener.open(self.base + path, timeout=45) as r:
            return r.read().decode("utf-8", "replace")

    def post(self, path: str, data: dict) -> str:
        body = urllib.parse.urlencode(data).encode()
        req = urllib.request.Request(self.base + path, data=body)
        with self.opener.open(req, timeout=90) as r:
            return r.read().decode("utf-8", "replace")

    @staticmethod
    def csrf(html: str) -> str:
        m = re.search(r'name="csrf_token" value="([^"]+)"', html)
        if not m:
            raise RuntimeError("no CSRF token found")
        return m.group(1)

    def login(self, user: str, password: str):
        html = self.get("/cgi-bin/koha/mainpage.pl")
        resp = self.post("/cgi-bin/koha/mainpage.pl", {
            "csrf_token": self.csrf(html), "op": "cud-login",
            "login_userid": user, "login_password": password, "branch": "",
        })
        if "loggedinusername" not in resp:
            raise RuntimeError("login failed")

    def saved_reports(self) -> dict:
        """Return {report_name: report_id} from the saved-reports list."""
        html = self.get("/cgi-bin/koha/reports/guided_reports.pl?op=list")
        pairs = re.findall(
            r'<label for="id_(\d+)">\d+</label>\s*</td>\s*<td class="report_name">\s*(\S+)',
            html,
        )
        return {name: int(rid) for rid, name in pairs}

    def run_report(self, report_id: int) -> list:
        """Run a saved report and return all rows as list-of-dicts.

        Uses the staff CSV export rather than svc/report JSON: the JSON
        endpoint is capped by the SvcMaxReportRows syspref (default 10 rows)
        and cached, while the export streams the full result set.
        """
        import csv
        import io
        raw = self.get(
            f"/cgi-bin/koha/reports/guided_reports.pl?op=export&format=csv&id={report_id}&reportname=r"
        )
        reader = csv.DictReader(io.StringIO(raw.lstrip("﻿")))
        return [dict(r) for r in reader]
