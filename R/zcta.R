# R/zcta.R — build ZCTA-level OD flows and ZCTA centroid locations.
# LODES has no native ZIP geography; "ZIP" == ZCTA reached via the LODES
# block->ZCTA crosswalk. See docs/superpowers/specs/2026-06-23-zcta-toggle-design.md.
suppressMessages({library(lehdr); library(tigris); library(sf); library(dplyr)})
options(tigris_use_cache = TRUE)

# Aggregate block-level OD to ZCTA pairs whose blocks fall in the region counties.
# counties = 5-digit FIPS vector (region_counties()); year = LODES year.
build_zcta_flows <- function(counties, year) {
  od <- grab_lodes(state = "in", year = year, lodes_type = "od",
                   job_type = "JT00", segment = "S000",
                   state_part = "main", agg_geo = "block", version = "LODES8")
  xwalk <- grab_crosswalk("in") |>
    dplyr::transmute(tabblk2020 = as.character(tabblk2020),
                     zcta = as.character(zcta),
                     cty  = as.character(cty))
  region_zctas <- xwalk |>
    dplyr::filter(cty %in% counties, zcta != "99999") |>
    dplyr::pull(zcta) |>
    unique()
  blk2zcta <- xwalk |> dplyr::select(tabblk2020, zcta)
  od |>
    dplyr::mutate(h_geocode = as.character(h_geocode),
                  w_geocode = as.character(w_geocode)) |>
    dplyr::left_join(blk2zcta, by = c("h_geocode" = "tabblk2020")) |>
    dplyr::rename(h_zcta = zcta) |>
    dplyr::left_join(blk2zcta, by = c("w_geocode" = "tabblk2020")) |>
    dplyr::rename(w_zcta = zcta) |>
    dplyr::filter(!is.na(h_zcta), !is.na(w_zcta),
                  h_zcta %in% region_zctas, w_zcta %in% region_zctas) |>
    dplyr::group_by(h_zcta, w_zcta) |>
    dplyr::summarise(count = sum(as.numeric(S000), na.rm = TRUE), .groups = "drop") |>
    dplyr::filter(count > 0) |>
    dplyr::transmute(origin = h_zcta, dest = w_zcta, count = count)
}

# ZCTA centroids (lon/lat, EPSG:4326) for the ZCTAs present in `flows`.
build_zcta_locations <- function(flows) {
  # tigris can't filter ZCTAs by state for this vintage, so narrow the national
  # download by Indiana ZIP prefixes (46xxx/47xxx). If a region ZCTA ever fell
  # outside these prefixes its centroid would be missing — the caller's
  # missing-centroid warning is the safety net.
  z <- tigris::zctas(cb = TRUE, year = 2020, starts_with = c("46", "47"),
                     progress_bar = FALSE)
  z <- sf::st_transform(z, 4326)
  used <- unique(c(flows$origin, flows$dest))
  z <- z[z$ZCTA5CE20 %in% used, ]
  cent <- suppressWarnings(sf::st_point_on_surface(sf::st_geometry(z)))
  xy <- sf::st_coordinates(cent)
  data.frame(id = as.character(z$ZCTA5CE20),
             lon = xy[, 1], lat = xy[, 2], stringsAsFactors = FALSE)
}
