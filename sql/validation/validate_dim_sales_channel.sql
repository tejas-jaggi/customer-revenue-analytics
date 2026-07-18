-- =====================================================================
-- Validation: Dim_Sales_Channel (Phase 3.4)
--
-- Slower, business-aware checks -- does the data satisfy the rules that
-- make it usable, not just "did the load mechanically work" (that's
-- sql/verification/smoke_test_dim_sales_channel.sql). Every check below
-- returns an empty result set (or an explicit PASS) when clean.
-- =====================================================================

-- 1. channel_type must only contain the 2 valid values
SELECT DISTINCT channel_type AS invalid_type
FROM Dim_Sales_Channel
WHERE channel_type NOT IN ('Owned', 'Third-Party');

-- 2. channel_name must exactly match the closed taxonomy documented in
--    business_glossary.md -- no extra channel, no missing channel, no typo
SELECT channel_name AS unexpected_channel_name
FROM Dim_Sales_Channel
WHERE channel_name NOT IN ('Website', 'Mobile App', 'Marketplace');

-- 2b. The reverse direction -- every documented channel must actually be present
WITH expected_channels(channel_name) AS (
    VALUES ('Website'), ('Mobile App'), ('Marketplace')
)
SELECT e.channel_name AS missing_channel_name
FROM expected_channels e
LEFT JOIN Dim_Sales_Channel d ON d.channel_name = e.channel_name
WHERE d.channel_name IS NULL;

-- 3. No duplicate channel_name
SELECT channel_name, COUNT(*) AS occurrences
FROM Dim_Sales_Channel
GROUP BY channel_name
HAVING COUNT(*) > 1;

-- 4. channel_name -> channel_type must match the canonical mapping from
--    business_glossary.md exactly (catches a transcription slip: right
--    channel, wrong type)
SELECT sales_channel_key, channel_name, channel_type AS actual_type
FROM Dim_Sales_Channel
WHERE (channel_name = 'Website'     AND channel_type != 'Owned')
   OR (channel_name = 'Mobile App'  AND channel_type != 'Owned')
   OR (channel_name = 'Marketplace' AND channel_type != 'Third-Party');

-- 5. Expected distribution -- 2 Owned, 1 Third-Party (exactly known,
--    same reasoning as Dim_Marketing_Channel's exact distribution check)
SELECT channel_type, COUNT(*) AS channel_count,
       CASE
           WHEN channel_type = 'Owned' AND COUNT(*) = 2 THEN 'PASS'
           WHEN channel_type = 'Third-Party' AND COUNT(*) = 1 THEN 'PASS'
           ELSE 'FAIL'
       END AS result
FROM Dim_Sales_Channel
GROUP BY channel_type
ORDER BY channel_type;

-- 6. No type missing entirely (both must appear at least once)
WITH expected_types(channel_type) AS (
    VALUES ('Owned'), ('Third-Party')
)
SELECT e.channel_type AS missing_type
FROM expected_types e
LEFT JOIN Dim_Sales_Channel d ON d.channel_type = e.channel_type
WHERE d.channel_type IS NULL;

-- 7. FK-readiness: sales_channel_key must be dense, contiguous, and
--    start at 1 -- this is exactly what Fact_Orders.sales_channel_key
--    will reference once that table is built
SELECT MIN(sales_channel_key) AS min_key, MAX(sales_channel_key) AS max_key,
       COUNT(*) AS row_count,
       CASE WHEN MIN(sales_channel_key) = 1
             AND MAX(sales_channel_key) = COUNT(*)
             AND COUNT(DISTINCT sales_channel_key) = COUNT(*)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Sales_Channel;
