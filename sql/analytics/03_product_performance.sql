-- ####################################################################
-- Phase 5 — SQL Analytics Layer
-- SECTION C — PRODUCT PERFORMANCE ANALYSIS
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 (frozen, certified). Read-only analytics.
--
-- Governed by permanent rules P5-1/P5-2/P5-3 (docs/phase5_build_log.md).
--
-- PURPOSE — the shift from Section B to Section C:
--   Section B answered "which categories drive REVENUE?" Section C answers
--   "which create VALUE?" Those rank categories DIFFERENTLY once COGS and
--   returns enter — that divergence is the entire reason this section
--   exists. Section C does NOT re-report revenue trend/growth/concentration
--   (Section B, approved); it evaluates profitability, return exposure, and
--   portfolio positioning.
--
-- SECTION SCOPE BOUNDARY:
--   Returns appear here ONLY as they bear on product profitability (return
--   rate + revenue at risk by category). The reason-code breakdown,
--   controllable-vs-not split, restocking recovery, and return timing are
--   reserved for Section G and are deliberately NOT computed here.
--
-- ANCHORS:
--   Margin       -> Section A certified Gross Margin 63.27%
--   Gross Profit -> total $1,389,245.69 (rev 2,195,871.49 - COGS 806,625.80)
--   Revenue      -> Section B / certified Order Net Revenue 2,195,871.49
--   Returns      -> certified 6,088 returned units, $412,899.58 refunded
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- C.1 — Category Profitability
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which categories generate the most PROFIT (not the
--                     most revenue), and at what margin?
-- Stakeholder       : CFO / VP Merchandising
-- Metric Definition : Gross Profit = SUM(net_line_revenue - quantity*unit_cost);
--                     Gross Margin % = Gross Profit / Revenue; Profit
--                     Contribution % = category profit / total gross profit
-- Metric Basis      : Net Line Revenue and COGS (product economics)
-- Analysis Grain    : Fact_Order_Lines (product grain — unit_cost lives here)
-- SQL Design        : Aggregate revenue and COGS at line grain per category;
--                     window SUM for profit contribution. Margin is a
--                     line-grain ratio (Phase 4 / Section A confirm the
--                     blended figure).
-- Analytical Assumptions : Gross margin is pre-returns product economics
--                     (standard COGS margin); return drag is layered in at C.4.
-- Independent Review: Line revenue and line COGS, same grain; contribution
--                     window over categories. Additive. OK.
-- Validation        : Type A — blended margin across all categories = 63.27%;
--                     total gross profit = $1,389,245.69.
-- Result Sanity     : Accessories highest margin (low COGS%), Footwear lowest
--                     (higher COGS%); profit ranking != revenue ranking.
-- ═══════════════════════════════════════════════════════════════════
SELECT p.category,
       ROUND(SUM(l.net_line_revenue), 2)                                          AS revenue,
       ROUND(SUM(l.quantity * l.unit_cost), 2)                                    AS cogs,
       ROUND(SUM(l.net_line_revenue) - SUM(l.quantity * l.unit_cost), 2)          AS gross_profit,
       ROUND(100.0 * (SUM(l.net_line_revenue) - SUM(l.quantity * l.unit_cost))
                    / SUM(l.net_line_revenue), 1)                                 AS gross_margin_pct,
       ROUND(100.0 * (SUM(l.net_line_revenue) - SUM(l.quantity * l.unit_cost))
                    / SUM(SUM(l.net_line_revenue) - SUM(l.quantity * l.unit_cost)) OVER (), 1)
                                                                                  AS profit_contribution_pct
FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key)
GROUP BY p.category ORDER BY gross_profit DESC;

-- C.1-VALIDATION (Type A) — blended margin reconciles to certified 63.27%
SELECT ROUND(100.0 * (SUM(net_line_revenue) - SUM(quantity*unit_cost)) / SUM(net_line_revenue), 2) AS blended_margin_pct,
       63.27 AS certified_anchor,
       ROUND(SUM(net_line_revenue) - SUM(quantity*unit_cost), 2) AS total_gross_profit,
       CASE WHEN ABS(100.0*(SUM(net_line_revenue)-SUM(quantity*unit_cost))/SUM(net_line_revenue) - 63.27) <= 0.01
             AND ABS((SUM(net_line_revenue)-SUM(quantity*unit_cost)) - 1389245.69) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM Fact_Order_Lines;


-- ═══════════════════════════════════════════════════════════════════
-- C.2 — Product Profitability (best and worst SKUs by profit)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which individual products create or destroy the most
--                     value — ranked by PROFIT contribution, not revenue?
-- Stakeholder       : VP Merchandising
-- Metric Definition : per product: units, revenue, gross profit, margin %;
--                     ranked by gross profit
-- Metric Basis      : Net Line Revenue and COGS
-- Analysis Grain    : Fact_Order_Lines x Dim_Product (product grain)
-- SQL Design        : Aggregate per product_key, join Dim_Product for name/
--                     category. Two result sets: top 15 and bottom 15 by
--                     gross profit. Bottom set filtered to products that
--                     actually sold (>0 units) — a never-sold SKU is a
--                     Phase-4 finding (4b.1), not a "low performer".
-- Analytical Assumptions : "Performance" = profit contribution. A low-revenue
--                     high-margin product is not a poor performer; the ranking
--                     is by absolute profit dollars, with margin shown for context.
-- Independent Review: Product-grain aggregate; no fan-out. OK.
-- Validation        : Type B — SUM of every product's gross profit across the
--                     full portfolio = total gross profit $1,389,245.69.
-- Result Sanity     : Top SKUs are higher-price or high-volume; bottom SKUs
--                     are low-volume; no product shows negative margin
--                     (unit_price >= unit_cost by product design).
-- ═══════════════════════════════════════════════════════════════════

-- C.2a Top 15 products by gross profit
SELECT p.product_key, p.product_name, p.category,
       SUM(l.quantity)                                                    AS units_sold,
       ROUND(SUM(l.net_line_revenue), 2)                                  AS revenue,
       ROUND(SUM(l.net_line_revenue) - SUM(l.quantity*l.unit_cost), 2)    AS gross_profit,
       ROUND(100.0 * (SUM(l.net_line_revenue) - SUM(l.quantity*l.unit_cost))
                    / SUM(l.net_line_revenue), 1)                         AS margin_pct
FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key)
GROUP BY p.product_key, p.product_name, p.category
ORDER BY gross_profit DESC LIMIT 15;

-- C.2b Bottom 15 products by gross profit (among products that sold)
SELECT p.product_key, p.product_name, p.category,
       SUM(l.quantity)                                                    AS units_sold,
       ROUND(SUM(l.net_line_revenue), 2)                                  AS revenue,
       ROUND(SUM(l.net_line_revenue) - SUM(l.quantity*l.unit_cost), 2)    AS gross_profit,
       ROUND(100.0 * (SUM(l.net_line_revenue) - SUM(l.quantity*l.unit_cost))
                    / SUM(l.net_line_revenue), 1)                         AS margin_pct
FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key)
GROUP BY p.product_key, p.product_name, p.category
ORDER BY gross_profit ASC LIMIT 15;

-- C.2-VALIDATION (Type B) — every product's profit sums to the total
SELECT ROUND(SUM(gp), 2) AS portfolio_gross_profit, 1389245.69 AS expected,
       CASE WHEN ABS(SUM(gp) - 1389245.69) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT product_key, SUM(net_line_revenue) - SUM(quantity*unit_cost) AS gp
      FROM Fact_Order_Lines GROUP BY product_key);


-- ═══════════════════════════════════════════════════════════════════
-- C.3 — Return Performance (product-profitability lens only)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : In which categories do returns materially erode
--                     product economics?
-- Stakeholder       : VP Merchandising / COO
-- Metric Definition : per category: return rate (units), returned units,
--                     revenue returned, and % of category revenue returned
-- Metric Basis      : Units and Return Amount
-- Analysis Grain    : Fact_Order_Lines (sold) + Fact_Returns (returned),
--                     joined to category via Dim_Product
-- SQL Design        : Two independent category aggregates (sold units/revenue;
--                     returned units/amount), joined on category. NOT a
--                     row-level orders<->returns join. LEFT JOIN so a
--                     zero-return category still appears.
-- Analytical Assumptions : SCOPE BOUNDARY — this is return performance for
--                     PRODUCT decisions only. Reason codes, controllable split,
--                     restocking recovery, and timing are Section G.
-- Independent Review: Category-level sold vs returned; no fan-out. OK.
-- Validation        : Type A — returned units sum to certified 6,088; revenue
--                     returned sums to certified $412,899.58.
-- Result Sanity     : Footwear highest (sizing), Accessories lowest (no
--                     sizing) — matches Phase 4 check 5.4 and generation design.
-- ═══════════════════════════════════════════════════════════════════
WITH sold AS (
    SELECT p.category, SUM(l.quantity) AS units_sold, SUM(l.net_line_revenue) AS revenue
    FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category
),
returned AS (
    SELECT p.category, SUM(r.return_quantity) AS units_returned, SUM(r.return_amount) AS revenue_returned
    FROM Fact_Returns r JOIN Dim_Product p USING (product_key) GROUP BY p.category
)
SELECT s.category,
       s.units_sold,
       COALESCE(rt.units_returned, 0)                                     AS units_returned,
       ROUND(100.0 * COALESCE(rt.units_returned, 0) / s.units_sold, 1)    AS return_rate_pct,
       ROUND(COALESCE(rt.revenue_returned, 0), 2)                         AS revenue_returned,
       ROUND(100.0 * COALESCE(rt.revenue_returned, 0) / s.revenue, 1)     AS pct_revenue_returned
FROM sold s LEFT JOIN returned rt USING (category)
ORDER BY return_rate_pct DESC;

-- C.3-VALIDATION (Type A) — category returns reconcile to certified totals
SELECT (SELECT SUM(return_quantity) FROM Fact_Returns)              AS total_units_returned,
       ROUND((SELECT SUM(return_amount) FROM Fact_Returns), 2)      AS total_revenue_returned,
       CASE WHEN (SELECT SUM(return_quantity) FROM Fact_Returns) = 6088
             AND ABS((SELECT SUM(return_amount) FROM Fact_Returns) - 412899.58) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END                             AS regression_result;


-- ═══════════════════════════════════════════════════════════════════
-- C.4 — Revenue vs Margin vs Returns (the value-divergence view)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Where does a category sell well but contribute
--                     relatively little PROFIT once cost and returns are
--                     accounted for?
-- Stakeholder       : CFO / VP Merchandising
-- Metric Definition : per category, side by side: revenue rank, gross profit
--                     rank, gross margin %, return rate %, and a RETURNS-
--                     ADJUSTED gross profit = gross_profit - (revenue_returned
--                     * gross_margin) [the profit actually lost when returned
--                     units are refunded, not the full refund]
-- Metric Basis      : Net Line Revenue, COGS, Return Amount
-- Analysis Grain    : Fact_Order_Lines + Fact_Returns via Dim_Product category
-- SQL Design        : Combine C.1 profit with C.3 return exposure per category.
--                     Returns-adjusted profit subtracts the MARGIN on returned
--                     revenue (COGS on a returned item is largely recovered as
--                     returned inventory; only the margin is truly lost) — an
--                     explicit, defensible approximation stated below.
-- Analytical Assumptions : Returns-adjusted profit assumes returned inventory
--                     is restockable, so only the gross MARGIN on returned
--                     revenue is lost, not the full refund. This is a
--                     product-economics approximation for ranking, not a P&L
--                     restatement; the true refund cash impact is in Section A
--                     (Net Revenue) and Section G.
-- Independent Review: Ranks derived from C.1/C.3 which are themselves
--                     anchored; adjustment is a documented approximation. OK.
-- Validation        : Type B — revenue and gross-profit columns reproduce C.1
--                     exactly (recomputed independently here).
-- Result Sanity     : Womenswear should show the widest gap between revenue
--                     rank and returns-adjusted profit rank (high return rate).
-- ═══════════════════════════════════════════════════════════════════
WITH econ AS (
    SELECT p.category,
           SUM(l.net_line_revenue) AS revenue,
           SUM(l.net_line_revenue) - SUM(l.quantity*l.unit_cost) AS gross_profit,
           (SUM(l.net_line_revenue) - SUM(l.quantity*l.unit_cost)) / SUM(l.net_line_revenue) AS margin
    FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category
),
ret AS (
    SELECT p.category, SUM(r.return_amount) AS revenue_returned, SUM(r.return_quantity) AS units_returned
    FROM Fact_Returns r JOIN Dim_Product p USING (product_key) GROUP BY p.category
),
sold AS (
    SELECT p.category, SUM(l.quantity) AS units_sold
    FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category
)
SELECT e.category,
       ROUND(e.revenue, 2)                                                        AS revenue,
       RANK() OVER (ORDER BY e.revenue DESC)                                      AS revenue_rank,
       ROUND(e.gross_profit, 2)                                                   AS gross_profit,
       RANK() OVER (ORDER BY e.gross_profit DESC)                                 AS profit_rank,
       ROUND(100.0 * e.margin, 1)                                                 AS margin_pct,
       ROUND(100.0 * COALESCE(rt.units_returned,0) / s.units_sold, 1)             AS return_rate_pct,
       ROUND(e.gross_profit - COALESCE(rt.revenue_returned,0) * e.margin, 2)      AS returns_adjusted_profit,
       RANK() OVER (ORDER BY e.gross_profit - COALESCE(rt.revenue_returned,0) * e.margin DESC)
                                                                                  AS adjusted_profit_rank
FROM econ e LEFT JOIN ret rt USING (category) JOIN sold s USING (category)
ORDER BY returns_adjusted_profit DESC;

-- C.4-VALIDATION (Type B) — independently recomputed revenue+profit = C.1 total
SELECT ROUND(SUM(revenue), 2) AS total_revenue, ROUND(SUM(gross_profit), 2) AS total_profit,
       CASE WHEN ABS(SUM(revenue) - 2195871.49) <= 0.01 AND ABS(SUM(gross_profit) - 1389245.69) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT p.category, SUM(l.net_line_revenue) AS revenue,
             SUM(l.net_line_revenue) - SUM(l.quantity*l.unit_cost) AS gross_profit
      FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category);


-- ═══════════════════════════════════════════════════════════════════
-- C.5 — Premium vs Volume Category Classification
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Does each category behave as a PREMIUM (high price,
--                     low volume) or VOLUME (low price, high volume) engine?
-- Stakeholder       : VP Merchandising
-- Metric Definition : per category: avg selling price per unit (revenue/units),
--                     units sold, and a classification derived by comparing
--                     each against the portfolio's unit-weighted averages
-- Metric Basis      : Net Line Revenue per unit, Units
-- Analysis Grain    : Fact_Order_Lines x Dim_Product
-- SQL Design        : avg_unit_price = revenue/units per category; compare to
--                     the overall avg unit price and overall avg category
--                     volume. Classify: PREMIUM (price above avg, volume below),
--                     VOLUME (price below, volume above), BALANCED otherwise.
--                     Classification is DERIVED from the data, not asserted.
-- Analytical Assumptions : Thresholds are the portfolio means (a category is
--                     premium/volume RELATIVE to Solstice's own mix, not an
--                     absolute industry benchmark).
-- Independent Review: Price and volume both from line grain; classification
--                     logic is deterministic from computed values. OK.
-- Validation        : Type B — units across categories = 36,594 total sold;
--                     revenue = 2,195,871.49.
-- Result Sanity     : Accessories = VOLUME (cheap, high units), Outerwear =
--                     PREMIUM (expensive, low units) — matches generation design.
-- ═══════════════════════════════════════════════════════════════════
WITH cat AS (
    SELECT p.category, SUM(l.net_line_revenue) AS revenue, SUM(l.quantity) AS units,
           SUM(l.net_line_revenue) / SUM(l.quantity) AS avg_unit_price
    FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category
),
benchmarks AS (
    SELECT SUM(revenue) / SUM(units) AS overall_avg_price, AVG(units) AS avg_category_units FROM cat
)
SELECT c.category,
       ROUND(c.avg_unit_price, 2)                                         AS avg_unit_price,
       c.units                                                            AS units_sold,
       ROUND(b.overall_avg_price, 2)                                      AS portfolio_avg_price,
       CASE
           WHEN c.avg_unit_price >= b.overall_avg_price AND c.units < b.avg_category_units THEN 'PREMIUM'
           WHEN c.avg_unit_price <  b.overall_avg_price AND c.units > b.avg_category_units THEN 'VOLUME'
           ELSE 'BALANCED'
       END                                                                AS classification
FROM cat c CROSS JOIN benchmarks b
ORDER BY c.avg_unit_price DESC;

-- C.5-VALIDATION (Type B) — units and revenue reconcile
SELECT SUM(units) AS total_units, ROUND(SUM(revenue), 2) AS total_revenue,
       CASE WHEN SUM(units) = 36594 AND ABS(SUM(revenue) - 2195871.49) <= 0.01
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT p.category, SUM(l.quantity) AS units, SUM(l.net_line_revenue) AS revenue
      FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category);


-- ═══════════════════════════════════════════════════════════════════
-- C.6 — Product Portfolio Assessment (revenue x margin quadrants)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which categories are high-revenue/high-margin stars,
--                     which are high-revenue/low-margin, low-revenue/high-
--                     margin, or low-revenue/low-margin?
-- Stakeholder       : CFO / VP Merchandising
-- Metric Definition : classify each category into a 2x2 on (revenue vs median
--                     category revenue) x (margin vs certified blended 63.27%)
-- Metric Basis      : Net Line Revenue, Gross Margin
-- Analysis Grain    : Fact_Order_Lines x Dim_Product
-- SQL Design        : Compare each category's revenue to the median category
--                     revenue and its margin to the 63.27% blended margin;
--                     assign a quadrant. Thresholds are the portfolio's own
--                     center, so the quadrants are relative and defensible.
-- Analytical Assumptions : "High/low margin" is relative to the blended 63.27%
--                     (the business's own average), not an external benchmark.
-- Independent Review: Quadrant logic deterministic from anchored inputs. OK.
-- Validation        : Type B — five categories each land in exactly one
--                     quadrant; revenue reconciles to 2,195,871.49.
-- Result Sanity     : Accessories = high-rev/high-margin (star); Footwear =
--                     lower-margin; no category should be low/low here.
-- ═══════════════════════════════════════════════════════════════════
WITH cat AS (
    SELECT p.category,
           SUM(l.net_line_revenue) AS revenue,
           100.0 * (SUM(l.net_line_revenue) - SUM(l.quantity*l.unit_cost)) / SUM(l.net_line_revenue) AS margin_pct
    FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category
),
thresholds AS (SELECT MEDIAN(revenue) AS median_rev FROM cat)
SELECT c.category,
       ROUND(c.revenue, 2)                                                AS revenue,
       ROUND(c.margin_pct, 1)                                            AS margin_pct,
       CASE
           WHEN c.revenue >= t.median_rev AND c.margin_pct >= 63.27 THEN 'High Revenue / High Margin'
           WHEN c.revenue >= t.median_rev AND c.margin_pct <  63.27 THEN 'High Revenue / Low Margin'
           WHEN c.revenue <  t.median_rev AND c.margin_pct >= 63.27 THEN 'Low Revenue / High Margin'
           ELSE 'Low Revenue / Low Margin'
       END                                                               AS portfolio_quadrant
FROM cat c CROSS JOIN thresholds t
ORDER BY c.revenue DESC;

-- C.6-VALIDATION (Type B) — revenue reconciles to certified total
SELECT ROUND(SUM(revenue), 2) AS total_revenue,
       CASE WHEN ABS(SUM(revenue) - 2195871.49) <= 0.01 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT p.category, SUM(l.net_line_revenue) AS revenue
      FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key) GROUP BY p.category);
