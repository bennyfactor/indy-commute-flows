#!/usr/bin/env bash
# scripts/deploy-pages.sh — rebuild the interactive map and publish it to the
# orphan `gh-pages` branch (served by GitHub Pages). Re-runnable: each run resets
# the gh-pages tip to a single index.html + .nojekyll and force-pushes it.
#
# Prereq: the data RDS files must exist (run scripts/01-fetch-data.R,
# 01b-build-locations.R, 01c-fetch-zcta-data.R first). main stays source-only;
# the built HTML is never committed to main.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$REPO"

# 1. Guard: required data must be present.
need=(data/flows.rds data/locations.rds data/flows_zcta.rds data/locations_zcta.rds data/lodes_year.txt)
missing=0
for f in "${need[@]}"; do
  [ -f "$f" ] || { echo "MISSING: $f" >&2; missing=1; }
done
if [ "$missing" -ne 0 ]; then
  echo "Run the fetch scripts first: ./run.sh scripts/01-fetch-data.R && ./run.sh scripts/01b-build-locations.R && ./run.sh scripts/01c-fetch-zcta-data.R" >&2
  exit 1
fi
YEAR="$(cat data/lodes_year.txt)"

# 2. Rebuild the self-contained widget.
echo "Rebuilding output/indy-commute-flows.html ..."
./run.sh scripts/02-build-flowmap.R
SRC="$REPO/output/indy-commute-flows.html"
[ -f "$SRC" ] || { echo "render did not produce $SRC" >&2; exit 1; }

# 3. Build index.html with an attribution overlay injected before </body>.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/overlay.html" <<EOF
<div style="position:fixed;left:8px;bottom:8px;z-index:1000;background:rgba(20,20,20,0.8);color:#ddd;font:12px/1.4 system-ui,sans-serif;padding:6px 9px;border-radius:5px;max-width:90vw;">
Central Indiana commute flows &middot; Data: US Census LODES ${YEAR} &middot;
Built with R <a style="color:#6cf" href="https://walker-data.com/mapgl/">mapgl</a> + Flowmap.gl &middot;
<a style="color:#6cf" href="https://github.com/bennyfactor/indy-commute-flows">source &#8599;</a>
</div>
EOF
# Insert the overlay before the first </body>; awk avoids sed escaping pitfalls.
awk 'NR==FNR{ov=ov $0 ORS; next} /<\/body>/&&!done{printf "%s",ov; done=1} {print}' \
  "$TMP/overlay.html" "$SRC" > "$TMP/index.html"
grep -q 'walker-data.com/mapgl' "$TMP/index.html" || { echo "overlay injection failed" >&2; exit 1; }

# 4. Publish to the gh-pages branch via a temp worktree. `-B` (re)creates the
# branch each run; we then strip all tracked source so the gh-pages TIP holds
# only index.html + .nojekyll (what Pages serves), force-pushed.
WT="$TMP/gh-pages"
git worktree add -B gh-pages "$WT" >/dev/null
( cd "$WT"
  git rm -rfq . >/dev/null 2>&1 || true
  cp "$TMP/index.html" index.html
  touch .nojekyll
  git add -A
  git commit -q -m "Deploy interactive map (LODES ${YEAR}) to GitHub Pages"
  git push -fq origin gh-pages
)
git worktree remove --force "$WT"
git worktree prune

echo "DEPLOYED. Pages will serve: https://bennyfactor.github.io/indy-commute-flows/"
