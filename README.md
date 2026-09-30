# Somaiya Libraries — KPI Dashboard

Interactive cross-campus library KPI dashboard for the Somaiya Koha rollout.
Aggregate statistics only — no patron-level data.

- `index.html` — the dashboard (static page, loads data at runtime)
- `data.json` — latest harvested KPI data; updated by the refresh pipeline

Open via GitHub Pages, or locally with any static server
(`python3 -m http.server` in this folder — `file://` won't work because the
page fetches `data.json`).

Maintained from the Library Module workspace (`dashboard/build_dashboard.py`).
