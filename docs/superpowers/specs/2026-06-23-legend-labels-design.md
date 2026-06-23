# Legend + Top-3 In / Top-3 Out Partner Labels — Design Spec

**Date:** 2026-06-23
**Status:** Approved (brainstorming)
**Branch:** `legend-labels` (repo bennyfactor/indy-commute-flows)

## Goal

Two additive touches to the node-highlight interaction:
1. An always-visible **legend** explaining the highlight colors (inbound rose, outbound
   gold, selected boundary white).
2. When a node is **pinned**, label its **top 3 inbound** and **top 3 outbound** partner
   nodes (up to 6 labels) with the commuter count, colored by direction.

Additive: the base map, resolution toggle, and existing hover/click/pin/dim behavior are
unchanged. Almost all work is in `R/interaction_js.R`.

## Components

### 1. Legend (always visible)

A small HTML overlay injected in `onRender`, positioned **top-left** (the resolution radio
is top-right; avoid overlap). Three rows, each a colored swatch + label:
- rose `#FF4D6D` — "inbound (to node)"
- gold `#FFD166` — "outbound (from node)"
- white `#FFFFFF` — "selected boundary"

Pure HTML/CSS, no data, present at all times. Dark translucent background to match the
existing controls.

### 2. Partner labels (pin-only)

A single MapLibre **symbol (text) layer** `partner-labels` backed by a GeoJSON source
`partner-labels` (empty initially), created once in the interaction JS (alongside the
highlight layers). On **pin** (click), build label point features and `setData`; on any
clear (Esc, empty-space click, unpin, resolution switch) set the source to empty. Labels
never appear on hover-preview.

**Selection:** from the active resolution's adjacency index (already built from the
`{ids,lon,lat,o,d,c}` payload), take the pinned node's inbound partners sorted by count
desc (top 3) and outbound partners sorted by count desc (top 3). A partner may appear in
both lists (one rose, one gold label).

**Feature per partner:** a Point at the partner's centroid (`ids[pos] → lon/lat`) with
properties:
- `label` — formatted commuter count with thousands separators (e.g. `1,234`); for the
  ZIP/ZCTA resolution, prefixed with the partner ZIP (e.g. `46032 · 1,234`).
- `dir` — `"in"` or `"out"`.

**Symbol layer paint/layout:**
- `text-field` = `["get","label"]`, `text-font` = `["Open Sans Bold"]` (confirmed present
  in the CARTO dark-matter glyphs), `text-size` ~12.
- `text-color` = `["match",["get","dir"],"in","#FF4D6D","out","#FFD166","#ffffff"]`.
- `text-halo-color` = `#101014`, `text-halo-width` ~1.4 (legibility on the dim base).
- `text-offset` by direction so a partner that is both a top inbound and top outbound gets
  two non-overlapping labels: `["match",["get","dir"],"in",["literal",[0,-0.9]],
  ["literal",[0,0.9]]]`; `text-allow-overlap` = `true` so all ≤6 always render.

The label layer renders on the MapLibre canvas, beneath the Flowmap.gl deck canvas. Since
pinning dims the deck to opacity 0.18, the labels (and the rose/gold lines and white
outline) read clearly.

## Files

- **Modify:** `R/interaction_js.R` — add the legend HTML; create the `partner-labels`
  source+symbol layer in `ensureHighlightLayers` (or a sibling); add a `setLabels(id)` /
  `clearLabels()` pair driven by the pin/clear paths; include `partner-labels` in the
  per-resolution visibility handling so it hides with the inactive set; `clearLabels()` on
  Esc/empty-click/resolution-switch.
- **Modify:** `README.md` — document the legend and the pin-only top-3/top-3 labels.
- **Unchanged:** `scripts/02-build-flowmap.R` (the existing payload suffices), all data
  scripts, capture/deploy scripts.

## Verification

Headless Playwright (existing tooling):
1. Build + render succeeds; HTML embeds the legend text ("inbound", "outbound",
   "selected boundary") and the `partner-labels` layer/source.
2. **Hover only** (no click): `partner-labels` source has **0** features (labels are
   pin-only).
3. **Click-pin** a node with flows: `partner-labels` has between 1 and 6 features; the
   `dir` split is ≤3 `"in"` and ≤3 `"out"`; the labelled partners and counts match the top
   inbound/outbound partners computed directly from the payload data.
4. **Esc** empties `partner-labels` (0 features); the legend remains in the DOM.
5. Works after switching to the ZIP/ZCTA resolution (labels use ZCTA partners; ZIP prefix
   present in the label text).

## Risks / Notes

- **Symbol glyphs** load from the CARTO dark-matter glyphs endpoint at runtime (same place
  the basemap labels come from); `Open Sans Bold` resolves there. No new runtime dependency
  beyond what the basemap already uses.
- **Label overlap** for partners appearing in both top-3 lists is handled by the directional
  `text-offset` + `text-allow-overlap`.
- Negligible payload/size impact (no new embedded data; labels computed in JS on pin).

## Success Criteria

1. A legend is always visible explaining inbound rose / outbound gold / selected boundary.
2. Pinning a node labels its top 3 inbound and top 3 outbound partners with direction-colored
   counts; hovering shows no labels; clearing removes them.
3. Base map, toggle, hover/click/pin/dim, video, and deploy all still work.
4. README documents the additions; the live Pages site is updated.
