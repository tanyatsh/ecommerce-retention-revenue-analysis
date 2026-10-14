# Two-page dashboard layout

Use a 16:9 canvas at **1280 × 720 px**. Page background is `#F6F8FB`; visual background is white. Keep 32 px outer margins, 16 px gaps, 8 px corner radius, and a consistent left alignment. Use `Segoe UI` and the supplied theme.

## Page 1 — Executive Overview

### Header

- **Title**: `Executive Overview`, x 32, y 20, w 560, h 34, 22 pt semibold.
- **Subtitle**: `Eligible orders | Jan 2017-Aug 2018 | GMV includes item value and freight`, x 32, y 55, w 760, h 22, 10 pt, `#60748A`.
- **Date slicer**: x 1000, y 20, w 248, h 54. Use `Date[Year Month]`, dropdown style, single select off. The model already limits the range to Jan 2017-Aug 2018.

### KPI cards

Place five cards at y 96, h 112. Use a 16 px gap.

| x | w | Card title | Measure | Display |
|---:|---:|---|---|---|
| 32 | 230 | Gross Order Value | `[Gross Order Value (GMV)]` | Currency/decimal, display units Millions, 2 decimals |
| 278 | 230 | Orders | `[Orders]` | Whole number, thousands separator |
| 524 | 230 | Unique Customers | `[Unique Customers]` | Whole number, thousands separator |
| 770 | 230 | Average Order Value | `[Average Order Value]` | Currency/decimal, 2 decimals |
| 1016 | 232 | Repeat Customer Share | `[Repeat Customer Share]` | Percentage, 2 decimals |

The customer cards describe the fixed reporting-period population and do not respond to the monthly Date slicer. Add the tooltip text `Fixed population: eligible purchasing customers, Jan 2017-Aug 2018`.

### Monthly performance trend

- **Visual**: Line and clustered column chart.
- **Position**: x 32, y 232, w 800, h 438.
- **Title**: `Monthly GMV and Orders`.
- **Shared axis**: `Date[Year Month]`, continuous or categorical in ascending `Year Month Sort` order.
- **Column y-axis**: `[Gross Order Value (GMV)]`.
- **Line y-axis**: `[Orders]`; secondary axis on.
- **Tooltips**: `[Item Value]`, `[Freight]`, `[Payments]`, `[Monthly Purchasing Customers]`, `[Average Order Value]`, `[GMV Month-over-Month %]`.
- **Formatting**: teal columns `#1F7A8C`, coral line `#E76F51`, line width 3, markers on, gridlines `#E7ECF2`.

### GMV composition

- **Visual**: Stacked column chart.
- **Position**: x 848, y 232, w 400, h 205.
- **Title**: `GMV Composition`.
- **Axis**: `Date[Year Month]`.
- **Values**: `[Item Value]`, `[Freight]`.
- **Formatting**: item value teal; freight gold; legend top-left; labels off.

### Customer volume trend

- **Visual**: Line chart.
- **Position**: x 848, y 453, w 400, h 217.
- **Title**: `Monthly Unique Customers`.
- **Axis**: `Date[Year Month]`.
- **Value**: `[Monthly Purchasing Customers]`. This measure returns a value only in a single-month context and prevents the monthly counts from being presented as a portfolio-level distinct count.
- **Formatting**: navy line `#172B4D`, line width 3, markers on, data labels off.

## Page 2 — Customer Retention & Experience

### Header

- **Title**: `Customer Retention & Experience`, x 32, y 20, w 700, h 34.
- **Subtitle**: `Exact-month mature cohorts | RFM snapshot Sep 1, 2018 | Delivered-order experience`, x 32, y 55, w 820, h 22.
- Do not place the Page 1 Date slicer on this page. The cohort, customer, and RFM tables use fixed populations; the experience trend already spans the reporting period.

### KPI cards

Place six cards at y 90, h 94, with 12 px gaps.

| x | w | Card | Measure | Note |
|---:|---:|---|---|---|
| 32 | 190 | Month 1 Retention | `[Month 1 Retention %]` | Weighted mature cohorts |
| 234 | 190 | Month 3 Retention | `[Month 3 Retention %]` | Weighted mature cohorts |
| 436 | 190 | Month 6 Retention | `[Month 6 Retention %]` | Weighted mature cohorts |
| 638 | 190 | Month 12 Retention | `[Month 12 Retention %]` | Weighted mature cohorts |
| 840 | 190 | Late Delivery Rate | `[Late Delivery Rate]` | Calendar-date definition |
| 1042 | 206 | Average Review Score | `[Average Review Score]` | Reviewed delivered orders |

### Cohort retention heatmap

- **Visual**: Matrix.
- **Position**: x 32, y 204, w 680, h 466.
- **Title**: `Exact-Month Cohort Retention`.
- **Rows**: `Cohort Retention[cohort_month]`, format `MMM yyyy`, ascending.
- **Columns**: `Cohort Retention[month_number]`, ascending.
- **Values**: `[Cohort Retention %]`.
- **Visual filter**: `observation_window_complete is True`.
- **Conditional formatting**: background color scale minimum `#F3F6F9`, center `#A8DADC`, maximum `#1F7A8C`; font white at the darkest end. Display as 0.0%.
- **Totals**: row and column subtotals off. The approved portfolio aggregate is weighted and appears in the cards, so a matrix average is not meaningful.

### RFM segment distribution

- **Visual**: Horizontal clustered bar chart.
- **Position**: x 728, y 204, w 520, h 206.
- **Title**: `RFM Customer Segments — Sep 1, 2018`.
- **Y-axis**: `RFM Segments[rfm_segment]`.
- **X-axis**: `[RFM Customers]`.
- **Tooltips**: `[RFM Customer Share]`, `[RFM Orders]`, `[RFM Monetary Value]`.
- **Sort**: `[RFM Customers]` descending.
- **Formatting**: one consistent teal series, data labels on, display units None.

### Repeat purchase behavior

- **Visual**: Donut chart.
- **Position**: x 728, y 426, w 244, h 244.
- **Title**: `Repeat Purchase Behavior`.
- **Legend**: `Customers[is_repeat_customer]`.
- **Values**: count of `Customers[customer_unique_id]`.
- **Colors**: repeat `#1F7A8C`; one-time `#D9E1EA`.
- **Detail labels**: category and percent of total. Rename the visual labels to `Repeat` and `One-time` if Desktop displays Boolean values.
- **Tooltip**: clarify that this is repeat customer share within the reporting period, not formal cohort retention.

### Delivery and review trend

- **Visual**: Line and clustered column chart.
- **Position**: x 988, y 426, w 260, h 244.
- **Title**: `Delivery & Review Trend`.
- **Shared axis**: `Date[Year Month]`.
- **Column y-axis**: `[Late Delivery Rate]`.
- **Line y-axis**: `[Average Review Score]`, secondary axis, range 1 to 5.
- **Tooltips**: `[Delivered Orders]`, `[Review Coverage %]`, `[Average Delivery Days]`, `[Average Delivery Delay Days]`, `[Multiple-Review Orders]`.
- **Formatting**: late rate coral `#E76F51`; review score navy `#172B4D`; markers on.

## Accessibility and interaction settings

- Set meaningful alt text for every visual, including metric scope and grain.
- Keep titles visible and use at least 10 pt body text.
- Use the same tab order as reading order: header, KPI cards left-to-right, then main visuals.
- Page 1 Date slicer should filter only the three Page 1 charts and the five financial/order cards that are Date-connected. Disable its interaction with fixed customer cards.
- Avoid cross-highlighting between the disconnected cohort, RFM, and customer visuals on Page 2. Their populations differ by analytical purpose.

