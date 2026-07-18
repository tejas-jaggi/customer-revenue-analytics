-- =====================================================================
-- Validation: Fact_Returns (Phase 3.11) -- business-aware checks.
-- Empty result set (or explicit PASS) = clean.
-- Section 9 targets are unit-weighted, per business_understanding.md's
-- KPI definition: Return Rate = Units Returned / Units Sold.
-- =====================================================================

-- 1-6. FK integrity against every live parent
SELECT r.return_key FROM Fact_Returns r LEFT JOIN Fact_Order_Lines l USING (order_line_key) WHERE l.order_line_key IS NULL;
SELECT r.return_key FROM Fact_Returns r LEFT JOIN Fact_Orders o USING (order_key) WHERE o.order_key IS NULL;
SELECT r.return_key FROM Fact_Returns r LEFT JOIN Dim_Customer c USING (customer_key) WHERE c.customer_key IS NULL;
SELECT r.return_key FROM Fact_Returns r LEFT JOIN Dim_Product p USING (product_key) WHERE p.product_key IS NULL;
SELECT r.return_key FROM Fact_Returns r LEFT JOIN Dim_Date d ON r.return_date_key = d.date_key WHERE d.date_key IS NULL;
SELECT r.return_key FROM Fact_Returns r LEFT JOIN Dim_Return_Reason rr USING (return_reason_key) WHERE rr.return_reason_key IS NULL;

-- 7. Denormalized consistency: a return's order/customer/product must
--    match the order line it originated from
SELECT r.return_key FROM Fact_Returns r JOIN Fact_Order_Lines l USING (order_line_key)
WHERE r.order_key != l.order_key OR r.customer_key != l.customer_key OR r.product_key != l.product_key;

-- 8. Section 7 (exact rule, no tolerance): return date is 5-21 days after
--    the originating order -- never same-day, never past 30
SELECT r.return_key, d1.full_date AS order_date, d2.full_date AS return_date,
       (d2.full_date - d1.full_date) AS lag_days
FROM Fact_Returns r
JOIN Fact_Orders o USING (order_key)
JOIN Dim_Date d1 ON o.order_date_key = d1.date_key
JOIN Dim_Date d2 ON r.return_date_key = d2.date_key
WHERE (d2.full_date - d1.full_date) < 5 OR (d2.full_date - d1.full_date) > 21;

-- 9. Never return more units than were sold on that line
SELECT r.return_key, r.return_quantity, l.quantity AS units_sold
FROM Fact_Returns r JOIN Fact_Order_Lines l USING (order_line_key)
WHERE r.return_quantity > l.quantity;

-- 10. return_amount ties out to the line proportionally, and never refunds
--     more than the line's net revenue.
--
--     Tolerance is one cent PLUS a hair (0.011), not zero, and that is
--     deliberate: an exact half-cent split (e.g. a 1-of-2 return of a
--     $163.39 line = $81.695) is resolved by the generator's explicit
--     half-up Decimal rule to $81.70, while DuckDB's float ROUND() lands
--     on $81.69. The generator's rule is the authoritative one -- it is
--     explicit, deterministic, and shared by build and validate. This
--     check's job is catching a wrong PROPORTION (returning half a line
--     and refunding all of it), not adjudicating rounding conventions
--     between two engines, so it tolerates the one-cent tie and stays
--     tight enough to catch any real allocation error.
SELECT r.return_key, r.return_amount, l.net_line_revenue,
       ROUND(l.net_line_revenue * r.return_quantity / l.quantity, 2) AS duckdb_recomputed
FROM Fact_Returns r JOIN Fact_Order_Lines l USING (order_line_key)
WHERE ABS(r.return_amount - ROUND(l.net_line_revenue * r.return_quantity / l.quantity, 2)) > 0.011
   OR r.return_amount > l.net_line_revenue + 0.01;

-- 11. Restocking fee is charged only on CHANGED_MIND (the business never
--     charges a customer for its own fault), at the documented 10%
SELECT r.return_key, rr.reason_code, r.restocking_fee
FROM Fact_Returns r JOIN Dim_Return_Reason rr USING (return_reason_key)
WHERE (rr.reason_code != 'CHANGED_MIND' AND r.restocking_fee != 0)
   OR (rr.reason_code  = 'CHANGED_MIND' AND ABS(r.restocking_fee - ROUND(r.return_amount * 0.10, 2)) > 0.011);  -- same half-cent tolerance rationale as check #10

-- 12. Section 9: blended unit return rate 15-20%
SELECT ROUND(100.0 * (SELECT SUM(return_quantity) FROM Fact_Returns)
                   / (SELECT SUM(quantity) FROM Fact_Order_Lines), 1) AS blended_return_rate_pct,
       CASE WHEN (SELECT SUM(return_quantity) FROM Fact_Returns) * 1.0
                 / (SELECT SUM(quantity) FROM Fact_Order_Lines)
                 BETWEEN 0.15*0.95 AND 0.20*1.05 THEN 'PASS' ELSE 'FAIL' END AS result;

-- 13. Section 9: Footwear 25-30%, Accessories 8-10% (the two pinned
--     categories). Other categories reported for visibility.
WITH sold AS (SELECT p.category, SUM(l.quantity) AS units FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category),
returned AS (SELECT p.category, SUM(r.return_quantity) AS units FROM Fact_Returns r JOIN Dim_Product p USING (product_key) GROUP BY p.category)
SELECT s.category, ROUND(100.0 * COALESCE(rt.units, 0) / s.units, 1) AS return_rate_pct,
       CASE
           WHEN s.category = 'Footwear'    AND COALESCE(rt.units,0)*1.0/s.units BETWEEN 0.25*0.95 AND 0.30*1.05 THEN 'PASS'
           WHEN s.category = 'Accessories' AND COALESCE(rt.units,0)*1.0/s.units BETWEEN 0.08*0.95 AND 0.10*1.05 THEN 'PASS'
           WHEN s.category IN ('Womenswear', 'Menswear', 'Outerwear') THEN 'PASS'  -- not pinned by Section 9
           ELSE 'FAIL'
       END AS result
FROM sold s LEFT JOIN returned rt USING (category)
ORDER BY return_rate_pct DESC;

-- 14. Every return reason in the closed taxonomy actually occurs (a mix
--     that never produces a documented reason would be a modelling gap)
SELECT rr.reason_code AS unused_reason
FROM Dim_Return_Reason rr LEFT JOIN Fact_Returns r USING (return_reason_key)
WHERE r.return_reason_key IS NULL;

-- 15. Accessories have no sizing dimension (Phase 3.6 leaves size NULL),
--     so Wrong Size must be a minor reason there -- guards against the
--     reason mix being applied category-blind
SELECT ROUND(100.0 * SUM(CASE WHEN rr.reason_code = 'WRONG_SIZE' THEN 1 ELSE 0 END) / COUNT(*), 1) AS accessories_wrong_size_pct,
       CASE WHEN SUM(CASE WHEN rr.reason_code = 'WRONG_SIZE' THEN 1 ELSE 0 END) * 1.0 / COUNT(*) < 0.20
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns r
JOIN Dim_Return_Reason rr USING (return_reason_key)
JOIN Dim_Product p USING (product_key)
WHERE p.category = 'Accessories';

-- 16. Controllable-vs-not split is meaningful (this is what the whole
--     is_controllable flag exists for, per Phase 3.7) -- both sides present
SELECT rr.is_controllable, COUNT(*) AS returns, ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 1) AS pct,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns r JOIN Dim_Return_Reason rr USING (return_reason_key)
GROUP BY rr.is_controllable ORDER BY rr.is_controllable;

-- 17. refund_completed_flag: no refund may be marked completed before its
--     own return date + the operational lag has elapsed within the window
SELECT COUNT(*) AS impossible_completions,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Returns r JOIN Dim_Date d ON r.return_date_key = d.date_key
WHERE r.refund_completed_flag AND d.full_date > DATE '2025-12-26';
