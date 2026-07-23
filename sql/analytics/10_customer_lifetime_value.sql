-- ####################################################################
-- Phase 6 — Advanced Customer Analytics
-- SECTION 6.3 — HISTORICAL CUSTOMER LIFETIME VALUE
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 frozen/certified · Repository v1.1.0. Read-only.
-- Governed by permanent rules P5-1/P5-2/P5-3 and the Phase 6 Operating Procedure.
--
-- PURPOSE: measure the observed, historical economic value every customer has
--   generated over their lifetime to date, and characterize how that value is
--   distributed across the portfolio.
--
-- ══ STRICTLY HISTORICAL (approved decision #1) ══
--   Historical CLV is a MEASURED HISTORICAL OUTCOME, never a prediction.
--   NO survival models, NO probabilistic lifetime, NO projected/future revenue.
--   Predictive CLV is explicitly DEFERRED to the future predictive-modeling
--   phase (Phase 9 churn), where survival probability is actually modeled.
--   This section answers "what value HAS each customer generated," not "what
--   value WILL they generate."
--
-- ══ TERMINOLOGY (must not be used interchangeably) ══
--   HISTORICAL CUSTOMER LIFETIME VALUE (Historical CLV): the total observed
--     Net Revenue a SINGLE customer has generated over their lifetime to date.
--     A per-customer quantity.
--   AVERAGE CUSTOMER VALUE: a portfolio aggregate — mean Historical CLV across
--     a group of customers. A summary statistic ABOUT a group, not a customer's
--     value. This report keeps the two distinct at every use.
--
-- BASIS (approved decision #3): Net Revenue (after returns) — the canonical
--   customer-value basis. Historical CLV(customer) = lifetime Order Net Revenue
--   − lifetime returns. Dual-source validated (snapshot cumulative vs base-fact
--   computation), both reconciling to certified Net Revenue $1,782,971.91.
--
-- GRAIN: one row per customer, ALL 8,000 (approved decision #2).
-- ANCHORS: base 8,000 · Net Revenue $1,782,971.91.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- 6.3.1 — Per-customer Historical CLV + dual-source reconciliation
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What historical net value has each customer generated,
--                     and do the two independent sources agree?
-- Stakeholder       : CFO / Analytics
-- Metric Definition : Historical CLV(customer) = lifetime Order Net Revenue
--                     − lifetime returns (Net Revenue basis)
-- Metric Basis      : Net Revenue (after returns)
-- Analysis Grain    : Customer (all 8,000)
-- SQL Design        : Base-fact computation (orders − returns per customer) as
--                     the canonical view; separately sum the snapshot's
--                     cumulative_net_revenue_to_date; validate the two agree and
--                     both hit the certified anchor. The agreement of two
--                     independent derivations is stronger evidence than one.
-- Analytical Assumptions : Historical/observed-to-date only. Returns netted per
--                     customer as a scalar (never row-multiplied against orders).
-- Independent Review: Customer grain; two independent sources; no fan-out. OK.
-- Validation        : Type A — base-fact total = $1,782,971.91.
--                     Type B — snapshot total = base-fact total (dual-source).
-- Result Sanity     : No negative CLV (returns never exceed purchases per
--                     customer, verified); total ties to certified.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE TEMPORARY VIEW v_historical_clv AS
SELECT c.customer_key,
       (SELECT COUNT(*) FROM Fact_Orders o WHERE o.customer_key = c.customer_key)          AS lifetime_orders,
       COALESCE((SELECT SUM(o.net_revenue) FROM Fact_Orders o WHERE o.customer_key = c.customer_key), 0)
     - COALESCE((SELECT SUM(r.return_amount) FROM Fact_Returns r WHERE r.customer_key = c.customer_key), 0)
                                                                                           AS historical_clv
FROM Dim_Customer c;

-- 6.3.1-VALIDATION (Type A) — base-fact Historical CLV total = certified Net Revenue
SELECT ROUND(SUM(historical_clv), 2) AS base_fact_total_clv,
       CASE WHEN ABS(SUM(historical_clv) - 1782971.91) <= 0.05 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_historical_clv;

-- 6.3.1b-VALIDATION (Type B) — DUAL-SOURCE: snapshot cumulative = base-fact computation
SELECT ROUND((SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot
              WHERE snapshot_month_date_key = 20251231), 2) AS snapshot_total,
       ROUND((SELECT SUM(historical_clv) FROM v_historical_clv), 2)                        AS base_fact_total,
       CASE WHEN ABS((SELECT SUM(cumulative_net_revenue_to_date) FROM Fact_Customer_Monthly_Snapshot WHERE snapshot_month_date_key = 20251231)
                   - (SELECT SUM(historical_clv) FROM v_historical_clv)) <= 0.05
            THEN 'PASS' ELSE 'FAIL' END AS regression_result;


-- ═══════════════════════════════════════════════════════════════════
-- 6.3.2 — Three-tier distribution (approved decision #2)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How does the customer base split by historical value,
--                     and what does each tier mean economically?
-- Stakeholder       : CFO
-- Metric Definition : three tiers with distinct business meaning —
--                     NON-PURCHASERS  : 0 orders, Historical CLV = 0 (acquired,
--                                       never activated)
--                     ZERO-NET BUYERS : >=1 order but Historical CLV = 0 (bought,
--                                       then fully refunded — real transactions,
--                                       zero retained value)
--                     POSITIVE CLV    : Historical CLV > 0 (retained value)
-- Metric Basis      : Net Revenue, Customer Count
-- Analysis Grain    : Customer
-- SQL Design        : Classify each customer into one of the three tiers by
--                     order count and CLV sign. The two zero-value tiers are
--                     economically distinct and reported separately so the $0
--                     mass is never a silent blob (a naive average over 8,000
--                     hides that ~12% sit at exactly zero for two reasons).
-- Analytical Assumptions : Zero-net buyers are a real, documented population
--                     (677 customers whose entire purchase value was refunded).
-- Independent Review: Tiers partition all 8,000; deterministic. OK.
-- Validation        : Type B — tiers sum to 8,000.
-- Result Sanity     : ~289 non-purchasers, ~677 zero-net buyers, ~7,034 positive.
-- ═══════════════════════════════════════════════════════════════════
SELECT CASE WHEN lifetime_orders = 0 THEN '1 Non-purchaser (acquired, never activated)'
            WHEN historical_clv = 0 THEN '2 Zero-net buyer (purchased, fully refunded)'
            ELSE '3 Positive Historical CLV' END                         AS value_tier,
       COUNT(*)                                                          AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                AS pct_of_base,
       ROUND(SUM(historical_clv), 2)                                    AS total_historical_clv,
       ROUND(100.0 * SUM(historical_clv)
             / SUM(SUM(historical_clv)) OVER (), 1)                      AS pct_of_total_clv
FROM v_historical_clv
GROUP BY 1 ORDER BY 1;

-- 6.3.2-VALIDATION (Type B) — three tiers partition all 8,000 customers
SELECT SUM(customers) AS total_customers,
       CASE WHEN SUM(customers) = 8000 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT CASE WHEN lifetime_orders = 0 THEN 'non' WHEN historical_clv = 0 THEN 'zero' ELSE 'pos' END AS tier,
             COUNT(*) AS customers FROM v_historical_clv GROUP BY 1);


-- ═══════════════════════════════════════════════════════════════════
-- 6.3.3 — Positive-CLV distribution (percentiles) + Historical Value Classes
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Among customers with retained value, how is Historical
--                     CLV distributed, and what descriptive value classes emerge?
-- Stakeholder       : CFO / Marketing
-- Metric Definition : percentiles of positive Historical CLV; empirical
--                     descriptive value classes (Low/Moderate/High/Elite)
-- Metric Basis      : Net Revenue (per-customer Historical CLV)
-- Analysis Grain    : Customer (positive-CLV only)
-- SQL Design        : Percentiles show the shape; value classes are empirical
--                     bands grounded on the distribution (breaks ≈ P50/P75/~P92:
--                     <100 / 100-300 / 300-750 / 750+). DESCRIPTIVE ONLY — these
--                     classes summarize observed historical value; they carry
--                     NO predictive meaning and imply nothing about future value.
--                     Concentration statistics (top-N%, Gini, Lorenz) are
--                     deliberately EXCLUDED — reserved for Section 6.4.
-- Analytical Assumptions : Value classes are descriptive historical bands, not
--                     predictive tiers. Median leads over mean given the ~22x
--                     P99/P50 right skew (mean is a poor central measure here).
-- Independent Review: Percentiles + empirical bands over positive CLV; no
--                     concentration math (that is 6.4). OK.
-- Validation        : Type B — value-class customers sum to the positive-CLV
--                     count; class CLV sums to positive-CLV total.
-- Result Sanity     : Heavy right skew; Elite (750+) small but large CLV share;
--                     Low (<100) large but small CLV share.
-- ═══════════════════════════════════════════════════════════════════

-- 6.3.3a Positive-CLV percentiles (distribution shape; mean shown but not emphasized)
SELECT COUNT(*)                                                          AS positive_clv_customers,
       ROUND(QUANTILE_CONT(historical_clv, 0.25), 2)                     AS p25,
       ROUND(QUANTILE_CONT(historical_clv, 0.50), 2)                     AS median_clv,
       ROUND(QUANTILE_CONT(historical_clv, 0.75), 2)                     AS p75,
       ROUND(QUANTILE_CONT(historical_clv, 0.90), 2)                     AS p90,
       ROUND(QUANTILE_CONT(historical_clv, 0.95), 2)                     AS p95,
       ROUND(AVG(historical_clv), 2)                                     AS mean_clv_context_only,
       ROUND(MAX(historical_clv), 2)                                     AS max_clv
FROM v_historical_clv WHERE historical_clv > 0;

-- 6.3.3b Empirical Historical Value Classes (DESCRIPTIVE, positive-CLV customers)
SELECT CASE WHEN historical_clv < 100 THEN '1 Low (<$100)'
            WHEN historical_clv < 300 THEN '2 Moderate ($100-300)'
            WHEN historical_clv < 750 THEN '3 High ($300-750)'
            ELSE '4 Elite ($750+)' END                                   AS historical_value_class,
       COUNT(*)                                                          AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                AS pct_of_positive,
       ROUND(AVG(historical_clv), 2)                                    AS avg_historical_clv,
       ROUND(SUM(historical_clv), 2)                                    AS total_historical_clv,
       ROUND(100.0 * SUM(historical_clv)
             / SUM(SUM(historical_clv)) OVER (), 1)                      AS pct_of_positive_clv
FROM v_historical_clv WHERE historical_clv > 0
GROUP BY 1 ORDER BY 1;

-- 6.3.3-VALIDATION (Type B) — value classes cover all positive-CLV customers
SELECT SUM(customers) AS classified, (SELECT COUNT(*) FROM v_historical_clv WHERE historical_clv > 0) AS positive_total,
       CASE WHEN SUM(customers) = (SELECT COUNT(*) FROM v_historical_clv WHERE historical_clv > 0)
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT CASE WHEN historical_clv < 100 THEN 'a' WHEN historical_clv < 300 THEN 'b'
                  WHEN historical_clv < 750 THEN 'c' ELSE 'd' END AS cls, COUNT(*) AS customers
      FROM v_historical_clv WHERE historical_clv > 0 GROUP BY 1);


-- ═══════════════════════════════════════════════════════════════════
-- 6.3.4 — CLV × RFM Segment (first-class bridge: 6.1 ↔ 6.3 ↔ 6.6)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How much historical value does each RFM segment hold —
--                     expressed in dollars rather than scores?
-- Stakeholder       : CFO / Marketing / Retention
-- Metric Definition : per RFM segment (from 6.1): customer count, AVERAGE
--                     Historical CLV, MEDIAN Historical CLV, TOTAL Historical
--                     CLV, and portfolio Historical CLV share
-- Metric Basis      : Net Revenue (Historical CLV)
-- Analysis Grain    : RFM segment (purchasing customers)
-- SQL Design        : Join v_rfm_segments (6.1) to v_historical_clv. Publishes
--                     both AVERAGE customer value (a group aggregate) and MEDIAN
--                     (robust to the right skew) alongside TOTAL and share —
--                     the principal bridge translating RFM scores into dollars.
-- Analytical Assumptions : Purchasing customers only (RFM excludes the 289 non-
--                     purchasers); segment totals reconcile to certified Net Rev.
--                     "Average Historical CLV" is explicitly a per-segment
--                     aggregate, distinct from an individual's Historical CLV.
-- Independent Review: Segment join on customer; avg/median/total/share. OK.
-- Validation        : Type A — segment total Historical CLV = $1,782,971.91.
-- Result Sanity     : Champions highest avg + total; median < mean within each
--                     segment (right skew); shares concentrate in Champions/Loyal.
-- ═══════════════════════════════════════════════════════════════════
SELECT seg.segment,
       COUNT(*)                                                          AS customers,
       ROUND(AVG(clv.historical_clv), 2)                                AS avg_historical_clv,
       ROUND(MEDIAN(clv.historical_clv), 2)                             AS median_historical_clv,
       ROUND(SUM(clv.historical_clv), 2)                                AS total_historical_clv,
       ROUND(100.0 * SUM(clv.historical_clv)
             / SUM(SUM(clv.historical_clv)) OVER (), 1)                  AS portfolio_clv_share_pct
FROM v_rfm_segments seg
JOIN v_historical_clv clv USING (customer_key)
GROUP BY seg.segment
ORDER BY total_historical_clv DESC;

-- 6.3.4-VALIDATION (Type A) — CLV across RFM segments = certified Net Revenue
-- (RFM covers the 7,711 purchasers; the 289 non-purchasers contribute $0, so
--  segment CLV total equals certified Net Revenue exactly.)
SELECT ROUND(SUM(historical_clv), 2) AS segment_clv_total,
       CASE WHEN ABS(SUM(historical_clv) - 1782971.91) <= 0.05 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_rfm_segments seg JOIN v_historical_clv clv USING (customer_key);
