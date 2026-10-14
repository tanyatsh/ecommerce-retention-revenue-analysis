import unittest
from datetime import timedelta
from pathlib import Path

import duckdb


ROOT = Path(__file__).resolve().parents[1]


class PipelineIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db_path = ROOT / "data" / "ecommerce.duckdb"
        if not cls.db_path.exists():
            raise RuntimeError("Run src/run_pipeline.py before the integration tests.")
        cls.con = duckdb.connect(str(cls.db_path), read_only=True)

    @classmethod
    def tearDownClass(cls):
        cls.con.close()

    def test_all_critical_validations_pass(self):
        failures = self.con.execute(
            "SELECT check_name, details FROM audit.validation_results WHERE severity = 'critical' AND NOT passed"
        ).fetchall()
        self.assertEqual([], failures)

    def test_all_nine_sources_are_profiled(self):
        count = self.con.execute("SELECT COUNT(*) FROM audit.source_profile").fetchone()[0]
        self.assertEqual(9, count)

    def test_power_bi_exports_exist_and_are_nonempty(self):
        expected = [
            "order_financials.csv", "order_financials_full_history.csv", "monthly_revenue_orders.csv",
            "customer_purchase_summary.csv", "customer_purchase_summary_full_history.csv",
            "cohort_retention.csv", "cohort_fixed_windows.csv", "customer_rfm.csv",
            "cohort_horizon_summary.csv", "customer_rfm_full_history.csv", "rfm_segment_summary.csv",
            "order_delivery_reviews.csv", "order_delivery_reviews_full_history.csv", "monthly_delivery_reviews.csv",
        ]
        for filename in expected:
            path = ROOT / "data" / "processed" / filename
            with self.subTest(filename=filename):
                self.assertTrue(path.is_file())
                self.assertGreater(path.stat().st_size, 0)

    def test_power_bi_export_grains_are_unique(self):
        checks = {
            "analytics.fct_order_financials_reporting": "order_id",
            "analytics.fct_monthly_revenue_orders": "purchase_month",
            "analytics.dim_customer_purchase_summary": "customer_unique_id",
            "analytics.dim_cohort_retention": "cohort_month, month_number",
            "analytics.fct_cohort_fixed_windows": "cohort_month",
            "analytics.fct_cohort_horizon_summary": "month_number",
            "analytics.dim_customer_rfm": "customer_unique_id",
            "analytics.fct_rfm_segment_summary": "rfm_segment",
            "analytics.fct_order_delivery_reviews": "order_id",
            "analytics.fct_monthly_delivery_reviews": "purchase_month",
        }
        for table, key in checks.items():
            total, distinct_keys = self.con.execute(
                f"SELECT COUNT(*), COUNT(*) FROM (SELECT {key} FROM {table} GROUP BY {key})"
            ).fetchone()
            source_total = self.con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            with self.subTest(table=table):
                self.assertEqual(source_total, total)
                self.assertEqual(total, distinct_keys)

    def test_dashboard_exports_use_reporting_cutoff(self):
        start_month, end_month, cutoff = self.con.execute(
            "SELECT analysis_start_month, last_complete_month, observation_cutoff FROM analytics.analysis_config"
        ).fetchone()
        for table in [
            "analytics.fct_order_financials_reporting",
            "analytics.fct_monthly_revenue_orders",
            "analytics.fct_order_delivery_reviews",
            "analytics.fct_monthly_delivery_reviews",
        ]:
            minimum, maximum = self.con.execute(
                f"SELECT MIN(purchase_month), MAX(purchase_month) FROM {table}"
            ).fetchone()
            with self.subTest(table=table):
                self.assertGreaterEqual(minimum, start_month)
                self.assertLessEqual(maximum, end_month)
        snapshots = self.con.execute("SELECT DISTINCT snapshot_date FROM analytics.dim_customer_rfm").fetchall()
        self.assertEqual([(cutoff + timedelta(days=1),)], snapshots)

    def test_delivery_and_rfm_regressions(self):
        inconsistent_delivery = self.con.execute(
            "SELECT COUNT(*) FROM analytics.fct_order_delivery_reviews_full_history WHERE is_late_delivery <> (delivery_delay_days > 0)"
        ).fetchone()[0]
        self.assertEqual(0, inconsistent_delivery)
        invalid_frequency_bands = self.con.execute(
            """
            SELECT COUNT(*) FROM analytics.dim_customer_rfm
            WHERE (frequency_orders = 1 AND frequency_band <> 'One-time: 1 order')
               OR (frequency_orders = 2 AND frequency_band <> 'Repeat: 2 orders')
               OR (frequency_orders >= 3 AND frequency_band <> 'Frequent: 3+ orders')
            """
        ).fetchone()[0]
        self.assertEqual(0, invalid_frequency_bands)


if __name__ == "__main__":
    unittest.main()
