// scripts/03-capture-video.mjs
// Headless Chromium on the Quadro P4000: load the widget, run a slow zoom/pan
// "tour", capture frames via CDP screencast/screenshots. Best-effort.
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const HTML = 'file://' + resolve('output/indy-commute-flows.html');
const OUT = resolve('output/frames');
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({
  headless: true,
  args: [
    '--use-gl=egl', '--enable-gpu', '--ignore-gpu-blocklist',
    '--enable-features=Vulkan', '--no-sandbox',
    '--window-size=1600,900',
  ],
});
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
await page.goto(HTML, { waitUntil: 'networkidle' });
await page.waitForTimeout(6000); // let WebGL + flows initialize

// Try to grab the MapLibre map instance the widget created, for a camera tour.
await page.evaluate(() => {
  window.__indyMap = null;
  try {
    // mapgl/maplibre htmlwidget keeps the map on the widget element.
    const el = document.querySelector('.maplibregl-map') || document.querySelector('.mapboxgl-map');
    if (el && el._maplibregl_map) window.__indyMap = el._maplibregl_map;
    // Fallback: scan for any object exposing flyTo on the global widget registry.
    if (!window.__indyMap && window.HTMLWidgets) {
      for (const inst of (window.HTMLWidgets.findAll ? window.HTMLWidgets.findAll('.maplibregl-map') : [])) {
        if (inst && inst.flyTo) { window.__indyMap = inst; break; }
      }
    }
  } catch (e) {}
});

// Camera tour waypoints (hubs). flyTo is best-effort; if no map handle, we just
// record the default animated view.
const tour = [
  { center: [-86.158, 39.768], zoom: 11.5, name: 'downtown' },     // Mile Square
  { center: [-86.176, 39.776], zoom: 12.5, name: 'medical-iupui' },// IU Health / IUPUI
  { center: [-86.295, 39.717], zoom: 12.0, name: 'airport-IND' },  // IND airport
  { center: [-86.118, 39.978], zoom: 11.0, name: 'carmel-fishers' },// north suburbs
  { center: [-86.20, 39.90],   zoom: 8.5,  name: 'region' },       // pull back
];

let n = 0;
const grab = async () => {
  const buf = await page.screenshot({ type: 'png' });
  writeFileSync(`${OUT}/frame-${String(n++).padStart(4,'0')}.png`, buf);
};

for (const wp of tour) {
  await page.evaluate(({center, zoom}) => {
    if (window.__indyMap && window.__indyMap.flyTo)
      window.__indyMap.flyTo({ center, zoom, duration: 3000 });
  }, wp);
  // ~3s of flight + dwell, sampling ~10 fps
  for (let i = 0; i < 50; i++) { await grab(); await page.waitForTimeout(100); }
}

await browser.close();
console.log(`CAPTURED ${n} frames`);
