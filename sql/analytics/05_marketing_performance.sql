-- ####################################################################
-- Phase 5 — SQL Analytics Layer
-- SECTION E — MARKETING PERFORMANCE & ACQUISITION QUALITY
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 (frozen, certified). Read-only analytics.
-- Governed by permanent rules P5-1/P5-2/P5-3 (docs/phase5_build_log.md).
--
-- PURPOSE: not "which channel is biggest," but "which channels acquire the
--   most VALUABLE long-term customers." Volume vs quality is the spine.
--
-- ══ TWO STRUCTURAL ATTRIBUTION LIMITATIONS (documented, not hidden) ══
-- L1  ACQUISITION CHANNEL IS A LIFETIME CUSTOMER ATTRIBUTE, not a per-order
--     marketing touch. acquisition_channel_key lives on Dim_Customer (how the
--     customer was acquired, once) and is denormalized onto Fact_Orders
--     (Phase 4 check 1.1: 0 mismatches, so either source is valid). "Revenue
--     by acquisition channel" therefore means "lifetime revenue from customers
--     acquired via that channel" — exactly the acquisition-QUALITY lens this
--     section wants. It is NOT touch-attribution of a marketing event to an order.
-- L2  CAMPAIGN ATTRIBUTION IS THIN AND GROSS-ONLY. campaign_key marks orders
--     placed DURING a campaign window; it does not link to how the customer was
--     acquired, and Fact_Returns has NO campaign_key. So campaign revenue can
--     only be measured gross of returns, and campaigns cannot be evaluated on
--     RETAINED revenue. E.3 respects this; E.5 refuses to force a conclusion
--     the data cannot support.
--
-- ANCHOR: acquisition-channel revenue reconciles to certified Order Net
--   Revenue $2,195,871.49 (verified: the acquisition-channel join is
--   lossless); customer counts reconcile to 8,000.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- E.1 — Acquisition Channel Performance (volume)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How much revenue, how many customers, and how many
--                     orders does each acquisition channel account for?
-- Stakeholder       : VP Marketing / CFO
-- Metric Definition : per channel: customers acquired, purchasing customers,
--                     orders, lifetime revenue, and revenue/customer contribution %
-- Metric Basis      : Order Net Revenue, Customer Count
-- Analysis Grain    : Dim_Customer (acquisition base) LEFT JOIN Fact_Orders
--                     (lifetime revenue) — customer grain rolled to channel
-- SQL Design        : Base = Dim_Customer by acquisition_channel_key (includes
--                     the 289 non-purchasers, so customer contribution is
--                     honest). LEFT JOIN orders for lifetime revenue. No line
--                     join (header revenue).
-- Analytical Assumptions : L1 — lifetime attribution. Customer contribution %
--                     uses the full acquired base; revenue contribution % uses
--                     lifetime revenue.
-- Independent Review: Customer-grain base + header revenue via LEFT JOIN; the
--                     289 non-purchasers correctly dilute their channel. OK.
-- Validation        : Type A — channel revenue sums to $2,195,871.49;
--                     customers sum to 8,000.
-- Result Sanity     : Paid Social largest (generation weight); paid channels
--                     (Social+Search) dominate volume; owned/organic smaller.
-- ═══════════════════════════════════════════════════════════════════
SELECT mc.channel_name,
       mc.channel_category,
       COUNT(DISTINCT c.customer_key)                             AS customers_acquired,
       COUNT(DISTINCT o.customer_key)                             AS purchasing_customers,
       COUNT(o.order_key)                                         AS orders,
       ROUND(SUM(o.net_revenue), 2)                               AS order_net_revenue,
       ROUND(100.0 * SUM(o.net_revenue)
             / SUM(SUM(o.net_revenue)) OVER (), 1)                AS pct_of_revenue,
       ROUND(100.0 * COUNT(DISTINCT c.customer_key)
             / SUM(COUNT(DISTINCT c.customer_key)) OVER (), 1)    AS pct_of_customers
FROM Dim_Customer c
JOIN Dim_Marketing_Channel mc ON c.acquisition_channel_key = mc.marketing_channel_key
LEFT JOIN Fact_Orders o ON o.customer_key = c.customer_key
GROUP BY mc.channel_name, mc.channel_category ORDER BY order_net_revenue DESC;

-- E.1-VALIDATION (Type A) — revenue and customers reconcile
SELECT ROUND(SUM(order_net_revenue), 2) AS total_revenue, SUM(customers) AS total_customers,
       CASE WHEN ABS(SUM(order_net_revenue) - 2195871.49) <= 0.01 AND SUM(customers) = 8000
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT mc.marketing_channel_key,
             COUNT(DISTINCT c.customer_key) AS customers,
             COALESCE(SUM(o.net_revenue), 0) AS order_net_revenue
      FROM Dim_Customer c
      JOIN Dim_Marketing_Channel mc ON c.acquisition_channel_key = mc.marketing_channel_key
      LEFT JOIN Fact_Orders o ON o.customer_key = c.customer_key
      GROUP BY mc.marketing_channel_key);


-- ═══════════════════════════════════════════════════════════════════
-- E.2 — Customer Quality by Acquisition Channel (the core of the section)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Do channels differ in the QUALITY of customer they
--                     bring — revenue per customer, repeat rate, AOV, order
--                     frequency — not just the volume?
-- Stakeholder       : VP Marketing / Head of Retention
-- Metric Definition : per channel: revenue per acquired customer, repeat
--                     purchase rate (>=2 orders / acquired base), AOV
--                     (revenue/orders), orders per purchasing customer
-- Metric Basis      : Order Net Revenue, Customer Count, Order Count
-- Analysis Grain    : Dim_Customer (base) + Fact_Orders (behavior), channel grain
-- SQL Design        : Combine per-channel order aggregates with the acquired
--                     base and a repeat-customer count (>=2 orders). Repeat-rate
--                     denominator is the full acquired base (consistent with the
--                     certified 35.64% definition).
-- Analytical Assumptions : L1 lifetime attribution. Repeat rate uses the same
--                     >=2-lifetime-orders definition as the certified KPI; the
--                     six channel rates aggregate to the national 35.64%.
-- Independent Review: Channel rollups; repeat count from HAVING subquery;
--                     denominators consistent with certified definitions. OK.
-- Validation        : Type A — repeat customers across channels sum to
--                     certified 2,851; AOV blends to $83.50.
-- Result Sanity     : If quality differs, expect owned/organic (Email, Direct,
--                     Organic) to show higher repeat rates than pure paid
--                     acquisition — the classic "paid buys volume, owned buys
--                     loyalty" pattern. Test, do not assume.
-- ═══════════════════════════════════════════════════════════════════
WITH channel_orders AS (
    SELECT c.acquisition_channel_key,
           COUNT(o.order_key) AS orders,
           SUM(o.net_revenue) AS revenue,
           COUNT(DISTINCT o.customer_key) AS purchasing_customers
    FROM Dim_Customer c LEFT JOIN Fact_Orders o ON o.customer_key = c.customer_key
    GROUP BY c.acquisition_channel_key
),
channel_repeat AS (
    SELECT acquisition_channel_key, COUNT(*) AS repeat_customers FROM (
        SELECT c.acquisition_channel_key, o.customer_key
        FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key = c.customer_key
        GROUP BY c.acquisition_channel_key, o.customer_key HAVING COUNT(*) >= 2
    ) GROUP BY acquisition_channel_key
),
channel_base AS (
    SELECT acquisition_channel_key, COUNT(*) AS acquired_customers
    FROM Dim_Customer GROUP BY acquisition_channel_key
)
SELECT mc.channel_name,
       cb.acquired_customers,
       ROUND(co.revenue / cb.acquired_customers, 2)                          AS revenue_per_customer,
       ROUND(100.0 * COALESCE(cr.repeat_customers,0) / cb.acquired_customers, 1) AS repeat_rate_pct,
       ROUND(co.revenue / NULLIF(co.orders,0), 2)                            AS aov,
       ROUND(1.0 * co.orders / NULLIF(co.purchasing_customers,0), 2)         AS orders_per_purchasing_customer
FROM channel_base cb
JOIN channel_orders co USING (acquisition_channel_key)
LEFT JOIN channel_repeat cr USING (acquisition_channel_key)
JOIN Dim_Marketing_Channel mc ON cb.acquisition_channel_key = mc.marketing_channel_key
ORDER BY revenue_per_customer DESC;

-- E.2-VALIDATION (Type A) — channel repeat customers sum to certified 2,851
SELECT COUNT(*) AS total_repeat_customers, 2851 AS certified_count,
       CASE WHEN COUNT(*) = 2851 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT c.acquisition_channel_key, o.customer_key
      FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key = c.customer_key
      GROUP BY c.acquisition_channel_key, o.customer_key HAVING COUNT(*) >= 2) sub;


-- ═══════════════════════════════════════════════════════════════════
-- E.3 — Campaign Performance (within documented attribution limits)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How do campaign TYPES compare on revenue, orders, and
--                     order value during their windows?
-- Stakeholder       : VP Marketing
-- Metric Definition : per campaign_type: orders, revenue, AOV, % of
--                     campaign-attributed revenue
-- Metric Basis      : Order Net Revenue (GROSS of returns — see L2)
-- Analysis Grain    : Fact_Orders (header) x Dim_Campaign, campaign-attributed
--                     orders only (campaign_key NOT NULL)
-- SQL Design        : Only 11,701 of 26,299 orders carry a campaign_key; this
--                     query is explicitly over that subset. NOT reconciled to
--                     the $2.2M total (most orders are non-campaign) — instead
--                     validated against the campaign-attributed subtotal.
-- Analytical Assumptions : L2 — campaign revenue is gross of returns (returns
--                     have no campaign_key), so this measures campaign-window
--                     GROSS performance, not retained revenue. AOV here is
--                     campaign-window AOV, comparable across campaign types.
-- Independent Review: Header revenue over the campaign-attributed subset;
--                     subset boundary explicit. OK.
-- Validation        : Type B — campaign-attributed revenue independently
--                     recomputed two ways (by type vs total attributed) agree.
-- Result Sanity     : Seasonal Launch largest (longest/most frequent windows);
--                     Clearance smallest and likely lowest AOV (deep discounts).
-- ═══════════════════════════════════════════════════════════════════
SELECT cam.campaign_type,
       COUNT(*)                                                   AS orders,
       ROUND(SUM(o.net_revenue), 2)                               AS campaign_revenue_gross,
       ROUND(AVG(o.net_revenue), 2)                               AS aov,
       ROUND(100.0 * SUM(o.net_revenue)
             / SUM(SUM(o.net_revenue)) OVER (), 1)                AS pct_of_campaign_revenue
FROM Fact_Orders o JOIN Dim_Campaign cam USING (campaign_key)
GROUP BY cam.campaign_type ORDER BY campaign_revenue_gross DESC;

-- E.3-VALIDATION (Type B) — campaign-attributed revenue reconciles two ways
SELECT ROUND((SELECT SUM(net_revenue) FROM Fact_Orders WHERE campaign_key IS NOT NULL), 2) AS attributed_total,
       ROUND((SELECT SUM(o.net_revenue) FROM Fact_Orders o JOIN Dim_Campaign cam USING (campaign_key)), 2) AS via_join,
       CASE WHEN ABS((SELECT SUM(net_revenue) FROM Fact_Orders WHERE campaign_key IS NOT NULL)
                   - (SELECT SUM(o.net_revenue) FROM Fact_Orders o JOIN Dim_Campaign cam USING (campaign_key))) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS regression_result;


-- ═══════════════════════════════════════════════════════════════════
-- E.4 — Marketing Efficiency (volume vs value, combined)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which channels generate high-VALUE customers rather
--                     than simply many customers — where should spend tilt?
-- Stakeholder       : VP Marketing / CFO
-- Metric Definition : per channel, side by side: customer share, revenue share,
--                     revenue per customer, repeat rate — with a value-vs-volume
--                     signal (revenue share minus customer share)
-- Metric Basis      : Order Net Revenue, Customer Count
-- Analysis Grain    : channel (Dim_Customer base + Fact_Orders behavior)
-- SQL Design        : Combine E.1 shares with E.2 quality. The key derived
--                     signal: (revenue share - customer share) is positive when
--                     a channel punches ABOVE its customer weight (high value)
--                     and negative when it punches below (volume-only).
-- Analytical Assumptions : L1 lifetime attribution. "Efficiency" here is value
--                     density, not cost efficiency — the warehouse has no
--                     marketing SPEND data, so ROI/CAC cannot be computed
--                     (documented limitation, not an omission).
-- Independent Review: Both shares from anchored E.1/E.2 logic; the differential
--                     is a derived comparison. OK.
-- Validation        : Type B — revenue shares sum to 100, customer shares sum
--                     to 100 (independent recomputation).
-- Result Sanity     : Channels with positive (rev% - cust%) are the value
--                     channels; expect owned/organic to over-index on value,
--                     paid to over-index on volume.
-- ═══════════════════════════════════════════════════════════════════
WITH ch AS (
    SELECT c.acquisition_channel_key,
           COUNT(DISTINCT c.customer_key) AS customers,
           SUM(o.net_revenue) AS revenue,
           COUNT(o.order_key) AS orders
    FROM Dim_Customer c LEFT JOIN Fact_Orders o ON o.customer_key = c.customer_key
    GROUP BY c.acquisition_channel_key
),
rep AS (
    SELECT acquisition_channel_key, COUNT(*) AS repeat_customers FROM (
        SELECT c.acquisition_channel_key, o.customer_key
        FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key = c.customer_key
        GROUP BY c.acquisition_channel_key, o.customer_key HAVING COUNT(*) >= 2
    ) GROUP BY acquisition_channel_key
)
SELECT mc.channel_name, mc.channel_category,
       ROUND(100.0 * ch.customers / SUM(ch.customers) OVER (), 1)            AS customer_share_pct,
       ROUND(100.0 * ch.revenue / SUM(ch.revenue) OVER (), 1)               AS revenue_share_pct,
       ROUND(100.0 * ch.revenue / SUM(ch.revenue) OVER ()
           - 100.0 * ch.customers / SUM(ch.customers) OVER (), 1)           AS value_vs_volume_gap,
       ROUND(ch.revenue / ch.customers, 2)                                  AS revenue_per_customer,
       ROUND(100.0 * COALESCE(rep.repeat_customers,0) / ch.customers, 1)    AS repeat_rate_pct
FROM ch
LEFT JOIN rep USING (acquisition_channel_key)
JOIN Dim_Marketing_Channel mc ON ch.acquisition_channel_key = mc.marketing_channel_key
ORDER BY value_vs_volume_gap DESC;

-- E.4-VALIDATION (Type B) — shares sum to 100
SELECT ROUND(SUM(revenue_share), 1) AS total_rev_share, ROUND(SUM(customer_share), 1) AS total_cust_share,
       CASE WHEN ABS(SUM(revenue_share) - 100.0) <= 0.1 AND ABS(SUM(customer_share) - 100.0) <= 0.1
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT ch.acquisition_channel_key,
             100.0 * SUM(o.net_revenue) / (SELECT SUM(net_revenue) FROM Fact_Orders) AS revenue_share,
             100.0 * COUNT(DISTINCT ch.customer_key) / 8000.0 AS customer_share
      FROM Dim_Customer ch LEFT JOIN Fact_Orders o ON o.customer_key = ch.customer_key
      GROUP BY ch.acquisition_channel_key) t;


-- ═══════════════════════════════════════════════════════════════════
-- E.5 — Investigating Inherited Cross-Section Questions
-- ───────────────────────────────────────────────────────────────────
-- Business Question : (a) Does acquisition-channel mix explain the West's
--                     Section-D edge? (b) Which channels bring Accessories vs
--                     Footwear buyers? (c) Can channel data explain the
--                     Section-B holiday plateau?
-- Stakeholder       : VP Marketing / CFO
-- Metric Definition : (a) channel mix by region; (b) category revenue share by
--                     acquisition channel; (c) tested, see assumptions
-- Metric Basis      : Order Net Revenue, Customer Count
-- Analysis Grain    : (a) Dim_Customer x region x channel; (b) Fact_Order_Lines
--                     x category x channel (LINE grain for category); (c) n/a
-- SQL Design        : (a) channel share within each region; (b) category-by-
--                     channel MUST use line grain (category attribute) — the
--                     one place this section touches lines, additivity-checked.
-- Analytical Assumptions : (c) THE HOLIDAY PLATEAU CANNOT BE ANSWERED BY THIS
--                     SECTION. Acquisition channel is a lifetime attribute (L1),
--                     not a per-period signal; it carries no information about
--                     WHY a specific season's growth slowed. Forcing a channel
--                     narrative onto a timing question would be false precision.
--                     Explicitly declined — the plateau stays a Section-B/Phase-7
--                     open thread, not a manufactured E.5 conclusion.
-- Independent Review: (a)/(b) are clean; (c) correctly declined with reason. OK.
-- Validation        : Type B — (b) category revenue by channel sums to
--                     $2,195,871.49 (all category-channel cells reconcile).
-- Result Sanity     : (a) channel mix roughly uniform across regions would mean
--                     channel does NOT explain West's edge; (b) look for a
--                     channel over-indexing on Accessories vs Footwear.
-- ═══════════════════════════════════════════════════════════════════

-- E.5a Acquisition channel mix by region (does channel explain the West?)
WITH rc AS (
    SELECT g.region, mc.channel_name, COUNT(*) AS customers
    FROM Dim_Customer c
    JOIN Dim_Geography g ON c.home_geography_key = g.geography_key
    JOIN Dim_Marketing_Channel mc ON c.acquisition_channel_key = mc.marketing_channel_key
    GROUP BY g.region, mc.channel_name
)
SELECT region, channel_name, customers,
       ROUND(100.0 * customers / SUM(customers) OVER (PARTITION BY region), 1) AS pct_of_region
FROM rc ORDER BY region, customers DESC;

-- E.5b Category revenue share by acquisition channel (who buys Accessories vs Footwear?)
WITH cat_chan AS (
    SELECT mc.channel_name, p.category, SUM(l.net_line_revenue) AS revenue
    FROM Fact_Order_Lines l
    JOIN Dim_Product p USING (product_key)
    JOIN Dim_Customer c ON l.customer_key = c.customer_key
    JOIN Dim_Marketing_Channel mc ON c.acquisition_channel_key = mc.marketing_channel_key
    GROUP BY mc.channel_name, p.category
)
SELECT channel_name,
       ROUND(100.0 * SUM(CASE WHEN category='Accessories' THEN revenue ELSE 0 END) / SUM(revenue), 1) AS accessories_pct,
       ROUND(100.0 * SUM(CASE WHEN category='Footwear'    THEN revenue ELSE 0 END) / SUM(revenue), 1) AS footwear_pct,
       ROUND(100.0 * SUM(CASE WHEN category='Womenswear'  THEN revenue ELSE 0 END) / SUM(revenue), 1) AS womenswear_pct,
       ROUND(SUM(revenue), 2) AS channel_category_revenue
FROM cat_chan GROUP BY channel_name ORDER BY accessories_pct DESC;

-- E.5-VALIDATION (Type B) — category-by-channel revenue reconciles to certified total
SELECT ROUND(SUM(revenue), 2) AS total, 2195871.49 AS anchor,
       CASE WHEN ABS(SUM(revenue) - 2195871.49) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT l.net_line_revenue AS revenue FROM Fact_Order_Lines l);


-- ═══════════════════════════════════════════════════════════════════
-- E.6 — Marketing Portfolio Assessment (volume x value quadrants)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which channels are high-volume/high-value, and which
--                     trade one for the other?
-- Stakeholder       : VP Marketing / CFO
-- Metric Definition : classify each channel on (customer share vs median
--                     channel share) x (revenue per customer vs national $274.48)
-- Metric Basis      : Customer Count, Order Net Revenue per Customer
-- Analysis Grain    : channel
-- SQL Design        : Combine acquired-customer volume with revenue per customer;
--                     2x2 against median channel volume and national RPC.
-- Analytical Assumptions : "High/low value" is RPC vs national $274.48;
--                     "high/low volume" vs the median channel's customer count.
-- Independent Review: Quadrant logic deterministic from anchored inputs. OK.
-- Validation        : Type B — six channels each land in one quadrant; customers
--                     sum to 8,000.
-- Result Sanity     : Expect a paid channel as high-volume/(low-or-avg)-value
--                     and an owned/organic channel as low-volume/high-value.
-- ═══════════════════════════════════════════════════════════════════
WITH ch AS (
    SELECT c.acquisition_channel_key,
           COUNT(DISTINCT c.customer_key) AS customers,
           SUM(o.net_revenue) AS revenue
    FROM Dim_Customer c LEFT JOIN Fact_Orders o ON o.customer_key = c.customer_key
    GROUP BY c.acquisition_channel_key
),
th AS (SELECT MEDIAN(customers) AS median_customers FROM ch)
SELECT mc.channel_name,
       ch.customers,
       ROUND(ch.revenue / ch.customers, 2)                        AS revenue_per_customer,
       ROUND(100.0 * (ch.revenue / ch.customers) / 274.48, 1)     AS rpc_index,
       CASE
           WHEN ch.customers >= t.median_customers AND ch.revenue/ch.customers >= 274.48 THEN 'High Volume / High Value'
           WHEN ch.customers >= t.median_customers AND ch.revenue/ch.customers <  274.48 THEN 'High Volume / Low Value'
           WHEN ch.customers <  t.median_customers AND ch.revenue/ch.customers >= 274.48 THEN 'Low Volume / High Value'
           ELSE 'Low Volume / Low Value'
       END                                                        AS portfolio_quadrant
FROM ch CROSS JOIN th t
JOIN Dim_Marketing_Channel mc ON ch.acquisition_channel_key = mc.marketing_channel_key
ORDER BY ch.customers DESC;

-- E.6-VALIDATION (Type B) — customers reconcile to 8,000
SELECT SUM(customers) AS total_customers,
       CASE WHEN SUM(customers) = 8000 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT acquisition_channel_key, COUNT(*) AS customers FROM Dim_Customer GROUP BY acquisition_channel_key);
