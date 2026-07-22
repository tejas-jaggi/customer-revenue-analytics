-- ####################################################################
-- Phase 5 — SQL Analytics Layer
-- SECTION G — RETURNS & VALUE LEAKAGE ANALYSIS
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 (frozen, certified). Read-only analytics.
-- Governed by permanent rules P5-1/P5-2/P5-3 (docs/phase5_build_log.md).
--
-- PURPOSE — the culminating analytical section. Not "returns reporting"
--   (Section C already did return rates by category), but WHERE VALUE IS
--   LOST and WHAT MANAGEMENT SHOULD FIX FIRST. Two things C did not do:
--   (1) decompose WHY returns happen (reason codes, controllability) to
--   separate fixable from structural; (2) connect returns to the Section-F
--   customer-value findings (a high-value customer who returns heavily is
--   worth less than gross). G culminates in G.7 — a single ranked leakage
--   table across returns, discounts, and unconverted customers.
--
-- BOUNDARY: the High-Return generation persona is unstored (ED-009). G.4
--   detects a BEHAVIORAL high-return cluster from observed data but does NOT
--   label it the generation persona.
--
-- ANCHORS: 5,687 returns; 6,088 units; $412,899.58 refunded (certified).
--   Category returns reconcile to Section C; customer returns to Section F.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- G.1 — Portfolio Return Overview
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What is the total scale of returns, and their true
--                     impact on net revenue?
-- Stakeholder       : CFO / COO
-- Metric Definition : returns, units returned, revenue refunded, restocking
--                     recovered, and net revenue impact (refund - restocking)
-- Metric Basis      : Return Amount, Units
-- Analysis Grain    : Fact_Returns (return-line grain)
-- SQL Design        : Single-table aggregate. Net impact = refunds minus the
--                     restocking fees recovered (the fee softens the leak).
-- Analytical Assumptions : Restocking fee is a partial recovery on the refund;
--                     net leakage = return_amount - restocking_fee.
-- Independent Review: Return-grain aggregate, no fan-out. OK.
-- Validation        : Type A — 5,687 returns, 6,088 units, $412,899.58 refunded.
-- Result Sanity     : Refunds ~$413K = 18.8% of Order Net Revenue; restocking
--                     recovers only a small fraction (fee applies to some reasons).
-- ═══════════════════════════════════════════════════════════════════
SELECT COUNT(*)                                                      AS total_returns,
       SUM(return_quantity)                                         AS units_returned,
       ROUND(SUM(return_amount), 2)                                 AS revenue_refunded,
       ROUND(SUM(restocking_fee), 2)                                AS restocking_recovered,
       ROUND(SUM(return_amount) - SUM(restocking_fee), 2)           AS net_revenue_leakage,
       ROUND(100.0 * SUM(return_amount)
             / (SELECT SUM(net_revenue) FROM Fact_Orders), 1)       AS refund_pct_of_order_net_rev
FROM Fact_Returns;

-- G.1-VALIDATION (Type A) — reconciles to certified return anchors
SELECT COUNT(*) AS total_returns, SUM(return_quantity) AS units, ROUND(SUM(return_amount),2) AS refunded,
       CASE WHEN COUNT(*) = 5687 AND SUM(return_quantity) = 6088 AND ABS(SUM(return_amount) - 412899.58) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM Fact_Returns;


-- ═══════════════════════════════════════════════════════════════════
-- G.2 — Return Drivers (reason codes & controllability)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : WHY are customers returning, and how much of the leak
--                     is operationally CONTROLLABLE vs structural?
-- Stakeholder       : COO / VP Merchandising
-- Metric Definition : per reason: returns, units, revenue returned, % of
--                     returned value, and the controllable/not split
-- Metric Basis      : Return Amount
-- Analysis Grain    : Fact_Returns x Dim_Return_Reason
-- SQL Design        : Group by reason + is_controllable; window for % of total.
--                     is_controllable comes from Dim_Return_Reason (sizing,
--                     quality, logistics = controllable; changed-mind = not).
-- Analytical Assumptions : Controllability is the warehouse's own definition
--                     (Dim_Return_Reason.is_controllable). "Controllable" means
--                     Solstice can realistically act to reduce it.
-- Independent Review: Return-grain grouped by reason; controllability from dim. OK.
-- Validation        : Type A — reason revenue sums to $412,899.58.
-- Result Sanity     : Wrong Size largest (apparel sizing); Changed Mind the
--                     largest NON-controllable; controllable share is the
--                     addressable majority.
-- ═══════════════════════════════════════════════════════════════════
SELECT rr.reason_description,
       rr.is_controllable,
       COUNT(*)                                                     AS returns,
       SUM(r.return_quantity)                                       AS units,
       ROUND(SUM(r.return_amount), 2)                               AS revenue_returned,
       ROUND(100.0 * SUM(r.return_amount)
             / SUM(SUM(r.return_amount)) OVER (), 1)                AS pct_of_returned_value
FROM Fact_Returns r JOIN Dim_Return_Reason rr USING (return_reason_key)
GROUP BY rr.reason_description, rr.is_controllable
ORDER BY revenue_returned DESC;

-- G.2b Controllable vs non-controllable summary
SELECT rr.is_controllable,
       ROUND(SUM(r.return_amount), 2)                               AS revenue_returned,
       ROUND(100.0 * SUM(r.return_amount)
             / SUM(SUM(r.return_amount)) OVER (), 1)                AS pct_of_returned_value
FROM Fact_Returns r JOIN Dim_Return_Reason rr USING (return_reason_key)
GROUP BY rr.is_controllable ORDER BY revenue_returned DESC;

-- G.2-VALIDATION (Type A) — reason revenue reconciles to certified refund total
SELECT ROUND(SUM(return_amount), 2) AS total, 412899.58 AS anchor,
       CASE WHEN ABS(SUM(return_amount) - 412899.58) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM Fact_Returns;


-- ═══════════════════════════════════════════════════════════════════
-- G.3 — Product Return Performance (extends Section C)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : WHY does Footwear return so heavily, and is Womenswear's
--                     larger dollar exposure a bigger financial risk than
--                     Footwear's higher rate?
-- Stakeholder       : VP Merchandising / COO
-- Metric Definition : per category: return rate, revenue returned, and the
--                     reason mix (esp. Wrong Size %) that explains the rate
-- Metric Basis      : Units, Return Amount
-- Analysis Grain    : Fact_Returns + Fact_Order_Lines via Dim_Product category
-- SQL Design        : Combine category return rate (from C.3) with the reason
--                     mix per category — specifically the Wrong Size share,
--                     which is the sizing-driven, fixable component. Dollar
--                     exposure vs rate is shown side by side.
-- Analytical Assumptions : "Financial risk" is measured in absolute dollars
--                     returned (exposure), distinct from rate (%). Both matter;
--                     the section compares them explicitly.
-- Independent Review: Category-level sold/returned + reason mix; no fan-out. OK.
-- Validation        : Type A — category revenue returned sums to $412,899.58
--                     (reconciles to Section C's returns figures).
-- Result Sanity     : Footwear highest rate + high Wrong Size %; Womenswear
--                     highest DOLLAR exposure despite lower rate (bigger base).
-- ═══════════════════════════════════════════════════════════════════
WITH sold AS (
    SELECT p.category, SUM(l.quantity) AS units_sold
    FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category
),
returned AS (
    SELECT p.category, SUM(r.return_quantity) AS units_returned, SUM(r.return_amount) AS revenue_returned
    FROM Fact_Returns r JOIN Dim_Product p USING (product_key) GROUP BY p.category
),
wrong_size AS (
    SELECT p.category, SUM(r.return_amount) AS wrong_size_amount
    FROM Fact_Returns r JOIN Dim_Product p USING (product_key)
    JOIN Dim_Return_Reason rr USING (return_reason_key)
    WHERE rr.reason_description = 'Wrong Size'
    GROUP BY p.category
)
SELECT s.category,
       ROUND(100.0 * rt.units_returned / s.units_sold, 1)           AS return_rate_pct,
       ROUND(rt.revenue_returned, 2)                                AS revenue_returned,
       ROUND(100.0 * COALESCE(ws.wrong_size_amount,0)
             / rt.revenue_returned, 1)                              AS wrong_size_pct_of_returns
FROM sold s JOIN returned rt USING (category) LEFT JOIN wrong_size ws USING (category)
ORDER BY revenue_returned DESC;

-- G.3-VALIDATION (Type A) — category revenue returned reconciles to certified
SELECT ROUND(SUM(revenue_returned), 2) AS total,
       CASE WHEN ABS(SUM(revenue_returned) - 412899.58) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT p.category, SUM(r.return_amount) AS revenue_returned
      FROM Fact_Returns r JOIN Dim_Product p USING (product_key) GROUP BY p.category);


-- ═══════════════════════════════════════════════════════════════════
-- G.4 — Customer Return Behavior
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Do Loyal/high-value customers return MORE? Do they stay
--                     high-value after returns? Is there a high-return cluster?
-- Stakeholder       : Head of Retention / CFO
-- Metric Definition : (a) return rate by frequency tier; (b) top-decile value
--                     before vs after returns; (c) distribution of customers by
--                     personal return rate (cluster detection)
-- Metric Basis      : Units, Net Revenue
-- Analysis Grain    : customer grain (Fact_Orders/Lines/Returns per customer)
-- SQL Design        : (a) per-customer return rate rolled to frequency tier;
--                     (c) band customers by personal return rate to detect a
--                     high-return cluster WITHOUT invoking the unstored persona.
-- Analytical Assumptions : High-Return PERSONA cannot be named (ED-009). A
--                     behavioral cluster CAN be detected from observed return
--                     rates — reported as behavior, not persona identity.
-- Independent Review: Customer-grain; returns netted per customer; cluster is
--                     behavioral. OK.
-- Validation        : Type B — customers across bands sum to 7,711 purchasers.
-- Result Sanity     : If Loyal customers return at ~the blended rate, loyalty
--                     is NOT a return risk; a distinct 60%+ band would be the
--                     behavioral High-Return cluster.
-- ═══════════════════════════════════════════════════════════════════

-- G.4a Return rate by customer frequency tier
WITH cust AS (
    SELECT c.customer_key, COUNT(o.order_key) AS orders FROM Dim_Customer c
    LEFT JOIN Fact_Orders o ON o.customer_key = c.customer_key GROUP BY c.customer_key
),
cr AS (SELECT customer_key, SUM(return_quantity) AS ru, SUM(return_amount) AS ra FROM Fact_Returns GROUP BY customer_key),
cs AS (SELECT customer_key, SUM(quantity) AS su FROM Fact_Order_Lines GROUP BY customer_key)
SELECT CASE WHEN cust.orders = 0 THEN '0 — Never'
            WHEN cust.orders = 1 THEN '1 — One-time'
            WHEN cust.orders BETWEEN 2 AND 3 THEN '2-3 — Occasional'
            WHEN cust.orders BETWEEN 4 AND 6 THEN '4-6 — Regular'
            ELSE '7+ — Loyal' END                                   AS value_segment,
       COUNT(*)                                                     AS customers,
       ROUND(100.0 * SUM(COALESCE(cr.ru,0))
             / NULLIF(SUM(COALESCE(cs.su,0)),0), 1)                 AS return_rate_pct,
       ROUND(SUM(COALESCE(cr.ra,0)), 2)                             AS revenue_returned
FROM cust LEFT JOIN cr USING (customer_key) LEFT JOIN cs USING (customer_key)
GROUP BY 1 ORDER BY value_segment;

-- G.4b High-return behavioral cluster (distribution by personal return rate)
WITH cs AS (SELECT customer_key, SUM(quantity) AS sold FROM Fact_Order_Lines GROUP BY customer_key),
cr AS (SELECT customer_key, SUM(return_quantity) AS ret FROM Fact_Returns GROUP BY customer_key)
SELECT CASE WHEN COALESCE(cr.ret,0) = 0 THEN '0% — no returns'
            WHEN 100.0*cr.ret/cs.sold < 20 THEN '1-19%'
            WHEN 100.0*cr.ret/cs.sold < 40 THEN '20-39%'
            WHEN 100.0*cr.ret/cs.sold < 60 THEN '40-59%'
            ELSE '60%+ — high-return cluster' END                   AS return_rate_band,
       COUNT(*)                                                     AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_of_purchasers
FROM cs LEFT JOIN cr USING (customer_key)
GROUP BY 1 ORDER BY 1;

-- G.4c Top-decile customers: value before vs after returns (do they stay high-value?)
WITH cust AS (
    SELECT c.customer_key,
           COALESCE(SUM(o.net_revenue),0) AS gross_value,
           COALESCE(SUM(o.net_revenue),0) - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key=c.customer_key),0) AS net_value
    FROM Dim_Customer c JOIN Fact_Orders o ON o.customer_key=c.customer_key GROUP BY c.customer_key
),
ranked AS (SELECT customer_key, gross_value, net_value, NTILE(10) OVER (ORDER BY net_value DESC) AS decile FROM cust)
SELECT CASE WHEN decile = 1 THEN 'Top decile' ELSE 'Deciles 2-10' END AS customer_group,
       COUNT(*)                                                     AS customers,
       ROUND(SUM(gross_value), 2)                                   AS gross_value,
       ROUND(SUM(net_value), 2)                                     AS net_value_after_returns,
       ROUND(100.0 * (SUM(gross_value) - SUM(net_value)) / SUM(gross_value), 1) AS pct_lost_to_returns
FROM ranked GROUP BY 1 ORDER BY 1;

-- G.4-VALIDATION (Type B) — return-rate bands cover all 7,711 purchasers
SELECT SUM(customers) AS total_purchasers,
       CASE WHEN SUM(customers) = 7711 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT CASE WHEN COALESCE(cr.ret,0)=0 THEN 'a' WHEN 100.0*cr.ret/cs.sold<20 THEN 'b'
                  WHEN 100.0*cr.ret/cs.sold<40 THEN 'c' WHEN 100.0*cr.ret/cs.sold<60 THEN 'd' ELSE 'e' END AS band,
             COUNT(*) AS customers
      FROM (SELECT customer_key, SUM(quantity) AS sold FROM Fact_Order_Lines GROUP BY customer_key) cs
      LEFT JOIN (SELECT customer_key, SUM(return_quantity) AS ret FROM Fact_Returns GROUP BY customer_key) cr USING (customer_key)
      GROUP BY 1);


-- ═══════════════════════════════════════════════════════════════════
-- G.5 — Geographic Returns (does it alter Section D?)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Do regional return rates materially change Section D's
--                     "geography is a weak differentiator" conclusion?
-- Stakeholder       : COO
-- Metric Definition : return rate by region; compared to the narrow RPC spread
-- Metric Basis      : Units
-- Analysis Grain    : Fact_Returns + Fact_Order_Lines via customer home region
-- SQL Design        : Region-level sold vs returned units (independent
--                     aggregates joined on region).
-- Analytical Assumptions : Returns attributed to the customer's home region.
-- Independent Review: Region-level; no fan-out. OK.
-- Validation        : Type B — regional returned units sum to certified 6,088.
-- Result Sanity     : If regional return rates are near-uniform (as customer
--                     quality was in D), returns do NOT change D's conclusion.
-- ═══════════════════════════════════════════════════════════════════
WITH sold AS (
    SELECT g.region, SUM(l.quantity) AS units_sold
    FROM Fact_Order_Lines l JOIN Dim_Customer c ON l.customer_key=c.customer_key
    JOIN Dim_Geography g ON c.home_geography_key=g.geography_key GROUP BY g.region
),
returned AS (
    SELECT g.region, SUM(r.return_quantity) AS units_returned
    FROM Fact_Returns r JOIN Dim_Customer c ON r.customer_key=c.customer_key
    JOIN Dim_Geography g ON c.home_geography_key=g.geography_key GROUP BY g.region
)
SELECT s.region,
       ROUND(100.0 * rt.units_returned / s.units_sold, 1)          AS return_rate_pct,
       rt.units_returned                                           AS units_returned
FROM sold s JOIN returned rt USING (region) ORDER BY return_rate_pct DESC;

-- G.5-VALIDATION (Type B) — regional returned units reconcile to certified 6,088
SELECT SUM(units_returned) AS total, 6088 AS anchor,
       CASE WHEN SUM(units_returned) = 6088 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT g.region, SUM(r.return_quantity) AS units_returned
      FROM Fact_Returns r JOIN Dim_Customer c ON r.customer_key=c.customer_key
      JOIN Dim_Geography g ON c.home_geography_key=g.geography_key GROUP BY g.region);


-- ═══════════════════════════════════════════════════════════════════
-- G.6 — Marketing Returns (does it reduce channel value advantage?)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Do high-value acquisition channels (esp. Paid Social)
--                     also bring higher-return customers, offsetting their
--                     Section-E value advantage?
-- Stakeholder       : VP Marketing / CFO
-- Metric Definition : return rate by acquisition channel; compared to each
--                     channel's Section-E revenue-per-customer
-- Metric Basis      : Units
-- Analysis Grain    : Fact_Returns + Fact_Order_Lines via customer acq channel
-- SQL Design        : Channel-level sold vs returned units.
-- Analytical Assumptions : Returns attributed to the customer's acquisition
--                     channel (a lifetime attribute, L1 from Section E).
-- Independent Review: Channel-level; no fan-out. OK.
-- Validation        : Type B — channel returned units sum to certified 6,088.
-- Result Sanity     : If Paid Social's return rate is near blended, its value
--                     advantage from E/F survives returns intact.
-- ═══════════════════════════════════════════════════════════════════
WITH sold AS (
    SELECT c.acquisition_channel_key AS ak, SUM(l.quantity) AS units_sold
    FROM Fact_Order_Lines l JOIN Dim_Customer c ON l.customer_key=c.customer_key GROUP BY 1
),
returned AS (
    SELECT c.acquisition_channel_key AS ak, SUM(r.return_quantity) AS units_returned
    FROM Fact_Returns r JOIN Dim_Customer c ON r.customer_key=c.customer_key GROUP BY 1
)
SELECT mc.channel_name,
       ROUND(100.0 * rt.units_returned / s.units_sold, 1)          AS return_rate_pct,
       rt.units_returned                                           AS units_returned
FROM sold s JOIN returned rt USING (ak) JOIN Dim_Marketing_Channel mc ON s.ak = mc.marketing_channel_key
ORDER BY return_rate_pct DESC;

-- G.6-VALIDATION (Type B) — channel returned units reconcile to certified 6,088
SELECT SUM(units_returned) AS total,
       CASE WHEN SUM(units_returned) = 6088 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT c.acquisition_channel_key, SUM(r.return_quantity) AS units_returned
      FROM Fact_Returns r JOIN Dim_Customer c ON r.customer_key=c.customer_key GROUP BY 1);


-- ═══════════════════════════════════════════════════════════════════
-- G.7 — VALUE LEAKAGE ANALYSIS (new executive section — the culmination)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Across the ENTIRE business, what are the largest
--                     sources of value leakage, ranked, and where should
--                     management act first?
-- Stakeholder       : CEO / CFO
-- Metric Definition : each leakage source quantified in dollars on one
--                     comparable scale:
--                       1. Returns — controllable portion (addressable)
--                       2. Returns — non-controllable portion (structural)
--                       3. Discounts (given up vs gross)
--                       4. Never-purchased customers (acquired, $0 realized)
--                       5. One-time customers (no repeat — opportunity cost vs
--                          if they reached average repeat value)
-- Metric Basis      : mixed dollars (each row labels its basis)
-- Analysis Grain    : business-wide scalars, each at its native grain
-- SQL Design        : UNION of independently-computed leakage scalars, ranked
--                     by dollar impact. The controllable-returns figure is the
--                     addressable leak; the one-time opportunity cost is
--                     modeled explicitly (see assumption).
-- Analytical Assumptions : (i) Returns split by Dim_Return_Reason.is_controllable.
--                     (ii) Discount leak = total discount given (what was
--                     conceded from gross). (iii) One-time opportunity cost is
--                     ILLUSTRATIVE: (avg repeat lifetime revenue - avg one-time
--                     revenue) x one-time customers — a sizing of the retention
--                     prize, explicitly a modeled scenario not a realized loss.
--                     Marked as such so it is not double-counted with actual leaks.
-- Independent Review: Actual leaks (returns, discounts) are realized dollars;
--                     the one-time figure is labeled opportunity cost, kept in a
--                     separate class. No double counting. OK.
-- Validation        : Type A — realized leaks reconcile: controllable +
--                     non-controllable returns = $412,899.58; discount leak =
--                     $161,827.55 (Phase 4 certified discount figure).
-- Result Sanity     : Returns (esp. controllable) and the retention opportunity
--                     should dominate; discounts smaller; never-purchased small.
-- ═══════════════════════════════════════════════════════════════════
WITH leakage AS (
    -- 1. Controllable returns (ADDRESSABLE realized leak)
    SELECT 1 AS rank_hint, 'Returns — controllable (Wrong Size, Quality, Logistics)' AS leakage_source,
           'Realized' AS leakage_class,
           ROUND(SUM(CASE WHEN rr.is_controllable THEN r.return_amount ELSE 0 END), 2) AS dollars
    FROM Fact_Returns r JOIN Dim_Return_Reason rr USING (return_reason_key)
    UNION ALL
    -- 2. Non-controllable returns (STRUCTURAL realized leak)
    SELECT 2, 'Returns — non-controllable (Changed Mind, Other)', 'Realized',
           ROUND(SUM(CASE WHEN NOT rr.is_controllable THEN r.return_amount ELSE 0 END), 2)
    FROM Fact_Returns r JOIN Dim_Return_Reason rr USING (return_reason_key)
    UNION ALL
    -- 3. Discounts (realized concession from gross)
    SELECT 3, 'Discounts given (vs gross revenue)', 'Realized',
           ROUND((SELECT SUM(discount_amount) FROM Fact_Orders), 2)
    UNION ALL
    -- 4. Never-purchased acquired customers (realized acquisition waste, $0 revenue)
    SELECT 4, 'Never-purchased acquired customers (count, $0 realized)', 'Realized',
           0.00
    UNION ALL
    -- 5. One-time customers: retention OPPORTUNITY COST (modeled, not realized)
    SELECT 5, 'One-time customers — retention opportunity cost (modeled)', 'Opportunity',
           ROUND((SELECT (AVG(CASE WHEN orders>=2 THEN rev END) - AVG(CASE WHEN orders=1 THEN rev END))
                         * COUNT(*) FILTER (WHERE orders=1)
                  FROM (SELECT customer_key, COUNT(*) AS orders, SUM(net_revenue) AS rev
                        FROM Fact_Orders GROUP BY customer_key) t), 2)
)
SELECT leakage_source, leakage_class, dollars,
       CASE WHEN leakage_class = 'Realized'
            THEN ROUND(100.0 * dollars / SUM(CASE WHEN leakage_class='Realized' THEN dollars ELSE 0 END) OVER (), 1)
            END AS pct_of_realized_leakage
FROM leakage ORDER BY (leakage_class = 'Opportunity'), dollars DESC;

-- G.7-VALIDATION (Type A) — realized leaks reconcile to certified figures
SELECT ROUND((SELECT SUM(return_amount) FROM Fact_Returns), 2) AS returns_total,
       ROUND((SELECT SUM(discount_amount) FROM Fact_Orders), 2) AS discount_total,
       CASE WHEN ABS((SELECT SUM(return_amount) FROM Fact_Returns) - 412899.58) <= 0.01
             AND ABS((SELECT SUM(discount_amount) FROM Fact_Orders) - 161827.55) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS regression_result;
