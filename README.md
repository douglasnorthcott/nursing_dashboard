# 🏥 WIC KPI Nursing Dashboard

A lightweight, interactive dashboard built with [Streamlit](https://streamlit.io) for analyzing monthly WIC (Women, Infants, and Children) KPI reports stored as Excel workbooks.

---

## Features

| Feature | Details |
|---|---|
| **Manual file upload** | Drop one or more `.xlsx` files via the sidebar |
| **Auto month detection** | Parses filenames like `January 2026.xlsx` |
| **Multi-sheet support** | Every worksheet in the workbook is ingested |
| **Summary cards** | Latest month KPI totals with MoM delta |
| **Trend charts** | Line or bar charts across all loaded months |
| **MoM % change table** | Color-coded month-over-month percentage changes |
| **KPI heatmap** | Normalized heatmap to spot patterns at a glance |
| **Raw data viewer** | Filterable table for any sheet/month |
| **Demo mode** | 3 synthetic months of sample data — no files needed |
| **Error handling** | Graceful warnings for unreadable sheets/files |

---

## Quick Start

### 1 — Prerequisites

- Python 3.10 or later
- `pip`

### 2 — Install dependencies

```bash
pip install -r requirements.txt
```

### 3 — Run the dashboard

```bash
streamlit run app.py
```

The app will open at **http://localhost:8501** in your browser.

> **Tip:** Enable *Load demo data* in the sidebar to explore the dashboard instantly without uploading any files.

---

## Providing Monthly Excel Files

### File naming convention

Name your files `<Month> <Year>.xlsx`, for example:

```
January 2026.xlsx
February 2026.xlsx
March 2026.xlsx
```

The dashboard will automatically extract the month and year from the filename and order the data chronologically. Files with other naming patterns are accepted but will use the raw filename as the month label.

### Upload via the UI

1. Run the app (`streamlit run app.py`).
2. Click **Browse files** (or drag & drop) in the left sidebar.
3. Select one or more `.xlsx` files.
4. The dashboard updates automatically.

### Expected workbook structure

The dashboard is schema-agnostic — it will ingest any worksheet. For best results:

- Each sheet should have **column headers in the first row**.
- KPI values should be **numeric** (integers or floats).
- Avoid merged cells in the header row.

If the structure differs (e.g., headers on row 3), you can adjust the `header=0` argument in `load_excel()` inside `app.py`.

---

## Project Structure

```
nursing_dashboard/
├── app.py              # Main Streamlit application
├── gdrive_loader.py    # Optional Google Drive integration module
├── requirements.txt    # Python dependencies
├── .gitignore
└── README.md
```

---

## Extending to Google Drive

`gdrive_loader.py` contains a ready-to-use integration layer. To activate it:

### Step 1 — Create a Google Cloud service account

1. Go to [Google Cloud Console](https://console.cloud.google.com).
2. Create a project (or use an existing one).
3. Enable the **Google Drive API**.
4. Create a **Service Account** and download its JSON key file.
5. Share the Google Drive folder (`WIC KPI`) with the service account's email address (give it **Viewer** access).

### Step 2 — Set environment variables

```bash
export GDRIVE_FOLDER_ID="<your-folder-id>"
export GDRIVE_SERVICE_ACCOUNT_JSON="/path/to/service-account.json"
# or paste the raw JSON string instead of the file path
```

The folder ID is the long string at the end of the folder's Google Drive URL.

### Step 3 — Install extra dependencies

```bash
pip install google-api-python-client google-auth
```

### Step 4 — Wire it into the app

In `app.py`, add the following block after the sidebar upload section:

```python
from gdrive_loader import is_configured, list_monthly_files, download_file

if is_configured():
    with st.sidebar:
        if st.button("🔄 Sync from Google Drive"):
            with st.spinner("Fetching files from Google Drive…"):
                for file_meta in list_monthly_files():
                    xlsx_bytes = download_file(file_meta["id"])
                    sheets = load_excel(xlsx_bytes, file_meta["name"])
                    month, year = _extract_month_year(file_meta["name"])
                    label = f"{month} {year}" if month else file_meta["name"]
                    monthly_data[label] = sheets
```

---

## Deployment

### Streamlit Community Cloud (free)

1. Push this repository to GitHub.
2. Go to [share.streamlit.io](https://share.streamlit.io) and connect the repo.
3. Set the main file to `app.py`.
4. Add `GDRIVE_FOLDER_ID` and `GDRIVE_SERVICE_ACCOUNT_JSON` as **Secrets** in the Streamlit Cloud settings if you want Google Drive auto-sync.

### Docker

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
```

```bash
docker build -t wic-dashboard .
docker run -p 8501:8501 wic-dashboard
```

---

## Contributing

Pull requests are welcome. For major changes please open an issue first.

---

## License

MIT
