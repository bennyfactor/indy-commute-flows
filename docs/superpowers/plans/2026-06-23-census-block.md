# Census Block Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third "Census block" resolution (LODES block-level OD, count ≥ 3) to the existing toggle, with the full hover/pin/outline/two-color/label interaction.

**Architecture:** A new R data path builds thresholded block flows + block centroids + simplified block polygons. The render script adds a third `add_flowmap` layer plus its hit/outline/highlight layers and a `block` payload entry. The interaction JS is generalized from the hardcoded two resolutions to iterate all `RES` keys, and the radio gains a "Census block" option. A build-time size guard raises the threshold if the page is unreasonably large.

**Tech Stack:** R (mapgl 0.5.0, lehdr `grab_lodes(agg_geo="block")`, tigris `blocks()`, sf, dplyr) in `indy-flows:latest`; Node + Playwright (host) for headless verification.

## Global Constraints

- Branch `census-block`. Additive: do NOT change the bg/zcta fetch/polygon scripts, `R/regions.R`, or capture/deploy scripts. Modify only `scripts/02-build-flowmap.R`, `R/interaction_js.R`, `README.md`, and add `R/blocks.R` + `scripts/01e-fetch-block-data.R`.
- Run R in the container: `./run.sh <script.R>`; `run.sh` has no `-i` — temp checks go in `scripts/_*.R`/`.mjs`, deleted, never committed.
- Block threshold: `BLOCK_MIN_COUNT <- 3L`. Region = same 15 counties (county = first 5 chars of the 15-digit block id, in `region_counties()`); both endpoints in region; drop self-loops.
- Block id = 15-digit `GEOID20` (tigris `blocks(year=2020)`, matching LODES8 2020 blocks).
- Resolution keys: `bg` / `zcta` / `block`. New layer/source ids: `indy-block` (flowmap), `hits-block`, `poly-block`, `outline-block`, `inbound-block`, `outbound-block`. Radio value `block`, label "Census block".
- Colors unchanged: inbound `#FF4D6D`, outbound `#FFD166`, outline `#FFFFFF`, halo `#101014`, font `["Open Sans Bold"]`. ZIP-prefix in labels stays gated on `active === 'zcta'` (block labels = count only).
- Data contracts: `flows_block`=`origin,dest,count`; `locations_block`=`id,lon,lat`; `polys_block` sf = `id`+geometry (EPSG:4326). Every flow block id must have a centroid and a polygon.
- Size guard: build prints the HTML size; if > ~40 MB, raise `BLOCK_MIN_COUNT` to 5 and rebuild (report it).
- Preserve `window.__indyMap`; block group stays the default visible resolution. mapgl ≥ 0.5.0. Commit after each task.

---

### Task 1: Census-block data path

**Files:**
- Create: `R/blocks.R`
- Create: `scripts/01e-fetch-block-data.R`

**Interfaces:**
- Consumes: `region_counties()` (`R/regions.R`); `data/lodes_year.txt`.
- Produces: `data/flows_block.rds` (`origin,dest,count`), `data/locations_block.rds` (`id,lon,lat`), `data/polys_block.rds` (sf `id`+geometry). Constant `BLOCK_MIN_COUNT <- 3L`; helpers `build_block_flows(counties, year)`, `load_blocks(counties, year)`, `build_block_locations(blocks_sf, flows)`, `build_block_polygons(blocks_sf, flows)`.

- [ ] **Step 1: Write `R/blocks.R`**

```r
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
  b <- blocks_sf[as.character(blocks_sf$GEOID20) %in% used, ]
  b <- sf::st_transform(b, 4326)
  b <- sf::st_simplify(b, preserveTopology = TRUE, dTolerance = 0.0004)
  data.frame(id = as.character(b$GEOID20)) |> sf::st_set_geometry(sf::st_geometry(b))
}
```

- [ ] **Step 2: Write `scripts/01e-fetch-block-data.R`**

```r
# scripts/01e-fetch-block-data.R — census-block flows + centroids + polygons.
suppressMessages({library(sf); library(dplyr)})
source("R/regions.R"); source("R/blocks.R")

dir.create("data", showWarnings = FALSE)
stopifnot("data/lodes_year.txt missing - run scripts/01-fetch-data.R first" =
          file.exists("data/lodes_year.txt"))
year <- as.integer(readLines("data/lodes_year.txt"))

flows <- build_block_flows(region_counties(), year)
message("Block OD pairs (count>=", BLOCK_MIN_COUNT, "): ", nrow(flows),
        " | commuters: ", format(sum(flows$count), big.mark = ","))
saveRDS(flows, "data/flows_block.rds")

blocks_sf <- load_blocks(region_counties(), 2020L)
locs  <- build_block_locations(blocks_sf, flows)
polys <- build_block_polygons(blocks_sf, flows)

used <- unique(c(flows$origin, flows$dest))
stopifnot("every flow block has a centroid" = length(setdiff(used, locs$id)) == 0)
stopifnot("every flow block has a polygon"  = length(setdiff(used, polys$id)) == 0)
saveRDS(locs,  "data/locations_block.rds")
saveRDS(polys, "data/polys_block.rds")
message("Block locations: ", nrow(locs), " | polygons: ", nrow(polys))
cat("BLOCK DATA OK\n")
```

- [ ] **Step 3: Run it**

Run: `./run.sh scripts/01e-fetch-block-data.R`
Expected: prints "Block OD pairs (count>=3): 19822" (±), a locations/polygons count (~7,992), and `BLOCK DATA OK`. (`tigris::blocks()` downloads all ~49k region blocks once — cached — so the first run is slower.)
If `tigris::blocks(year=2020)` errors, inspect `args(tigris::blocks)` and adapt the year arg (2020 blocks are required to match the 15-digit `GEOID20` block ids); report any change.

- [ ] **Step 4: Sanity-check (temp script, not committed)**

Write `scripts/_check.R`:

```r
suppressMessages(library(sf))
f <- readRDS("data/flows_block.rds"); l <- readRDS("data/locations_block.rds")
p <- readRDS("data/polys_block.rds")
stopifnot(all(c("origin","dest","count") %in% names(f)), all(f$count >= 3))
stopifnot(all(c("id","lon","lat") %in% names(l)))
stopifnot(all(nchar(f$origin) == 15), all(nchar(l$id) == 15), all(nchar(p$id) == 15))
stopifnot(sf::st_crs(p)$epsg == 4326)
stopifnot(all(l$lon > -88 & l$lon < -85), all(l$lat > 38.5 & l$lat < 41))
miss <- setdiff(unique(c(f$origin, f$dest)), l$id)
stopifnot("every flow block has a centroid" = length(miss) == 0)
cat("pairs:", nrow(f), "blocks:", nrow(l), "\nBLOCK CHECK OK\n")
```

Run: `./run.sh scripts/_check.R` → expect `BLOCK CHECK OK`. Then `rm scripts/_check.R`.

- [ ] **Step 5: Commit**

```bash
git add R/blocks.R scripts/01e-fetch-block-data.R
git commit -m "Add census-block OD data path (count>=3) + centroids + polygons"
```

---

### Task 2: Render + interaction (third resolution)

**Files:**
- Modify: `R/interaction_js.R` (full rewrite below — generalize 2→N resolutions, add `block`)
- Modify: `scripts/02-build-flowmap.R` (full rewrite below — third flowmap + native layers + payload + size print)

**Interfaces:**
- Consumes: all bg/zcta/block `flows_*`/`locations_*`/`polys_*` rds.
- Produces: `output/indy-commute-flows.html` with three toggle options and the full interaction on each.

- [ ] **Step 1: Replace `R/interaction_js.R` with this exact content**

```r
# R/interaction_js.R — onRender JS for the node hover/click interaction.
# Receives (el, x, data); data = { bg:{ids,lon,lat,o,d,c}, zcta:{...}, block:{...} }
# where o/d are 0-based indices into ids and c is the commuter count. Builds
# inbound (#FF4D6D) and outbound (#FFD166) line layers + a white polygon outline,
# dims the Flowmap.gl deck canvas on focus, supports hover-preview + click-to-pin,
# shows an always-on color legend, and labels the pinned node's top 3 inbound /
# top 3 outbound partners. Generalized over all resolutions in RES.
INTERACTION_JS <- "
function(el, x, data) {
  var map = el.map;
  if (!map) return;
  window.__indyMap = map;

  var RES = {
    bg:    { flow:'indy-bg',    hits:'hits-bg',    outline:'outline-bg',    inbound:'inbound-bg',    outbound:'outbound-bg' },
    zcta:  { flow:'indy-zcta',  hits:'hits-zcta',  outline:'outline-zcta',  inbound:'inbound-zcta',  outbound:'outbound-zcta' },
    block: { flow:'indy-block', hits:'hits-block', outline:'outline-block', inbound:'inbound-block', outbound:'outbound-block' }
  };
  var KEYS = Object.keys(RES);
  var active = 'bg', pinnedId = null, lastSel = null, idx = {};

  function buildIndex(d) {
    var pos = {}, adj = {};
    for (var i = 0; i < d.ids.length; i++) pos[String(d.ids[i])] = i;
    for (var k = 0; k < d.o.length; k++) {
      var o = d.o[k], dd = d.d[k], c = d.c[k];
      if (o === dd) continue;
      (adj[o] = adj[o] || {inb:[], out:[]}).out.push([dd, c]);
      (adj[dd] = adj[dd] || {inb:[], out:[]}).inb.push([o, c]);
    }
    return { ids:d.ids, lon:d.lon, lat:d.lat, pos:pos, adj:adj };
  }
  function fc(features) { return { type:'FeatureCollection', features:features }; }
  function lines(res, id, dir) {
    var ix = idx[res]; if (!ix) return fc([]);
    var p = ix.pos[String(id)]; if (p === undefined) return fc([]);
    var here = [ix.lon[p], ix.lat[p]];
    var list = (ix.adj[p] || {})[dir] || [], out = [];
    for (var i = 0; i < list.length; i++) {
      var q = list[i][0], there = [ix.lon[q], ix.lat[q]];
      var a = (dir === 'inb') ? there : here;
      var b = (dir === 'inb') ? here  : there;
      out.push({ type:'Feature', properties:{ count:list[i][1] },
                 geometry:{ type:'LineString', coordinates:[a, b] } });
    }
    return fc(out);
  }

  function deckCanvas() {
    var cs = map.getContainer().querySelectorAll('canvas');
    for (var i = 0; i < cs.length; i++)
      if (!cs[i].classList.contains('maplibregl-canvas')) return cs[i];
    return (map._deckgl && map._deckgl.canvas) || null;
  }
  function dim(on) {
    var c = deckCanvas();
    if (c) { c.style.transition = 'opacity 0.15s'; c.style.opacity = on ? '0.18' : '1'; }
  }

  function topN(list, n) {
    return list.slice().sort(function(a, b) { return b[1] - a[1]; }).slice(0, n);
  }
  function fmt(n) { return Math.round(n).toLocaleString('en-US'); }
  function setLabels(id) {
    var ix = idx[active]; if (!ix) return;
    var p = ix.pos[String(id)];
    if (p === undefined) { clearLabels(); return; }
    var a = ix.adj[p] || { inb:[], out:[] }, feats = [];
    var addOne = function(pair, dir) {
      var q = pair[0], pid = String(ix.ids[q]);
      var txt = (active === 'zcta') ? (pid + ' · ' + fmt(pair[1])) : fmt(pair[1]);
      feats.push({ type:'Feature', properties:{ label:txt, dir:dir },
                   geometry:{ type:'Point', coordinates:[ix.lon[q], ix.lat[q]] } });
    };
    topN(a.inb, 3).forEach(function(pr) { addOne(pr, 'in'); });
    topN(a.out, 3).forEach(function(pr) { addOne(pr, 'out'); });
    if (map.getSource('partner-labels')) map.getSource('partner-labels').setData(fc(feats));
  }
  function clearLabels() {
    if (map.getSource('partner-labels')) map.getSource('partner-labels').setData(fc([]));
  }

  function select(id) {
    if (id === lastSel) return;
    lastSel = id;
    var r = RES[active];
    if (map.getSource(r.inbound))  map.getSource(r.inbound).setData(lines(active, id, 'inb'));
    if (map.getSource(r.outbound)) map.getSource(r.outbound).setData(lines(active, id, 'out'));
    if (map.getLayer(r.outline))   map.setFilter(r.outline, ['==', ['get','id'], String(id)]);
    dim(true);
  }
  function clear() {
    lastSel = null;
    KEYS.forEach(function(res) {
      var r = RES[res];
      if (map.getSource(r.inbound))  map.getSource(r.inbound).setData(fc([]));
      if (map.getSource(r.outbound)) map.getSource(r.outbound).setData(fc([]));
      if (map.getLayer(r.outline))   map.setFilter(r.outline, ['==', ['get','id'], '']);
    });
    clearLabels();
    dim(false);
  }

  function ensureHighlightLayers() {
    KEYS.forEach(function(res) {
      var r = RES[res];
      [[r.inbound, '#FF4D6D'], [r.outbound, '#FFD166']].forEach(function(t) {
        if (!map.getSource(t[0])) map.addSource(t[0], { type:'geojson', data:fc([]) });
        if (!map.getLayer(t[0])) map.addLayer({
          id:t[0], type:'line', source:t[0],
          layout:{ visibility:(res === active ? 'visible':'none'), 'line-cap':'round' },
          paint:{ 'line-color':t[1], 'line-opacity':0.92,
                  'line-width':['interpolate',['linear'],['get','count'], 1,1, 50,4, 500,9] }
        });
      });
    });
    if (!map.getSource('partner-labels')) map.addSource('partner-labels', { type:'geojson', data:fc([]) });
    if (!map.getLayer('partner-labels')) map.addLayer({
      id:'partner-labels', type:'symbol', source:'partner-labels',
      layout:{
        'text-field':['get','label'],
        'text-font':['Open Sans Bold'],
        'text-size':12,
        'text-allow-overlap':true,
        'text-anchor':'center',
        'text-offset':['match',['get','dir'],'in',['literal',[0,-0.9]],['literal',[0,0.9]]]
      },
      paint:{
        'text-color':['match',['get','dir'],'in','#FF4D6D','out','#FFD166','#ffffff'],
        'text-halo-color':'#101014', 'text-halo-width':1.4
      }
    });
  }
  function setNativeVisibility(res) {
    KEYS.forEach(function(rr) {
      var r = RES[rr], vis = (rr === res) ? 'visible' : 'none';
      [r.hits, r.outline, r.inbound, r.outbound].forEach(function(lid) {
        if (map.getLayer(lid)) map.setLayoutProperty(lid, 'visibility', vis);
      });
    });
  }
  function applyFlow(chosen) {
    var p = window.MapGLFlowmapPlugin; if (!p) return false;
    var ok = true;
    KEYS.forEach(function(res) {
      var fid = RES[res].flow;
      if (!p.setVisibility(map, fid, fid === chosen ? 'visible':'none')) ok = false;
    });
    return ok;
  }

  function wire() {
    KEYS.forEach(function(res) {
      var r = RES[res];
      map.on('mousemove', r.hits, function(e) {
        if (res !== active || pinnedId || !e.features || !e.features.length) return;
        map.getCanvas().style.cursor = 'pointer';
        select(e.features[0].properties.id);
      });
      map.on('mouseleave', r.hits, function() {
        if (res !== active || pinnedId) return;
        map.getCanvas().style.cursor = ''; clear();
      });
      map.on('click', r.hits, function(e) {
        if (res !== active || !e.features || !e.features.length) return;
        pinnedId = e.features[0].properties.id;
        select(pinnedId);
        setLabels(pinnedId);   // labels only on pin
      });
    });
    map.on('click', function(e) {
      var hit = map.queryRenderedFeatures(e.point, { layers:[RES[active].hits] });
      if (!hit.length) { pinnedId = null; clear(); }
    });
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') { pinnedId = null; clear(); }
    });
  }

  function buildLegend() {
    var lg = document.createElement('div');
    lg.style.cssText = 'position:absolute;top:10px;left:10px;z-index:1000;' +
      'background:rgba(20,20,20,0.85);color:#eee;padding:8px 10px;border-radius:6px;' +
      'font:12px/1.5 system-ui,sans-serif;';
    var row = function(color, label) {
      return '<div style=\"display:flex;align-items:center;gap:6px;\">' +
        '<span style=\"display:inline-block;width:14px;height:3px;background:' + color +
        ';border-radius:2px;\"></span>' + label + '</div>';
    };
    lg.innerHTML = '<div style=\"font-weight:600;margin-bottom:4px;\">Flows</div>' +
      row('#FF4D6D', 'inbound (to node)') +
      row('#FFD166', 'outbound (from node)') +
      row('#FFFFFF', 'selected boundary');
    el.appendChild(lg);
  }

  function buildRadio() {
    var ctrl = document.createElement('div');
    ctrl.style.cssText = 'position:absolute;top:10px;right:10px;z-index:1000;' +
      'background:rgba(20,20,20,0.85);color:#eee;padding:8px 10px;border-radius:6px;' +
      'font:13px/1.4 system-ui,sans-serif;';
    ctrl.innerHTML =
      '<div style=\"font-weight:600;margin-bottom:4px;\">Resolution</div>' +
      '<label style=\"display:block;cursor:pointer;\"><input type=\"radio\" name=\"indy-res\" value=\"bg\" checked> Block group</label>' +
      '<label style=\"display:block;cursor:pointer;\"><input type=\"radio\" name=\"indy-res\" value=\"zcta\"> ZIP code</label>' +
      '<label style=\"display:block;cursor:pointer;\"><input type=\"radio\" name=\"indy-res\" value=\"block\"> Census block</label>' +
      '<div style=\"margin-top:6px;font-size:11px;color:#9bd;\">hover a node &middot; click to pin &middot; Esc clears</div>';
    el.appendChild(ctrl);
    ctrl.addEventListener('change', function(e) {
      if (e.target && e.target.name === 'indy-res') {
        pinnedId = null; clear();
        active = e.target.value;
        applyFlow(RES[active].flow);
        setNativeVisibility(active);
      }
    });
  }

  var tries = 0, inited = false;
  function init() {
    if (!window.MapGLFlowmapPlugin || !data || !data.bg) {
      if (tries++ < 60) { setTimeout(init, 150); }
      return;
    }
    if (inited) return;
    KEYS.forEach(function(res) { if (data[res]) idx[res] = buildIndex(data[res]); });
    ensureHighlightLayers();
    setNativeVisibility(active);
    applyFlow(RES[active].flow);
    wire();
    inited = true;
  }
  buildLegend();
  buildRadio();
  if (map.once) map.once('idle', init);
  init();
}"
```

- [ ] **Step 2: Replace `scripts/02-build-flowmap.R` with this exact content**

```r
# scripts/02-build-flowmap.R
suppressMessages({library(mapgl); library(dplyr); library(sf); library(htmlwidgets)})
source('R/interaction_js.R')   # defines INTERACTION_JS

flows_bg    <- readRDS('data/flows.rds')
locs_bg     <- readRDS('data/locations.rds')
flows_zcta  <- readRDS('data/flows_zcta.rds')
locs_zcta   <- readRDS('data/locations_zcta.rds')
flows_block <- readRDS('data/flows_block.rds')
locs_block  <- readRDS('data/locations_block.rds')
polys_bg    <- readRDS('data/polys_bg.rds')
polys_zcta  <- readRDS('data/polys_zcta.rds')
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
flows_block <- cap_flows(flows_block, locs_block$id, 'block')

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
payload <- list(bg    = make_payload(flows_bg,    locs_bg),
                zcta  = make_payload(flows_zcta,  locs_zcta),
                block = make_payload(flows_block, locs_block))

hits_bg    <- sf::st_as_sf(locs_bg,    coords = c('lon','lat'), crs = 4326)
hits_zcta  <- sf::st_as_sf(locs_zcta,  coords = c('lon','lat'), crs = 4326)
hits_block <- sf::st_as_sf(locs_block, coords = c('lon','lat'), crs = 4326)

message('BG: ', nrow(flows_bg), '/', nrow(locs_bg),
        ' | ZCTA: ', nrow(flows_zcta), '/', nrow(locs_zcta),
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
  fm('indy-block', locs_block, flows_block, 'none') |>
  add_source(id = 'poly-bg',    data = polys_bg) |>
  add_source(id = 'poly-zcta',  data = polys_zcta) |>
  add_source(id = 'poly-block', data = polys_block) |>
  add_line_layer(id = 'outline-bg',    source = 'poly-bg',
                 line_color = '#FFFFFF', line_width = 2, filter = empty_filter) |>
  add_line_layer(id = 'outline-zcta',  source = 'poly-zcta',
                 line_color = '#FFFFFF', line_width = 2, filter = empty_filter) |>
  add_line_layer(id = 'outline-block', source = 'poly-block',
                 line_color = '#FFFFFF', line_width = 2, filter = empty_filter) |>
  add_circle_layer(id = 'hits-bg',    source = hits_bg,
                   circle_color = '#ffffff', circle_opacity = 0, circle_radius = 10) |>
  add_circle_layer(id = 'hits-zcta',  source = hits_zcta,
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
```

- [ ] **Step 3: Render and check size**

Run: `./run.sh scripts/02-build-flowmap.R`
Expected: prints the BG/ZCTA/BLOCK counts, `HTML size: <N> MB`, and `RENDER OK`.
**Size guard:** if `HTML size` > ~40 MB, edit `R/blocks.R` `BLOCK_MIN_COUNT <- 5L`, re-run `./run.sh scripts/01e-fetch-block-data.R` then this step, and note the change in the report. If it is ≤ ~25 MB, proceed.

- [ ] **Step 4: Static checks**

Run:
```bash
for s in indy-block hits-block outline-block inbound-block outbound-block 'value=\"block\"' 'Census block'; do
  printf '%s: ' "$s"; grep -c -- "$s" output/indy-commute-flows.html
done
```
Expected: each returns a non-zero count.

- [ ] **Step 5: Headless interaction check (acceptance gate)**

Write `scripts/_block-check.mjs` (host Node + Playwright; not committed):

```js
import { chromium } from 'playwright';
import { resolve } from 'node:path';
const HTML = 'file://' + resolve('output/indy-commute-flows.html');
const b = await chromium.launch({ args:['--use-gl=egl','--enable-unsafe-swiftshader','--no-sandbox'] });
const p = await b.newPage({ viewport:{ width:1280, height:860 } });
await p.goto(HTML, { waitUntil:'networkidle' });
await p.waitForTimeout(6000);

const srcLen = (id) => p.evaluate((i) => {
  const s = window.__indyMap.getSource(i);
  const d = (s && (s._data || (s.serialize && s.serialize().data))) || { features:[] };
  return d.features.length;
}, id);

// Switch to Census block.
await p.evaluate(() => {
  const r = document.querySelector('input[name=\"indy-res\"][value=\"block\"]');
  r.checked = true; r.dispatchEvent(new Event('change', { bubbles:true }));
});
await p.waitForTimeout(1200);
await p.evaluate(() => window.__indyMap.setZoom(12));
await p.waitForTimeout(1500);

const probe = await p.evaluate(() => {
  const m = window.__indyMap;
  const fs = m.queryRenderedFeatures({ layers:['hits-block'] });
  if (!fs.length) return null;
  const f = fs[0], pt = m.project(f.geometry.coordinates);
  return { id:f.properties.id, x:pt.x, y:pt.y };
});
if (!probe) { console.log('FAIL: no hits-block features'); await b.close(); process.exit(1); }

await p.mouse.move(probe.x, probe.y);
await p.waitForTimeout(600);
const hoverLines = (await srcLen('inbound-block')) + (await srcLen('outbound-block'));
const hoverLabels = await srcLen('partner-labels');

await p.mouse.click(probe.x, probe.y);
await p.waitForTimeout(600);
const pinLines = (await srcLen('inbound-block')) + (await srcLen('outbound-block'));
const pinLabels = await srcLen('partner-labels');

await p.keyboard.press('Escape');
await p.waitForTimeout(400);
const escLines = (await srcLen('inbound-block')) + (await srcLen('outbound-block'));

await b.close();
console.log('block node', probe.id, 'hover lines', hoverLines, 'hover labels', hoverLabels,
            'pin lines', pinLines, 'pin labels', pinLabels, 'esc lines', escLines);
const ok = hoverLines > 0 && hoverLabels === 0
        && pinLines > 0 && pinLabels >= 1 && pinLabels <= 6
        && escLines === 0;
console.log(ok ? 'BLOCK CHECK OK' : 'BLOCK CHECK FAIL');
process.exit(ok ? 0 : 1);
```

Run: `node scripts/_block-check.mjs`
Expected: prints the states and `BLOCK CHECK OK` — on the block resolution: hover populates inbound/outbound lines with 0 labels; click-pin keeps lines and adds 1–6 labels; Esc clears the lines. Then `rm scripts/_block-check.mjs`.
If no `hits-block` features render at zoom 12, raise the zoom (13–14) and re-probe; block centroids are dense, so a higher zoom isolates one. Report which zoom worked.

- [ ] **Step 6: Commit**

```bash
git add R/interaction_js.R scripts/02-build-flowmap.R
git commit -m "Add Census block as a third resolution (generalize interaction to N)"
```

---

### Task 3: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the resolution-toggle section of `README.md`**

Read `README.md`; in the "Resolution toggle" section, add Census block to the description and rebuild steps. Append this paragraph + code block at the end of that section:

```markdown
A third **Census block** option shows the most granular LODES geography (the
level the data is built from). Block-to-block LODES is heavily noise-infused, so
this layer is thresholded to commuter **count ≥ 3** — it drops the ~873k count-1
fuzzing pairs in the region and shows the strongest block-to-block corridors
(~19.8k flows / ~8k blocks), not every commuter.

```bash
./run.sh scripts/01e-fetch-block-data.R  # census-block OD (count>=3) + centroids + polygons
```
```

- [ ] **Step 2: Verify**

Run: `grep -c -E 'Census block|01e-fetch-block|count . 3|corridors' README.md`
Expected: non-zero.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the Census block resolution"
```

---

## Self-Review

**Spec coverage:** block data path (thresholded flows + centroids + simplified polygons, every block covered) → Task 1; third `indy-block` flowmap + hits/outline/highlight layers + `block` payload + size print + interaction JS generalized 2→N with the "Census block" radio option → Task 2; README → Task 3. The size guard is in Task 2 Step 3. bg/zcta paths and scripts untouched. All spec sections mapped.

**Placeholder scan:** No TBD/TODO; full files provided. The adaptation notes (tigris `blocks` year arg; size-guard threshold raise; check-script zoom raise) are explicit fallbacks with values.

**Type consistency:** resolution keys `bg`/`zcta`/`block`; ids `indy-block`/`hits-block`/`poly-block`/`outline-block`/`inbound-block`/`outbound-block`; payload shape `{ids,lon,lat,o,d,c}`; `RES[active].flow` used in `applyFlow`/radio; `BLOCK_MIN_COUNT`, `build_block_flows`/`load_blocks`/`build_block_locations`/`build_block_polygons` signatures match their callers; colors/font unchanged. The generalized loops use `KEYS = Object.keys(RES)` consistently.
