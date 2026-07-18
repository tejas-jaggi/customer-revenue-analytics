-- =====================================================================
-- Smoke Test: Fact_Orders (Phase 3.9) -- fast, mechanical checks.
-- Deeper business checks: sql/validation/validate_fact_orders.sql
-- =====================================================================

-- 1. Row count within the emergent expected range (see generator: Section 3
--    vs Section 9 inconsistency resolved in favor of Section 9)
SELECT COUNT(*) AS row_count,
       CASE WHEN COUNT(*) BETWEEN 18000 AND 60000 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders;

-- 2. order_key: no nulls, no duplicates
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT order_key) AS distinct_keys,
       CASE WHEN COUNT(*) = COUNT(DISTINCT order_key) AND COUNT(*) = COUNT(order_key)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders;

-- 3. order_id: no nulls, no duplicates
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT order_id) AS distinct_ids,
       CASE WHEN COUNT(*) = COUNT(DISTINCT order_id) AND COUNT(*) = COUNT(order_id)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders;

-- 4. NOT NULL sweep (campaign_key is the only nullable column)
SELECT CASE WHEN SUM(CASE WHEN customer_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN order_date_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN sales_channel_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN geography_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN acquisition_channel_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN gross_revenue IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN discount_amount IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN net_revenue IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN shipping_revenue IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN is_first_order IS NULL THEN 1 ELSE 0 END) = 0
       THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders;

-- 5. No negative money values (re-confirms schema CHECK constraints)
SELECT COUNT(*) AS bad_rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders
WHERE gross_revenue < 0 OR discount_amount < 0 OR net_revenue < 0 OR shipping_revenue < 0;

-- 6. Structural shape check
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'Fact_Orders' ORDER BY ordinal_position;
