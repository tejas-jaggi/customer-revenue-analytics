-- =====================================================================
-- Validation: Dim_Date (Phase 3.1)
--
-- Run against data/solstice_apparel.duckdb after generate_dim_date.py
-- (or sql/load_dim_date.sql) has populated the table. Every check
-- returns a PASS/FAIL column so this can be scanned quickly rather
-- than eyeballing raw numbers.
-- =====================================================================

-- 1. Row count must be exactly 1,096 (365 + 366 [2024 leap year] + 365)
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) = 1096 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date;

-- 2. date_key must be unique (no duplicate calendar days)
SELECT COUNT(*) AS duplicate_date_keys,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT date_key FROM Dim_Date GROUP BY date_key HAVING COUNT(*) > 1
);

-- 3. Date range must be exactly 2023-01-01 through 2025-12-31
SELECT MIN(full_date) AS min_date, MAX(full_date) AS max_date,
       CASE WHEN MIN(full_date) = DATE '2023-01-01' AND MAX(full_date) = DATE '2025-12-31'
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date;

-- 4. No gaps: distinct full_date count must equal total row count
SELECT COUNT(DISTINCT full_date) AS distinct_dates, COUNT(*) AS total_rows,
       CASE WHEN COUNT(DISTINCT full_date) = COUNT(*) THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date;

-- 5. No nulls in any column
SELECT
    SUM(CASE WHEN date_key IS NULL THEN 1 ELSE 0 END)              AS null_date_key,
    SUM(CASE WHEN full_date IS NULL THEN 1 ELSE 0 END)             AS null_full_date,
    SUM(CASE WHEN year IS NULL THEN 1 ELSE 0 END)                  AS null_year,
    SUM(CASE WHEN quarter IS NULL THEN 1 ELSE 0 END)                AS null_quarter,
    SUM(CASE WHEN month IS NULL THEN 1 ELSE 0 END)                  AS null_month,
    SUM(CASE WHEN month_name IS NULL THEN 1 ELSE 0 END)             AS null_month_name,
    SUM(CASE WHEN week_of_year IS NULL THEN 1 ELSE 0 END)           AS null_week_of_year,
    SUM(CASE WHEN day_of_week IS NULL THEN 1 ELSE 0 END)           AS null_day_of_week,
    SUM(CASE WHEN day_name IS NULL THEN 1 ELSE 0 END)               AS null_day_name,
    SUM(CASE WHEN is_weekend IS NULL THEN 1 ELSE 0 END)             AS null_is_weekend,
    SUM(CASE WHEN holiday_flag IS NULL THEN 1 ELSE 0 END)           AS null_holiday_flag,
    SUM(CASE WHEN fiscal_quarter IS NULL THEN 1 ELSE 0 END)        AS null_fiscal_quarter,
    SUM(CASE WHEN fiscal_year IS NULL THEN 1 ELSE 0 END)            AS null_fiscal_year,
    SUM(CASE WHEN season IS NULL THEN 1 ELSE 0 END)                 AS null_season,
    SUM(CASE WHEN campaign_period_flag IS NULL THEN 1 ELSE 0 END)   AS null_campaign_period_flag
FROM Dim_Date;

-- 6. is_weekend must exactly match day_of_week IN (6,7) — Saturday/Sunday
SELECT COUNT(*) AS weekend_logic_mismatches,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date
WHERE is_weekend != (day_of_week IN (6, 7));

-- 7. fiscal_quarter/fiscal_year must equal quarter/year — v1.1 documented
--    assumption that fiscal year = calendar year (see design_decisions.md)
SELECT COUNT(*) AS fiscal_mismatches,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date
WHERE fiscal_quarter != quarter OR fiscal_year != year;

-- 8. season must match the documented month mapping
SELECT COUNT(*) AS season_mismatches,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date
WHERE season != CASE
    WHEN month IN (12, 1, 2) THEN 'Winter'
    WHEN month IN (3, 4, 5)  THEN 'Spring'
    WHEN month IN (6, 7, 8)  THEN 'Summer'
    WHEN month IN (9, 10, 11) THEN 'Fall'
END;

-- 9. holiday_flag: expect exactly 21 flagged dates (7 holidays x 3 years,
--    none of the 7 ever coincide with each other in this calendar)
SELECT COUNT(*) AS holiday_count,
       CASE WHEN COUNT(*) = 21 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date WHERE holiday_flag = TRUE;

-- 10. campaign_period_flag coverage — informational, not pass/fail (windows
--     deliberately overlap, e.g. Holiday Collection over Black Friday, so
--     there's no single "correct" count — this just surfaces the actual
--     coverage for a sanity read).
SELECT
    SUM(CASE WHEN campaign_period_flag THEN 1 ELSE 0 END) AS campaign_days,
    COUNT(*) AS total_days,
    ROUND(100.0 * SUM(CASE WHEN campaign_period_flag THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_campaign_days
FROM Dim_Date;

-- 11. Spot check: Black Friday 2024 (Nov 29, 2024) must land on a Friday
--     and be flagged TRUE for both holiday_flag and campaign_period_flag
SELECT date_key, full_date, day_name, holiday_flag, campaign_period_flag,
       CASE WHEN day_name = 'Friday' AND holiday_flag = TRUE AND campaign_period_flag = TRUE
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date WHERE full_date = DATE '2024-11-29';

-- 12. Spot check: Christmas Day 2023 must be holiday_flag = TRUE
SELECT date_key, full_date, day_name, holiday_flag,
       CASE WHEN holiday_flag = TRUE THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date WHERE full_date = DATE '2023-12-25';

-- 13. Spot check: a random ordinary Tuesday in March (non-holiday,
--     non-campaign, non-weekend) — confirms flags default to FALSE
--     correctly rather than being TRUE everywhere by accident
SELECT date_key, full_date, day_name, is_weekend, holiday_flag, campaign_period_flag,
       CASE WHEN is_weekend = FALSE AND holiday_flag = FALSE AND campaign_period_flag = FALSE
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Date WHERE full_date = DATE '2024-03-26';
