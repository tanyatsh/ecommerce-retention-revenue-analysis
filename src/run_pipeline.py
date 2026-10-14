from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import duckdb


ROOT = Path(__file__).resolve().parents[1]

EXPECTED_SCHEMAS = {
    "olist_customers_dataset.csv": ["customer_id", "customer_unique_id", "customer_zip_code_prefix", "customer_city", "customer_state"],
    "olist_geolocation_dataset.csv": ["geolocation_zip_code_prefix", "geolocation_lat", "geolocation_lng", "geolocation_city", "geolocation_state"],
    "olist_order_items_dataset.csv": ["order_id", "order_item_id", "product_id", "seller_id", "shipping_limit_date", "price", "freight_value"],
    "olist_order_payments_dataset.csv": ["order_id", "payment_sequential", "payment_type", "payment_installments", "payment_value"],
    "olist_order_reviews_dataset.csv": ["review_id", "order_id", "review_score", "review_comment_title", "review_comment_message", "review_creation_date", "review_answer_timestamp"],
    "olist_orders_dataset.csv": ["order_id", "customer_id", "order_status", "order_purchase_timestamp", "order_approved_at", "order_delivered_carrier_date", "order_delivered_customer_date", "order_estimated_delivery_date"],
    "olist_products_dataset.csv": ["product_id", "product_category_name", "product_name_lenght", "product_description_lenght", "product_photos_qty", "product_weight_g", "product_length_cm", "product_height_cm", "product_width_cm"],
    "olist_sellers_dataset.csv": ["seller_id", "seller_zip_code_prefix", "seller_city", "seller_state"],
    "product_category_name_translation.csv": ["product_category_name", "product_category_name_english"],
}

TABLES = {
    "customers": "olist_customers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "product_category_translation": "product_category_name_translation.csv",
}

KEYS = {
    "customers": ["customer_id"],
    "orders": ["order_id"],
    "products": ["product_id"],
    "sellers": ["seller_id"],
    "order_items": ["order_id", "order_item_id"],
    "order_payments": ["order_id", "payment_sequential"],
    "product_category_translation": ["product_category_name"],
    "order_reviews": ["review_id"],
}

DATE_COLUMNS = {
    "order_items": ["shipping_limit_date"],
    "order_reviews": ["review_creation_date", "review_answer_timestamp"],
    "orders": ["order_purchase_timestamp", "order_approved_at", "order_delivered_carrier_date", "order_delivered_customer_date", "order_estimated_delivery_date"],
}

EXPORTS = {
    "order_financials.csv": "analytics.fct_order_financials_reporting",
    "order_financials_full_history.csv": "analytics.fct_order_financials",
    "monthly_revenue_orders.csv": "analytics.fct_monthly_revenue_orders",
    "customer_purchase_summary.csv": "analytics.dim_customer_purchase_summary",
    "customer_purchase_summary_full_history.csv": "analytics.dim_customer_purchase_summary_full_history",
    "cohort_retention.csv": "analytics.dim_cohort_retention",
    "cohort_fixed_windows.csv": "analytics.fct_cohort_fixed_windows",
    "cohort_horizon_summary.csv": "analytics.fct_cohort_horizon_summary",
    "customer_rfm.csv": "analytics.dim_customer_rfm",
    "customer_rfm_full_history.csv": "analytics.dim_customer_rfm_full_history",
    "rfm_segment_summary.csv": "analytics.fct_rfm_segment_summary",
    "order_delivery_reviews.csv": "analytics.fct_order_delivery_reviews",
    "order_delivery_reviews_full_history.csv": "analytics.fct_order_delivery_reviews_full_history",
    "monthly_delivery_reviews.csv": "analytics.fct_monthly_delivery_reviews",
    "validation_results.csv": "audit.validation_results",
    "source_profile.csv": "audit.source_profile",
    "column_profile.csv": "audit.column_profile",
    "key_profile.csv": "audit.key_profile",
    "date_range_profile.csv": "audit.date_range_profile",
}


def quoted(path: Path) -> str:
    return path.resolve().as_posix().replace("'", "''")


def validate_sources(raw_dir: Path) -> None:
    errors = []
    for filename, expected in EXPECTED_SCHEMAS.items():
        path = raw_dir / filename
        if not path.is_file():
            errors.append(f"Missing source: {path}")
            continue
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            actual = next(csv.reader(handle), [])
        if actual != expected:
            errors.append(f"Unexpected columns in {filename}: expected {expected}; found {actual}")
    if errors:
        raise RuntimeError("\n".join(errors))


def execute_sql(con: duckdb.DuckDBPyConnection, raw_dir: Path) -> None:
    for filename in ["01_staging.sql", "02_intermediate.sql", "03_marts.sql", "04_checks.sql"]:
        sql = (ROOT / "sql" / filename).read_text(encoding="utf-8")
        sql = sql.replace("{{RAW_DIR}}", quoted(raw_dir))
        con.execute(sql)


def build_profiles(con: duckdb.DuckDBPyConnection) -> None:
    source_rows = []
    column_rows = []
    key_rows = []
    date_rows = []

    for table, filename in TABLES.items():
        row_count = con.execute(f"SELECT COUNT(*) FROM raw.{table}").fetchone()[0]
        columns = con.execute(
            "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'raw' AND table_name = ? ORDER BY ordinal_position",
            [table],
        ).fetchall()
        all_columns = ", ".join('"' + column.replace('"', '""') + '"' for column, _ in columns)
        duplicate_rows = con.execute(
            f"SELECT COALESCE(SUM(n - 1), 0) FROM (SELECT COUNT(*) n FROM raw.{table} GROUP BY {all_columns} HAVING COUNT(*) > 1)"
        ).fetchone()[0]
        source_rows.append((filename, table, row_count, duplicate_rows))

        for column, data_type in columns:
            safe_column = '"' + column.replace('"', '""') + '"'
            null_count, distinct_count = con.execute(
                f"SELECT COUNT(*) FILTER (WHERE {safe_column} IS NULL), COUNT(DISTINCT {safe_column}) FROM raw.{table}"
            ).fetchone()
            column_rows.append((filename, table, column, data_type, row_count, null_count, distinct_count))

        if table in KEYS:
            key_columns = KEYS[table]
            expression = ", ".join('"' + c.replace('"', '""') + '"' for c in key_columns)
            null_keys = con.execute(
                "SELECT COUNT(*) FROM raw." + table + " WHERE " + " OR ".join(f'"{c}" IS NULL' for c in key_columns)
            ).fetchone()[0]
            duplicate_keys = con.execute(
                f"SELECT COUNT(*) FROM (SELECT {expression}, COUNT(*) n FROM raw.{table} GROUP BY {expression} HAVING COUNT(*) > 1)"
            ).fetchone()[0]
            key_rows.append((filename, table, ", ".join(key_columns), row_count, null_keys, duplicate_keys, duplicate_keys == 0 and null_keys == 0))

        for column in DATE_COLUMNS.get(table, []):
            minimum, maximum, null_count = con.execute(
                f'SELECT MIN("{column}"), MAX("{column}"), COUNT(*) FILTER (WHERE "{column}" IS NULL) FROM raw.{table}'
            ).fetchone()
            date_rows.append((filename, table, column, minimum, maximum, null_count))

    con.execute("CREATE OR REPLACE TABLE audit.source_profile (source_file VARCHAR, table_name VARCHAR, row_count BIGINT, exact_duplicate_rows BIGINT)")
    con.executemany("INSERT INTO audit.source_profile VALUES (?, ?, ?, ?)", source_rows)
    con.execute("CREATE OR REPLACE TABLE audit.column_profile (source_file VARCHAR, table_name VARCHAR, column_name VARCHAR, data_type VARCHAR, row_count BIGINT, null_count BIGINT, distinct_count BIGINT)")
    con.executemany("INSERT INTO audit.column_profile VALUES (?, ?, ?, ?, ?, ?, ?)", column_rows)
    con.execute("CREATE OR REPLACE TABLE audit.key_profile (source_file VARCHAR, table_name VARCHAR, key_columns VARCHAR, row_count BIGINT, null_key_rows BIGINT, duplicate_key_groups BIGINT, is_unique_and_not_null BOOLEAN)")
    con.executemany("INSERT INTO audit.key_profile VALUES (?, ?, ?, ?, ?, ?, ?)", key_rows)
    con.execute("CREATE OR REPLACE TABLE audit.date_range_profile (source_file VARCHAR, table_name VARCHAR, column_name VARCHAR, minimum_timestamp TIMESTAMP, maximum_timestamp TIMESTAMP, null_count BIGINT)")
    con.executemany("INSERT INTO audit.date_range_profile VALUES (?, ?, ?, ?, ?, ?)", date_rows)


def export_tables(con: duckdb.DuckDBPyConnection, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for filename, table in EXPORTS.items():
        destination = quoted(output_dir / filename)
        con.execute(f"COPY (SELECT * FROM {table}) TO '{destination}' (HEADER, DELIMITER ',')")


def scalar(con: duckdb.DuckDBPyConnection, query: str):
    return con.execute(query).fetchone()[0]


def collect_summary(con: duckdb.DuckDBPyConnection) -> dict:
    def scope_kpis(financial_table: str, customer_table: str, delivery_table: str) -> dict:
        kpis = con.execute(
            f"""
        SELECT
            COUNT(*) FILTER (WHERE is_eligible_order) AS eligible_orders,
            COUNT(DISTINCT customer_unique_id) FILTER (WHERE is_eligible_order) AS unique_customers,
            COUNT(gmv) FILTER (WHERE is_eligible_order) AS eligible_orders_with_gmv,
            COUNT(*) FILTER (WHERE is_eligible_order AND gmv IS NULL) AS eligible_orders_missing_gmv,
            SUM(item_value) FILTER (WHERE is_eligible_order) AS item_value,
            SUM(freight_value) FILTER (WHERE is_eligible_order) AS freight_value,
            SUM(gmv) FILTER (WHERE is_eligible_order) AS gmv,
            SUM(payment_value) FILTER (WHERE is_eligible_order) AS payments
        FROM {financial_table}
        """
        ).fetchone()
        repeat_customers, all_customers = con.execute(
            f"SELECT COUNT(*) FILTER (WHERE is_repeat_customer), COUNT(*) FROM {customer_table}"
        ).fetchone()
        delivered, late_rate, review_score, reviewed_orders = con.execute(
            f"SELECT COUNT(*), AVG(CASE WHEN is_late_delivery THEN 1.0 ELSE 0.0 END), AVG(average_review_score), COUNT(*) FILTER (WHERE has_review) FROM {delivery_table}"
        ).fetchone()
        return {
            "eligible_orders": kpis[0],
            "unique_customers": kpis[1],
            "eligible_orders_with_gmv": kpis[2],
            "eligible_orders_missing_gmv": kpis[3],
            "repeat_customers": repeat_customers,
            "repeat_purchase_rate": repeat_customers / all_customers if all_customers else None,
            "item_value": float(kpis[4]),
            "freight_value": float(kpis[5]),
            "gmv": float(kpis[6]),
            "payments": float(kpis[7]),
            "average_order_gmv_complete_case": float(kpis[6] / kpis[2]) if kpis[2] else None,
            "delivered_orders_with_delivery_date": delivered,
            "reviewed_delivered_orders": reviewed_orders,
            "review_coverage_rate": reviewed_orders / delivered if delivered else None,
            "late_delivery_rate": float(late_rate) if late_rate is not None else None,
            "average_order_level_review_score": float(review_score) if review_score is not None else None,
        }

    reporting_kpis = scope_kpis(
        "analytics.fct_order_financials_reporting",
        "analytics.dim_customer_purchase_summary",
        "analytics.fct_order_delivery_reviews",
    )
    full_history_kpis = scope_kpis(
        "analytics.fct_order_financials",
        "analytics.dim_customer_purchase_summary_full_history",
        "analytics.fct_order_delivery_reviews_full_history",
    )
    source_counts = dict(con.execute("SELECT source_file, row_count FROM audit.source_profile ORDER BY source_file").fetchall())
    passed, critical_failed, warnings = con.execute(
        "SELECT COUNT(*) FILTER (WHERE passed), COUNT(*) FILTER (WHERE NOT passed AND severity = 'critical'), COUNT(*) FILTER (WHERE NOT passed AND severity = 'warning') FROM audit.validation_results"
    ).fetchone()
    return {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_row_counts": source_counts,
        "reporting_period": {"start_month": "2017-01-01", "end_month": "2018-08-01", "observation_cutoff": "2018-08-31"},
        "kpis": reporting_kpis,
        "full_history_kpis": full_history_kpis,
        "validation": {"passed": passed, "critical_failed": critical_failed, "warnings": warnings},
    }


def write_quality_report(con: duckdb.DuckDBPyConnection, path: Path, summary: dict) -> None:
    lines = [
        "# Data quality report",
        "",
        "This report is generated by `src/run_pipeline.py` from the supplied CSVs. Counts are never synthesized.",
        "",
        "## Source rows and exact duplicates",
        "",
        "| Source file | Rows | Exact duplicate rows |",
        "|---|---:|---:|",
    ]
    for source_file, _, rows, duplicates in con.execute("SELECT * FROM audit.source_profile ORDER BY source_file").fetchall():
        lines.append(f"| {source_file} | {rows:,} | {duplicates:,} |")
    lines.extend(["", "## Column completeness and cardinality", "", "| Table.column | Type | Missing | Missing % | Distinct |", "|---|---|---:|---:|---:|"])
    for _, table, column, data_type, rows, nulls, distinct in con.execute(
        "SELECT * FROM audit.column_profile ORDER BY table_name, column_name"
    ).fetchall():
        missing_percent = 100.0 * nulls / rows if rows else 0.0
        lines.append(f"| {table}.{column} | {data_type} | {nulls:,} | {missing_percent:.2f}% | {distinct:,} |")
    lines.extend(["", "## Candidate key checks", "", "| Table | Candidate key | Null key rows | Duplicate key groups | Unique |", "|---|---|---:|---:|---|"])
    for _, table, keys, _, nulls, duplicates, valid in con.execute("SELECT * FROM audit.key_profile ORDER BY table_name").fetchall():
        lines.append(f"| {table} | `{keys}` | {nulls:,} | {duplicates:,} | {'yes' if valid else 'no'} |")
    lines.extend(["", "`review_id` is profiled as a candidate key but is not assumed unique by downstream models. Reviews are aggregated by `order_id` before joining.", "", "## Date ranges", "", "| Table.column | Minimum | Maximum | Missing |", "|---|---|---|---:|"])
    for _, table, column, minimum, maximum, nulls in con.execute("SELECT * FROM audit.date_range_profile ORDER BY table_name, column_name").fetchall():
        lines.append(f"| {table}.{column} | {minimum or ''} | {maximum or ''} | {nulls:,} |")
    lines.extend(["", "## Automated validation", "", "| Check | Result | Actual | Expected |", "|---|---|---:|---:|"])
    for name, passed, actual, expected, severity, _ in con.execute("SELECT * FROM audit.validation_results ORDER BY check_name").fetchall():
        result = "PASS" if passed else ("WARNING" if severity == "warning" else "FAIL")
        lines.append(f"| {name} | {result} | {actual:g} | {expected:g} |")
    lines.extend([
        "",
        "## Interpretation notes",
        "",
        "Missing-value counts for every field are exported to `data/processed/column_profile.csv`. Geolocation is intentionally not assigned a unique key because multiple coordinate observations can exist per postal-code prefix. Source review identifiers and order identifiers can repeat; the analytics layer uses order-level review aggregates. Payment totals and GMV are both retained because they represent different source concepts and are not forced to match.",
        "",
        "The final purchase month is treated as incomplete for cohort observation. Retention values for windows whose full calendar month is not observable are null rather than zero.",
        "",
    ])
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the Olist DuckDB analytics foundation.")
    parser.add_argument("--raw-dir", type=Path, default=ROOT / "data" / "raw")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "data" / "processed")
    parser.add_argument("--db-path", type=Path, default=ROOT / "data" / "ecommerce.duckdb")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    validate_sources(args.raw_dir)
    args.db_path.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(args.db_path))
    try:
        execute_sql(con, args.raw_dir)
        build_profiles(con)
        export_tables(con, args.output_dir)
        summary = collect_summary(con)
        (args.output_dir / "pipeline_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        write_quality_report(con, ROOT / "docs" / "data_quality_report.md", summary)
        failures = con.execute("SELECT check_name, details FROM audit.validation_results WHERE NOT passed AND severity = 'critical'").fetchall()
        print(json.dumps(summary, indent=2))
        if failures:
            for name, details in failures:
                print(f"FAILED: {name}: {details}", file=sys.stderr)
            return 1
        return 0
    finally:
        con.close()


if __name__ == "__main__":
    raise SystemExit(main())

