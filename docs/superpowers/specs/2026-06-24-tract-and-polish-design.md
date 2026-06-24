# Census Tract Resolution + Toggle Reorder/Rename + Coarser Block Polygons — Design Spec

**Date:** 2026-06-24
**Status:** Approved (brainstorming)
**Branch:** `tract-and-polish` (repo bennyfactor/indy-commute-flows)

## Goal

Three related refinements to the resolution toggle:
1. **Add Census tract** as a fourth resolution (between ZIP/ZCTA and block group).
2. **Reorder** the toggle largest → smallest by area and **rename** "Block group" →
   "Census block group" (to match "Census block").
3. **Coarsen the block polygons** to trim page weight (the block-polygon GeoJSON is the
   single largest contributor at ~7 MB).

Census block group remains the default-shown layer (preserves the signature view and the
camera-tour video).

## Final toggle (largest → smallest area)

| Order | Label | key | value | default |
|---|---|---|---|---|
| 1 | ZIP code | zcta | `zcta` | |
| 2 | Census tract | tract | `tract` | |
| 3 | Census block group | bg | `bg` | **checked** |
| 4 | Census block | block | `block` | |

(`active` initializes to `bg`; the `bg` radio is `checked` even though it is listed third.)

## Components

### 1. Census tract data — `scripts/01f-fetch-tract-data.R` (+ helpers in `R/tracts.R`)

- **Flows:** `grab_lodes(state="in", year=<data/lodes_year.txt>, lodes_type="od",
  agg_geo="tract", state_part="main", segment="S000", job_type="JT00", version="LODES8")`
  yields `h_tract`/`w_tract` (11-digit tract GEOIDs) + `S000`. Keep OD pairs where **both**
  endpoints' county (first 5 chars) is in `region_counties()`, drop self-loops, keep
  `count > 0`. → `data/flows_tract.rds`, columns `origin, dest, count`.
- **Geometry:** `tigris::tracts(state="18", county=<3-digit codes>, year=<tg_year>,
  cb=TRUE, progress_bar=FALSE)` — tract id column `GEOID` (11-digit). Reproject to
  EPSG:4326.
  - Centroids (`st_point_on_surface`) filtered to flow tracts → `data/locations_tract.rds`
    (`id, lon, lat`).
  - Simplified polygons (`st_simplify(preserveTopology=TRUE, dTolerance=0.0004)`) filtered
    to flow tracts → `data/polys_tract.rds` (`id` + geometry, EPSG:4326).
- Every tract id in the flows must have a centroid and a polygon. Mirrors the block-group
  path (`R/locations.R` / `R/polygons.R`).

### 2. Coarser block polygons — `R/blocks.R`

In `build_block_polygons`, change `st_simplify(..., dTolerance = 0.0004)` →
`dTolerance = 0.0008`. Re-run `scripts/01e-fetch-block-data.R` to regenerate
`data/polys_block.rds` (≈ halves the ~7 MB block-polygon chunk; imperceptible on the thin
selected-boundary outline). No other block-path change.

### 3. Render — `scripts/02-build-flowmap.R`

Add the tract resolution alongside the existing three (the `fm()`, `cap_flows()`,
`make_payload()`, and `empty_filter` helpers already generalize):
- Load `data/flows_tract.rds`, `data/locations_tract.rds`, `data/polys_tract.rds`.
- `cap_flows(flows_tract, locs_tract$id, 'tract')`; `make_payload(...)` → `payload$tract`;
  `hits_tract <- st_as_sf(locs_tract, ...)`.
- `fm('indy-tract', locs_tract, flows_tract, 'none')`; `add_source('poly-tract', …)`;
  `add_line_layer('outline-tract', source='poly-tract', line_color='#FFFFFF',
  line_width=2, filter=empty_filter)`; `add_circle_layer('hits-tract', source=hits_tract,
  circle_opacity=0, circle_radius=12)`.

### 4. Interaction JS — `R/interaction_js.R`

- `RES` gains `tract: { flow:'indy-tract', hits:'hits-tract', outline:'outline-tract',
  inbound:'inbound-tract', outbound:'outbound-tract' }`. All per-resolution logic already
  iterates `KEYS = Object.keys(RES)`, so behavior generalizes automatically.
- `init()` builds `idx` for each present payload resolution (the existing
  `KEYS.forEach(... if (data[res]) ...)` already covers `tract`).
- **Radio rewrite:** four `<label>` rows in the order ZIP code / Census tract / Census
  block group / Census block, with values `zcta`/`tract`/`bg`/`block`; the `bg` input keeps
  `checked`. `active` still initializes to `bg`. The ZIP-prefix in labels stays gated on
  `active === 'zcta'` (tract labels show count only).

### 5. Docs + deploy

README: document the four resolutions, the `scripts/01f-fetch-tract-data.R` build step, and
the coarser-block note. Redeploy via `./scripts/deploy-pages.sh`. The build prints the HTML
size (expect ~27–28 MB: tract adds ~2–3 MB, block coarsening saves ~3 MB).

## Files

- **New:** `R/tracts.R`, `scripts/01f-fetch-tract-data.R`.
- **Modify:** `R/blocks.R` (block dTolerance), `scripts/02-build-flowmap.R` (4th layer +
  payload), `R/interaction_js.R` (RES.tract + reorder/rename radio), `README.md`.
- **Unchanged:** bg/zcta fetch + polygon scripts, `R/regions.R`, capture/deploy scripts.

## Verification

Headless Playwright:
1. Build + render succeeds; HTML embeds `indy-tract`/`hits-tract`/`outline-tract`/
   `inbound-tract`/`outbound-tract` and four radio options in order ZIP / tract / block
   group / block with the renamed "Census block group" label; the `bg` radio is `checked`.
   Report the HTML size.
2. Select Census tract → hover a tract node populates inbound/outbound lines + dims; pin
   adds ≤6 count-only labels; Esc clears.
3. Block group (default), ZIP/ZCTA, and Census block still hover/pin/label correctly (no
   regression); the block outline still renders (coarser geometry).

## Risks / Notes

- **`grab_lodes(agg_geo="tract")`** column names (`h_tract`/`w_tract`) verified during
  implementation; adapt if the installed lehdr differs.
- **tract polygon vintage:** use a `tigris::tracts()` year that yields 11-digit `GEOID`
  matching the LODES tract ids (2020-based; `tg_year <- min(lodes_year, 2023)` like the
  block-group path).
- **Default radio not topmost:** `bg` is checked while listed third — intentional, keeps the
  default view on block group.

## Success Criteria

1. Four resolutions, ordered largest → smallest, with "Census block group" / "Census block"
   labels; block group is the default-shown layer.
2. Census tract has the full hover/pin/outline/two-color/label interaction.
3. Block-polygon outline still looks right at the coarser tolerance; page size stays
   reasonable (~27–28 MB).
4. README updated; the live Pages site reflects all four resolutions.
