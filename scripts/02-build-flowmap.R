# scripts/02-build-flowmap.R
suppressMessages({library(mapgl); library(dplyr); library(sf); library(htmlwidgets)})
source('R/interaction_js.R')   # defines INTERACTION_JS

flows_bg   <- readRDS('data/flows.rds')
locs_bg    <- readRDS('data/locations.rds')
flows_zcta <- readRDS('data/flows_zcta.rds')
locs_zcta  <- readRDS('data/locations_zcta.rds')
polys_bg   <- readRDS('data/polys_bg.rds')
polys_zcta <- readRDS('data/polys_zcta.rds')

# Block-group layer: drop orphan-endpoint flows, cap to the strongest 40k.
valid_bg <- locs_bg$id
flows_bg <- flows_bg |> filter(origin %in% valid_bg, dest %in% valid_bg)
MAX_FLOWS <- 40000
if (nrow(flows_bg) > MAX_FLOWS) {
  flows_bg <- flows_bg |> arrange(desc(count)) |> slice_head(n = MAX_FLOWS)
  message('Capped block-group flows to top ', MAX_FLOWS)
}
valid_zcta <- locs_zcta$id
flows_zcta <- flows_zcta |> filter(origin %in% valid_zcta, dest %in% valid_zcta)

# Compact payload for the interaction JS: ids + lon/lat + flows as 0-based
# index triples (o,d,c). Uses the SAME (capped) flows shown by the flowmap.
make_payload <- function(flows, locs) {
  ids <- as.character(locs$id)
  pos <- setNames(seq_along(ids) - 1L, ids)
  f <- flows[flows$origin %in% ids & flows$dest %in% ids &
             as.character(flows$origin) != as.character(flows$dest), ]
  list(ids = ids,
       lon = round(as.numeric(locs$lon), 6),
       lat = round(as.numeric(locs$lat), 6),
       o = unname(pos[as.character(f$origin)]),
       d = unname(pos[as.character(f$dest)]),
       c = as.numeric(f$count))
}
payload <- list(bg = make_payload(flows_bg, locs_bg),
                zcta = make_payload(flows_zcta, locs_zcta))

# Transparent hit-target points (carry id) for picking.
hits_bg   <- sf::st_as_sf(locs_bg,   coords = c('lon','lat'), crs = 4326)
hits_zcta <- sf::st_as_sf(locs_zcta, coords = c('lon','lat'), crs = 4326)

message('BG: ', nrow(flows_bg), ' flows / ', nrow(locs_bg), ' locs | ',
        'ZCTA: ', nrow(flows_zcta), ' flows / ', nrow(locs_zcta), ' locs')

empty_filter <- list('==', list('get','id'), '')

m <- maplibre(style = carto_style('dark-matter'),
              center = c(-86.2, 39.9), zoom = 8, projection = 'mercator') |>
  add_flowmap(
    id = 'indy-bg', locations = locs_bg, flows = flows_bg,
    flow_color_scheme = 'Teal', flow_dark_mode = TRUE,
    flow_lines_rendering_mode = 'animated-straight',
    flow_clustering_enabled = TRUE, flow_clustering_auto = TRUE,
    flow_adaptive_scales_enabled = TRUE, flow_location_totals_enabled = TRUE,
    tooltip = TRUE, visibility = 'visible'
  ) |>
  add_flowmap(
    id = 'indy-zcta', locations = locs_zcta, flows = flows_zcta,
    flow_color_scheme = 'Teal', flow_dark_mode = TRUE,
    flow_lines_rendering_mode = 'animated-straight',
    flow_clustering_enabled = TRUE, flow_clustering_auto = TRUE,
    flow_adaptive_scales_enabled = TRUE, flow_location_totals_enabled = TRUE,
    tooltip = TRUE, visibility = 'none'
  ) |>
  add_source(id = 'poly-bg',   data = polys_bg) |>
  add_source(id = 'poly-zcta', data = polys_zcta) |>
  add_line_layer(id = 'outline-bg',   source = 'poly-bg',
                 line_color = '#FFFFFF', line_width = 2, filter = empty_filter) |>
  add_line_layer(id = 'outline-zcta', source = 'poly-zcta',
                 line_color = '#FFFFFF', line_width = 2, filter = empty_filter) |>
  add_circle_layer(id = 'hits-bg',   source = hits_bg,
                   circle_color = '#ffffff', circle_opacity = 0, circle_radius = 10) |>
  add_circle_layer(id = 'hits-zcta', source = hits_zcta,
                   circle_color = '#ffffff', circle_opacity = 0, circle_radius = 12) |>
  htmlwidgets::onRender(INTERACTION_JS, data = payload)

dir.create('output', showWarnings = FALSE)
htmlwidgets::saveWidget(m, 'output/indy-commute-flows.html',
                        selfcontained = TRUE, title = 'Central Indiana Commute Flows')
cat('RENDER OK\n')
