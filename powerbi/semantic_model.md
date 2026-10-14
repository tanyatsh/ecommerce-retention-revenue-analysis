# Power BI semantic model

## Model scope

The reporting window is fixed at **2017-01-01 through 2018-08-31**. The RFM table is a **2018-09-01 snapshot** calculated from eligible purchases in that same reporting window. Eligible commercial order statuses are `approved`, `processing`, `invoiced`, `shipped`, and `delivered`.

The model uses pre-aggregated exports at their documented grains. It does not join payments, order items, reviews, or order rows inside Power BI. This preserves the pipeline's protections against monetary multiplication.

## Tables and contracts

| Power BI table | CSV | Grain | Candidate key | Purpose |
|---|---|---|---|---|
| `Monthly Revenue` | `monthly_revenue_orders.csv` | One row per purchase month | `purchase_month` | Financial and order KPIs and trends |
| `Customers` | `customer_purchase_summary.csv` | One row per purchasing customer | `customer_unique_id` | Unique and repeat customer KPIs |
| `Cohort Retention` | `cohort_retention.csv` | One row per acquisition cohort and exact month age | `cohort_month`, `month_number` | Cohort matrix with maturity flags |
| `Cohort Horizons` | `cohort_horizon_summary.csv` | One row per retention horizon | `month_number` | Weighted mature-cohort cards |
| `RFM Segments` | `rfm_segment_summary.csv` | One row per RFM segment | `rfm_segment` | Segment distribution, orders, and monetary value |
| `Monthly Experience` | `monthly_delivery_reviews.csv` | One row per purchase month | `purchase_month` | Delivery, review, and coverage trends |
| `Date` | DAX calculated table | One row per calendar date | `Date[Date]` | Shared reporting-period filters and month axis |

## Relationships

Create only these active, single-direction relationships:

| One side | Many side | Cardinality | Cross-filter |
|---|---|---|---|
| `Date[Date]` | `Monthly Revenue[purchase_month]` | One-to-many | Single, Date to fact |
| `Date[Date]` | `Monthly Experience[purchase_month]` | One-to-many | Single, Date to fact |

`purchase_month` contains the first calendar day of each month. The daily `Date` table is still safe: a Year Month filter includes the matching first day and therefore filters the monthly fact row.

Leave `Customers`, `Cohort Retention`, `Cohort Horizons`, and `RFM Segments` disconnected. Each is already a complete analytical population at its own grain. Connecting acquisition cohort month to the transaction Date table would cause the main period slicer to change cohort populations while appearing to filter activity month. Connecting segment or customer aggregates to monthly facts would create unsupported many-to-many allocations.

## Filter behavior

- The page-level Date slicer filters `Monthly Revenue` and `Monthly Experience` only.
- Customer cards always describe the fixed dashboard reporting population. Label them `Jan 2017-Aug 2018`.
- Cohort visuals show acquisition cohorts from January 2017 onward and use their own `cohort_month` field.
- RFM visuals always describe the September 1, 2018 snapshot. Label the visual with that date.
- `Cohort Retention[observation_window_complete]` must be `TRUE` for displayed retention values. The export already nulls immature rates, and the visual filter makes the maturity rule explicit.

## Required data types

| Table | Field | Type |
|---|---|---|
| `Monthly Revenue` | `purchase_month` | Date |
|  | count fields | Whole number |
|  | value and average fields | Decimal number |
|  | `period_quality` | Text |
| `Customers` | `customer_unique_id` | Text; do not summarize |
|  | timestamp fields | Date/time |
|  | count fields | Whole number |
|  | monetary fields | Decimal number |
|  | `is_repeat_customer` | True/False |
| `Cohort Retention` | `cohort_month`, `observation_cutoff` | Date |
|  | `month_number`, size and customer fields | Whole number |
|  | `observation_window_complete` | True/False |
|  | `retention_rate` | Decimal number; percentage format |
| `Cohort Horizons` | count fields and `month_number` | Whole number |
|  | `weighted_retention_rate` | Decimal number; percentage format |
| `RFM Segments` | `rfm_segment` | Text |
|  | count fields | Whole number |
|  | `customer_share` | Decimal number; percentage format |
|  | `monetary_value` | Decimal number |
| `Monthly Experience` | `purchase_month` | Date |
|  | count fields | Whole number |
|  | rate fields | Decimal number; percentage format |
|  | days and score fields | Decimal number |

## Hidden technical fields

Hide fields used only to support measures or auditing: `orders_with_gmv`, `orders_missing_gmv`, `orders_with_payment`, `orders_missing_payment`, `period_quality`, customer timestamps, customer-level raw monetary columns, cohort `observation_cutoff`, and monthly experience count components. Keep them available in the model for measure calculations and troubleshooting.

