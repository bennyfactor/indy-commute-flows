# Census Block Resolution (Third Toggle Option) — Design Spec

**Date:** 2026-06-23
**Status:** Approved (brainstorming)
**Branch:** `census-block` (repo bennyfactor/indy-commute-flows)

## Goal

Add **Census block** as a third resolution on the existing toggle, alongside Block group
and ZIP/ZCTA. Census block is the most granular unit LODES is built from. Because block-to-
block LODES is heavily noise-infused, the layer is thresholded to **commuter count ≥ 3**
(this drops ~873k of the region's 947k OD pairs, almost all of them `count == 1` fuzzing
noise) — so it shows the strongest block-to-block corridors, embedded like the other layers
(no lazy-loading).

## Measured feasibility (LODES 2023, 15-county region)

- Total region blocks: 49,496; OD pairs (both endpoints in region): 947,486; of which
  ~873k are `count == 1`.
- At **`count ≥ 3`**: **19,822 OD pairs / 7,992 distinct blocks** — the chosen layer.
- Estimated page weight: current ~8.5 MB (bg+zcta) → **~20–23 MB** with the block layer.
  A build-time size guard steps the threshold up to `count ≥ 5` (~13 MB) if the real size
  is unreasonable (> ~40 MB).

## Components

### 1. Block data — `scripts/01e-fetch-block-data.R` (+ helpers in `R/blocks.R`)

- **Flows:** `grab_lodes(state="in", year=<data/lodes_year.txt>, lodes_type="od",
  agg_geo="block", state_part="main", segment="S000", job_type="JT00", version="LODES8")`.
  Keep OD pairs where **both** `h_geocode` and `w_geocode` are in the 15 counties (county =
  first 5 chars of the 15-digit block id, in `region_counties()`), drop self-loops, keep
  **`count (S000) ≥ 3`**. → `data/flows_block.rds`, columns `origin, dest, count` (15-digit
  block ids). Threshold is a named constant `BLOCK_MIN_COUNT <- 3`.
- **Geometry:** `tigris::blocks(state="18", county=<3-digit codes>, year=2020,
  progress_bar=FALSE)` (2020 blocks match LODES8). Block id column is `GEOID20`.
  - Centroids (`st_point_on_surface`, EPSG:4326) filtered to ids present in the flows →
    `data/locations_block.rds`, columns `id, lon, lat`.
  - Simplified polygons (`st_simplify(preserveTopology=TRUE, dTolerance=0.0004)`, EPSG:4326)
    filtered to ids present in the flows → `data/polys_block.rds`, columns `id` + geometry.
- Every block id in the flows must have a centroid and a polygon (the render contract).

### 2. Render — `scripts/02-build-flowmap.R`

- Load the three new files. Apply the validity filter (`origin`/`dest` in
  `locations_block$id`) and the existing 40k cap (already a no-op at `count ≥ 3`).
- Add a third `add_flowmap(id="indy-block", visibility="none", …)` (same Teal/animated/
  clustering settings as the others).
- Add `add_source("poly-block", polys_block)`, `add_line_layer("outline-block",
  source="poly-block", line_color="#FFFFFF", line_width=2, filter=empty)`,
  `add_circle_layer("hits-block", source=<block centroids sf>, circle_opacity=0,
  circle_radius=8)`.
- Add a `block` entry to the `onRender` payload via `make_payload(flows_block,
  locs_block)`.

### 3. Interaction JS — `R/interaction_js.R`

Generalize from two resolutions to N:
- `RES` gains `block: { flow:'indy-block', hits:'hits-block', outline:'outline-block',
  inbound:'inbound-block', outbound:'outbound-block' }`.
- Replace the hardcoded `['bg','zcta'].forEach(...)` loops (in `clear`,
  `ensureHighlightLayers`, `setNativeVisibility`, `wire`) with iteration over
  `Object.keys(RES)`. `applyFlow(chosen)` iterates the `RES[*].flow` ids instead of the
  literal `['indy-bg','indy-zcta']`.
- `init()` builds `idx[r]` for every payload resolution present (`data.bg`, `data.zcta`,
  `data.block`).
- The radio gains a third option **"Census block"** (value `block`).
- All existing behavior (hover-preview, click-pin, deck dim, white outline, two-color
  in/out flows, top-3/top-3 partner labels) works identically for `block`. Block labels show
  the count only — the ZIP prefix stays gated on `active === 'zcta'`.

### 4. Size guard

The render/build step prints the resulting `output/indy-commute-flows.html` size. If it
exceeds ~40 MB, raise `BLOCK_MIN_COUNT` to 5, rebuild, and flag the change before deploying.

## Files

- **New:** `R/blocks.R`, `scripts/01e-fetch-block-data.R`.
- **Modify:** `scripts/02-build-flowmap.R` (third flowmap + native layers + payload),
  `R/interaction_js.R` (generalize to 3 resolutions + radio option), `README.md`.
- **Unchanged:** the bg/zcta fetch + polygon scripts, `R/regions.R`, capture/deploy scripts.

## Verification

Headless Playwright (existing approach):
1. Build + render succeeds; HTML embeds `indy-block`, `hits-block`, `outline-block`,
   `inbound-block`/`outbound-block`, and the "Census block" radio option. Report the size.
2. Select Census block; hover a block node → `inbound-block`/`outbound-block` populate and
   the deck dims; the outline filter targets that block id.
3. Click-pin → ≤6 partner labels (count-only text, no ZIP prefix); Esc clears.
4. Block group and ZIP/ZCTA still hover/pin/label correctly (no regression from the
   2→3 generalization).

## Risks / Notes

- **Noise:** block-level LODES is synthetic/noise-infused; the `count ≥ 3` floor is
  deliberate. Document that this layer shows strong corridors, not every commuter.
- **`tigris::blocks()`** downloads all ~49k region blocks (cached); we keep only the ~8k in
  the flows. First run is slower.
- **Size:** the size guard is the safety valve; we bail/raise the threshold rather than ship
  a sluggish page.

## Success Criteria

1. A third "Census block" toggle option renders ~19.8k strongest block-to-block flows with
   the full hover/pin/outline/two-color/label interaction.
2. The page size is reasonable (target ~20–23 MB; guard raises the threshold otherwise).
3. Block group, ZIP/ZCTA, video, and deploy still work.
4. README documents the new resolution and the noise/threshold caveat; the live site updates.
