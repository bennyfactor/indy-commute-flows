# Block-group ↔ ZIP/ZCTA Resolution Toggle — Design Spec

**Date:** 2026-06-23
**Status:** Approved (brainstorming)
**Branch:** `zcta-toggle` (same repo: bennyfactor/indy-commute-flows)

## Goal

Add a geographic-resolution switch to the existing central-Indiana commute flow map:
the rendered HTML widget gains a radio control that flips between the current
**block-group** flows and a new **ZIP / ZCTA** flow layer, in place, in one
self-contained file. The work is additive — the working block-group pipeline is
untouched.

## Domain Background (why ZCTA, not "ZIP")

LODES has **no native ZIP geography**. Its OD files are enumerated at 2020 Census
blocks; `lehdr::grab_lodes(agg_geo=...)` supports only block/bg/tract/county/state.
For areal mapping, "ZIP code" means **ZCTA** (ZIP Code Tabulation Area — the Census's
areal approximation of USPS ZIPs, built from block-plurality ZIP assignment). USPS
ZIPs are address/route collections, not polygons; a USPS ZIP may map to several ZCTAs
and PO-box-only ZIPs have no ZCTA. ZCTA is the correct, mappable unit.

ZCTA-level flows are also *cleaner*: central Indiana has hundreds of ZCTAs vs ~1,500
block groups, so far fewer OD pairs, no clustering needed, and LODES block-level
fuzzing largely cancels out under ZCTA aggregation.

## ZCTA Data Path

New script `scripts/01c-fetch-zcta-data.R` with helpers in `R/zcta.R`:

1. **Block-level OD** (raw blocks are required to join the crosswalk — `agg_geo="bg"`
   cannot be reused):
   ```r
   grab_lodes(state="in", year=<year>, lodes_type="od", agg_geo="block",
              state_part="main", segment="S000", job_type="JT00", version="LODES8")
   ```
   `<year>` is read from `data/lodes_year.txt` (the year the block-group pipeline chose;
   currently 2023) so both layers use the same vintage.
   Columns used: `w_geocode`, `h_geocode` (15-digit block FIPS), `S000` (jobs).

2. **Crosswalk:** `lehdr::grab_crosswalk("in")` → keep `tabblk2020`, `zcta`, `cty`.
   `tabblk2020` matches `h_geocode`/`w_geocode` directly (both 15-digit).

3. **Region as ZCTAs (same 15 counties):**
   `region_zctas = unique(zcta where cty ∈ region_counties())`, reusing
   `region_counties()` from `R/regions.R`. A ZCTA straddling the county boundary is
   included if any of its blocks fall in-region (documented behavior; the ZCTA analog of
   the block-group "both endpoints in region" rule).

4. **Aggregate:** join `h_geocode→h_zcta` and `w_geocode→w_zcta`; drop rows where either
   ZCTA is NA; keep pairs with both ZCTAs in `region_zctas`; `sum(S000)` grouped by
   `(h_zcta, w_zcta)`; drop `count == 0`. → `data/flows_zcta.rds`, columns
   `origin`, `dest`, `count` (same contract as the block-group `flows`).

5. **ZCTA centroids:**
   ```r
   tigris::zctas(cb=TRUE, year=2020, starts_with=c("46","47"))
   ```
   2020 vintage matches LODES8's 2020-block base. `starts_with` narrows the otherwise
   nationwide download to Indiana ZIP prefixes (tigris cannot filter ZCTAs by state for
   this vintage); `options(tigris_use_cache=TRUE)` avoids re-downloading. The ZCTA id
   column is `ZCTA5CE20`. Reproject to EPSG:4326, `st_point_on_surface`, keep only ZCTAs
   present in `data/flows_zcta.rds`. → `data/locations_zcta.rds`, columns `id`, `lon`,
   `lat` (same contract as block-group `locations`).

## Render — Two Layers + Radio Switch

Modify `scripts/02-build-flowmap.R` to load both datasets and emit two flowmap layers in
one widget:

```r
flows_bg   <- readRDS("data/flows.rds");      locs_bg   <- readRDS("data/locations.rds")
flows_zcta <- readRDS("data/flows_zcta.rds");  locs_zcta <- readRDS("data/locations_zcta.rds")
# (existing bg validity filter + top-40000 cap applies to the bg layer only)

m <- maplibre(style=carto_style("dark-matter"),
              center=c(-86.2,39.9), zoom=8, projection="mercator") |>
  add_flowmap(id="indy-bg",   locations=locs_bg,   flows=flows_bg,
              flow_color_scheme="Teal", flow_dark_mode=TRUE,
              flow_lines_rendering_mode="animated-straight",
              flow_clustering_enabled=TRUE, flow_clustering_auto=TRUE,
              flow_adaptive_scales_enabled=TRUE, visibility="visible") |>
  add_flowmap(id="indy-zcta", locations=locs_zcta, flows=flows_zcta,
              flow_color_scheme="Teal", flow_dark_mode=TRUE,
              flow_lines_rendering_mode="animated-straight",
              flow_clustering_enabled=TRUE, flow_clustering_auto=TRUE,
              flow_adaptive_scales_enabled=TRUE, visibility="none") |>
  htmlwidgets::onRender(TOGGLE_JS)
```

`TOGGLE_JS` (injected via onRender):
- Grabs the map (`el.map`, as the existing camera-tour onRender already does) and
  **preserves `window.__indyMap = el.map`** so video capture keeps working.
- Inserts a small top-right control with two radios: **Block group** (default) and
  **ZIP code**.
- On change, sets visibility for both ids so exactly one layer shows:
  `window.MapGLFlowmapPlugin.setVisibility(map, id, id===chosen ? "visible" : "none")`.
  Mutual exclusion means no shared-canvas blend conflict.
- Guards for plugin/map readiness (`map.once('idle', ...)` or a short retry) since
  onRender may fire around the flowmap plugin's init.

**Fallback (if the runtime plugin call proves unreliable):** `add_layers_control(layers=
list("Block group"="indy-bg","ZIP code"="indy-zcta"))` — confirmed flowmap-aware, but
checkbox-style (both could show at once; mitigate with identical `flow_blend`). The custom
radio is preferred for true switch semantics.

## Deliverables / Compatibility

- Same output file `output/indy-commute-flows.html`, now with the live switch.
- Block group remains the **default** layer → the existing `output/indy-commute-flows.mp4`
  / `.gif` camera tour stays valid and is **not** re-generated (interactive-only scope).
- `scripts/03-capture-video.mjs` / `capture.sh` unchanged; capture still tours the
  default (block-group) view via `window.__indyMap`.

## Files

- **New:** `R/zcta.R` (`build_zcta_flows()`, `build_zcta_locations()` helpers),
  `scripts/01c-fetch-zcta-data.R`.
- **Modify:** `scripts/02-build-flowmap.R` (two layers + toggle, preserve map exposure),
  `README.md` (toggle section, ZCTA caveats, new rebuild step).
- **Unchanged:** `R/regions.R`, `R/lodes.R`, `R/locations.R`, `scripts/01-fetch-data.R`,
  `scripts/01b-build-locations.R`, capture scripts, Dockerfile, run.sh.

## Risks / Notes

- **Block-level OD download** is larger than the bg pull (full IN OD file; lehdr caches
  it after first fetch — and it's the same underlying file the bg path already pulled).
- **`tigris::zctas()`** downloads nationwide ZCTAs then filters; `starts_with` + cache keep
  it manageable. If `cb=TRUE, year=2020` errors, fall back to `cb=FALSE` and note it.
- **Threshold:** ZCTA flows are sparse; default keeps `count>0`. If the widget is noisy, a
  small floor (e.g. `count>=10`) may be applied — decided during implementation, documented.
- **Toggle JS timing** is the main implementation risk; verify the switch actually flips
  layers (and that capture still works) before claiming done. Fallback noted above.

## Success Criteria

1. `output/indy-commute-flows.html` opens with a Block group / ZIP code radio; switching to
   ZIP shows the ZCTA flow layer and hides the block-group layer (and back), with exactly
   one layer visible at a time.
2. `data/flows_zcta.rds` and `data/locations_zcta.rds` build correctly (sane ZCTA counts,
   coords within Indiana, every flow endpoint has a centroid).
3. The existing block-group view, camera-tour video, and all prior scripts still work
   unchanged.
4. README documents the toggle, the ZCTA crosswalk method/caveats, and the rebuild step.
