"""
Phase 3.4 - Dim_Sales_Channel generator.

Dim_Sales_Channel is fixed taxonomy, not simulated behavior: it is the
closed set of 3 channels Solstice Apparel actually sells through
(Website, Mobile App, Marketplace), defined in docs/business_glossary.md
and referenced by Fact_Orders.sales_channel_key. Same shape as
Dim_Marketing_Channel (Phase 3.3): a single canonical mapping, no
randomness, no two-source cross-check like Dim_Geography needed.

Why an exact row count (3) rather than a range: identical reasoning to
Dim_Marketing_Channel -- this is a closed business definition already
locked in business_glossary.md, not a curated-but-flexible list like
Dim_Geography's city selection. A 4th channel appearing here would mean
the glossary and the warehouse have silently drifted apart.

Engineering standards (FPS v1.0, unchanged from Phase 3.2/3.3 -- see
docs/engineering_decision_log.md ED-001 through ED-004, all still in
effect with no deviations for this table):
    - Generation, validation, and database loading are separate functions.
    - Validation raises explicit exceptions (ValueError), never `assert`.
    - The database load is wrapped in an explicit transaction and is
      idempotent.

Run:
    python python/generators/generate_dim_sales_channel.py
"""

from pathlib import Path

import duckdb
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "dim_sales_channel.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

VALID_TYPES = {"Owned", "Third-Party"}
EXPECTED_ROW_COUNT = 3  # closed taxonomy per docs/business_glossary.md -- exact, not a range

COLUMN_ORDER = ["sales_channel_key", "channel_name", "channel_type"]

# Canonical channel -> type mapping, copied verbatim from
# docs/business_glossary.md's "Sales Channels" table. Order here is the
# order channels appear there, which becomes the deterministic key
# assignment order below (Website = 1, Mobile App = 2, Marketplace = 3).
# Single source, same as Dim_Marketing_Channel's _CHANNEL_CATEGORY --
# validate_dataframe() checks the generated OUTPUT against this same
# dict rather than needing a second independent source to cross-check
# against, since there isn't one for this table (unlike Dim_Geography's
# state/region split).
_CHANNEL_TYPE = {
    "Website": "Owned",
    "Mobile App": "Owned",
    "Marketplace": "Third-Party",
}


def build_dataframe() -> pd.DataFrame:
    """
    Builds the Dim_Sales_Channel rows from the canonical _CHANNEL_TYPE
    mapping, in glossary order.

    sales_channel_key is assigned by dict iteration order (1-indexed).
    Deterministic and reproducible by construction: Python dicts preserve
    insertion order, and this dict's literal source never changes
    between runs.
    """
    rows = [
        {
            "sales_channel_key": idx,
            "channel_name": channel_name,
            "channel_type": channel_type,
        }
        for idx, (channel_name, channel_type) in enumerate(_CHANNEL_TYPE.items(), start=1)
    ]
    return pd.DataFrame(rows, columns=COLUMN_ORDER)


def validate_dataframe(df: pd.DataFrame) -> None:
    """
    Business-rule validation performed in memory, before anything is
    written to disk or the database.

    Every failure raises a descriptive ValueError -- never `assert`, per
    ED-003: `assert` is compiled out entirely under Python's `-O` flag, so
    an ETL pipeline that depends on it for data-quality gating can
    silently stop validating in that configuration.
    """
    if df.empty:
        raise ValueError(f"Dim_Sales_Channel DataFrame is empty -- expected exactly {EXPECTED_ROW_COUNT} rows.")

    row_count = len(df)
    if row_count != EXPECTED_ROW_COUNT:
        raise ValueError(
            f"Dim_Sales_Channel row count {row_count} does not match the exact "
            f"expected count of {EXPECTED_ROW_COUNT} (closed taxonomy per "
            f"docs/business_glossary.md) -- a channel was added, removed, or "
            f"duplicated somewhere in _CHANNEL_TYPE."
        )

    if df["sales_channel_key"].isnull().any():
        raise ValueError("sales_channel_key contains nulls -- every row must have a surrogate key.")
    if not df["sales_channel_key"].is_unique:
        raise ValueError("sales_channel_key must be unique -- found duplicate surrogate keys.")

    expected_keys = set(range(1, row_count + 1))
    actual_keys = set(df["sales_channel_key"])
    if actual_keys != expected_keys:
        raise ValueError(
            "sales_channel_key must be a contiguous sequence starting at 1 (this is "
            f"what Fact_Orders.sales_channel_key will later reference) -- found a "
            f"mismatch: {sorted(actual_keys ^ expected_keys)}"
        )

    for col in ["channel_name", "channel_type"]:
        if df[col].isnull().any():
            raise ValueError(
                f"Column '{col}' contains nulls, which violates the NOT NULL "
                f"constraint defined for Dim_Sales_Channel in schema.sql."
            )

    expected_names = set(_CHANNEL_TYPE.keys())
    actual_names = set(df["channel_name"])
    if actual_names != expected_names:
        raise ValueError(
            f"channel_name values don't match the documented taxonomy in "
            f"business_glossary.md. Missing: {expected_names - actual_names}; "
            f"Unexpected: {actual_names - expected_names}"
        )

    if not df["channel_name"].is_unique:
        raise ValueError("channel_name must be unique -- found a duplicate channel name.")

    invalid_types = set(df["channel_type"]) - VALID_TYPES
    if invalid_types:
        raise ValueError(f"Found channel_type values outside the valid set {VALID_TYPES}: {invalid_types}")

    # Cross-check every row's type against the canonical mapping -- catches
    # a transcription slip (right channel, wrong type) even though both
    # come from the same dict, same rationale as Dim_Marketing_Channel.
    mismatches = [
        (row.channel_name, row.channel_type, _CHANNEL_TYPE[row.channel_name])
        for row in df.itertuples()
        if row.channel_type != _CHANNEL_TYPE.get(row.channel_name)
    ]
    if mismatches:
        raise ValueError(f"channel_name/channel_type mismatches against the canonical mapping: {mismatches}")


def write_csv(df: pd.DataFrame) -> Path:
    """
    Writes the already-validated DataFrame to data/generated/dim_sales_channel.csv.

    Kept as a durable, human-inspectable artifact independent of the
    database load, same rationale as Phase 3.2/3.3's write_csv().
    """
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """
    Loads the validated DataFrame into Dim_Sales_Channel inside a single
    explicit transaction.

    Identical pattern to Dim_Marketing_Channel's load_to_duckdb() (ED-004):
    DELETE + INSERT wrapped in BEGIN TRANSACTION / COMMIT, row count
    checked before commit, explicit ROLLBACK on any mismatch or
    exception, connection always closed in `finally`.

    Raises FileNotFoundError if the database file doesn't exist yet.
    """
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"{DB_PATH} does not exist. Apply sql/schema.sql to this path first "
            f"to create the empty table structure before loading Dim_Sales_Channel."
        )

    expected_row_count = len(df)
    con = duckdb.connect(str(DB_PATH))
    transaction_open = False
    try:
        con.execute("BEGIN TRANSACTION")
        transaction_open = True

        con.execute("DELETE FROM Dim_Sales_Channel")
        con.execute(f"""
            INSERT INTO Dim_Sales_Channel ({", ".join(COLUMN_ORDER)})
            SELECT {", ".join(COLUMN_ORDER)} FROM df
        """)

        actual_row_count = con.execute("SELECT COUNT(*) FROM Dim_Sales_Channel").fetchone()[0]
        if actual_row_count != expected_row_count:
            con.execute("ROLLBACK")
            transaction_open = False
            raise ValueError(
                f"Row count mismatch after load: expected {expected_row_count}, "
                f"got {actual_row_count}. Transaction rolled back -- "
                f"Dim_Sales_Channel is unchanged from its state before this run."
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
    print(f"Loaded {row_count} rows into Dim_Sales_Channel at {DB_PATH}")


if __name__ == "__main__":
    main()
