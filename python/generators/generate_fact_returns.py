"""
Phase 3.11 - Fact_Returns generator.

Grain: one row per returned line item (at most one return per
order_line_key -- a partial return of 2-of-3 units is one row with
return_quantity=2, not two rows).

ARCHITECTURE NOTE -- why this generator does NOT replay
order_generation_core.simulate_orders_and_lines():
    Fact_Order_Lines replayed the shared simulation because headers and
    lines are two views of ONE simulated object -- reconciliation
    (SUM(net_line_revenue) == header net_revenue) is only guaranteed if
    both come from the same pass (ED-010). Returns are categorically
    different: a return is a downstream event ABOUT a line that already
    exists, already persisted, already validated. So this generator reads
    Fact_Order_Lines from the live database (ED-007's live-parent
    pattern, via db_utils.load_dimension_lookup per ED-011) and joins
    personas via order_generation_core.assign_customer_personas()
    (ED-009).

    Three reasons that's correct rather than convenient:
      1. It cannot perturb the frozen, byte-identical-verified order
         simulation -- adding return draws to that shared RNG stream
         would risk exactly what Phase 3.10 proved stable.
      2. The live table is the authoritative record of what was actually
         sold -- the same argument ED-007 already made for FK resolution.
      3. Returns become independently regenerable without regenerating
         orders.

    No new engineering decision is required: this is ED-007 + ED-009 +
    ED-011 composed. Return logic stays in this generator rather than a
    new shared module because there is no second consumer --
    Fact_Customer_Monthly_Snapshot needs order-derived state, not return
    logic -- and ED-005's own threshold says don't extract until there is.

RETURN PROBABILITY MODEL (personas x product characteristics, never noise):
    P(return) = CATEGORY_BASE[category] x PERSONA_MULTIPLIER[persona]

    Two independent documented target sets must hold simultaneously:
      - docs/data_generation_strategy.md Section 9 (category view):
        blended 15-20%, Footwear 25-30%, Accessories 8-10%
      - Section 4 (persona view): VIP 8-10%, Fashion Enthusiast 18-22%,
        Bargain Hunter 15-18%, Seasonal Shopper ~12%, One-Time Buyer
        ~20%, High-Return Customer 35-45%

    CATEGORY_BASE holds the Section 9 blended-across-persona rates.
    PERSONA_MULTIPLIER is each persona's tendency divided by the blended
    tendency (~0.175), so the multipliers average ~1.0 and neither target
    set overrides the other.

    Section 7's "VIP return ceiling" rule -- VIP return probability is
    always the LOWEST of any persona for a given category, regardless of
    that category's base rate -- holds BY CONSTRUCTION: VIP's multiplier
    is strictly the smallest, and scaling every category by a common
    factor preserves that ordering. validate_dataframe() checks it anyway.

BUSINESS-CONTENT DECISIONS (undocumented in the source specs, so decided
and documented here rather than silently -- same treatment as Phase 3.7's
Late Delivery boolean, and deliberately NOT engineering_decision_log.md
entries, which track code structure, not what a field means):
    - restocking_fee: charged only on CHANGED_MIND returns (customer
      preference, not a business failure), at 10% of return_amount.
      Controllable-fault reasons (wrong size, defect, bad listing, late
      delivery) and the unclassified OTHER bucket carry no fee -- charging
      a customer for the business's own error would be a strange policy to
      encode into a warehouse other stakeholders will read.
    - refund_completed_flag: TRUE once REFUND_LAG_DAYS have elapsed since
      the return date, with ~3% of otherwise-eligible refunds still
      pending (real processing exceptions). This is exactly the
      request-vs-completed operational distinction the v1.1 schema
      changelog added the field for.

Run:
    python python/generators/generate_fact_returns.py
"""

import sys
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from random import Random

import duckdb
import pandas as pd

sys.path.append(str(Path(__file__).parent))
from db_utils import load_dimension_lookup
from order_generation_core import assign_customer_personas, PERSONA_POPULATION

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "fact_returns.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

RETURN_SEED = 42                # this generator's own RNG stream (ED-006 pattern)
PERSONA_ASSIGNMENT_SEED = 42    # must match the fact-order generators (ED-009)

HORIZON_END = date(2025, 12, 31)

# --- Section 9 category return rates (blended across personas) ---
# Footwear and Accessories are documented explicitly; the three apparel
# categories are interpolated between them on sizing risk: Womenswear
# highest of the three (fit variance), Outerwear next, Menswear lowest.
# Two-step calibration, both steps forced by the documents rather than chosen:
#
# STEP 1 -- the apparel rates. Only Footwear (25-30%) and Accessories
# (8-10%) are pinned by Section 9; the three apparel rates are specified
# nowhere. Accessories are ~48% of units (a Phase 3.9 AOV calibration) and
# Footwear ~8%, so the two pinned categories contribute only ~6.4 points of
# the blended. The apparel categories carry ~45% of units, so they must
# average ~24% for Section 9's pinned 15-20% blended to be reachable at
# all. Targeting Womenswear 26% / Outerwear 22% / Menswear 20% (ordered by
# fit variance) yields a 17.1% blended. That is also simply the more
# realistic figure -- real DTC womenswear returns run 25-40%; the first
# implementation interpolated 14-18% between the two pinned endpoints,
# produced a 13.8% blended, and was caught by validate_dataframe().
#
# STEP 2 -- deflating for persona loading. base x multiplier does NOT make
# a category realize its base rate, because persona category preferences
# are not uniform: Section 4 says High-Return Customers skew Footwear
# (Phase 3.9 encodes a 3.5x tilt), so Footwear's buyers carry a 1.25x
# units-weighted return multiplier, while Outerwear's Seasonal-Shopper
# skew carries only 0.81x. A base of 0.275 therefore realized 34.0%
# Footwear -- again caught by validation. Each base below is
# desired_realized / M_cat, where M_cat is the measured units-weighted
# persona multiplier for that category. The deliberate consequence: these
# constants are NOT the realized rates and should not be read as such --
# the realized rates are the desired_realized values in the comments, and
# validate_dataframe() checks those, not these.
CATEGORY_BASE_RETURN_RATE = {
    "Footwear": 0.2202,      # -> realizes ~27.5% (Section 9: 25-30%, pinned); M_cat 1.249
    "Womenswear": 0.2398,    # -> realizes ~26%; M_cat 1.084
    "Outerwear": 0.2701,     # -> realizes ~22%; M_cat 0.815
    "Menswear": 0.2184,      # -> realizes ~20%; M_cat 0.916
    "Accessories": 0.0975,   # -> realizes ~9% (Section 9: 8-10%, pinned); M_cat 0.923
}

# --- Section 4 persona return tendencies (midpoints) ---
PERSONA_RETURN_TENDENCY = {
    "Loyal VIP": 0.09,
    "Fashion Enthusiast": 0.20,
    "Bargain Hunter": 0.165,
    "Seasonal Shopper": 0.12,
    "One-Time Buyer": 0.20,
    "High-Return Customer": 0.40,
}

# Blended tendency, population-weighted -- derived, never hardcoded, so it
# can't drift from PERSONA_POPULATION or PERSONA_RETURN_TENDENCY.
BLENDED_PERSONA_TENDENCY = sum(
    PERSONA_POPULATION[p] * PERSONA_RETURN_TENDENCY[p] for p in PERSONA_RETURN_TENDENCY
)
PERSONA_RETURN_MULTIPLIER = {
    p: PERSONA_RETURN_TENDENCY[p] / BLENDED_PERSONA_TENDENCY for p in PERSONA_RETURN_TENDENCY
}

MIN_RETURN_PROBABILITY = 0.01
MAX_RETURN_PROBABILITY = 0.75

# --- Section 7: "every return's date is 5-21 days after its originating
#     order's date -- never same-day, never past 30 days" ---
RETURN_LAG_DAYS_RANGE = (5, 21)

# --- Partial returns (design_decisions.md #4: "a customer can return 2 of
#     3 units"). Most returns are the whole line; partials only arise when
#     the line had >1 unit in the first place. ---
FULL_LINE_RETURN_PROBABILITY = 0.85

# --- Reason mix by category. Sizing-driven categories skew Wrong Size;
#     Accessories have no sizing dimension at all (Phase 3.6 leaves size
#     NULL for them), so they skew Changed Mind / Not as Described. ---
REASON_WEIGHTS_BY_CATEGORY = {
    "Footwear":    {"WRONG_SIZE": 0.55, "CHANGED_MIND": 0.15, "DEFECTIVE_QUALITY": 0.12, "NOT_AS_DESCRIBED": 0.10, "LATE_DELIVERY": 0.05, "OTHER": 0.03},
    "Womenswear":  {"WRONG_SIZE": 0.45, "CHANGED_MIND": 0.20, "DEFECTIVE_QUALITY": 0.10, "NOT_AS_DESCRIBED": 0.15, "LATE_DELIVERY": 0.06, "OTHER": 0.04},
    "Menswear":    {"WRONG_SIZE": 0.45, "CHANGED_MIND": 0.20, "DEFECTIVE_QUALITY": 0.10, "NOT_AS_DESCRIBED": 0.15, "LATE_DELIVERY": 0.06, "OTHER": 0.04},
    "Outerwear":   {"WRONG_SIZE": 0.35, "CHANGED_MIND": 0.22, "DEFECTIVE_QUALITY": 0.13, "NOT_AS_DESCRIBED": 0.18, "LATE_DELIVERY": 0.08, "OTHER": 0.04},
    "Accessories": {"WRONG_SIZE": 0.10, "CHANGED_MIND": 0.35, "DEFECTIVE_QUALITY": 0.15, "NOT_AS_DESCRIBED": 0.28, "LATE_DELIVERY": 0.08, "OTHER": 0.04},
}

RESTOCKING_FEE_REASON = "CHANGED_MIND"
RESTOCKING_FEE_PCT = 0.10
REFUND_LAG_DAYS = 5
REFUND_PENDING_EXCEPTION_RATE = 0.03

# --- Section 9 validation targets (unit-weighted, per business_understanding.md:
#     "Return Rate = Units Returned / Units Sold") ---
BLENDED_RETURN_RATE_TARGET = (0.15, 0.20)
FOOTWEAR_RETURN_RATE_TARGET = (0.25, 0.30)
ACCESSORIES_RETURN_RATE_TARGET = (0.08, 0.10)
VALIDATION_TOLERANCE = 0.05  # multiplicative, same convention as Phase 3.9

COLUMN_ORDER = [
    "return_key", "order_key", "order_line_key", "customer_key", "product_key",
    "return_date_key", "return_reason_key", "return_quantity", "return_amount",
    "restocking_fee", "refund_completed_flag",
]


def _round_money(value: float) -> float:
    """
    Rounds a money amount to cents, HALF-UP, via Decimal.

    Not cosmetic: a partial return of a $58.51 line is exactly $29.255,
    and Python's round() (banker's rounding) and pandas' .round() resolve
    that tie in opposite directions -- build_dataframe() and
    validate_dataframe() disagreed on 2 of ~5,900 rows on this
    generator's first execution, which validation caught. Routing every
    money calculation through one explicit half-up rule (the conventional
    financial convention) makes the result deterministic and makes build
    and validate agree by construction rather than by luck. Same spirit
    as Phase 3.10's deterministic discount-remainder allocation.
    """
    return float(Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def _return_probability(category: str, persona: str) -> float:
    """
    P(return) = category base x persona multiplier, clipped.

    Clipping is deliberately wide enough never to bind for any real
    combination (max is High-Return x Footwear = 0.275 x 2.29 = 0.63 <
    0.75) -- it exists as a guard against a future edit to either table
    producing a nonsense probability, not as an active part of the model.
    Because it never binds, the Section 7 VIP-return-ceiling ordering is
    preserved exactly.
    """
    raw = CATEGORY_BASE_RETURN_RATE[category] * PERSONA_RETURN_MULTIPLIER[persona]
    return min(max(raw, MIN_RETURN_PROBABILITY), MAX_RETURN_PROBABILITY)


def build_dataframe(seed: int = RETURN_SEED, persona_seed: int = PERSONA_ASSIGNMENT_SEED, db_path: Path = DB_PATH) -> pd.DataFrame:
    """
    Reads the live Fact_Order_Lines (ED-007) and emits at most one return
    per line, driven by persona x category probability.

    Lines are processed in order_line_key order so the single RNG stream
    is consumed identically on every run -- the same determinism
    discipline the order simulation uses.
    """
    rng = Random(seed)

    lines = load_dimension_lookup(
        db_path, "Fact_Order_Lines",
        ["order_line_key", "order_key", "customer_key", "product_key",
         "order_date_key", "quantity", "net_line_revenue"],
    ).sort_values("order_line_key")

    products = load_dimension_lookup(db_path, "Dim_Product", ["product_key", "category"])
    product_category = dict(zip(products["product_key"], products["category"]))
    missing_categories = set(CATEGORY_BASE_RETURN_RATE) - set(product_category.values())
    if missing_categories:
        raise ValueError(
            f"Dim_Product is missing required categor(y/ies) referenced in "
            f"CATEGORY_BASE_RETURN_RATE: {sorted(missing_categories)}."
        )

    reasons = load_dimension_lookup(db_path, "Dim_Return_Reason", ["return_reason_key", "reason_code"])
    reason_code_to_key = dict(zip(reasons["reason_code"], reasons["return_reason_key"]))
    required_reason_codes = {code for w in REASON_WEIGHTS_BY_CATEGORY.values() for code in w}
    missing_reasons = required_reason_codes - set(reason_code_to_key)
    if missing_reasons:
        raise ValueError(
            f"Dim_Return_Reason is missing required reason code(s): "
            f"{sorted(missing_reasons)}. Found: {sorted(reason_code_to_key)}."
        )

    dim_dates = load_dimension_lookup(db_path, "Dim_Date", ["date_key"])
    valid_date_keys = set(dim_dates["date_key"])

    customers = load_dimension_lookup(db_path, "Dim_Customer", ["customer_key"])
    personas = assign_customer_personas(customers["customer_key"].tolist(), seed=persona_seed)

    rows = []
    return_key = 1
    for line in lines.itertuples():
        category = product_category[line.product_key]
        persona = personas[line.customer_key]

        if rng.random() >= _return_probability(category, persona):
            continue

        order_date = pd.Timestamp(str(line.order_date_key)).date()
        lag_days = rng.randint(*RETURN_LAG_DAYS_RANGE)
        return_date = order_date + timedelta(days=lag_days)
        # A return dated past the observation window simply hasn't happened
        # yet as of the data's horizon -- a real "bought late in December,
        # return not yet recorded" state, and the only way return_date_key
        # can honour its Dim_Date FK. Not emitting the row is correct;
        # clamping the date would fabricate a return that didn't occur.
        if return_date > HORIZON_END:
            continue
        return_date_key = int(return_date.strftime("%Y%m%d"))
        if return_date_key not in valid_date_keys:
            raise ValueError(
                f"Computed return_date_key {return_date_key} has no matching Dim_Date "
                f"row despite falling within the horizon -- Dim_Date has a gap."
            )

        if line.quantity > 1 and rng.random() >= FULL_LINE_RETURN_PROBABILITY:
            return_quantity = rng.randint(1, line.quantity - 1)
        else:
            return_quantity = line.quantity

        # Proportional to the units actually returned: ties out to the line
        # exactly on a full return, and can never exceed net_line_revenue.
        return_amount = _round_money(float(line.net_line_revenue) * return_quantity / line.quantity)

        weights = REASON_WEIGHTS_BY_CATEGORY[category]
        reason_code = rng.choices(list(weights.keys()), weights=list(weights.values()), k=1)[0]

        restocking_fee = _round_money(return_amount * RESTOCKING_FEE_PCT) if reason_code == RESTOCKING_FEE_REASON else 0.0

        refund_eligible = (HORIZON_END - return_date).days >= REFUND_LAG_DAYS
        refund_completed = refund_eligible and (rng.random() >= REFUND_PENDING_EXCEPTION_RATE)

        rows.append({
            "return_key": return_key,
            "order_key": int(line.order_key),
            "order_line_key": int(line.order_line_key),
            "customer_key": int(line.customer_key),
            "product_key": int(line.product_key),
            "return_date_key": return_date_key,
            "return_reason_key": int(reason_code_to_key[reason_code]),
            "return_quantity": int(return_quantity),
            "return_amount": return_amount,
            "restocking_fee": restocking_fee,
            "refund_completed_flag": bool(refund_completed),
        })
        return_key += 1

    return pd.DataFrame(rows, columns=COLUMN_ORDER)


def validate_dataframe(df: pd.DataFrame, persona_seed: int = PERSONA_ASSIGNMENT_SEED, db_path: Path = DB_PATH) -> None:
    """
    Key integrity, live-parent FK integrity (ED-007), Section 7's exact
    business rules, and Section 9's unit-weighted return-rate targets --
    tolerance-based where genuinely sampled (ED-008), exact where the rule
    is deterministic. Explicit exceptions only, never assert (ED-003).
    """
    if df.empty:
        raise ValueError("Fact_Returns DataFrame is empty -- expected several thousand rows.")

    n = len(df)
    if df["return_key"].isnull().any() or not df["return_key"].is_unique:
        raise ValueError("return_key must be non-null and unique.")
    if set(df["return_key"]) != set(range(1, n + 1)):
        raise ValueError("return_key must be a contiguous sequence starting at 1.")

    for col in COLUMN_ORDER:
        if df[col].isnull().any():
            raise ValueError(f"Column '{col}' contains nulls, violating NOT NULL in schema.sql.")

    # Grain: at most one return row per order line.
    if not df["order_line_key"].is_unique:
        dupes = df.loc[df["order_line_key"].duplicated(), "order_line_key"].tolist()[:10]
        raise ValueError(f"order_line_key must be unique -- Fact_Returns' grain is one row per returned line: {dupes}")

    if (df["return_quantity"] <= 0).any():
        raise ValueError("return_quantity must be > 0, violating schema.sql's CHECK constraint.")
    if (df["return_amount"] < 0).any() or (df["restocking_fee"] < 0).any():
        raise ValueError("return_amount / restocking_fee contain negative values, violating schema CHECK constraints.")

    # --- FK integrity against live parents (ED-007) ---
    lines = load_dimension_lookup(
        db_path, "Fact_Order_Lines",
        ["order_line_key", "order_key", "customer_key", "product_key", "order_date_key", "quantity", "net_line_revenue"],
    )
    bad_line_fk = set(df["order_line_key"]) - set(lines["order_line_key"])
    if bad_line_fk:
        raise ValueError(f"order_line_key value(s) missing from live Fact_Order_Lines: {sorted(bad_line_fk)[:10]}")
    orders = load_dimension_lookup(db_path, "Fact_Orders", ["order_key"])
    if set(df["order_key"]) - set(orders["order_key"]):
        raise ValueError("order_key value(s) missing from live Fact_Orders.")
    customers = load_dimension_lookup(db_path, "Dim_Customer", ["customer_key"])
    if set(df["customer_key"]) - set(customers["customer_key"]):
        raise ValueError("customer_key value(s) missing from Dim_Customer.")
    products = load_dimension_lookup(db_path, "Dim_Product", ["product_key", "category"])
    if set(df["product_key"]) - set(products["product_key"]):
        raise ValueError("product_key value(s) missing from Dim_Product.")
    dates = load_dimension_lookup(db_path, "Dim_Date", ["date_key"])
    if set(df["return_date_key"]) - set(dates["date_key"]):
        raise ValueError("return_date_key value(s) missing from Dim_Date.")
    reasons = load_dimension_lookup(db_path, "Dim_Return_Reason", ["return_reason_key", "reason_code"])
    if set(df["return_reason_key"]) - set(reasons["return_reason_key"]):
        raise ValueError("return_reason_key value(s) missing from Dim_Return_Reason.")

    merged = df.merge(lines, on="order_line_key", suffixes=("", "_line"))
    if len(merged) != n:
        raise ValueError("Join to Fact_Order_Lines lost or duplicated rows -- FK integrity is broken.")

    # --- Denormalized consistency: a return's order/customer/product must
    #     match the line it came from (all four are on Fact_Returns, so
    #     they can disagree if the generator is wrong) ---
    for col in ["order_key", "customer_key", "product_key"]:
        mism = merged[merged[col] != merged[f"{col}_line"]]
        if not mism.empty:
            raise ValueError(f"{len(mism)} return(s) disagree with their order line's {col}.")

    # --- Section 7: return timing 5-21 days after the order, exactly ---
    order_dt = pd.to_datetime(merged["order_date_key"].astype(str), format="%Y%m%d")
    return_dt = pd.to_datetime(merged["return_date_key"].astype(str), format="%Y%m%d")
    lag = (return_dt - order_dt).dt.days
    lo, hi = RETURN_LAG_DAYS_RANGE
    bad_lag = merged[(lag < lo) | (lag > hi)]
    if not bad_lag.empty:
        raise ValueError(
            f"{len(bad_lag)} return(s) fall outside the documented {lo}-{hi} day return "
            f"window (Section 7, exact rule -- no tolerance). Observed lag range: "
            f"{lag.min()}-{lag.max()} days."
        )

    # --- return_quantity never exceeds the line's quantity ---
    over = merged[merged["return_quantity"] > merged["quantity"]]
    if not over.empty:
        raise ValueError(f"{len(over)} return(s) have return_quantity greater than the line's quantity sold.")

    # --- return_amount ties out to the line, proportionally ---
    expected_amount = merged.apply(
        lambda r: _round_money(float(r["net_line_revenue"]) * r["return_quantity"] / r["quantity"]), axis=1
    )
    bad_amount = merged[(merged["return_amount"] - expected_amount).abs() > 0.01]
    if not bad_amount.empty:
        raise ValueError(f"{len(bad_amount)} return(s) have return_amount != net_line_revenue x (return_quantity/quantity).")
    over_refund = merged[merged["return_amount"] > merged["net_line_revenue"].astype(float) + 0.01]
    if not over_refund.empty:
        raise ValueError(f"{len(over_refund)} return(s) refund more than the line's net revenue.")

    # --- Restocking fee: only on CHANGED_MIND, at the documented rate ---
    reason_key_to_code = dict(zip(reasons["return_reason_key"], reasons["reason_code"]))
    merged["reason_code"] = merged["return_reason_key"].map(reason_key_to_code)
    fee_on_wrong_reason = merged[(merged["reason_code"] != RESTOCKING_FEE_REASON) & (merged["restocking_fee"] != 0)]
    if not fee_on_wrong_reason.empty:
        raise ValueError(
            f"{len(fee_on_wrong_reason)} return(s) carry a restocking fee on a reason other than "
            f"{RESTOCKING_FEE_REASON} -- the business never charges customers for its own faults."
        )
    cm = merged[merged["reason_code"] == RESTOCKING_FEE_REASON]
    expected_fee = cm.apply(lambda r: _round_money(r["return_amount"] * RESTOCKING_FEE_PCT), axis=1)
    bad_fee = cm[(cm["restocking_fee"] - expected_fee).abs() > 0.01]
    if not bad_fee.empty:
        raise ValueError(f"{len(bad_fee)} CHANGED_MIND return(s) have a restocking_fee != {RESTOCKING_FEE_PCT:.0%} of return_amount.")

    # --- Section 9 targets, unit-weighted (Return Rate = Units Returned / Units Sold) ---
    units_sold_total = float(lines["quantity"].sum())
    units_returned_total = float(df["return_quantity"].sum())
    blended = units_returned_total / units_sold_total
    b_lo = BLENDED_RETURN_RATE_TARGET[0] * (1 - VALIDATION_TOLERANCE)
    b_hi = BLENDED_RETURN_RATE_TARGET[1] * (1 + VALIDATION_TOLERANCE)
    if not (b_lo <= blended <= b_hi):
        raise ValueError(f"Blended unit return rate {blended:.1%} outside tolerance-widened target {BLENDED_RETURN_RATE_TARGET} (Section 9).")

    cat_by_product = dict(zip(products["product_key"], products["category"]))
    lines_cat = lines.assign(category=lines["product_key"].map(cat_by_product))
    df_cat = df.assign(category=df["product_key"].map(cat_by_product))
    sold_by_cat = lines_cat.groupby("category")["quantity"].sum()
    returned_by_cat = df_cat.groupby("category")["return_quantity"].sum()

    for category, target in (("Footwear", FOOTWEAR_RETURN_RATE_TARGET), ("Accessories", ACCESSORIES_RETURN_RATE_TARGET)):
        rate = float(returned_by_cat.get(category, 0)) / float(sold_by_cat[category])
        t_lo = target[0] * (1 - VALIDATION_TOLERANCE)
        t_hi = target[1] * (1 + VALIDATION_TOLERANCE)
        if not (t_lo <= rate <= t_hi):
            raise ValueError(f"{category} unit return rate {rate:.1%} outside tolerance-widened target {target} (Section 9).")

    # --- Section 7 VIP return ceiling: Loyal VIP must have the LOWEST
    #     realized return rate of any persona, for every category ---
    personas = assign_customer_personas(customers["customer_key"].tolist(), seed=persona_seed)
    lines_p = lines_cat.assign(persona=lines_cat["customer_key"].map(personas))
    df_p = df_cat.assign(persona=df_cat["customer_key"].map(personas))
    sold_pc = lines_p.groupby(["persona", "category"])["quantity"].sum()
    ret_pc = df_p.groupby(["persona", "category"])["return_quantity"].sum()
    for category in CATEGORY_BASE_RETURN_RATE:
        rates = {}
        for persona in PERSONA_RETURN_TENDENCY:
            sold = float(sold_pc.get((persona, category), 0))
            if sold == 0:
                continue
            rates[persona] = float(ret_pc.get((persona, category), 0)) / sold
        if "Loyal VIP" in rates and len(rates) > 1:
            lowest = min(rates, key=rates.get)
            if lowest != "Loyal VIP":
                raise ValueError(
                    f"Section 7 VIP return ceiling violated for {category}: Loyal VIP "
                    f"({rates['Loyal VIP']:.1%}) is not the lowest persona -- {lowest} "
                    f"({rates[lowest]:.1%}) is."
                )

    # --- High-Return Customer must genuinely be the highest-return persona ---
    sold_p = lines_p.groupby("persona")["quantity"].sum()
    ret_p = df_p.groupby("persona")["return_quantity"].sum()
    overall = {p: float(ret_p.get(p, 0)) / float(sold_p[p]) for p in sold_p.index}
    if max(overall, key=overall.get) != "High-Return Customer":
        raise ValueError(
            f"High-Return Customer is not the highest-return persona overall -- "
            f"{max(overall, key=overall.get)} is. Realized: "
            f"{ {k: f'{v:.1%}' for k, v in overall.items()} }"
        )


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
        con.execute("DELETE FROM Fact_Returns")
        con.execute(f"INSERT INTO Fact_Returns ({', '.join(COLUMN_ORDER)}) SELECT {', '.join(COLUMN_ORDER)} FROM df")
        actual = con.execute("SELECT COUNT(*) FROM Fact_Returns").fetchone()[0]
        if actual != expected:
            con.execute("ROLLBACK"); txn = False
            raise ValueError(f"Row count mismatch after load: expected {expected}, got {actual}. Rolled back -- Fact_Returns unchanged.")
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
    print(f"Loaded {load_to_duckdb(df)} rows into Fact_Returns at {DB_PATH}")


if __name__ == "__main__":
    main()
