# Analytics implementation audit

## Current recommendation

**READY for Power BI dashboard development.** Dashboard-facing exports use one reporting period, January 1, 2017 through August 31, 2018. Explicitly named `_full_history.csv` files preserve the prior broader populations for audit and sensitivity work.

## Reporting-period consistency

The comparable dashboard cutoff is based on purchase month:

- Start: January 1, 2017.
- Last included purchase month: August 2018.
- Observation cutoff: August 31, 2018.
- RFM snapshot: September 1, 2018.

The primary financial, revenue, customer, cohort, RFM, and delivery exports now use this scope. Full-history financial, customer, RFM, and delivery data remain separate rather than being silently discarded.

| Metric | Previous full-history scope | Dashboard reporting scope |
|---|---:|---:|
| All-status order-financial rows | 99,441 | 99,092 |
| Eligible orders | 98,202 | 97,905 |
| Unique eligible customers | 94,986 | 94,703 |
| Repeat customers | 2,887 | 2,874 |
| Repeat purchase rate | 3.039395% | 3.034751% |
| GMV | 15,735,527.03 | 15,683,706.74 |
| Delivered orders with delivery timestamp | 96,470 | 96,203 |

The primary customer summary uses `reporting_period_` column names. Its `_full_history` counterpart retains `lifetime_` names, preventing the two scopes from being mistaken for the same metric.

## Late-delivery definition

The source estimated delivery timestamps are at midnight. Direct timestamp comparison therefore labels a delivery later on the estimated calendar date as late, while `delivery_delay_days` returns zero.

The executed comparison found:

| Scope | Delivered rows | Timestamp-late | Calendar-day late | Contradictory | Timestamp rate | Calendar-day rate |
|---|---:|---:|---:|---:|---:|---:|
| Reporting period | 96,203 | 7,822 | 6,531 | 1,291 | 8.130724% | 6.788770% |
| Full history | 96,470 | 7,826 | 6,534 | 1,292 | 8.112367% | 6.773090% |

Every contradiction is a delivery later in the day on the estimated calendar date and has `delivery_delay_days = 0`. The business definition is now:

> An order is late when its actual delivery calendar date is after its estimated delivery calendar date, equivalently `delivery_delay_days > 0`.

The reporting-period late rate decreased by 1.341954 percentage points. The previous timestamp result remains in `is_late_delivery_timestamp_comparison`, and `has_late_classification_conflict` identifies the affected records.

## RFM assessment and correction

The reporting-period customer frequency distribution is highly concentrated:

| Frequency band | Customers | Customer share | Orders | GMV |
|---|---:|---:|---:|---:|
| One-time: 1 order | 91,829 | 96.965249% | 91,829 | 14,797,478.72 |
| Repeat: 2 orders | 2,639 | 2.786607% | 5,278 | 768,046.74 |
| Frequent: 3+ orders | 235 | 0.248143% | 798 | 118,181.28 |

Percentile frequency scoring is not useful for this distribution. The prior tie-preserving percentile method assigned all one-order customers a score of 1 and nearly every repeat customer a score of 5, leaving no meaningful middle frequency level. The corrected model uses explicit thresholds:

- Recency: `0-90`, `91-180`, `181-365`, and `366+` days, scored 4, 3, 2, and 1.
- Frequency: `1`, `2`, and `3+` orders, scored 1, 3, and 5.
- Monetary: below `100`, `100-199.99`, and `200+`, scored 1, 3, and 5.

The monetary thresholds bracket the observed median of 107.88 and 80th percentile of 208.96. The recency thresholds align with observed 20th, 40th, and approximately 80th percentile values of 95, 180, and 384 days while remaining readable business intervals. All thresholds preserve ties.

The prior method produced broad score-driven groups on the same reporting population: 36,883 `Promising`, 36,594 `Hibernating`, 18,352 `New customers`, 1,238 `Champions`, 1,019 `At risk`, and 617 `Loyal customers`. Those names depended heavily on a binary effective frequency score.

The corrected segment summary is:

| Segment | Customers | Share | Orders | Monetary value |
|---|---:|---:|---:|---:|
| Recent one-time | 29,197 | 30.830069% | 29,197 | 2,763,672.15 |
| Cooling one-time | 27,300 | 28.826964% | 27,300 | 2,546,659.85 |
| Lapsed one-time | 16,626 | 17.555938% | 16,626 | 1,518,475.79 |
| High-value lapsed one-time | 11,056 | 11.674393% | 11,056 | 4,661,483.67 |
| High-value recent one-time | 7,650 | 8.077886% | 7,650 | 3,307,187.26 |
| At-risk repeat | 1,636 | 1.727506% | 3,406 | 488,315.62 |
| Loyal repeat | 1,110 | 1.172085% | 2,220 | 327,981.72 |
| Champions | 128 | 0.135159% | 450 | 69,930.68 |

`rfm_segment_summary.csv` persists these customer counts, customer shares, order counts, and monetary values. Its totals reconcile to the customer-level RFM export.

## Financial and cohort controls retained

Order items and payments are aggregated independently before joining, preserving one row per order. Full-source item value, freight, and payment totals reconcile exactly to raw data. Three eligible full-history orders without item rows and one without payments remain null and warning-flagged; all four are outside the dashboard reporting period.

Cohort activity remains exact-calendar-month retention. Customers are deduplicated within activity month, incomplete horizons remain null, and weighted horizon retention is calculated as total retained customers divided by total eligible customers across mature cohorts.

## Export scopes

Primary dashboard exports use January 2017-August 2018:

- `order_financials.csv`
- `monthly_revenue_orders.csv`
- `customer_purchase_summary.csv`
- `cohort_retention.csv`
- `cohort_fixed_windows.csv`
- `cohort_horizon_summary.csv`
- `customer_rfm.csv`
- `rfm_segment_summary.csv`
- `order_delivery_reviews.csv`
- `monthly_delivery_reviews.csv`

Explicit full-history exports are:

- `order_financials_full_history.csv`
- `customer_purchase_summary_full_history.csv`
- `customer_rfm_full_history.csv`
- `order_delivery_reviews_full_history.csv`

The grain, key, eligibility rule, date scope, and population for each file are documented in `docs/metric_definitions.md`.

## Corrections made

1. Added dashboard-period financial, customer, RFM, and delivery tables while preserving named full-history counterparts.
2. Changed late delivery to the same calendar-day rule used by `delivery_delay_days` and retained timestamp classification for audit.
3. Replaced percentile RFM scoring with explicit recency, frequency, and monetary bands.
4. Added a reporting-period RFM segment summary with reconciled customer, order, and monetary totals.
5. Added SQL and Python regressions for reporting cutoffs, late-delivery consistency, RFM frequency thresholds, segment reconciliation, and full-history preservation.
6. Updated pipeline summary output to report dashboard and full-history KPIs separately.

## Remaining limitations

- Repeat purchase rate remains a within-period share and is not formal retention. Customers acquired near August 2018 have less opportunity to repeat.
- Delivery performance is conditional on delivered orders with a non-null actual delivery timestamp.
- Review metrics remain conditional on submitted reviews; missing reviews are not imputed.
- RFM thresholds are transparent portfolio rules, not experimentally validated campaign cutoffs. The extreme one-order concentration limits the predictive meaning of frequency.
- Monetary thresholds use source currency units because the files have no explicit currency field.
- GMV is item value plus freight, not marketplace net revenue, margin, or profit.
- Source timestamps lack timezone metadata and are used without conversion.
- The reporting start is dataset-specific and must be reassessed if the source extract changes.

## Final test results

- Pipeline rebuild: passed.
- Critical SQL validations: 35 passed, 0 failed.
- Source-quality warnings: 2 — three full-history eligible orders without items and one without payments.
- Python integration tests: 6 passed, 0 failed.
- Python compilation: passed.

## Final status

**READY for Power BI dashboard development.** Comparable KPIs now share one reporting cutoff, late delivery has one internally consistent definition, and RFM groups use explicit, tie-preserving business rules with a ready-to-use segment summary.
