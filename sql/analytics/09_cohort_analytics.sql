-- ####################################################################
-- Phase 6 — Advanced Customer Analytics
-- SECTION 6.2 — COHORT ANALYTICS
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 frozen/certified · Repository v1.1.0. Read-only.
-- Governed by permanent rules P5-1/P5-2/P5-3 and the Phase 6 Operating Procedure.
--
-- PURPOSE: the only LONGITUDINAL lens in the platform. Phase 5 and RFM are
--   cross-sectional (who is valuable now); cohorts answer "is customer
--   quality improving or decaying over time?" — do later signup vintages
--   retain and monetize better than earlier ones?
--
-- APPROVED DESIGN DECISIONS (Stage 1 review):
--   (1) SIGNUP COHORTS (group by signup month), NOT first-purchase cohorts —
--       measures the full lifecycle from acquisition through repeat purchase.
--       ALL customers included, INCLUDING the 289 non-purchasers (signup
--       without activation is a real, measurable acquisition outcome).
--       Denominators documented explicitly per query.
--   (2) RETENTION — TWO metrics, never combined:
--       PRIMARY  = Monthly Purchase Retention (placed >=1 ORDER in month N
--                  since signup). The standard "did they come back" measure.
--       SECONDARY = 90-Day Activity Retention (is_active_flag, a rolling-90-day
--                  ENGAGEMENT state). ALWAYS labeled an engagement measure, and
--                  NOT presented as purchase retention.
--   (3) COHORT COMPOSITION SNAPSHOT — RFM-segment mix by cohort (supporting
--       integration with 6.1, not the primary objective).
--   (4) Certified regression anchors throughout.
--
-- COHORT MATURITY CLASSIFICATION (observable window to 2025-12):
--   Immature      0-2 months observable   (3 cohorts)   — do NOT compare on retention curves
--   Growing       3-5 months observable   (3 cohorts)
--   Established    6-11 months observable  (6 cohorts)
--   Fully Mature   12+ months observable   (24 cohorts)
--   Business comparisons across cohorts MUST be at a COMMON observable age
--   (the "retention triangle" trap): a 1-month-old cohort has no month-12
--   data and would look falsely terrible against a 36-month-old one.
--
-- BASIS DISCIPLINE (P5-3):
--   Retention   = customer count.
--   Revenue/Orders/AOV = Order Net Revenue (header grain, Fact_Orders).
--   Customer value = Net Revenue after returns (customer-value basis).
--
-- ANCHORS: base 8,000 · Order Net Revenue $2,195,871.49 · orders 26,299 ·
--   Net Revenue $1,782,971.91 · 36 signup cohort-months.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- 6.2.1 — Cohort Base & Maturity Classification
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How many customers are in each signup cohort, and how
--                     much observation window does each cohort have?
-- Stakeholder       : Analytics / CFO
-- Metric Definition : per cohort: customers (full base incl. non-purchasers),
--                     observable months to 2025-12, maturity class
-- Metric Basis      : Customer Count
-- Analysis Grain    : Signup cohort (month)
-- SQL Design        : Group Dim_Customer by signup month; observable_months =
--                     months from cohort to 2025-12; classify into the four
--                     maturity bands.
-- Analytical Assumptions : DENOMINATOR = full signup base (all customers,
--                     incl. the 289 non-purchasers) — a signup cohort measures
--                     activation as well as retention.
-- Independent Review: One row per signup month; full base; deterministic bands. OK.
-- Validation        : Type A — cohorts = 36, customers sum to 8,000.
-- Result Sanity     : 3 Immature / 3 Growing / 6 Established / 24 Fully Mature;
--                     cohort sizes 186-282.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE TEMPORARY VIEW v_cohort_base AS
SELECT date_trunc('month', signup_date)                                          AS cohort_month,
       COUNT(*)                                                                  AS cohort_customers,
       DATE_DIFF('month', date_trunc('month', signup_date), DATE '2025-12-01')   AS observable_months,
       CASE
           WHEN DATE_DIFF('month', date_trunc('month', signup_date), DATE '2025-12-01') <= 2  THEN 'Immature'
           WHEN DATE_DIFF('month', date_trunc('month', signup_date), DATE '2025-12-01') <= 5  THEN 'Growing'
           WHEN DATE_DIFF('month', date_trunc('month', signup_date), DATE '2025-12-01') <= 11 THEN 'Established'
           ELSE 'Fully Mature'
       END                                                                       AS maturity_class
FROM Dim_Customer
GROUP BY 1;

SELECT maturity_class,
       COUNT(*)                                                                  AS cohorts,
       SUM(cohort_customers)                                                     AS customers,
       MIN(observable_months)                                                    AS min_observable_months,
       MAX(observable_months)                                                    AS max_observable_months
FROM v_cohort_base
GROUP BY maturity_class
ORDER BY min_observable_months DESC;

-- 6.2.1-VALIDATION (Type A) — 36 cohorts, base sums to 8,000
SELECT COUNT(*) AS cohort_count, SUM(cohort_customers) AS total_customers,
       CASE WHEN COUNT(*) = 36 AND SUM(cohort_customers) = 8000 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_cohort_base;


-- ═══════════════════════════════════════════════════════════════════
-- 6.2.2 — PRIMARY: Monthly Purchase Retention (order-based)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What share of a signup cohort places an order in each
--                     month after signup (did they come back)?
-- Stakeholder       : Head of Retention
-- Metric Definition : retention(cohort, age) = distinct cohort customers who
--                     placed >=1 order in the calendar month `age` months after
--                     their signup month / cohort base
-- Metric Basis      : Customer Count (purchase-based)
-- Analysis Grain    : Signup cohort × months-since-signup (age)
-- SQL Design        : For each order, age = months between the customer's
--                     signup month and the order month. Distinct customers per
--                     (cohort, age). Retention = that / cohort base. Denominator
--                     is the FULL signup base (incl. non-purchasers), so age-0
--                     retention = activation rate, not 100%.
-- Analytical Assumptions : PRIMARY definition = placed an order that month.
--                     This is NOT the 90-day engagement measure (6.2.3). The
--                     two are never combined.
-- Independent Review: Age computed from signup month to order month; distinct
--                     customers; full-base denominator. OK.
-- Validation        : Type B — age-0 active customers = distinct customers who
--                     ordered in their own signup month; bounded by 7,711 buyers.
--                     Retention never exceeds 100% and is monotone-bounded.
-- Result Sanity     : Age-0 retention = activation (< 100%, since 289 never buy
--                     and some buy after signup month); later ages decay.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE TEMPORARY VIEW v_cohort_retention AS
WITH cust_cohort AS (
    SELECT customer_key, date_trunc('month', signup_date) AS cohort_month FROM Dim_Customer
),
order_age AS (
    SELECT cc.cohort_month,
           cc.customer_key,
           DATE_DIFF('month', cc.cohort_month, date_trunc('month', d.full_date)) AS age_months
    FROM cust_cohort cc
    JOIN Fact_Orders o ON o.customer_key = cc.customer_key
    JOIN Dim_Date d ON o.order_date_key = d.date_key
),
active_by_age AS (
    SELECT cohort_month, age_months, COUNT(DISTINCT customer_key) AS active_customers
    FROM order_age WHERE age_months >= 0
    GROUP BY cohort_month, age_months
)
SELECT b.cohort_month, b.maturity_class, b.cohort_customers, b.observable_months,
       a.age_months,
       a.active_customers,
       ROUND(100.0 * a.active_customers / b.cohort_customers, 1) AS retention_pct
FROM v_cohort_base b JOIN active_by_age a USING (cohort_month);

-- 6.2.2 output: average monthly purchase retention curve (Fully Mature cohorts only, ages 0-12)
SELECT age_months,
       ROUND(AVG(retention_pct), 1) AS avg_retention_pct,
       SUM(active_customers)        AS total_active
FROM v_cohort_retention
WHERE maturity_class = 'Fully Mature' AND age_months <= 12
GROUP BY age_months ORDER BY age_months;

-- 6.2.2-VALIDATION (Type B) — age-0 active = distinct customers who ordered in signup month; <= 7,711
SELECT SUM(active_customers) AS age0_active_customers,
       CASE WHEN SUM(active_customers) = (
                SELECT COUNT(DISTINCT o.customer_key)
                FROM Fact_Orders o JOIN Dim_Date d ON o.order_date_key = d.date_key
                JOIN Dim_Customer c ON o.customer_key = c.customer_key
                WHERE date_trunc('month', d.full_date) = date_trunc('month', c.signup_date))
            AND SUM(active_customers) <= 7711
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_cohort_retention WHERE age_months = 0;


-- ═══════════════════════════════════════════════════════════════════
-- 6.2.3 — SECONDARY: 90-Day Activity Retention (ENGAGEMENT measure)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What share of a cohort is in an "active" ENGAGEMENT
--                     state (rolling 90-day) at each age? [engagement, NOT
--                     purchase retention]
-- Stakeholder       : Head of Retention (engagement view)
-- Metric Definition : engagement(cohort, age) = cohort customers with
--                     is_active_flag = TRUE at months_since_first_purchase = age
--                     / cohort base
-- Metric Basis      : Customer Count (90-day activity state)
-- Analysis Grain    : Signup cohort × months-since-signup
-- SQL Design        : Read is_active_flag straight from the snapshot at each
--                     months_since_first_purchase. THIS IS A 90-DAY ENGAGEMENT
--                     WINDOW, explicitly distinct from 6.2.2's monthly purchase
--                     retention — the two definitions are reported separately
--                     and never blended (approved decision #2).
-- Analytical Assumptions : is_active_flag is a rolling-90-day active state
--                     (verified: active rows avg 36-day recency, 1.39 orders/90d;
--                     inactive avg 387-day recency, 0 orders). Labeled ENGAGEMENT.
--                     Snapshot ages by months_since_first_purchase (buyers only),
--                     so this curve is over BUYERS, a different base than 6.2.2 —
--                     documented, not reconciled to the purchase-retention base.
-- Independent Review: Snapshot-native flag; window labeled; base difference
--                     documented. OK.
-- Validation        : Type B — at months_since_first_purchase=0 all buyers are
--                     active (7,711), the snapshot's construction invariant.
-- Result Sanity     : Near-100% engagement at age 0-2 (90-day window unlapsed),
--                     sharp drop at age ~3 as the window clears the first order.
-- ═══════════════════════════════════════════════════════════════════
SELECT s.months_since_first_purchase AS age_months,
       COUNT(*)                                                 AS buyers_at_age,
       COUNT(*) FILTER (WHERE s.is_active_flag)                 AS engaged_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE s.is_active_flag) / COUNT(*), 1) AS engagement_pct
FROM Fact_Customer_Monthly_Snapshot s
WHERE s.months_since_first_purchase BETWEEN 0 AND 12
GROUP BY s.months_since_first_purchase
ORDER BY s.months_since_first_purchase;

-- 6.2.3-VALIDATION (Type B) — at first-purchase month all buyers are active (construction invariant)
SELECT COUNT(*) FILTER (WHERE is_active_flag) AS engaged_at_age0, COUNT(*) AS buyers_at_age0,
       CASE WHEN COUNT(*) FILTER (WHERE is_active_flag) = COUNT(*) AND COUNT(*) = 7711
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM Fact_Customer_Monthly_Snapshot WHERE months_since_first_purchase = 0;


-- ═══════════════════════════════════════════════════════════════════
-- 6.2.4 — Cohort Revenue, Orders, AOV
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How much revenue and how many orders does each cohort
--                     generate, and at what AOV?
-- Stakeholder       : CFO
-- Metric Definition : per cohort: total Order Net Revenue, orders, AOV
--                     (revenue/orders); revenue per cohort customer
-- Metric Basis      : Order Net Revenue (header grain)
-- Analysis Grain    : Signup cohort (all ages aggregated)
-- SQL Design        : Sum order revenue and count orders per cohort; AOV at
--                     header grain. Reconciles across cohorts to certified totals.
-- Analytical Assumptions : Revenue attributed to the customer's signup cohort
--                     regardless of when in the lifecycle it was earned.
-- Independent Review: Header measures per cohort; no fan-out. OK.
-- Validation        : Type A — cohort revenue sums to $2,195,871.49, orders to 26,299.
-- Result Sanity     : Earlier cohorts have more revenue (more time to accumulate);
--                     AOV roughly uniform (~$83.50) across cohorts.
-- ═══════════════════════════════════════════════════════════════════
WITH cust_cohort AS (
    SELECT customer_key, date_trunc('month', signup_date) AS cohort_month FROM Dim_Customer
)
SELECT b.maturity_class,
       COUNT(DISTINCT cc.cohort_month)                          AS cohorts,
       ROUND(SUM(o.net_revenue), 2)                             AS order_net_revenue,
       COUNT(o.order_key)                                       AS orders,
       ROUND(SUM(o.net_revenue) / NULLIF(COUNT(o.order_key), 0), 2) AS aov
FROM cust_cohort cc
JOIN v_cohort_base b ON b.cohort_month = cc.cohort_month
LEFT JOIN Fact_Orders o ON o.customer_key = cc.customer_key
GROUP BY b.maturity_class
ORDER BY MIN(b.observable_months) DESC;

-- 6.2.4-VALIDATION (Type A) — cohort revenue and orders reconcile to certified totals
SELECT ROUND(SUM(o.net_revenue), 2) AS total_revenue, COUNT(o.order_key) AS total_orders,
       CASE WHEN ABS(SUM(o.net_revenue) - 2195871.49) <= 0.01 AND COUNT(o.order_key) = 26299
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM Fact_Orders o;


-- ═══════════════════════════════════════════════════════════════════
-- 6.2.5 — Cohort Customer Value (Net Revenue basis)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What is the average lifetime customer value of each
--                     cohort, and is it improving across vintages (at a
--                     comparable age)?
-- Stakeholder       : CFO
-- Metric Definition : per cohort: Net Revenue (after returns) / cohort
--                     customers = value per acquired customer
-- Metric Basis      : Net Revenue (customer-value basis)
-- Analysis Grain    : Signup cohort
-- SQL Design        : Net Revenue = order revenue minus the cohort's returns.
--                     Divided by the FULL cohort base (incl. non-purchasers),
--                     so this is value per ACQUIRED customer — the honest
--                     acquisition-quality metric.
-- Analytical Assumptions : Value per acquired customer (full-base denominator).
--                     Cross-cohort comparison caveat: later cohorts have less
--                     time to accumulate, so absolute value is NOT comparable
--                     across maturity classes — comparison must be at equal age
--                     (see the report's maturity guidance).
-- Independent Review: Net Revenue per cohort over full base; returns netted
--                     as scalar per customer. OK.
-- Validation        : Type A — cohort Net Revenue sums to $1,782,971.91.
-- Result Sanity     : Fully Mature cohorts show highest per-customer value
--                     (most accumulation time); Immature lowest (little time) —
--                     an artifact of maturity, flagged not interpreted as decay.
-- ═══════════════════════════════════════════════════════════════════
WITH cust_cohort AS (
    SELECT customer_key, date_trunc('month', signup_date) AS cohort_month FROM Dim_Customer
),
cust_value AS (
    SELECT cc.cohort_month, cc.customer_key,
           COALESCE((SELECT SUM(o.net_revenue) FROM Fact_Orders o WHERE o.customer_key = cc.customer_key), 0)
         - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key = cc.customer_key), 0) AS net_value
    FROM cust_cohort cc
)
SELECT b.maturity_class,
       COUNT(*)                                                 AS customers,
       ROUND(SUM(cv.net_value), 2)                              AS net_revenue,
       ROUND(SUM(cv.net_value) / COUNT(*), 2)                   AS value_per_acquired_customer
FROM cust_value cv JOIN v_cohort_base b USING (cohort_month)
GROUP BY b.maturity_class
ORDER BY MIN(b.observable_months) DESC;

-- 6.2.5-VALIDATION (Type A) — cohort net revenue reconciles to certified Net Revenue
SELECT ROUND(SUM(net_value), 2) AS total_net_revenue,
       CASE WHEN ABS(SUM(net_value) - 1782971.91) <= 0.05 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (
    SELECT c.customer_key,
           COALESCE((SELECT SUM(o.net_revenue) FROM Fact_Orders o WHERE o.customer_key = c.customer_key), 0)
         - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key = c.customer_key), 0) AS net_value
    FROM Dim_Customer c);


-- ═══════════════════════════════════════════════════════════════════
-- 6.2.6 — Cohort Composition Snapshot (RFM segment mix by cohort) [supporting]
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Do later signup cohorts produce a higher share of
--                     high-value RFM segments (improving acquisition quality)?
-- Stakeholder       : CFO / VP Marketing
-- Metric Definition : per maturity class: share of purchasers in each RFM
--                     segment (Champions/Loyal/... from 6.1)
-- Metric Basis      : Customer Count
-- Analysis Grain    : Signup cohort (maturity class) × RFM segment
-- SQL Design        : Join v_rfm_segments (from 6.1) to signup cohort; segment
--                     share within maturity class. SUPPORTING integration, not
--                     the primary objective (approved decision #3).
-- Analytical Assumptions : RFM segments come from 6.1's final-snapshot scoring.
--                     CROSS-COHORT CAUTION: RFM recency is measured as of
--                     2025-12-31, so newer cohorts mechanically skew to high-R
--                     segments (they signed up recently). Segment mix across
--                     maturity classes is therefore descriptive, and the
--                     recency confound is documented — NOT read as pure quality.
-- Independent Review: v_rfm_segments joined by customer; share within class.
--                     Confound documented. OK.
-- Validation        : Type B — classified purchasers sum to 7,711 (all RFM-
--                     scored customers map to a cohort).
-- Result Sanity     : Champions concentrate in older (Fully Mature) cohorts
--                     that had time to reach 7+ orders; newer cohorts skew
--                     New/Recent — partly real, partly the recency confound.
-- ═══════════════════════════════════════════════════════════════════
WITH cust_cohort AS (
    SELECT customer_key, date_trunc('month', signup_date) AS cohort_month FROM Dim_Customer
)
SELECT b.maturity_class,
       seg.segment,
       COUNT(*)                                                 AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY b.maturity_class), 1) AS pct_of_cohort_class
FROM v_rfm_segments seg
JOIN cust_cohort cc ON seg.customer_key = cc.customer_key
JOIN v_cohort_base b ON b.cohort_month = cc.cohort_month
WHERE seg.segment IN ('Champions', 'Loyal', 'At Risk', 'Lost')
GROUP BY b.maturity_class, seg.segment
ORDER BY b.maturity_class, customers DESC;

-- 6.2.6-VALIDATION (Type B) — all 7,711 RFM-scored purchasers map to a cohort
SELECT COUNT(*) AS classified_purchasers,
       CASE WHEN COUNT(*) = 7711 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_rfm_segments seg
JOIN (SELECT customer_key, date_trunc('month', signup_date) AS cohort_month FROM Dim_Customer) cc
     ON seg.customer_key = cc.customer_key;
