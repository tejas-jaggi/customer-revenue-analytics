# SQL Analytics Layer — Phase 5

Business-facing analytical SQL for the certified Solstice Apparel warehouse (v1.0.0, frozen). Each section is a self-contained, independently-reviewable module; every query carries a 13-field documentation header and exactly one validation.

## Why a README index (not a monolithic `analytics.sql`)

The continuation doc originally specified a single `sql/analytics.sql`. This layer is instead split into section files, mirroring the repository's existing `sql/{generation,validation,verification}/` convention. A README index is the better navigation artifact here because it does what a concatenated `.sql` file cannot: it maps each file to the **business question it answers** and the **executive who asked it**, so a reviewer can navigate by intent rather than scrolling hundreds of lines. The section files remain the single source of truth; this index only points into them.

## Sections

| File | Section | Business Question | Stakeholder | Validations |
|---|---|---|---|---|
| `01_executive_kpi_summary.sql` | A — Executive KPI Summary | How is the business performing overall? | CFO | 7 |
| `02_revenue_analysis.sql` | B — Revenue Analysis | Where is revenue coming from, and how is it growing? | CFO | 8 |
| `03_product_performance.sql` | C — Product Performance | Which products and categories create *value* (not just revenue)? | Merchandising | 6 |
| `04_geographic_performance.sql` | D — Geographic Performance | Where does the business over/under-perform geographically? | COO | 5 |
| `05_marketing_performance.sql` | E — Marketing Performance & Acquisition Quality | Which channels acquire the most *valuable* customers? | VP Marketing | 6 |
| `06_customer_value_retention.sql` | F — Customer Value & Retention | Who creates value, and why do repeats drive 82.4%? | Retention / CFO | 6 |
| `07_returns_value_leakage.sql` | G — Returns & Value Leakage | Where is value leaking, and what should be fixed first? | COO / CFO | 7 |
| | | | **Total** | **45** |

## Running the analytics

The section files are read-only analytical SQL against `data/database/solstice_apparel.duckdb`. To re-verify that the whole layer still reconciles to the certified warehouse:

```bash
python python/validation/run_phase5_validation.py
# → 45/45 validations passed
```

## Governing rules (see `docs/phase5_build_log.md`)

- **P5-1** — the seven Phase 4 certified KPIs are permanent regression anchors; any query reproducing one must match it.
- **P5-2** — every query carries exactly one validation: **Type A** (regression vs a certified anchor) or **Type B** (independent recomputation).
- **P5-3** — every query declares its **Metric Basis** and **Analysis Grain** — the additivity firewall against the 1.291× Orders→Lines fan-out.

## Supporting documentation

- `docs/phase5_analytics_report.md` — the business-facing readout (what each section found and what it means).
- `docs/phase5_build_log.md` — build evidence, methodology, and the 13-field query template.
- `docs/phase5_cross_section_insights.md` — the Resolved/Open/Deferred insight tracker.
- `docs/phase5_executive_findings_matrix.md` — the consolidated findings matrix (input to the Executive Synthesis).
