"""
Phase 4 - Warehouse validation runner.

Phase 3 validated each table against its specification.
Phase 4 validates the warehouse against itself.

Executes every Phase 4 validation suite plus the Dim_Date smoke test
created in this phase, classifies each check by tier and severity, and
writes docs/phase4_validation_report.md -- including the final warehouse
certification summary that answers, at a glance, "can this warehouse be
trusted for analytics?"

Check metadata is declared inline in the SQL itself:

    -- @CHECK: id=1.1; tier=1; severity=BLOCKING; name=...

so a check and its own classification can never drift apart in two files.

Severity semantics:
    BLOCKING  -- a non-PASS blocks the Phase Gate.
    ADVISORY  -- a non-PASS is recorded as a FINDING, not a failure. An
                 unused campaign is intelligence for Phase 8; a narrative
                 claim the data contradicts is a business finding whose
                 documented resolution is to update the narrative, never
                 to modify generated data to satisfy it.

Engineering standards (unchanged): ED-003 explicit exceptions, never
`assert`; ED-011 shared db_utils is not used here because this runner
reads no dimension lookups -- it executes SQL files and reports. No new
engineering decision is introduced by this phase.

Run:
    python python/validation/run_warehouse_validation.py
"""

import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import duckdb

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DB_PATH = PROJECT_ROOT / "data" / "database" / "solstice_apparel.duckdb"
REPORT_PATH = PROJECT_ROOT / "docs" / "phase4_validation_report.md"

SUITES = [
    ("Dim_Date smoke test (gap closed in Phase 4)", PROJECT_ROOT / "sql" / "verification" / "smoke_test_dim_date.sql"),
    ("Warehouse Integrity (Tier 0-1)", PROJECT_ROOT / "sql" / "validation" / "validate_warehouse_integrity.sql"),
    ("Warehouse Reconciliation (Tier 2-3)", PROJECT_ROOT / "sql" / "validation" / "validate_warehouse_reconciliation.sql"),
    ("Warehouse Readiness (Tier 4-6)", PROJECT_ROOT / "sql" / "validation" / "validate_warehouse_readiness.sql"),
]

TIER_NAMES = {
    "SMOKE": "Dim_Date Smoke Test (historical gap closed in Phase 4)",
    "0": "Tier 0 - Structural Integrity",
    "1": "Tier 1 - Vintage Coherence",
    "2": "Tier 2 - Cross-Grain Aggregate Reconciliation",
    "3": "Tier 3 - KPI Reconciliation",
    "4a": "Tier 4a - Structural Completeness",
    "4b": "Tier 4b - Business Observations",
    "5": "Tier 5 - Business Narrative / Executive Sanity",
    "6": "Tier 6 - Analytical Readiness",
}
TIER_ORDER = ["SMOKE", "0", "1", "2", "3", "4a", "4b", "5", "6"]

CHECK_MARKER = "-- @CHECK:"


def parse_checks(sql_path: Path) -> list:
    """
    Extracts (metadata, sql) pairs from an annotated suite.

    Raises FileNotFoundError / ValueError explicitly rather than using
    assert (ED-003) -- a malformed suite must fail loudly, not silently
    validate nothing, which is exactly the failure mode ED-003 exists to
    prevent.
    """
    if not sql_path.exists():
        raise FileNotFoundError(f"Validation suite not found: {sql_path}")

    lines = sql_path.read_text().splitlines()
    checks = []
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped.startswith(CHECK_MARKER):
            meta_raw = stripped[len(CHECK_MARKER):].strip()
            meta = {}
            for part in meta_raw.split(";"):
                if "=" in part:
                    k, v = part.split("=", 1)
                    meta[k.strip()] = v.strip()
            for required in ("id", "tier", "severity", "name"):
                if required not in meta:
                    raise ValueError(f"{sql_path.name}: @CHECK near line {i+1} is missing '{required}'. Metadata: {meta_raw}")

            sql_lines = []
            j = i + 1
            while j < len(lines):
                sql_lines.append(lines[j])
                if lines[j].rstrip().endswith(";"):
                    break
                j += 1
            if not sql_lines or not sql_lines[-1].rstrip().endswith(";"):
                raise ValueError(f"{sql_path.name}: @CHECK {meta['id']} has no terminating ';'.")
            checks.append((meta, "\n".join(sql_lines).rstrip().rstrip(";")))
            i = j + 1
        else:
            i += 1

    if not checks:
        raise ValueError(f"{sql_path.name} contains no @CHECK-annotated statements -- nothing would be validated.")
    return checks


def run_suite(con, suite_name: str, sql_path: Path) -> list:
    """Executes every check in a suite and returns structured results."""
    results = []
    for meta, sql in parse_checks(sql_path):
        try:
            cursor = con.execute(sql)
            columns = [d[0] for d in cursor.description]
            rows = cursor.fetchall()
        except Exception as exc:
            raise ValueError(f"{sql_path.name}: check {meta['id']} failed to execute: {exc}") from exc

        if "result" not in columns:
            raise ValueError(
                f"{sql_path.name}: check {meta['id']} returned no 'result' column. Every Phase 4 check must "
                f"state its own verdict explicitly rather than leaving interpretation to the runner."
            )
        if not rows:
            raise ValueError(f"{sql_path.name}: check {meta['id']} returned no rows -- it cannot state a verdict.")

        result_idx = columns.index("result")
        verdicts = {row[result_idx] for row in rows}
        status = "PASS" if verdicts == {"PASS"} else ("FINDING" if verdicts <= {"PASS", "FINDING"} else "FAIL")

        detail_cols = [c for c in columns if c != "result"]
        detail = "; ".join(
            f"{c}={rows[0][columns.index(c)]}" for c in detail_cols
        ) if detail_cols and len(rows) == 1 else f"{len(rows)} row(s)"

        results.append({
            "suite": suite_name,
            "id": meta["id"],
            "tier": meta["tier"],
            "severity": meta["severity"],
            "name": meta["name"],
            "status": status,
            "detail": detail,
        })
    return results


def build_report(results: list) -> str:
    total = len(results)
    passed = sum(1 for r in results if r["status"] == "PASS")
    findings = [r for r in results if r["status"] == "FINDING"]
    blocking_failures = [r for r in results if r["status"] == "FAIL" and r["severity"] == "BLOCKING"]
    advisory_failures = [r for r in results if r["status"] == "FAIL" and r["severity"] == "ADVISORY"]
    certified = not blocking_failures and not advisory_failures

    out = []
    out.append("# Phase 4 — Warehouse Validation Report")
    out.append("## Customer Revenue Analytics — Solstice Apparel")
    out.append("")
    out.append(f"*Generated by `python/validation/run_warehouse_validation.py` on "
               f"{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}. Re-runnable at any time — "
               f"this is the warehouse's standing health check, not a one-off audit.*")
    out.append("")
    out.append("> **Phase 3 validated each table against its specification.**")
    out.append("> **Phase 4 validates the warehouse against itself.**")
    out.append("")
    out.append("Every check below compares two independent derivations of the same truth, or asserts an "
               "invariant that must hold across tables. Nothing here re-runs a Phase 3 per-table check for its "
               "own sake: those questions are answered and stay answered.")
    out.append("")
    out.append("**Why almost everything here is exact:** this phase compares the warehouse to itself, not "
               "sampled data to a business target. A tolerance would only hide a defect. No ED-008 statistical "
               "tolerances appear in Phase 4 — those exist for sampled-vs-target comparisons and belong to "
               "Phase 3. The only latitude given is cent-level on large money aggregates, for the "
               "float/decimal reason Phase 3.11 documented.")
    out.append("")

    for tier in TIER_ORDER:
        tier_results = [r for r in results if r["tier"] == tier]
        if not tier_results:
            continue
        t_pass = sum(1 for r in tier_results if r["status"] == "PASS")
        out.append(f"## {TIER_NAMES[tier]}")
        out.append("")
        out.append(f"**{t_pass}/{len(tier_results)} PASS**")
        out.append("")
        out.append("| Check | Name | Severity | Status | Evidence |")
        out.append("|---|---|---|---|---|")
        for r in tier_results:
            icon = {"PASS": "✅ PASS", "FINDING": "📋 FINDING", "FAIL": "❌ FAIL"}[r["status"]]
            detail = r["detail"].replace("|", "\\|")
            out.append(f"| `{r['id']}` | {r['name']} | {r['severity']} | {icon} | {detail} |")
        out.append("")

    out.append("## Findings Register")
    out.append("")
    if findings:
        out.append("Advisory findings are **not defects**. They are business intelligence surfaced by "
                   "validation — an unused campaign, or a narrative claim the data contradicts. Per the Phase 4 "
                   "ruling, generated data is never modified to satisfy a narrative; the narrative is updated "
                   "to match the evidence.")
        out.append("")
        out.append("| Check | Finding | Evidence |")
        out.append("|---|---|---|")
        for r in findings:
            out.append(f"| `{r['id']}` | {r['name']} | {r['detail'].replace('|', chr(92) + '|')} |")
    else:
        out.append("No advisory findings.")
    out.append("")

    out.append("## Warehouse Certification Summary")
    out.append("")
    out.append("| Item | Result |")
    out.append("|---|---|")
    out.append("| Tables validated | **12** (8 dimensions + 4 facts) |")
    out.append(f"| Validation suites executed | **{len(SUITES)}** |")
    out.append(f"| Total validation checks | **{total}** |")
    out.append(f"| Passed | **{passed}** |")
    out.append(f"| Advisory findings | **{len(findings)}** |")
    out.append(f"| Blocking failures | **{len(blocking_failures)}** |")
    status_line = ("✅ **CERTIFIED — the warehouse can be trusted for analytics**"
                   if certified else
                   "❌ **NOT CERTIFIED — blocking failures must be resolved**")
    out.append(f"| **Overall warehouse certification status** | {status_line} |")
    out.append("")
    if certified:
        out.append("**Can this warehouse be trusted for analytics? Yes.** Referential integrity holds across all "
                   "17 fact-to-parent relationships at a single instant; every fact derives from the same vintage "
                   "of its parents; all four grains reconcile exactly; every KPI in `business_understanding.md` "
                   "resolves to one number by two or more independent derivations; and Phases 5, 6, 7 and 10 are "
                   "certified constructible on this data.")
    else:
        out.append("**Blocking failures present — see above.** Per the standing project rule, these are resolved "
                   "by fixing the warehouse or documenting a genuine business conflict, never by relaxing the check.")
    out.append("")
    return "\n".join(out)


def main():
    if not DB_PATH.exists():
        raise FileNotFoundError(f"{DB_PATH} does not exist. Build the warehouse before validating it.")

    con = duckdb.connect(str(DB_PATH), read_only=True)
    try:
        results = []
        for suite_name, sql_path in SUITES:
            suite_results = run_suite(con, suite_name, sql_path)
            p = sum(1 for r in suite_results if r["status"] == "PASS")
            print(f"{suite_name}: {p}/{len(suite_results)} PASS")
            results.extend(suite_results)
    finally:
        con.close()

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(build_report(results))

    blocking = [r for r in results if r["status"] == "FAIL"]
    findings = [r for r in results if r["status"] == "FINDING"]
    print()
    print(f"TOTAL: {len(results)} checks | {sum(1 for r in results if r['status']=='PASS')} passed | "
          f"{len(findings)} findings | {len(blocking)} blocking failures")
    print(f"Report written to {REPORT_PATH}")
    for r in blocking:
        print(f"  BLOCKING FAIL {r['id']}: {r['name']} -- {r['detail']}")
    for r in findings:
        print(f"  FINDING {r['id']}: {r['name']} -- {r['detail']}")
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
