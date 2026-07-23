-- ####################################################################
-- Phase 6 — Advanced Customer Analytics
-- SECTION 6.5 — CUSTOMER BEHAVIORAL ANALYTICS
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 frozen/certified · Repository v1.1.0. Read-only.
-- Governed by permanent rules P5-1/P5-2/P5-3 and the Phase 6 Operating Procedure.
--
-- ══ WHAT THIS SECTION ADDS (analytical necessity) ══
--   Sections 6.1/6.3/6.4 MEASURE value (classify it, quantify it, describe its
--   distribution). Section 6.5 is the first section that attempts to EXPLAIN it:
--   which observable, repeatedly-chosen customer behaviors remain associated
--   with higher historical value AFTER controlling for purchase frequency.
--   Output is a candidate LEVER for experimentation, not another number.
--
-- ══ GOVERNING METHODOLOGY: FREQUENCY CONTROL (approved decision #1) ══
--   Purchase frequency is a CONTROL VARIABLE, never a reported behavioral
--   finding (frequency is already covered by 6.1 RFM, 6.2 cohort, Phase 5 F).
--   Rationale — behavioral breadth is MECHANICALLY coupled to order count: a
--   customer with 1 order touches ~1.17 categories, one with 7 orders ~3.42.
--   A raw breadth-vs-value comparison could therefore be pure frequency wearing
--   a different name. Every behavioral dimension is therefore evaluated BOTH
--   raw AND within fixed order-count strata; only dimensions that survive the
--   control are described as associated with value.
--
-- ══ INTERPRETATION LANGUAGE (approved decision #5) ══
--   NO CAUSAL CLAIMS. Behaviors are never said to "drive" or "predict" value.
--   The permitted formulation is that a behavior "remains strongly associated
--   with customer value after controlling for purchase frequency."
--   Recommendations are framed as opportunities for future experimentation.
--
-- ══ CANONICAL VALUE AXIS (approved decision #2) ══
--   Historical Value Classes from Section 6.3 — Low (<$100) / Moderate
--   ($100-300) / High ($300-750) / Elite ($750+). No CLV quartiles, no
--   alternative taxonomy: ONE canonical customer value classification platform-wide.
--
-- ══ POPULATION (approved decision #8) ══
--   Certified Positive Historical CLV population from 6.3: 7,034 customers.
--   EXCLUDED and documented: 289 non-purchasers (no behavior to observe) and
--   677 zero-net buyers (fully refunded; would distort behavioral averages).
--   289 + 677 + 7,034 = 8,000 certified base.
--
-- ══ BEHAVIORAL DEFINITION (approved decision #3) ══
--   PRIMARY dimensions are behaviors customers REPEATEDLY CHOOSE:
--     Category Breadth · Channel Breadth · Purchase Cadence
--   Returns and Discount Usage are NOT primary behavioral drivers — both are
--   substantially shaped by business policy and post-purchase outcomes rather
--   than free customer choice. Basket Value is not itself a behavioral
--   dimension. All three are tested and reported as NEGATIVE FINDINGS (12.5).
--
-- CONSUMES (integration, not duplication):
--   v_historical_clv   (6.3) — value axis; value is never recomputed here
--   v_rfm_segments     (6.1) — segment profiling
--
-- MIN CELL SIZE (approved decision #7): frequency-controlled cells with <30
--   customers are flagged LOW_BASE and excluded from executive interpretation.
--
-- ANCHORS: positive-CLV population 7,034 · Net Revenue $1,782,971.91 ·
--   certified base 8,000 · category bound 5 · channel bound 3.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- 12.1 — Behavioral feature base & population reconciliation
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What is the behavioral feature set per customer, and
--                     does the analysis population reconcile to the certified base?
-- Stakeholder       : Analytics
-- Metric Definition : per customer — order frequency (CONTROL), category
--                     breadth, channel breadth, purchase cadence (mean days
--                     between consecutive orders), plus the 6.3 Historical CLV
--                     and its Historical Value Class
-- Metric Basis      : Historical CLV (Net Revenue) for value; counts/days for behavior
-- Analysis Grain    : Customer (positive-CLV population, 7,034)
-- Analytical Design : Category breadth from Fact_Order_Lines (category is a LINE
--                     attribute); channel breadth and cadence from Fact_Orders
--                     (HEADER attributes) — correct grain per dimension, no
--                     fan-out. Cadence uses LAG over each customer's ordered
--                     purchase dates; it is legitimately NULL for single-order
--                     customers (no interval exists) — documented null handling,
--                     not a defect.
-- Independent Review: Features at their native grains; value consumed from 6.3
--                     not recomputed; population explicitly bounded. OK.
-- Validation        : Type A — population = 7,034 and value = $1,782,971.91.
--                     Type B — feature completeness (no NULL breadth/frequency)
--                     and null handling (cadence NULL iff single-order).
-- Result Sanity     : breadth within dimension bounds; cadence positive.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE TEMPORARY VIEW v_behavioral_features AS
WITH category_breadth AS (
    SELECT l.customer_key, COUNT(DISTINCT p.category) AS category_breadth
    FROM Fact_Order_Lines l JOIN Dim_Product p USING (product_key)
    GROUP BY l.customer_key
),
channel_breadth AS (
    SELECT customer_key, COUNT(DISTINCT sales_channel_key) AS channel_breadth
    FROM Fact_Orders GROUP BY customer_key
),
order_gaps AS (
    SELECT o.customer_key,
           DATE_DIFF('day', LAG(d.full_date) OVER (PARTITION BY o.customer_key ORDER BY d.full_date), d.full_date) AS gap_days
    FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
),
cadence AS (
    SELECT customer_key, AVG(gap_days) AS avg_days_between_orders
    FROM order_gaps WHERE gap_days IS NOT NULL GROUP BY customer_key
)
SELECT clv.customer_key,
       clv.lifetime_orders                                          AS order_frequency,   -- CONTROL variable
       clv.historical_clv,
       CASE WHEN clv.historical_clv < 100 THEN '1 Low (<$100)'
            WHEN clv.historical_clv < 300 THEN '2 Moderate ($100-300)'
            WHEN clv.historical_clv < 750 THEN '3 High ($300-750)'
            ELSE '4 Elite ($750+)' END                               AS historical_value_class,
       cb.category_breadth,
       ch.channel_breadth,
       cad.avg_days_between_orders                                   AS purchase_cadence_days
FROM v_historical_clv clv
LEFT JOIN category_breadth cb USING (customer_key)
LEFT JOIN channel_breadth ch USING (customer_key)
LEFT JOIN cadence cad USING (customer_key)
WHERE clv.historical_clv > 0;

-- 12.1a Population reconciliation with documented exclusions
SELECT 'Positive Historical CLV (analysis population)'                AS population,
       (SELECT COUNT(*) FROM v_behavioral_features)                   AS customers
UNION ALL
SELECT 'Excluded — zero-net buyers (purchased, fully refunded)',
       (SELECT COUNT(*) FROM v_historical_clv WHERE historical_clv = 0 AND lifetime_orders > 0)
UNION ALL
SELECT 'Excluded — non-purchasers (never activated)',
       (SELECT COUNT(*) FROM v_historical_clv WHERE lifetime_orders = 0)
UNION ALL
SELECT 'Certified customer base',
       (SELECT COUNT(*) FROM v_historical_clv);

-- 12.1-VALIDATION (Type A) — population and value reconcile to certified anchors
SELECT COUNT(*) AS behavioral_population,
       ROUND(SUM(historical_clv), 2) AS total_historical_clv,
       CASE WHEN COUNT(*) = 7034 AND ABS(SUM(historical_clv) - 1782971.91) <= 0.05
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_behavioral_features;

-- 12.1b-VALIDATION (Type B) — population reconciliation: analysis + exclusions = 8,000
SELECT (SELECT COUNT(*) FROM v_behavioral_features)
     + (SELECT COUNT(*) FROM v_historical_clv WHERE historical_clv = 0 AND lifetime_orders > 0)
     + (SELECT COUNT(*) FROM v_historical_clv WHERE lifetime_orders = 0)                     AS reconciled_base,
       CASE WHEN (SELECT COUNT(*) FROM v_behavioral_features)
                + (SELECT COUNT(*) FROM v_historical_clv WHERE historical_clv = 0 AND lifetime_orders > 0)
                + (SELECT COUNT(*) FROM v_historical_clv WHERE lifetime_orders = 0) = 8000
            THEN 'PASS' ELSE 'FAIL' END AS regression_result;

-- 12.1c-VALIDATION (Type B) — behavioral feature completeness (no missing core features)
SELECT COUNT(*) FILTER (WHERE category_breadth IS NULL)  AS missing_category_breadth,
       COUNT(*) FILTER (WHERE channel_breadth IS NULL)   AS missing_channel_breadth,
       COUNT(*) FILTER (WHERE order_frequency IS NULL)   AS missing_frequency,
       CASE WHEN COUNT(*) FILTER (WHERE category_breadth IS NULL) = 0
             AND COUNT(*) FILTER (WHERE channel_breadth IS NULL) = 0
             AND COUNT(*) FILTER (WHERE order_frequency IS NULL) = 0
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_behavioral_features;

-- 12.1d-VALIDATION (Type B) — null handling: cadence is NULL iff the customer has one order
SELECT COUNT(*) FILTER (WHERE purchase_cadence_days IS NULL AND order_frequency > 1)  AS unexpected_null_cadence,
       COUNT(*) FILTER (WHERE purchase_cadence_days IS NOT NULL AND order_frequency = 1) AS unexpected_cadence_on_single,
       CASE WHEN COUNT(*) FILTER (WHERE purchase_cadence_days IS NULL AND order_frequency > 1) = 0
             AND COUNT(*) FILTER (WHERE purchase_cadence_days IS NOT NULL AND order_frequency = 1) = 0
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_behavioral_features;

-- 12.1e-VALIDATION (Type B) — behavioral bounds: breadth within dimension cardinality
SELECT MIN(category_breadth) AS min_cat, MAX(category_breadth) AS max_cat,
       MIN(channel_breadth)  AS min_chan, MAX(channel_breadth) AS max_chan,
       ROUND(MIN(purchase_cadence_days), 1) AS min_cadence,
       CASE WHEN MIN(category_breadth) >= 1 AND MAX(category_breadth) <= (SELECT COUNT(DISTINCT category) FROM Dim_Product)
             AND MIN(channel_breadth) >= 1 AND MAX(channel_breadth) <= (SELECT COUNT(*) FROM Dim_Sales_Channel)
             AND COALESCE(MIN(purchase_cadence_days), 0) >= 0
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_behavioral_features;


-- ═══════════════════════════════════════════════════════════════════
-- 12.2 — Raw behavioral profile by Historical Value Class (with dispersion)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How do the primary behaviors differ across the canonical
--                     Historical Value Classes, before controlling for frequency?
-- Stakeholder       : CFO / Marketing
-- Metric Definition : per value class — median and IQR of category breadth,
--                     channel breadth, purchase cadence; plus the control
--                     variable (median order frequency) shown for transparency
-- Metric Basis      : Historical CLV classes (6.3); behavioral counts/days
-- Analysis Grain    : Historical Value Class
-- Analytical Design : MEDIAN and IQR (P25-P75) are reported rather than means
--                     alone (approved decision #6) because the behavioral
--                     distributions are skewed and small counts make means
--                     fragile; robust statistics prevent averages being read in
--                     isolation. Order frequency is displayed as the CONTROL,
--                     explicitly not as a behavioral finding.
-- Independent Review: Class-level robust statistics; control variable labeled. OK.
-- Validation        : Type B — value classes partition the 7,034 population.
-- Result Sanity     : Breadth and cadence should separate by class; frequency
--                     will also separate, which is exactly why 12.3/12.4 control for it.
-- ═══════════════════════════════════════════════════════════════════
SELECT historical_value_class,
       COUNT(*)                                                              AS customers,
       MEDIAN(order_frequency)                                               AS median_order_frequency_control,
       MEDIAN(category_breadth)                                              AS median_category_breadth,
       ROUND(QUANTILE_CONT(category_breadth, 0.25), 1)                       AS cat_breadth_p25,
       ROUND(QUANTILE_CONT(category_breadth, 0.75), 1)                       AS cat_breadth_p75,
       MEDIAN(channel_breadth)                                               AS median_channel_breadth,
       ROUND(MEDIAN(purchase_cadence_days), 0)                               AS median_cadence_days,
       ROUND(QUANTILE_CONT(purchase_cadence_days, 0.25), 0)                  AS cadence_p25,
       ROUND(QUANTILE_CONT(purchase_cadence_days, 0.75), 0)                  AS cadence_p75
FROM v_behavioral_features
GROUP BY historical_value_class ORDER BY historical_value_class;

-- 12.2-VALIDATION (Type B) — value classes partition the behavioral population
SELECT SUM(customers) AS classified_customers,
       CASE WHEN SUM(customers) = 7034 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT historical_value_class, COUNT(*) AS customers FROM v_behavioral_features GROUP BY 1);


-- ═══════════════════════════════════════════════════════════════════
-- 12.3 — FREQUENCY-CONTROLLED: Category Breadth  [the centerpiece]
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Among customers who placed the SAME number of orders,
--                     is greater category breadth still associated with higher
--                     historical customer value?
-- Stakeholder       : VP Merchandising / CFO
-- Metric Definition : within fixed order-frequency strata, median and mean
--                     Historical CLV by category breadth, with cell counts and
--                     a low-base flag
-- Metric Basis      : Historical CLV (Net Revenue); category breadth (line grain)
-- Analysis Grain    : order-frequency stratum × category breadth
-- Analytical Design : THE governing test. Holding order count fixed removes the
--                     mechanical coupling between breadth and frequency. If value
--                     still rises with breadth inside a stratum, breadth carries
--                     explanatory information independent of how often the
--                     customer buys. Strata shown for representative repeat-buyer
--                     frequencies; cells <30 customers flagged LOW_BASE and
--                     excluded from executive interpretation (approved #7).
--                     MEDIAN reported alongside mean (approved #6).
-- Analytical Assumptions : Association only — no causal claim. Customers
--                     inclined to buy broadly may differ in unobserved ways;
--                     this identifies a candidate for experimentation, not a cause.
-- Independent Review: Stratification is exact (integer order counts); low-base
--                     guardrail applied; robust statistic reported. OK.
-- Validation        : Type B — frequency-control integrity: strata cells
--                     partition the customers they cover with no double-counting.
-- Result Sanity     : If breadth is purely mechanical, value will be flat within
--                     a stratum. If it carries independent information, value
--                     will rise with breadth at fixed frequency.
-- ═══════════════════════════════════════════════════════════════════
SELECT order_frequency                                                       AS order_frequency_stratum,
       category_breadth,
       COUNT(*)                                                              AS customers,
       ROUND(MEDIAN(historical_clv), 2)                                      AS median_historical_clv,
       ROUND(AVG(historical_clv), 2)                                         AS mean_historical_clv,
       CASE WHEN COUNT(*) < 30 THEN 'LOW_BASE — excluded from interpretation'
            ELSE 'RELIABLE' END                                              AS cell_reliability
FROM v_behavioral_features
WHERE order_frequency IN (3, 4, 5, 6)
GROUP BY order_frequency, category_breadth
ORDER BY order_frequency, category_breadth;

-- 12.3-VALIDATION (Type B) — frequency-control integrity: strata cells partition their population
SELECT SUM(customers) AS cells_total,
       (SELECT COUNT(*) FROM v_behavioral_features WHERE order_frequency IN (3,4,5,6)) AS stratum_population,
       CASE WHEN SUM(customers) = (SELECT COUNT(*) FROM v_behavioral_features WHERE order_frequency IN (3,4,5,6))
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT order_frequency, category_breadth, COUNT(*) AS customers
      FROM v_behavioral_features WHERE order_frequency IN (3,4,5,6)
      GROUP BY order_frequency, category_breadth);


-- ═══════════════════════════════════════════════════════════════════
-- 12.4 — FREQUENCY-CONTROLLED: Channel Breadth and Purchase Cadence
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Do channel breadth and purchase cadence remain associated
--                     with higher value once order frequency is held constant?
-- Stakeholder       : VP Marketing / Head of Retention
-- Metric Definition : within fixed order-frequency strata — median Historical
--                     CLV by channel breadth; and by cadence band
-- Metric Basis      : Historical CLV; channel breadth and cadence (header grain)
-- Analysis Grain    : order-frequency stratum × (channel breadth | cadence band)
-- Analytical Design : Same control as 12.3. Cadence is banded (fast <60d,
--                     moderate 60-120d, slow 120d+) since it is continuous;
--                     bands are descriptive cut-points, not fitted thresholds.
--                     Low-base guardrail and median reporting as in 12.3.
-- Analytical Assumptions : Association only, no causal claim. Cadence applies
--                     only to repeat buyers (single-order customers have no
--                     interval and are correctly absent from the cadence view).
-- Independent Review: Same stratification discipline; cadence NULLs excluded by
--                     construction, consistent with 12.1d null handling. OK.
-- Validation        : Type B — cadence view covers only multi-order customers.
-- Result Sanity     : Channel breadth expected to hold some association; cadence
--                     expected to show faster repurchase among higher-value.
-- ═══════════════════════════════════════════════════════════════════

-- 12.4a Channel breadth, frequency-controlled
SELECT order_frequency                                                       AS order_frequency_stratum,
       channel_breadth,
       COUNT(*)                                                              AS customers,
       ROUND(MEDIAN(historical_clv), 2)                                      AS median_historical_clv,
       CASE WHEN COUNT(*) < 30 THEN 'LOW_BASE — excluded from interpretation'
            ELSE 'RELIABLE' END                                              AS cell_reliability
FROM v_behavioral_features
WHERE order_frequency IN (4, 6)
GROUP BY order_frequency, channel_breadth
ORDER BY order_frequency, channel_breadth;

-- 12.4b Purchase cadence band, frequency-controlled
SELECT order_frequency                                                       AS order_frequency_stratum,
       CASE WHEN purchase_cadence_days < 60 THEN '1 Fast (<60 days)'
            WHEN purchase_cadence_days < 120 THEN '2 Moderate (60-120 days)'
            ELSE '3 Slow (120+ days)' END                                    AS cadence_band,
       COUNT(*)                                                              AS customers,
       ROUND(MEDIAN(historical_clv), 2)                                      AS median_historical_clv,
       CASE WHEN COUNT(*) < 30 THEN 'LOW_BASE — excluded from interpretation'
            ELSE 'RELIABLE' END                                              AS cell_reliability
FROM v_behavioral_features
WHERE order_frequency IN (4, 6) AND purchase_cadence_days IS NOT NULL
GROUP BY order_frequency, cadence_band
ORDER BY order_frequency, cadence_band;

-- 12.4-VALIDATION (Type B) — cadence view covers only multi-order customers
SELECT COUNT(*) AS cadence_customers,
       COUNT(*) FILTER (WHERE order_frequency = 1) AS single_order_contamination,
       CASE WHEN COUNT(*) FILTER (WHERE order_frequency = 1) = 0 AND COUNT(*) > 0
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_behavioral_features WHERE purchase_cadence_days IS NOT NULL;


-- ═══════════════════════════════════════════════════════════════════
-- 12.5 — Tested but NON-EXPLANATORY variables (negative findings)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which candidate variables were tested and did NOT show a
--                     consistent association with customer value?
-- Stakeholder       : Analytics / CFO (methodological transparency)
-- Metric Definition : by Historical Value Class — median basket value, personal
--                     return rate, and discount share of gross spend
-- Metric Basis      : Order Net Revenue (basket), units (returns), discount share
-- Analysis Grain    : Historical Value Class
-- Analytical Design : Reported deliberately rather than discarded (approved
--                     decision #4). These are NOT primary behavioral dimensions:
--                     basket value is an outcome rather than a repeatedly-chosen
--                     behavior, and returns/discount usage are substantially
--                     shaped by business policy and post-purchase outcomes rather
--                     than free customer choice (approved decision #3).
--                     Documenting their non-association demonstrates that the
--                     primary dimensions were selected on evidence, not assumption.
-- Analytical Assumptions : A dimension is non-explanatory here if it fails to
--                     vary monotonically with value class.
-- Independent Review: Same population and value axis as the primary analysis. OK.
-- Validation        : Type B — negative-finding view covers the full population.
-- Result Sanity     : Basket expected NON-monotonic (corroborating the platform
--                     finding that value is not basket-driven); returns weak/
--                     inverse (consistent with Phase 5 G); discount patternless.
-- ═══════════════════════════════════════════════════════════════════
WITH basket AS (
    SELECT customer_key, AVG(net_revenue) AS avg_basket,
           SUM(discount_amount) / NULLIF(SUM(gross_revenue), 0) * 100 AS discount_share_pct
    FROM Fact_Orders GROUP BY customer_key
),
units_sold AS (SELECT customer_key, SUM(quantity) AS units FROM Fact_Order_Lines GROUP BY customer_key),
units_returned AS (SELECT customer_key, SUM(return_quantity) AS units FROM Fact_Returns GROUP BY customer_key)
SELECT bf.historical_value_class,
       COUNT(*)                                                              AS customers,
       ROUND(MEDIAN(b.avg_basket), 2)                                        AS median_basket_value,
       ROUND(100.0 * SUM(COALESCE(ur.units, 0)) / SUM(us.units), 1)          AS return_rate_pct,
       ROUND(MEDIAN(b.discount_share_pct), 1)                                AS median_discount_share_pct
FROM v_behavioral_features bf
JOIN basket b USING (customer_key)
JOIN units_sold us USING (customer_key)
LEFT JOIN units_returned ur USING (customer_key)
GROUP BY bf.historical_value_class ORDER BY bf.historical_value_class;

-- 12.5-VALIDATION (Type B) — negative-finding view covers the full behavioral population
SELECT SUM(customers) AS covered_customers,
       CASE WHEN SUM(customers) = 7034 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT bf.historical_value_class, COUNT(*) AS customers
      FROM v_behavioral_features bf
      JOIN (SELECT customer_key FROM Fact_Orders GROUP BY customer_key) b USING (customer_key)
      GROUP BY bf.historical_value_class);


-- ═══════════════════════════════════════════════════════════════════
-- 12.6 — Behavioral profile by RFM segment (integration with 6.1)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What behavioral signature characterizes each RFM segment?
-- Stakeholder       : Marketing / Retention
-- Metric Definition : per RFM segment — median category breadth, channel
--                     breadth, and cadence
-- Metric Basis      : behavioral features; RFM segments from 6.1
-- Analysis Grain    : RFM segment
-- Analytical Design : Attaches behavioral PROFILES to the EXISTING segmentation
--                     rather than creating a competing behavioral taxonomy —
--                     6.1 already segments customers and 6.6 will synthesize.
--                     This keeps one canonical segmentation platform-wide.
-- Analytical Assumptions : Profiles are descriptive. ED-009 — no generation
--                     persona is named, inferred, or reconstructed; these are
--                     observed behaviors attached to discovered RFM segments.
-- Independent Review: Join on customer; medians per segment; no new taxonomy. OK.
-- Validation        : Type B — profiled customers reconcile to the behavioral
--                     population intersected with RFM-scored customers.
-- Result Sanity     : Champions should show the broadest, fastest profile.
-- ═══════════════════════════════════════════════════════════════════
SELECT seg.segment,
       COUNT(*)                                                              AS customers,
       MEDIAN(bf.category_breadth)                                           AS median_category_breadth,
       MEDIAN(bf.channel_breadth)                                            AS median_channel_breadth,
       ROUND(MEDIAN(bf.purchase_cadence_days), 0)                            AS median_cadence_days
FROM v_behavioral_features bf
JOIN v_rfm_segments seg USING (customer_key)
GROUP BY seg.segment ORDER BY median_category_breadth DESC, customers DESC;

-- 12.6-VALIDATION (Type B) — RFM-profiled customers reconcile to the behavioral population
SELECT COUNT(*) AS profiled_customers,
       (SELECT COUNT(*) FROM v_behavioral_features) AS behavioral_population,
       CASE WHEN COUNT(*) = (SELECT COUNT(*) FROM v_behavioral_features)
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_behavioral_features bf JOIN v_rfm_segments seg USING (customer_key);
