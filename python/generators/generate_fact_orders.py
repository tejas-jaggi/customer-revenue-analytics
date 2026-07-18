"""
Phase 3.9 - Fact_Orders generator.

The first fact table in this warehouse, and the first generator that
simulates actual customer purchasing behavior rather than reference data
or master data. See docs/engineering_decision_log.md ED-009 and ED-010
for the two genuinely new patterns this phase introduces: deterministic
persona assignment (deferred from Phase 3.8 on purpose, see that
generator's docstring) and a shared order/line-item generation core that
this table's header revenue is computed from.

Grain: one row per order (header level). gross_revenue, discount_amount,
and net_revenue are all AGGREGATES of internally-simulated line items
(via order_generation_core.generate_line_items_for_order()) -- this
generator does not persist those line items itself (that's
Fact_Order_Lines, a future phase), but it cannot compute realistic
header revenue without simulating them first. This is why Fact_Orders
depends on Dim_Product being loaded even though Dim_Product doesn't
appear as a foreign key anywhere in Fact_Orders' own schema.

Dependencies (all must be loaded first):
    Dim_Customer          (customer_key, signup_date, acquisition_channel_key, home_geography_key)
    Dim_Product           (product_key, category, list_price, unit_cost -- for revenue simulation only)
    Dim_Campaign          (campaign_key, campaign_name, discount_depth -- for attribution)
    Dim_Sales_Channel     (sales_channel_key, channel_name)
    Dim_Date              (full_date range, to confirm order dates fall within it)

Row count is NOT deterministic the way every prior table's was -- it
emerges from 8,000 customers each independently sampling a persona-driven
order count. docs/data_generation_strategy.md Section 3 estimated ~65,000
orders total; validate_dataframe() checks a wide but real range, not an
exact figure, consistent with ED-008's tolerance-based philosophy now
applied to a fact table's total row count, not just a dimension's
category distribution.

Validation targets below are transcribed directly from
docs/data_generation_strategy.md Section 9 -- this is the first
generator whose own validation closes the loop back to numbers that
section specified before any code existed.

Run:
    python python/generators/generate_fact_orders.py
"""

import sys
from datetime import timedelta
from pathlib import Path
from random import Random

import duckdb
import pandas as pd

sys.path.append(str(Path(__file__).parent))
from db_utils import load_dimension_lookup
from campaign_calendar_reference import get_campaign_windows
from order_generation_core import (
    assign_customer_personas,
    prepare_simulation_inputs,
    simulate_orders_and_lines,
    FREE_SHIPPING_THRESHOLD,
    FLAT_SHIPPING_FEE,
)

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "fact_orders.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

RANDOM_SEED = 42               # order timing / line-item simulation RNG
PERSONA_ASSIGNMENT_SEED = 42   # separate Random() instance, same seed value, per ED-009

HORIZON_END = pd.Timestamp("2025-12-31").date()

# --- Business rule: sales channel mix, no documented persona dependency,
#     targeting Marketplace within data_generation_strategy.md Section 9's
#     documented 10-15% share-of-orders validation target. ---
# --- Row count: emergent, not deterministic (ED-008 extended to a fact
#     table). Section 3's "~65,000 orders (roughly 8 orders per customer)"
#     estimate turned out to be jointly inconsistent with Section 9's
#     35-45% repeat-purchase-rate target once the retention-conversion
#     mechanism required to hit that target was implemented: with only
#     ~40% of customers repeating at all, ~25-35k orders is the
#     mathematically natural volume. Section 9 is the explicit pass/fail
#     authority ("these become the pass/fail thresholds"), Section 3 was
#     a sizing estimate -- resolved in favor of Section 9, documented in
#     docs/phase3_build_log.md Phase 3.9. This range still catches real
#     generation bugs (everyone at 0 or 100 orders). ---
EXPECTED_ROW_COUNT_RANGE = (18_000, 60_000)

# --- docs/data_generation_strategy.md Section 9 validation targets,
#     the ones computable from Fact_Orders alone (AOV, campaign revenue
#     share, marketplace share, holiday revenue share, repeat purchase
#     rate -- return rate and churn-risk prevalence need Fact_Returns and
#     Fact_Customer_Monthly_Snapshot, which don't exist yet). ---
AOV_TARGET_RANGE = (65.0, 85.0)
CAMPAIGN_REVENUE_SHARE_TARGET_RANGE = (0.30, 0.40)
MARKETPLACE_ORDER_SHARE_TARGET_RANGE = (0.10, 0.15)
HOLIDAY_REVENUE_SHARE_TARGET_RANGE = (0.25, 0.30)
REPEAT_PURCHASE_RATE_TARGET_RANGE = (0.35, 0.45)
# Validation tolerance applied multiplicatively on top of the documented
# target range itself -- these are realized from genuine random draws, so
# a small buffer accounts for legitimate sampling variance without
# loosening the target itself.
VALIDATION_TOLERANCE = 0.05

COLUMN_ORDER = [
    "order_key", "order_id", "customer_key", "order_date_key", "sales_channel_key",
    "geography_key", "campaign_key", "acquisition_channel_key",
    "gross_revenue", "discount_amount", "net_revenue", "shipping_revenue", "is_first_order",
]


def _date_range(start, end):
    current = start
    while current <= end:
        yield current
        current += timedelta(days=1)


def build_dataframe(seed: int = RANDOM_SEED, persona_seed: int = PERSONA_ASSIGNMENT_SEED, db_path: Path = DB_PATH) -> pd.DataFrame:
    """
    Thin wrapper over the shared simulation (ED-010 completed): prepares
    inputs from the live database and persists the ORDER-HEADER half of
    simulate_orders_and_lines(). generate_fact_order_lines.py persists
    the other half of the very same simulated objects, which is what
    makes header/line reconciliation true by construction.
    """
    inputs = prepare_simulation_inputs(db_path)
    order_rows, _line_rows = simulate_orders_and_lines(seed, persona_seed, inputs)
    df = pd.DataFrame(order_rows, columns=COLUMN_ORDER)
    df["campaign_key"] = df["campaign_key"].astype("Int64")
    return df


def validate_dataframe(df: pd.DataFrame, db_path: Path = DB_PATH) -> None:
    """
    Business-rule validation performed in memory, before anything is
    written to disk or the database.

    This is the richest validation suite in the project so far -- key
    integrity, referential integrity against live parent tables (ED-007),
    internal revenue-math consistency, and -- for the first time -- five
    validation targets pulled directly from docs/data_generation_
    strategy.md Section 9, closing the loop back to numbers that document
    specified before this generator existed.

    Every failure raises a descriptive ValueError -- never `assert`, per
    ED-003.
    """
    if df.empty:
        raise ValueError("Fact_Orders DataFrame is empty -- expected tens of thousands of rows.")

    row_count = len(df)
    lo, hi = EXPECTED_ROW_COUNT_RANGE
    if not (lo <= row_count <= hi):
        raise ValueError(
            f"Fact_Orders row count {row_count} is outside the expected range "
            f"{EXPECTED_ROW_COUNT_RANGE} (docs/data_generation_strategy.md Section 3 "
            f"estimated ~65,000) -- this range is wide enough to accommodate genuine "
            f"sampling variance, so a miss here likely indicates a real generation bug."
        )

    # --- Key integrity ------------------------------------------------
    if df["order_key"].isnull().any():
        raise ValueError("order_key contains nulls.")
    if not df["order_key"].is_unique:
        raise ValueError("order_key must be unique -- found duplicates.")
    expected_keys = set(range(1, row_count + 1))
    actual_keys = set(df["order_key"])
    if actual_keys != expected_keys:
        raise ValueError(f"order_key must be contiguous starting at 1 -- mismatch: {sorted(actual_keys ^ expected_keys)[:20]}")

    if not df["order_id"].is_unique:
        raise ValueError("order_id must be unique.")
    bad_ids = df.loc[~df["order_id"].astype(str).str.match(r"^ORD-\d{6}$"), "order_id"].tolist()
    if bad_ids:
        raise ValueError(f"order_id values must match ORD-###### (6 digits): {bad_ids[:10]}")

    # --- NOT NULL sweep (campaign_key is the only nullable FK) -----------
    required_not_null = [
        "customer_key", "order_date_key", "sales_channel_key", "geography_key",
        "acquisition_channel_key", "gross_revenue", "discount_amount",
        "net_revenue", "shipping_revenue", "is_first_order",
    ]
    for col in required_not_null:
        if df[col].isnull().any():
            raise ValueError(f"Column '{col}' contains nulls, violating its NOT NULL constraint in schema.sql.")

    # --- FK integrity against LIVE parent tables (ED-007) -----------------
    customer_lookup = load_dimension_lookup(db_path, "Dim_Customer", ["customer_key"])
    invalid_customer_fks = set(df["customer_key"]) - set(customer_lookup["customer_key"])
    if invalid_customer_fks:
        raise ValueError(f"Found customer_key value(s) with no matching Dim_Customer row: {sorted(invalid_customer_fks)[:10]}")

    sales_channel_full = load_dimension_lookup(db_path, "Dim_Sales_Channel", ["sales_channel_key", "channel_name"])
    invalid_channel_fks = set(df["sales_channel_key"]) - set(sales_channel_full["sales_channel_key"])
    if invalid_channel_fks:
        raise ValueError(f"Found sales_channel_key value(s) with no matching Dim_Sales_Channel row: {sorted(invalid_channel_fks)}")

    geography_lookup = load_dimension_lookup(db_path, "Dim_Geography", ["geography_key"])
    invalid_geo_fks = set(df["geography_key"]) - set(geography_lookup["geography_key"])
    if invalid_geo_fks:
        raise ValueError(f"Found geography_key value(s) with no matching Dim_Geography row: {sorted(invalid_geo_fks)}")

    marketing_channel_lookup = load_dimension_lookup(db_path, "Dim_Marketing_Channel", ["marketing_channel_key"])
    invalid_mc_fks = set(df["acquisition_channel_key"]) - set(marketing_channel_lookup["marketing_channel_key"])
    if invalid_mc_fks:
        raise ValueError(f"Found acquisition_channel_key value(s) with no matching Dim_Marketing_Channel row: {sorted(invalid_mc_fks)}")

    campaign_lookup = load_dimension_lookup(db_path, "Dim_Campaign", ["campaign_key"])
    non_null_campaign_keys = set(df["campaign_key"].dropna())
    invalid_campaign_fks = non_null_campaign_keys - set(campaign_lookup["campaign_key"])
    if invalid_campaign_fks:
        raise ValueError(f"Found non-null campaign_key value(s) with no matching Dim_Campaign row: {sorted(invalid_campaign_fks)}")

    date_lookup = load_dimension_lookup(db_path, "Dim_Date", ["date_key"])
    invalid_date_fks = set(df["order_date_key"]) - set(date_lookup["date_key"])
    if invalid_date_fks:
        raise ValueError(f"Found order_date_key value(s) with no matching Dim_Date row: {sorted(invalid_date_fks)[:10]}")

    # --- Revenue math consistency -----------------------------------------
    if (df["gross_revenue"] < 0).any() or (df["discount_amount"] < 0).any() or (df["net_revenue"] < 0).any() or (df["shipping_revenue"] < 0).any():
        raise ValueError("Found negative revenue/discount/shipping values -- violates schema.sql's CHECK constraints.")

    recomputed_net = (df["gross_revenue"] - df["discount_amount"]).round(2)
    net_mismatches = df[(df["net_revenue"] - recomputed_net).abs() > 0.01]
    if not net_mismatches.empty:
        raise ValueError(f"net_revenue != gross_revenue - discount_amount for {len(net_mismatches)} row(s), e.g.: {net_mismatches.head(3).to_dict('records')}")

    no_campaign_with_discount = df[df["campaign_key"].isna() & (df["discount_amount"] != 0)]
    if not no_campaign_with_discount.empty:
        raise ValueError(f"Found {len(no_campaign_with_discount)} order(s) with no campaign_key but a nonzero discount_amount.")

    expected_shipping = df["net_revenue"].apply(lambda x: 0.0 if x >= FREE_SHIPPING_THRESHOLD else FLAT_SHIPPING_FEE)
    shipping_mismatches = df[(df["shipping_revenue"] - expected_shipping).abs() > 0.001]
    if not shipping_mismatches.empty:
        raise ValueError(f"shipping_revenue doesn't match the ${FREE_SHIPPING_THRESHOLD} free-shipping-threshold rule for {len(shipping_mismatches)} row(s).")

    # --- is_first_order: exactly one True per customer with >=1 order,
    #     and it must be on that customer's earliest order --------------
    first_order_counts = df.groupby("customer_key")["is_first_order"].sum()
    bad_first_order_customers = first_order_counts[first_order_counts != 1]
    if not bad_first_order_customers.empty:
        raise ValueError(f"{len(bad_first_order_customers)} customer(s) don't have exactly one is_first_order=True row.")

    earliest_date_per_customer = df.groupby("customer_key")["order_date_key"].min()
    flagged = df[df["is_first_order"]].set_index("customer_key")["order_date_key"]
    misflagged = flagged[flagged != earliest_date_per_customer.loc[flagged.index]]
    if not misflagged.empty:
        raise ValueError(f"{len(misflagged)} customer(s) have is_first_order=True on a row that isn't their earliest order.")

    # --- Validation targets from docs/data_generation_strategy.md Section 9 ---
    actual_aov = df["net_revenue"].mean()
    aov_lo = AOV_TARGET_RANGE[0] * (1 - VALIDATION_TOLERANCE)
    aov_hi = AOV_TARGET_RANGE[1] * (1 + VALIDATION_TOLERANCE)
    if not (aov_lo <= actual_aov <= aov_hi):
        raise ValueError(f"Blended AOV ${actual_aov:.2f} is outside the tolerance-widened target {AOV_TARGET_RANGE} (Section 9).")

    marketplace_keys = set(sales_channel_full.loc[sales_channel_full["channel_name"] == "Marketplace", "sales_channel_key"])
    marketplace_share = df["sales_channel_key"].isin(marketplace_keys).mean()
    mp_lo = MARKETPLACE_ORDER_SHARE_TARGET_RANGE[0] * (1 - VALIDATION_TOLERANCE)
    mp_hi = MARKETPLACE_ORDER_SHARE_TARGET_RANGE[1] * (1 + VALIDATION_TOLERANCE)
    if not (mp_lo <= marketplace_share <= mp_hi):
        raise ValueError(f"Marketplace order share {marketplace_share:.1%} is outside the tolerance-widened target {MARKETPLACE_ORDER_SHARE_TARGET_RANGE} (Section 9).")

    campaign_revenue_share = df.loc[df["campaign_key"].notna(), "net_revenue"].sum() / df["net_revenue"].sum()
    cr_lo = CAMPAIGN_REVENUE_SHARE_TARGET_RANGE[0] * (1 - VALIDATION_TOLERANCE)
    cr_hi = CAMPAIGN_REVENUE_SHARE_TARGET_RANGE[1] * (1 + VALIDATION_TOLERANCE)
    if not (cr_lo <= campaign_revenue_share <= cr_hi):
        raise ValueError(f"Campaign revenue share {campaign_revenue_share:.1%} is outside the tolerance-widened target {CAMPAIGN_REVENUE_SHARE_TARGET_RANGE} (Section 9).")

    order_dates = pd.to_datetime(df["order_date_key"].astype(str), format="%Y%m%d")
    holiday_mask = order_dates.dt.month.isin([11, 12])
    holiday_revenue_share = df.loc[holiday_mask, "net_revenue"].sum() / df["net_revenue"].sum()
    hr_lo = HOLIDAY_REVENUE_SHARE_TARGET_RANGE[0] * (1 - VALIDATION_TOLERANCE)
    hr_hi = HOLIDAY_REVENUE_SHARE_TARGET_RANGE[1] * (1 + VALIDATION_TOLERANCE)
    if not (hr_lo <= holiday_revenue_share <= hr_hi):
        raise ValueError(f"Holiday (Nov-Dec) revenue share {holiday_revenue_share:.1%} is outside the tolerance-widened target {HOLIDAY_REVENUE_SHARE_TARGET_RANGE} (Section 9).")

    total_customers = len(customer_lookup)
    orders_per_customer = df.groupby("customer_key").size()
    repeat_purchase_rate = (orders_per_customer >= 2).sum() / total_customers
    rp_lo = REPEAT_PURCHASE_RATE_TARGET_RANGE[0] * (1 - VALIDATION_TOLERANCE)
    rp_hi = REPEAT_PURCHASE_RATE_TARGET_RANGE[1] * (1 + VALIDATION_TOLERANCE)
    if not (rp_lo <= repeat_purchase_rate <= rp_hi):
        raise ValueError(f"Repeat purchase rate {repeat_purchase_rate:.1%} is outside the tolerance-widened target {REPEAT_PURCHASE_RATE_TARGET_RANGE} (Section 9).")

    # --- VIP AOV floor / Bargain Hunter ceiling sanity check (Section 7) ---
    personas = assign_customer_personas(customer_lookup["customer_key"].tolist(), seed=PERSONA_ASSIGNMENT_SEED)
    df_persona = df.copy()
    df_persona["persona"] = df_persona["customer_key"].map(personas)
    avg_by_persona = df_persona.groupby("persona")["net_revenue"].mean()
    if "Loyal VIP" in avg_by_persona.index and "Bargain Hunter" in avg_by_persona.index:
        if avg_by_persona["Loyal VIP"] <= avg_by_persona["Bargain Hunter"]:
            raise ValueError(
                f"Loyal VIP average net_revenue (${avg_by_persona['Loyal VIP']:.2f}) is not "
                f"greater than Bargain Hunter's (${avg_by_persona['Bargain Hunter']:.2f}) -- "
                f"violates the documented VIP AOV floor / Bargain Hunter ceiling business rule."
            )


def write_csv(df: pd.DataFrame) -> Path:
    """Writes the already-validated DataFrame to data/generated/fact_orders.csv."""
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """
    Loads the validated DataFrame into Fact_Orders inside a single
    explicit transaction. Identical pattern to every prior phase's
    load_to_duckdb() (ED-004).
    """
    if not DB_PATH.exists():
        raise FileNotFoundError(f"{DB_PATH} does not exist. Apply sql/schema.sql to this path first.")

    expected_row_count = len(df)
    con = duckdb.connect(str(DB_PATH))
    transaction_open = False
    try:
        con.execute("BEGIN TRANSACTION")
        transaction_open = True

        con.execute("DELETE FROM Fact_Orders")
        con.execute(f"""
            INSERT INTO Fact_Orders ({", ".join(COLUMN_ORDER)})
            SELECT {", ".join(COLUMN_ORDER)} FROM df
        """)

        actual_row_count = con.execute("SELECT COUNT(*) FROM Fact_Orders").fetchone()[0]
        if actual_row_count != expected_row_count:
            con.execute("ROLLBACK")
            transaction_open = False
            raise ValueError(
                f"Row count mismatch after load: expected {expected_row_count}, got "
                f"{actual_row_count}. Transaction rolled back -- Fact_Orders is unchanged."
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
    print(f"Loaded {row_count} rows into Fact_Orders at {DB_PATH}")


if __name__ == "__main__":
    main()
