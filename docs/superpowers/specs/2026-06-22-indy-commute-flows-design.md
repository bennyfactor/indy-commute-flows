# Central Indiana Animated Commute Flow Map — Design Spec

**Date:** 2026-06-22
**Status:** Approved (brainstorming)

## Goal

Reproduce, for central Indiana, the kind of visualization Kyle Walker posted for
Dallas–Fort Worth: an **animated, hierarchical origin–destination commute flow map**
built with R's **mapgl 0.5.0** (`add_flowmap()`, powered by Flowmap.gl / deck.gl) over
**LODES** commute data. Downtowns, the medical district, the airport, and suburban job
hubs should "light up" as animated flows, with adaptive clustering revealing a hub
hierarchy as the viewer zooms.

Reference post: Kyle Walker (@kylewalker.bsky.social), implementation credit Egor Kotov
(@ekotov.pro), Flowmap.gl by Ilya Boyandin.

## Geography

15 Indiana counties (state FIPS `18`). Core Indianapolis–Carmel–Anderson MSA (11) plus
4 user-requested additions (Bloomington + Lafayette region):

| County | FIPS | County | FIPS | County | FIPS |
|---|---|---|---|---|---|
| Marion | 097 | Hancock | 059 | Brown | 013 |
| Hamilton | 057 | Morgan | 109 | Monroe | 105 |
| Hendricks | 063 | Shelby | 145 | Clinton | 023 |
| Boone | 011 | Madison | 095 | Tippecanoe | 157 |
| Johnson | 081 | Putnam | 133 | White | 181 |

**Resolution:** Census **block groups** (~1,500 across the 15 counties). Flowmap.gl's
adaptive clustering handles visual density.

## Data Pipeline (R)

1. **Determine newest LODES year** available for Indiana (LODES8 / 2020-block geography).
   Probe the LEHD index; LODES8 currently covers ~2002–2022. Use the newest year present
   for IN; fall back one year if the newest is missing. Record the chosen year.
2. **Fetch OD data:** `lehdr::grab_lodes(state="in", year=<newest>, lodes_type="od",
   agg_geo="bg", version="LODES8")`. Use `S000` (all jobs) as the flow `count`.
3. **Filter to region:** keep OD pairs where **both** the home block group and work block
   group lie in the 15 counties (intra-region commutes). Derive county from the first 5
   chars of the 12-digit BG GEOID.
4. **Threshold:** drop `count == 0`; rely on `flow_max_top_flows_display_num` + clustering
   for display. Optionally drop the long tail (e.g. `count < 2`) if widget size demands.
5. **Locations:** `tigris::block_groups()` for the 15 counties (year matching the data),
   compute centroids, reproject to EPSG:4326 → `id`, `lon`, `lat`. `id` must match the
   LODES BG GEOIDs used in `origin`/`dest`.
6. **Flows frame:** columns `origin`, `dest`, `count`.

## Render (mapgl >= 0.5.0)

```r
maplibre(style = carto_style("dark-matter"),
         center = c(-86.2, 39.9), zoom = 8, projection = "mercator") |>
  add_flowmap(
    id = "indy",
    locations = locs, flows = flows,
    flow_color_scheme = "Teal", flow_dark_mode = TRUE,
    flow_lines_rendering_mode = "animated-straight",
    flow_clustering_enabled = TRUE, flow_clustering_auto = TRUE,
    flow_adaptive_scales_enabled = TRUE
  )
```

- **Hierarchical** = flowmap.gl adaptive clustering (hubs emerge at different zooms).
- **Animated** = `animated-straight` flow lines.
- Output a **self-contained HTML** widget via `htmlwidgets::saveWidget(..., selfcontained=TRUE)`.

## Runtime

- **podman `rocker/geospatial`** image (R + sf + GDAL/GEOS/PROJ + tidyverse prebuilt).
  Install `mapgl`, `lehdr`, `tigris` inside. Repo bind-mounted; outputs written to host.
- **`renv.lock`** captures exact package versions for reproducibility.
- A `run.sh` wrapper runs the data + render scripts in the container.

## Video / GIF (best-effort)

- Headless **Chromium via Playwright** (Node 24 already installed) loads the HTML.
- **GPU acceleration via the Quadro P4000** (driver 575.57.08): launch Chromium with GPU
  flags (`--use-gl=egl`/ANGLE, `--enable-gpu`, `--ignore-gpu-blocklist`) so WebGL renders
  on the discrete GPU rather than software (`swiftshader`).
- Scripted **camera tour**: set zoom levels to trigger hierarchical clustering and `flyTo`
  between downtown / IUPUI medical district / IND airport / suburban hubs (Carmel,
  Fishers). Capture frames via CDP `Page.startScreencast`.
- **`ffmpeg`** (host) encodes frames → `.mp4` + `.gif`.
- Flagged best-effort: WebGL headless capture is finicky; the interactive HTML is the
  primary deliverable and must succeed regardless.

## Deliverables

```
indy-commute-flows/
  R/                       # reusable functions (regions, fetch, build)
  scripts/
    01-fetch-data.R        # determine year, grab_lodes, filter, save data/*.rds
    02-build-flowmap.R     # locations + flows -> output/indy-commute-flows.html
    03-capture-video.mjs   # Playwright tour -> frames -> ffmpeg mp4/gif
  data/                    # cached LODES + tigris pulls (gitignored if large)
  output/
    indy-commute-flows.html
    indy-commute-flows.mp4
    indy-commute-flows.gif
  Dockerfile / run.sh      # podman rocker/geospatial wrapper
  renv.lock
  README.md                # how to rebuild
  .gitignore
```

## Risks / Notes

- **LODES year:** 2023 may not be published for IN yet; pipeline picks newest available.
- **Widget size:** ~hundreds of thousands of OD pairs possible; threshold/clustering keep
  the HTML manageable. Monitor file size; tighten `count` threshold if needed.
- **GPU in container vs host:** video capture runs on the **host** (Node/Playwright +
  ffmpeg + Quadro), not in the rocker container, to avoid GPU passthrough complexity.
- **Non-contiguous counties:** Monroe and the Lafayette trio (Tippecanoe/Clinton/White)
  are detached from the Indy core; few intra-region flows bridge them — expected.

## Success Criteria

1. `output/indy-commute-flows.html` opens in a browser showing animated, clustered
   commute flows across the 15-county region, hubs visibly lighting up.
2. Zooming changes clustering (hierarchy visible).
3. Best-effort `.mp4`/`.gif` tour produced, or a clear note on why capture was deferred.
4. Repo rebuildable from scratch via `run.sh` + documented steps.
