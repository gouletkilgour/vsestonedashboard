# Fetches wealth-share data for Canada from the World Inequality Database
# (WID.world) using the project's official R client, and writes the result
# as JSON for consumption by wealth_shares.jl.
#
# Usage: Rscript fetch_wealth_shares.R <output_path.json>

args        <- commandArgs(trailingOnly = TRUE)
output_path <- if (length(args) >= 1) args[1] else "wid_wealth_shares.json"

if (!requireNamespace("wid", quietly = TRUE)) {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes", repos = "https://cloud.r-project.org")
  }
  remotes::install_github("world-inequality-database/wid-r-tool", upgrade = "never", quiet = TRUE)
}

suppressPackageStartupMessages(library(wid))
suppressPackageStartupMessages(library(jsonlite))

START_YEAR <- 1980

# shweal = net personal wealth share; age 992 = adults (20+);
# pop "j" = equal-split adults. See https://wid.world/codes-dictionary/
df <- download_wid(
  indicators = "shweal",
  areas      = "CA",
  perc       = c("p99p100", "p90p100", "p0p50"),
  ages       = "992",
  pop        = "j",
  years      = START_YEAR:as.integer(format(Sys.Date(), "%Y")),
  verbose    = TRUE
)

labels <- c("p99p100" = "Top 1%", "p90p100" = "Top 10%", "p0p50" = "Bottom 50%")
df     <- df[order(df$percentile, df$year), ]

result <- list()
for (code in names(labels)) {
  sub <- df[df$percentile == code & !is.na(df$value), ]
  result[[labels[[code]]]] <- list(
    x = as.list(as.integer(sub$year)),
    y = as.list(round(sub$value * 100, 2))
  )
}

write(toJSON(result, auto_unbox = TRUE, digits = NA), output_path)
cat("Wrote", nrow(df), "rows to", output_path, "\n")
