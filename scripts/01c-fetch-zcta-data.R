# scripts/01c-fetch-zcta-data.R — build ZCTA OD flows + centroids for the region.
suppressMessages({library(dplyr)})
source("R/regions.R"); source("R/zcta.R")

dir.create("data", showWarnings = FALSE)
stopifnot("data/lodes_year.txt missing - run scripts/01-fetch-data.R first" =
          file.exists("data/lodes_year.txt"))
year <- as.integer(readLines("data/lodes_year.txt"))
message("Building ZCTA flows for LODES year ", year)

flows_zcta <- build_zcta_flows(region_counties(), year)
message("ZCTA OD pairs: ", nrow(flows_zcta),
        " | commuters: ", format(sum(flows_zcta$count), big.mark = ","))
saveRDS(flows_zcta, "data/flows_zcta.rds")

locs_zcta <- build_zcta_locations(flows_zcta)
used <- unique(c(flows_zcta$origin, flows_zcta$dest))
missing <- setdiff(used, locs_zcta$id)
if (length(missing) > 0)
  message("WARNING: ", length(missing), " ZCTAs in flows lack centroids (dropped in render)")
saveRDS(locs_zcta, "data/locations_zcta.rds")
message("ZCTA locations: ", nrow(locs_zcta))
cat("ZCTA DATA OK\n")
