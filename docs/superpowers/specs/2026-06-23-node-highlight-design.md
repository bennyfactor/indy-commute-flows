# Node Hover/Click → Boundary + Two-Color In/Out Flow Highlight — Design Spec

**Date:** 2026-06-23
**Status:** Approved (brainstorming)
**Branch:** `node-highlight` (repo bennyfactor/indy-commute-flows)

## Goal

When a user hovers or clicks a node (a block-group or ZCTA centroid) in the interactive
map, (1) draw that area's boundary polygon, and (2) highlight the flows touching the node
in two colors — **inbound** (flows TO the node) in one color and **outbound** (flows FROM
the node) in another — both distinct from the base Teal flows. Works for both resolutions
(block group and ZIP/ZCTA). Additive: the base flow map and the resolution toggle are
unchanged.

## Behaviour

- **Trigger:** hover previews the highlight transiently; **click pins** it (the highlight
  stays while the cursor moves away); clicking empty space or pressing **Esc** clears the
  pin. While pinned, hover does not change the selection.
- **Base flows during focus:** the animated base flows **dim to a faint backdrop** so the
  two-color highlight reads clearly; they return to full strength when the selection clears.
- **Resolution switch:** switching the existing Block group / ZIP radio clears any
  selection and activates the corresponding node set.

## Key Findings (from research; drive the architecture)

- Flowmap.gl's built-in highlight is **single-color** and its runtime filter/settings
  setters are **Shiny-only** — so the two-color requirement must be a **custom** highlight
  we render ourselves.
- The robust node-pick path is a **native MapLibre circle layer** on the centroids; the
  Flowmap.gl deck overlay is `pointer-events:none`, so `map.on('mousemove'/'click', layer,
  …)` → `feature.properties.id` works.
- The Flowmap.gl deck overlay renders in its **own canvas above the MapLibre canvas**.
  Setting that canvas's **CSS opacity** dims the base flows wholesale (no Flowmap.gl
  internals), and simultaneously lets native highlight layers on the lower MapLibre canvas
  read clearly — solving dimming and z-order at once.

## Components

### 1. Polygon data — `scripts/01d-build-polygons.R` (+ helpers in `R/polygons.R`)

- Fetch block-group polygons (`tigris::block_groups`, same 15 counties, cached) and ZCTA
  polygons (`tigris::zctas(cb=TRUE, year=2020, starts_with=c("46","47"))`, cached) — the
  same pulls the centroid builders already use.
- **Simplify** with `sf::st_simplify(preserveTopology=TRUE, dTolerance=0.0004)` (~40 m) to
  keep embedded size down. Independent per-polygon simplification is acceptable because
  only one polygon is outlined at a time.
- Reproject to EPSG:4326; keep an `id` column (`GEOID` for bg, `ZCTA5CE20` for ZCTA);
  filter to the `id`s present in `data/locations.rds` / `data/locations_zcta.rds`.
- Save `data/polys_bg.rds` and `data/polys_zcta.rds` (sf, columns `id` + geometry).

### 2. Render additions — `scripts/02-build-flowmap.R` (+ JS in `R/interaction_js.R`)

For **each** resolution `r ∈ {bg, zcta}` (ids suffixed `-bg` / `-zcta`):
- **Hit layer:** a transparent `add_circle_layer` on the centroid points (`circle_opacity=0`,
  `circle_radius≈10`), carrying the `id` property — `hits-<r>`.
- **Polygon source + outline:** `add_source(poly-<r>, sf)` + `add_line_layer(outline-<r>,
  line_color="#FFFFFF", line_width=2)` with `filter = ["==",["get","id"],""]` (matches
  nothing initially).
- **Highlight layers:** two empty-GeoJSON line layers — `inbound-<r>` (`#FF4D6D`, rose) and
  `outbound-<r>` (`#FFD166`, gold) — `line_width` interpolated by a `count` property.

Visibility of the `-zcta` set starts `none`; the existing resolution radio shows the active
set and hides the other (and clears any selection). To keep `02-build-flowmap.R` readable,
the interaction JS lives in `R/interaction_js.R` (a string constant) and a small R helper
adds the per-resolution layers.

### 3. Interaction JS (extends the existing `onRender`)

- After the map is idle, read the active resolution's **flows + centroids from the embedded
  flowmap config** (`x.flowmaps[i]`, matched by layer id `indy-bg`/`indy-zcta`); build a
  per-resolution centroid lookup and an adjacency from the flows. (Fallback if the property
  names differ: pass `{bg,zcta}` flows+locs via `onRender(data=…)`.)
- On `mousemove` (when not pinned) and `click` over the active `hits-<r>` layer: get the
  node `id`; compute inbound LineStrings (`partner→node`) and outbound (`node→partner`) with
  a `count` property; `setData` `inbound-<r>` / `outbound-<r>`; `setFilter` `outline-<r>` to
  `["==",["get","id"], id]`; **dim the deck canvas** (`opacity≈0.18`).
- **Click** pins the current node (stops hover updates). Click on empty space or **Esc**
  clears: restore deck-canvas opacity to 1, set the two highlight sources to empty
  FeatureCollections, reset the outline filter, unpin.
- The deck canvas is found without relying on internals:
  `Array.from(map.getContainer().querySelectorAll('canvas')).find(c =>
  !c.classList.contains('maplibregl-canvas'))` (fallback `map._deckgl?.canvas`).
- Radio switch handler (existing) also clears the selection and points the interaction at
  the newly active resolution's layers.

### 4. Colors

Inbound **#FF4D6D** (rose), outbound **#FFD166** (gold), outline **#FFFFFF** (white),
against the **Teal** base on dark-matter — contrast-tested and colorblind-separable.

## Files

- **New:** `scripts/01d-build-polygons.R`, `R/polygons.R`, `R/interaction_js.R`.
- **Modify:** `scripts/02-build-flowmap.R` (add hit/outline/highlight layers + wire the
  interaction JS), `README.md` (document the interaction + the new build step).
- **Unchanged:** all fetch/centroid scripts, the resolution toggle, capture/deploy scripts.

## Verification

Headless Playwright (existing tooling):
1. Build succeeds; HTML embeds the new layer ids and the interaction JS.
2. Simulate `mousemove` at a known node's screen point (or invoke the handler with a known
   id): assert `outline-<r>` filter is set to that id, `inbound-<r>`/`outbound-<r>` sources
   contain the expected partner counts (cross-check against the flows data), and the deck
   canvas opacity is dimmed.
3. `click` pins (selection persists after a subsequent mousemove elsewhere); `Esc` clears
   (opacity restored, sources emptied, outline filter reset).
4. Works after switching to the ZIP resolution.

## Risks / Notes

- **Payload size:** simplified polygons add a few MB (total ~9–12 MB); fine for GitHub Pages
  (<100 MB/file). Tighten `dTolerance` if needed.
- **`x.flowmaps[i]` property names** are the one unverified assumption — verified during
  implementation; documented fallback is passing the data via `onRender(data=…)`.
- **Deploy:** after merge, redeploy the live page with `./scripts/deploy-pages.sh`.

## Success Criteria

1. Hovering a node (either resolution) draws its boundary and shows inbound vs outbound
   flows in two distinct colors over a dimmed base; moving off clears it.
2. Clicking pins the selection; Esc / empty-space click clears it.
3. Base map, animated flows, resolution toggle, video, and deploy all still work.
4. README documents the interaction; the live Pages site is updated.
