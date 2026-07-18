# Schema Changelog — Customer Revenue Analytics
## Solstice Apparel

Version history for the data warehouse schema. Every change to `schema.sql` after the initial Phase 2 design gets an entry here — what changed, why, and what version it landed in. This is the record that keeps `schema.sql`, `data_dictionary.md`, and `er_diagram.drawio` honest with each other over time.

---

## v1.0 — Initial Phase 2 Schema
**Date:** Phase 2 completion, prior to Phase 2.5

Fact constellation architecture locked in: 8 dimensions (Dim_Date, Dim_Customer, Dim_Product, Dim_Geography, Dim_Sales_Channel, Dim_Marketing_Channel, Dim_Campaign, Dim_Return_Reason) and 4 fact tables (Fact_Orders, Fact_Order_Lines, Fact_Returns, Fact_Customer_Monthly_Snapshot).

Key decisions locked at this version:
- Type 1 dimensions only — no SCD2, since no dimension attribute survived the review with a genuine mutable/analytically-relevant reason to need it.
- Customer analytics (loyalty tier, activity, repeat status) live in the fact layer, not in Dim_Customer.
- Fact_Customer_Monthly_Snapshot designed as a true periodic snapshot — derived customer-state measures only, doubling as the Phase 10 ML feature/label source.
- Integer surrogate keys throughout, assigned by Phase 3 generation scripts rather than database identities.
- Fact_Returns as its own fact (separate date, partial-quantity support, its own reason dimension).

See `docs/design_decisions.md` for the full reasoning behind each of these.

---

## v1.1 — Phase 2.5 Refinement Patch
**Date:** Phase 2.5 completion, prior to Phase 3 implementation

Four fields added following the Phase 2.5 data generation strategy review (`docs/data_generation_strategy.md`, Section 12). Each was evaluated against a single test — does it serve a business question this project actually has, not just general realism.

| Field | Table | Why Added |
|---|---|---|
| `gender` | Dim_Product | Women's/Men's/Unisex cuts across category in a way category naming alone doesn't (e.g., unisex Accessories) — not derivable from existing fields, standard apparel product dimension. |
| `birth_year` | Dim_Customer | Dimensionally correct alternative to storing a static `age` column, which would go stale. Age is always computed at query time. Enables an age-band segmentation cut for Phase 6. |
| `postal_code` | Dim_Geography | Descriptive granularity below city/state, low cost, standard practice in a geography dimension. Stays flat — city/state/region remain the analytical rollup levels. |
| `refund_completed_flag` | Fact_Returns | Captures the real operational distinction between a return being requested/processed and the refund actually completing — not derivable from any other field, ties to the Operations/COO concern from Phase 1. |

**Considered and declined at this version:**

| Field | Table | Why Declined |
|---|---|---|
| `brand` | Dim_Product | Doesn't apply — Solstice Apparel is a single-brand D2C business, not a multi-brand catalog. |
| `material` | Dim_Product | Real merchandising value, but no Phase 1 business question depends on it. Candidate for a future extension. |
| `payment_method` | Fact_Orders | Plausible real-world relevance (e.g., BNPL and return risk) but no current business question needs it, and it would add persona/business-rule complexity in Phase 2.5 Section 7 without payoff. |
| `discount_percent` | Fact_Order_Lines | Fully derivable from `discount_amount ÷ gross_line_revenue`. Belongs in a SQL view or Power BI measure, not a stored column — same principle already applied to keep derived state out of Dim_Customer in v1.0. |

**Net change:** 4 columns added across 3 dimensions and 1 fact table. No tables added or removed. No grain changes. No relationship changes.

---

## Architecture Freeze

As of **v1.1**, the schema is frozen. Phase 3 (synthetic data generation), Phase 4 (validation), Phase 5/6 (SQL analytics), and the Power BI model all build against this version as a fixed contract. Any further schema change requires a genuine design defect surfaced during implementation — not a stylistic preference — and should be logged here with the same before/why/after structure as the v1.1 entry above if it happens.
