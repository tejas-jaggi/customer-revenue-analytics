"""
Shared campaign calendar reference — Solstice Apparel.

This module is the single source of truth for the marketing campaign
calendar's date windows. It is consumed by two different generators:

  1. generate_dim_date.py      (Phase 3.1) — computes Dim_Date.campaign_period_flag
  2. generate_dim_campaign.py  (a later Phase 3.x) — populates Dim_Campaign itself

Defining the windows exactly once, here, guarantees the two tables can
never disagree about when a campaign ran. See docs/data_generation_strategy.md
Section 6 for the business rationale behind each campaign's timing.

Scope note (Phase 3.1): only campaign_name, campaign_type, start_date, and
end_date are populated here — enough for Dim_Date's boolean flag. The
richer fields Dim_Campaign needs (discount_depth, season, target_audience,
is_active_flag) are added when that table's own generator is built,
without changing any of the dates defined here.
"""

from datetime import datetime, timedelta

YEARS = [2023, 2024, 2025]


def _nth_weekday(year: int, month: int, weekday: int, n: int) -> datetime:
    """weekday: Monday=0 ... Sunday=6. Returns the date of the nth such weekday in the month."""
    first_day = datetime(year, month, 1)
    delta_days = (weekday - first_day.weekday()) % 7
    first_occurrence = first_day + timedelta(days=delta_days)
    return first_occurrence + timedelta(weeks=n - 1)


def _last_weekday(year: int, month: int, weekday: int) -> datetime:
    """weekday: Monday=0 ... Sunday=6. Returns the date of the last such weekday in the month."""
    next_month = datetime(year + 1, 1, 1) if month == 12 else datetime(year, month + 1, 1)
    last_day_of_month = next_month - timedelta(days=1)
    delta_days = (last_day_of_month.weekday() - weekday) % 7
    return last_day_of_month - timedelta(days=delta_days)


def get_campaign_windows() -> list[dict]:
    """
    Returns one dict per campaign instance — 7 named campaigns x 3 years = 21 rows:
        {campaign_name, campaign_type, start_date, end_date}
    All dates are Python `date` objects (not datetime).
    """
    windows = []
    for year in YEARS:
        thanksgiving = _nth_weekday(year, 11, 3, 4)          # 4th Thursday of November
        black_friday = thanksgiving + timedelta(days=1)
        cyber_monday = thanksgiving + timedelta(days=4)      # Thu + 4 days = Mon

        windows.extend([
            {
                "campaign_name": f"Spring Collection Launch {year}",
                "campaign_type": "Seasonal Launch",
                "start_date": datetime(year, 2, 15).date(),
                "end_date": datetime(year, 3, 15).date(),
            },
            {
                "campaign_name": f"Summer Sale {year}",
                "campaign_type": "Promotional Sale",
                "start_date": datetime(year, 7, 5).date(),
                "end_date": datetime(year, 7, 25).date(),
            },
            {
                "campaign_name": f"Back-to-School {year}",
                "campaign_type": "Promotional Sale",
                "start_date": datetime(year, 8, 1).date(),
                "end_date": datetime(year, 8, 21).date(),
            },
            {
                "campaign_name": f"Black Friday {year}",
                "campaign_type": "Promotional Sale",
                "start_date": black_friday.date(),
                "end_date": (black_friday + timedelta(days=2)).date(),   # Fri through Sun
            },
            {
                "campaign_name": f"Cyber Monday {year}",
                "campaign_type": "Promotional Sale",
                "start_date": cyber_monday.date(),
                "end_date": cyber_monday.date(),
            },
            {
                "campaign_name": f"Holiday Collection {year}",
                "campaign_type": "Seasonal Launch",
                # Nov 15 start (was Nov 1): revised during Phase 3.9
                # calibration. The original 54-day window x 3 years put
                # 39.8% of ALL calendar days inside some campaign window,
                # making data_generation_strategy.md Section 9's 30-40%
                # campaign-revenue-share target mathematically infeasible
                # with any positive campaign lift. The docs only specify
                # "Nov-Dec" -- the specific start day was always an
                # implementation choice, and Section 9 explicitly says to
                # fix generation parameters, not loosen targets.
                "start_date": datetime(year, 11, 15).date(),
                "end_date": datetime(year, 12, 24).date(),
            },
            {
                "campaign_name": f"January Clearance {year}",
                "campaign_type": "Clearance",
                "start_date": datetime(year, 1, 2).date(),
                "end_date": datetime(year, 1, 21).date(),
            },
        ])
    return windows


def get_us_retail_holidays() -> set:
    """
    Returns a set of `date` objects for the specific retail-holiday
    definition used by Dim_Date.holiday_flag, documented in
    docs/data_dictionary.md: New Year's Day, Memorial Day, Independence
    Day, Labor Day, Thanksgiving, Black Friday, and Christmas Day.

    Deliberately a retail-relevant subset, not the full US federal holiday
    calendar — days like MLK Day, Presidents Day, Columbus Day, and
    Veterans Day carry no meaningful retail demand signature for an
    apparel brand and are intentionally excluded.
    """
    holidays = set()
    for year in YEARS:
        thanksgiving = _nth_weekday(year, 11, 3, 4)
        black_friday = thanksgiving + timedelta(days=1)
        memorial_day = _last_weekday(year, 5, 0)   # last Monday of May
        labor_day = _nth_weekday(year, 9, 0, 1)     # first Monday of September

        holidays.update([
            datetime(year, 1, 1).date(),
            memorial_day.date(),
            datetime(year, 7, 4).date(),
            labor_day.date(),
            thanksgiving.date(),
            black_friday.date(),
            datetime(year, 12, 25).date(),
        ])
    return holidays
