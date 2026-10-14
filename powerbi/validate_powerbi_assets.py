"""Validate the Power BI delivery package without Power BI Desktop dependencies."""

from __future__ import annotations

import csv
import json
import math
import re
import sys
from collections import Counter
from datetime import date, datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROCESSED = ROOT / "data" / "processed"
POWERBI = ROOT / "powerbi"
PBIP = POWERBI / "pbip"

CONTRACTS = {
    "monthly_revenue_orders.csv": [
        "purchase_month", "order_count", "orders_with_gmv", "orders_missing_gmv",
        "orders_with_payment", "orders_missing_payment", "unique_customers", "item_value",
        "freight_value", "gmv", "payment_value", "average_order_gmv", "period_quality",
    ],
    "customer_purchase_summary.csv": [
        "customer_unique_id", "first_reporting_purchase_timestamp", "last_reporting_purchase_timestamp",
        "reporting_period_order_count", "reporting_period_item_value",
        "reporting_period_freight_value", "reporting_period_gmv",
        "reporting_period_payment_value", "orders_missing_gmv", "orders_missing_payment",
        "is_repeat_customer",
    ],
    "cohort_retention.csv": [
        "cohort_month", "month_number", "cohort_size", "retained_customers",
        "observation_cutoff", "observation_window_complete", "retention_rate",
    ],
    "cohort_horizon_summary.csv": [
        "month_number", "mature_cohort_count", "eligible_customer_count",
        "retained_customer_count", "weighted_retention_rate",
    ],
    "rfm_segment_summary.csv": [
        "rfm_segment", "customer_count", "customer_share", "order_count", "monetary_value",
    ],
    "monthly_delivery_reviews.csv": [
        "purchase_month", "delivered_order_count", "reviewed_order_count",
        "unreviewed_order_count", "multiple_review_order_count", "review_coverage_rate",
        "average_delivery_days", "average_delivery_delay_days", "late_delivery_rate",
        "average_review_score", "late_delivery_review_score", "on_time_review_score",
    ],
}


class Checks:
    def __init__(self) -> None:
        self.results: list[dict[str, object]] = []

    def check(self, name: str, condition: bool, detail: str) -> None:
        self.results.append({"check": name, "passed": bool(condition), "detail": detail})

    @property
    def failed(self) -> list[dict[str, object]]:
        return [item for item in self.results if not item["passed"]]


def read_csv(name: str) -> tuple[list[str], list[dict[str, str]]]:
    path = PROCESSED / name
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def number(value: str) -> float:
    return float(value) if value not in ("", None) else math.nan


def is_close(left: float, right: float, absolute: float = 0.01) -> bool:
    return math.isclose(left, right, rel_tol=1e-9, abs_tol=absolute)


def main() -> int:
    checks = Checks()
    tables: dict[str, list[dict[str, str]]] = {}

    for filename, expected_header in CONTRACTS.items():
        path = PROCESSED / filename
        checks.check(f"file_exists::{filename}", path.is_file(), str(path))
        if not path.is_file():
            continue
        header, rows = read_csv(filename)
        tables[filename] = rows
        checks.check(
            f"header_exact::{filename}",
            header == expected_header,
            f"expected={expected_header}; actual={header}",
        )
        checks.check(f"has_rows::{filename}", len(rows) > 0, f"rows={len(rows)}")

    if len(tables) != len(CONTRACTS):
        failed = len(checks.failed)
        print(f"Power BI validation stopped: {failed} failed checks")
        return 1

    revenue = tables["monthly_revenue_orders.csv"]
    customers = tables["customer_purchase_summary.csv"]
    retention = tables["cohort_retention.csv"]
    horizons = tables["cohort_horizon_summary.csv"]
    rfm = tables["rfm_segment_summary.csv"]
    experience = tables["monthly_delivery_reviews.csv"]

    expected_months = [date(2017 + (month - 1) // 12, (month - 1) % 12 + 1, 1).isoformat() for month in range(1, 21)]
    revenue_months = [row["purchase_month"] for row in revenue]
    experience_months = [row["purchase_month"] for row in experience]
    checks.check("revenue_exact_reporting_months", revenue_months == expected_months, str(revenue_months))
    checks.check("experience_exact_reporting_months", experience_months == expected_months, str(experience_months))
    checks.check("revenue_month_key_unique", len(revenue_months) == len(set(revenue_months)), f"rows={len(revenue_months)}")
    checks.check("experience_month_key_unique", len(experience_months) == len(set(experience_months)), f"rows={len(experience_months)}")

    revenue_reconciles = all(
        is_close(number(row["gmv"]), number(row["item_value"]) + number(row["freight_value"]))
        for row in revenue
    )
    aov_reconciles = all(
        is_close(number(row["average_order_gmv"]), number(row["gmv"]) / int(row["orders_with_gmv"]))
        for row in revenue if int(row["orders_with_gmv"]) > 0
    )
    checks.check("monthly_gmv_reconciles", revenue_reconciles, "gmv = item_value + freight_value")
    checks.check("monthly_aov_complete_case", aov_reconciles, "average_order_gmv = gmv / orders_with_gmv")

    customer_ids = [row["customer_unique_id"] for row in customers]
    checks.check("customer_key_unique", len(customer_ids) == len(set(customer_ids)), f"rows={len(customer_ids)}")
    checks.check("customer_key_nonblank", all(customer_ids), f"blank={sum(not value for value in customer_ids)}")
    repeat_rule = all(
        (row["is_repeat_customer"].strip().lower() == "true") == (int(row["reporting_period_order_count"]) >= 2)
        for row in customers
    )
    checks.check("repeat_customer_rule", repeat_rule, "is_repeat_customer iff reporting_period_order_count >= 2")

    cohort_keys = [(row["cohort_month"], row["month_number"]) for row in retention]
    checks.check("cohort_key_unique", len(cohort_keys) == len(set(cohort_keys)), f"rows={len(cohort_keys)}")
    immature_blank = all(
        row["retention_rate"] == ""
        for row in retention
        if row["observation_window_complete"].strip().lower() != "true"
    )
    complete_reconciles = all(
        is_close(number(row["retention_rate"]), int(row["retained_customers"]) / int(row["cohort_size"]), 1e-12)
        for row in retention
        if row["observation_window_complete"].strip().lower() == "true"
    )
    checks.check("cohort_immature_rates_blank", immature_blank, "right-censored cells remain blank")
    checks.check("cohort_complete_rates_reconcile", complete_reconciles, "retained_customers / cohort_size")
    checks.check("cohort_month_age_range", all(0 <= int(row["month_number"]) <= 12 for row in retention), "expected 0-12")

    horizon_values = {int(row["month_number"]) for row in horizons}
    checks.check("cohort_horizons_exact", horizon_values == {1, 3, 6, 12}, str(sorted(horizon_values)))
    weighted_reconciles = all(
        is_close(number(row["weighted_retention_rate"]), int(row["retained_customer_count"]) / int(row["eligible_customer_count"]), 1e-12)
        for row in horizons
    )
    checks.check("weighted_retention_reconciles", weighted_reconciles, "retained / eligible customers")

    segment_names = [row["rfm_segment"] for row in rfm]
    checks.check("rfm_segment_key_unique", len(segment_names) == len(set(segment_names)), str(segment_names))
    rfm_customers = sum(int(row["customer_count"]) for row in rfm)
    rfm_orders = sum(int(row["order_count"]) for row in rfm)
    rfm_monetary = sum(number(row["monetary_value"]) for row in rfm)
    customer_orders = sum(int(row["reporting_period_order_count"]) for row in customers)
    customer_gmv = sum(number(row["reporting_period_gmv"]) for row in customers if row["reporting_period_gmv"] != "")
    checks.check("rfm_customer_population", rfm_customers == len(customers), f"rfm={rfm_customers}; customers={len(customers)}")
    checks.check("rfm_order_population", rfm_orders == customer_orders, f"rfm={rfm_orders}; customers={customer_orders}")
    checks.check("rfm_monetary_population", is_close(rfm_monetary, customer_gmv, 0.05), f"rfm={rfm_monetary:.2f}; customers={customer_gmv:.2f}")
    checks.check("rfm_shares_sum_to_one", is_close(sum(number(row["customer_share"]) for row in rfm), 1.0, 1e-9), "segment shares")

    review_components = all(
        int(row["reviewed_order_count"]) + int(row["unreviewed_order_count"]) == int(row["delivered_order_count"])
        for row in experience
    )
    coverage_reconciles = all(
        is_close(number(row["review_coverage_rate"]), int(row["reviewed_order_count"]) / int(row["delivered_order_count"]), 1e-12)
        for row in experience if int(row["delivered_order_count"]) > 0
    )
    checks.check("review_population_reconciles", review_components, "reviewed + unreviewed = delivered")
    checks.check("review_coverage_reconciles", coverage_reconciles, "reviewed / delivered")
    checks.check("late_delivery_rates_bounded", all(0 <= number(row["late_delivery_rate"]) <= 1 for row in experience), "all rates in [0,1]")

    json_files = [
        POWERBI / "theme" / "olist_portfolio_theme.json",
        PBIP / "OlistRetentionDashboard.pbip",
        PBIP / "OlistRetentionDashboard.Report" / "definition.pbir",
        PBIP / "OlistRetentionDashboard.Report" / ".platform",
        PBIP / "OlistRetentionDashboard.Report" / "definition" / "version.json",
        PBIP / "OlistRetentionDashboard.Report" / "definition" / "report.json",
        PBIP / "OlistRetentionDashboard.Report" / "definition" / "pages" / "pages.json",
        PBIP / "OlistRetentionDashboard.SemanticModel" / "definition.pbism",
        PBIP / "OlistRetentionDashboard.SemanticModel" / ".platform",
    ]
    for path in json_files:
        try:
            json.loads(path.read_text(encoding="utf-8"))
            valid = True
            detail = str(path.relative_to(ROOT))
        except (OSError, json.JSONDecodeError) as exc:
            valid = False
            detail = str(exc)
        checks.check(f"json_valid::{path.name}", valid, detail)

    pages_path = PBIP / "OlistRetentionDashboard.Report" / "definition" / "pages" / "pages.json"
    pages = json.loads(pages_path.read_text(encoding="utf-8"))
    checks.check("pbir_has_two_pages", len(pages["pageOrder"]) == 2, str(pages["pageOrder"]))

    table_dir = PBIP / "OlistRetentionDashboard.SemanticModel" / "definition" / "tables"
    expected_tmdl = {"Monthly Revenue.tmdl", "Customers.tmdl", "Cohort Retention.tmdl", "Cohort Horizons.tmdl", "RFM Segments.tmdl", "Monthly Experience.tmdl", "Date.tmdl"}
    actual_tmdl = {path.name for path in table_dir.glob("*.tmdl")}
    checks.check("semantic_model_tables_exact", actual_tmdl == expected_tmdl, str(sorted(actual_tmdl)))

    relationships_text = (PBIP / "OlistRetentionDashboard.SemanticModel" / "definition" / "relationships.tmdl").read_text(encoding="utf-8")
    checks.check("relationship_count_exact", len(re.findall(r"(?m)^relationship ", relationships_text)) == 2, "two Date-to-monthly-fact relationships")
    checks.check("relationships_single_direction", "crossFilteringBehavior: bothDirections" not in relationships_text, "no bidirectional relationship")

    dax = (POWERBI / "dax" / "measures.dax").read_text(encoding="utf-8")
    required_measures = {
        "Gross Order Value (GMV)", "Orders", "Unique Customers", "Average Order Value",
        "Repeat Customer Share", "Cohort Retention %", "Weighted Retention %",
        "RFM Customers", "Late Delivery Rate", "Average Review Score",
    }
    missing_measures = sorted(name for name in required_measures if f"{name} =" not in dax)
    checks.check("required_dax_measures_present", not missing_measures, f"missing={missing_measures}")
    checks.check("aov_uses_complete_case_denominator", "DIVIDE([Gross Order Value (GMV)], [Orders with GMV])" in dax, "Orders with GMV denominator")

    total_orders = sum(int(row["order_count"]) for row in revenue)
    orders_with_gmv = sum(int(row["orders_with_gmv"]) for row in revenue)
    total_gmv = sum(number(row["gmv"]) for row in revenue)
    repeat_customers = sum(row["is_repeat_customer"].strip().lower() == "true" for row in customers)
    delivered_orders = sum(int(row["delivered_order_count"]) for row in experience)
    reviewed_orders = sum(int(row["reviewed_order_count"]) for row in experience)
    late_deliveries = sum(int(row["delivered_order_count"]) * number(row["late_delivery_rate"]) for row in experience)
    weighted_review_score = sum(int(row["reviewed_order_count"]) * number(row["average_review_score"]) for row in experience) / reviewed_orders

    summary = {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "source_rows": {name: len(rows) for name, rows in tables.items()},
        "kpis": {
            "gross_order_value": round(total_gmv, 2),
            "orders": total_orders,
            "orders_with_gmv": orders_with_gmv,
            "unique_customers": len(customers),
            "average_order_value": round(total_gmv / orders_with_gmv, 2),
            "repeat_customers": repeat_customers,
            "repeat_customer_share": repeat_customers / len(customers),
            "delivered_orders": delivered_orders,
            "late_delivery_rate": late_deliveries / delivered_orders,
            "reviewed_orders": reviewed_orders,
            "average_review_score": weighted_review_score,
            "retention_horizons": {row["month_number"]: number(row["weighted_retention_rate"]) for row in horizons},
        },
        "checks_passed": len(checks.results) - len(checks.failed),
        "checks_failed": len(checks.failed),
        "checks": checks.results,
    }
    report_path = POWERBI / "validation_report.json"
    report_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    print(f"Power BI validation: {summary['checks_passed']} passed, {summary['checks_failed']} failed")
    for failure in checks.failed:
        print(f"FAIL {failure['check']}: {failure['detail']}")
    print(f"Report: {report_path}")
    return 1 if checks.failed else 0


if __name__ == "__main__":
    sys.exit(main())

