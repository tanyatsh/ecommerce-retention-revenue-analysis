# Executive Summary

## Objective

This project provides a reproducible view of Olist marketplace revenue, customer purchasing, exact-month cohort retention, RFM segments, delivery performance, and review scores. The dashboard is scoped to eligible orders purchased from January 1, 2017 through August 31, 2018. RFM uses a September 1, 2018 snapshot.

## Headline results

| KPI | Validated result |
|---|---:|
| Gross order value | 15,683,706.74 BRL |
| Eligible orders | 97,905 |
| Unique purchasing customers | 94,703 |
| Average order value | 160.19 BRL |
| Repeat customers | 2,874 |
| Repeat customer share | 3.03% |
| M1 exact-month retention | 0.48% |
| M3 exact-month retention | 0.26% |
| M6 exact-month retention | 0.23% |
| M12 exact-month retention | 0.18% |
| Delivered orders with an actual delivery date | 96,203 |
| Late delivery rate | 6.79% |
| Reviewed delivered orders | 95,560 |
| Average order-level review score | 4.16 |

## Validated business insights

### The customer base is overwhelmingly one-time

91,829 customers placed exactly one eligible order, representing 96.97% of purchasing customers. Another 2,639 customers placed two orders and 235 placed three or more. This concentration makes explicit frequency bands more interpretable than percentile ranks.

The largest RFM groups are Recent one-time (29,197 customers), Cooling one-time (27,300), and Lapsed one-time (16,626). High-value recent one-time customers add another 7,650 customers, while repeat-oriented segments remain small.

### Repeat customer share and cohort retention answer different questions

The 3.03% repeat customer share is the proportion of reporting-period customers with at least two eligible orders anywhere in the window. It does not control for when the customer first purchased and should not be described as retention.

Exact-month cohort retention measures the share of an acquisition cohort purchasing again in one specific later calendar month. The weighted mature-cohort rates are 0.48% at M1, 0.26% at M3, 0.23% at M6, and 0.18% at M12. Immature cohort-month combinations remain blank, preventing right-censored cohorts from being treated as zero-retention cohorts.

### Delivery logic materially changes the KPI

A calendar-day late definition produces a 6.79% reporting-period late-delivery rate. A timestamp comparison would produce 8.13% because estimated delivery timestamps are normally at midnight and would incorrectly classify 1,291 deliveries later on the promised date as late. The dashboard uses the calendar-day definition.

### Commercial metrics reconcile at order grain

GMV is item value plus freight for eligible orders. Order items and payments are aggregated independently before joining, preventing one-to-many multiplication. The reporting period contains no eligible orders missing item-derived GMV. Three eligible full-history orders lack items and one lacks payments; all four fall outside the dashboard period and remain null and warning-flagged.

### Review metrics have strong coverage but remain conditional

95,560 of 96,203 delivered reporting-period orders have at least one review, or approximately 99.33% coverage. The 4.16 average score is calculated after aggregating multiple review records to order grain. It therefore describes reviewed delivered orders, not every order or every customer.

## Recommended actions

1. **Prioritize the second purchase.** Design controlled lifecycle tests for recent one-time and high-value recent one-time customers. Use the same exact-month cohort method to evaluate whether treatment changes M1 or M3 purchasing.
2. **Separate activation from reactivation.** Recent one-time customers and lapsed one-time customers require different messages, timing, and success measures. Preserve the current RFM thresholds while testing campaign-specific variants.
3. **Investigate late-delivery drivers.** Break the 6.79% late population down by product, seller, route, and promised lead time before proposing operational changes. Keep the calendar-day definition consistent.
4. **Track review coverage with score.** Report response coverage beside average score and keep multiple-review flags available so changes in review behavior are not mistaken for experience changes.
5. **Refresh mature cohorts deliberately.** As new months arrive, advance the observation cutoff only after a full month is observed. Do not backfill immature cells with zero.
6. **Retain order-grain financial controls.** Continue aggregating items and payments separately and surface missing financial records instead of imputing zero.

These are analysis-led opportunities for testing and investigation. The dataset does not establish causal impact or forecast financial returns.

## Limitations

- The public dataset is historical, anonymized, and ends in 2018.
- Reporting begins in January 2017 because earlier source months are sparse or abnormal.
- Repeat customer share is bounded by the reporting window and gives late-acquired customers less time to repeat.
- Exact-month retention is not cumulative retention or customer survival.
- Delivery metrics include only delivered orders with a non-null actual delivery timestamp.
- Review averages exclude unreviewed orders and may reflect response selection.
- RFM thresholds are transparent portfolio rules, not experimentally optimized campaign cutoffs.
- GMV includes item value and freight; it is not net revenue, margin, or profit.
- The source files contain no explicit currency field, timezone metadata, website sessions, traffic, marketing exposure, or experiment assignment.
- Conversion rates and causal business impact cannot be calculated from this dataset.

## Decision use

The dashboard is suitable for portfolio demonstration, descriptive performance monitoring, cohort diagnostics, and hypothesis generation. Any production decision should revalidate the reporting window, source completeness, currency interpretation, RFM thresholds, and cohort maturity against current operational data.
