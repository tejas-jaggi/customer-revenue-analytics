-- =====================================================================
-- Validation: Dim_Campaign (Phase 3.5)
--
-- Slower, business-aware checks -- does the data satisfy the rules that
-- make it usable, not just "did the load mechanically work" (that's
-- sql/verification/smoke_test_dim_campaign.sql). This table is richer
-- than Phase 3.3/3.4's (9 columns, an enrichment layer over the shared
-- campaign calendar), so this suite is deliberately more thorough than
-- Dim_Sales_Channel's, not lightened to match a "small dimension"
-- assumption. Every check returns an empty result set (or an explicit
-- PASS) when clean.
-- =====================================================================

-- 1. campaign_type must only contain the 3 valid values
SELECT DISTINCT campaign_type AS invalid_campaign_type
FROM Dim_Campaign
WHERE campaign_type NOT IN ('Seasonal Launch', 'Promotional Sale', 'Clearance');

-- 2. discount_depth must only contain the 5 valid values
SELECT DISTINCT discount_depth AS invalid_discount_depth
FROM Dim_Campaign
WHERE discount_depth NOT IN ('None', 'Light', 'Moderate', 'Deep', 'Deepest');

-- 3. season must only contain the 4 valid values
SELECT DISTINCT season AS invalid_season
FROM Dim_Campaign
WHERE season NOT IN ('Spring', 'Summer', 'Fall', 'Winter');

-- 4. target_audience must only contain the 4 valid values
SELECT DISTINCT target_audience AS invalid_target_audience
FROM Dim_Campaign
WHERE target_audience NOT IN ('All Customers', 'New Customers', 'Loyal-VIP', 'Lapsed-Winback');

-- 5. No duplicate campaign_name (each year's instance of a campaign is distinct)
SELECT campaign_name, COUNT(*) AS occurrences
FROM Dim_Campaign
GROUP BY campaign_name
HAVING COUNT(*) > 1;

-- 6. end_date must never precede start_date (Python already checks this
--    pre-load; this re-confirms it against the actual loaded table)
SELECT campaign_name, start_date, end_date
FROM Dim_Campaign
WHERE end_date < start_date;

-- 7. Every campaign_name -> discount_depth pairing must match the
--    canonical mapping from business_glossary.md (catches a transcription
--    slip: right campaign, wrong discount depth). campaign_name includes
--    the year (e.g. "Black Friday 2024"), so this matches on prefix.
SELECT campaign_name, discount_depth AS actual_discount_depth
FROM Dim_Campaign
WHERE (campaign_name LIKE 'Spring Collection Launch%' AND discount_depth != 'None')
   OR (campaign_name LIKE 'Summer Sale%'              AND discount_depth != 'Moderate')
   OR (campaign_name LIKE 'Back-to-School%'            AND discount_depth != 'Moderate')
   OR (campaign_name LIKE 'Black Friday%'              AND discount_depth != 'Deep')
   OR (campaign_name LIKE 'Cyber Monday%'               AND discount_depth != 'Deep')
   OR (campaign_name LIKE 'Holiday Collection%'         AND discount_depth != 'Light')
   OR (campaign_name LIKE 'January Clearance%'          AND discount_depth != 'Deepest');

-- 8. Every campaign appears in exactly 3 distinct years (2023, 2024, 2025) --
--    structural completeness check. Uses a LIKE-based base-name grouping
--    since campaign_name embeds the year.
WITH base_names AS (
    SELECT
        campaign_key,
        start_date,
        CASE
            WHEN campaign_name LIKE 'Spring Collection Launch%' THEN 'Spring Collection Launch'
            WHEN campaign_name LIKE 'Summer Sale%'              THEN 'Summer Sale'
            WHEN campaign_name LIKE 'Back-to-School%'           THEN 'Back-to-School'
            WHEN campaign_name LIKE 'Black Friday%'             THEN 'Black Friday'
            WHEN campaign_name LIKE 'Cyber Monday%'             THEN 'Cyber Monday'
            WHEN campaign_name LIKE 'Holiday Collection%'       THEN 'Holiday Collection'
            WHEN campaign_name LIKE 'January Clearance%'        THEN 'January Clearance'
            ELSE 'UNRECOGNIZED: ' || campaign_name
        END AS base_name
    FROM Dim_Campaign
)
SELECT base_name, COUNT(DISTINCT EXTRACT(YEAR FROM start_date)) AS distinct_years,
       CASE WHEN COUNT(DISTINCT EXTRACT(YEAR FROM start_date)) = 3 THEN 'PASS' ELSE 'FAIL' END AS result
FROM base_names
GROUP BY base_name
ORDER BY base_name;

-- 9. Expected distribution: discount_depth (exact counts, not a range --
--    this table's shape is fully deterministic)
SELECT discount_depth, COUNT(*) AS campaign_count,
       CASE
           WHEN discount_depth = 'None'     AND COUNT(*) = 3 THEN 'PASS'
           WHEN discount_depth = 'Moderate' AND COUNT(*) = 6 THEN 'PASS'
           WHEN discount_depth = 'Deep'     AND COUNT(*) = 6 THEN 'PASS'
           WHEN discount_depth = 'Light'    AND COUNT(*) = 3 THEN 'PASS'
           WHEN discount_depth = 'Deepest'  AND COUNT(*) = 3 THEN 'PASS'
           ELSE 'FAIL'
       END AS result
FROM Dim_Campaign
GROUP BY discount_depth
ORDER BY discount_depth;

-- 10. Expected distribution: campaign_type (exact counts)
SELECT campaign_type, COUNT(*) AS campaign_count,
       CASE
           WHEN campaign_type = 'Seasonal Launch'  AND COUNT(*) = 6  THEN 'PASS'
           WHEN campaign_type = 'Promotional Sale'  AND COUNT(*) = 12 THEN 'PASS'
           WHEN campaign_type = 'Clearance'         AND COUNT(*) = 3  THEN 'PASS'
           ELSE 'FAIL'
       END AS result
FROM Dim_Campaign
GROUP BY campaign_type
ORDER BY campaign_type;

-- 11. Expected distribution: season (exact counts). NOTE: 'Spring' is
--     expected to be ABSENT entirely -- "Spring Collection Launch" starts
--     Feb 15, which is calendar Winter under the same month->season
--     mapping Dim_Date uses. This is intentional, documented behavior,
--     not a bug (see generate_dim_campaign.py's module docstring).
SELECT season, COUNT(*) AS campaign_count,
       CASE
           WHEN season = 'Winter' AND COUNT(*) = 8 THEN 'PASS'
           WHEN season = 'Fall'   AND COUNT(*) = 7 THEN 'PASS'
           WHEN season = 'Summer' AND COUNT(*) = 6 THEN 'PASS'
           ELSE 'FAIL'
       END AS result
FROM Dim_Campaign
GROUP BY season
ORDER BY season;

-- 11b. Explicit confirmation that 'Spring' truly has zero rows (distinct
--      from the check above, which would simply omit it silently)
SELECT COUNT(*) AS spring_row_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Campaign
WHERE season = 'Spring';

-- 12. MVP scope: every row's target_audience should be 'All Customers'
--     (see module docstring for why the other enum values are valid but
--     unused in this generation)
SELECT DISTINCT target_audience
FROM Dim_Campaign
WHERE target_audience != 'All Customers';

-- 13. Every row's is_active_flag should be TRUE in this initial generation
SELECT COUNT(*) AS inactive_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Campaign
WHERE is_active_flag != TRUE;

-- 14. FK-readiness: campaign_key must be dense, contiguous, and start at
--     1 -- this is what Fact_Orders.campaign_key (a NULLABLE FK -- not
--     every order ties to a named campaign) will reference once that
--     table is built
SELECT MIN(campaign_key) AS min_key, MAX(campaign_key) AS max_key,
       COUNT(*) AS row_count,
       CASE WHEN MIN(campaign_key) = 1
             AND MAX(campaign_key) = COUNT(*)
             AND COUNT(DISTINCT campaign_key) = COUNT(*)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Campaign;
