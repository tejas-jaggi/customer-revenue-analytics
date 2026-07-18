"""
Shared database lookup utility — Solstice Apparel.

Extracted from generate_dim_customer.py (Phase 3.8) now that a second
real consumer needs the identical logic: generate_fact_orders.py
(Phase 3.9) also needs to resolve foreign keys by querying already-loaded
parent tables (ED-007), not by hardcoding or re-deriving their
key-assignment dicts.

This is a deliberately different threshold than campaign_calendar_
reference.py's small SEASON_BY_MONTH dict (ED-005), which stayed
duplicated across two generators because it was a 12-entry constant, not
substantial logic. This function is a real, non-trivial helper (a
read-only DB connection, existence checks, descriptive errors) -- with
a second real consumer already in hand and a third (Fact_Order_Lines,
Fact_Returns, Fact_Customer_Monthly_Snapshot will all need this too)
clearly coming, extracting it now avoids duplicating that logic a
second time, rather than waiting for a third copy to justify it.

See docs/engineering_decision_log.md ED-011.
"""

from pathlib import Path

import duckdb
import pandas as pd


def load_dimension_lookup(db_path: Path, table_name: str, columns: list) -> pd.DataFrame:
    """
    Reads a small, already-loaded parent dimension table directly from the
    database (ED-007), rather than hardcoding or re-deriving its
    key-assignment logic in the calling generator.

    Opened read-only: this function only ever needs to read a parent
    dimension, never write to it -- a read-only connection makes that
    guarantee explicit rather than relying on discipline.

    Deliberately checks only that the table exists and has at least one
    row -- NOT an exact row count. Which specific business dependencies
    (named channels, named regions, named categories) must actually be
    present is checked by the caller against the table's real content,
    keeping every consumer resilient to legitimate future expansion of a
    parent dimension.

    Raises FileNotFoundError if the database doesn't exist, ValueError if
    the parent table is empty -- both indicate the calling generator is
    being run out of order, before its dependencies are actually loaded.
    """
    if not db_path.exists():
        raise FileNotFoundError(
            f"{db_path} does not exist. Apply sql/schema.sql to this path first."
        )

    con = duckdb.connect(str(db_path), read_only=True)
    try:
        col_list = ", ".join(columns)
        lookup_df = con.execute(f"SELECT {col_list} FROM {table_name}").df()
    finally:
        con.close()

    if lookup_df.empty:
        raise ValueError(
            f"{table_name} has no rows. It must be generated and loaded before "
            f"this generator can resolve foreign keys against it -- check that "
            f"generate_{table_name.lower()}.py has been run."
        )
    return lookup_df
