# Phase 6 Operating Procedure
## Customer Revenue Analytics Platform

**Version:** 1.1  
**Repository Version:** v1.1.0+  
**Applies to:** Phase 6 – Advanced Customer Analytics

---

# Purpose

This document defines the standard engineering workflow for every analytical section implemented during Phase 6.

The objective is to maintain publication-quality analytical engineering, repository consistency, reproducibility, and enterprise-level documentation throughout the remainder of the project.

This procedure is mandatory for every Phase 6 section.

---

# Engineering Principles

Every analytical deliverable must follow these principles.

- Business questions drive implementation.
- Warehouse remains frozen.
- Certified KPIs remain permanent regression anchors.
- SQL execution is never treated as proof of correctness.
- Every analytical result must be independently validated.
- Methodology must always be documented.
- Historical project records are never silently rewritten.
- Repository consistency is treated as part of engineering quality.

---

# Repository Standards

## Frozen Warehouse

The dimensional warehouse is certified and frozen.

No schema modifications are permitted unless a genuine warehouse defect is discovered.

---

## UTF-8 Encoding Standard

All repository source files shall use UTF-8 encoding.

This includes:

- SQL
- Python
- Markdown

Python utilities must explicitly specify:

```python
encoding="utf-8"