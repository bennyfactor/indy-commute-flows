# Legend + Top-3 In/Out Partner Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible color legend and, on click-pin, label the pinned node's top 3 inbound and top 3 outbound partners with direction-colored commuter counts.

**Architecture:** All behavior lives in the existing `R/interaction_js.R` onRender module. A `buildLegend()` adds a static top-left legend. A `partner-labels` GeoJSON symbol layer (Open Sans Bold, color by `dir`) is created at init and populated by `setLabels(id)` only from the pin click path; `clearLabels()` empties it on every clear. `scripts/02-build-flowmap.R` is unchanged — the existing `{ids,lon,lat,o,d,c}` payload already provides partner ids, centroids, and counts.

**Tech Stack:** R (mapgl 0.5.0, htmlwidgets) in the `indy-flows:latest` container; MapLibre symbol layer with CARTO dark-matter glyphs; Node + Playwright (host) for headless verification.

## Global Constraints

- Branch `legend-labels`. Additive: do NOT change data/fetch/centroid/capture/deploy scripts or `scripts/02-build-flowmap.R`. Only `R/interaction_js.R` and `README.md` change.
- Run R in the container: `./run.sh scripts/02-build-flowmap.R`. `run.sh` has no `-i`; never use the `/dev/stdin` heredoc — temp checks go in `scripts/_*.R`/`.mjs`, deleted, never committed.
- Colors (verbatim): inbound `#FF4D6D` (rose), outbound `#FFD166` (gold), outline/boundary `#FFFFFF` (white). Label halo `#101014`. Font `["Open Sans Bold"]` (present in the CARTO dark-matter glyphs).
- Labels are **pin-only** (set in the hits `click` handler, never in `select()`); each clear path empties them. Top **3** inbound + top **3** outbound, by commuter count desc. ZCTA label text is prefixed with the partner ZIP; block-group label text is the count alone.
- Label feature props: `label` (string) and `dir` (`"in"`/`"out"`). Source/layer id `partner-labels` (single shared layer, always `visible`, emptied when not pinned).
- Preserve all existing behavior and ids (`indy-bg`/`indy-zcta`, `hits-*`, `outline-*`, `inbound-*`, `outbound-*`, radio `name=indy-res`) and `window.__indyMap`.
- mapgl ≥ 0.5.0. Commit after each task.

---

### Task 1: Legend + partner labels (interaction JS)

**Files:**
- Modify: `R/interaction_js.R` (full rewrite below — adds `buildLegend`, the `partner-labels` layer, `setLabels`/`clearLabels`, and the pin/clear wiring; everything else unchanged).

**Interfaces:**
- Consumes: the onRender `data` payload `{bg,zcta}` each `{ids,lon,lat,o,d,c}` (already produced by `scripts/02-build-flowmap.R`).
- Produces: `output/indy-commute-flows.html` with the legend always visible and pin-only top-3/top-3 partner labels.

- [ ] **Step 1: Replace `R/interaction_js.R` with this exact content**

```r
# R/interaction_js.R — onRender JS for the node hover/click interaction.
# Receives (el, x, data); data = { bg:{ids,lon,lat,o,d,c}, zcta:{...} } where
# o/d are 0-based indices into ids and c is the commuter count. Builds inbound
# (#FF4D6D) and outbound (#FFD166) line layers + a white polygon outline, dims
# the Flowmap.gl deck canvas on focus, supports hover-preview + click-to-pin,
# shows an always-on color legend, and labels the pinned node's top 3 inbound /
# top 3 outbound partners.
INTERACTION_JS <- "
function(el, x, data) {
  var map = el.map;
  if (!map) return;
  window.__indyMap = map;

  var RES = {
    bg:   { flow:'indy-bg',   hits:'hits-bg',   outline:'outline-bg',   inbound:'inbound-bg',   outbound:'outbound-bg' },
    zcta: { flow:'indy-zcta', hits:'hits-zcta', outline:'outline-zcta', inbound:'inbound-zcta', outbound:'outbound-zcta' }
  };
  var active = 'bg', pinnedId = null, lastSel = null, idx = {};

  function buildIndex(d) {
    var pos = {}, adj = {};
    for (var i = 0; i < d.ids.length; i++) pos[String(d.ids[i])] = i;
    for (var k = 0; k < d.o.length; k++) {
      var o = d.o[k], dd = d.d[k], c = d.c[k];
      if (o === dd) continue;
      (adj[o] = adj[o] || {inb:[], out:[]}).out.push([dd, c]);
      (adj[dd] = adj[dd] || {inb:[], out:[]}).inb.push([o, c]);
    }
    return { ids:d.ids, lon:d.lon, lat:d.lat, pos:pos, adj:adj };
  }
  function fc(features) { return { type:'FeatureCollection', features:features }; }
  function lines(res, id, dir) {
    var ix = idx[res]; if (!ix) return fc([]);
    var p = ix.pos[String(id)]; if (p === undefined) return fc([]);
    var here = [ix.lon[p], ix.lat[p]];
    var list = (ix.adj[p] || {})[dir] || [], out = [];
    for (var i = 0; i < list.length; i++) {
      var q = list[i][0], there = [ix.lon[q], ix.lat[q]];
      var a = (dir === 'inb') ? there : here;
      var b = (dir === 'inb') ? here  : there;
      out.push({ type:'Feature', properties:{ count:list[i][1] },
                 geometry:{ type:'LineString', coordinates:[a, b] } });
    }
    return fc(out);
  }

  function deckCanvas() {
    var cs = map.getContainer().querySelectorAll('canvas');
    for (var i = 0; i < cs.length; i++)
      if (!cs[i].classList.contains('maplibregl-canvas')) return cs[i];
    return (map._deckgl && map._deckgl.canvas) || null;
  }
  function dim(on) {
    var c = deckCanvas();
    if (c) { c.style.transition = 'opacity 0.15s'; c.style.opacity = on ? '0.18' : '1'; }
  }

  // ---- top-3 in / top-3 out partner labels (pin only) ----
  function topN(list, n) {
    return list.slice().sort(function(a, b) { return b[1] - a[1]; }).slice(0, n);
  }
  function fmt(n) { return Math.round(n).toLocaleString('en-US'); }
  function setLabels(id) {
    var ix = idx[active]; if (!ix) return;
    var p = ix.pos[String(id)];
    if (p === undefined) { clearLabels(); return; }
    var a = ix.adj[p] || { inb:[], out:[] }, feats = [];
    var addOne = function(pair, dir) {
      var q = pair[0], pid = String(ix.ids[q]);
      var txt = (active === 'zcta') ? (pid + ' · ' + fmt(pair[1])) : fmt(pair[1]);
      feats.push({ type:'Feature', properties:{ label:txt, dir:dir },
                   geometry:{ type:'Point', coordinates:[ix.lon[q], ix.lat[q]] } });
    };
    topN(a.inb, 3).forEach(function(pr) { addOne(pr, 'in'); });
    topN(a.out, 3).forEach(function(pr) { addOne(pr, 'out'); });
    if (map.getSource('partner-labels')) map.getSource('partner-labels').setData(fc(feats));
  }
  function clearLabels() {
    if (map.getSource('partner-labels')) map.getSource('partner-labels').setData(fc([]));
  }

  function select(id) {
    if (id === lastSel) return;
    lastSel = id;
    var r = RES[active];
    if (map.getSource(r.inbound))  map.getSource(r.inbound).setData(lines(active, id, 'inb'));
    if (map.getSource(r.outbound)) map.getSource(r.outbound).setData(lines(active, id, 'out'));
    if (map.getLayer(r.outline))   map.setFilter(r.outline, ['==', ['get','id'], String(id)]);
    dim(true);
  }
  function clear() {
    lastSel = null;
    ['bg','zcta'].forEach(function(res) {
      var r = RES[res];
      if (map.getSource(r.inbound))  map.getSource(r.inbound).setData(fc([]));
      if (map.getSource(r.outbound)) map.getSource(r.outbound).setData(fc([]));
      if (map.getLayer(r.outline))   map.setFilter(r.outline, ['==', ['get','id'], '']);
    });
    clearLabels();
    dim(false);
  }

  function ensureHighlightLayers() {
    ['bg','zcta'].forEach(function(res) {
      var r = RES[res];
      [[r.inbound, '#FF4D6D'], [r.outbound, '#FFD166']].forEach(function(t) {
        if (!map.getSource(t[0])) map.addSource(t[0], { type:'geojson', data:fc([]) });
        if (!map.getLayer(t[0])) map.addLayer({
          id:t[0], type:'line', source:t[0],
          layout:{ visibility:(res === active ? 'visible':'none'), 'line-cap':'round' },
          paint:{ 'line-color':t[1], 'line-opacity':0.92,
                  'line-width':['interpolate',['linear'],['get','count'], 1,1, 50,4, 500,9] }
        });
      });
    });
    // Single shared label layer (always visible; emptied when not pinned).
    if (!map.getSource('partner-labels')) map.addSource('partner-labels', { type:'geojson', data:fc([]) });
    if (!map.getLayer('partner-labels')) map.addLayer({
      id:'partner-labels', type:'symbol', source:'partner-labels',
      layout:{
        'text-field':['get','label'],
        'text-font':['Open Sans Bold'],
        'text-size':12,
        'text-allow-overlap':true,
        'text-anchor':'center',
        'text-offset':['match',['get','dir'],'in',['literal',[0,-0.9]],['literal',[0,0.9]]]
      },
      paint:{
        'text-color':['match',['get','dir'],'in','#FF4D6D','out','#FFD166','#ffffff'],
        'text-halo-color':'#101014', 'text-halo-width':1.4
      }
    });
  }
  function setNativeVisibility(res) {
    ['bg','zcta'].forEach(function(rr) {
      var r = RES[rr], vis = (rr === res) ? 'visible' : 'none';
      [r.hits, r.outline, r.inbound, r.outbound].forEach(function(lid) {
        if (map.getLayer(lid)) map.setLayoutProperty(lid, 'visibility', vis);
      });
    });
  }
  function applyFlow(chosen) {
    var p = window.MapGLFlowmapPlugin; if (!p) return false;
    var ok = true;
    ['indy-bg','indy-zcta'].forEach(function(fid) {
      if (!p.setVisibility(map, fid, fid === chosen ? 'visible':'none')) ok = false;
    });
    return ok;
  }

  function wire() {
    ['bg','zcta'].forEach(function(res) {
      var r = RES[res];
      map.on('mousemove', r.hits, function(e) {
        if (res !== active || pinnedId || !e.features || !e.features.length) return;
        map.getCanvas().style.cursor = 'pointer';
        select(e.features[0].properties.id);
      });
      map.on('mouseleave', r.hits, function() {
        if (res !== active || pinnedId) return;
        map.getCanvas().style.cursor = ''; clear();
      });
      map.on('click', r.hits, function(e) {
        if (res !== active || !e.features || !e.features.length) return;
        pinnedId = e.features[0].properties.id;
        select(pinnedId);
        setLabels(pinnedId);   // labels only on pin
      });
    });
    map.on('click', function(e) {
      var hit = map.queryRenderedFeatures(e.point, { layers:[RES[active].hits] });
      if (!hit.length) { pinnedId = null; clear(); }
    });
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') { pinnedId = null; clear(); }
    });
  }

  function buildLegend() {
    var lg = document.createElement('div');
    lg.style.cssText = 'position:absolute;top:10px;left:10px;z-index:1000;' +
      'background:rgba(20,20,20,0.85);color:#eee;padding:8px 10px;border-radius:6px;' +
      'font:12px/1.5 system-ui,sans-serif;';
    var row = function(color, label) {
      return '<div style=\"display:flex;align-items:center;gap:6px;\">' +
        '<span style=\"display:inline-block;width:14px;height:3px;background:' + color +
        ';border-radius:2px;\"></span>' + label + '</div>';
    };
    lg.innerHTML = '<div style=\"font-weight:600;margin-bottom:4px;\">Flows</div>' +
      row('#FF4D6D', 'inbound (to node)') +
      row('#FFD166', 'outbound (from node)') +
      row('#FFFFFF', 'selected boundary');
    el.appendChild(lg);
  }

  function buildRadio() {
    var ctrl = document.createElement('div');
    ctrl.style.cssText = 'position:absolute;top:10px;right:10px;z-index:1000;' +
      'background:rgba(20,20,20,0.85);color:#eee;padding:8px 10px;border-radius:6px;' +
      'font:13px/1.4 system-ui,sans-serif;';
    ctrl.innerHTML =
      '<div style=\"font-weight:600;margin-bottom:4px;\">Resolution</div>' +
      '<label style=\"display:block;cursor:pointer;\"><input type=\"radio\" name=\"indy-res\" value=\"bg\" checked> Block group</label>' +
      '<label style=\"display:block;cursor:pointer;\"><input type=\"radio\" name=\"indy-res\" value=\"zcta\"> ZIP code</label>' +
      '<div style=\"margin-top:6px;font-size:11px;color:#9bd;\">hover a node &middot; click to pin &middot; Esc clears</div>';
    el.appendChild(ctrl);
    ctrl.addEventListener('change', function(e) {
      if (e.target && e.target.name === 'indy-res') {
        pinnedId = null; clear();
        active = e.target.value;
        applyFlow(active === 'bg' ? 'indy-bg' : 'indy-zcta');
        setNativeVisibility(active);
      }
    });
  }

  var tries = 0, inited = false;
  function init() {
    if (!window.MapGLFlowmapPlugin || !data || !data.bg) {
      if (tries++ < 60) { setTimeout(init, 150); }
      return;
    }
    if (inited) return;
    idx.bg = buildIndex(data.bg);
    if (data.zcta) idx.zcta = buildIndex(data.zcta);
    ensureHighlightLayers();
    setNativeVisibility(active);
    applyFlow('indy-bg');
    wire();
    inited = true;
  }
  buildLegend();
  buildRadio();
  if (map.once) map.once('idle', init);
  init();
}"
```

- [ ] **Step 2: Re-render**

Run: `./run.sh scripts/02-build-flowmap.R`
Expected: prints the BG/ZCTA counts and `RENDER OK`; rewrites `output/indy-commute-flows.html`.

- [ ] **Step 3: Static checks**

Run:
```bash
for s in 'partner-labels' 'Open Sans Bold' 'inbound (to node)' 'outbound (from node)' 'selected boundary'; do
  printf '%s: ' "$s"; grep -c -- "$s" output/indy-commute-flows.html
done
```
Expected: each returns a non-zero count (the label layer, the font, and the three legend rows are embedded).

- [ ] **Step 4: Headless interaction check (acceptance gate)**

Write `scripts/_labels-check.mjs` (host Node + Playwright; not committed):

```js
import { chromium } from 'playwright';
import { resolve } from 'node:path';
const HTML = 'file://' + resolve('output/indy-commute-flows.html');
const b = await chromium.launch({ args:['--use-gl=egl','--enable-unsafe-swiftshader','--no-sandbox'] });
const p = await b.newPage({ viewport:{ width:1280, height:860 } });
await p.goto(HTML, { waitUntil:'networkidle' });
await p.waitForTimeout(6000);
await p.evaluate(() => window.__indyMap.setZoom(11));
await p.waitForTimeout(1500);

const legendPresent = await p.evaluate(() => document.body.innerText.includes('inbound (to node)'));

// Find a rendered hit node and its pixel point.
const probe = await p.evaluate(() => {
  const m = window.__indyMap;
  const fs = m.queryRenderedFeatures({ layers:['hits-bg'] });
  if (!fs.length) return null;
  const f = fs[0], pt = m.project(f.geometry.coordinates);
  return { id:f.properties.id, x:pt.x, y:pt.y };
});
if (!probe) { console.log('FAIL: no hits-bg features'); await b.close(); process.exit(1); }

const labelCount = () => p.evaluate(() => {
  const d = window.__indyMap.getSource('partner-labels')._data || { features:[] };
  const f = d.features;
  return { n:f.length,
           in:f.filter(x => x.properties.dir === 'in').length,
           out:f.filter(x => x.properties.dir === 'out').length,
           sample:(f[0] && f[0].properties.label) || null };
});

// Hover should NOT label (pin-only).
await p.mouse.move(probe.x, probe.y);
await p.waitForTimeout(600);
const onHover = await labelCount();

// Click to pin → labels appear.
await p.mouse.click(probe.x, probe.y);
await p.waitForTimeout(600);
const onPin = await labelCount();
// Highlight line counts, to tie labels to the same data.
const lineCounts = await p.evaluate(() => {
  const inb = window.__indyMap.getSource('inbound-bg')._data || { features:[] };
  const out = window.__indyMap.getSource('outbound-bg')._data || { features:[] };
  return { inb:inb.features.length, out:out.features.length };
});

// Esc clears labels.
await p.keyboard.press('Escape');
await p.waitForTimeout(400);
const onEsc = await labelCount();
await b.close();

console.log('legend:', legendPresent, 'hover:', onHover, 'pin:', onPin, 'lines:', lineCounts, 'esc:', onEsc);
const ok = legendPresent
  && onHover.n === 0
  && onPin.n >= 1 && onPin.n <= 6
  && onPin.in <= 3 && onPin.out <= 3
  && onPin.in === Math.min(3, lineCounts.inb)
  && onPin.out === Math.min(3, lineCounts.out)
  && onEsc.n === 0;
console.log(ok ? 'LABELS CHECK OK' : 'LABELS CHECK FAIL');
process.exit(ok ? 0 : 1);
```

Run: `node scripts/_labels-check.mjs`
Expected: prints the states and `LABELS CHECK OK` — legend present; hover shows 0 labels; pin shows 1–6 labels split ≤3 in / ≤3 out and equal to `min(3, inbound/outbound line count)`; Esc clears. Then `rm scripts/_labels-check.mjs`.

If `_data` is unavailable on the source, assert via `getSource('partner-labels').serialize().data.features` or `queryRenderedFeatures({layers:['partner-labels']})` after a tiny pan; report which path was used. If the chosen first node has no flows, iterate candidates from `queryRenderedFeatures({layers:['hits-bg']})` until one yields non-empty highlight lines.

- [ ] **Step 5: Commit**

```bash
git add R/interaction_js.R
git commit -m "Add color legend and pin-only top-3 in/out partner labels"
```

---

### Task 2: README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing new. Documents the legend and labels.

- [ ] **Step 1: Extend the "Interactive node highlight" section in `README.md`**

Read the current `README.md`, find the "Interactive node highlight" section, and append this paragraph at its end (match the file's markdown style):

```markdown
A color **legend** (top-left) labels the inbound (rose) / outbound (gold) /
selected-boundary (white) cues. When you **pin** a node (click), its **top 3
inbound and top 3 outbound** partner nodes are labeled with the commuter count
(the ZIP is shown too in ZIP/ZCTA mode), colored by direction. Labels appear on
pin only and clear with the rest of the selection.
```

- [ ] **Step 2: Verify**

Run: `grep -c -E 'legend|top 3 inbound|partner' README.md`
Expected: non-zero.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the legend and partner labels"
```

---

## Self-Review

**Spec coverage:** always-visible legend (`buildLegend`, top-left) → Task 1; pin-only top-3 in / top-3 out partner labels with direction color, ZIP prefix for ZCTA, halo, offset/allow-overlap, `partner-labels` symbol layer + `setLabels`/`clearLabels` wired into the pin/clear paths → Task 1; README → Task 2. `scripts/02-build-flowmap.R` unchanged (spec). All spec sections mapped.

**Placeholder scan:** No TBD/TODO; the full file is concrete. The check-script fallbacks (`_data` vs serialize vs queryRenderedFeatures; candidate iteration) are explicit alternatives, not placeholders.

**Type consistency:** label props `label`/`dir`, layer/source id `partner-labels`, colors `#FF4D6D`/`#FFD166`/`#FFFFFF`/`#101014`, font `Open Sans Bold`, and the `setLabels`/`clearLabels`/`topN`/`fmt` names are consistent throughout. `setLabels` is called only in the hits `click` handler; `clearLabels` is called inside `clear()` (covering mouseleave/Esc/empty-click/resolution-switch). Existing ids and `select`/`clear` semantics preserved.
