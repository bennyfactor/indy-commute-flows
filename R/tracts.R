# R/tracts.R — census-tract OD flows + centroids + simplified polygons.
# Native lehdr aggregation (agg_geo="tract"), no crosswalk. Mirrors R/locations.R
# + R/polygons.R for the block-group path.
suppressMessages({library(lehdr); library(tigris); library(sf); library(dplyr)})
options(tigris_use_cache = TRUE)

build_tract_flows <- function(counties, year) {
  od <- grab_lodes(state = "in", year = year, lodes_type = "od", job_type = "JT00",
                   segment = "S000", state_part = "main", agg_geo = "tract",
                   version = "LODES8")
  od |>
    dplyr::mutate(origin = as.character(h_tract),
                  dest   = as.character(w_tract),
                  count  = as.numeric(S000)) |>
    dplyr::filter(substr(origin, 1, 5) %in% counties,
                  substr(dest, 1, 5) %in% counties,
                  origin != dest, count > 0) |>
    dplyr::select(origin, dest, count)
}

load_tracts <- function(counties, year) {
  county_fips <- substr(counties, 3, 5)
  tigris::tracts(state = "18", county = county_fips, year = year,
                 cb = TRUE, progress_bar = FALSE)
}

build_tract_locations <- function(tracts_sf, flows) {
  used <- unique(c(flows$origin, flows$dest))
  t <- tracts_sf[as.character(tracts_sf$GEOID) %in% used, ]
  t <- sf::st_transform(t, 4326)
  cent <- suppressWarnings(sf::st_point_on_surface(sf::st_geometry(t)))
  xy <- sf::st_coordinates(cent)
  data.frame(id = as.character(t$GEOID), lon = xy[, 1], lat = xy[, 2],
             stringsAsFactors = FALSE)
}

build_tract_polygons <- function(tracts_sf, flows) {
  used <- unique(c(flows$origin, flows$dest))
  t <- tracts_sf[as.character(tracts_sf$GEOID) %in% used, ]
  t <- sf::st_transform(t, 4326)
  t <- sf::st_simplify(t, preserveTopology = TRUE, dTolerance = 0.0004)
  data.frame(id = as.character(t$GEOID)) |> sf::st_set_geometry(sf::st_geometry(t))
}
