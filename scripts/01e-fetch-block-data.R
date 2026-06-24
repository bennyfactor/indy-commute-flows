# scripts/01e-fetch-block-data.R — census-block flows + centroids + polygons.
suppressMessages({library(sf); library(dplyr)})
source("R/regions.R"); source("R/blocks.R")

dir.create("data", showWarnings = FALSE)
stopifnot("data/lodes_year.txt missing - run scripts/01-fetch-data.R first" =
          file.exists("data/lodes_year.txt"))
year <- as.integer(readLines("data/lodes_year.txt"))

flows <- build_block_flows(region_counties(), year)
message("Block OD pairs (count>=", BLOCK_MIN_COUNT, "): ", nrow(flows),
        " | commuters: ", format(sum(flows$count), big.mark = ","))
saveRDS(flows, "data/flows_block.rds")

blocks_sf <- load_blocks(region_counties(), 2020L)
locs  <- build_block_locations(blocks_sf, flows)
polys <- build_block_polygons(blocks_sf, flows)

used <- unique(c(flows$origin, flows$dest))
stopifnot("every flow block has a centroid" = length(setdiff(used, locs$id)) == 0)
stopifnot("every flow block has a polygon"  = length(setdiff(used, polys$id)) == 0)
saveRDS(locs,  "data/locations_block.rds")
saveRDS(polys, "data/polys_block.rds")
message("Block locations: ", nrow(locs), " | polygons: ", nrow(polys))
cat("BLOCK DATA OK\n")
