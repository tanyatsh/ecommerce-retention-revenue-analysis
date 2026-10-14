# Metric definitions

## Scope and grain

Customer analysis uses `customer_unique_id`. The source `customer_id` identifies the order-specific customer record and must not be used as a person-level identifier.

The eligible order statuses for financial and customer purchase metrics are `approved`, `processing`, `invoiced`, `shipped`, and `delivered`. Orders with `created`, `canceled`, or `unavailable` status are excluded. Delivery metrics use delivered orders with an actual delivery timestamp. All financial models retain ineligible orders with an `is_eligible_order` flag so analysts can audit exclusions.

Comparable dashboard KPIs use one reporting period: purchases from January 1, 2017 through August 31, 2018. The RFM snapshot is September 1, 2018. Primary exports use this reporting period; explicitly named `_full_history.csv` exports preserve all source periods for audit and sensitivity analysis. Metrics from the two scopes must not be combined in one comparison without a visible scope label.

## Financial measures

- **Item value** is the sum of `order_items.price` at order grain. It excludes freight.
- **Freight** is the sum of `order_items.freight_value` at order grain.
- **GMV** is item value plus freight for eligible orders. It represents merchandise and freight recorded in order items; it is not Olist net revenue or profit.
- **Payments** is the sum of `order_payments.payment_value` at order grain. It is reported separately because vouchers, adjustments, and source anomalies can make it differ from GMV.
- **Order count** is the distinct count of eligible `order_id` values with a purchase timestamp.
- **Average order GMV** is complete-case GMV divided by the count of eligible orders with item-derived GMV. The three eligible orders without item records are reported separately and are not treated as zero-value orders.

Order items and payments are aggregated independently before joining to orders. Joining both one-to-many tables directly would multiply item and payment values.

Orders without a matching item or payment record retain null monetary amounts and expose `has_item_data` and `has_payment_data` flags. Missing financial source data is not converted to zero. Aggregate `SUM` measures therefore use the amounts that are actually present.

## Customers, repeat purchases, and retention

- **Unique customers** is the distinct count of `customer_unique_id` among eligible orders.
- **Repeat customer** means a customer with at least two eligible orders within the selected metric scope.
- **Repeat purchase rate** is repeat customers divided by all purchasing customers in the same scope. The dashboard rate uses the January 2017-August 2018 reporting period. The full-history rate remains available separately. Neither is formal retention.
- **Cohort month** is the calendar month of a customer's first eligible order.
- **Monthly cohort retention** is the share of the original cohort with at least one eligible order in an exact later calendar month.

The last source month may be incomplete. `dim_cohort_retention` returns months 0 through 12 and sets retention to null unless the entire activity month is observed. `fct_cohort_fixed_windows` exposes fixed 1, 3, 6, and 12-month rates only when each window is complete. This prevents right-censored cohorts from appearing to have zero retention.

Formal cohort reporting starts in January 2017. September and October 2016 are sparse launch data, November is absent, and December contains one eligible order. The observation cutoff is the end of the month before the latest eligible activity month. `fct_cohort_horizon_summary` calculates portfolio-level retention as total retained customers divided by total customers across mature cohorts; averaging cohort rates would give every cohort equal weight and is not the approved aggregate.

## RFM

Dashboard RFM uses eligible reporting-period purchases and a September 1, 2018 snapshot. The full-history RFM export uses all eligible source purchases and a snapshot one day after the latest eligible purchase:

- **Recency:** days since the customer's latest eligible purchase.
- **Frequency:** count of distinct eligible orders.
- **Monetary:** sum of order-level GMV.

RFM uses explicit, tie-preserving bands:

- Recency: active `0-90` days, warm `91-180`, cooling `181-365`, and dormant `366+`. Scores are 4, 3, 2, and 1 respectively.
- Frequency: one-time `1` order, repeat `2` orders, and frequent `3+` orders. Scores are 1, 3, and 5.
- Monetary: low below `100`, mid from `100` through `199.99`, and high at least `200` source currency units. Scores are 1, 3, and 5.

The thresholds reflect the observed reporting-period distribution: 96.97% of customers have one order; monetary value is approximately 107.88 at the median and 208.96 at the 80th percentile; recency is 95 days at the 20th percentile, 180 at the 40th, and 384 at the 80th. Customers with identical inputs always receive identical bands and scores.

Segments apply these rules in order: frequent customers active within 180 days are `Champions`; two-order customers active within 180 days are `Loyal repeat`; customers with at least two orders and recency above 180 days are `At-risk repeat`; one-time customers are split by recency and the `200` high-value threshold into recent, cooling, lapsed, and high-value groups. Customers with missing GMV receive `Incomplete financial data`. Segment labels are descriptive and are not causal customer-lifetime-value estimates.

## Delivery and reviews

- **Delivery days** is the date difference from purchase to actual customer delivery.
- **Delivery delay days** is actual delivery calendar date minus estimated delivery calendar date. Positive values are late; zero or negative values are on time or early.
- **Late delivery** means `delivery_delay_days > 0`. A delivery at any time on the estimated calendar date is on time. The source estimated timestamp is normally midnight, so direct timestamp comparison is retained only as an audit field and is not the business KPI.
- **Review score** is averaged at order grain first. The source can contain multiple review records for one order, so this prevents reviews from duplicating order-level amounts.

Review averages exclude unreviewed orders because their score remains null. `has_review`, `review_record_count`, and `has_multiple_reviews` preserve coverage and multiplicity. The delivery-review marts contain delivered orders with an actual delivery timestamp, so they must not be interpreted as review coverage for all order statuses.

## Power BI export contracts

| Export | Grain | Key | Eligibility and period |
|---|---|---|---|
| `order_financials.csv` | One row per source order in the reporting period | `order_id` | All statuses; January 2017-August 2018; use `is_eligible_order` for commercial KPIs. |
| `order_financials_full_history.csv` | One row per source order | `order_id` | All statuses and source periods; audit and sensitivity use. |
| `monthly_revenue_orders.csv` | One row per purchase month | `purchase_month` | Eligible statuses; January 2017 through the last complete month, August 2018. |
| `customer_purchase_summary.csv` | One row per purchasing customer | `customer_unique_id` | Eligible reporting-period orders; columns use the `reporting_period_` prefix. |
| `customer_purchase_summary_full_history.csv` | One row per purchasing customer | `customer_unique_id` | All eligible source orders; lifetime columns retain their original meaning. |
| `cohort_retention.csv` | One row per cohort and month age | `cohort_month`, `month_number` | Eligible orders; January 2017 acquisition cohorts; months 0-12; incomplete windows have null retention. |
| `cohort_fixed_windows.csv` | One row per cohort | `cohort_month` | Same cohort scope; fixed 1, 3, 6, and 12-month windows. |
| `cohort_horizon_summary.csv` | One row per retention horizon | `month_number` | Mature cohorts only; weighted from retained and eligible customer counts. |
| `customer_rfm.csv` | One row per purchasing customer | `customer_unique_id` | Eligible reporting-period orders; September 1, 2018 snapshot. |
| `customer_rfm_full_history.csv` | One row per purchasing customer | `customer_unique_id` | All eligible source orders; snapshot follows the latest eligible purchase. |
| `rfm_segment_summary.csv` | One row per RFM segment | `rfm_segment` | Reporting-period customers; includes customer count/share, order count, and monetary value. |
| `order_delivery_reviews.csv` | One row per delivered order with delivery timestamp | `order_id` | Reporting-period purchases; reviews optional and aggregated per order. |
| `order_delivery_reviews_full_history.csv` | One row per delivered order with delivery timestamp | `order_id` | All source periods; audit and sensitivity use. |
| `monthly_delivery_reviews.csv` | One row per purchase month | `purchase_month` | Reporting-period delivered orders with delivery timestamps; reviews optional. |

Audit exports use their explicit column combinations rather than business entity keys: source by `source_file`, columns by `table_name` plus `column_name`, candidate keys by `table_name` plus `key_columns`, date ranges by `table_name` plus `column_name`, and validations by `check_name`.

The monthly revenue export intentionally omits the four abnormal boundary months: September, October, and December 2016 plus September 2018. The unfiltered monthly reconciliation remains available inside DuckDB as `analytics.int_monthly_revenue_orders_all_periods`.

Dates reflect source timestamps without timezone conversion. The dataset contains no sessions or traffic denominators; website conversion is intentionally not calculated.

