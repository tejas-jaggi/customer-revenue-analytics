"""
Phase 3.5 - Dim_Campaign generator.

Dim_Campaign is the enriched version of the 21 campaign windows already
defined in campaign_calendar_reference.py (7 named campaigns x 3 years),
which Phase 3.1's generate_dim_date.py already consumes for
Dim_Date.campaign_period_flag. This generator is the SECOND consumer of
that same shared module -- deliberately reusing it rather than
re-defining the campaign calendar a second time, so Dim_Date and
Dim_Campaign can never disagree about when a campaign ran (see
campaign_calendar_reference.py's own module docstring, written back in
Phase 3.1 anticipating this exact generator).

What this generator adds on top of the shared module: campaign_calendar_
reference.py's scope was deliberately limited to campaign_name,
campaign_type, start_date, end_date -- enough for a boolean flag. Dim_
Campaign's schema needs three more NOT NULL fields (discount_depth,
season, target_audience) plus is_active_flag. Those are enrichment this
generator adds itself, not duplicated calendar logic:

    - discount_depth: a fixed per-campaign-type mapping from
      docs/business_glossary.md's campaign calendar table.
    - season: computed from start_date's month using the exact same
      Dec-Feb/Mar-May/Jun-Aug/Sep-Nov mapping generate_dim_date.py uses
      for Dim_Date.season. This is deliberately a calendar fact, not a
      marketing label -- "Spring Collection Launch" starts Feb 15, which
      is calendar Winter under this definition, so it will show
      season='Winter' despite the name. That's intentional: campaign_name
      carries the marketing framing, season is a consistent BI attribute
      computed identically everywhere in the warehouse. See the
      Interview section of docs/phase3_build_log.md for this exact
      question.
    - target_audience: every row in this MVP is "All Customers" -- the
      shared module defines 21 general campaign instances, not separate
      VIP-only or win-back-specific campaign rows. The schema's other
      enum values (New Customers, Loyal-VIP, Lapsed-Winback) are real
      and valid, just not populated by any row in this generation --
      reserved for a future phase that would need its own distinct
      campaign rows to use them, not a change to this generator.
    - is_active_flag: always True for this generation. This is a
      data-management flag (is this campaign definition currently in use
      in the system), not "is this campaign running today" -- none of
      these 21 historical campaign records are being retired.

Engineering standards (FPS v1.0, unchanged from Phase 3.2/3.3/3.4 -- see
docs/engineering_decision_log.md ED-001 through ED-004, plus ED-005
introduced by this phase for the shared-module consumption pattern):
    - Generation, validation, and database loading are separate functions.
    - Validation raises explicit exceptions (ValueError), never `assert`.
    - The database load is wrapped in an explicit transaction and is
      idempotent.

Run:
    python python/generators/generate_dim_campaign.py
"""

import sys
from pathlib import Path

import duckdb
import pandas as pd

sys.path.append(str(Path(__file__).parent))
from campaign_calendar_reference import get_campaign_windows

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "dim_campaign.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

EXPECTED_ROW_COUNT = 21  # 7 named campaigns x 3 years, per campaign_calendar_reference.py -- exact, not a range
EXPECTED_YEARS = {2023, 2024, 2025}

VALID_CAMPAIGN_TYPES = {"Seasonal Launch", "Promotional Sale", "Clearance"}
VALID_DISCOUNT_DEPTHS = {"None", "Light", "Moderate", "Deep", "Deepest"}
VALID_SEASONS = {"Spring", "Summer", "Fall", "Winter"}
VALID_TARGET_AUDIENCES = {"All Customers", "New Customers", "Loyal-VIP", "Lapsed-Winback"}

DEFAULT_TARGET_AUDIENCE = "All Customers"  # MVP scope -- see module docstring

COLUMN_ORDER = [
    "campaign_key", "campaign_name", "campaign_type", "start_date", "end_date",
    "discount_depth", "season", "target_audience", "is_active_flag",
]

# Same month -> season mapping generate_dim_date.py uses for Dim_Date.season.
# Deliberately duplicated here rather than imported: generators shouldn't
# import each other (only shared reference modules like
# campaign_calendar_reference.py), and this is a 12-entry constant used in
# exactly two places -- not enough duplication to justify extracting a
# second shared module over. If a third generator ever needs it, that's
# the trigger to promote it into campaign_calendar_reference.py or a new
# shared date-utilities module.
_SEASON_BY_MONTH = {
    12: "Winter", 1: "Winter", 2: "Winter",
    3: "Spring", 4: "Spring", 5: "Spring",
    6: "Summer", 7: "Summer", 8: "Summer",
    9: "Fall", 10: "Fall", 11: "Fall",
}

# Canonical base-campaign-name -> discount_depth, from
# docs/business_glossary.md's campaign calendar table. Keyed by the
# campaign's base name (without the year suffix that
# campaign_calendar_reference.py appends), since that module produces
# names like "Black Friday 2024", not "Black Friday".
_DISCOUNT_DEPTH_BY_BASE_NAME = {
    "Spring Collection Launch": "None",
    "Summer Sale": "Moderate",
    "Back-to-School": "Moderate",
    "Black Friday": "Deep",
    "Cyber Monday": "Deep",
    "Holiday Collection": "Light",
    "January Clearance": "Deepest",
}


def _base_campaign_name(campaign_name: str) -> str:
    """
    Strips the trailing year from a campaign_name produced by
    campaign_calendar_reference.py (e.g. "Black Friday 2024" ->
    "Black Friday"). Splitting on the last space is safe here because
    none of the 7 base campaign names themselves end in a number or
    contain a trailing space -- verified against every name the shared
    module actually produces, not assumed.
    """
    return campaign_name.rsplit(" ", 1)[0]


def build_dataframe() -> pd.DataFrame:
    """
    Builds the Dim_Campaign rows by enriching campaign_calendar_reference.
    get_campaign_windows()'s 21 base windows with discount_depth, season,
    target_audience, and is_active_flag.

    campaign_key is assigned by the shared module's own iteration order
    (1-indexed) -- deterministic and reproducible because
    get_campaign_windows() itself is deterministic (see that module's
    docstring), not because of anything this function adds.
    """
    windows = get_campaign_windows()
    rows = []
    for idx, window in enumerate(windows, start=1):
        campaign_name = window["campaign_name"]
        base_name = _base_campaign_name(campaign_name)

        discount_depth = _DISCOUNT_DEPTH_BY_BASE_NAME.get(base_name)
        if discount_depth is None:
            raise ValueError(
                f"No discount_depth mapping found for campaign base name "
                f"'{base_name}' (derived from '{campaign_name}') -- add it to "
                f"_DISCOUNT_DEPTH_BY_BASE_NAME before generating."
            )

        start_date = window["start_date"]
        season = _SEASON_BY_MONTH.get(start_date.month)
        if season is None:
            raise ValueError(
                f"No season mapping found for month {start_date.month} "
                f"(campaign '{campaign_name}', start_date {start_date}) -- "
                f"_SEASON_BY_MONTH should cover all 12 months."
            )

        rows.append({
            "campaign_key": idx,
            "campaign_name": campaign_name,
            "campaign_type": window["campaign_type"],
            "start_date": start_date,
            "end_date": window["end_date"],
            "discount_depth": discount_depth,
            "season": season,
            "target_audience": DEFAULT_TARGET_AUDIENCE,
            "is_active_flag": True,
        })

    return pd.DataFrame(rows, columns=COLUMN_ORDER)


def validate_dataframe(df: pd.DataFrame) -> None:
    """
    Business-rule validation performed in memory, before anything is
    written to disk or the database.

    This table is larger and richer than Phase 3.3/3.4's (9 columns vs.
    3, an enrichment layer instead of a flat lookup), so this function is
    intentionally more thorough than Dim_Sales_Channel's, not simplified
    to match its row count -- per the standing instruction not to
    lighten validation just because a table is bigger.

    Every failure raises a descriptive ValueError -- never `assert`, per
    ED-003.
    """
    if df.empty:
        raise ValueError(f"Dim_Campaign DataFrame is empty -- expected exactly {EXPECTED_ROW_COUNT} rows.")

    row_count = len(df)
    if row_count != EXPECTED_ROW_COUNT:
        raise ValueError(
            f"Dim_Campaign row count {row_count} does not match the exact expected "
            f"count of {EXPECTED_ROW_COUNT} (7 named campaigns x 3 years, per "
            f"campaign_calendar_reference.py) -- the shared module's output changed "
            f"unexpectedly."
        )

    # --- Surrogate key integrity -----------------------------------------
    if df["campaign_key"].isnull().any():
        raise ValueError("campaign_key contains nulls -- every row must have a surrogate key.")
    if not df["campaign_key"].is_unique:
        raise ValueError("campaign_key must be unique -- found duplicate surrogate keys.")

    expected_keys = set(range(1, row_count + 1))
    actual_keys = set(df["campaign_key"])
    if actual_keys != expected_keys:
        raise ValueError(
            "campaign_key must be a contiguous sequence starting at 1 (this is what "
            f"Fact_Orders.campaign_key will later reference) -- found a mismatch: "
            f"{sorted(actual_keys ^ expected_keys)}"
        )

    # --- NOT NULL columns --------------------------------------------------
    required_not_null = [
        "campaign_name", "campaign_type", "start_date", "end_date",
        "discount_depth", "season", "target_audience", "is_active_flag",
    ]
    for col in required_not_null:
        if df[col].isnull().any():
            raise ValueError(
                f"Column '{col}' contains nulls, which violates the NOT NULL "
                f"constraint defined for Dim_Campaign in schema.sql."
            )

    # --- Uniqueness ----------------------------------------------------
    if not df["campaign_name"].is_unique:
        raise ValueError("campaign_name must be unique -- found a duplicate campaign_name.")

    # --- Enum membership -------------------------------------------------
    invalid_types = set(df["campaign_type"]) - VALID_CAMPAIGN_TYPES
    if invalid_types:
        raise ValueError(f"Found campaign_type values outside the valid set {VALID_CAMPAIGN_TYPES}: {invalid_types}")

    invalid_discounts = set(df["discount_depth"]) - VALID_DISCOUNT_DEPTHS
    if invalid_discounts:
        raise ValueError(f"Found discount_depth values outside the valid set {VALID_DISCOUNT_DEPTHS}: {invalid_discounts}")

    invalid_seasons = set(df["season"]) - VALID_SEASONS
    if invalid_seasons:
        raise ValueError(f"Found season values outside the valid set {VALID_SEASONS}: {invalid_seasons}")

    invalid_audiences = set(df["target_audience"]) - VALID_TARGET_AUDIENCES
    if invalid_audiences:
        raise ValueError(f"Found target_audience values outside the valid set {VALID_TARGET_AUDIENCES}: {invalid_audiences}")

    # --- Date logic (pre-checks the schema.sql CHECK (end_date >= start_date)) ---
    bad_date_order = df[df["end_date"] < df["start_date"]]
    if not bad_date_order.empty:
        raise ValueError(
            f"Found {len(bad_date_order)} row(s) where end_date precedes start_date, "
            f"which would fail schema.sql's CHECK (end_date >= start_date) constraint:\n"
            f"{bad_date_order[['campaign_name', 'start_date', 'end_date']].to_string(index=False)}"
        )

    # --- Structural completeness: every base campaign appears exactly once per year ---
    df_copy = df.copy()
    df_copy["base_name"] = df_copy["campaign_name"].apply(_base_campaign_name)
    df_copy["year"] = pd.to_datetime(df_copy["start_date"]).dt.year

    actual_base_names = set(df_copy["base_name"])
    expected_base_names = set(_DISCOUNT_DEPTH_BY_BASE_NAME.keys())
    if actual_base_names != expected_base_names:
        raise ValueError(
            f"Base campaign names don't match the documented calendar. "
            f"Missing: {expected_base_names - actual_base_names}; "
            f"Unexpected: {actual_base_names - expected_base_names}"
        )

    actual_years = set(df_copy["year"])
    if actual_years != EXPECTED_YEARS:
        raise ValueError(f"Expected campaign years {EXPECTED_YEARS}, found {actual_years}.")

    counts_per_base = df_copy.groupby("base_name")["year"].nunique()
    incomplete = counts_per_base[counts_per_base != len(EXPECTED_YEARS)]
    if not incomplete.empty:
        raise ValueError(
            f"Every campaign should appear exactly once per year "
            f"({len(EXPECTED_YEARS)} years). Found a mismatch: {incomplete.to_dict()}"
        )

    # --- Output cross-check: discount_depth matches the canonical mapping ---
    # Same rationale as Dim_Marketing_Channel/Dim_Sales_Channel: catches a
    # future edit that changes the mapping without updating generated rows.
    discount_mismatches = [
        (row.campaign_name, row.discount_depth, _DISCOUNT_DEPTH_BY_BASE_NAME[_base_campaign_name(row.campaign_name)])
        for row in df.itertuples()
        if row.discount_depth != _DISCOUNT_DEPTH_BY_BASE_NAME.get(_base_campaign_name(row.campaign_name))
    ]
    if discount_mismatches:
        raise ValueError(f"campaign_name/discount_depth mismatches against the canonical mapping: {discount_mismatches}")

    # --- Output cross-check: season matches recomputation from start_date ---
    season_mismatches = [
        (row.campaign_name, row.start_date, row.season, _SEASON_BY_MONTH[row.start_date.month])
        for row in df.itertuples()
        if row.season != _SEASON_BY_MONTH.get(row.start_date.month)
    ]
    if season_mismatches:
        raise ValueError(f"campaign_name/season mismatches against the recomputed calendar season: {season_mismatches}")

    # --- Expected distributions (exact, not a range -- this table's shape is
    #     fully deterministic given campaign_calendar_reference.py) ---
    discount_counts = df["discount_depth"].value_counts().to_dict()
    expected_discount_counts = {"None": 3, "Moderate": 6, "Deep": 6, "Light": 3, "Deepest": 3}
    if discount_counts != expected_discount_counts:
        raise ValueError(
            f"discount_depth distribution mismatch. Expected {expected_discount_counts}, "
            f"got {discount_counts}."
        )

    type_counts = df["campaign_type"].value_counts().to_dict()
    expected_type_counts = {"Promotional Sale": 12, "Seasonal Launch": 6, "Clearance": 3}
    if type_counts != expected_type_counts:
        raise ValueError(
            f"campaign_type distribution mismatch. Expected {expected_type_counts}, "
            f"got {type_counts}."
        )

    # season distribution deliberately has NO Spring rows -- "Spring Collection
    # Launch" starts Feb 15, which is calendar Winter under _SEASON_BY_MONTH.
    # This is documented, expected behavior, not a bug -- see module docstring.
    season_counts = df["season"].value_counts().to_dict()
    expected_season_counts = {"Winter": 8, "Fall": 7, "Summer": 6}
    if season_counts != expected_season_counts:
        raise ValueError(
            f"season distribution mismatch. Expected {expected_season_counts} "
            f"(note: 'Spring' is expected to be absent entirely -- see module "
            f"docstring), got {season_counts}."
        )

    # --- MVP-scope constants: every row should carry the same defaults ---
    if not (df["target_audience"] == DEFAULT_TARGET_AUDIENCE).all():
        raise ValueError(
            f"Expected every row's target_audience to be '{DEFAULT_TARGET_AUDIENCE}' "
            f"in this MVP generation -- found other values: "
            f"{set(df['target_audience']) - {DEFAULT_TARGET_AUDIENCE}}"
        )
    if not df["is_active_flag"].all():
        raise ValueError("Expected every row's is_active_flag to be True in this initial generation.")


def write_csv(df: pd.DataFrame) -> Path:
    """
    Writes the already-validated DataFrame to data/generated/dim_campaign.csv.

    Kept as a durable, human-inspectable artifact independent of the
    database load, same rationale as every prior phase's write_csv().
    """
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """
    Loads the validated DataFrame into Dim_Campaign inside a single
    explicit transaction.

    Identical pattern to every prior phase's load_to_duckdb() (ED-004):
    DELETE + INSERT wrapped in BEGIN TRANSACTION / COMMIT, row count
    checked before commit, explicit ROLLBACK on any mismatch or
    exception, connection always closed in `finally`.

    Note: schema.sql's CHECK (end_date >= start_date) constraint is a
    second, database-level line of defense -- validate_dataframe()
    already checks this in Python, but the DB constraint stays in place
    as a backstop for any future load path (e.g. a manually edited CSV
    loaded via sql/generation/load_dim_campaign.sql) that bypasses this
    generator entirely.

    Raises FileNotFoundError if the database file doesn't exist yet.
    """
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"{DB_PATH} does not exist. Apply sql/schema.sql to this path first "
            f"to create the empty table structure before loading Dim_Campaign."
        )

    expected_row_count = len(df)
    con = duckdb.connect(str(DB_PATH))
    transaction_open = False
    try:
        con.execute("BEGIN TRANSACTION")
        transaction_open = True

        con.execute("DELETE FROM Dim_Campaign")
        con.execute(f"""
            INSERT INTO Dim_Campaign ({", ".join(COLUMN_ORDER)})
            SELECT {", ".join(COLUMN_ORDER)} FROM df
        """)

        actual_row_count = con.execute("SELECT COUNT(*) FROM Dim_Campaign").fetchone()[0]
        if actual_row_count != expected_row_count:
            con.execute("ROLLBACK")
            transaction_open = False
            raise ValueError(
                f"Row count mismatch after load: expected {expected_row_count}, "
                f"got {actual_row_count}. Transaction rolled back -- Dim_Campaign "
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
    print(f"Loaded {row_count} rows into Dim_Campaign at {DB_PATH}")


if __name__ == "__main__":
    main()
