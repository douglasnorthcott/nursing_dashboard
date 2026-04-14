# WIC KPI Dashboard — R Shiny Version

An interactive R Shiny dashboard for analyzing monthly WIC KPI Excel reports.
This is the R Shiny equivalent of the Python Streamlit dashboard in the parent directory.

---

## Features

| Feature | Details |
|---|---|
| **Manual file upload** | Upload one or more `.xlsx` files via the sidebar |
| **Auto month detection** | Parses filenames like `January 2026.xlsx` |
| **Multi-sheet support** | Every worksheet in the workbook is ingested |
| **Summary value boxes** | Latest-month KPI totals with ▲/▼ MoM delta |
| **Trend charts** | Interactive line or bar charts across all loaded months |
| **MoM % change table** | Color-coded month-over-month percentage change table |
| **KPI heatmap** | Normalized heatmap to spot patterns at a glance |
| **Descriptive statistics** | N, Min, Mean, Median, Max, SD per KPI |
| **Raw data viewer** | Per-month, per-sheet filterable table |
| **Demo mode** | 3 synthetic months of sample data — no files needed |

---

## Files

```
shiny_app/
├── global.R            # Shared helpers: ingestion, demo data, summary builder
├── ui.R                # shinydashboard UI definition
├── server.R            # Reactive server logic
├── install_packages.R  # One-time package installer
└── www/                # Static assets (logo, custom CSS if needed)
```

---

## Quick Start

### 1 — Install R (≥ 4.0)

Download from [https://cran.r-project.org](https://cran.r-project.org).

### 2 — Install required packages

```r
# In an R console or RStudio:
source("shiny_app/install_packages.R")
```

Or from the command line:

```bash
Rscript shiny_app/install_packages.R
```

Packages installed: `shiny`, `shinydashboard`, `readxl`, `openxlsx`, `dplyr`,
`tidyr`, `plotly`, `DT`, `scales`.

### 3 — Run the dashboard

**From R / RStudio:**

```r
shiny::runApp("shiny_app")
```

**From the command line:**

```bash
Rscript -e "shiny::runApp('shiny_app', port = 3838, launch.browser = TRUE)"
```

The app opens at **http://localhost:3838**.

---

## Providing Monthly Excel Files

Name your files `<Month> <Year>.xlsx`:

```
January 2026.xlsx
February 2026.xlsx
March 2026.xlsx
```

1. Run the app.
2. Click **Browse / Drop files** in the sidebar.
3. Select one or more `.xlsx` files — the dashboard updates automatically.

**Expected workbook structure**

- Column headers in **row 1** of each sheet.
- Numeric KPI values in subsequent rows.
- Avoid merged header cells.

---

## App Architecture

### `global.R`
Contains all pure helper functions — no Shiny dependencies — making them
independently testable:

| Function | Purpose |
|---|---|
| `extract_month_year(filename)` | Parse month + year from a filename |
| `month_sort_key(labels)` | Numeric sort key for chronological ordering |
| `load_excel_file(path, filename)` | Read all sheets from an `.xlsx` file |
| `generate_demo_xlsx(month)` | Create synthetic demo workbook |
| `build_monthly_summary(monthly_data)` | Aggregate numeric KPI sums per month/sheet |

### `ui.R`
`shinydashboard` layout — sidebar with file upload + filters, main area with
`tabBox` holding five tabs (Trends, MoM Change, Heatmap, Statistics, Raw Data).

### `server.R`
Reactive graph:

```
xlsx_files / use_demo
        │
        ▼
  monthly_data  ──► all_sheets ──► sheet_selector_ui
        │
        ▼
  summary_df  ──► sheet_summary ──► numeric_kpi_cols
        │                 │
        │          ┌──────┼──────┬──────────┬──────────┐
        │          ▼      ▼      ▼          ▼          ▼
        │     value_  trend_ mom_    heatmap_   stats_
        │     boxes  chart  table   chart      table
        │
        └──► raw_table  (via monthly_data directly)
```

---

## Extending to Google Drive

See the `gdrive_loader.py` module in the parent directory for the integration
pattern. In R, the equivalent approach uses the `googledrive` package:

```r
# Install once
install.packages("googledrive")

# Authenticate (interactive or via service account)
googledrive::drive_auth(path = Sys.getenv("GDRIVE_SERVICE_ACCOUNT_JSON"))

# List .xlsx files in the target folder
files <- googledrive::drive_ls(
  path   = googledrive::as_id(Sys.getenv("GDRIVE_FOLDER_ID")),
  type   = "spreadsheet"
)

# Download each file
for (i in seq_len(nrow(files))) {
  tmp <- tempfile(fileext = ".xlsx")
  googledrive::drive_download(files$id[i], path = tmp, overwrite = TRUE)
  sheets <- load_excel_file(tmp, files$name[i])
  # … add to monthly_data
}
```

Set these environment variables before running:

```bash
export GDRIVE_FOLDER_ID="<your-drive-folder-id>"
export GDRIVE_SERVICE_ACCOUNT_JSON="/path/to/service-account.json"
```

---

## Deployment

### shinyapps.io (free tier)

```r
install.packages("rsconnect")
rsconnect::deployApp("shiny_app", appName = "wic-kpi-dashboard")
```

### Shiny Server (self-hosted)

Copy the `shiny_app/` folder to `/srv/shiny-server/wic_kpi/` on your server.

### Docker

```dockerfile
FROM rocker/shiny:4.3.3
RUN R -e "install.packages(c('shinydashboard','readxl','openxlsx','dplyr','tidyr','plotly','DT','scales'), repos='https://cloud.r-project.org')"
COPY shiny_app/ /srv/shiny-server/wic_kpi/
EXPOSE 3838
```

```bash
docker build -t wic-shiny .
docker run -p 3838:3838 wic-shiny
```
