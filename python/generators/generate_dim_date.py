"""
Phase 3.1 — Dim_Date generator.

Populates every calendar date from 2023-01-01 through 2025-12-31
(1,096 rows: 365 + 366 [2024 is a leap year] + 365). Every column is a
fully deterministic function of the calendar date — this is the one
table in the entire project with zero randomness, so "reproducible"
here simply means "produces the identical result every run," no random
seed required.

Outputs:
    data/dim_date.csv            — generated rows, source for sql/load_dim_date.sql
    data/solstice_apparel.duckdb — Dim_Date table populated directly

Run:
    python python/generators/generate_dim_date.py

Prerequisite: sql/schema.sql must already have been run once against
data/solstice_apparel.duckdb so the (empty) Dim_Date table exists.
"""

import sys
from pathlib import Path
from datetime import datetime, timedelta

import duckdb
import pandas as pd

sys.path.append(str(Path(__file__).parent))
from campaign_calendar_reference import get_campaign_windows, get_us_retail_holidays

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = PROJECT_ROOT / "data"
DB_PATH = DATA_DIR / "database" / "solstice_apparel.duckdb"
CSV_PATH = DATA_DIR / "generated" / "dim_date.csv"

START_DATE = datetime(2023, 1, 1).date()
END_DATE = datetime(2025, 12, 31).date()
EXPECTED_ROW_COUNT = 1096  # 365 (2023) + 366 (2024, leap year) + 365 (2025)

SEASON_BY_MONTH = {
    12: "Winter", 1: "Winter", 2: "Winter",
    3: "Spring", 4: "Spring", 5: "Spring",
    6: "Summer", 7: "Summer", 8: "Summer",
    9: "Fall", 10: "Fall", 11: "Fall",
}

# Column order matches sql/schema.sql's Dim_Date definition exactly.
COLUMN_ORDER = [
    "date_key", "full_date", "year", "quarter", "month", "month_name",
    "week_of_year", "day_of_week", "day_name", "is_weekend", "holiday_flag",
    "fiscal_quarter", "fiscal_year", "season", "campaign_period_flag",
]


def build_dim_date() -> pd.DataFrame:
    holidays = get_us_retail_holidays()
    campaign_windows = get_campaign_windows()

    rows = []
    current = START_DATE
    while current <= END_DATE:
        iso_year, iso_week, iso_weekday = current.isocalendar()

        is_weekend = current.isoweekday() in (6, 7)  # Saturday=6, Sunday=7
        holiday_flag = current in holidays
        campaign_period_flag = any(
            w["start_date"] <= current <= w["end_date"] for w in campaign_windows
        )
        quarter = (current.month - 1) // 3 + 1

        rows.append({
            "date_key": int(current.strftime("%Y%m%d")),
            "full_date": current,
            "year": current.year,
            "quarter": quarter,
            "month": current.month,
            "month_name": current.strftime("%B"),
            "week_of_year": iso_week,
            "day_of_week": current.isoweekday(),       # 1=Monday ... 7=Sunday
            "day_name": current.strftime("%A"),
            "is_weekend": is_weekend,
            "holiday_flag": holiday_flag,
            "fiscal_quarter": quarter,                  # fiscal year = calendar year, documented assumption
            "fiscal_year": current.year,
            "season": SEASON_BY_MONTH[current.month],
            "campaign_period_flag": campaign_period_flag,
        })
        current += timedelta(days=1)

    df = pd.DataFrame(rows, columns=COLUMN_ORDER)
    return df


def validate_in_memory(df: pd.DataFrame) -> None:
    """Perform in-memory validation before writing data to disk or DuckDB.
    Raises: ValueError: If any validation rule fails."""
    if len(df) != EXPECTED_ROW_COUNT:
        raise ValueError(
            f"Expected {EXPECTED_ROW_COUNT} rows but found {len(df)}."
        )

    if not df["date_key"].is_unique:
        raise ValueError("date_key values must be unique.")

    if df["full_date"].min() != START_DATE:
        raise ValueError(
            f"Expected first date {START_DATE} but found {df['full_date'].min()}."
        )

    if df["full_date"].max() != END_DATE:
        raise ValueError(
            f"Expected last date {END_DATE} but found {df['full_date'].max()}."
        )

    if df["full_date"].nunique() != EXPECTED_ROW_COUNT:
        raise ValueError(
            "Calendar contains missing or duplicate dates."
        )

    if df.isnull().any().any():
        raise ValueError(
            "Dim_Date contains NULL values."
        )

    print(
        f"In-memory validation passed: "
        f"{len(df)} rows, "
        f"{df['date_key'].nunique()} unique date_keys."
    )


def load_to_duckdb(df: pd.DataFrame) -> None:
    """
    Load the generated Dim_Date DataFrame into DuckDB.

    The load is wrapped in a database transaction so that either the
    entire operation succeeds or the database is returned to its
    previous state if an error occurs.
    """

    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"{DB_PATH} does not exist. "
            "Run python/generators/init_database.py first."
        )

    con = duckdb.connect(str(DB_PATH))

    try:
        con.execute("BEGIN TRANSACTION")

        # Remove existing rows
        con.execute("DELETE FROM Dim_Date")

        # Load freshly generated rows
        con.execute(
            f"""
            INSERT INTO Dim_Date ({", ".join(COLUMN_ORDER)})
            SELECT {", ".join(COLUMN_ORDER)}
            FROM df
            """
        )

        row_count = con.execute(
            "SELECT COUNT(*) FROM Dim_Date"
        ).fetchone()[0]

        if row_count != EXPECTED_ROW_COUNT:
            raise ValueError(
                f"Expected {EXPECTED_ROW_COUNT} rows after load, "
                f"but found {row_count}."
            )

        con.execute("COMMIT")

        print(
            f"Loaded {row_count} rows into Dim_Date "
            f"at {DB_PATH}"
        )

    except Exception:
        con.execute("ROLLBACK")
        raise

    finally:
        con.close()


def main():
    df = build_dim_date()
    validate_in_memory(df)

    (DATA_DIR / "database").mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "generated").mkdir(parents=True, exist_ok=True)
    df.to_csv(CSV_PATH, index=False)
    print(f"Wrote {CSV_PATH}")

    load_to_duckdb(df)


if __name__ == "__main__":
    main()
