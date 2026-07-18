-- =====================================================================
-- Validation: Fact_Order_Lines (Phase 3.10) -- business-aware checks.
-- The reconciliation check (#7) is the one this table exists to satisfy.
-- Empty result set (or explicit PASS) = clean.
-- =====================================================================
-- 1-4. FK integrity against live parents
SELECT l.order_line_key FROM Fact_Order_Lines l LEFT JOIN Fact_Orders o USING (order_key) WHERE o.order_key IS NULL;
SELECT l.order_line_key FROM Fact_Order_Lines l LEFT JOIN Dim_Customer c USING (customer_key) WHERE c.customer_key IS NULL;
SELECT l.order_line_key FROM Fact_Order_Lines l LEFT JOIN Dim_Product p USING (product_key) WHERE p.product_key IS NULL;
SELECT l.order_line_key FROM Fact_Order_Lines l LEFT JOIN Dim_Date d ON l.order_date_key = d.date_key WHERE d.date_key IS NULL;
-- 5. Line math: gross = qty x unit_price; net = gross - discount
SELECT order_line_key FROM Fact_Order_Lines
WHERE ABS(gross_line_revenue - ROUND(quantity * unit_price, 2)) > 0.01
   OR ABS(net_line_revenue - ROUND(gross_line_revenue - discount_amount, 2)) > 0.005;
-- 6. Denormalized consistency with header (customer, date)
SELECT l.order_line_key FROM Fact_Order_Lines l JOIN Fact_Orders o USING (order_key)
WHERE l.customer_key != o.customer_key OR l.order_date_key != o.order_date_key;
-- 7. RECONCILIATION: per-order SUM(net_line_revenue) == header net_revenue
SELECT o.order_key, o.net_revenue AS header_net, ROUND(SUM(l.net_line_revenue), 2) AS line_sum
FROM Fact_Orders o JOIN Fact_Order_Lines l USING (order_key)
GROUP BY o.order_key, o.net_revenue
HAVING ABS(ROUND(SUM(l.net_line_revenue), 2) - o.net_revenue) > 0.005;
-- 7b. Same reconciliation for gross and discount (full three-way tie-out)
SELECT o.order_key FROM Fact_Orders o JOIN Fact_Order_Lines l USING (order_key)
GROUP BY o.order_key, o.gross_revenue, o.discount_amount
HAVING ABS(ROUND(SUM(l.gross_line_revenue), 2) - o.gross_revenue) > 0.005
    OR ABS(ROUND(SUM(l.discount_amount), 2) - o.discount_amount) > 0.005;
-- 8. Every order has >= 1 line; no order exceeds the documented max of 3
SELECT o.order_key AS order_without_lines FROM Fact_Orders o LEFT JOIN Fact_Order_Lines l USING (order_key) WHERE l.order_key IS NULL;
SELECT order_key, COUNT(*) AS line_count FROM Fact_Order_Lines GROUP BY order_key HAVING COUNT(*) > 3;
-- 9. Average lines/order within calibrated range (informational + PASS/FAIL)
SELECT ROUND(COUNT(*) * 1.0 / (SELECT COUNT(*) FROM Fact_Orders), 3) AS avg_lines_per_order,
       CASE WHEN COUNT(*) * 1.0 / (SELECT COUNT(*) FROM Fact_Orders) BETWEEN 1.20 AND 1.45
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Order_Lines;
-- 10. FK-readiness for Fact_Returns: order_line_key dense from 1
SELECT MIN(order_line_key) AS min_key, MAX(order_line_key) AS max_key, COUNT(*) AS row_count,
       CASE WHEN MIN(order_line_key) = 1 AND MAX(order_line_key) = COUNT(*)
             AND COUNT(DISTINCT order_line_key) = COUNT(*) THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Order_Lines;
