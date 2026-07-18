-- =====================================================================
-- Smoke Test: Dim_Date (created in Phase 4)
--
-- Closes a historical gap: Phase 3.1 predates ED-002, which formalised
-- the verification/validation split, so Dim_Date received a validation
-- suite but never a smoke test. Same era as the `assert` usage ED-003
-- flags retroactively. Created here rather than left as a known hole --
-- Dim_Date is the conformed dimension every fact's date role points at,
-- so it is the last table that should lack a mechanical check.
-- =====================================================================

-- @CHECK: id=D.1; tier=SMOKE; severity=BLOCKING; name=Row count is exactly 1096 (2023-2025 inclusive, 365+366+365)
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) = 1096 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date;

-- @CHECK: id=D.2; tier=SMOKE; severity=BLOCKING; name=date_key is non-null and unique
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT date_key) AS distinct_keys,
       CASE WHEN COUNT(*) = COUNT(DISTINCT date_key) AND COUNT(*) = COUNT(date_key)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date;

-- @CHECK: id=D.3; tier=SMOKE; severity=BLOCKING; name=full_date is non-null and unique
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT full_date) AS distinct_dates,
       CASE WHEN COUNT(*) = COUNT(DISTINCT full_date) AND COUNT(*) = COUNT(full_date)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date;

-- @CHECK: id=D.4; tier=SMOKE; severity=BLOCKING; name=NOT NULL sweep across every NOT NULL column
SELECT CASE WHEN SUM(CASE WHEN full_date IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN year IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN quarter IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN month IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN month_name IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN week_of_year IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN day_of_week IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN day_name IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN is_weekend IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN holiday_flag IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN fiscal_quarter IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN fiscal_year IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN season IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN campaign_period_flag IS NULL THEN 1 ELSE 0 END) = 0
       THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date;

-- @CHECK: id=D.5; tier=SMOKE; severity=BLOCKING; name=date_key matches YYYYMMDD of full_date
SELECT COUNT(*) AS mismatched_keys,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date
WHERE date_key != CAST(STRFTIME(full_date, '%Y%m%d') AS INTEGER);

-- @CHECK: id=D.6; tier=SMOKE; severity=BLOCKING; name=Calendar is contiguous with no missing days
WITH gaps AS (
    SELECT full_date, LAG(full_date) OVER (ORDER BY full_date) AS prev_date FROM Dim_Date
)
SELECT COUNT(*) AS gap_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM gaps
WHERE prev_date IS NOT NULL AND DATE_DIFF('day', prev_date, full_date) != 1;

-- @CHECK: id=D.7; tier=SMOKE; severity=BLOCKING; name=Calendar spans exactly 2023-01-01 through 2025-12-31
SELECT MIN(full_date) AS first_date, MAX(full_date) AS last_date,
       CASE WHEN MIN(full_date) = DATE '2023-01-01' AND MAX(full_date) = DATE '2025-12-31'
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date;
