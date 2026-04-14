# ui.R
# ─────────────────────────────────────────────────────────────
# WIC KPI Nursing Dashboard — Shiny UI definition
# ─────────────────────────────────────────────────────────────

dashboardPage(
  skin = "blue",

  # ── Header ──────────────────────────────────────────────────
  dashboardHeader(
    title = tags$span(
      tags$img(src = "wic_logo.png", height = "28px", style = "margin-right:6px;"),
      "WIC KPI Dashboard"
    ),
    titleWidth = 280
  ),

  # ── Sidebar ─────────────────────────────────────────────────
  dashboardSidebar(
    width = 280,

    tags$div(
      style = "padding: 10px 15px;",

      h4("📁 Upload Monthly Files"),
      fileInput(
        "xlsx_files",
        label    = NULL,
        multiple = TRUE,
        accept   = c(".xlsx", ".xls"),
        placeholder = "January 2026.xlsx …",
        buttonLabel = "Browse / Drop files"
      ),

      tags$hr(),

      checkboxInput(
        "use_demo",
        label = "Load demo data (3 sample months)",
        value = TRUE
      ),

      tags$hr(),

      uiOutput("sheet_selector_ui"),
      uiOutput("month_filter_ui"),

      tags$hr(),

      tags$small(
        tags$b("How to use:"),
        tags$ol(
          style = "padding-left:18px; margin-top:4px;",
          tags$li("Upload one or more .xlsx files above."),
          tags$li("Name them Month YYYY, e.g. March 2026.xlsx."),
          tags$li("Explore the dashboard tabs.")
        ),
        tags$b("Google Drive:"),
        tags$br(),
        "Set ", tags$code("GDRIVE_FOLDER_ID"), " and ",
        tags$code("GDRIVE_SERVICE_ACCOUNT_JSON"), " env vars — see README."
      )
    )
  ),

  # ── Body ─────────────────────────────────────────────────────
  dashboardBody(

    # Custom CSS
    tags$head(
      tags$style(HTML("
        .info-box { min-height: 80px; }
        .info-box-icon { height: 80px; line-height: 80px; }
        .info-box-content { padding-top: 10px; padding-bottom: 10px; }
        .nav-tabs-custom .nav-tabs li.active a { font-weight: bold; }
        .small-box h3 { font-size: 30px; }
        .delta-pos { color: #27ae60; font-weight: bold; }
        .delta-neg { color: #e74c3c; font-weight: bold; }
        .delta-neu { color: #7f8c8d; }
      "))
    ),

    # ── Status banner ────────────────────────────────────────
    fluidRow(
      column(12, uiOutput("status_banner"))
    ),

    # ── Summary value boxes ──────────────────────────────────
    fluidRow(
      uiOutput("value_boxes")
    ),

    # ── Tabs ─────────────────────────────────────────────────
    fluidRow(
      column(12,
        tabBox(
          width = 12,
          id = "main_tabs",

          # Tab 1 — Trends
          tabPanel(
            title = tagList(icon("chart-line"), " Trends"),
            value = "tab_trends",
            fluidRow(
              column(6,
                selectizeInput(
                  "kpi_select",
                  "Select KPIs to chart",
                  choices  = NULL,
                  multiple = TRUE
                )
              ),
              column(3,
                radioButtons(
                  "chart_type",
                  "Chart type",
                  choices  = c("Line", "Bar"),
                  inline   = TRUE,
                  selected = "Line"
                )
              )
            ),
            plotlyOutput("trend_chart", height = "420px")
          ),

          # Tab 2 — MoM Change
          tabPanel(
            title = tagList(icon("exchange-alt"), " MoM Change"),
            value = "tab_mom",
            DTOutput("mom_table")
          ),

          # Tab 3 — Heatmap
          tabPanel(
            title = tagList(icon("th"), " Heatmap"),
            value = "tab_heatmap",
            plotlyOutput("heatmap_chart", height = "420px")
          ),

          # Tab 4 — Descriptive Stats
          tabPanel(
            title = tagList(icon("table"), " Statistics"),
            value = "tab_stats",
            DTOutput("stats_table")
          ),

          # Tab 5 — Raw Data
          tabPanel(
            title = tagList(icon("database"), " Raw Data"),
            value = "tab_raw",
            fluidRow(
              column(4,
                uiOutput("raw_month_ui")
              ),
              column(8,
                textInput("raw_search", "🔍 Filter rows", placeholder = "Type to search…")
              )
            ),
            DTOutput("raw_table")
          )
        )
      )
    ),

    # ── Footer ────────────────────────────────────────────────
    fluidRow(
      column(12,
        tags$hr(),
        tags$p(
          style = "color:#95a5a6; font-size:12px; text-align:center;",
          "WIC KPI Dashboard · Built with R Shiny · ",
          tags$a(
            "GitHub",
            href   = "https://github.com/douglasnorthcott/nursing_dashboard",
            target = "_blank"
          )
        )
      )
    )
  )
)
