"""
order_generation_core.py — shared, deterministic customer-behavior and
order/line-item generation logic.

This module exists for two reasons, both documented as engineering
decisions (docs/engineering_decision_log.md ED-009, ED-010):

1. Persona assignment (ED-009). Phase 3.8's generate_dim_customer.py
   deliberately did NOT assign personas -- no Dim_Customer column has a
   documented persona dependency. This module is where personas are
   finally computed, deterministically, from customer_key + a seed --
   never stored anywhere, never passed between generators as data,
   always re-derivable identically by any fact-table generator that
   needs to know a customer's persona (Fact_Orders now; Fact_Returns and
   Fact_Customer_Monthly_Snapshot later). Every consumer gets the SAME
   persona for the SAME customer_key, which is essential: a customer
   can't be a "Loyal VIP" in one fact table and a "Bargain Hunter" in
   another.

2. Order + line-item generation (ED-010). Fact_Orders (header revenue)
   and Fact_Order_Lines (line-item detail, a future phase) must
   reconcile: SUM(net_line_revenue) per order must equal
   Fact_Orders.net_revenue for that order (docs/design_decisions.md
   reconciliation rule). That's only guaranteed if both tables derive
   from the SAME underlying line-item simulation, not two independently
   written approximations of the same idea. generate_fact_orders.py
   (Phase 3.9) calls generate_line_items_for_order() to compute revenue
   for the header it persists, but does NOT persist the line items
   themselves. A future generate_fact_order_lines.py will call the exact
   same function, with the exact same seed and customer/order processing
   order, and persist what this module already computed -- guaranteed to
   reconcile by construction, not by coincidence.

Persona parameters below are transcribed directly from
docs/data_generation_strategy.md Section 4 (population, frequency, AOV
tendency, category preference) and Section 7 (the VIP AOV floor/ceiling
business rule, the Seasonal Shopper campaign-window constraint, the
signup-to-first-purchase timing split). Nothing here should need to
change unless those source documents change first.
"""

from datetime import date, timedelta
from random import Random

# --- Persona population (docs/data_generation_strategy.md Section 4) ---
PERSONA_POPULATION = {
    "Loyal VIP": 0.08,
    "Fashion Enthusiast": 0.18,
    "Bargain Hunter": 0.22,
    "Seasonal Shopper": 0.20,
    "One-Time Buyer": 0.25,
    "High-Return Customer": 0.07,
}

# --- Orders per year once active (Section 4's "Purchase Frequency" column) ---
# One-Time Buyer is handled as a special case (exactly 1, ever), not a rate.
PERSONA_ANNUAL_ORDER_RANGE = {
    "Loyal VIP": (8, 12),
    "Fashion Enthusiast": (5, 8),
    "Bargain Hunter": (3, 5),
    "Seasonal Shopper": (1, 3),
    "High-Return Customer": (4, 6),
}

# --- AOV multiplier applied to a product's list_price (Section 4's "AOV
#     Tendency" column, and Section 7's explicit "VIP AOV floor" /
#     "never allowed to fall to a Bargain-Hunter-level price point" rule).
#     Sampled ONCE per order (not per line item) so every item in a given
#     order reflects the same customer-level pricing behavior. Ranges are
#     deliberately non-overlapping between Loyal VIP and Bargain Hunter,
#     satisfying the floor/ceiling rule by construction. ---
PERSONA_AOV_MULTIPLIER_RANGE = {
    "Loyal VIP": (1.30, 1.60),
    "Fashion Enthusiast": (1.10, 1.30),
    "Bargain Hunter": (0.70, 0.85),
    "Seasonal Shopper": (0.95, 1.05),
    "One-Time Buyer": (0.85, 1.15),
    "High-Return Customer": (0.90, 1.10),
}

# --- Category volume mix and persona tilts (Section 4's "Preferred
#     Categories" column, calibrated).
#     BASE_CATEGORY_VOLUME_MIX is the unit-volume reality of an apparel
#     catalog: Accessories/basics dominate unit volume ("high-volume gift
#     category" per Section 5), Outerwear is low-volume premium ("premium
#     seasonal category"). A flat 20%-per-category draw would over-sample
#     $90-280 Outerwear and blow the documented $65-85 AOV target --
#     caught by validate_dataframe() on this generator's first real
#     execution, then calibrated here.
#     PERSONA_CATEGORY_TILTS multiply the base mix per persona (then
#     renormalize), preserving each persona's documented directional
#     preference on top of the realistic base. ---
BASE_CATEGORY_VOLUME_MIX = {
    "Womenswear": 0.25,
    "Menswear": 0.17,
    "Outerwear": 0.04,
    "Footwear": 0.08,
    "Accessories": 0.46,
}

PERSONA_CATEGORY_TILTS = {
    "Loyal VIP": {},  # cross-category: buys the base mix, no tilt
    "Fashion Enthusiast": {"Womenswear": 2.0, "Accessories": 1.5, "Menswear": 0.5, "Outerwear": 0.5, "Footwear": 0.5},
    "Bargain Hunter": {},  # "no strong category preference"
    "Seasonal Shopper": {"Outerwear": 3.0, "Accessories": 1.5, "Womenswear": 0.5, "Menswear": 0.5, "Footwear": 0.5},
    "One-Time Buyer": {},  # "no pattern"
    "High-Return Customer": {"Footwear": 3.5, "Womenswear": 1.75, "Menswear": 0.5, "Outerwear": 0.5, "Accessories": 0.5},
}


def _persona_category_weights(persona: str) -> dict:
    """Base volume mix x persona tilt, renormalized to sum to 1."""
    tilts = PERSONA_CATEGORY_TILTS[persona]
    raw = {cat: share * tilts.get(cat, 1.0) for cat, share in BASE_CATEGORY_VOLUME_MIX.items()}
    total = sum(raw.values())
    return {cat: w / total for cat, w in raw.items()}


PERSONA_CATEGORY_WEIGHTS = {persona: _persona_category_weights(persona) for persona in PERSONA_CATEGORY_TILTS}

# --- Order-timing mode per persona ---
# "regular": gap-based, next order = prev order + a persona-specific
#            random day gap.
# "campaign": orders anchored to actual Dim_Campaign windows (Bargain
#            Hunter -- "follows discount depth," any campaign window).
# "campaign_holiday_bts": orders anchored ONLY to Holiday Collection /
#            Back-to-School windows (Seasonal Shopper -- Section 7's
#            explicit "+/-2-week window" business rule).
# "single": exactly one order, ever (One-Time Buyer).
PERSONA_TIMING_MODE = {
    "Loyal VIP": "regular",
    "Fashion Enthusiast": "regular",
    "Bargain Hunter": "campaign",
    "Seasonal Shopper": "campaign_holiday_bts",
    "One-Time Buyer": "single",
    "High-Return Customer": "regular",
}

# --- Inter-purchase day-gap range for "regular"-mode personas. Chosen to
#     be roughly consistent with each persona's annual order rate
#     (365 / annual_rate approximately centers within the range). ---
PERSONA_GAP_DAYS_RANGE = {
    "Loyal VIP": (25, 45),
    "Fashion Enthusiast": (40, 70),
    "High-Return Customer": (50, 90),
}

# --- Signup-to-first-purchase timing (Section 7, exact business rule) ---
FIRST_ORDER_WITHIN_7_DAYS_PROBABILITY = 0.70
FIRST_ORDER_SHORT_DELAY_RANGE = (0, 7)
FIRST_ORDER_LONG_DELAY_RANGE = (8, 60)

# --- Line items per order, and quantity per line item (Section 3's
#     "~1.4 items per order" target: 0.70*1 + 0.25*2 + 0.05*3 = 1.35) ---
LINE_ITEM_COUNT_CHOICES = [1, 2, 3]
LINE_ITEM_COUNT_WEIGHTS = [0.75, 0.21, 0.04]  # avg 1.29 items/order, calibrated vs the ~1.4 doc estimate to land the documented $65-85 AOV
QUANTITY_CHOICES = [1, 2]
QUANTITY_WEIGHTS = [0.92, 0.08]  # avg 1.08 units/line, calibrated (same AOV target)

# --- Discount depth -> percentage off, applied when an order falls
#     inside a campaign window (docs/business_glossary.md campaign
#     calendar's discount_depth values) ---
DISCOUNT_PCT_BY_DEPTH = {
    "None": 0.00,
    "Light": 0.10,
    "Moderate": 0.20,
    "Deep": 0.30,
    "Deepest": 0.45,
}

VALID_PERSONAS = set(PERSONA_POPULATION.keys())


# --- Retention conversion probability by signup year (Section 2's
#     business-evolution narrative, made operational): 2023 was "almost
#     entirely first-order volume -- the retention/lifecycle program
#     doesn't exist yet"; repeat behavior matures through 2024-2025. A
#     customer's persona repeat-purchase behavior only activates with
#     this probability; otherwise they stop after their first order
#     regardless of persona (One-Time Buyers are unaffected -- they
#     already stop at one by definition). Without this gate, every
#     non-OTB persona repeats from day one and the overall repeat rate
#     lands ~65%, far above Section 9's documented 35-45% target --
#     caught by validate_dataframe() during Phase 3.9 execution. ---
REPEAT_CONVERSION_PROBABILITY_BY_SIGNUP_YEAR = {2023: 0.45, 2024: 0.60, 2025: 0.65}


def assign_customer_personas(customer_keys: list, seed: int) -> dict:
    """
    Deterministically assigns one persona per customer_key, using the
    Section 4 population weights.

    Uses its OWN Random(seed) instance, entirely separate from whatever
    RNG a calling generator uses for order timing/line items -- this
    keeps persona assignment independently reproducible and callable on
    its own (e.g. by a future Fact_Customer_Monthly_Snapshot generator
    that needs to know personas but has no reason to replay order
    generation) without depending on call order relative to anything else.

    customer_keys are processed in sorted order specifically so the
    result doesn't depend on whatever order the caller's DataFrame or
    query happened to return rows in.
    """
    rng = Random(seed)
    personas = list(PERSONA_POPULATION.keys())
    weights = list(PERSONA_POPULATION.values())
    return {
        customer_key: rng.choices(personas, weights=weights, k=1)[0]
        for customer_key in sorted(customer_keys)
    }


def _date_range(start: date, end: date):
    """All dates from start to end, inclusive."""
    current = start
    while current <= end:
        yield current
        current += timedelta(days=1)


def build_campaign_date_lookup(campaign_windows: list, live_campaign_rows) -> dict:
    """
    Builds {date: {"campaign_key", "discount_depth", "discount_pct"}} for
    every date covered by any campaign window, resolving campaign_key
    against the LIVE Dim_Campaign table (ED-007 pattern) rather than
    assuming an order.

    When campaign windows overlap (e.g. Holiday Collection covers Black
    Friday), the deeper-discount campaign wins for that date -- the
    reasoning being that the deeper discount is the more plausible actual
    purchase driver on a day where multiple promotions are technically
    active.

    live_campaign_rows: an iterable of rows (e.g. from df.itertuples())
    with .campaign_name, .campaign_key, .discount_depth attributes.
    """
    name_to_row = {row.campaign_name: row for row in live_campaign_rows}

    date_lookup = {}
    for window in campaign_windows:
        campaign_row = name_to_row.get(window["campaign_name"])
        if campaign_row is None:
            raise ValueError(
                f"Campaign '{window['campaign_name']}' from campaign_calendar_reference.py "
                f"was not found in the live Dim_Campaign table -- has it been (re)loaded?"
            )
        discount_pct = DISCOUNT_PCT_BY_DEPTH[campaign_row.discount_depth]
        for d in _date_range(window["start_date"], window["end_date"]):
            existing = date_lookup.get(d)
            if existing is None or discount_pct > existing["discount_pct"]:
                date_lookup[d] = {
                    "campaign_key": campaign_row.campaign_key,
                    "discount_depth": campaign_row.discount_depth,
                    "discount_pct": discount_pct,
                }
    return date_lookup


def _first_order_date(rng: Random, signup_date: date, horizon_end: date):
    """
    Section 7's exact business rule: 70% of customers order within 7 days
    of signup, the remaining 30% within 8-60 days. Returns None if even
    the earliest possible first order would land after horizon_end (a
    customer who signed up too close to the end of the observation
    window to have a first order recorded at all -- a real, expected
    outcome, not a bug).
    """
    if rng.random() < FIRST_ORDER_WITHIN_7_DAYS_PROBABILITY:
        delay = rng.randint(*FIRST_ORDER_SHORT_DELAY_RANGE)
    else:
        delay = rng.randint(*FIRST_ORDER_LONG_DELAY_RANGE)
    candidate = signup_date + timedelta(days=delay)
    return candidate if candidate <= horizon_end else None


def generate_order_dates_for_customer(
    rng: Random,
    persona: str,
    signup_date: date,
    horizon_end: date,
    holiday_bts_dates_in_range: list,
    campaign_dates_in_range: list,
) -> list:
    """
    Generates the list of order dates for one customer, following their
    persona's timing mode. Returns an empty list for a customer who never
    places an order in the observation window -- either because their
    sampled order count came out to zero (a non-converting signup, a real
    possibility for every persona except One-Time Buyer) or because they
    signed up too close to horizon_end for even a first order to land in
    range.
    """
    tenure_days = (horizon_end - signup_date).days
    if tenure_days < 0:
        return []
    tenure_years = tenure_days / 365.25

    if persona == "One-Time Buyer":
        target_orders = 1
    else:
        lo, hi = PERSONA_ANNUAL_ORDER_RANGE[persona]
        annual_rate = rng.uniform(lo, hi)
        target_orders = max(0, round(annual_rate * tenure_years))

    if target_orders == 0:
        return []

    first = _first_order_date(rng, signup_date, horizon_end)
    if first is None:
        return []

    dates = [first]
    remaining = target_orders - 1
    if remaining <= 0:
        return dates

    # Retention conversion gate (Section 2, see module constant above):
    # the customer's persona repeat behavior only activates with a
    # probability that grows by signup-year cohort as the business's
    # retention program matures. The roll consumes exactly one draw from
    # the shared RNG stream for every non-single persona, keeping the
    # stream deterministic and replayable by the future Fact_Order_Lines
    # generator (ED-010).
    conversion_p = REPEAT_CONVERSION_PROBABILITY_BY_SIGNUP_YEAR.get(signup_date.year, 0.55)
    if rng.random() >= conversion_p:
        return dates

    mode = PERSONA_TIMING_MODE[persona]
    if mode == "regular":
        # Holiday gravity (Section 6's campaign-lift concept applied to
        # gap-based personas): real e-commerce demand is elevated for
        # EVERYONE in the gift season, not just campaign-anchored
        # personas. Each gap-generated order has a 12% chance of being
        # redirected to a uniform random Nov-Dec date in the same year --
        # without this, the majority of revenue (regular personas) is
        # season-blind and Section 9's 25-30% holiday-revenue-share
        # target is unreachable. Calibrated during Phase 3.9 execution.
        gap_lo, gap_hi = PERSONA_GAP_DAYS_RANGE[persona]
        current = first
        for _ in range(remaining):
            current = current + timedelta(days=rng.randint(gap_lo, gap_hi))
            if current > horizon_end:
                break
            placed = current
            if rng.random() < 0.12:
                holiday_start = date(placed.year, 11, 1)
                holiday_end = min(date(placed.year, 12, 31), horizon_end)
                if signup_date <= holiday_start <= holiday_end:
                    offset = rng.randint(0, (holiday_end - holiday_start).days)
                    placed = holiday_start + timedelta(days=offset)
            dates.append(placed)
    elif mode == "campaign":
        # "Heavily clustered in sale windows" (Section 4) -- heavily, not
        # exclusively: 50% of a Bargain Hunter's repeat orders land on
        # campaign days, the remaining half on ordinary days (a bargain
        # hunter still occasionally needs something at full price).
        # Calibrated jointly with the Seasonal Shopper +/-2-week rule
        # below to land Section 9's 30-40% campaign-revenue-share target
        # against a calendar where 39.8% of ALL days fall inside some
        # campaign window.
        pool = [d for d in campaign_dates_in_range if d > first]
        span_days = (horizon_end - first).days
        for _ in range(remaining):
            if pool and rng.random() < 0.50:
                dates.append(rng.choice(pool))
            elif span_days > 0:
                dates.append(first + timedelta(days=rng.randint(1, span_days)))
    elif mode == "campaign_holiday_bts":
        # Section 7's exact wording: "within a +/-2-week window of a
        # Holiday or Back-to-School campaign period" -- AROUND the window,
        # not strictly inside it. The caller passes a date pool already
        # expanded by +/-14 days for exactly this reason. (Implemented
        # strictly-inside at first; corrected when the campaign-revenue-
        # share validation caught the aggregate effect.)
        pool = [d for d in holiday_bts_dates_in_range if d > first]
        if pool:
            k = min(remaining, len(pool))
            dates.extend(rng.sample(pool, k=k))
    # mode == "single" (One-Time Buyer): remaining is always 0, handled above.

    return sorted(set(dates))


def generate_line_items_for_order(rng: Random, persona: str, category_products: dict) -> list:
    """
    Generates 1-3 line items for one order: category (persona-weighted),
    product (uniform within the chosen category), quantity, and an
    effective unit_price = the product's list_price x a single
    order-level AOV multiplier sampled once and applied to every item in
    the order (so an order's items reflect one consistent pricing
    behavior, not independently-varying prices within the same order).

    category_products: dict[category_name] -> list of
    (product_key, list_price, unit_cost) tuples.

    Returns a list of dicts: product_key, quantity, unit_price, unit_cost.
    (unit_cost is passed through unchanged -- margin isn't persona-driven.)
    """
    aov_lo, aov_hi = PERSONA_AOV_MULTIPLIER_RANGE[persona]
    aov_multiplier = rng.uniform(aov_lo, aov_hi)

    n_items = rng.choices(LINE_ITEM_COUNT_CHOICES, weights=LINE_ITEM_COUNT_WEIGHTS, k=1)[0]
    category_names = list(PERSONA_CATEGORY_WEIGHTS[persona].keys())
    category_weights = list(PERSONA_CATEGORY_WEIGHTS[persona].values())

    line_items = []
    for _ in range(n_items):
        category = rng.choices(category_names, weights=category_weights, k=1)[0]
        products = category_products[category]
        # Price-INVERSE weighting within the category: cheaper items sell
        # more units -- the volume reality of any apparel catalog, and a
        # necessary part of hitting the documented $65-85 blended AOV
        # target with category price ranges reaching $280. Calibrated
        # after this generator's first real execution blew that target
        # ($145.95) using uniform product selection.
        price_inverse_weights = [1.0 / p[1] for p in products]
        product_key, list_price, unit_cost = rng.choices(products, weights=price_inverse_weights, k=1)[0]
        quantity = rng.choices(QUANTITY_CHOICES, weights=QUANTITY_WEIGHTS, k=1)[0]
        line_items.append({
            "product_key": product_key,
            "quantity": quantity,
            "unit_price": round(list_price * aov_multiplier, 2),
            "unit_cost": unit_cost,
        })
    return line_items


# =====================================================================
# Full simulation (ED-010 completed): the entire order+line simulation
# lives HERE, not in any generator. generate_fact_orders.py persists the
# order headers this returns; generate_fact_order_lines.py persists the
# line rows. Reconciliation (SUM(net_line_revenue) == header net_revenue
# per order) is guaranteed by construction: line-level discounts are
# allocated proportionally with the rounding remainder assigned to the
# final line, so the line sum equals the header figure exactly -- both
# tables are two views of one simulated object, not two simulations.
# =====================================================================

import sys as _sys
from pathlib import Path as _Path
_sys.path.append(str(_Path(__file__).parent))
from db_utils import load_dimension_lookup as _load_lookup

# Simulation-level business constants, shared by both fact generators.
SALES_CHANNEL_WEIGHTS = {"Website": 0.65, "Mobile App": 0.22, "Marketplace": 0.13}
REQUIRED_CATEGORIES = {"Womenswear", "Menswear", "Outerwear", "Footwear", "Accessories"}
FREE_SHIPPING_THRESHOLD = 75.00
FLAT_SHIPPING_FEE = 6.99
SIMULATION_HORIZON_END = date(2025, 12, 31)


def prepare_simulation_inputs(db_path) -> dict:
    """
    Resolves every live-database dependency the simulation needs (ED-007
    pattern, ED-011 shared helper), validating business requirements
    rather than table sizes. Called identically by generate_fact_orders
    and generate_fact_order_lines so both replay from the same inputs.
    """
    from campaign_calendar_reference import get_campaign_windows

    customer_lookup = _load_lookup(
        db_path, "Dim_Customer",
        ["customer_key", "signup_date", "acquisition_channel_key", "home_geography_key"],
    ).sort_values("customer_key")

    product_lookup = _load_lookup(db_path, "Dim_Product", ["product_key", "category", "list_price", "unit_cost"])
    category_products = {
        cat: list(zip(g["product_key"], g["list_price"].astype(float), g["unit_cost"].astype(float)))
        for cat, g in product_lookup.groupby("category")
    }
    missing = REQUIRED_CATEGORIES - set(category_products)
    if missing:
        raise ValueError(f"Dim_Product is missing required categor(y/ies): {sorted(missing)}.")

    campaign_lookup = _load_lookup(db_path, "Dim_Campaign", ["campaign_key", "campaign_name", "discount_depth"])
    windows = get_campaign_windows()
    missing_c = {w["campaign_name"] for w in windows} - set(campaign_lookup["campaign_name"])
    if missing_c:
        raise ValueError(f"Dim_Campaign is missing required campaign(s): {sorted(missing_c)}.")
    campaign_date_lookup = build_campaign_date_lookup(windows, campaign_lookup.itertuples())
    holiday_bts_dates_all = sorted({
        d for w in windows
        if w["campaign_name"].startswith("Holiday Collection") or w["campaign_name"].startswith("Back-to-School")
        for d in _date_range(w["start_date"] - timedelta(days=14), w["end_date"] + timedelta(days=14))
    })
    all_campaign_dates_all = sorted(campaign_date_lookup.keys())

    sc = _load_lookup(db_path, "Dim_Sales_Channel", ["sales_channel_key", "channel_name"])
    channel_name_to_key = dict(zip(sc["channel_name"], sc["sales_channel_key"]))
    missing_s = set(SALES_CHANNEL_WEIGHTS) - set(channel_name_to_key)
    if missing_s:
        raise ValueError(f"Dim_Sales_Channel is missing required channel(s): {sorted(missing_s)}.")

    dd = _load_lookup(db_path, "Dim_Date", ["full_date"])
    min_date, max_date = dd["full_date"].min().date(), dd["full_date"].max().date()

    return {
        "customer_lookup": customer_lookup,
        "category_products": category_products,
        "campaign_date_lookup": campaign_date_lookup,
        "holiday_bts_dates_all": holiday_bts_dates_all,
        "all_campaign_dates_all": all_campaign_dates_all,
        "channel_name_to_key": channel_name_to_key,
        "min_date": min_date,
        "max_date": max_date,
    }


def simulate_orders_and_lines(seed: int, persona_seed: int, inputs: dict):
    """
    Runs the complete deterministic simulation and returns
    (order_rows, line_rows). The RNG stream is consumed in exactly one
    fixed order (sorted customers -> order dates -> line items -> sales
    channel), so the same (seed, persona_seed, inputs) always yields the
    identical pair. Line discount allocation adds no RNG draws.
    """
    rng = Random(seed)
    customer_lookup = inputs["customer_lookup"]
    category_products = inputs["category_products"]
    campaign_date_lookup = inputs["campaign_date_lookup"]
    holiday_bts_dates_all = inputs["holiday_bts_dates_all"]
    all_campaign_dates_all = inputs["all_campaign_dates_all"]
    channel_name_to_key = inputs["channel_name_to_key"]
    min_date, max_date = inputs["min_date"], inputs["max_date"]

    channel_names = list(SALES_CHANNEL_WEIGHTS.keys())
    channel_weights = list(SALES_CHANNEL_WEIGHTS.values())

    personas = assign_customer_personas(customer_lookup["customer_key"].tolist(), seed=persona_seed)

    order_rows, line_rows = [], []
    order_key = 1
    order_line_key = 1
    for customer in customer_lookup.itertuples():
        persona = personas[customer.customer_key]
        signup_date = customer.signup_date
        if hasattr(signup_date, "date"):
            signup_date = signup_date.date()

        hb = [d for d in holiday_bts_dates_all if signup_date <= d <= SIMULATION_HORIZON_END]
        cd = [d for d in all_campaign_dates_all if signup_date <= d <= SIMULATION_HORIZON_END]
        order_dates = generate_order_dates_for_customer(
            rng, persona, signup_date, SIMULATION_HORIZON_END, hb, cd
        )

        for i, order_date in enumerate(order_dates):
            if order_date < min_date or order_date > max_date:
                raise ValueError(
                    f"Generated order_date {order_date} for customer_key "
                    f"{customer.customer_key} falls outside Dim_Date's range."
                )

            line_items = generate_line_items_for_order(rng, persona, category_products)
            gross_revenue = sum(li["quantity"] * li["unit_price"] for li in line_items)

            info = campaign_date_lookup.get(order_date)
            if info is not None:
                campaign_key = int(info["campaign_key"])
                discount_pct = info["discount_pct"]
                discount_amount = round(gross_revenue * discount_pct, 2)
            else:
                campaign_key = None
                discount_pct = 0.0
                discount_amount = 0.0

            net_revenue = round(gross_revenue - discount_amount, 2)
            shipping_revenue = 0.0 if net_revenue >= FREE_SHIPPING_THRESHOLD else FLAT_SHIPPING_FEE
            chosen = rng.choices(channel_names, weights=channel_weights, k=1)[0]

            order_rows.append({
                "order_key": order_key,
                "order_id": f"ORD-{order_key:06d}",
                "customer_key": int(customer.customer_key),
                "order_date_key": int(order_date.strftime("%Y%m%d")),
                "sales_channel_key": int(channel_name_to_key[chosen]),
                "geography_key": int(customer.home_geography_key),
                "campaign_key": campaign_key,
                "acquisition_channel_key": int(customer.acquisition_channel_key),
                "gross_revenue": round(gross_revenue, 2),
                "discount_amount": discount_amount,
                "net_revenue": net_revenue,
                "shipping_revenue": shipping_revenue,
                "is_first_order": (i == 0),
            })

            # Line-level discount allocation: proportional, remainder on
            # the final line so SUM(line discounts) == header discount and
            # therefore SUM(net_line_revenue) == header net_revenue exactly.
            allocated = 0.0
            for j, li in enumerate(line_items):
                gross_line = round(li["quantity"] * li["unit_price"], 2)
                if j < len(line_items) - 1:
                    disc_line = round(gross_line * discount_pct, 2)
                    allocated = round(allocated + disc_line, 2)
                else:
                    disc_line = round(discount_amount - allocated, 2)
                line_rows.append({
                    "order_line_key": order_line_key,
                    "order_key": order_key,
                    "customer_key": int(customer.customer_key),
                    "product_key": int(li["product_key"]),
                    "order_date_key": int(order_date.strftime("%Y%m%d")),
                    "quantity": li["quantity"],
                    "unit_price": li["unit_price"],
                    "gross_line_revenue": gross_line,
                    "discount_amount": disc_line,
                    "net_line_revenue": round(gross_line - disc_line, 2),
                    "unit_cost": li["unit_cost"],
                })
                order_line_key += 1

            order_key += 1

    return order_rows, line_rows
