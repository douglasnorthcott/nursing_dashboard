# server.R
# ─────────────────────────────────────────────────────────────
# WIC KPI Nursing Dashboard — Shiny server logic
# ─────────────────────────────────────────────────────────────

function(input, output, session) {

  # ── 1. Collect raw monthly data ───────────────────────────────
  # monthly_data: reactive list  { "January 2026" = list(Sheet1 = df, ...), ... }

  monthly_data <- reactive({
    data <- list()

    # ── Demo data ────────────────────────────────────────────
    if (isTRUE(input$use_demo)) {
      for (month in c("January", "February", "March")) {
        label <- paste(month, "2026")
        tmp   <- tryCatch(
          generate_demo_xlsx(month),
          error = function(e) { showNotification(e$message, type = "error"); NULL }
        )
        if (!is.null(tmp)) {
          sheets <- tryCatch(
            load_excel_file(tmp, paste0(label, ".xlsx")),
            error = function(e) { showNotification(e$message, type = "error"); list() }
          )
          if (length(sheets) > 0) data[[label]] <- sheets
        }
      }
    }

    # ── Uploaded files ────────────────────────────────────────
    req_files <- input$xlsx_files
    if (!is.null(req_files) && nrow(req_files) > 0) {
      for (i in seq_len(nrow(req_files))) {
        filename <- req_files$name[i]
        path     <- req_files$datapath[i]

        parsed   <- extract_month_year(filename)
        label    <- if (!is.na(parsed$month)) {
          paste(parsed$month, parsed$year)
        } else {
          tools::file_path_sans_ext(filename)
        }

        sheets <- tryCatch(
          load_excel_file(path, filename),
          error = function(e) {
            showNotification(
              paste0("⚠️ Could not read '", filename, "': ", e$message),
              type     = "error",
              duration = 8
            )
            list()
          }
        )
        if (length(sheets) > 0) {
          # Merge with same-label data if already present
          if (!is.null(data[[label]])) {
            data[[label]] <- c(data[[label]], sheets)
          } else {
            data[[label]] <- sheets
          }
        }
      }
    }

    # Sort labels chronologically
    lbls <- names(data)
    if (length(lbls) > 1) {
      data <- data[lbls[order(month_sort_key(lbls))]]
    }
    data
  })

  # ── 2. Derived reactives ──────────────────────────────────────

  all_sheets <- reactive({
    md <- monthly_data()
    unique(unlist(lapply(md, names)))
  })

  sorted_labels <- reactive({
    names(monthly_data())
  })

  summary_df <- reactive({
    build_monthly_summary(monthly_data())
  })

  # Filtered summary for the selected sheet
  sheet_summary <- reactive({
    sel <- input$sheet_select
    req(sel)
    df <- summary_df()
    if (nrow(df) == 0 || !("Sheet" %in% colnames(df))) return(data.frame())
    df[df$Sheet == sel, , drop = FALSE]
  })

  numeric_kpi_cols <- reactive({
    df <- sheet_summary()
    if (nrow(df) == 0) return(character(0))
    candidates <- setdiff(names(df)[vapply(df, is.numeric, logical(1))], "Rows")
    # Keep only columns that have at least one non-NA value for this sheet
    candidates[vapply(candidates, function(c) any(!is.na(df[[c]])), logical(1))]
  })

  # ── 3. Sidebar UI outputs ─────────────────────────────────────

  output$sheet_selector_ui <- renderUI({
    sheets <- all_sheets()
    if (length(sheets) == 0) return(NULL)
    selectInput(
      "sheet_select",
      "Worksheet / KPI category",
      choices  = sheets,
      selected = sheets[1]
    )
  })

  output$month_filter_ui <- renderUI({
    lbls <- sorted_labels()
    if (length(lbls) == 0) return(NULL)
    checkboxGroupInput(
      "month_filter",
      "Filter months",
      choices  = lbls,
      selected = lbls
    )
  })

  # Update KPI multiselect when sheet changes
  observe({
    cols <- numeric_kpi_cols()
    updateSelectizeInput(session, "kpi_select",
      choices  = cols,
      selected = head(cols, 3)
    )
  })

  # ── 4. Status banner ──────────────────────────────────────────

  output$status_banner <- renderUI({
    md   <- monthly_data()
    lbls <- names(md)
    if (length(lbls) == 0) {
      return(
        div(class = "alert alert-info",
          icon("info-circle"),
          " Upload one or more .xlsx files in the sidebar, or enable ",
          strong("Load demo data"), " to explore sample data."
        )
      )
    }
    sheets <- all_sheets()
    div(
      class = "alert alert-success",
      style = "margin-bottom:8px;",
      icon("check-circle"),
      sprintf(
        " %d month(s) loaded: %s  ·  %d sheet(s): %s",
        length(lbls), paste(lbls, collapse = ", "),
        length(sheets), paste(sheets, collapse = ", ")
      )
    )
  })

  # ── 5. Value boxes (summary cards) ───────────────────────────

  output$value_boxes <- renderUI({
    df    <- sheet_summary()
    lbls  <- sorted_labels()
    filt  <- input$month_filter
    if (!is.null(filt)) lbls <- lbls[lbls %in% filt]
    df    <- df[df$Month %in% lbls, , drop = FALSE]

    cols  <- numeric_kpi_cols()
    if (nrow(df) == 0 || length(cols) == 0) return(NULL)

    df    <- df[order(month_sort_key(df$Month)), , drop = FALSE]
    latest <- df[nrow(df), , drop = FALSE]
    prev   <- if (nrow(df) >= 2) df[nrow(df) - 1, , drop = FALSE] else NULL

    # Only show columns that have at least one non-NA value for this sheet
    cols <- cols[vapply(cols, function(c) any(!is.na(df[[c]])), logical(1))]
    if (length(cols) == 0) return(NULL)

    box_list <- lapply(head(cols, 8), function(col) {
      val      <- latest[[col]]
      val_fmt  <- if (is.na(val)) "N/A" else formatC(val, format = "f", digits = 0, big.mark = ",")

      delta_ui <- NULL
      if (!is.null(prev)) {
        pv <- prev[[col]]
        if (!is.na(pv) && pv != 0 && !is.na(val)) {
          pct   <- (val - pv) / abs(pv) * 100
          arrow <- if (pct > 0) "▲" else if (pct < 0) "▼" else "●"
          cls   <- if (pct > 0) "delta-pos" else if (pct < 0) "delta-neg" else "delta-neu"
          delta_ui <- tags$span(
            class = cls,
            sprintf("%s %.1f%%", arrow, abs(pct))
          )
        }
      }

      infoBox(
        title    = col,
        value    = tagList(val_fmt, tags$br(), delta_ui),
        icon     = icon("chart-bar"),
        color    = "light-blue",
        fill     = FALSE,
        width    = 3
      )
    })

    do.call(tagList, box_list)
  })

  # ── 6. Trend chart ────────────────────────────────────────────

  output$trend_chart <- renderPlotly({
    df      <- sheet_summary()
    filt    <- input$month_filter
    kpis    <- input$kpi_select
    ctype   <- input$chart_type

    if (is.null(filt) || is.null(kpis) || nrow(df) == 0 || length(kpis) == 0)
      return(plotly_empty(type = "scatter") |> layout(title = "Select KPIs to chart"))

    df <- df[df$Month %in% filt, c("Month", kpis), drop = FALSE]
    df <- df[order(month_sort_key(df$Month)), , drop = FALSE]
    df$Month <- factor(df$Month, levels = df$Month)

    long <- pivot_longer(df, cols = all_of(kpis), names_to = "KPI", values_to = "Value")

    if (ctype == "Line") {
      p <- plot_ly(long, x = ~Month, y = ~Value, color = ~KPI,
                   type = "scatter", mode = "lines+markers",
                   marker = list(size = 8)) |>
        layout(title = "KPI Trends Over Time",
               xaxis = list(title = "Month"),
               yaxis = list(title = "Value"),
               legend = list(title = list(text = "KPI")))
    } else {
      p <- plot_ly(long, x = ~Month, y = ~Value, color = ~KPI,
                   type = "bar", barmode = "group") |>
        layout(title = "KPI Trends Over Time",
               xaxis = list(title = "Month"),
               yaxis = list(title = "Value"),
               legend = list(title = list(text = "KPI")))
    }
    p
  })

  # ── 7. Month-over-month % change table ───────────────────────

  output$mom_table <- renderDT({
    df   <- sheet_summary()
    filt <- input$month_filter
    cols <- numeric_kpi_cols()

    if (is.null(filt) || nrow(df) == 0 || length(cols) == 0) return(datatable(data.frame()))

    df   <- df[df$Month %in% filt, , drop = FALSE]
    df   <- df[order(month_sort_key(df$Month)), , drop = FALSE]
    months <- df$Month

    if (length(months) < 2) {
      return(datatable(
        data.frame(Note = "Need at least 2 months of data"),
        options = list(dom = "t"), rownames = FALSE
      ))
    }

    pct_rows <- lapply(seq(2, length(months)), function(i) {
      row <- list(Period = paste(months[i - 1], "→", months[i]))
      for (col in cols) {
        pv <- df[i - 1, col, drop = TRUE]
        cv <- df[i,     col, drop = TRUE]
        row[[col]] <- if (!is.na(pv) && !is.na(cv) && pv != 0) {
          round((cv - pv) / abs(pv) * 100, 1)
        } else NA_real_
      }
      as.data.frame(row, stringsAsFactors = FALSE)
    })
    pct_df <- bind_rows(pct_rows)

    datatable(
      pct_df,
      rownames  = FALSE,
      options   = list(pageLength = 10, scrollX = TRUE, dom = "tip"),
      caption   = "Month-over-month percentage change (%) per KPI"
    ) |>
      formatStyle(
        columns    = cols[cols %in% names(pct_df)],
        background = styleInterval(
          cuts   = c(-0.001, 0.001),
          values = c("#fde8e8", "#f5f5f5", "#e8fde8")
        )
      ) |>
      formatString(
        columns = cols[cols %in% names(pct_df)],
        suffix  = "%",
        mark    = ""
      )
  })

  # ── 8. Heatmap ────────────────────────────────────────────────

  output$heatmap_chart <- renderPlotly({
    df   <- sheet_summary()
    filt <- input$month_filter
    cols <- numeric_kpi_cols()

    if (is.null(filt) || nrow(df) == 0 || length(cols) == 0) {
      return(plotly_empty() |> layout(title = "No data for heatmap"))
    }

    df   <- df[df$Month %in% filt, , drop = FALSE]
    df   <- df[order(month_sort_key(df$Month)), , drop = FALSE]

    if (nrow(df) < 2) {
      return(plotly_empty() |> layout(title = "Need at least 2 months for heatmap"))
    }

    heat_mat <- as.matrix(df[, cols, drop = FALSE])
    rownames(heat_mat) <- df$Month

    # Normalize each column to 0–1
    norm_mat <- apply(heat_mat, 2, function(x) {
      mn <- min(x, na.rm = TRUE); mx <- max(x, na.rm = TRUE)
      if (mx == mn) rep(0.5, length(x)) else (x - mn) / (mx - mn)
    })

    plot_ly(
      x          = cols,
      y          = df$Month,
      z          = norm_mat,
      text       = round(heat_mat, 1),
      texttemplate = "%{text}",
      type       = "heatmap",
      colorscale = "RdYlGn",
      hovertemplate = "<b>%{y}</b><br>%{x}: %{text}<extra></extra>"
    ) |>
      layout(
        title  = "Normalized KPI Heatmap (green = high, red = low)",
        xaxis  = list(title = "KPI", tickangle = -30),
        yaxis  = list(title = "Month")
      )
  })

  # ── 9. Descriptive statistics table ───────────────────────────

  output$stats_table <- renderDT({
    df   <- sheet_summary()
    filt <- input$month_filter
    cols <- numeric_kpi_cols()

    if (is.null(filt) || nrow(df) == 0 || length(cols) == 0) return(datatable(data.frame()))

    df   <- df[df$Month %in% filt, cols, drop = FALSE]

    stats <- data.frame(
      Statistic = c("N", "Min", "Mean", "Median", "Max", "Std Dev"),
      stringsAsFactors = FALSE
    )
    for (col in cols) {
      x <- df[[col]]
      stats[[col]] <- round(c(
        sum(!is.na(x)),
        min(x, na.rm = TRUE),
        mean(x, na.rm = TRUE),
        median(x, na.rm = TRUE),
        max(x, na.rm = TRUE),
        sd(x, na.rm = TRUE)
      ), 2)
    }

    datatable(
      stats,
      rownames = FALSE,
      options  = list(pageLength = 10, scrollX = TRUE, dom = "tip"),
      caption  = "Descriptive statistics across loaded months"
    )
  })

  # ── 10. Raw data tab ──────────────────────────────────────────

  output$raw_month_ui <- renderUI({
    lbls <- sorted_labels()
    filt <- input$month_filter
    if (!is.null(filt)) lbls <- lbls[lbls %in% filt]
    if (length(lbls) == 0) return(NULL)
    selectInput("raw_month", "Select month", choices = lbls, selected = lbls[length(lbls)])
  })

  output$raw_table <- renderDT({
    sel_month <- input$raw_month
    sel_sheet <- input$sheet_select
    search_q  <- input$raw_search

    req(sel_month, sel_sheet)

    md <- monthly_data()
    df <- md[[sel_month]][[sel_sheet]]

    if (is.null(df) || nrow(df) == 0) {
      avail <- names(md[[sel_month]])
      return(datatable(
        data.frame(Note = paste0(
          "Sheet '", sel_sheet, "' not found in ", sel_month, ". ",
          "Available: ", paste(avail, collapse = ", ")
        )),
        options = list(dom = "t"), rownames = FALSE
      ))
    }

    # Text search filter
    if (!is.null(search_q) && nzchar(trimws(search_q))) {
      mask <- apply(df, 1, function(row) {
        any(grepl(search_q, as.character(row), ignore.case = TRUE))
      })
      df <- df[mask, , drop = FALSE]
    }

    datatable(
      df,
      rownames  = FALSE,
      filter    = "top",
      options   = list(
        pageLength = 15,
        scrollX   = TRUE,
        dom       = "lftip"
      ),
      caption = paste0(sel_sheet, " — ", sel_month,
                       " (", nrow(df), " rows × ", ncol(df), " columns)")
    )
  })
}
