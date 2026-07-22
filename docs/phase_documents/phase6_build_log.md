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
