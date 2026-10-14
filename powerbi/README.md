# Power BI delivery package

This folder contains the editable two-page Olist Power BI project, semantic model, report definition, DAX reference, theme, and supporting build documentation.

- **Dashboard scope:** January 1, 2017 through August 31, 2018
- **RFM snapshot:** September 1, 2018
- **Report pages:** Executive Overview; Customer Retention & Experience
- **Report visuals:** 23
- **Canvas:** 1280 x 720

The publication PDF and preview are stored in the repository-level [docs folder](../docs/OlistRetentionDashboard.pdf).

## Open the project

1. Rebuild the processed CSVs from the repository root:

   ```powershell
   .\.venv\Scripts\python.exe src\run_pipeline.py
   ```

2. Confirm the six files listed below exist in `<repository>\data\processed\`.
3. Open `powerbi/pbip/OlistRetentionDashboard.pbip` in Power BI Desktop.
4. Select **Home > Transform data > Manage Parameters** and set the required `DataFolder` text parameter to the cloned repository's absolute `data\processed` path, for example `D:\Projects\ecommerce-retention-revenue-analysis\data\processed`. Do not include a trailing slash.
5. Select **Close & Apply** and refresh the semantic model. Each query appends its required filename to `DataFolder` before calling `File.Contents`.

## Required dashboard exports

- `data/processed/monthly_revenue_orders.csv`
- `data/processed/customer_purchase_summary.csv`
- `data/processed/cohort_retention.csv`
- `data/processed/cohort_horizon_summary.csv`
- `data/processed/rfm_segment_summary.csv`
- `data/processed/monthly_delivery_reviews.csv`

Each file's grain, key, date scope, and eligibility rule is documented in [metric definitions](../docs/metric_definitions.md).

| Power Query | Required CSV |
|---|---|
| `Monthly Revenue` | `monthly_revenue_orders.csv` |
| `Customers` | `customer_purchase_summary.csv` |
| `Cohort Retention` | `cohort_retention.csv` |
| `Cohort Horizons` | `cohort_horizon_summary.csv` |
| `RFM Segments` | `rfm_segment_summary.csv` |
| `Monthly Experience` | `monthly_delivery_reviews.csv` |

## Asset map

- `pbip/` - editable report and semantic model
- `theme/olist_portfolio_theme.json` - dashboard theme
- `dax/measures.dax` - reference measure library
- `semantic_model.md` - grains, keys, and relationships
- `dashboard_layout.md` - page and visual specifications
- `import_assembly_guide.md` - field-level assembly reference
- `validate_powerbi_assets.py` - export and project contract checks
- `validate_tmdl.ps1` - TMDL parsing and dependency checks

## Validation note

The designed semantic model contains seven public business tables and two explicit Date-to-monthly-fact relationships. Power BI Desktop can generate hidden Auto Date/Time tables and relationships when saving the project. The strict validators intentionally flag those generated objects. Disable Auto Date/Time and reconcile generated local date tables before running a clean publication validation.

The PDF is the verified static presentation artifact. The published `DataFolder` value is the nonworking placeholder `C:\SET_DATA_FOLDER`; every clone must update it before the next refresh. Refresh success must then be confirmed in Power BI Desktop.
