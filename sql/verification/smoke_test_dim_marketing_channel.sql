-- =====================================================================
-- Smoke Test: Dim_Marketing_Channel (Phase 3.3)
--
-- Fast, mechanical checks -- did the load succeed at all. Run
-- immediately after generate_dim_marketing_channel.py or
-- load_dim_marketing_channel.sql. Deeper business-rule checks live in
-- sql/validation/validate_dim_marketing_channel.sql, not here.
-- =====================================================================

-- 1. Row count must be exactly 6 (closed taxonomy, not a range)
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) = 6 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Marketing_Channel;

-- 2. marketing_channel_key: no nulls, no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT marketing_channel_key) AS distinct_keys,
    COUNT(marketing_channel_key) AS non_null_keys,
    CASE WHEN COUNT(*) = COUNT(DISTINCT marketing_channel_key)
              AND COUNT(*) = COUNT(marketing_channel_key)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Marketing_Channel;

-- 3. No nulls in channel_name / channel_category
SELECT
    SUM(CASE WHEN channel_name IS NULL THEN 1 ELSE 0 END) AS null_channel_name,
    SUM(CASE WHEN channel_category IS NULL THEN 1 ELSE 0 END) AS null_channel_category,
    CASE WHEN SUM(CASE WHEN channel_name IS NULL THEN 1 ELSE 0 END) = 0
              AND SUM(CASE WHEN channel_category IS NULL THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Marketing_Channel;

-- 4. Structural shape check -- confirms the table has exactly the
--    columns schema.sql defines (catches a load into the wrong table
--    or a schema drift immediately, before deeper checks run)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'Dim_Marketing_Channel'
ORDER BY ordinal_position;
