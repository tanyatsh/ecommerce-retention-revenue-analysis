# Power BI import and assembly guide

## 1. Validate source assets

From the repository root:

```powershell
python powerbi/validate_powerbi_assets.py
powershell -ExecutionPolicy Bypass -File powerbi/validate_tmdl.ps1
```

The validator checks file availability, exact headers, expected keys, reporting dates, RFM totals, JSON syntax, required DAX measures, and the PBIP folder contract.

## 2. Open the editable project

Open:

`powerbi/pbip/OlistRetentionDashboard.pbip`

The project contains two empty 1280 × 720 pages and an editable semantic model. Select **Home > Refresh**. If the repository was moved, open **Transform data**, select each query, and replace the old repository root in `File.Contents(...)` with the new absolute path to `data/processed`.

If the PBIP does not open in the installed Desktop build, enable **Power BI Project (.pbip) save option** and **Store reports using enhanced metadata format (PBIR)** under **File > Options and settings > Options > Preview features**, restart Desktop, then open the `.pbip` again.

## 3. Required imports and names

The PBIP already defines these queries. For a manual fallback, use **Get data > Text/CSV** and import the exact files below, then rename the tables exactly as shown.

| File | Rename table to |
|---|---|
| `data/processed/monthly_revenue_orders.csv` | `Monthly Revenue` |
| `data/processed/customer_purchase_summary.csv` | `Customers` |
| `data/processed/cohort_retention.csv` | `Cohort Retention` |
| `data/processed/cohort_horizon_summary.csv` | `Cohort Horizons` |
| `data/processed/rfm_segment_summary.csv` | `RFM Segments` |
| `data/processed/monthly_delivery_reviews.csv` | `Monthly Experience` |

Use the field data types listed in `semantic_model.md`. Do not import the `_full_history.csv` files into this dashboard.

## 4. Date table and relationships

If using the manual fallback, choose **Modeling > New table** and paste the `Date = ...` expression from `dax/measures.dax`. Then:

1. Mark `Date` as the date table using `Date[Date]`.
2. Sort `Date[Year Month]` by `Date[Year Month Sort]`.
3. Relate `Date[Date]` to `Monthly Revenue[purchase_month]` as active, one-to-many, single direction.
4. Relate `Date[Date]` to `Monthly Experience[purchase_month]` as active, one-to-many, single direction.
5. Leave all other tables disconnected.

Do not enable bidirectional filtering and do not create a relationship from `Cohort Retention[cohort_month]` to `Date`.

## 5. Measures and formats

The PBIP contains the measures from `dax/measures.dax`. For a manual fallback, create them under the indicated source tables. Recommended formats:

| Measure group | Format |
|---|---|
| GMV, item, freight, payments, AOV, RFM monetary | `#,0.00` |
| Counts | `#,0` |
| Shares, rates, retention, MoM | `0.00%` |
| Delivery days | `0.0` |
| Review scores | `0.00` |

`Average Order Value` uses orders with item-derived GMV as the denominator. All 97,905 eligible reporting-period orders currently have GMV. The three full-history eligible orders without item records fall outside the dashboard period; the complete-case denominator keeps the measure correct if the scope changes.

## 6. Theme

Choose **View > Themes > Browse for themes** and select:

`powerbi/theme/olist_portfolio_theme.json`

If Desktop reports a version-specific theme warning, remove only the rejected optional formatting block shown in the error dialog. The core palette, fonts, and semantic colors are standard theme properties.

## 7. Build the pages

The PBIP already contains:

- `Executive Overview`
- `Customer Retention & Experience`

Follow `dashboard_layout.md` for exact coordinates, fields, filters, sort order, interactions, titles, and tooltip content. Use **View > Snap to grid** for faster placement.

## 8. Validation in Desktop

After refresh and visual assembly, verify:

1. `Monthly Revenue[purchase_month]` spans 2017-01-01 to 2018-08-01 and contains 20 rows.
2. `Monthly Experience[purchase_month]` spans 2017-01-01 to 2018-08-01 and contains 20 rows.
3. Page 1 customer cards do not change when the Date slicer changes.
4. `[Average Order Value]` equals GMV divided by orders with GMV, not all eligible orders.
5. Cohort matrix cells are blank for immature horizons and subtotals are off.
6. Retention horizon cards use `Cohort Horizons`, not an average of cohort percentages.
7. RFM customer counts sum to the fixed customer population and the snapshot label says September 1, 2018.
8. Late delivery rate uses the exported calendar-date classification.
9. Average review score is weighted by reviewed orders when aggregated across months.
10. No relationship is bidirectional and there are no many-to-many relationships.

## 9. Publish-ready finishing steps

- Save as PBIP for source control. Optionally save a `.pbix` copy for sharing.
- Add a small info tooltip or report-page tooltip containing the definitions from `docs/metric_definitions.md`.
- Confirm currency labeling with the portfolio owner. The source contains values but no explicit currency field; the project should not invent a currency symbol.
- Test at 100% and Fit to page, check keyboard tab order, and run the Power BI Performance Analyzer once visuals are assembled.

