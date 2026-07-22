"""
Analytics-layer validation runner (generalized).

Supersedes the phase-specific run_phase5_validation.py: this runner validates
the ENTIRE analytics layer under sql/analytics/ — every section file, Phase 5
(A–G) and Phase 6 (RFM, cohort, CLV, Pareto, behavioral, synthesis) alike —
so one command re-verifies that all analytics still reconcile to the certified
warehouse. It reuses the certified KPI anchors and the Type A / Type B
validation methodology established in Phase 5.

A validation query is any statement selecting a `regression_result` column
('PASS'/'FAIL'). Analytical queries and view-creation statements are executed
too (so an error surfaces loudly, per ED-003) but only verdict-bearing queries
count toward the tally.

Read-only. Explicit exceptions, never assert. No new engineering decision —
this is the Phase 5 runner pattern generalized to the whole layer.

Run:
    python python/validation/run_analytics_validation.py
"""

import glob
import sys
from datetime import datetime, timezone
from pathlib import Path

import duckdb

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"
ANALYTICS_DIR = PROJECT_ROOT / "sql" / "analytics"

SECTION_TITLES = {
    "01": "A — Executive KPI Summary",
    "02": "B — Revenue Analysis",
    "03": "C — Product Performance",
    "04": "D — Geographic Performance",
    "05": "E — Marketing Performance & Acquisition Quality",
    "06": "F — Customer Value & Retention",
    "07": "G — Returns & Value Leakage",
    "08": "6.1 — RFM Segmentation",
    "09": "6.2 — Cohort Analytics",
    "10": "6.3 — Historical CLV",
    "11": "6.4 — Pareto & Concentration",
    "12": "6.5 — Behavioral Analytics",
    "13": "6.6 — Customer Portfolio Synthesis",
}


def strip_sql_comments(raw: str) -> str:
    return "\n".join(line for line in raw.splitlines() if not line.strip().startswith("--"))


def split_statements(code: str) -> list:
    return [s.strip() for s in code.split(";") if s.strip()]


def read_sql_utf8(sql_path: Path) -> str:
    """
    Read an analytics SQL file as UTF-8 explicitly.

    The repository standard is UTF-8: the analytics SQL files contain Unicode
    characters (box-drawing headers, em dashes, arrows, approximation symbols).
    Path.read_text() without an explicit encoding uses the platform default
    (e.g. cp1252 on Windows), which cannot decode these bytes and raises a
    UnicodeDecodeError before any SQL runs. Pinning UTF-8 makes the runner
    portable across platforms; a decode failure is turned into a clear,
    actionable RuntimeError rather than an opaque codec traceback.
    """
    try:
        return sql_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise RuntimeError(
            f"{sql_path.name} is not valid UTF-8: {exc}. "
            "Analytics SQL files must be UTF-8 encoded (the repository standard). "
            "Re-save the file as UTF-8 and re-run."
        ) from exc


def run_section(con, sql_path: Path) -> dict:
    statements = split_statements(strip_sql_comments(read_sql_utf8(sql_path)))
    passed = failed = 0
    failures = []
    for stmt in statements:
        try:
            cursor = con.execute(stmt)
        except Exception as exc:
            raise ValueError(f"{sql_path.name}: a query failed to execute: {exc}") from exc
        columns = [d[0] for d in cursor.description] if cursor.description else []
        if "regression_result" not in columns:
            if cursor.description:
                cursor.fetchall()
            continue
        idx = columns.index("regression_result")
        for row in cursor.fetchall():
            if row[idx] == "PASS":
                passed += 1
            else:
                failed += 1
                failures.append({"file": sql_path.name, "row": dict(zip(columns, row))})
    return {"passed": passed, "failed": failed, "failures": failures}


def main():
    if not DB_PATH.exists():
        raise FileNotFoundError(f"{DB_PATH} does not exist. Build and certify the warehouse first.")
    section_files = sorted(glob.glob(str(ANALYTICS_DIR / "[0-9][0-9]_*.sql")))
    if not section_files:
        raise FileNotFoundError(f"No analytics section files under {ANALYTICS_DIR}.")

    con = duckdb.connect(str(DB_PATH), read_only=True)
    total_pass = total_fail = 0
    all_failures = []
    try:
        print("Analytics Layer Validation (Phases 5–6)")
        print(f"{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')} · warehouse v1.0.0 (frozen)")
        print("-" * 64)
        for fp in section_files:
            path = Path(fp)
            res = run_section(con, path)
            total_pass += res["passed"]
            total_fail += res["failed"]
            all_failures.extend(res["failures"])
            title = SECTION_TITLES.get(path.name[:2], path.name)
            tag = "OK" if res["failed"] == 0 else f"{res['failed']} FAIL"
            n = res["passed"] + res["failed"]
            print(f"  {title:52s} {res['passed']:>2}/{n:>2}  {tag}")
    finally:
        con.close()

    print("-" * 64)
    total = total_pass + total_fail
    print(f"  {total_pass}/{total} validations passed")
    if all_failures:
        print("\nFAILURES:")
        for f in all_failures:
            print(f"  {f['file']}: {f['row']}")
        return 1
    print("  Analytics layer reconciles to the certified warehouse. ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
