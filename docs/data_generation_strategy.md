# Data Generation Strategy — Customer Revenue Analytics
## Solstice Apparel — Phase 2.5

This is the blueprint for Phase 3. Nothing here is implementation — no Python, no SQL — this document exists so that every generation decision is made deliberately, once, before any code is written. Every SQL script, Python generator, validation check, and dashboard number should trace back to a rule stated here.

---

## 1. Project Purpose

A downloaded dataset (Kaggle or otherwise) is built around whatever business questions its original owner had, not this project's. It would never align with the exact schema from Phase 2, the specific personas this project needs to demonstrate segmentation on, or the multi-year evolution needed for growth and retention analysis. It also can't be trusted to contain the deliberate edge cases (a sizing-driven high-return segment, a one-time-buyer majority, a churn-risk window) that make Phase 6 and Phase 10 analytically interesting rather than descriptive.

Generating synthetic data means the business behavior can be designed on purpose. That distinction matters more than it sounds: if customer behavior were pure noise, every KPI would be flat, RFM segments would be arbitrary quintile cuts with no real underlying cluster structure, cohort retention curves would be flat lines, and a churn model would have no real signal to learn from. The value of this project is that the data has genuine structure baked in by design — realistic personas, seasonal demand, a maturing marketing mix — so that when Phase 6 "discovers" a Loyal VIP segment or Phase 10's model finds recency to be the strongest churn predictor, that's a real result being recovered from data engineered to contain it, not a coincidence.

---

## 2. Business Evolution Timeline

Solstice Apparel doesn't look the same in January 2023 as it does in December 2025. The three years should read as a business maturing, not three copies of the same static behavior stamped with different dates.

### 2023 — Early Growth
- **Customer growth:** Rapid new-customer acquisition off a small base — the highest *relative* growth rate of the three years, in absolute terms the smallest cohort.
- **Order growth:** Volume grows quarter over quarter as the customer base grows, but almost entirely first-order volume.
- **Marketing maturity:** Acquisition is paid-channel-heavy (Paid Social, Paid Search dominate). Email/SMS list is still small and immature. No real affiliate program yet.
- **Repeat purchase behavior:** Lowest of the three years — most customers are brand new, and the retention/lifecycle program doesn't exist yet.
- **Campaign maturity:** Campaigns run on the full calendar, but targeting is undifferentiated — everyone gets the same offer, no VIP-specific or win-back-specific treatment.
- **Revenue trend:** Growing off a small base, high month-to-month volatility, seasonal spikes look dramatic relative to the small non-seasonal baseline.

### 2024 — Retention Investment
- **Customer growth:** Continued acquisition, but the standout story this year is the 2023 cohort starting to come back. Cumulative customer base roughly doubles.
- **Order growth:** Growth now comes from two sources at once — new customers and repeat orders from 2023's cohort — which is what makes cohort retention curves in Phase 6 meaningful (there's a real prior-year cohort to measure).
- **Marketing maturity:** Email/SMS matures into a real lifecycle channel. Organic/SEO share starts climbing as brand awareness compounds. Affiliate/referral appears for the first time.
- **Repeat purchase behavior:** Visibly improves. This is the year real "Loyal"/"Champion" RFM clusters start to exist in the data.
- **Campaign maturity:** Targeting differentiates — VIP early-access treatment and win-back offers to lapsed customers both start showing up.
- **Revenue trend:** The strongest year-over-year growth rate of the three years, off a meaningfully larger base than 2023.

### 2025 — Maturity & Optimization
- **Customer growth:** Growth decelerates — this is deliberate. It's the data-level expression of the CFO's concern from Phase 1: is the business still buying growth, or has it earned durable retention? Diminishing returns on paid acquisition become visible.
- **Order growth:** Increasingly driven by repeat purchases and CLV expansion in the existing base rather than new-customer volume — a genuine mix shift, not just a slowdown.
- **Marketing maturity:** Full channel mix is in place, including a marketplace channel that's now a meaningful (if lower-margin) contributor. Paid channels show visibly diminishing efficiency.
- **Repeat purchase behavior:** Highest repeat rate of the three years, though the rate of improvement itself is slowing — a maturity curve, not runaway growth.
- **Campaign maturity:** Fully differentiated targeting across all four target_audience segments (All Customers / New Customers / Loyal-VIP / Lapsed-Winback).
- **Revenue trend:** Moderate YoY growth, but higher revenue *quality* — more of it retention-driven. Early churn-risk signal starts building in the aging 2023 cohort, since the retention program didn't exist for the first part of their relationship with the brand.

This arc is what gives Phase 8 something honest to say: acquisition efficiency is declining while retention is improving, and the business's real strategic question is whether the second trend can outrun the first.

---

## 3. Expected Dataset Size

| Table | Recommended Rows | Rationale |
|---|---|---|
| Customers | ~8,000 (cumulative, 2023–2025) | Large enough for statistically meaningful RFM quintiles and cohort curves with real signal in each monthly cohort; small enough to stay fast in DuckDB and reviewable by hand. Acquisition weighted ~2,500 (2023) / ~3,000 (2024) / ~2,500 (2025, deceleration). |
| Products | ~180 SKUs | Enough category/subcategory variety and seasonal collection rotation without turning product master data into its own project. |
| Orders | ~65,000 | With 8,000 customers and a repeat purchase rate climbing toward 35–45% by 2025, this implies roughly 8 orders per customer lifetime on average — within the original 50k–100k target, weighted toward 2024–2025 as repeat behavior builds. |
| Order Lines | ~95,000 | Average ~1.4 items per order, consistent with typical apparel basket sizes (most orders are 1–2 items). |
| Returns | ~16,000–18,000 line items | Blended return rate ~15–20% of units sold, higher in Footwear, lower in Accessories (see Section 5). |
| Monthly Snapshots | ~150,000–180,000 | 8,000 customers × up to 36 months each, but customers acquired later in the timeline accumulate fewer snapshot months — each row is small and derived, so the larger row count doesn't strain DuckDB. |
| Campaigns | 21 (7 named campaigns × 3 years) | Each year's instance of a named campaign (e.g., "Black Friday 2024") is its own row per the data dictionary, not a recurring template. |
| Marketing Channels | 6 (fixed) | Paid Social, Paid Search, Organic/SEO, Email/SMS, Affiliate/Referral, Direct. |
| Sales Channels | 3 (fixed) | Website, Mobile App, Marketplace. |
| Geographies | ~40–50 city/state combinations | Enough for real regional analysis across all 4 regions without exhaustively modeling every US city. |
| Date Dimension | 1,096 rows | Every calendar date from 2023-01-01 through 2025-12-31 (three years, one leap year). |

---

## 4. Customer Personas

Expanded from `business_glossary.md`. Population percentages sum to 100% of the customer base. **These personas are generation-time logic only — never a stored column.**

| Persona | Population | Purchase Frequency | Preferred Categories | AOV Tendency | Return Tendency | Churn Tendency |
|---|---|---|---|---|---|---|
| Loyal VIP | 8% | High — 8–12 orders/year once established | Cross-category, first to buy new collections | High, 1.3–1.6× blended average | Low, ~8–10% | Very low — rarely crosses the 90-day recency threshold |
| Fashion Enthusiast | 18% | Medium-high — 5–8 orders/year | Concentrated in Womenswear/Accessories, drop-chasing behavior around new collection launches | Medium-high, 1.1–1.3× average | Medium, ~18–22% (sizing experimentation) | Medium — retains well if campaign cadence stays frequent |
| Bargain Hunter | 22% | Medium — 3–5 orders/year, but heavily clustered in sale windows | No strong category preference; follows discount depth | Low, 0.7–0.85× average | Medium, ~15–18% | High between sale windows, but reliably returns for the next one — "dormant," not truly gone |
| Seasonal Shopper | 20% | Low-medium — 1–3 orders/year, tightly clustered around Holiday and Back-to-School | Gift-oriented — Accessories and Outerwear skew for holiday | Medium, ~1.0× average | Low-medium, ~12% | Appears "churned" by the 90-day rule most of the year even though they're not truly gone — a deliberate discussion point for Phase 8 |
| One-Time Buyer | 25% | Exactly 1 order, ever | No pattern | Variable, roughly average | Slightly elevated, ~20% (buyer's-remorse pattern) | 100% by definition — this is the segment that drags down the overall repeat purchase rate |
| High-Return Customer | 7% | Medium — 4–6 orders/year | Skews Footwear (sizing risk) and Womenswear | Medium | High, 35–45% | Medium-high — and a real business tension: is retaining this segment worth the return-processing cost? |

---

## 5. Product Strategy

**Category mix (of ~180 SKUs):**

| Category | Approx. SKUs | Price Range | Cost as % of List Price |
|---|---|---|---|
| Womenswear | 45 | $28–$120 | ~40% |
| Menswear | 35 | $25–$110 | ~40% |
| Outerwear | 30 | $90–$280 | ~35% (highest margin, premium seasonal category) |
| Footwear | 30 | $60–$180 | ~45% (lowest margin — sizing/return costs eat into it) |
| Accessories | 40 | $15–$65 | ~30% (highest margin, high-volume gift category) |

**Seasonality and collection launches:** each product's `collection_season` ties it to a launch window — Spring Collection (Feb–Mar) introduces new Womenswear/Menswear, Holiday Collection (Nov–Dec) introduces gift-leaning Accessories and Outerwear. This is what makes `Dim_Campaign` and `Dim_Product` connect narratively even though there's no direct foreign key between them.

**Footwear return behavior:** deliberately the highest base return rate (~25–30% before persona modifiers), reflecting the real apparel-industry reality that sizing is the single largest driver of returns for shoes specifically.

**Accessory behavior:** deliberately the lowest base return rate (~8–10% — no-fit-risk items like bags and jewelry), but the highest gift-purchase concentration around the holidays, and commonly a basket-filler alongside a primary purchase rather than a standalone one.

---

## 6. Marketing Strategy

**Acquisition channel mix, evolving by year** (illustrative targets, not hard rules — see Section 8 for how these get applied as weighted randomness):

| Channel | 2023 | 2024 | 2025 |
|---|---|---|---|
| Paid Social | 40% | 32% | 25% |
| Paid Search | 25% | 22% | 20% |
| Organic/SEO | 10% | 18% | 25% |
| Email/SMS | 5% | 10% | 15% |
| Affiliate/Referral | 5% | 7% | 8% |
| Direct | 15% | 11% | 7% |

Owned/organic channels growing share over time is the realistic maturation pattern for a D2C brand — and it's also what feeds the "which channels retain customers" business question with a real, non-obvious answer (paid-social-acquired customers should show measurably weaker retention than email/organic-acquired ones).

**Campaign lift (order-volume multiplier vs. a non-campaign baseline day):**

| Campaign | Lift | Note |
|---|---|---|
| Black Friday / Cyber Monday | 3–4× | Deepest discount, biggest volume spike |
| Summer Sale | 1.5–2× | Moderate discount |
| Back-to-School | 1.3–1.5× | Moderate discount |
| Spring Collection Launch | 1.2–1.4× | Mostly full-price, new-product driven |
| Holiday Collection Launch | 1.2–1.4× | Mostly full-price, gift-driven |
| January Clearance | 1.5× volume, but lowest net revenue per order | Deepest discount of the calendar |

**Email effectiveness:** customers acquired via Email/SMS, and customers who engage with lifecycle email overall, should show measurably higher repeat purchase rate and lower recency-based churn risk than paid-social-acquired customers. This isn't a coincidence — it's the intended signal for the marketing-attribution business question.

**Marketplace behavior:** Marketplace (Amazon)-channel customers show weaker repeat purchase rate and lower channel loyalty (the business owns less of that relationship directly), but contribute meaningfully to gross order volume — especially in Footwear and Accessories, categories marketplace shoppers browse more readily than a brand's own site.

---

## 7. Business Rules

Deterministic logic the generator must follow exactly, no randomness involved:

- **One-Time Buyers:** exactly one row in Fact_Orders per customer. No exceptions.
- **Seasonal Shoppers:** every order timestamp falls within a ±2-week window of a Holiday or Back-to-School campaign period — never outside it.
- **VIP AOV floor:** Loyal VIP orders are sampled from a multiplier range (1.3–1.6×) applied to the category baseline — never allowed to fall to a Bargain-Hunter-level price point.
- **VIP return ceiling:** Loyal VIP return probability is always the lowest of any persona for a given category, regardless of the category's base return rate.
- **Campaign attribution:** any order whose date falls inside an active `Dim_Campaign` window is assigned that `campaign_key` and has its `discount_amount` sampled from that campaign's `discount_depth` range. Orders outside any campaign window get `campaign_key = NULL`.
- **Return timing:** every return's date is 5–21 days after its originating order's date — never same-day, never past 30 days, matching a realistic retail return-window policy.
- **Signup-to-first-purchase timing:** 70% of customers place their first order within 7 days of signup (impulse/promo-driven signup); the remaining 30% show a longer gap, up to 60 days (email-list-building before conversion).
- **Flags are computed, never sampled:** `is_active_flag`, `is_repeat_customer_flag`, and `churn_risk_flag` on the snapshot fact are always calculated directly from `recency_days` and `cumulative_orders_to_date` using the exact thresholds from `design_decisions.md` — the same formula for every customer regardless of persona. Personas only shape the underlying order timestamps that recency is computed from; the flag logic itself must stay persona-blind, or a downstream churn model trained on it would just be learning the generation rules back.

---

## 8. Randomness Strategy

Every generated attribute falls into exactly one of three categories.

**Business Rule (deterministic, zero randomness):**
One-Time Buyer order count, Seasonal Shopper date window constraint, campaign attribution when an order falls in a campaign window, all three snapshot flags, return-date offset bounds, and the reconciliation between `Fact_Orders.net_revenue` and `SUM(Fact_Order_Lines.net_line_revenue)`.
*Why:* these are the specific edge cases and internal-consistency checks the project needs to guarantee exist — leaving them to chance risks generating a dataset that doesn't actually demonstrate what it's supposed to.

**Weighted Random (a genuine distribution, shaped by persona/business context):**
Persona assignment (drawn using the Section 4 population weights), order frequency per persona (sampled from a persona-specific distribution around its stated mean), per-order AOV (sampled around the category/persona price tier with noise), return probability (a weighted coin-flip using category × persona rate), acquisition channel assignment (weighted by that year's channel mix from Section 6), geography assignment (weighted toward realistic US population density, not uniform across states).
*Why:* this is what creates believable variance — real KPI distributions with a genuine center and spread, instead of either uniform noise or every customer of a given persona behaving identically.

**Pure Random (no business logic attached):**
Customer first/last name and email generation, exact time-of-day for an order timestamp, specific color/size combination within a product's category, specific city selection within an already-weighted state.
*Why:* these attributes carry zero analytical importance in this project's business questions — spending design effort making them "realistic" wouldn't be noticed by any query or dashboard that matters, so pure randomness is the right (and cheapest) choice.

---

## 9. Validation Targets

These become the pass/fail thresholds Phase 4's `validation.py` and `validation.sql` check the generated dataset against.

| Metric | Target Range |
|---|---|
| Repeat Purchase Rate (by end of 2025) | 35–45% (starting from ~15–20% in 2023) |
| Average Order Value (blended) | $65–$85 |
| Return Rate (blended) | 15–20% (Footwear 25–30%, Accessories 8–10%) |
| Campaign Revenue Share | 30–40% of annual revenue occurs during named campaign windows |
| Marketplace Share of Orders | 10–15% of order volume (lower % of revenue, given lower typical AOV) |
| Holiday Revenue Share (Nov–Dec) | 25–30% of annual revenue |
| Customer Growth Rate | +80–120% cumulative customers 2023→2024; +25–40% 2024→2025 |
| Churn-Risk Flag Prevalence | 8–12% of active customers in any given snapshot month |

If generated data falls meaningfully outside these ranges, that's a signal to revisit the generation parameters before moving to Phase 5 — not a signal to loosen the validation targets to match whatever came out.

---

## 10. Interview Section

**Build:** A persona-driven, business-rule-constrained synthetic data generator producing a 3-year (2023–2025), ~8,000-customer history for a D2C apparel brand, with deliberate business evolution, seasonality, and edge-case behavior baked in by design.

**Validate:** Generated data is checked against the explicit ranges in Section 9, plus internal reconciliation checks (order-to-order-line revenue, referential integrity across all foreign keys).

**Explain (plain language):** We simulated three years of a growing apparel brand's real behavior — acquisition, repeat purchases, seasonal spikes, returns — so the customer analytics that follow have real signal to find, instead of numbers that were decided in advance.

**Example interview questions this section should prepare you for:**
- "Why did you generate synthetic data instead of using a public dataset?"
- "How did you make sure the synthetic data wasn't just random noise with no real patterns?"
- "Walk me through how a single customer's behavior gets generated end to end."
- "How would you validate that a synthetic dataset is realistic enough to trust the analysis built on it?"
- "How did you avoid leaking your persona logic into your later analysis?" — this one is worth being ready for specifically, since the answer (personas never touch the warehouse as a stored column) is the single design decision most likely to come up.
- "What would you do differently if this were real production data instead of synthetic?"

---

## 11. Design Decisions

**Alternatives considered:**
- *Pure random generation, no personas or rules:* rejected — produces no real behavioral clusters, so RFM/cohort/churn analysis would have nothing genuine to discover.
- *A real, publicly available e-commerce dataset:* rejected — no public dataset aligns to this project's exact schema, campaign calendar, return-reason detail, or multi-year evolution, and none allow deliberately embedding the specific edge cases this project needs to demonstrate.
- *Fully deterministic generation with no randomness anywhere:* rejected — would look artificial under any real inspection, and would remove the need for genuine statistical validation in Phase 4, which is itself a skill this project is meant to demonstrate.

**Why personas:** they give the dataset real, *discoverable* behavioral clusters instead of ones handed to the analysis upfront — this is what makes Phase 6's segmentation work an actual analytical exercise instead of a lookup against a hidden answer key.

**Why weighted randomness specifically:** it's the balance point between two failure modes — too much structure (data that looks obviously gamed) and too little (data with no real signal). Weighted distributions produce genuine variance around a realistic center.

**Why a business evolution across years:** static, unchanging behavior across 2023–2025 would make every growth-rate and year-over-year metric meaningless. A visibly maturing business gives Phase 5 and Phase 8 something real to narrate — and it's also just a more honest simulation of how D2C brands actually grow.

**Why synthetic enterprise data over a static download, restated in generation-specific terms:** every decision in this document — the evolution timeline, the persona mix, the business rules — only exists because the data was designed rather than downloaded. That control is the entire point.

---

## 12. Schema Refinement Recommendations

Six additional fields were proposed. Each is evaluated against one standard: does it improve analytical value for *this* project's business questions, not just general realism.

| Field | Target Table | Recommendation | Reasoning |
|---|---|---|---|
| `brand` | Dim_Product | **Exclude** (not deferred — doesn't apply) | Solstice Apparel is a single-brand D2C business. A `brand` column implies a multi-brand catalog, which isn't this business model. Adding it would be padding with no business question behind it. Worth revisiting only if a future extension introduces a sub-brand or wholesale strategy. |
| `gender` | Dim_Product | **Include in MVP** | Cheap to add and genuinely useful — an explicit Women's/Men's/Unisex attribute cuts across category (e.g., unisex Accessories) in a way category naming alone doesn't capture, and it's a standard apparel product dimension. |
| `material` | Dim_Product | **Defer** | Has some merchandising value (e.g., material-driven return patterns) but doesn't connect to any of the twelve business questions from Phase 1. Good candidate for a future merchandising-focused extension, not the current MVP. |
| `birth_year` (not age) | Dim_Customer | **Include in MVP** | Storing `birth_year` instead of a derived `age` is the dimensionally correct choice — a static "age" column goes stale the moment it's written. Age is computed at query time (current or snapshot date minus birth_year) whenever needed. Enables an age-band segmentation cut that adds real richness to Phase 6 without much generation cost. |
| `postal_code` | Dim_Geography | **Include in MVP** | Low cost, adds real granularity below city/state, and is standard practice in a geography dimension — also opens the door to real ZIP-based demographic enrichment if this project is ever extended. Stays a flat descriptive attribute; city/state/region remain the analytical rollup levels. |
| `payment_method` | Fact_Orders | **Defer** | Has a plausible real-world story (e.g., BNPL usage as a leading indicator of return risk) but no Phase 1 business question asks about it, and including it would require yet another dimension of persona/business-rule logic in Section 7 with nothing to justify it. Flagged as a strong "how would you extend this" interview talking point rather than an MVP field. |
| `discount_percent` | Fact_Order_Lines | **Defer — compute, don't store** | Fully derivable from existing fields (`discount_amount ÷ gross_line_revenue`). Storing it duplicates information already present and risks drifting out of sync with the source fields. Same principle already applied to keep derived customer state out of Dim_Customer in Phase 2 — it belongs in a SQL view or Power BI measure, not a physical column. |
| `refund_completed_flag` | Fact_Returns | **Include in MVP** | Genuinely not derivable from anything else in the model, and it captures a real operational distinction — a return being *requested* versus the refund actually being *completed*. Directly relevant to the Operations/COO stakeholder concern from Phase 1 and cheap to add. |

**Net effect if approved:** four fields added (`gender` on Dim_Product, `birth_year` on Dim_Customer, `postal_code` on Dim_Geography, `refund_completed_flag` on Fact_Returns), four declined or deferred (`brand`, `material`, `payment_method`, `discount_percent`). This is a small, isolated patch to the already-locked Phase 2 schema, not a redesign — I'd apply it to `schema.sql`, `data_dictionary.md`, and the ER diagram as a quick follow-up once you confirm, rather than folding schema changes into this strategy document.
