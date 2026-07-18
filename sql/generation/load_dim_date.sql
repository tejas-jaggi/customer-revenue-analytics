-- =====================================================================
-- Load: Dim_Date (Phase 3.1)
--
-- Standalone SQL-only load path.
--
-- This script mirrors the behavior of generate_dim_date.py by loading the
-- deterministic CSV output into DuckDB.
--
-- The load is wrapped in a transaction to ensure atomicity:
-- either the entire load succeeds or no changes are committed.
--
-- Prerequisites:
--   1. Run python/generators/init_database.py to create the database schema.
--   2. Run python/generators/generate_dim_date.py to generate data/generated/dim_date.csv.
-- The SQL script loads the generated CSV but does not create it.
--
-- Run:
--   duckdb data/database/solstice_apparel.duckdb
--   .read sql/generation/load_dim_date.sql
-- =====================================================================

BEGIN TRANSACTION;

-- Remove existing rows so the script remains idempotent.
DELETE FROM Dim_Date;

-- Load the freshly generated CSV.
COPY Dim_Date (
    date_key,
    full_date,
    year,
    quarter,
    month,
    month_name,
    week_of_year,
    day_of_week,
    day_name,
    is_weekend,
    holiday_flag,
    fiscal_quarter,
    fiscal_year,
    season,
    campaign_period_flag
)
FROM 'data/generated/dim_date.csv'
(
    HEADER,
    DELIMITER ','
);

-- Verify the final row count before committing.
-- Expected result: 1096 rows
SELECT
    COUNT(*) AS rows_loaded
FROM Dim_Date;

COMMIT;