"""
Phase 5 — Analytics validation runner.

Phase 4 validated the warehouse. Phase 5 validates that the ANALYTICS LAYER
reproduces the certified numbers — every analytical query that recomputes a
certified KPI must match it (rule P5-1), and every query carries exactly one
validation: Type A (regression vs a certified anchor) or Type B (independent
recomputation) — rule P5-2.

This runner executes every validation query embedded in the Section A–G SQL
files and prints a concise pass summary (e.g. "45/45 validations passed"),
mirroring the re-runnable health-check philosophy of Phase 4's
run_warehouse_validation.py. It is the one-command way to re-verify that the
whole analytics layer still reconciles to the frozen warehouse.

A validation query is any statement in sql/analytics/*.sql that selects a
column named `regression_result` (value 'PASS' or 'FAIL'). The analytical
queries themselves (which return business results, not a verdict) are executed
too — so a query that errors is caught — but only the verdict-bearing queries
count toward the pass tally.

Explicit exceptions, never assert (ED-003). Read-only against the certified
warehouse. No new engineering decision: this composes the existing pattern.

Run:
    python python/validation/run_phase5_validation.py
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
}


def strip_sql_comments(raw: str) -> str:
    """Remove full-line -- comments so statements can be split on ';'."""
    return "\n".join(line for line in raw.splitlines() if not line.strip().startswith("--"))


def split_statements(code: str) -> list:
    return [s.strip() for s in code.split(";") if s.strip()]


def run_section(con, sql_path: Path) -> dict:
    """
    Executes every statement in a section file. Verdict-bearing statements
    (those with a `regression_result` column) are tallied; all statements are
    executed so a malformed query surfaces as an error rather than silently
    passing (the failure mode ED-003 exists to prevent).
    """
    raw = sql_path.read_text()
    statements = split_statements(strip_sql_comments(raw))

    passed = 0
    failed = 0
    failures = []
    for stmt in statements:
        try:
            cursor = con.execute(stmt)
        except Exception as exc:
            raise ValueError(f"{sql_path.name}: a query failed to execute: {exc}") from exc
        columns = [d[0] for d in cursor.description]
        if "regression_result" not in columns:
            cursor.fetchall()  # drain analytical query; not a verdict
            continue
        result_idx = columns.index("regression_result")
        for row in cursor.fetchall():
            verdict = row[result_idx]
            if verdict == "PASS":
                passed += 1
            else:
                failed += 1
                failures.append({"file": sql_path.name, "row": dict(zip(columns, row))})
    return {"passed": passed, "failed": failed, "failures": failures}


def main():
    if not DB_PATH.exists():
        raise FileNotFoundError(f"{DB_PATH} does not exist. Build and certify the warehouse first.")

    section_files = sorted(glob.glob(str(ANALYTICS_DIR / "0*.sql")))
    if not section_files:
        raise FileNotFoundError(f"No analytics section files found under {ANALYTICS_DIR}.")

    con = duckdb.connect(str(DB_PATH), read_only=True)
    total_pass = total_fail = 0
    all_failures = []
    try:
        print("Phase 5 — Analytics Layer Validation")
        print(f"{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')} · warehouse v1.0.0 (frozen)")
        print("-" * 60)
        for fp in section_files:
            path = Path(fp)
            prefix = path.name[:2]
            title = SECTION_TITLES.get(prefix, path.name)
            res = run_section(con, path)
            total_pass += res["passed"]
            total_fail += res["failed"]
            all_failures.extend(res["failures"])
            status = "OK" if res["failed"] == 0 else f"{res['failed']} FAIL"
            print(f"  Section {title:48s} {res['passed']:>2}/{res['passed']+res['failed']:>2}  {status}")
    finally:
        con.close()

    print("-" * 60)
    total = total_pass + total_fail
    print(f"  {total_pass}/{total} validations passed")
    if all_failures:
        print("\nFAILURES:")
        for f in all_failures:
            print(f"  {f['file']}: {f['row']}")
        return 1
    print("  Phase 5 analytics layer reconciles to the certified warehouse. ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
