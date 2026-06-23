# Central Indiana Commute Flow Map

Animated, hierarchical origin–destination commute flows for the 15-county
central-Indiana region (Indianapolis MSA + Bloomington + Lafayette area),
built with R's [mapgl](https://walker-data.com/mapgl/) 0.5.0 `add_flowmap()`
(Flowmap.gl / deck.gl) over the newest available LODES commute data.

Inspired by Kyle Walker's Dallas–Fort Worth flow map; implementation pattern
credit to Egor Kotov; Flowmap.gl by Ilya Boyandin.

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
