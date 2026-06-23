// scripts/03-capture-video.mjs
// Headless Chromium: load the widget, run a slow zoom/pan "tour",
// capture frames via screenshots. Best-effort.
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

// Forward browser console to Node stdout so we can see diagnostics.
page.on('console', msg => console.log('[browser]', msg.text()));

await page.goto(HTML, { waitUntil: 'networkidle' });
await page.waitForTimeout(6000); // let WebGL + flows initialize

// Grab the MapLibre map instance the widget created.
//
// mapgl htmlwidget (mapgl >= 0.5) stores the map TWO ways:
//   1. el.map   — the container div has .map assigned directly after style.load
//   2. HTMLWidgets.find("#id").getMap() — the factory return object has getMap()
//
// We try both in order.
const mapFound = await page.evaluate(() => {
  window.__indyMap = null;
  try {
    // Method 1: el.map on the maplibre container div.
    const el = document.querySelector('.maplibregl-map');
    if (el && el.map && typeof el.map.flyTo === 'function') {
      window.__indyMap = el.map;
      console.log('__indyMap found via el.map on', el.id);
      return 'el.map';
    }

    // Method 2: HTMLWidgets widget instance .getMap()
    if (window.HTMLWidgets && window.HTMLWidgets.find) {
      const mapEl = document.querySelector('.maplibregl-map');
      if (mapEl) {
        const widget = window.HTMLWidgets.find('#' + mapEl.id);
        if (widget && typeof widget.getMap === 'function') {
          const m = widget.getMap();
          if (m && typeof m.flyTo === 'function') {
            window.__indyMap = m;
            console.log('__indyMap found via HTMLWidgets.find().getMap() on', mapEl.id);
            return 'HTMLWidgets.getMap';
          }
        }
      }
    }

    // Method 3: scan all window properties for an object with flyTo + getCenter
    for (const key of Object.keys(window)) {
      const val = window[key];
      if (val && typeof val === 'object' && typeof val.flyTo === 'function' &&
          typeof val.getCenter === 'function') {
        window.__indyMap = val;
        console.log('__indyMap found via window scan: window.' + key);
        return 'window.' + key;
      }
    }
  } catch (e) {
    console.log('__indyMap lookup error: ' + e.message);
  }
  console.log('__indyMap NOT FOUND — tour will be static');
  return null;
});

console.log(`[node] Map handle method: ${mapFound || 'none — static capture'}`);

// Camera tour waypoints (hubs). flyTo is best-effort; if no map handle, we just
// record the default animated view.
const tour = [
  { center: [-86.158, 39.768], zoom: 11.5, name: 'downtown' },     // Mile Square
  { center: [-86.176, 39.776], zoom: 12.5, name: 'medical-iupui' },// IU Health / IUPUI
  { center: [-86.295, 39.717], zoom: 12.0, name: 'airport-IND' },  // IND airport
  { center: [-86.118, 39.978], zoom: 11.0, name: 'carmel-fishers' },// north suburbs
  { center: [-86.20,  39.90],  zoom: 8.5,  name: 'region' },       // pull back
];

let n = 0;
const grab = async () => {
  const buf = await page.screenshot({ type: 'png' });
  writeFileSync(`${OUT}/frame-${String(n++).padStart(4,'0')}.png`, buf);
};

for (const wp of tour) {
  const flew = await page.evaluate(({center, zoom, name}) => {
    if (window.__indyMap && window.__indyMap.flyTo) {
      window.__indyMap.flyTo({ center, zoom, duration: 3000 });
      return true;
    }
    return false;
  }, wp);
  console.log(`[node] waypoint ${wp.name}: flyTo=${flew}`);
  // ~3s of flight + dwell, sampling ~10 fps
  for (let i = 0; i < 50; i++) { await grab(); await page.waitForTimeout(100); }
}

await browser.close();
console.log(`CAPTURED ${n} frames`);
