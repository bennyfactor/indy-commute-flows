# R/blocks.R — census-block OD flows (count >= BLOCK_MIN_COUNT) + centroids +
# simplified polygons. Block-level LODES is heavily noise-infused; the threshold
# drops the ~873k count==1 fuzzing pairs and keeps the strongest corridors.
suppressMessages({library(lehdr); library(tigris); library(sf); library(dplyr)})
options(tigris_use_cache = TRUE)

BLOCK_MIN_COUNT <- 3L

# Region block OD pairs (both endpoints in counties), thresholded.
build_block_flows <- function(counties, year) {
  od <- grab_lodes(state = "in", year = year, lodes_type = "od", job_type = "JT00",
                   segment = "S000", state_part = "main", agg_geo = "block",
                   version = "LODES8")
  od |>
    dplyr::mutate(origin = as.character(h_geocode),
                  dest   = as.character(w_geocode),
                  count  = as.numeric(S000)) |>
    dplyr::filter(substr(origin, 1, 5) %in% counties,
                  substr(dest, 1, 5) %in% counties,
                  origin != dest, count >= BLOCK_MIN_COUNT) |>
    dplyr::select(origin, dest, count)
}

# All 2020 census blocks for the region's counties (sf, id column = GEOID20).
load_blocks <- function(counties, year) {
  county_fips <- substr(counties, 3, 5)
  tigris::blocks(state = "18", county = county_fips, year = year, progress_bar = FALSE)
}

build_block_locations <- function(blocks_sf, flows) {
  used <- unique(c(flows$origin, flows$dest))
  b <- blocks_sf[as.character(blocks_sf$GEOID20) %in% used, ]
  b <- sf::st_transform(b, 4326)
  cent <- suppressWarnings(sf::st_point_on_surface(sf::st_geometry(b)))
  xy <- sf::st_coordinates(cent)
  data.frame(id = as.character(b$GEOID20), lon = xy[, 1], lat = xy[, 2],
             stringsAsFactors = FALSE)
}

build_block_polygons <- function(blocks_sf, flows) {
  used <- unique(c(flows$origin, flows$dest))
  b  <- blocks_sf[as.character(blocks_sf$GEOID20) %in% used, ]
  bm <- sf::st_transform(b, 3857)
  g  <- suppressWarnings(sf::st_simplify(sf::st_geometry(bm),
                                         preserveTopology = TRUE, dTolerance = 20))
  empty <- sf::st_is_empty(g)
  if (any(empty)) g[empty] <- sf::st_geometry(bm)[empty]   # keep original for tiny blocks
  out <- sf::st_sf(id = as.character(bm$GEOID20), geometry = g)
  sf::st_transform(out, 4326)
}
