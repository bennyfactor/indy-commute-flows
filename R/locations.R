# R/locations.R
suppressMessages({library(tigris); library(sf); library(dplyr)})
options(tigris_use_cache = TRUE)

# Block-group centroids (lon/lat, EPSG:4326) for the region's counties.
build_locations <- function(counties, year) {
  county_fips <- substr(counties, 3, 5)        # "18097" -> "097"
  bg <- tigris::block_groups(state = "18", county = county_fips,
                             year = year, cb = TRUE, progress_bar = FALSE)
  bg <- sf::st_transform(bg, 4326)
  cent <- suppressWarnings(sf::st_point_on_surface(sf::st_geometry(bg)))
  xy <- sf::st_coordinates(cent)
  data.frame(id = as.character(bg$GEOID),
             lon = xy[, 1], lat = xy[, 2],
             stringsAsFactors = FALSE)
}
