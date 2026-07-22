# Phase 6 — Build Log
## Customer Revenue Analytics — Solstice Apparel Co.

Phase 6 (Advanced Customer Analytics) formalizes the customer-value analytics Phase 5 previewed: RFM, cohort, historical CLV, Pareto/concentration, behavioral analytics, and a portfolio synthesis. Warehouse v1.0.0 frozen; repository v1.1.0. Methodology, permanent rules (P5-1/2/3), and the 13-step per-query sequence carry forward from Phase 5 unchanged.

**Execution order (approved):** RFM → Cohort → Historical CLV → Pareto & Concentration → Behavioral Analytics → Portfolio Synthesis. One section per turn, phase-gated.

---

## Section 6.1 — RFM Segmentation (Adaptive RFM)

**Status: complete, executed, validated. Phase Gate: APPROVED.**

### Deliverable
`sql/analytics/08_rfm_segmentation.sql` — 6.1.0 (frequency band verification), 6.1.1 (per-customer R/F/M scores), 6.1.2 (segment assignment + code), 6.1.3 (reconciliation). Creates temp views `v_rfm_scores` and `v_rfm_segments` for downstream sections.

### Adaptive RFM methodology (approved refinement)
- **Recency & Monetary → empirical quintiles** (NTILE 5); 1,079 and 6,246 distinct values respectively — quintile-safe.
- **Frequency → behavior-defined bands** (1 / 2-3 / 4-6 / 7-11 / 12+). **Empirical quintiles documented as inappropriate**: 63.0% of purchasers have frequency=1 and the median frequency is 1, so NTILE(5) would tie the bottom three quintiles at the floor.
- **Thresholds verified before finalizing** (per approval requirement): frequency median 1 · P75 4 · P90 10 · P95 13 · max 32 · mean 3.41. The Phase 5 behavioral bands align with these percentiles (F3 edge≈P75, F4 spans P90, F5≈P95) and each band holds 6.9-10.8% (plus the 63% one-time floor), so the Phase 5 thresholds were **re-verified and retained unchanged with documented justification**.
- **Both published:** business segment names (Champions, Loyal, …) and analytical codes (R5F4M5, …).

### Execution result (4 validations, against frozen v1.0.0)

| Validation | Type | Result |
|---|---|---|
| 6.1.0 frequency bands cover 7,711 purchasers | B | ✅ PASS |
| 6.1.1 7,711 scored; R and M span 1..5 | B | ✅ PASS |
| 6.1.2 segments partition 7,711, no NULLs | B | ✅ PASS |
| 6.1.3 segment net revenue=$1,782,971.91 & base=8,000 | A | ✅ PASS |

**4/4 pass.**

### Grain, basis, source (P5-3)
Customer grain @ final snapshot 2025-12-31. R=recency_days, F=cumulative_orders_to_date, M=cumulative_net_revenue_to_date (Net Revenue basis, per Phase 4 ruling). Single certified source (the snapshot) for all three axes — no re-derivation from raw orders. Non-purchasers (289) excluded from scoring, reconciled separately to keep the base at 8,000.

### Key finding
RFM independently reproduces Phase 5's concentration via a different method: **Champions (15.3% of purchasers) drive 56.1% of net revenue; Champions+Loyal (27.9%) drive 76.2%.** At Risk+Lost (40% of purchasers, the one-time majority) hold only 11% of revenue — the second-purchase conversion pool. Method convergence strengthens the finding.

### Regression Anchors Used

Documenting every permanent validation anchor Section 6.1 relied on, separated by validation type — mirroring the Phase 5 anchor discipline.

**Type A — regression against certified anchors**
- **Certified Net Revenue ($1,782,971.91)** — segment monetary totals must sum to it (6.1.3). The permanent Net Revenue anchor (after returns), the customer-value basis.
- **Customer Base (8,000)** — scored purchasers (7,711) + non-purchasers (289) must reconcile to the certified Dim_Customer count (6.1.3).
- **Snapshot reconciliation** — Monetary is sourced from `Fact_Customer_Monthly_Snapshot` @ 2025-12-31, whose final-month cumulative net revenue was certified in Phase 3.12/Phase 4 to equal certified Net Revenue; RFM inherits that reconciliation by construction (single certified source, no re-derivation).

**Type B — independent recomputation**
- **Frequency coverage** — the five frequency bands must cover all 7,711 purchasers with none dropped (6.1.0).
- **Score coverage** — exactly 7,711 scored customers, with Recency and Monetary scores each spanning the full 1..5 range (6.1.1).
- **Segment partition** — the segment taxonomy must classify all 7,711 purchasers with zero NULLs (every customer lands in exactly one segment) (6.1.2).
- **Band verification** — frequency band thresholds verified against the distribution's own percentiles (median 1 · P75 4 · P90 10 · P95 13) before finalizing, demonstrating (not asserting) that empirical quintiles are inappropriate (6.1.0).

### ED-009 compliance
Segments are DISCOVERED from RFM scores, not mapped to the unstored generation personas. No persona label is asserted.

### No new Engineering Decision
Standard RFM composing existing structure; the adaptive-frequency choice is a documented analytical method, not an engineering pattern.

---

## Section 6.2 — Cohort Analytics

**Status: complete, executed, validated. Phase Gate: APPROVED.**

### Deliverable
`sql/analytics/09_cohort_retention.sql` — 6.2.1 (cohort base & maturity), 6.2.2 (primary: monthly purchase retention), 6.2.3 (secondary: 90-day engagement), 6.2.4 (revenue/orders/AOV), 6.2.5 (customer value), 6.2.6 (RFM composition by cohort). Creates temp view `v_cohort_base` (+ `v_cohort_retention`); consumes `v_rfm_segments` from 6.1.

### Approved design decisions implemented
1. **Signup cohorts**, full 8,000 base including 289 non-purchasers (age-0 = activation). Denominators documented per query.
2. **Two retention definitions, never combined:** PRIMARY = monthly purchase retention (order-based); SECONDARY = 90-day activity retention, always labeled an ENGAGEMENT measure.
3. **Cohort composition snapshot** (RFM mix by cohort) as supporting integration, not primary.
4. Certified regression anchors throughout.

### Cohort Maturity Classification (new methodology)
Observable window to 2025-12: **Immature 0-2mo (3 cohorts) · Growing 3-5mo (3) · Established 6-11mo (6) · Fully Mature 12+mo (24)**. Cross-cohort comparisons restricted to a common observable age; primary findings drawn from Fully Mature cohorts. This is the "retention triangle" guardrail — young cohorts lack the observation window to compare fairly and are excluded from quality judgments.

### Observable Window
- **Maximum comparable age:** 12 months is used as the primary comparison horizon (all 24 Fully Mature cohorts observe at least 12 months; the retention curve is drawn to age 12). The full observable range extends to 35 months for the oldest (2023-01) cohort.
- **Excluded immature observations:** the 3 Immature (0-2mo, 611 customers) and 3 Growing (3-5mo, 661 customers) cohorts are excluded from cross-cohort retention and value comparisons — they cannot yet be observed at the 12-month horizon. Established cohorts (6-11mo) are usable up to their own observable age but not at 12 months.
- **Interpretation guidance:** absolute cumulative measures (customer value 6.2.5, Champions share 6.2.6) rise monotonically with maturity as a pure artifact of accumulation time and RFM recency-as-of-2025-12-31. These are NOT vintage-quality trends. The only valid cross-vintage quality comparison is the retention curve at equal age (6.2.2); the cumulative gradients are reported with the confound flagged and must not be read as decay or improvement.

### Execution result (6 validations, against frozen v1.0.0)

| Validation | Type | Result |
|---|---|---|
| 6.2.1 cohorts=36, base=8,000 | A | ✅ PASS |
| 6.2.2 age-0 active = signup-month buyers, ≤7,711 | B | ✅ PASS |
| 6.2.3 all buyers active at first-purchase month (7,711) | B | ✅ PASS |
| 6.2.4 revenue=$2,195,871.49, orders=26,299 | A | ✅ PASS |
| 6.2.5 customer value=$1,782,971.91 | A | ✅ PASS |
| 6.2.6 RFM-scored purchasers map to cohorts (7,711) | B | ✅ PASS |

**6/6 pass. Whole analytics layer now 55/55.**

### Cross-file dependency
6.2.6 consumes `v_rfm_segments` from `08_rfm_segmentation.sql`. The validation runner processes files in filename order (08 before 09), so the RFM views exist when 09 runs. Verified end-to-end via the full runner (55/55).

### Key finding
Monthly purchase retention stabilizes at a **durable ~13% floor from month 3** (after the one-time majority churns) — the cohort-level signature of the loyal core. The 90-day engagement measure sits at ~27% and exhibits a mechanical cliff at month 3 (window-lapse), demonstrating exactly why the two definitions were kept separate. Cumulative value/composition gradients are maturity/recency confounds, flagged not interpreted.

### Regression Anchors Used
**Type A:** Customer Base (8,000) · Order Net Revenue ($2,195,871.49) · Orders (26,299) · Net Revenue ($1,782,971.91) · Cohort count (36).
**Type B:** age-0 retention = signup-month buyers (independent recompute) · first-purchase-month engagement invariant (7,711) · RFM-to-cohort mapping coverage (7,711).

### ED-009 compliance
6.2.6 uses the RFM segments discovered in 6.1; no generation persona is named or inferred. The maturity/recency confounds are documented so segment mix is not misread as ground-truth quality.

### No new Engineering Decision
Cohort analysis composes existing structure (snapshot + order aggregates + certified anchors + the 6.1 views). The maturity classification and dual-retention methodology are documented analytical methods, not reusable engineering patterns.

---
