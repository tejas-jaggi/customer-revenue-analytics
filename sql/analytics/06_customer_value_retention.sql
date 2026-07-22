-- ####################################################################
-- Phase 5 — SQL Analytics Layer
-- SECTION F — CUSTOMER VALUE & RETENTION ANALYSIS
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 (frozen, certified). Read-only analytics.
-- Governed by permanent rules P5-1/P5-2/P5-3 (docs/phase5_build_log.md).
--
-- PURPOSE: determine WHO creates value, why repeat customers already drive
--   82.4% of revenue (Phase 4 finding), and whether customer COMPOSITION
--   explains what Marketing (E) and Geography (D) could not.
--
-- ══ STRUCTURAL LIMITATION — PERSONAS ARE NOT STORED (ED-009, design #5) ══
--   The generation personas (Loyal VIP, Fashion Enthusiast, Bargain Hunter,
--   Seasonal Shopper, One-Time Buyer, High-Return) are computed
--   deterministically at generation time and NEVER PERSISTED — deliberately,
--   so Phase 6 must DISCOVER segments and the Phase 10 churn model cannot
--   cheat. There is no persona column in Dim_Customer or any fact (verified).
--
--   Therefore F.2/F.3 do NOT group by a stored persona (impossible). Instead
--   they build BEHAVIORAL VALUE SEGMENTS from OBSERVED data — order-frequency
--   tiers x lifetime-value tiers — which answer every underlying executive
--   question ("who creates value," "is revenue concentrated in few segments")
--   using what customers DID, not a hidden label. This is also the honest
--   preview of Phase 6 RFM, not a pre-emption of it. Where an inherited
--   question genuinely requires the unstored persona label (F.6), it is
--   explicitly DECLINED, not faked.
--
-- BASIS DISCIPLINE:
--   Order Net Revenue for reconciliation to Sections A/B ($2,195,871.49).
--   Net Revenue (after returns) for CLV / customer-value measures, per the
--   Phase 4 ruling — a customer's value must be net of returns.
--
-- ANCHORS: repeat customers = 2,851; one-time = 4,860; never-purchased = 289
--   (sum 8,000); Order Net Revenue $2,195,871.49; Net Revenue $1,782,971.91.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- F.1 — Customer Portfolio Overview
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How does the customer base split into never-purchased,
--                     one-time, and repeat — and what does each contribute?
-- Stakeholder       : CFO / Head of Retention
-- Metric Definition : per segment: customers, orders, Order Net Revenue,
--                     revenue share, and share of the customer base
-- Metric Basis      : Order Net Revenue, Customer Count
-- Analysis Grain    : Dim_Customer (base) + Fact_Orders (behavior), customer grain
-- SQL Design        : Classify each customer by lifetime order count (0 / 1 /
--                     >=2) from Fact_Orders, LEFT JOIN to keep the 289 non-
--                     purchasers. Header revenue only.
-- Analytical Assumptions : Segment by observed lifetime order count — the
--                     honest, stored-data version of "customer type."
-- Independent Review: Customer-grain classification; non-purchasers retained
--                     via LEFT JOIN; header revenue. OK.
-- Validation        : Type A — customers sum to 8,000, revenue to $2,195,871.49,
--                     repeat customers = 2,851.
-- Result Sanity     : 289 never / 4,860 one-time / 2,851 repeat; repeat is the
--                     minority of customers but the majority of revenue.
-- ═══════════════════════════════════════════════════════════════════
WITH cust AS (
    SELECT c.customer_key,
           COUNT(o.order_key) AS orders,
           COALESCE(SUM(o.net_revenue), 0) AS revenue
    FROM Dim_Customer c LEFT JOIN Fact_Orders o ON o.customer_key = c.customer_key
    GROUP BY c.customer_key
)
SELECT CASE WHEN orders = 0 THEN 'Never Purchased'
            WHEN orders = 1 THEN 'One-Time'
            ELSE 'Repeat (2+)' END                                   AS segment,
       COUNT(*)                                                      AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS pct_of_customers,
       SUM(orders)                                                  AS orders,
       ROUND(SUM(revenue), 2)                                       AS order_net_revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)   AS pct_of_revenue
FROM cust
GROUP BY 1
ORDER BY order_net_revenue DESC;

-- F.1-VALIDATION (Type A) — base, revenue, and repeat count reconcile
SELECT SUM(customers) AS total_customers,
       ROUND(SUM(revenue), 2) AS total_revenue,
       SUM(CASE WHEN seg = 'Repeat (2+)' THEN customers ELSE 0 END) AS repeat_customers,
       CASE WHEN SUM(customers) = 8000 AND ABS(SUM(revenue) - 2195871.49) <= 0.01
             AND SUM(CASE WHEN seg = 'Repeat (2+)' THEN customers ELSE 0 END) = 2851
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT CASE WHEN orders=0 THEN 'Never' WHEN orders=1 THEN 'One' ELSE 'Repeat (2+)' END AS seg,
             COUNT(*) AS customers, SUM(revenue) AS revenue
      FROM (SELECT c.customer_key, COUNT(o.order_key) AS orders, COALESCE(SUM(o.net_revenue),0) AS revenue
            FROM Dim_Customer c LEFT JOIN Fact_Orders o ON o.customer_key=c.customer_key GROUP BY c.customer_key)
      GROUP BY 1);


-- ═══════════════════════════════════════════════════════════════════
-- F.2 — Behavioral Value-Segment Performance  (persona stand-in — see header)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which BEHAVIORAL customer segments truly create value —
--                     by frequency and lifetime spend?
-- Stakeholder       : CFO / Head of Retention
-- Metric Definition : segment customers by lifetime order-frequency tier
--                     (1 / 2-3 / 4-6 / 7+ orders); per tier: customers, Net
--                     Revenue, revenue %, avg lifetime value (CLV, Net basis),
--                     avg orders, AOV, repeat rate
-- Metric Basis      : Net Revenue (CLV basis, per Phase 4 ruling), Order Net
--                     Revenue for AOV
-- Analysis Grain    : Dim_Customer + Fact_Orders + Fact_Returns (customer grain)
-- SQL Design        : Frequency tier from lifetime order count. CLV uses Net
--                     Revenue (orders minus that customer's returns). AOV uses
--                     Order Net Revenue (transaction basis). Returns joined as
--                     a per-customer scalar, never row-multiplied.
-- Analytical Assumptions : Behavioral tiers stand in for unstored personas.
--                     Frequency tiers chosen at natural apparel breakpoints
--                     (1 / occasional / regular / loyal).
-- Independent Review: Customer-grain tiers; CLV nets each customer's own
--                     returns; two bases used correctly (CLV Net, AOV Order Net). OK.
-- Validation        : Type B — tier Net Revenue sums to certified $1,782,971.91;
--                     customers to 8,000.
-- Result Sanity     : Value should rise steeply with frequency; the 7+ tier
--                     should show disproportionate CLV — the 82.4% mechanism.
-- ═══════════════════════════════════════════════════════════════════
WITH cust AS (
    SELECT c.customer_key,
           COUNT(o.order_key) AS orders,
           COALESCE(SUM(o.net_revenue), 0) AS order_net_rev,
           COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key = c.customer_key), 0) AS returns
    FROM Dim_Customer c LEFT JOIN Fact_Orders o ON o.customer_key = c.customer_key
    GROUP BY c.customer_key
)
SELECT CASE WHEN orders = 0 THEN '0 — Never'
            WHEN orders = 1 THEN '1 — One-time'
            WHEN orders BETWEEN 2 AND 3 THEN '2-3 — Occasional'
            WHEN orders BETWEEN 4 AND 6 THEN '4-6 — Regular'
            ELSE '7+ — Loyal' END                                    AS value_segment,
       COUNT(*)                                                      AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS pct_of_customers,
       ROUND(SUM(order_net_rev - returns), 2)                        AS net_revenue,
       ROUND(100.0 * SUM(order_net_rev - returns)
             / SUM(SUM(order_net_rev - returns)) OVER (), 1)         AS pct_of_net_revenue,
       ROUND(AVG(order_net_rev - returns), 2)                        AS avg_clv_net,
       ROUND(AVG(orders), 2)                                         AS avg_orders,
       ROUND(SUM(order_net_rev) / NULLIF(SUM(orders), 0), 2)         AS aov
FROM cust
GROUP BY 1 ORDER BY value_segment;

-- F.2-VALIDATION (Type B) — tier net revenue and customers reconcile
SELECT ROUND(SUM(net_rev), 2) AS total_net_revenue, SUM(customers) AS total_customers,
       CASE WHEN ABS(SUM(net_rev) - 1782971.91) <= 0.05 AND SUM(customers) = 8000
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT c.customer_key,
             COALESCE(SUM(o.net_revenue),0)
               - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key=c.customer_key),0) AS net_rev,
             1 AS customers
      FROM Dim_Customer c LEFT JOIN Fact_Orders o ON o.customer_key=c.customer_key
      GROUP BY c.customer_key);


-- ═══════════════════════════════════════════════════════════════════
-- F.3 — Customer Composition / Concentration
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Does the business depend disproportionately on a small
--                     number of high-value customers?
-- Stakeholder       : CFO
-- Metric Definition : rank customers by lifetime Net Revenue into deciles;
--                     show each decile's revenue share and cumulative share
-- Metric Basis      : Net Revenue
-- Analysis Grain    : Dim_Customer + Fact_Orders + Fact_Returns (customer grain)
-- SQL Design        : NTILE(10) over purchasing customers by lifetime net
--                     revenue; cumulative share via window. Non-purchasers
--                     excluded from deciling (0 revenue, would distort tiles)
--                     but their existence is noted. This is a CONCENTRATION
--                     curve, NOT the customer Pareto (top-20% single figure)
--                     which is reserved for Phase 6 — this shows the full
--                     distribution shape instead.
-- Analytical Assumptions : Deciles over the 7,711 purchasers. The single-figure
--                     top-20% Pareto stat is deferred to Phase 6; F.3 shows the
--                     shape that motivates it.
-- Independent Review: Customer-grain deciles; cumulative window. OK.
-- Validation        : Type B — decile net revenue sums to $1,782,971.91.
-- Result Sanity     : Top decile should hold a large share; curve steeply
--                     concave — the concentration the 82.4% figure implies.
-- ═══════════════════════════════════════════════════════════════════
WITH cust AS (
    SELECT c.customer_key,
           COALESCE(SUM(o.net_revenue),0)
             - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key=c.customer_key),0) AS net_rev
    FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key = c.customer_key
    GROUP BY c.customer_key
),
deciled AS (
    SELECT customer_key, net_rev, NTILE(10) OVER (ORDER BY net_rev DESC) AS decile FROM cust
)
SELECT decile,
       COUNT(*)                                                      AS customers,
       ROUND(SUM(net_rev), 2)                                        AS net_revenue,
       ROUND(100.0 * SUM(net_rev) / SUM(SUM(net_rev)) OVER (), 1)    AS pct_of_net_revenue,
       ROUND(100.0 * SUM(SUM(net_rev)) OVER (ORDER BY decile)
             / SUM(SUM(net_rev)) OVER (), 1)                         AS cumulative_pct
FROM deciled GROUP BY decile ORDER BY decile;

-- F.3-VALIDATION (Type B) — decile net revenue reconciles to purchasers' total
SELECT ROUND(SUM(net_rev), 2) AS purchasers_net_revenue,
       CASE WHEN ABS(SUM(net_rev) - 1782971.91) <= 0.05 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT c.customer_key,
             COALESCE(SUM(o.net_revenue),0)
               - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key=c.customer_key),0) AS net_rev
      FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key=c.customer_key GROUP BY c.customer_key);


-- ═══════════════════════════════════════════════════════════════════
-- F.4 — Repeat vs New (why repeats generate 82.4%)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : WHY do repeat customers generate 82.4% of revenue —
--                     is it more customers, more orders each, or higher AOV?
-- Stakeholder       : CFO / Head of Retention
-- Metric Definition : repeat (>=2) vs one-time: customers, orders, revenue,
--                     avg lifetime revenue, avg orders, AOV, revenue/customer
-- Metric Basis      : Order Net Revenue (share reconciles to certified 82.4%)
-- Analysis Grain    : Dim_Customer + Fact_Orders (customer grain)
-- SQL Design        : Two-way split; decompose the 82.4% into its drivers
--                     (customer count x orders-each x AOV).
-- Analytical Assumptions : Uses Order Net Revenue so the 82.4% ties to the
--                     Phase 4 finding exactly (that figure was on Order Net Rev).
-- Independent Review: Customer-grain two-way split; header revenue. OK.
-- Validation        : Type A — repeat revenue share = 82.4% (Phase 4 finding
--                     5.5), repeat customers = 2,851.
-- Result Sanity     : Repeats generate 82.4% via BOTH more orders each (~7.5
--                     vs 1) and slightly higher AOV — frequency is the driver.
-- ═══════════════════════════════════════════════════════════════════
WITH cust AS (
    SELECT customer_key, COUNT(*) AS orders, SUM(net_revenue) AS revenue
    FROM Fact_Orders GROUP BY customer_key
)
SELECT CASE WHEN orders >= 2 THEN 'Repeat (2+)' ELSE 'One-Time' END   AS segment,
       COUNT(*)                                                       AS customers,
       SUM(orders)                                                    AS total_orders,
       ROUND(SUM(revenue), 2)                                         AS order_net_revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)     AS pct_of_revenue,
       ROUND(AVG(revenue), 2)                                         AS avg_lifetime_revenue,
       ROUND(AVG(orders), 2)                                          AS avg_orders_per_customer,
       ROUND(SUM(revenue) / SUM(orders), 2)                           AS aov
FROM cust GROUP BY 1 ORDER BY order_net_revenue DESC;

-- F.4-VALIDATION (Type A) — repeat share and count reconcile to Phase 4 finding
SELECT ROUND(100.0 * SUM(CASE WHEN orders>=2 THEN revenue ELSE 0 END) / SUM(revenue), 1) AS repeat_rev_share_pct,
       SUM(CASE WHEN orders>=2 THEN 1 ELSE 0 END) AS repeat_customers,
       CASE WHEN ABS(100.0 * SUM(CASE WHEN orders>=2 THEN revenue ELSE 0 END)/SUM(revenue) - 82.4) <= 0.1
             AND SUM(CASE WHEN orders>=2 THEN 1 ELSE 0 END) = 2851
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT customer_key, COUNT(*) AS orders, SUM(net_revenue) AS revenue FROM Fact_Orders GROUP BY customer_key);


-- ═══════════════════════════════════════════════════════════════════
-- F.5 — Customer Behavior (frequency, recency, cadence, 90-day repeat)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How do customers behave — frequency, recency, time
--                     between purchases — and how many make a 2nd purchase
--                     within 90 days (a distinct retention metric)?
-- Stakeholder       : Head of Retention
-- Metric Definition : (a) recency/frequency distribution from the final
--                     snapshot; (b) 90-DAY REPEAT RATE = customers whose 2nd
--                     order is within 90 days of their 1st / customers with a
--                     1st order
-- Metric Basis      : Order Count, Customer Count, days
-- Analysis Grain    : Fact_Customer_Monthly_Snapshot (state) + Fact_Orders (timing)
-- SQL Design        : (a) reads recency/cumulative straight from the final
--                     snapshot (the table exists for exactly this). (b) computes
--                     first and second order dates from Fact_Orders and measures
--                     the gap. 90-Day Repeat Rate is a NEW metric, DISTINCT from
--                     the certified lifetime Repeat Purchase Rate (35.64%) — a
--                     90-day window, not lifetime >=2.
-- Analytical Assumptions : 90-Day Repeat Rate denominator = customers with a
--                     first order (7,711), not all 8,000 — it measures 2nd-
--                     purchase conversion among buyers. Explicitly NOT the
--                     certified lifetime rate; the two must never be conflated.
-- Independent Review: Snapshot for state, orders for timing; new metric clearly
--                     separated from the certified one. OK.
-- Validation        : Type B — 90-day rate independently bounded: must be < the
--                     lifetime repeat rate among buyers (a 90-day window can't
--                     exceed lifetime repeats). Buyer base = 7,711.
-- Result Sanity     : 90-day rate materially below the lifetime buyer-repeat
--                     rate (2,851/7,711 = 37.0%); ~24% is plausible.
-- ═══════════════════════════════════════════════════════════════════

-- F.5a Recency / frequency distribution (final snapshot)
SELECT CASE WHEN cumulative_orders_to_date = 0 THEN '0 orders'
            WHEN cumulative_orders_to_date = 1 THEN '1 order'
            WHEN cumulative_orders_to_date BETWEEN 2 AND 3 THEN '2-3 orders'
            WHEN cumulative_orders_to_date BETWEEN 4 AND 6 THEN '4-6 orders'
            ELSE '7+ orders' END                                     AS frequency_tier,
       COUNT(*)                                                      AS customers,
       ROUND(AVG(recency_days), 0)                                   AS avg_recency_days,
       COUNT(*) FILTER (WHERE is_active_flag)                        AS active_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_active_flag) / COUNT(*), 1) AS active_pct
FROM Fact_Customer_Monthly_Snapshot
WHERE snapshot_month_date_key = 20251231
GROUP BY 1 ORDER BY frequency_tier;

-- F.5b 90-Day Repeat Rate (NEW metric — distinct from certified 35.64% lifetime)
WITH first_order AS (
    SELECT o.customer_key, MIN(d.full_date) AS first_date
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    GROUP BY o.customer_key
),
second_order AS (
    SELECT fo.customer_key, MIN(d.full_date) AS second_date
    FROM first_order fo
    JOIN Fact_Orders o ON o.customer_key = fo.customer_key
    JOIN Dim_Date d ON o.order_date_key = d.date_key
    WHERE d.full_date > fo.first_date
    GROUP BY fo.customer_key
)
SELECT COUNT(DISTINCT fo.customer_key)                                                          AS customers_with_first_order,
       COUNT(DISTINCT CASE WHEN DATE_DIFF('day', fo.first_date, so.second_date) <= 90
                           THEN fo.customer_key END)                                            AS repeat_within_90d,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN DATE_DIFF('day', fo.first_date, so.second_date) <= 90
                           THEN fo.customer_key END) / COUNT(DISTINCT fo.customer_key), 1)      AS repeat_90d_rate_pct
FROM first_order fo LEFT JOIN second_order so USING (customer_key);

-- F.5-VALIDATION (Type B) — 90-day rate is bounded by lifetime buyer-repeat rate
SELECT repeat_90d_rate_pct, 37.0 AS lifetime_buyer_repeat_pct,
       CASE WHEN repeat_90d_rate_pct < 37.0 AND repeat_90d_rate_pct > 0 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (
    WITH fo AS (SELECT o.customer_key, MIN(d.full_date) fd FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key=d.date_key GROUP BY 1),
    so AS (SELECT fo.customer_key, MIN(d.full_date) sd FROM fo JOIN Fact_Orders o ON o.customer_key=fo.customer_key JOIN Dim_Date d ON o.order_date_key=d.date_key WHERE d.full_date>fo.fd GROUP BY 1)
    SELECT ROUND(100.0*COUNT(DISTINCT CASE WHEN DATE_DIFF('day',fo.fd,so.sd)<=90 THEN fo.customer_key END)/COUNT(DISTINCT fo.customer_key),1) AS repeat_90d_rate_pct
    FROM fo LEFT JOIN so USING (customer_key)
);


-- ═══════════════════════════════════════════════════════════════════
-- F.6 — Cross-Section Investigation (inherited questions)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Does customer COMPOSITION explain (a) the West's value
--                     edge, (b) Accessories affinity among high-value customers,
--                     (c) Paid Social's higher-value customers, (d) Affiliate's
--                     high repeat rate?
-- Stakeholder       : CFO / VP Marketing
-- Metric Definition : (a) high-value-customer share by region; (b) category mix
--                     of top-decile vs rest; (c) high-value-customer share by
--                     channel; (d) repeat rate by channel already in E —
--                     revisited for persona dependence
-- Metric Basis      : Net Revenue, Customer Count
-- Analysis Grain    : customer grain, joined to region/channel/category
-- SQL Design        : Define "high-value" as top-decile lifetime Net Revenue
--                     (from F.3). Compare its regional and channel distribution
--                     to the base. (b) uses LINE grain for category.
-- Analytical Assumptions : (d) PERSONA-DEPENDENCE CANNOT BE ANSWERED — persona
--                     is unstored (ED-009). We CAN show Affiliate's behavioral
--                     profile (repeat rate, frequency) but cannot attribute it
--                     to a named persona. Declined where persona is required.
-- Independent Review: High-value = top decile (consistent with F.3); category
--                     at line grain; persona questions correctly bounded. OK.
-- Validation        : Type B — high-value customers = 771 (top decile of 7,711
--                     purchasers, +/- rounding); their share reconciles.
-- Result Sanity     : If high-value customers are evenly spread across regions
--                     and channels, composition does NOT explain D/E — a
--                     legitimate (and likely) negative finding.
-- ═══════════════════════════════════════════════════════════════════

-- F.6a High-value (top-decile) customer share by region
WITH cust AS (
    SELECT c.customer_key, c.home_geography_key,
           COALESCE(SUM(o.net_revenue),0)
             - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key=c.customer_key),0) AS net_rev
    FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key=c.customer_key
    GROUP BY c.customer_key, c.home_geography_key
),
ranked AS (SELECT customer_key, home_geography_key, NTILE(10) OVER (ORDER BY net_rev DESC) AS decile FROM cust)
SELECT g.region,
       COUNT(*) FILTER (WHERE decile = 1)                            AS high_value_customers,
       COUNT(*)                                                      AS all_purchasers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE decile = 1) / COUNT(*), 1) AS high_value_pct
FROM ranked r JOIN Dim_Geography g ON r.home_geography_key = g.geography_key
GROUP BY g.region ORDER BY high_value_pct DESC;

-- F.6b High-value (top-decile) customer share by acquisition channel
WITH cust AS (
    SELECT c.customer_key, c.acquisition_channel_key,
           COALESCE(SUM(o.net_revenue),0)
             - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key=c.customer_key),0) AS net_rev
    FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key=c.customer_key
    GROUP BY c.customer_key, c.acquisition_channel_key
),
ranked AS (SELECT customer_key, acquisition_channel_key, NTILE(10) OVER (ORDER BY net_rev DESC) AS decile FROM cust)
SELECT mc.channel_name,
       COUNT(*) FILTER (WHERE decile = 1)                            AS high_value_customers,
       COUNT(*)                                                      AS all_purchasers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE decile = 1) / COUNT(*), 1) AS high_value_pct
FROM ranked r JOIN Dim_Marketing_Channel mc ON r.acquisition_channel_key = mc.marketing_channel_key
GROUP BY mc.channel_name ORDER BY high_value_pct DESC;

-- F.6c Category mix: top-decile customers vs the rest (do high-value buy Accessories?)
WITH cust AS (
    SELECT c.customer_key,
           COALESCE(SUM(o.net_revenue),0)
             - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key=c.customer_key),0) AS net_rev
    FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key=c.customer_key GROUP BY c.customer_key
),
ranked AS (SELECT customer_key, NTILE(10) OVER (ORDER BY net_rev DESC) AS decile FROM cust)
SELECT CASE WHEN r.decile = 1 THEN 'Top decile (high value)' ELSE 'Deciles 2-10' END AS customer_group,
       ROUND(100.0 * SUM(CASE WHEN p.category='Accessories' THEN l.net_line_revenue ELSE 0 END) / SUM(l.net_line_revenue), 1) AS accessories_pct,
       ROUND(100.0 * SUM(CASE WHEN p.category='Footwear'    THEN l.net_line_revenue ELSE 0 END) / SUM(l.net_line_revenue), 1) AS footwear_pct,
       ROUND(100.0 * SUM(CASE WHEN p.category='Womenswear'  THEN l.net_line_revenue ELSE 0 END) / SUM(l.net_line_revenue), 1) AS womenswear_pct
FROM ranked r
JOIN Fact_Order_Lines l ON l.customer_key = r.customer_key
JOIN Dim_Product p USING (product_key)
GROUP BY 1 ORDER BY 1;

-- F.6-VALIDATION (Type B) — top decile is ~10% of the 7,711 purchasers
SELECT COUNT(*) FILTER (WHERE decile = 1) AS top_decile_customers, COUNT(*) AS purchasers,
       CASE WHEN COUNT(*) FILTER (WHERE decile=1) BETWEEN 760 AND 775 AND COUNT(*) = 7711
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT c.customer_key, NTILE(10) OVER (ORDER BY
             COALESCE(SUM(o.net_revenue),0) - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key=c.customer_key),0) DESC) AS decile
      FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key=c.customer_key GROUP BY c.customer_key);
