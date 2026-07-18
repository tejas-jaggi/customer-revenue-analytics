-- =====================================================================
-- Validation: Dim_Return_Reason (Phase 3.7)
--
-- Slower, business-aware checks -- does the data satisfy the rules that
-- make it usable, not just "did the load mechanically work" (that's
-- sql/verification/smoke_test_dim_return_reason.sql). Every check below
-- returns an empty result set (or an explicit PASS) when clean.
-- =====================================================================

-- 1. reason_code must exactly match the closed taxonomy documented in
--    business_glossary.md -- no extra reason, no missing reason, no typo
SELECT reason_code AS unexpected_reason_code
FROM Dim_Return_Reason
WHERE reason_code NOT IN (
    'WRONG_SIZE', 'DEFECTIVE_QUALITY', 'NOT_AS_DESCRIBED',
    'CHANGED_MIND', 'LATE_DELIVERY', 'OTHER'
);

-- 1b. The reverse direction -- every documented reason must actually be present
WITH expected_reasons(reason_code) AS (
    VALUES ('WRONG_SIZE'), ('DEFECTIVE_QUALITY'), ('NOT_AS_DESCRIBED'),
           ('CHANGED_MIND'), ('LATE_DELIVERY'), ('OTHER')
)
SELECT e.reason_code AS missing_reason_code
FROM expected_reasons e
LEFT JOIN Dim_Return_Reason d ON d.reason_code = e.reason_code
WHERE d.reason_code IS NULL;

-- 2. No duplicate reason_code or reason_description
SELECT reason_code, COUNT(*) AS occurrences
FROM Dim_Return_Reason
GROUP BY reason_code
HAVING COUNT(*) > 1;

-- 3. reason_code -> is_controllable must match the canonical mapping.
--    Late Delivery and Other are the two judgment calls documented in
--    generate_dim_return_reason.py (glossary says "Partially" and "N/A"
--    respectively -- mapped to TRUE and FALSE for this strict boolean
--    column; see that module's docstring for the reasoning).
SELECT reason_code, is_controllable AS actual_is_controllable
FROM Dim_Return_Reason
WHERE (reason_code = 'WRONG_SIZE'        AND is_controllable != TRUE)
   OR (reason_code = 'DEFECTIVE_QUALITY' AND is_controllable != TRUE)
   OR (reason_code = 'NOT_AS_DESCRIBED'  AND is_controllable != TRUE)
   OR (reason_code = 'CHANGED_MIND'      AND is_controllable != FALSE)
   OR (reason_code = 'LATE_DELIVERY'     AND is_controllable != TRUE)
   OR (reason_code = 'OTHER'             AND is_controllable != FALSE);

-- 4. Expected distribution -- exactly 4 controllable, 2 not controllable
SELECT is_controllable, COUNT(*) AS reason_count,
       CASE
           WHEN is_controllable = TRUE  AND COUNT(*) = 4 THEN 'PASS'
           WHEN is_controllable = FALSE AND COUNT(*) = 2 THEN 'PASS'
           ELSE 'FAIL'
       END AS result
FROM Dim_Return_Reason
GROUP BY is_controllable
ORDER BY is_controllable;

-- 5. Both is_controllable values must actually be represented (guards
--    against every row accidentally landing on the same flag)
WITH expected_flags(is_controllable) AS (
    VALUES (TRUE), (FALSE)
)
SELECT e.is_controllable AS missing_flag_value
FROM expected_flags e
LEFT JOIN Dim_Return_Reason d ON d.is_controllable = e.is_controllable
WHERE d.is_controllable IS NULL;

-- 6. FK-readiness: return_reason_key must be dense, contiguous, and
--    start at 1 -- this is what Fact_Returns.return_reason_key will
--    reference once that table is built
SELECT MIN(return_reason_key) AS min_key, MAX(return_reason_key) AS max_key,
       COUNT(*) AS row_count,
       CASE WHEN MIN(return_reason_key) = 1
             AND MAX(return_reason_key) = COUNT(*)
             AND COUNT(DISTINCT return_reason_key) = COUNT(*)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Return_Reason;
