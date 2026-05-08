/**
 * DutyCardPage.jsx
 *
 * Full React/desktop equivalent of Flutter's DutyCardPage.
 *
 * Features:
 *  - Election config banner (3-source fallback: /admin/election-config/active →
 *    embedded in /duties → /admin/config)
 *  - Tab 1 — Booth Duty: search, rank/armed/card-download filters, paginated list,
 *    select-all, print selected, print all, per-card print
 *  - Tab 2 — District Duty: expandable duty-type rows, batch list with per-batch
 *    print and print-all
 *  - PDF: buildDutyCardHtml() & buildDistrictDutyCardHtml() produce A6-landscape
 *    cards matching Flutter's layout exactly
 *
 * API endpoints (all from existing api.js + new ones listed at bottom):
 *   GET /admin/election-config/active
 *   GET /admin/duties?page&limit&q&rank&armed&card
 *   GET /admin/district-duty/summary
 *   GET /admin/district-duty/:dutyType/batches
 *   GET /auth/me
 *   GET /admin/config  (legacy fallback)
 */

import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import {
  Search, X, Printer, CheckSquare, Square, Shield, ShieldOff,
  MapPin, Phone, Hash, Bus, Layers, RefreshCw, Download,
  CheckCircle2, ChevronDown, ChevronUp, Users, AlertTriangle,
  Info, Vote, Building2, ChevronLeft, ChevronRight,
  ChevronsLeft, ChevronsRight, Loader2, FileText, Filter,
  RotateCcw, Eye, BarChart3, TrendingUp, BadgeCheck, Calendar,
  Clock, Globe, Star, Zap,
} from 'lucide-react';
import toast, { Toaster } from 'react-hot-toast';
import api from '../../api/client';

// ── Theme (mirrors Flutter kBg / kPrimary etc.) ────────────────────────────
const T = {
  bg:      '#FDF6E3',
  surface: '#F5E6C8',
  primary: '#8B6914',
  accent:  '#B8860B',
  dark:    '#4A3000',
  subtle:  '#AA8844',
  border:  '#D4A843',
  error:   '#C0392B',
  success: '#2D6A1E',
  info:    '#1A5276',
  armed:   '#C62828',
  unarmed: '#1565C0',
};

// ── Rank map (Hindi abbr.) ─────────────────────────────────────────────────
const RANK_MAP = {
  constable:'कां0','head constable':'हो0गा0',si:'उ0नि0',
  'sub inspector':'उ0नि0',inspector:'निरीक्षक',asi:'स0उ0नि0',
  'assistant sub inspector':'स0उ0नि0',dsp:'उपाधीक्षक',
  asp:'सहा0 पुलिस अधीक्षक',sp:'पुलिस अधीक्षक',
  'circle officer':'क्षेत्राधिकारी',co:'क्षेत्राधिकारी',
};
const ALL_RANKS = ['SP','ASP','DSP','Inspector','SI','ASI','Head Constable','Constable'];

const RANK_PALETTE = {
  SP:             { text:'#6C3483', bg:'#f3e5f5', border:'#d7b8e8' },
  ASP:            { text:'#1A5276', bg:'#e3f0fb', border:'#a9cce3' },
  DSP:            { text:'#0E6655', bg:'#e8f5f0', border:'#a2d9c8' },
  INSPECTOR:      { text:'#1F618D', bg:'#dbeeff', border:'#9ac3e6' },
  SI:             { text:'#117A65', bg:'#e0f5f0', border:'#82c7b8' },
  ASI:            { text:'#B7950B', bg:'#fdf5d9', border:'#e6cc65' },
  'HEAD CONSTABLE':{ text:'#BA4A00', bg:'#fde8dc', border:'#f0a87a' },
  CONSTABLE:      { text:'#6E2F1A', bg:'#fbe5d6', border:'#d4836d' },
};

// ── Helpers ────────────────────────────────────────────────────────────────
const rh  = v => RANK_MAP[(v||'').toLowerCase().trim()] || v || '—';
const vd  = x => (x==null||String(x).trim()==='') ? '—' : String(x);
const isArmedFn  = s => s.isArmed===true||s.is_armed===true||s.is_armed===1||s.isArmed===1;
const isDownFn   = s => Number(s.card_downloaded||0) > 0 || s.card_downloaded===true;
const rankPal    = r => RANK_PALETTE[(r||'').toUpperCase()] || { text:T.primary, bg:T.surface, border:T.border };

/**
 * Robustly parse any date/datetime string → "DD.MM.YYYY"
 * Handles:
 *   "2024-04-26"                        → "26.04.2024"
 *   "26.04.2024"                        → "26.04.2024"  (passthrough)
 *   "Mon May 04 2026 05:30:00 GMT+0530" → "04.05.2026"
 *   JS Date object                      → "DD.MM.YYYY"
 *   MySQL "2026-05-04T00:00:00.000Z"    → "04.05.2026"
 */
function normaliseDate(raw) {
  if (!raw) return '';
  const s = String(raw).trim();

  // Already DD.MM.YYYY
  if (/^\d{2}\.\d{2}\.\d{4}$/.test(s)) return s;

  // YYYY-MM-DD  or  YYYY-MM-DDTHH:...
  const isoMatch = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (isoMatch) return `${isoMatch[3]}.${isoMatch[2]}.${isoMatch[1]}`;

  // Full JS toString / GMT string — parse via Date
  try {
    const d = new Date(s);
    if (!isNaN(d.getTime())) {
      const dd = String(d.getDate()).padStart(2,'0');
      const mm = String(d.getMonth()+1).padStart(2,'0');
      const yyyy = d.getFullYear();
      return `${dd}.${mm}.${yyyy}`;
    }
  } catch {}

  return s;
}

/**
 * Normalise a time string → "HH:MM" (24-hr) for display / print.
 * Strips any timezone suffix, handles full datetime strings.
 * E.g. "Mon May 04 2026 10:00:00 GMT+0530" → "10:00"
 *      "10:00"                              → "10:00"
 *      "2026-05-04T10:00:00.000Z"           → "10:00" (IST +5:30)
 */
function normaliseTime(raw) {
  if (!raw) return '';
  const s = String(raw).trim();

  // Already HH:MM or HH:MM:SS
  if (/^\d{1,2}:\d{2}(:\d{2})?$/.test(s)) return s.slice(0,5);

  // Full datetime string
  try {
    const d = new Date(s);
    if (!isNaN(d.getTime())) {
      // Show in IST (UTC+5:30)
      const utcMs = d.getTime() + (5.5 * 60 * 60 * 1000);
      const ist   = new Date(utcMs);
      const hh    = String(ist.getUTCHours()).padStart(2,'0');
      const mm    = String(ist.getUTCMinutes()).padStart(2,'0');
      return `${hh}:${mm}`;
    }
  } catch {}

  return s.slice(0,5);
}

// ── Election Config ────────────────────────────────────────────────────────
function parseConfig(m, adminDistrict='') {
  if (!m || !Object.keys(m).length) return null;
  const rawDate   = m.electionDate   || m.election_date   || '';
  const rawPratah = m.pratahSamay    || m.pratah_samay    || '';
  const rawSaya   = m.sayaSamay      || m.saya_samay      || '';
  const date      = normaliseDate(rawDate);
  const year      = m.electionYear   || m.election_year   ||
                    (date.length>=4 ? date.slice(-4) : new Date().getFullYear().toString());
  const pratah    = normaliseTime(rawPratah) || '07:00';
  const saya      = normaliseTime(rawSaya)   || '06:00';

  return {
    district:     m.district     || adminDistrict || '',
    state:        m.state        || '',
    electionType: m.electionType || m.election_type || '',
    electionName: m.electionName || m.election_name || '',
    phase:        m.phase        || 'द्वितीय',
    electionYear: String(year),
    electionDate: date,
    pratahSamay:  pratah,
    sayaSamay:    saya,
  };
}

// ══════════════════════════════════════════════════════════════════════════
//  PDF HTML BUILDERS
// ══════════════════════════════════════════════════════════════════════════

const FONT_LINK = `<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700&display=swap" rel="stylesheet">`;

const BASE_CSS = `
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Noto Sans Devanagari',sans-serif;font-size:6px;background:#fff;color:#000;print-color-adjust:exact;-webkit-print-color-adjust:exact}
@page{margin:3mm;size:A6 landscape}
@media print{.card{page-break-after:always}.no-print{display:none!important}}
`;

/* ── Booth duty card (mirrors buildDutyCardPdf) ─────────────────────────── */
function buildDutyCardHtml(cards, cfg={}) {
  // Sanitise all config values before injecting into HTML
  const district    = cfg.district     || 'बागपत';
  const state       = cfg.state        || 'उत्तर प्रदेश';
  const elecName    = cfg.electionName || 'लोकसभा सामान्य निर्वाचन';
  const phase       = cfg.phase        || 'द्वितीय';
  // Extra normalise in case config came from a raw server response
  const date        = normaliseDate(cfg.electionDate) || '—';
  const year        = cfg.electionYear || (date.length>=4 ? date.slice(-4) : '');
  const pratah      = normaliseTime(cfg.pratahSamay)  || '07:00';
  const saya        = normaliseTime(cfg.sayaSamay)    || '06:00';

  const officerBlock = (title, name, mobile, rank) => `
    <div style="border-bottom:.4px solid #bbb">
      <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:4.8px;border-bottom:.3px solid #999">${title}</div>
      <div style="padding:2px;text-align:center;font-size:4.3px;line-height:1.5">${[rank,name,mobile].filter(Boolean).join('<br>')}</div>
    </div>`;

  const cardHTML = cards.map(s => {
    const sahyogi     = s.sahyogi||s.allStaff||s.all_staff||[];
    const totalRows   = Math.max(12, sahyogi.length);
    const zonalOff    = s.zonalOfficers||s.zonal_officers||[];
    const sectorOff   = s.sectorOfficers||s.sector_officers||[];
    const superOff    = s.superOfficers||s.super_officers||[];
    const zonalMag    = zonalOff[0]||null;
    const sectorMag   = sectorOff[0]||null;
    const zonalPol    = superOff[0]||null;
    const sectorPol   = sectorOff[1]||sectorOff[0]||null;
    const busNo       = vd(s.busNo||s.bus_no);
    const armedLabel  = isArmedFn(s)?'सशस्त्र':'निःशस्त्र';
    const cardDistrict= (s.adminDistrict||'').trim()||district;

    const staffRows = Array.from({length:totalRows}).map((_,i)=>{
      const e = sahyogi[i]||null;
      const bg= i%2===0?'#fff':'#f5f5f5';
      return `<tr style="background:${bg}">
        <td>${e?rh(e.user_rank||e.rank):''}</td>
        <td>${e?vd(e.pno):''}</td>
        <td style="font-weight:${e?700:400}">${e?vd(e.name):''}</td>
        <td>${e?vd(e.mobile):''}</td>
        <td>${e?vd(e.thana):''}</td>
        <td>${e?vd(e.district):''}</td>
        <td style="text-align:center">${e?(isArmedFn(e)?'स.':'नि.'):''}</td>
      </tr>`;
    }).join('');

    const metaRows = [
      ['म0 केंद्र सं0', vd(s.centerId||s.center_id)],
      ['बूथ सं0',       vd(s.boothNo||s.booth_no)],
      ['थाना',          vd(s.staffThana||s.thana)],
      ['जोन न0',        vd(s.zoneName||s.zone_name)],
      ['सेक्टर न0',     vd(s.sectorName||s.sector_name)],
      ['वि0स0','—'],
      ['श्रेणी',        vd(s.centerType||s.center_type||'0')],
    ].map(([k,v])=>`
      <div style="display:flex;border-bottom:.3px solid #ddd">
        <span style="background:#eee;flex:2;padding:1px;font-weight:700;font-size:4px;border-right:.3px solid #ccc">${k}</span>
        <span style="flex:3;padding:1px;font-size:4px">${v}</span>
      </div>`).join('');

    return `
<div class="card" style="border:1px solid #333;display:flex;flex-direction:column;width:148mm;height:104mm;overflow:hidden;page-break-after:always;flex-shrink:0">

  <!-- HEADER -->
  <div style="display:flex;border-bottom:.8px solid #333;flex-shrink:0">
    <div style="width:40px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:7px;border-right:.5px solid #333;padding:2px;text-align:center">ECI</div>
    <div style="flex:1;padding:2px 4px;text-align:center">
      <div style="font-size:10px;font-weight:700;text-decoration:underline;line-height:1.2">ड्यूटी कार्ड</div>
      <div style="font-size:6.5px;font-weight:700;line-height:1.2">${elecName}–${year}</div>
      ${state?`<div style="font-size:5px;line-height:1.2">राज्य: ${state}</div>`:''}
      <div style="font-size:6px;line-height:1.2">जनपद ${cardDistrict}</div>
      <div style="font-size:5px;font-weight:700;border-top:.5px solid #aaa;margin-top:1px;padding-top:1px;line-height:1.2">मतदान चरण–${phase} &nbsp; दिनांक ${date} &nbsp; प्रातः ${pratah} से सांय ${saya} तक</div>
    </div>
    <div style="width:40px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:6px;border-left:.5px solid #333;padding:2px;text-align:center;line-height:1.4">उ0प्र0<br>पुलिस</div>
  </div>

  <!-- PRIMARY ROW TABLE -->
  <table style="width:100%;border-collapse:collapse;border:.5px solid #999;flex-shrink:0;table-layout:fixed;font-size:5px">
    <colgroup><col style="width:14%"><col style="width:7%"><col style="width:9%"><col style="width:18%"><col style="width:11%"><col style="width:11%"><col style="width:10%"><col style="width:7%"><col style="width:13%"></colgroup>
    <thead><tr>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999;line-height:1.2">नाम अधि0/<br>कर्म0 गण</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">पद</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">बैज सं0</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">नाम अधि0/कर्म0</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">मोबाइल न0</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">तैनाती</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">जनपद</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999;line-height:1.2">स0/<br>नि0</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999;line-height:1.2">वाहन<br>संख्या</th>
    </tr></thead>
    <tbody><tr>
      <td style="border:.5px solid #999;padding:1px"></td>
      <td style="border:.5px solid #999;padding:1px;font-weight:700;text-align:center">${rh(s.rank||s.user_rank)}</td>
      <td style="border:.5px solid #999;padding:1px;text-align:center">${vd(s.pno)}</td>
      <td style="border:.5px solid #999;padding:1px;font-weight:700">${vd(s.name)}</td>
      <td style="border:.5px solid #999;padding:1px;text-align:center">${vd(s.mobile)}</td>
      <td style="border:.5px solid #999;padding:1px;text-align:center">${vd(s.staffThana||s.thana)}</td>
      <td style="border:.5px solid #999;padding:1px;text-align:center">${vd(s.district)}</td>
      <td style="border:.5px solid #999;padding:1px;font-size:4.3px;text-align:center">${armedLabel}</td>
      <td style="border:.5px solid #999;padding:1px;text-align:center;font-weight:700">${busNo!=='—'?'बस–'+busNo:'—'}</td>
    </tr></tbody>
  </table>

  <!-- MIDDLE: duty location | sahyogi | bus panel -->
  <div style="display:flex;flex:1;border-top:.5px solid #999;overflow:hidden;min-height:0">

    <div style="width:48px;border-right:.5px solid #999;display:flex;flex-direction:column;flex-shrink:0">
      <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5px;border-bottom:.5px solid #999;flex-shrink:0">डियूटी स्थान</div>
      <div style="flex:1;padding:2px;text-align:center;font-weight:700;font-size:5px;display:flex;align-items:center;justify-content:center;line-height:1.3">${vd(s.centerName||s.center_name)}</div>
      <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5px;border-top:.5px solid #999;border-bottom:.5px solid #999;flex-shrink:0">डियूटी प्रकार</div>
      <div style="flex:1;padding:2px;text-align:center;font-weight:700;font-size:5px;display:flex;align-items:center;justify-content:center">बूथ डियूटी</div>
    </div>

    <div style="flex:1;overflow:hidden;display:flex;flex-direction:column;min-width:0">
      <table style="width:100%;border-collapse:collapse;table-layout:fixed;font-size:4.5px;flex-shrink:0">
        <colgroup><col style="width:9%"><col style="width:14%"><col style="width:24%"><col style="width:16%"><col style="width:15%"><col style="width:14%"><col style="width:8%"></colgroup>
        <thead><tr>
          <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">पद</th>
          <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">बैज सं0</th>
          <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">नाम</th>
          <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">मोबाइल</th>
          <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">तैनाती</th>
          <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">जनपद</th>
          <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-bottom:.5px solid #999">स0/नि0</th>
        </tr></thead>
        <tbody>${staffRows}</tbody>
      </table>
    </div>

    <div style="width:26px;border-left:.5px solid #999;display:flex;flex-direction:column;flex-shrink:0;font-size:4.5px">
      <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:4.3px;border-bottom:.5px solid #999">बस–${busNo}</div>
      <div style="padding:2px;text-align:center;font-size:4px;line-height:1.4">दिनांक<br><strong>${date}</strong></div>
      <div style="flex:1"></div>
      <div style="padding:1px;text-align:center;font-size:4px;border-top:.5px solid #bbb">सीपीएम एफ</div>
      <div style="padding:1px;text-align:center;font-size:4px;border-top:.5px solid #bbb">1/2 सै0</div>
    </div>
  </div>

  <!-- FOOTER -->
  <div style="display:flex;border-top:.8px solid #333;flex-shrink:0">
    <div style="width:48px;border-right:.5px solid #999;flex-shrink:0">${metaRows}</div>
    <div style="flex:1;border-right:.5px solid #999">
      ${officerBlock('जोनल मजिस्ट्रेट', zonalMag?.name, zonalMag?.mobile, null)}
      ${officerBlock('जोनल पुलिस अधिकारी', zonalPol?.name, zonalPol?.mobile, zonalPol?rh(zonalPol.user_rank):null)}
    </div>
    <div style="flex:1;border-right:.5px solid #999">
      ${officerBlock('सैक्टर मजिस्ट्रेट', sectorMag?.name, sectorMag?.mobile, null)}
      ${officerBlock('सेक्टर पुलिस अधिकारी', sectorPol?.name, sectorPol?.mobile, sectorPol?rh(sectorPol.user_rank):null)}
    </div>
    <div style="width:36px;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:3px;flex-shrink:0">
      <div style="height:14px;width:28px;border-bottom:.5px solid #333"></div>
      <div style="font-size:5px;font-weight:700;text-align:center;margin-top:2px;line-height:1.4">पुलिस अधीक्षक<br>${cardDistrict}</div>
    </div>
  </div>

</div>`;
  }).join('');

  return `<!DOCTYPE html><html><head><meta charset="UTF-8">${FONT_LINK}
    <style>${BASE_CSS}table td,table th{overflow:hidden;white-space:nowrap;text-overflow:ellipsis}</style>
  </head><body>${cardHTML}</body></html>`;
}

/* ── District duty batch card (mirrors buildDistrictDutyCardPdf) ─────────── */
function buildDistrictDutyCardHtml(batches, dutyLabelHi, cfg={}) {
  // Sanitise all config values
  const district  = cfg.district     || 'बागपत';
  const state     = cfg.state        || 'उत्तर प्रदेश';
  const elecName  = cfg.electionName || 'लोकसभा सामान्य निर्वाचन';
  const phase     = cfg.phase        || 'द्वितीय';
  const date      = normaliseDate(cfg.electionDate) || '—';
  const year      = cfg.electionYear || (date.length>=4 ? date.slice(-4) : '');
  const pratah    = normaliseTime(cfg.pratahSamay)  || '07:00';
  const saya      = normaliseTime(cfg.sayaSamay)    || '06:00';

  const cardHTML = batches.map(b => {
    const batchNo   = b.batchNo || b.batch_no || 1;
    const busNo     = vd(b.busNo || b.bus_no);
    const note      = (b.note||'').toString().trim();
    const staffList = b.staff || [];
    const totalRows = Math.max(14, staffList.length);

    const staffRows = Array.from({length:totalRows}).map((_,i)=>{
      const e = staffList[i]||null;
      const bg= i%2===0?'#fff':'#f5f5f5';
      return `<tr style="background:${bg}">
        <td style="text-align:center">${i+1}</td>
        <td>${e?rh(e.rank||e.user_rank):''}</td>
        <td>${e?vd(e.pno):''}</td>
        <td style="font-weight:${e?700:400}">${e?vd(e.name):''}</td>
        <td>${e?vd(e.mobile):''}</td>
        <td>${e?vd(e.thana):''}</td>
        <td>${e?vd(e.district):''}</td>
        <td style="text-align:center">${e?(isArmedFn(e)?'स.':'नि.'):''}</td>
      </tr>`;
    }).join('');

    const metaRows = [
      ['ड्यूटी प्रकार', dutyLabelHi],
      ['बैच सं0',       String(batchNo)],
      ['बस सं0',        busNo],
      ['चरण',           phase],
      ['मतदान दिनांक',  date],
      ['जनपद',          district],
    ].map(([k,v])=>`
      <div style="display:flex;border-bottom:.3px solid #ddd">
        <span style="background:#eee;flex:2;padding:1px;font-weight:700;font-size:4px;border-right:.3px solid #ccc">${k}</span>
        <span style="flex:3;padding:1px;font-size:4px">${v}</span>
      </div>`).join('');

    return `
<div class="card" style="border:1px solid #333;display:flex;flex-direction:column;width:148mm;height:104mm;overflow:hidden;page-break-after:always;flex-shrink:0">

  <!-- HEADER -->
  <div style="display:flex;border-bottom:.8px solid #333;flex-shrink:0">
    <div style="width:40px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:7px;border-right:.5px solid #333;padding:2px;text-align:center">ECI</div>
    <div style="flex:1;padding:2px 4px;text-align:center">
      <div style="font-size:9px;font-weight:700;text-decoration:underline;line-height:1.2">ड्यूटी कार्ड (जनपदीय)</div>
      <div style="font-size:6.5px;font-weight:700;line-height:1.2">${elecName}–${year}</div>
      ${state?`<div style="font-size:5px;line-height:1.2">राज्य: ${state}</div>`:''}
      <div style="font-size:6px;line-height:1.2">जनपद ${district}</div>
      <div style="font-size:5px;font-weight:700;border-top:.5px solid #aaa;margin-top:1px;padding-top:1px;line-height:1.2">मतदान चरण–${phase} &nbsp; दिनांक ${date} &nbsp; प्रातः ${pratah} से सांय ${saya} तक</div>
    </div>
    <div style="width:40px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:6px;border-left:.5px solid #333;padding:2px;text-align:center;line-height:1.4">उ0प्र0<br>पुलिस</div>
  </div>

  <!-- BATCH INFO TABLE -->
  <table style="width:100%;border-collapse:collapse;border:.5px solid #999;flex-shrink:0;table-layout:fixed;font-size:5px">
    <colgroup><col style="width:28%"><col style="width:12%"><col style="width:18%"><col style="width:18%"><col style="width:24%"></colgroup>
    <thead><tr>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">ड्यूटी प्रकार</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">बैच सं0</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">बस सं0</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">दिनांक</th>
      <th style="background:#ddd;font-size:4.8px;text-align:center;padding:1px;border:.5px solid #999">कुल कर्मी</th>
    </tr></thead>
    <tbody><tr>
      <td style="border:.5px solid #999;padding:1px 2px;font-weight:700;font-size:5.5px">${dutyLabelHi}</td>
      <td style="border:.5px solid #999;padding:1px;text-align:center;font-weight:700;font-size:5.5px">${batchNo}</td>
      <td style="border:.5px solid #999;padding:1px;text-align:center;font-weight:700;font-size:5px">${busNo}</td>
      <td style="border:.5px solid #999;padding:1px;text-align:center;font-size:5px">${date}</td>
      <td style="border:.5px solid #999;padding:1px;text-align:center;font-weight:700;font-size:5.5px">${staffList.length}</td>
    </tr></tbody>
  </table>

  ${note?`<div style="background:#f9f9f9;border-bottom:.4px solid #ccc;padding:2px 4px;display:flex;gap:4px;flex-shrink:0">
    <span style="font-weight:700;font-size:4.5px">विशेष टिप्पणी:</span>
    <span style="font-size:4.5px">${note}</span>
  </div>`:''}

  <!-- STAFF TABLE -->
  <div style="flex:1;display:flex;flex-direction:column;overflow:hidden;min-height:0">
    <table style="width:100%;border-collapse:collapse;table-layout:fixed;font-size:4.5px">
      <colgroup><col style="width:5%"><col style="width:11%"><col style="width:10%"><col style="width:24%"><col style="width:14%"><col style="width:14%"><col style="width:14%"><col style="width:8%"></colgroup>
      <thead><tr>
        <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">क्र0</th>
        <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">पद</th>
        <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">बैज सं0</th>
        <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">नाम</th>
        <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">मोबाइल</th>
        <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">थाना</th>
        <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-right:.3px solid #bbb;border-bottom:.5px solid #999">जनपद</th>
        <th style="background:#ddd;font-size:4.3px;font-weight:700;text-align:center;padding:1px;border-bottom:.5px solid #999">स0/नि0</th>
      </tr></thead>
      <tbody>${staffRows}</tbody>
    </table>
  </div>

  <!-- FOOTER -->
  <div style="display:flex;border-top:.8px solid #333;flex-shrink:0">
    <div style="width:80px;border-right:.5px solid #999;flex-shrink:0">${metaRows}</div>
    <div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:4px">
      <div style="height:14px;width:50px;border-bottom:.5px solid #333"></div>
      <div style="font-size:5.5px;font-weight:700;text-align:center;margin-top:2px;line-height:1.4">पुलिस अधीक्षक<br>${district}</div>
    </div>
  </div>

</div>`;
  }).join('');

  return `<!DOCTYPE html><html><head><meta charset="UTF-8">${FONT_LINK}
    <style>${BASE_CSS}table td,table th{overflow:hidden;white-space:nowrap;text-overflow:ellipsis}</style>
  </head><body>${cardHTML}</body></html>`;
}

/* ── Trigger print via iframe ─────────────────────────────────────────────── */
function triggerPrint(html) {
  const ifr = document.createElement('iframe');
  ifr.style.cssText = 'position:fixed;top:-9999px;left:-9999px;width:148mm;height:108mm;border:none;visibility:hidden';
  document.body.appendChild(ifr);
  const doc = ifr.contentDocument || ifr.contentWindow.document;
  doc.open(); doc.write(html); doc.close();
  ifr.onload = () => {
    setTimeout(() => {
      try { ifr.contentWindow.focus(); ifr.contentWindow.print(); }
      catch(e) { console.error(e); }
      setTimeout(() => document.body.removeChild(ifr), 3000);
    }, 700);
  };
}

// ══════════════════════════════════════════════════════════════════════════
//  SMALL UI ATOMS
// ══════════════════════════════════════════════════════════════════════════

const Chip = ({label,selected,color,bg,border,onClick,icon:Icon}) => (
  <button onClick={onClick} style={{
    display:'inline-flex',alignItems:'center',gap:4,padding:'5px 12px',borderRadius:20,
    fontSize:11,fontWeight:selected?800:600,cursor:'pointer',whiteSpace:'nowrap',
    border:`${selected?1.5:1}px solid ${selected?color:border}`,
    background:selected?color:bg,color:selected?'#fff':color,
    transition:'all .15s',fontFamily:'inherit',
  }}>
    {Icon && <Icon size={11}/>}{label}
  </button>
);

const Tag = ({icon:Icon,text,color}) => (
  <span style={{display:'inline-flex',alignItems:'center',gap:3,color:color||T.subtle,fontSize:11,overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap',maxWidth:220}}>
    <Icon size={11} style={{flexShrink:0}}/>{text}
  </span>
);

const StatBadge = ({label,value,color}) => (
  <span style={{
    display:'inline-flex',alignItems:'center',gap:5,padding:'3px 10px',borderRadius:8,
    background:`${color}14`,border:`1px solid ${color}30`,fontSize:11,
  }}>
    <span style={{color:`${color}bb`,fontWeight:600}}>{label}</span>
    <span style={{color,fontWeight:800,fontSize:12}}>{value}</span>
  </span>
);

const PillBtn = ({label,icon:Icon,color,onClick,disabled}) => (
  <button onClick={onClick} disabled={disabled} style={{
    display:'inline-flex',alignItems:'center',gap:6,padding:'7px 16px',borderRadius:9,
    border:'none',background:disabled?T.subtle:color,color:'#fff',
    fontSize:12,fontWeight:700,cursor:disabled?'not-allowed':'pointer',
    opacity:disabled?.65:1,transition:'all .2s',fontFamily:'inherit',
  }}>
    {Icon&&<Icon size={14}/>}{label}
  </button>
);

// ══════════════════════════════════════════════════════════════════════════
//  BOOTH DUTY CARD ROW
// ══════════════════════════════════════════════════════════════════════════
const BoothCard = ({s,index,selected,onToggle,onPrint}) => {
  const armed      = isArmedFn(s);
  const downloaded = isDownFn(s);
  const rc         = rankPal(s.rank||s.user_rank||'');
  const sahyogi    = s.sahyogi||[];
  const busNo      = s.busNo||s.bus_no||'';

  return (
    <div onClick={()=>onToggle(s.id)} style={{
      borderRadius:12,cursor:'pointer',overflow:'hidden',transition:'all .15s',
      border:`${selected?1.5:1}px solid ${selected?T.primary:downloaded?T.success+99:T.border+'66'}`,
      background:selected?`${T.primary}07`:downloaded?`${T.success}05`:'white',
      boxShadow:downloaded?`0 2px 12px ${T.success}18`:`0 2px 10px ${T.primary}08`,
    }}>
      <div style={{padding:'13px 16px',display:'flex',alignItems:'flex-start',gap:13}}>

        {/* Index / checkbox */}
        <div onClick={e=>{e.stopPropagation();onToggle(s.id);}} style={{
          width:42,height:42,borderRadius:'50%',flexShrink:0,marginTop:2,
          border:`1.5px solid ${selected?T.primary:downloaded?T.success:T.border}`,
          background:selected?T.primary:downloaded?`${T.success}20`:T.surface,
          display:'flex',alignItems:'center',justifyContent:'center',cursor:'pointer',position:'relative',
        }}>
          {selected
            ? <CheckSquare size={18} color="white"/>
            : <span style={{color:downloaded?T.success:T.primary,fontWeight:800,fontSize:12}}>{index+1}</span>
          }
          {downloaded&&!selected&&(
            <div style={{position:'absolute',bottom:-3,right:-3,width:16,height:16,borderRadius:'50%',
              background:T.success,border:'2px solid white',display:'flex',alignItems:'center',justifyContent:'center'}}>
              <CheckCircle2 size={9} color="white"/>
            </div>
          )}
        </div>

        {/* Content */}
        <div style={{flex:1,minWidth:0}}>
          <div style={{display:'flex',alignItems:'center',flexWrap:'wrap',gap:6,marginBottom:5}}>
            <span style={{color:T.dark,fontWeight:700,fontSize:14}}>{s.name}</span>

            {downloaded&&(
              <span style={{display:'inline-flex',alignItems:'center',gap:3,padding:'2px 7px',borderRadius:5,
                fontSize:9.5,fontWeight:700,color:T.success,background:`${T.success}12`,border:`1px solid ${T.success}30`}}>
                <CheckCircle2 size={9}/> कार्ड लिया
              </span>
            )}
            <span style={{display:'inline-flex',alignItems:'center',gap:3,padding:'2px 7px',borderRadius:5,
              fontSize:9.5,fontWeight:700,color:armed?T.armed:T.unarmed,
              background:armed?`${T.armed}10`:`${T.unarmed}10`,
              border:`1px solid ${armed?T.armed:T.unarmed}30`}}>
              {armed?<Shield size={9}/>:<ShieldOff size={9}/>}
              {armed?'सशस्त्र':'निःशस्त्र'}
            </span>
            <span style={{display:'inline-flex',alignItems:'center',padding:'2px 8px',borderRadius:6,
              fontSize:10,fontWeight:700,color:rc.text,background:rc.bg,border:`1px solid ${rc.border}`}}>
              {rh(s.rank||s.user_rank||'')}
            </span>
            {sahyogi.length>0&&(
              <span style={{display:'inline-flex',alignItems:'center',gap:3,padding:'2px 7px',borderRadius:5,
                fontSize:9.5,fontWeight:600,color:T.success,background:`${T.success}10`,border:`1px solid ${T.success}25`}}>
                <Users size={9}/>{sahyogi.length} सहयोगी
              </span>
            )}
          </div>
          <div style={{display:'flex',flexWrap:'wrap',gap:'3px 14px',marginBottom:3}}>
            <Tag icon={BadgeCheck} text={vd(s.pno)}/>
            <Tag icon={Phone} text={vd(s.mobile)}/>
            {busNo&&<Tag icon={Bus} text={`बस–${busNo}`} color={T.accent}/>}
          </div>
          <div style={{marginBottom:2}}>
            <Tag icon={MapPin} text={`${vd(s.centerName||s.center_name)} • ${vd(s.gpName||s.gp_name)}`} color={T.info}/>
          </div>
          <Tag icon={Layers} text={`${vd(s.sectorName)} › ${vd(s.zoneName)} › ${vd(s.superZoneName)}`}/>
        </div>

        {/* Print button */}
        <button onClick={e=>{e.stopPropagation();onPrint([{...s}]);}} style={{
          background:'none',border:`1px solid ${T.border}`,borderRadius:8,
          padding:'7px 9px',cursor:'pointer',color:T.primary,flexShrink:0,
          display:'flex',alignItems:'center',justifyContent:'center',transition:'background .15s',
        }}
          onMouseEnter={e=>e.currentTarget.style.background=T.surface}
          onMouseLeave={e=>e.currentTarget.style.background='none'}>
          <Printer size={16}/>
        </button>
      </div>
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════
//  PAGINATION
// ══════════════════════════════════════════════════════════════════════════
const Pagination = ({page,totalPages,total,onPage}) => {
  if (totalPages<=1) return null;
  const pages=[];
  for(let i=1;i<=totalPages;i++){
    if(i===1||i===totalPages||Math.abs(i-page)<=2) pages.push(i);
    else if(pages[pages.length-1]!=='...') pages.push('...');
  }
  const btnStyle=(active,disabled)=>({
    minWidth:32,height:32,borderRadius:8,display:'inline-flex',alignItems:'center',justifyContent:'center',
    border:`1px solid ${active?T.primary:T.border}`,
    background:active?T.primary:'white',color:active?'white':disabled?T.subtle:T.dark,
    fontSize:12,fontWeight:700,cursor:disabled?'not-allowed':'pointer',opacity:disabled?.4:1,transition:'all .15s',
  });
  return (
    <div style={{display:'flex',alignItems:'center',justifyContent:'space-between',padding:'10px 20px',
      background:'white',borderTop:`1px solid ${T.border}44`,flexWrap:'wrap',gap:8,flexShrink:0}}>
      <span style={{color:T.subtle,fontSize:12}}>
        कुल <strong style={{color:T.dark}}>{total}</strong> — पृष्ठ <strong style={{color:T.dark}}>{page}</strong> / {totalPages}
      </span>
      <div style={{display:'flex',gap:4,alignItems:'center'}}>
        <button style={btnStyle(false,page===1)} onClick={()=>onPage(1)} disabled={page===1}><ChevronsLeft size={14}/></button>
        <button style={btnStyle(false,page===1)} onClick={()=>onPage(page-1)} disabled={page===1}><ChevronLeft size={14}/></button>
        {pages.map((p,i)=> p==='...'
          ? <span key={`e${i}`} style={{color:T.subtle,padding:'0 4px',fontSize:13}}>…</span>
          : <button key={p} style={btnStyle(p===page,false)} onClick={()=>onPage(p)}>{p}</button>
        )}
        <button style={btnStyle(false,page===totalPages)} onClick={()=>onPage(page+1)} disabled={page===totalPages}><ChevronRight size={14}/></button>
        <button style={btnStyle(false,page===totalPages)} onClick={()=>onPage(totalPages)} disabled={page===totalPages}><ChevronsRight size={14}/></button>
      </div>
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY ROW
// ══════════════════════════════════════════════════════════════════════════
const DistrictDutyRow = ({dutyType,info,batches,expanded,loading,onToggle,onPrintBatch,onPrintAll,cfg}) => {
  const labelHi  = info.dutyLabelHi||dutyType;
  const sankhya  = info.sankhya||0;
  const assigned = info.totalAssigned||0;
  const batchCnt = info.batchCount||0;
  const pct      = sankhya>0 ? Math.min(assigned/sankhya,1) : 0;
  const isFull   = sankhya>0 && assigned>=sankhya;

  return (
    <div style={{borderRadius:14,overflow:'hidden',border:`${expanded?1.5:1}px solid ${expanded?T.primary:T.border+'55'}`,
      background:'white',boxShadow:`0 2px 12px ${T.primary}08`,transition:'all .2s'}}>

      {/* Header row */}
      <div onClick={onToggle} style={{padding:'14px 18px',cursor:'pointer',userSelect:'none'}}>
        <div style={{display:'flex',alignItems:'center',gap:12}}>
          <div style={{flex:1,minWidth:0}}>
            <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:6,flexWrap:'wrap'}}>
              <span style={{color:T.dark,fontWeight:800,fontSize:15}}>{labelHi}</span>
              {isFull&&<span style={{background:`${T.success}14`,color:T.success,fontSize:10,fontWeight:700,
                borderRadius:6,padding:'2px 8px',border:`1px solid ${T.success}30`}}>✓ पूर्ण</span>}
            </div>
            <div style={{display:'flex',gap:8,flexWrap:'wrap',marginBottom:8}}>
              <StatBadge label="आवश्यक" value={sankhya} color={T.accent}/>
              <StatBadge label="नियुक्त" value={assigned} color={isFull?T.success:T.primary}/>
              <StatBadge label="बैच" value={batchCnt} color={T.info}/>
            </div>
            {/* Progress bar */}
            <div style={{height:6,borderRadius:3,background:`${T.border}33`,overflow:'hidden',maxWidth:360}}>
              <div style={{height:'100%',borderRadius:3,background:isFull?T.success:T.primary,
                width:`${pct*100}%`,transition:'width .4s ease'}}/>
            </div>
            <span style={{color:T.subtle,fontSize:10,marginTop:2,display:'block'}}>{Math.round(pct*100)}% पूर्ण</span>
          </div>
          <div style={{display:'flex',gap:8,alignItems:'center',flexShrink:0}}>
            {batchCnt>0&&(
              <button onClick={e=>{e.stopPropagation();onPrintAll();}} style={{
                display:'inline-flex',alignItems:'center',gap:5,padding:'7px 13px',borderRadius:8,
                border:'none',background:T.primary,color:'white',fontSize:11,fontWeight:700,
                cursor:'pointer',fontFamily:'inherit',
              }}>
                <Printer size={13}/>सभी बैच
              </button>
            )}
            <div style={{color:T.subtle,transition:'transform .2s',transform:expanded?'rotate(180deg)':'rotate(0deg)'}}>
              <ChevronDown size={20}/>
            </div>
          </div>
        </div>
      </div>

      {/* Expanded batches */}
      {expanded&&(
        <div style={{borderTop:`1px solid ${T.border}44`}}>
          {loading ? (
            <div style={{display:'flex',alignItems:'center',justifyContent:'center',padding:32,gap:10}}>
              <Loader2 size={20} color={T.primary} style={{animation:'spin 1s linear infinite'}}/>
              <span style={{color:T.subtle,fontSize:12}}>लोड हो रहा है...</span>
            </div>
          ) : batches.length===0 ? (
            <div style={{textAlign:'center',padding:24,color:T.subtle,fontSize:12}}>कोई batch नहीं मिला</div>
          ) : (
            <div style={{padding:'10px 14px',display:'flex',flexDirection:'column',gap:10}}>
              {batches.map((b,bi)=>{
                const staffList = b.staff||[];
                const bNo = b.batchNo||b.batch_no||bi+1;
                const busNo = (b.busNo||b.bus_no||'').toString();
                const note  = (b.note||'').toString();
                return (
                  <div key={bNo} style={{borderRadius:10,border:`1px solid ${T.border}44`,
                    background:T.bg,overflow:'hidden'}}>
                    <div style={{padding:'10px 14px',display:'flex',alignItems:'center',gap:10}}>
                      <div style={{background:T.primary,color:'white',fontWeight:800,fontSize:11,
                        borderRadius:6,padding:'3px 10px',flexShrink:0}}>बैच {bNo}</div>
                      {busNo&&<Tag icon={Bus} text={`बस–${busNo}`} color={T.accent}/>}
                      <Tag icon={Users} text={`${staffList.length} कर्मी`}/>
                      <div style={{flex:1}}/>
                      <button onClick={()=>onPrintBatch(b)} style={{
                        display:'inline-flex',alignItems:'center',gap:5,padding:'6px 12px',borderRadius:8,
                        border:'none',background:T.primary,color:'white',fontSize:11,fontWeight:700,
                        cursor:'pointer',fontFamily:'inherit',flexShrink:0,
                      }}>
                        <Printer size={12}/>Print
                      </button>
                    </div>
                    {note&&<div style={{padding:'3px 14px 6px',fontSize:11,color:T.subtle,display:'flex',gap:4}}>
                      <FileText size={11}/>{note}
                    </div>}
                    {staffList.length>0&&(
                      <>
                        <div style={{height:1,background:`${T.border}44`,margin:'0 14px'}}/>
                        <div style={{padding:'8px 14px',display:'grid',
                          gridTemplateColumns:'repeat(auto-fill,minmax(240px,1fr))',gap:'5px 12px'}}>
                          {staffList.slice(0,8).map((e,ei)=>{
                            const armed2 = isArmedFn(e);
                            return (
                              <div key={ei} style={{display:'flex',alignItems:'center',gap:7,minWidth:0}}>
                                <div style={{width:6,height:6,borderRadius:'50%',background:T.primary,flexShrink:0}}/>
                                <span style={{color:T.dark,fontSize:11.5,fontWeight:600,overflow:'hidden',
                                  textOverflow:'ellipsis',whiteSpace:'nowrap',flex:1}}>{e.name||'—'}</span>
                                <span style={{fontSize:10,color:rankPal(e.rank||'').text,fontWeight:700,flexShrink:0}}>
                                  {rh(e.rank||e.user_rank||'')}</span>
                                <span style={{fontSize:9,color:armed2?T.armed:T.unarmed,flexShrink:0}}>
                                  {armed2?<Shield size={10}/>:<ShieldOff size={10}/>}
                                </span>
                              </div>
                            );
                          })}
                          {staffList.length>8&&(
                            <div style={{color:T.subtle,fontSize:10,padding:'2px 0'}}>
                              + {staffList.length-8} और कर्मी...
                            </div>
                          )}
                        </div>
                      </>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════
//  MAIN PAGE
// ══════════════════════════════════════════════════════════════════════════
export default function DutyCardPage() {

  const [activeTab,  setActiveTab]  = useState('booth');

  // ── Election config ──────────────────────────────────────────────────────
  const [config,        setConfig]        = useState(null);
  const [configLoading, setConfigLoading] = useState(true);
  const [adminDistrict, setAdminDistrict] = useState('');

  // ── Booth state ──────────────────────────────────────────────────────────
  const [items,      setItems]      = useState([]);
  const [total,      setTotal]      = useState(0);
  const [totalPages, setTotalPages] = useState(1);
  const [page,       setPage]       = useState(1);
  const [loading,    setLoading]    = useState(false);

  const [q,          setQ]          = useState('');
  const [inputVal,   setInputVal]   = useState('');
  const [rankFilter, setRankFilter] = useState(null);
  const [armedFilter,setArmedFilter]= useState('all');
  const [cardFilter, setCardFilter] = useState('all');
  const [selected,   setSelected]   = useState(new Set());

  // ── District state ───────────────────────────────────────────────────────
  const [distSummary,  setDistSummary]  = useState({});
  const [distBatches,  setDistBatches]  = useState({});
  const [distLoading,  setDistLoading]  = useState(false);
  const [batchLoading, setBatchLoading] = useState({});
  const [expandedDuty, setExpandedDuty] = useState(null);

  const debounceRef = useRef(null);
  const LIMIT = 20;

  // ── Init admin profile → config ──────────────────────────────────────────
  useEffect(()=>{ initAdminConfig(); },[]);

  const initAdminConfig = async () => {
    let dist = '';
    try {
      const res = await api.get('/auth/me');
      dist = (res.data?.data||res.data||{}).district||'';
      setAdminDistrict(dist);
    } catch {}
    await fetchConfig(dist);
  };

  const fetchConfig = async (dist='') => {
    setConfigLoading(true);
    // Source 1
    try {
      const res  = await api.get('/admin/election-config/active');
      const data = res.data?.data || res.data || {};
      if (data && Object.keys(data).length) {
        const parsed = parseConfig(data, dist);
        if (parsed && (parsed.district===''||parsed.district.toLowerCase()===dist.toLowerCase()||dist==='')) {
          setConfig(parsed); setConfigLoading(false); return;
        }
      }
    } catch {}
    // Source 2 — embedded in duties
    try {
      const res = await api.get('/admin/duties?page=1&limit=1');
      const emb = (res.data?.data||{}).electionConfig;
      if (emb && Object.keys(emb).length) {
        const parsed = parseConfig(emb, dist);
        if (parsed) { setConfig(parsed); setConfigLoading(false); return; }
      }
    } catch {}
    // Source 3 — legacy
    try {
      const res = await api.get('/admin/config');
      const legacy = res.data?.data||res.data||{};
      if (legacy && Object.keys(legacy).length) {
        const parsed = parseConfig({...legacy,district:dist}, dist);
        if (parsed) { setConfig(parsed); setConfigLoading(false); return; }
      }
    } catch {}
    setConfigLoading(false);
  };

  // ── Fetch duties ──────────────────────────────────────────────────────────
  const fetchDuties = useCallback(async(pg,query,card,rank,armed)=>{
    setLoading(true);
    try {
      const params = new URLSearchParams({page:pg,limit:LIMIT});
      if (query) params.set('q',query);
      // Backend uses card=downloaded | card=pending
      if (card&&card!=='all') params.set('card',card);
      if (rank) params.set('rank',rank);
      // Backend uses armed=yes | armed=no (not 'armed'/'unarmed')
      if (armed==='armed')   params.set('armed','yes');
      if (armed==='unarmed') params.set('armed','no');
      const res = await api.get(`/admin/duties?${params}`);
      const w   = res.data?.data||res.data||{};
      const dataArr = Array.isArray(w) ? w : (w.data||[]);
      setItems(dataArr.map(e=>({...e})));
      setTotal(w.total||dataArr.length||0);
      setTotalPages(w.totalPages||Math.ceil((w.total||dataArr.length||0)/LIMIT)||1);
      setSelected(new Set());
      // try to hydrate config from response
      if (!config&&w.electionConfig) {
        const p=parseConfig(w.electionConfig,adminDistrict);
        if(p) setConfig(p);
      }
    } catch(e){ toast.error(`लोड विफल: ${e.message||e}`); }
    finally{ setLoading(false); }
  },[config,adminDistrict]);

  useEffect(()=>{ fetchDuties(page,q,cardFilter,rankFilter,armedFilter); },[page,q,cardFilter,rankFilter,armedFilter]);

  // ── District duty ─────────────────────────────────────────────────────────
  const loadDistrictSummary = useCallback(async()=>{
    if(distLoading) return;
    setDistLoading(true);
    try {
      const res = await api.get('/admin/district-duty/summary');
      setDistSummary(res.data?.data||res.data||{});
    } catch(e){ toast.error(`District duty विफल: ${e.message||e}`); }
    finally{ setDistLoading(false); }
  },[distLoading]);

  const loadBatchesForDuty = useCallback(async(dutyType)=>{
    if(distBatches[dutyType]||batchLoading[dutyType]) return;
    setBatchLoading(p=>({...p,[dutyType]:true}));
    try {
      const res = await api.get(`/admin/district-duty/${dutyType}/batches`);
      setDistBatches(p=>({...p,[dutyType]:res.data?.data||res.data||[]}));
    } catch(e){ toast.error(`Batch लोड विफल: ${e.message||e}`); }
    finally{ setBatchLoading(p=>({...p,[dutyType]:false})); }
  },[distBatches,batchLoading]);

  const handleTabChange = (tab) => {
    setActiveTab(tab);
    if(tab==='district'&&!Object.keys(distSummary).length) loadDistrictSummary();
  };

  // ── Filters / selection ───────────────────────────────────────────────────
  const handleSearch = e => {
    setInputVal(e.target.value);
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(()=>{ setQ(e.target.value.trim()); setPage(1); },400);
  };
  const clearSearch = () => { setInputVal(''); setQ(''); setPage(1); };

  const setRank  = r =>{ setRankFilter(r);  setPage(1); setSelected(new Set()); };
  const setArmed = v =>{ setArmedFilter(v); setPage(1); setSelected(new Set()); };
  const setCard  = v =>{ setCardFilter(v);  setPage(1); setSelected(new Set()); };

  const toggleSel  = id => setSelected(p=>{ const n=new Set(p); n.has(id)?n.delete(id):n.add(id); return n; });
  const toggleAll  = () => setSelected(items.length>0&&selected.size===items.length ? new Set() : new Set(items.map(s=>s.id)));
  const allSel     = items.length>0&&selected.size===items.length;

  // ── Print handlers ────────────────────────────────────────────────────────
  const printCards = useCallback((list)=>{
    if(!list.length){ toast.error('कोई रिकॉर्ड नहीं'); return; }
    const html = buildDutyCardHtml(list, config||{});
    triggerPrint(html);
  },[config]);

  const printAll = useCallback(async()=>{
    try {
      const all=[]; let pg=1, tp=totalPages;
      while(pg<=tp){
        const params=new URLSearchParams({page:pg,limit:200});
        if(q) params.set('q',q);
        if(cardFilter!=='all') params.set('card',cardFilter);
        if(rankFilter) params.set('rank',rankFilter);
        if(armedFilter==='armed')   params.set('armed','yes');
        if(armedFilter==='unarmed') params.set('armed','no');
        const res=await api.get(`/admin/duties?${params}`);
        const w=res.data?.data||res.data||{};
        const dataArr = Array.isArray(w) ? w : (w.data||[]);
        all.push(...dataArr);
        tp=w.totalPages||1; pg++;
      }
      if(!all.length){ toast.error('कोई रिकॉर्ड नहीं'); return; }
      printCards(all);
    } catch(e){ toast.error(`Print विफल: ${e.message||e}`); }
  },[q,cardFilter,rankFilter,armedFilter,totalPages,printCards]);

  const printSelected = () => {
    const list = items.filter(s=>selected.has(s.id));
    printCards(list);
  };

  const printDistrictBatch = useCallback((batch, dutyLabelHi)=>{
    const html = buildDistrictDutyCardHtml([batch], dutyLabelHi, config||{});
    triggerPrint(html);
  },[config]);

  const printAllDistrictBatches = useCallback(async(dutyType,dutyLabelHi)=>{
    let batches = distBatches[dutyType];
    if(!batches){ await loadBatchesForDuty(dutyType); batches=distBatches[dutyType]||[]; }
    if(!batches?.length){ toast.error('पहले batches लोड करें'); return; }
    const html = buildDistrictDutyCardHtml(batches, dutyLabelHi, config||{});
    triggerPrint(html);
  },[distBatches,loadBatchesForDuty,config]);

  const handleToggleDuty = useCallback(async(dutyType)=>{
    const isOpen = expandedDuty===dutyType;
    setExpandedDuty(isOpen?null:dutyType);
    if(!isOpen&&!distBatches[dutyType]) await loadBatchesForDuty(dutyType);
  },[expandedDuty,distBatches,loadBatchesForDuty]);

  const distEntries = useMemo(()=>Object.entries(distSummary),[distSummary]);
  const anyFilter   = rankFilter!==null||armedFilter!=='all'||cardFilter!=='all';

  // ══════════════════════════════════════════════════════════════════════════
  //  RENDER
  // ══════════════════════════════════════════════════════════════════════════
  return (
    <div style={{display:'flex',flexDirection:'column',height:'100%',background:T.bg,
      fontFamily:"'Tiro Devanagari Hindi',Georgia,serif",overflow:'hidden'}}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Tiro+Devanagari+Hindi&family=Playfair+Display:wght@700;800&display=swap');
        @keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
        @keyframes fadeIn{from{opacity:0;transform:translateY(5px)}to{opacity:1;transform:translateY(0)}}
        .fade-in{animation:fadeIn .25s ease-out}
        *{box-sizing:border-box}
        button,input,select{font-family:inherit}
        ::-webkit-scrollbar{width:5px;height:5px}
        ::-webkit-scrollbar-track{background:${T.surface}}
        ::-webkit-scrollbar-thumb{background:${T.border};border-radius:3px}
      `}</style>
      <Toaster position="top-right" toastOptions={{style:{background:T.bg,color:T.dark,
        border:`1px solid ${T.border}`,fontFamily:'inherit',fontSize:13}}}/>

      {/* ── Election Config Banner ── */}
      {configLoading ? (
        <div style={{background:T.surface,padding:'9px 20px',display:'flex',alignItems:'center',
          gap:10,borderBottom:`1px solid ${T.border}55`,flexShrink:0}}>
          <Loader2 size={14} color={T.primary} style={{animation:'spin 1s linear infinite'}}/>
          <span style={{color:T.subtle,fontSize:11}}>निर्वाचन विवरण लोड हो रहा है...</span>
        </div>
      ) : !config ? (
        <div style={{background:'#FFF3E0',padding:'9px 20px',display:'flex',alignItems:'center',
          gap:10,borderBottom:`1px solid ${T.accent}44`,flexShrink:0}}>
          <AlertTriangle size={15} color={T.accent}/>
          <span style={{flex:1,color:T.accent,fontSize:11,fontWeight:600}}>
            निर्वाचन विवरण उपलब्ध नहीं — Election Config सेट करें
          </span>
          <button onClick={()=>fetchConfig(adminDistrict)} style={{background:'none',border:'none',
            cursor:'pointer',color:T.accent,display:'flex'}}>
            <RefreshCw size={14}/>
          </button>
        </div>
      ) : (
        <div style={{background:T.surface,padding:'9px 20px',display:'flex',alignItems:'center',
          gap:12,borderBottom:`1px solid ${T.border}55`,flexShrink:0}}>
          <Vote size={15} color={T.primary}/>
          <div style={{flex:1,minWidth:0}}>
            <div style={{color:T.dark,fontSize:11.5,fontWeight:800,
              overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap'}}>
              {config.electionName||'निर्वाचन'}
            </div>
            <div style={{color:T.subtle,fontSize:9.5,overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap'}}>
              जनपद: {config.district||adminDistrict} &nbsp;•&nbsp; चरण: {config.phase} &nbsp;•&nbsp; दिनांक: {normaliseDate(config.electionDate)||config.electionDate}
            </div>
          </div>
          <div style={{display:'flex',gap:8,alignItems:'center',flexShrink:0}}>
            <span style={{background:`${T.primary}12`,color:T.primary,fontSize:10,fontWeight:700,
              borderRadius:12,padding:'3px 10px',border:`1px solid ${T.primary}30`,
              display:'flex',alignItems:'center',gap:4}}>
              <Clock size={10}/>{normaliseTime(config.pratahSamay)||config.pratahSamay}–{normaliseTime(config.sayaSamay)||config.sayaSamay}
            </span>
            {config.state&&<span style={{background:`${T.info}10`,color:T.info,fontSize:10,fontWeight:600,
              borderRadius:12,padding:'3px 9px',border:`1px solid ${T.info}25`}}>
              {config.state}
            </span>}
            <button onClick={()=>fetchConfig(adminDistrict)} style={{background:'none',border:'none',cursor:'pointer',color:T.subtle,display:'flex'}}>
              <RefreshCw size={13}/>
            </button>
          </div>
        </div>
      )}

      {/* ── Tabs ── */}
      <div style={{background:T.surface,borderBottom:`1px solid ${T.border}55`,
        display:'flex',padding:'0 20px',gap:2,flexShrink:0}}>
        {[['booth','बूथ ड्यूटी',Vote],['district','जनपदीय ड्यूटी',Building2]].map(([v,l,Icon])=>(
          <button key={v} onClick={()=>handleTabChange(v)} style={{
            padding:'11px 22px',border:'none',background:'transparent',
            color:activeTab===v?T.primary:T.subtle,fontWeight:activeTab===v?800:500,fontSize:13,
            cursor:'pointer',borderBottom:activeTab===v?`3px solid ${T.primary}`:'3px solid transparent',
            transition:'all .18s',fontFamily:'inherit',display:'flex',alignItems:'center',gap:7,
          }}>
            <Icon size={15}/>{l}
          </button>
        ))}
      </div>

      {/* ══════════════════════════════════════════════════════════════════ */}
      {/* BOOTH TAB                                                         */}
      {/* ══════════════════════════════════════════════════════════════════ */}
      {activeTab==='booth'&&(
        <div style={{flex:1,display:'flex',flexDirection:'column',overflow:'hidden'}}>

          {/* Filter panel */}
          <div style={{background:T.surface,padding:'12px 20px',borderBottom:`1px solid ${T.border}44`,flexShrink:0}}>
            {/* Search */}
            <div style={{position:'relative',marginBottom:10}}>
              <Search size={15} color={T.subtle} style={{position:'absolute',left:12,top:'50%',transform:'translateY(-50%)'}}/>
              <input value={inputVal} onChange={handleSearch}
                placeholder="नाम, PNO, केंद्र, जोन, थाना से खोजें..."
                style={{width:'100%',padding:'9px 36px',border:`1.2px solid ${T.border}`,borderRadius:10,
                  outline:'none',background:'white',color:T.dark,fontSize:13,transition:'border-color .2s'}}
                onFocus={e=>e.target.style.borderColor=T.primary}
                onBlur={e=>e.target.style.borderColor=T.border}/>
              {inputVal&&(
                <button onClick={clearSearch} style={{position:'absolute',right:10,top:'50%',
                  transform:'translateY(-50%)',background:'none',border:'none',cursor:'pointer',
                  color:T.subtle,display:'flex'}}>
                  <X size={15}/>
                </button>
              )}
            </div>

            {/* Armed + Card filters */}
            <div style={{display:'flex',flexWrap:'wrap',gap:'8px 20px',marginBottom:10,alignItems:'center'}}>
              <div style={{display:'flex',alignItems:'center',gap:7}}>
                <span style={{color:T.subtle,fontSize:11,fontWeight:600,whiteSpace:'nowrap'}}>शस्त्र:</span>
                {[['all','सभी',T.primary,T.surface,T.border,null],
                  ['armed','सशस्त्र',T.armed,'#fdecea','#f0a87a',Shield],
                  ['unarmed','निःशस्त्र',T.unarmed,'#e3f0fb','#9ac3e6',ShieldOff]
                ].map(([v,l,col,bg,brd,Ic])=>(
                  <Chip key={v} label={l} selected={armedFilter===v} color={col} bg={bg} border={brd}
                    icon={Ic} onClick={()=>setArmed(v)}/>
                ))}
              </div>
              <div style={{display:'flex',alignItems:'center',gap:7}}>
                <Download size={13} color={T.subtle}/>
                {[['all','सभी',T.subtle,'white',T.border,null],
                  ['downloaded','✅ कार्ड लिया',T.success,'#e6f4ea','#a2d9c8',CheckCircle2],
                  ['pending','⏳ कार्ड बाकी',T.error,'#fdecea','#f0a87a',null],
                ].map(([v,l,col,bg,brd,Ic])=>(
                  <Chip key={v} label={l} selected={cardFilter===v} color={col} bg={bg} border={brd}
                    icon={Ic} onClick={()=>setCard(v)}/>
                ))}
              </div>
            </div>

            {/* Rank chips */}
            <div style={{display:'flex',gap:6,overflowX:'auto',paddingBottom:2}}>
              <Chip label="सभी पद" selected={rankFilter===null} color={T.primary}
                bg={T.surface} border={T.border} onClick={()=>setRank(null)}/>
              {ALL_RANKS.map(r=>{
                const rp=rankPal(r);
                return <Chip key={r} label={r} selected={rankFilter===r} color={rp.text}
                  bg={rp.bg} border={rp.border} onClick={()=>setRank(rankFilter===r?null:r)}/>;
              })}
            </div>
          </div>

          {/* Action bar */}
          {!loading&&items.length>0&&(
            <div style={{background:'white',padding:'8px 20px',borderBottom:`1px solid ${T.border}33`,
              display:'flex',alignItems:'center',gap:10,flexShrink:0,flexWrap:'wrap'}}>
              <div>
                <div style={{color:T.dark,fontWeight:700,fontSize:13}}>
                  {/* Show page count / total — total is server-side filtered count */}
                  {total > 0 ? (
                    anyFilter
                      ? <>{items.length} <span style={{color:T.subtle,fontWeight:400,fontSize:12}}>/ {total} फ़िल्टर</span></>
                      : String(total)
                  ) : String(items.length)}
                </div>
                <div style={{color:T.subtle,fontSize:10}}>
                  {[rankFilter,
                    armedFilter!=='all'?(armedFilter==='armed'?'सशस्त्र':'निःशस्त्र'):null,
                    cardFilter==='downloaded'?'कार्ड लिया':cardFilter==='pending'?'कार्ड बाकी':null,
                  ].filter(Boolean).join(' • ')||'कुल ड्यूटी'}
                </div>
              </div>
              <div style={{flex:1}}/>
              <button onClick={toggleAll} style={{display:'inline-flex',alignItems:'center',gap:5,
                padding:'6px 13px',borderRadius:8,cursor:'pointer',border:`1px solid ${T.border}`,
                background:'transparent',color:T.primary,fontSize:11,fontWeight:700,fontFamily:'inherit'}}>
                {allSel?<CheckSquare size={14}/>:<Square size={14}/>}
                {allSel?'Deselect All':'Select All'}
              </button>
              {selected.size>0&&(
                <PillBtn label={`Print (${selected.size})`} icon={Printer} color={T.primary} onClick={printSelected}/>
              )}
              <PillBtn label={`Print All (${total||items.length})`} icon={Printer} color={T.dark} onClick={printAll}/>
              <button onClick={()=>fetchDuties(page,q,cardFilter,rankFilter,armedFilter)} style={{
                background:'none',border:`1px solid ${T.border}`,borderRadius:8,
                padding:'6px 8px',cursor:'pointer',color:T.primary,display:'flex'}}>
                <RefreshCw size={14}/>
              </button>
            </div>
          )}

          {/* List */}
          <div style={{flex:1,overflowY:'auto',padding:'14px 20px'}}>
            {loading ? (
              <div style={{display:'flex',alignItems:'center',justifyContent:'center',height:300}}>
                <Loader2 size={36} color={T.primary} style={{animation:'spin 1s linear infinite'}}/>
              </div>
            ) : items.length===0 ? (
              <div style={{display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',
                height:280,color:T.subtle}}>
                <Filter size={52} style={{opacity:.25,marginBottom:14}}/>
                <div style={{fontSize:15,fontWeight:600}}>कोई ड्यूटी नहीं मिली</div>
                <div style={{fontSize:12,marginTop:4}}>फ़िल्टर या खोज बदलें</div>
              </div>
            ) : (
              <div style={{display:'flex',flexDirection:'column',gap:8}} className="fade-in">
                {items.map((s,i)=>(
                  <BoothCard key={s.id} s={s}
                    index={i+(page-1)*LIMIT}
                    selected={selected.has(s.id)}
                    onToggle={toggleSel}
                    onPrint={printCards}/>
                ))}
              </div>
            )}
          </div>

          <Pagination page={page} totalPages={totalPages} total={total}
            onPage={p=>{setPage(p);window.scrollTo(0,0);}}/>
        </div>
      )}

      {/* ══════════════════════════════════════════════════════════════════ */}
      {/* DISTRICT TAB                                                      */}
      {/* ══════════════════════════════════════════════════════════════════ */}
      {activeTab==='district'&&(
        <div style={{flex:1,display:'flex',flexDirection:'column',overflow:'hidden'}}>
          {distLoading ? (
            <div style={{flex:1,display:'flex',alignItems:'center',justifyContent:'center',gap:12}}>
              <Loader2 size={32} color={T.primary} style={{animation:'spin 1s linear infinite'}}/>
              <span style={{color:T.subtle}}>लोड हो रहा है...</span>
            </div>
          ) : distEntries.length===0 ? (
            <div style={{flex:1,display:'flex',flexDirection:'column',alignItems:'center',
              justifyContent:'center',gap:14,color:T.subtle}}>
              <Building2 size={52} style={{opacity:.25}}/>
              <div style={{fontSize:15,fontWeight:600}}>कोई जनपदीय ड्यूटी नहीं मिली</div>
              <button onClick={loadDistrictSummary} style={{display:'inline-flex',alignItems:'center',gap:7,
                padding:'9px 20px',borderRadius:9,border:`1px solid ${T.border}`,background:'white',
                color:T.primary,fontSize:13,fontWeight:700,cursor:'pointer',fontFamily:'inherit'}}>
                <RefreshCw size={15}/>पुनः लोड करें
              </button>
            </div>
          ) : (
            <div style={{flex:1,overflowY:'auto',padding:'14px 20px'}}>
              {/* Summary header */}
              <div style={{display:'flex',alignItems:'center',justifyContent:'space-between',marginBottom:14,flexWrap:'wrap',gap:8}}>
                <div style={{display:'flex',gap:10,flexWrap:'wrap'}}>
                  <StatBadge label="ड्यूटी प्रकार" value={distEntries.length} color={T.accent}/>
                  <StatBadge label="कुल assigned"
                    value={distEntries.reduce((a,[,v])=>a+(v.totalAssigned||0),0)} color={T.success}/>
                  <StatBadge label="कुल batches"
                    value={distEntries.reduce((a,[,v])=>a+(v.batchCount||0),0)} color={T.info}/>
                </div>
                <button onClick={loadDistrictSummary} style={{display:'inline-flex',alignItems:'center',gap:6,
                  padding:'7px 14px',borderRadius:8,border:`1px solid ${T.border}`,background:'white',
                  color:T.primary,fontSize:12,fontWeight:700,cursor:'pointer',fontFamily:'inherit'}}>
                  <RefreshCw size={13}/>रीफ्रेश
                </button>
              </div>
              <div style={{display:'flex',flexDirection:'column',gap:12}} className="fade-in">
                {distEntries.map(([dutyType,info])=>(
                  <DistrictDutyRow key={dutyType}
                    dutyType={dutyType}
                    info={info}
                    batches={distBatches[dutyType]||[]}
                    expanded={expandedDuty===dutyType}
                    loading={!!batchLoading[dutyType]}
                    onToggle={()=>handleToggleDuty(dutyType)}
                    onPrintBatch={b=>printDistrictBatch(b,info.dutyLabelHi||dutyType)}
                    onPrintAll={()=>printAllDistrictBatches(dutyType,info.dutyLabelHi||dutyType)}
                    cfg={config||{}}
                  />
                ))}
              </div>
              <div style={{height:20}}/>
            </div>
          )}
        </div>
      )}
    </div>
  );
}