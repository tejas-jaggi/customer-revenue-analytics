-- =====================================================================
-- Smoke Test: Dim_Return_Reason (Phase 3.7)
--
-- Fast, mechanical checks -- did the load succeed at all. Run
-- immediately after generate_dim_return_reason.py or
-- load_dim_return_reason.sql. Deeper business-rule checks live in
-- sql/validation/validate_dim_return_reason.sql, not here.
-- =====================================================================

-- 1. Row count must be exactly 6 (closed taxonomy, not a range)
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) = 6 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Return_Reason;

-- 2. return_reason_key: no nulls, no duplicates
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT return_reason_key) AS distinct_keys,
    COUNT(return_reason_key) AS non_null_keys,
    CASE WHEN COUNT(*) = COUNT(DISTINCT return_reason_key)
              AND COUNT(*) = COUNT(return_reason_key)
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Return_Reason;

-- 3. No nulls in reason_code / reason_description / is_controllable
SELECT
    SUM(CASE WHEN reason_code IS NULL THEN 1 ELSE 0 END)        AS null_reason_code,
    SUM(CASE WHEN reason_description IS NULL THEN 1 ELSE 0 END) AS null_reason_description,
    SUM(CASE WHEN is_controllable IS NULL THEN 1 ELSE 0 END)    AS null_is_controllable,
    CASE WHEN SUM(CASE WHEN reason_code IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN reason_description IS NULL THEN 1 ELSE 0 END)
            + SUM(CASE WHEN is_controllable IS NULL THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Return_Reason;

-- 4. Structural shape check -- confirms the table has exactly the
--    columns schema.sql defines
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'Dim_Return_Reason'
ORDER BY ordinal_position;
