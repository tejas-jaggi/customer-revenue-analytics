"""
Phase 3.3 - Dim_Marketing_Channel generator.

Dim_Marketing_Channel is fixed taxonomy, not simulated behavior: it is the
closed set of 6 acquisition channels defined in docs/business_glossary.md
that Dim_Customer.acquisition_channel_key and Fact_Orders.acquisition_channel_key
will reference. Like Dim_Geography, there is no randomness anywhere in this
generator -- the correctness bar is "does this match the documented
taxonomy exactly," not "does this look statistically plausible."

Why an exact row count (6) rather than a range: unlike Dim_Geography
(40-50 real cities, some reasonable variation acceptable), the channel
taxonomy is a closed business definition already locked in
business_glossary.md. There is no "roughly 6" -- it is exactly the 6
channels documented there, no more, no less. A 7th channel appearing here
would mean the glossary and the warehouse have silently drifted apart.

Engineering standards (FPS v1.0, unchanged from Phase 3.2 -- see
docs/engineering_decision_log.md ED-001 through ED-004, all still in
effect with no deviations for this table):
    - Generation, validation, and database loading are separate functions.
    - Validation raises explicit exceptions (ValueError), never `assert`.
    - The database load is wrapped in an explicit transaction and is
      idempotent.

Run:
    python python/generators/generate_dim_marketing_channel.py
"""

from pathlib import Path

import duckdb
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "dim_marketing_channel.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

VALID_CATEGORIES = {"Paid", "Organic", "Owned"}
EXPECTED_ROW_COUNT = 6  # closed taxonomy per docs/business_glossary.md -- exact, not a range

COLUMN_ORDER = ["marketing_channel_key", "channel_name", "channel_category"]

# Canonical channel -> category mapping, copied verbatim from
# docs/business_glossary.md's "Acquisition / Marketing Channels" table.
# Order here is the order channels appear in that table, which becomes
# the deterministic key assignment order below (Paid Social = 1, ...,
# Direct = 6). This is the single source for this table's content --
# unlike Dim_Geography's state/region split, there is no second
# independent source to cross-check here, so validate_dataframe() checks
# the OUTPUT directly against this same dict instead of checking one
# hand-typed list against another.
_CHANNEL_CATEGORY = {
    "Paid Social": "Paid",
    "Paid Search": "Paid",
    "Organic/SEO": "Organic",
    "Email/SMS": "Owned",
    "Affiliate/Referral": "Paid",
    "Direct": "Organic",
}


def build_dataframe() -> pd.DataFrame:
    """
    Builds the Dim_Marketing_Channel rows from the canonical
    _CHANNEL_CATEGORY mapping, in glossary order.

    marketing_channel_key is assigned by dict iteration order (1-indexed).
    Deterministic and reproducible by construction: Python dicts preserve
    insertion order, and this dict's literal source never changes between
    runs.
    """
    rows = [
        {
            "marketing_channel_key": idx,
            "channel_name": channel_name,
            "channel_category": category,
        }
        for idx, (channel_name, category) in enumerate(_CHANNEL_CATEGORY.items(), start=1)
    ]
    return pd.DataFrame(rows, columns=COLUMN_ORDER)


def validate_dataframe(df: pd.DataFrame) -> None:
    """
    Business-rule validation performed in memory, before anything is
    written to disk or the database.

    Every failure raises a descriptive ValueError -- never `assert`, per
    ED-003: `assert` is compiled out entirely under Python's `-O` flag, so
    an ETL pipeline that depends on it for data-quality gating can silently
    stop validating in that configuration.
    """
    if df.empty:
        raise ValueError(f"Dim_Marketing_Channel DataFrame is empty -- expected exactly {EXPECTED_ROW_COUNT} rows.")

    row_count = len(df)
    if row_count != EXPECTED_ROW_COUNT:
        raise ValueError(
            f"Dim_Marketing_Channel row count {row_count} does not match the exact "
            f"expected count of {EXPECTED_ROW_COUNT} (closed taxonomy per "
            f"docs/business_glossary.md) -- a channel was added, removed, or "
            f"duplicated somewhere in _CHANNEL_CATEGORY."
        )

    if df["marketing_channel_key"].isnull().any():
        raise ValueError("marketing_channel_key contains nulls -- every row must have a surrogate key.")
    if not df["marketing_channel_key"].is_unique:
        raise ValueError("marketing_channel_key must be unique -- found duplicate surrogate keys.")

    expected_keys = set(range(1, row_count + 1))
    actual_keys = set(df["marketing_channel_key"])
    if actual_keys != expected_keys:
        raise ValueError(
            "marketing_channel_key must be a contiguous sequence starting at 1 (this is "
            "what Dim_Customer.acquisition_channel_key and Fact_Orders.acquisition_channel_key "
            f"will later reference) -- found a mismatch: {sorted(actual_keys ^ expected_keys)}"
        )

    for col in ["channel_name", "channel_category"]:
        if df[col].isnull().any():
            raise ValueError(
                f"Column '{col}' contains nulls, which violates the NOT NULL "
                f"constraint defined for Dim_Marketing_Channel in schema.sql."
            )

    expected_names = set(_CHANNEL_CATEGORY.keys())
    actual_names = set(df["channel_name"])
    if actual_names != expected_names:
        raise ValueError(
            f"channel_name values don't match the documented taxonomy in "
            f"business_glossary.md. Missing: {expected_names - actual_names}; "
            f"Unexpected: {actual_names - expected_names}"
        )

    if not df["channel_name"].is_unique:
        raise ValueError("channel_name must be unique -- found a duplicate channel name.")

    invalid_categories = set(df["channel_category"]) - VALID_CATEGORIES
    if invalid_categories:
        raise ValueError(f"Found channel_category values outside the valid set {VALID_CATEGORIES}: {invalid_categories}")

    # Cross-check every row's category against the canonical mapping --
    # catches a transcription slip (right channel, wrong category) even
    # though both come from the same dict, in case a future edit changes
    # one without the other in some intermediate refactor.
    mismatches = [
        (row.channel_name, row.channel_category, _CHANNEL_CATEGORY[row.channel_name])
        for row in df.itertuples()
        if row.channel_category != _CHANNEL_CATEGORY.get(row.channel_name)
    ]
    if mismatches:
        raise ValueError(f"channel_name/channel_category mismatches against the canonical mapping: {mismatches}")


def write_csv(df: pd.DataFrame) -> Path:
    """
    Writes the already-validated DataFrame to data/generated/dim_marketing_channel.csv.

    Kept as a durable, human-inspectable artifact independent of the
    database load, same rationale as Dim_Geography's write_csv().
    """
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """
    Loads the validated DataFrame into Dim_Marketing_Channel inside a
    single explicit transaction.

    Identical pattern to Dim_Geography's load_to_duckdb() (ED-004):
    DELETE + INSERT wrapped in BEGIN TRANSACTION / COMMIT, row count
    checked before commit, explicit ROLLBACK on any mismatch or
    exception, connection always closed in `finally`.

    Raises FileNotFoundError if the database file doesn't exist yet.
    """
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"{DB_PATH} does not exist. Apply sql/schema.sql to this path first "
            f"to create the empty table structure before loading Dim_Marketing_Channel."
        )

    expected_row_count = len(df)
    con = duckdb.connect(str(DB_PATH))
    transaction_open = False
    try:
        con.execute("BEGIN TRANSACTION")
        transaction_open = True

        con.execute("DELETE FROM Dim_Marketing_Channel")
        con.execute(f"""
            INSERT INTO Dim_Marketing_Channel ({", ".join(COLUMN_ORDER)})
            SELECT {", ".join(COLUMN_ORDER)} FROM df
        """)

        actual_row_count = con.execute("SELECT COUNT(*) FROM Dim_Marketing_Channel").fetchone()[0]
        if actual_row_count != expected_row_count:
            con.execute("ROLLBACK")
            transaction_open = False
            raise ValueError(
                f"Row count mismatch after load: expected {expected_row_count}, "
                f"got {actual_row_count}. Transaction rolled back -- "
                f"Dim_Marketing_Channel is unchanged from its state before this run."
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
    print(f"Loaded {row_count} rows into Dim_Marketing_Channel at {DB_PATH}")


if __name__ == "__main__":
    main()
