# Central Indiana Commute Flow Map

Animated, hierarchical origin–destination commute flows for the 15-county
central-Indiana region (Indianapolis MSA + Bloomington + Lafayette area),
built with R's [mapgl](https://walker-data.com/mapgl/) 0.5.0 `add_flowmap()`
(Flowmap.gl / deck.gl) over the newest available LODES commute data.

Inspired by Kyle Walker's Dallas–Fort Worth flow map; implementation pattern
credit to Egor Kotov; Flowmap.gl by Ilya Boyandin.

**▶ Live interactive map: https://bennyfactor.github.io/indy-commute-flows/**
(use the top-right toggle to switch between block-group and ZIP/ZCTA resolution).

## Outputs

- `output/indy-commute-flows.html` — interactive, self-contained widget (5.3 MB).
- `output/indy-commute-flows.mp4` — 13 MB, 25-second camera-tour video.
- `output/indy-commute-flows.gif` — compact 480 px / 8 fps preview (~17 MB).

## Rebuild

```bash
podman build -t indy-flows:latest .         # R + spatial stack + mapgl/lehdr/tigris
./run.sh scripts/00-verify-env.R            # confirm mapgl >= 0.5.0
./run.sh scripts/01-fetch-data.R            # newest LODES OD -> data/flows.rds
./run.sh scripts/01b-build-locations.R      # block-group centroids -> data/locations.rds
./run.sh scripts/02-build-flowmap.R         # -> output/indy-commute-flows.html
./scripts/capture.sh                        # best-effort -> mp4/gif (host + Quadro P4000)
```

## Publish (GitHub Pages)

The live map is served from the `gh-pages` branch (a single self-contained
`index.html`). To rebuild and redeploy after a data refresh:

```bash
./scripts/deploy-pages.sh                   # rebuild -> push gh-pages -> Pages serves it
```

`main` stays source-only; the built HTML is never committed to `main`.

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
./run.sh scripts/02-build-flowmap.R     # multi-layer HTML with the resolution toggle
```

## Interactive node highlight

Hover any node (a block-group, ZIP/ZCTA, or census-block centroid) to draw that
area's boundary and split its commute flows into two colors — **inbound** (flows
*to* the node, rose `#FF4D6D`) and **outbound** (flows *from* the node, gold
`#FFD166`) — over a dimmed base. **Click** a node to pin the selection (move the
mouse freely); **Esc** or a click on empty space clears it. Works in all three
resolutions.

Boundaries come from simplified census block-group / ZCTA / census-block polygons
(`scripts/01d-build-polygons.R`, `scripts/01e-fetch-block-data.R`). The highlight is drawn as native MapLibre line
layers from the embedded flows, and the base Flowmap.gl layer is dimmed via its
canvas opacity so the two-color highlight reads clearly.

### Rebuild step (in addition to the toggle steps)

```bash
./run.sh scripts/01d-build-polygons.R   # boundary polygons -> data/polys_{bg,zcta}.rds
./run.sh scripts/02-build-flowmap.R     # render with the node interaction
```

A third **Census block** option shows the most granular LODES geography (the
level the data is built from). Block-to-block LODES is heavily noise-infused, so
this layer is thresholded to commuter **count ≥ 3** — it drops the ~873k count-1
fuzzing pairs in the region and shows the strongest block-to-block corridors
(~19.8k flows / ~8k blocks), not every commuter.

```bash
./run.sh scripts/01e-fetch-block-data.R  # census-block OD (count>=3) + centroids + polygons
```

The toggle offers four resolutions, listed largest → smallest by area: **ZIP code**
(ZCTA) → **Census tract** → **Census block group** (the default view) → **Census
block**. Census tract is the easy middle level — `lehdr` aggregates to it natively
(no crosswalk).

```bash
./run.sh scripts/01f-fetch-tract-data.R  # census-tract OD + centroids + polygons
```

A color **legend** (top-left) labels the inbound (rose) / outbound (gold) /
selected-boundary (white) cues. When you **pin** a node (click), its **top 3
inbound and top 3 outbound** partner nodes are labeled with the commuter count
(the ZIP is shown too in ZIP/ZCTA mode), colored by direction. Labels appear on
pin only and clear with the rest of the selection.

## Region

15 IN counties: Marion, Hamilton, Hendricks, Boone, Johnson, Hancock, Morgan,
Shelby, Madison, Putnam, Brown, Monroe, Clinton, Tippecanoe, White.

## Data

LODES8 OD (`state_part=main`, `JT00`, `S000`), newest year available for IN
(2023; 2024 not yet published). See `data/lodes_year.txt`.

- **385,768** region OD pairs; **1,068,499** total commuters represented.
- **1,724** block-group centroids (0 missing geometry).
- Flows capped to top **40,000** by count for widget performance.

## Known Issues

- **Software WebGL rendering**: Headless Chromium rendered via SwiftShader
  software rasterization, not the Quadro P4000 GPU. Video frames are correct
  but not GPU-accelerated. The `--use-gl` flags are present in `capture.sh`
  but the discrete GPU did not engage in headless mode.

- **Camera-tour wiring**: The flyTo camera tour requires the MapLibre map
  instance, which `mapgl` exposes as `el.map` on the widget container div.
  This is wired via `htmlwidgets::onRender` in `scripts/02-build-flowmap.R`.
  The HTML must be regenerated with that script for capture to pan/zoom
  correctly; copying an old HTML file will break the tour.

## Reproducibility

Package versions are pinned in `renv.lock`. `mapgl` (0.5.0) is installed from
GitHub (`walkerke/mapgl`) because the container's CRAN snapshot only had 0.2.0.

```r
# restore environment (inside container or local R with renv):
renv::restore()
```
