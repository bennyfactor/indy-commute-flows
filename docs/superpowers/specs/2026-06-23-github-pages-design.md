# Publish Interactive Map to GitHub Pages — Design Spec

**Date:** 2026-06-23
**Status:** Approved (brainstorming)
**Repo:** bennyfactor/indy-commute-flows (public)

## Goal

Host the interactive commute flow map (with the block-group/ZIP toggle) on GitHub
Pages for free, so anyone can open and interact with it at a public URL. Keep `main`
source-only; make redeploying after a data refresh a one-command operation.

## Why this works without a build server

The rendered `output/indy-commute-flows.html` is a **self-contained** htmlwidget: the
MapLibre/Flowmap.gl/deck.gl assets and both flow datasets are embedded. The only
runtime fetch is the **CARTO dark-matter basemap tiles** (`basemaps.cartocdn.com`,
free/public). So GitHub Pages only has to serve one static HTML file — no build step,
no server.

## Approach

**Publish from a dedicated `gh-pages` branch** (orphan, source-free) containing just
`index.html` (the widget) + `.nojekyll`. `main` stays source-only, consistent with the
existing rule that `output/` is generated and gitignored. A committed deploy script
rebuilds and pushes the artifact.

(Rejected: committing the 5.7 MB HTML into `main`/`docs` — churns a binary through
source history and would expose `/docs` specs. Rejected: CI rebuild — running the full
geospatial stack + Census downloads in a runner is heavy/fragile for ~annual data.)

## Components

### 1. `scripts/deploy-pages.sh` (committed on `main`)

Re-runnable deploy. Steps:
1. Guard: require `data/flows.rds`, `data/locations.rds`, `data/flows_zcta.rds`,
   `data/locations_zcta.rds`, `data/lodes_year.txt` — else print "run the fetch scripts
   first" and exit non-zero.
2. Rebuild the widget: `./run.sh scripts/02-build-flowmap.R` → `output/indy-commute-flows.html`.
3. Build `index.html`: inject a small attribution overlay before `</body>` (the file has
   exactly one). Overlay text: `Data: US Census LODES <year> · Built with R mapgl +
   Flowmap.gl · source ↗` (year read from `data/lodes_year.txt`; "source" links to the
   repo; mapgl link to walker-data.com/mapgl). Injected via `awk` reading an overlay
   snippet file (no fragile sed escaping); the local/video HTML is left untouched —
   only the published `index.html` carries the overlay.
4. Publish to `gh-pages` via a temporary git worktree:
   `git worktree add --orphan -B gh-pages "$WT"` (git ≥2.42; gh-pages stays orphan/clean),
   copy `index.html`, `touch .nojekyll`, `git add -A`, commit, `git push -f origin gh-pages`,
   then `git worktree remove`.

### 2. GitHub Pages enablement (one-time, this session)

`gh api -X POST repos/bennyfactor/indy-commute-flows/pages` with
`source.branch=gh-pages`, `source.path=/`. Public URL:
**https://bennyfactor.github.io/indy-commute-flows/**.

### 3. README

Add a "Live demo" line linking the Pages URL, and a one-line redeploy note
(`./scripts/deploy-pages.sh`).

## Error Handling

- Missing data → clear message, exit 1 (don't deploy a broken page).
- `gh` not authenticated / push rejected → surfaced by `git push` / `gh` exit codes;
  script uses `set -euo pipefail`.
- Re-runs are idempotent: `-B gh-pages` resets the branch tip each deploy; force-push
  replaces the published artifact.

## Success Criteria

1. `gh-pages` branch exists containing only `index.html` + `.nojekyll`.
2. GitHub Pages is enabled and serves the map at the public URL (HTTP 200, the toggle
   works for an external visitor — verified by fetching the deployed URL and checking the
   page loads the flowmap assets and the attribution overlay).
3. `./scripts/deploy-pages.sh` re-runs cleanly to update the published page.
4. `main` contains the deploy script + README link; no generated HTML committed to `main`.
