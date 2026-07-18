-- =====================================================================
-- Smoke Test: Fact_Order_Lines (Phase 3.10) -- fast mechanical checks.
-- =====================================================================
-- 1. Non-trivial row count consistent with ~1.29 lines/order
SELECT COUNT(*) AS line_count, (SELECT COUNT(*) FROM Fact_Orders) AS order_count,
       CASE WHEN COUNT(*) BETWEEN 1.20*(SELECT COUNT(*) FROM Fact_Orders)
                              AND 1.45*(SELECT COUNT(*) FROM Fact_Orders)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Order_Lines;
-- 2. order_line_key: no nulls, no duplicates
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT order_line_key) AS distinct_keys,
       CASE WHEN COUNT(*) = COUNT(DISTINCT order_line_key) AND COUNT(*) = COUNT(order_line_key)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Order_Lines;
-- 3. NOT NULL sweep
SELECT CASE WHEN SUM(CASE WHEN order_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN customer_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN product_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN order_date_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN quantity IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN unit_price IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN gross_line_revenue IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN discount_amount IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN net_line_revenue IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN unit_cost IS NULL THEN 1 ELSE 0 END) = 0
       THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Order_Lines;
-- 4. No negative money / non-positive quantity
SELECT COUNT(*) AS bad_rows, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Order_Lines
WHERE quantity <= 0 OR unit_price < 0 OR gross_line_revenue < 0 OR discount_amount < 0 OR net_line_revenue < 0 OR unit_cost < 0;
-- 5. Structural shape
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'Fact_Order_Lines' ORDER BY ordinal_position;
