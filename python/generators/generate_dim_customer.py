"""
Phase 3.8 - Dim_Customer generator.

Dim_Customer is the first dimension in this project with real foreign
key dependencies on other GENERATED dimensions (Dim_Marketing_Channel,
Dim_Geography), and the first whose weighted-random attributes are
validated with a tolerance band rather than an exact count. See
docs/engineering_decision_log.md ED-007 and ED-008 for both.

Business purpose: who the customer is and how/where they entered the
business. Deliberately excludes loyalty_tier/customer_status (those are
derived fact-layer concepts on Fact_Customer_Monthly_Snapshot -- see
docs/design_decisions.md #5) and deliberately excludes persona (see
below).

Row count and split (docs/data_generation_strategy.md Section 3):
    2023: 2,500 new customers
    2024: 3,000 new customers
    2025: 2,500 new customers (deceleration)
    Total: 8,000

Why personas are NOT assigned here, even though this is "the customer
table": every documented persona effect (purchase frequency, AOV,
category preference, return rate) is a Fact_Orders / Fact_Order_Lines /
Fact_Returns / Fact_Customer_Monthly_Snapshot concept -- none of which
exist yet. No column on THIS table has a documented persona dependency:
signup_date's within-year distribution, birth_year, acquisition channel,
and geography are all governed by their own independent rules in
docs/data_generation_strategy.md with no persona cross-reference.
Assigning personas here would mean inventing a persona -> signup-date or
persona -> acquisition-channel correlation that was never specified.
Personas are correctly deferred to whichever future fact-table generator
actually needs them, computed directly from customer_key at that time --
this is the more literal reading of "personas exist only during data
generation," not a gap in this phase.

Foreign key resolution (ED-007): acquisition_channel_key and
home_geography_key are resolved by querying the ALREADY-LOADED
Dim_Marketing_Channel and Dim_Geography tables directly, not by
hardcoding or re-deriving their key-assignment dicts. This is more
correct (resolves against what's actually in the database, not an
assumption about it) and doesn't violate ED-005's "generators shouldn't
import each other" principle, since neither of those generators is a
shared reference module.

The dependency check itself validates business requirements, not table
size: Dim_Marketing_Channel must contain every channel name referenced
in CHANNEL_MIX_BY_YEAR, and Dim_Geography must contain every region in
REGION_WEIGHTS with at least one geography each. Neither check cares how
many total rows the parent table has -- a future 7th marketing channel
or 47th city requires no change here. Only a genuinely missing required
channel or region fails the generator.

Randomness classification (docs/data_generation_strategy.md Section 8):
    - Business Rule: customer count per year, the FK-resolution logic itself.
    - Weighted Random: signup_date within its year (uniform), birth_year
      (via a realistic adult-age distribution), acquisition_channel_key
      (year-specific channel mix), home_geography_key (region population
      weighting, then uniform within the region).
    - Pure Random: first_name, last_name.

Engineering standards (FPS v1.0, unchanged from Phase 3.2-3.7 -- see
docs/engineering_decision_log.md ED-001 through ED-006): generation,
validation, and database loading remain separate functions; validation
raises explicit exceptions, never `assert`; the database load is
transaction-wrapped and idempotent; randomness uses a locally-scoped
seeded Random instance (ED-006). ED-007 and ED-008 (this phase) extend
that baseline for FK resolution and distribution validation specifically.

Run:
    python python/generators/generate_dim_customer.py
"""

import re
import sys
from datetime import date, timedelta
from pathlib import Path
from random import Random

import duckdb
import pandas as pd

sys.path.append(str(Path(__file__).parent))
from db_utils import load_dimension_lookup

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "dim_customer.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

RANDOM_SEED = 42  # ED-006 pattern, reused: locally-scoped Random(seed), never global state

# --- Business rule: customers per acquisition year (docs/data_generation_strategy.md Section 3) ---
CUSTOMERS_BY_YEAR = {2023: 2500, 2024: 3000, 2025: 2500}
EXPECTED_ROW_COUNT = sum(CUSTOMERS_BY_YEAR.values())  # 8000, derived not hardcoded

# --- Business rule: acquisition channel mix per year (docs/data_generation_strategy.md Section 6) ---
CHANNEL_MIX_BY_YEAR = {
    2023: {"Paid Social": 0.40, "Paid Search": 0.25, "Organic/SEO": 0.10, "Email/SMS": 0.05, "Affiliate/Referral": 0.05, "Direct": 0.15},
    2024: {"Paid Social": 0.32, "Paid Search": 0.22, "Organic/SEO": 0.18, "Email/SMS": 0.10, "Affiliate/Referral": 0.07, "Direct": 0.11},
    2025: {"Paid Social": 0.25, "Paid Search": 0.20, "Organic/SEO": 0.25, "Email/SMS": 0.15, "Affiliate/Referral": 0.08, "Direct": 0.07},
}

# --- Business rule: region population weighting (approximate real US Census
#     regional population shares, used because Dim_Geography has no
#     population figures of its own to weight by -- documented
#     approximation, not exact census data) ---
REGION_WEIGHTS = {"South": 0.38, "West": 0.24, "Midwest": 0.21, "Northeast": 0.17}

# Age distribution at signup: triangular, skewed toward core D2C shopper
# age (peak ~32), tapering to 18 and 70. No documented persona-age
# correlation exists, so this is independent of anything persona-related.
MIN_AGE_AT_SIGNUP = 18
MAX_AGE_AT_SIGNUP = 70
MODE_AGE_AT_SIGNUP = 32

# Distribution validation tolerance (ED-008): wide enough that a correctly
# implemented weighted sampler essentially cannot fail it by chance at
# these sample sizes (n=2,500-8,000 per group; standard error for the
# smallest weight in play is under 0.5 percentage points), tight enough
# to catch a real bug (e.g. a year's weights swapped, which would produce
# 10-15+ point deviations).
DISTRIBUTION_TOLERANCE_PCT = 5.0

FIRST_NAMES = [
    "James", "Mary", "Robert", "Patricia", "John", "Jennifer", "Michael", "Linda",
    "David", "Elizabeth", "William", "Barbara", "Richard", "Susan", "Joseph", "Jessica",
    "Thomas", "Sarah", "Charles", "Karen", "Christopher", "Nancy", "Daniel", "Lisa",
    "Matthew", "Betty", "Anthony", "Margaret", "Mark", "Sandra", "Donald", "Ashley",
    "Steven", "Kimberly", "Andrew", "Emily", "Joshua", "Donna", "Kevin", "Michelle",
]

LAST_NAMES = [
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
    "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas",
    "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White",
    "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson", "Walker", "Young",
    "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores",
]

CUSTOMER_ID_PATTERN = re.compile(r"^CUST-\d{6}$")
EMAIL_PATTERN = re.compile(r"^[^@\s]+@example\.com$")

COLUMN_ORDER = [
    "customer_key", "customer_id", "first_name", "last_name", "email",
    "signup_date", "birth_year", "acquisition_channel_key", "home_geography_key",
]


def _random_date_in_year(rng: Random, year: int) -> date:
    """Uniform random date within the given calendar year."""
    start = date(year, 1, 1)
    end = date(year, 12, 31)
    offset_days = rng.randint(0, (end - start).days)
    return start + timedelta(days=offset_days)


def build_dataframe(seed: int = RANDOM_SEED, db_path: Path = DB_PATH) -> pd.DataFrame:
    """
    Builds all 8,000 Dim_Customer rows.

    Foreign keys are resolved against the actual, currently-loaded
    Dim_Marketing_Channel and Dim_Geography tables (ED-007) -- this
    function will fail loudly and specifically if either dependency
    hasn't been generated yet, rather than silently producing rows with
    fabricated key values.

    Determinism note, same as ED-006: a locally-scoped Random(seed)
    instance, not global `random` state, so this generator's output can
    never depend on what else has used randomness in the same process.
    """
    rng = Random(seed)

    channel_lookup = load_dimension_lookup(
        db_path, "Dim_Marketing_Channel", ["marketing_channel_key", "channel_name"]
    )
    channel_name_to_key = dict(zip(channel_lookup["channel_name"], channel_lookup["marketing_channel_key"]))
    all_expected_channels = set()
    for weights in CHANNEL_MIX_BY_YEAR.values():
        all_expected_channels.update(weights.keys())
    missing_channels = all_expected_channels - set(channel_name_to_key.keys())
    if missing_channels:
        raise ValueError(
            f"Dim_Marketing_Channel is missing required channel(s) referenced in "
            f"CHANNEL_MIX_BY_YEAR: {sorted(missing_channels)}. Found {len(channel_lookup)} "
            f"channel(s) total: {sorted(channel_name_to_key.keys())}. Extra channels "
            f"beyond the required set are fine and are simply never sampled -- only "
            f"a genuinely missing required channel is an error."
        )

    geography_lookup = load_dimension_lookup(
        db_path, "Dim_Geography", ["geography_key", "region"]
    )
    region_to_keys = {region: group["geography_key"].tolist() for region, group in geography_lookup.groupby("region")}
    # A region with zero rows would never appear as a groupby key above, so
    # this single check simultaneously verifies both that the region exists
    # AND that it has at least one geography to sample from -- exactly the
    # two conditions that matter, without pinning down how many rows a
    # region "should" have.
    missing_regions = set(REGION_WEIGHTS.keys()) - set(region_to_keys.keys())
    if missing_regions:
        raise ValueError(
            f"Dim_Geography is missing required region(s) referenced in "
            f"REGION_WEIGHTS (each must have at least one geography): "
            f"{sorted(missing_regions)}. Found {len(geography_lookup)} geography row(s) "
            f"across region(s): {sorted(region_to_keys.keys())}. Additional cities "
            f"in existing regions are fine and require no change here -- only a "
            f"genuinely missing required region is an error."
        )

    rows = []
    customer_key = 1
    for year, count in CUSTOMERS_BY_YEAR.items():
        channel_names = list(CHANNEL_MIX_BY_YEAR[year].keys())
        channel_weights = list(CHANNEL_MIX_BY_YEAR[year].values())
        region_names = list(REGION_WEIGHTS.keys())
        region_weights = list(REGION_WEIGHTS.values())

        for _ in range(count):
            first_name = rng.choice(FIRST_NAMES)
            last_name = rng.choice(LAST_NAMES)

            signup_date = _random_date_in_year(rng, year)
            age_at_signup = rng.triangular(MIN_AGE_AT_SIGNUP, MAX_AGE_AT_SIGNUP, MODE_AGE_AT_SIGNUP)
            birth_year = signup_date.year - int(age_at_signup)

            chosen_channel_name = rng.choices(channel_names, weights=channel_weights, k=1)[0]
            acquisition_channel_key = int(channel_name_to_key[chosen_channel_name])

            chosen_region = rng.choices(region_names, weights=region_weights, k=1)[0]
            home_geography_key = int(rng.choice(region_to_keys[chosen_region]))

            rows.append({
                "customer_key": customer_key,
                "customer_id": f"CUST-{customer_key:06d}",
                "first_name": first_name,
                "last_name": last_name,
                "email": f"{first_name.lower()}.{last_name.lower()}{customer_key}@example.com",
                "signup_date": signup_date,
                "birth_year": birth_year,
                "acquisition_channel_key": acquisition_channel_key,
                "home_geography_key": home_geography_key,
            })
            customer_key += 1

    return pd.DataFrame(rows, columns=COLUMN_ORDER)


def validate_dataframe(df: pd.DataFrame, db_path: Path = DB_PATH) -> None:
    """
    Business-rule validation performed in memory, before anything is
    written to disk or the database.

    This is the richest validation suite in Phase 3 to date -- it has to
    check both the things every prior table checked (key integrity,
    NOT NULL, uniqueness) AND two genuinely new categories: referential
    integrity against LIVE parent tables (ED-007) and tolerance-based
    statistical distribution checks for genuinely random attributes
    (ED-008), as opposed to the exact-count checks every fixed-enumeration
    table before this one could use.

    Every failure raises a descriptive ValueError -- never `assert`, per
    ED-003.
    """
    if df.empty:
        raise ValueError(f"Dim_Customer DataFrame is empty -- expected exactly {EXPECTED_ROW_COUNT} rows.")

    row_count = len(df)
    if row_count != EXPECTED_ROW_COUNT:
        raise ValueError(
            f"Dim_Customer row count {row_count} does not match the exact expected "
            f"count of {EXPECTED_ROW_COUNT} (sum of CUSTOMERS_BY_YEAR) -- the year "
            f"plan and the generated rows have drifted apart."
        )

    # --- Surrogate key integrity -----------------------------------------
    if df["customer_key"].isnull().any():
        raise ValueError("customer_key contains nulls -- every row must have a surrogate key.")
    if not df["customer_key"].is_unique:
        raise ValueError("customer_key must be unique -- found duplicate surrogate keys.")
    expected_keys = set(range(1, row_count + 1))
    actual_keys = set(df["customer_key"])
    if actual_keys != expected_keys:
        raise ValueError(
            "customer_key must be a contiguous sequence starting at 1 (this is what "
            f"Fact_Orders.customer_key, Fact_Order_Lines.customer_key, Fact_Returns."
            f"customer_key, and Fact_Customer_Monthly_Snapshot.customer_key will all "
            f"later reference) -- found a mismatch: {sorted(actual_keys ^ expected_keys)}"
        )

    # --- Natural key integrity --------------------------------------------
    if df["customer_id"].isnull().any():
        raise ValueError("customer_id contains nulls -- every row must have a natural key.")
    if not df["customer_id"].is_unique:
        raise ValueError("customer_id must be unique -- found duplicate natural keys.")
    bad_ids = df.loc[~df["customer_id"].astype(str).str.match(CUSTOMER_ID_PATTERN), "customer_id"].tolist()
    if bad_ids:
        raise ValueError(f"customer_id values must match the pattern CUST-###### (6 digits): {bad_ids}")

    # --- NOT NULL sweep. birth_year is nullable in schema.sql, but this
    #     generator always assigns one -- checked as a generator-level
    #     expectation, same treatment as Dim_Product's color check. -------
    required_not_null = [
        "first_name", "last_name", "email", "signup_date",
        "birth_year", "acquisition_channel_key", "home_geography_key",
    ]
    for col in required_not_null:
        if df[col].isnull().any():
            raise ValueError(f"Column '{col}' contains nulls (birth_year is schema-nullable, but this generator always populates it).")

    # --- Email format and uniqueness --------------------------------------
    if not df["email"].is_unique:
        raise ValueError("email must be unique -- found a duplicate email address.")
    bad_emails = df.loc[~df["email"].astype(str).str.match(EMAIL_PATTERN), "email"].tolist()
    if bad_emails:
        raise ValueError(f"email values must match the pattern local-part@example.com: {bad_emails}")

    # --- signup_date range and exact year distribution ---------------------
    min_year, max_year = min(CUSTOMERS_BY_YEAR), max(CUSTOMERS_BY_YEAR)
    range_start, range_end = date(min_year, 1, 1), date(max_year, 12, 31)
    out_of_range = df[(df["signup_date"] < range_start) | (df["signup_date"] > range_end)]
    if not out_of_range.empty:
        raise ValueError(
            f"Found {len(out_of_range)} row(s) with signup_date outside "
            f"{range_start}-{range_end}, the range Dim_Date actually covers."
        )

    df_work = df.copy()
    df_work["signup_year"] = pd.to_datetime(df_work["signup_date"]).dt.year
    actual_year_counts = {int(k): int(v) for k, v in df_work["signup_year"].value_counts().items()}
    if actual_year_counts != CUSTOMERS_BY_YEAR:
        raise ValueError(
            f"signup_date year distribution mismatch. Expected {CUSTOMERS_BY_YEAR} "
            f"(exact -- this is loop-driven, not sampled), got {actual_year_counts}."
        )

    # --- birth_year plausibility range, derived from the actual signup
    #     range and the documented age bounds, not hardcoded separately ---
    expected_min_birth_year = min_year - MAX_AGE_AT_SIGNUP
    expected_max_birth_year = max_year - MIN_AGE_AT_SIGNUP
    bad_birth_years = df[(df["birth_year"] < expected_min_birth_year) | (df["birth_year"] > expected_max_birth_year)]
    if not bad_birth_years.empty:
        raise ValueError(
            f"Found {len(bad_birth_years)} row(s) with birth_year outside the plausible "
            f"range [{expected_min_birth_year}, {expected_max_birth_year}] implied by "
            f"ages {MIN_AGE_AT_SIGNUP}-{MAX_AGE_AT_SIGNUP} at signup."
        )

    # --- FK integrity against the LIVE parent tables (ED-007) --------------
    channel_lookup = load_dimension_lookup(
        db_path, "Dim_Marketing_Channel", ["marketing_channel_key", "channel_name"]
    )
    key_to_channel_name = dict(zip(channel_lookup["marketing_channel_key"], channel_lookup["channel_name"]))
    invalid_channel_fks = set(df["acquisition_channel_key"]) - set(key_to_channel_name.keys())
    if invalid_channel_fks:
        raise ValueError(
            f"Found acquisition_channel_key value(s) with no matching row in the "
            f"live Dim_Marketing_Channel table: {invalid_channel_fks}"
        )

    geography_lookup = load_dimension_lookup(
        db_path, "Dim_Geography", ["geography_key", "region"]
    )
    key_to_region = dict(zip(geography_lookup["geography_key"], geography_lookup["region"]))
    invalid_geo_fks = set(df["home_geography_key"]) - set(key_to_region.keys())
    if invalid_geo_fks:
        raise ValueError(
            f"Found home_geography_key value(s) with no matching row in the live "
            f"Dim_Geography table: {invalid_geo_fks}"
        )

    # --- Tolerance-based distribution checks (ED-008) -----------------------
    # These are genuinely random draws, not fixed enumerations like
    # Dim_Product's category counts -- exact-match validation would fail
    # spuriously on a perfectly correct generator, so a percentage-point
    # tolerance is used instead. See DISTRIBUTION_TOLERANCE_PCT's
    # module-level comment for the statistical justification.
    df_work["channel_name"] = df_work["acquisition_channel_key"].map(key_to_channel_name)
    channel_violations = []
    for year, expected_weights in CHANNEL_MIX_BY_YEAR.items():
        year_df = df_work[df_work["signup_year"] == year]
        year_total = len(year_df)
        actual_counts = year_df["channel_name"].value_counts()
        for channel_name, expected_share in expected_weights.items():
            actual_pct = 100.0 * actual_counts.get(channel_name, 0) / year_total
            expected_pct = expected_share * 100.0
            if abs(actual_pct - expected_pct) > DISTRIBUTION_TOLERANCE_PCT:
                channel_violations.append((year, channel_name, expected_pct, round(actual_pct, 1)))
    if channel_violations:
        raise ValueError(
            f"Acquisition channel mix drifted more than {DISTRIBUTION_TOLERANCE_PCT} "
            f"percentage points from target (year, channel, expected%, actual%): "
            f"{channel_violations}"
        )

    df_work["region"] = df_work["home_geography_key"].map(key_to_region)
    actual_region_counts = df_work["region"].value_counts()
    total = len(df_work)
    region_violations = []
    for region, expected_share in REGION_WEIGHTS.items():
        actual_pct = 100.0 * actual_region_counts.get(region, 0) / total
        expected_pct = expected_share * 100.0
        if abs(actual_pct - expected_pct) > DISTRIBUTION_TOLERANCE_PCT:
            region_violations.append((region, expected_pct, round(actual_pct, 1)))
    if region_violations:
        raise ValueError(
            f"Geography region mix drifted more than {DISTRIBUTION_TOLERANCE_PCT} "
            f"percentage points from target (region, expected%, actual%): {region_violations}"
        )


def write_csv(df: pd.DataFrame) -> Path:
    """
    Writes the already-validated DataFrame to data/generated/dim_customer.csv.

    Kept as a durable, human-inspectable artifact independent of the
    database load, same rationale as every prior phase's write_csv().
    """
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """
    Loads the validated DataFrame into Dim_Customer inside a single
    explicit transaction.

    Identical pattern to every prior phase's load_to_duckdb() (ED-004):
    DELETE + INSERT wrapped in BEGIN TRANSACTION / COMMIT, row count
    checked before commit, explicit ROLLBACK on any mismatch or
    exception, connection always closed in `finally`.

    Note: schema.sql's own FOREIGN KEY REFERENCES constraints on
    acquisition_channel_key and home_geography_key are a second,
    database-level line of defense on top of validate_dataframe()'s
    ED-007 checks -- if either FK were somehow invalid despite Python's
    validation, DuckDB itself would reject the INSERT and this function's
    ROLLBACK path would trigger.

    Raises FileNotFoundError if the database file doesn't exist yet.
    """
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"{DB_PATH} does not exist. Apply sql/schema.sql to this path first "
            f"to create the empty table structure before loading Dim_Customer."
        )

    expected_row_count = len(df)
    con = duckdb.connect(str(DB_PATH))
    transaction_open = False
    try:
        con.execute("BEGIN TRANSACTION")
        transaction_open = True

        con.execute("DELETE FROM Dim_Customer")
        con.execute(f"""
            INSERT INTO Dim_Customer ({", ".join(COLUMN_ORDER)})
            SELECT {", ".join(COLUMN_ORDER)} FROM df
        """)

        actual_row_count = con.execute("SELECT COUNT(*) FROM Dim_Customer").fetchone()[0]
        if actual_row_count != expected_row_count:
            con.execute("ROLLBACK")
            transaction_open = False
            raise ValueError(
                f"Row count mismatch after load: expected {expected_row_count}, "
                f"got {actual_row_count}. Transaction rolled back -- Dim_Customer "
                f"is unchanged from its state before this run."
            )

        con.execute("COMMIT")
        transaction_open = False
        return actual_row_count

    except Exception:
        if transaction_open:
            con.execute("ROLLBACK")
        raise
    finally:
        con.close()


def main():
    df = build_dataframe()
    validate_dataframe(df)

    csv_path = write_csv(df)
    print(f"Wrote {len(df)} rows to {csv_path}")

    row_count = load_to_duckdb(df)
    print(f"Loaded {row_count} rows into Dim_Customer at {DB_PATH}")


if __name__ == "__main__":
    main()
