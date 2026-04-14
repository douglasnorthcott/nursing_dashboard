"""
WIC KPI Nursing Dashboard
=========================
A Streamlit dashboard for analyzing monthly WIC KPI Excel reports.

Upload one or more monthly .xlsx files (e.g. "January 2026.xlsx",
"February 2026.xlsx") to explore trends, summaries, and comparisons
across months.
"""

import io
import re
from collections import defaultdict

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

# ─────────────────────────────────────────────────────────────
# Page config
# ─────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="WIC KPI Dashboard",
    page_icon="🏥",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ─────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────
MONTH_ORDER = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]

# ─────────────────────────────────────────────────────────────
# Helpers – file ingestion
# ─────────────────────────────────────────────────────────────

def _extract_month_year(filename: str) -> tuple[str, str] | tuple[None, None]:
    """Try to pull a month and year from a filename like 'January 2026.xlsx'."""
    name = filename.replace(".xlsx", "").replace(".xls", "").strip()
    # Try "Month YYYY" or "YYYY-MM" or "MM-YYYY"
    for month in MONTH_ORDER:
        if month.lower() in name.lower():
            year_match = re.search(r"(\d{4})", name)
            year = year_match.group(1) if year_match else "Unknown"
            return month, year
    # Fallback: try numeric month
    m = re.search(r"(\d{4})[_\-](\d{1,2})", name)
    if m:
        try:
            month_idx = int(m.group(2))
            if 1 <= month_idx <= 12:
                return MONTH_ORDER[month_idx - 1], m.group(1)
        except ValueError:
            pass
    m = re.search(r"(\d{1,2})[_\-](\d{4})", name)
    if m:
        try:
            month_idx = int(m.group(1))
            if 1 <= month_idx <= 12:
                return MONTH_ORDER[month_idx - 1], m.group(2)
        except ValueError:
            pass
    return None, None


def _coerce_numeric(df: pd.DataFrame) -> pd.DataFrame:
    """Try to coerce object columns to numeric where most values are numbers."""
    for col in df.select_dtypes(include="object").columns:
        converted = pd.to_numeric(df[col], errors="coerce")
        ratio = converted.notna().sum() / max(len(df), 1)
        if ratio > 0.5:
            df[col] = converted
    return df


def load_excel(file_bytes: bytes, filename: str) -> dict[str, pd.DataFrame]:
    """
    Load all sheets from an Excel file.

    Returns a dict mapping sheet_name -> DataFrame, with columns cleaned up.
    Raises ValueError with a user-friendly message on parse failure.
    """
    try:
        xls = pd.ExcelFile(io.BytesIO(file_bytes), engine="openpyxl")
    except Exception as exc:
        raise ValueError(f"Could not open '{filename}': {exc}") from exc

    sheets: dict[str, pd.DataFrame] = {}
    for sheet in xls.sheet_names:
        try:
            df = pd.read_excel(xls, sheet_name=sheet, header=0)
            # Drop completely empty rows/columns
            df.dropna(how="all", inplace=True)
            df.dropna(axis=1, how="all", inplace=True)
            # Trim whitespace from string columns
            for col in df.select_dtypes(include="object").columns:
                df[col] = df[col].astype(str).str.strip()
                df[col] = df[col].replace("nan", pd.NA)
            df = _coerce_numeric(df)
            df.columns = [str(c).strip() for c in df.columns]
            if not df.empty:
                sheets[sheet] = df
        except Exception as exc:
            st.warning(f"⚠️ Could not read sheet '{sheet}' from '{filename}': {exc}")
    return sheets


# ─────────────────────────────────────────────────────────────
# Helpers – KPI analysis
# ─────────────────────────────────────────────────────────────

def numeric_columns(df: pd.DataFrame) -> list[str]:
    return df.select_dtypes(include="number").columns.tolist()


def build_monthly_summary(
    monthly_data: dict[str, dict[str, pd.DataFrame]]
) -> pd.DataFrame:
    """
    Build a month-level summary DataFrame.

    monthly_data: {label: {sheet_name: df}}
    Returns a DataFrame with columns [Month, Sheet, <numeric col sums...>]
    """
    rows = []
    for label, sheets in monthly_data.items():
        for sheet_name, df in sheets.items():
            num_cols = numeric_columns(df)
            row = {"Month": label, "Sheet": sheet_name, "Rows": len(df)}
            for col in num_cols:
                row[col] = df[col].sum(skipna=True)
            rows.append(row)
    if not rows:
        return pd.DataFrame()
    return pd.DataFrame(rows)


def month_sort_key(label: str) -> tuple[int, int]:
    """Return (year, month_index) for sorting labels like 'January 2026'."""
    for i, m in enumerate(MONTH_ORDER):
        if m.lower() in label.lower():
            year_match = re.search(r"(\d{4})", label)
            year = int(year_match.group(1)) if year_match else 0
            return (year, i)
    return (9999, 99)


# ─────────────────────────────────────────────────────────────
# UI components
# ─────────────────────────────────────────────────────────────

def render_summary_cards(summary_df: pd.DataFrame, selected_sheet: str):
    """Render top-level KPI summary cards for the latest month."""
    sheet_df = summary_df[summary_df["Sheet"] == selected_sheet].copy()
    if sheet_df.empty:
        st.info("No data available for summary cards.")
        return

    sheet_df = sheet_df.sort_values("Month", key=lambda s: s.map(month_sort_key))
    latest = sheet_df.iloc[-1]
    prev = sheet_df.iloc[-2] if len(sheet_df) > 1 else None

    numeric_cols = [
        c for c in sheet_df.columns if c not in ("Month", "Sheet", "Rows")
    ]

    if not numeric_cols:
        st.info("No numeric KPI columns detected for summary cards.")
        return

    st.subheader(f"📊 Latest Month Summary — {latest['Month']}")
    cols = st.columns(min(len(numeric_cols), 4))
    for i, col_name in enumerate(numeric_cols[:8]):
        val = latest.get(col_name, 0)
        delta = None
        if prev is not None:
            prev_val = prev.get(col_name, 0)
            if pd.notna(prev_val) and prev_val != 0:
                delta = f"{((val - prev_val) / abs(prev_val)) * 100:.1f}%"
        with cols[i % 4]:
            st.metric(
                label=col_name,
                value=f"{val:,.0f}" if pd.notna(val) else "N/A",
                delta=delta,
            )


def render_trend_chart(summary_df: pd.DataFrame, selected_sheet: str):
    """Render a line/bar trend chart across months."""
    sheet_df = summary_df[summary_df["Sheet"] == selected_sheet].copy()
    if sheet_df.empty:
        return

    sheet_df = sheet_df.sort_values("Month", key=lambda s: s.map(month_sort_key))
    numeric_cols = [
        c for c in sheet_df.columns if c not in ("Month", "Sheet", "Rows")
    ]
    if not numeric_cols:
        return

    st.subheader("📈 Month-over-Month Trends")

    selected_kpis = st.multiselect(
        "Select KPIs to chart",
        options=numeric_cols,
        default=numeric_cols[:min(3, len(numeric_cols))],
        key=f"kpi_select_{selected_sheet}",
    )
    if not selected_kpis:
        st.info("Select at least one KPI above to see the trend chart.")
        return

    chart_type = st.radio(
        "Chart type", ["Line", "Bar"], horizontal=True, key=f"chart_type_{selected_sheet}"
    )

    plot_df = sheet_df[["Month"] + selected_kpis].melt(
        id_vars="Month", var_name="KPI", value_name="Value"
    )

    if chart_type == "Line":
        fig = px.line(
            plot_df,
            x="Month",
            y="Value",
            color="KPI",
            markers=True,
            title="KPI Trends Over Time",
        )
    else:
        fig = px.bar(
            plot_df,
            x="Month",
            y="Value",
            color="KPI",
            barmode="group",
            title="KPI Trends Over Time",
        )

    fig.update_layout(xaxis_title="Month", yaxis_title="Value", legend_title="KPI")
    st.plotly_chart(fig, use_container_width=True)


def render_mom_comparison(summary_df: pd.DataFrame, selected_sheet: str):
    """Month-over-month % change table."""
    sheet_df = summary_df[summary_df["Sheet"] == selected_sheet].copy()
    if len(sheet_df) < 2:
        return

    sheet_df = sheet_df.sort_values("Month", key=lambda s: s.map(month_sort_key))
    numeric_cols = [
        c for c in sheet_df.columns if c not in ("Month", "Sheet", "Rows")
    ]
    if not numeric_cols:
        return

    st.subheader("🔄 Month-over-Month % Change")

    pct_rows = []
    months = sheet_df["Month"].tolist()
    for i in range(1, len(months)):
        row = {"Period": f"{months[i-1]} → {months[i]}"}
        for col in numeric_cols:
            prev_val = sheet_df.iloc[i - 1][col]
            curr_val = sheet_df.iloc[i][col]
            if pd.notna(prev_val) and pd.notna(curr_val) and prev_val != 0:
                row[col] = round(((curr_val - prev_val) / abs(prev_val)) * 100, 1)
            else:
                row[col] = None
        pct_rows.append(row)

    pct_df = pd.DataFrame(pct_rows)

    def color_delta(val):
        if pd.isna(val):
            return ""
        color = "green" if val > 0 else ("red" if val < 0 else "grey")
        return f"color: {color}"

    styled = pct_df.style.applymap(
        color_delta,
        subset=[c for c in pct_df.columns if c != "Period"],
    ).format(
        {c: "{:+.1f}%" for c in pct_df.columns if c != "Period"},
        na_rep="—",
    )
    st.dataframe(styled, use_container_width=True)


def render_raw_data(sheets: dict[str, pd.DataFrame], selected_sheet: str, month_label: str):
    """Render the raw data table for a selected sheet."""
    df = sheets.get(selected_sheet)
    if df is None or df.empty:
        st.info("No data to display.")
        return

    st.subheader(f"📋 Raw Data — {selected_sheet} ({month_label})")

    # Search/filter
    search = st.text_input("🔍 Filter rows (case-insensitive text search)", key=f"search_{month_label}_{selected_sheet}")
    if search:
        mask = df.apply(
            lambda col: col.astype(str).str.contains(search, case=False, na=False)
        ).any(axis=1)
        df = df[mask]

    st.dataframe(df, use_container_width=True)
    st.caption(f"{len(df):,} rows × {len(df.columns):,} columns")


def render_heatmap(summary_df: pd.DataFrame, selected_sheet: str):
    """Render a heatmap of KPI values across months."""
    sheet_df = summary_df[summary_df["Sheet"] == selected_sheet].copy()
    if sheet_df.empty or len(sheet_df) < 2:
        return

    numeric_cols = [
        c for c in sheet_df.columns if c not in ("Month", "Sheet", "Rows")
    ]
    if not numeric_cols:
        return

    st.subheader("🌡️ KPI Heatmap (Normalized)")
    sheet_df = sheet_df.sort_values("Month", key=lambda s: s.map(month_sort_key))
    heat_df = sheet_df[["Month"] + numeric_cols].set_index("Month")

    # Normalize each column 0-1 for comparable heatmap
    normed = heat_df.copy()
    for col in normed.columns:
        col_min = normed[col].min()
        col_max = normed[col].max()
        if col_max != col_min:
            normed[col] = (normed[col] - col_min) / (col_max - col_min)
        else:
            normed[col] = 0.5

    fig = go.Figure(
        data=go.Heatmap(
            z=normed.values,
            x=normed.columns.tolist(),
            y=normed.index.tolist(),
            colorscale="RdYlGn",
            text=heat_df.values.round(1),
            texttemplate="%{text}",
            hoverongaps=False,
        )
    )
    fig.update_layout(
        title="Normalized KPI Heatmap (green = high, red = low)",
        xaxis_title="KPI",
        yaxis_title="Month",
    )
    st.plotly_chart(fig, use_container_width=True)


# ─────────────────────────────────────────────────────────────
# Sample data generator (for demo/testing)
# ─────────────────────────────────────────────────────────────

def generate_sample_excel(month: str, year: int = 2026) -> bytes:
    """Generate a synthetic WIC KPI Excel workbook for demo purposes."""
    import random

    random.seed(MONTH_ORDER.index(month))
    base = 100 + MONTH_ORDER.index(month) * 5

    summary_data = {
        "Program": ["WIC", "Nutrition Counseling", "Breastfeeding Support", "Referrals"],
        "Participants": [base + random.randint(-10, 10) for _ in range(4)],
        "Certifications": [base - 20 + random.randint(-5, 5) for _ in range(4)],
        "Follow-up Visits": [base - 30 + random.randint(-8, 8) for _ in range(4)],
        "New Enrollments": [random.randint(10, 40) for _ in range(4)],
        "Retention Rate (%)": [round(random.uniform(75, 95), 1) for _ in range(4)],
    }
    outcomes_data = {
        "Outcome": ["Healthy Weight", "Breastfeeding 6mo", "Iron Deficiency", "On-Track Development"],
        "Count": [random.randint(50, 150) for _ in range(4)],
        "Target": [120, 90, 20, 110],
        "% of Target": [round(random.uniform(70, 110), 1) for _ in range(4)],
    }

    buf = io.BytesIO()
    with pd.ExcelWriter(buf, engine="openpyxl") as writer:
        pd.DataFrame(summary_data).to_excel(writer, sheet_name="Summary", index=False)
        pd.DataFrame(outcomes_data).to_excel(writer, sheet_name="Outcomes", index=False)
    return buf.getvalue()


# ─────────────────────────────────────────────────────────────
# Main app
# ─────────────────────────────────────────────────────────────

def main():
    # ── Sidebar ──────────────────────────────────────────────
    with st.sidebar:
        st.image(
            "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/WIC_logo.svg/200px-WIC_logo.svg.png",
            width=140,
        )
        st.title("WIC KPI Dashboard")
        st.markdown("---")

        st.header("📁 Upload Monthly Files")
        uploaded_files = st.file_uploader(
            "Drop one or more monthly .xlsx files here",
            type=["xlsx", "xls"],
            accept_multiple_files=True,
            help="Name files like 'January 2026.xlsx', 'February 2026.xlsx', etc.",
        )

        st.markdown("---")
        use_demo = st.checkbox(
            "Load demo data (3 sample months)",
            value=not bool(uploaded_files),
            help="Pre-loads synthetic January, February, March 2026 data.",
        )

        st.markdown("---")
        st.markdown(
            """
            **How to use**
            1. Upload one or more `.xlsx` files.
            2. Name them *Month YYYY* (e.g. `March 2026.xlsx`).
            3. Explore the tabs below.

            **Google Drive integration**
            Set the env vars `GDRIVE_FOLDER_ID` and
            `GDRIVE_SERVICE_ACCOUNT_JSON` and extend
            `gdrive_loader.py` to fetch files automatically.
            """
        )

    # ── Collect data ─────────────────────────────────────────
    # {label: {sheet_name: df}}
    monthly_data: dict[str, dict[str, pd.DataFrame]] = {}
    errors: list[str] = []

    # Demo data
    if use_demo:
        for month in ["January", "February", "March"]:
            label = f"{month} 2026"
            try:
                sheets = load_excel(generate_sample_excel(month), f"{label}.xlsx")
                if sheets:
                    monthly_data[label] = sheets
            except ValueError as exc:
                errors.append(str(exc))

    # Uploaded files
    for uf in uploaded_files:
        filename = uf.name
        month, year = _extract_month_year(filename)
        label = f"{month} {year}" if month else filename.replace(".xlsx", "").replace(".xls", "")
        try:
            sheets = load_excel(uf.read(), filename)
            if sheets:
                if label in monthly_data:
                    # Merge sheets from same-month duplicate uploads
                    monthly_data[label].update(sheets)
                else:
                    monthly_data[label] = sheets
        except ValueError as exc:
            errors.append(str(exc))

    # ── Error display ─────────────────────────────────────────
    for err in errors:
        st.error(err)

    # ── No data state ─────────────────────────────────────────
    if not monthly_data:
        st.title("🏥 WIC KPI Nursing Dashboard")
        st.info(
            "👈  Upload one or more monthly `.xlsx` files in the sidebar, "
            "or enable **Load demo data** to explore with sample data."
        )
        st.stop()

    # ── Sort months chronologically ───────────────────────────
    sorted_labels = sorted(monthly_data.keys(), key=month_sort_key)
    monthly_data = {k: monthly_data[k] for k in sorted_labels}

    # ── Collect all sheet names ────────────────────────────────
    all_sheets: list[str] = []
    for sheets in monthly_data.values():
        for s in sheets:
            if s not in all_sheets:
                all_sheets.append(s)

    # ── Build summary ─────────────────────────────────────────
    summary_df = build_monthly_summary(monthly_data)

    # ── Header ────────────────────────────────────────────────
    st.title("🏥 WIC KPI Nursing Dashboard")
    months_loaded = list(monthly_data.keys())
    st.caption(
        f"Loaded {len(months_loaded)} month(s): {', '.join(months_loaded)}  |  "
        f"{len(all_sheets)} sheet(s): {', '.join(all_sheets)}"
    )

    # ── Sheet selector ────────────────────────────────────────
    selected_sheet = st.selectbox(
        "Select worksheet / KPI category",
        options=all_sheets,
        key="sheet_selector",
    )

    st.markdown("---")

    # ── Tabs ──────────────────────────────────────────────────
    tab_summary, tab_trends, tab_mom, tab_heatmap, tab_raw = st.tabs(
        ["📊 Summary", "📈 Trends", "🔄 MoM Change", "🌡️ Heatmap", "📋 Raw Data"]
    )

    with tab_summary:
        render_summary_cards(summary_df, selected_sheet)

        # Quick stats table
        if not summary_df.empty:
            sheet_sum = summary_df[summary_df["Sheet"] == selected_sheet]
            if not sheet_sum.empty:
                num_cols = [
                    c for c in sheet_sum.columns if c not in ("Month", "Sheet", "Rows")
                ]
                if num_cols:
                    st.subheader("📉 Descriptive Statistics")
                    st.dataframe(
                        sheet_sum[num_cols].describe().round(1),
                        use_container_width=True,
                    )

    with tab_trends:
        render_trend_chart(summary_df, selected_sheet)

    with tab_mom:
        render_mom_comparison(summary_df, selected_sheet)
        if len(months_loaded) < 2:
            st.info("Upload at least 2 months of data to see month-over-month comparisons.")

    with tab_heatmap:
        render_heatmap(summary_df, selected_sheet)
        if len(months_loaded) < 2:
            st.info("Upload at least 2 months of data to see the heatmap.")

    with tab_raw:
        month_for_raw = st.selectbox(
            "Select month",
            options=sorted_labels,
            key="raw_month_select",
        )
        if month_for_raw in monthly_data and selected_sheet in monthly_data[month_for_raw]:
            render_raw_data(
                monthly_data[month_for_raw],
                selected_sheet,
                month_for_raw,
            )
        else:
            available = list(monthly_data.get(month_for_raw, {}).keys())
            st.info(
                f"Sheet '{selected_sheet}' not found in {month_for_raw}. "
                f"Available sheets: {available or 'none'}"
            )

    # ── Footer ────────────────────────────────────────────────
    st.markdown("---")
    st.caption(
        "WIC KPI Dashboard · Built with Streamlit · "
        "[GitHub](https://github.com/douglasnorthcott/nursing_dashboard)"
    )


if __name__ == "__main__":
    main()
