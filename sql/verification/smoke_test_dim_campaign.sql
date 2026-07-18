-- =====================================================================
-- Smoke Test: Dim_Campaign (Phase 3.5)
--
-- Fast, mechanical checks -- did the load succeed at all. Run
-- immediately after generate_dim_campaign.py or load_dim_campaign.sql.
-- Deeper business-rule checks live in
-- sql/validation/validate_dim_campaign.sql, not here.
-- =====================================================================

-- 1. Row count must be exactly 21 (7 named campaigns x 3 years)
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) = 21 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Campaign;

-- 2. campaign_key: no nulls, no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT campaign_key) AS distinct_keys,
    COUNT(campaign_key) AS non_null_keys,
    CASE WHEN COUNT(*) = COUNT(DISTINCT campaign_key)
              AND COUNT(*) = COUNT(campaign_key)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Campaign;

-- 3. No nulls in any NOT NULL column
SELECT
    SUM(CASE WHEN campaign_name IS NULL THEN 1 ELSE 0 END)     AS null_campaign_name,
    SUM(CASE WHEN campaign_type IS NULL THEN 1 ELSE 0 END)     AS null_campaign_type,
    SUM(CASE WHEN start_date IS NULL THEN 1 ELSE 0 END)        AS null_start_date,
    SUM(CASE WHEN end_date IS NULL THEN 1 ELSE 0 END)          AS null_end_date,
    SUM(CASE WHEN discount_depth IS NULL THEN 1 ELSE 0 END)    AS null_discount_depth,
    SUM(CASE WHEN season IS NULL THEN 1 ELSE 0 END)            AS null_season,
    SUM(CASE WHEN target_audience IS NULL THEN 1 ELSE 0 END)   AS null_target_audience,
    SUM(CASE WHEN is_active_flag IS NULL THEN 1 ELSE 0 END)    AS null_is_active_flag,
    CASE WHEN SUM(CASE WHEN campaign_name IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN campaign_type IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN start_date IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN end_date IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN discount_depth IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN season IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN target_audience IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN is_active_flag IS NULL THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Campaign;

-- 4. schema.sql's CHECK (end_date >= start_date) constraint sanity read --
--    if the load succeeded at all, this is already enforced by the
--    database, but surfacing it here makes the smoke test self-contained
SELECT COUNT(*) AS rows_with_bad_date_order,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Campaign
WHERE end_date < start_date;

-- 5. Structural shape check -- confirms the table has exactly the
--    columns schema.sql defines
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'Dim_Campaign'
ORDER BY ordinal_position;
