CREATE OR REPLACE TABLE analytics.analysis_config AS
SELECT
    DATE '2017-01-01' AS analysis_start_month,
    CAST(date_trunc('month', MAX(order_purchase_timestamp)) - INTERVAL '1 month' AS DATE) AS last_complete_month,
    CAST(last_day(date_trunc('month', MAX(order_purchase_timestamp)) - INTERVAL '1 month') AS DATE) AS observation_cutoff
FROM analytics.fct_order_financials
WHERE is_eligible_order;

CREATE OR REPLACE TABLE analytics.fct_order_financials_reporting AS
SELECT f.*, TRUE AS is_reporting_period
FROM analytics.fct_order_financials f
CROSS JOIN analytics.analysis_config c
WHERE f.purchase_month BETWEEN c.analysis_start_month AND c.last_complete_month;

CREATE OR REPLACE TABLE analytics.int_monthly_revenue_orders_all_periods AS
SELECT
    purchase_month,
    COUNT(DISTINCT order_id) AS order_count,
    COUNT(gmv) AS orders_with_gmv,
    COUNT(*) FILTER (WHERE gmv IS NULL) AS orders_missing_gmv,
    COUNT(payment_value) AS orders_with_payment,
    COUNT(*) FILTER (WHERE payment_value IS NULL) AS orders_missing_payment,
    COUNT(DISTINCT customer_unique_id) AS unique_customers,
    SUM(item_value)::DECIMAL(18, 2) AS item_value,
    SUM(freight_value)::DECIMAL(18, 2) AS freight_value,
    SUM(gmv)::DECIMAL(18, 2) AS gmv,
    SUM(payment_value)::DECIMAL(18, 2) AS payment_value,
    AVG(gmv)::DECIMAL(18, 2) AS average_order_gmv
FROM analytics.fct_order_financials
WHERE is_eligible_order AND purchase_month IS NOT NULL
GROUP BY purchase_month
ORDER BY purchase_month;

CREATE OR REPLACE TABLE analytics.fct_monthly_revenue_orders AS
SELECT
    m.*,
    'core_complete_period'::VARCHAR AS period_quality
FROM analytics.int_monthly_revenue_orders_all_periods m
CROSS JOIN analytics.analysis_config c
WHERE m.purchase_month BETWEEN c.analysis_start_month AND c.last_complete_month
ORDER BY m.purchase_month;

CREATE OR REPLACE TABLE analytics.dim_customer_purchase_summary_full_history AS
SELECT
    customer_unique_id,
    MIN(order_purchase_timestamp) AS first_purchase_timestamp,
    MAX(order_purchase_timestamp) AS last_purchase_timestamp,
    COUNT(DISTINCT order_id) AS lifetime_order_count,
    SUM(item_value)::DECIMAL(18, 2) AS lifetime_item_value,
    SUM(freight_value)::DECIMAL(18, 2) AS lifetime_freight_value,
    SUM(gmv)::DECIMAL(18, 2) AS lifetime_gmv,
    SUM(payment_value)::DECIMAL(18, 2) AS lifetime_payment_value,
    COUNT(*) FILTER (WHERE gmv IS NULL) AS orders_missing_gmv,
    COUNT(*) FILTER (WHERE payment_value IS NULL) AS orders_missing_payment,
    COUNT(DISTINCT order_id) >= 2 AS is_repeat_customer
FROM analytics.fct_order_financials
WHERE is_eligible_order AND customer_unique_id IS NOT NULL
GROUP BY customer_unique_id;

CREATE OR REPLACE TABLE analytics.dim_customer_purchase_summary AS
SELECT
    customer_unique_id,
    MIN(order_purchase_timestamp) AS first_reporting_purchase_timestamp,
    MAX(order_purchase_timestamp) AS last_reporting_purchase_timestamp,
    COUNT(DISTINCT order_id) AS reporting_period_order_count,
    SUM(item_value)::DECIMAL(18, 2) AS reporting_period_item_value,
    SUM(freight_value)::DECIMAL(18, 2) AS reporting_period_freight_value,
    SUM(gmv)::DECIMAL(18, 2) AS reporting_period_gmv,
    SUM(payment_value)::DECIMAL(18, 2) AS reporting_period_payment_value,
    COUNT(*) FILTER (WHERE gmv IS NULL) AS orders_missing_gmv,
    COUNT(*) FILTER (WHERE payment_value IS NULL) AS orders_missing_payment,
    COUNT(DISTINCT order_id) >= 2 AS is_repeat_customer
FROM analytics.fct_order_financials f
CROSS JOIN analytics.analysis_config c
WHERE is_eligible_order
  AND customer_unique_id IS NOT NULL
  AND purchase_month BETWEEN c.analysis_start_month AND c.last_complete_month
GROUP BY customer_unique_id;

CREATE OR REPLACE TABLE analytics.int_customer_months AS
WITH customer_orders AS (
    SELECT DISTINCT
        customer_unique_id,
        CAST(date_trunc('month', order_purchase_timestamp) AS DATE) AS activity_month
    FROM analytics.fct_order_financials
    WHERE is_eligible_order
      AND customer_unique_id IS NOT NULL
      AND order_purchase_timestamp IS NOT NULL
), first_orders AS (
    SELECT customer_unique_id, MIN(activity_month) AS cohort_month
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    o.customer_unique_id,
    f.cohort_month,
    o.activity_month,
    date_diff('month', f.cohort_month, o.activity_month) AS month_number
FROM customer_orders o
JOIN first_orders f USING (customer_unique_id);

CREATE OR REPLACE TABLE analytics.dim_cohort_retention AS
WITH cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM analytics.int_customer_months
    CROSS JOIN analytics.analysis_config c
    WHERE month_number = 0
      AND cohort_month BETWEEN c.analysis_start_month AND c.last_complete_month
    GROUP BY cohort_month
), retained AS (
    SELECT cohort_month, month_number, COUNT(DISTINCT customer_unique_id) AS retained_customers
    FROM analytics.int_customer_months
    WHERE month_number BETWEEN 0 AND 12
    GROUP BY cohort_month, month_number
), observation AS (
    SELECT observation_cutoff FROM analytics.analysis_config
), grid AS (
    SELECT c.cohort_month, c.cohort_size, r.range AS month_number
    FROM cohort_sizes c
    CROSS JOIN range(0, 13) r
)
SELECT
    g.cohort_month,
    g.month_number,
    g.cohort_size,
    COALESCE(a.retained_customers, 0) AS retained_customers,
    o.observation_cutoff,
    last_day(g.cohort_month + g.month_number * INTERVAL '1 month') <= o.observation_cutoff AS observation_window_complete,
    CASE
        WHEN last_day(g.cohort_month + g.month_number * INTERVAL '1 month') <= o.observation_cutoff
        THEN COALESCE(a.retained_customers, 0)::DOUBLE / NULLIF(g.cohort_size, 0)
        ELSE NULL
    END AS retention_rate
FROM grid g
CROSS JOIN observation o
LEFT JOIN retained a
    ON g.cohort_month = a.cohort_month
   AND g.month_number = a.month_number
ORDER BY g.cohort_month, g.month_number;

CREATE OR REPLACE TABLE analytics.fct_cohort_fixed_windows AS
SELECT
    cohort_month,
    MAX(cohort_size) AS cohort_size,
    MAX(observation_cutoff) AS observation_cutoff,
    MAX(CASE WHEN month_number = 1 THEN retention_rate END) AS month_1_retention,
    MAX(CASE WHEN month_number = 3 THEN retention_rate END) AS month_3_retention,
    MAX(CASE WHEN month_number = 6 THEN retention_rate END) AS month_6_retention,
    MAX(CASE WHEN month_number = 12 THEN retention_rate END) AS month_12_retention,
    BOOL_AND(CASE WHEN month_number = 1 THEN observation_window_complete ELSE TRUE END) AS month_1_complete,
    BOOL_AND(CASE WHEN month_number = 3 THEN observation_window_complete ELSE TRUE END) AS month_3_complete,
    BOOL_AND(CASE WHEN month_number = 6 THEN observation_window_complete ELSE TRUE END) AS month_6_complete,
    BOOL_AND(CASE WHEN month_number = 12 THEN observation_window_complete ELSE TRUE END) AS month_12_complete
FROM analytics.dim_cohort_retention
GROUP BY cohort_month
ORDER BY cohort_month;

CREATE OR REPLACE TABLE analytics.fct_cohort_horizon_summary AS
SELECT
    month_number,
    COUNT(*) AS mature_cohort_count,
    SUM(cohort_size) AS eligible_customer_count,
    SUM(retained_customers) AS retained_customer_count,
    SUM(retained_customers)::DOUBLE / NULLIF(SUM(cohort_size), 0) AS weighted_retention_rate
FROM analytics.dim_cohort_retention
WHERE observation_window_complete
  AND month_number IN (1, 3, 6, 12)
GROUP BY month_number
ORDER BY month_number;

CREATE OR REPLACE TABLE analytics.int_customer_rfm_measures AS
WITH reporting AS (
    SELECT
        'reporting_period'::VARCHAR AS metric_scope,
        customer_unique_id,
        date_diff('day', CAST(MAX(order_purchase_timestamp) AS DATE), c.observation_cutoff + 1) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency_orders,
        SUM(gmv)::DECIMAL(18, 2) AS monetary_gmv,
        COUNT(*) FILTER (WHERE gmv IS NULL) AS orders_missing_gmv,
        c.observation_cutoff + 1 AS snapshot_date
    FROM analytics.fct_order_financials f
    CROSS JOIN analytics.analysis_config c
    WHERE is_eligible_order
      AND customer_unique_id IS NOT NULL
      AND purchase_month BETWEEN c.analysis_start_month AND c.last_complete_month
    GROUP BY customer_unique_id, c.observation_cutoff
), full_history_snapshot AS (
    SELECT CAST(MAX(order_purchase_timestamp) AS DATE) + 1 AS snapshot_date
    FROM analytics.fct_order_financials
    WHERE is_eligible_order
), full_history AS (
    SELECT
        'full_history'::VARCHAR AS metric_scope,
        customer_unique_id,
        date_diff('day', CAST(MAX(order_purchase_timestamp) AS DATE), s.snapshot_date) AS recency_days,
        COUNT(DISTINCT order_id) AS frequency_orders,
        SUM(gmv)::DECIMAL(18, 2) AS monetary_gmv,
        COUNT(*) FILTER (WHERE gmv IS NULL) AS orders_missing_gmv,
        s.snapshot_date
    FROM analytics.fct_order_financials
    CROSS JOIN full_history_snapshot s
    WHERE is_eligible_order AND customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id, s.snapshot_date
)
SELECT * FROM reporting
UNION ALL
SELECT * FROM full_history;

CREATE OR REPLACE TABLE analytics.int_customer_rfm_segmented AS
WITH bands AS (
    SELECT
        *,
        CASE
            WHEN recency_days <= 90 THEN 'Active: 0-90 days'
            WHEN recency_days <= 180 THEN 'Warm: 91-180 days'
            WHEN recency_days <= 365 THEN 'Cooling: 181-365 days'
            ELSE 'Dormant: 366+ days'
        END AS recency_band,
        CASE
            WHEN frequency_orders = 1 THEN 'One-time: 1 order'
            WHEN frequency_orders = 2 THEN 'Repeat: 2 orders'
            ELSE 'Frequent: 3+ orders'
        END AS frequency_band,
        CASE
            WHEN monetary_gmv IS NULL THEN 'Unknown'
            WHEN monetary_gmv < 100 THEN 'Low: under 100'
            WHEN monetary_gmv < 200 THEN 'Mid: 100-199.99'
            ELSE 'High: 200+'
        END AS monetary_band,
        CASE WHEN recency_days <= 90 THEN 4 WHEN recency_days <= 180 THEN 3 WHEN recency_days <= 365 THEN 2 ELSE 1 END AS recency_score,
        CASE WHEN frequency_orders = 1 THEN 1 WHEN frequency_orders = 2 THEN 3 ELSE 5 END AS frequency_score,
        CASE WHEN monetary_gmv IS NULL THEN NULL WHEN monetary_gmv < 100 THEN 1 WHEN monetary_gmv < 200 THEN 3 ELSE 5 END AS monetary_score
    FROM analytics.int_customer_rfm_measures
)
SELECT
    *,
    CASE WHEN monetary_score IS NOT NULL THEN CONCAT(recency_score, frequency_score, monetary_score) END AS rfm_score,
    CASE
        WHEN monetary_gmv IS NULL THEN 'Incomplete financial data'
        WHEN frequency_orders >= 3 AND recency_days <= 180 THEN 'Champions'
        WHEN frequency_orders = 2 AND recency_days <= 180 THEN 'Loyal repeat'
        WHEN frequency_orders >= 2 AND recency_days > 180 THEN 'At-risk repeat'
        WHEN frequency_orders = 1 AND recency_days <= 180 AND monetary_gmv >= 200 THEN 'High-value recent one-time'
        WHEN frequency_orders = 1 AND recency_days <= 180 THEN 'Recent one-time'
        WHEN frequency_orders = 1 AND recency_days > 180 AND monetary_gmv >= 200 THEN 'High-value lapsed one-time'
        WHEN frequency_orders = 1 AND recency_days <= 365 THEN 'Cooling one-time'
        ELSE 'Lapsed one-time'
    END AS rfm_segment
FROM bands;

CREATE OR REPLACE TABLE analytics.dim_customer_rfm AS
SELECT * EXCLUDE (metric_scope)
FROM analytics.int_customer_rfm_segmented
WHERE metric_scope = 'reporting_period';

CREATE OR REPLACE TABLE analytics.dim_customer_rfm_full_history AS
SELECT * EXCLUDE (metric_scope)
FROM analytics.int_customer_rfm_segmented
WHERE metric_scope = 'full_history';

CREATE OR REPLACE TABLE analytics.fct_rfm_segment_summary AS
SELECT
    rfm_segment,
    COUNT(*) AS customer_count,
    COUNT(*)::DOUBLE / SUM(COUNT(*)) OVER () AS customer_share,
    SUM(frequency_orders) AS order_count,
    SUM(monetary_gmv)::DECIMAL(18, 2) AS monetary_value
FROM analytics.dim_customer_rfm
GROUP BY rfm_segment
ORDER BY customer_count DESC, rfm_segment;

CREATE OR REPLACE TABLE analytics.fct_order_delivery_reviews_full_history AS
SELECT
    f.order_id,
    f.customer_unique_id,
    f.purchase_month,
    f.order_purchase_timestamp,
    f.order_delivered_customer_date,
    f.order_estimated_delivery_date,
    date_diff('day', CAST(f.order_purchase_timestamp AS DATE), CAST(f.order_delivered_customer_date AS DATE)) AS delivery_days,
    date_diff('day', CAST(f.order_estimated_delivery_date AS DATE), CAST(f.order_delivered_customer_date AS DATE)) AS delivery_delay_days,
    CAST(f.order_delivered_customer_date AS DATE) > CAST(f.order_estimated_delivery_date AS DATE) AS is_late_delivery,
    f.order_delivered_customer_date > f.order_estimated_delivery_date AS is_late_delivery_timestamp_comparison,
    (f.order_delivered_customer_date > f.order_estimated_delivery_date) <>
        (CAST(f.order_delivered_customer_date AS DATE) > CAST(f.order_estimated_delivery_date AS DATE)) AS has_late_classification_conflict,
    r.order_id IS NOT NULL AS has_review,
    COALESCE(r.review_record_count, 0) AS review_record_count,
    COALESCE(r.review_record_count, 0) > 1 AS has_multiple_reviews,
    r.average_review_score,
    r.minimum_review_score,
    r.maximum_review_score
FROM analytics.fct_order_financials f
LEFT JOIN analytics.int_order_reviews r USING (order_id)
WHERE f.order_status = 'delivered'
  AND f.order_delivered_customer_date IS NOT NULL;

CREATE OR REPLACE TABLE analytics.fct_order_delivery_reviews AS
SELECT d.*
FROM analytics.fct_order_delivery_reviews_full_history d
CROSS JOIN analytics.analysis_config c
WHERE d.purchase_month BETWEEN c.analysis_start_month AND c.last_complete_month;

CREATE OR REPLACE TABLE analytics.fct_monthly_delivery_reviews AS
SELECT
    purchase_month,
    COUNT(*) AS delivered_order_count,
    COUNT(*) FILTER (WHERE has_review) AS reviewed_order_count,
    COUNT(*) FILTER (WHERE NOT has_review) AS unreviewed_order_count,
    COUNT(*) FILTER (WHERE has_multiple_reviews) AS multiple_review_order_count,
    COUNT(*) FILTER (WHERE has_review)::DOUBLE / NULLIF(COUNT(*), 0) AS review_coverage_rate,
    AVG(delivery_days) AS average_delivery_days,
    AVG(delivery_delay_days) AS average_delivery_delay_days,
    AVG(CASE WHEN is_late_delivery THEN 1.0 ELSE 0.0 END) AS late_delivery_rate,
    AVG(average_review_score) AS average_review_score,
    AVG(CASE WHEN is_late_delivery THEN average_review_score END) AS late_delivery_review_score,
    AVG(CASE WHEN NOT is_late_delivery THEN average_review_score END) AS on_time_review_score
FROM analytics.fct_order_delivery_reviews
GROUP BY purchase_month
ORDER BY purchase_month;

