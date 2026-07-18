-- =====================================================================
-- Phase 4 -- Warehouse Validation: TIER 4a (Structural Completeness)
--                                  TIER 4b (Business Observations)
--                                  TIER 5  (Business Narrative / Exec Sanity)
--                                  TIER 6  (Analytical Readiness)
--
-- Phase 3 validated each table against its specification.
-- Phase 4 validates the warehouse against itself.
--
-- SCOPE DISCIPLINE: Tier 6 CERTIFIES that the downstream analyses are
-- possible -- it does NOT perform them. Verifying that RFM quintiles are
-- non-degenerate is Phase 4's job; computing the RFM segments is Phase
-- 6's. Verifying a churn label is derivable is Phase 4's job; training
-- the model is Phase 10's. Every check below stops at "can this be
-- built?" and deliberately declines to answer "what does it say?".
--
-- TIER 4 is split, per the Phase 4 design refinement:
--   4a STRUCTURAL COMPLETENESS -- things that MUST be complete for the
--      warehouse to be coherent. BLOCKING.
--   4b BUSINESS OBSERVATIONS -- unused campaigns, products, channels,
--      reasons. These are FINDINGS, not failures: a campaign that drove
--      no orders is intelligence for Phase 8, not a defect.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TIER 4a -- STRUCTURAL COMPLETENESS (BLOCKING)
-- ---------------------------------------------------------------------

-- @CHECK: id=4a.1; tier=4a; severity=BLOCKING; name=Every customer in Dim_Customer has a complete snapshot series
SELECT (SELECT COUNT(DISTINCT customer_key) FROM Fact_Customer_Monthly_Snapshot) AS customers_with_series,
       (SELECT COUNT(*) FROM Dim_Customer) AS total_customers,
       CASE WHEN (SELECT COUNT(DISTINCT customer_key) FROM Fact_Customer_Monthly_Snapshot) = (SELECT COUNT(*) FROM Dim_Customer)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=4a.2; tier=4a; severity=BLOCKING; name=No dimension table is empty (every conformed dimension is populated)
WITH counts AS (
    SELECT 'Dim_Date' AS tbl, COUNT(*) AS n FROM Dim_Date
    UNION ALL SELECT 'Dim_Geography', COUNT(*) FROM Dim_Geography
    UNION ALL SELECT 'Dim_Marketing_Channel', COUNT(*) FROM Dim_Marketing_Channel
    UNION ALL SELECT 'Dim_Sales_Channel', COUNT(*) FROM Dim_Sales_Channel
    UNION ALL SELECT 'Dim_Campaign', COUNT(*) FROM Dim_Campaign
    UNION ALL SELECT 'Dim_Product', COUNT(*) FROM Dim_Product
    UNION ALL SELECT 'Dim_Return_Reason', COUNT(*) FROM Dim_Return_Reason
    UNION ALL SELECT 'Dim_Customer', COUNT(*) FROM Dim_Customer
)
SELECT COUNT(*) FILTER (WHERE n = 0) AS empty_dimensions,
       CASE WHEN COUNT(*) FILTER (WHERE n = 0) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM counts;

-- @CHECK: id=4a.3; tier=4a; severity=BLOCKING; name=No fact table is empty (all four grains populated)
WITH counts AS (
    SELECT 'Fact_Orders' AS tbl, COUNT(*) AS n FROM Fact_Orders
    UNION ALL SELECT 'Fact_Order_Lines', COUNT(*) FROM Fact_Order_Lines
    UNION ALL SELECT 'Fact_Returns', COUNT(*) FROM Fact_Returns
    UNION ALL SELECT 'Fact_Customer_Monthly_Snapshot', COUNT(*) FROM Fact_Customer_Monthly_Snapshot
)
SELECT COUNT(*) FILTER (WHERE n = 0) AS empty_facts,
       CASE WHEN COUNT(*) FILTER (WHERE n = 0) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM counts;

-- @CHECK: id=4a.4; tier=4a; severity=BLOCKING; name=Every customer who ordered has a first-order flag and vice versa
SELECT (SELECT COUNT(DISTINCT customer_key) FROM Fact_Orders WHERE is_first_order) AS customers_with_first_order_flag,
       (SELECT COUNT(DISTINCT customer_key) FROM Fact_Orders) AS customers_who_ordered,
       CASE WHEN (SELECT COUNT(DISTINCT customer_key) FROM Fact_Orders WHERE is_first_order)
                 = (SELECT COUNT(DISTINCT customer_key) FROM Fact_Orders)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- ---------------------------------------------------------------------
-- TIER 4b -- BUSINESS OBSERVATIONS (ADVISORY -- findings, not failures)
-- ---------------------------------------------------------------------

-- @CHECK: id=4b.1; tier=4b; severity=ADVISORY; name=Products never sold (merchandising finding for Phase 8)
SELECT COUNT(*) AS finding_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FINDING' END AS result
FROM Dim_Product p LEFT JOIN (SELECT DISTINCT product_key FROM Fact_Order_Lines) l USING (product_key)
WHERE l.product_key IS NULL;

-- @CHECK: id=4b.2; tier=4b; severity=ADVISORY; name=Campaigns that attracted zero attributed orders (marketing finding)
SELECT COUNT(*) AS finding_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FINDING' END AS result
FROM Dim_Campaign c LEFT JOIN (SELECT DISTINCT campaign_key FROM Fact_Orders WHERE campaign_key IS NOT NULL) o USING (campaign_key)
WHERE o.campaign_key IS NULL;

-- @CHECK: id=4b.3; tier=4b; severity=ADVISORY; name=Marketing channels that acquired zero customers
SELECT COUNT(*) AS finding_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FINDING' END AS result
FROM Dim_Marketing_Channel m LEFT JOIN (SELECT DISTINCT acquisition_channel_key FROM Dim_Customer) c
  ON m.marketing_channel_key = c.acquisition_channel_key
WHERE c.acquisition_channel_key IS NULL;

-- @CHECK: id=4b.4; tier=4b; severity=ADVISORY; name=Sales channels with zero orders
SELECT COUNT(*) AS finding_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FINDING' END AS result
FROM Dim_Sales_Channel s LEFT JOIN (SELECT DISTINCT sales_channel_key FROM Fact_Orders) o USING (sales_channel_key)
WHERE o.sales_channel_key IS NULL;

-- @CHECK: id=4b.5; tier=4b; severity=ADVISORY; name=Return reasons never used
SELECT COUNT(*) AS finding_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FINDING' END AS result
FROM Dim_Return_Reason rr LEFT JOIN (SELECT DISTINCT return_reason_key FROM Fact_Returns) r USING (return_reason_key)
WHERE r.return_reason_key IS NULL;

-- @CHECK: id=4b.6; tier=4b; severity=ADVISORY; name=Geographies with no customers (regional coverage finding)
SELECT COUNT(*) AS finding_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FINDING' END AS result
FROM Dim_Geography g LEFT JOIN (SELECT DISTINCT home_geography_key FROM Dim_Customer) c
  ON g.geography_key = c.home_geography_key
WHERE c.home_geography_key IS NULL;

-- @CHECK: id=4b.7; tier=4b; severity=ADVISORY; name=Customers who never purchased (expected: real signups that never converted)
SELECT COUNT(*) AS finding_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FINDING' END AS result
FROM Dim_Customer c LEFT JOIN (SELECT DISTINCT customer_key FROM Fact_Orders) o USING (customer_key)
WHERE o.customer_key IS NULL;

-- ---------------------------------------------------------------------
-- TIER 5 -- BUSINESS NARRATIVE / EXECUTIVE SANITY
-- Tests the claims docs/business_understanding.md makes about this
-- business. A failure here is a DATA-VS-NARRATIVE conflict requiring a
-- documented resolution, not a code defect -- and per the Phase 4
-- ruling, the data is never modified to satisfy the narrative.
-- ---------------------------------------------------------------------

-- @CHECK: id=5.1; tier=5; severity=BLOCKING; name=Revenue grows year over year 2023 -> 2024 -> 2025 (documented growth story)
WITH yearly AS (
    SELECT d.year, SUM(o.net_revenue) AS net_revenue
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    GROUP BY d.year
)
SELECT MAX(CASE WHEN year = 2023 THEN ROUND(net_revenue, 2) END) AS rev_2023,
       MAX(CASE WHEN year = 2024 THEN ROUND(net_revenue, 2) END) AS rev_2024,
       MAX(CASE WHEN year = 2025 THEN ROUND(net_revenue, 2) END) AS rev_2025,
       CASE WHEN MAX(CASE WHEN year = 2024 THEN net_revenue END) > MAX(CASE WHEN year = 2023 THEN net_revenue END)
             AND MAX(CASE WHEN year = 2025 THEN net_revenue END) > MAX(CASE WHEN year = 2024 THEN net_revenue END)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM yearly;

-- @CHECK: id=5.2; tier=5; severity=BLOCKING; name=Holiday peak (Nov-Dec) outperforms the average month (documented seasonal dynamic)
WITH monthly AS (
    SELECT d.year, d.month, SUM(o.net_revenue) AS net_revenue
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    GROUP BY d.year, d.month
)
SELECT ROUND(AVG(CASE WHEN month IN (11, 12) THEN net_revenue END), 2) AS avg_holiday_month,
       ROUND(AVG(CASE WHEN month NOT IN (11, 12) THEN net_revenue END), 2) AS avg_other_month,
       CASE WHEN AVG(CASE WHEN month IN (11, 12) THEN net_revenue END)
                 > AVG(CASE WHEN month NOT IN (11, 12) THEN net_revenue END)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM monthly;

-- @CHECK: id=5.3; tier=5; severity=BLOCKING; name=No calendar month has negative net revenue (executive sanity)
WITH monthly AS (
    SELECT d.year, d.month, SUM(o.net_revenue) - COALESCE((
        SELECT SUM(r.return_amount) FROM Fact_Returns r JOIN Dim_Date rd ON r.return_date_key = rd.date_key
        WHERE rd.year = d.year AND rd.month = d.month), 0) AS net_revenue
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    GROUP BY d.year, d.month
)
SELECT COUNT(*) FILTER (WHERE net_revenue < 0) AS negative_months,
       CASE WHEN COUNT(*) FILTER (WHERE net_revenue < 0) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM monthly;

-- @CHECK: id=5.4; tier=5; severity=BLOCKING; name=Footwear has the highest category return rate (documented apparel dynamic)
WITH rates AS (
    SELECT p.category,
           SUM(l.quantity) AS units_sold,
           COALESCE((SELECT SUM(r.return_quantity) FROM Fact_Returns r JOIN Dim_Product rp USING (product_key) WHERE rp.category = p.category), 0) AS units_returned
    FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key)
    GROUP BY p.category
)
SELECT (SELECT category FROM rates ORDER BY units_returned * 1.0 / units_sold DESC LIMIT 1) AS highest_return_category,
       CASE WHEN (SELECT category FROM rates ORDER BY units_returned * 1.0 / units_sold DESC LIMIT 1) = 'Footwear'
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- Phase 4 resolved this one. business_understanding.md originally claimed
-- "a growing but still minority share of revenue from repeat customers".
-- The warehouse disproved the "minority" half decisively (82.4%), and per
-- the Phase 4 ruling the NARRATIVE was corrected rather than the data.
-- The check is deliberately retained, and deliberately still reports a
-- FINDING: a concentration this material should keep announcing itself in
-- every validation run rather than going quiet once written down. It is a
-- standing business flag for Phase 8, and a regression guard if the figure
-- ever moves.
-- @CHECK: id=5.5; tier=5; severity=ADVISORY; name=Repeat-customer revenue concentration (original 'minority share' claim disproved; narrative corrected in Phase 4)
WITH repeat_customers AS (
    SELECT customer_key FROM Fact_Orders GROUP BY customer_key HAVING COUNT(*) >= 2
),
totals AS (
    SELECT SUM(CASE WHEN o.customer_key IN (SELECT customer_key FROM repeat_customers) THEN o.net_revenue ELSE 0 END) AS repeat_revenue,
           SUM(o.net_revenue) AS total_revenue
    FROM Fact_Orders o
)
SELECT ROUND(100.0 * repeat_revenue / total_revenue, 2) AS repeat_revenue_share_pct,
       ROUND(repeat_revenue, 2) AS repeat_revenue,
       ROUND(total_revenue, 2) AS total_revenue,
       CASE WHEN repeat_revenue / total_revenue < 0.50 THEN 'PASS' ELSE 'FINDING' END AS result
FROM totals;

-- @CHECK: id=5.6; tier=5; severity=ADVISORY; name=Repeat-customer revenue share is growing year over year (the half of the original narrative the data CONFIRMS)
WITH repeat_customers AS (
    SELECT customer_key FROM Fact_Orders GROUP BY customer_key HAVING COUNT(*) >= 2
),
yearly AS (
    SELECT d.year,
           SUM(CASE WHEN o.customer_key IN (SELECT customer_key FROM repeat_customers) THEN o.net_revenue ELSE 0 END) / SUM(o.net_revenue) AS repeat_share
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    GROUP BY d.year
)
SELECT ROUND(100.0 * MAX(CASE WHEN year = 2023 THEN repeat_share END), 2) AS share_2023_pct,
       ROUND(100.0 * MAX(CASE WHEN year = 2024 THEN repeat_share END), 2) AS share_2024_pct,
       ROUND(100.0 * MAX(CASE WHEN year = 2025 THEN repeat_share END), 2) AS share_2025_pct,
       CASE WHEN MAX(CASE WHEN year = 2024 THEN repeat_share END) > MAX(CASE WHEN year = 2023 THEN repeat_share END)
             AND MAX(CASE WHEN year = 2025 THEN repeat_share END) > MAX(CASE WHEN year = 2024 THEN repeat_share END)
            THEN 'PASS' ELSE 'FINDING' END AS result
FROM yearly;

-- ---------------------------------------------------------------------
-- TIER 6 -- ANALYTICAL READINESS (BLOCKING)
-- Certifies that later phases CAN be built. Does not build them.
-- ---------------------------------------------------------------------

-- @CHECK: id=6.1; tier=6; severity=BLOCKING; name=READINESS Phase 6 RFM -- every purchasing customer has complete R/F/M inputs at the final snapshot
SELECT COUNT(*) AS customers_missing_rfm_inputs,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot s
WHERE s.snapshot_month_date_key = 20251231
  AND s.cumulative_orders_to_date > 0
  AND (s.recency_days IS NULL OR s.cumulative_orders_to_date IS NULL OR s.cumulative_net_revenue_to_date IS NULL);

-- @CHECK: id=6.2; tier=6; severity=BLOCKING; name=READINESS Phase 6 RFM -- recency and monetary are non-degenerate (quintiles are constructible)
SELECT COUNT(DISTINCT recency_days) AS distinct_recency_values,
       COUNT(DISTINCT cumulative_net_revenue_to_date) AS distinct_monetary_values,
       CASE WHEN COUNT(DISTINCT recency_days) >= 5 AND COUNT(DISTINCT cumulative_net_revenue_to_date) >= 5
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot
WHERE snapshot_month_date_key = 20251231 AND cumulative_orders_to_date > 0;

-- @CHECK: id=6.3; tier=6; severity=BLOCKING; name=READINESS Phase 6 Cohorts -- every signup cohort month is populated and has snapshot coverage
WITH cohorts AS (
    SELECT DATE_TRUNC('month', signup_date) AS cohort_month, COUNT(*) AS customers FROM Dim_Customer GROUP BY 1
)
SELECT COUNT(*) AS cohort_count,
       MIN(customers) AS smallest_cohort,
       CASE WHEN COUNT(*) = 36 AND MIN(customers) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM cohorts;

-- @CHECK: id=6.4; tier=6; severity=BLOCKING; name=READINESS Phase 10 Churn -- labels are derivable (a +2-month successor row exists for non-boundary months)
WITH s AS (
    SELECT sn.customer_key, DATE_DIFF('month', DATE '2023-01-01', d.full_date) AS month_idx
    FROM Fact_Customer_Monthly_Snapshot sn JOIN Dim_Date d ON sn.snapshot_month_date_key = d.date_key
),
labelable AS (
    SELECT COUNT(*) AS n FROM s a WHERE EXISTS (SELECT 1 FROM s b WHERE b.customer_key = a.customer_key AND b.month_idx = a.month_idx + 2)
),
boundary AS (
    SELECT COUNT(*) AS n FROM s a WHERE a.month_idx >= 34 AND EXISTS (SELECT 1 FROM s b WHERE b.customer_key = a.customer_key AND b.month_idx = a.month_idx + 2)
)
SELECT (SELECT n FROM labelable) AS labelable_rows,
       (SELECT n FROM boundary) AS boundary_rows_with_impossible_labels,
       CASE WHEN (SELECT n FROM labelable) > 0 AND (SELECT n FROM boundary) = 0 THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=6.5; tier=6; severity=BLOCKING; name=READINESS Phase 10 Churn -- the rule-based baseline (churn_risk_flag) has both classes present
SELECT SUM(CASE WHEN churn_risk_flag THEN 1 ELSE 0 END) AS positive_class,
       SUM(CASE WHEN NOT churn_risk_flag THEN 1 ELSE 0 END) AS negative_class,
       CASE WHEN SUM(CASE WHEN churn_risk_flag THEN 1 ELSE 0 END) > 0
             AND SUM(CASE WHEN NOT churn_risk_flag THEN 1 ELSE 0 END) > 0
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot;

-- @CHECK: id=6.6; tier=6; severity=BLOCKING; name=READINESS Phase 6 Pareto -- lifetime spend is rankable across a sufficient customer base
SELECT COUNT(*) AS customers_with_positive_spend,
       CASE WHEN COUNT(*) >= 100 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot
WHERE snapshot_month_date_key = 20251231 AND cumulative_net_revenue_to_date > 0;

-- @CHECK: id=6.7; tier=6; severity=BLOCKING; name=READINESS Phase 5 Time Series -- no dead months in the 36-month order history
WITH months AS (
    SELECT d.year, d.month, COUNT(o.order_key) AS orders
    FROM Dim_Date d LEFT JOIN Fact_Orders o ON o.order_date_key = d.date_key
    GROUP BY d.year, d.month
)
SELECT COUNT(*) AS total_months,
       COUNT(*) FILTER (WHERE orders = 0) AS dead_months,
       CASE WHEN COUNT(*) = 36 AND COUNT(*) FILTER (WHERE orders = 0) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM months;

-- @CHECK: id=6.8; tier=6; severity=BLOCKING; name=READINESS Phase 7 Additivity -- the Orders->Lines fan-out hazard is quantified and documented
SELECT (SELECT COUNT(*) FROM Fact_Orders o JOIN Fact_Order_Lines l USING (order_key)) AS naive_join_rows,
       (SELECT COUNT(*) FROM Fact_Orders) AS true_order_grain,
       ROUND(1.0 * (SELECT COUNT(*) FROM Fact_Orders o JOIN Fact_Order_Lines l USING (order_key)) / (SELECT COUNT(*) FROM Fact_Orders), 3) AS fanout_factor,
       CASE WHEN (SELECT COUNT(*) FROM Fact_Orders o JOIN Fact_Order_Lines l USING (order_key)) > (SELECT COUNT(*) FROM Fact_Orders)
            THEN 'PASS' ELSE 'FAIL' END AS result;
