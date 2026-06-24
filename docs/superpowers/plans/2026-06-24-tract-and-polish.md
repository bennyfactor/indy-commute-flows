# Census Tract + Toggle Reorder/Rename + Coarser Block Polygons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Census tract resolution, reorder the toggle largest→smallest with renamed labels, and coarsen the block polygons to trim page weight.

**Architecture:** A new R data path builds tract flows + centroids + simplified polygons (native `agg_geo="tract"`, no crosswalk). The block-polygon simplify tolerance is doubled and regenerated. The render adds a fourth `add_flowmap` + layers + payload entry; the interaction JS gains `tract` in `RES` (already iterates `Object.keys(RES)`) and a reordered/renamed radio. Census block group stays the default-shown layer.

**Tech Stack:** R (mapgl 0.5.0, lehdr `grab_lodes(agg_geo="tract")`, tigris `tracts()`, sf, dplyr) in `indy-flows:latest`; Node + Playwright (host) for headless verification.

## Global Constraints

- Branch `tract-and-polish`. Additive except the two targeted edits (block dTolerance, render/JS). Do NOT change bg/zcta fetch+polygon scripts, `R/regions.R`, or capture/deploy scripts.
- Run R in the container: `./run.sh <script.R>`; `run.sh` has no `-i` — temp checks go in `scripts/_*.R`/`.mjs`, deleted, never committed.
- Tract: `grab_lodes(agg_geo="tract")` → `h_tract`/`w_tract` (11-digit GEOID) + `S000`; both endpoints in `region_counties()` (county = first 5 chars); drop self-loops; `count > 0`. Tigris tract id column = `GEOID` (11-digit), `tigris::tracts(year=tg_year, cb=TRUE)`, `tg_year <- min(lodes_year, 2023L)`. Tract polygon simplify `dTolerance=0.0004`.
- Block polygons: `build_block_polygons` `dTolerance` `0.0004 → 0.0008`; regenerate `data/polys_block.rds`.
- Resolution keys: `bg`/`zcta`/`block`/`tract`. New ids: `indy-tract`, `hits-tract`, `poly-tract`, `outline-tract`, `inbound-tract`, `outbound-tract`.
- Toggle order (largest→smallest) with values/labels: `zcta` "ZIP code", `tract` "Census tract", `bg` "Census block group" (**checked**, default), `block` "Census block". `active` initializes to `bg`.
- Colors/font unchanged: inbound `#FF4D6D`, outbound `#FFD166`, outline `#FFFFFF`, halo `#101014`, `["Open Sans Bold"]`. ZIP-prefix in labels stays gated on `active === 'zcta'` (tract labels = count only).
- Data contracts: `flows_tract`=`origin,dest,count`; `locations_tract`=`id,lon,lat`; `polys_tract` sf=`id`+geometry (EPSG:4326). Every flow tract id has a centroid and a polygon.
- Preserve `window.__indyMap`. mapgl ≥ 0.5.0. Commit after each task.

---

### Task 1: Tract data path + coarser block polygons

**Files:**
- Create: `R/tracts.R`
- Create: `scripts/01f-fetch-tract-data.R`
- Modify: `R/blocks.R` (one line: block `dTolerance`)

**Interfaces:**
- Consumes: `region_counties()`; `data/lodes_year.txt`.
- Produces: `data/flows_tract.rds`, `data/locations_tract.rds`, `data/polys_tract.rds`; regenerated (coarser) `data/polys_block.rds`. Helpers `build_tract_flows(counties, year)`, `load_tracts(counties, year)`, `build_tract_locations(tracts_sf, flows)`, `build_tract_polygons(tracts_sf, flows)`.

- [ ] **Step 1: Write `R/tracts.R`**

```r
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
```

- [ ] **Step 2: Write `scripts/01f-fetch-tract-data.R`**

```r
# scripts/01f-fetch-tract-data.R — census-tract flows + centroids + polygons.
suppressMessages({library(sf); library(dplyr)})
source("R/regions.R"); source("R/tracts.R")

dir.create("data", showWarnings = FALSE)
stopifnot("data/lodes_year.txt missing - run scripts/01-fetch-data.R first" =
          file.exists("data/lodes_year.txt"))
year <- as.integer(readLines("data/lodes_year.txt"))
tg_year <- min(year, 2023L)

flows <- build_tract_flows(region_counties(), year)
message("Tract OD pairs: ", nrow(flows),
        " | commuters: ", format(sum(flows$count), big.mark = ","))
saveRDS(flows, "data/flows_tract.rds")

tracts_sf <- load_tracts(region_counties(), tg_year)
locs  <- build_tract_locations(tracts_sf, flows)
polys <- build_tract_polygons(tracts_sf, flows)

used <- unique(c(flows$origin, flows$dest))
stopifnot("every flow tract has a centroid" = length(setdiff(used, locs$id)) == 0)
stopifnot("every flow tract has a polygon"  = length(setdiff(used, polys$id)) == 0)
saveRDS(locs,  "data/locations_tract.rds")
saveRDS(polys, "data/polys_tract.rds")
message("Tract locations: ", nrow(locs), " | polygons: ", nrow(polys))
cat("TRACT DATA OK\n")
```

- [ ] **Step 3: Coarsen the block polygons in `R/blocks.R`**

Change the one line in `build_block_polygons`:

```r
  b <- sf::st_simplify(b, preserveTopology = TRUE, dTolerance = 0.0008)
```

(was `dTolerance = 0.0004`). No other change to `R/blocks.R`.

- [ ] **Step 4: Run both data builds**

Run: `./run.sh scripts/01f-fetch-tract-data.R`
Expected: prints a Tract OD pair count (tens of thousands), a tract locations/polygons count (~350), and `TRACT DATA OK`.

Run: `ls -l data/polys_block.rds` (note the size), then `./run.sh scripts/01e-fetch-block-data.R`
Expected: prints `BLOCK DATA OK`; `ls -l data/polys_block.rds` afterward should be **smaller** than before (coarser simplification). If `tigris::tracts(... cb=TRUE, year=2023)` errors or the id column isn't `GEOID`, inspect `args(tigris::tracts)` / `names(load_tracts(region_counties(), 2023L))` and adapt the year/id-column (must yield 11-digit ids matching the LODES `h_tract`/`w_tract`); report any change.
If `grab_lodes(agg_geo="tract")` yields different column names than `h_tract`/`w_tract`, inspect `names()` of a small pull and adapt the `mutate`, keeping the `origin/dest/count` contract; report it.

- [ ] **Step 5: Sanity-check (temp script, not committed)**

Write `scripts/_check.R`:

```r
suppressMessages(library(sf))
f <- readRDS("data/flows_tract.rds"); l <- readRDS("data/locations_tract.rds")
p <- readRDS("data/polys_tract.rds")
stopifnot(all(c("origin","dest","count") %in% names(f)), all(f$count > 0))
stopifnot(all(c("id","lon","lat") %in% names(l)))
stopifnot(all(nchar(f$origin) == 11), all(nchar(l$id) == 11), all(nchar(p$id) == 11))
stopifnot(sf::st_crs(p)$epsg == 4326)
stopifnot(all(l$lon > -88 & l$lon < -85), all(l$lat > 38.5 & l$lat < 41))
stopifnot("every flow tract has a centroid" = length(setdiff(unique(c(f$origin,f$dest)), l$id)) == 0)
cat("tract pairs:", nrow(f), "tracts:", nrow(l), "\nTRACT CHECK OK\n")
```

Run: `./run.sh scripts/_check.R` → expect `TRACT CHECK OK`. Then `rm scripts/_check.R`.

- [ ] **Step 6: Commit**

```bash
git add R/tracts.R scripts/01f-fetch-tract-data.R R/blocks.R
git commit -m "Add census-tract data path; coarsen block polygons (dTolerance 0.0008)"
```

---

### Task 2: Render + interaction (4th resolution, reordered/renamed toggle)

**Files:**
- Modify: `R/interaction_js.R` (full rewrite below — add `tract` to RES, reorder/rename radio)
- Modify: `scripts/02-build-flowmap.R` (full rewrite below — add tract layer + payload)

**Interfaces:**
- Consumes: all bg/zcta/block/tract `flows_*`/`locations_*`/`polys_*` rds.
- Produces: `output/indy-commute-flows.html` with four toggle options and the full interaction on each.

- [ ] **Step 1: Replace `R/interaction_js.R` with this exact content**

```r
# R/interaction_js.R — onRender JS for the node hover/click interaction.
# Receives (el, x, data); data has one entry per resolution (bg/zcta/block/tract),
# each {ids,lon,lat,o,d,c} with o/d 0-based indices into ids and c the commuter
# count. Builds inbound (#FF4D6D) / outbound (#FFD166) line layers + a white
# polygon outline, dims the Flowmap.gl deck canvas on focus, supports hover-preview
# + click-to-pin, shows an always-on color legend, and labels the pinned node's
# top 3 inbound / top 3 outbound partners. Generalized over all resolutions in RES.
INTERACTION_JS <- "
function(el, x, data) {
  var map = el.map;
  if (!map) return;
  window.__indyMap = map;

  var RES = {
    bg:    { flow:'indy-bg',    hits:'hits-bg',    outline:'outline-bg',    inbound:'inbound-bg',    outbound:'outbound-bg' },
    zcta:  { flow:'indy-zcta',  hits:'hits-zcta',  outline:'outline-zcta',  inbound:'inbound-zcta',  outbound:'outbound-zcta' },
    block: { flow:'indy-block', hits:'hits-block', outline:'outline-block', inbound:'inbound-block', outbound:'outbound-block' },
    tract: { flow:'indy-tract', hits:'hits-tract', outline:'outline-tract', inbound:'inbound-tract', outbound:'outbound-tract' }
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
    var opt = function(value, label, checked) {
      return '<label style=\"display:block;cursor:pointer;\">' +
        '<input type=\"radio\" name=\"indy-res\" value=\"' + value + '\"' +
        (checked ? ' checked' : '') + '> ' + label + '</label>';
    };
    ctrl.innerHTML =
      '<div style=\"font-weight:600;margin-bottom:4px;\">Resolution</div>' +
      opt('zcta',  'ZIP code', false) +
      opt('tract', 'Census tract', false) +
      opt('bg',    'Census block group', true) +
      opt('block', 'Census block', false) +
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
```

- [ ] **Step 3: Render**

Run: `./run.sh scripts/02-build-flowmap.R`
Expected: prints BG/ZCTA/TRACT/BLOCK counts, `HTML size: <N> MB` (expect ~27–28 MB), and `RENDER OK`.

- [ ] **Step 4: Static checks**

Run:
```bash
for s in indy-tract hits-tract outline-tract inbound-tract 'Census tract' 'Census block group' 'value=\"tract\"'; do
  printf '%s: ' "$s"; grep -c -- "$s" output/indy-commute-flows.html
done
```
Expected: each returns a non-zero count. (Also confirm the OLD label is gone: `grep -c '> Block group<' output/indy-commute-flows.html` should be 0.)

- [ ] **Step 5: Headless interaction check (acceptance gate)**

Write `scripts/_tract-check.mjs` (host Node + Playwright; not committed):

```js
import { chromium } from 'playwright';
import { resolve } from 'node:path';
const HTML = 'file://' + resolve('output/indy-commute-flows.html');
const b = await chromium.launch({ args:['--use-gl=egl','--enable-unsafe-swiftshader','--no-sandbox'] });
const p = await b.newPage({ viewport:{ width:1280, height:860 } });
await p.goto(HTML, { waitUntil:'networkidle' });
await p.waitForTimeout(6000);

const radio = await p.evaluate(() => {
  const els = [...document.querySelectorAll('input[name=\"indy-res\"]')];
  return { order: els.map(e => e.value),
           labels: els.map(e => e.parentElement.textContent.trim()),
           checked: (els.find(e => e.checked) || {}).value };
});

const srcLen = (id) => p.evaluate((i) => {
  const s = window.__indyMap.getSource(i);
  const d = (s && (s._data || (s.serialize && s.serialize().data))) || { features:[] };
  return d.features.length;
}, id);

// Select Census tract.
await p.evaluate(() => {
  const r = document.querySelector('input[name=\"indy-res\"][value=\"tract\"]');
  r.checked = true; r.dispatchEvent(new Event('change', { bubbles:true }));
});
await p.waitForTimeout(1200);
await p.evaluate(() => window.__indyMap.setZoom(11));
await p.waitForTimeout(1500);
const probe = await p.evaluate(() => {
  const m = window.__indyMap;
  const fs = m.queryRenderedFeatures({ layers:['hits-tract'] });
  if (!fs.length) return null;
  const f = fs[0], pt = m.project(f.geometry.coordinates);
  return { id:f.properties.id, x:pt.x, y:pt.y };
});
if (!probe) { console.log('FAIL: no hits-tract features'); await b.close(); process.exit(1); }

await p.mouse.move(probe.x, probe.y);
await p.waitForTimeout(600);
const hoverLines = (await srcLen('inbound-tract')) + (await srcLen('outbound-tract'));
const hoverLabels = await srcLen('partner-labels');
await p.mouse.click(probe.x, probe.y);
await p.waitForTimeout(600);
const pinLabels = await srcLen('partner-labels');
await p.keyboard.press('Escape');
await p.waitForTimeout(400);
const escLines = (await srcLen('inbound-tract')) + (await srcLen('outbound-tract'));
await b.close();

console.log('radio', radio, 'tract', probe.id,
            'hover lines', hoverLines, 'hover labels', hoverLabels,
            'pin labels', pinLabels, 'esc lines', escLines);
const ok = JSON.stringify(radio.order) === JSON.stringify(['zcta','tract','bg','block'])
  && radio.checked === 'bg'
  && radio.labels[0].includes('ZIP') && radio.labels[1].includes('Census tract')
  && radio.labels[2].includes('Census block group') && radio.labels[3].includes('Census block')
  && hoverLines > 0 && hoverLabels === 0
  && pinLabels >= 1 && pinLabels <= 6
  && escLines === 0;
console.log(ok ? 'TRACT CHECK OK' : 'TRACT CHECK FAIL');
process.exit(ok ? 0 : 1);
```

Run: `node scripts/_tract-check.mjs`
Expected: prints the radio state + interaction values and `TRACT CHECK OK` — radio order `[zcta,tract,bg,block]` with `bg` checked and the four expected labels; tract hover populates lines (0 labels); pin adds 1–6 labels; Esc clears. Then `rm scripts/_tract-check.mjs`.
If no `hits-tract` features render at zoom 11, raise the zoom (12–13) and re-probe; report which worked.

- [ ] **Step 6: Commit**

```bash
git add R/interaction_js.R scripts/02-build-flowmap.R
git commit -m "Add Census tract resolution; reorder/rename the toggle largest->smallest"
```

---

### Task 3: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the resolution-toggle section of `README.md`**

Read `README.md`; in the "Resolution toggle" section, document the four resolutions in
largest→smallest order, the renamed "Census block group" label, and the new build step.
Append this paragraph + code block at the end of that section:

```markdown
The toggle offers four resolutions, listed largest → smallest by area: **ZIP code**
(ZCTA) → **Census tract** → **Census block group** (the default view) → **Census
block**. Census tract is the easy middle level — `lehdr` aggregates to it natively
(no crosswalk).

```bash
./run.sh scripts/01f-fetch-tract-data.R  # census-tract OD + centroids + polygons
```
```

- [ ] **Step 2: Verify**

Run: `grep -c -E 'Census tract|01f-fetch-tract|four resolutions' README.md`
Expected: non-zero.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the Census tract resolution and reordered toggle"
```

---

## Self-Review

**Spec coverage:** tract data path (native agg_geo=tract, centroids + simplified polygons, full coverage) + block-polygon coarsening → Task 1; fourth `indy-tract` flowmap + layers + payload + `RES.tract` + reordered/renamed radio (bg default-checked) → Task 2; README → Task 3. bg/zcta paths untouched. All spec sections mapped.

**Placeholder scan:** No TBD/TODO; full files provided. Adaptation notes (tigris tract year/id column; `h_tract`/`w_tract` column names; check-script zoom) are explicit fallbacks.

**Type consistency:** keys `bg`/`zcta`/`block`/`tract`; ids `indy-tract`/`hits-tract`/`poly-tract`/`outline-tract`/`inbound-tract`/`outbound-tract`; radio values `zcta`/`tract`/`bg`/`block` with `bg` checked and `active` initialized to `bg`; `build_tract_flows`/`load_tracts`/`build_tract_locations`/`build_tract_polygons` signatures match callers; colors/font unchanged; `KEYS = Object.keys(RES)` used throughout.
