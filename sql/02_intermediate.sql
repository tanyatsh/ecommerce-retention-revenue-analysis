CREATE OR REPLACE TABLE analytics.int_order_items AS
SELECT
    order_id,
    COUNT(*) AS item_line_count,
    SUM(price) AS item_value,
    SUM(freight_value) AS freight_value,
    SUM(price + freight_value) AS gmv
FROM raw.order_items
GROUP BY order_id;

CREATE OR REPLACE TABLE analytics.int_order_payments AS
SELECT
    order_id,
    COUNT(*) AS payment_record_count,
    SUM(payment_value) AS payment_value
FROM raw.order_payments
GROUP BY order_id;

CREATE OR REPLACE TABLE analytics.int_order_reviews AS
SELECT
    order_id,
    COUNT(*) AS review_record_count,
    AVG(review_score) AS average_review_score,
    MIN(review_score) AS minimum_review_score,
    MAX(review_score) AS maximum_review_score
FROM raw.order_reviews
GROUP BY order_id;

CREATE OR REPLACE TABLE analytics.fct_order_financials AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    o.order_status,
    o.order_purchase_timestamp,
    CAST(date_trunc('month', o.order_purchase_timestamp) AS DATE) AS purchase_month,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    o.order_status IN ('approved', 'processing', 'invoiced', 'shipped', 'delivered') AS is_eligible_order,
    i.order_id IS NOT NULL AS has_item_data,
    COALESCE(i.item_line_count, 0) AS item_line_count,
    i.item_value::DECIMAL(18, 2) AS item_value,
    i.freight_value::DECIMAL(18, 2) AS freight_value,
    i.gmv::DECIMAL(18, 2) AS gmv,
    p.order_id IS NOT NULL AS has_payment_data,
    COALESCE(p.payment_record_count, 0) AS payment_record_count,
    p.payment_value::DECIMAL(18, 2) AS payment_value,
    (p.payment_value - i.gmv)::DECIMAL(18, 2) AS payment_gmv_difference
FROM raw.orders o
LEFT JOIN raw.customers c USING (customer_id)
LEFT JOIN analytics.int_order_items i USING (order_id)
LEFT JOIN analytics.int_order_payments p USING (order_id);

