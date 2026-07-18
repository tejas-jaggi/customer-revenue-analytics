# Customer Revenue Analytics — Solstice Apparel Co.
## Refined Project Roadmap

Same technology stack as procurement-spend-intelligence (DuckDB, VS Code, SQL, Python/Pandas, Power BI, Git, GitHub, Markdown). Business domain and analytical focus are deliberately different: this project is the customer/demand-side counterpart to procurement's supply-side analysis.

## Repository Structure

```
customer-revenue-analytics/
│
├── data/
├── sql/
│     schema.sql
│     data_generation.sql
│     validation.sql
│     analytics.sql
├── python/
│     validation.py
│     exploratory_analysis.py
├── ml/                        # Phase 10 stretch
│     churn_model.py
│     model_evaluation.py
├── dashboard/
├── docs/
│     business_understanding.md
│     project_roadmap.md
│     data_dictionary.md
│     assumptions.md
├── images/
├── README.md
└── requirements.txt
```

## Phases

**MVP path (Phases 1–8) — this is the core deliverable.**
**Phase 9 (portfolio polish) and Phase 10 (churn model) are the stretch goals once the MVP ships.**

| Phase | Focus | Status |
|---|---|---|
| 1 | Business Understanding & Planning | ✅ Done — see `business_understanding.md` |
| 2 | Data Warehouse Design (fact constellation, ER diagram, schema.sql) | Next |
| 3 | Synthetic Data Generation (5–10K customers, 50–100K orders, 100–300 products, 2023–2025) | Pending |
| 4 | Data Quality Validation (Python + SQL checks) | Pending |
| 5 | Business Analytics — SQL (revenue, retention, product, geography) | Pending |
| 6 | Advanced Customer Analytics (RFM, CLV, cohort retention, Pareto) | Pending |
| 7 | Power BI Dashboard (6–8 pages) | Pending |
| 8 | Business Insights & Recommendations | Pending |
| 9 | GitHub & Portfolio Preparation | Pending |
| 10 | Churn Prediction Model (stretch) | Pending |

## Scope Decisions Locked In

- **Vertical:** D2C apparel/lifestyle e-commerce (Solstice Apparel Co.)
- **ML stretch phase:** Included, positioned as Phase 10 after the core BI deliverable ships — this becomes the bridge piece into your ML/AI project track
- **Basket analysis and Slowly Changing Dimensions:** Deferred to stretch/optional, not MVP, to keep momentum

## Differentiation from procurement-spend-intelligence

| | procurement-spend-intelligence | customer-revenue-analytics |
|---|---|---|
| Business side | Supply (buying, suppliers, spend) | Demand (customers, revenue, retention) |
| Signature analysis | Supplier risk scoring | RFM, CLV, cohort retention, churn |
| Interview story | "How well are we buying" | "How well are we keeping and growing customers" |
| Resume roles emphasized | Procurement/Supply Chain Analyst | Customer/Retention/Growth Analyst, general BI |

## Next Step

Phase 2: data warehouse design. This means finalizing the fact/dimension list, drawing the ER diagram, and writing `schema.sql` — same process we used for procurement's fact constellation. I'll propose a fact table list (Orders/Order Lines, Returns) and dimension list (Customer, Product, Date, Geography, Marketing Channel) for your review before generating the schema.
