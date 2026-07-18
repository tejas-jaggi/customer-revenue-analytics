"""
One-time database initialization — applies sql/schema.sql to create the
full (empty) table structure in data/solstice_apparel.duckdb.

This is run ONCE at the start of Phase 3, not by each phase's individual
generator. schema.sql contains DROP TABLE IF EXISTS for every table, so
re-running this script resets the entire database — useful for a clean
rebuild, but NOT part of the normal per-table generation workflow (each
phase's generate_dim_*.py / generate_fact_*.py script only DELETEs and
re-INSERTs into its own table, so tables from earlier phases are never
touched by later phases' generators).

Run:
    python python/generators/init_database.py
"""

from pathlib import Path
import duckdb

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = PROJECT_ROOT / "data"
DB_PATH = DATA_DIR / "database" / "solstice_apparel.duckdb"
SCHEMA_PATH = PROJECT_ROOT / "sql" / "schema" / "schema.sql"


def main():
    (DATA_DIR / "database").mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB_PATH))
    con.execute(SCHEMA_PATH.read_text())
    tables = con.execute(
        "SELECT table_name FROM information_schema.tables ORDER BY table_name"
    ).fetchall()
    con.close()
    print(f"Initialized {DB_PATH} with {len(tables)} tables:")
    for t in tables:
        print(f"  - {t[0]}")


if __name__ == "__main__":
    main()
