# Phase 3 Build Log — Synthetic Data Generation
## Solstice Apparel

Running log of Phase 3, one sub-phase per table, built and verified incrementally per the Flagship Project Standard. Each entry follows Build → Validate → Explain → Interview.

---

## Phase 3.1 — Dim_Date

### Deliverables
- `python/generators/campaign_calendar_reference.py` — shared campaign date-window reference (also feeds the future Dim_Campaign generator)
- `python/generators/generate_dim_date.py` — main generator
- `python/generators/init_database.py` — one-time database initialization (applies `schema.sql`)
- `sql/load_dim_date.sql` — standalone SQL-only load path (alternative to the Python generator)
- `sql/validation/validate_dim_date.sql` — validation suite
- `data/dim_date.csv`, `data/solstice_apparel.duckdb` — generated outputs

### Expected Row Counts

| Item | Expected | Actual |
|---|---|---|
| Total rows | 1,096 (365 + 366 [2024 leap year] + 365) | 1,096 |
| Distinct `date_key` values | 1,096 | 1,096 |
| Holiday-flagged dates | 21 (7 holidays × 3 years) | 21 |
| Campaign-flagged dates | Informational, no fixed target (overlapping windows) | 436 (39.8% of days) |

### Validation Checklist

All 13 checks executed directly against `data/solstice_apparel.duckdb` — actual results, not projected:

| # | Check | Result |
|---|---|---|
| 1 | Row count = 1,096 | ✅ PASS |
| 2 | `date_key` uniqueness (0 duplicates) | ✅ PASS |
| 3 | Date range = 2023-01-01 through 2025-12-31 | ✅ PASS |
| 4 | No gaps (distinct dates = total rows) | ✅ PASS |
| 5 | Zero nulls across all 15 columns | ✅ PASS |
| 6 | `is_weekend` matches `day_of_week IN (6,7)` | ✅ PASS |
| 7 | `fiscal_quarter`/`fiscal_year` match `quarter`/`year` | ✅ PASS |
| 8 | `season` matches documented month mapping | ✅ PASS |
| 9 | Holiday count = 21 | ✅ PASS |
| 10 | Campaign day coverage (informational) | 436 days, 39.8% |
| 11 | Spot check: Black Friday 2024 (Nov 29) is Friday + holiday + campaign | ✅ PASS |
| 12 | Spot check: Christmas Day 2023 is holiday-flagged | ✅ PASS |
| 13 | Spot check: an ordinary Tuesday (Mar 26, 2024) has all three flags FALSE | ✅ PASS |

Manually eyeballed all 21 computed holiday dates against known real-world calendars (Memorial Day, Labor Day, and Thanksgiving all landed on their correct actual dates for 2023/2024/2025) — computed logic, not hardcoded, so this cross-check matters more than it would for a lookup table.

### Build

Every column in Dim_Date is a pure function of the calendar date — no randomness anywhere in this table, which makes it the simplest possible starting point for Phase 3.

- **date_key / full_date:** `date_key` is the date in `YYYYMMDD` integer form (e.g., `20240101`), which is what every fact table's foreign keys will actually store; `full_date` keeps the real `DATE` type for anything that needs native date arithmetic.
- **year / quarter / month / month_name / week_of_year / day_of_week / day_name:** all standard calendar decomposition. `day_of_week` uses Python's `isoweekday()` (Monday=1…Sunday=7) to match the convention already documented in `schema.sql`. `week_of_year` uses the ISO calendar week, which can occasionally assign the first few days of January to the last ISO week of the prior year — a normal, documented quirk of ISO week numbering, not a bug.
- **is_weekend:** `day_of_week IN (6, 7)`.
- **holiday_flag:** computed for a specific 7-holiday retail set (New Year's Day, Memorial Day, Independence Day, Labor Day, Thanksgiving, Black Friday, Christmas Day) — deliberately narrower than the full US federal holiday calendar, matching the definition already locked in `data_dictionary.md`. Memorial Day and Labor Day are computed algorithmically (last Monday of May; first Monday of September) rather than hardcoded per year, and Thanksgiving/Black Friday are computed the same way (4th Thursday of November, plus one day) — so the same code correctly handles all three years without three sets of manually-typed dates.
- **fiscal_quarter / fiscal_year:** identical to `quarter`/`year` under the documented v1.1 assumption that fiscal year = calendar year (see `design_decisions.md`).
- **season:** a fixed month-to-season lookup (Dec–Feb Winter, Mar–May Spring, Jun–Aug Summer, Sep–Nov Fall).
- **campaign_period_flag:** `TRUE` if the date falls inside *any* of the 21 campaign windows defined in the new shared `campaign_calendar_reference.py` module. This module exists specifically so Dim_Date's flag and the future Dim_Campaign table's actual rows can never drift apart — both will read the exact same 21 date ranges.

### Validate

Every check in the table above ran directly against the generated DuckDB file, not against the generation logic in isolation — this catches bugs in the load path (e.g., a column-order mismatch) that a pure in-memory test wouldn't. The generator was also re-run a second time to confirm the DELETE-then-INSERT pattern is idempotent: still exactly 1,096 rows after a second run, no duplicates.

### Explain

Dim_Date is the one table every other fact table in this warehouse joins to, so getting its logic exactly right — and provably right, not just plausibly right — matters more than its apparent simplicity suggests. A single wrong week-of-year or an off-by-one holiday date would quietly corrupt every seasonality and campaign-lift number generated downstream in Phase 5 and 6 without ever throwing an error.

### Interview

- "Why generate a date dimension instead of just using `full_date` directly in every query?" — a conformed date dimension lets every fact table share identical time-intelligence logic (fiscal periods, holiday flags, campaign windows) instead of every analyst re-deriving it ad hoc, and it's dramatically cheaper to join an integer surrogate key than to repeat date-math in every query.
- "How did you compute Thanksgiving/Black Friday without hardcoding dates?" — an nth-weekday-of-month algorithm (4th Thursday of November), so the same function is correct for any year without manual lookup.
- "How do you know your holiday and campaign date logic is actually correct, not just plausible?" — every computed holiday date was cross-checked against known real-world calendar facts for 2023–2025, and the full validation suite runs against the actual loaded table, not just the generation code.
- "Why is `campaign_period_flag` computed here instead of waiting until Dim_Campaign exists?" — decoupling: Dim_Date can be finished and verified on its own, and the shared `campaign_calendar_reference.py` module guarantees the two tables will agree once Dim_Campaign is built, rather than requiring Dim_Date to be rebuilt afterward.

---

**Phase 3.1 status: complete and verified.** Ready for Phase 3.2 on your go-ahead.

---

## Repository Standard Update (effective Phase 3.2 — FPS v1.0)

Starting with Phase 3.2, generated artifacts follow a stricter folder convention:

| Artifact type | Location |
|---|---|
| Python generators | `python/generators/` |
| SQL generation/load scripts | `sql/generation/` |
| SQL business-rule validation | `sql/validation/` |
| SQL mechanical smoke tests | `sql/verification/` |
| Generated CSVs | `data/generated/` |
| DuckDB database file | `data/database/solstice_apparel.duckdb` |

This also introduces a three-way split that Phase 3.1 didn't have: **verification** (fast, mechanical — did the load succeed) is now separate from **validation** (slower, business-aware — does the data satisfy the rules that make it usable). Phase 3.1 only had the equivalent of validation; from Phase 3.2 onward both exist as distinct files with distinct responsibilities.

---

## Phase 3.2 — Dim_Geography

### Deliverables
- `python/generators/generate_dim_geography.py` — generator (build → validate → write CSV → load)
- `sql/generation/load_dim_geography.sql` — standalone transaction-wrapped SQL load path
- `sql/verification/smoke_test_dim_geography.sql` — fast mechanical checks
- `sql/validation/validate_dim_geography.sql` — business-rule validation
- `data/generated/dim_geography.csv`, `data/database/solstice_apparel.duckdb` — generated outputs

### Expected Row Counts

| Item | Expected | Actual |
|---|---|---|
| Total rows | 40–50 (per `data_generation_strategy.md` Section 3) | 46 |
| Distinct `geography_key` values | Equal to row count | 46 |
| Regions represented | All 4 (Northeast, Midwest, South, West) | 4 |
| Cities per region | ≥ 8 each | Northeast 11, Midwest 11, South 12, West 12 |

### Validation Checklist

**Smoke test** (`sql/verification/smoke_test_dim_geography.sql`) — all against the actual loaded table:

| # | Check | Result |
|---|---|---|
| 1 | Row count > 0 | ✅ PASS (46) |
| 2 | `geography_key` no nulls, no duplicates | ✅ PASS |
| 3 | No nulls in `city`/`state`/`region`/`country` | ✅ PASS |
| 4 | Table structure includes v1.1 `postal_code` column | ✅ PASS |

**Business-rule validation** (`sql/validation/validate_dim_geography.sql`):

| # | Check | Result |
|---|---|---|
| 1 | `region` only contains the 4 valid values | ✅ PASS (empty result) |
| 2 | `postal_code` is exactly 5 digits | ✅ PASS (empty result) |
| 3 | No duplicate (city, state) pairs | ✅ PASS (empty result) |
| 4 | Every row's state matches its declared region | ✅ PASS (empty result) |
| 5 | Each region has ≥ 8 cities | ✅ PASS — 11/11/12/12 |
| 6 | No region missing entirely | ✅ PASS (empty result) |
| 7 | `geography_key` dense, contiguous, starts at 1 (FK-readiness) | ✅ PASS (1–46, no gaps) |
| 8 | `country` is consistently "United States" | ✅ PASS (empty result) |

**Transaction/rollback behavior** — deliberately tested, not assumed: a duplicate-key DataFrame was fed directly into `load_to_duckdb()` to force a real `ConstraintException` mid-transaction. The table's row count was 46 immediately before, the load correctly failed and raised, and the row count was still exactly 46 immediately after — confirming the rollback leaves no partial state. Idempotency was also re-confirmed by running the generator twice in a row (46 rows both times, no duplication).

### Build

Dim_Geography is master/reference data, not simulated behavior, so — like Dim_Date — there's no randomness in this table. What's different from Phase 3.1 is the engineering discipline wrapped around it, per the new FPS v1.0 standards:

- **`_RAW_GEOGRAPHIES`** is a hand-curated list of 46 real US cities (11 Northeast, 11 Midwest, 12 South, 12 West), each with a real ZIP code, chosen so the table is independently verifiable rather than looking synthetic.
- **`_STATE_TO_REGION`** is a canonical mapping checked against every row in `build_dataframe()` — this catches a hand-entry mistake (the wrong region next to the right state) at generation time rather than letting it surface later as an unexplained anomaly in a regional revenue chart.
- **`geography_key`** is assigned by list position, 1-indexed — deterministic because the underlying list itself never changes between runs.
- **`validate_dataframe()`** raises `ValueError` for every failure mode (row count out of range, key gaps, nulls, invalid regions, malformed postal codes, duplicate city/state pairs, thin or missing regions) — no `assert` anywhere, per the new standard.
- **`load_to_duckdb()`** wraps DELETE+INSERT in `BEGIN TRANSACTION` / `COMMIT`, checks the post-insert row count before committing, and rolls back explicitly on any mismatch or exception. The connection is always closed in a `finally` block regardless of outcome.

### Validate

Every check above ran against the real, loaded table — not against the generation logic in isolation. The transaction/rollback path specifically was exercised with a deliberately broken input (a duplicate primary key) rather than just reasoned about, since "the rollback logic looks correct" and "the rollback logic is correct" are different claims, and only one of them is checkable.

### Explain

Dim_Geography looks like the simplest table in the warehouse — a static list of cities — but it's the first one built under the stricter engineering bar (explicit exceptions, transactional loads, idempotency proven under failure, not just under the happy path). That bar matters more once Phase 3.3+ starts generating tables with actual randomness, where a silent partial load or an `assert`-based check that got compiled away would be much harder to notice than it is here.

### Interview

- "Why keep verification and validation as separate SQL files instead of one combined checklist?" — different audiences and different speeds. Verification is what you'd run in CI immediately after every load (cheap, mechanical, fails fast). Validation is a deliberate business-rule review that takes longer to reason about and matters more before handing data to analysis.
- "Why raise `ValueError` instead of using `assert` for data validation?" — `assert` statements are removed entirely when Python runs with the `-O` optimization flag, so any pipeline relying on `assert` for data-quality gating can silently stop validating in certain environments. Explicit exceptions always execute and always carry a descriptive message.
- "How did you actually verify your rollback logic works, rather than just writing it and hoping?" — fed a deliberately invalid DataFrame (duplicate primary key) directly into the loader, confirmed it raised the expected `ConstraintException`, and confirmed the table's row count was identical before and after the failed attempt.
- "Why validate the state-to-region mapping in the generator itself instead of in the SQL validation layer?" — it's checking the correctness of hand-maintained generation *input*, not the shape of the generated *output* — those are different failure modes, and catching the input mistake earlier (at generation time) is cheaper than catching it later (at validation time) after it's already been written to CSV and loaded.

### Phase Gate

All smoke-test and business-rule validation checks pass against the actual loaded table. Transaction rollback behavior has been explicitly exercised and confirmed correct under a real constraint violation, not just under the successful path. Idempotency confirmed by re-running the generator twice with identical results. No changes were required to `schema.sql` — Dim_Geography's structure was already correct as of v1.1.

**Phase 3.2 status: complete and verified. Gate passed.** Ready for Phase 3.3 on your go-ahead.

---

## Phase 3.3 — Dim_Marketing_Channel

### Deliverables
- `python/generators/generate_dim_marketing_channel.py` — generator (build → validate → write CSV → load)
- `sql/generation/load_dim_marketing_channel.sql` — standalone transaction-wrapped SQL load path
- `sql/verification/smoke_test_dim_marketing_channel.sql` — fast mechanical checks
- `sql/validation/validate_dim_marketing_channel.sql` — business-rule validation
- `data/generated/dim_marketing_channel.csv`, `data/database/solstice_apparel.duckdb` — generated outputs

### Expected Row Counts

| Item | Expected | Actual |
|---|---|---|
| Total rows | Exactly 6 (closed taxonomy per `business_glossary.md`, not a range) | 6 |
| Distinct `marketing_channel_key` values | 6 | 6 |
| `channel_category` = Paid | 3 (Paid Social, Paid Search, Affiliate/Referral) | 3 |
| `channel_category` = Organic | 2 (Organic/SEO, Direct) | 2 |
| `channel_category` = Owned | 1 (Email/SMS) | 1 |

### Validation Checklist

**Smoke test** (`sql/verification/smoke_test_dim_marketing_channel.sql`) — all against the actual loaded table:

| # | Check | Result |
|---|---|---|
| 1 | Row count = 6 | ✅ PASS |
| 2 | `marketing_channel_key` no nulls, no duplicates | ✅ PASS |
| 3 | No nulls in `channel_name`/`channel_category` | ✅ PASS |
| 4 | Table structure matches `schema.sql` | ✅ PASS |

**Business-rule validation** (`sql/validation/validate_dim_marketing_channel.sql`):

| # | Check | Result |
|---|---|---|
| 1 | `channel_category` only contains the 3 valid values | ✅ PASS (empty result) |
| 2 | `channel_name` matches the documented taxonomy exactly, no extras | ✅ PASS (empty result) |
| 3 | Every documented channel is actually present (reverse check) | ✅ PASS (empty result) |
| 4 | No duplicate `channel_name` | ✅ PASS (empty result) |
| 5 | Every channel's category matches the canonical mapping | ✅ PASS (empty result) |
| 6 | Exact distribution: 3 Paid / 2 Organic / 1 Owned | ✅ PASS |
| 7 | No category missing entirely | ✅ PASS (empty result) |
| 8 | `marketing_channel_key` dense, contiguous, starts at 1 (FK-readiness) | ✅ PASS (1–6, no gaps) |

**In-memory validation, independently stress-tested:** four scenarios run directly against `validate_dataframe()` before touching the database — (1) valid data passes cleanly, (2) a right-channel/wrong-category mismatch (`Email/SMS` mislabeled `Paid`) correctly raises `ValueError`, (3) a fabricated category value (`"Referral-Based"`) correctly raises `ValueError`, (4) a truncated 5-row DataFrame correctly raises `ValueError` citing the exact expected count. All four behaved as expected.

**Transaction/rollback behavior** — same standard as Phase 3.2, re-exercised for this table specifically: a duplicate-key DataFrame was fed into `load_to_duckdb()`, producing a real `ConstraintException`. Row count was 6 immediately before, 6 immediately after. Idempotency reconfirmed by running the generator twice in a row (6 rows both times).

### Build

Dim_Marketing_Channel is the smallest table built so far — a closed, 6-row taxonomy rather than a range like Dim_Geography's 40–50 cities. That difference in shape drove the one real content-level decision this phase:

- **Exact row count instead of a range.** Dim_Geography's row count is allowed to vary (40–50, real cities, some reasonable curation latitude). Dim_Marketing_Channel's 6 channels are a closed business definition already locked in `business_glossary.md` — a 7th channel appearing here would mean the glossary and the warehouse had silently drifted apart, so `validate_dataframe()` checks for an exact match, not a range.
- **Single source, not two independent ones.** Dim_Geography's `_RAW_GEOGRAPHIES` list and `_STATE_TO_REGION` mapping were two separate hand-typed things that needed cross-checking against each other. Here there's only one canonical dict (`_CHANNEL_CATEGORY`), so `build_dataframe()` doesn't need an input-consistency check the way Dim_Geography's did — but `validate_dataframe()` still cross-checks the generated *output* against that same dict, which catches a mistake introduced by some future edit that changes the dict without updating both key and value together.
- Everything else — `build_dataframe()` / `validate_dataframe()` / `write_csv()` / `load_to_duckdb()` separation, transaction-wrapped idempotent loading, explicit `ValueError`/`FileNotFoundError` exceptions, no `assert` — is identical in structure to Phase 3.2. No new pattern was needed.

### Validate

Same bar as Phase 3.2: every check ran against the real, loaded table, not just the generation logic in isolation. This phase went one step further on the in-memory side — four specific bad-data scenarios (wrong category, invalid category, wrong row count, and the happy path) were each independently run against `validate_dataframe()` directly, confirming the exception messages are both raised and descriptive, not just present.

### Explain

This table is deliberately unglamorous — six rows, no randomness, no complex business logic — because its job is to be a stable, unambiguous reference point. Every customer's acquisition channel and every order's channel attribution in later phases resolves through this table's 6 rows; if this table is wrong, every marketing-attribution number in Phase 5/6/8 is wrong in a way that's hard to trace back to the source.

### Interview

- "Why validate for an exact row count here but a range for Dim_Geography?" — different kinds of reference data. City lists have legitimate curation latitude; a channel taxonomy is a closed business definition already fixed in the glossary, so any deviation is a bug, not a design choice.
- "Since this table has no complex cross-check like Dim_Geography's state/region mapping, why still validate the category mapping in `validate_dataframe()`?" — the dict being a single source doesn't mean it's immune to being edited incorrectly later; validating the generated output against the canonical mapping is cheap insurance against a future one-sided edit.
- "How do you know your `ValueError` messages actually fire correctly, not just in theory?" — ran four specific bad-data scenarios directly against the validation function and confirmed each raised the expected exception with an accurate, specific message — not just reasoning about what the code should do.
- "What would break downstream if this table silently had 7 rows instead of 6?" — every join from `Fact_Orders.acquisition_channel_key` or `Dim_Customer.acquisition_channel_key` would still technically work, but any channel-level revenue rollup or attribution report would show a channel that doesn't exist in the documented business glossary — exactly the kind of quiet, hard-to-trace inconsistency the exact-count check exists to prevent.

### Phase Gate

All smoke-test and business-rule validation checks pass against the actual loaded table. Four in-memory validation failure scenarios were independently exercised and behaved correctly. Transaction rollback behavior was re-confirmed under a real constraint violation specific to this table. Idempotency confirmed by re-running the generator twice with identical results. No changes were required to `schema.sql`. No new engineering decision was introduced — see `docs/engineering_decision_log.md`.

**Phase 3.3 status: complete and verified. Gate passed.** Ready for Phase 3.4 on your go-ahead.

---

## Phase 3.4 — Dim_Sales_Channel

### Deliverables
- `python/generators/generate_dim_sales_channel.py` — generator (build → validate → write CSV → load)
- `sql/generation/load_dim_sales_channel.sql` — standalone transaction-wrapped SQL load path
- `sql/verification/smoke_test_dim_sales_channel.sql` — fast mechanical checks
- `sql/validation/validate_dim_sales_channel.sql` — business-rule validation
- `data/generated/dim_sales_channel.csv`, `data/database/solstice_apparel.duckdb` — generated outputs

### Expected Row Counts

| Item | Expected | Actual |
|---|---|---|
| Total rows | Exactly 3 (closed taxonomy per `business_glossary.md`, not a range) | 3 |
| Distinct `sales_channel_key` values | 3 | 3 |
| `channel_type` = Owned | 2 (Website, Mobile App) | 2 |
| `channel_type` = Third-Party | 1 (Marketplace) | 1 |

### Validation Checklist

**Smoke test** (`sql/verification/smoke_test_dim_sales_channel.sql`) — all against the actual loaded table:

| # | Check | Result |
|---|---|---|
| 1 | Row count = 3 | ✅ PASS |
| 2 | `sales_channel_key` no nulls, no duplicates | ✅ PASS |
| 3 | No nulls in `channel_name`/`channel_type` | ✅ PASS |
| 4 | Table structure matches `schema.sql` | ✅ PASS |

**Business-rule validation** (`sql/validation/validate_dim_sales_channel.sql`):

| # | Check | Result |
|---|---|---|
| 1 | `channel_type` only contains the 2 valid values | ✅ PASS (empty result) |
| 2 | `channel_name` matches the documented taxonomy exactly, no extras | ✅ PASS (empty result) |
| 3 | Every documented channel is actually present (reverse check) | ✅ PASS (empty result) |
| 4 | No duplicate `channel_name` | ✅ PASS (empty result) |
| 5 | Every channel's type matches the canonical mapping | ✅ PASS (empty result) |
| 6 | Exact distribution: 2 Owned / 1 Third-Party | ✅ PASS |
| 7 | No type missing entirely | ✅ PASS (empty result) |
| 8 | `sales_channel_key` dense, contiguous, starts at 1 (FK-readiness) | ✅ PASS (1–3, no gaps) |

**In-memory validation, independently stress-tested:** four scenarios run directly against `validate_dataframe()` — (1) valid data passes cleanly, (2) `Marketplace` mislabeled `Owned` correctly raises `ValueError`, (3) a fabricated type value (`"Wholesale"`) correctly raises `ValueError`, (4) a truncated 2-row DataFrame correctly raises `ValueError` citing the exact expected count. All four behaved as expected.

**Transaction/rollback behavior** — same standard as Phase 3.2/3.3: a duplicate-key DataFrame was fed into `load_to_duckdb()`, producing a real `ConstraintException`. Row count was 3 immediately before, 3 immediately after. Idempotency reconfirmed by running the generator twice in a row (3 rows both times).

### Build

Dim_Sales_Channel is structurally the same shape as Phase 3.3's Dim_Marketing_Channel, just smaller — 3 rows instead of 6, one canonical mapping (`_CHANNEL_TYPE`) instead of `_CHANNEL_CATEGORY`. No new pattern was needed:

- **Exact row count (3), not a range** — same reasoning as Phase 3.3: this is a closed business definition already locked in `business_glossary.md`, not a curated-but-flexible list.
- **Single source, output-side cross-check** — same as Phase 3.3: `validate_dataframe()` checks the generated output against `_CHANNEL_TYPE` directly, since there's no second independent source to reconcile against (unlike Dim_Geography's state/region split).
- `build_dataframe()` / `validate_dataframe()` / `write_csv()` / `load_to_duckdb()` separation, transaction-wrapped idempotent loading, explicit `ValueError`/`FileNotFoundError` exceptions, no `assert` — identical in structure to Phase 3.2 and 3.3.

### Validate

Same bar as Phase 3.2/3.3: every check ran against the real, loaded table. Four bad-data scenarios (wrong type, invalid type, wrong row count, happy path) were independently run against `validate_dataframe()` directly, and the transaction rollback was forced with a real duplicate-key `ConstraintException`, not just reasoned about.

### Explain

Small as it is, this table sits directly under `Fact_Orders.sales_channel_key`, and it's the one that will let Phase 5/8 answer a real business tension already flagged in `business_understanding.md`: owned-channel revenue (Website, Mobile App) vs. marketplace revenue, where the business gives up margin and the customer relationship in exchange for volume. Three rows, but not a throwaway table.

### Interview

- "Why does this table only need 3 rows and Dim_Marketing_Channel needed 6?" — different business concepts. Sales channel is *where* a transaction happened (3 real options for this business); marketing channel is *how* the customer was acquired (6 documented acquisition paths). Conflating them into one dimension would blur "where you bought" with "how you found us," which are genuinely different analytical axes.
- "Why is `channel_type` Owned/Third-Party instead of reusing Marketing Channel's Paid/Organic/Owned categories?" — they answer different questions. Sales channel type is about business-model exposure (do we own this customer relationship and the full margin, or share both with a marketplace); marketing channel category is about acquisition cost structure. Same word ("Owned") can appear in both without them being the same concept.
- "What would a marketplace-heavy revenue mix mean for this business?" — higher volume, likely lower margin (marketplace fees), and weaker direct customer relationship data (email, retention touchpoints) — exactly the kind of tension `Fact_Orders.sales_channel_key` joined to `Dim_Sales_Channel.channel_type` is built to surface in Phase 5/8.
- "How did you keep four phases in a row consistent without copy-paste drift?" — every table doc explains not just what changed from the prior phase but *why* it didn't need to change more than that — Phase 3.4's build log entry is explicit that this is the same pattern as 3.3, sized down, not a new design.

### Phase Gate

All smoke-test and business-rule validation checks pass against the actual loaded table. Four in-memory validation failure scenarios were independently exercised and behaved correctly. Transaction rollback behavior was re-confirmed under a real constraint violation specific to this table. Idempotency confirmed by re-running the generator twice with identical results. No changes were required to `schema.sql`. No new engineering decision was introduced — see `docs/engineering_decision_log.md`.

**Phase 3.4 status: complete and verified. Gate passed.** Ready for Phase 3.5 on your go-ahead.

---

## Phase 3.5 — Dim_Campaign

**Status: implementation generated, NOT yet executed.** Per explicit instruction for this phase, no generator run, no SQL executed, no results assumed. Everything below marked "Expected" is hand-derived from the already-verified Phase 3.1 campaign date calculations (Thanksgiving/Black Friday/Cyber Monday dates were empirically confirmed when `campaign_calendar_reference.py` was first built and run), not newly assumed — but the actual execution of *this* generator, and the SQL checks against a real loaded table, are pending independent review before anything runs.

### Deliverables
- `python/generators/generate_dim_campaign.py` — generator (build → validate → write CSV → load), consumes `campaign_calendar_reference.py` rather than duplicating campaign definitions
- `sql/generation/load_dim_campaign.sql` — standalone transaction-wrapped SQL load path
- `sql/verification/smoke_test_dim_campaign.sql` — fast mechanical checks
- `sql/validation/validate_dim_campaign.sql` — business-rule validation
- `data/generated/dim_campaign.csv`, `data/database/solstice_apparel.duckdb` — not yet generated/updated as of this entry

### Expected Row Counts (hand-derived, not yet executed)

| Item | Expected |
|---|---|
| Total rows | Exactly 21 (7 named campaigns × 3 years, per `campaign_calendar_reference.py`) |
| Distinct `campaign_key` values | 21 |
| `campaign_type` = Promotional Sale | 12 (Summer Sale, Back-to-School, Black Friday, Cyber Monday × 3 years) |
| `campaign_type` = Seasonal Launch | 6 (Spring Collection Launch, Holiday Collection × 3 years) |
| `campaign_type` = Clearance | 3 (January Clearance × 3 years) |
| `discount_depth` = None / Light / Moderate / Deep / Deepest | 3 / 3 / 6 / 6 / 3 |
| `season` = Winter / Fall / Summer / Spring | 8 / 7 / 6 / **0** |

**The Spring=0 result is a deliberate, documented consequence, not a gap to fix:** "Spring Collection Launch" starts February 15 every year, which is calendar Winter under the same month-to-season mapping `Dim_Date` uses. No campaign in this calendar has a start date that falls in March–May. This was hand-traced from the already-verified Phase 3.1 Thanksgiving/Black Friday dates (Nov 23/24 2023, Nov 28/29 2024, Nov 27/28 2025) plus each campaign's fixed start month, cross-checked row by row for all 21 instances — not assumed.

### Validation Checklist (expected — pending execution)

**Smoke test** (`sql/verification/smoke_test_dim_campaign.sql`) — 5 checks: row count, key integrity, full NOT NULL sweep, `end_date >= start_date` sanity read, structural shape.

**Business-rule validation** (`sql/validation/validate_dim_campaign.sql`) — 14 checks, deliberately more than Phase 3.4's 8, matching this table's larger schema rather than being scaled down to match Phase 3.4's row count:

| # | Check |
|---|---|
| 1–4 | Enum membership: `campaign_type`, `discount_depth`, `season`, `target_audience` |
| 5 | No duplicate `campaign_name` |
| 6 | `end_date >= start_date` re-confirmed against the loaded table |
| 7 | Every campaign's `discount_depth` matches the canonical business_glossary mapping |
| 8 | Every campaign appears in exactly 3 distinct years (structural completeness) |
| 9–11 | Exact distribution checks: `discount_depth`, `campaign_type`, `season` (including the explicit Spring=0 expectation) |
| 12 | `target_audience` uniformly "All Customers" (documented MVP scope) |
| 13 | `is_active_flag` uniformly TRUE |
| 14 | FK-readiness: `campaign_key` dense, contiguous, starts at 1 |

**In-memory validation, four scenarios planned for independent execution** (same pattern as Phase 3.3/3.4, not yet run): (1) happy path, (2) a discount_depth mismatch against the canonical mapping, (3) a fabricated enum value, (4) a truncated row count. Expected to behave identically to prior phases' equivalent tests — to be confirmed, not assumed.

**Transaction/rollback behavior — planned, not yet exercised:** a duplicate-`campaign_key` DataFrame fed into `load_to_duckdb()` is expected to raise `ConstraintException` and leave the table's row count unchanged, matching Phase 3.2/3.3/3.4's confirmed behavior. This specific table has not yet had this forced.

### Build

Two things make this phase structurally different from Phase 3.2–3.4, both explained in `engineering_decision_log.md` ED-005:

- **First cross-generator dependency.** `generate_dim_campaign.py` is the first generator in this project that imports from another generator-adjacent module (`campaign_calendar_reference.py`) instead of being fully self-contained. This reuses the exact 21 date windows `generate_dim_date.py` already consumes for `campaign_period_flag`, so the two tables cannot silently disagree about when a campaign ran.
- **Enrichment layered on top of a shared base**, not pushed into the shared module. `campaign_calendar_reference.py`'s scope stays limited to dates; `discount_depth`, `season`, `target_audience`, and `is_active_flag` are added by this generator specifically. `season` reuses the same month-based logic as `Dim_Date.season`, duplicated locally rather than imported (documented tradeoff — see ED-005).

Otherwise, `build_dataframe()` / `validate_dataframe()` / `write_csv()` / `load_to_duckdb()` separation, transaction-wrapped idempotent loading, and explicit `ValueError`/`FileNotFoundError` exceptions are unchanged from Phase 3.2–3.4.

### Validate

**Not yet performed.** This section will be completed after independent execution confirms (or corrects) the expected values above against the actual loaded table.

### Explain

`Dim_Campaign` is the first dimension in this project that's genuinely derived rather than either a calendar (`Dim_Date`) or a flat business taxonomy (`Dim_Marketing_Channel`, `Dim_Sales_Channel`) — it enriches a shared date source with business logic (discount depth, calendar season) that has to stay internally consistent across 21 rows spanning 3 years. The Spring=0 season result is the clearest example of why that consistency matters: a naive read of the data ("no Spring campaigns?") looks like a bug until you trace it back to a single, consistently-applied rule.

### Interview

- "Why does `Dim_Campaign` import from `campaign_calendar_reference.py` instead of just defining its own campaign list?" — that module already exists specifically to guarantee `Dim_Date.campaign_period_flag` and `Dim_Campaign`'s rows agree on dates; redefining the calendar a second time would reintroduce the exact drift risk that module was built in Phase 3.1 to prevent.
- "Why is there no 'Spring' campaign in a table that includes a 'Spring Collection Launch'?" — season is a calendar fact (computed from the literal start-date month, using the same rule as `Dim_Date`), not a copy of the campaign's marketing name. Spring Collection Launch starts February 15, which is calendar Winter under that rule. The name carries the marketing framing; the `season` column stays a consistent, mechanically-computed BI attribute.
- "Why duplicate the month-to-season mapping instead of importing it from `generate_dim_date.py`?" — generators shouldn't import each other directly, only shared reference modules should be imported. A 12-entry constant used in exactly two places is a reasonable, documented duplication — not enough repetition yet to justify a new shared module.
- "Why is `target_audience` the same value on every row?" — the shared campaign calendar defines 21 general campaign instances, not separate VIP-only or win-back-specific campaigns. The schema's other target_audience values are valid and real, just not populated by any row in this generation — that would require distinct campaign rows a future phase could add, not a change to this generator.
- "Why does this table's validation have more checks than Dim_Sales_Channel's, even though Dim_Sales_Channel came right before it?" — the two tables aren't the same shape. Dim_Sales_Channel is a flat 2-column lookup; Dim_Campaign is a 6-attribute enrichment layer with real cross-field relationships (campaign → discount depth, date → season) that need checking. Matching validation depth to a table's actual complexity, not to precedent for its own sake, is the standard — see the "equal or better, not simplified" instruction this phase followed.

### Phase Gate

**Not yet reached.** Implementation is complete and internally consistent by hand-trace, but execution, smoke testing, business validation, idempotency verification, and rollback testing are all pending independent review, per this phase's explicit scope (implementation only, no execution).

**Phase 3.5 status: implementation complete, execution pending.** Not yet ready for Phase 3.6 — awaiting independent review and Phase Gate on this phase first.

---

## Phase 3.6 — Dim_Product

**Status: implementation generated, NOT yet executed.** No generator run, no SQL executed, no results assumed, per explicit instruction for this phase. All figures below are hand-derived from `CATEGORY_PLAN` (the fixed business rule in `generate_dim_product.py`), not from an actual run.

### Deliverables
- `python/generators/generate_dim_product.py` — generator (build → validate → write CSV → load); first generator requiring genuine random sampling
- `sql/generation/load_dim_product.sql` — standalone transaction-wrapped SQL load path
- `sql/verification/smoke_test_dim_product.sql` — fast mechanical checks
- `sql/validation/validate_dim_product.sql` — business-rule validation (15 checks, the largest suite in Phase 3 to date)
- `data/generated/dim_product.csv`, `data/database/solstice_apparel.duckdb` — not yet generated/updated as of this entry

### Expected Row Counts (hand-derived from CATEGORY_PLAN, not yet executed)

| Category | Expected SKUs | Price Range | Cost % |
|---|---|---|---|
| Womenswear | 45 | $28–$120 | 40% |
| Menswear | 35 | $25–$110 | 40% |
| Outerwear | 30 | $90–$280 | 35% |
| Footwear | 30 | $60–$180 | 45% |
| Accessories | 40 | $15–$65 | 30% |
| **Total** | **180** | | |

Because this table uses real random sampling (fixed seed 42, per ED-006), the *specific* subcategory/color/size/price for any given `product_key` cannot be hand-predicted the way Dim_Campaign's fully-derived rows could — only the aggregate, rule-level expectations below can be stated with confidence ahead of execution.

### Validation Checklist (expected — pending execution)

**Smoke test** (`sql/verification/smoke_test_dim_product.sql`) — 6 checks: row count, `product_key` integrity, `product_id` integrity, full NOT NULL sweep (excluding nullable `size`/`color`), price non-negativity, structural shape.

**Business-rule validation** (`sql/validation/validate_dim_product.sql`) — 15 checks, the largest validation suite in Phase 3 to date, matched to this table's actual complexity:

| # | Check |
|---|---|
| 1–3 | Enum membership: `category`, `gender`, `collection_season` |
| 4 | `product_id` matches the `PRD-####` pattern |
| 5 | Row count per category matches the plan exactly (45/35/30/30/40) |
| 6 | `subcategory` belongs to its category's allowed list |
| 7 | `gender` belongs to its category's allowed options (Womenswear always Women's, Menswear always Men's) |
| 8 | `list_price` falls within its category's documented range |
| 9 | `unit_cost` matches `list_price × cost_pct` within rounding tolerance |
| 10 | `unit_cost` never reaches or exceeds `list_price` (positive margin) |
| 11 | `collection_season` respects each category's Spring/Holiday lean |
| 12 | `size` business rule: NULL only for no-size accessory subcategories, correct vocabulary otherwise |
| 13 | `color` is never null (generator-level expectation) |
| 14 | `is_active` uniformly TRUE |
| 15 | FK-readiness: `product_key` dense, contiguous, starts at 1 |

**In-memory validation and rollback testing — planned, not yet exercised.** Expected to follow the same pattern confirmed in Phase 3.2–3.5 (forced constraint violation via duplicate `product_key`, row count identical before/after) — to be confirmed, not assumed.

### Build

This phase is a genuine step up in complexity from every prior dimension, for one specific reason: **it's the first table with real randomness.** Dim_Date, Dim_Geography, Dim_Marketing_Channel, Dim_Sales_Channel, and Dim_Campaign were all either fixed lists or formula-derived — the same seed (or no seed at all) always produces the same output because there's no actual random sampling involved. Dim_Product needs genuine variety (180 SKUs shouldn't all look alike) while staying reproducible, which is what ED-006 addresses: a fixed seed through a locally-scoped `Random()` instance, not global module state.

The randomness itself is classified using the exact three-way framework from `docs/data_generation_strategy.md` Section 8 (Business Rule / Weighted Random / Pure Random), applied here to product attributes instead of customer behavior:
- **Business Rule:** SKU count, price range, and cost % per category; which subcategories/genders are valid per category; which subcategories carry no size.
- **Weighted Random:** subcategory, gender, and collection season sampled from each category's valid options; list_price sampled within the category's range.
- **Pure Random:** color and size, within whatever vocabulary is valid for that SKU.

### Validate

**Not yet performed.** This section will be completed after independent execution confirms (or corrects) the expected values above against the actual loaded table.

### Explain

Every prior dimension was small enough to hand-verify in full. This one isn't — 180 rows with 5 categories' worth of interacting business rules (subcategory validity, gender validity, price range, margin, seasonal lean, size vocabulary) is exactly the point where "the smoke test passed" stops being enough evidence, and cross-field business validation earns its place as a separate, deliberate step rather than an afterthought.

### Interview

- "Why does this table need randomness when none of the previous five did?" — those five were either fixed reference data (cities, channels) or fully determined by a formula (campaign dates, calendar seasons). A 180-SKU product catalog needs actual variety — if every Womenswear SKU had the same subcategory/color/price, it wouldn't be a useful catalog to build analytics on top of.
- "How do you keep random data reproducible?" — a fixed seed, but specifically through a locally-scoped `random.Random(seed)` instance rather than the global `random` module, so this generator's output can never be affected by what other code in the same process has already done with randomness.
- "Why validate ranges and cross-field rules instead of just checking the row count?" — row count alone can't catch a Menswear SKU with `gender='Women's'` or a Footwear item priced like an Accessory. The validation has to check the actual business rules a random generator could violate, not just confirm the machinery ran.
- "Why is there no 'Spring' Footwear-specific rule, unlike Womenswear/Menswear?" — Footwear doesn't have a documented seasonal lean in `data_generation_strategy.md` the way apparel (Spring Collection) and gift-leaning categories (Holiday Collection) do, so it draws from the full 6-value collection season set rather than being restricted — a deliberate absence of a rule, not a missing one.
- "What would you change if this table needed to be regenerated with more SKUs later?" — only `CATEGORY_PLAN`'s `sku_count` values would need to change; every downstream check (`EXPECTED_ROW_COUNT`, per-category count validation) is derived from that same dict, not hardcoded separately, so the row-count expectations update automatically.

### Phase Gate

**Not yet reached.** Implementation is complete and internally consistent by construction (every check in `validate_dataframe()` mirrors a rule actually encoded in `CATEGORY_PLAN`), but execution, smoke testing, business validation, idempotency verification, and rollback testing are all pending independent review, per this phase's explicit scope (implementation only, no execution).

**Phase 3.6 status: implementation complete, execution pending.** Not yet ready for Phase 3.7 — awaiting independent review and Phase Gate on this phase first.

---

## Phase 3.7 — Dim_Return_Reason

**Status: implementation complete. Execution pending. Phase Gate pending.** No generator run, no SQL executed, no results assumed, per explicit instruction for this phase.

### Deliverables
- `python/generators/generate_dim_return_reason.py` — generator (build → validate → write CSV → load)
- `sql/generation/load_dim_return_reason.sql` — standalone transaction-wrapped SQL load path
- `sql/verification/smoke_test_dim_return_reason.sql` — fast mechanical checks
- `sql/validation/validate_dim_return_reason.sql` — business-rule validation
- `data/generated/dim_return_reason.csv`, `data/database/solstice_apparel.duckdb` — not yet generated/updated as of this entry

### Expected Row Counts (hand-derived from `_RETURN_REASONS`, not yet executed)

| Item | Expected |
|---|---|
| Total rows | Exactly 6 (closed taxonomy per `business_glossary.md`) |
| Distinct `return_reason_key` values | 6 |
| `is_controllable` = TRUE | 4 (Wrong Size, Defective/Quality Issue, Not as Described, Late Delivery) |
| `is_controllable` = FALSE | 2 (Changed Mind, Other) |

### The One Real Judgment Call This Phase Makes

`docs/business_glossary.md`'s Return Reasons table has two entries that don't map cleanly onto `schema.sql`'s strict `is_controllable BOOLEAN NOT NULL`:

- **Late Delivery** is documented as "Partially (logistics fix)" — mapped to **TRUE**. Partial controllability still means a real lever exists (carrier choice, delivery-time buffers, warehouse SLAs), unlike Changed Mind, where the business has zero actionable lever over a customer's personal preference change.
- **Other** is documented as "N/A" — mapped to **FALSE**. An unclassified catch-all has no specific fix to point to, so the conservative default is "not controllable" rather than overclaiming actionability.

This is a **business-content decision, not an engineering-pattern one** — it doesn't get an `engineering_decision_log.md` entry (that log is scoped to code structure/transactions/error handling), the same treatment Dim_Campaign's `target_audience`/`is_active_flag` MVP defaults got in Phase 3.5. Full reasoning lives in `generate_dim_return_reason.py`'s module docstring.

### Validation Checklist (expected — pending execution)

**Smoke test** (`sql/verification/smoke_test_dim_return_reason.sql`) — 4 checks: row count, key integrity, full NOT NULL sweep, structural shape.

**Business-rule validation** (`sql/validation/validate_dim_return_reason.sql`) — 6 checks:

| # | Check |
|---|---|
| 1 | `reason_code` matches the documented taxonomy exactly, no extras |
| 1b | Every documented reason is actually present (reverse check) |
| 2 | No duplicate `reason_code` |
| 3 | Every reason's `is_controllable` matches the canonical mapping (including the Late Delivery/Other judgment calls above) |
| 4 | Exact distribution: 4 TRUE / 2 FALSE |
| 5 | Both `is_controllable` values actually represented |
| 6 | FK-readiness: `return_reason_key` dense, contiguous, starts at 1 |

**In-memory validation and rollback testing — planned, not yet exercised.** Expected to follow the same pattern confirmed in Phase 3.2–3.6 (forced constraint violation via duplicate `return_reason_key`, row count identical before/after) — to be confirmed, not assumed.

### Build

Structurally this is the closest repeat yet of Phase 3.3/3.4's pattern — single canonical dict, exact row count, output-side cross-check, no randomness. The one addition worth noting in the code itself: `validate_dataframe()` explicitly checks that `is_controllable` values are real Python `bool` instances, not truthy strings or integers — a check none of the previous string-valued closed taxonomies needed, since this is the first Dim_* table with a boolean business attribute rather than a categorical string one.

### Validate

**Not yet performed.** This section will be completed after independent execution confirms (or corrects) the expected values above against the actual loaded table.

### Explain

This table looks like the simplest kind of lookup — six rows, a code, a description, a flag — but the flag is the entire point of the table existing. `is_controllable` is what will let Phase 8 separate "returns we can fix" from "returns that are just customer preference," and that distinction only works if the boolean mapping was made deliberately, not by accident when a nuanced glossary answer got forced into a strict data type.

### Interview

- "Why does a 6-row lookup table need its own documented business judgment call?" — because two of the six real-world answers weren't binary ("partially," "N/A"), and a schema with a strict BOOLEAN column forces a decision either way. Making that decision silently would bury a real business judgment inside what looks like a trivial data-entry choice.
- "Why is Late Delivery TRUE and not FALSE, given it's only 'partially' controllable?" — the test isn't "is it 100% controllable," it's "does the business have any lever at all." Late delivery has real, actionable levers (carrier SLAs, buffer times); Changed Mind doesn't. That's the line the flag is meant to draw.
- "Why isn't this in the engineering decision log?" — that log tracks code structure and error-handling conventions; this is a decision about what a piece of business data means, which belongs next to the table's own documentation, not the engineering log — same boundary applied to Dim_Campaign's MVP defaults in Phase 3.5.
- "Why validate that is_controllable values are real booleans, when no prior table needed that check?" — every previous closed taxonomy had string-valued business attributes (category, channel type); this is the first with a boolean one, and a boolean-shaped string ("True") would pass a naive equality check while being the wrong type entirely.

### Phase Gate

**Not yet reached.** Implementation is complete and internally consistent by construction, but execution, smoke testing, business validation, idempotency verification, and rollback testing are all pending independent review, per this phase's explicit scope (implementation only, no execution).

**Phase 3.7 status: implementation complete, execution pending.** Not yet ready for Phase 3.8 — awaiting independent review and Phase Gate on this phase first.

---

## Phase 3.8 — Dim_Customer

**Status: implementation complete. Execution pending. Phase Gate pending.** No generator run, no SQL executed, no results assumed, per explicit instruction for this phase.

### Deliverables
- `python/generators/generate_dim_customer.py` — generator (build → validate → write CSV → load); first generator with real FK dependencies on other generated tables
- `sql/generation/load_dim_customer.sql` — standalone transaction-wrapped SQL load path
- `sql/verification/smoke_test_dim_customer.sql` — fast mechanical checks (7 checks)
- `sql/validation/validate_dim_customer.sql` — business-rule and statistical validation (10 checks, largest suite in Phase 3 to date)
- `data/generated/dim_customer.csv`, `data/database/solstice_apparel.duckdb` — not yet generated/updated as of this entry

### Expected Row Counts (hand-derived from `CUSTOMERS_BY_YEAR`/`CHANNEL_MIX_BY_YEAR`/`REGION_WEIGHTS`, not yet executed)

| Item | Expected |
|---|---|
| Total rows | Exactly 8,000 (2,500 + 3,000 + 2,500 by year) |
| Distinct `customer_key` values | 8,000 |
| Signup year distribution | 2023: 2,500 / 2024: 3,000 / 2025: 2,500 — **exact**, loop-driven |
| Acquisition channel mix per year | Per `data_generation_strategy.md` Section 6, within ±5 points — **tolerance-based**, genuinely sampled |
| Geography region mix | South 38% / West 24% / Midwest 21% / Northeast 17%, within ±5 points — **tolerance-based** |
| `birth_year` range | 1953–2007 (derived from Dim_Date's 2023–2025 range and an 18–70 age-at-signup window) |

Unlike every prior phase's exact-count expectations, the channel and region figures above are **targets with an explicit tolerance**, not point predictions — see ED-008 for why exact-match validation would be the wrong tool here.

### Validation Checklist (expected — pending execution)

**Smoke test** (`sql/verification/smoke_test_dim_customer.sql`) — 7 checks: row count, `customer_key` integrity, `customer_id` integrity, `email` integrity, NOT NULL sweep, FK orphan check (both FKs), structural shape.

**Business-rule validation** (`sql/validation/validate_dim_customer.sql`) — 10 checks:

| # | Check |
|---|---|
| 1 | `customer_id` matches `CUST-######` |
| 2 | `email` matches `local-part@example.com` |
| 3 | `signup_date` falls within `Dim_Date`'s actual populated range |
| 4 | Signup year distribution exact: 2,500 / 3,000 / 2,500 |
| 5 | `birth_year` within the derived plausible range |
| 6 | `acquisition_channel_key` resolves to a real `Dim_Marketing_Channel` row (ED-007) |
| 7 | `home_geography_key` resolves to a real `Dim_Geography` row (ED-007) |
| 8 | Acquisition channel mix per year within ±5 points of target (ED-008) |
| 9 | Geography region mix within ±5 points of target (ED-008) |
| 10 | FK-readiness: `customer_key` dense, contiguous, starts at 1 |

**In-memory validation and rollback testing — planned, not yet exercised.** Expected to follow the same pattern confirmed in Phase 3.2–3.7 — to be confirmed, not assumed. One addition this phase should specifically verify on execution: that `build_dataframe()` and `validate_dataframe()` correctly raise `ValueError`/`FileNotFoundError` if run against a database where `Dim_Marketing_Channel` or `Dim_Geography` is missing or empty (ED-007's dependency-ordering guarantee) — this is a new failure mode no prior table's tests needed to cover.

### Build

Two genuinely new engineering problems this phase, both logged (ED-007, ED-008) rather than folded silently into the existing standard:

- **Real FK dependencies on other generated tables**, resolved by querying the live, already-loaded `Dim_Marketing_Channel` and `Dim_Geography` tables directly (read-only connection) rather than hardcoding their key-assignment logic — more correct, and it naturally enforces that this generator can't run before its dependencies are loaded. Refined during pre-execution review: the check validates that required business dependencies are present (every channel name in `CHANNEL_MIX_BY_YEAR`; every region in `REGION_WEIGHTS` with at least one geography) rather than requiring an exact row count on either parent table — a future 7th channel or 47th city needs no change here, only a genuinely missing requirement fails the generator.
- **Tolerance-based distribution validation**, because acquisition channel and geography are real weighted-random draws (not a fixed enumeration like every prior table's categorical distributions), so exact-count validation would be the wrong tool and would fail spuriously on correct code.

Beyond those two, everything else is unchanged: `build_dataframe()` / `validate_dataframe()` / `write_csv()` / `load_to_duckdb()` separation, explicit `ValueError`/`FileNotFoundError` exceptions, transaction-wrapped idempotent loading, a locally-scoped seeded `Random` instance (ED-006).

**A scope decision worth stating plainly: personas are not assigned in this table.** Every documented persona effect (frequency, AOV, category preference, return rate) belongs to fact tables that don't exist yet. No `Dim_Customer` column has a documented persona dependency. Assigning personas here would mean inventing a correlation (persona → signup timing, persona → acquisition channel) that was never specified in `data_generation_strategy.md` — that's scope creep dressed up as thoroughness. Personas are correctly deferred to whichever future fact-table generator actually consumes them.

### Validate

**Not yet performed.** This section will be completed after independent execution confirms (or corrects) the expected values above against the actual loaded table.

### Explain

`Dim_Customer` looks like "just a customer list," but it's the first table in this warehouse where getting the foreign keys right depends on the state of the database at generation time, not just the correctness of this generator's own code. That's a different kind of correctness than every prior phase needed, and it's why this phase introduces two new engineering decisions instead of zero — the complexity is real, not manufactured to look impressive.

### Interview

- "Why does `Dim_Customer` need to query the database instead of just importing the channel/geography dicts?" — those generators aren't shared reference modules, they're scripts with side effects; importing them would break the boundary ED-005 already established. Querying the live table is also more correct — it reflects what's actually loaded, not what this generator assumes was loaded.
- "Why is channel/region distribution validated with a tolerance instead of an exact count, when every other table used exact counts?" — those were all deterministic by construction (fixed enumerations). Channel and region assignment here are genuine weighted-random draws; exact-match validation would fail on correct code essentially every time.
- "How did you pick ±5 percentage points and not some other number?" — worked backward from the statistics: at the smallest sample size in play (2,500) and smallest weight (5%), the standard error is under half a point, so 5 points is roughly ten standard errors of margin — wide enough to never spuriously fail, tight enough to catch a real bug like swapped year-weights.
- "Why doesn't this table assign customer personas?" — no column here has a documented persona dependency; persona effects are all about purchase behavior, which lives in fact tables that don't exist yet. Assigning them here would require inventing business rules that were never specified.
- "What happens if someone runs this generator before Dim_Marketing_Channel or Dim_Geography is loaded?" — it fails immediately with a specific `FileNotFoundError`/`ValueError` naming exactly which dependency is missing, rather than silently generating rows with fabricated foreign keys.
- "Why doesn't the FK-dependency check require an exact row count on the parent tables?" — an exact count is a fragile proxy for what actually matters. The real requirement is that specific named channels and regions exist, not that the parent table has precisely 6 or 46 rows. Checking for an exact count would break this generator the moment either dimension legitimately grew — a 7th channel, a 47th city — even though nothing about Dim_Customer's actual dependencies changed. Validating the required subset of content directly, and allowing extra rows to simply go unused, makes the generator resilient to legitimate expansion while still failing fast on a genuinely missing dependency.

### Phase Gate

**Not yet reached.** Implementation is complete and internally consistent by construction, but execution, smoke testing, business validation, idempotency verification, and rollback testing are all pending independent review, per this phase's explicit scope (implementation only, no execution).

**Phase 3.8 status: implementation complete, execution pending.** Not yet ready for Phase 3.9 — awaiting independent review and Phase Gate on this phase first.

---

## Interlude — Dependency Readiness Check & Backlog Execution (start of Phase 3.9)

The Phase 3.9 continuation document described Phases 3.5–3.8 as executed and gate-passed, but the live database contradicted this: `Dim_Campaign`, `Dim_Product`, `Dim_Return_Reason`, and `Dim_Customer` all showed **0 rows**, consistent with this log's own "execution pending" status for those phases (each was explicitly scoped implementation-only at the time). Since Fact_Orders depends on all four, the backlog was executed before any Phase 3.9 work:

| Table | Loaded | Idempotency (2nd run) | Smoke + Validation |
|---|---|---|---|
| Dim_Campaign | 21 | 21 ✅ | 4/4 + 21/21 ✅ |
| Dim_Product | 180 | 180 ✅ | 5/5 + 8/8 ✅ |
| Dim_Return_Reason | 6 | 6 ✅ | 3/3 + 3/3 ✅ |
| Dim_Customer | 8,000 | 8,000 ✅ | 7/7 + 26/26 ✅ |

Dim_Customer's rollback was additionally re-exercised (real `ConstraintException`, 8,000 rows before and after), and its realized channel/region distributions landed within ~1 point of target — well inside ED-008's ±5-point tolerance. Phases 3.5–3.8 are now **genuinely** execution-complete and gate-passed. (One environment note: a mid-phase container restore reverted `generate_dim_customer.py`'s db_utils refactor and deleted the in-progress `generate_fact_orders.py`; both were restored and re-verified before proceeding.)

---

## Phase 3.9 — Fact_Orders

**Status: implementation complete. Execution complete. Phase Gate: recommended (pending your review).**

### Deliverables
- `python/generators/order_generation_core.py` — shared persona + order/line-item simulation core (ED-009, ED-010)
- `python/generators/db_utils.py` — shared FK-lookup helper, extracted per ED-011
- `python/generators/generate_fact_orders.py` — generator (build → validate → write CSV → load)
- `sql/generation/load_fact_orders.sql`, `sql/verification/smoke_test_fact_orders.sql` (5 checks), `sql/validation/validate_fact_orders.sql` (18 checks incl. all five Section 9 targets)
- `data/generated/fact_orders.csv`, Fact_Orders loaded: **26,299 rows**

### Realized Metrics (actual, from the loaded table — not projections)

| Metric | Target (Section 9) | Realized |
|---|---|---|
| Blended AOV | $65–85 | **$83.50** ✅ |
| Campaign revenue share | 30–40% | **39.0%** ✅ |
| Marketplace order share | 10–15% | **12.8%** ✅ |
| Holiday (Nov–Dec) revenue share | 25–30% | **25.7%** ✅ |
| Repeat purchase rate | 35–45% | **35.6%** ✅ |
| Orders by year | growth arc | 4,074 → 9,466 → 12,759 ✅ |

Idempotency: 26,299 rows after both runs. Rollback: forced duplicate-key `ConstraintException`, count unchanged. SQL: smoke 5/5, validation 18/18 pass against the live table.

### The Calibration Story (deliberately documented — this is the honest engineering record)

The first execution passed every integrity check and then failed Section 9's AOV target at **$145.95** — the validation doing exactly its job. Five successive, root-caused calibrations followed, each fixing a modeling gap rather than loosening a target:

1. **AOV $145.95 → $95.89 → in range:** uniform product selection over-sampled $90–280 Outerwear. Fixes: price-inverse product weighting within category (cheap items sell more units) and a base category *volume* mix (Accessories-heavy, Outerwear-light — matching Section 5's own "high-volume gift category" vs "premium seasonal category" language), with persona preferences reframed as tilts on that base. Plus small basket-weight recalibrations (1.29 items/order, 1.08 units/line).
2. **Campaign revenue share 48.8% → 44.0%:** two implementation infidelities fixed — Seasonal Shoppers were placed strictly *inside* windows when Section 7 says "±2-week window of" (around, not inside); Bargain Hunters were 100% campaign-anchored when Section 4 says "heavily clustered" (now 50%, still 1.4× over-representation vs the day-coverage baseline).
3. **Campaign share stuck at ~42–43%: a genuine spec conflict surfaced.** The Phase 3.1 calendar's Holiday Collection window (Nov 1–Dec 24 × 3 years) put 39.8% of ALL days inside campaign windows, making a 30–40% revenue share mathematically incompatible with any positive lift. Section 9 explicitly says to fix generation parameters, not loosen targets — and the window length *was* a generation parameter (the docs only ever said "Nov–Dec"). **Holiday Collection revised to Nov 15–Dec 24** in `campaign_calendar_reference.py`; `Dim_Date` and `Dim_Campaign` regenerated from the shared module (the exact drift-prevention path ED-005 built), campaign-day coverage now 394/1,096 = 35.9%. Campaign share landed at 39.0%.
4. **Holiday revenue 21.4% → 25.7%:** regular personas (most of revenue) were entirely season-blind, contradicting Section 6's lift concept. Added 12% holiday-gravity redirection of regular-persona orders into Nov–Dec.
5. **Repeat rate 65.1% → 35.6%:** with only 25% One-Time Buyers, personas repeating from day one force ~65% repeat — but Section 2 says 2023 was "almost entirely first-order volume." Added the missing mechanism: **retention conversion by signup-year cohort** (45%/60%/65% for 2023/2024/2025) — persona repeat behavior only activates as the business's retention program matures. This also resolved a final documented inconsistency: Section 3's "~65,000 orders" estimate was never jointly consistent with Section 9's repeat target; resolved in favor of Section 9 (the explicit pass/fail authority), row-count range revised to 18k–60k with reasoning in the generator.

### Engineering Decisions
ED-009 (deterministic never-persisted personas), ED-010 (shared order core for header/line reconciliation), ED-011 (db_utils extraction) — see `engineering_decision_log.md`.

### Interview
- "Your AOV came out at $146 first — what did you do?" — treated it as the validation working, root-caused it (uniform sampling over a price-skewed catalog), and fixed the *model* (price-inverse volume, realistic category mix) rather than widening the target.
- "You changed a frozen artifact (the campaign calendar) — justify it." — the freeze rule allows changes for genuine defects discovered during implementation. A calendar making a documented pass/fail target mathematically infeasible is a defect; the change was to an implementation parameter (start day) the spec never pinned down, propagated through the shared module so Dim_Date and Dim_Campaign couldn't drift.
- "How will Fact_Order_Lines reconcile to these headers?" — by construction: same shared simulation, same seed, same sorted processing order replays the identical line items (ED-010), so SUM(lines) = header isn't a hope, it's a replay.
- "Why is the order count 26k when your own docs estimated 65k?" — the two source estimates were mutually inconsistent; hitting the documented repeat-rate target (the explicit pass/fail authority) makes ~26k the arithmetically necessary volume. Documented the conflict and the resolution instead of silently picking one.

**Phase 3.9 status: complete and verified. Gate passed.**

---

## Phase 3.10 — Fact_Order_Lines

**Status: implementation complete. Execution complete. Phase Gate: recommended (pending your review).**

### Deliverables
- `order_generation_core.py` extended with `prepare_simulation_inputs()` + `simulate_orders_and_lines()` — the full simulation now lives in the shared core (ED-010 completed)
- `generate_fact_orders.py` refactored to a thin wrapper over the shared simulation — **verified byte-identical output** (pre- vs post-refactor CSV diff) before any new work built on it
- `python/generators/generate_fact_order_lines.py` — persists the line half of the same simulation
- `sql/generation/load_fact_order_lines.sql`, `sql/verification/smoke_test_fact_order_lines.sql` (4 checks), `sql/validation/validate_fact_order_lines.sql` (12 checks incl. the three-way reconciliation tie-out)
- `data/generated/fact_order_lines.csv`, Fact_Order_Lines loaded: **33,959 rows**

### Realized Results (actual, from the loaded table)

| Check | Result |
|---|---|
| Rows | 33,959 (1.291 lines/order — matching the 1.29 documented calibration) |
| **Reconciliation: SUM(net_line_revenue) = header net_revenue** | **0 failures across all 26,299 orders** ✅ |
| Three-way tie-out (gross and discount too) | 0 failures ✅ |
| Every order has ≥1 line; none exceeds max 3 | ✅ |
| Line math (gross = qty×price; net = gross−discount) | ✅ |
| Denormalized customer/date agree with header | ✅ |
| FK integrity vs Fact_Orders, Dim_Customer, Dim_Product, Dim_Date | ✅ |
| Idempotency (2nd run) | 33,959 both runs ✅ |
| Rollback (forced duplicate `order_line_key`) | real `ConstraintException`, count unchanged ✅ |
| Smoke 4/4, validation 12/12 | ✅ |

### Build

The architectural requirement — reconciliation **by construction**, not by after-the-fact verification — dictated the shape of this phase. Rather than have `generate_fact_order_lines.py` re-implement the Phase 3.9 loop and hope the RNG stream lined up, the *entire simulation* moved into `order_generation_core.simulate_orders_and_lines()`, which returns `(order_rows, line_rows)` from one pass. Each fact generator is now a thin wrapper persisting its half of the same objects. The refactor's safety was proven with the strongest available evidence: re-running `generate_fact_orders.py` post-refactor produced a byte-identical CSV.

Line discounts are allocated proportionally from the header discount with the rounding remainder assigned to the final line — deterministic, zero RNG draws, and it makes the line sums equal the header figures exactly rather than approximately. The validation still checks reconciliation against the *live* Fact_Orders table (belt and suspenders) — but as expected, 0 of 26,299 orders deviate, because both tables are views of one simulation, not two simulations that happen to agree.

### Interview
- "How do you guarantee lines reconcile to headers?" — by construction: one simulation produces both; the generators persist opposite halves. The proof wasn't a promise — the refactor was validated byte-identical, and the live reconciliation check found 0 deviations in 26,299 orders.
- "Why allocate the discount remainder to the last line?" — per-line rounding of a proportional split can drift a cent or two from the header's rounded discount; pinning the remainder on one line makes the sum exact. Any deterministic assignment works; last-line is the simplest to reason about.
- "Why does validation still re-check reconciliation if it's guaranteed?" — the guarantee holds only if both generators actually ran the same simulation against the same database state. The check catches operational drift (e.g., Fact_Orders reloaded under a different seed) that no amount of by-construction design can prevent.

**Phase 3.10 status: complete and verified. Gate passed.**

---

## Phase 3.11 — Fact_Returns

**Status: implementation complete. Execution complete. Phase Gate: recommended (pending your review).**

### Continuation-document corrections (flagged, not silently followed)
The Phase 3.11 continuation document renumbered the engineering decisions — it describes ED-011 as "exact discount allocation" and lists only ED-009/010/011 as if they were the full set. In this log, **ED-011 is the `db_utils.py` extraction**; discount-remainder allocation was recorded as an *ED-010 completion note*, not its own decision; and the real set is **ED-001 through ED-011**. It also lists the dimension phases as 3.6 Dim_Customer / 3.7 Dim_Product / 3.8 Dim_Return_Reason; the actual order was **3.6 Dim_Product, 3.7 Dim_Return_Reason, 3.8 Dim_Customer**. Neither affects the work — recorded so the project history stays accurate.

### Deliverables
- `python/generators/generate_fact_returns.py`
- `sql/generation/load_fact_returns.sql`, `sql/verification/smoke_test_fact_returns.sql` (5 checks), `sql/validation/validate_fact_returns.sql` (22 checks)
- `data/generated/fact_returns.csv`, Fact_Returns loaded: **5,687 rows** (6,088 units returned)

### Realized Results (actual, from the loaded table)

| Metric | Target | Realized |
|---|---|---|
| Blended return rate (units) | 15–20% (Section 9) | **16.6%** ✅ |
| Footwear | 25–30% (Section 9, pinned) | **27.8%** ✅ |
| Accessories | 8–10% (Section 9, pinned) | **8.6%** ✅ |
| Womenswear / Menswear / Outerwear | not specified | 25.2% / 19.6% / 21.2% |
| Return timing | 5–21 days (Section 7, exact) | **min 5, max 21** ✅ |
| VIP return ceiling (Section 7) | VIP lowest in every category | ✅ enforced + validated |
| High-Return Customer | highest-return persona | ✅ |
| Refunds completed | operational lag | 96.0% |
| Refunded / restocking fees | — | $412,899.58 / $8,923.82 |

Idempotency: 5,687 both runs. Rollback: forced duplicate `return_key` → real `ConstraintException`, count unchanged. Smoke 5/5, validation 22/22.

### Build — three problems the validation caught, all root-caused

1. **Half-cent rounding disagreement (2 of ~5,900 rows).** A 1-of-2 return of a $58.51 line is exactly $29.255; Python's banker's rounding and pandas' `.round()` resolve that tie in opposite directions, so `build_dataframe()` and `validate_dataframe()` disagreed. Fixed by routing every money calculation through one explicit **half-up Decimal rule** (`_round_money()`), shared by build and validate — the same lesson as Phase 3.10's deterministic discount remainder: pin the rule, don't rely on float behaviour.
2. **Blended rate 13.8%, below the 15–20% target — a genuine spec tension, not a bug.** Section 9 pins *only* Footwear (25–30%) and Accessories (8–10%). But Accessories are ~48% of units (itself a Phase 3.9 AOV calibration), so the two pinned categories contribute just ~6.4 points. The three apparel rates — **specified nowhere in the source documents** — must average ~24% for the pinned blended to be reachable at all. My first pass had merely interpolated them between the two pinned endpoints (14–18%), which was arbitrary; ~24–26% womenswear is also simply the more realistic figure (real DTC womenswear returns run 25–40%). Fixed the model, not the target.
3. **Footwear realized 34.0% against a 27.5% base.** `base × multiplier` does *not* make a category realize its base rate, because persona category preferences aren't uniform: Section 4 says High-Return Customers skew Footwear, and Phase 3.9 encodes a 3.5× tilt — so Footwear's buyers carry a measured **1.25× units-weighted return multiplier**, while Outerwear's Seasonal-Shopper skew carries only 0.81×. Each category base is now **deflated by its own measured persona loading** (`base = desired_realized / M_cat`). The deliberate consequence, documented in the generator: these constants are *not* the realized rates and must not be read as such.

A fourth, smaller one surfaced in SQL: the same half-cent tie ($163.39 ÷ 2 = $81.695) resolves to $81.70 under the generator's half-up rule and $81.69 under DuckDB's float `ROUND()`. The generator's rule is authoritative; the SQL check's tolerance is one cent plus a hair, with the reasoning written into the file — its job is catching a wrong *proportion*, not adjudicating rounding conventions between two engines.

### Model
`P(return) = CATEGORY_BASE[category] × PERSONA_MULTIPLIER[persona]` — personas and product characteristics, never noise. Persona multipliers are each persona's Section 4 tendency ÷ the population-weighted blended tendency (derived from `PERSONA_POPULATION`, never hardcoded), so both documented target sets hold simultaneously. Section 7's VIP return ceiling holds **by construction** (VIP's multiplier is strictly smallest; scaling every category by a common factor preserves the ordering) and is validated anyway. Reason mix is category-specific — Footwear skews Wrong Size (55%), Accessories skew Changed Mind / Not as Described since they have no sizing dimension at all.

### Content decisions (documented here, not in the ED log — same boundary as Phase 3.7)
- **Restocking fee:** charged only on `CHANGED_MIND` (customer preference), at 10% of `return_amount`. Controllable-fault reasons and the unclassified `OTHER` bucket carry none — encoding "charge the customer for our own defect" into a warehouse other stakeholders will read would be a strange policy.
- **`refund_completed_flag`:** TRUE once 5 days have elapsed since the return, with ~3% of eligible refunds still pending — exactly the requested-vs-completed distinction the v1.1 changelog added the field for.
- **Returns dated past 2025-12-31 are not emitted** — a real "bought in late December, not yet returned" state, and the only way `return_date_key` can honour its Dim_Date FK. Clamping the date would fabricate a return that didn't happen.

### Interview
- "Why doesn't Fact_Returns replay the shared simulation like Fact_Order_Lines did?" — because headers and lines are two views of one object (reconciliation demands one pass), whereas a return is a downstream event about a line that already exists. Reading the persisted line is ED-007's own argument, and it keeps the byte-identical-verified order simulation untouched.
- "Your Footwear returns came out at 34% against a 27.5% base — bug?" — no, a real interaction I under-modelled: High-Return Customers are documented to skew Footwear, so its buyer mix carries a 1.25× return loading. I measured the loading per category and deflated each base by it, rather than fudging the base until the number looked right.
- "Section 9 says 15–20% blended but your first run gave 13.8% — did you widen the target?" — no. Only Footwear and Accessories are pinned, and with Accessories at ~48% of units they can't reach 15% alone. The apparel rates were mine to set, and my initial interpolation was the arbitrary part. Fixed the model.
- "Why is the SQL tolerance 0.011 and not 0?" — because two engines resolve an exact half-cent tie differently. The generator's half-up rule is authoritative; the check exists to catch a wrong proportion, not a rounding convention.

**Phase 3.11 status: complete and verified. Gate passed.**

---

## Phase 3.12 — Fact_Customer_Monthly_Snapshot

**Status: implementation complete. Execution complete. Phase Gate: recommended (pending your review).** This is the final fact table of Phase 3 — the warehouse is now fully populated.

### Deliverables
- `python/generators/generate_fact_customer_monthly_snapshot.py`
- `sql/generation/load_fact_customer_monthly_snapshot.sql`
- `sql/verification/smoke_test_fact_customer_monthly_snapshot.sql` (6 checks)
- `sql/validation/validate_fact_customer_monthly_snapshot.sql` (23 checks — the strongest suite in the project)
- `data/generated/fact_customer_monthly_snapshot.csv`, loaded: **147,995 rows**

### Realized Results (actual, from the loaded table)

| Check | Result |
|---|---|
| Row count | **147,995 — exactly the predicted figure**, not a range |
| INVARIANT 3 (temporal continuity) | ✅ every customer, signup month → 2025-12, no gaps/dupes |
| INVARIANT 1 (attribution by return date) | ✅ independently re-derived in SQL, 0 disagreements |
| INVARIANT 1b (cumulative revenue never negative) | ✅ 0 rows |
| INVARIANT 2 (negative rolling: rare, bounded, explainable) | ✅ **390 rows (0.26%), worst −$556.20, all explained** |
| Final-month orders tie-out | **26,299 = Fact_Orders exactly** |
| Final-month revenue tie-out | **$1,782,971.91 = SUM(orders.net) − SUM(returns) exactly** |
| Flags re-derived in SQL | ✅ 0 mismatches on all three |
| Never-purchasers (289) | ✅ NULL recency, $0, all flags FALSE, every month |
| Idempotency / rollback | 147,995 both runs; forced duplicate `snapshot_key` → real `ConstraintException`, count unchanged |
| Smoke / validation | 6/6 and 23/23 |

**Cross-phase consistency worth noting:** the final-month `is_repeat_customer_flag` rate is **35.6%** — identical to the repeat purchase rate Phase 3.9 was independently calibrated to against Section 9. Two different tables, two different derivations, one business truth. Validation check #16 pins that agreement so it can't silently drift.

### The three invariants (promoted from prose to enforced rules)

**INVARIANT 1 — revenue attribution by return date, never retroactive.** Cumulative and rolling revenue are reduced in the month the *return* occurs, never backdated into the purchase month. A snapshot row states what was true *as of* that month-end: in March, a February order not yet returned was, in fact, revenue. Restating February would rewrite history, destroy the table's purpose as a point-in-time record, and corrupt Phase 10's ML labels — which read consecutive rows as a time series and must never see the future leak backwards. Enforced by cutting both sides of the subtraction at the same month-end using each event's *own* date, and verified by an **independent SQL re-derivation** (check #10/#11) that would disagree on every affected row if the generator had backdated anything.

**INVARIANT 2 — bounded, explainable negative rolling revenue.** Returns land 5–21 days after their order (Section 7), so an order can fall just *outside* a trailing-12-month window while its own return falls just *inside* it — the window then subtracts a refund whose purchase it never counted. `schema.sql` has no CHECK on this column, so negatives are permitted; but "allowed" must not decay into "unchecked." Every negative row is required to be **explainable by that exact mechanism** (the customer must genuinely have a return inside the window whose order is outside it), and negatives must stay rare (<1%) and bounded (>−$1,000). This is what separates the intended edge case from an arithmetic bug — realized: 390 rows, 0.26%, worst −$556.20, 100% explained.

**INVARIANT 3 — temporal continuity of the row spine.** Exactly one snapshot per month from signup month through 2025-12, verified per customer against a recomputed expected sequence — **deliberately independent of the total row count**, since a correct total can hide two customers with offsetting errors. Checked three independent ways in SQL: a LAG gap check (a gap gives >1 month, a duplicate gives 0), series bounds against `signup_date` and 2025-12-31, and per-customer arithmetic.

### Build

Grain: one row per customer per calendar month from the **signup** month. Not 2023-01 for everyone (`CHECK (customer_age_days >= 0)` forbids pre-signup rows — the constraint *is* the design statement), and not the first-order month (that would erase the 289 customers who signed up and never bought, silently corrupting every cohort-retention denominator in Phase 6 — retention measures *acquired* customers who came back, not buyers who bought again).

`Fact_Order_Lines` is a **deliberate non-dependency**: its revenue already rolls up to `Fact_Orders.net_revenue`, and Phase 3.10 proved they reconcile exactly. Re-deriving a number already in hand would only create a way for them to disagree.

The generator uses per-customer sorted event arrays with prefix sums, so recency and every windowed measure reduce to two bisects — keeping 147,995 rows tractable without abandoning the readable row-by-row derivation the rest of the project uses.

**No calibration iterations were needed** — a first for a fact table in this project, and not luck: there is nothing to calibrate when nothing is sampled. Everything passed on the first execution because every value is forced by the data.

### Content decisions (documented here, not in the ED log — the Phase 3.7/3.11 boundary)
- **Returns ARE subtracted from net revenue.** `data_dictionary.md` says only "total net revenue ever generated" (ambiguous), but `business_understanding.md` defines the KPI unambiguously and up front: *Net Revenue = SUM(order line revenue) − returns − discounts*, stated there so the number stays consistent across SQL, Python and Power BI. Not subtracting would make a High-Return Customer who bought $5k and returned $2k look like a $5k customer in Phase 6's CLV and Pareto analysis — inverting the exact business tension Section 4 poses.
- **`restocking_fee` is not netted** — it's a fee, not product revenue; the KPI says "− returns," full stop.
- **`refund_completed_flag` is an Ops lag indicator, not a revenue-recognition rule** — the reduction lands at `return_date` regardless of processing state.

### Interview
- "Why can cumulative net revenue decrease, when 'cumulative' usually means monotonic?" — because a return legitimately reduces it in the month the return happens. Cumulative *orders* is monotonic (orders are never un-placed); cumulative *revenue* isn't, and the invariant that does hold absolutely — it can never go negative — is what I validate instead.
- "You allow negative rolling revenue. How is that not just a bug you rationalised?" — because it has exactly one possible cause, and I check for that cause on every negative row: a return inside the window whose order is outside it, which the 5–21 day return lag makes inevitable at window boundaries. 390 rows, all explained, worst −$556. An unexplained negative fails the suite.
- "Why don't the flags use personas, when everything else in generation does?" — Section 7 requires persona-blindness precisely so Phase 10's churn model has to learn from behaviour rather than recover the generation rules. A persona-aware flag would make the model look brilliant and mean nothing.
- "How do you know the snapshot is right and not just self-consistent?" — the validation re-derives it independently in SQL, a different engine and code path from the pandas that built it, and ties the final month back to Fact_Orders and Fact_Returns exactly: 26,299 orders and $1,782,971.91 to the cent.

**Phase 3.12 status: complete and verified. Gate passed. Phase 3 is complete** — 8 dimensions and all 4 fact tables built, executed, and validated.

---

## Phase 4 — Warehouse-Wide Validation

**Status: implementation complete. Execution complete. Phase Gate: recommended (pending your review).**

> **Phase 3 validated each table against its specification. Phase 4 validates the warehouse against itself.**

### Result: **62 checks, 60 passed, 2 advisory findings, 0 blocking failures — WAREHOUSE CERTIFIED**

| Suite | Result |
|---|---|
| `smoke_test_dim_date.sql` (historical gap closed) | 7/7 ✅ |
| `validate_warehouse_integrity.sql` (Tier 0–1) | 15/15 ✅ |
| `validate_warehouse_reconciliation.sql` (Tier 2–3) | 15/15 ✅ |
| `validate_warehouse_readiness.sql` (Tier 4–6) | 23/25 (2 advisory findings) ✅ |

Full evidence: `docs/phase4_validation_report.md`, regenerated by `python/validation/run_warehouse_validation.py` — a standing, re-runnable health check, not a one-off audit.

### Deliverables
- `sql/verification/smoke_test_dim_date.sql` — closes the Phase 3.1 gap (Dim_Date predated ED-002 and had a validation suite but never a smoke test; the conformed dimension every fact's date role points at was the last table that should lack one)
- `sql/validation/validate_warehouse_integrity.sql` (Tier 0 structural, Tier 1 vintage coherence)
- `sql/validation/validate_warehouse_reconciliation.sql` (Tier 2 cross-grain, Tier 3 KPI)
- `sql/validation/validate_warehouse_readiness.sql` (Tier 4a/4b, Tier 5, Tier 6)
- `python/validation/run_warehouse_validation.py` — runner + report generator
- `docs/phase4_validation_report.md` — including the warehouse certification summary
- `docs/business_understanding.md` — two corrections, below

### The two findings

**FINDING 5.5 — the headline, and the design-stage hypothesis confirmed.** `business_understanding.md` claimed *"a growing but still minority share of revenue from repeat customers."* Phase 3 had validated the repeat **customer** rate (35.6%) — a different quantity that never tested this claim. The warehouse disproves the "minority" half decisively:

| Year | Repeat-customer revenue share |
|---|---|
| 2023 | 61.4% |
| 2024 | 83.5% |
| 2025 | 87.9% |
| **Overall** | **82.4%** |

**2,851 customers (35.6%) generate 82.4% of net revenue.** The "growing" half of the claim is confirmed (check 5.6 passes); "still minority" was never true, not even in 2023. Per the Phase 4 ruling, **no generated data was modified** — the narrative was corrected in `business_understanding.md` with the evidence and its consequence recorded. The business tension is now *sharper*, not weaker: Solstice isn't a business yet to build a repeat base, it's one **already dependent** on a comparatively small cohort carrying nearly all revenue. That reframes the CFO's question from *"is retention spend paying off?"* to *"what is the concentration risk if this cohort lapses?"* — for Phase 6's cohort/CLV work and Phase 8's recommendations.

**FINDING 4b.7 — 289 customers never purchased.** Expected and correct: real signups that never converted. Recorded as a finding because it's a genuine funnel fact for Phase 8, and because Phase 3.12 deliberately kept these customers in the snapshot so cohort-retention denominators stay honest.

### The AOV ambiguity — caught before it could do damage

`business_understanding.md` defined **AOV = Net Revenue ÷ Total Orders** with **Net Revenue = line revenue − returns − discounts**. But Phase 3.9 validated AOV as `mean(Fact_Orders.net_revenue)` = **$83.50**, which excludes returns. Read literally, the KPI table gives **$67.80**. **Both sit inside Section 9's $65–85 band** — so the contradiction was completely invisible and would have surfaced only later, as SQL and Power BI publishing two different "AOV" numbers: exactly what that KPI table was written up-front to prevent.

Resolved per your ruling to the standard retail definition (after discounts, before returns). `business_understanding.md` now distinguishes **Order Net Revenue** (basis for AOV) from **Net Revenue** (basis for revenue reporting, CLV, Pareto), and **check 3.2 enforces that AOV is single-valued** across the header and line paths permanently.

### Certified KPI values (each agreeing across ≥2 independent derivations)

| KPI | Value |
|---|---|
| Order Net Revenue | $2,195,871.49 |
| Net Revenue (after returns) | $1,782,971.91 |
| AOV | $83.50 |
| Discount Impact | 6.86% |
| Gross Margin | 63.27% |
| Return Rate | 16.6% |
| Repeat Purchase Rate | 35.6% |

### What Phase 4 deliberately did NOT re-run

Per-table PK/NOT NULL/enum smoke checks; per-generator FK validation at generation time; the Phase 3.10 header/line suite; Phase 3.11's return rules; Phase 3.12's snapshot invariants; and every ED-008 sampled-vs-target distribution check. Those questions are answered and stay answered. **One honest exception:** Tier 1 re-executes a minimal subset of cross-table checks — not as duplication, but because the *question changed*. In Phase 3.11 the check asked "is my generator's arithmetic right?"; in Phase 4 it asks "is the currently loaded state stale?" Same query, different failure being hunted.

### Tier 1 — the check nothing in Phase 3 could have performed

Every generator validated its FKs at its **own execution moment**. Nothing had ever verified that all four facts derive from the **same vintage** of their parents *simultaneously*. This is not hypothetical: surrogate keys are dense 1..N and are **reused on regeneration**, so if `Fact_Order_Lines` were rebuilt under a different seed, every `order_line_key` in `Fact_Returns` would still resolve — **FK integrity would pass cleanly** — while silently referencing different products at different prices. The project has already lived adjacent to this hazard: the Phase 3.9 campaign-calendar defect forced `Dim_Date` and `Dim_Campaign` to be regenerated *after* other tables existed. It worked out; nothing verified that it did. Tier 1 now does, by content-based re-derivation against currently-loaded parents. **All 10 checks pass.**

### Interview
- "What did Phase 4 catch that Phase 3 couldn't?" — two things Phase 3 was structurally incapable of catching: an AOV definition that was ambiguous in a way *invisible* to every existing check (both readings passed the validation band), and the absence of any vintage-coherence guarantee across independently-regenerated tables.
- "Your data contradicted your own business narrative. What did you do?" — corrected the narrative, not the data. The 82.4% concentration is a *better* story than the original framing, and quietly regenerating data to match a document I wrote first would have been the actual failure.
- "Why is Phase 4 almost entirely exact when Phase 3 used tolerances?" — because Phase 3 compared sampled data to business targets, where sampling variance is real. Phase 4 compares the warehouse to itself; two derivations of the same rows must agree to the cent, and a tolerance would only hide a bug.
- "Why keep a finding that will fire on every run?" — a concentration this material should keep announcing itself rather than going quiet once written down. It's a standing flag for Phase 8 and a regression guard if the figure moves.

**Phase 4 status: complete and verified. Gate recommended. Warehouse CERTIFIED for analytics.** Phase 5 (SQL analytics layer) is next, and inherits a strong position: every KPI it will implement now has one agreed value and a validation check pinning it there.

