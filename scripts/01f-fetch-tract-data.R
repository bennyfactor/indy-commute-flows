# scripts/01f-fetch-tract-data.R — census-tract flows + centroids + polygons.
suppressMessages({library(sf); library(dplyr)})
source("R/regions.R"); source("R/tracts.R")

dir.create("data", showWarnings = FALSE)
stopifnot("data/lodes_year.txt missing - run scripts/01-fetch-data.R first" =
          file.exists("data/lodes_year.txt"))
year <- as.integer(readLines("data/lodes_year.txt"))
tg_year <- min(year, 2023L)

flows <- build_tract_flows(region_counties(), year)
message("Tract OD pairs: ", nrow(flows),
        " | commuters: ", format(sum(flows$count), big.mark = ","))
saveRDS(flows, "data/flows_tract.rds")

tracts_sf <- load_tracts(region_counties(), tg_year)
locs  <- build_tract_locations(tracts_sf, flows)
polys <- build_tract_polygons(tracts_sf, flows)

used <- unique(c(flows$origin, flows$dest))
stopifnot("every flow tract has a centroid" = length(setdiff(used, locs$id)) == 0)
stopifnot("every flow tract has a polygon"  = length(setdiff(used, polys$id)) == 0)
saveRDS(locs,  "data/locations_tract.rds")
saveRDS(polys, "data/polys_tract.rds")
message("Tract locations: ", nrow(locs), " | polygons: ", nrow(polys))
cat("TRACT DATA OK\n")
