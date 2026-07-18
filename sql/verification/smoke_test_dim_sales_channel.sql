-- =====================================================================
-- Smoke Test: Dim_Sales_Channel (Phase 3.4)
--
-- Fast, mechanical checks -- did the load succeed at all. Run
-- immediately after generate_dim_sales_channel.py or
-- load_dim_sales_channel.sql. Deeper business-rule checks live in
-- sql/validation/validate_dim_sales_channel.sql, not here.
-- =====================================================================

-- 1. Row count must be exactly 3 (closed taxonomy, not a range)
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Sales_Channel;

-- 2. sales_channel_key: no nulls, no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT sales_channel_key) AS distinct_keys,
    COUNT(sales_channel_key) AS non_null_keys,
    CASE WHEN COUNT(*) = COUNT(DISTINCT sales_channel_key)
              AND COUNT(*) = COUNT(sales_channel_key)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Sales_Channel;

-- 3. No nulls in channel_name / channel_type
SELECT
    SUM(CASE WHEN channel_name IS NULL THEN 1 ELSE 0 END) AS null_channel_name,
    SUM(CASE WHEN channel_type IS NULL THEN 1 ELSE 0 END) AS null_channel_type,
    CASE WHEN SUM(CASE WHEN channel_name IS NULL THEN 1 ELSE 0 END) = 0
              AND SUM(CASE WHEN channel_type IS NULL THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Sales_Channel;

-- 4. Structural shape check -- confirms the table has exactly the
--    columns schema.sql defines
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'Dim_Sales_Channel'
ORDER BY ordinal_position;
