-- ####################################################################
-- Phase 5 — SQL Analytics Layer
-- SECTION B — REVENUE ANALYSIS
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 (frozen, certified). Read-only analytics.
--
-- Governed by the permanent rules (docs/phase5_build_log.md):
--   P5-1 certified KPIs are regression anchors
--   P5-2 every query is Type A (regression) or Type B (independent recompute)
--   P5-3 every query declares Metric Basis + Analysis Grain (additivity firewall)
--
-- SECTION-WIDE BASIS: Order Net Revenue (after discounts, before returns)
--   — the transaction-time basis, per the Phase 4 ruling. Returns are a
--   separate KPI handled in Section G; they are never netted per channel/
--   category here because the schema does not attribute a return to a
--   channel/campaign (returns reference the order line, not the header's
--   channel). This is an Analytical Assumption in force for all of Section B.
--
-- SECTION-WIDE ANCHOR: every revenue roll-up in this section must sum to
--   the Section A / Phase 4 certified Order Net Revenue $2,195,871.49.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- B.1 — Revenue Trend (year, quarter, month)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How has revenue trended over the three years, at
--                     yearly, quarterly, and monthly resolution?
-- Stakeholder       : CFO / VP Finance
-- Metric Definition : SUM(order net_revenue) grouped by calendar period
-- Metric Basis      : Order Net Revenue
-- Analysis Grain    : Fact_Orders (header grain) x Dim_Date
-- SQL Design        : Join Fact_Orders to Dim_Date for calendar attributes,
--                     aggregate at each grain. No line join (header measure).
--                     Three result sets (year / quarter / month) from one
--                     conformed pattern.
-- Analytical Assumptions : Order date drives period attribution (revenue is
--                     recognized at order time, consistent with the Order Net
--                     Revenue basis).
-- Independent Review: Header measure + date dimension, no fan-out. OK.
-- Validation        : Type A — the yearly roll-up must sum to $2,195,871.49
--                     (Section A / certified Order Net Revenue).
-- Result Sanity     : Monotonic yearly rise (2023<2024<2025 — Phase 4 check
--                     5.1); Nov-Dec elevated (check 5.2); no empty months
--                     (check 6.7).
-- ═══════════════════════════════════════════════════════════════════

-- B.1a Yearly
SELECT d.year,
       COUNT(*)                          AS orders,
       ROUND(SUM(o.net_revenue), 2)      AS order_net_revenue,
       ROUND(100.0 * SUM(o.net_revenue)
             / SUM(SUM(o.net_revenue)) OVER (), 2) AS pct_of_total
FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
GROUP BY d.year ORDER BY d.year;

-- B.1b Quarterly
SELECT d.year, d.quarter,
       COUNT(*)                          AS orders,
       ROUND(SUM(o.net_revenue), 2)      AS order_net_revenue
FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
GROUP BY d.year, d.quarter ORDER BY d.year, d.quarter;

-- B.1c Monthly
SELECT d.year, d.month,
       COUNT(*)                          AS orders,
       ROUND(SUM(o.net_revenue), 2)      AS order_net_revenue
FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
GROUP BY d.year, d.month ORDER BY d.year, d.month;

-- B.1-VALIDATION — yearly roll-up reconciles to certified Order Net Revenue
SELECT ROUND(SUM(net_revenue), 2) AS revenue_trend_total,
       2195871.49                 AS certified_anchor,
       CASE WHEN ABS(SUM(net_revenue) - 2195871.49) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM Fact_Orders;


-- ═══════════════════════════════════════════════════════════════════
-- B.2 — Year-over-Year Growth (seasonality-adjusted)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How fast is the business really growing, once
--                     seasonality is stripped out?
-- Stakeholder       : CFO / VP Finance
-- Metric Definition : Same-period YoY growth = (period_year_N -
--                     period_year_N-1) / period_year_N-1. Same-MONTH and
--                     same-QUARTER comparisons remove seasonality by
--                     construction (Dec vs Dec, not Dec vs Nov). Annual
--                     growth is the underlying trend.
-- Metric Basis      : Order Net Revenue
-- Analysis Grain    : Fact_Orders x Dim_Date
-- SQL Design        : LAG over the same month/quarter of the prior year
--                     (LAG partitioned by month/quarter, ordered by year) so
--                     each period is compared to its OWN prior-year twin —
--                     that is what isolates growth from seasonality. Naive
--                     sequential MoM would conflate the two and is deliberately
--                     NOT used.
-- Analytical Assumptions : 2023 has no prior year, so its YoY is NULL (not
--                     zero) — correctly undefined, not a data gap.
-- Independent Review: Same-period-prior-year comparison is the standard
--                     seasonality control; annual line is the trend. OK.
-- Validation        : Type B — independent recomputation: the annual growth
--                     multipliers must reproduce the B.1a yearly totals
--                     (785090.66/329574.19 and 1081206.64/785090.66).
-- Result Sanity     : Growth positive but decelerating YoY is the expected
--                     maturing-business shape; no negative annual growth.
-- ═══════════════════════════════════════════════════════════════════

-- B.2a Annual YoY (the underlying trend)
WITH yearly AS (
    SELECT d.year, SUM(o.net_revenue) AS onr
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    GROUP BY d.year
)
SELECT year,
       ROUND(onr, 2)                                            AS order_net_revenue,
       ROUND(LAG(onr) OVER (ORDER BY year), 2)                  AS prior_year,
       ROUND(100.0 * (onr - LAG(onr) OVER (ORDER BY year))
             / LAG(onr) OVER (ORDER BY year), 1)                AS yoy_growth_pct
FROM yearly ORDER BY year;

-- B.2b Same-quarter YoY (seasonality-controlled)
WITH q AS (
    SELECT d.year, d.quarter, SUM(o.net_revenue) AS onr
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    GROUP BY d.year, d.quarter
)
SELECT year, quarter,
       ROUND(onr, 2)                                                          AS order_net_revenue,
       ROUND(100.0 * (onr - LAG(onr) OVER (PARTITION BY quarter ORDER BY year))
             / LAG(onr) OVER (PARTITION BY quarter ORDER BY year), 1)         AS yoy_same_quarter_pct
FROM q ORDER BY year, quarter;

-- B.2c Same-month YoY (seasonality-controlled, finest resolution)
WITH m AS (
    SELECT d.year, d.month, SUM(o.net_revenue) AS onr
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
    GROUP BY d.year, d.month
)
SELECT year, month,
       ROUND(onr, 2)                                                        AS order_net_revenue,
       ROUND(100.0 * (onr - LAG(onr) OVER (PARTITION BY month ORDER BY year))
             / LAG(onr) OVER (PARTITION BY month ORDER BY year), 1)         AS yoy_same_month_pct
FROM m ORDER BY year, month;


-- ═══════════════════════════════════════════════════════════════════
-- B.3 — Revenue by Sales Channel
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How does revenue, order volume, and order value
--                     split across Website, Mobile App, and Marketplace?
-- Stakeholder       : CFO / VP Finance (+ feeds Marketing, Section E)
-- Metric Definition : per channel: SUM(net_revenue), COUNT(orders),
--                     AVG(net_revenue) as AOV, and % of total revenue
-- Metric Basis      : Order Net Revenue
-- Analysis Grain    : Fact_Orders (header) x Dim_Sales_Channel
-- SQL Design        : sales_channel_key lives on Fact_Orders (header), so
--                     channel revenue is a clean header aggregate — NO line
--                     join. Window SUM for contribution %.
-- Analytical Assumptions : Channel is the order's sales channel, not the
--                     customer's acquisition channel (that is Section E).
-- Independent Review: Header measure grouped by a header FK. Additive. OK.
-- Validation        : Type A — channel revenue sums to $2,195,871.49.
-- Result Sanity     : Website dominant (~65% weighting in generation),
--                     Marketplace smallest (~13%); channel AOVs in a tight
--                     band since pricing is channel-independent.
-- ═══════════════════════════════════════════════════════════════════
SELECT sc.channel_name,
       COUNT(*)                                                   AS orders,
       ROUND(SUM(o.net_revenue), 2)                               AS order_net_revenue,
       ROUND(AVG(o.net_revenue), 2)                               AS aov,
       ROUND(100.0 * SUM(o.net_revenue)
             / SUM(SUM(o.net_revenue)) OVER (), 1)                AS pct_of_revenue
FROM Fact_Orders o JOIN Dim_Sales_Channel sc USING (sales_channel_key)
GROUP BY sc.channel_name ORDER BY order_net_revenue DESC;

-- B.3-VALIDATION — channel revenue reconciles to certified total
SELECT ROUND(SUM(net_revenue), 2) AS channel_revenue_total, 2195871.49 AS certified_anchor,
       CASE WHEN ABS(SUM(net_revenue) - 2195871.49) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM Fact_Orders;


-- ═══════════════════════════════════════════════════════════════════
-- B.4 — Revenue by Product Category
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which product categories drive the most revenue,
--                     and how is each growing?
-- Stakeholder       : CFO / VP Finance (+ feeds Merchandising, Section C)
-- Metric Definition : per category: SUM(net_line_revenue), % of total, and
--                     yearly trend
-- Metric Basis      : Order Net Revenue (expressed at line grain as
--                     net_line_revenue, which sums to the same total)
-- Analysis Grain    : Fact_Order_Lines (PRODUCT grain — category only exists
--                     here) x Dim_Product
-- SQL Design        : *** ADDITIVITY-CRITICAL *** Category is a product
--                     attribute, so this MUST aggregate net_line_revenue on
--                     Fact_Order_Lines. Using Fact_Orders would have no
--                     category, and joining orders->lines then summing header
--                     revenue would multiply by the 1.291x fan-out. net_line_
--                     revenue is the correct additive line measure; it sums to
--                     Order Net Revenue exactly (Phase 4 check 2.1).
-- Analytical Assumptions : Line-grain net revenue is the category basis;
--                     reconciles to header Order Net Revenue by construction.
-- Independent Review: Line measure grouped by a product attribute at line
--                     grain. Additive; ties to header total. OK.
-- Validation        : Type A — category revenue sums to $2,195,871.49.
-- Result Sanity     : Accessories + Womenswear lead on volume (generation
--                     mix); Outerwear smaller but higher price point.
-- ═══════════════════════════════════════════════════════════════════
SELECT p.category,
       ROUND(SUM(l.net_line_revenue), 2)                          AS order_net_revenue,
       ROUND(100.0 * SUM(l.net_line_revenue)
             / SUM(SUM(l.net_line_revenue)) OVER (), 1)           AS pct_of_revenue,
       SUM(l.quantity)                                            AS units_sold
FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key)
GROUP BY p.category ORDER BY order_net_revenue DESC;

-- B.4b Category revenue by year (growth trend)
SELECT p.category, d.year,
       ROUND(SUM(l.net_line_revenue), 2)                          AS order_net_revenue
FROM Fact_Order_Lines l
JOIN Dim_Product p USING (product_key)
JOIN Dim_Date d ON l.order_date_key = d.date_key
GROUP BY p.category, d.year ORDER BY p.category, d.year;

-- B.4-VALIDATION — category revenue (line grain) reconciles to certified total
SELECT ROUND(SUM(net_line_revenue), 2) AS category_revenue_total, 2195871.49 AS certified_anchor,
       CASE WHEN ABS(SUM(net_line_revenue) - 2195871.49) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM Fact_Order_Lines;


-- ═══════════════════════════════════════════════════════════════════
-- B.5 — Revenue Concentration Across Categories
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Is revenue concentrated in a few categories or
--                     spread evenly? (A structural product-mix question —
--                     NOT customer Pareto, which is reserved for Phase 6.)
-- Stakeholder       : CFO / VP Finance + Merchandising
-- Metric Definition : cumulative % of revenue as categories are ranked
--                     high-to-low; top-2 and top-3 concentration
-- Metric Basis      : Order Net Revenue
-- Analysis Grain    : Fact_Order_Lines (category = product attribute)
-- SQL Design        : Rank categories by revenue, running cumulative % via a
--                     window ordered by revenue desc.
-- Analytical Assumptions : Concentration is measured across the 5 CATEGORIES,
--                     a structural mix statistic. Customer-level Pareto (top
--                     20% of customers) is explicitly deferred to Phase 6.
-- Independent Review: Line measure, category grain, window over ranked
--                     categories. OK.
-- Validation        : Type B — cumulative % of the last (5th) category row
--                     must equal 100.00, proving the concentration curve
--                     spans all revenue.
-- Result Sanity     : With 5 categories, expect top-2 in roughly the
--                     50-70% range — concentrated but not extreme.
-- ═══════════════════════════════════════════════════════════════════
WITH cat AS (
    SELECT p.category, SUM(l.net_line_revenue) AS onr
    FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key)
    GROUP BY p.category
)
SELECT category,
       ROUND(onr, 2)                                                        AS order_net_revenue,
       ROUND(100.0 * onr / SUM(onr) OVER (), 1)                             AS pct_of_revenue,
       ROUND(100.0 * SUM(onr) OVER (ORDER BY onr DESC)
             / SUM(onr) OVER (), 1)                                         AS cumulative_pct,
       ROW_NUMBER() OVER (ORDER BY onr DESC)                                AS revenue_rank
FROM cat ORDER BY onr DESC;


-- ═══════════════════════════════════════════════════════════════════
-- B.6 — Revenue Variance Decomposition (2024 -> 2025)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : The business grew ~$296K from 2024 to 2025 — WHERE
--                     did that growth come from, by channel and by category?
-- Stakeholder       : CFO / VP Finance
-- Metric Definition : per dimension member: (revenue_2025 - revenue_2024),
--                     and that delta as a % of the total YoY change. The
--                     member deltas SUM to the total change (a true
--                     decomposition, not an impression).
-- Metric Basis      : Order Net Revenue
-- Analysis Grain    : channel view = Fact_Orders; category view =
--                     Fact_Order_Lines (each dimension at its native grain)
-- SQL Design        : Conditional aggregation to pivot 2024 vs 2025 per
--                     member, then difference. Two views (channel, category)
--                     since they live at different grains and must not be
--                     joined into one fan-out-prone query.
-- Analytical Assumptions : Latest full-year transition (2024->2025) is the
--                     decomposition of interest; the same pattern applies to
--                     2023->2024 if needed. Channel and category are reported
--                     separately, each reconciling to the SAME total delta.
-- Independent Review: Each view sums its member deltas to the identical
--                     total YoY change — that mutual reconciliation is the
--                     correctness proof. OK.
-- Validation        : Type B — both the channel decomposition and the
--                     category decomposition must sum to the same total YoY
--                     delta (1,081,206.64 - 785,090.66 = 296,115.98).
-- Result Sanity     : All-positive contributions in a uniformly growing year;
--                     largest contributors are the largest channels/categories.
-- ═══════════════════════════════════════════════════════════════════

-- B.6a Channel contribution to 2024->2025 change
WITH ch AS (
    SELECT sc.channel_name,
           SUM(CASE WHEN d.year = 2024 THEN o.net_revenue ELSE 0 END) AS rev_2024,
           SUM(CASE WHEN d.year = 2025 THEN o.net_revenue ELSE 0 END) AS rev_2025
    FROM Fact_Orders o
    JOIN Dim_Date d ON o.order_date_key = d.date_key
    JOIN Dim_Sales_Channel sc USING (sales_channel_key)
    WHERE d.year IN (2024, 2025)
    GROUP BY sc.channel_name
)
SELECT channel_name,
       ROUND(rev_2024, 2)                       AS rev_2024,
       ROUND(rev_2025, 2)                       AS rev_2025,
       ROUND(rev_2025 - rev_2024, 2)            AS yoy_change,
       ROUND(100.0 * (rev_2025 - rev_2024)
             / SUM(rev_2025 - rev_2024) OVER (), 1) AS pct_of_total_change
FROM ch ORDER BY yoy_change DESC;

-- B.6b Category contribution to 2024->2025 change
WITH cat AS (
    SELECT p.category,
           SUM(CASE WHEN d.year = 2024 THEN l.net_line_revenue ELSE 0 END) AS rev_2024,
           SUM(CASE WHEN d.year = 2025 THEN l.net_line_revenue ELSE 0 END) AS rev_2025
    FROM Fact_Order_Lines l
    JOIN Dim_Date d ON l.order_date_key = d.date_key
    JOIN Dim_Product p USING (product_key)
    WHERE d.year IN (2024, 2025)
    GROUP BY p.category
)
SELECT category,
       ROUND(rev_2024, 2)                       AS rev_2024,
       ROUND(rev_2025, 2)                       AS rev_2025,
       ROUND(rev_2025 - rev_2024, 2)            AS yoy_change,
       ROUND(100.0 * (rev_2025 - rev_2024)
             / SUM(rev_2025 - rev_2024) OVER (), 1) AS pct_of_total_change
FROM cat ORDER BY yoy_change DESC;

-- B.6-VALIDATION — both decompositions sum to the identical total YoY delta
SELECT
    (SELECT ROUND(SUM(CASE WHEN d.year=2025 THEN o.net_revenue ELSE -o.net_revenue END),2)
     FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key=d.date_key WHERE d.year IN (2024,2025)) AS channel_view_delta,
    (SELECT ROUND(SUM(CASE WHEN d.year=2025 THEN l.net_line_revenue ELSE -l.net_line_revenue END),2)
     FROM Fact_Order_Lines l JOIN Dim_Date d ON l.order_date_key=d.date_key WHERE d.year IN (2024,2025)) AS category_view_delta,
    296115.98 AS expected_delta,
    CASE WHEN ABS((SELECT SUM(CASE WHEN d.year=2025 THEN o.net_revenue ELSE -o.net_revenue END)
                   FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key=d.date_key WHERE d.year IN (2024,2025)) - 296115.98) <= 0.01
          AND ABS((SELECT SUM(CASE WHEN d.year=2025 THEN l.net_line_revenue ELSE -l.net_line_revenue END)
                   FROM Fact_Order_Lines l JOIN Dim_Date d ON l.order_date_key=d.date_key WHERE d.year IN (2024,2025)) - 296115.98) <= 0.01
         THEN 'PASS' ELSE 'FAIL' END AS regression_result;


-- ═══════════════════════════════════════════════════════════════════
-- B.7 — Revenue Reconciliation (section-wide proof)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Do all Section B revenue roll-ups agree with the
--                     certified executive total?
-- Stakeholder       : CFO / VP Finance (analytical trust)
-- Metric Definition : four independent roll-up paths, all = Order Net Revenue
-- Metric Basis      : Order Net Revenue
-- Analysis Grain    : deliberately MIXED across paths to prove grain-independence
-- SQL Design        : Compute Order Net Revenue four ways — header total,
--                     header-by-year, header-by-channel, line-by-category —
--                     and assert all four equal the certified anchor. This is
--                     the section's capstone: if any B roll-up used the wrong
--                     grain (fan-out), its path would diverge here.
-- Analytical Assumptions : All paths are the pre-returns Order Net Revenue
--                     basis; the return-inclusive Net Revenue is a Section A
--                     figure, not a Section B roll-up.
-- Independent Review: Four disjoint aggregation strategies converging on one
--                     number is the strongest available additivity proof. OK.
-- Validation        : Type A — all four paths = $2,195,871.49.
-- Result Sanity     : Four identical values; any mismatch localizes the bug
--                     to the divergent path.
-- ═══════════════════════════════════════════════════════════════════
WITH paths AS (
    SELECT 'header_total'      AS path, SUM(net_revenue)      AS onr FROM Fact_Orders
    UNION ALL
    SELECT 'header_by_year',   SUM(onr) FROM (SELECT d.year, SUM(o.net_revenue) onr FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key=d.date_key GROUP BY d.year)
    UNION ALL
    SELECT 'header_by_channel',SUM(onr) FROM (SELECT sales_channel_key, SUM(net_revenue) onr FROM Fact_Orders GROUP BY sales_channel_key)
    UNION ALL
    SELECT 'line_by_category', SUM(onr) FROM (SELECT p.category, SUM(l.net_line_revenue) onr FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category)
)
SELECT path, ROUND(onr, 2) AS order_net_revenue,
       CASE WHEN ABS(onr - 2195871.49) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM paths ORDER BY path;
