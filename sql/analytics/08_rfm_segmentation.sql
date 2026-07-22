-- ####################################################################
-- Phase 6 — Advanced Customer Analytics
-- SECTION 6.1 — RFM SEGMENTATION (Adaptive RFM)
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 frozen/certified · Repository v1.1.0. Read-only.
-- Governed by permanent rules P5-1/P5-2/P5-3.
--
-- ADAPTIVE RFM METHODOLOGY (approved):
--   Recency   → empirical quintiles (NTILE 5)   — 1,079 distinct values, supports quintiles
--   Monetary  → empirical quintiles (NTILE 5)   — 6,246 distinct values, supports quintiles
--   Frequency → BEHAVIOR-DEFINED BANDS          — see justification below
--
-- WHY FREQUENCY IS NOT QUINTILED (documented, verified empirically):
--   The purchasing frequency distribution is highly DEGENERATE — 63.0% of
--   purchasers (4,860 of 7,711) have frequency = 1, and the MEDIAN frequency
--   is 1.0. Empirical NTILE(5) quintiles are therefore mathematically
--   inappropriate: the bottom three quintiles would all fall at frequency=1,
--   assigning arbitrary scores by tie-break. Instead F uses behavior-defined
--   bands validated against the frequency distribution's own percentiles:
--     Descriptive stats (final snapshot, purchasers): median 1 · P75 4 ·
--     P90 10 · P95 13 · P99 21 · max 32 · mean 3.41.
--   Band design and its percentile alignment:
--     F1 freq = 1     → 63.0% (the one-time floor; median sits here)
--     F2 freq 2-3     → 8.9%
--     F3 freq 4-6     → 10.4%  (upper edge ≈ P75 = 4)
--     F4 freq 7-11    → 10.8%  (spans P90 = 10)
--     F5 freq 12+     → 6.9%   (≈ P95 = 13 and above)
--   These are the Phase 5 F.2 behavioral tiers, re-verified here against the
--   distribution percentiles and RETAINED unchanged because each band is
--   materially populated (6.9%-10.8%, plus the 63% one-time floor) and the
--   band edges track the empirical quartiles. Documented per the approved
--   "verify thresholds before finalizing" requirement.
--
-- SCORING CONVENTION: 5 = best on every axis.
--   R5 = most recent (smallest recency_days) · F5 = most frequent ·
--   M5 = highest monetary. Recency is inverted (low days = high score).
--
-- GRAIN: one row per PURCHASING customer, as of the final snapshot
--   (2025-12-31). Non-purchasers (289) are excluded from RFM — they have no
--   recency/frequency to score — and are reported separately as an
--   un-scored segment so the customer base still reconciles to 8,000.
-- BASIS: Recency = recency_days; Frequency = cumulative_orders_to_date;
--   Monetary = cumulative_net_revenue_to_date (Net Revenue, after returns —
--   the customer-value basis per the Phase 4 ruling).
-- SOURCE: Fact_Customer_Monthly_Snapshot @ 2025-12-31 — one certified source
--   for all three dimensions (no re-derivation from raw orders).
--
-- OUTPUT: publishes BOTH the analytical score code (e.g. R5F5M5) AND the
--   business segment name (Champions, Loyal, ...).
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- 6.1.0 — Frequency band verification (evidence for the scoring choice)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Are the behavior-defined Frequency bands empirically
--                     justified, and is quintiling genuinely inappropriate?
-- Stakeholder       : Analytics (methodology evidence)
-- Metric Definition : frequency percentiles + per-band coverage
-- Metric Basis      : Frequency (cumulative_orders_to_date)
-- Analysis Grain    : Purchasing customer @ final snapshot
-- Analytical Assumptions : Degeneracy is demonstrated, not asserted — if the
--                     median equals the minimum, quintiles cannot separate.
-- Validation        : Type B — band counts sum to 7,711 purchasers.
-- ═══════════════════════════════════════════════════════════════════
SELECT
    ROUND(MEDIAN(cumulative_orders_to_date), 0)                     AS freq_median,
    ROUND(QUANTILE_CONT(cumulative_orders_to_date, 0.75), 0)        AS freq_p75,
    ROUND(QUANTILE_CONT(cumulative_orders_to_date, 0.90), 0)        AS freq_p90,
    ROUND(QUANTILE_CONT(cumulative_orders_to_date, 0.95), 0)        AS freq_p95,
    MAX(cumulative_orders_to_date)                                  AS freq_max,
    ROUND(AVG(cumulative_orders_to_date), 2)                        AS freq_mean
FROM Fact_Customer_Monthly_Snapshot
WHERE snapshot_month_date_key = 20251231 AND cumulative_orders_to_date > 0;

-- 6.1.0-VALIDATION (Type B) — frequency bands cover all 7,711 purchasers
SELECT SUM(customers) AS total_purchasers,
       CASE WHEN SUM(customers) = 7711 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (
    SELECT CASE WHEN cumulative_orders_to_date = 1 THEN 'F1'
                WHEN cumulative_orders_to_date BETWEEN 2 AND 3 THEN 'F2'
                WHEN cumulative_orders_to_date BETWEEN 4 AND 6 THEN 'F3'
                WHEN cumulative_orders_to_date BETWEEN 7 AND 11 THEN 'F4'
                ELSE 'F5' END AS band, COUNT(*) AS customers
    FROM Fact_Customer_Monthly_Snapshot
    WHERE snapshot_month_date_key = 20251231 AND cumulative_orders_to_date > 0
    GROUP BY 1);


-- ═══════════════════════════════════════════════════════════════════
-- 6.1.1 — RFM scores per customer (the adaptive core)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What is each purchasing customer's R, F, M score?
-- Stakeholder       : Retention / CRM
-- Metric Definition : R = NTILE(5) over recency ASC inverted (recent=5);
--                     M = NTILE(5) over monetary (high=5);
--                     F = behavior band (1..5) per the verified thresholds
-- Metric Basis      : R recency_days · F cumulative_orders · M net revenue
-- Analysis Grain    : Purchasing customer @ 2025-12-31
-- SQL Design        : NTILE(5) for R and M (empirical quintiles); CASE bands
--                     for F. Recency inverted: fewer days → higher score, via
--                     NTILE over recency_days DESC-inverted (ORDER BY recency
--                     ASC gives tile 1 = most recent, so 6 - tile = score).
-- Analytical Assumptions : as-of 2025-12-31 (recency_days already computed to
--                     that date in the snapshot). Net Revenue monetary basis.
-- Independent Review: R/M have >1,000 distinct values (quintile-safe); F is
--                     banded for the documented degeneracy. OK.
-- Validation        : Type B — exactly 7,711 scored customers; R and M each
--                     span scores 1..5.
-- Result Sanity     : R and M roughly balanced (~1,542/quintile); F heavily
--                     weighted to F1 (63%) by the real distribution.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE TEMPORARY VIEW v_rfm_scores AS
WITH base AS (
    SELECT customer_key, recency_days,
           cumulative_orders_to_date       AS frequency,
           cumulative_net_revenue_to_date  AS monetary
    FROM Fact_Customer_Monthly_Snapshot
    WHERE snapshot_month_date_key = 20251231 AND cumulative_orders_to_date > 0
)
SELECT customer_key, recency_days, frequency, monetary,
       6 - NTILE(5) OVER (ORDER BY recency_days ASC)                AS r_score,  -- recent → 5
       CASE WHEN frequency = 1 THEN 1
            WHEN frequency BETWEEN 2 AND 3 THEN 2
            WHEN frequency BETWEEN 4 AND 6 THEN 3
            WHEN frequency BETWEEN 7 AND 11 THEN 4
            ELSE 5 END                                              AS f_score,
       NTILE(5) OVER (ORDER BY monetary ASC)                        AS m_score   -- high → 5
FROM base;

-- 6.1.1 output: score distribution
SELECT r_score, f_score, m_score, COUNT(*) AS customers
FROM v_rfm_scores GROUP BY r_score, f_score, m_score ORDER BY r_score DESC, f_score DESC, m_score DESC;

-- 6.1.1-VALIDATION (Type B) — 7,711 scored; R and M span 1..5
SELECT COUNT(*) AS scored_customers,
       COUNT(DISTINCT r_score) AS r_levels, COUNT(DISTINCT m_score) AS m_levels,
       CASE WHEN COUNT(*) = 7711 AND COUNT(DISTINCT r_score) = 5 AND COUNT(DISTINCT m_score) = 5
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_rfm_scores;


-- ═══════════════════════════════════════════════════════════════════
-- 6.1.2 — Business segment assignment (score code → segment name)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Which named segment does each customer belong to?
-- Stakeholder       : Marketing / Retention
-- Metric Definition : standard RFM taxonomy mapped from (R, F, M) scores
-- Metric Basis      : RFM scores
-- Analysis Grain    : Purchasing customer
-- SQL Design        : Rule-based mapping on R and F (the standard 2-axis RFM
--                     grid), with M informing value within segment. Uses a
--                     documented, conventional taxonomy: Champions, Loyal,
--                     Potential Loyalists, Recent/New, Promising, Needs
--                     Attention, At Risk, Can't Lose (high value lapsed),
--                     Hibernating, Lost.
-- Analytical Assumptions : Standard RFM segment rules (R×F grid). Boundaries
--                     are a conventional scheme, documented, not fitted to
--                     persona ground truth (ED-009 — segments are DISCOVERED
--                     from RFM, never mapped to unstored generation personas).
-- Independent Review: Every (R,F) combination maps to exactly one segment;
--                     no customer unclassified. OK.
-- Validation        : Type B — segment counts sum to 7,711.
-- Result Sanity     : Champions/Loyal small and high-value; Hibernating/Lost
--                     large (the 63% one-time, lower-recency tail).
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE TEMPORARY VIEW v_rfm_segments AS
SELECT *,
       'R' || r_score || 'F' || f_score || 'M' || m_score           AS rfm_code,
       CASE
           WHEN r_score >= 4 AND f_score >= 4                        THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 3                        THEN 'Loyal'
           WHEN r_score >= 4 AND f_score = 2                         THEN 'Potential Loyalists'
           WHEN r_score >= 4 AND f_score = 1                         THEN 'New / Recent'
           WHEN r_score = 3 AND f_score <= 2                         THEN 'Promising'
           WHEN r_score = 2 AND f_score >= 3                         THEN 'Needs Attention'
           WHEN r_score = 2 AND f_score <= 2                         THEN 'At Risk'
           WHEN r_score = 1 AND f_score >= 4                         THEN 'Cant Lose'
           WHEN r_score = 1 AND f_score >= 2                         THEN 'Hibernating'
           ELSE 'Lost'
       END                                                          AS segment
FROM v_rfm_scores;

-- 6.1.2 output: segment summary with value (BOTH names and codes published)
SELECT segment,
       COUNT(*)                                                     AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_of_customers,
       ROUND(SUM(monetary), 2)                                      AS net_revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_net_revenue,
       ROUND(AVG(monetary), 2)                                      AS avg_clv,
       ROUND(AVG(frequency), 2)                                     AS avg_orders,
       ROUND(AVG(recency_days), 0)                                  AS avg_recency_days
FROM v_rfm_segments
GROUP BY segment ORDER BY net_revenue DESC;

-- 6.1.2-VALIDATION (Type B) — segments partition all 7,711 purchasers, no NULLs
SELECT COUNT(*) AS total, SUM(CASE WHEN segment IS NULL THEN 1 ELSE 0 END) AS unclassified,
       CASE WHEN COUNT(*) = 7711 AND SUM(CASE WHEN segment IS NULL THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_rfm_segments;


-- ═══════════════════════════════════════════════════════════════════
-- 6.1.3 — Reconciliation to certified Net Revenue + full base
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Do the RFM segments account for all customer value?
-- Stakeholder       : CFO (analytical trust)
-- Metric Definition : segment net revenue sums to certified Net Revenue;
--                     scored + non-purchasers = 8,000
-- Metric Basis      : Net Revenue, Customer Count
-- Analysis Grain    : Customer
-- SQL Design        : Sum segment monetary; add the 289 unscored non-
--                     purchasers to reconcile the full base.
-- Validation        : Type A — segment net revenue = $1,782,971.91;
--                     scored (7,711) + non-purchasers (289) = 8,000.
-- ═══════════════════════════════════════════════════════════════════
SELECT ROUND(SUM(monetary), 2) AS rfm_net_revenue,
       (SELECT COUNT(*) FROM v_rfm_segments) AS scored_customers,
       (SELECT COUNT(*) FROM Dim_Customer) - (SELECT COUNT(*) FROM v_rfm_segments) AS non_purchasers,
       CASE WHEN ABS(SUM(monetary) - 1782971.91) <= 0.05
             AND (SELECT COUNT(*) FROM v_rfm_segments) + 289 = 8000
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_rfm_segments;
