# global.R
# ─────────────────────────────────────────────────────────────
# WIC KPI Nursing Dashboard — shared helpers loaded by both
# ui.R and server.R (and by any tests).
# ─────────────────────────────────────────────────────────────

library(shiny)
library(shinydashboard)
library(readxl)
library(dplyr)
library(tidyr)
library(plotly)
library(DT)
library(scales)

# ── Constants ────────────────────────────────────────────────

MONTH_ORDER <- c(
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
)

# ── Month / year extraction ───────────────────────────────────

#' Extract (month, year) from a filename like "January 2026.xlsx".
#' Returns a named list with $month and $year (both character).
#' Returns list(month = NA, year = NA) on failure.
extract_month_year <- function(filename) {
  name <- tools::file_path_sans_ext(basename(filename))
  name <- trimws(name)

  # Try each named month
  for (m in MONTH_ORDER) {
    if (grepl(m, name, ignore.case = TRUE)) {
      yr <- regmatches(name, regexpr("\\d{4}", name))
      year <- if (length(yr) == 1) yr else "Unknown"
      return(list(month = m, year = year))
    }
  }

  # Fallback: YYYY-MM or MM-YYYY
  m1 <- regmatches(name, regexpr("(\\d{4})[_\\-](\\d{1,2})", name, perl = TRUE))
  if (length(m1) == 1) {
    parts <- strsplit(m1, "[_\\-]")[[1]]
    idx <- as.integer(parts[2])
    if (!is.na(idx) && idx >= 1 && idx <= 12)
      return(list(month = MONTH_ORDER[idx], year = parts[1]))
  }

  m2 <- regmatches(name, regexpr("(\\d{1,2})[_\\-](\\d{4})", name, perl = TRUE))
  if (length(m2) == 1) {
    parts <- strsplit(m2, "[_\\-]")[[1]]
    idx <- as.integer(parts[1])
    if (!is.na(idx) && idx >= 1 && idx <= 12)
      return(list(month = MONTH_ORDER[idx], year = parts[2]))
  }

  list(month = NA_character_, year = NA_character_)
}

#' Sort key for a "Month YYYY" label — returns a numeric value
#' suitable for use with order().
month_sort_key <- function(labels) {
  vapply(labels, function(lbl) {
    yr  <- regmatches(lbl, regexpr("\\d{4}", lbl))
    year_num <- if (length(yr) == 1) as.integer(yr) else 9999L
    month_idx <- which(
      vapply(MONTH_ORDER, function(m) grepl(m, lbl, ignore.case = TRUE), logical(1))
    )
    idx <- if (length(month_idx) > 0) month_idx[1] else 99L
    year_num * 100L + idx
  }, numeric(1))
}

# ── Excel ingestion ───────────────────────────────────────────

#' Read all non-empty sheets from an xlsx file (given a path).
#' Returns a named list of data frames, one per sheet.
#' Emits a warning (not an error) for sheets that cannot be parsed.
load_excel_file <- function(path, filename = basename(path)) {
  sheet_names <- tryCatch(
    excel_sheets(path),
    error = function(e) stop(paste0("Cannot open '", filename, "': ", e$message))
  )

  result <- list()
  for (sn in sheet_names) {
    df <- tryCatch({
      raw <- read_excel(path, sheet = sn, col_names = TRUE, .name_repair = "unique")
      # Drop all-NA rows and columns
      raw <- raw[rowSums(!is.na(raw)) > 0, , drop = FALSE]
      raw <- raw[, colSums(!is.na(raw)) > 0, drop = FALSE]
      # Coerce column names to character
      colnames(raw) <- trimws(as.character(colnames(raw)))
      raw
    }, error = function(e) {
      warning(paste0("Could not read sheet '", sn, "' from '", filename, "': ", e$message))
      NULL
    })
    if (!is.null(df) && nrow(df) > 0) {
      result[[sn]] <- df
    }
  }
  result
}

# ── Demo data generator ───────────────────────────────────────

#' Generate a synthetic WIC KPI workbook for a given month.
#' Returns a temp file path to the .xlsx file.
generate_demo_xlsx <- function(month) {
  set.seed(which(MONTH_ORDER == month))
  base_n <- 100 + which(MONTH_ORDER == month) * 5

  rand <- function(n, lo, hi) round(runif(n, lo, hi))

  summary_df <- data.frame(
    Program              = c("WIC", "Nutrition Counseling", "Breastfeeding Support", "Referrals"),
    Participants         = rand(4, base_n - 10, base_n + 10),
    Certifications       = rand(4, base_n - 25, base_n - 15),
    `Follow-up Visits`   = rand(4, base_n - 35, base_n - 25),
    `New Enrollments`    = rand(4, 10, 40),
    `Retention Rate (%)`  = round(runif(4, 75, 95), 1),
    check.names = FALSE
  )

  outcomes_df <- data.frame(
    Outcome              = c("Healthy Weight", "Breastfeeding 6mo", "Iron Deficiency", "On-Track Development"),
    Count                = rand(4, 50, 150),
    Target               = c(120, 90, 20, 110),
    `% of Target`        = round(runif(4, 70, 110), 1),
    check.names = FALSE
  )

  tmp <- tempfile(fileext = ".xlsx")
  # Write both sheets using openxlsx
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Summary")
  openxlsx::writeData(wb, "Summary", summary_df)
  openxlsx::addWorksheet(wb, "Outcomes")
  openxlsx::writeData(wb, "Outcomes", outcomes_df)
  openxlsx::saveWorkbook(wb, tmp, overwrite = TRUE)
  tmp
}

# ── Monthly summary builder ───────────────────────────────────

#' Given monthly_data (list of lists of data frames), build a
#' long-format summary data frame with one row per (Month, Sheet),
#' summing all numeric columns.
build_monthly_summary <- function(monthly_data) {
  rows <- list()
  for (label in names(monthly_data)) {
    for (sn in names(monthly_data[[label]])) {
      df   <- monthly_data[[label]][[sn]]
      nums <- df |> select(where(is.numeric))
      row  <- data.frame(Month = label, Sheet = sn, Rows = nrow(df),
                         stringsAsFactors = FALSE)
      if (ncol(nums) > 0) {
        sums <- colSums(nums, na.rm = TRUE)
        row  <- cbind(row, as.data.frame(t(sums), stringsAsFactors = FALSE))
      }
      rows <- c(rows, list(row))
    }
  }
  if (length(rows) == 0) return(data.frame())
  bind_rows(rows)
}
