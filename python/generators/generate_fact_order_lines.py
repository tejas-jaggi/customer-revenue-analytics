"""
Phase 3.10 - Fact_Order_Lines generator.

Persists the LINE half of the shared simulation in
order_generation_core.simulate_orders_and_lines() -- the same call, same
seeds, same inputs as generate_fact_orders.py, which persists the header
half. Reconciliation (SUM(net_line_revenue) == Fact_Orders.net_revenue
per order) is therefore true by construction (ED-010): both tables are
two views of one simulated object. The refactor that moved the full
simulation into the shared core was verified by re-running
generate_fact_orders.py and confirming BYTE-IDENTICAL output against the
pre-refactor CSV before this generator was written.

Grain: one row per product per order. Line discounts are allocated
proportionally from the order's header discount with the rounding
remainder assigned to the final line (no RNG draws), so line sums match
header figures exactly, not approximately.

Engineering standards unchanged: ED-001..ED-011 (explicit exceptions,
transaction-wrapped idempotent load, live-parent FK validation,
tolerance checks only where genuinely random).

Run:
    python python/generators/generate_fact_order_lines.py
"""

import sys
from pathlib import Path

import duckdb
import pandas as pd

sys.path.append(str(Path(__file__).parent))
from db_utils import load_dimension_lookup
from order_generation_core import (
    prepare_simulation_inputs,
    simulate_orders_and_lines,
    LINE_ITEM_COUNT_WEIGHTS,
    LINE_ITEM_COUNT_CHOICES,
)

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "fact_order_lines.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

RANDOM_SEED = 42
PERSONA_ASSIGNMENT_SEED = 42

COLUMN_ORDER = [
    "order_line_key", "order_key", "customer_key", "product_key", "order_date_key",
    "quantity", "unit_price", "gross_line_revenue", "discount_amount",
    "net_line_revenue", "unit_cost",
]

# Emergent range: lines per order averages ~1.29 (documented calibration),
# so expected lines ~= 1.29 x Fact_Orders rows. Wide bounds catch real
# bugs without failing on sampling variance (ED-008 philosophy).
EXPECTED_LINES_PER_ORDER_RANGE = (1.20, 1.45)


def build_dataframe(seed: int = RANDOM_SEED, persona_seed: int = PERSONA_ASSIGNMENT_SEED, db_path: Path = DB_PATH) -> pd.DataFrame:
    """Thin wrapper: replay the shared simulation, keep the line half."""
    inputs = prepare_simulation_inputs(db_path)
    _order_rows, line_rows = simulate_orders_and_lines(seed, persona_seed, inputs)
    return pd.DataFrame(line_rows, columns=COLUMN_ORDER)


def validate_dataframe(df: pd.DataFrame, db_path: Path = DB_PATH) -> None:
    """
    Key integrity, FK integrity against live parents (including the
    just-loaded Fact_Orders), line-math consistency, and THE check this
    table exists to satisfy: exact per-order reconciliation to
    Fact_Orders.net_revenue. Explicit exceptions only (ED-003).
    """
    if df.empty:
        raise ValueError("Fact_Order_Lines DataFrame is empty.")

    n = len(df)
    if df["order_line_key"].isnull().any() or not df["order_line_key"].is_unique:
        raise ValueError("order_line_key must be non-null and unique.")
    if set(df["order_line_key"]) != set(range(1, n + 1)):
        raise ValueError("order_line_key must be contiguous starting at 1.")

    for col in COLUMN_ORDER[1:]:
        if df[col].isnull().any():
            raise ValueError(f"Column '{col}' contains nulls, violating NOT NULL in schema.sql.")

    if (df["quantity"] <= 0).any():
        raise ValueError("quantity must be > 0 for every line.")
    for col in ["unit_price", "gross_line_revenue", "discount_amount", "net_line_revenue", "unit_cost"]:
        if (df[col] < 0).any():
            raise ValueError(f"{col} contains negative values, violating schema CHECK constraints.")

    bad_gross = df[(df["gross_line_revenue"] - (df["quantity"] * df["unit_price"]).round(2)).abs() > 0.01]
    if not bad_gross.empty:
        raise ValueError(f"gross_line_revenue != quantity x unit_price for {len(bad_gross)} row(s).")
    bad_net = df[(df["net_line_revenue"] - (df["gross_line_revenue"] - df["discount_amount"]).round(2)).abs() > 0.005]
    if not bad_net.empty:
        raise ValueError(f"net_line_revenue != gross - discount for {len(bad_net)} row(s).")

    # FK integrity against live parents (ED-007)
    orders = load_dimension_lookup(db_path, "Fact_Orders", ["order_key", "net_revenue", "customer_key", "order_date_key"])
    bad_fk = set(df["order_key"]) - set(orders["order_key"])
    if bad_fk:
        raise ValueError(f"order_key value(s) missing from live Fact_Orders: {sorted(bad_fk)[:10]}")
    customers = load_dimension_lookup(db_path, "Dim_Customer", ["customer_key"])
    if set(df["customer_key"]) - set(customers["customer_key"]):
        raise ValueError("customer_key value(s) missing from Dim_Customer.")
    products = load_dimension_lookup(db_path, "Dim_Product", ["product_key"])
    if set(df["product_key"]) - set(products["product_key"]):
        raise ValueError("product_key value(s) missing from Dim_Product.")
    dates = load_dimension_lookup(db_path, "Dim_Date", ["date_key"])
    if set(df["order_date_key"]) - set(dates["date_key"]):
        raise ValueError("order_date_key value(s) missing from Dim_Date.")

    # Every order must have at least one line, and lines/order in range
    lines_per_order = df.groupby("order_key").size()
    missing_orders = set(orders["order_key"]) - set(lines_per_order.index)
    if missing_orders:
        raise ValueError(f"{len(missing_orders)} order(s) in Fact_Orders have no lines at all.")
    avg_lines = lines_per_order.mean()
    lo, hi = EXPECTED_LINES_PER_ORDER_RANGE
    if not (lo <= avg_lines <= hi):
        raise ValueError(f"Average lines/order {avg_lines:.3f} outside expected range {EXPECTED_LINES_PER_ORDER_RANGE}.")
    if lines_per_order.max() > max(LINE_ITEM_COUNT_CHOICES):
        raise ValueError(f"Some order has {lines_per_order.max()} lines, exceeding the documented max of {max(LINE_ITEM_COUNT_CHOICES)}.")

    # Denormalized consistency: line customer/date must match the header's
    merged = df.merge(orders, on="order_key", suffixes=("", "_hdr"))
    mism = merged[(merged["customer_key"] != merged["customer_key_hdr"]) | (merged["order_date_key"] != merged["order_date_key_hdr"])]
    if not mism.empty:
        raise ValueError(f"{len(mism)} line(s) disagree with their header's customer_key/order_date_key.")

    # THE reconciliation check (must hold exactly, by construction)
    line_sums = df.groupby("order_key")["net_line_revenue"].sum().round(2)
    hdr = orders.set_index("order_key")["net_revenue"].round(2)
    joined = line_sums.to_frame("line_sum").join(hdr)
    bad = joined[(joined["line_sum"] - joined["net_revenue"]).abs() > 0.005]
    if not bad.empty:
        raise ValueError(
            f"RECONCILIATION FAILURE: SUM(net_line_revenue) != Fact_Orders.net_revenue "
            f"for {len(bad)} order(s), e.g. {bad.head(3).to_dict('index')}"
        )


def write_csv(df: pd.DataFrame) -> Path:
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """Transaction-wrapped idempotent load (ED-004), identical pattern."""
    if not DB_PATH.exists():
        raise FileNotFoundError(f"{DB_PATH} does not exist. Apply sql/schema.sql first.")
    expected = len(df)
    con = duckdb.connect(str(DB_PATH))
    txn = False
    try:
        con.execute("BEGIN TRANSACTION"); txn = True
        con.execute("DELETE FROM Fact_Order_Lines")
        con.execute(f"INSERT INTO Fact_Order_Lines ({', '.join(COLUMN_ORDER)}) SELECT {', '.join(COLUMN_ORDER)} FROM df")
        actual = con.execute("SELECT COUNT(*) FROM Fact_Order_Lines").fetchone()[0]
        if actual != expected:
            con.execute("ROLLBACK"); txn = False
            raise ValueError(f"Row count mismatch after load: expected {expected}, got {actual}. Rolled back.")
        con.execute("COMMIT"); txn = False
        return actual
    except Exception:
        if txn:
            con.execute("ROLLBACK")
        raise
    finally:
        con.close()


def main():
    df = build_dataframe()
    validate_dataframe(df)
    print(f"Wrote {len(df)} rows to {write_csv(df)}")
    print(f"Loaded {load_to_duckdb(df)} rows into Fact_Order_Lines at {DB_PATH}")


if __name__ == "__main__":
    main()
