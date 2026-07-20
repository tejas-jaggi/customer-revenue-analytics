# Customer Revenue Analytics — Solstice Apparel Co.
# Project Roadmap

## Project Status

**Current Version:** v1.0 — Certified Warehouse

This project builds a production-style analytical data warehouse for a fictional direct-to-consumer apparel company (Solstice Apparel Co.).

Unlike the Procurement Spend Intelligence project, which analyzes the supply side of the business, this project focuses entirely on customer analytics, revenue quality, retention, customer lifetime value, and growth.

The project follows a documentation-first, phase-gated engineering methodology where every phase must pass verification and validation before the next phase begins.

---

# Technology Stack

- DuckDB
- SQL
- Python
- Pandas
- VS Code
- Git
- GitHub
- Markdown

Power BI was originally planned but intentionally removed from scope to prioritize deeper SQL analytics and customer analytics while maintaining a realistic project timeline.

---

# Current Repository Status

| Phase | Status |
|--------|--------|
| Phase 1 – Business Understanding | ✅ Complete |
| Phase 2 – Data Warehouse Design | ✅ Complete |
| Phase 3 – Deterministic Synthetic Data Generation | ✅ Complete |
| Phase 4 – Warehouse-wide Validation & Certification | ✅ Complete |
| Phase 5 – SQL Analytics Layer | ⬜ Next |
| Phase 6 – Advanced Customer Analytics | ⬜ Planned |
| Phase 7 – Business Insights & Executive Recommendations | ⬜ Planned |
| Phase 8 – Repository & Portfolio Finalization | ⬜ Planned |
| Phase 9 – Churn Prediction (Stretch Goal) | ⬜ Planned |

---

# Project Objectives

Build a fully reproducible analytical warehouse capable of supporting:

- Revenue analysis
- Customer segmentation
- Retention analysis
- Cohort analysis
- Customer Lifetime Value (CLV)
- Pareto analysis
- Churn analysis
- Executive KPI reporting

while demonstrating production-quality engineering practices including:

- deterministic data generation
- dimensional modeling
- warehouse validation
- reproducibility
- documented engineering decisions
- analytical readiness

---

# Roadmap

## Phase 1 — Business Understanding ✅

Established:

- Business stakeholders
- Business questions
- KPIs
- Business glossary
- Solstice Apparel business context

Deliverables

- business_understanding.md

---

## Phase 2 — Warehouse Architecture ✅

Designed and documented:

- Fact constellation schema
- Eight dimensions
- Four fact tables
- Data dictionary
- Schema
- Engineering decisions

Deliverables

- schema.sql
- data_dictionary.md
- data_warehouse_design.md
- design_decisions.md
- schema_changelog.md

---

## Phase 3 — Synthetic Data Generation ✅

Implemented deterministic generators for:

### Dimensions

- Date
- Geography
- Marketing Channel
- Sales Channel
- Campaign
- Product
- Return Reason
- Customer

### Facts

- Orders
- Order Lines
- Returns
- Customer Monthly Snapshot

Generation characteristics:

- Deterministic
- Seed reproducible
- Transaction-safe
- Idempotent
- Fully documented

Deliverables

- Python generators
- SQL load scripts
- Verification suites
- Validation suites
- Build log

---

## Phase 4 — Warehouse Certification ✅

Warehouse-wide validation introduced:

- Structural integrity
- Vintage coherence
- Cross-grain reconciliation
- KPI reconciliation
- Analytical readiness

Final certification:

- 62 validation checks
- 60 PASS
- 2 advisory findings
- 0 blocking failures

Warehouse status:

**Certified for analytics.**

Deliverables

- Warehouse validation SQL
- Validation runner
- Phase 4 certification report

---

## Phase 5 — SQL Analytics Layer

Objective

Build business-facing analytical SQL answering executive questions.

Topics include:

- Revenue trends
- Channel performance
- Product performance
- Customer growth
- Geographic analysis
- Return analysis
- Executive KPI dashboard queries

Deliverables

- Reusable SQL analytics library
- Business query documentation

---

## Phase 6 — Advanced Customer Analytics

Build:

- RFM segmentation
- Customer Lifetime Value
- Cohort retention
- Pareto analysis
- Customer concentration
- Churn metrics

Deliverables

- Advanced SQL analysis
- Executive-ready analytical outputs

---

## Phase 7 — Business Insights

Translate analysis into business recommendations.

Focus areas:

- Marketing optimization
- Customer retention
- Revenue quality
- Product strategy
- Geographic expansion
- Return reduction

Deliverables

- Executive findings
- Business recommendations

---

## Phase 8 — Repository Finalization

Finalize the public portfolio repository.

Includes:

- Documentation review
- Repository audit
- GitHub release
- Screenshots
- Portfolio polish

Deliverables

- Production README
- Version 1.0 release
- Portfolio-ready repository

---

## Phase 9 — Churn Prediction (Stretch Goal)

Potential machine learning extension using the certified warehouse.

Possible work:

- Feature engineering
- Baseline models
- Model evaluation
- Business interpretation

This phase is intentionally optional and does not affect the completion of the warehouse project.

---

# Engineering Philosophy

Every phase follows the same workflow:

Design

↓

Implementation

↓

Verification

↓

Business Validation

↓

Evidence

↓

Phase Gate

No phase advances until the previous phase is successfully completed.

---

# Relationship to Procurement Spend Intelligence

| Procurement Spend Intelligence | Customer Revenue Analytics |
|-------------------------------|----------------------------|
| Supply-side analytics | Demand-side analytics |
| Procurement | Customer behavior |
| Supplier performance | Customer retention |
| Spend optimization | Revenue optimization |
| Supplier risk | Customer value |
| Procurement KPIs | Customer KPIs |

The two projects intentionally complement one another while demonstrating different analytical domains using the same engineering standards.

---

# Current Focus

The warehouse has been fully certified.

The next milestone is **Phase 5 — SQL Analytics**, where the certified warehouse begins producing business insights.