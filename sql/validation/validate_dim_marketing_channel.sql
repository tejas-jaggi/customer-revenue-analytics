-- =====================================================================
-- Validation: Dim_Marketing_Channel (Phase 3.3)
--
-- Slower, business-aware checks -- does the data satisfy the rules that
-- make it usable, not just "did the load mechanically work" (that's
-- sql/verification/smoke_test_dim_marketing_channel.sql). Every check
-- below returns an empty result set (or an explicit PASS) when clean.
-- =====================================================================

-- 1. channel_category must only contain the 3 valid values
SELECT DISTINCT channel_category AS invalid_category
FROM Dim_Marketing_Channel
WHERE channel_category NOT IN ('Paid', 'Organic', 'Owned');

-- 2. channel_name must exactly match the closed taxonomy documented in
--    business_glossary.md -- no extra channel, no missing channel, no typo
SELECT channel_name AS unexpected_channel_name
FROM Dim_Marketing_Channel
WHERE channel_name NOT IN (
    'Paid Social', 'Paid Search', 'Organic/SEO', 'Email/SMS', 'Affiliate/Referral', 'Direct'
);

-- 2b. The reverse direction -- every documented channel must actually be present
WITH expected_channels(channel_name) AS (
    VALUES ('Paid Social'), ('Paid Search'), ('Organic/SEO'),
           ('Email/SMS'), ('Affiliate/Referral'), ('Direct')
)
SELECT e.channel_name AS missing_channel_name
FROM expected_channels e
LEFT JOIN Dim_Marketing_Channel d ON d.channel_name = e.channel_name
WHERE d.channel_name IS NULL;

-- 3. No duplicate channel_name
SELECT channel_name, COUNT(*) AS occurrences
FROM Dim_Marketing_Channel
GROUP BY channel_name
HAVING COUNT(*) > 1;

-- 4. channel_name -> channel_category must match the canonical mapping
--    from business_glossary.md exactly (catches a transcription slip:
--    right channel, wrong category)
SELECT marketing_channel_key, channel_name, channel_category AS actual_category
FROM Dim_Marketing_Channel
WHERE (channel_name = 'Paid Social'        AND channel_category != 'Paid')
   OR (channel_name = 'Paid Search'        AND channel_category != 'Paid')
   OR (channel_name = 'Organic/SEO'        AND channel_category != 'Organic')
   OR (channel_name = 'Email/SMS'          AND channel_category != 'Owned')
   OR (channel_name = 'Affiliate/Referral' AND channel_category != 'Paid')
   OR (channel_name = 'Direct'             AND channel_category != 'Organic');

-- 5. Expected distribution -- 3 Paid, 2 Organic, 1 Owned (informational
--    and PASS/FAIL both: this is a small, exactly-known distribution,
--    unlike Dim_Geography's "at least N" regional thresholds)
SELECT channel_category, COUNT(*) AS channel_count,
       CASE
           WHEN channel_category = 'Paid' AND COUNT(*) = 3 THEN 'PASS'
           WHEN channel_category = 'Organic' AND COUNT(*) = 2 THEN 'PASS'
           WHEN channel_category = 'Owned' AND COUNT(*) = 1 THEN 'PASS'
           ELSE 'FAIL'
       END AS result
FROM Dim_Marketing_Channel
GROUP BY channel_category
ORDER BY channel_category;

-- 6. No category missing entirely (all 3 must appear at least once)
WITH expected_categories(channel_category) AS (
    VALUES ('Paid'), ('Organic'), ('Owned')
)
SELECT e.channel_category AS missing_category
FROM expected_categories e
LEFT JOIN Dim_Marketing_Channel d ON d.channel_category = e.channel_category
WHERE d.channel_category IS NULL;

-- 7. FK-readiness: marketing_channel_key must be dense, contiguous, and
--    start at 1 -- this is exactly what Dim_Customer.acquisition_channel_key
--    and Fact_Orders.acquisition_channel_key will reference once those
--    tables are built
SELECT MIN(marketing_channel_key) AS min_key, MAX(marketing_channel_key) AS max_key,
       COUNT(*) AS row_count,
       CASE WHEN MIN(marketing_channel_key) = 1
             AND MAX(marketing_channel_key) = COUNT(*)
             AND COUNT(DISTINCT marketing_channel_key) = COUNT(*)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Marketing_Channel;
