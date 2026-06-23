# Central Indiana Commute Flow Map — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an animated, hierarchical origin–destination commute flow map of the 15-county central-Indiana region using R's mapgl 0.5.0 (`add_flowmap()` / Flowmap.gl) over the newest available LODES data, output as a self-contained HTML widget plus a best-effort GPU-rendered MP4/GIF.

**Architecture:** A podman `rocker/geospatial` container runs two R scripts: `01-fetch-data.R` (determine newest LODES year, download IN OD data, filter to the 15 counties, build block-group centroid locations, save `.rds`) and `02-build-flowmap.R` (assemble `locations`/`flows`, render `add_flowmap()`, save HTML). A host-side Node/Playwright script (`03-capture-video.mjs`) drives headless Chromium on the Quadro P4000 to screen-record a camera tour, encoded to MP4/GIF with host `ffmpeg`.

**Tech Stack:** R 4.x, mapgl ≥0.5.0, lehdr, tigris, sf, dplyr (rocker/geospatial); podman 4.6.1; Node 24 + Playwright; ffmpeg; NVIDIA Quadro P4000 (driver 575.57.08).

## Global Constraints

- Working dir: `/home/ben/projects/indy-commute-flows` (git repo, branch `main` OK — solo project).
- mapgl version floor: **≥ 0.5.0** (must expose `add_flowmap`). Verify before rendering.
- Region: 15 IN counties, FIPS-5 prefixes (state `18`): `18011 18013 18023 18057 18059 18063 18081 18095 18097 18105 18109 18133 18145 18157 18181`.
- LODES: `version="LODES8"`, `lodes_type="od"`, `state_part="main"`, `segment="S000"`, `job_type="JT00"`. Use the **newest year present for IN**; fall back to the next-newest if a download 404s.
- Flow data contract: `flows` = columns `origin, dest, count`; `locations` = columns `id, lon, lat`. Every `origin`/`dest` must have a matching `locations.id`.
- Container runs as the host user (`--userns=keep-id`) and bind-mounts the repo at `/work`; all outputs land under `output/` and `data/` on the host.
- Video capture is **best-effort**; the HTML widget is the required deliverable and must be produced regardless of capture success.
- Commit after each task.

---

### Task 1: Container environment + package install

**Files:**
- Create: `Dockerfile`
- Create: `run.sh`
- Create: `scripts/00-verify-env.R`

**Interfaces:**
- Produces: a runnable image tag `indy-flows:latest` containing R with `mapgl (>=0.5.0)`, `lehdr`, `tigris`, `sf`, `dplyr`, `htmlwidgets`. `run.sh <script.R>` executes an R script in the container with the repo mounted at `/work`.

- [ ] **Step 1: Write the Dockerfile**

```dockerfile
# Dockerfile
FROM rocker/geospatial:4.4.2
# rocker/geospatial already has sf, GDAL/GEOS/PROJ, tidyverse, htmlwidgets
RUN install2.r --error --skipinstalled \
      mapgl lehdr tigris \
 && rm -rf /tmp/downloaded_packages
```

- [ ] **Step 2: Write run.sh**

```bash
#!/usr/bin/env bash
# run.sh — execute an R script inside the indy-flows container with repo mounted
set -euo pipefail
SCRIPT="${1:?usage: run.sh scripts/NN-name.R}"
podman run --rm \
  --userns=keep-id \
  -v "$(pwd)":/work -w /work \
  -e HOME=/work \
  indy-flows:latest \
  Rscript "$SCRIPT"
```

- [ ] **Step 3: Write the env-verify script**

```r
# scripts/00-verify-env.R
pkgs <- c("mapgl","lehdr","tigris","sf","dplyr","htmlwidgets")
for (p in pkgs) {
  v <- as.character(packageVersion(p))
  cat(sprintf("%-12s %s\n", p, v))
}
stopifnot("mapgl >= 0.5.0 required" = packageVersion("mapgl") >= "0.5.0")
stopifnot("add_flowmap missing" = "add_flowmap" %in% getNamespaceExports("mapgl"))
cat("ENV OK\n")
```

- [ ] **Step 4: Build the image**

Run: `cd ~/projects/indy-commute-flows && chmod +x run.sh && podman build -t indy-flows:latest .`
Expected: build completes; final layer installs mapgl/lehdr/tigris without error. (First build pulls rocker/geospatial, several minutes.)

- [ ] **Step 5: Verify the environment**

Run: `./run.sh scripts/00-verify-env.R`
Expected: prints package versions with `mapgl` ≥ 0.5.0 and ends with `ENV OK`. If mapgl < 0.5.0, add `mapgl` from GitHub in the Dockerfile (`installGithub.r walkerke/mapgl`) and rebuild.

- [ ] **Step 6: Commit**

```bash
git add Dockerfile run.sh scripts/00-verify-env.R
git commit -m "Add podman rocker/geospatial env with mapgl/lehdr/tigris"
```

---

### Task 2: Region definition

**Files:**
- Create: `R/regions.R`

**Interfaces:**
- Produces: `region_counties()` → character vector of 15 FIPS-5 county codes; `in_region(geoid)` → logical, TRUE when a 12-digit BG GEOID's first 5 chars are in the region.

- [ ] **Step 1: Write the region module**

```r
# R/regions.R
# 15 central-Indiana counties (state FIPS 18). Indianapolis-Carmel-Anderson MSA (11)
# plus Monroe (Bloomington), Tippecanoe/Clinton/White (Lafayette area).
region_counties <- function() {
  c("18011", # Boone
    "18013", # Brown
    "18023", # Clinton
    "18057", # Hamilton
    "18059", # Hancock
    "18063", # Hendricks
    "18081", # Johnson
    "18095", # Madison
    "18097", # Marion (Indianapolis)
    "18105", # Monroe (Bloomington)
    "18109", # Morgan
    "18133", # Putnam
    "18145", # Shelby
    "18157", # Tippecanoe (Lafayette)
    "18181") # White
}

in_region <- function(geoid) {
  substr(geoid, 1, 5) %in% region_counties()
}
```

- [ ] **Step 2: Verify it loads and counts correctly**

Run:
```bash
./run.sh /dev/stdin <<'EOF'
source("R/regions.R")
stopifnot(length(region_counties()) == 15)
stopifnot(all(nchar(region_counties()) == 5))
stopifnot(in_region("180970012001"))   # Marion BG -> TRUE
stopifnot(!in_region("180030001001"))  # Allen County -> FALSE
cat("REGIONS OK\n")
EOF
```
Expected: prints `REGIONS OK`. (Note: `run.sh` passes `$1` to Rscript; `/dev/stdin` + heredoc runs inline R.)

- [ ] **Step 3: Commit**

```bash
git add R/regions.R
git commit -m "Add 15-county central Indiana region definition"
```

---

### Task 3: Fetch + filter LODES OD data

**Files:**
- Create: `scripts/01-fetch-data.R`
- Create: `R/lodes.R`

**Interfaces:**
- Consumes: `region_counties()`, `in_region()` from `R/regions.R`.
- Produces: `data/flows.rds` — a data frame with columns `origin` (chr, 12-digit BG GEOID), `dest` (chr), `count` (num, S000 jobs). `data/lodes_year.txt` — the chosen year. Helper `newest_lodes_year(state)` in `R/lodes.R` → integer year that successfully downloads.

- [ ] **Step 1: Write the year-probe helper**

```r
# R/lodes.R
suppressMessages(library(lehdr))
# Try candidate years newest-first; return the first that downloads without error.
newest_lodes_year <- function(state = "in", candidates = 2024:2018) {
  for (y in candidates) {
    ok <- tryCatch({
      suppressWarnings(suppressMessages(
        grab_lodes(state = state, year = y, lodes_type = "od",
                   job_type = "JT00", segment = "S000",
                   state_part = "main", agg_geo = "bg", version = "LODES8")
      ))
      TRUE
    }, error = function(e) FALSE)
    if (ok) return(y)
    message(sprintf("LODES %d not available for %s, trying older...", y, state))
  }
  stop("No LODES year available for ", state)
}
```

- [ ] **Step 2: Write the fetch script**

```r
# scripts/01-fetch-data.R
suppressMessages({library(lehdr); library(dplyr)})
source("R/regions.R"); source("R/lodes.R")

dir.create("data", showWarnings = FALSE)
year <- newest_lodes_year("in")
message("Using LODES year: ", year)
writeLines(as.character(year), "data/lodes_year.txt")

od <- grab_lodes(state = "in", year = year, lodes_type = "od",
                 job_type = "JT00", segment = "S000",
                 state_part = "main", agg_geo = "bg", version = "LODES8")

# grab_lodes(agg_geo="bg") yields h_bg / w_bg (12-digit) and S000.
flows <- od |>
  transmute(origin = as.character(h_bg),
            dest   = as.character(w_bg),
            count  = as.numeric(S000)) |>
  filter(in_region(origin), in_region(dest), count > 0)

message("Region OD pairs: ", nrow(flows),
        " | total commuters: ", format(sum(flows$count), big.mark=","))
saveRDS(flows, "data/flows.rds")
cat("FETCH OK\n")
```

- [ ] **Step 3: Run the fetch**

Run: `./run.sh scripts/01-fetch-data.R`
Expected: prints the chosen year, a non-zero OD pair count (tens of thousands expected), and `FETCH OK`. Creates `data/flows.rds` and `data/lodes_year.txt`.

- [ ] **Step 4: Sanity-check the output**

Run:
```bash
./run.sh /dev/stdin <<'EOF'
f <- readRDS("data/flows.rds")
stopifnot(all(c("origin","dest","count") %in% names(f)))
stopifnot(nrow(f) > 1000, all(f$count > 0))
stopifnot(all(nchar(f$origin) == 12), all(nchar(f$dest) == 12))
cat("rows:", nrow(f), "max count:", max(f$count), "\n"); cat("FLOWS OK\n")
EOF
```
Expected: `FLOWS OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/01-fetch-data.R R/lodes.R
git commit -m "Fetch + filter newest LODES OD data to 15-county region"
```

---

### Task 4: Build block-group centroid locations

**Files:**
- Create: `scripts/01b-build-locations.R`
- Create: `R/locations.R`

**Interfaces:**
- Consumes: `region_counties()`; `data/lodes_year.txt`; `data/flows.rds`.
- Produces: `data/locations.rds` — data frame `id` (chr 12-digit BG GEOID), `lon` (num), `lat` (num) in EPSG:4326, covering every BG referenced in `flows`.

- [ ] **Step 1: Write the locations helper**

```r
# R/locations.R
suppressMessages({library(tigris); library(sf); library(dplyr)})
options(tigris_use_cache = TRUE)

# Block-group centroids (lon/lat, EPSG:4326) for the region's counties.
build_locations <- function(counties, year) {
  county_fips <- substr(counties, 3, 5)        # "18097" -> "097"
  bg <- tigris::block_groups(state = "18", county = county_fips,
                             year = year, cb = TRUE, progress_bar = FALSE)
  bg <- sf::st_transform(bg, 4326)
  cent <- suppressWarnings(sf::st_point_on_surface(sf::st_geometry(bg)))
  xy <- sf::st_coordinates(cent)
  data.frame(id = as.character(bg$GEOID),
             lon = xy[, 1], lat = xy[, 2],
             stringsAsFactors = FALSE)
}
```

- [ ] **Step 2: Write the build-locations script**

```r
# scripts/01b-build-locations.R
suppressMessages({library(dplyr)})
source("R/regions.R"); source("R/locations.R")

# tigris block_groups supports years up to ~ (current-1); clamp if needed.
lodes_year <- as.integer(readLines("data/lodes_year.txt"))
tg_year <- min(lodes_year, 2023L)   # adjust down if tigris lacks the year

locs <- build_locations(region_counties(), tg_year)

# Keep only BGs actually referenced in flows; warn on any missing centroids.
flows <- readRDS("data/flows.rds")
used <- unique(c(flows$origin, flows$dest))
missing <- setdiff(used, locs$id)
if (length(missing) > 0)
  message("WARNING: ", length(missing), " referenced BGs lack centroids (will be dropped in render)")
locs <- locs |> filter(id %in% used)

saveRDS(locs, "data/locations.rds")
message("Locations: ", nrow(locs))
cat("LOCATIONS OK\n")
```

- [ ] **Step 3: Run it**

Run: `./run.sh scripts/01b-build-locations.R`
Expected: prints a location count (~1,000–1,800) and `LOCATIONS OK`. If `block_groups` errors on `tg_year`, lower `tg_year` (e.g. 2022) and rerun.

- [ ] **Step 4: Sanity-check coordinates**

Run:
```bash
./run.sh /dev/stdin <<'EOF'
l <- readRDS("data/locations.rds")
stopifnot(all(c("id","lon","lat") %in% names(l)))
stopifnot(all(nchar(l$id) == 12))
stopifnot(all(l$lon > -88 & l$lon < -85), all(l$lat > 38.5 & l$lat < 41))  # IN bbox
cat("locations:", nrow(l), "\n"); cat("COORDS OK\n")
EOF
```
Expected: `COORDS OK` (coordinates fall within Indiana's bounding box).

- [ ] **Step 5: Commit**

```bash
git add scripts/01b-build-locations.R R/locations.R
git commit -m "Build block-group centroid locations for region"
```

---

### Task 5: Render the animated flow map (HTML)

**Files:**
- Create: `scripts/02-build-flowmap.R`

**Interfaces:**
- Consumes: `data/flows.rds`, `data/locations.rds`.
- Produces: `output/indy-commute-flows.html` — self-contained mapgl/Flowmap.gl widget.

- [ ] **Step 1: Write the render script**

```r
# scripts/02-build-flowmap.R
suppressMessages({library(mapgl); library(dplyr); library(htmlwidgets)})

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
  )

dir.create("output", showWarnings = FALSE)
htmlwidgets::saveWidget(m, "output/indy-commute-flows.html",
                        selfcontained = TRUE, title = "Central Indiana Commute Flows")
cat("RENDER OK\n")
```

- [ ] **Step 2: Run the render**

Run: `./run.sh scripts/02-build-flowmap.R`
Expected: prints flow/location counts and `RENDER OK`; creates `output/indy-commute-flows.html`.

- [ ] **Step 3: Verify the HTML**

Run:
```bash
ls -lh output/indy-commute-flows.html
grep -c -iE 'flowmap|deck|maplibre' output/indy-commute-flows.html
```
Expected: file exists (likely 1–10 MB self-contained); grep returns a non-zero count (Flowmap.gl/MapLibre assets embedded). Optionally open via Tailscale/copy to Mac to confirm animated flows render and clustering changes with zoom.

- [ ] **Step 4: Commit**

```bash
git add scripts/02-build-flowmap.R
git commit -m "Render animated hierarchical flow map to self-contained HTML"
```

---

### Task 6: Best-effort GPU video/GIF capture

**Files:**
- Create: `scripts/03-capture-video.mjs`
- Create: `scripts/capture.sh`
- Create: `package.json`

**Interfaces:**
- Consumes: `output/indy-commute-flows.html`.
- Produces: `output/frames/frame-*.png`, `output/indy-commute-flows.mp4`, `output/indy-commute-flows.gif`. Runs on the **host** (not the container) to use the Quadro P4000 + host ffmpeg.

- [ ] **Step 1: Create package.json and install Playwright (host)**

```json
{
  "name": "indy-commute-flows-capture",
  "version": "1.0.0",
  "type": "module",
  "private": true,
  "dependencies": { "playwright": "^1.48.0" }
}
```

Run: `cd ~/projects/indy-commute-flows && npm install && npx playwright install chromium`
Expected: Playwright + a Chromium build installed.

- [ ] **Step 2: Write the capture script**

```js
// scripts/03-capture-video.mjs
// Headless Chromium on the Quadro P4000: load the widget, run a slow zoom/pan
// "tour", capture frames via CDP screencast. Best-effort.
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const HTML = 'file://' + resolve('output/indy-commute-flows.html');
const OUT = resolve('output/frames');
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({
  headless: true,
  args: [
    '--use-gl=egl', '--enable-gpu', '--ignore-gpu-blocklist',
    '--enable-features=Vulkan', '--no-sandbox',
    '--window-size=1600,900',
  ],
});
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
await page.goto(HTML, { waitUntil: 'networkidle' });
await page.waitForTimeout(6000); // let WebGL + flows initialize

// Try to grab the MapLibre map instance the widget created, for a camera tour.
await page.evaluate(() => {
  window.__indyMap = null;
  try {
    // mapgl/maplibre htmlwidget keeps the map on the widget element.
    const el = document.querySelector('.maplibregl-map') || document.querySelector('.mapboxgl-map');
    if (el && el._maplibregl_map) window.__indyMap = el._maplibregl_map;
    // Fallback: scan for any object exposing flyTo on the global widget registry.
    if (!window.__indyMap && window.HTMLWidgets) {
      for (const inst of (window.HTMLWidgets.findAll ? window.HTMLWidgets.findAll('.maplibregl-map') : [])) {
        if (inst && inst.flyTo) { window.__indyMap = inst; break; }
      }
    }
  } catch (e) {}
});

// Camera tour waypoints (hubs). flyTo is best-effort; if no map handle, we just
// record the default animated view.
const tour = [
  { center: [-86.158, 39.768], zoom: 11.5, name: 'downtown' },     // Mile Square
  { center: [-86.176, 39.776], zoom: 12.5, name: 'medical-iupui' },// IU Health / IUPUI
  { center: [-86.295, 39.717], zoom: 12.0, name: 'airport-IND' },  // IND airport
  { center: [-86.118, 39.978], zoom: 11.0, name: 'carmel-fishers' },// north suburbs
  { center: [-86.20, 39.90],   zoom: 8.5,  name: 'region' },       // pull back
];

const cdp = await page.context().newCDPSession(page);
let n = 0;
const grab = async () => {
  const buf = await page.screenshot({ type: 'png' });
  writeFileSync(`${OUT}/frame-${String(n++).padStart(4,'0')}.png`, buf);
};

for (const wp of tour) {
  await page.evaluate(({center, zoom}) => {
    if (window.__indyMap && window.__indyMap.flyTo)
      window.__indyMap.flyTo({ center, zoom, duration: 3000 });
  }, wp);
  // ~3s of flight + dwell, sampling ~10 fps
  for (let i = 0; i < 50; i++) { await grab(); await page.waitForTimeout(100); }
}

await browser.close();
console.log(`CAPTURED ${n} frames`);
```

- [ ] **Step 3: Write the encode wrapper**

```bash
#!/usr/bin/env bash
# scripts/capture.sh — run the headless tour, then encode mp4 + gif.
set -euo pipefail
node scripts/03-capture-video.mjs
FR=output/frames
ffmpeg -y -framerate 10 -pattern_type glob -i "$FR/frame-*.png" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
  output/indy-commute-flows.mp4
# GIF via palette for quality
ffmpeg -y -framerate 10 -pattern_type glob -i "$FR/frame-*.png" \
  -vf "fps=10,scale=900:-1:flags=lanczos,palettegen" /tmp/indy-pal.png
ffmpeg -y -framerate 10 -pattern_type glob -i "$FR/frame-*.png" -i /tmp/indy-pal.png \
  -lavfi "fps=10,scale=900:-1:flags=lanczos[x];[x][1:v]paletteuse" \
  output/indy-commute-flows.gif
echo "ENCODE OK"
```

- [ ] **Step 4: Confirm the GPU is usable by headless Chromium**

Run:
```bash
nvidia-smi --query-gpu=name,utilization.gpu,memory.used --format=csv,noheader
node -e "const {chromium}=require('playwright');(async()=>{const b=await chromium.launch({args:['--use-gl=egl','--enable-gpu','--ignore-gpu-blocklist','--no-sandbox']});const p=await b.newPage();await p.goto('chrome://gpu');const t=await p.content();console.log(/WebGL.*Hardware accelerated/i.test(t)?'GPU: hardware accelerated':'GPU: software (swiftshader) — capture still works, slower');await b.close();})()" 2>/dev/null || echo "gpu probe inconclusive — proceed best-effort"
```
Expected: ideally "hardware accelerated"; if software, proceed anyway (capture still works).

- [ ] **Step 5: Run capture + encode**

Run: `chmod +x scripts/capture.sh && ./scripts/capture.sh`
Expected: frames written, then `ENCODE OK`; `output/indy-commute-flows.mp4` and `.gif` exist. If frames are black/empty (WebGL didn't render headlessly), record the failure in README's "Known issues" and keep the HTML as the deliverable — do not block.

- [ ] **Step 6: Verify outputs**

Run: `ls -lh output/indy-commute-flows.mp4 output/indy-commute-flows.gif && ffprobe -v error -show_entries format=duration -of csv=p=0 output/indy-commute-flows.mp4`
Expected: both files non-empty; mp4 duration ~15s.

- [ ] **Step 7: Commit**

```bash
git add package.json scripts/03-capture-video.mjs scripts/capture.sh
git commit -m "Add best-effort GPU headless video/GIF capture"
```

---

### Task 7: renv lockfile, README, finalize

**Files:**
- Create: `scripts/99-renv-snapshot.R`
- Create: `README.md`
- Modify: `.gitignore` (already present from spec commit)

**Interfaces:**
- Produces: `renv.lock`; `README.md` documenting full rebuild.

- [ ] **Step 1: Write the renv snapshot script**

```r
# scripts/99-renv-snapshot.R
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
renv::snapshot(packages = c("mapgl","lehdr","tigris","sf","dplyr","htmlwidgets","renv"),
               prompt = FALSE, lockfile = "renv.lock")
cat("SNAPSHOT OK\n")
```

- [ ] **Step 2: Generate the lockfile**

Run: `./run.sh scripts/99-renv-snapshot.R`
Expected: `renv.lock` created listing mapgl (≥0.5.0) and deps; prints `SNAPSHOT OK`.

- [ ] **Step 3: Write the README**

```markdown
# Central Indiana Commute Flow Map

Animated, hierarchical origin–destination commute flows for the 15-county
central-Indiana region (Indianapolis MSA + Bloomington + Lafayette area),
built with R's [mapgl](https://walker-data.com/mapgl/) 0.5.0 `add_flowmap()`
(Flowmap.gl / deck.gl) over the newest available LODES commute data.

Inspired by Kyle Walker's Dallas–Fort Worth flow map; implementation pattern
credit to Egor Kotov; Flowmap.gl by Ilya Boyandin.

## Outputs
- `output/indy-commute-flows.html` — interactive, self-contained widget.
- `output/indy-commute-flows.mp4` / `.gif` — best-effort camera-tour recording.

## Rebuild
```bash
podman build -t indy-flows:latest .   # R + spatial stack + mapgl/lehdr/tigris
./run.sh scripts/00-verify-env.R      # confirm mapgl >= 0.5.0
./run.sh scripts/01-fetch-data.R      # newest LODES OD -> data/flows.rds
./run.sh scripts/01b-build-locations.R# block-group centroids -> data/locations.rds
./run.sh scripts/02-build-flowmap.R   # -> output/indy-commute-flows.html
./scripts/capture.sh                  # best-effort -> mp4/gif (host + Quadro P4000)
```

## Region
15 IN counties: Marion, Hamilton, Hendricks, Boone, Johnson, Hancock, Morgan,
Shelby, Madison, Putnam, Brown, Monroe, Clinton, Tippecanoe, White.

## Data
LODES8 OD (`state_part=main`, `JT00`, `S000`), newest year available for IN
(see `data/lodes_year.txt`). Endpoints at census block-group resolution.

## Known issues
- Headless WebGL capture can fail on some driver/Chromium combos; if so the
  HTML remains the primary deliverable. (Note actual outcome here after first run.)
```

- [ ] **Step 4: Commit**

```bash
git add scripts/99-renv-snapshot.R renv.lock README.md
git commit -m "Add renv lockfile and README; finalize project"
```

---

## Self-Review

**Spec coverage:** Geography (15 counties) → Task 2; newest-LODES fetch + region filter → Task 3; block-group locations → Task 4; mapgl `add_flowmap` render → Task 5; podman rocker runtime → Task 1; GPU video/GIF → Task 6; renv + README deliverables → Task 7. All spec sections mapped.

**Placeholder scan:** No TBD/TODO; all code blocks are concrete and runnable. The one deliberate adaptation point (lower `tg_year`/`MAX_FLOWS` if a download or size limit hits) is an explicit fallback with a value, not a placeholder.

**Type consistency:** `flows` = `origin,dest,count` and `locations` = `id,lon,lat` used identically in Tasks 3–6; `region_counties()`/`in_region()` signatures consistent between Tasks 2–4; `run.sh <script>` usage consistent throughout.
