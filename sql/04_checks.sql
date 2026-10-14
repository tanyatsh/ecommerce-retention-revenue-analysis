CREATE OR REPLACE TABLE audit.validation_results AS
WITH checks AS (
    SELECT 'orders_unique_after_financial_joins' AS check_name,
           COUNT(*) = COUNT(DISTINCT order_id) AS passed,
           COUNT(*)::DOUBLE AS actual_value,
           COUNT(DISTINCT order_id)::DOUBLE AS expected_value,
           'critical' AS severity,
           'Order-level financial model must have one row per order.' AS details
    FROM analytics.fct_order_financials

    UNION ALL
    SELECT 'all_orders_retained_in_financial_model',
           (SELECT COUNT(*) FROM analytics.fct_order_financials) = (SELECT COUNT(*) FROM raw.orders),
           (SELECT COUNT(*) FROM analytics.fct_order_financials)::DOUBLE,
           (SELECT COUNT(*) FROM raw.orders)::DOUBLE,
           'critical', 'Left joins must retain every source order.'

    UNION ALL
    SELECT 'item_value_not_duplicated',
           ABS((SELECT SUM(item_value) FROM analytics.fct_order_financials) - (SELECT SUM(price) FROM raw.order_items)) < 0.01,
           (SELECT SUM(item_value) FROM analytics.fct_order_financials)::DOUBLE,
           (SELECT SUM(price) FROM raw.order_items)::DOUBLE,
           'critical', 'Order aggregation must preserve source item value exactly.'

    UNION ALL
    SELECT 'freight_not_duplicated',
           ABS((SELECT SUM(freight_value) FROM analytics.fct_order_financials) - (SELECT SUM(freight_value) FROM raw.order_items)) < 0.01,
           (SELECT SUM(freight_value) FROM analytics.fct_order_financials)::DOUBLE,
           (SELECT SUM(freight_value) FROM raw.order_items)::DOUBLE,
           'critical', 'Order aggregation must preserve source freight exactly.'

    UNION ALL
    SELECT 'payments_not_duplicated',
           ABS((SELECT SUM(payment_value) FROM analytics.fct_order_financials) - (SELECT SUM(payment_value) FROM raw.order_payments)) < 0.01,
           (SELECT SUM(payment_value) FROM analytics.fct_order_financials)::DOUBLE,
           (SELECT SUM(payment_value) FROM raw.order_payments)::DOUBLE,
           'critical', 'Order aggregation must preserve source payments exactly.'

    UNION ALL
    SELECT 'monthly_order_count_consistent',
           (SELECT SUM(order_count) FROM analytics.fct_monthly_revenue_orders) =
           (SELECT COUNT(*) FROM analytics.fct_order_financials f CROSS JOIN analytics.analysis_config c
            WHERE is_eligible_order AND purchase_month BETWEEN c.analysis_start_month AND c.last_complete_month),
           (SELECT SUM(order_count) FROM analytics.fct_monthly_revenue_orders)::DOUBLE,
           (SELECT COUNT(*) FROM analytics.fct_order_financials f CROSS JOIN analytics.analysis_config c
            WHERE is_eligible_order AND purchase_month BETWEEN c.analysis_start_month AND c.last_complete_month)::DOUBLE,
           'critical', 'Monthly orders must reconcile to eligible order-level rows in the core complete period.'

    UNION ALL
    SELECT 'monthly_gmv_consistent',
           ABS((SELECT SUM(gmv) FROM analytics.fct_monthly_revenue_orders) -
               (SELECT SUM(gmv) FROM analytics.fct_order_financials f CROSS JOIN analytics.analysis_config c
                WHERE is_eligible_order AND purchase_month BETWEEN c.analysis_start_month AND c.last_complete_month)) < 0.01,
           (SELECT SUM(gmv) FROM analytics.fct_monthly_revenue_orders)::DOUBLE,
           (SELECT SUM(gmv) FROM analytics.fct_order_financials f CROSS JOIN analytics.analysis_config c
            WHERE is_eligible_order AND purchase_month BETWEEN c.analysis_start_month AND c.last_complete_month)::DOUBLE,
           'critical', 'Monthly GMV must reconcile to eligible order-level GMV in the core complete period.'

    UNION ALL
    SELECT 'all_period_monthly_orders_reconcile',
           (SELECT SUM(order_count) FROM analytics.int_monthly_revenue_orders_all_periods) =
           (SELECT COUNT(*) FROM analytics.fct_order_financials WHERE is_eligible_order AND purchase_month IS NOT NULL),
           (SELECT SUM(order_count) FROM analytics.int_monthly_revenue_orders_all_periods)::DOUBLE,
           (SELECT COUNT(*) FROM analytics.fct_order_financials WHERE is_eligible_order AND purchase_month IS NOT NULL)::DOUBLE,
           'critical', 'The unfiltered monthly audit table must retain every eligible order.'

    UNION ALL
    SELECT 'monthly_export_contains_only_core_complete_period',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'critical',
           'Power BI monthly revenue rows must remain within the documented complete period.'
    FROM analytics.fct_monthly_revenue_orders m
    CROSS JOIN analytics.analysis_config c
    WHERE m.purchase_month NOT BETWEEN c.analysis_start_month AND c.last_complete_month

    UNION ALL
    SELECT 'dashboard_exports_share_reporting_period',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'critical',
           'Dashboard-facing financial, customer, cohort, RFM, and delivery exports must use the documented reporting cutoff.'
    FROM (
        SELECT f.purchase_month AS period_value
        FROM analytics.fct_order_financials_reporting f CROSS JOIN analytics.analysis_config c
        WHERE f.purchase_month NOT BETWEEN c.analysis_start_month AND c.last_complete_month
        UNION ALL
        SELECT CAST(date_trunc('month', s.first_reporting_purchase_timestamp) AS DATE)
        FROM analytics.dim_customer_purchase_summary s CROSS JOIN analytics.analysis_config c
        WHERE CAST(date_trunc('month', s.first_reporting_purchase_timestamp) AS DATE) NOT BETWEEN c.analysis_start_month AND c.last_complete_month
           OR CAST(date_trunc('month', s.last_reporting_purchase_timestamp) AS DATE) NOT BETWEEN c.analysis_start_month AND c.last_complete_month
        UNION ALL
        SELECT d.purchase_month
        FROM analytics.fct_order_delivery_reviews d CROSS JOIN analytics.analysis_config c
        WHERE d.purchase_month NOT BETWEEN c.analysis_start_month AND c.last_complete_month
        UNION ALL
        SELECT m.purchase_month
        FROM analytics.fct_monthly_delivery_reviews m CROSS JOIN analytics.analysis_config c
        WHERE m.purchase_month NOT BETWEEN c.analysis_start_month AND c.last_complete_month
        UNION ALL
        SELECT r.snapshot_date
        FROM analytics.dim_customer_rfm r CROSS JOIN analytics.analysis_config c
        WHERE r.snapshot_date <> c.observation_cutoff + 1
    ) temporal_violations

    UNION ALL
    SELECT 'full_history_customer_metrics_preserved',
           COUNT(*) = (SELECT COUNT(DISTINCT customer_unique_id) FROM analytics.fct_order_financials WHERE is_eligible_order),
           COUNT(*)::DOUBLE,
           (SELECT COUNT(DISTINCT customer_unique_id) FROM analytics.fct_order_financials WHERE is_eligible_order)::DOUBLE,
           'critical', 'The explicitly named full-history customer summary must preserve all eligible customers.'
    FROM analytics.dim_customer_purchase_summary_full_history

    UNION ALL
    SELECT 'customer_summary_unique',
           COUNT(*) = COUNT(DISTINCT customer_unique_id), COUNT(*)::DOUBLE,
           COUNT(DISTINCT customer_unique_id)::DOUBLE, 'critical',
           'Customer summary must have one row per customer_unique_id.'
    FROM analytics.dim_customer_purchase_summary

    UNION ALL
    SELECT 'repeat_customer_denominator_consistent',
           (SELECT COUNT(*) FROM analytics.dim_customer_purchase_summary) =
           (SELECT COUNT(DISTINCT c.customer_unique_id) FROM raw.orders o JOIN raw.customers c USING (customer_id)
            CROSS JOIN analytics.analysis_config cfg
            WHERE o.order_status IN ('approved', 'processing', 'invoiced', 'shipped', 'delivered')
              AND CAST(date_trunc('month', o.order_purchase_timestamp) AS DATE) BETWEEN cfg.analysis_start_month AND cfg.last_complete_month),
           (SELECT COUNT(*) FROM analytics.dim_customer_purchase_summary)::DOUBLE,
           (SELECT COUNT(DISTINCT c.customer_unique_id) FROM raw.orders o JOIN raw.customers c USING (customer_id)
            CROSS JOIN analytics.analysis_config cfg
            WHERE o.order_status IN ('approved', 'processing', 'invoiced', 'shipped', 'delivered')
              AND CAST(date_trunc('month', o.order_purchase_timestamp) AS DATE) BETWEEN cfg.analysis_start_month AND cfg.last_complete_month)::DOUBLE,
           'critical', 'Repeat purchase denominator must be unique customer_unique_id values with eligible reporting-period orders.'

    UNION ALL
    SELECT 'repeat_customer_numerator_consistent',
           (SELECT COUNT(*) FROM analytics.dim_customer_purchase_summary WHERE is_repeat_customer) =
           (SELECT COUNT(*) FROM (
                SELECT c.customer_unique_id
                FROM raw.orders o JOIN raw.customers c USING (customer_id)
                CROSS JOIN analytics.analysis_config cfg
                WHERE o.order_status IN ('approved', 'processing', 'invoiced', 'shipped', 'delivered')
                  AND CAST(date_trunc('month', o.order_purchase_timestamp) AS DATE) BETWEEN cfg.analysis_start_month AND cfg.last_complete_month
                GROUP BY c.customer_unique_id HAVING COUNT(DISTINCT o.order_id) >= 2
            )),
           (SELECT COUNT(*) FROM analytics.dim_customer_purchase_summary WHERE is_repeat_customer)::DOUBLE,
           (SELECT COUNT(*) FROM (
                SELECT c.customer_unique_id
                FROM raw.orders o JOIN raw.customers c USING (customer_id)
                CROSS JOIN analytics.analysis_config cfg
                WHERE o.order_status IN ('approved', 'processing', 'invoiced', 'shipped', 'delivered')
                  AND CAST(date_trunc('month', o.order_purchase_timestamp) AS DATE) BETWEEN cfg.analysis_start_month AND cfg.last_complete_month
                GROUP BY c.customer_unique_id HAVING COUNT(DISTINCT o.order_id) >= 2
            ))::DOUBLE,
           'critical', 'Repeat purchase numerator must count customers with at least two distinct eligible reporting-period orders.'

    UNION ALL
    SELECT 'customer_missing_gmv_flags_reconcile',
           (SELECT SUM(orders_missing_gmv) FROM analytics.dim_customer_purchase_summary) =
           (SELECT COUNT(*) FROM analytics.fct_order_financials_reporting WHERE is_eligible_order AND gmv IS NULL),
           (SELECT SUM(orders_missing_gmv) FROM analytics.dim_customer_purchase_summary)::DOUBLE,
           (SELECT COUNT(*) FROM analytics.fct_order_financials_reporting WHERE is_eligible_order AND gmv IS NULL)::DOUBLE,
           'critical', 'Customer-level missing GMV counts must reconcile to eligible order rows.'

    UNION ALL
    SELECT 'customer_missing_payment_flags_reconcile',
           (SELECT SUM(orders_missing_payment) FROM analytics.dim_customer_purchase_summary) =
           (SELECT COUNT(*) FROM analytics.fct_order_financials_reporting WHERE is_eligible_order AND payment_value IS NULL),
           (SELECT SUM(orders_missing_payment) FROM analytics.dim_customer_purchase_summary)::DOUBLE,
           (SELECT COUNT(*) FROM analytics.fct_order_financials_reporting WHERE is_eligible_order AND payment_value IS NULL)::DOUBLE,
           'critical', 'Customer-level missing payment counts must reconcile to eligible order rows.'

    UNION ALL
    SELECT 'cohort_retention_within_bounds',
           COUNT(*) FILTER (WHERE retained_customers > cohort_size OR retained_customers < 0) = 0,
           COUNT(*) FILTER (WHERE retained_customers > cohort_size OR retained_customers < 0)::DOUBLE,
           0::DOUBLE, 'critical', 'Retained customers cannot exceed cohort size.'
    FROM analytics.dim_cohort_retention

    UNION ALL
    SELECT 'cohort_month_number_matches_calendar_months',
           COUNT(*) FILTER (WHERE month_number <> date_diff('month', cohort_month, activity_month)) = 0,
           COUNT(*) FILTER (WHERE month_number <> date_diff('month', cohort_month, activity_month))::DOUBLE,
           0::DOUBLE, 'critical', 'Cohort age must use calendar-month boundaries after month truncation.'
    FROM analytics.int_customer_months

    UNION ALL
    SELECT 'cohort_boundary_semantics',
           date_diff('month', date_trunc('month', TIMESTAMP '2017-01-31 23:59:59'), date_trunc('month', TIMESTAMP '2017-02-01 00:00:00')) = 1
           AND date_diff('month', date_trunc('month', TIMESTAMP '2017-01-01 00:00:00'), date_trunc('month', TIMESTAMP '2017-01-31 23:59:59')) = 0,
           1::DOUBLE, 1::DOUBLE, 'critical',
           'Adjacent calendar months must be month 1 even when timestamps are one second apart; dates in one month must be month 0.'

    UNION ALL
    SELECT 'weighted_cohort_summary_reconciles',
           COALESCE(MAX(ABS(s.weighted_retention_rate - x.expected_rate)), 0) < 0.000000000001,
           COALESCE(MAX(ABS(s.weighted_retention_rate - x.expected_rate)), 0)::DOUBLE,
           0::DOUBLE, 'critical', 'Weighted cohort retention must equal total retained customers divided by total eligible customers for mature cohorts.'
    FROM analytics.fct_cohort_horizon_summary s
    JOIN (
        SELECT month_number, SUM(retained_customers)::DOUBLE / SUM(cohort_size) AS expected_rate
        FROM analytics.dim_cohort_retention
        WHERE observation_window_complete AND month_number IN (1, 3, 6, 12)
        GROUP BY month_number
    ) x USING (month_number)

    UNION ALL
    SELECT 'cohort_summary_has_fixed_horizons',
           COUNT(*) = 4 AND MIN(month_number) = 1 AND MAX(month_number) = 12,
           COUNT(*)::DOUBLE, 4::DOUBLE, 'critical',
           'Weighted cohort summary must contain the four documented horizons: 1, 3, 6, and 12 months.'
    FROM analytics.fct_cohort_horizon_summary

    UNION ALL
    SELECT 'right_censored_retention_is_null',
           COUNT(*) FILTER (WHERE NOT observation_window_complete AND retention_rate IS NOT NULL) = 0,
           COUNT(*) FILTER (WHERE NOT observation_window_complete AND retention_rate IS NOT NULL)::DOUBLE,
           0::DOUBLE, 'critical', 'Incomplete observation windows must not report retention.'
    FROM analytics.dim_cohort_retention

    UNION ALL
    SELECT 'order_reviews_do_not_duplicate_deliveries',
           COUNT(*) = COUNT(DISTINCT order_id), COUNT(*)::DOUBLE,
           COUNT(DISTINCT order_id)::DOUBLE, 'critical',
           'Review aggregation must preserve one delivery row per order.'
    FROM analytics.fct_order_delivery_reviews

    UNION ALL
    SELECT 'review_records_preserved_by_order_aggregation',
           (SELECT SUM(review_record_count) FROM analytics.int_order_reviews) = (SELECT COUNT(*) FROM raw.order_reviews),
           (SELECT SUM(review_record_count) FROM analytics.int_order_reviews)::DOUBLE,
           (SELECT COUNT(*) FROM raw.order_reviews)::DOUBLE,
           'critical', 'Order review aggregation must preserve the source review-record count.'

    UNION ALL
    SELECT 'review_coverage_counts_reconcile',
           SUM(reviewed_order_count + unreviewed_order_count) = SUM(delivered_order_count),
           SUM(reviewed_order_count + unreviewed_order_count)::DOUBLE,
           SUM(delivered_order_count)::DOUBLE,
           'critical', 'Reviewed and unreviewed order counts must add to delivered orders in monthly review metrics.'
    FROM analytics.fct_monthly_delivery_reviews

    UNION ALL
    SELECT 'late_delivery_matches_calendar_delay',
           COUNT(*) FILTER (WHERE is_late_delivery <> (delivery_delay_days > 0)) = 0,
           COUNT(*) FILTER (WHERE is_late_delivery <> (delivery_delay_days > 0))::DOUBLE,
           0::DOUBLE, 'critical', 'Late delivery must use the same calendar-day definition as delivery_delay_days.'
    FROM analytics.fct_order_delivery_reviews_full_history

    UNION ALL
    SELECT 'late_delivery_timestamp_conflicts_are_same_day',
           COUNT(*) FILTER (WHERE has_late_classification_conflict) =
           COUNT(*) FILTER (WHERE delivery_delay_days = 0 AND is_late_delivery_timestamp_comparison),
           COUNT(*) FILTER (WHERE has_late_classification_conflict)::DOUBLE,
           COUNT(*) FILTER (WHERE delivery_delay_days = 0 AND is_late_delivery_timestamp_comparison)::DOUBLE,
           'critical', 'Timestamp/calendar conflicts must be limited to deliveries later on the estimated calendar date.'
    FROM analytics.fct_order_delivery_reviews_full_history

    UNION ALL
    SELECT 'rfm_frequency_ties_preserve_scores',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'critical',
           'Customers with the same frequency must not receive different frequency scores.'
    FROM (
        SELECT frequency_orders FROM analytics.dim_customer_rfm
        GROUP BY frequency_orders HAVING COUNT(DISTINCT frequency_score) > 1
    ) tie_splits

    UNION ALL
    SELECT 'rfm_recency_ties_preserve_scores',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'critical',
           'Customers with the same recency must not receive different recency scores.'
    FROM (
        SELECT recency_days FROM analytics.dim_customer_rfm
        GROUP BY recency_days HAVING COUNT(DISTINCT recency_score) > 1
    ) tie_splits

    UNION ALL
    SELECT 'rfm_monetary_ties_preserve_scores',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'critical',
           'Customers with the same monetary value must not receive different monetary scores.'
    FROM (
        SELECT monetary_gmv FROM analytics.dim_customer_rfm WHERE monetary_gmv IS NOT NULL
        GROUP BY monetary_gmv HAVING COUNT(DISTINCT monetary_score) > 1
    ) tie_splits

    UNION ALL
    SELECT 'rfm_frequency_bands_match_thresholds',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'critical',
           'RFM frequency bands must map 1 order to one-time, 2 to repeat, and 3+ to frequent.'
    FROM analytics.dim_customer_rfm
    WHERE (frequency_orders = 1 AND frequency_band <> 'One-time: 1 order')
       OR (frequency_orders = 2 AND frequency_band <> 'Repeat: 2 orders')
       OR (frequency_orders >= 3 AND frequency_band <> 'Frequent: 3+ orders')

    UNION ALL
    SELECT 'rfm_segment_summary_reconciles',
           s.customers = r.customers AND s.orders = r.orders AND ABS(s.monetary - r.monetary) < 0.01,
           s.customers::DOUBLE, r.customers::DOUBLE, 'critical',
           'RFM segment summary customer, order, and monetary totals must reconcile to customer-level RFM.'
    FROM (
        SELECT SUM(customer_count) AS customers, SUM(order_count) AS orders, SUM(monetary_value) AS monetary
        FROM analytics.fct_rfm_segment_summary
    ) s
    CROSS JOIN (
        SELECT COUNT(*) AS customers, SUM(frequency_orders) AS orders, SUM(monetary_gmv) AS monetary
        FROM analytics.dim_customer_rfm
    ) r

    UNION ALL
    SELECT 'orders_have_customers',
           COUNT(*) FILTER (WHERE customer_unique_id IS NULL) = 0,
           COUNT(*) FILTER (WHERE customer_unique_id IS NULL)::DOUBLE,
           0::DOUBLE, 'critical', 'Every order should join to a source customer.'
    FROM analytics.fct_order_financials

    UNION ALL
    SELECT 'items_reference_orders',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'critical',
           'Every order item should reference a source order.'
    FROM raw.order_items i LEFT JOIN raw.orders o USING (order_id) WHERE o.order_id IS NULL

    UNION ALL
    SELECT 'payments_reference_orders',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'critical',
           'Every payment should reference a source order.'
    FROM raw.order_payments p LEFT JOIN raw.orders o USING (order_id) WHERE o.order_id IS NULL

    UNION ALL
    SELECT 'eligible_orders_have_item_records',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'warning',
           'Eligible orders without item rows retain null item value, freight, and GMV.'
    FROM analytics.fct_order_financials WHERE is_eligible_order AND NOT has_item_data

    UNION ALL
    SELECT 'eligible_orders_have_payment_records',
           COUNT(*) = 0, COUNT(*)::DOUBLE, 0::DOUBLE, 'warning',
           'Eligible orders without payment rows retain a null payment value.'
    FROM analytics.fct_order_financials WHERE is_eligible_order AND NOT has_payment_data
)
SELECT * FROM checks ORDER BY check_name;

