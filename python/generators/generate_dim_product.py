"""
Phase 3.6 - Dim_Product generator.

Dim_Product is the first table in this project that needs genuine
stochastic variety rather than a fixed reference list (Dim_Geography),
a closed taxonomy (Dim_Marketing_Channel, Dim_Sales_Channel), or a
formula-derived enrichment (Dim_Campaign). 180 SKUs across 5 categories
need varied subcategories, colors, sizes, and prices-within-a-range --
real randomness -- while still needing to stay fully deterministic
across re-runs. See docs/engineering_decision_log.md ED-006 for the
seeding approach that resolves that tension.

Business plan (from docs/data_generation_strategy.md Section 5):
    Category      SKUs  Price Range     Cost % of List
    Womenswear      45  $28-$120        40%
    Menswear        35  $25-$110        40%
    Outerwear       30  $90-$280        35% (highest margin, premium seasonal)
    Footwear        30  $60-$180        45% (lowest margin -- sizing/return costs)
    Accessories     40  $15-$65         30% (highest margin, gift-driven)
    Total          180

Randomness classification, per data_generation_strategy.md Section 8
(the same three-way framework used to plan Phase 3's synthetic customer
behavior, applied here to product attributes):
    - Business Rule (deterministic): SKU count per category, price range
      per category, cost-% per category, which subcategories/genders are
      valid for a category, which subcategories carry no size.
    - Weighted Random: which subcategory/gender/collection season a given
      SKU gets within its category's valid options; list_price sampled
      within the category's range.
    - Pure Random: color, size (within the valid set for that SKU).

Engineering standards (FPS v1.0, unchanged from Phase 3.2-3.5 -- see
docs/engineering_decision_log.md ED-001 through ED-005): generation,
validation, and database loading remain separate functions; validation
raises explicit exceptions, never `assert`; the database load is
transaction-wrapped and idempotent. ED-006 (this phase) adds the seeding
convention for reproducible randomness -- everything else is unchanged.

Run:
    python python/generators/generate_dim_product.py
"""

import re
from pathlib import Path
from random import Random

import duckdb
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = PROJECT_ROOT / "data" / "generated" / "dim_product.csv"
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"

# ED-006: fixed seed for reproducible randomness -- see build_dataframe()'s
# docstring for why a locally-scoped Random instance is used instead of
# the global `random` module.
RANDOM_SEED = 42

# --- Business rule: the category plan itself (docs/data_generation_strategy.md Section 5) ---
CATEGORY_PLAN = {
    "Womenswear": {
        "sku_count": 45,
        "price_range": (28.00, 120.00),
        "cost_pct": 0.40,
        "gender_options": ["Women's"],
        "subcategories": ["Dresses", "Tops", "Bottoms", "Denim", "Knitwear"],
    },
    "Menswear": {
        "sku_count": 35,
        "price_range": (25.00, 110.00),
        "cost_pct": 0.40,
        "gender_options": ["Men's"],
        "subcategories": ["Shirts", "Bottoms", "Denim", "Knitwear", "Activewear"],
    },
    "Outerwear": {
        "sku_count": 30,
        "price_range": (90.00, 280.00),
        "cost_pct": 0.35,
        "gender_options": ["Women's", "Men's", "Unisex"],
        "subcategories": ["Jackets", "Coats", "Vests"],
    },
    "Footwear": {
        "sku_count": 30,
        "price_range": (60.00, 180.00),
        "cost_pct": 0.45,
        "gender_options": ["Women's", "Men's", "Unisex"],
        "subcategories": ["Sneakers", "Boots", "Sandals"],
    },
    "Accessories": {
        "sku_count": 40,
        "price_range": (15.00, 65.00),
        "cost_pct": 0.30,
        "gender_options": ["Women's", "Men's", "Unisex"],
        "subcategories": ["Bags", "Jewelry", "Belts", "Hats", "Scarves"],
    },
}

EXPECTED_ROW_COUNT = sum(plan["sku_count"] for plan in CATEGORY_PLAN.values())  # 180, derived not hardcoded
VALID_CATEGORIES = set(CATEGORY_PLAN.keys())
VALID_GENDERS = {"Women's", "Men's", "Unisex"}

# One representative noun per subcategory, used only to build a simple,
# readable product_name (color + noun). Not a rich naming engine -- none
# of Phase 1's business questions need product names to carry more detail
# than category/subcategory/color already do as separate columns.
SUBCATEGORY_NOUN = {
    "Dresses": "Dress", "Tops": "Top", "Bottoms": "Pants", "Denim": "Jeans", "Knitwear": "Sweater",
    "Shirts": "Shirt", "Activewear": "Joggers",
    "Jackets": "Jacket", "Coats": "Coat", "Vests": "Vest",
    "Sneakers": "Sneakers", "Boots": "Boots", "Sandals": "Sandals",
    "Bags": "Handbag", "Jewelry": "Necklace", "Belts": "Belt", "Hats": "Hat", "Scarves": "Scarf",
}

COLOR_PALETTE = ["Black", "White", "Navy", "Grey", "Beige", "Olive", "Burgundy", "Denim Blue", "Camel", "Ivory"]

APPAREL_SIZES = ["XS", "S", "M", "L", "XL"]
FOOTWEAR_SIZES = [str(s) for s in range(6, 13)]  # US sizes 6-12

# Subcategories that don't carry a size at all (one-size / not size-tracked
# accessories) -- size is NULL for these, which schema.sql permits (size
# has no NOT NULL constraint). All five only ever appear under Accessories
# in CATEGORY_PLAN above, so this set and "category == Accessories" are
# currently equivalent, but the check is written against subcategory to
# stay correct even if a sized Accessories subcategory were ever added.
NO_SIZE_SUBCATEGORIES = {"Bags", "Jewelry", "Belts", "Hats", "Scarves"}

# Collection-season leaning per docs/data_generation_strategy.md Section 5:
# Spring Collection introduces new Womenswear/Menswear; Holiday Collection
# introduces gift-leaning Accessories/Outerwear. Footwear has no lean.
SPRING_SEASONS = ["Spring 2023", "Spring 2024", "Spring 2025"]
HOLIDAY_SEASONS = ["Holiday 2023", "Holiday 2024", "Holiday 2025"]
ALL_COLLECTION_SEASONS = SPRING_SEASONS + HOLIDAY_SEASONS
SPRING_LEANING_CATEGORIES = {"Womenswear", "Menswear"}
HOLIDAY_LEANING_CATEGORIES = {"Outerwear", "Accessories"}
VALID_COLLECTION_SEASONS = set(ALL_COLLECTION_SEASONS)

PRODUCT_ID_PATTERN = re.compile(r"^PRD-\d{4}$")

COLUMN_ORDER = [
    "product_key", "product_id", "product_name", "category", "subcategory",
    "gender", "size", "color", "collection_season", "list_price", "unit_cost", "is_active",
]


def build_dataframe(seed: int = RANDOM_SEED) -> pd.DataFrame:
    """
    Builds all 180 Dim_Product rows from CATEGORY_PLAN.

    Why a locally-scoped `Random(seed)` instance instead of the global
    `random` module: this generator may eventually run in the same
    Python process as other generators (e.g. a future orchestration
    script that builds every dimension in one pass). If this function
    called module-level `random.seed()` / `random.choice()`, its output
    would depend on what other code had already called `random`
    elsewhere in that process -- an easy way to lose reproducibility
    without noticing. A `Random(seed)` instance is self-contained: this
    function's output depends only on `seed`, never on call order or any
    other code's use of randomness. This is the pattern any future
    generator needing randomness should follow (see ED-006).

    Determinism note: everything in validate_dataframe() checks
    properties that hold for ANY seed (row counts per category, valid
    ranges, cross-field consistency) -- not just seed=42's specific
    output. That's deliberate: a validation suite that only passes for
    one particular seed's output isn't really validating the business
    rules, it's just checking today's random draw.
    """
    rng = Random(seed)
    rows = []
    product_key = 1

    for category, plan in CATEGORY_PLAN.items():
        for _ in range(plan["sku_count"]):
            subcategory = rng.choice(plan["subcategories"])
            gender = rng.choice(plan["gender_options"])
            color = rng.choice(COLOR_PALETTE)

            if subcategory in NO_SIZE_SUBCATEGORIES:
                size = None
            elif category == "Footwear":
                size = rng.choice(FOOTWEAR_SIZES)
            else:
                size = rng.choice(APPAREL_SIZES)

            if category in SPRING_LEANING_CATEGORIES:
                collection_season = rng.choice(SPRING_SEASONS)
            elif category in HOLIDAY_LEANING_CATEGORIES:
                collection_season = rng.choice(HOLIDAY_SEASONS)
            else:
                collection_season = rng.choice(ALL_COLLECTION_SEASONS)

            low, high = plan["price_range"]
            list_price = round(rng.uniform(low, high), 2)
            unit_cost = round(list_price * plan["cost_pct"], 2)

            rows.append({
                "product_key": product_key,
                "product_id": f"PRD-{product_key:04d}",
                "product_name": f"{color} {SUBCATEGORY_NOUN[subcategory]}",
                "category": category,
                "subcategory": subcategory,
                "gender": gender,
                "size": size,
                "color": color,
                "collection_season": collection_season,
                "list_price": list_price,
                "unit_cost": unit_cost,
                "is_active": True,
            })
            product_key += 1

    return pd.DataFrame(rows, columns=COLUMN_ORDER)


def validate_dataframe(df: pd.DataFrame) -> None:
    """
    Business-rule validation performed in memory, before anything is
    written to disk or the database.

    This is the largest, richest dimension built so far (12 columns,
    5 categories each with their own valid subcategory/gender/price-range
    rules), so this function is deliberately the most thorough validation
    suite in Phase 3 to date -- matched to the table's actual complexity,
    not scaled down because "it's just a product list."

    Every failure raises a descriptive ValueError -- never `assert`, per
    ED-003.
    """
    if df.empty:
        raise ValueError(f"Dim_Product DataFrame is empty -- expected exactly {EXPECTED_ROW_COUNT} rows.")

    row_count = len(df)
    if row_count != EXPECTED_ROW_COUNT:
        raise ValueError(
            f"Dim_Product row count {row_count} does not match the exact expected "
            f"count of {EXPECTED_ROW_COUNT} (sum of CATEGORY_PLAN sku_count values) -- "
            f"the category plan and the generated rows have drifted apart."
        )

    # --- Surrogate key integrity -----------------------------------------
    if df["product_key"].isnull().any():
        raise ValueError("product_key contains nulls -- every row must have a surrogate key.")
    if not df["product_key"].is_unique:
        raise ValueError("product_key must be unique -- found duplicate surrogate keys.")

    expected_keys = set(range(1, row_count + 1))
    actual_keys = set(df["product_key"])
    if actual_keys != expected_keys:
        raise ValueError(
            "product_key must be a contiguous sequence starting at 1 (this is what "
            f"Fact_Order_Lines.product_key and Fact_Returns.product_key will later "
            f"reference) -- found a mismatch: {sorted(actual_keys ^ expected_keys)}"
        )

    # --- Natural key integrity --------------------------------------------
    if df["product_id"].isnull().any():
        raise ValueError("product_id contains nulls -- every row must have a natural key.")
    if not df["product_id"].is_unique:
        raise ValueError("product_id must be unique -- found duplicate natural keys.")
    bad_ids = df.loc[~df["product_id"].astype(str).str.match(PRODUCT_ID_PATTERN), "product_id"].tolist()
    if bad_ids:
        raise ValueError(f"product_id values must match the pattern PRD-#### (4 digits): {bad_ids}")

    # --- NOT NULL columns (size and color are nullable in schema.sql; size
    #     is intentionally NULL for no-size subcategories, checked separately
    #     below; color is always populated by this generator, checked below
    #     as a generator-level expectation, not a schema requirement) -------
    required_not_null = [
        "product_name", "category", "subcategory", "gender",
        "collection_season", "list_price", "unit_cost", "is_active",
    ]
    for col in required_not_null:
        if df[col].isnull().any():
            raise ValueError(
                f"Column '{col}' contains nulls, which violates the NOT NULL "
                f"constraint defined for Dim_Product in schema.sql."
            )
    if df["color"].isnull().any():
        raise ValueError(
            "color contains nulls -- schema.sql permits this, but this generator "
            "always assigns a color from COLOR_PALETTE, so a null here indicates a "
            "gap in the sampling logic, not an intentional NULL."
        )

    # --- Enum membership -------------------------------------------------
    invalid_categories = set(df["category"]) - VALID_CATEGORIES
    if invalid_categories:
        raise ValueError(f"Found category values outside CATEGORY_PLAN: {invalid_categories}")

    invalid_genders = set(df["gender"]) - VALID_GENDERS
    if invalid_genders:
        raise ValueError(f"Found gender values outside the valid set {VALID_GENDERS}: {invalid_genders}")

    invalid_seasons = set(df["collection_season"]) - VALID_COLLECTION_SEASONS
    if invalid_seasons:
        raise ValueError(f"Found collection_season values outside the valid set: {invalid_seasons}")

    # --- Per-category cross-field business rules --------------------------
    # These check the generated OUTPUT against CATEGORY_PLAN's own rules --
    # same "output cross-check against the canonical source" philosophy
    # used in every prior phase's validate_dataframe(), applied here across
    # more dimensions at once (subcategory, gender, price, cost, season)
    # because this table has more business rules to violate.
    for category, plan in CATEGORY_PLAN.items():
        category_rows = df[df["category"] == category]

        actual_count = len(category_rows)
        if actual_count != plan["sku_count"]:
            raise ValueError(
                f"Category '{category}' has {actual_count} rows, expected exactly "
                f"{plan['sku_count']} per CATEGORY_PLAN."
            )

        invalid_subcats = set(category_rows["subcategory"]) - set(plan["subcategories"])
        if invalid_subcats:
            raise ValueError(
                f"Category '{category}' has subcategory value(s) not in its allowed "
                f"list {plan['subcategories']}: {invalid_subcats}"
            )

        invalid_genders_for_cat = set(category_rows["gender"]) - set(plan["gender_options"])
        if invalid_genders_for_cat:
            raise ValueError(
                f"Category '{category}' has gender value(s) not in its allowed "
                f"options {plan['gender_options']}: {invalid_genders_for_cat}"
            )

        low, high = plan["price_range"]
        out_of_range = category_rows[(category_rows["list_price"] < low) | (category_rows["list_price"] > high)]
        if not out_of_range.empty:
            raise ValueError(
                f"Category '{category}' has {len(out_of_range)} row(s) with list_price "
                f"outside its documented range ${low}-${high}: "
                f"{out_of_range[['product_id', 'list_price']].to_string(index=False)}"
            )

        expected_cost = (category_rows["list_price"] * plan["cost_pct"]).round(2)
        cost_mismatches = category_rows[(category_rows["unit_cost"] - expected_cost).abs() > 0.01]
        if not cost_mismatches.empty:
            raise ValueError(
                f"Category '{category}' has {len(cost_mismatches)} row(s) where unit_cost "
                f"doesn't match list_price x {plan['cost_pct']} within rounding tolerance: "
                f"{cost_mismatches[['product_id', 'list_price', 'unit_cost']].to_string(index=False)}"
            )

        if category in SPRING_LEANING_CATEGORIES:
            allowed_seasons = set(SPRING_SEASONS)
        elif category in HOLIDAY_LEANING_CATEGORIES:
            allowed_seasons = set(HOLIDAY_SEASONS)
        else:
            allowed_seasons = set(ALL_COLLECTION_SEASONS)
        bad_seasons = set(category_rows["collection_season"]) - allowed_seasons
        if bad_seasons:
            raise ValueError(
                f"Category '{category}' has collection_season value(s) outside its "
                f"documented lean {sorted(allowed_seasons)}: {bad_seasons}"
            )

    # --- Size business rule: NULL iff no-size subcategory, else from the
    #     correct size vocabulary for the row's category --------------------
    size_violations = []
    for row in df.itertuples():
        if row.subcategory in NO_SIZE_SUBCATEGORIES:
            if row.size is not None and not pd.isna(row.size):
                size_violations.append((row.product_id, row.subcategory, row.size, "expected NULL"))
        elif row.category == "Footwear":
            if row.size not in FOOTWEAR_SIZES:
                size_violations.append((row.product_id, row.subcategory, row.size, f"expected one of {FOOTWEAR_SIZES}"))
        else:
            if row.size not in APPAREL_SIZES:
                size_violations.append((row.product_id, row.subcategory, row.size, f"expected one of {APPAREL_SIZES}"))
    if size_violations:
        raise ValueError(f"size business rule violations (product_id, subcategory, actual_size, expected): {size_violations}")

    # --- Sanity: unit_cost must never reach or exceed list_price ------------
    bad_margin = df[df["unit_cost"] >= df["list_price"]]
    if not bad_margin.empty:
        raise ValueError(
            f"Found {len(bad_margin)} row(s) where unit_cost >= list_price, which "
            f"would mean zero or negative margin: "
            f"{bad_margin[['product_id', 'list_price', 'unit_cost']].to_string(index=False)}"
        )

    # --- MVP scope: every product should be active in this initial generation ---
    if not df["is_active"].all():
        raise ValueError("Expected every row's is_active to be True in this initial generation.")


def write_csv(df: pd.DataFrame) -> Path:
    """
    Writes the already-validated DataFrame to data/generated/dim_product.csv.

    Kept as a durable, human-inspectable artifact independent of the
    database load, same rationale as every prior phase's write_csv().
    """
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    return CSV_PATH


def load_to_duckdb(df: pd.DataFrame) -> int:
    """
    Loads the validated DataFrame into Dim_Product inside a single
    explicit transaction.

    Identical pattern to every prior phase's load_to_duckdb() (ED-004):
    DELETE + INSERT wrapped in BEGIN TRANSACTION / COMMIT, row count
    checked before commit, explicit ROLLBACK on any mismatch or
    exception, connection always closed in `finally`.

    Note: schema.sql's CHECK (list_price >= 0) and CHECK (unit_cost >= 0)
    constraints are a second, database-level line of defense -- always
    satisfied by construction here since CATEGORY_PLAN's price ranges and
    cost percentages are all positive, but they remain in place as a
    backstop for any future load path that bypasses this generator.

    Raises FileNotFoundError if the database file doesn't exist yet.
    """
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"{DB_PATH} does not exist. Apply sql/schema.sql to this path first "
            f"to create the empty table structure before loading Dim_Product."
        )

    expected_row_count = len(df)
    con = duckdb.connect(str(DB_PATH))
    transaction_open = False
    try:
        con.execute("BEGIN TRANSACTION")
        transaction_open = True

        con.execute("DELETE FROM Dim_Product")
        con.execute(f"""
            INSERT INTO Dim_Product ({", ".join(COLUMN_ORDER)})
            SELECT {", ".join(COLUMN_ORDER)} FROM df
        """)

        actual_row_count = con.execute("SELECT COUNT(*) FROM Dim_Product").fetchone()[0]
        if actual_row_count != expected_row_count:
            con.execute("ROLLBACK")
            transaction_open = False
            raise ValueError(
                f"Row count mismatch after load: expected {expected_row_count}, "
                f"got {actual_row_count}. Transaction rolled back -- Dim_Product "
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
    print(f"Loaded {row_count} rows into Dim_Product at {DB_PATH}")


if __name__ == "__main__":
    main()
