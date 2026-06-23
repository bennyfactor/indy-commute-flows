# R/polygons.R — simplified boundary polygons (id + geometry, EPSG:4326) for
# block groups and ZCTAs, for the hover/click outline. Independent per-polygon
# simplification is fine; only one polygon is outlined at a time.
suppressMessages({library(tigris); library(sf); library(dplyr)})
options(tigris_use_cache = TRUE)

simplify_keep <- function(x) {
  x <- sf::st_transform(x, 4326)
  sf::st_simplify(x, preserveTopology = TRUE, dTolerance = 0.0004)
}

build_bg_polygons <- function(counties, year) {
  county_fips <- substr(counties, 3, 5)
  bg <- tigris::block_groups(state = "18", county = county_fips,
                             year = year, cb = TRUE, progress_bar = FALSE)
  bg <- simplify_keep(bg)
  data.frame(id = as.character(bg$GEOID)) |>
    sf::st_set_geometry(sf::st_geometry(bg))
}

build_zcta_polygons <- function() {
  z <- tigris::zctas(cb = TRUE, year = 2020, starts_with = c("46", "47"),
                     progress_bar = FALSE)
  z <- simplify_keep(z)
  data.frame(id = as.character(z$ZCTA5CE20)) |>
    sf::st_set_geometry(sf::st_geometry(z))
}
