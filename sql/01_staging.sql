CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;

CREATE OR REPLACE TABLE raw.customers AS
SELECT
    customer_id::VARCHAR AS customer_id,
    customer_unique_id::VARCHAR AS customer_unique_id,
    customer_zip_code_prefix::VARCHAR AS customer_zip_code_prefix,
    customer_city::VARCHAR AS customer_city,
    customer_state::VARCHAR AS customer_state
FROM read_csv('{{RAW_DIR}}/olist_customers_dataset.csv', header = true, all_varchar = true, nullstr = '');

CREATE OR REPLACE TABLE raw.geolocation AS
SELECT
    geolocation_zip_code_prefix::VARCHAR AS geolocation_zip_code_prefix,
    TRY_CAST(geolocation_lat AS DOUBLE) AS geolocation_lat,
    TRY_CAST(geolocation_lng AS DOUBLE) AS geolocation_lng,
    geolocation_city::VARCHAR AS geolocation_city,
    geolocation_state::VARCHAR AS geolocation_state
FROM read_csv('{{RAW_DIR}}/olist_geolocation_dataset.csv', header = true, all_varchar = true, nullstr = '');

CREATE OR REPLACE TABLE raw.order_items AS
SELECT
    order_id::VARCHAR AS order_id,
    TRY_CAST(order_item_id AS INTEGER) AS order_item_id,
    product_id::VARCHAR AS product_id,
    seller_id::VARCHAR AS seller_id,
    TRY_CAST(shipping_limit_date AS TIMESTAMP) AS shipping_limit_date,
    TRY_CAST(price AS DECIMAL(18, 2)) AS price,
    TRY_CAST(freight_value AS DECIMAL(18, 2)) AS freight_value
FROM read_csv('{{RAW_DIR}}/olist_order_items_dataset.csv', header = true, all_varchar = true, nullstr = '');

CREATE OR REPLACE TABLE raw.order_payments AS
SELECT
    order_id::VARCHAR AS order_id,
    TRY_CAST(payment_sequential AS INTEGER) AS payment_sequential,
    payment_type::VARCHAR AS payment_type,
    TRY_CAST(payment_installments AS INTEGER) AS payment_installments,
    TRY_CAST(payment_value AS DECIMAL(18, 2)) AS payment_value
FROM read_csv('{{RAW_DIR}}/olist_order_payments_dataset.csv', header = true, all_varchar = true, nullstr = '');

CREATE OR REPLACE TABLE raw.order_reviews AS
SELECT
    review_id::VARCHAR AS review_id,
    order_id::VARCHAR AS order_id,
    TRY_CAST(review_score AS INTEGER) AS review_score,
    review_comment_title::VARCHAR AS review_comment_title,
    review_comment_message::VARCHAR AS review_comment_message,
    TRY_CAST(review_creation_date AS TIMESTAMP) AS review_creation_date,
    TRY_CAST(review_answer_timestamp AS TIMESTAMP) AS review_answer_timestamp
FROM read_csv('{{RAW_DIR}}/olist_order_reviews_dataset.csv', header = true, all_varchar = true, nullstr = '');

CREATE OR REPLACE TABLE raw.orders AS
SELECT
    order_id::VARCHAR AS order_id,
    customer_id::VARCHAR AS customer_id,
    order_status::VARCHAR AS order_status,
    TRY_CAST(order_purchase_timestamp AS TIMESTAMP) AS order_purchase_timestamp,
    TRY_CAST(order_approved_at AS TIMESTAMP) AS order_approved_at,
    TRY_CAST(order_delivered_carrier_date AS TIMESTAMP) AS order_delivered_carrier_date,
    TRY_CAST(order_delivered_customer_date AS TIMESTAMP) AS order_delivered_customer_date,
    TRY_CAST(order_estimated_delivery_date AS TIMESTAMP) AS order_estimated_delivery_date
FROM read_csv('{{RAW_DIR}}/olist_orders_dataset.csv', header = true, all_varchar = true, nullstr = '');

CREATE OR REPLACE TABLE raw.products AS
SELECT
    product_id::VARCHAR AS product_id,
    product_category_name::VARCHAR AS product_category_name,
    TRY_CAST(product_name_lenght AS INTEGER) AS product_name_length,
    TRY_CAST(product_description_lenght AS INTEGER) AS product_description_length,
    TRY_CAST(product_photos_qty AS INTEGER) AS product_photos_qty,
    TRY_CAST(product_weight_g AS DOUBLE) AS product_weight_g,
    TRY_CAST(product_length_cm AS DOUBLE) AS product_length_cm,
    TRY_CAST(product_height_cm AS DOUBLE) AS product_height_cm,
    TRY_CAST(product_width_cm AS DOUBLE) AS product_width_cm
FROM read_csv('{{RAW_DIR}}/olist_products_dataset.csv', header = true, all_varchar = true, nullstr = '');

CREATE OR REPLACE TABLE raw.sellers AS
SELECT
    seller_id::VARCHAR AS seller_id,
    seller_zip_code_prefix::VARCHAR AS seller_zip_code_prefix,
    seller_city::VARCHAR AS seller_city,
    seller_state::VARCHAR AS seller_state
FROM read_csv('{{RAW_DIR}}/olist_sellers_dataset.csv', header = true, all_varchar = true, nullstr = '');

CREATE OR REPLACE TABLE raw.product_category_translation AS
SELECT
    product_category_name::VARCHAR AS product_category_name,
    product_category_name_english::VARCHAR AS product_category_name_english
FROM read_csv('{{RAW_DIR}}/product_category_name_translation.csv', header = true, all_varchar = true, nullstr = '');

