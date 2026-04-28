// MapViewPage.jsx
// Requires: leaflet (npm install leaflet)
// Add to index.html: <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />

import React, { useState, useEffect, useRef } from 'react';
import L from 'leaflet';
import apiClient from '../api/client';
import {CircleX, MoveDown} from 'lucide-react'
import { useNavigate } from 'react-router-dom';

// ── Palette ───────────────────────────────────────────────────────────────────
const C = {
  bg:      '#F8F9FC',
  primary: '#0F2B5B',
  accent:  '#FBBF24',
  green:   '#186A3B',
  red:     '#C0392B',
  orange:  '#E67E22',
  purple:  '#6C3483',
  subtle:  '#6B7C93',
  border:  '#DDE3EE',
  dark:    '#1A2332',
  surface: '#FFFFFF',
};

function typeColor(t) {
  if (t === 'A++') return C.purple;
  if (t === 'A')   return C.red;
  if (t === 'B')   return C.orange;
  return C.green;
}
function typeLabel(t) {
  if (t === 'A++') return 'अत्यति संवेदनशील';
  if (t === 'A')   return 'अति संवेदनशील';
  if (t === 'B')   return 'संवेदनशील';
  return 'सामान्य';
}

// ── API ───────────────────────────────────────────────────────────────────────
async function fetchHierarchy() {
  const res = await apiClient.get('/admin/hierarchy/full');
  return Array.isArray(res) ? res : (res.data ?? []);
}

// ══════════════════════════════════════════════════════════════════════════════
//  MapViewPage
// ══════════════════════════════════════════════════════════════════════════════
export default function MapViewPage({ onBack }) {
  const [level, setLevel]           = useState('district');
  const [district, setDistrict]     = useState(null);
  const [superZone, setSuperZone]   = useState(null);
  const [zone, setZone]             = useState(null);
  const [zones, setZones]           = useState([]);
  const [centers, setCenters]       = useState([]);
  const [superZones, setSuperZones] = useState([]);
  const [districts, setDistricts]   = useState([]);
  const [loading, setLoading]       = useState(false);
  const [error, setError]           = useState(null);

  const nav = useNavigate();
  
  const mapViewRef = useRef(null);

  useEffect(() => { loadHierarchy(); }, []);

  async function loadHierarchy() {
    setLoading(true); setError(null);
    try {
      const data = await fetchHierarchy();
      const districtSet = new Set();
      data.forEach(sz => { const d = (sz.district || '').trim(); if (d) districtSet.add(d); });
      setSuperZones(data);
      setDistricts([...districtSet].map(d => ({ district: d })));
    } catch (e) { setError(e.message); }
    finally { setLoading(false); }
  }

  function selectDistrict(d)   { setDistrict(d); setLevel('superZone'); }
  function selectSuperZone(sz) { setSuperZone(sz); setZones(sz.zones || []); setLevel('zone'); }
  function selectZone(z) {
    const cs = [];
    (z.sectors || []).forEach(s =>
      (s.panchayats || []).forEach(gp =>
        (gp.centers || []).forEach(c => {
          if (c.latitude != null && c.longitude != null)
            cs.push({ ...c, _zone: z, _sector: s, _gp: gp, _superZone: superZone });
        })
      )
    );
    setZone(z); setCenters(cs); setLevel('map');
  }

  function goBack() {
    if (level === 'map')            { setLevel('zone');      setZone(null);      setCenters([]); }
    else if (level === 'zone')      { setLevel('superZone'); setSuperZone(null); setZones([]); }
    else if (level === 'superZone') { setLevel('district');  setDistrict(null); }
  }

  const filteredSuperZones = district == null
    ? superZones
    : superZones.filter(sz => (sz.district || '').trim() === district);

  const title = level === 'district'  ? 'जिला चुनें'
    : level === 'superZone' ? (district || 'सुपर जोन')
    : level === 'zone'      ? (superZone?.name || 'जोन')
    : (zone?.name || 'नक्शा');

  const breadcrumbs = ['चुनाव नक्शा', district, superZone?.name, zone?.name].filter(Boolean).join(' › ');

  return (
    <div style={{ display:'flex', flexDirection:'column', height:'100vh', backgroundColor:C.bg, fontFamily:"'Noto Sans Devanagari','Segoe UI',sans-serif" }}>
      {/* AppBar */}
      <div style={{ backgroundColor:C.primary, padding:'0 16px', display:'flex', alignItems:'center', gap:8, minHeight:56, flexShrink:0, boxShadow:'0 2px 8px rgba(0,0,0,0.2)', position:'relative', zIndex:2000 }}>
        { (
          <button onClick={()=>{
            level !== 'district' ? goBack() : nav("/");
          }} style={styles.iconBtn}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round"><polyline points="15 18 9 12 15 6"/></svg>
          </button>
        )}
        <div style={{ flex:1, minWidth:0 }}>
          <div style={{ color:'#fff', fontSize:15, fontWeight:800, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{title}</div>
          <div style={{ color:'rgba(255,255,255,0.54)', fontSize:10, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{breadcrumbs}</div>
        </div>
        {level === 'map' && (
          <button onClick={() => mapViewRef.current?.printMap()} style={styles.iconBtn} title="नक्शा प्रिंट करें">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round">
              <polyline points="6 9 6 2 18 2 18 9"/>
              <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/>
              <rect x="6" y="14" width="12" height="8"/>
            </svg>
          </button>
        )}
        <button onClick={loadHierarchy} style={styles.iconBtn} title="रिफ्रेश">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round">
            <polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/>
            <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
          </svg>
        </button>
      </div>

      {/* Body */}
      <div style={{ flex:1, overflow:'hidden', position:'relative' }}>
        {loading  ? <div style={styles.center}><Spinner /></div>
        : error   ? <ErrorView error={error} onRetry={loadHierarchy} />
        : level === 'district'  ? <DistrictList districts={districts} onSelect={selectDistrict} />
        : level === 'superZone' ? <SuperZoneList superZones={filteredSuperZones} onSelect={selectSuperZone} />
        : level === 'zone'      ? <ZoneList zones={zones} superZone={superZone} onSelect={selectZone} />
        : <MapView ref={mapViewRef} zone={zone} superZone={superZone} centers={centers} />}
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  List screens
// ══════════════════════════════════════════════════════════════════════════════
function DistrictList({ districts, onSelect }) {
  if (!districts.length) return <Empty text="कोई जिला नहीं मिला" />;
  return (
    <div style={{ overflowY:'auto', height:'100%', padding:14 }}>
      {districts.map((d, i) => (
        <DrillCard key={i}
          leading={<div style={{ width:44, height:44, borderRadius:10, backgroundColor:`${C.primary}1A`, display:'flex', alignItems:'center', justifyContent:'center' }}><CityIcon /></div>}
          title={d.district} subtitle="जिला" color={C.primary} onTap={() => onSelect(d.district)}
        />
      ))}
    </div>
  );
}

function SuperZoneList({ superZones, onSelect }) {
  if (!superZones.length) return <Empty text="कोई सुपर जोन नहीं मिला" />;
  return (
    <div style={{ overflowY:'auto', height:'100%', padding:14 }}>
      {superZones.map((sz, i) => {
        const nm = sz.name || '';
        return (
          <DrillCard key={i}
            leading={<div style={{ width:44, height:44, borderRadius:10, background:'linear-gradient(135deg,#0F2B5B,#1E3F80)', display:'flex', alignItems:'center', justifyContent:'center' }}><span style={{ color:'#fff', fontSize:13, fontWeight:900 }}>{nm.slice(0,2)}</span></div>}
            title={nm} subtitle={`ब्लॉक: ${sz.block||'—'}  •  ${(sz.zones||[]).length} जोन`}
            badge={(sz.officers||[]).length ? `${sz.officers.length} अधिकारी` : null}
            color={C.primary} onTap={() => onSelect(sz)}
          />
        );
      })}
    </div>
  );
}

function ZoneList({ zones, superZone, onSelect }) {
  if (!zones.length) return <Empty text="कोई जोन नहीं मिला" />;
  const szOfficers = superZone?.officers || [];
  return (
    <div style={{ display:'flex', flexDirection:'column', height:'100%', overflow:'hidden' }}>
      {szOfficers.length > 0 && <OfficerBanner label={`सुपर जोन अधिकारी – ${superZone?.name}`} officers={szOfficers} color={C.primary} />}
      <div style={{ overflowY:'auto', flex:1, padding:14 }}>
        {zones.map((z, i) => {
          const sectors = (z.sectors||[]).length;
          let centersCount = 0;
          (z.sectors||[]).forEach(s => (s.panchayats||[]).forEach(gp => centersCount += (gp.centers||[]).length));
          return (
            <DrillCard key={i}
              leading={<div style={{ width:44, height:44, borderRadius:10, backgroundColor:`${C.green}1A`, border:`1px solid ${C.green}4D`, display:'flex', alignItems:'center', justifyContent:'center' }}><MapIcon color={C.green} /></div>}
              title={z.name||''} subtitle={`${sectors} सैक्टर  •  ${centersCount} मतदान केन्द्र`}
              badge={(z.officers||[]).length ? `${z.officers.length} अधिकारी` : null}
              extra={z.hq_address ? `HQ: ${z.hq_address}` : null}
              color={C.green} onTap={() => onSelect(z)}
            />
          );
        })}
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  MapView
//
//  BANNER FIX:
//    • Banner is a sibling of the Leaflet container div, not inside it.
//    • Outer wrapper uses isolation:isolate → z-index:1000 beats Leaflet's
//      internal panes (which max out at ~650).
//    • Banner is COLLAPSIBLE: a chevron button toggles it between a slim
//      title-only bar and the full expanded view. When collapsed the map
//      is fully accessible for pan/zoom beneath the slim bar.
//
//  PRINT FIX (canvas-compose approach — no html2canvas needed):
//    • OSM tiles loaded with crossOrigin:true are CORS-safe for canvas export.
//    • We read tile positions directly from the DOM (getBoundingClientRect),
//      draw each tile onto an offscreen canvas, then draw each CircleMarker
//      (filled dot + white stroke + text label) using Leaflet's own
//      latLngToContainerPoint() for pixel-perfect placement.
//    • The composed PNG is embedded in a print window — tiles AND markers
//      both appear correctly.
// ══════════════════════════════════════════════════════════════════════════════
const MapView = React.forwardRef(function MapView({ zone, superZone, centers }, ref) {
  const mapContainerRef               = useRef(null);
  const mapRef                        = useRef(null);
  const markersRef                    = useRef([]);
  const [selectedCenter, setSelectedCenter] = useState(null);
  const [showSheet, setShowSheet]           = useState(false);
  const [showLegend, setShowLegend]         = useState(false);
  const [bannerCollapsed, setBannerCollapsed] = useState(false);  // ← collapse state

  React.useImperativeHandle(ref, () => ({ printMap }));

  // Fix Leaflet icon URLs broken by bundlers
  useEffect(() => {
    delete L.Icon.Default.prototype._getIconUrl;
    L.Icon.Default.mergeOptions({
      iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
      iconUrl:       'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
      shadowUrl:     'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
    });
  }, []);

  // Init / re-init map
  useEffect(() => {
    if (!centers.length || !mapContainerRef.current) return;

    if (mapRef.current) {
      markersRef.current.forEach(m => m.remove());
      markersRef.current = [];
      mapRef.current.remove();
      mapRef.current = null;
    }

    const map = L.map(mapContainerRef.current, {
      center: [centers[0].latitude, centers[0].longitude],
      zoom: 13, zoomControl: true, attributionControl: true,
    });
    mapRef.current = map;

    // crossOrigin: true is required so tile images can be drawn onto canvas
    // without triggering a security error when we call toDataURL() for print
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      maxZoom: 19,
      crossOrigin: true,
    }).addTo(map);

    centers.forEach(c => {
      const color  = typeColor(c.center_type || c.centerType || 'C');
      const marker = L.circleMarker([c.latitude, c.longitude], {
        radius: 10, fillColor: color, color: '#ffffff',
        weight: 2.5, opacity: 1, fillOpacity: 1,
      }).addTo(map);

      marker.bindTooltip(c.name || '', {
        permanent: true, direction: 'bottom', offset: [0, 8],
        className: 'leaflet-center-label',
      }).openTooltip();

      marker.on('click', () => { setSelectedCenter(c); setShowSheet(false); });
      markersRef.current.push(marker);
    });

    fitAllBounds(map);

    return () => {
      markersRef.current.forEach(m => m.remove());
      markersRef.current = [];
      map.remove();
      mapRef.current = null;
    };
  }, [centers]);

  function fitAllBounds(map) {
    if (!centers.length) return;
    map.fitBounds(L.latLngBounds(centers.map(c => [c.latitude, c.longitude])), { padding: [60, 60] });
  }

  // ── Print: draw tiles + markers onto canvas → open print window ─────────────
  async function printMap() {
    const map   = mapRef.current;
    const mapEl = mapContainerRef.current;
    if (!map || !mapEl) return;

    const W = mapEl.clientWidth;
    const H = mapEl.clientHeight;

    // Offscreen canvas — same pixel size as the visible map
    const canvas = document.createElement('canvas');
    canvas.width  = W;
    canvas.height = H;
    const ctx = canvas.getContext('2d');

    // ── Step 1: draw all visible tiles ──────────────────────────────────────
    // Each Leaflet tile <img> has a bounding rect relative to the page.
    // We subtract the map container's rect to get the local offset.
    const mapRect  = mapEl.getBoundingClientRect();
    const tileEls  = Array.from(mapEl.querySelectorAll('.leaflet-tile'));

    await Promise.all(tileEls.map(tile => new Promise(resolve => {
      if (!tile.src || tile.style.display === 'none' || tile.style.visibility === 'hidden') {
        resolve(); return;
      }
      const tileRect = tile.getBoundingClientRect();
      const dx = Math.round(tileRect.left - mapRect.left);
      const dy = Math.round(tileRect.top  - mapRect.top);
      const dw = Math.round(tileRect.width);
      const dh = Math.round(tileRect.height);

      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload  = () => { try { ctx.drawImage(img, dx, dy, dw, dh); } catch(_){} resolve(); };
      img.onerror = () => resolve();
      // Add cache-bust only if needed; OSM allows CORS by default
      img.src = tile.src;
    })));

    // ── Step 2: draw each marker as a filled circle + label ─────────────────
    centers.forEach(c => {
      const color  = typeColor(c.center_type || c.centerType || 'C');
      const pt     = map.latLngToContainerPoint(L.latLng(c.latitude, c.longitude));
      const RADIUS = 10;

      // Circle fill
      ctx.beginPath();
      ctx.arc(pt.x, pt.y, RADIUS, 0, Math.PI * 2);
      ctx.fillStyle   = color;
      ctx.fill();
      // White stroke
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth   = 2.5;
      ctx.stroke();

      // Name label below dot (with white halo for legibility)
      const label = (c.name || '').trim();
      if (label) {
        ctx.font        = 'bold 10px sans-serif';
        ctx.textAlign   = 'center';
        ctx.textBaseline = 'top';
        ctx.lineWidth   = 3;
        ctx.strokeStyle = 'rgba(255,255,255,0.95)';
        ctx.strokeText(label, pt.x, pt.y + RADIUS + 3);
        ctx.fillStyle   = '#1A2332';
        ctx.fillText(label,   pt.x, pt.y + RADIUS + 3);
      }
    });

    // ── Step 3: build type-count legend HTML ─────────────────────────────────
    const typeCounts = {};
    centers.forEach(c => {
      const t = c.center_type || c.centerType || 'C';
      typeCounts[t] = (typeCounts[t] || 0) + 1;
    });
    const legendHtml = ['A++','A','B','C']
      .filter(t => typeCounts[t])
      .map(t => `
        <span style="display:inline-flex;align-items:center;gap:5px;margin-right:14px">
          <span style="width:10px;height:10px;border-radius:50%;background:${typeColor(t)};display:inline-block"></span>
          <span style="font-size:11px;color:#555">${t}: ${typeCounts[t]}  ${typeLabel(t)}</span>
        </span>`).join('');

    // ── Step 4: open print window with composed PNG ──────────────────────────
    const imgData  = canvas.toDataURL('image/png');
    const printWin = window.open('', '_blank');
    if (!printWin) { alert('Popup blocked — please allow popups for this site.'); return; }

    printWin.document.write(`<!DOCTYPE html><html><head><meta charset="utf-8">
      <title>चुनाव नक्शा – ${zone?.name || ''}</title>
      <style>
        * { box-sizing:border-box; margin:0; padding:0; }
        body { font-family:sans-serif; }
        .header { background:#0F2B5B; color:#fff; padding:12px 18px; }
        .header h2 { font-size:15px; margin-bottom:3px; }
        .header p  { font-size:10px; opacity:0.65; }
        img.map { width:100%; display:block; }
        .footer { padding:10px 18px; border-top:1px solid #eee; display:flex; justify-content:space-between; align-items:center; }
        .date { font-size:10px; color:#999; }
        @media print { body { -webkit-print-color-adjust:exact; print-color-adjust:exact; } }
      </style></head><body>
      <div class="header">
        <h2>चुनाव नक्शा – Election Center Map</h2>
        <p>जोन: ${zone?.name||'—'}  •  सुपर जोन: ${superZone?.name||'—'}  •  ब्लॉक: ${superZone?.block||'—'}  •  कुल केन्द्र: ${centers.length}</p>
      </div>
      <img src="${imgData}" class="map" />
      <div class="footer">
        <div>${legendHtml}</div>
        <span class="date">मुद्रण दिनांक: ${new Date().toLocaleDateString('hi-IN')}</span>
      </div>
      <script>window.onload = () => window.print();<\/script>
    </body></html>`);
    printWin.document.close();
  }

  if (!centers.length) return <Empty text="इस जोन में कोई मतदान केन्द्र नहीं (GPS निर्देशांक उपलब्ध नहीं)" />;

  const typeCounts = {};
  centers.forEach(c => { const t = c.center_type || c.centerType || 'C'; typeCounts[t] = (typeCounts[t]||0)+1; });
  const types = ['A++','A','B','C'].filter(t => typeCounts[t]);

  return (
    // isolation:isolate creates a self-contained stacking context.
    // Our z-index:1000 overlays beat Leaflet's internal panes (max ~650).
    <div style={{ position:'relative', width:'100%', height:'100%', overflow:'hidden', isolation:'isolate' }}>

      {/* Leaflet map fills the full container at the bottom of the stack */}
      <div style={{ position:'absolute', inset:0 }}>
        <div ref={mapContainerRef} style={{ width:'100%', height:'100%' }} />
      </div>

      <LeafletLabelStyle />

      {/*
        Collapsible ZoneInfoBanner
        ─────────────────────────
        • Sits as a sibling of the map div → not trapped in Leaflet's stacking context.
        • pointerEvents:'none' on the outer positioning div lets map touches pass
          through the transparent gaps; inner div restores pointer events.
        • When collapsed → only a slim bar with zone name + chevron is shown,
          so the map beneath is fully pannable/zoomable.
        • When expanded → full info including super-zone, badges, officers.
        • The chevron rotates 180° on collapse so direction is always clear.
      */}
      <div style={{ position:'absolute', top:12, left:12, right:12, zIndex:1000, pointerEvents:'none' }}>
        <div style={{ pointerEvents:'auto' }}>
          <ZoneInfoBanner
            zone={zone} superZone={superZone} centers={centers} typeCounts={typeCounts}
            collapsed={bannerCollapsed}
            onToggle={() => setBannerCollapsed(v => !v)}
          />
        </div>
      </div>

      {/* FABs — bottom right */}
      <div style={{ position:'absolute', bottom:24, right:12, zIndex:1000, display:'flex', flexDirection:'column', gap:8 }}>
        <MapFab icon="print" tooltip="नक्शा प्रिंट करें" color={C.primary} onClick={printMap} />
        <MapFab icon="fit"   tooltip="सभी केन्द्र दिखाएं" onClick={() => fitAllBounds(mapRef.current)} />
        <MapFab icon="info"  tooltip="रंग संकेत"           onClick={() => setShowLegend(true)} />
      </div>

      {/* Legend strip — bottom left */}
      <div style={{ position:'absolute', bottom:24, left:12, zIndex:1000 }}>
        <div style={{ padding:'8px 10px', background:'rgba(26,35,50,0.85)', borderRadius:10 }}>
          {types.map((t, i) => (
            <div key={t} style={{ display:'flex', alignItems:'center', gap:6, marginBottom: i < types.length-1 ? 4 : 0 }}>
              <span style={{ width:10, height:10, borderRadius:'50%', backgroundColor:typeColor(t), flexShrink:0, display:'inline-block' }}/>
              <span style={{ color:'#fff', fontSize:10, fontWeight:700 }}>{t}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Selected center mini-card */}
      {selectedCenter && !showSheet && (
        <div style={{ position:'absolute', bottom:90, left:12, right:60, zIndex:1000 }}>
          <SelectedCenterCard
            center={selectedCenter}
            onTap={() => setShowSheet(true)}
            onClose={() => { setSelectedCenter(null); setShowSheet(false); }}
          />
        </div>
      )}

      {selectedCenter && showSheet && (
        <CenterDetailSheet
          center={selectedCenter}
          onClose={() => { setShowSheet(false); setSelectedCenter(null); }}
        />
      )}

      {showLegend && <LegendDialog onClose={() => setShowLegend(false)} />}
    </div>
  );
});

// ── Leaflet label CSS (injected once) ─────────────────────────────────────────
function LeafletLabelStyle() {
  useEffect(() => {
    if (document.getElementById('leaflet-center-label-style')) return;
    const s = document.createElement('style');
    s.id = 'leaflet-center-label-style';
    s.textContent = `
      .leaflet-center-label {
        background: transparent !important; border: none !important; box-shadow: none !important;
        font-size: 10px !important; font-weight: 600 !important; color: #1A2332 !important;
        white-space: nowrap !important;
        text-shadow: 0 0 3px #fff, 0 0 3px #fff, 0 0 3px #fff !important;
        padding: 0 !important; pointer-events: none !important;
      }
      .leaflet-center-label::before { display: none !important; }
    `;
    document.head.appendChild(s);
  }, []);
  return null;
}

// ══════════════════════════════════════════════════════════════════════════════
//  ZoneInfoBanner — collapsible
//
//  collapsed=false  → full card: zone name, super-zone line, type badges, officers
//  collapsed=true   → slim bar:  just zone name + chevron (minimally intrusive)
//
//  The chevron button is always rendered in the top-right corner of the card.
//  It rotates 180° when expanded so the arrow always points toward its action.
// ══════════════════════════════════════════════════════════════════════════════
function ZoneInfoBanner({ zone, superZone, centers, typeCounts, collapsed, onToggle }) {
  const zOfficers   = zone?.officers || [];
  const szOfficers  = superZone?.officers || [];
  const allOfficers = [...szOfficers, ...zOfficers];

  return (
    <div style={{
      background: 'rgba(15,43,91,0.93)',
      borderRadius: 12,
      border: '1px solid rgba(255,255,255,0.15)',
      overflow: 'hidden',
      backdropFilter: 'blur(8px)',
      WebkitBackdropFilter: 'blur(8px)',
    }}>

      {/* ── Header row — always visible ── */}
      <div style={{ display:'flex', alignItems:'center', gap:8, padding:'10px 10px 10px 12px' }}>
        {/* Zone name + (when expanded) super-zone subtitle */}
        <div style={{ flex:1, minWidth:0 }}>
          <div style={{ color:'#fff', fontSize:13, fontWeight:800, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>
            जोन: {zone?.name}
          </div>
          {!collapsed && (
            <div style={{ color:'rgba(255,255,255,0.6)', fontSize:10, marginTop:2, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>
              सुपर जोन: {superZone?.name}  •  ब्लॉक: {superZone?.block || '—'}
            </div>
          )}
        </div>

        {/* Type-count badges — hidden when collapsed to save space */}
        {!collapsed && (
          <div style={{ display:'flex', flexWrap:'wrap', gap:4, flexShrink:0 }}>
            {Object.entries(typeCounts).map(([t, v]) => (
              <span key={t} style={{
                padding:'2px 6px', borderRadius:5, fontSize:10, fontWeight:700,
                color:typeColor(t), backgroundColor:typeColor(t)+'40',
                border:`1px solid ${typeColor(t)}80`,
              }}>{t}:{v}</span>
            ))}
          </div>
        )}

        {/* Chevron toggle button — always visible */}
        <button
          onClick={onToggle}
          title={collapsed ? 'विस्तार करें' : 'संक्षिप्त करें'}
          style={{
            flexShrink:0, background:'rgba(255,255,255,0.12)', border:'none',
            borderRadius:6, width:28, height:28,
            display:'flex', alignItems:'center', justifyContent:'center',
            cursor:'pointer',
          }}
        >
          {/* Arrow points UP when expanded (click = collapse), DOWN when collapsed (click = expand) */}
          <svg
            width="14" height="14" viewBox="0 0 24 24"
            fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round"
            style={{ transform: collapsed ? 'rotate(180deg)' : 'rotate(0deg)', transition:'transform 0.2s' }}
          >
            <polyline points="18 15 12 9 6 15"/>
          </svg>
        </button>
      </div>

      {/* ── Officers strip — visible only when expanded ── */}
      {!collapsed && allOfficers.length > 0 && (
        <div style={{ borderTop:'1px solid rgba(255,255,255,0.08)', padding:'6px 12px 8px', display:'flex', gap:6, overflowX:'auto' }}>
          {allOfficers.map((o, i) => (
            <div key={i} style={{
              flexShrink:0, padding:'4px 8px', borderRadius:6, fontSize:10,
              color:'rgba(255,255,255,0.8)', background:'rgba(255,255,255,0.08)',
              whiteSpace:'nowrap',
            }}>
              {o.name}  {o.user_rank || ''}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  MapFab
// ══════════════════════════════════════════════════════════════════════════════
function MapFab({ icon, tooltip, onClick, color }) {
  const icons = {
    print: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={color||C.primary} strokeWidth="2" strokeLinecap="round">
      <polyline points="6 9 6 2 18 2 18 9"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/>
    </svg>,
    fit: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={C.primary} strokeWidth="2" strokeLinecap="round">
      <path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/>
    </svg>,
    info: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={C.primary} strokeWidth="2" strokeLinecap="round">
      <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
    </svg>,
  };
  return (
    <button onClick={onClick} title={tooltip} style={{ width:44, height:44, borderRadius:'50%', backgroundColor:C.surface, border:'none', cursor:'pointer', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 3px 8px rgba(0,0,0,0.15)' }}>
      {icons[icon]}
    </button>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  SelectedCenterCard
// ══════════════════════════════════════════════════════════════════════════════
function SelectedCenterCard({ center, onTap, onClose }) {
  const type   = center.center_type || center.centerType || 'C';
  const tColor = typeColor(type);
  return (
    <div onClick={onTap} style={{ background:C.surface, borderRadius:12, border:`1.5px solid ${tColor}66`, boxShadow:'0 4px 12px rgba(0,0,0,0.15)', padding:'10px 8px 10px 12px', display:'flex', alignItems:'center', gap:10, cursor:'pointer' }}>
      <div style={{ width:36, height:36, borderRadius:8, flexShrink:0, backgroundColor:tColor+'1F', border:`1px solid ${tColor}4D`, display:'flex', alignItems:'center', justifyContent:'center' }}>
        <span style={{ color:tColor, fontSize:type.length>1?9:14, fontWeight:900 }}>{type}</span>
      </div>
      <div style={{ flex:1, minWidth:0 }}>
        <div style={{ color:C.dark, fontWeight:700, fontSize:13, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{center.name}</div>
        <div style={{ color:C.subtle, fontSize:10 }}>{[typeLabel(type), center.thana?`थाना: ${center.thana}`:null].filter(Boolean).join('  •  ')}</div>
      </div>
      <div style={{ display:'flex', flexDirection:'column', alignItems:'center', gap:6, flexShrink:0 }}>
        <button onClick={e=>{ e.stopPropagation(); onClose(); }} style={{ background:'none', border:'none', cursor:'pointer', padding:0, lineHeight:1 }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={C.subtle} strokeWidth="2" strokeLinecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={C.primary} strokeWidth="2" strokeLinecap="round"><polyline points="17 11 12 6 7 11"/><line x1="12" y1="18" x2="12" y2="6"/></svg>
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  CenterDetailSheet
// ══════════════════════════════════════════════════════════════════════════════
function CenterDetailSheet({ center, onClose }) {
  const type   = center.center_type || center.centerType || 'C';
  const tColor = typeColor(type);
  const zone   = center._zone;
  const sector = center._sector;
  const gp     = center._gp;
  const szObj  = center._superZone;
  const kendras = center.kendras || [];
  const duty    = center.duty_officers || [];
  const szOff   = szObj?.officers || [];
  const zOff    = zone?.officers || [];
  const sOff    = sector?.officers || [];
  const busNo   = center.bus_no || center.busNo || '';

  return (
    <>
      <div style={{ position:'fixed', bottom:0, left:0, right:0, zIndex:1101, background:C.bg, borderRadius:'20px 20px 0 0', maxHeight:'90vh', display:'flex', flexDirection:'column', boxShadow:'0 -8px 32px rgba(0,0,0,0.2)' }}>
        <div style={{ display:'flex', justifyContent:'center', padding:'10px 0 6px' }}>
          <MoveDown className='cursor-pointer text-gray-500' onClick={onClose} />
        </div>
        <div style={{ margin:'0 16px 8px', background:`linear-gradient(135deg,${tColor},${tColor}B3)`, borderRadius:14, padding:14, display:'flex', alignItems:'center', gap:12 }}>
          <div style={{ padding:'6px 10px', background:'rgba(255,255,255,0.2)', borderRadius:8, color:'#fff', fontSize:16, fontWeight:900 }}>{type}</div>
          <div style={{ flex:1 }}>
            <div style={{ color:'#fff', fontSize:14, fontWeight:800 }}>{center.name}</div>
            <div style={{ color:'rgba(255,255,255,0.8)', fontSize:11 }}>{typeLabel(type)}</div>
          </div>
          {busNo && (
            <div style={{ background:'rgba(255,255,255,0.15)', borderRadius:6, padding:'4px 8px', display:'flex', alignItems:'center', gap:4 }}>
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2"><rect x="1" y="3" width="15" height="13"/><polygon points="16 8 20 8 23 11 23 16 16 16 16 8"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/></svg>
              <span style={{ color:'#fff', fontSize:11, fontWeight:700 }}>{busNo}</span>
            </div>
          )}
        </div>
        <div style={{ overflowY:'auto', flex:1, padding:'0 16px 20px' }}>
          <SheetSection icon="tree" title="पदानुक्रम" color={C.primary}>
            {szObj   && <InfoRow icon="layers" label="सुपर जोन"    value={`${szObj.name} (ब्लॉक: ${szObj.block||'—'})`}/>}
            {zone    && <InfoRow icon="map"    label="जोन"          value={zone.name}/>}
            {sector  && <InfoRow icon="grid"   label="सैक्टर"       value={sector.name}/>}
            {gp      && <InfoRow icon="bank"   label="ग्राम पंचायत" value={gp.name}/>}
            {center.thana && <InfoRow icon="police" label="थाना"   value={center.thana}/>}
          </SheetSection>
          <SheetSection icon="vote" title="मतदेय स्थल / मतदान केन्द्र" color={C.green}>
            {kendras.length === 0
              ? <InfoRow icon="vote" label="मतदान केन्द्र" value={center.name}/>
              : kendras.map((k,i) => <KendraRow key={i} no={i+1} kendra={k} sthalName={center.name}/>)}
          </SheetSection>
          {szOff.length > 0 && <OfficersSection title="सुपर जोन अधिकारी" color={C.primary} officers={szOff}/>}
          {zOff.length  > 0 && <OfficersSection title="जोनल अधिकारी"     color={C.green}   officers={zOff}/>}
          {sOff.length  > 0 && <OfficersSection title="सैक्टर अधिकारी"   color={C.orange}  officers={sOff}/>}
          <SheetSection icon="shield" title={`ड्यूटी पर तैनात स्टाफ (${duty.length})`} color={duty.length?C.red:C.subtle}>
            {duty.length === 0
              ? <p style={{ color:C.subtle, fontSize:12, margin:'8px 0' }}>कोई स्टाफ असाइन नहीं है</p>
              : duty.map((d,i) => <DutyOfficerRow key={i} officer={d}/>)}
          </SheetSection>
        </div>
      </div>
    </>
  );
}

// ── Sheet sub-components ──────────────────────────────────────────────────────
function SheetSection({ icon, title, color, children }) {
  return (
    <div style={{ marginBottom:12, background:C.surface, borderRadius:12, border:`1px solid ${C.border}`, overflow:'hidden' }}>
      <div style={{ padding:'10px 14px', background:color+'12', borderBottom:`1px solid ${color}26`, display:'flex', alignItems:'center', gap:7 }}>
        <SheetIcon name={icon} color={color}/><span style={{ color, fontSize:12, fontWeight:800 }}>{title}</span>
      </div>
      <div style={{ padding:12 }}>{children}</div>
    </div>
  );
}
function InfoRow({ icon, label, value }) {
  if (!value || value==='null' || value==='undefined') return null;
  return (
    <div style={{ display:'flex', alignItems:'flex-start', gap:7, marginBottom:6 }}>
      <SheetIcon name={icon} color={C.subtle} size={13}/>
      <span style={{ width:90, flexShrink:0, color:C.subtle, fontSize:11 }}>{label}</span>
      <span style={{ color:C.dark, fontSize:11, fontWeight:600, flex:1 }}>{value}</span>
    </div>
  );
}
function KendraRow({ no, kendra, sthalName }) {
  return (
    <div style={{ marginBottom:6, padding:'8px 10px', background:C.green+'0D', borderRadius:8, border:`1px solid ${C.green}33`, display:'flex', alignItems:'center', gap:10 }}>
      <div style={{ width:26, height:26, borderRadius:6, background:C.green+'26', display:'flex', alignItems:'center', justifyContent:'center', color:C.green, fontSize:11, fontWeight:900, flexShrink:0 }}>{no}</div>
      <span style={{ color:C.dark, fontSize:12, fontWeight:600 }}>{sthalName} कक्ष {kendra.room_number}</span>
    </div>
  );
}
function OfficersSection({ title, color, officers }) {
  return (
    <SheetSection icon="person" title={title} color={color}>
      {officers.map((o,i) => <OfficerRow key={i} officer={o} color={color}/>)}
    </SheetSection>
  );
}
function OfficerRow({ officer, color }) {
  const name=officer.name||''; const rank=officer.user_rank||officer.rank||'';
  const mobile=officer.mobile||''; const pno=officer.pno||'';
  return (
    <div style={{ marginBottom:6, padding:'8px 10px', background:color+'0D', borderRadius:8, border:`1px solid ${color}26`, display:'flex', alignItems:'center', gap:10 }}>
      <div style={{ width:36, height:36, borderRadius:'50%', flexShrink:0, background:color+'1F', display:'flex', alignItems:'center', justifyContent:'center', color, fontSize:14, fontWeight:800 }}>{name?name[0].toUpperCase():'?'}</div>
      <div>
        <div style={{ color:C.dark, fontSize:12, fontWeight:700 }}>{name||'—'}</div>
        <div style={{ color:C.subtle, fontSize:10 }}>{[rank,pno?`PNO: ${pno}`:null].filter(Boolean).join('  •  ')}</div>
        {mobile && <div style={{ color:C.subtle, fontSize:10 }}>{mobile}</div>}
      </div>
    </div>
  );
}
function DutyOfficerRow({ officer }) {
  const isArmed = officer.isArmed===true || officer.is_armed===true || officer.is_armed===1;
  const acColor = isArmed ? C.red : C.green;
  return (
    <div style={{ marginBottom:6, padding:'8px 10px', background:'#fff', borderRadius:8, border:`1px solid ${isArmed?C.red+'40':C.border}`, display:'flex', alignItems:'center', gap:10 }}>
      <div style={{ width:34, height:34, borderRadius:'50%', flexShrink:0, background:isArmed?C.red+'1A':'#0000001A', display:'flex', alignItems:'center', justifyContent:'center' }}>
        <SheetIcon name={isArmed?'shield':'person'} color={isArmed?C.red:C.subtle} size={16}/>
      </div>
      <div style={{ flex:1 }}>
        <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', gap:8 }}>
          <span style={{ color:C.dark, fontSize:12, fontWeight:700 }}>{officer.name||'—'}</span>
          <span style={{ padding:'2px 6px', borderRadius:5, fontSize:9, fontWeight:700, color:acColor, background:acColor+'1A', border:`1px solid ${acColor}4D` }}>{isArmed?'सशस्त्र':'निःशस्त्र'}</span>
        </div>
        <div style={{ color:C.subtle, fontSize:10 }}>{[officer.user_rank,officer.pno?`PNO: ${officer.pno}`:null,officer.mobile].filter(Boolean).join('  •  ')}</div>
      </div>
    </div>
  );
}

// ── Legend Dialog ─────────────────────────────────────────────────────────────
function LegendDialog({ onClose }) {
  const items = [['A++','अत्यति संवेदनशील'],['A','अति संवेदनशील'],['B','संवेदनशील'],['C','सामान्य']];
  return (
    <>
      <div onClick={onClose} style={{ position:'fixed', inset:0, background:'rgba(0,0,0,0.4)', zIndex:1200 }}/>
      <div style={{ position:'fixed', top:'50%', left:'50%', transform:'translate(-50%,-50%)', background:'#fff', borderRadius:14, padding:20, zIndex:1201, minWidth:260, boxShadow:'0 8px 32px rgba(0,0,0,0.2)' }}>
        <div style={{ fontSize:14, fontWeight:800, marginBottom:14, color:C.dark }}>रंग संकेत</div>
        {items.map(([t,label]) => (
          <div key={t} style={{ display:'flex', alignItems:'center', gap:10, marginBottom:10 }}>
            <div style={{ width:14, height:14, borderRadius:'50%', backgroundColor:typeColor(t), flexShrink:0 }}/>
            <span style={{ fontSize:13 }}>{t} – {label}</span>
          </div>
        ))}
        <button onClick={onClose} style={{ marginTop:8, background:'none', border:`1px solid ${C.border}`, borderRadius:8, padding:'6px 16px', cursor:'pointer', color:C.primary, fontWeight:600, fontSize:13 }}>बंद</button>
      </div>
    </>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shared UI components
// ══════════════════════════════════════════════════════════════════════════════
function DrillCard({ leading, title, subtitle, color, onTap, badge, extra }) {
  const [hovered, setHovered] = useState(false);
  return (
    <div onClick={onTap} onMouseEnter={()=>setHovered(true)} onMouseLeave={()=>setHovered(false)}
      style={{ marginBottom:10, padding:14, cursor:'pointer', background:hovered?'#f0f4ff':C.surface, borderRadius:12, border:`1px solid ${C.border}`, boxShadow:`0 3px 8px ${color}0F`, display:'flex', alignItems:'center', gap:12, transition:'background 0.15s' }}>
      {leading}
      <div style={{ flex:1, minWidth:0 }}>
        <div style={{ color:C.dark, fontSize:14, fontWeight:800 }}>{title}</div>
        <div style={{ color:C.subtle, fontSize:11, marginTop:3 }}>{subtitle}</div>
        {extra && <div style={{ color:C.subtle, fontSize:10 }}>{extra}</div>}
        {badge && <div style={{ display:'inline-block', marginTop:6, padding:'3px 8px', borderRadius:20, background:color+'1A', border:`1px solid ${color}4D`, color, fontSize:10, fontWeight:700 }}>{badge}</div>}
      </div>
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={color+'99'} strokeWidth="2" strokeLinecap="round"><polyline points="9 18 15 12 9 6"/></svg>
    </div>
  );
}

function OfficerBanner({ label, officers, color }) {
  return (
    <div style={{ padding:'10px 16px', backgroundColor:color+'12', flexShrink:0 }}>
      <div style={{ color, fontSize:11, fontWeight:800, marginBottom:6 }}>{label}</div>
      <div style={{ display:'flex', gap:8, overflowX:'auto', paddingBottom:2 }}>
        {officers.map((o,i) => (
          <div key={i} style={{ flexShrink:0, padding:'6px 10px', borderRadius:8, background:color+'1A', border:`1px solid ${color}4D`, color, fontSize:11, fontWeight:600, whiteSpace:'nowrap' }}>
            {o.name}  {o.user_rank||''}
          </div>
        ))}
      </div>
    </div>
  );
}

function Empty({ text }) {
  return (
    <div style={styles.center}>
      <MapIcon color={C.subtle} size={52}/>
      <p style={{ color:C.subtle, fontSize:14, marginTop:12, textAlign:'center', padding:'0 32px' }}>{text}</p>
    </div>
  );
}

function ErrorView({ error, onRetry }) {
  return (
    <div style={styles.center}>
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke={C.red} strokeWidth="1.5"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      <div style={{ marginTop:10, fontSize:15, fontWeight:700, color:C.dark }}>डेटा लोड करने में त्रुटि</div>
      <div style={{ marginTop:6, fontSize:12, color:C.subtle, textAlign:'center', maxWidth:280 }}>{error}</div>
      <button onClick={onRetry} style={{ marginTop:14, background:C.primary, color:'#fff', border:'none', borderRadius:10, padding:'8px 20px', cursor:'pointer', fontSize:13, fontWeight:700, display:'flex', alignItems:'center', gap:6 }}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
        पुनः प्रयास
      </button>
    </div>
  );
}

function Spinner() {
  return <div style={{ width:36, height:36, borderRadius:'50%', border:`3px solid ${C.border}`, borderTopColor:C.primary, animation:'spin 0.8s linear infinite' }}/>;
}

function CityIcon() {
  return <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={C.primary} strokeWidth="1.8" strokeLinecap="round"><rect x="3" y="7" width="7" height="14"/><path d="M10 7l4-4 4 4"/><rect x="14" y="7" width="7" height="14"/><line x1="3" y1="21" x2="21" y2="21"/></svg>;
}
function MapIcon({ color, size=22 }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round"><polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/></svg>;
}
function SheetIcon({ name, color, size=15 }) {
  const s = { width:size, height:size, viewBox:'0 0 24 24', fill:'none', stroke:color, strokeWidth:'1.8', strokeLinecap:'round' };
  switch(name) {
    case 'tree':   return <svg {...s}><path d="M18 3a3 3 0 0 0-3 3l-7 3.5V7.5"/><circle cx="6" cy="12" r="4"/><path d="M10 12h11"/><path d="M21 12v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-8"/></svg>;
    case 'layers': return <svg {...s}><polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/></svg>;
    case 'map':    return <svg {...s}><polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6"/><line x1="8" y1="2" x2="8" y2="18"/><line x1="16" y1="6" x2="16" y2="22"/></svg>;
    case 'grid':   return <svg {...s}><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>;
    case 'bank':   return <svg {...s}><line x1="3" y1="22" x2="21" y2="22"/><line x1="6" y1="18" x2="6" y2="11"/><line x1="10" y1="18" x2="10" y2="11"/><line x1="14" y1="18" x2="14" y2="11"/><line x1="18" y1="18" x2="18" y2="11"/><polygon points="12 2 20 7 4 7 12 2"/></svg>;
    case 'police': return <svg {...s}><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>;
    case 'vote':   return <svg {...s}><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>;
    case 'person': return <svg {...s}><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>;
    case 'shield': return <svg {...s}><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>;
    default:       return <svg {...s}><circle cx="12" cy="12" r="10"/></svg>;
  }
}

const styles = {
  iconBtn: { background:'none', border:'none', cursor:'pointer', padding:8, display:'flex', alignItems:'center', justifyContent:'center', borderRadius:8 },
  center:  { display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', height:'100%', padding:32 },
};

if (typeof document !== 'undefined' && !document.getElementById('map-view-spin')) {
  const s = document.createElement('style');
  s.id = 'map-view-spin';
  s.textContent = `@keyframes spin { to { transform: rotate(360deg); } }`;
  document.head.appendChild(s);
}