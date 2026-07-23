-- ####################################################################
-- Phase 6 — Advanced Customer Analytics
-- SECTION 6.4 — PARETO & CUSTOMER CONCENTRATION
--
-- Customer Revenue Analytics — Solstice Apparel Co.
-- Warehouse: v1.0.0 frozen/certified · Repository v1.1.0. Read-only.
-- Governed by permanent rules P5-1/P5-2/P5-3 and the Phase 6 Operating Procedure.
--
-- ══ WHAT THIS SECTION ADDS (analytical necessity) ══
--   Section 6.3 answered "WHAT IS EACH CUSTOMER WORTH?" — a measurement
--   question producing a per-customer value.
--   Section 6.4 answers "HOW CONCENTRATED IS PORTFOLIO VALUE?" — a STRUCTURAL
--   question about the portfolio as a system, producing population-level
--   inequality statistics that have no per-customer analogue.
--   These are different questions supporting different decisions, and the
--   distinction is maintained throughout (approved decision #5).
--
--   NEW CAPABILITY: inequality measurement (Lorenz curve + Gini coefficient),
--   which no prior section provides. Enables concentration-risk quantification,
--   key-account thresholds, and revenue-at-risk sizing.
--
-- ══ ANALYTICAL BASIS — DECLARED EXPLICITLY (approved decision #1) ══
--   PRIMARY BASE: the COMPLETE customer portfolio (8,000 customers).
--     Concentration risk is a question about the whole portfolio; customers
--     acquired but generating zero value are a real part of it, and excluding
--     them would flatter the numbers.
--   SECONDARY/RECONCILIATION BASE: the certified Phase 5 purchaser base
--     (7,711 customers), published so the certified Phase 5 F.3 finding
--     ("top decile = 50.1% of net revenue") remains DIRECTLY COMPARABLE and is
--     visibly preserved rather than silently superseded.
--   Every concentration figure in this section states its base. The same
--   "top decile" concept computes differently by base (51.0% on 8,000 vs
--   50.1% on 7,711) — publishing both prevents an apparent contradiction
--   with a certified finding.
--
-- SOURCE (approved decision #2): consumes v_historical_clv from Section 6.3.
--   Customer value is NOT recomputed here — 6.4 EXTENDS 6.3.
--
-- EXCLUDED (approved decision #4): HHI, CR4/CR8, Palma ratio — these do not
--   materially improve executive decision support for a 8,000-customer
--   portfolio (HHI/CR-n are industrial-organization metrics for markets with
--   few firms and produce near-zero, uninterpretable values at this scale).
--   A primary decile table is also excluded as duplicative of Phase 5 F.3;
--   decile points appear only as Lorenz coordinates.
--
-- ANCHORS: Net Revenue $1,782,971.91 · base 8,000 · Phase 5 F.3 top decile
--   50.1% on the 7,711-purchaser base.
-- ####################################################################


-- ═══════════════════════════════════════════════════════════════════
-- 6.4.1 — Concentration base & total reconciliation
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What population and what total value are the
--                     concentration metrics computed over?
-- Stakeholder       : CFO / Analytics
-- Metric Definition : customer counts and total Historical CLV for the primary
--                     (8,000) and reconciliation (7,711 purchaser) bases
-- Metric Basis      : Historical CLV (Net Revenue), Customer Count
-- Analysis Grain    : Customer
-- SQL Design        : Read v_historical_clv (6.3). Report both bases side by
--                     side so every downstream figure has a declared population.
-- Analytical Assumptions : Both bases carry the SAME total value
--                     ($1,782,971.91) because the 289 non-purchasers contribute
--                     $0 — the bases differ in DENOMINATOR (customer count),
--                     not in numerator (value). This is precisely why
--                     concentration percentages differ by base.
-- Independent Review: Customer grain; value consumed not recomputed. OK.
-- Validation        : Type A — total Historical CLV = $1,782,971.91; base = 8,000.
-- Result Sanity     : Both bases total the same value; purchaser base is 7,711.
-- ═══════════════════════════════════════════════════════════════════
SELECT 'Primary — complete portfolio'                                    AS analytical_basis,
       COUNT(*)                                                          AS customers,
       ROUND(SUM(historical_clv), 2)                                     AS total_historical_clv
FROM v_historical_clv
UNION ALL
SELECT 'Reconciliation — Phase 5 purchaser base',
       COUNT(*),
       ROUND(SUM(historical_clv), 2)
FROM v_historical_clv WHERE lifetime_orders > 0;

-- 6.4.1-VALIDATION (Type A) — total value and primary base reconcile to certified
SELECT COUNT(*) AS customers, ROUND(SUM(historical_clv), 2) AS total_clv,
       CASE WHEN COUNT(*) = 8000 AND ABS(SUM(historical_clv) - 1782971.91) <= 0.05
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM v_historical_clv;


-- ═══════════════════════════════════════════════════════════════════
-- 6.4.2 — Top-N concentration ladder (PRIMARY OUTPUT)
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What share of total customer value is held by the top
--                     1%, 5%, 10%, 20%, and 50% of customers?
-- Stakeholder       : CFO / Board
-- Metric Definition : cumulative share of Historical CLV held by the highest-
--                     value N% of customers, on the declared base
-- Metric Basis      : Historical CLV (Net Revenue)
-- Analysis Grain    : Customer, ranked by Historical CLV descending
-- SQL Design        : Rank customers by CLV desc; for each threshold N, sum the
--                     CLV of customers whose rank falls within the top N% and
--                     divide by the total. Computed on BOTH bases and labeled.
-- Analytical Assumptions : "Top N%" is by customer count, not value. Ranking
--                     ties are immaterial (continuous dollar values).
-- Independent Review: Window ranking + threshold sums; both bases labeled. OK.
-- Validation        : Type B — ladder is monotonically non-decreasing
--                     (top1% <= top5% <= top10% <= top20% <= top50% <= 100%).
-- Result Sanity     : Concentration high but not extreme; top 20% around 70%
--                     of value on the complete-portfolio base.
-- ═══════════════════════════════════════════════════════════════════
WITH ranked_all AS (
    SELECT historical_clv,
           ROW_NUMBER() OVER (ORDER BY historical_clv DESC) AS value_rank,
           COUNT(*) OVER ()                                 AS base_size,
           SUM(historical_clv) OVER ()                      AS total_value
    FROM v_historical_clv
),
ranked_purchasers AS (
    SELECT historical_clv,
           ROW_NUMBER() OVER (ORDER BY historical_clv DESC) AS value_rank,
           COUNT(*) OVER ()                                 AS base_size,
           SUM(historical_clv) OVER ()                      AS total_value
    FROM v_historical_clv WHERE lifetime_orders > 0
)
SELECT 'Primary — complete portfolio (8,000)'                            AS analytical_basis,
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.01 THEN historical_clv END) / MAX(total_value), 1) AS top_1_pct,
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.05 THEN historical_clv END) / MAX(total_value), 1) AS top_5_pct,
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.10 THEN historical_clv END) / MAX(total_value), 1) AS top_10_pct,
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.20 THEN historical_clv END) / MAX(total_value), 1) AS top_20_pct,
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.50 THEN historical_clv END) / MAX(total_value), 1) AS top_50_pct
FROM ranked_all
UNION ALL
SELECT 'Reconciliation — purchaser base (7,711)',
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.01 THEN historical_clv END) / MAX(total_value), 1),
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.05 THEN historical_clv END) / MAX(total_value), 1),
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.10 THEN historical_clv END) / MAX(total_value), 1),
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.20 THEN historical_clv END) / MAX(total_value), 1),
       ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.50 THEN historical_clv END) / MAX(total_value), 1)
FROM ranked_purchasers;

-- 6.4.2-VALIDATION (Type B) — ladder is monotonically non-decreasing and bounded
SELECT top_1_pct, top_5_pct, top_10_pct, top_20_pct, top_50_pct,
       CASE WHEN top_1_pct <= top_5_pct AND top_5_pct <= top_10_pct
             AND top_10_pct <= top_20_pct AND top_20_pct <= top_50_pct
             AND top_50_pct <= 100.0 AND top_1_pct >= 0.0
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (
    SELECT ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.01 THEN historical_clv END) / MAX(total_value), 1) AS top_1_pct,
           ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.05 THEN historical_clv END) / MAX(total_value), 1) AS top_5_pct,
           ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.10 THEN historical_clv END) / MAX(total_value), 1) AS top_10_pct,
           ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.20 THEN historical_clv END) / MAX(total_value), 1) AS top_20_pct,
           ROUND(100.0 * SUM(CASE WHEN value_rank <= base_size * 0.50 THEN historical_clv END) / MAX(total_value), 1) AS top_50_pct
    FROM (SELECT historical_clv,
                 ROW_NUMBER() OVER (ORDER BY historical_clv DESC) AS value_rank,
                 COUNT(*) OVER () AS base_size, SUM(historical_clv) OVER () AS total_value
          FROM v_historical_clv));


-- ═══════════════════════════════════════════════════════════════════
-- 6.4.3 — Phase 5 F.3 cross-phase reconciliation
-- ───────────────────────────────────────────────────────────────────
-- Business Question : Does this section's concentration measurement remain
--                     consistent with the certified Phase 5 F.3 finding?
-- Stakeholder       : Analytics (cross-phase integrity)
-- Metric Definition : top-decile share of Historical CLV on the 7,711-purchaser
--                     base — the exact population and metric Phase 5 F.3 used
-- Metric Basis      : Historical CLV (Net Revenue)
-- Analysis Grain    : Customer (purchaser base)
-- SQL Design        : NTILE(10) over purchasers by CLV desc; share of decile 1.
--                     This deliberately reproduces the Phase 5 F.3 construction
--                     so the certified 50.1% is regression-tested, not restated.
-- Analytical Assumptions : Phase 5 F.3 measured the top decile of the 7,711
--                     purchasers at 50.1% of net revenue. Reproducing it here
--                     proves 6.4 extends rather than contradicts Phase 5.
-- Independent Review: Same base, same metric, same construction as F.3. OK.
-- Validation        : Type A — top decile share = 50.1% (Phase 5 F.3 anchor).
-- Result Sanity     : Exactly 50.1%; any drift would signal an inconsistency
--                     between the CLV vector and Phase 5's revenue measurement.
-- ═══════════════════════════════════════════════════════════════════
WITH purchaser_deciles AS (
    SELECT historical_clv,
           NTILE(10) OVER (ORDER BY historical_clv DESC) AS value_decile,
           SUM(historical_clv) OVER ()                   AS total_value
    FROM v_historical_clv WHERE lifetime_orders > 0
)
SELECT COUNT(*)                                                          AS purchaser_base,
       ROUND(100.0 * SUM(CASE WHEN value_decile = 1 THEN historical_clv END)
             / MAX(total_value), 1)                                      AS top_decile_share_pct,
       50.1                                                              AS phase5_f3_certified_anchor
FROM purchaser_deciles;

-- 6.4.3-VALIDATION (Type A) — cross-phase regression against the Phase 5 F.3 anchor
SELECT ROUND(100.0 * SUM(CASE WHEN value_decile = 1 THEN historical_clv END) / MAX(total_value), 1) AS top_decile_share_pct,
       50.1 AS certified_anchor,
       CASE WHEN ABS(100.0 * SUM(CASE WHEN value_decile = 1 THEN historical_clv END) / MAX(total_value) - 50.1) <= 0.1
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (SELECT historical_clv, NTILE(10) OVER (ORDER BY historical_clv DESC) AS value_decile,
             SUM(historical_clv) OVER () AS total_value
      FROM v_historical_clv WHERE lifetime_orders > 0);


-- ═══════════════════════════════════════════════════════════════════
-- 6.4.4 — Lorenz Curve
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What is the full shape of value distribution across the
--                     customer portfolio (not just selected thresholds)?
-- Stakeholder       : CFO / Analytics
-- Metric Definition : cumulative share of Historical CLV against cumulative
--                     share of customers, ordered from lowest to highest value
-- Metric Basis      : Historical CLV (Net Revenue)
-- Analysis Grain    : Customer, ranked ascending by CLV
-- SQL Design        : Rank ascending; cumulative CLV share via running window.
--                     Reported at 10-point population intervals (decile
--                     coordinates) — these are LORENZ COORDINATES, deliberately
--                     not a standalone decile table (that would duplicate
--                     Phase 5 F.3). Primary base (complete portfolio).
-- Analytical Assumptions : Ascending order is the Lorenz convention (curve bows
--                     BELOW the 45-degree line of perfect equality). The curve
--                     is flat at the low end because 966 customers hold exactly
--                     $0 — a genuine feature of the portfolio, not an artifact.
-- Independent Review: Running cumulative window over ascending rank. OK.
-- Validation        : Type B — curve endpoints: 0% of customers hold 0% of
--                     value; 100% of customers hold 100%.
-- Result Sanity     : Curve flat then steeply rising — the classic concentrated
--                     shape; bottom 50% of customers hold a small single-digit
--                     share.
-- ═══════════════════════════════════════════════════════════════════
WITH ranked AS (
    SELECT historical_clv,
           ROW_NUMBER() OVER (ORDER BY historical_clv ASC) AS value_rank,
           COUNT(*) OVER ()                                AS base_size,
           SUM(historical_clv) OVER ()                     AS total_value
    FROM v_historical_clv
),
cumulative AS (
    SELECT value_rank, base_size,
           ROUND(100.0 * value_rank / base_size, 1)                                          AS cumulative_customer_pct,
           ROUND(100.0 * SUM(historical_clv) OVER (ORDER BY value_rank) / MAX(total_value) OVER (), 2) AS cumulative_value_pct
    FROM ranked
)
SELECT cumulative_customer_pct, cumulative_value_pct
FROM cumulative
WHERE value_rank % (base_size / 10) = 0
ORDER BY cumulative_customer_pct;

-- 6.4.4-VALIDATION (Type B) — Lorenz endpoint: all customers hold all value
WITH ranked_asc AS (
    SELECT historical_clv,
           ROW_NUMBER() OVER (ORDER BY historical_clv ASC) AS value_rank,
           SUM(historical_clv) OVER ()                     AS total_value
    FROM v_historical_clv
),
cumulative_share AS (
    SELECT ROUND(100.0 * SUM(historical_clv) OVER (ORDER BY value_rank) / MAX(total_value) OVER (), 2) AS cumulative_value_pct
    FROM ranked_asc
)
SELECT ROUND(MAX(cumulative_value_pct), 1) AS final_cumulative_value_pct,
       CASE WHEN ABS(MAX(cumulative_value_pct) - 100.0) <= 0.1 THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM cumulative_share;


-- ═══════════════════════════════════════════════════════════════════
-- 6.4.5 — Gini Coefficient
-- ───────────────────────────────────────────────────────────────────
-- Business Question : What single figure summarizes how unequally customer
--                     value is distributed, so it can be tracked over time?
-- Stakeholder       : CFO / Board
-- Metric Definition : Gini = (2 * SUM(rank_i * value_i)) / (n * SUM(value))
--                            - (n + 1) / n,  with values ranked ASCENDING.
--                     0 = perfect equality (every customer worth the same);
--                     1 = maximal concentration (one customer holds all value).
-- Metric Basis      : Historical CLV (Net Revenue)
-- Analysis Grain    : Customer (both bases reported)
-- SQL Design        : Standard covariance-form Gini computed from ascending
--                     ranks. Reported on the primary base and, for
--                     comparability, on the purchaser base.
-- Analytical Assumptions : The Gini is a DESCRIPTIVE inequality statistic about
--                     the portfolio. It is NOT a risk score, NOT a churn
--                     measure, and NOT a distress indicator — see the report's
--                     interpretation guidance. The primary-base Gini exceeds the
--                     purchaser-base Gini because 966 zero-value customers are
--                     legitimately included in the complete portfolio.
-- Independent Review: Standard formula; ascending rank; both bases. OK.
-- Validation        : Type B — Gini bounded in [0, 1] on both bases and higher
--                     on the complete-portfolio base (zero-value customers
--                     increase measured inequality).
-- Result Sanity     : Moderate-to-high concentration consistent with the
--                     top-N ladder and the Lorenz shape.
-- ═══════════════════════════════════════════════════════════════════
WITH gini_all AS (
    SELECT historical_clv,
           ROW_NUMBER() OVER (ORDER BY historical_clv ASC) AS value_rank,
           COUNT(*) OVER ()                                AS base_size,
           SUM(historical_clv) OVER ()                     AS total_value
    FROM v_historical_clv
),
gini_purchasers AS (
    SELECT historical_clv,
           ROW_NUMBER() OVER (ORDER BY historical_clv ASC) AS value_rank,
           COUNT(*) OVER ()                                AS base_size,
           SUM(historical_clv) OVER ()                     AS total_value
    FROM v_historical_clv WHERE lifetime_orders > 0
)
SELECT 'Primary — complete portfolio (8,000)'                            AS analytical_basis,
       ROUND((2.0 * SUM(value_rank * historical_clv) / (MAX(base_size) * MAX(total_value)))
             - (MAX(base_size) + 1.0) / MAX(base_size), 4)                AS gini_coefficient
FROM gini_all
UNION ALL
SELECT 'Reconciliation — purchaser base (7,711)',
       ROUND((2.0 * SUM(value_rank * historical_clv) / (MAX(base_size) * MAX(total_value)))
             - (MAX(base_size) + 1.0) / MAX(base_size), 4)
FROM gini_purchasers;

-- 6.4.5-VALIDATION (Type B) — Gini bounded [0,1] and ordered as expected
SELECT ROUND(gini_primary, 4) AS gini_primary, ROUND(gini_purchasers, 4) AS gini_purchasers,
       CASE WHEN gini_primary BETWEEN 0.0 AND 1.0 AND gini_purchasers BETWEEN 0.0 AND 1.0
             AND gini_primary > gini_purchasers
            THEN 'PASS' ELSE 'FAIL' END AS regression_result
FROM (
    SELECT (SELECT (2.0 * SUM(value_rank * historical_clv) / (MAX(base_size) * MAX(total_value)))
                   - (MAX(base_size) + 1.0) / MAX(base_size)
            FROM (SELECT historical_clv, ROW_NUMBER() OVER (ORDER BY historical_clv ASC) AS value_rank,
                         COUNT(*) OVER () AS base_size, SUM(historical_clv) OVER () AS total_value
                  FROM v_historical_clv)) AS gini_primary,
           (SELECT (2.0 * SUM(value_rank * historical_clv) / (MAX(base_size) * MAX(total_value)))
                   - (MAX(base_size) + 1.0) / MAX(base_size)
            FROM (SELECT historical_clv, ROW_NUMBER() OVER (ORDER BY historical_clv ASC) AS value_rank,
                         COUNT(*) OVER () AS base_size, SUM(historical_clv) OVER () AS total_value
                  FROM v_historical_clv WHERE lifetime_orders > 0)) AS gini_purchasers);
