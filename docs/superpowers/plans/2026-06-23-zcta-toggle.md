# Block-group ↔ ZIP/ZCTA Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a geographic-resolution radio switch (Block group ↔ ZIP/ZCTA) to the existing central-Indiana commute flow map, in one self-contained HTML widget, without disturbing the working block-group pipeline.

**Architecture:** A new R data path aggregates block-level LODES OD to ZCTA pairs via the LODES block→ZCTA crosswalk and builds ZCTA centroids from tigris (`scripts/01c-fetch-zcta-data.R` + `R/zcta.R`). The render script (`scripts/02-build-flowmap.R`) is extended to emit two `add_flowmap()` layers (`indy-bg` visible, `indy-zcta` hidden) and an `onRender` JS control that flips visibility via `window.MapGLFlowmapPlugin.setVisibility()`, mutually exclusive. README documents the toggle and ZCTA caveats.

**Tech Stack:** R (mapgl ≥0.5.0, lehdr `grab_lodes`/`grab_crosswalk`, tigris `zctas`, sf, dplyr) in the existing `indy-flows:latest` podman container; existing Node/Playwright for a headless toggle check.

## Global Constraints

- Branch: `zcta-toggle` (same repo bennyfactor/indy-commute-flows). Work is additive; do not modify the block-group fetch/locations scripts, `R/regions.R`, `R/lodes.R`, `R/locations.R`, or the capture scripts.
- Run R scripts in the container: `./run.sh <script.R>`. **`run.sh` has no `-i`** — the `./run.sh /dev/stdin <<EOF` heredoc does NOT forward stdin. For inline verification, write the check to a temp `scripts/_check.R`, run `./run.sh scripts/_check.R`, then delete it (never commit temp checks).
- Region = 15 IN counties via `region_counties()` (5-digit FIPS, e.g. `"18097"`); the crosswalk county column `cty` is also 5-digit and matches directly.
- LODES params: `version="LODES8"`, `lodes_type="od"`, `state_part="main"`, `segment="S000"`, `job_type="JT00"`. ZCTA path uses `agg_geo="block"` (raw blocks, required for the crosswalk join). Year is read from `data/lodes_year.txt` (currently 2023).
- Data contracts: `flows*` = columns `origin, dest, count`; `locations*` = columns `id, lon, lat` (EPSG:4326). Every `origin`/`dest` must have a matching `locations.id`.
- Crosswalk key: `tabblk2020` (15-digit) matches OD `h_geocode`/`w_geocode` directly. ZCTA column is `zcta`. tigris ZCTA id column is `ZCTA5CE20`.
- Layer ids are exactly `indy-bg` and `indy-zcta`; the radio control's input `name` is `indy-res`. Block group is the default visible layer (so the existing camera-tour video stays valid).
- Preserve `window.__indyMap = el.map` exposure in the render's onRender (the capture script depends on it).
- mapgl ≥ 0.5.0. Commit after each task.

---

### Task 1: ZCTA data path (flows + locations)

**Files:**
- Create: `R/zcta.R`
- Create: `scripts/01c-fetch-zcta-data.R`

**Interfaces:**
- Consumes: `region_counties()` from `R/regions.R`; `data/lodes_year.txt`.
- Produces: `data/flows_zcta.rds` (`origin, dest, count`), `data/locations_zcta.rds` (`id, lon, lat`). Helpers `build_zcta_flows(counties, year)` → data.frame(origin,dest,count); `build_zcta_locations(flows)` → data.frame(id,lon,lat).

- [ ] **Step 1: Write `R/zcta.R`**

```r
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
    dplyr::filter(cty %in% counties) |>
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
```

- [ ] **Step 2: Write `scripts/01c-fetch-zcta-data.R`**

```r
# scripts/01c-fetch-zcta-data.R — build ZCTA OD flows + centroids for the region.
suppressMessages({library(dplyr)})
source("R/regions.R"); source("R/zcta.R")

dir.create("data", showWarnings = FALSE)
stopifnot("data/lodes_year.txt missing - run scripts/01-fetch-data.R first" =
          file.exists("data/lodes_year.txt"))
year <- as.integer(readLines("data/lodes_year.txt"))
message("Building ZCTA flows for LODES year ", year)

flows_zcta <- build_zcta_flows(region_counties(), year)
message("ZCTA OD pairs: ", nrow(flows_zcta),
        " | commuters: ", format(sum(flows_zcta$count), big.mark = ","))
saveRDS(flows_zcta, "data/flows_zcta.rds")

locs_zcta <- build_zcta_locations(flows_zcta)
used <- unique(c(flows_zcta$origin, flows_zcta$dest))
missing <- setdiff(used, locs_zcta$id)
if (length(missing) > 0)
  message("WARNING: ", length(missing), " ZCTAs in flows lack centroids (dropped in render)")
saveRDS(locs_zcta, "data/locations_zcta.rds")
message("ZCTA locations: ", nrow(locs_zcta))
cat("ZCTA DATA OK\n")
```

- [ ] **Step 3: Ensure prerequisite + run the fetch**

Run: `ls data/lodes_year.txt || ./run.sh scripts/01-fetch-data.R`
Then: `./run.sh scripts/01c-fetch-zcta-data.R`
Expected: downloads block-level OD + the crosswalk (and nationwide ZCTAs once, cached), prints a non-zero "ZCTA OD pairs" count (hundreds to low thousands), a "ZCTA locations" count, and `ZCTA DATA OK`. Creates `data/flows_zcta.rds` and `data/locations_zcta.rds`. (First run is slower — block-level OD is the full IN file; tigris pulls the national ZCTA CB file once.)

If `tigris::zctas(cb=TRUE, year=2020, starts_with=...)` errors, retry with `cb = FALSE` (full TIGER) and note it in the report.

- [ ] **Step 4: Sanity-check the outputs (temp script, not committed)**

Write `scripts/_check.R`:

```r
f <- readRDS("data/flows_zcta.rds"); l <- readRDS("data/locations_zcta.rds")
stopifnot(all(c("origin","dest","count") %in% names(f)))
stopifnot(all(c("id","lon","lat") %in% names(l)))
stopifnot(nrow(f) > 100, all(f$count > 0))
stopifnot(all(nchar(f$origin) == 5), all(nchar(f$dest) == 5))      # ZCTA5
stopifnot(all(nchar(l$id) == 5))
stopifnot(all(l$lon > -88 & l$lon < -85), all(l$lat > 38.5 & l$lat < 41))  # IN bbox
miss <- setdiff(unique(c(f$origin, f$dest)), l$id)
stopifnot("every flow ZCTA has a centroid" = length(miss) == 0)
cat("pairs:", nrow(f), "zctas:", nrow(l), "\nZCTA CHECK OK\n")
```

Run: `./run.sh scripts/_check.R` → expect `ZCTA CHECK OK`. Then `rm scripts/_check.R`.

- [ ] **Step 5: Commit**

```bash
git add R/zcta.R scripts/01c-fetch-zcta-data.R
git commit -m "Add ZCTA OD flow + centroid data path via LODES crosswalk"
```

---

### Task 2: Two-layer render + radio toggle

**Files:**
- Modify: `scripts/02-build-flowmap.R` (full rewrite below)

**Interfaces:**
- Consumes: `data/flows.rds`, `data/locations.rds`, `data/flows_zcta.rds`, `data/locations_zcta.rds`.
- Produces: `output/indy-commute-flows.html` with two flowmap layers (`indy-bg` default-visible, `indy-zcta` hidden) and a working Block group / ZIP code radio switch; preserves `window.__indyMap`.

- [ ] **Step 1: Rewrite `scripts/02-build-flowmap.R`**

```r
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
```

- [ ] **Step 2: Render**

Run: `./run.sh scripts/02-build-flowmap.R`
Expected: prints the BG/ZCTA flow+loc counts and `RENDER OK`; rewrites `output/indy-commute-flows.html`.

- [ ] **Step 3: Static checks on the HTML**

Run:
```bash
grep -c -- 'indy-bg' output/indy-commute-flows.html
grep -c -- 'indy-zcta' output/indy-commute-flows.html
grep -c -- 'indy-res' output/indy-commute-flows.html
grep -c -- 'MapGLFlowmapPlugin' output/indy-commute-flows.html
ls -lh output/indy-commute-flows.html
```
Expected: every grep returns a non-zero count (both layer ids, the radio name, and the plugin reference are embedded); the file is self-contained (a few MB).

- [ ] **Step 4: Headless toggle check (proves the switch flips layers)**

Write `scripts/_toggle-check.mjs` (host Node + existing Playwright; not committed):

```js
import { chromium } from 'playwright';
import { resolve } from 'node:path';
const HTML = 'file://' + resolve('output/indy-commute-flows.html');
const b = await chromium.launch({ args: ['--use-gl=egl','--enable-unsafe-swiftshader','--no-sandbox'] });
const p = await b.newPage({ viewport: { width: 1200, height: 800 } });
await p.goto(HTML, { waitUntil: 'networkidle' });
await p.waitForTimeout(5000);
const vis = () => p.evaluate(() => {
  const m = window.__indyMap, pl = window.MapGLFlowmapPlugin;
  if (!m || !pl) return { ready: false };
  return { ready: true,
           bg: pl.getVisibility(m, 'indy-bg'),
           zcta: pl.getVisibility(m, 'indy-zcta') };
});
const before = await vis();
// Flip to ZIP via the radio.
await p.evaluate(() => {
  const r = document.querySelector('input[name=\"indy-res\"][value=\"indy-zcta\"]');
  r.checked = true; r.dispatchEvent(new Event('change', { bubbles: true }));
});
await p.waitForTimeout(1500);
const after = await vis();
await b.close();
console.log('before', before, 'after', after);
const ok = before.ready && before.bg === 'visible' && before.zcta === 'none'
        && after.bg === 'none' && after.zcta === 'visible';
console.log(ok ? 'TOGGLE CHECK OK' : 'TOGGLE CHECK FAIL');
process.exit(ok ? 0 : 1);
```

Run: `node scripts/_toggle-check.mjs`
Expected: prints the before/after visibility objects and `TOGGLE CHECK OK` (block-group visible→hidden, ZCTA hidden→visible). Then `rm scripts/_toggle-check.mjs`.

If it prints `TOGGLE CHECK FAIL` with `ready:false`, the plugin/global wasn't found — increase the initial `waitForTimeout`, and if still failing, fall back to the spec's documented alternative (`add_layers_control(layers=list("Block group"="indy-bg","ZIP code"="indy-zcta"))` instead of the custom radio) and re-run this check adapted to click the control. Report whichever mechanism succeeded.

- [ ] **Step 5: Commit**

```bash
git add scripts/02-build-flowmap.R
git commit -m "Render two flowmap layers with block-group/ZIP resolution toggle"
```

---

### Task 3: README + finalize

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing new. Documents the toggle, the ZCTA data path/caveats, and the new rebuild step.

- [ ] **Step 1: Add a "Resolution toggle (block group ↔ ZIP/ZCTA)" section to `README.md`**

Read the current `README.md`, then insert a new section after the existing "Outputs"/rebuild content. The section must contain exactly this content (adjust surrounding markdown to fit the file's style):

```markdown
## Resolution toggle: block group ↔ ZIP / ZCTA

The interactive map has a **Resolution** radio (top-right): switch between
block-group flows and ZIP-code flows in place (one layer shown at a time).

**"ZIP" means ZCTA.** LODES has no native ZIP geography — its OD data is at
census blocks. "ZIP code" here is the Census **ZCTA** (ZIP Code Tabulation
Area), reached by aggregating block-level OD through the LODES block→ZCTA
crosswalk (`lehdr::grab_crosswalk`, `tabblk2020 → zcta`). USPS ZIPs are mail
routes, not polygons; ZCTA is the mappable approximation. ZCTA flows are
coarser (hundreds of nodes vs ~1,500 block groups), so they are sparser and
need no clustering, and LODES block-level fuzzing largely cancels out.

The ZIP/ZCTA region uses the **same 15 counties**, expressed as the set of
ZCTAs whose blocks fall in those counties (a ZCTA straddling the boundary is
included if any of its blocks are in-region).

### Rebuild with the toggle
```bash
./run.sh scripts/01-fetch-data.R        # block-group OD (writes data/lodes_year.txt)
./run.sh scripts/01b-build-locations.R  # block-group centroids
./run.sh scripts/01c-fetch-zcta-data.R  # ZCTA OD + centroids (block-level OD + crosswalk)
./run.sh scripts/02-build-flowmap.R     # two-layer HTML with the resolution toggle
```
```

- [ ] **Step 2: Verify README mentions the new script and the toggle**

Run: `grep -c -E 'ZCTA|01c-fetch-zcta|Resolution' README.md`
Expected: non-zero (the section, the script, and the toggle are documented).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the block-group/ZIP resolution toggle and ZCTA data path"
```

---

## Self-Review

**Spec coverage:** ZCTA data path (crosswalk join, region-as-ZCTAs, centroids) → Task 1; two-layer render + custom radio toggle preserving `window.__indyMap` → Task 2; README toggle section + ZCTA caveats + rebuild step → Task 3. Block-group pipeline and capture scripts left unchanged (per spec). Fallback to `add_layers_control` is captured in Task 2 Step 4. All spec sections mapped.

**Placeholder scan:** No TBD/TODO. All code blocks are concrete. The two adaptation points (tigris `cb=FALSE` fallback; `add_layers_control` fallback) are explicit fallbacks with exact values, not placeholders.

**Type consistency:** `flows*`=`origin,dest,count` and `locations*`=`id,lon,lat` used identically across Tasks 1–2; layer ids `indy-bg`/`indy-zcta` and radio `name=indy-res` consistent between the render (Task 2 Step 1) and the toggle check (Task 2 Step 4); crosswalk columns `tabblk2020`/`zcta`/`cty` and tigris `ZCTA5CE20` consistent with the spec; `build_zcta_flows`/`build_zcta_locations` signatures match their callers.
