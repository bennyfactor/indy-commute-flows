# scripts/02-build-flowmap.R
suppressMessages({library(mapgl); library(dplyr); library(htmlwidgets)})

# onRender JS: (1) alias the live MapLibre map to window.__indyMap for headless
# capture; (2) add a Block group / ZIP code radio that flips the two flowmap
# layers' visibility via the mapgl flowmap plugin (mutually exclusive).
TOGGLE_JS <- "
function(el, x) {
  var setGlobal = function() {
    if (el.map && typeof el.map.flyTo === 'function') { window.__indyMap = el.map; }
  };
  setGlobal();
  if (el.map && el.map.on) { el.map.on('style.load', setGlobal); }

  var IDS = ['indy-bg', 'indy-zcta'];
  var apply = function(chosen) {
    var p = window.MapGLFlowmapPlugin;
    if (!p || !el.map) return false;
    var ok = true;
    IDS.forEach(function(id) {
      var vis = (id === chosen) ? 'visible' : 'none';
      if (!p.setVisibility(el.map, id, vis)) ok = false;
    });
    return ok;
  };

  var ctrl = document.createElement('div');
  ctrl.style.cssText = 'position:absolute;top:10px;right:10px;z-index:1000;' +
    'background:rgba(20,20,20,0.85);color:#eee;padding:8px 10px;border-radius:6px;' +
    'font:13px/1.4 system-ui,sans-serif;';
  ctrl.innerHTML =
    '<div style=\"font-weight:600;margin-bottom:4px;\">Resolution</div>' +
    '<label style=\"display:block;cursor:pointer;\">' +
    '<input type=\"radio\" name=\"indy-res\" value=\"indy-bg\" checked> Block group</label>' +
    '<label style=\"display:block;cursor:pointer;\">' +
    '<input type=\"radio\" name=\"indy-res\" value=\"indy-zcta\"> ZIP code</label>';
  el.appendChild(ctrl);
  ctrl.addEventListener('change', function(e) {
    if (e.target && e.target.name === 'indy-res') { apply(e.target.value); }
  });

  // Apply the default once the flowmap plugin is ready; retry briefly in case
  // onRender fires before MapGLFlowmapPlugin/init is available.
  var tries = 0;
  var ensure = function() {
    if (apply('indy-bg')) return;
    if (tries++ < 40) { setTimeout(ensure, 150); }
  };
  if (el.map && el.map.once) { el.map.once('idle', ensure); }
  ensure();
}"

flows_bg   <- readRDS('data/flows.rds')
locs_bg    <- readRDS('data/locations.rds')
flows_zcta <- readRDS('data/flows_zcta.rds')
locs_zcta  <- readRDS('data/locations_zcta.rds')

# Block-group layer: drop orphan-endpoint flows, cap to the strongest 40k.
valid_bg <- locs_bg$id
flows_bg <- flows_bg |> filter(origin %in% valid_bg, dest %in% valid_bg)
MAX_FLOWS <- 40000
if (nrow(flows_bg) > MAX_FLOWS) {
  flows_bg <- flows_bg |> arrange(desc(count)) |> slice_head(n = MAX_FLOWS)
  message('Capped block-group flows to top ', MAX_FLOWS)
}

# ZCTA layer: sparse already; just enforce the endpoint contract.
valid_zcta <- locs_zcta$id
flows_zcta <- flows_zcta |> filter(origin %in% valid_zcta, dest %in% valid_zcta)

message('BG: ', nrow(flows_bg), ' flows / ', nrow(locs_bg), ' locs | ',
        'ZCTA: ', nrow(flows_zcta), ' flows / ', nrow(locs_zcta), ' locs')

m <- maplibre(style = carto_style('dark-matter'),
              center = c(-86.2, 39.9), zoom = 8, projection = 'mercator') |>
  add_flowmap(
    id = 'indy-bg',
    locations = locs_bg, flows = flows_bg,
    flow_color_scheme = 'Teal', flow_dark_mode = TRUE,
    flow_lines_rendering_mode = 'animated-straight',
    flow_clustering_enabled = TRUE, flow_clustering_auto = TRUE,
    flow_adaptive_scales_enabled = TRUE, flow_location_totals_enabled = TRUE,
    tooltip = TRUE, visibility = 'visible'
  ) |>
  add_flowmap(
    id = 'indy-zcta',
    locations = locs_zcta, flows = flows_zcta,
    flow_color_scheme = 'Teal', flow_dark_mode = TRUE,
    flow_lines_rendering_mode = 'animated-straight',
    flow_clustering_enabled = TRUE, flow_clustering_auto = TRUE,
    flow_adaptive_scales_enabled = TRUE, flow_location_totals_enabled = TRUE,
    tooltip = TRUE, visibility = 'none'
  ) |>
  htmlwidgets::onRender(TOGGLE_JS)

dir.create('output', showWarnings = FALSE)
htmlwidgets::saveWidget(m, 'output/indy-commute-flows.html',
                        selfcontained = TRUE, title = 'Central Indiana Commute Flows')
cat('RENDER OK\n')
