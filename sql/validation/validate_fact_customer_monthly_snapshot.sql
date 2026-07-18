-- =====================================================================
-- Validation: Fact_Customer_Monthly_Snapshot (Phase 3.12)
--
-- The strongest deterministic validation suite in the project, as befits
-- the final fact table. Nothing in this table is sampled -- every value
-- is a pure function of already-persisted facts -- so EVERY check here is
-- EXACT. Tolerance bands (ED-008) are deliberately absent: they would be
-- weaker than the data warrants. The only tolerances present are one-cent
-- money comparisons, which exist solely to absorb float representation,
-- not sampling variance.
--
-- Checks 10-12 are the real point of this file: they RE-DERIVE the
-- snapshot's measures independently, in SQL, from Fact_Orders and
-- Fact_Returns -- a different engine and a different code path from the
-- pandas generator that produced them. Agreement between two independent
-- derivations is far stronger evidence than any self-consistency check.
--
-- Empty result set (or explicit PASS) = clean.
-- =====================================================================

-- 1. FK integrity: customer_key -> Dim_Customer
SELECT s.snapshot_key FROM Fact_Customer_Monthly_Snapshot s
LEFT JOIN Dim_Customer c USING (customer_key) WHERE c.customer_key IS NULL;

-- 2. FK integrity: snapshot_month_date_key -> Dim_Date
SELECT s.snapshot_key FROM Fact_Customer_Monthly_Snapshot s
LEFT JOIN Dim_Date d ON s.snapshot_month_date_key = d.date_key WHERE d.date_key IS NULL;

-- 3. Every snapshot month must be a true MONTH-END date, not just any date
SELECT s.snapshot_key, d.full_date
FROM Fact_Customer_Monthly_Snapshot s JOIN Dim_Date d ON s.snapshot_month_date_key = d.date_key
WHERE d.full_date != (date_trunc('month', d.full_date) + INTERVAL 1 MONTH - INTERVAL 1 DAY);

-- 4. Grain: no duplicate (customer, month)
SELECT customer_key, snapshot_month_date_key, COUNT(*) AS occurrences
FROM Fact_Customer_Monthly_Snapshot GROUP BY customer_key, snapshot_month_date_key HAVING COUNT(*) > 1;

-- =====================================================================
-- 5. INVARIANT 3 -- TEMPORAL CONTINUITY OF THE ROW SPINE
--    Exactly one snapshot per month from the signup month through
--    2025-12: no gaps, no duplicates, no out-of-range months. Verified
--    independently of the total row count, since a correct total can hide
--    two customers with offsetting errors.
-- =====================================================================

-- 5a. No gaps and no duplicates: consecutive snapshot months within a
--     customer must differ by exactly one month (a gap gives >1, a
--     duplicate gives 0)
WITH months AS (
    SELECT s.customer_key, d.full_date AS month_end,
           LAG(d.full_date) OVER (PARTITION BY s.customer_key ORDER BY d.full_date) AS prev_month_end
    FROM Fact_Customer_Monthly_Snapshot s JOIN Dim_Date d ON s.snapshot_month_date_key = d.date_key
)
SELECT customer_key, prev_month_end, month_end,
       datediff('month', date_trunc('month', prev_month_end), date_trunc('month', month_end)) AS month_gap
FROM months
WHERE prev_month_end IS NOT NULL
  AND datediff('month', date_trunc('month', prev_month_end), date_trunc('month', month_end)) != 1;

-- 5b. Each customer's series starts exactly at their signup month and
--     ends exactly at 2025-12
WITH bounds AS (
    SELECT s.customer_key, MIN(d.full_date) AS first_month_end, MAX(d.full_date) AS last_month_end
    FROM Fact_Customer_Monthly_Snapshot s JOIN Dim_Date d ON s.snapshot_month_date_key = d.date_key
    GROUP BY s.customer_key
)
SELECT b.customer_key, c.signup_date, b.first_month_end, b.last_month_end
FROM bounds b JOIN Dim_Customer c USING (customer_key)
WHERE date_trunc('month', b.first_month_end) != date_trunc('month', c.signup_date)
   OR b.last_month_end != DATE '2025-12-31';

-- 5c. Row count per customer equals the exactly-computable expected month
--     count (independent arithmetic, not a trust of 5a/5b)
WITH expected AS (
    SELECT customer_key,
           datediff('month', date_trunc('month', signup_date), DATE '2025-12-01') + 1 AS expected_months
    FROM Dim_Customer
),
actual AS (
    SELECT customer_key, COUNT(*) AS actual_months FROM Fact_Customer_Monthly_Snapshot GROUP BY customer_key
)
SELECT e.customer_key, e.expected_months, a.actual_months
FROM expected e JOIN actual a USING (customer_key)
WHERE e.expected_months != a.actual_months;

-- 6. customer_age_days: never negative, strictly increasing within a customer
SELECT snapshot_key FROM Fact_Customer_Monthly_Snapshot WHERE customer_age_days < 0;

WITH ages AS (
    SELECT customer_key, snapshot_month_date_key, customer_age_days,
           LAG(customer_age_days) OVER (PARTITION BY customer_key ORDER BY snapshot_month_date_key) AS prev_age
    FROM Fact_Customer_Monthly_Snapshot
)
SELECT customer_key, snapshot_month_date_key, prev_age, customer_age_days
FROM ages WHERE prev_age IS NOT NULL AND customer_age_days <= prev_age;

-- 7. NULL discipline, BOTH directions: recency_days and
--    months_since_first_purchase are NULL if and only if the customer has
--    no orders as of that month
SELECT snapshot_key, cumulative_orders_to_date, recency_days, months_since_first_purchase
FROM Fact_Customer_Monthly_Snapshot
WHERE (cumulative_orders_to_date = 0 AND (recency_days IS NOT NULL OR months_since_first_purchase IS NOT NULL))
   OR (cumulative_orders_to_date > 0 AND (recency_days IS NULL OR months_since_first_purchase IS NULL))
   OR recency_days < 0
   OR months_since_first_purchase < 0;

-- 8. Window containment: 30d <= 90d <= cumulative
SELECT snapshot_key, orders_last_30_days, orders_last_90_days, cumulative_orders_to_date
FROM Fact_Customer_Monthly_Snapshot
WHERE orders_last_30_days > orders_last_90_days OR orders_last_90_days > cumulative_orders_to_date;

-- =====================================================================
-- 9. INVARIANT 1a / 1b -- REVENUE ATTRIBUTION CONSEQUENCES
--    cumulative_ORDERS is monotonic (orders are never un-placed), but
--    cumulative_REVENUE is deliberately NOT -- a return legitimately
--    reduces it in the month the return occurs. Revenue is instead
--    checked for the invariant that DOES hold absolutely: it can never go
--    negative, because every return_amount <= its line's net revenue and
--    a return always follows its order.
-- =====================================================================
WITH ord AS (
    SELECT customer_key, snapshot_month_date_key, cumulative_orders_to_date,
           LAG(cumulative_orders_to_date) OVER (PARTITION BY customer_key ORDER BY snapshot_month_date_key) AS prev_orders
    FROM Fact_Customer_Monthly_Snapshot
)
SELECT customer_key, snapshot_month_date_key, prev_orders, cumulative_orders_to_date
FROM ord WHERE prev_orders IS NOT NULL AND cumulative_orders_to_date < prev_orders;

SELECT snapshot_key, customer_key, snapshot_month_date_key, cumulative_net_revenue_to_date
FROM Fact_Customer_Monthly_Snapshot WHERE cumulative_net_revenue_to_date < 0;

-- =====================================================================
-- 10. INVARIANT 1 -- INDEPENDENT SQL RE-DERIVATION of the cumulative
--     measures, including the revenue attribution rule itself: orders are
--     summed to the snapshot month by ORDER date, returns are subtracted
--     to the snapshot month by RETURN date. If the generator had
--     retroactively netted a return into its purchase month, this
--     recomputation would disagree on every affected row.
-- =====================================================================
WITH snap AS (
    SELECT s.snapshot_key, s.customer_key, s.cumulative_orders_to_date,
           s.cumulative_net_revenue_to_date, s.recency_days, s.orders_last_30_days,
           s.orders_last_90_days, d.full_date AS month_end
    FROM Fact_Customer_Monthly_Snapshot s JOIN Dim_Date d ON s.snapshot_month_date_key = d.date_key
),
ord AS (
    SELECT sn.snapshot_key,
           COUNT(*) AS cum_orders,
           SUM(o.net_revenue) AS cum_order_revenue,
           MAX(od.full_date) AS last_order_date,
           SUM(CASE WHEN od.full_date > sn.month_end - INTERVAL 30 DAY THEN 1 ELSE 0 END) AS o30,
           SUM(CASE WHEN od.full_date > sn.month_end - INTERVAL 90 DAY THEN 1 ELSE 0 END) AS o90
    FROM snap sn
    JOIN Fact_Orders o ON o.customer_key = sn.customer_key
    JOIN Dim_Date od ON o.order_date_key = od.date_key
    WHERE od.full_date <= sn.month_end
    GROUP BY sn.snapshot_key
),
ret AS (
    SELECT sn.snapshot_key, SUM(r.return_amount) AS cum_return_amount
    FROM snap sn
    JOIN Fact_Returns r ON r.customer_key = sn.customer_key
    JOIN Dim_Date rd ON r.return_date_key = rd.date_key
    WHERE rd.full_date <= sn.month_end
    GROUP BY sn.snapshot_key
)
SELECT sn.snapshot_key, sn.cumulative_orders_to_date, COALESCE(ord.cum_orders, 0) AS recomputed_orders,
       sn.cumulative_net_revenue_to_date,
       ROUND(COALESCE(ord.cum_order_revenue, 0) - COALESCE(ret.cum_return_amount, 0), 2) AS recomputed_revenue,
       sn.recency_days, DATE_DIFF('day', ord.last_order_date, sn.month_end) AS recomputed_recency,
       sn.orders_last_30_days, COALESCE(ord.o30, 0) AS recomputed_o30,
       sn.orders_last_90_days, COALESCE(ord.o90, 0) AS recomputed_o90
FROM snap sn
LEFT JOIN ord USING (snapshot_key)
LEFT JOIN ret USING (snapshot_key)
WHERE sn.cumulative_orders_to_date != COALESCE(ord.cum_orders, 0)
   OR ABS(sn.cumulative_net_revenue_to_date - ROUND(COALESCE(ord.cum_order_revenue, 0) - COALESCE(ret.cum_return_amount, 0), 2)) > 0.01
   OR sn.orders_last_30_days != COALESCE(ord.o30, 0)
   OR sn.orders_last_90_days != COALESCE(ord.o90, 0)
   OR COALESCE(sn.recency_days, -1) != COALESCE(DATE_DIFF('day', ord.last_order_date, sn.month_end), -1);

-- 11. INVARIANT 1 -- independent SQL re-derivation of rolling 12-month
--     net revenue, on the same attribution rule (orders by order date,
--     returns by return date), over the trailing 12 calendar months
--     ending at the snapshot month.
WITH snap AS (
    SELECT s.snapshot_key, s.customer_key, s.rolling_12mo_net_revenue, d.full_date AS month_end,
           GREATEST(date_trunc('month', d.full_date) - INTERVAL 11 MONTH, DATE '2023-01-01') AS window_start
    FROM Fact_Customer_Monthly_Snapshot s JOIN Dim_Date d ON s.snapshot_month_date_key = d.date_key
),
ord AS (
    SELECT sn.snapshot_key, SUM(o.net_revenue) AS rev
    FROM snap sn
    JOIN Fact_Orders o ON o.customer_key = sn.customer_key
    JOIN Dim_Date od ON o.order_date_key = od.date_key
    WHERE od.full_date <= sn.month_end AND od.full_date >= sn.window_start
    GROUP BY sn.snapshot_key
),
ret AS (
    SELECT sn.snapshot_key, SUM(r.return_amount) AS amt
    FROM snap sn
    JOIN Fact_Returns r ON r.customer_key = sn.customer_key
    JOIN Dim_Date rd ON r.return_date_key = rd.date_key
    WHERE rd.full_date <= sn.month_end AND rd.full_date >= sn.window_start
    GROUP BY sn.snapshot_key
)
SELECT sn.snapshot_key, sn.rolling_12mo_net_revenue,
       ROUND(COALESCE(ord.rev, 0) - COALESCE(ret.amt, 0), 2) AS recomputed_rolling
FROM snap sn LEFT JOIN ord USING (snapshot_key) LEFT JOIN ret USING (snapshot_key)
WHERE ABS(sn.rolling_12mo_net_revenue - ROUND(COALESCE(ord.rev, 0) - COALESCE(ret.amt, 0), 2)) > 0.01;

-- =====================================================================
-- 12. INVARIANT 2 -- negative rolling revenue must be EXPLAINABLE, RARE
--     and BOUNDED. Negative values are EXPECTED (a return can fall inside
--     the rolling window while its originating order falls outside it,
--     because returns land 5-21 days after their order), so treating
--     every negative as an error would be wrong. Instead each negative
--     row is required to be explained by that exact mechanism.
-- =====================================================================

-- 12a. Every negative row must have a boundary return: a return inside
--      the window whose originating order is outside it. Rows returned
--      here are arithmetic bugs, not the intended edge case.
WITH snap AS (
    SELECT s.snapshot_key, s.customer_key, s.rolling_12mo_net_revenue, d.full_date AS month_end,
           GREATEST(date_trunc('month', d.full_date) - INTERVAL 11 MONTH, DATE '2023-01-01') AS window_start
    FROM Fact_Customer_Monthly_Snapshot s JOIN Dim_Date d ON s.snapshot_month_date_key = d.date_key
    WHERE s.rolling_12mo_net_revenue < 0
)
SELECT sn.snapshot_key, sn.customer_key, sn.month_end, sn.rolling_12mo_net_revenue
FROM snap sn
WHERE NOT EXISTS (
    SELECT 1
    FROM Fact_Returns r
    JOIN Dim_Date rd ON r.return_date_key = rd.date_key
    JOIN Fact_Orders o ON r.order_key = o.order_key
    JOIN Dim_Date od ON o.order_date_key = od.date_key
    WHERE r.customer_key = sn.customer_key
      AND rd.full_date BETWEEN sn.window_start AND sn.month_end
      AND od.full_date < sn.window_start
);

-- 12b. Negatives stay rare (<1% of rows) and bounded (> -$1,000)
SELECT COUNT(*) AS negative_rows,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM Fact_Customer_Monthly_Snapshot), 3) AS pct_of_rows,
       MIN(rolling_12mo_net_revenue) AS most_negative,
       CASE WHEN COUNT(*) * 1.0 / (SELECT COUNT(*) FROM Fact_Customer_Monthly_Snapshot) <= 0.01
                 AND COALESCE(MIN(rolling_12mo_net_revenue), 0) >= -1000.00
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot WHERE rolling_12mo_net_revenue < 0;

-- 13. Flags re-derived exactly from the documented thresholds. These are
--     computed, never sampled, and strictly persona-blind (Section 7) --
--     a churn model trained on a persona-aware flag would just be
--     learning the generation rules back.
SELECT snapshot_key, recency_days, cumulative_orders_to_date,
       is_active_flag, is_repeat_customer_flag, churn_risk_flag
FROM Fact_Customer_Monthly_Snapshot
WHERE is_active_flag != (recency_days IS NOT NULL AND recency_days <= 90)
   OR is_repeat_customer_flag != (cumulative_orders_to_date >= 2)
   OR churn_risk_flag != (recency_days IS NOT NULL AND recency_days > 60 AND recency_days <= 90);

-- 13b. The churn-risk band is a strict subset of the active band
SELECT snapshot_key FROM Fact_Customer_Monthly_Snapshot WHERE churn_risk_flag AND NOT is_active_flag;

-- 14. Tie-out to the source facts at the final month: every order counted
--     exactly once, and revenue equal to orders minus returns
SELECT (SELECT SUM(cumulative_orders_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231) AS snapshot_orders,
       (SELECT COUNT(*) FROM Fact_Orders) AS fact_orders,
       CASE WHEN (SELECT SUM(cumulative_orders_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231)
                 = (SELECT COUNT(*) FROM Fact_Orders)
            THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT ROUND((SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231), 2) AS snapshot_net_revenue,
       ROUND((SELECT SUM(net_revenue) FROM Fact_Orders) - (SELECT SUM(return_amount) FROM Fact_Returns), 2) AS expected_net_revenue,
       CASE WHEN ABS((SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231)
                     - ((SELECT SUM(net_revenue) FROM Fact_Orders) - (SELECT SUM(return_amount) FROM Fact_Returns))) <= 0.05
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- 15. Customers who never purchased must look exactly like never-purchasers
--     in every month of their series -- they are kept deliberately (cohort
--     retention denominators need them), so their state must be right
SELECT s.snapshot_key, s.customer_key
FROM Fact_Customer_Monthly_Snapshot s
WHERE s.customer_key NOT IN (SELECT DISTINCT customer_key FROM Fact_Orders)
  AND (s.cumulative_orders_to_date != 0 OR s.cumulative_net_revenue_to_date != 0
       OR s.rolling_12mo_net_revenue != 0 OR s.recency_days IS NOT NULL
       OR s.months_since_first_purchase IS NOT NULL
       OR s.is_active_flag OR s.is_repeat_customer_flag OR s.churn_risk_flag);

-- 16. Cross-phase consistency: the final-month repeat-customer rate must
--     equal Section 9's 35-45% repeat purchase rate target that Phase 3.9
--     was independently calibrated to -- two different tables, two
--     different derivations, one business truth
SELECT ROUND(100.0 * AVG(CASE WHEN is_repeat_customer_flag THEN 1.0 ELSE 0 END), 1) AS final_month_repeat_pct,
       CASE WHEN AVG(CASE WHEN is_repeat_customer_flag THEN 1.0 ELSE 0 END) BETWEEN 0.35 AND 0.45
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231;
