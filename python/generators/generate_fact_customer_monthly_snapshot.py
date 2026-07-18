"""
Phase 3.12 - Fact_Customer_Monthly_Snapshot generator.

The final fact table of Phase 3, and the only one that is PURELY DERIVED:
it contains no randomness whatsoever. Every value is a deterministic
function of already-persisted, already-validated facts, so determinism
here is stronger than anywhere else in the project -- not "same seed
produces the same output" (ED-006), but "same inputs necessarily produce
the same output." There is no seed to set because there is nothing to
sample.

Grain: one row per customer per calendar month, from the customer's
SIGNUP month through 2025-12 inclusive.

    Why signup month and not 2023-01: schema.sql's
    CHECK (customer_age_days >= 0) forbids pre-signup rows outright --
    the constraint is the design statement.

    Why signup month and not first-order month: 289 customers signed up
    and never purchased. Starting at first order would erase them and
    silently corrupt every cohort-retention denominator in Phase 6 --
    retention measures ACQUIRED customers who came back, not buyers who
    bought again. Their rows carry NULL recency and FALSE flags, which is
    precisely their true state.

Dependencies (all read live per ED-007, via db_utils per ED-011):
    Dim_Customer   -- row spine (customer_key, signup_date)
    Dim_Date       -- month-end date keys (never computed independently)
    Fact_Orders    -- order dates and net_revenue
    Fact_Returns   -- return dates and return_amount (see INVARIANT 1)

    Fact_Order_Lines is DELIBERATELY NOT read. Its revenue already rolls
    up to Fact_Orders.net_revenue, and Phase 3.10 proved the two
    reconcile exactly (0 failures across 26,299 orders). Re-deriving a
    number already in hand would only create a way for them to disagree.

=====================================================================
INVARIANT 1 -- REVENUE ATTRIBUTION BY RETURN DATE (never retroactive)
=====================================================================
    cumulative_net_revenue_to_date and rolling_12mo_net_revenue are
    reduced in the month the RETURN OCCURS (return_date), and NEVER
    retroactively in the month the original purchase occurred.

    A snapshot row is a statement about what was true AS OF that
    month-end. In March, a February order that had not yet been returned
    was, in fact, revenue. Restating February's snapshot when the refund
    lands in March would rewrite history and destroy the table's entire
    purpose as a periodic point-in-time record -- and would corrupt
    Phase 10's ML labels, which read consecutive rows as a time series
    and must never see the future leak backwards into the past.

    Consequences that follow from this invariant, and are asserted as
    such in validate_dataframe() rather than left to chance:
      1a. A customer's cumulative_net_revenue_to_date CAN decrease
          month-over-month (when a return lands). It is NOT monotonic.
          cumulative_ORDERS_to_date, by contrast, IS monotonic -- orders
          are never un-placed.
      1b. cumulative_net_revenue_to_date can never go NEGATIVE. Provable:
          every return_amount <= its line's net revenue, and a return
          always follows its order, so cumulative returns can never
          exceed cumulative order revenue.
      1c. rolling_12mo_net_revenue CAN legitimately go negative -- see
          INVARIANT 2.

=====================================================================
INVARIANT 2 -- BOUNDED, EXPLAINABLE NEGATIVE ROLLING REVENUE
=====================================================================
    rolling_12mo_net_revenue may be negative, but ONLY by the mechanism
    INVARIANT 1 creates: returns land 5-21 days after their order
    (Section 7), so an order can fall just OUTSIDE a trailing-12-month
    window while its own return falls just INSIDE it. The window then
    subtracts a refund whose matching purchase it never counted.

    schema.sql deliberately has no CHECK on this column, so the schema
    already permits it. But "negative is allowed" must not degrade into
    "negative is unchecked". Every negative row is therefore validated to
    be EXPLAINABLE by that exact mechanism -- the customer must genuinely
    have a return inside the window whose originating order is outside it
    -- and negatives must stay RARE and BOUNDED. A negative row that
    can't be explained this way is an arithmetic bug, and this validation
    is what separates the two.

=====================================================================
INVARIANT 3 -- TEMPORAL CONTINUITY OF THE ROW SPINE
=====================================================================
    For every customer, exactly one snapshot exists for every month from
    their signup month through 2025-12: no missing months, no duplicate
    months, no months outside that range. Verified per-customer against
    a recomputed expected month sequence -- independently of the total
    row count, since a total can be right while individual spines are
    wrong in offsetting ways.

Business-content decisions (documented here and in
docs/phase3_build_log.md, deliberately NOT in
docs/engineering_decision_log.md, which tracks code structure rather
than what a field means -- the same boundary drawn in Phase 3.7 and
reused in Phase 3.11):
    - Returns ARE subtracted from net revenue. docs/data_dictionary.md
      says only "total net revenue ever generated" (ambiguous), but
      docs/business_understanding.md defines the KPI unambiguously and up
      front: Net Revenue = SUM(order line revenue) - returns - discounts,
      stated there so the number stays consistent across SQL, Python and
      Power BI. Fact_Orders.net_revenue is gross-minus-discounts (returns
      are unknowable at order time); this snapshot is the first place
      returns CAN be netted. Not subtracting would make a High-Return
      Customer who bought $5k and returned $2k look like a $5k customer
      in Phase 6's CLV and Pareto analysis -- inverting the exact
      business tension Section 4 poses.
    - restocking_fee is NOT netted: it is a fee, not product revenue, and
      the KPI says "- returns", full stop.
    - refund_completed_flag is an operations lag indicator, not a
      revenue-recognition rule -- the reduction lands at return_date
      regardless of whether the refund has finished processing.

Engineering standards: ED-001/002 (repository layout, smoke vs
validation), ED-003 (explicit exceptions, never assert), ED-004
(transaction-wrapped idempotent load), ED-007 (live-parent lookups
validating business dependencies, never row counts), ED-011 (db_utils).
Deliberately NOT applicable: ED-006 (no randomness to seed), ED-008 (no
sampling, so tolerance bands would be WEAKER than warranted -- every
check here is exact), ED-009 (Section 7 requires the flags stay
persona-blind, or a churn model trained on them would just learn the
generation rules back), ED-010 (nothing is simulated). No new
engineering decision is required; see the Phase 3.12 entry in
docs/engineering_decision_log.md.

Run:
    python python/generators/generate_fact_customer_monthly_snapshot.py
"""

import sys
from bisect import bisect_left, bisect_right
from datetime import date, timedelta
from pathlib import Path

import duckdb
import pandas as pd

sys.path.append(str(Path(__file__).parent))
from db_utils import load_dimension_lookup

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "fact_customer_monthly_snapshot.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

HORIZON_START_YEAR = 2023
HORIZON_END = date(2025, 12, 31)

# --- Business rules, from docs/design_decisions.md #7 and the
#     schema.sql column comments. Flags are COMPUTED from these
#     thresholds, never sampled, and never persona-aware (Section 7). ---
ACTIVE_RECENCY_DAYS = 90          # is_active_flag: recency_days <= 90
CHURN_RISK_LOWER_EXCLUSIVE = 60   # churn_risk_flag: 60 < recency_days <= 90
REPEAT_CUSTOMER_MIN_ORDERS = 2    # is_repeat_customer_flag

ORDERS_WINDOW_SHORT_DAYS = 30
ORDERS_WINDOW_LONG_DAYS = 90
ROLLING_REVENUE_MONTHS = 12

# --- INVARIANT 2 bounds. Negative rolling revenue is expected but must
#     stay rare and bounded; anything beyond these is a bug, not an edge
#     case. Both are deliberately generous relative to the mechanism
#     (a single boundary order's return), so tripping one means something
#     is genuinely wrong rather than merely unusual. ---
MAX_NEGATIVE_ROLLING_ROW_SHARE = 0.01     # <1% of all snapshot rows
MAX_NEGATIVE_ROLLING_MAGNITUDE = 1000.00  # dollars

COLUMN_ORDER = [
    "snapshot_key", "customer_key", "snapshot_month_date_key", "customer_age_days",
    "months_since_first_purchase", "recency_days", "orders_last_30_days",
    "orders_last_90_days", "cumulative_orders_to_date", "cumulative_net_revenue_to_date",
    "rolling_12mo_net_revenue", "is_active_flag", "is_repeat_customer_flag", "churn_risk_flag",
]


def _month_index(d: date) -> int:
    """Months since 2023-01, so month arithmetic never touches day-of-month."""
    return (d.year - HORIZON_START_YEAR) * 12 + (d.month - 1)


def _first_day_of_month_index(idx: int) -> date:
    return date(HORIZON_START_YEAR + idx // 12, idx % 12 + 1, 1)


def _prefix_sums(values: list) -> list:
    """prefix[i] = sum of the first i values; prefix[0] = 0."""
    out = [0.0]
    total = 0.0
    for v in values:
        total += v
        out.append(total)
    return out


def _load_month_ends(db_path: Path) -> list:
    """
    The 36 month-end date keys, read from Dim_Date rather than computed --
    the snapshot's FK must point at rows that actually exist, so Dim_Date
    is the source of truth for what a month-end is (ED-007's principle
    applied to dates).
    """
    dim_date = load_dimension_lookup(db_path, "Dim_Date", ["date_key", "full_date"])
    dim_date["full_date"] = pd.to_datetime(dim_date["full_date"]).dt.date
    by_month = {}
    for row in dim_date.itertuples():
        idx = _month_index(row.full_date)
        if idx not in by_month or row.full_date > by_month[idx][1]:
            by_month[idx] = (int(row.date_key), row.full_date)

    expected_months = (_month_index(HORIZON_END) + 1)
    if len(by_month) != expected_months:
        raise ValueError(
            f"Dim_Date covers {len(by_month)} month(s); the snapshot horizon "
            f"({HORIZON_START_YEAR}-01 through {HORIZON_END:%Y-%m}) needs exactly "
            f"{expected_months}. Dim_Date has a gap -- the snapshot's month spine "
            f"cannot be built against it."
        )
    return [by_month[i] for i in range(expected_months)]


def build_dataframe(db_path: Path = DB_PATH) -> pd.DataFrame:
    """
    Builds every snapshot row. No seed parameter and no RNG: this is a
    pure function of the persisted facts (see the module docstring).

    Customers are processed in customer_key order and months in calendar
    order, so snapshot_key assignment is deterministic by construction.
    """
    month_ends = _load_month_ends(db_path)
    last_month_idx = len(month_ends) - 1

    customers = load_dimension_lookup(db_path, "Dim_Customer", ["customer_key", "signup_date"]).sort_values("customer_key")
    customers["signup_date"] = pd.to_datetime(customers["signup_date"]).dt.date

    orders = load_dimension_lookup(db_path, "Fact_Orders", ["customer_key", "order_date_key", "net_revenue"])
    orders["order_date"] = pd.to_datetime(orders["order_date_key"].astype(str), format="%Y%m%d").dt.date
    orders["net_revenue"] = orders["net_revenue"].astype(float)

    returns = load_dimension_lookup(db_path, "Fact_Returns", ["customer_key", "return_date_key", "return_amount"])
    returns["return_date"] = pd.to_datetime(returns["return_date_key"].astype(str), format="%Y%m%d").dt.date
    returns["return_amount"] = returns["return_amount"].astype(float)

    orphan_order_customers = set(orders["customer_key"]) - set(customers["customer_key"])
    if orphan_order_customers:
        raise ValueError(f"Fact_Orders references customer_key(s) absent from Dim_Customer: {sorted(orphan_order_customers)[:10]}")
    orphan_return_customers = set(returns["customer_key"]) - set(customers["customer_key"])
    if orphan_return_customers:
        raise ValueError(f"Fact_Returns references customer_key(s) absent from Dim_Customer: {sorted(orphan_return_customers)[:10]}")

    # Per-customer sorted event arrays + prefix sums: recency and every
    # windowed measure then reduce to two bisects, which keeps ~148k rows
    # x 36 months tractable without giving up the readable row-by-row
    # derivation the rest of the project uses.
    orders_by_customer = {}
    for customer_key, group in orders.sort_values(["customer_key", "order_date"]).groupby("customer_key"):
        dates = group["order_date"].tolist()
        orders_by_customer[customer_key] = (dates, _prefix_sums(group["net_revenue"].tolist()))

    returns_by_customer = {}
    for customer_key, group in returns.sort_values(["customer_key", "return_date"]).groupby("customer_key"):
        dates = group["return_date"].tolist()
        returns_by_customer[customer_key] = (dates, _prefix_sums(group["return_amount"].tolist()))

    empty = ([], [0.0])
    rows = []
    snapshot_key = 1

    for customer in customers.itertuples():
        customer_key = int(customer.customer_key)
        signup_date = customer.signup_date
        start_idx = _month_index(signup_date)

        order_dates, order_prefix = orders_by_customer.get(customer_key, empty)
        return_dates, return_prefix = returns_by_customer.get(customer_key, empty)
        first_order_month_idx = _month_index(order_dates[0]) if order_dates else None

        for month_idx in range(start_idx, last_month_idx + 1):
            month_end_key, month_end = month_ends[month_idx]

            orders_to_date = bisect_right(order_dates, month_end)
            returns_to_date = bisect_right(return_dates, month_end)

            # --- INVARIANT 1: returns reduce revenue in the month the
            #     RETURN happened. Both sides of this subtraction are cut
            #     at the same month_end using each event's OWN date, so a
            #     refund can never reach back into a month that closed
            #     before it occurred.
            cumulative_net_revenue = round(order_prefix[orders_to_date] - return_prefix[returns_to_date], 2)

            window_start = _first_day_of_month_index(max(0, month_idx - (ROLLING_REVENUE_MONTHS - 1)))
            orders_window_lo = bisect_left(order_dates, window_start)
            returns_window_lo = bisect_left(return_dates, window_start)
            rolling_net_revenue = round(
                (order_prefix[orders_to_date] - order_prefix[orders_window_lo])
                - (return_prefix[returns_to_date] - return_prefix[returns_window_lo]),
                2,
            )

            if orders_to_date > 0:
                last_order_date = order_dates[orders_to_date - 1]
                recency_days = (month_end - last_order_date).days
                months_since_first_purchase = month_idx - first_order_month_idx
            else:
                recency_days = None
                months_since_first_purchase = None

            orders_last_30 = orders_to_date - bisect_right(order_dates, month_end - timedelta(days=ORDERS_WINDOW_SHORT_DAYS))
            orders_last_90 = orders_to_date - bisect_right(order_dates, month_end - timedelta(days=ORDERS_WINDOW_LONG_DAYS))

            # Flags: computed from the documented thresholds, persona-blind,
            # FALSE (never NULL) for a customer who has never ordered.
            is_active = recency_days is not None and recency_days <= ACTIVE_RECENCY_DAYS
            is_repeat = orders_to_date >= REPEAT_CUSTOMER_MIN_ORDERS
            churn_risk = recency_days is not None and CHURN_RISK_LOWER_EXCLUSIVE < recency_days <= ACTIVE_RECENCY_DAYS

            rows.append({
                "snapshot_key": snapshot_key,
                "customer_key": customer_key,
                "snapshot_month_date_key": month_end_key,
                "customer_age_days": (month_end - signup_date).days,
                "months_since_first_purchase": months_since_first_purchase,
                "recency_days": recency_days,
                "orders_last_30_days": orders_last_30,
                "orders_last_90_days": orders_last_90,
                "cumulative_orders_to_date": orders_to_date,
                "cumulative_net_revenue_to_date": cumulative_net_revenue,
                "rolling_12mo_net_revenue": rolling_net_revenue,
                "is_active_flag": is_active,
                "is_repeat_customer_flag": is_repeat,
                "churn_risk_flag": churn_risk,
            })
            snapshot_key += 1

    df = pd.DataFrame(rows, columns=COLUMN_ORDER)
    # Nullable integer dtype: keeps real NULLs for the two
    # nullable-until-first-purchase columns without pandas coercing the
    # populated values to floats.
    df["months_since_first_purchase"] = df["months_since_first_purchase"].astype("Int64")
    df["recency_days"] = df["recency_days"].astype("Int64")
    return df


def validate_dataframe(df: pd.DataFrame, db_path: Path = DB_PATH) -> None:
    """
    The strongest deterministic validation suite in the project, as befits
    the final fact table: nothing here is sampled, so every check is EXACT.
    Tolerance bands (ED-008) are deliberately absent -- they would be
    weaker than the data warrants.

    Explicit exceptions only, never assert (ED-003).
    """
    if df.empty:
        raise ValueError("Fact_Customer_Monthly_Snapshot DataFrame is empty.")

    n = len(df)

    # --- Key integrity -------------------------------------------------
    if df["snapshot_key"].isnull().any() or not df["snapshot_key"].is_unique:
        raise ValueError("snapshot_key must be non-null and unique.")
    if set(df["snapshot_key"]) != set(range(1, n + 1)):
        raise ValueError("snapshot_key must be a contiguous sequence starting at 1.")
    if df.duplicated(["customer_key", "snapshot_month_date_key"]).any():
        dupes = df[df.duplicated(["customer_key", "snapshot_month_date_key"], keep=False)].head(4)
        raise ValueError(
            f"UNIQUE (customer_key, snapshot_month_date_key) violated -- the grain is one row "
            f"per customer per month:\n{dupes.to_string(index=False)}"
        )

    # --- NOT NULL discipline. Only two columns are nullable, and they are
    #     nullable for exactly one documented reason. ---
    non_nullable = [c for c in COLUMN_ORDER if c not in ("months_since_first_purchase", "recency_days")]
    for col in non_nullable:
        if df[col].isnull().any():
            raise ValueError(f"Column '{col}' contains nulls, violating NOT NULL in schema.sql.")

    # --- FK integrity against live parents (ED-007) ---------------------
    customers = load_dimension_lookup(db_path, "Dim_Customer", ["customer_key", "signup_date"])
    customers["signup_date"] = pd.to_datetime(customers["signup_date"]).dt.date
    if set(df["customer_key"]) - set(customers["customer_key"]):
        raise ValueError("customer_key value(s) missing from Dim_Customer.")
    if set(customers["customer_key"]) - set(df["customer_key"]):
        missing = sorted(set(customers["customer_key"]) - set(df["customer_key"]))[:10]
        raise ValueError(f"Every customer must have a snapshot series; missing customer_key(s): {missing}")

    month_ends = _load_month_ends(db_path)
    valid_month_end_keys = {k for k, _ in month_ends}
    bad_months = set(df["snapshot_month_date_key"]) - valid_month_end_keys
    if bad_months:
        raise ValueError(
            f"snapshot_month_date_key value(s) are not month-end dates in Dim_Date: {sorted(bad_months)[:10]}"
        )

    # =================================================================
    # INVARIANT 3 -- TEMPORAL CONTINUITY, verified per customer against a
    # recomputed expected month sequence. Deliberately independent of the
    # total row count: a correct total can hide two customers with
    # offsetting errors (one short a month, one with an extra).
    # =================================================================
    signup_by_customer = dict(zip(customers["customer_key"], customers["signup_date"]))
    last_month_idx = _month_index(HORIZON_END)
    key_to_month_idx = {k: _month_index(d) for k, d in month_ends}

    work = df[["customer_key", "snapshot_month_date_key"]].copy()
    work["month_idx"] = work["snapshot_month_date_key"].map(key_to_month_idx)
    continuity_failures = []
    for customer_key, group in work.groupby("customer_key"):
        expected = set(range(_month_index(signup_by_customer[customer_key]), last_month_idx + 1))
        actual = set(group["month_idx"])
        if actual != expected:
            continuity_failures.append((
                int(customer_key),
                sorted(expected - actual)[:5],   # missing months
                sorted(actual - expected)[:5],   # unexpected months
            ))
            if len(continuity_failures) >= 5:
                break
    if continuity_failures:
        raise ValueError(
            f"INVARIANT 3 violated -- temporal continuity broken for at least "
            f"{len(continuity_failures)} customer(s). (customer_key, missing_month_idx, "
            f"unexpected_month_idx): {continuity_failures}"
        )

    expected_total = sum(last_month_idx - _month_index(s) + 1 for s in signup_by_customer.values())
    if n != expected_total:
        raise ValueError(
            f"Row count {n} != the exactly-computable expected {expected_total} "
            f"(sum over customers of months from signup month through {HORIZON_END:%Y-%m})."
        )

    # --- customer_age_days: non-negative, and strictly increasing within
    #     a customer's series ---
    if (df["customer_age_days"] < 0).any():
        raise ValueError("customer_age_days contains negative values, violating schema.sql's CHECK constraint.")
    ordered = df.sort_values(["customer_key", "snapshot_month_date_key"])
    age_deltas = ordered.groupby("customer_key")["customer_age_days"].diff().dropna()
    if (age_deltas <= 0).any():
        raise ValueError("customer_age_days must strictly increase month-over-month within a customer.")

    # --- NULL discipline, both directions: recency and
    #     months_since_first_purchase are NULL IFF the customer has no
    #     orders yet as of that month ---
    no_orders = df["cumulative_orders_to_date"] == 0
    if df.loc[no_orders, "recency_days"].notna().any():
        raise ValueError("recency_days must be NULL for a customer-month with zero orders to date.")
    if df.loc[~no_orders, "recency_days"].isna().any():
        raise ValueError("recency_days must be populated once a customer has at least one order.")
    if df.loc[no_orders, "months_since_first_purchase"].notna().any():
        raise ValueError("months_since_first_purchase must be NULL for a customer-month with zero orders to date.")
    if df.loc[~no_orders, "months_since_first_purchase"].isna().any():
        raise ValueError("months_since_first_purchase must be populated once a customer has at least one order.")
    if (df["months_since_first_purchase"].dropna() < 0).any():
        raise ValueError("months_since_first_purchase can never be negative.")
    if (df["recency_days"].dropna() < 0).any():
        raise ValueError("recency_days can never be negative -- an order cannot post-date its own snapshot month.")

    # --- Window containment ---------------------------------------------
    if not (df["orders_last_30_days"] <= df["orders_last_90_days"]).all():
        raise ValueError("orders_last_30_days must never exceed orders_last_90_days.")
    if not (df["orders_last_90_days"] <= df["cumulative_orders_to_date"]).all():
        raise ValueError("orders_last_90_days must never exceed cumulative_orders_to_date.")

    # --- INVARIANT 1a: cumulative ORDERS are monotonic (orders are never
    #     un-placed). Cumulative REVENUE is deliberately NOT checked for
    #     monotonicity -- a return legitimately reduces it in the month the
    #     return occurs, which is the whole point of INVARIANT 1. ---
    order_deltas = ordered.groupby("customer_key")["cumulative_orders_to_date"].diff().dropna()
    if (order_deltas < 0).any():
        raise ValueError("cumulative_orders_to_date must never decrease -- orders are never un-placed.")

    # --- INVARIANT 1b: cumulative net revenue can never go negative ------
    if (df["cumulative_net_revenue_to_date"] < 0).any():
        worst = df.loc[df["cumulative_net_revenue_to_date"].idxmin()]
        raise ValueError(
            f"INVARIANT 1b violated -- cumulative_net_revenue_to_date went negative "
            f"(customer_key {int(worst['customer_key'])}, month {int(worst['snapshot_month_date_key'])}, "
            f"${worst['cumulative_net_revenue_to_date']:.2f}). Every return_amount is <= its line's net "
            f"revenue and always follows its order, so cumulative returns cannot exceed cumulative order "
            f"revenue -- a negative here is an arithmetic bug, not an edge case."
        )

    # =================================================================
    # INVARIANT 2 -- negative rolling revenue must be EXPLAINABLE, RARE
    # and BOUNDED. Every negative row is checked against the one mechanism
    # that can legitimately produce it; anything else is a bug.
    # =================================================================
    negative = df[df["rolling_12mo_net_revenue"] < 0]
    if not negative.empty:
        share = len(negative) / n
        if share > MAX_NEGATIVE_ROLLING_ROW_SHARE:
            raise ValueError(
                f"INVARIANT 2 violated -- {len(negative)} rows ({share:.2%}) have negative "
                f"rolling_12mo_net_revenue, above the {MAX_NEGATIVE_ROLLING_ROW_SHARE:.0%} ceiling. "
                f"The boundary mechanism (a return inside the window whose order is outside it) is rare "
                f"by construction; this many negatives indicates a windowing bug."
            )
        worst_magnitude = float(-negative["rolling_12mo_net_revenue"].min())
        if worst_magnitude > MAX_NEGATIVE_ROLLING_MAGNITUDE:
            raise ValueError(
                f"INVARIANT 2 violated -- the most negative rolling_12mo_net_revenue is "
                f"${-worst_magnitude:.2f}, beyond the ${MAX_NEGATIVE_ROLLING_MAGNITUDE:.2f} plausible "
                f"bound for a single boundary order's return."
            )

        # Every negative row must be explainable by the documented
        # mechanism: a return inside the window whose originating order
        # falls outside it. This is what distinguishes the intended edge
        # case from an arithmetic error.
        returns = load_dimension_lookup(db_path, "Fact_Returns", ["customer_key", "order_key", "return_date_key", "return_amount"])
        orders = load_dimension_lookup(db_path, "Fact_Orders", ["order_key", "order_date_key"])
        returns = returns.merge(orders, on="order_key", how="left")
        if returns["order_date_key"].isna().any():
            raise ValueError("Fact_Returns contains order_key(s) with no matching Fact_Orders row.")
        returns["return_date"] = pd.to_datetime(returns["return_date_key"].astype(str), format="%Y%m%d").dt.date
        returns["order_date"] = pd.to_datetime(returns["order_date_key"].astype(str), format="%Y%m%d").dt.date

        returns_by_customer = {k: g for k, g in returns.groupby("customer_key")}
        month_end_by_key = {k: d for k, d in month_ends}
        unexplained = []
        for row in negative.itertuples():
            month_end = month_end_by_key[row.snapshot_month_date_key]
            window_start = _first_day_of_month_index(
                max(0, _month_index(month_end) - (ROLLING_REVENUE_MONTHS - 1))
            )
            g = returns_by_customer.get(row.customer_key)
            explained = False
            if g is not None:
                boundary = g[
                    (g["return_date"] >= window_start) & (g["return_date"] <= month_end)
                    & (g["order_date"] < window_start)
                ]
                explained = not boundary.empty
            if not explained:
                unexplained.append((int(row.customer_key), int(row.snapshot_month_date_key), float(row.rolling_12mo_net_revenue)))
                if len(unexplained) >= 5:
                    break
        if unexplained:
            raise ValueError(
                f"INVARIANT 2 violated -- {len(unexplained)}+ negative rolling_12mo_net_revenue row(s) "
                f"are NOT explained by the documented boundary mechanism (a return inside the rolling "
                f"window whose originating order falls outside it). These are arithmetic bugs, not the "
                f"intended edge case. (customer_key, month, value): {unexplained}"
            )

    # --- Flags: re-derived from the documented thresholds, exactly ------
    expected_active = df["recency_days"].notna() & (df["recency_days"] <= ACTIVE_RECENCY_DAYS)
    if not df["is_active_flag"].equals(expected_active.astype(bool)):
        raise ValueError(f"is_active_flag does not equal (recency_days <= {ACTIVE_RECENCY_DAYS}) on every row.")
    expected_repeat = df["cumulative_orders_to_date"] >= REPEAT_CUSTOMER_MIN_ORDERS
    if not df["is_repeat_customer_flag"].equals(expected_repeat.astype(bool)):
        raise ValueError(f"is_repeat_customer_flag does not equal (cumulative_orders_to_date >= {REPEAT_CUSTOMER_MIN_ORDERS}) on every row.")
    expected_churn = (
        df["recency_days"].notna()
        & (df["recency_days"] > CHURN_RISK_LOWER_EXCLUSIVE)
        & (df["recency_days"] <= ACTIVE_RECENCY_DAYS)
    )
    if not df["churn_risk_flag"].equals(expected_churn.astype(bool)):
        raise ValueError(
            f"churn_risk_flag does not equal ({CHURN_RISK_LOWER_EXCLUSIVE} < recency_days <= "
            f"{ACTIVE_RECENCY_DAYS}) on every row."
        )
    # The churn-risk band sits inside the active band by definition.
    if (df["churn_risk_flag"] & ~df["is_active_flag"]).any():
        raise ValueError("churn_risk_flag implies is_active_flag -- the 61-90 day band is a subset of the <=90 day band.")

    # --- Tie-out to the source facts, exactly ---------------------------
    final_month_key = month_ends[-1][0]
    final = df[df["snapshot_month_date_key"] == final_month_key]
    orders_all = load_dimension_lookup(db_path, "Fact_Orders", ["order_key", "net_revenue"])
    returns_all = load_dimension_lookup(db_path, "Fact_Returns", ["return_key", "return_amount"])

    if int(final["cumulative_orders_to_date"].sum()) != len(orders_all):
        raise ValueError(
            f"Final-month cumulative_orders_to_date sums to {int(final['cumulative_orders_to_date'].sum())}, "
            f"but Fact_Orders holds {len(orders_all)} orders. Every order must be counted exactly once."
        )
    expected_final_revenue = round(float(orders_all["net_revenue"].astype(float).sum()) - float(returns_all["return_amount"].astype(float).sum()), 2)
    actual_final_revenue = round(float(final["cumulative_net_revenue_to_date"].sum()), 2)
    if abs(actual_final_revenue - expected_final_revenue) > 0.05:
        raise ValueError(
            f"Final-month cumulative_net_revenue_to_date sums to ${actual_final_revenue:,.2f}, but "
            f"SUM(Fact_Orders.net_revenue) - SUM(Fact_Returns.return_amount) = ${expected_final_revenue:,.2f}. "
            f"Revenue is leaking or being double-counted."
        )

    # --- The 289 never-purchasers must look exactly like never-purchasers ---
    never_purchased_customers = set(customers["customer_key"]) - set(
        load_dimension_lookup(db_path, "Fact_Orders", ["customer_key"])["customer_key"]
    )
    if never_purchased_customers:
        np_rows = df[df["customer_key"].isin(never_purchased_customers)]
        if (np_rows["cumulative_orders_to_date"] != 0).any():
            raise ValueError("A customer with no orders in Fact_Orders has a nonzero cumulative_orders_to_date.")
        if (np_rows["cumulative_net_revenue_to_date"] != 0).any():
            raise ValueError("A customer with no orders has nonzero cumulative_net_revenue_to_date.")
        if np_rows["recency_days"].notna().any():
            raise ValueError("A customer with no orders has a non-NULL recency_days.")
        if np_rows[["is_active_flag", "is_repeat_customer_flag", "churn_risk_flag"]].any().any():
            raise ValueError("A customer with no orders has a TRUE flag; all three must be FALSE.")


def write_csv(df: pd.DataFrame) -> Path:
    """Durable, human-inspectable artifact, independent of the DB load."""
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """Transaction-wrapped idempotent load (ED-004), identical pattern to every prior phase."""
    if not DB_PATH.exists():
        raise FileNotFoundError(f"{DB_PATH} does not exist. Apply sql/schema.sql to this path first.")

    expected = len(df)
    con = duckdb.connect(str(DB_PATH))
    txn = False
    try:
        con.execute("BEGIN TRANSACTION"); txn = True
        con.execute("DELETE FROM Fact_Customer_Monthly_Snapshot")
        con.execute(
            f"INSERT INTO Fact_Customer_Monthly_Snapshot ({', '.join(COLUMN_ORDER)}) "
            f"SELECT {', '.join(COLUMN_ORDER)} FROM df"
        )
        actual = con.execute("SELECT COUNT(*) FROM Fact_Customer_Monthly_Snapshot").fetchone()[0]
        if actual != expected:
            con.execute("ROLLBACK"); txn = False
            raise ValueError(
                f"Row count mismatch after load: expected {expected}, got {actual}. Rolled back -- "
                f"Fact_Customer_Monthly_Snapshot is unchanged."
            )
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
    print(f"Loaded {load_to_duckdb(df)} rows into Fact_Customer_Monthly_Snapshot at {DB_PATH}")


if __name__ == "__main__":
    main()
