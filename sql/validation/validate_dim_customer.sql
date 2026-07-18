-- =====================================================================
-- Validation: Dim_Customer (Phase 3.8)
--
-- Slower, business-aware checks -- does the data satisfy the rules that
-- make it usable, not just "did the load mechanically work" (that's
-- sql/verification/smoke_test_dim_customer.sql). This is the richest
-- validation suite in Phase 3 to date: it's the first table needing
-- both live-parent FK verification (ED-007) and tolerance-based
-- statistical distribution checks (ED-008) rather than exact counts,
-- because acquisition channel and geography are genuinely random draws,
-- not a fixed enumeration like Dim_Product's category counts.
-- =====================================================================

-- 1. customer_id must match the CUST-###### pattern (6 digits)
SELECT customer_id
FROM Dim_Customer
WHERE NOT regexp_matches(customer_id, '^CUST-\d{6}$');

-- 2. email must match the local-part@example.com pattern
SELECT email
FROM Dim_Customer
WHERE NOT regexp_matches(email, '^[^@[:space:]]+@example\.com$');

-- 3. signup_date must fall within Dim_Date's actual populated range
SELECT customer_id, signup_date
FROM Dim_Customer
WHERE signup_date < (SELECT MIN(full_date) FROM Dim_Date)
   OR signup_date > (SELECT MAX(full_date) FROM Dim_Date);

-- 4. signup_date year distribution must be EXACT (2,500 / 3,000 / 2,500 --
--    this is loop-driven, not sampled, so no tolerance applies here,
--    unlike the channel/region checks below)
SELECT EXTRACT(YEAR FROM signup_date) AS signup_year, COUNT(*) AS customer_count,
       CASE
           WHEN EXTRACT(YEAR FROM signup_date) = 2023 AND COUNT(*) = 2500 THEN 'PASS'
           WHEN EXTRACT(YEAR FROM signup_date) = 2024 AND COUNT(*) = 3000 THEN 'PASS'
           WHEN EXTRACT(YEAR FROM signup_date) = 2025 AND COUNT(*) = 2500 THEN 'PASS'
           ELSE 'FAIL'
       END AS result
FROM Dim_Customer
GROUP BY EXTRACT(YEAR FROM signup_date)
ORDER BY signup_year;

-- 5. birth_year must fall within the plausible range implied by
--    18-70 years old at signup across 2023-2025 (1953-2007)
SELECT customer_id, signup_date, birth_year
FROM Dim_Customer
WHERE birth_year IS NULL
   OR birth_year < (EXTRACT(YEAR FROM (SELECT MIN(full_date) FROM Dim_Date)) - 70)
   OR birth_year > (EXTRACT(YEAR FROM (SELECT MAX(full_date) FROM Dim_Date)) - 18);

-- 6. Foreign key integrity: acquisition_channel_key must exist in
--    Dim_Marketing_Channel (schema.sql's REFERENCES constraint already
--    enforces this at load time -- this is an explicit re-confirmation)
SELECT c.customer_id, c.acquisition_channel_key
FROM Dim_Customer c
LEFT JOIN Dim_Marketing_Channel m ON c.acquisition_channel_key = m.marketing_channel_key
WHERE m.marketing_channel_key IS NULL;

-- 7. Foreign key integrity: home_geography_key must exist in Dim_Geography
SELECT c.customer_id, c.home_geography_key
FROM Dim_Customer c
LEFT JOIN Dim_Geography g ON c.home_geography_key = g.geography_key
WHERE g.geography_key IS NULL;

-- 8. Acquisition channel mix per year, within +/-5 percentage points of
--    the documented target (ED-008: tolerance-based, not exact, since
--    this is a genuine weighted-random draw across 2,500-3,000 samples
--    per year, not a fixed enumeration)
WITH channel_by_year AS (
    SELECT
        EXTRACT(YEAR FROM c.signup_date) AS signup_year,
        m.channel_name,
        COUNT(*) AS actual_count
    FROM Dim_Customer c
    JOIN Dim_Marketing_Channel m ON c.acquisition_channel_key = m.marketing_channel_key
    GROUP BY EXTRACT(YEAR FROM c.signup_date), m.channel_name
),
year_totals AS (
    SELECT signup_year, SUM(actual_count) AS year_total
    FROM channel_by_year
    GROUP BY signup_year
),
expected AS (
    SELECT * FROM (VALUES
        (2023, 'Paid Social', 40.0), (2023, 'Paid Search', 25.0), (2023, 'Organic/SEO', 10.0),
        (2023, 'Email/SMS', 5.0), (2023, 'Affiliate/Referral', 5.0), (2023, 'Direct', 15.0),
        (2024, 'Paid Social', 32.0), (2024, 'Paid Search', 22.0), (2024, 'Organic/SEO', 18.0),
        (2024, 'Email/SMS', 10.0), (2024, 'Affiliate/Referral', 7.0), (2024, 'Direct', 11.0),
        (2025, 'Paid Social', 25.0), (2025, 'Paid Search', 20.0), (2025, 'Organic/SEO', 25.0),
        (2025, 'Email/SMS', 15.0), (2025, 'Affiliate/Referral', 8.0), (2025, 'Direct', 7.0)
    ) AS t(signup_year, channel_name, expected_pct)
)
SELECT
    e.signup_year, e.channel_name, e.expected_pct,
    ROUND(100.0 * COALESCE(cby.actual_count, 0) / yt.year_total, 1) AS actual_pct,
    CASE WHEN ABS(100.0 * COALESCE(cby.actual_count, 0) / yt.year_total - e.expected_pct) <= 5.0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected e
JOIN year_totals yt ON yt.signup_year = e.signup_year
LEFT JOIN channel_by_year cby ON cby.signup_year = e.signup_year AND cby.channel_name = e.channel_name
ORDER BY e.signup_year, e.channel_name;

-- 9. Geography region mix, within +/-5 percentage points of the
--    documented target (same tolerance-based reasoning as #8)
WITH region_counts AS (
    SELECT g.region, COUNT(*) AS actual_count
    FROM Dim_Customer c
    JOIN Dim_Geography g ON c.home_geography_key = g.geography_key
    GROUP BY g.region
),
total AS (
    SELECT SUM(actual_count) AS grand_total FROM region_counts
),
expected AS (
    SELECT * FROM (VALUES
        ('South', 38.0), ('West', 24.0), ('Midwest', 21.0), ('Northeast', 17.0)
    ) AS t(region, expected_pct)
)
SELECT
    e.region, e.expected_pct,
    ROUND(100.0 * COALESCE(rc.actual_count, 0) / t.grand_total, 1) AS actual_pct,
    CASE WHEN ABS(100.0 * COALESCE(rc.actual_count, 0) / t.grand_total - e.expected_pct) <= 5.0
         THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected e
CROSS JOIN total t
LEFT JOIN region_counts rc ON rc.region = e.region
ORDER BY e.region;

-- 10. FK-readiness: customer_key must be dense, contiguous, and start at
--     1 -- this is what Fact_Orders.customer_key, Fact_Order_Lines.
--     customer_key, Fact_Returns.customer_key, and Fact_Customer_Monthly_
--     Snapshot.customer_key will all reference once those tables are built
SELECT MIN(customer_key) AS min_key, MAX(customer_key) AS max_key,
       COUNT(*) AS row_count,
       CASE WHEN MIN(customer_key) = 1
             AND MAX(customer_key) = COUNT(*)
             AND COUNT(DISTINCT customer_key) = COUNT(*)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Dim_Customer;
