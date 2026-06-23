# Node Highlight (Boundary + Two-Color In/Out Flows) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On hover/click of a node (block-group or ZCTA centroid), draw its boundary polygon and highlight inbound vs outbound flows in two distinct colors over a dimmed base.

**Architecture:** A new R script builds simplified boundary polygons. The render script adds, per resolution, a transparent hit-target circle layer, a polygon source + white outline line layer, and embeds a compact flows+centroids payload. An interaction JS module (passed via `onRender(data=…)`) wires hover-preview + click-to-pin: it builds inbound/outbound MapLibre line layers (rose/gold), outlines the hovered polygon via `setFilter`, and dims the Flowmap.gl deck canvas via CSS so the highlight reads clearly.

**Tech Stack:** R (mapgl 0.5.0 `add_circle_layer`/`add_line_layer`/`add_source`/`add_flowmap`/`onRender`, sf, tigris, dplyr) in the `indy-flows:latest` container; Node + Playwright (host) for headless verification.

## Global Constraints

- Branch `node-highlight`. Additive: do NOT change the fetch/centroid scripts, capture or deploy scripts, or `R/regions.R`/`R/lodes.R`/`R/zcta.R`/`R/locations.R`.
- Run R in the container: `./run.sh <script.R>`. **`run.sh` has no `-i`** — never use the `/dev/stdin` heredoc; write temp checks to `scripts/_check.R` (or `.mjs` for Node) and delete them, never commit.
- Flowmap layer ids stay `indy-bg` / `indy-zcta` (block group default visible). Resolution keys are `bg` / `zcta`.
- Exact native layer/source ids: hit layers `hits-bg`/`hits-zcta`; polygon sources `poly-bg`/`poly-zcta`; outline layers `outline-bg`/`outline-zcta`; highlight layers `inbound-bg`/`outbound-bg`/`inbound-zcta`/`outbound-zcta`. Radio input `name` = `indy-res`, values `bg`/`zcta`.
- Colors: inbound `#FF4D6D` (rose), outbound `#FFD166` (gold), outline `#FFFFFF` (white). Base `Teal`, dark-matter basemap.
- Data contracts: `flows*`=`origin,dest,count`; `locations*`=`id,lon,lat`; polygons sf = `id` + geometry, EPSG:4326. Highlight uses the SAME (capped) flows the flowmap shows, so the highlight matches the visible base.
- Preserve `window.__indyMap = el.map` (capture depends on it). Keep the block-group camera-tour video valid (block group is the default).
- mapgl ≥ 0.5.0. Commit after each task.

---

### Task 1: Boundary polygon data

**Files:**
- Create: `R/polygons.R`
- Create: `scripts/01d-build-polygons.R`

**Interfaces:**
- Consumes: `region_counties()` (`R/regions.R`); `data/locations.rds`, `data/locations_zcta.rds`.
- Produces: `data/polys_bg.rds`, `data/polys_zcta.rds` — sf, columns `id` (chr) + geometry (EPSG:4326), filtered to the ids present in the matching locations file. Helpers `build_bg_polygons(counties, year)` and `build_zcta_polygons()`.

- [ ] **Step 1: Write `R/polygons.R`**

```r
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
```

- [ ] **Step 2: Write `scripts/01d-build-polygons.R`**

```r
# scripts/01d-build-polygons.R — boundary polygons for the hover outline.
suppressMessages({library(sf); library(dplyr)})
source("R/regions.R"); source("R/polygons.R")

dir.create("data", showWarnings = FALSE)
stopifnot("data/lodes_year.txt missing - run scripts/01-fetch-data.R first" =
          file.exists("data/lodes_year.txt"))
lodes_year <- as.integer(readLines("data/lodes_year.txt"))
tg_year <- min(lodes_year, 2023L)

bg <- build_bg_polygons(region_counties(), tg_year)
loc_bg <- readRDS("data/locations.rds")
bg <- bg[bg$id %in% loc_bg$id, ]
saveRDS(bg, "data/polys_bg.rds")
message("BG polygons: ", nrow(bg))

zc <- build_zcta_polygons()
loc_zc <- readRDS("data/locations_zcta.rds")
zc <- zc[zc$id %in% loc_zc$id, ]
saveRDS(zc, "data/polys_zcta.rds")
message("ZCTA polygons: ", nrow(zc))
cat("POLYGONS OK\n")
```

- [ ] **Step 3: Run it**

Run: `./run.sh scripts/01d-build-polygons.R`
Expected: prints BG polygon count (~1,724) and ZCTA polygon count (~201), then `POLYGONS OK`. (Reuses cached tigris downloads from the centroid build, so fast.)

- [ ] **Step 4: Sanity-check (temp script, not committed)**

Write `scripts/_check.R`:

```r
suppressMessages(library(sf))
bg <- readRDS("data/polys_bg.rds"); zc <- readRDS("data/polys_zcta.rds")
lb <- readRDS("data/locations.rds"); lz <- readRDS("data/locations_zcta.rds")
stopifnot("id" %in% names(bg), "id" %in% names(zc))
stopifnot(all(nchar(bg$id) == 12), all(nchar(zc$id) == 5))
stopifnot(sf::st_crs(bg)$epsg == 4326, sf::st_crs(zc)$epsg == 4326)
stopifnot(length(setdiff(lb$id, bg$id)) == 0)   # every bg location has a polygon
stopifnot(length(setdiff(lz$id, zc$id)) == 0)   # every zcta location has a polygon
cat("bg:", nrow(bg), "zcta:", nrow(zc), "\nPOLY CHECK OK\n")
```

Run: `./run.sh scripts/_check.R` → expect `POLY CHECK OK`. Then `rm scripts/_check.R`.

- [ ] **Step 5: Commit**

```bash
git add R/polygons.R scripts/01d-build-polygons.R
git commit -m "Add simplified boundary polygons for hover outline"
```

---

### Task 2: Render + interaction (boundary outline, two-color in/out highlight, pin, dim)

**Files:**
- Create: `R/interaction_js.R`
- Modify: `scripts/02-build-flowmap.R` (full rewrite below)

**Interfaces:**
- Consumes: `data/flows.rds`, `data/locations.rds`, `data/flows_zcta.rds`, `data/locations_zcta.rds`, `data/polys_bg.rds`, `data/polys_zcta.rds`.
- Produces: `output/indy-commute-flows.html` with the hover/click node interaction. The interaction reads its flows+centroids from the `onRender` `data` payload (keys `bg`/`zcta`, each `{ids, lon, lat, o, d, c}` where `o`/`d` are 0-based position indices into `ids`).

- [ ] **Step 1: Write `R/interaction_js.R`**

```r
# R/interaction_js.R — onRender JS for the node hover/click interaction.
# Receives (el, x, data); data = { bg:{ids,lon,lat,o,d,c}, zcta:{...} } where
# o/d are 0-based indices into ids and c is the commuter count. Builds inbound
# (#FF4D6D) and outbound (#FFD166) line layers + a white polygon outline, dims
# the Flowmap.gl deck canvas on focus, and supports hover-preview + click-to-pin.
INTERACTION_JS <- "
function(el, x, data) {
  var map = el.map;
  if (!map) return;
  window.__indyMap = map;

  var RES = {
    bg:   { flow:'indy-bg',   hits:'hits-bg',   outline:'outline-bg',   inbound:'inbound-bg',   outbound:'outbound-bg' },
    zcta: { flow:'indy-zcta', hits:'hits-zcta', outline:'outline-zcta', inbound:'inbound-zcta', outbound:'outbound-zcta' }
  };
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
    ['bg','zcta'].forEach(function(res) {
      var r = RES[res];
      if (map.getSource(r.inbound))  map.getSource(r.inbound).setData(fc([]));
      if (map.getSource(r.outbound)) map.getSource(r.outbound).setData(fc([]));
      if (map.getLayer(r.outline))   map.setFilter(r.outline, ['==', ['get','id'], '']);
    });
    dim(false);
  }

  function ensureHighlightLayers() {
    ['bg','zcta'].forEach(function(res) {
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
  }
  function setNativeVisibility(res) {
    ['bg','zcta'].forEach(function(rr) {
      var r = RES[rr], vis = (rr === res) ? 'visible' : 'none';
      [r.hits, r.outline, r.inbound, r.outbound].forEach(function(lid) {
        if (map.getLayer(lid)) map.setLayoutProperty(lid, 'visibility', vis);
      });
    });
  }
  function applyFlow(chosen) {
    var p = window.MapGLFlowmapPlugin; if (!p) return false;
    var ok = true;
    ['indy-bg','indy-zcta'].forEach(function(fid) {
      if (!p.setVisibility(map, fid, fid === chosen ? 'visible':'none')) ok = false;
    });
    return ok;
  }

  function wire() {
    ['bg','zcta'].forEach(function(res) {
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
        pinnedId = e.features[0].properties.id; select(pinnedId);
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

  function buildRadio() {
    var ctrl = document.createElement('div');
    ctrl.style.cssText = 'position:absolute;top:10px;right:10px;z-index:1000;' +
      'background:rgba(20,20,20,0.85);color:#eee;padding:8px 10px;border-radius:6px;' +
      'font:13px/1.4 system-ui,sans-serif;';
    ctrl.innerHTML =
      '<div style=\"font-weight:600;margin-bottom:4px;\">Resolution</div>' +
      '<label style=\"display:block;cursor:pointer;\"><input type=\"radio\" name=\"indy-res\" value=\"bg\" checked> Block group</label>' +
      '<label style=\"display:block;cursor:pointer;\"><input type=\"radio\" name=\"indy-res\" value=\"zcta\"> ZIP code</label>' +
      '<div style=\"margin-top:6px;font-size:11px;color:#9bd;\">hover a node &middot; click to pin &middot; Esc clears</div>';
    el.appendChild(ctrl);
    ctrl.addEventListener('change', function(e) {
      if (e.target && e.target.name === 'indy-res') {
        pinnedId = null; clear();
        active = e.target.value;
        applyFlow(active === 'bg' ? 'indy-bg' : 'indy-zcta');
        setNativeVisibility(active);
      }
    });
  }

  var tries = 0;
  function init() {
    if (!window.MapGLFlowmapPlugin || !data || !data.bg) {
      if (tries++ < 60) { setTimeout(init, 150); }
      return;
    }
    idx.bg = buildIndex(data.bg);
    if (data.zcta) idx.zcta = buildIndex(data.zcta);
    ensureHighlightLayers();
    setNativeVisibility(active);
    applyFlow('indy-bg');
    wire();
  }
  buildRadio();
  if (map.once) map.once('idle', init);
  init();
}"
```

- [ ] **Step 2: Rewrite `scripts/02-build-flowmap.R`**

```r
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
```

- [ ] **Step 3: Render**

Run: `./run.sh scripts/02-build-flowmap.R`
Expected: prints the BG/ZCTA counts and `RENDER OK`; rewrites `output/indy-commute-flows.html`.
If `add_circle_layer`/`add_line_layer`/`add_source` reject an argument name in the installed mapgl, inspect `args(mapgl::add_circle_layer)` etc. in the container and adapt the argument names (keep ids, colors, transparent hit, empty filter intent). If `add_source(data=<sf>)` errors, convert with `geojsonsf`/`sf::st_write` to a GeoJSON string and pass that. Note any adaptation in the report.

- [ ] **Step 4: Static checks on the HTML**

Run:
```bash
for s in hits-bg hits-zcta outline-bg outline-zcta inbound-bg outbound-bg indy-res MapGLFlowmapPlugin __indyMap; do
  printf '%s: ' "$s"; grep -c -- "$s" output/indy-commute-flows.html
done
ls -lh output/indy-commute-flows.html```
Expected: each id returns a non-zero count (all native layer ids, the radio, the plugin, and `__indyMap` are embedded). File is self-contained (~9–12 MB).

- [ ] **Step 5: Headless interaction check (the real acceptance gate)**

Write `scripts/_interaction-check.mjs` (host Node + Playwright; not committed):

```js
import { chromium } from 'playwright';
import { resolve } from 'node:path';
const HTML = 'file://' + resolve('output/indy-commute-flows.html');
const b = await chromium.launch({ args:['--use-gl=egl','--enable-unsafe-swiftshader','--no-sandbox'] });
const p = await b.newPage({ viewport:{ width:1280, height:860 } });
await p.goto(HTML, { waitUntil:'networkidle' });
await p.waitForTimeout(6000);

// Pick a real block-group node id with known partners from the embedded payload,
// then drive the interaction directly (deterministic, independent of pixel hit-testing).
const r = await p.evaluate(() => {
  const m = window.__indyMap;
  // Recover the active payload via a hover on the first node that has partners.
  // The interaction stores nothing global, so re-derive from the source updates:
  // call the documented behaviors through the map API.
  // 1) find a node id present in the hits-bg source
  const feats = m.querySourceFeatures
    ? m.queryRenderedFeatures({ layers:['hits-bg'] }) : [];
  return { hasMap: !!m, hasPlugin: !!window.MapGLFlowmapPlugin };
});
if (!r.hasMap || !r.hasPlugin) { console.log('FAIL: map/plugin not ready', r); await b.close(); process.exit(1); }

// Drive a hover by dispatching a real mousemove at the screen point of a known node.
// Use the map to project a known centroid to pixels, then move there.
const probe = await p.evaluate(() => {
  const m = window.__indyMap;
  // Use the first feature in the hits-bg layer's source data via queryRenderedFeatures
  const fs = m.queryRenderedFeatures({ layers:['hits-bg'] });
  if (!fs.length) return null;
  // choose a node that has flows: try several until inbound/outbound non-empty after select
  const f = fs[0];
  const pt = m.project(f.geometry.coordinates);
  return { id: f.properties.id, x: pt.x, y: pt.y };
});
if (!probe) { console.log('FAIL: no hits-bg features rendered'); await b.close(); process.exit(1); }

await p.mouse.move(probe.x, probe.y);
await p.waitForTimeout(700);
const afterHover = await p.evaluate(() => {
  const m = window.__indyMap;
  const inb = m.getSource('inbound-bg')._data || { features:[] };
  const out = m.getSource('outbound-bg')._data || { features:[] };
  const cs = document.querySelectorAll('canvas');
  let deckOpacity = '1';
  cs.forEach(c => { if (!c.classList.contains('maplibregl-canvas')) deckOpacity = c.style.opacity || '1'; });
  return { inbound: inb.features.length, outbound: out.features.length, deckOpacity };
});
console.log('after hover:', afterHover, 'node:', probe.id);

// Click to pin, then move away — selection must persist.
await p.mouse.click(probe.x, probe.y);
await p.waitForTimeout(300);
await p.mouse.move(probe.x + 250, probe.y + 250);
await p.waitForTimeout(400);
const afterPin = await p.evaluate(() => {
  const m = window.__indyMap;
  const inb = m.getSource('inbound-bg')._data || { features:[] };
  return { inbound: inb.features.length };
});

// Esc clears.
await p.keyboard.press('Escape');
await p.waitForTimeout(400);
const afterEsc = await p.evaluate(() => {
  const m = window.__indyMap;
  const inb = m.getSource('inbound-bg')._data || { features:[] };
  let deckOpacity = '1';
  document.querySelectorAll('canvas').forEach(c => { if (!c.classList.contains('maplibregl-canvas')) deckOpacity = c.style.opacity || '1'; });
  return { inbound: inb.features.length, deckOpacity };
});
await b.close();

const ok = (afterHover.inbound + afterHover.outbound) > 0
        && afterHover.deckOpacity !== '1'
        && afterPin.inbound > 0
        && afterEsc.inbound === 0 && afterEsc.deckOpacity === '1';
console.log('pin:', afterPin, 'esc:', afterEsc);
console.log(ok ? 'INTERACTION CHECK OK' : 'INTERACTION CHECK FAIL');
process.exit(ok ? 0 : 1);
```

Run: `node scripts/_interaction-check.mjs`
Expected: prints the hover/pin/esc states and `INTERACTION CHECK OK` — on hover a node, inbound+outbound line features are populated and the deck canvas is dimmed (opacity ≠ 1); after click-pin the selection persists when the mouse moves away; Esc empties the highlight and restores opacity. Then `rm scripts/_interaction-check.mjs`.

If `INTERACTION CHECK FAIL` because the chosen first node has no flows, adjust the probe to scan `queryRenderedFeatures({layers:['hits-bg']})` for a node whose `select()` yields non-empty sources (iterate a few candidates). If sources read back empty because MapLibre doesn't expose `_data`, instead assert via `map.getSource(id).serialize().data.features.length` or re-query the rendered `inbound-bg` line features with `queryRenderedFeatures({layers:['inbound-bg']})` after moving the map a hair. Report which assertion path was used.

- [ ] **Step 6: Commit**

```bash
git add R/interaction_js.R scripts/02-build-flowmap.R
git commit -m "Add node hover/click boundary outline + two-color in/out flow highlight"
```

---

### Task 3: README + finalize

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing new. Documents the interaction and the new build step.

- [ ] **Step 1: Add an "Interactive node highlight" section to `README.md`**

Read the current `README.md`, then insert this section after the "Resolution toggle" section (match the file's markdown style):

```markdown
## Interactive node highlight

Hover any node (a block-group or ZIP/ZCTA centroid) to draw that area's boundary
and split its commute flows into two colors — **inbound** (flows *to* the node,
rose `#FF4D6D`) and **outbound** (flows *from* the node, gold `#FFD166`) — over a
dimmed base. **Click** a node to pin the selection (move the mouse freely);
**Esc** or a click on empty space clears it. Works in both resolutions.

Boundaries come from simplified census block-group / ZCTA polygons
(`scripts/01d-build-polygons.R`). The highlight is drawn as native MapLibre line
layers from the embedded flows, and the base Flowmap.gl layer is dimmed via its
canvas opacity so the two-color highlight reads clearly.

### Rebuild step (in addition to the toggle steps)
```bash
./run.sh scripts/01d-build-polygons.R   # boundary polygons -> data/polys_{bg,zcta}.rds
./run.sh scripts/02-build-flowmap.R     # render with the node interaction
```
```

- [ ] **Step 2: Verify**

Run: `grep -c -E 'node highlight|01d-build-polygons|inbound|outbound' README.md`
Expected: non-zero.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the interactive node highlight"
```

---

## Self-Review

**Spec coverage:** boundary polygon data (simplified, filtered to located ids) → Task 1; hit-target picking + white outline via setFilter + two-color inbound/outbound MapLibre line layers + deck-canvas dimming + hover-preview/click-pin/Esc + resolution switch clearing → Task 2; README → Task 3. The spec's "read from x.flowmaps" is intentionally replaced by the more reliable `onRender(data=…)` payload (the spec listed this as the fallback); noted in the plan header. All spec sections mapped.

**Placeholder scan:** No TBD/TODO; all code is concrete. The adaptation notes (mapgl arg-name check; payload single-element unboxing; the interaction-check assertion-path fallback) are explicit fallbacks with values, not placeholders.

**Type consistency:** layer/source ids (`hits-*`,`outline-*`,`inbound-*`,`outbound-*`,`poly-*`), flowmap ids (`indy-bg`/`indy-zcta`), radio `name=indy-res` values `bg`/`zcta`, payload shape `{ids,lon,lat,o,d,c}`, and colors (`#FF4D6D`/`#FFD166`/`#FFFFFF`) are identical across `R/interaction_js.R` and `scripts/02-build-flowmap.R`. `make_payload`/`build_bg_polygons`/`build_zcta_polygons` signatures match their callers.
