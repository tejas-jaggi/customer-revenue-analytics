-- =====================================================================
-- Validation: Fact_Orders (Phase 3.9) -- business-aware checks including
-- the five Section 9 targets computable from this table alone.
-- Empty result set (or explicit PASS) = clean.
-- =====================================================================

-- 1-6. FK integrity against every live parent (schema REFERENCES already
--      enforce these at load; explicit re-confirmation, ED-007 style)
SELECT f.order_key FROM Fact_Orders f LEFT JOIN Dim_Customer c USING (customer_key) WHERE c.customer_key IS NULL;
SELECT f.order_key FROM Fact_Orders f LEFT JOIN Dim_Date d ON f.order_date_key = d.date_key WHERE d.date_key IS NULL;
SELECT f.order_key FROM Fact_Orders f LEFT JOIN Dim_Sales_Channel s USING (sales_channel_key) WHERE s.sales_channel_key IS NULL;
SELECT f.order_key FROM Fact_Orders f LEFT JOIN Dim_Geography g USING (geography_key) WHERE g.geography_key IS NULL;
SELECT f.order_key FROM Fact_Orders f LEFT JOIN Dim_Marketing_Channel m ON f.acquisition_channel_key = m.marketing_channel_key WHERE m.marketing_channel_key IS NULL;
SELECT f.order_key FROM Fact_Orders f LEFT JOIN Dim_Campaign cp USING (campaign_key) WHERE f.campaign_key IS NOT NULL AND cp.campaign_key IS NULL;

-- 7. net_revenue = gross_revenue - discount_amount (1 cent tolerance)
SELECT order_key, gross_revenue, discount_amount, net_revenue
FROM Fact_Orders WHERE ABS(net_revenue - (gross_revenue - discount_amount)) > 0.01;

-- 8. No discount without a campaign (documented attribution rule)
SELECT order_key FROM Fact_Orders WHERE campaign_key IS NULL AND discount_amount != 0;

-- 9. Free-shipping threshold rule ($75 / $6.99 flat)
SELECT order_key, net_revenue, shipping_revenue FROM Fact_Orders
WHERE (net_revenue >= 75.00 AND shipping_revenue != 0)
   OR (net_revenue <  75.00 AND ABS(shipping_revenue - 6.99) > 0.001);

-- 10. Exactly one is_first_order per customer, on their earliest order
SELECT customer_key, SUM(CASE WHEN is_first_order THEN 1 ELSE 0 END) AS flags
FROM Fact_Orders GROUP BY customer_key HAVING flags != 1;
SELECT f.customer_key FROM Fact_Orders f
JOIN (SELECT customer_key, MIN(order_date_key) AS min_dk FROM Fact_Orders GROUP BY customer_key) e USING (customer_key)
WHERE f.is_first_order AND f.order_date_key != e.min_dk;

-- 11. Campaign attribution consistency: every campaign-attributed order's
--     date falls inside that campaign's start/end window
SELECT f.order_key, f.order_date_key, cp.campaign_name, cp.start_date, cp.end_date
FROM Fact_Orders f JOIN Dim_Campaign cp USING (campaign_key)
WHERE CAST(STRFTIME(cp.start_date, '%Y%m%d') AS INT) > f.order_date_key
   OR CAST(STRFTIME(cp.end_date,   '%Y%m%d') AS INT) < f.order_date_key;

-- 12-16. Section 9 validation targets (PASS/FAIL, +/-5% multiplicative tolerance)
SELECT ROUND(AVG(net_revenue), 2) AS blended_aov,
       CASE WHEN AVG(net_revenue) BETWEEN 65*0.95 AND 85*1.05 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders;

SELECT ROUND(100.0 * SUM(CASE WHEN campaign_key IS NOT NULL THEN net_revenue ELSE 0 END) / SUM(net_revenue), 1) AS campaign_rev_share_pct,
       CASE WHEN SUM(CASE WHEN campaign_key IS NOT NULL THEN net_revenue ELSE 0 END) / SUM(net_revenue)
                 BETWEEN 0.30*0.95 AND 0.40*1.05 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders;

SELECT ROUND(100.0 * AVG(CASE WHEN s.channel_name = 'Marketplace' THEN 1.0 ELSE 0 END), 1) AS marketplace_order_share_pct,
       CASE WHEN AVG(CASE WHEN s.channel_name = 'Marketplace' THEN 1.0 ELSE 0 END)
                 BETWEEN 0.10*0.95 AND 0.15*1.05 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders f JOIN Dim_Sales_Channel s USING (sales_channel_key);

SELECT ROUND(100.0 * SUM(CASE WHEN CAST(order_date_key/100 AS INT)%100 IN (11,12) THEN net_revenue ELSE 0 END) / SUM(net_revenue), 1) AS holiday_rev_share_pct,
       CASE WHEN SUM(CASE WHEN CAST(order_date_key/100 AS INT)%100 IN (11,12) THEN net_revenue ELSE 0 END) / SUM(net_revenue)
                 BETWEEN 0.25*0.95 AND 0.30*1.05 THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders;

SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE cnt >= 2) / (SELECT COUNT(*) FROM Dim_Customer), 1) AS repeat_rate_pct,
       CASE WHEN COUNT(*) FILTER (WHERE cnt >= 2) * 1.0 / (SELECT COUNT(*) FROM Dim_Customer)
                 BETWEEN 0.35*0.95 AND 0.45*1.05 THEN 'PASS' ELSE 'FAIL' END AS result
FROM (SELECT customer_key, COUNT(*) AS cnt FROM Fact_Orders GROUP BY customer_key);

-- 17. FK-readiness for Fact_Order_Lines/Fact_Returns: order_key dense from 1
SELECT MIN(order_key) AS min_key, MAX(order_key) AS max_key, COUNT(*) AS row_count,
       CASE WHEN MIN(order_key) = 1 AND MAX(order_key) = COUNT(*)
             AND COUNT(DISTINCT order_key) = COUNT(*) THEN 'PASS' ELSE 'FAIL' END AS result
FROM Fact_Orders;
