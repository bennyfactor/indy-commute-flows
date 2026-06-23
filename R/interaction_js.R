# R/interaction_js.R — onRender JS for the node hover/click interaction.
# Receives (el, x, data); data = { bg:{ids,lon,lat,o,d,c}, zcta:{...} } where
# o/d are 0-based indices into ids and c is the commuter count. Builds inbound
# (#FF4D6D) and outbound (#FFD166) line layers + a white polygon outline, dims
# the Flowmap.gl deck canvas on focus, and supports hover-preview + click-to-pin.
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
        pinnedId = e.features[0].properties.id; select(pinnedId);
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
  buildRadio();
  if (map.once) map.once('idle', init);
  init();
}"
