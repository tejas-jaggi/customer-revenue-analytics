"""
Phase 3.2 - Dim_Geography generator.

Dim_Geography is master/reference data, not simulated behavior: it is a
fixed, curated list of real US city/state/region/postal_code combinations
that Dim_Customer and Fact_Orders will later reference. Because it's
reference data rather than a business process, this generator has no
randomness anywhere -- the correctness bar is "does every row reflect a
real, verifiable US location," not "does this look statistically
plausible."

Why real, curated cities instead of procedurally generated ones: every
downstream regional cut in Phase 5/6/8 is only as credible as this table.
Real cities also make Dim_Geography self-checkable -- the canonical
state -> region mapping used in build_dataframe() below is what catches a
copy-paste mistake (a Texas city tagged "Midwest") before it ever reaches
disk, which a synthetic/fabricated place name couldn't support.

Engineering standards (FPS v1.0, adopted Phase 3.2):
    - Generation, validation, and database loading are separate functions,
      each independently testable and independently callable.
    - Validation raises explicit exceptions (ValueError), never `assert` --
      `assert` statements are stripped when Python runs with `-O`, which
      makes them unsafe for anything that must always execute.
    - The database load is wrapped in an explicit transaction and is
      idempotent: re-running this script any number of times converges on
      the same 40-50 rows, never duplicates or partial state.

Run:
    python python/generators/generate_dim_geography.py
"""

from pathlib import Path

import duckdb
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "dim_geography.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

VALID_REGIONS = {"Northeast", "Midwest", "South", "West"}
MIN_EXPECTED_ROWS = 40
MAX_EXPECTED_ROWS = 50
MIN_CITIES_PER_REGION = 8  # below this, regional cuts in Phase 5/6 get too thin to mean much

COLUMN_ORDER = ["geography_key", "city", "state", "region", "country", "postal_code"]

# Canonical state -> region mapping. Used only to validate _RAW_GEOGRAPHIES
# against itself in build_dataframe() -- this is a check on the generation
# INPUT's internal consistency, not on the shape of the generated OUTPUT,
# which is why it lives here rather than in validate_dataframe().
_STATE_TO_REGION = {
    "NY": "Northeast", "MA": "Northeast", "PA": "Northeast", "NJ": "Northeast", "CT": "Northeast",
    "IL": "Midwest", "OH": "Midwest", "MI": "Midwest", "WI": "Midwest", "MN": "Midwest", "MO": "Midwest",
    "TX": "South", "FL": "South", "GA": "South", "NC": "South", "TN": "South", "VA": "South",
    "CA": "West", "WA": "West", "OR": "West", "AZ": "West", "CO": "West", "NV": "West",
}

# geography_key is assigned by list position (1-indexed) in build_dataframe().
# Deterministic and reproducible by construction: this list never changes
# between runs, so the same city always gets the same key every time.
_RAW_GEOGRAPHIES = [
    # (city, state, region, postal_code)
    ("New York", "NY", "Northeast", "10001"),
    ("Brooklyn", "NY", "Northeast", "11201"),
    ("Buffalo", "NY", "Northeast", "14202"),
    ("Boston", "MA", "Northeast", "02108"),
    ("Cambridge", "MA", "Northeast", "02138"),
    ("Philadelphia", "PA", "Northeast", "19102"),
    ("Pittsburgh", "PA", "Northeast", "15222"),
    ("Newark", "NJ", "Northeast", "07102"),
    ("Jersey City", "NJ", "Northeast", "07302"),
    ("Hartford", "CT", "Northeast", "06103"),
    ("Stamford", "CT", "Northeast", "06901"),

    ("Chicago", "IL", "Midwest", "60601"),
    ("Naperville", "IL", "Midwest", "60540"),
    ("Columbus", "OH", "Midwest", "43215"),
    ("Cleveland", "OH", "Midwest", "44113"),
    ("Cincinnati", "OH", "Midwest", "45202"),
    ("Detroit", "MI", "Midwest", "48226"),
    ("Ann Arbor", "MI", "Midwest", "48104"),
    ("Milwaukee", "WI", "Midwest", "53202"),
    ("Minneapolis", "MN", "Midwest", "55401"),
    ("St. Paul", "MN", "Midwest", "55102"),
    ("St. Louis", "MO", "Midwest", "63101"),

    ("Houston", "TX", "South", "77002"),
    ("Austin", "TX", "South", "78701"),
    ("Dallas", "TX", "South", "75201"),
    ("San Antonio", "TX", "South", "78205"),
    ("Miami", "FL", "South", "33131"),
    ("Orlando", "FL", "South", "32801"),
    ("Tampa", "FL", "South", "33602"),
    ("Atlanta", "GA", "South", "30303"),
    ("Charlotte", "NC", "South", "28202"),
    ("Raleigh", "NC", "South", "27601"),
    ("Nashville", "TN", "South", "37203"),
    ("Richmond", "VA", "South", "23219"),

    ("Los Angeles", "CA", "West", "90012"),
    ("San Francisco", "CA", "West", "94102"),
    ("San Diego", "CA", "West", "92101"),
    ("Sacramento", "CA", "West", "95814"),
    ("Seattle", "WA", "West", "98101"),
    ("Portland", "OR", "West", "97201"),
    ("Phoenix", "AZ", "West", "85004"),
    ("Tucson", "AZ", "West", "85701"),
    ("Denver", "CO", "West", "80202"),
    ("Boulder", "CO", "West", "80302"),
    ("Las Vegas", "NV", "West", "89101"),
    ("Reno", "NV", "West", "89501"),
]


def build_dataframe() -> pd.DataFrame:
    """
    Builds the Dim_Geography rows from the curated _RAW_GEOGRAPHIES list.

    Why this raises ValueError instead of silently trusting the list:
    _RAW_GEOGRAPHIES is hand-maintained, and hand-maintained lists are
    exactly where a copy-paste error (the wrong region next to the right
    state) hides. Checking every row against the canonical
    _STATE_TO_REGION mapping here means that kind of mistake fails loudly,
    at generation time, instead of silently shipping bad regional data
    that Phase 5/6 analysis would only notice as an unexplained anomaly.
    """
    rows = []
    for idx, (city, state, region, postal_code) in enumerate(_RAW_GEOGRAPHIES, start=1):
        expected_region = _STATE_TO_REGION.get(state)
        if expected_region is None:
            raise ValueError(
                f"State '{state}' (city: {city}) is not in the canonical "
                f"_STATE_TO_REGION mapping -- add it before generating."
            )
        if region != expected_region:
            raise ValueError(
                f"Row for {city}, {state} declares region='{region}', but the "
                f"canonical mapping says '{state}' belongs to '{expected_region}'. "
                f"Fix the _RAW_GEOGRAPHIES entry."
            )
        rows.append({
            "geography_key": idx,
            "city": city,
            "state": state,
            "region": region,
            "country": "United States",
            "postal_code": postal_code,
        })

    return pd.DataFrame(rows, columns=COLUMN_ORDER)


def validate_dataframe(df: pd.DataFrame) -> None:
    """
    Business-rule validation performed in memory, before anything is
    written to disk or the database.

    Every failure here raises a descriptive ValueError rather than using
    `assert`. This matters for ETL specifically: `assert` statements are
    compiled out entirely when Python runs with the `-O` flag, so code
    that relies on `assert` for data-quality gating can silently stop
    validating anything in certain deployment configurations. An explicit
    `raise ValueError(...)` always executes and always carries a message
    describing exactly what's wrong and why it matters.
    """
    if df.empty:
        raise ValueError("Dim_Geography DataFrame is empty -- expected 40-50 rows.")

    row_count = len(df)
    if not (MIN_EXPECTED_ROWS <= row_count <= MAX_EXPECTED_ROWS):
        raise ValueError(
            f"Dim_Geography row count {row_count} is outside the expected "
            f"{MIN_EXPECTED_ROWS}-{MAX_EXPECTED_ROWS} range documented in "
            f"data_generation_strategy.md Section 3."
        )

    if df["geography_key"].isnull().any():
        raise ValueError("geography_key contains nulls -- every row must have a surrogate key.")
    if not df["geography_key"].is_unique:
        raise ValueError("geography_key must be unique -- found duplicate surrogate keys.")

    expected_keys = set(range(1, row_count + 1))
    actual_keys = set(df["geography_key"])
    if actual_keys != expected_keys:
        raise ValueError(
            "geography_key must be a contiguous sequence starting at 1 (this is what "
            "Dim_Customer.home_geography_key and Fact_Orders.geography_key will later "
            f"reference) -- found a mismatch: {sorted(actual_keys ^ expected_keys)}"
        )

    required_not_null = ["city", "state", "region", "country", "postal_code"]
    for col in required_not_null:
        if df[col].isnull().any():
            raise ValueError(
                f"Column '{col}' contains nulls, which violates the NOT NULL "
                f"constraint defined for Dim_Geography in schema.sql."
            )

    invalid_regions = set(df["region"]) - VALID_REGIONS
    if invalid_regions:
        raise ValueError(f"Found region values outside the valid set {VALID_REGIONS}: {invalid_regions}")

    bad_postal_codes = df.loc[
        ~df["postal_code"].astype(str).str.match(r"^\d{5}$"), "postal_code"
    ].tolist()
    if bad_postal_codes:
        raise ValueError(f"postal_code values must be exactly 5 digits: {bad_postal_codes}")

    duplicate_city_state = df[df.duplicated(subset=["city", "state"], keep=False)]
    if not duplicate_city_state.empty:
        raise ValueError(
            "Duplicate (city, state) combinations found -- each location should "
            f"appear exactly once:\n{duplicate_city_state[['city', 'state']].to_string(index=False)}"
        )

    region_counts = df["region"].value_counts()
    missing_regions = VALID_REGIONS - set(region_counts.index)
    if missing_regions:
        raise ValueError(f"No rows generated for region(s): {missing_regions} -- all 4 regions must be represented.")

    thin_regions = region_counts[region_counts < MIN_CITIES_PER_REGION]
    if not thin_regions.empty:
        raise ValueError(
            f"Region(s) with fewer than {MIN_CITIES_PER_REGION} cities are too thin "
            f"for meaningful regional analysis in Phase 5/6: {thin_regions.to_dict()}"
        )


def write_csv(df: pd.DataFrame) -> Path:
    """
    Writes the already-validated DataFrame to data/generated/dim_geography.csv.

    The CSV is kept as a durable, human-inspectable artifact, independent
    of the database load -- sql/generation/load_dim_geography.sql can
    re-load these exact validated rows at any time without re-running
    this Python generator.
    """
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """
    Loads the validated DataFrame into Dim_Geography inside a single
    explicit transaction.

    Why a transaction: DELETE-then-INSERT is only safe to call repeatedly
    (idempotent) if a failure partway through can't leave the table half
    -deleted or half-loaded. Wrapping both statements in BEGIN
    TRANSACTION / COMMIT means a failure at any point rolls back to the
    exact pre-load state -- there is no observable intermediate state.

    Row count is checked against the DataFrame's row count BEFORE the
    commit; a mismatch triggers an explicit rollback and a raised
    ValueError instead of committing a partial load.

    Raises FileNotFoundError if the database file doesn't exist yet --
    this generator assumes sql/schema.sql has already been applied.
    """
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"{DB_PATH} does not exist. Apply sql/schema.sql to this path first "
            f"to create the empty table structure before loading Dim_Geography."
        )

    expected_row_count = len(df)
    con = duckdb.connect(str(DB_PATH))
    transaction_open = False
    try:
        con.execute("BEGIN TRANSACTION")
        transaction_open = True

        con.execute("DELETE FROM Dim_Geography")
        con.execute(f"""
            INSERT INTO Dim_Geography ({", ".join(COLUMN_ORDER)})
            SELECT {", ".join(COLUMN_ORDER)} FROM df
        """)

        actual_row_count = con.execute("SELECT COUNT(*) FROM Dim_Geography").fetchone()[0]
        if actual_row_count != expected_row_count:
            con.execute("ROLLBACK")
            transaction_open = False
            raise ValueError(
                f"Row count mismatch after load: expected {expected_row_count}, "
                f"got {actual_row_count}. Transaction rolled back -- Dim_Geography "
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
    print(f"Loaded {row_count} rows into Dim_Geography at {DB_PATH}")


if __name__ == "__main__":
    main()
