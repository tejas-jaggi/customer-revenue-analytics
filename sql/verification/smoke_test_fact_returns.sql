-- =====================================================================
-- Smoke Test: Fact_Returns (Phase 3.11) -- fast, mechanical checks.
-- Business-rule checks live in sql/validation/validate_fact_returns.sql.
-- =====================================================================

-- 1. Row count is non-trivial and below the number of order lines
--    (a return is at most one per line, and most lines aren't returned)
SELECT COUNT(*) AS return_count, (SELECT COUNT(*) FROM Fact_Order_Lines) AS line_count,
       CASE WHEN COUNT(*) > 0 AND COUNT(*) < (SELECT COUNT(*) FROM Fact_Order_Lines)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns;

-- 2. return_key: no nulls, no duplicates
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT return_key) AS distinct_keys,
       CASE WHEN COUNT(*) = COUNT(DISTINCT return_key) AND COUNT(*) = COUNT(return_key)
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns;

-- 3. Grain: at most one return per order_line_key
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT order_line_key) AS distinct_lines,
       CASE WHEN COUNT(*) = COUNT(DISTINCT order_line_key) THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns;

-- 4. NOT NULL sweep (every column on this table is NOT NULL)
SELECT CASE WHEN SUM(CASE WHEN order_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN order_line_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN customer_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN product_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN return_date_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN return_reason_key IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN return_quantity IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN return_amount IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN restocking_fee IS NULL THEN 1 ELSE 0 END)
          + SUM(CASE WHEN refund_completed_flag IS NULL THEN 1 ELSE 0 END) = 0
       THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns;

-- 5. schema.sql CHECK constraints re-read: quantity > 0, money >= 0
SELECT COUNT(*) AS bad_rows, CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns
WHERE return_quantity <= 0 OR return_amount < 0 OR restocking_fee < 0;

-- 6. Structural shape
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'Fact_Returns' ORDER BY ordinal_position;
