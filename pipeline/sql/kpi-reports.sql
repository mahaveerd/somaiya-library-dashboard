-- ============================================================
-- Somaiya Libraries — KPI & Widget report pack (Koha 25.05)
-- Create each report via: Reports → Create from SQL
--   · Report name = the UPPERCASE name in the header (EXACT — harvester fetches by name)
--   · Report group = "KPI" (create the group once)
--   · Public = YES for all reports in this file (they contain no patron data)
-- ============================================================

-- ------------------------------------------------------------
-- Name: KPI_SNAPSHOT
-- Notes: One-row snapshot of the library right now.
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM biblio)  AS titles,
  (SELECT COUNT(*) FROM items)   AS copies,
  (SELECT COUNT(*) FROM borrowers) AS members,
  (SELECT COUNT(DISTINCT borrowernumber) FROM statistics
     WHERE type='issue' AND datetime >= CURDATE() - INTERVAL 90 DAY) AS active_members_90d,
  (SELECT COUNT(*) FROM issues)  AS current_checkouts,
  (SELECT COUNT(*) FROM issues WHERE date_due < NOW()) AS overdue_now,
  (SELECT COUNT(*) FROM reserves) AS open_holds,
  (SELECT IFNULL(ROUND(SUM(amountoutstanding),2),0) FROM accountlines
     WHERE amountoutstanding > 0) AS fines_outstanding;

-- ------------------------------------------------------------
-- Name: KPI_DAILY_CIRC
-- Notes: Checkouts / returns / renewals per day, last 30 days.
-- ------------------------------------------------------------
SELECT DATE(datetime) AS day,
       SUM(type='issue')  AS checkouts,
       SUM(type='return') AS returns,
       SUM(type='renew')  AS renewals
FROM statistics
WHERE datetime >= CURDATE() - INTERVAL 30 DAY
  AND type IN ('issue','return','renew')
GROUP BY DATE(datetime)
ORDER BY day;

-- ------------------------------------------------------------
-- Name: KPI_MONTHLY_CIRC
-- Notes: Circulation per month, last 13 months (trend line).
-- ------------------------------------------------------------
SELECT DATE_FORMAT(datetime,'%Y-%m') AS month,
       SUM(type='issue')  AS checkouts,
       SUM(type='return') AS returns,
       SUM(type='renew')  AS renewals
FROM statistics
WHERE datetime >= DATE_SUB(DATE_FORMAT(CURDATE(),'%Y-%m-01'), INTERVAL 12 MONTH)
  AND type IN ('issue','return','renew')
GROUP BY month
ORDER BY month;

-- ------------------------------------------------------------
-- Name: KPI_TOP_TITLES_MONTH
-- Notes: 10 most-borrowed titles this calendar month.
-- ------------------------------------------------------------
SELECT b.title, b.author, COUNT(*) AS checkouts
FROM statistics s
JOIN items  i ON i.itemnumber   = s.itemnumber
JOIN biblio b ON b.biblionumber = i.biblionumber
WHERE s.type='issue'
  AND s.datetime >= DATE_FORMAT(CURDATE(),'%Y-%m-01')
GROUP BY b.biblionumber, b.title, b.author
ORDER BY checkouts DESC
LIMIT 10;

-- ------------------------------------------------------------
-- Name: KPI_CIRC_BY_CATEGORY
-- Notes: Checkouts this month by patron category (aggregate only).
-- ------------------------------------------------------------
SELECT c.description AS category, COUNT(*) AS checkouts
FROM statistics s
JOIN borrowers  bo ON bo.borrowernumber = s.borrowernumber
JOIN categories c  ON c.categorycode    = bo.categorycode
WHERE s.type='issue'
  AND s.datetime >= DATE_FORMAT(CURDATE(),'%Y-%m-01')
GROUP BY c.description
ORDER BY checkouts DESC;

-- ------------------------------------------------------------
-- Name: KPI_COLLECTION_BY_ITYPE
-- Notes: Collection size by item type.
-- ------------------------------------------------------------
SELECT COALESCE(it.description, i.itype, 'Unspecified') AS item_type,
       COUNT(*) AS copies
FROM items i
LEFT JOIN itemtypes it ON it.itemtype = i.itype
GROUP BY 1
ORDER BY copies DESC;

-- ------------------------------------------------------------
-- Name: KPI_NEW_ITEMS_MONTHLY
-- Notes: Items accessioned per month, last 13 months.
-- ------------------------------------------------------------
SELECT DATE_FORMAT(dateaccessioned,'%Y-%m') AS month, COUNT(*) AS added
FROM items
WHERE dateaccessioned >= DATE_SUB(DATE_FORMAT(CURDATE(),'%Y-%m-01'), INTERVAL 12 MONTH)
GROUP BY month
ORDER BY month;

-- ============================================================
-- OPAC widget reports (also Public; consumed by opac-widgets/)
-- ============================================================

-- ------------------------------------------------------------
-- Name: WIDGET_NEW_ARRIVALS
-- Notes: Newest 12 titles added in the last 60 days.
-- ------------------------------------------------------------
SELECT b.biblionumber, b.title, b.author,
       DATE(MAX(i.dateaccessioned)) AS added
FROM items i
JOIN biblio b ON b.biblionumber = i.biblionumber
WHERE i.dateaccessioned >= CURDATE() - INTERVAL 60 DAY
GROUP BY b.biblionumber, b.title, b.author
ORDER BY added DESC
LIMIT 12;

-- ------------------------------------------------------------
-- Name: WIDGET_MOST_BORROWED
-- Notes: 10 most-borrowed titles, last 90 days.
-- ------------------------------------------------------------
SELECT b.biblionumber, b.title, b.author, COUNT(*) AS times_borrowed
FROM statistics s
JOIN items  i ON i.itemnumber   = s.itemnumber
JOIN biblio b ON b.biblionumber = i.biblionumber
WHERE s.type='issue'
  AND s.datetime >= CURDATE() - INTERVAL 90 DAY
GROUP BY b.biblionumber, b.title, b.author
ORDER BY times_borrowed DESC
LIMIT 10;

-- ------------------------------------------------------------
-- Name: WIDGET_GLANCE
-- Notes: One-row "library at a glance" counters.
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM biblio) AS titles,
  (SELECT COUNT(*) FROM items)  AS copies,
  (SELECT COUNT(*) FROM borrowers) AS members,
  (SELECT COUNT(*) FROM statistics
     WHERE type='issue' AND YEAR(datetime)=YEAR(CURDATE())) AS checkouts_this_year;

-- ============================================================
-- Branch-level variants (v2) — one row per branch library, for
-- multi-branch instances like library-svu (8 constituent libraries).
-- All Public-safe: aggregates + bibliographic data only.
-- ============================================================

-- ------------------------------------------------------------
-- Name: KPI_SNAPSHOT_BR
-- Notes: One-row-per-branch snapshot.
-- ------------------------------------------------------------
SELECT br.branchcode AS branch, br.branchname AS branch_name,
  (SELECT COUNT(*) FROM items i WHERE i.homebranch = br.branchcode) AS copies,
  (SELECT COUNT(DISTINCT i.biblionumber) FROM items i WHERE i.homebranch = br.branchcode) AS titles,
  (SELECT COUNT(*) FROM borrowers p WHERE p.branchcode = br.branchcode) AS members,
  (SELECT COUNT(DISTINCT s.borrowernumber) FROM statistics s
     WHERE s.branch = br.branchcode AND s.type='issue'
       AND s.datetime >= CURDATE() - INTERVAL 90 DAY) AS active_members_90d,
  (SELECT COUNT(*) FROM issues iss WHERE iss.branchcode = br.branchcode) AS current_checkouts,
  (SELECT COUNT(*) FROM issues iss WHERE iss.branchcode = br.branchcode
     AND iss.date_due < NOW()) AS overdue_now,
  (SELECT COUNT(*) FROM reserves r WHERE r.branchcode = br.branchcode) AS open_holds,
  (SELECT IFNULL(ROUND(SUM(a.amountoutstanding),2),0) FROM accountlines a
     JOIN borrowers p2 ON p2.borrowernumber = a.borrowernumber
     WHERE p2.branchcode = br.branchcode AND a.amountoutstanding > 0) AS fines_outstanding
FROM branches br
ORDER BY br.branchcode;

-- ------------------------------------------------------------
-- Name: KPI_MONTHLY_CIRC_BR
-- Notes: Circulation per branch per month, last 13 months.
-- ------------------------------------------------------------
SELECT s.branch, DATE_FORMAT(s.datetime,'%Y-%m') AS month,
       SUM(s.type='issue')  AS checkouts,
       SUM(s.type='return') AS returns,
       SUM(s.type='renew')  AS renewals
FROM statistics s
WHERE s.datetime >= DATE_SUB(DATE_FORMAT(CURDATE(),'%Y-%m-01'), INTERVAL 12 MONTH)
  AND s.type IN ('issue','return','renew')
GROUP BY s.branch, month
ORDER BY s.branch, month;

-- ------------------------------------------------------------
-- Name: KPI_DAILY_CIRC_BR
-- Notes: Circulation per branch per day, last 30 days.
-- ------------------------------------------------------------
SELECT s.branch, DATE(s.datetime) AS day,
       SUM(s.type='issue')  AS checkouts,
       SUM(s.type='return') AS returns,
       SUM(s.type='renew')  AS renewals
FROM statistics s
WHERE s.datetime >= CURDATE() - INTERVAL 30 DAY
  AND s.type IN ('issue','return','renew')
GROUP BY s.branch, day
ORDER BY s.branch, day;

-- ------------------------------------------------------------
-- Name: KPI_TOP_TITLES_MONTH_BR
-- Notes: Top 5 borrowed titles per branch this month.
-- ------------------------------------------------------------
SELECT branch, title, author, checkouts FROM (
  SELECT s.branch AS branch, b.title, b.author, COUNT(*) AS checkouts,
         ROW_NUMBER() OVER (PARTITION BY s.branch ORDER BY COUNT(*) DESC) AS rn
  FROM statistics s
  JOIN items  i ON i.itemnumber   = s.itemnumber
  JOIN biblio b ON b.biblionumber = i.biblionumber
  WHERE s.type='issue'
    AND s.datetime >= DATE_FORMAT(CURDATE(),'%Y-%m-01')
  GROUP BY s.branch, b.biblionumber, b.title, b.author
) ranked
WHERE rn <= 5
ORDER BY branch, checkouts DESC;

-- ------------------------------------------------------------
-- Name: KPI_CIRC_BY_CATEGORY_BR
-- Notes: Checkouts per branch by patron category, this month.
-- ------------------------------------------------------------
SELECT s.branch, c.description AS category, COUNT(*) AS checkouts
FROM statistics s
JOIN borrowers  bo ON bo.borrowernumber = s.borrowernumber
JOIN categories c  ON c.categorycode    = bo.categorycode
WHERE s.type='issue'
  AND s.datetime >= DATE_FORMAT(CURDATE(),'%Y-%m-01')
GROUP BY s.branch, c.description
ORDER BY s.branch, checkouts DESC;

-- ------------------------------------------------------------
-- Name: KPI_COLLECTION_BY_ITYPE_BR
-- Notes: Collection per branch by item type.
-- ------------------------------------------------------------
SELECT i.homebranch AS branch,
       COALESCE(it.description, i.itype, 'Unspecified') AS item_type,
       COUNT(*) AS copies
FROM items i
LEFT JOIN itemtypes it ON it.itemtype = i.itype
GROUP BY i.homebranch, item_type
ORDER BY branch, copies DESC;

-- ------------------------------------------------------------
-- Name: KPI_NEW_ITEMS_MONTHLY_BR
-- Notes: Items accessioned per branch per month, last 13 months.
-- ------------------------------------------------------------
SELECT i.homebranch AS branch, DATE_FORMAT(i.dateaccessioned,'%Y-%m') AS month,
       COUNT(*) AS added
FROM items i
WHERE i.dateaccessioned >= DATE_SUB(DATE_FORMAT(CURDATE(),'%Y-%m-01'), INTERVAL 12 MONTH)
GROUP BY branch, month
ORDER BY branch, month;
