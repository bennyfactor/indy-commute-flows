# scripts/01d-build-polygons.R — boundary polygons for the hover outline.
suppressMessages({library(sf); library(dplyr)})
source("R/regions.R"); source("R/polygons.R")

dir.create("data", showWarnings = FALSE)
stopifnot("data/lodes_year.txt missing - run scripts/01-fetch-data.R first" =
          file.exists("data/lodes_year.txt"))
lodes_year <- as.integer(readLines("data/lodes_year.txt"))
tg_year <- min(lodes_year, 2023L)

bg <- build_bg_polygons(region_counties(), tg_year)
loc_bg <- readRDS("data/locations.rds")
bg <- bg[bg$id %in% loc_bg$id, ]
saveRDS(bg, "data/polys_bg.rds")
message("BG polygons: ", nrow(bg))

zc <- build_zcta_polygons()
loc_zc <- readRDS("data/locations_zcta.rds")
zc <- zc[zc$id %in% loc_zc$id, ]
saveRDS(zc, "data/polys_zcta.rds")
message("ZCTA polygons: ", nrow(zc))
cat("POLYGONS OK\n")
