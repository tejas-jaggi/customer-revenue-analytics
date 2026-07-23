-- ####################################################################
-- Phase 6 — Advanced Customer Analytics
-- SECTION 6.6 — CUSTOMER PORTFOLIO SYNTHESIS  [Phase 6 capstone]
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 frozen/certified · Repository v1.2.0. Read-only.
-- Governed by permanent rules P5-1/P5-2/P5-3 and the Phase 6 Operating Procedure.
--
-- ══ PURPOSE: INTEGRATION, NOT EXPANSION ══
--   Sections 6.1-6.5 each produced new measurement. This section produces
--   almost none, by design. It exists to integrate certified evidence into one
--   coherent portfolio interpretation.
--
--   DELIBERATELY THIN (approved decision #1). This module builds ONLY the two
--   artifacts that cannot be obtained from previously certified sections:
--     (1) the UNIFIED CUSTOMER PORTFOLIO VIEW — one row per customer carrying
--         every certified classification together, which no single prior view
--         provides; and
--     (2) CONVERGENCE QUANTIFICATION — measuring whether independently
--         constructed methods identify the SAME customers, a question no prior
--         section asks.
--   Everything else lives in the analytics report as narrative. Re-selecting
--   certified metrics here would create a SECOND HOME for numbers that already
--   have one, which is precisely how documentation drifts out of alignment.
--
-- ══ NO NEW TAXONOMY (approved decision #4) ══
--   The platform maintains ONE canonical segmentation (RFM, from 6.1) and ONE
--   canonical value axis (Historical Value Classes, from 6.3). This capstone
--   introduces neither a third segmentation nor an alternative value
--   classification. The executive framework GROUPS the existing RFM segments:
--     PROTECT → Champions, Loyal
--     GROW    → Potential Loyalists, Promising
--     CONVERT → At Risk, Lost
--   This is a presentation grouping of certified segments, not a new taxonomy.
--
-- ══ INVESTIGATED NEGATIVE FINDING (approved decision #7) ══
--   A "Protect-vs-Lapsed" framework (high historical value customers whose
--   recency has slipped) was investigated during design review and DELIBERATELY
--   NOT BUILT: only 2 top-decile customers sit in genuinely lapsing segments,
--   holding ~$1,453 combined. The portfolio contains no material population of
--   high-value lapsing customers. Building that machinery would have addressed
--   a problem this portfolio does not have. Documented rather than implemented.
--
-- CONSUMES (never recomputes):
--   v_rfm_segments        (6.1) — RFM segment + score code
--   v_historical_clv      (6.3) — Historical CLV
--   v_behavioral_features (6.5) — behavioral features + Historical Value Class
--
-- ANCHORS: customer base 8,000 · Net Revenue $1,782,971.91.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- 13.1 — Unified Customer Portfolio View
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What does the complete customer portfolio look like when
--                     every certified classification is carried on one row?
-- Stakeholder       : CFO / Analytics (and downstream Phase 7 / Phase 9)
-- Metric Definition : one row per customer carrying RFM segment, Historical
--                     Value Class, Historical CLV, behavioral features, and
--                     concentration position (value rank + percentile)
-- Metric Basis      : Historical CLV (Net Revenue) — consistent with 6.3-6.5
-- Analysis Grain    : Customer — the COMPLETE portfolio of 8,000
-- Analytical Design : LEFT JOINs from the full customer value base so that no
--                     customer is dropped. Concentration position is the one
--                     derived field: a value rank and percentile over the
--                     complete portfolio, which places each customer on the
--                     distribution measured in 6.4 without recomputing any of
--                     6.4's statistics.
-- Analytical Assumptions : Behavioral attributes are legitimately NULL for the
--                     966 customers outside the 6.5 behavioral population
--                     (289 non-purchasers + 677 zero-net buyers) — exclusions
--                     documented exactly as in 6.5, not treated as defects.
--                     RFM segment is NULL for the 289 non-purchasers (RFM scores
--                     purchasers only, per 6.1).
-- Independent Review: LEFT JOIN from the 8,000-row value base guarantees
--                     completeness; classifications are carried through
--                     unchanged, never re-derived. OK.
-- Validation        : Type A — 8,000 rows, one per customer; total Historical
--                     CLV = $1,782,971.91.
-- Result Sanity     : Row count equals the certified base; NULL counts match
--                     the documented exclusion populations exactly.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE TEMPORARY VIEW v_customer_portfolio AS
SELECT clv.customer_key,
       -- Certified value (6.3)
       clv.lifetime_orders,
       clv.historical_clv,
       bf.historical_value_class,
       -- Certified segmentation (6.1)
       seg.segment                                                   AS rfm_segment,
       seg.rfm_code,
       -- Executive framework grouping of the EXISTING taxonomy (no new taxonomy)
       CASE
           WHEN seg.segment IN ('Champions', 'Loyal')                    THEN '1 Protect'
           WHEN seg.segment IN ('Potential Loyalists', 'Promising')      THEN '2 Grow'
           WHEN seg.segment IN ('At Risk', 'Lost')                       THEN '3 Convert'
           WHEN seg.segment IS NULL                                      THEN '5 Not activated'
           ELSE '4 Other'
       END                                                           AS executive_framework,
       -- Certified behavioral features (6.5) — NULL outside the behavioral population
       bf.category_breadth,
       bf.channel_breadth,
       bf.purchase_cadence_days,
       -- Concentration position on the distribution measured in 6.4
       ROW_NUMBER() OVER (ORDER BY clv.historical_clv DESC)          AS portfolio_value_rank,
       ROUND(100.0 * ROW_NUMBER() OVER (ORDER BY clv.historical_clv DESC)
             / COUNT(*) OVER (), 2)                                  AS portfolio_value_percentile
FROM v_historical_clv clv
LEFT JOIN v_rfm_segments seg USING (customer_key)
LEFT JOIN v_behavioral_features bf USING (customer_key);

-- 13.1a Portfolio composition with documented exclusion populations
SELECT COUNT(*)                                                      AS total_customers,
       COUNT(*) FILTER (WHERE rfm_segment IS NOT NULL)               AS rfm_scored,
       COUNT(*) FILTER (WHERE category_breadth IS NOT NULL)          AS behavioral_population,
       COUNT(*) FILTER (WHERE rfm_segment IS NULL)                   AS excluded_non_purchasers,
       COUNT(*) FILTER (WHERE rfm_segment IS NOT NULL AND category_breadth IS NULL) AS excluded_zero_net_buyers,
       ROUND(SUM(historical_clv), 2)                                 AS total_historical_clv
FROM v_customer_portfolio;

-- 13.1-VALIDATION (Type A) — Unified Customer Portfolio View completeness
-- One row per customer across the complete certified portfolio; no customer
-- dropped or duplicated by the integration joins.
SELECT COUNT(*) AS portfolio_rows, COUNT(DISTINCT customer_key) AS distinct_customers,
       CASE WHEN COUNT(*) = 8000 AND COUNT(DISTINCT customer_key) = 8000
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_customer_portfolio;

-- 13.1b-VALIDATION (Type A) — certified Net Revenue reconciliation
-- Integration must carry customer value through without distortion.
SELECT ROUND(SUM(historical_clv), 2) AS total_historical_clv, 1782971.91 AS certified_anchor,
       CASE WHEN ABS(SUM(historical_clv) - 1782971.91) <= 0.05
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_customer_portfolio;


-- ═══════════════════════════════════════════════════════════════════
-- 13.2 — Classification fidelity (the synthesis-specific risk)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Does the integrated view carry the certified
--                     classifications through UNCHANGED?
-- Stakeholder       : Analytics (integration integrity)
-- Metric Definition : count of customers whose RFM segment or Historical Value
--                     Class on the portfolio view differs from the certified
--                     source view — expected to be zero
-- Metric Basis      : classification labels
-- Analysis Grain    : Customer
-- Analytical Design : THE validation that matters most for a synthesis layer.
--                     The characteristic failure mode of a capstone is silent
--                     drift — a join subtly reclassifying customers so the
--                     synthesis disagrees with its own sources. This compares
--                     the integrated view back to 6.1 and 6.5 row by row.
--                     Deliberately NOT re-testing what those sections already
--                     certified (approved decision #8) — testing only that
--                     integration preserved them.
-- Independent Review: Row-level comparison against both source views. OK.
-- Validation        : Type B — zero classification drift.
-- Result Sanity     : Zero mismatches on both dimensions.
-- ═══════════════════════════════════════════════════════════════════
SELECT COUNT(*) FILTER (WHERE p.rfm_segment IS DISTINCT FROM s.segment)                       AS rfm_segment_drift,
       COUNT(*) FILTER (WHERE p.historical_value_class IS DISTINCT FROM b.historical_value_class) AS value_class_drift
FROM v_customer_portfolio p
LEFT JOIN v_rfm_segments s USING (customer_key)
LEFT JOIN v_behavioral_features b USING (customer_key);

-- 13.2-VALIDATION (Type B) — zero classification drift from certified sources
SELECT COUNT(*) FILTER (WHERE p.rfm_segment IS DISTINCT FROM s.segment) AS rfm_drift,
       COUNT(*) FILTER (WHERE p.historical_value_class IS DISTINCT FROM b.historical_value_class) AS class_drift,
       CASE WHEN COUNT(*) FILTER (WHERE p.rfm_segment IS DISTINCT FROM s.segment) = 0
             AND COUNT(*) FILTER (WHERE p.historical_value_class IS DISTINCT FROM b.historical_value_class) = 0
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_customer_portfolio p
LEFT JOIN v_rfm_segments s USING (customer_key)
LEFT JOIN v_behavioral_features b USING (customer_key);


-- ═══════════════════════════════════════════════════════════════════
-- 13.3 — Convergence quantification across independent methods
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Do independently constructed analytical methods identify
--                     the SAME customers as high value?
-- Stakeholder       : CFO / Analytics
-- Metric Definition : overlap between three high-value definitions built by
--                     different constructions —
--                       (A) RFM Champions        (6.1: recency/frequency/monetary scoring)
--                       (B) Elite Value Class    (6.3: absolute CLV banding, >= $750)
--                       (C) Top CLV decile       (6.4: concentration ranking)
--                     plus the disagreement populations
-- Metric Basis      : Customer Count; Historical CLV for the disagreement view
-- Analysis Grain    : Customer sets
-- Analytical Design : The genuinely NEW question this section asks. Each method
--                     was constructed differently — scores vs absolute bands vs
--                     rank position — so agreement is informative rather than
--                     tautological. Disagreement populations are summarized
--                     briefly to explain WHY methods legitimately diverge
--                     (approved decision #3), not expanded into new analysis.
-- Analytical Assumptions : CONVERGENCE INCREASES CONFIDENCE; IT DOES NOT PROVE.
--                     Agreement between independently constructed methods raises
--                     confidence that they are identifying genuine characteristics
--                     of the customer portfolio rather than artifacts of any one
--                     technique. It is not proof of correctness (approved #6).
-- Independent Review: Set membership from certified classifications; intersections
--                     bounded by their sets. OK.
-- Validation        : Type B — convergence integrity: every intersection is
--                     less than or equal to each contributing set.
-- Result Sanity     : Substantial but not total overlap — the methods measure
--                     related but distinct things, so partial divergence is expected.
-- ═══════════════════════════════════════════════════════════════════
WITH champions AS (SELECT customer_key FROM v_customer_portfolio WHERE rfm_segment = 'Champions'),
elite       AS (SELECT customer_key FROM v_customer_portfolio WHERE historical_value_class = '4 Elite ($750+)'),
top_decile  AS (SELECT customer_key FROM v_customer_portfolio
                WHERE historical_clv > 0 AND portfolio_value_rank <= (SELECT COUNT(*) FROM v_customer_portfolio WHERE historical_clv > 0) * 0.10)
SELECT 'A · RFM Champions (6.1 scoring)'                             AS method_or_overlap,
       (SELECT COUNT(*) FROM champions)                              AS customers
UNION ALL SELECT 'B · Elite Value Class (6.3 banding)',              (SELECT COUNT(*) FROM elite)
UNION ALL SELECT 'C · Top CLV decile (6.4 ranking)',                 (SELECT COUNT(*) FROM top_decile)
UNION ALL SELECT 'A ∩ B — Champion and Elite',                       (SELECT COUNT(*) FROM champions JOIN elite USING (customer_key))
UNION ALL SELECT 'A ∩ C — Champion and top decile',                  (SELECT COUNT(*) FROM champions JOIN top_decile USING (customer_key))
UNION ALL SELECT 'B ∩ C — Elite and top decile',                     (SELECT COUNT(*) FROM elite JOIN top_decile USING (customer_key))
UNION ALL SELECT 'A ∩ B ∩ C — all three methods agree',              (SELECT COUNT(*) FROM champions JOIN elite USING (customer_key) JOIN top_decile USING (customer_key));

-- 13.3b Disagreement populations — where methods legitimately diverge, and why
WITH champions AS (SELECT customer_key FROM v_customer_portfolio WHERE rfm_segment = 'Champions'),
elite AS (SELECT customer_key FROM v_customer_portfolio WHERE historical_value_class = '4 Elite ($750+)')
SELECT 'Elite but NOT Champion'                                      AS disagreement_population,
       COUNT(*)                                                      AS customers,
       ROUND(MEDIAN(p.historical_clv), 2)                            AS median_historical_clv,
       ROUND(MEDIAN(p.purchase_cadence_days), 0)                     AS median_cadence_days
FROM elite e JOIN v_customer_portfolio p USING (customer_key)
WHERE e.customer_key NOT IN (SELECT customer_key FROM champions)
UNION ALL
SELECT 'Champion but NOT Elite', COUNT(*),
       ROUND(MEDIAN(p.historical_clv), 2), ROUND(MEDIAN(p.purchase_cadence_days), 0)
FROM champions c JOIN v_customer_portfolio p USING (customer_key)
WHERE c.customer_key NOT IN (SELECT customer_key FROM elite);

-- 13.3-VALIDATION (Type B) — convergence integrity: intersections bounded by their sets
WITH champions AS (SELECT customer_key FROM v_customer_portfolio WHERE rfm_segment = 'Champions'),
elite AS (SELECT customer_key FROM v_customer_portfolio WHERE historical_value_class = '4 Elite ($750+)'),
top_decile AS (SELECT customer_key FROM v_customer_portfolio
               WHERE historical_clv > 0 AND portfolio_value_rank <= (SELECT COUNT(*) FROM v_customer_portfolio WHERE historical_clv > 0) * 0.10),
counts AS (
    SELECT (SELECT COUNT(*) FROM champions) AS n_a, (SELECT COUNT(*) FROM elite) AS n_b,
           (SELECT COUNT(*) FROM top_decile) AS n_c,
           (SELECT COUNT(*) FROM champions JOIN elite USING (customer_key)) AS n_ab,
           (SELECT COUNT(*) FROM champions JOIN top_decile USING (customer_key)) AS n_ac,
           (SELECT COUNT(*) FROM elite JOIN top_decile USING (customer_key)) AS n_bc,
           (SELECT COUNT(*) FROM champions JOIN elite USING (customer_key) JOIN top_decile USING (customer_key)) AS n_abc
)
SELECT n_a, n_b, n_c, n_abc,
       CASE WHEN n_ab <= LEAST(n_a, n_b) AND n_ac <= LEAST(n_a, n_c) AND n_bc <= LEAST(n_b, n_c)
             AND n_abc <= LEAST(n_ab, n_ac, n_bc) AND n_abc > 0
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM counts;


-- ═══════════════════════════════════════════════════════════════════
-- 13.4 — Portfolio summary by executive framework
-- ───────────────────────────────────────────────────────────────────
-- Business Question : How does the portfolio distribute across the Protect /
--                     Grow / Convert framework?
-- Stakeholder       : CEO / CFO
-- Metric Definition : per framework group — customers, share of base, total and
--                     share of Historical CLV, median behavioral profile
-- Metric Basis      : Historical CLV (Net Revenue); Customer Count
-- Analysis Grain    : Executive framework group (a grouping of certified RFM segments)
-- Analytical Design : The single integration table the report needs. It groups
--                     CERTIFIED segments rather than introducing a taxonomy, and
--                     is compact by design — the detailed segment tables remain
--                     in 6.1/6.3/6.5 and are not reproduced here.
-- Analytical Assumptions : Framework groups are a presentation layer over the
--                     canonical RFM taxonomy. "Not activated" isolates the 289
--                     non-purchasers, who belong to no RFM segment.
-- Independent Review: Grouping is deterministic from certified segments; value
--                     carried through unchanged. OK.
-- Validation        : covered by 13.1 (completeness/value) and 13.2 (fidelity);
--                     no additional validation added, per the focused validation
--                     philosophy — a further check here would re-test 6.1/6.3.
-- Result Sanity     : Protect holds the large majority of value on a minority of
--                     customers; Convert holds many customers and little value.
-- ═══════════════════════════════════════════════════════════════════
SELECT executive_framework,
       COUNT(*)                                                      AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS pct_of_portfolio,
       ROUND(SUM(historical_clv), 2)                                 AS total_historical_clv,
       ROUND(100.0 * SUM(historical_clv)
             / SUM(SUM(historical_clv)) OVER (), 1)                  AS pct_of_portfolio_value,
       MEDIAN(category_breadth)                                      AS median_category_breadth,
       ROUND(MEDIAN(purchase_cadence_days), 0)                       AS median_cadence_days
FROM v_customer_portfolio
GROUP BY executive_framework ORDER BY executive_framework;
