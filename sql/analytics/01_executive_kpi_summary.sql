-- ####################################################################
-- Phase 5 — SQL Analytics Layer
-- SECTION A — EXECUTIVE KPI SUMMARY
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 (frozen, certified). Read-only analytics.
--
-- PURPOSE
--   A concise executive dashboard of overall business health. This
--   section is the ANALYTICAL REGRESSION BASELINE for all of Phase 5:
--   every KPI here reproduces a Phase 4 certified value EXACTLY, so the
--   rest of the analytics layer can trust these figures as anchors.
--
-- PERMANENT RULES IN FORCE (see docs/phase5_build_log.md)
--   P5-1  Certified KPIs are regression anchors; any mismatch is a defect
--         in the analytical SQL until proven otherwise.
--   P5-2  Every query carries exactly one validation: Type A (regression
--         vs certified anchor) or Type B (independent recomputation).
--   P5-3  Every query declares Metric Basis and Analysis Grain — the
--         additivity firewall against the 1.291x Orders->Lines fan-out.
--
-- CERTIFIED ANCHORS (docs/phase4_validation_report.md, Tier 3)
--   Order Net Revenue    $2,195,871.49
--   Net Revenue          $1,782,971.91
--   Gross Margin %        63.27%
--   AOV                  $83.50
--   Discount Impact %      6.86%
--   Return Rate %         16.64%
--   Repeat Purchase Rate  35.64%
--
-- Every KPI in this section is Type A (Regression) by definition — that
-- is what makes it the baseline. Precision: cent for money, 0.01pp rates.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- A.1 — Order Net Revenue
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What total revenue did Solstice transact across
--                     three years, at the point of sale (after discounts,
--                     before returns)?
-- Stakeholder       : CFO / VP Finance
-- Metric Definition : SUM(order net_revenue) = SUM(gross_revenue - discount_amount)
-- Metric Basis      : Order Net Revenue
-- Analysis Grain    : Fact_Orders (header grain — one row per order)
-- SQL Design        : Single-table aggregate over Fact_Orders. NO join to
--                     Fact_Order_Lines — that would multiply header revenue
--                     by the 1.291x fan-out (Phase 4 check 6.8). net_revenue
--                     already lives at header grain.
-- Analytical Assumptions : "Order Net Revenue" is the transaction-time basis
--                     defined in business_understanding.md; returns are a
--                     separate KPI (A.6), never netted here.
-- Independent Review: Header grain + header measure + no fan-out join = additive. OK.
-- Validation        : Type A — anchor $2,195,871.49.
-- Result Sanity     : Should equal header net and line net (all three tie
--                     out per Phase 4 check 2.1); positive; ~$2.2M over 3yr.
-- ═══════════════════════════════════════════════════════════════════
SELECT
    ROUND(SUM(net_revenue), 2)                                  AS order_net_revenue,
    2195871.49                                                  AS certified_anchor,
    CASE WHEN ABS(SUM(net_revenue) - 2195871.49) <= 0.01
         THEN 'PASS' ELSE 'FAIL' END                            AS regression_result
FROM Fact_Orders;


-- ═══════════════════════════════════════════════════════════════════
-- A.2 — Net Revenue (after returns)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What revenue did Solstice actually keep after
--                     customers returned product?
-- Stakeholder       : CFO / VP Finance
-- Metric Definition : SUM(order net_revenue) - SUM(return_amount)
-- Metric Basis      : Net Revenue
-- Analysis Grain    : Fact_Orders (+ Fact_Returns aggregate, both header/
--                     return grain — combined as two scalars, not a row join)
-- SQL Design        : Two independent scalar aggregates subtracted. Returns
--                     are summed on Fact_Returns alone, NOT joined row-wise
--                     to orders, so no fan-out is possible.
-- Analytical Assumptions : restocking_fee is NOT added back — the KPI table
--                     defines Net Revenue as "Order Net Revenue - returns";
--                     the fee is a separate recovery, out of scope for this KPI.
-- Independent Review: Two disjoint scalars; subtraction cannot double-count. OK.
-- Validation        : Type A — anchor $1,782,971.91.
-- Result Sanity     : Must be < Order Net Revenue by exactly total returns
--                     ($412,899.58); must equal snapshot final-month revenue
--                     (Phase 4 check 3.1 ties all three paths).
-- ═══════════════════════════════════════════════════════════════════
SELECT
    ROUND((SELECT SUM(net_revenue) FROM Fact_Orders)
        - (SELECT SUM(return_amount) FROM Fact_Returns), 2)     AS net_revenue,
    1782971.91                                                  AS certified_anchor,
    CASE WHEN ABS(((SELECT SUM(net_revenue) FROM Fact_Orders)
        - (SELECT SUM(return_amount) FROM Fact_Returns)) - 1782971.91) <= 0.01
         THEN 'PASS' ELSE 'FAIL' END                            AS regression_result;


-- ═══════════════════════════════════════════════════════════════════
-- A.3 — Gross Margin %
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What percentage of product revenue is gross profit,
--                     after cost of goods?
-- Stakeholder       : CFO / VP Finance
-- Metric Definition : (SUM(net_line_revenue) - SUM(quantity*unit_cost))
--                     / SUM(net_line_revenue) * 100
-- Metric Basis      : Net Line Revenue and COGS (product economics)
-- Analysis Grain    : Fact_Order_Lines (product grain — margin only exists here)
-- SQL Design        : Margin REQUIRES the line grain: unit_cost and quantity
--                     live on Fact_Order_Lines, not the header. This is the
--                     one executive KPI that must be computed on lines, and
--                     doing so is correct (not a fan-out error) because both
--                     numerator and denominator are line-grain measures.
-- Analytical Assumptions : Gross margin is computed BEFORE returns, on sold
--                     product economics — the standard COGS margin. A
--                     returns-adjusted margin is a distinct metric (out of scope).
-- Independent Review: Line grain + line measures (revenue & cost) = additive. OK.
-- Validation        : Type A — anchor 63.27%.
-- Result Sanity     : Apparel gross margins commonly 55-70%; 63.27% is
--                     squarely plausible; must be positive and < 100%.
-- ═══════════════════════════════════════════════════════════════════
SELECT
    ROUND(100.0 * (SUM(net_line_revenue) - SUM(quantity * unit_cost))
                / SUM(net_line_revenue), 2)                     AS gross_margin_pct,
    63.27                                                       AS certified_anchor,
    CASE WHEN ABS(100.0 * (SUM(net_line_revenue) - SUM(quantity * unit_cost))
                / SUM(net_line_revenue) - 63.27) <= 0.01
         THEN 'PASS' ELSE 'FAIL' END                            AS regression_result
FROM Fact_Order_Lines;


-- ═══════════════════════════════════════════════════════════════════
-- A.4 — Average Order Value (AOV)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What is the average value of an order at the point
--                     of sale?
-- Stakeholder       : CFO / VP Finance
-- Metric Definition : Order Net Revenue / Total Orders
-- Metric Basis      : Order Net Revenue (after discounts, BEFORE returns —
--                     the Phase-4-resolved standard retail definition)
-- Analysis Grain    : Fact_Orders (header grain)
-- SQL Design        : AVG(net_revenue) over Fact_Orders. Equivalent to
--                     SUM(net_revenue)/COUNT(*) at this grain; AVG is the
--                     direct expression of "per order".
-- Analytical Assumptions : Uses Order Net Revenue per the Phase 4 ruling that
--                     ended the $67.80-vs-$83.50 ambiguity. Returns are NOT
--                     netted into AOV (they are reported via Return Rate).
-- Independent Review: Header measure / header count, same grain. OK.
-- Validation        : Type A — anchor $83.50. (Phase 4 check 3.2 also pins
--                     header-path == line-path AOV single-valued.)
-- Result Sanity     : Within the documented $65-85 target band; consistent
--                     with ~1.29 items/order at apparel price points.
-- ═══════════════════════════════════════════════════════════════════
SELECT
    ROUND(AVG(net_revenue), 2)                                  AS avg_order_value,
    83.50                                                       AS certified_anchor,
    CASE WHEN ABS(AVG(net_revenue) - 83.50) <= 0.01
         THEN 'PASS' ELSE 'FAIL' END                            AS regression_result
FROM Fact_Orders;


-- ═══════════════════════════════════════════════════════════════════
-- A.5 — Discount Impact %
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What share of gross revenue is given back to
--                     customers as discounts?
-- Stakeholder       : CFO / VP Finance
-- Metric Definition : SUM(discount_amount) / SUM(gross_revenue) * 100
-- Metric Basis      : Gross Revenue and Discount (header)
-- Analysis Grain    : Fact_Orders (header grain)
-- SQL Design        : Both measures at header grain on Fact_Orders. (Line
--                     grain would give the identical ratio — Phase 4 check
--                     3.5 proved header==line — but header is the native grain.)
-- Analytical Assumptions : Discount Impact is a gross-revenue ratio per the
--                     KPI table ("Revenue lost to discounts / Gross Revenue"),
--                     not a net-revenue ratio.
-- Independent Review: Two header measures, same grain, ratio. OK.
-- Validation        : Type A — anchor 6.86%.
-- Result Sanity     : Single-digit blended discount rate is reasonable for a
--                     brand running periodic (not permanent) promotions.
-- ═══════════════════════════════════════════════════════════════════
SELECT
    ROUND(100.0 * SUM(discount_amount) / SUM(gross_revenue), 2) AS discount_impact_pct,
    6.86                                                        AS certified_anchor,
    CASE WHEN ABS(100.0 * SUM(discount_amount) / SUM(gross_revenue) - 6.86) <= 0.01
         THEN 'PASS' ELSE 'FAIL' END                            AS regression_result
FROM Fact_Orders;


-- ═══════════════════════════════════════════════════════════════════
-- A.6 — Return Rate %
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What share of units sold is returned?
-- Stakeholder       : COO / Operations (executive view)
-- Metric Definition : SUM(return_quantity) / SUM(quantity) * 100
-- Metric Basis      : Units (returned vs sold)
-- Analysis Grain    : Fact_Returns and Fact_Order_Lines (unit measures,
--                     combined as two scalars)
-- SQL Design        : Two independent scalar unit-sums, divided. NOT a row
--                     join between returns and lines — the ratio is of two
--                     grand totals, so no fan-out arises. Return Rate is a
--                     UNIT ratio per the KPI table, not a revenue or row ratio.
-- Analytical Assumptions : Units, not orders and not dollars — this is the
--                     documented definition (Units Returned / Units Sold).
-- Independent Review: Two disjoint unit scalars, ratio. OK.
-- Validation        : Type A — anchor 16.64%.
-- Result Sanity     : Blended apparel return rate mid-teens is realistic;
--                     footwear-heavy skew handled in Section G, not here.
-- ═══════════════════════════════════════════════════════════════════
SELECT
    ROUND(100.0 * (SELECT SUM(return_quantity) FROM Fact_Returns)
                / (SELECT SUM(quantity) FROM Fact_Order_Lines), 2) AS return_rate_pct,
    16.64                                                       AS certified_anchor,
    CASE WHEN ABS(100.0 * (SELECT SUM(return_quantity) FROM Fact_Returns)
                / (SELECT SUM(quantity) FROM Fact_Order_Lines) - 16.64) <= 0.01
         THEN 'PASS' ELSE 'FAIL' END                            AS regression_result;


-- ═══════════════════════════════════════════════════════════════════
-- A.7 — Repeat Purchase Rate
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What share of all customers have purchased more
--                     than once (over their full history)?
-- Stakeholder       : Head of Retention
-- Metric Definition : Customers with >=2 orders / Total Customers * 100
-- Metric Basis      : Customer Count
-- Analysis Grain    : Fact_Orders (customer rollup) vs Dim_Customer (base)
-- SQL Design        : Count customers with >=2 orders (GROUP BY customer_key
--                     HAVING COUNT(*)>=2), divide by the full Dim_Customer
--                     base (denominator is ALL customers, including the 289
--                     who never purchased and the ~1.4k one-time buyers).
-- Analytical Assumptions : This is the LIFETIME repeat rate (>=2 orders ever).
--                     The distinct "90-Day Repeat Rate" (2nd order within 90
--                     days of the 1st) is a DIFFERENT metric, computed in
--                     Section F — the two must never be conflated.
-- Independent Review: Numerator = distinct repeat customers; denominator =
--                     full customer base. Both customer-grain. OK.
-- Validation        : Type A — anchor 35.64%. (Phase 4 check 3.3 also pins
--                     this equal to the snapshot is_repeat_customer_flag path.)
-- Result Sanity     : Within Section 9's 35-45% target; consistent with the
--                     25% one-time-buyer persona share plus non-converters.
-- ═══════════════════════════════════════════════════════════════════
SELECT
    ROUND(100.0 * (SELECT COUNT(*) FROM (
              SELECT customer_key FROM Fact_Orders
              GROUP BY customer_key HAVING COUNT(*) >= 2))
                / (SELECT COUNT(*) FROM Dim_Customer), 2)       AS repeat_purchase_rate_pct,
    35.64                                                       AS certified_anchor,
    CASE WHEN ABS(100.0 * (SELECT COUNT(*) FROM (
              SELECT customer_key FROM Fact_Orders
              GROUP BY customer_key HAVING COUNT(*) >= 2))
                / (SELECT COUNT(*) FROM Dim_Customer) - 35.64) <= 0.01
         THEN 'PASS' ELSE 'FAIL' END                            AS regression_result;


-- ═══════════════════════════════════════════════════════════════════
-- A.8 — Consolidated Executive KPI Panel (single-row dashboard)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Give me every headline number on one line.
-- Stakeholder       : CFO / VP Finance (executive dashboard header)
-- Metric Definition : A.1-A.7 assembled into one row, plus two supporting
--                     counts (Total Orders, Total Customers) that give the
--                     rates their denominators and context. See justification
--                     in docs/phase5_analytics_report.md.
-- Metric Basis      : Mixed (each column labels its own basis)
-- Analysis Grain    : Composed from scalar sub-aggregates, each at its own
--                     native grain — deliberately assembled as independent
--                     scalars (not a multi-table row join) so no grain is
--                     mixed and no fan-out occurs.
-- Analytical Assumptions : Total Orders and Total Customers are added as
--                     context/denominators only; they are exact counts, not
--                     certified KPIs, so they carry no anchor.
-- Independent Review: Every column is an independent scalar sub-select; none
--                     shares a FROM with another. No cross-grain join. OK.
-- Validation        : Type A — the seven KPI columns must equal A.1-A.7
--                     (which are themselves anchored). The two count columns
--                     are Type B (independent exact counts).
-- Result Sanity     : One row; every rate in a sensible band; counts match
--                     the certified warehouse (26,299 orders / 8,000 customers).
-- ═══════════════════════════════════════════════════════════════════
SELECT
    ROUND((SELECT SUM(net_revenue) FROM Fact_Orders), 2)                        AS order_net_revenue,
    ROUND((SELECT SUM(net_revenue) FROM Fact_Orders)
        - (SELECT SUM(return_amount) FROM Fact_Returns), 2)                     AS net_revenue,
    ROUND((SELECT 100.0 * (SUM(net_line_revenue) - SUM(quantity * unit_cost))
                / SUM(net_line_revenue) FROM Fact_Order_Lines), 2)              AS gross_margin_pct,
    ROUND((SELECT AVG(net_revenue) FROM Fact_Orders), 2)                        AS avg_order_value,
    ROUND((SELECT 100.0 * SUM(discount_amount) / SUM(gross_revenue)
                FROM Fact_Orders), 2)                                           AS discount_impact_pct,
    ROUND(100.0 * (SELECT SUM(return_quantity) FROM Fact_Returns)
                / (SELECT SUM(quantity) FROM Fact_Order_Lines), 2)              AS return_rate_pct,
    ROUND(100.0 * (SELECT COUNT(*) FROM (
              SELECT customer_key FROM Fact_Orders
              GROUP BY customer_key HAVING COUNT(*) >= 2))
                / (SELECT COUNT(*) FROM Dim_Customer), 2)                       AS repeat_purchase_rate_pct,
    (SELECT COUNT(*) FROM Fact_Orders)                                          AS total_orders,
    (SELECT COUNT(*) FROM Dim_Customer)                                         AS total_customers;
