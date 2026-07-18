# Design Decisions — Customer Revenue Analytics
## Solstice Apparel

This document explains the *why* behind the warehouse design, not just the what. Anyone reviewing this project (including a future version of me in an interview) should be able to read this and understand the tradeoffs, not just the resulting tables.

---

## 1. Why a Fact Constellation Instead of a Single Star Schema

A single star schema forces every fact into one grain. This business genuinely operates at four different grains that don't collapse into each other without losing information:

- **Order** (header-level: channel, campaign, geography)
- **Order line** (product-level: category, size, quantity)
- **Return** (its own date, its own reason, partial-quantity possible)
- **Customer-month** (a time-series state, not a transaction at all)

Forcing all four into one fact table means either duplicating header attributes onto every line (denormalization that breaks additivity — you'd double-count order-level revenue across lines) or losing the ability to analyze returns and monthly customer state cleanly. A constellation with conformed dimensions (Dim_Date, Dim_Customer, Dim_Product, Dim_Geography shared across facts) keeps each fact additive at its own grain while still letting every fact be sliced the same way. This is also the standard pattern real retail/e-commerce warehouses use — it's not architecture for its own sake.

## 2. Why a Customer Monthly Snapshot Fact

Without it, every retention curve, every RFM recalculation, and every churn signal has to be re-derived from raw order history with window functions, every time it's queried. That's slow, error-prone to keep consistent across SQL/Python/Power BI, and it means Phase 10's ML model would need its own separate feature-engineering pipeline built from scratch.

A periodic snapshot fact — one row per customer per month — turns "how has this customer's relationship with us evolved" into a stored fact instead of a derived query. Cohort retention becomes a `GROUP BY` on stored fields. RFM's recency and frequency components are already computed. And critically, Phase 10's supervised learning table is *this table*: each row is a labeled feature vector where the label (churned or not) is just looking two rows ahead for the same customer. Designing the churn model's feature source before writing any model code is what separates a warehouse built with ML in mind from one that has ML bolted on afterward.

**What it deliberately does NOT do:** duplicate transactional detail. Early drafts of this fact included orders_this_month and revenue_this_month, which are just Fact_Orders filtered to a month — redundant and a source of drift if the two ever disagree. The finalized version keeps only *state* measures (cumulative position, rolling windows, recency, and three business-rule flags) that aren't already sitting at finer grain elsewhere.

## 3. Why Type 1 Dimensions Only (MVP)

Type 2 SCD earns its complexity when there's a real business question that requires knowing what a dimension attribute *was* at the time of a transaction — e.g., "what was this customer's loyalty tier when they made this purchase." That question only exists if loyalty_tier lives in the dimension in the first place.

Once loyalty_tier and customer_status were moved out of Dim_Customer (see #5 below) and into the fact layer as derived state, there was nothing left in Dim_Customer that plausibly changes in a way the analysis cares about — signup_date, acquisition channel, and home geography are effectively fixed facts about a customer's origin. Type 2 history on those fields would add join complexity (current-vs-historical row selection) with no analytical payoff. If a future extension introduces genuinely mutable, analytically-relevant dimension attributes (e.g., a real CRM-assigned segment that marketing manually overrides), that's the trigger to revisit Type 2 — not before.

## 4. Why Fact_Returns Is a Separate Fact

Three reasons, all grain-related:
1. **Different date.** A return happens on a different calendar date than the original purchase — sometimes weeks later. Bolting a return onto the order-line fact means that fact no longer has a single, clean date grain.
2. **Partial quantities.** A customer can return 2 of 3 units from a line. An is_returned flag on Fact_Order_Lines can't represent that; a separate fact with its own return_quantity can.
3. **Its own dimension (reason).** Return reason is a real analytical axis (controllable vs. not) that has no equivalent on the original sale. Giving it a home in a dedicated fact keeps Fact_Order_Lines additive and clean, and keeps returns analysis (which categories, which reasons, revenue impact) self-contained.

## 5. Why Customer Analytics Live in Facts, Not in Dim_Customer

The original draft included loyalty_tier and customer_status directly on Dim_Customer. Both are outputs of behavioral analysis (how much has this customer bought, how recently), not descriptive attributes of who the customer is. Two problems with leaving them in the dimension:
- It pre-computes the answer Phase 6 is supposed to derive, turning an analytical exercise into a lookup.
- It creates a dimension that needs constant updating from fact-derived logic, which is a modeling smell — dimensions should describe, facts (and views built on them) should measure and derive.

Both attributes now live as computed flags on Fact_Customer_Monthly_Snapshot (is_active_flag, is_repeat_customer_flag) where they belong next to the other derived customer-state measures.

## 6. Why Integer Surrogate Keys Everywhere

Three standard warehouse reasons, all of which apply here: joins on integers are faster than joins on text business keys; surrogate keys insulate the warehouse from changes to source-system identifiers (if a natural key format ever changed, only the mapping layer would need to update, not every fact table); and consistent integer surrogates across every dimension make the schema mechanically predictable to extend. Surrogate keys are assigned during Phase 3 data generation in Python rather than via database identity/sequence, which keeps the synthetic dataset fully reproducible across regenerations — the same generation script with the same seed produces the same keys every time.

## 7. The Churn Risk Business Rule

`churn_risk_flag` on Fact_Customer_Monthly_Snapshot is TRUE when a customer's recency_days is between 61 and 90 (inclusive of 61, up to but not yet crossing 90). Below 60, a customer is within a normal repurchase window for apparel and isn't flagged. Above 90, `is_active_flag` already flips to FALSE — that customer is inactive, not "at risk," the risk window has already closed. The 61–90 day band is deliberately the narrow zone where a retention intervention (email, discount, personalized recommendation) still has a chance to land before the customer is counted as churned outright.

This is intentionally a simple, transparent business rule — not a model. Phase 10's actual predictive model is what gets compared against this rule as a baseline: does a trained classifier meaningfully outperform "flag anyone in the 61–90 day window," or does the simple rule already capture most of the signal? That comparison is a better interview story than the model existing in isolation.

## 8. Other Notable Choices

- **No Dim_Sales_Rep:** Solstice is a self-service D2C e-commerce brand. There's no sales force, so a rep dimension would exist only to look complete, not to answer a real question.
- **No separate Dim_Promotion:** discount amounts are stored as measures on Fact_Orders/Fact_Order_Lines. Dim_Campaign supplies the "why" for campaign-driven discounts. A fully separate promotions dimension would be justified by many overlapping non-seasonal promo codes, which isn't this business's reality.
- **Fiscal year = calendar year:** documented simplifying assumption. A true retail 4-5-4 fiscal calendar (starting the Sunday nearest Feb 1) was considered but adds complexity with no analytical payoff for this project's business questions — flagged here so it's a documented choice, not an oversight.
- **acquisition_channel_key denormalized onto Fact_Orders:** in addition to living on Dim_Customer, it's copied onto every order so channel-level revenue rollups don't require a join through the customer dimension for a query pattern (marketing attribution) that will run constantly.
- **customer_key denormalized onto Fact_Order_Lines:** same reasoning — product-by-customer analysis (e.g., category affinity by RFM segment in Phase 6) is common enough to justify skipping the join through Fact_Orders.
