# Engineering Decision Log — Customer Revenue Analytics
## Solstice Apparel

This log tracks *engineering* decisions — code structure, error-handling conventions, transaction discipline, repository layout — as distinct from `design_decisions.md`, which tracks *data warehouse architecture* decisions (schema, grain, keys). Same spirit as `schema_changelog.md`, but for how the code is built rather than how the data is modeled.

---

## ED-001 — Adoption of FPS v1.0 Repository Standards (Phase 3.2)

**Decision:** Starting with Phase 3.2, generated artifacts follow a stricter folder convention — `sql/generation/`, `sql/validation/`, `sql/verification/` as three distinct SQL responsibilities, generated CSVs under `data/generated/`, and the DuckDB file at `data/database/solstice_apparel.duckdb`.

**Why:** Phase 3.1 kept everything flatter (`sql/`, `data/` directly). That was fine at one table, but doesn't scale cleanly once every phase produces a generator, a load script, and multiple kinds of checks — a flat folder becomes a wall of similarly-named files. Splitting by responsibility (generation vs. verification vs. validation) makes the repository self-documenting: the folder a file lives in tells you what kind of check it is before you open it.

**Scope:** Repository/tooling convention only. No change to `schema.sql` or any table's grain, keys, or relationships.

---

## ED-002 — Verification and Validation as Separate Responsibilities (Phase 3.2)

**Decision:** Every table gets two distinct SQL check files: a `verification` smoke test (fast, mechanical — row count, key uniqueness, null checks, structural shape) and a `validation` suite (slower, business-aware — do the values actually make sense: valid enums, correct cross-field relationships, expected distributions, foreign-key readiness).

**Why:** These serve different moments and different failure modes. A smoke test is what you want the instant a load finishes — did it mechanically work at all. Business-rule validation is a deliberate, slower review that matters before handing data to downstream analysis. Conflating them into one file means either the smoke test gets bloated with slow business checks, or the business validation gets skipped because "the smoke test already passed."

---

## ED-003 — Explicit Exceptions Instead of `assert` for ETL Validation (Phase 3.2)

**Decision:** All in-memory data validation raises explicit, descriptive exceptions (`ValueError`, `FileNotFoundError`) rather than using `assert`.

**Why:** `assert` statements are compiled out entirely when Python runs with the `-O` optimization flag — code that relies on `assert` for data-quality gating can silently stop validating in that configuration, with no warning. Explicit `raise ValueError(...)` always executes, always carries a message describing exactly what failed and why it matters, and is catchable by name in a calling context (a test suite, a scheduler, a notebook) in a way a bare `AssertionError` with no context isn't.

**Retroactive note:** Phase 3.1's original `generate_dim_date.py` used `assert` for its in-memory checks, written before this standard was formalized. Not revisited as part of this phase per the instruction to leave Phase 3.1 alone — flagged here so the inconsistency is visible and intentional, not accidental, and so it's addressed if Phase 3.1 is ever touched again for an unrelated reason.

---

## ED-004 — Transaction-Wrapped, Idempotent Database Loads (Phase 3.2)

**Decision:** Every database load wraps DELETE+INSERT in an explicit `BEGIN TRANSACTION` / `COMMIT`, checks the post-insert row count before committing, rolls back explicitly on any mismatch or exception, and always closes the connection in a `finally` block.

**Why:** DELETE-then-INSERT is only safe to call repeatedly (the idempotency this project needs, since every generator may be re-run any number of times during development) if a failure partway through can't leave the table in a half-deleted or half-loaded state. A transaction makes "partially loaded" an impossible observable state — it's either the old data, unchanged, or the new data, fully committed, never something in between.

**How this was verified, not just asserted to be true:** for Dim_Geography, a deliberately invalid DataFrame (duplicate primary key) was fed directly into `load_to_duckdb()` to force a real `ConstraintException` mid-transaction. The table's row count was confirmed identical immediately before and immediately after the failed attempt. See `docs/phase3_build_log.md`, Phase 3.2 entry, for the full result.

---

## ED-005 — Cross-Generator Shared Reference Modules, With Per-Table Enrichment Layered On Top (Phase 3.5)

**Decision:** `generate_dim_campaign.py` imports `get_campaign_windows()` from `campaign_calendar_reference.py` (the same shared module `generate_dim_date.py` already consumes for `Dim_Date.campaign_period_flag`) rather than re-declaring the 21 campaign date windows a second time. The shared module's scope stays limited to what both consumers agree on (`campaign_name`, `campaign_type`, `start_date`, `end_date`); each consuming generator adds its own table-specific enrichment on top of that shared base rather than pushing table-specific fields into the shared module. For `Dim_Campaign`, that enrichment is `discount_depth`, `season`, `target_audience`, and `is_active_flag`.

**Why:** This is the first phase where two generators depend on the same upstream source. Duplicating the 21 campaign windows directly into `generate_dim_campaign.py` was the alternative — rejected because it reintroduces exactly the drift risk `campaign_calendar_reference.py` was created in Phase 3.1 to prevent: `Dim_Date.campaign_period_flag` and `Dim_Campaign`'s actual rows could silently disagree about a campaign's date range after any future edit to one but not the other. Importing the single source guarantees they can't drift apart. Keeping the shared module's scope narrow (dates only, not discount depth or targeting) instead of expanding it to hold everything `Dim_Campaign` needs keeps the module honest about what it actually guarantees: date consistency, not full campaign business logic.

**A related, smaller tradeoff in the same spirit:** `Dim_Campaign`'s `season` needs the same month-to-season mapping `generate_dim_date.py` uses for `Dim_Date.season`. That mapping is duplicated locally in `generate_dim_campaign.py` rather than imported, on the reasoning that generators shouldn't import each other directly (only shared reference modules should be imported), and a 12-entry constant used in exactly two places isn't enough duplication yet to justify promoting it into a shared module. If a third consumer ever needs it, that's the trigger to extract it.

**Impact:**
- `Dim_Date` and `Dim_Campaign` cannot silently disagree about a campaign's date range — both are computed from the same 21 window definitions.
- Establishes the pattern for any future table that needs to consume `campaign_calendar_reference.py` (or another shared module): import the shared source, add only your table's own enrichment on top, don't duplicate the shared part and don't bloat the shared module with fields only one consumer needs.

---



**Phase:** Phase 3.3 – Dim_Marketing_Channel

Dim_Marketing_Channel was implemented using the exact same pattern established in Phase 3.2 (ED-001 through ED-004) with no deviations: separated `build_dataframe()` / `validate_dataframe()` / `write_csv()` / `load_to_duckdb()`, explicit `ValueError`/`FileNotFoundError` exceptions with no `assert`, and a transaction-wrapped, idempotent database load with rollback re-verified under a real forced constraint violation.

The only differences from Phase 3.2 are content-level, not engineering-level: an exact row-count check (6, a closed taxonomy) instead of Dim_Geography's range check (40–50, curated real cities), and a single-source category mapping instead of Dim_Geography's two-source (raw list + region mapping) cross-check. Neither of these is a new *pattern* — they're the same validation philosophy applied to reference data with a different shape. Per the standing instruction, no new numbered entry was added for this phase.

---

## Phase 3.4 — No New Engineering Decision

**Phase:** Phase 3.4 – Dim_Sales_Channel

Dim_Sales_Channel was implemented using the exact same pattern established in Phase 3.2 and reused unchanged in Phase 3.3 (ED-001 through ED-004): separated `build_dataframe()` / `validate_dataframe()` / `write_csv()` / `load_to_duckdb()`, explicit `ValueError`/`FileNotFoundError` exceptions with no `assert`, and a transaction-wrapped, idempotent database load with rollback re-verified under a real forced constraint violation.

This table is structurally the closest repeat yet of a prior phase — same shape as Dim_Marketing_Channel (single canonical mapping, exact row count, output-side cross-check against that mapping), just smaller (3 rows vs. 6). No new validation technique, no new transaction pattern, no new file organization. Per the standing instruction, no new numbered entry was added for this phase.

---

## ED-006 — Seeded, Locally-Scoped Randomness for the First Stochastic Generator (Phase 3.6)

**Decision:** `generate_dim_product.py` is the first generator in this project whose output depends on genuine random sampling (which subcategory/gender/color/size/collection season a given SKU gets, and where its list_price falls within its category's range) rather than a fixed list, a closed taxonomy, or a date formula. Reproducibility is preserved with a fixed seed (`RANDOM_SEED = 42`) passed into a **locally-scoped** `random.Random(seed)` instance created inside `build_dataframe()`, rather than calling the global `random` module's `random.seed()` / `random.choice()`.

**Why a local RNG instance instead of global module state:** every prior generator (Phase 3.1–3.5) was fully deterministic with zero randomness, so this question never came up. Now that one exists, the risk is real: if this generator is ever run in the same Python process as other generators (e.g. a future orchestration script that builds every dimension in one pass), global `random` state would make this generator's output depend on what else had already called `random` earlier in that process — a subtle, easy-to-miss way to lose reproducibility. A `Random(seed)` instance is self-contained: its output depends only on the seed value passed to it, never on call order or any other code's use of randomness elsewhere in the same process.

**Validation implication:** `validate_dataframe()` checks properties that must hold for *any* seed (row counts per category, price ranges, cross-field consistency between category/subcategory/gender/season) rather than properties specific to seed 42's particular output. A validation suite that only passes for one specific random draw isn't really validating the business rules — it's just confirming today's draw happened to look right.

**Impact:**
- Establishes the pattern for any future generator that needs randomness (Fact_Orders, Fact_Order_Lines, Fact_Returns, and Fact_Customer_Monthly_Snapshot will all need this, per `docs/data_generation_strategy.md`'s Weighted Random / Pure Random categories): accept an explicit `seed` parameter defaulting to a documented module constant, use a locally-scoped `Random()` instance, never touch global random state.
- This was flagged as a known gap all the way back in the Phase 3.1 build log entry ("every later dimension and fact table will need an actual random seed for reproducibility") — this is that prediction being resolved, not a surprise.

---



## ED-007 — Resolving Foreign Keys by Querying Already-Loaded Parent Dimensions (Phase 3.8)

**Decision:** `generate_dim_customer.py` is the first generator with real foreign key dependencies on other *generated* dimensions (`Dim_Marketing_Channel`, `Dim_Geography`). Rather than hardcoding or re-deriving those tables' key-assignment dicts inside `generate_dim_customer.py`, it opens a **read-only** connection to the live database and queries `Dim_Marketing_Channel`/`Dim_Geography` directly to build its own name/region → surrogate-key lookups before generating a single customer row.

**Why not just import the canonical dicts from `generate_dim_marketing_channel.py` and `generate_dim_geography.py`:** that would violate ED-005's own principle — those are generators with side effects (a `main()`, file writes, database writes), not shared reference modules like `campaign_calendar_reference.py`. Importing them as libraries would be inconsistent with the boundary ED-005 already drew.

**Why querying the live database is the more correct choice, not just the available one:** it resolves foreign keys against what is *actually* in the database at generation time, not an assumption about it. If either parent table's key assignment ever changed, or was manually edited, a hardcoded dict in `generate_dim_customer.py` would silently produce wrong (or luckily-still-valid but semantically wrong) foreign keys. A live query can't drift from reality the same way. It also naturally enforces generation order: if `Dim_Marketing_Channel` or `Dim_Geography` haven't been generated and loaded yet, this generator fails immediately with a specific, descriptive error rather than producing corrupted data.

**Refinement (made during pre-execution review, before this phase was ever run):** the initial version of this check required each parent table to have an *exact* row count (6 for `Dim_Marketing_Channel`, 46 for `Dim_Geography`). That's a fragile proxy for what actually matters — it would break this generator the moment either parent dimension legitimately grew (a 7th marketing channel, a 47th city), even though nothing about `Dim_Customer`'s actual dependencies would be violated. The check now validates the real business requirement directly against the live table's *content*, not its *size*: `Dim_Marketing_Channel` must contain every channel name referenced in `CHANNEL_MIX_BY_YEAR`, and `Dim_Geography` must contain every region in `REGION_WEIGHTS` with at least one geography each (a region with zero rows can't appear as a `groupby` key, so this is one check, not two). Extra rows in either parent table beyond what's required are simply never sampled — not an error.

**Impact:**
- `validate_dataframe()` re-queries the same two tables independently of `build_dataframe()`, so foreign-key integrity is checked against the live database twice, at two different points in the pipeline, not assumed to still hold from generation time.
- Establishes the pattern for any future table with real FK dependencies on prior dimensions (`Fact_Orders`, `Fact_Order_Lines`, `Fact_Returns`, and `Fact_Customer_Monthly_Snapshot` will all need this): resolve FK values by querying the actual parent table, and validate the specific business-required subset of its content — never an exact row count, and never by hardcoding or duplicating its key-assignment logic.

---

## ED-008 — Tolerance-Based Statistical Validation for Weighted-Random Distributions (Phase 3.8)

**Decision:** Where a column's value is assigned by genuine weighted-random sampling (`Dim_Customer.acquisition_channel_key` by year-specific channel mix, `Dim_Customer.home_geography_key` by region population weighting), `validate_dataframe()` checks the realized distribution against the target within a **±5 percentage point tolerance**, not an exact count.

**Why the existing exact-count validation technique (used for `Dim_Product`'s category counts, `Dim_Campaign`'s discount-depth distribution, etc.) doesn't work here:** those were all deterministic by construction — a fixed enumeration loop, not a random draw, so the exact target count was always achievable and checking for it exactly was correct. `Dim_Customer`'s channel and region assignments are actual weighted-random draws across 2,500–8,000 samples; the realized percentage will essentially never match the target percentage exactly, even in a perfectly correct implementation. Applying exact-match validation here would fail spuriously on correct code, which would either mask real bugs (if the check were removed out of frustration) or waste time chasing a "failure" that isn't one.

**Why ±5 percentage points specifically, not an arbitrary number:** at the sample sizes involved (smallest per-group sample is 2,500), the standard error for even the smallest weight in play (5%) is under half a percentage point. A 5-point tolerance is roughly ten standard errors — wide enough that a correctly implemented sampler essentially cannot fail it by chance, narrow enough that a real bug (e.g., a year's channel weights accidentally swapped, which would produce 10–15+ point deviations) still gets caught.

**Impact:**
- Two different validation techniques now coexist deliberately in this codebase: exact-match for deterministic distributions, tolerance-band for genuinely random ones. Which one applies is determined by whether the underlying attribute is loop-driven or sampled — not a style preference.
- Establishes the pattern for any future generator with weighted-random attributes at scale (persona assignment in a future `Fact_Orders` generator will need this same technique).

---



**Phase:** Phase 3.7 – Dim_Return_Reason

Dim_Return_Reason was implemented using the exact same closed-taxonomy pattern established in Phase 3.3/3.4 (ED-001 through ED-004): a single canonical mapping (`_RETURN_REASONS`), exact row-count validation, output-side cross-check against that mapping, transaction-wrapped idempotent loading. No randomness, so ED-006 doesn't apply here — same as every closed-taxonomy table before Dim_Product.

This table does carry one genuine judgment call — mapping the glossary's "Partially" (Late Delivery) and "N/A" (Other) onto a strict `is_controllable BOOLEAN` — but that's a **business-content decision**, not an engineering-pattern one, so it's documented in `generate_dim_return_reason.py`'s module docstring and in `docs/phase3_build_log.md`'s Phase 3.7 entry rather than logged here, consistent with how Dim_Campaign's `target_audience`/`is_active_flag` MVP defaults were handled in Phase 3.5 (also content decisions, also kept out of this log). Per the standing instruction, no new numbered entry was added for this phase.

---



## ED-009 — Deterministic, Never-Persisted Persona Assignment (Phase 3.9)

**Decision:** Customer personas are computed by `order_generation_core.assign_customer_personas(customer_keys, seed)` — a dedicated `Random(seed)` instance drawing from the documented Section 4 population weights over customer_keys processed in **sorted order**. Personas are never stored in any table, never written to any CSV, and never passed between generators as data. Any generator that needs a customer's persona (Fact_Orders now; Fact_Order_Lines, Fact_Returns, Fact_Customer_Monthly_Snapshot later) calls the same function with the same seed and gets the identical assignment.

**Why:** `data_generation_strategy.md` Section 4 is explicit that personas are "generation-time logic only — never a stored column" (deliberately, so Phase 6's segmentation is a real analytical exercise, not a lookup). But multiple fact generators still need to *agree* on each customer's persona — a customer can't be a Loyal VIP in Fact_Orders and a Bargain Hunter in Fact_Returns. Deterministic recomputation from a shared function + seed gives cross-generator consistency without persistence. Sorted-key processing ensures the result doesn't depend on incidental row order from a DataFrame or query.

---

## ED-010 — Shared Order/Line-Item Generation Core for Header/Detail Reconciliation (Phase 3.9)

**Decision:** All order-simulation logic (order timing per persona, line-item composition, pricing, campaign attribution inputs) lives in `order_generation_core.py`, a shared module. `generate_fact_orders.py` calls `generate_line_items_for_order()` to compute each order's header revenue but does **not** persist the line items. The future `generate_fact_order_lines.py` will replay the identical simulation (same seed, same sorted customer processing order, same shared RNG stream) and persist what this module already computed.

**Why:** `design_decisions.md`'s reconciliation rule — SUM(net_line_revenue) per order must equal Fact_Orders.net_revenue — is only guaranteed if both tables derive from the *same* line-item simulation. Two independently-written approximations would reconcile only by luck. This extends ED-005's shared-module principle from static reference data (campaign dates) to behavioral simulation logic. The single shared RNG stream consumed in a fixed order is what makes replay exact — which is also why `build_dataframe()` sorts customers by customer_key before processing.

---

**Completion note (Phase 3.10):** ED-010 was fully realized in Phase 3.10. The complete simulation loop moved out of `generate_fact_orders.py` into `order_generation_core.simulate_orders_and_lines()` (plus `prepare_simulation_inputs()` for shared live-DB dependency resolution). The refactor was proven behavior-preserving the strongest way available: `generate_fact_orders.py` re-run post-refactor produced a **byte-identical** CSV to the pre-refactor output. Both fact generators now call the same function and persist opposite halves of the same simulated objects. One implementation detail worth recording: line-level discounts are allocated proportionally from the header discount with the rounding remainder assigned to the final line — zero additional RNG draws, and it makes SUM(line net/gross/discount) equal the header figures *exactly*, verified as 0 reconciliation failures across all 26,299 orders. No new engineering decision was required for Phase 3.10; ED-009/ED-010/ED-011 covered it fully as designed.

---

## ED-011 — Promoting the FK-Lookup Helper to a Shared Module (`db_utils.py`) (Phase 3.9)

**Decision:** `_load_dimension_lookup()` was extracted from `generate_dim_customer.py` into `python/generators/db_utils.py` as `load_dimension_lookup()`, now imported by both `generate_dim_customer.py` and `generate_fact_orders.py`.

**Why:** ED-005 deliberately left a 12-entry season dict duplicated between two generators ("not enough duplication to justify extracting... if a third generator ever needs it, that's the trigger"). This helper crossed a different threshold at its *second* consumer: it's substantial logic (read-only connection handling, existence checks, descriptive dependency-ordering errors), and every remaining fact table will need it too. Extracting at the second consumer, with a third clearly inbound, is the documented judgment call — the refactor was verified behavior-preserving by re-running `generate_dim_customer.py` (identical 8,000 rows) before Fact_Orders was built on top of it.

---

## Phase 3.11 — No New Engineering Decision

**Phase:** Phase 3.11 – Fact_Returns

Fact_Returns introduced no new engineering pattern. It composes three existing decisions: ED-007 (resolve FKs by querying live parent tables, validating business dependencies rather than row counts), ED-009 (personas recomputed deterministically from `customer_key` + seed, never persisted), and ED-011 (`db_utils.load_dimension_lookup`). The load is ED-004's transaction-wrapped idempotent DELETE+INSERT, validation raises explicit exceptions per ED-003, randomness uses a locally-scoped seeded `Random` per ED-006, and distribution targets use tolerance bands per ED-008.

**The one architectural question worth recording — why Fact_Returns does *not* replay `simulate_orders_and_lines()` (ED-010):** Fact_Order_Lines replayed the shared simulation because headers and lines are two views of *one* simulated object, and reconciliation is only guaranteed if both come from the same pass. A return is categorically different — a downstream event *about* a line that already exists and is already validated. So this generator reads the persisted `Fact_Order_Lines` as its source. Three reasons that's correct rather than convenient: it cannot perturb the frozen, byte-identical-verified order simulation (adding return draws to that RNG stream would risk exactly what Phase 3.10 proved stable); the live table is the authoritative record of what was actually sold, which is ED-007's own argument; and returns become independently regenerable without regenerating orders. **ED-010 is honoured, not bypassed** — its principle is "don't duplicate or approximate shared simulation logic," and no order-simulation logic is duplicated here.

Return logic likewise stays *in* the generator rather than a new shared module: `Fact_Customer_Monthly_Snapshot` (the only remaining table) derives order-based state, not return logic, so there is no second consumer — and ED-005's own stated threshold is not to extract until there is one.

**Content decisions, deliberately kept out of this log** (it tracks code structure, not what a field means — same boundary as Phase 3.7's Late Delivery boolean): the restocking-fee policy, the `refund_completed_flag` lag rule, the undocumented apparel return rates, and the half-up money-rounding rule. All are documented in `generate_fact_returns.py`'s docstring and `docs/phase3_build_log.md`'s Phase 3.11 entry.

---

## Phase 3.12 — No New Engineering Decision

**Phase:** Phase 3.12 – Fact_Customer_Monthly_Snapshot

The question was asked directly rather than assumed, and the answer is no. This table composes ED-001/002 (repository layout, verification vs. validation), ED-003 (explicit exceptions, never `assert`), ED-004 (transaction-wrapped idempotent load), ED-007 (live-parent lookups validating business dependencies rather than row counts), and ED-011 (`db_utils.load_dimension_lookup`). No new pattern was needed to build it.

**What's notable is which decisions deliberately do NOT apply, each for a documented reason** — the absence of a pattern is not a new pattern:

- **ED-006 (seeded randomness): N/A.** This is the only generator in the project with no randomness at all. Determinism here is *stronger* than a seed provides — not "the same seed produces the same output," but "the same inputs necessarily produce the same output." There is no seed parameter because there is nothing to sample.
- **ED-008 (tolerance validation): deliberately N/A.** Every value is exactly recomputable, so a tolerance band would be *weaker* than the data warrants. Every check in this phase is exact; the only tolerances present are one-cent money comparisons absorbing float representation, not sampling variance. This is the mirror image of ED-008's own reasoning: match the validation technique to whether the value is sampled or derived.
- **ED-009 (personas): deliberately unused.** `data_generation_strategy.md` Section 7 requires the snapshot's flag logic stay persona-blind, or a churn model trained on it in Phase 10 would just be learning the generation rules back. No persona is read anywhere in this generator. That is a positive design commitment protecting Phase 10's validity, not an omission.
- **ED-010 (replay the shared simulation): N/A.** Nothing is simulated. Every measure is derived from persisted facts.
- **ED-005 (shared module extraction): no new module.** Snapshot logic has exactly one consumer — this is Phase 3's final table — and ED-005's own stated threshold is not to extract until a second consumer exists.

Three named invariants are documented in the generator and enforced in both the Python and SQL validation suites (INVARIANT 1: revenue attribution by return date, never retroactive; INVARIANT 2: bounded, explainable negative rolling revenue; INVARIANT 3: temporal continuity of the row spine). These are *business/data* invariants, not engineering patterns, so they live in the generator docstring and `docs/phase3_build_log.md` — the same boundary applied in Phase 3.7 and Phase 3.11.

---

## Phase 4 — No New Engineering Decision

**Phase:** Phase 4 – Warehouse-Wide Validation

Asked directly rather than assumed, and the answer is no. Phase 4 composes ED-001 (existing `sql/validation/` and `sql/verification/` folders; warehouse-scope suites needed only a `validate_warehouse_*` naming convention, not a new one), ED-002 (the verification/validation split holds unchanged — ED-002's distinction is *mechanical vs business-aware*, which is orthogonal to *table-scope vs warehouse-scope*, so system-level validation is a new **scope**, not a third responsibility), and ED-003 (the runner raises explicit `FileNotFoundError`/`ValueError`, never `assert` — a malformed suite must fail loudly rather than silently validate nothing, which is precisely the failure mode ED-003 exists to prevent).

**ED-008 is deliberately excluded**, and the reasoning is the mirror image of Phase 3.12's: tolerance bands exist for *sampled-vs-target* comparisons. Phase 4 compares the warehouse *to itself*, so every check is exact and a tolerance would only hide a defect. The sole latitude is cent-level on large money aggregates, for the float/decimal reason Phase 3.11 documented.

**One candidate considered and rejected: a generation-vintage manifest table.** Tier 1 needed to detect whether all facts derive from the same vintage of their parents — a real hazard, because surrogate keys are dense 1..N and get *reused* on regeneration, so a stale parent would pass every FK check while silently referencing different products at different prices. A manifest recording each table's generation seed and timestamp was considered and rejected on two grounds: the schema is frozen (design_decisions.md), and a manifest records what we *claim* rather than verifying what is *true*. Content-based re-derivation — recomputing each fact's dependent values from its currently-loaded parents — cannot lie, needs no schema change, and is what Tier 1 implements.

New tooling introduced (`python/validation/`, first use of an existing folder in the repository layout) follows established conventions and required no new decision.

---

## Standing Convention Going Forward

Every future Phase 3.x table follows ED-001 through ED-011 by default. Deviations (if any table has a genuine reason to load differently) should get their own numbered entry here explaining why, rather than silently diverging from the pattern.
