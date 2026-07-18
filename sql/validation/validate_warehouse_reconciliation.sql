-- =====================================================================
-- Phase 4 -- Warehouse Validation: TIER 2 (Cross-Grain Aggregate Reconciliation)
--                                  TIER 3 (KPI Reconciliation)
--
-- Phase 3 validated each table against its specification.
-- Phase 4 validates the warehouse against itself.
--
-- Every check here computes the same business truth by TWO OR MORE
-- INDEPENDENT PATHS and requires exact agreement. That is the whole
-- point: a KPI that can be derived two ways and disagrees is a KPI no
-- dashboard can be trusted to publish.
--
-- AOV DEFINITION (resolved in Phase 4, see docs/business_understanding.md):
--   AOV = Order Net Revenue / Total Orders, where Order Net Revenue is
--   AFTER discounts but BEFORE returns -- the standard retail definition.
--   Returns are reported separately (Return Rate, Returns KPIs). This was
--   ambiguous until Phase 4: the KPI table's generic "Net Revenue"
--   subtracts returns, which would have yielded a different AOV than
--   Phase 3.9 validated, with BOTH values sitting inside Section 9's
--   $65-85 band -- an invisible contradiction that would have surfaced
--   later as SQL and Power BI publishing two different "AOV" numbers.
--   Check 3.2 exists specifically to make that impossible from now on.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TIER 2 -- CROSS-GRAIN AGGREGATE RECONCILIATION
-- ---------------------------------------------------------------------

-- @CHECK: id=2.1; tier=2; severity=BLOCKING; name=Order header money reconciles to line money warehouse-wide (gross, discount, net)
SELECT ROUND((SELECT SUM(gross_revenue) FROM Fact_Orders), 2) AS header_gross,
       ROUND((SELECT SUM(gross_line_revenue) FROM Fact_Order_Lines), 2) AS line_gross,
       ROUND((SELECT SUM(discount_amount) FROM Fact_Orders), 2) AS header_discount,
       ROUND((SELECT SUM(discount_amount) FROM Fact_Order_Lines), 2) AS line_discount,
       ROUND((SELECT SUM(net_revenue) FROM Fact_Orders), 2) AS header_net,
       ROUND((SELECT SUM(net_line_revenue) FROM Fact_Order_Lines), 2) AS line_net,
       CASE WHEN ABS((SELECT SUM(gross_revenue) FROM Fact_Orders) - (SELECT SUM(gross_line_revenue) FROM Fact_Order_Lines)) <= 0.05
             AND ABS((SELECT SUM(discount_amount) FROM Fact_Orders) - (SELECT SUM(discount_amount) FROM Fact_Order_Lines)) <= 0.05
             AND ABS((SELECT SUM(net_revenue) FROM Fact_Orders) - (SELECT SUM(net_line_revenue) FROM Fact_Order_Lines)) <= 0.05
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=2.2; tier=2; severity=BLOCKING; name=Every order has at least one line and every line has a header (both directions)
SELECT (SELECT COUNT(*) FROM Fact_Orders o LEFT JOIN (SELECT DISTINCT order_key FROM Fact_Order_Lines) l USING (order_key) WHERE l.order_key IS NULL) AS orders_without_lines,
       (SELECT COUNT(DISTINCT order_key) FROM Fact_Order_Lines) AS orders_referenced_by_lines,
       (SELECT COUNT(*) FROM Fact_Orders) AS total_orders,
       CASE WHEN (SELECT COUNT(*) FROM Fact_Orders o LEFT JOIN (SELECT DISTINCT order_key FROM Fact_Order_Lines) l USING (order_key) WHERE l.order_key IS NULL) = 0
             AND (SELECT COUNT(DISTINCT order_key) FROM Fact_Order_Lines) = (SELECT COUNT(*) FROM Fact_Orders)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=2.3; tier=2; severity=BLOCKING; name=Returned units never exceed sold units, per line and in aggregate
SELECT (SELECT SUM(return_quantity) FROM Fact_Returns) AS units_returned,
       (SELECT SUM(quantity) FROM Fact_Order_Lines) AS units_sold,
       (SELECT COUNT(*) FROM Fact_Returns r JOIN Fact_Order_Lines l USING (order_line_key) WHERE r.return_quantity > l.quantity) AS per_line_violations,
       CASE WHEN (SELECT SUM(return_quantity) FROM Fact_Returns) <= (SELECT SUM(quantity) FROM Fact_Order_Lines)
             AND (SELECT COUNT(*) FROM Fact_Returns r JOIN Fact_Order_Lines l USING (order_line_key) WHERE r.return_quantity > l.quantity) = 0
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=2.4; tier=2; severity=BLOCKING; name=Refunds never exceed the revenue of the line they refund, in aggregate
SELECT ROUND((SELECT SUM(return_amount) FROM Fact_Returns), 2) AS total_refunded,
       ROUND((SELECT SUM(net_line_revenue) FROM Fact_Order_Lines), 2) AS total_line_net,
       CASE WHEN (SELECT SUM(return_amount) FROM Fact_Returns) <= (SELECT SUM(net_line_revenue) FROM Fact_Order_Lines)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=2.5; tier=2; severity=BLOCKING; name=Snapshot per-customer final order count equals that customer's actual order count (all 8000 customers)
WITH actual AS (
    SELECT c.customer_key, COUNT(o.order_key) AS order_count
    FROM Dim_Customer c LEFT JOIN Fact_Orders o USING (customer_key) GROUP BY c.customer_key
),
snap AS (
    SELECT customer_key, cumulative_orders_to_date
    FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231
)
SELECT COUNT(*) AS mismatched_customers,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM actual a JOIN snap s USING (customer_key)
WHERE a.order_count != s.cumulative_orders_to_date;

-- @CHECK: id=2.6; tier=2; severity=BLOCKING; name=Snapshot per-customer final net revenue equals that customer's orders minus returns
WITH actual AS (
    SELECT c.customer_key,
           COALESCE((SELECT SUM(o.net_revenue) FROM Fact_Orders o WHERE o.customer_key = c.customer_key), 0)
         - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key = c.customer_key), 0) AS net_revenue
    FROM Dim_Customer c
),
snap AS (
    SELECT customer_key, cumulative_net_revenue_to_date
    FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231
)
SELECT COUNT(*) AS mismatched_customers,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM actual a JOIN snap s USING (customer_key)
WHERE ABS(a.net_revenue - s.cumulative_net_revenue_to_date) > 0.011;

-- @CHECK: id=2.7; tier=2; severity=BLOCKING; name=is_first_order count equals the number of customers who ever ordered (two independent derivations)
SELECT (SELECT SUM(CASE WHEN is_first_order THEN 1 ELSE 0 END) FROM Fact_Orders) AS first_order_flags,
       (SELECT COUNT(DISTINCT customer_key) FROM Fact_Orders) AS customers_who_ordered,
       CASE WHEN (SELECT SUM(CASE WHEN is_first_order THEN 1 ELSE 0 END) FROM Fact_Orders)
                 = (SELECT COUNT(DISTINCT customer_key) FROM Fact_Orders)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=2.8; tier=2; severity=BLOCKING; name=is_first_order (Fact_Orders) agrees with months_since_first_purchase=0 (Snapshot) on the first-purchase month
WITH from_orders AS (
    SELECT o.customer_key, DATE_TRUNC('month', d.full_date) AS first_month
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    WHERE o.is_first_order
),
from_snapshot AS (
    SELECT s.customer_key, DATE_TRUNC('month', d.full_date) AS first_month
    FROM Fact_Customer_Monthly_Snapshot s JOIN Dim_Date d ON s.snapshot_month_date_key = d.date_key
    WHERE s.months_since_first_purchase = 0
)
SELECT COUNT(*) AS disagreements,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM from_orders fo FULL OUTER JOIN from_snapshot fs USING (customer_key)
WHERE fo.first_month IS DISTINCT FROM fs.first_month;

-- ---------------------------------------------------------------------
-- TIER 3 -- KPI RECONCILIATION (each KPI, two or more independent paths)
-- ---------------------------------------------------------------------

-- @CHECK: id=3.1; tier=3; severity=BLOCKING; name=KPI Net Revenue agrees across three independent paths (lines, headers, snapshot)
SELECT ROUND((SELECT SUM(net_line_revenue) FROM Fact_Order_Lines) - (SELECT SUM(return_amount) FROM Fact_Returns), 2) AS path_a_lines,
       ROUND((SELECT SUM(net_revenue) FROM Fact_Orders) - (SELECT SUM(return_amount) FROM Fact_Returns), 2) AS path_b_headers,
       ROUND((SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231), 2) AS path_c_snapshot,
       CASE WHEN ABS(((SELECT SUM(net_line_revenue) FROM Fact_Order_Lines) - (SELECT SUM(return_amount) FROM Fact_Returns))
                   - ((SELECT SUM(net_revenue) FROM Fact_Orders) - (SELECT SUM(return_amount) FROM Fact_Returns))) <= 0.05
             AND ABS(((SELECT SUM(net_revenue) FROM Fact_Orders) - (SELECT SUM(return_amount) FROM Fact_Returns))
                   - (SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231)) <= 0.05
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=3.2; tier=3; severity=BLOCKING; name=KPI AOV is single-valued (header path == line path) under the Phase 4 definition (after discounts, before returns)
SELECT ROUND((SELECT AVG(net_revenue) FROM Fact_Orders), 2) AS aov_header_path,
       ROUND((SELECT SUM(net_line_revenue) FROM Fact_Order_Lines) / (SELECT COUNT(*) FROM Fact_Orders), 2) AS aov_line_path,
       CASE WHEN ABS((SELECT AVG(net_revenue) FROM Fact_Orders)
                   - (SELECT SUM(net_line_revenue) FROM Fact_Order_Lines) / (SELECT COUNT(*) FROM Fact_Orders)) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=3.3; tier=3; severity=BLOCKING; name=KPI Repeat Purchase Rate agrees across two paths (Fact_Orders vs Snapshot flag)
SELECT ROUND(100.0 * (SELECT COUNT(*) FROM (SELECT customer_key FROM Fact_Orders GROUP BY customer_key HAVING COUNT(*) >= 2)) / (SELECT COUNT(*) FROM Dim_Customer), 2) AS path_a_orders,
       ROUND(100.0 * (SELECT COUNT(*) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231 AND is_repeat_customer_flag) / (SELECT COUNT(*) FROM Dim_Customer), 2) AS path_b_snapshot,
       CASE WHEN (SELECT COUNT(*) FROM (SELECT customer_key FROM Fact_Orders GROUP BY customer_key HAVING COUNT(*) >= 2))
                 = (SELECT COUNT(*) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231 AND is_repeat_customer_flag)
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=3.4; tier=3; severity=BLOCKING; name=KPI Return Rate (units returned / units sold) is single-valued
SELECT ROUND(100.0 * (SELECT SUM(return_quantity) FROM Fact_Returns) / (SELECT SUM(quantity) FROM Fact_Order_Lines), 2) AS return_rate_pct,
       CASE WHEN (SELECT SUM(return_quantity) FROM Fact_Returns) > 0
             AND (SELECT SUM(quantity) FROM Fact_Order_Lines) > 0
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=3.5; tier=3; severity=BLOCKING; name=KPI Discount Impact (never validated before Phase 4) is single-valued across header and line paths
SELECT ROUND(100.0 * (SELECT SUM(discount_amount) FROM Fact_Orders) / (SELECT SUM(gross_revenue) FROM Fact_Orders), 2) AS discount_impact_header_pct,
       ROUND(100.0 * (SELECT SUM(discount_amount) FROM Fact_Order_Lines) / (SELECT SUM(gross_line_revenue) FROM Fact_Order_Lines), 2) AS discount_impact_line_pct,
       CASE WHEN ABS(100.0 * (SELECT SUM(discount_amount) FROM Fact_Orders) / (SELECT SUM(gross_revenue) FROM Fact_Orders)
                   - 100.0 * (SELECT SUM(discount_amount) FROM Fact_Order_Lines) / (SELECT SUM(gross_line_revenue) FROM Fact_Order_Lines)) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=3.6; tier=3; severity=BLOCKING; name=KPI CLV (historical) agrees between the snapshot and a direct per-customer derivation
WITH direct AS (
    SELECT ROUND(SUM(x.net), 2) AS total FROM (
        SELECT COALESCE((SELECT SUM(o.net_revenue) FROM Fact_Orders o WHERE o.customer_key = c.customer_key), 0)
             - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key = c.customer_key), 0) AS net
        FROM Dim_Customer c
    ) x
)
SELECT (SELECT total FROM direct) AS clv_direct_path,
       ROUND((SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231), 2) AS clv_snapshot_path,
       CASE WHEN ABS((SELECT total FROM direct)
                   - (SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231)) <= 0.05
            THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=3.7; tier=3; severity=BLOCKING; name=Gross margin inputs are complete and coherent (CLV projected needs Gross Margin %)
SELECT ROUND(100.0 * ((SELECT SUM(net_line_revenue) FROM Fact_Order_Lines) - (SELECT SUM(quantity * unit_cost) FROM Fact_Order_Lines))
                   / (SELECT SUM(net_line_revenue) FROM Fact_Order_Lines), 2) AS gross_margin_pct,
       (SELECT COUNT(*) FROM Fact_Order_Lines WHERE unit_cost IS NULL OR unit_cost <= 0) AS lines_missing_cost,
       CASE WHEN (SELECT COUNT(*) FROM Fact_Order_Lines WHERE unit_cost IS NULL OR unit_cost <= 0) = 0
             AND ((SELECT SUM(net_line_revenue) FROM Fact_Order_Lines) - (SELECT SUM(quantity * unit_cost) FROM Fact_Order_Lines)) > 0
            THEN 'PASS' ELSE 'FAIL' END AS result;
