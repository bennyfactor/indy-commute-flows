# scripts/02-build-flowmap.R
suppressMessages({library(mapgl); library(dplyr); library(htmlwidgets)})

# JS injected via onRender to expose the MapLibre map at window.__indyMap.
# mapgl htmlwidget already stores the map on el.map; this just aliases it to
# a stable global for headless capture (03-capture-video.mjs).
EXPOSE_MAP_JS <- "
function(el, x) {
  // el.map is set synchronously by the mapgl renderValue; alias to global.
  // Also hook style.load in case the widget fires onRender before the map
  // is fully ready, so we always get the live instance.
  var setGlobal = function() {
    if (el.map && typeof el.map.flyTo === 'function') {
      window.__indyMap = el.map;
    }
  };
  setGlobal();
  if (el.map && el.map.on) {
    el.map.on('style.load', setGlobal);
  }
}"

flows <- readRDS("data/flows.rds")
locs  <- readRDS("data/locations.rds")

# Drop any flow whose endpoints lack a centroid (data contract: every id present).
valid <- locs$id
flows <- flows |> filter(origin %in% valid, dest %in% valid)

# Keep the widget light: cap to the strongest flows; clustering handles the rest.
MAX_FLOWS <- 40000
if (nrow(flows) > MAX_FLOWS) {
  flows <- flows |> arrange(desc(count)) |> slice_head(n = MAX_FLOWS)
  message("Capped to top ", MAX_FLOWS, " flows by count")
}
message("Rendering ", nrow(flows), " flows over ", nrow(locs), " locations")

m <- maplibre(style = carto_style("dark-matter"),
              center = c(-86.2, 39.9), zoom = 8, projection = "mercator") |>
  add_flowmap(
    id = "indy",
    locations = locs, flows = flows,
    flow_color_scheme = "Teal",
    flow_dark_mode = TRUE,
    flow_lines_rendering_mode = "animated-straight",
    flow_clustering_enabled = TRUE,
    flow_clustering_auto = TRUE,
    flow_adaptive_scales_enabled = TRUE,
    flow_location_totals_enabled = TRUE,
    tooltip = TRUE
  ) |>
  htmlwidgets::onRender(EXPOSE_MAP_JS)

dir.create("output", showWarnings = FALSE)
htmlwidgets::saveWidget(m, "output/indy-commute-flows.html",
                        selfcontained = TRUE, title = "Central Indiana Commute Flows")
cat("RENDER OK\n")
