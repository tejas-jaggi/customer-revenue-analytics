-- =====================================================================
-- Phase 4 -- Warehouse Validation: TIER 0 (Structural Integrity)
--                                  TIER 1 (Vintage Coherence)
--
-- Phase 3 validated each table against its specification.
-- Phase 4 validates the warehouse against itself.
--
-- Everything here is EXACT. These checks compare two independent
-- derivations of the same truth, so a tolerance would only hide a
-- defect. No ED-008 statistical tolerances appear in this phase --
-- those exist for sampled-vs-target comparisons and belong to Phase 3.
-- The only latitude given anywhere is cent-level on large money
-- aggregates, for the float/decimal reason Phase 3.11 documented.
--
-- TIER 1 is the flagship, and nothing in Phase 3 could have caught it:
-- every generator validated its FKs at its OWN execution moment. Nothing
-- has ever verified that all four facts derive from the SAME VINTAGE of
-- their parents simultaneously. Surrogate keys are dense 1..N and are
-- REUSED on regeneration, so if a parent were regenerated under a
-- different seed, every FK would still resolve -- integrity would pass
-- cleanly -- while silently referencing different products at different
-- prices. Only content-based re-derivation can detect that.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TIER 0 -- STRUCTURAL INTEGRITY
-- ---------------------------------------------------------------------

-- @CHECK: id=0.1; tier=0; severity=BLOCKING; name=Warehouse-wide FK orphan sweep (all 4 facts, 17 relationships, one instant)
WITH orphans AS (
    SELECT 'Fact_Orders.customer_key' AS relationship, COUNT(*) AS orphan_count FROM Fact_Orders f LEFT JOIN Dim_Customer d USING (customer_key) WHERE d.customer_key IS NULL
    UNION ALL SELECT 'Fact_Orders.order_date_key', COUNT(*) FROM Fact_Orders f LEFT JOIN Dim_Date d ON f.order_date_key = d.date_key WHERE d.date_key IS NULL
    UNION ALL SELECT 'Fact_Orders.sales_channel_key', COUNT(*) FROM Fact_Orders f LEFT JOIN Dim_Sales_Channel d USING (sales_channel_key) WHERE d.sales_channel_key IS NULL
    UNION ALL SELECT 'Fact_Orders.geography_key', COUNT(*) FROM Fact_Orders f LEFT JOIN Dim_Geography d USING (geography_key) WHERE d.geography_key IS NULL
    UNION ALL SELECT 'Fact_Orders.campaign_key', COUNT(*) FROM Fact_Orders f LEFT JOIN Dim_Campaign d USING (campaign_key) WHERE f.campaign_key IS NOT NULL AND d.campaign_key IS NULL
    UNION ALL SELECT 'Fact_Orders.acquisition_channel_key', COUNT(*) FROM Fact_Orders f LEFT JOIN Dim_Marketing_Channel d ON f.acquisition_channel_key = d.marketing_channel_key WHERE d.marketing_channel_key IS NULL
    UNION ALL SELECT 'Fact_Order_Lines.order_key', COUNT(*) FROM Fact_Order_Lines f LEFT JOIN Fact_Orders o USING (order_key) WHERE o.order_key IS NULL
    UNION ALL SELECT 'Fact_Order_Lines.customer_key', COUNT(*) FROM Fact_Order_Lines f LEFT JOIN Dim_Customer d USING (customer_key) WHERE d.customer_key IS NULL
    UNION ALL SELECT 'Fact_Order_Lines.product_key', COUNT(*) FROM Fact_Order_Lines f LEFT JOIN Dim_Product d USING (product_key) WHERE d.product_key IS NULL
    UNION ALL SELECT 'Fact_Order_Lines.order_date_key', COUNT(*) FROM Fact_Order_Lines f LEFT JOIN Dim_Date d ON f.order_date_key = d.date_key WHERE d.date_key IS NULL
    UNION ALL SELECT 'Fact_Returns.order_key', COUNT(*) FROM Fact_Returns f LEFT JOIN Fact_Orders o USING (order_key) WHERE o.order_key IS NULL
    UNION ALL SELECT 'Fact_Returns.order_line_key', COUNT(*) FROM Fact_Returns f LEFT JOIN Fact_Order_Lines l USING (order_line_key) WHERE l.order_line_key IS NULL
    UNION ALL SELECT 'Fact_Returns.customer_key', COUNT(*) FROM Fact_Returns f LEFT JOIN Dim_Customer d USING (customer_key) WHERE d.customer_key IS NULL
    UNION ALL SELECT 'Fact_Returns.product_key', COUNT(*) FROM Fact_Returns f LEFT JOIN Dim_Product d USING (product_key) WHERE d.product_key IS NULL
    UNION ALL SELECT 'Fact_Returns.return_date_key', COUNT(*) FROM Fact_Returns f LEFT JOIN Dim_Date d ON f.return_date_key = d.date_key WHERE d.date_key IS NULL
    UNION ALL SELECT 'Fact_Returns.return_reason_key', COUNT(*) FROM Fact_Returns f LEFT JOIN Dim_Return_Reason d USING (return_reason_key) WHERE d.return_reason_key IS NULL
    UNION ALL SELECT 'Fact_Customer_Monthly_Snapshot.customer_key', COUNT(*) FROM Fact_Customer_Monthly_Snapshot f LEFT JOIN Dim_Customer d USING (customer_key) WHERE d.customer_key IS NULL
    UNION ALL SELECT 'Fact_Customer_Monthly_Snapshot.snapshot_month_date_key', COUNT(*) FROM Fact_Customer_Monthly_Snapshot f LEFT JOIN Dim_Date d ON f.snapshot_month_date_key = d.date_key WHERE d.date_key IS NULL
)
SELECT SUM(orphan_count) AS total_orphans,
       COUNT(*) FILTER (WHERE orphan_count > 0) AS broken_relationships,
       CASE WHEN SUM(orphan_count) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM orphans;

-- @CHECK: id=0.2; tier=0; severity=BLOCKING; name=Primary key uniqueness across all four fact tables
WITH pk AS (
    SELECT 'Fact_Orders' AS tbl, COUNT(*) AS rows, COUNT(DISTINCT order_key) AS distinct_pk FROM Fact_Orders
    UNION ALL SELECT 'Fact_Order_Lines', COUNT(*), COUNT(DISTINCT order_line_key) FROM Fact_Order_Lines
    UNION ALL SELECT 'Fact_Returns', COUNT(*), COUNT(DISTINCT return_key) FROM Fact_Returns
    UNION ALL SELECT 'Fact_Customer_Monthly_Snapshot', COUNT(*), COUNT(DISTINCT snapshot_key) FROM Fact_Customer_Monthly_Snapshot
)
SELECT COUNT(*) FILTER (WHERE rows != distinct_pk) AS tables_with_dup_pk,
       CASE WHEN COUNT(*) FILTER (WHERE rows != distinct_pk) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM pk;

-- @CHECK: id=0.3; tier=0; severity=BLOCKING; name=Business grain uniqueness (returns one-per-line, snapshot one-per-customer-month)
WITH grain AS (
    SELECT 'Fact_Returns.order_line_key' AS grain_rule,
           (SELECT COUNT(*) FROM Fact_Returns) - (SELECT COUNT(DISTINCT order_line_key) FROM Fact_Returns) AS violations
    UNION ALL
    SELECT 'Fact_Customer_Monthly_Snapshot.(customer,month)',
           (SELECT COUNT(*) FROM Fact_Customer_Monthly_Snapshot) - (SELECT COUNT(DISTINCT (customer_key, snapshot_month_date_key)) FROM Fact_Customer_Monthly_Snapshot)
)
SELECT SUM(violations) AS total_violations,
       CASE WHEN SUM(violations) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM grain;

-- @CHECK: id=0.4; tier=0; severity=BLOCKING; name=Every fact date falls inside Dim_Date's populated range
WITH bounds AS (SELECT MIN(date_key) AS lo, MAX(date_key) AS hi FROM Dim_Date)
SELECT
    (SELECT COUNT(*) FROM Fact_Orders, bounds WHERE order_date_key < lo OR order_date_key > hi)
  + (SELECT COUNT(*) FROM Fact_Order_Lines, bounds WHERE order_date_key < lo OR order_date_key > hi)
  + (SELECT COUNT(*) FROM Fact_Returns, bounds WHERE return_date_key < lo OR return_date_key > hi)
  + (SELECT COUNT(*) FROM Fact_Customer_Monthly_Snapshot, bounds WHERE snapshot_month_date_key < lo OR snapshot_month_date_key > hi) AS out_of_range_rows,
    CASE WHEN (SELECT COUNT(*) FROM Fact_Orders, bounds WHERE order_date_key < lo OR order_date_key > hi)
            + (SELECT COUNT(*) FROM Fact_Order_Lines, bounds WHERE order_date_key < lo OR order_date_key > hi)
            + (SELECT COUNT(*) FROM Fact_Returns, bounds WHERE return_date_key < lo OR return_date_key > hi)
            + (SELECT COUNT(*) FROM Fact_Customer_Monthly_Snapshot, bounds WHERE snapshot_month_date_key < lo OR snapshot_month_date_key > hi) = 0
         THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=0.5; tier=0; severity=BLOCKING; name=A return can never precede its own order
SELECT COUNT(*) AS impossible_returns,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns r JOIN Fact_Orders o USING (order_key)
WHERE r.return_date_key < o.order_date_key;

-- ---------------------------------------------------------------------
-- TIER 1 -- VINTAGE COHERENCE
-- Re-derives each fact's dependent values from its CURRENTLY LOADED
-- parents. A stale regeneration passes every FK check but fails here.
-- ---------------------------------------------------------------------

-- @CHECK: id=1.1; tier=1; severity=BLOCKING; name=Fact_Orders geography/acquisition channel still match the customer's current dimension row
SELECT COUNT(*) AS stale_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders o JOIN Dim_Customer c USING (customer_key)
WHERE o.geography_key != c.home_geography_key
   OR o.acquisition_channel_key != c.acquisition_channel_key;

-- @CHECK: id=1.2; tier=1; severity=BLOCKING; name=No order predates its own customer's signup date
SELECT COUNT(*) AS impossible_orders,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders o JOIN Dim_Customer c USING (customer_key) JOIN Dim_Date d ON o.order_date_key = d.date_key
WHERE d.full_date < c.signup_date;

-- @CHECK: id=1.3; tier=1; severity=BLOCKING; name=Fact_Order_Lines unit_cost still matches the product's current unit_cost
SELECT COUNT(*) AS stale_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key)
WHERE ABS(l.unit_cost - p.unit_cost) > 0.001;

-- @CHECK: id=1.4; tier=1; severity=BLOCKING; name=Fact_Order_Lines denormalized customer/date still match the current header
SELECT COUNT(*) AS stale_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Order_Lines l JOIN Fact_Orders o USING (order_key)
WHERE l.customer_key != o.customer_key OR l.order_date_key != o.order_date_key;

-- @CHECK: id=1.5; tier=1; severity=BLOCKING; name=Header net_revenue still equals SUM of its CURRENT lines (staleness detector, not a generator re-test)
WITH line_rollup AS (
    SELECT order_key, ROUND(SUM(net_line_revenue), 2) AS line_net FROM Fact_Order_Lines GROUP BY order_key
)
SELECT COUNT(*) AS stale_orders,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders o JOIN line_rollup lr USING (order_key)
WHERE ABS(o.net_revenue - lr.line_net) > 0.011;

-- @CHECK: id=1.6; tier=1; severity=BLOCKING; name=Fact_Returns amounts still reconcile to the CURRENT line they reference
SELECT COUNT(*) AS stale_returns,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns r JOIN Fact_Order_Lines l USING (order_line_key)
WHERE ABS(r.return_amount - ROUND(l.net_line_revenue * r.return_quantity / l.quantity, 2)) > 0.011
   OR r.return_quantity > l.quantity
   OR r.order_key != l.order_key
   OR r.customer_key != l.customer_key
   OR r.product_key != l.product_key;

-- @CHECK: id=1.7; tier=1; severity=BLOCKING; name=Campaign attribution still valid against the CURRENT Dim_Campaign windows
SELECT COUNT(*) AS misattributed_orders,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders f JOIN Dim_Campaign c USING (campaign_key) JOIN Dim_Date d ON f.order_date_key = d.date_key
WHERE d.full_date < c.start_date OR d.full_date > c.end_date;

-- @CHECK: id=1.8; tier=1; severity=BLOCKING; name=Campaign-attributed orders fall on a campaign_period_flag day in the CURRENT Dim_Date
SELECT COUNT(*) AS inconsistent_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders f JOIN Dim_Date d ON f.order_date_key = d.date_key
WHERE f.campaign_key IS NOT NULL AND d.campaign_period_flag = FALSE;

-- @CHECK: id=1.9; tier=1; severity=BLOCKING; name=Snapshot final month still reflects the CURRENT Fact_Orders and Fact_Returns
SELECT
    (SELECT SUM(cumulative_orders_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231) AS snapshot_orders,
    (SELECT COUNT(*) FROM Fact_Orders) AS actual_orders,
    ROUND((SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231), 2) AS snapshot_net_revenue,
    ROUND((SELECT SUM(net_revenue) FROM Fact_Orders) - (SELECT SUM(return_amount) FROM Fact_Returns), 2) AS actual_net_revenue,
    CASE WHEN (SELECT SUM(cumulative_orders_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231) = (SELECT COUNT(*) FROM Fact_Orders)
          AND ABS((SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231)
                  - ((SELECT SUM(net_revenue) FROM Fact_Orders) - (SELECT SUM(return_amount) FROM Fact_Returns))) <= 0.05
         THEN 'PASS' ELSE 'FAIL' END AS result;

-- @CHECK: id=1.10; tier=1; severity=BLOCKING; name=Every customer's snapshot series still starts at their CURRENT signup month
SELECT COUNT(*) AS stale_series,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (
    SELECT s.customer_key, MIN(d.full_date) AS first_month_end
    FROM Fact_Customer_Monthly_Snapshot s JOIN Dim_Date d ON s.snapshot_month_date_key = d.date_key
    GROUP BY s.customer_key
) b JOIN Dim_Customer c USING (customer_key)
WHERE DATE_TRUNC('month', b.first_month_end) != DATE_TRUNC('month', c.signup_date);
