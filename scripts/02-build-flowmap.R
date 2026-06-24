# scripts/02-build-flowmap.R
suppressMessages({library(mapgl); library(dplyr); library(sf); library(htmlwidgets)})
source('R/interaction_js.R')   # defines INTERACTION_JS

flows_bg    <- readRDS('data/flows.rds')
locs_bg     <- readRDS('data/locations.rds')
flows_zcta  <- readRDS('data/flows_zcta.rds')
locs_zcta   <- readRDS('data/locations_zcta.rds')
flows_tract <- readRDS('data/flows_tract.rds')
locs_tract  <- readRDS('data/locations_tract.rds')
flows_block <- readRDS('data/flows_block.rds')
locs_block  <- readRDS('data/locations_block.rds')
polys_bg    <- readRDS('data/polys_bg.rds')
polys_zcta  <- readRDS('data/polys_zcta.rds')
polys_tract <- readRDS('data/polys_tract.rds')
polys_block <- readRDS('data/polys_block.rds')

MAX_FLOWS <- 40000
cap_flows <- function(flows, valid, label) {
  flows <- flows |> filter(origin %in% valid, dest %in% valid)
  if (nrow(flows) > MAX_FLOWS) {
    flows <- flows |> arrange(desc(count)) |> slice_head(n = MAX_FLOWS)
    message('Capped ', label, ' flows to top ', MAX_FLOWS)
  }
  flows
}
flows_bg    <- cap_flows(flows_bg,    locs_bg$id,    'block-group')
flows_zcta  <- cap_flows(flows_zcta,  locs_zcta$id,  'zcta')
flows_tract <- cap_flows(flows_tract, locs_tract$id, 'tract')
flows_block <- cap_flows(flows_block, locs_block$id, 'block')

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
payload <- list(bg    = make_payload(flows_bg,    locs_bg),
                zcta  = make_payload(flows_zcta,  locs_zcta),
                tract = make_payload(flows_tract, locs_tract),
                block = make_payload(flows_block, locs_block))

hits_bg    <- sf::st_as_sf(locs_bg,    coords = c('lon','lat'), crs = 4326)
hits_zcta  <- sf::st_as_sf(locs_zcta,  coords = c('lon','lat'), crs = 4326)
hits_tract <- sf::st_as_sf(locs_tract, coords = c('lon','lat'), crs = 4326)
hits_block <- sf::st_as_sf(locs_block, coords = c('lon','lat'), crs = 4326)

message('BG: ', nrow(flows_bg), '/', nrow(locs_bg),
        ' | ZCTA: ', nrow(flows_zcta), '/', nrow(locs_zcta),
        ' | TRACT: ', nrow(flows_tract), '/', nrow(locs_tract),
        ' | BLOCK: ', nrow(flows_block), '/', nrow(locs_block))

empty_filter <- list('==', list('get','id'), '')
fm <- function(map, id, locs, flows, vis) {
  add_flowmap(map, id = id, locations = locs, flows = flows,
              flow_color_scheme = 'Teal', flow_dark_mode = TRUE,
              flow_lines_rendering_mode = 'animated-straight',
              flow_clustering_enabled = TRUE, flow_clustering_auto = TRUE,
              flow_adaptive_scales_enabled = TRUE, flow_location_totals_enabled = TRUE,
              tooltip = TRUE, visibility = vis)
}

m <- maplibre(style = carto_style('dark-matter'),
              center = c(-86.2, 39.9), zoom = 8, projection = 'mercator') |>
  fm('indy-bg',    locs_bg,    flows_bg,    'visible') |>
  fm('indy-zcta',  locs_zcta,  flows_zcta,  'none') |>
  fm('indy-tract', locs_tract, flows_tract, 'none') |>
  fm('indy-block', locs_block, flows_block, 'none') |>
  add_source(id = 'poly-bg',    data = polys_bg) |>
  add_source(id = 'poly-zcta',  data = polys_zcta) |>
  add_source(id = 'poly-tract', data = polys_tract) |>
  add_source(id = 'poly-block', data = polys_block) |>
  add_line_layer(id = 'outline-bg',    source = 'poly-bg',
                 line_color = '#FFFFFF', line_width = 2, filter = empty_filter) |>
  add_line_layer(id = 'outline-zcta',  source = 'poly-zcta',
                 line_color = '#FFFFFF', line_width = 2, filter = empty_filter) |>
  add_line_layer(id = 'outline-tract', source = 'poly-tract',
                 line_color = '#FFFFFF', line_width = 2, filter = empty_filter) |>
  add_line_layer(id = 'outline-block', source = 'poly-block',
                 line_color = '#FFFFFF', line_width = 2, filter = empty_filter) |>
  add_circle_layer(id = 'hits-bg',    source = hits_bg,
                   circle_color = '#ffffff', circle_opacity = 0, circle_radius = 10) |>
  add_circle_layer(id = 'hits-zcta',  source = hits_zcta,
                   circle_color = '#ffffff', circle_opacity = 0, circle_radius = 12) |>
  add_circle_layer(id = 'hits-tract', source = hits_tract,
                   circle_color = '#ffffff', circle_opacity = 0, circle_radius = 12) |>
  add_circle_layer(id = 'hits-block', source = hits_block,
                   circle_color = '#ffffff', circle_opacity = 0, circle_radius = 8) |>
  htmlwidgets::onRender(INTERACTION_JS, data = payload)

dir.create('output', showWarnings = FALSE)
htmlwidgets::saveWidget(m, 'output/indy-commute-flows.html',
                        selfcontained = TRUE, title = 'Central Indiana Commute Flows')
mb <- round(file.size('output/indy-commute-flows.html') / 1e6, 1)
cat('HTML size:', mb, 'MB\n')
cat('RENDER OK\n')
