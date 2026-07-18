-- =====================================================================
-- Smoke Test: Dim_Geography (Phase 3.2)
--
-- Fast, mechanical checks that the load succeeded -- did the table get
-- populated, does the primary key look sane, does the shape match
-- schema.sql. This is deliberately NOT business-rule validation (that's
-- sql/validation/validate_dim_geography.sql); this is what you'd run in
-- the few seconds right after any load, before spending time on deeper
-- checks.
-- =====================================================================

-- 1. Table exists and has rows
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Geography;

-- 2. Primary key has no nulls and no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT geography_key) AS distinct_keys,
    COUNT(geography_key) AS non_null_keys,
    CASE WHEN COUNT(*) = COUNT(DISTINCT geography_key) AND COUNT(*) = COUNT(geography_key)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Geography;

-- 3. Every NOT NULL column from schema.sql actually has zero nulls
SELECT
    SUM(CASE WHEN city IS NULL THEN 1 ELSE 0 END)    AS null_city,
    SUM(CASE WHEN state IS NULL THEN 1 ELSE 0 END)   AS null_state,
    SUM(CASE WHEN region IS NULL THEN 1 ELSE 0 END)  AS null_region,
    SUM(CASE WHEN country IS NULL THEN 1 ELSE 0 END) AS null_country,
    CASE WHEN SUM(CASE WHEN city IS NULL OR state IS NULL OR region IS NULL OR country IS NULL THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Geography;

-- 4. Table structure sanity -- confirms the v1.1 patch (postal_code) is
--    actually present, and no column was dropped or renamed
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'Dim_Geography'
ORDER BY ordinal_position;
