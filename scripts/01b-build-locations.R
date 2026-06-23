# scripts/01b-build-locations.R
suppressMessages({library(dplyr)})
source("R/regions.R"); source("R/locations.R")

# tigris block_groups supports years up to ~ (current-1); clamp if needed.
lodes_year <- as.integer(readLines("data/lodes_year.txt"))
tg_year <- min(lodes_year, 2023L)   # adjust down if tigris lacks the year

locs <- build_locations(region_counties(), tg_year)

# Keep only BGs actually referenced in flows; warn on any missing centroids.
flows <- readRDS("data/flows.rds")
used <- unique(c(flows$origin, flows$dest))
missing <- setdiff(used, locs$id)
if (length(missing) > 0)
  message("WARNING: ", length(missing), " referenced BGs lack centroids (will be dropped in render)")
locs <- locs |> filter(id %in% used)

saveRDS(locs, "data/locations.rds")
message("Locations: ", nrow(locs))
cat("LOCATIONS OK\n")
