# Customer Revenue Analytics Platform
### Production-Grade Customer Analytics, Data Warehousing & Executive Decision Support

<p align="center">

![Status](https://img.shields.io/badge/Status-Complete-success)
![Version](https://img.shields.io/badge/Version-v1.3.0-blue)
![Warehouse](https://img.shields.io/badge/Warehouse-Certified-success)
![Analytics](https://img.shields.io/badge/Analytics-13%20Modules-success)
![Validation](https://img.shields.io/badge/Validation-79%2F79-success)
![Database](https://img.shields.io/badge/DuckDB-SQL-orange)
![License](https://img.shields.io/badge/License-MIT-lightgrey)
![Python](https://img.shields.io/badge/python-3.11%2B-blue?logo=python&logoColor=white)

</p>

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Project Objectives](#project-objectives)
- [Platform Architecture](#platform-architecture)
- [Repository Highlights](#repository-highlights)
- [Technology Stack](#technology-stack)
- [Business Scenario](#business-scenario)
- [Warehouse Design](#warehouse-design-philosophy)
- [Analytics Layer](#analytics-layer)
- [Validation Framework](#validation-framework)
- [Executive Decision Layer](#executive-decision-layer)
- [Engineering Philosophy](#engineering-philosophy)
- [Skills Demonstrated](#skills-demonstrated)
- [Repository Certification](#repository-certification)
- [Project Evolution](#project-evolution)
- [Repository Achievements](#repository-achievements)
- [Repository Visuals](#repository-visuals)
- [Future Work](#future-work)
- [Lessons Learned](#lessons-learned)
- [About](#about-this-project)
- [Contact](#contact)

---

# Executive Summary

The **Customer Revenue Analytics Platform** is a production-style analytics engineering project built around a certified dimensional data warehouse for a fictional Direct-to-Consumer (D2C) apparel retailer, **Solstice Apparel Co.**

The project demonstrates an end-to-end analytical workflow beginning with dimensional modeling and warehouse engineering, progressing through a validated SQL analytics layer, and culminating in an executive decision framework that translates analytical findings into evidence-based business recommendations.

Unlike many portfolio projects that focus on isolated dashboards or SQL queries, this repository emphasizes:

- production-quality engineering practices
- dimensional warehouse architecture
- reproducible synthetic data generation
- automated analytical validation
- customer analytics
- executive decision support
- documentation-driven development
- repository governance and version control

The project intentionally follows an enterprise-style development lifecycle where every analytical deliverable is independently reviewed, validated, documented, and certified before becoming part of the platform.

---

# Project Objectives

The platform was designed to answer one fundamental business question:

> **How can an apparel retailer better understand customer behavior and convert analytical findings into measurable business decisions?**

To answer that question, the project develops a complete analytical ecosystem including:

- Certified dimensional warehouse
- Executive KPI reporting
- Revenue analytics
- Product performance analysis
- Geographic analysis
- Marketing effectiveness
- Customer value analytics
- RFM segmentation
- Cohort analysis
- Historical Customer Lifetime Value (CLV)
- Pareto & customer concentration analysis
- Behavioral analytics
- Portfolio synthesis
- Executive recommendations

---

# Platform Architecture

The repository is intentionally organized into three logical layers.

```
                   Customer Revenue Analytics Platform

                           Executive Decision Layer
                     ───────────────────────────────────
                    Evidence-Based Business Recommendations
                    Recommendation Traceability
                    Executive Decision Support
                    Phase 7

                                    ▲

                          Certified Analytics Layer
                     ───────────────────────────────────
                    13 SQL Analytics Modules
                    Customer Analytics
                    Behavioral Analytics
                    Portfolio Synthesis
                    Automated Validation
                    79 / 79 Certified Checks

                                    ▲

                       Certified Data Warehouse
                     ───────────────────────────────────
                    Frozen Star Schema
                    Synthetic Enterprise Dataset
                    DuckDB
                    Fact Constellation
                    Reproducible Data Generation
```

---

## Architecture Overview
 
<p align="center">
  <img src="docs/architecture/er_diagram.png" alt="Customer Revenue Analytics ER Diagram" width="900">
</p>
 
```
                          ┌──────────────────────────────────────────────┐
                          │              CONFORMED DIMENSIONS            │
                          │  Dim_Date  Dim_Customer  Dim_Product         │
                          │  Dim_Geography  Dim_Marketing_Channel        │
                          │  Dim_Sales_Channel  Dim_Campaign             │
                          │  Dim_Return_Reason                           │
                          └──────────────────────────────────────────────┘
                                 │            │            │           │
              ┌──────────────────┘   ┌────────┘     ┌──────┘    ┌──────┘
              ▼                      ▼              ▼           ▼
   ┌───────────────────┐  ┌───────────────────┐  ┌─────────────┐  ┌────────────────────────────────┐
   │    Fact_Orders    │  │ Fact_Order_Lines  │  │Fact_Returns │  │ Fact_Customer_Monthly_Snapshot │
   │  (order grain)    │◄─│  (line grain)     │◄─│(return grn) │  │   (customer-month grain)       │
   │  header revenue   │  │ product detail    │  │ per-line    │  │  derived state, no randomness  │
   └───────────────────┘  └───────────────────┘  └─────────────┘  └────────────────────────────────┘
```
 
Each fact is **additive at its own grain**; conformed dimensions let every fact be sliced the same way. Header revenue reconciles to line revenue *by construction* (a single shared simulation produces both), and the monthly snapshot reconciles to the transactional facts to the cent.
 
---

# Repository Highlights

## Certified Warehouse

✔ Production-style dimensional warehouse

✔ Star schema architecture

✔ Frozen after certification

✔ Reproducible synthetic data

✔ Complete warehouse validation

---

## Certified Analytics Layer

The analytics layer consists of **13 production analytics modules**, each independently implemented, validated, documented, and integrated into the certified warehouse.

| Module | Area |
|---------|------|
| 01 | Executive KPI Summary |
| 02 | Revenue Analysis |
| 03 | Product Performance |
| 04 | Geographic Performance |
| 05 | Marketing Performance |
| 06 | Customer Value & Retention |
| 07 | Returns & Value Leakage |
| 08 | Adaptive RFM Segmentation |
| 09 | Cohort Analytics |
| 10 | Historical Customer Lifetime Value |
| 11 | Pareto & Customer Concentration |
| 12 | Customer Behavioral Analytics |
| 13 | Customer Portfolio Synthesis |

---

## Executive Decision Layer

Following completion of the certified analytics layer, the project introduces an **Executive Decision Layer**.

Rather than generating additional metrics, this layer transforms validated analytical findings into structured executive recommendations using a strict evidence-first methodology without introducing additional analytical measurement.

Every recommendation follows the same decision framework:

```
Certified Evidence

↓

Business Interpretation

↓

Executive Recommendation

↓

Expected Business Outcome

↓

Business KPI

↓

Success Metric
```

Recommendations are intentionally separated from analytical measurement to preserve the integrity of the certified analytics layer while providing actionable business guidance.

---

# Key Features

### Data Engineering

- Dimensional Data Warehouse
- Star Schema
- Fact Constellation
- Slowly Changing Dimensions
- DuckDB
- Synthetic Data Generation

### Analytics Engineering

- SQL Analytics Layer
- Automated Validation Framework
- Customer Analytics
- Historical CLV
- Cohort Analysis
- Adaptive RFM Segmentation
- Behavioral Analytics

### Business Intelligence

- Executive KPI Reporting
- Customer Portfolio Analysis
- Customer Concentration
- Revenue Analysis
- Marketing Effectiveness
- Executive Recommendations

### Software Engineering

- Modular Architecture
- Version Control
- Engineering Decision Log
- Build Logs
- Cross-Section Insight Tracking
- Repository Governance

---

# Technology Stack

| Category | Technologies |
|-----------|--------------|
| Database | DuckDB |
| Language | SQL, Python |
| Development | VS Code |
| Data Generation | Python |
| Analytics | SQL |
| Validation | Python |
| Version Control | Git, GitHub |
| Documentation | Markdown |
| Visualization | Draw.io (Architecture), GitHub Markdown |

---

# Repository Structure

```
customer-revenue-analytics/

├── data/
│
├── database/
│
├── docs/
│   ├── architecture/
│   ├── phase_documents/
│   ├── business_glossary.md
│   ├── business_understanding.md
│   ├── data_dictionary.md
│   ├── data_generation_strategy.md
│   ├── data_warehouse_design.md
│   ├── design_decisions.md
│   ├── engineering_decision_log.md
│   ├── project_roadmap.md
│   └── schema_changelog.md
│
├── python/
│   ├── generation/
│   ├── validation/
│   └── utilities/
│
├── sql/
│   ├── warehouse/
│   ├── analytics/
│   └── validation/
│
├── README.md
└── LICENSE
```

---

# Repository Status

| Component | Status |
|------------|--------|
| Warehouse | ✅ Certified |
| Data Generation | ✅ Complete |
| Analytics Layer | ✅ Complete |
| Executive Decision Layer | ✅ Complete |
| SQL Modules | ✅ 13 |
| Automated Validation | ✅ 79 / 79 |
| Documentation | ✅ Complete |
| GitHub | ✅ Synchronized |

---

> **This repository represents a complete customer analytics platform developed using production-style analytics engineering practices. Every analytical conclusion presented within the project is traceable to certified warehouse data and validated SQL outputs.**

---

# Business Scenario

## Company Overview

**Solstice Apparel Co.** is a fictional direct-to-consumer (D2C) apparel retailer specializing in contemporary clothing and accessories sold through online channels.

The business operates nationally across the United States and serves customers through multiple acquisition channels, including Organic Search, Paid Search, Social Media, Email Marketing, and Direct traffic.

Like many growing e-commerce businesses, Solstice Apparel has accumulated large volumes of transactional data but lacks an integrated analytical platform capable of transforming operational data into strategic business insight.

The objective of this project is to design and implement a modern customer analytics platform that enables business leaders to answer questions such as:

- Which customers generate the greatest long-term value?
- How concentrated is revenue among customers?
- Which marketing channels produce the highest-value customers?
- Which customer behaviors distinguish high-value customers?
- Where are the largest controllable sources of revenue leakage?
- Which executive actions are most strongly supported by analytical evidence?

Rather than focusing on reporting alone, the project emphasizes **decision support** built upon validated analytical evidence.

---

# Business Objectives

The platform was developed around six strategic objectives.

| Objective | Business Purpose |
|-----------|------------------|
| Revenue Visibility | Understand where revenue is generated and how it changes over time |
| Customer Value | Measure customer lifetime value and retention patterns |
| Operational Efficiency | Identify controllable revenue leakage and operational improvements |
| Customer Segmentation | Classify customers for targeted retention and growth strategies |
| Executive Decision Support | Convert validated findings into prioritized business actions |
| Engineering Excellence | Demonstrate production-style analytics engineering practices |

---

# Warehouse Design Philosophy

The repository follows a traditional **Kimball dimensional modeling approach** optimized for analytical workloads.

The warehouse is intentionally separated from the analytics layer.

This separation allows:

- warehouse stability
- reproducible analytics
- independent validation
- simplified maintenance
- clear architectural boundaries

Once certified, the warehouse is considered **permanently frozen**.

Subsequent phases consume warehouse data through analytical views without modifying warehouse structures.

---

# Dimensional Architecture

The warehouse uses a **fact constellation schema** consisting of multiple fact tables supported by shared dimensions.

```
                         DIM_DATE
                             │
                             │
      ┌──────────────────────┼──────────────────────┐
      │                      │                      │
      │                      │                      │
DIM_CUSTOMER          FACT_ORDERS           FACT_RETURNS
      │                      │                      │
      │                      │                      │
DIM_PRODUCT ───────── FACT_ORDER_LINES ───── DIM_CHANNEL
      │
DIM_CATEGORY
      │
DIM_GEOGRAPHY
```

The architecture separates transactional facts from descriptive dimensions while supporting reusable analytical models across all reporting modules.

---

# Warehouse Components

## Dimension Tables

The warehouse contains business dimensions representing relatively stable descriptive information.

Examples include:

- Customer
- Product
- Category
- Date
- Geography
- Sales Channel

Dimensions provide descriptive context while minimizing redundancy throughout analytical queries.

---

## Fact Tables

Transactional activity is stored in fact tables at the appropriate business grain.

Major facts include:

- Customer Orders
- Order Line Items
- Product Returns
- Customer Behavioral Features

Fact tables preserve transactional history while enabling flexible aggregation across analytical dimensions.

---

# Certified Warehouse Statistics

The certified warehouse contains:

| Metric | Value |
|---------|------:|
| Customers | 8,000 |
| Orders | 26,299 |
| Order Line Items | 33,959 |
| Returns | 5,687 |
| Historical Period | 2023–2025 |
| Product Categories | 5 |
| Geographic Markets | 46 |
| Sales Channels | 3 |

All warehouse statistics remain frozen following certification.

---

# Synthetic Data Generation

Rather than using publicly available datasets, the repository generates a realistic enterprise-scale synthetic dataset.

The generation process models:

- customer acquisition
- repeat purchasing
- seasonal demand
- returns
- product mix
- geographic distribution
- customer lifetime
- marketing channels

Every dataset is reproducible through deterministic generation scripts.

This approach allows analytical experimentation while avoiding privacy concerns associated with real customer information.

---

# Engineering Principles

The repository follows several engineering principles throughout development.

## Frozen Warehouse

Warehouse structures remain immutable after certification.

All future work consumes certified warehouse objects.

---

## Business Questions First

Every analytical module begins with clearly defined business questions before SQL implementation.

This prevents "analysis for analysis's sake" and ensures every deliverable supports executive decision-making.

---

## Independent Design Review

Every major analytical section follows the same methodology:

1. Business Question
2. Design Review
3. SQL Implementation
4. Validation
5. Executive Interpretation
6. Repository Certification

Separating design from implementation improves analytical quality and mirrors professional engineering review practices.

---

## Validation Before Publication

Analytical findings are never accepted solely because SQL executes successfully.

Every module includes independent validation against certified regression anchors before publication.

This repository currently contains:

- **13 certified analytics modules**
- **79 automated validation checks**

Every validation must pass before repository publication.

---

# Analytics Layer

The SQL Analytics Layer represents the analytical core of the platform.

Each module addresses a distinct business domain while consuming the same certified warehouse.

## Executive Analytics

| Module | Business Question |
|---------|-------------------|
| 01 | How is the business performing overall? |
| 02 | Where is revenue generated? |
| 03 | Which products create value? |
| 04 | How do geographic markets compare? |
| 05 | Which acquisition channels perform best? |
| 06 | Which customers create the most value? |
| 07 | Where does value leak from the business? |

---

## Advanced Customer Analytics

Phase 6 extends the analytical platform through customer-centric analytics.

| Module | Purpose |
|---------|----------|
| 08 | Adaptive RFM Segmentation |
| 09 | Cohort Analytics |
| 10 | Historical Customer Lifetime Value |
| 11 | Pareto & Customer Concentration |
| 12 | Customer Behavioral Analytics |
| 13 | Customer Portfolio Synthesis |

Unlike traditional dashboards, these modules progressively explain not only **what** customers are worth, but also **why** they create value and **how** the portfolio should be interpreted by executive leadership.

---

# Validation Framework

A distinguishing characteristic of this project is the use of a formal validation framework.

Every analytical module includes independently designed validation checks that verify:

- reconciliation to certified warehouse totals
- population integrity
- analytical boundaries
- business-rule correctness
- regression stability

Validation is automated through a Python-based validation runner.

Current certification status:

| Layer | Status |
|-------|--------|
| Warehouse | ✅ Certified |
| Analytics Modules | ✅ 13 |
| Automated Validations | ✅ 79 / 79 Passing |
| Regression Anchors | ✅ Preserved |

This validation-first philosophy reflects enterprise analytics engineering practices where correctness is verified independently of implementation.

---

# Executive Decision Layer

After completing the certified analytics layer, the project transitions from **analytical measurement** to **executive decision support**.

Rather than generating additional metrics or dashboards, the Executive Decision Layer transforms validated analytical findings into structured business recommendations while preserving the integrity of the certified analytics platform.

This deliberate architectural separation ensures that:

- analytical findings remain reproducible and independently validated,
- business recommendations remain traceable to certified evidence,
- executive guidance can evolve without modifying historical analytical results.

The Executive Decision Layer therefore represents the final business-facing component of the platform.

---

# Recommendation Methodology

Every recommendation follows a standardized evidence-first framework.

```
Certified Evidence

↓

Business Interpretation

↓

Executive Recommendation

↓

Expected Business Outcome

↓

Business KPI

↓

Success Metric
```

This structure intentionally separates:

- objective measurement,
- business interpretation,
- executive judgment,
- expected operational impact.

Recommendations are therefore **traceable**, **transparent**, and **defensible**.

---

# Evidence Hierarchy

Not all business evidence carries the same level of certainty.

To avoid overstating analytical conclusions, every recommendation is classified using an explicit evidence hierarchy.

| Evidence Strength | Description |
|-------------------|-------------|
| Certified Measurement | Directly measured and validated analytical result |
| Validated Observation | Repeated analytical finding supported across certified modules |
| Observed Association | Statistically consistent relationship without causal proof |
| Illustrative Scenario | Modeled business scenario used only for planning discussions |

This hierarchy prevents recommendations from presenting modeled opportunities as guaranteed business outcomes.

---

# Recommendation Prioritization Framework

Recommendations are prioritized using four independent dimensions.

| Dimension | Purpose |
|-----------|----------|
| Business Impact | Expected strategic value |
| Implementation Complexity | Estimated organizational effort |
| Evidence Strength | Confidence supported by certified analytics |
| Implementation Horizon | Recommended execution timeline |

Implementation horizons are categorized as:

- **Immediate (0–3 months)**
- **Near-Term (3–6 months)**
- **Strategic (6–12 months)**

This framework intentionally prioritizes **certainty over speculative upside**, preserving the disciplined decision-making approach established throughout the project.

---

# Recommendation Traceability

Every executive recommendation can be traced directly back to one or more certified analytical modules.

| Recommendation Theme | Supporting Analytics |
|----------------------|----------------------|
| Returns Reduction | Product Performance, Returns & Value Leakage |
| Customer Retention | Customer Value, RFM, Pareto Analysis |
| Second Purchase Conversion | Cohort Analytics, Customer Portfolio |
| Category Expansion | Behavioral Analytics |
| Marketing Investment | Marketing Performance |
| Customer Portfolio Strategy | Portfolio Synthesis |

No recommendation exists without supporting analytical evidence.

---

# What Makes This Project Different?

Many analytics portfolio projects demonstrate the ability to write SQL.

This repository demonstrates an end-to-end analytical engineering workflow.

Unlike conventional portfolio projects, this platform includes:

- certified dimensional warehouse
- reproducible synthetic enterprise dataset
- modular SQL analytics architecture
- automated regression validation
- engineering decision governance
- structured documentation
- independent design reviews
- executive recommendation methodology
- evidence traceability
- repository versioning and certification

The emphasis is not simply on building dashboards, but on creating a maintainable analytical platform that mirrors enterprise analytics engineering practices.

---

# Engineering Philosophy

Several principles guided every phase of development.

## Business Questions Drive Implementation

Every analytical module begins with a clearly defined business question.

Technology supports business objectives rather than driving them.

---

## Certification Before Publication

No analytical result is considered complete until it passes independent validation against certified regression anchors.

Analytical correctness always takes precedence over implementation speed.

---

## Frozen Warehouse Architecture

The dimensional warehouse is permanently frozen following certification.

Subsequent phases consume warehouse outputs through analytical views without modifying warehouse structures.

This preserves reproducibility while simplifying long-term maintenance.

---

## Independent Design Review

Each major analytical section follows a structured review process before implementation.

This mirrors professional software engineering and analytics governance practices where architectural decisions are validated before code is written.

---

## Documentation as an Engineering Artifact

Documentation is treated as a first-class deliverable rather than an afterthought.

The repository maintains:

- build logs
- engineering decision logs
- analytical reports
- cross-section insight tracking
- completion documents
- recommendation documentation

This provides complete traceability throughout the project's lifecycle.

---

# Skills Demonstrated

This repository demonstrates practical experience across multiple areas of modern analytics engineering.

## Data Engineering

- Dimensional Modeling
- Star Schema Design
- Fact Constellation Architecture
- Synthetic Data Generation
- Data Quality Validation
- Data Warehouse Engineering

---

## SQL & Analytics Engineering

- Advanced SQL
- Analytical Views
- Customer Segmentation
- Historical Customer Lifetime Value
- Cohort Analysis
- RFM Segmentation
- Behavioral Analytics
- Executive KPI Development
- Business Metric Design

---

## Software Engineering

- Python Automation
- Validation Frameworks
- Modular Repository Design
- Version Control (Git)
- GitHub Workflow
- Documentation-Driven Development
- Engineering Governance

---

## Business Analytics

- Executive Decision Support
- Customer Analytics
- Revenue Optimization
- Marketing Analytics
- Portfolio Analysis
- Strategic Recommendations
- Evidence-Based Decision Making

---

# Repository Certification

The platform concludes with three independently governed layers.

| Layer | Status |
|--------|--------|
| Certified Warehouse | ✅ Complete |
| Certified Analytics Layer | ✅ Complete |
| Executive Decision Layer | ✅ Complete |

Platform certification summary:

| Component | Status |
|------------|--------|
| Warehouse Tables | 12 |
| Analytics Modules | 13 |
| Automated Validations | **79 / 79 Passing** |
| Engineering Decisions | Fully Documented |
| Repository Governance | Complete |
| Executive Recommendations | Evidence Traceable |

The repository is therefore complete as an end-to-end customer analytics platform.

---

# Why This Project Matters

The objective of this repository was never simply to demonstrate SQL proficiency.

Instead, it demonstrates how analytical engineering can be applied to solve realistic business problems through disciplined architecture, rigorous validation, and evidence-based decision making.

By separating data engineering, analytical measurement, and executive interpretation into distinct but connected layers, the project reflects many of the practices used by modern analytics engineering teams.

The resulting platform illustrates not only **how to analyze data**, but also **how to build analytical systems that business leaders can trust.**

---

# Project Evolution

The Customer Revenue Analytics Platform was developed incrementally using a structured engineering methodology where each major milestone was independently reviewed, validated, documented, and certified before progressing.

| Release | Milestone | Status |
|----------|-----------|--------|
| **v1.0.0** | Certified Dimensional Warehouse | ✅ |
| **v1.1.0** | Certified SQL Analytics Layer (Phase 5) | ✅ |
| **v1.2.0** | Advanced Customer Analytics (Phase 6) | ✅ |
| **v1.3.0** | Executive Decision Layer & Portfolio Release (Phase 7) | ✅ |

The platform now consists of:

- Certified Enterprise Data Warehouse
- 13 Production Analytics Modules
- Executive Decision Layer
- Automated Validation Framework
- Complete Engineering Documentation

---

# Repository Achievements

Throughout development the project maintained a disciplined engineering process rather than focusing solely on analytical outputs.

Final repository statistics:

| Metric | Value |
|---------|------:|
| Warehouse Tables | 12 |
| Analytics Modules | 13 |
| SQL Validation Checks | **79 / 79 Passing** |
| Development Phases | 7 |
| Engineering Decisions | Fully Documented |
| Build Logs | Complete |
| Repository Certification | Complete |

Major analytical capabilities include:

- Executive KPI Reporting
- Revenue Analytics
- Product Analytics
- Marketing Analytics
- Geographic Analytics
- Customer Value Analysis
- Customer Lifetime Value
- Adaptive RFM Segmentation
- Cohort Analysis
- Pareto & Customer Concentration
- Behavioral Analytics
- Portfolio Synthesis
- Executive Recommendations

---

# Future Work

The analytical platform is intentionally complete.

---

## Future Research — Predictive Analytics Extension

Future research directions include:

- Predictive Customer Lifetime Value
- Customer Churn Prediction
- Propensity Modeling
- Machine Learning Feature Store
- Model Monitoring
- Recommendation Systems

These topics were intentionally excluded from the certified analytics platform to preserve a clear distinction between descriptive analytics and predictive modeling.

---

# Lessons Learned

Developing this project reinforced several important engineering principles.

- Correct architecture is more valuable than writing more code.
- Validation is as important as implementation.
- Business questions should drive analytical design.
- Documentation is an engineering deliverable.
- Executive recommendations should always remain traceable to analytical evidence.
- Analytical discipline often means choosing **not** to make unsupported claims.

These lessons shaped every phase of the platform and remain applicable beyond this project.

---

# About This Project

This repository was developed as part of my graduate studies in Information Management at the **University of Illinois Urbana-Champaign (UIUC)**.

The project was designed to demonstrate practical experience across:

- Analytics Engineering
- Data Engineering
- SQL Development
- Customer Analytics
- Business Intelligence
- Executive Decision Support
- Software Engineering Best Practices

Rather than emphasizing individual technologies, the platform demonstrates how these disciplines integrate into a complete analytical solution.

---

# Contact
 
**[Tejas Jaggi]** — [jaggitejas4@gmail.com.com](mailto:jaggitejas4@gmail.com.com)
[LinkedIn](https://www.linkedin.com/in/tejas-jaggi/) · [Portfolio](https://tejas-jaggi.github.io/) · [GitHub](https://github.com/tejas-jaggi/)

---

# License

This project is released under the **MIT License**.

See the `LICENSE` file for additional details.

---

# Acknowledgements

This project benefited from iterative engineering reviews, analytical design validation, and repository governance throughout its development lifecycle.

Special emphasis was placed on maintaining production-style engineering discipline, reproducibility, and evidence-based business interpretation.

---

# Final Statement

The **Customer Revenue Analytics Platform** represents a complete end-to-end analytics engineering project, progressing from dimensional warehouse design through certified analytical measurement to executive decision support.

The repository demonstrates not only how to build a modern analytical platform, but also how to develop analytical systems that business stakeholders can trust through disciplined engineering, independent validation, and transparent documentation.

While the technologies used in this repository are important, the primary objective has always been to demonstrate a repeatable engineering methodology capable of producing reliable analytical products.

**Thank you for taking the time to explore this project. Feedback, suggestions, and discussion are always welcome.**
