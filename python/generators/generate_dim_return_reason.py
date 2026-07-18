"""
Phase 3.7 - Dim_Return_Reason generator.

Dim_Return_Reason is fixed taxonomy, not simulated behavior: the closed
set of 6 return reasons defined in docs/business_glossary.md's "Return
Reasons" table, referenced by Fact_Returns.return_reason_key. Same shape
as Dim_Marketing_Channel (Phase 3.3) and Dim_Sales_Channel (Phase 3.4):
a single canonical mapping, no randomness, exact row count rather than a
range.

The one genuinely new wrinkle this table introduces -- worth flagging
even though it isn't an engineering-pattern change -- is is_controllable.
docs/business_glossary.md's source table has six reasons, but two of them
don't answer "Yes/No" cleanly:

    - Late Delivery is marked "Partially (logistics fix)" in the glossary.
    - Other is marked "N/A" in the glossary.

schema.sql defines is_controllable as BOOLEAN NOT NULL -- there's no
"partially" or "not applicable" option. This generator makes an explicit,
documented judgment call rather than silently picking one:

    - Late Delivery -> TRUE. "Partially controllable" still means there's
      a real business lever (carrier selection, delivery-time buffers,
      warehouse SLAs) -- unlike Changed Mind, where the business has zero
      actionable lever over a customer's personal preference change.
      Rounding "partially" to "controllable" keeps the flag meaningful
      for the Phase 8 question it exists to answer: which return drivers
      can the business actually act on.
    - Other -> FALSE. "Other" is an unclassified catch-all. Without a
      specific identified cause, there's no concrete fix to point to, so
      the conservative default is "not controllable" rather than
      overclaiming actionability for a bucket that by definition doesn't
      have one.

This is a business-content decision, not an engineering-pattern one, so
it doesn't get its own docs/engineering_decision_log.md entry (that log
is scoped to code structure/transactions/error handling) -- it's
documented here and in docs/phase3_build_log.md instead, the same way
Dim_Campaign's target_audience/is_active_flag MVP defaults were handled
in Phase 3.5 rather than logged as engineering decisions.

Engineering standards (FPS v1.0, unchanged from Phase 3.2-3.6 -- see
docs/engineering_decision_log.md ED-001 through ED-006, all still in
effect with no deviations for this table): generation, validation, and
database loading remain separate functions; validation raises explicit
exceptions, never `assert`; the database load is transaction-wrapped and
idempotent. This table needs no randomness, so ED-006's seeding pattern
doesn't apply here -- same as every closed-taxonomy table before Dim_Product.

Run:
    python python/generators/generate_dim_return_reason.py
"""

from pathlib import Path

import duckdb
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "dim_return_reason.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

EXPECTED_ROW_COUNT = 6  # closed taxonomy per docs/business_glossary.md -- exact, not a range

COLUMN_ORDER = ["return_reason_key", "reason_code", "reason_description", "is_controllable"]

# Canonical reason_code -> (reason_description, is_controllable), copied
# verbatim (description wording) from docs/business_glossary.md's
# "Return Reasons" table. See module docstring for the Late
# Delivery / Other boolean-mapping rationale. Order here is the order
# reasons appear in that table, which becomes the deterministic key
# assignment order below (Wrong Size = 1, ..., Other = 6).
_RETURN_REASONS = {
    "WRONG_SIZE":         {"description": "Wrong Size",               "is_controllable": True},
    "DEFECTIVE_QUALITY":  {"description": "Defective/Quality Issue",  "is_controllable": True},
    "NOT_AS_DESCRIBED":   {"description": "Not as Described",         "is_controllable": True},
    "CHANGED_MIND":       {"description": "Changed Mind",             "is_controllable": False},
    "LATE_DELIVERY":      {"description": "Late Delivery",            "is_controllable": True},
    "OTHER":              {"description": "Other",                   "is_controllable": False},
}


def build_dataframe() -> pd.DataFrame:
    """
    Builds the Dim_Return_Reason rows from the canonical _RETURN_REASONS
    mapping, in glossary order.

    return_reason_key is assigned by dict iteration order (1-indexed).
    Deterministic and reproducible by construction: Python dicts preserve
    insertion order, and this dict's literal source never changes
    between runs. No randomness anywhere in this table -- same as every
    closed-taxonomy dimension before Dim_Product.
    """
    rows = [
        {
            "return_reason_key": idx,
            "reason_code": code,
            "reason_description": info["description"],
            "is_controllable": info["is_controllable"],
        }
        for idx, (code, info) in enumerate(_RETURN_REASONS.items(), start=1)
    ]
    return pd.DataFrame(rows, columns=COLUMN_ORDER)


def validate_dataframe(df: pd.DataFrame) -> None:
    """
    Business-rule validation performed in memory, before anything is
    written to disk or the database.

    Every failure raises a descriptive ValueError -- never `assert`, per
    ED-003.
    """
    if df.empty:
        raise ValueError(f"Dim_Return_Reason DataFrame is empty -- expected exactly {EXPECTED_ROW_COUNT} rows.")

    row_count = len(df)
    if row_count != EXPECTED_ROW_COUNT:
        raise ValueError(
            f"Dim_Return_Reason row count {row_count} does not match the exact "
            f"expected count of {EXPECTED_ROW_COUNT} (closed taxonomy per "
            f"docs/business_glossary.md) -- a reason was added, removed, or "
            f"duplicated somewhere in _RETURN_REASONS."
        )

    if df["return_reason_key"].isnull().any():
        raise ValueError("return_reason_key contains nulls -- every row must have a surrogate key.")
    if not df["return_reason_key"].is_unique:
        raise ValueError("return_reason_key must be unique -- found duplicate surrogate keys.")

    expected_keys = set(range(1, row_count + 1))
    actual_keys = set(df["return_reason_key"])
    if actual_keys != expected_keys:
        raise ValueError(
            "return_reason_key must be a contiguous sequence starting at 1 (this is "
            f"what Fact_Returns.return_reason_key will later reference) -- found a "
            f"mismatch: {sorted(actual_keys ^ expected_keys)}"
        )

    for col in ["reason_code", "reason_description", "is_controllable"]:
        if df[col].isnull().any():
            raise ValueError(
                f"Column '{col}' contains nulls, which violates the NOT NULL "
                f"constraint defined for Dim_Return_Reason in schema.sql."
            )

    expected_codes = set(_RETURN_REASONS.keys())
    actual_codes = set(df["reason_code"])
    if actual_codes != expected_codes:
        raise ValueError(
            f"reason_code values don't match the documented taxonomy in "
            f"business_glossary.md. Missing: {expected_codes - actual_codes}; "
            f"Unexpected: {actual_codes - expected_codes}"
        )
    if not df["reason_code"].is_unique:
        raise ValueError("reason_code must be unique -- found a duplicate reason_code.")

    expected_descriptions = {info["description"] for info in _RETURN_REASONS.values()}
    actual_descriptions = set(df["reason_description"])
    if actual_descriptions != expected_descriptions:
        raise ValueError(
            f"reason_description values don't match the documented taxonomy. "
            f"Missing: {expected_descriptions - actual_descriptions}; "
            f"Unexpected: {actual_descriptions - expected_descriptions}"
        )
    if not df["reason_description"].is_unique:
        raise ValueError("reason_description must be unique -- found a duplicate description.")

    # is_controllable must be actual booleans, not truthy strings/ints --
    # the Late Delivery / Other mapping decision only means anything if
    # the stored value is a real boolean, not "True"/"1" as a string.
    non_bool_values = [v for v in df["is_controllable"] if not isinstance(v, (bool,))]
    if non_bool_values:
        raise ValueError(
            f"is_controllable must contain actual booleans, found non-boolean "
            f"value(s): {non_bool_values}"
        )

    # Cross-check every row's is_controllable against the canonical mapping --
    # catches a transcription slip (right reason, wrong flag) even though
    # both come from the same dict, same rationale as every prior
    # closed-taxonomy table's output cross-check.
    mismatches = [
        (row.reason_code, row.is_controllable, _RETURN_REASONS[row.reason_code]["is_controllable"])
        for row in df.itertuples()
        if row.is_controllable != _RETURN_REASONS.get(row.reason_code, {}).get("is_controllable")
    ]
    if mismatches:
        raise ValueError(f"reason_code/is_controllable mismatches against the canonical mapping: {mismatches}")

    # Expected distribution: 4 controllable (Wrong Size, Defective/Quality,
    # Not as Described, Late Delivery), 2 not controllable (Changed Mind,
    # Other) -- exact, not a range, since this table's shape is fully
    # deterministic given _RETURN_REASONS.
    controllable_count = int(df["is_controllable"].sum())
    if controllable_count != 4:
        raise ValueError(
            f"Expected exactly 4 controllable reasons (Wrong Size, "
            f"Defective/Quality Issue, Not as Described, Late Delivery), "
            f"found {controllable_count}."
        )
    not_controllable_count = row_count - controllable_count
    if not_controllable_count != 2:
        raise ValueError(
            f"Expected exactly 2 non-controllable reasons (Changed Mind, Other), "
            f"found {not_controllable_count}."
        )


def write_csv(df: pd.DataFrame) -> Path:
    """
    Writes the already-validated DataFrame to data/generated/dim_return_reason.csv.

    Kept as a durable, human-inspectable artifact independent of the
    database load, same rationale as every prior phase's write_csv().
    """
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """
    Loads the validated DataFrame into Dim_Return_Reason inside a single
    explicit transaction.

    Identical pattern to every prior phase's load_to_duckdb() (ED-004):
    DELETE + INSERT wrapped in BEGIN TRANSACTION / COMMIT, row count
    checked before commit, explicit ROLLBACK on any mismatch or
    exception, connection always closed in `finally`.

    Raises FileNotFoundError if the database file doesn't exist yet.
    """
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"{DB_PATH} does not exist. Apply sql/schema.sql to this path first "
            f"to create the empty table structure before loading Dim_Return_Reason."
        )

    expected_row_count = len(df)
    con = duckdb.connect(str(DB_PATH))
    transaction_open = False
    try:
        con.execute("BEGIN TRANSACTION")
        transaction_open = True

        con.execute("DELETE FROM Dim_Return_Reason")
        con.execute(f"""
            INSERT INTO Dim_Return_Reason ({", ".join(COLUMN_ORDER)})
            SELECT {", ".join(COLUMN_ORDER)} FROM df
        """)

        actual_row_count = con.execute("SELECT COUNT(*) FROM Dim_Return_Reason").fetchone()[0]
        if actual_row_count != expected_row_count:
            con.execute("ROLLBACK")
            transaction_open = False
            raise ValueError(
                f"Row count mismatch after load: expected {expected_row_count}, "
                f"got {actual_row_count}. Transaction rolled back -- "
                f"Dim_Return_Reason is unchanged from its state before this run."
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
    print(f"Loaded {row_count} rows into Dim_Return_Reason at {DB_PATH}")


if __name__ == "__main__":
    main()
