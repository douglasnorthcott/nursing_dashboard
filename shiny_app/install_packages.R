# install_packages.R
# ─────────────────────────────────────────────────────────────
# Run this script once to install all required R packages.
# Usage:  Rscript install_packages.R
# ─────────────────────────────────────────────────────────────

pkgs <- c(
  "shiny",
  "shinydashboard",
  "readxl",
  "openxlsx",
  "dplyr",
  "tidyr",
  "plotly",
  "DT",
  "scales"
)

missing_pkgs <- pkgs[!pkgs %in% rownames(installed.packages())]

if (length(missing_pkgs) > 0) {
  message("Installing: ", paste(missing_pkgs, collapse = ", "))
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
} else {
  message("All packages already installed.")
}

message("Done.")
