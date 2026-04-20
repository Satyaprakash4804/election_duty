/**
 * DutyCardPage.jsx
 * UP Police Election Cell — Duty Card Management
 * React equivalent of the Flutter DutyCardPage
 *
 * Dependencies (already in package.json):
 *   react, react-hot-toast, lucide-react, axios, zustand, @tanstack/react-query
 *
 * Drop this file into your pages/admin/ directory.
 * Import and render as: <DutyCardPage />
 *
 * PDF printing uses the browser's native print dialog via a hidden iframe
 * that renders the duty card as HTML styled to match the Flutter PDF layout.
 */

import React, {
  useState, useEffect, useRef, useCallback, useMemo,
} from 'react';
import {
  Search, X, Lock, User, UserCircle, ArrowLeft, ArrowRight,
  ChevronsLeft, ChevronsRight, Printer, CheckSquare, Square, ShieldOff,
  MapPin, Phone, BadgeCheck, Bus, Layers, Filter, RefreshCw,
} from 'lucide-react';
import toast from 'react-hot-toast';

// ─── API client (mirrors your endpoints.js) ──────────────────────────────────
import api from '../../api/client';          // adjust path as needed

// ─── Constants ────────────────────────────────────────────────────────────────
const RANK_MAP = {
  constable:               'कां0',
  'head constable':        'हो0गा0',
  si:                      'उ0नि0',
  'sub inspector':         'उ0नि0',
  inspector:               'निरीक्षक',
  asi:                     'स0उ0नि0',
  'assistant sub inspector':'स0उ0नि0',
  dsp:                     'उपाधीक्षक',
  asp:                     'सहा0 पुलिस अधीक्षक',
  sp:                      'पुलिस अधीक्षक',
  'circle officer':        'क्षेत्राधिकारी',
  co:                      'क्षेत्राधिकारी',
};

const ALL_RANKS = ['SP','ASP','DSP','Inspector','SI','ASI','Head Constable','Constable'];

const RANK_COLORS = {
  SP:             { text: '#6C3483', bg: '#f3e5f5', border: '#d7b8e8' },
  ASP:            { text: '#1A5276', bg: '#e3f0fb', border: '#a9cce3' },
  DSP:            { text: '#0E6655', bg: '#e8f5f0', border: '#a2d9c8' },
  INSPECTOR:      { text: '#1F618D', bg: '#dbeeff', border: '#9ac3e6' },
  SI:             { text: '#117A65', bg: '#e0f5f0', border: '#82c7b8' },
  ASI:            { text: '#B7950B', bg: '#fdf5d9', border: '#e6cc65' },
  'HEAD CONSTABLE':{ text: '#BA4A00', bg: '#fde8dc', border: '#f0a87a' },
  CONSTABLE:      { text: '#6E2F1A', bg: '#fbe5d6', border: '#d4836d' },
};

const PRIMARY   = '#8B6914';
const ACCENT    = '#B8860B';
const DARK      = '#4A3000';
const SUBTLE    = '#AA8844';
const BORDER    = '#D4A843';
const BG        = '#FDF6E3';
const SURFACE   = '#F5E6C8';
const SUCCESS   = '#2D6A1E';
const INFO      = '#1A5276';
const ERROR_RED = '#C0392B';
const ARMED_RED = '#C62828';
const UNARMED_BLUE = '#1565C0';

const LIMIT = 20; // per page (desktop pagination)

// ─── Utility helpers ──────────────────────────────────────────────────────────
const rh  = (val) => RANK_MAP[(val || '').toLowerCase().trim()] || val || '—';
const vd  = (x)   => (x == null || String(x).trim() === '') ? '—' : String(x);
const isArmedFn = (s) =>
  s.isArmed === true || s.is_armed === true || s.is_armed === 1;

function rankColor(rank) {
  return RANK_COLORS[(rank || '').toUpperCase()] ||
    { text: PRIMARY, bg: SURFACE, border: BORDER };
}

function debounce(fn, ms = 350) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

// ─── PDF Print helper (generates an iframe with styled HTML) ─────────────────
function printDutyCards(list) {
  if (!list.length) return;

  const vd = (v) => (v === null || v === undefined || v === '') ? '—' : String(v);
  const rh = (v) => vd(v);
  const isArmedFn = (e) =>
    e.isArmed === true || e.is_armed === true || e.is_armed === 1;

  const cardHTML = list.map((s) => {
    const sahyogi = s.sahyogi || s.allStaff || s.all_staff || [];
    const totalRows = Math.max(12, sahyogi.length);

    const zonalOfficers  = s.zonalOfficers  || s.zonal_officers  || [];
    const sectorOfficers = s.sectorOfficers || s.sector_officers || [];
    const superOfficers  = s.superOfficers  || s.super_officers  || [];

    const zonalMag    = zonalOfficers[0]  || null;
    const sectorMag   = sectorOfficers[0] || null;
    const zonalPolice = superOfficers[0]  || null;
    const sectorPolice = sectorOfficers[1] || sectorOfficers[0] || null;

    const busNo = vd(s.busNo || s.bus_no);
    const armed = isArmedFn(s) ? 'सशस्त्र' : 'निःशस्त्र';

    const staffRows = Array.from({ length: totalRows }).map((_, i) => {
      const e = sahyogi[i] || null;
      const bg = i % 2 === 0 ? '#fff' : '#f5f5f5';
      return `<tr style="background:${bg}">
        <td style="font-size:4.8px;padding:0.5px 1px;border-bottom:0.3px solid #eee;border-right:0.3px solid #ddd;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">${e ? rh(e.user_rank || e.rank) : ''}</td>
        <td style="font-size:4.8px;padding:0.5px 1px;border-bottom:0.3px solid #eee;border-right:0.3px solid #ddd;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">${e ? vd(e.pno) : ''}</td>
        <td style="font-size:4.8px;padding:0.5px 1px;border-bottom:0.3px solid #eee;border-right:0.3px solid #ddd;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;font-weight:${e ? '700' : '400'}">${e ? vd(e.name) : ''}</td>
        <td style="font-size:4.8px;padding:0.5px 1px;border-bottom:0.3px solid #eee;border-right:0.3px solid #ddd;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">${e ? vd(e.mobile) : ''}</td>
        <td style="font-size:4.8px;padding:0.5px 1px;border-bottom:0.3px solid #eee;border-right:0.3px solid #ddd;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">${e ? vd(e.thana) : ''}</td>
        <td style="font-size:4.8px;padding:0.5px 1px;border-bottom:0.3px solid #eee;border-right:0.3px solid #ddd;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">${e ? vd(e.district) : ''}</td>
        <td style="font-size:4.8px;padding:0.5px 1px;border-bottom:0.3px solid #eee;text-align:center;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">${e ? (isArmedFn(e) ? 'सशस्त्र' : 'निःशस्त्र') : ''}</td>
      </tr>`;
    }).join('');

    const officerBlock = (title, name, mobile, rank) => `
      <div style="border-bottom:0.4px solid #ccc">
        <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5px;border-bottom:0.4px solid #ccc">${title}</div>
        <div style="padding:2px;text-align:center;font-size:4.5px;line-height:1.4">${[rank, name, mobile].filter(Boolean).join('<br>')}</div>
      </div>`;

    return `
      <div class="card">

        <!-- HEADER -->
        <div style="display:flex;border-bottom:0.8px solid #333;flex-shrink:0">
          <div style="width:42px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:8px;padding:3px;text-align:center;border-right:0.5px solid #333">ECI</div>
          <div style="flex:1;padding:2px 4px;text-align:center">
            <div style="font-size:11px;font-weight:700;text-decoration:underline;line-height:1.2">ड्यूटी कार्ड</div>
            <div style="font-size:7px;font-weight:700;line-height:1.2">लोकसभा सामान्य निर्वाचन–2024</div>
            <div style="font-size:6.5px;line-height:1.2">जनपद ${vd(s.adminDistrict || s.district || 'बागपत')}</div>
            <div style="font-size:5.5px;font-weight:700;border-top:0.5px solid #999;margin-top:1px;padding-top:1px;line-height:1.2">मतदान चरण–द्वितीय &nbsp; दिनांक 26.04.2024 &nbsp; प्रातः 07:00 से सांय 06:00 तक</div>
          </div>
          <div style="width:42px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:7px;padding:3px;text-align:center;border-left:0.5px solid #333;line-height:1.3">उ0प्र0<br>पुलिस</div>
        </div>

        <!-- PRIMARY TABLE -->
        <table style="width:100%;border-collapse:collapse;border:0.5px solid #999;flex-shrink:0;table-layout:fixed">
          <colgroup>
            <col style="width:14%"><col style="width:8%"><col style="width:10%">
            <col style="width:18%"><col style="width:11%"><col style="width:11%">
            <col style="width:10%"><col style="width:8%"><col style="width:10%">
          </colgroup>
          <thead>
            <tr>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">नाम अधि0/<br>कर्म0 गण</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">पद</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">बैज नंबर</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">नाम अधि0/कर्म0</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">मोबाइल न0</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">तैनाती</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">जनपद</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">स0/<br>नि0</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">वाहन<br>संख्या</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px"></td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;font-weight:700;text-align:center">${rh(s.rank || s.user_rank)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center">${vd(s.pno)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;font-weight:700">${vd(s.name)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center">${vd(s.mobile)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center">${vd(s.staffThana || s.thana)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center">${vd(s.district)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:4.5px;text-align:center">${armed}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center;font-weight:700">${busNo !== '—' ? 'बस–' + busNo : '—'}</td>
            </tr>
          </tbody>
        </table>

        <!-- MIDDLE -->
        <div style="display:flex;flex:1;border-top:0.5px solid #999;overflow:hidden;min-height:0">

          <!-- Duty location -->
          <div style="width:50px;border-right:0.5px solid #999;display:flex;flex-direction:column;flex-shrink:0">
            <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5.5px;border-bottom:0.5px solid #999;line-height:1.2;flex-shrink:0">डियूटी स्थान</div>
            <div style="flex:1;padding:2px;text-align:center;font-weight:700;font-size:5.5px;display:flex;align-items:center;justify-content:center;line-height:1.3">${vd(s.centerName || s.center_name)}</div>
            <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5.5px;border-bottom:0.5px solid #999;border-top:0.5px solid #999;line-height:1.2;flex-shrink:0">डियूटी प्रकार</div>
            <div style="flex:1;padding:2px;text-align:center;font-weight:700;font-size:5.5px;display:flex;align-items:center;justify-content:center;line-height:1.3">बूथ डियूटी</div>
          </div>

          <!-- Sahyogi table -->
          <div style="flex:1;overflow:hidden;display:flex;flex-direction:column">
            <table style="width:100%;border-collapse:collapse;table-layout:fixed">
              <colgroup>
                <col style="width:9%"><col style="width:14%"><col style="width:23%">
                <col style="width:16%"><col style="width:16%"><col style="width:14%"><col style="width:8%">
              </colgroup>
              <thead>
                <tr>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">पद</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">बैज नंबर</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">नाम</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">मोबाइल न0</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">तैनाती</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">जनपद</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-bottom:0.5px solid #999;line-height:1.2">स0/नि0</th>
                </tr>
              </thead>
              <tbody>${staffRows}</tbody>
            </table>
          </div>

          <!-- Bus panel -->
          <div style="width:28px;border-left:0.5px solid #999;display:flex;flex-direction:column;flex-shrink:0;font-size:5px">
            <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5px;border-bottom:0.5px solid #999;line-height:1.2">बस–${busNo}</div>
            <div style="padding:2px;text-align:center;font-size:4.8px;line-height:1.3">दिनांक<br><strong>15.2.17</strong></div>
            <div style="padding:2px;text-align:center;font-size:4.8px;line-height:1.3;border-top:0.5px solid #bbb">सीपीएम एफ</div>
            <div style="padding:2px;text-align:center;font-size:4.8px;line-height:1.3;border-top:0.5px solid #bbb">1/2 सै0</div>
          </div>

        </div>

        <!-- FOOTER -->
        <div style="display:flex;border-top:0.8px solid #333;flex-shrink:0">

          <!-- Meta info -->
          <div style="width:50px;border-right:0.5px solid #999;flex-shrink:0">
            ${[
              ['म0 केंद्र सं0', vd(s.centerId  || s.center_id)],
              ['बूथ सं0',       vd(s.boothNo   || s.booth_no)],
              ['थाना',          vd(s.staffThana || s.thana)],
              ['जोन न0',        vd(s.zoneName   || s.zone_name)],
              ['सेक्टर न0',     vd(s.sectorName || s.sector_name)],
              ['वि0स0',         '—'],
              ['श्रेणी',        vd(s.centerType || s.center_type)],
            ].map(([k, v]) => `
              <div style="display:flex;border-bottom:0.3px solid #ddd">
                <span style="background:#eee;flex:2;padding:1px;font-weight:700;border-right:0.3px solid #ccc;font-size:4.5px;line-height:1.2">${k}</span>
                <span style="flex:3;padding:1px;font-size:4.5px;line-height:1.2">${v}</span>
              </div>`).join('')}
          </div>

          <!-- Zonal officers -->
          <div style="flex:1;border-right:0.5px solid #999">
            ${officerBlock('जोनल मजिस्ट्रेट',    zonalMag?.name,    zonalMag?.mobile,    null)}
            ${officerBlock('जोनल पुलिस अधिकारी', zonalPolice?.name, zonalPolice?.mobile, zonalPolice ? rh(zonalPolice.user_rank) : null)}
          </div>

          <!-- Sector officers -->
          <div style="flex:1;border-right:0.5px solid #999">
            ${officerBlock('सैक्टर मजिस्ट्रेट',    sectorMag?.name,    sectorMag?.mobile,    null)}
            ${officerBlock('सेक्टर पुलिस अधिकारी', sectorPolice?.name, sectorPolice?.mobile, sectorPolice ? rh(sectorPolice.user_rank) : null)}
          </div>

          <!-- SP signature -->
          <div style="width:38px;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:3px;flex-shrink:0">
            <div style="height:18px;width:30px;border-bottom:0.5px solid #333"></div>
            <div style="font-size:5.5px;font-weight:700;text-align:center;margin-top:2px;line-height:1.3">पुलिस अधीक्षक<br>${vd(s.adminDistrict || s.district || 'बागपत')}</div>
          </div>

        </div>

      </div>`;
  }).join('<div style="page-break-after:always"></div>');

  const html = `<!DOCTYPE html><html><head>
    <meta charset="UTF-8">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700&display=swap" rel="stylesheet">
    <style>
      *{box-sizing:border-box;margin:0;padding:0}
      body{font-family:'Noto Sans Devanagari',sans-serif;font-size:7px;background:#fff;color:#000}
      .card{
        border:1px solid #333;
        display:flex;
        flex-direction:column;
        width:148mm;
        overflow:hidden;
        page-break-after:always;
      }
      @page{margin:4mm;size:A6 landscape}
      @media print{
        html,body{width:148mm;height:105mm}
        .card{page-break-after:always}
      }
    </style>
  </head><body>${cardHTML}</body></html>`;

  const iframe = document.createElement('iframe');
  iframe.style.cssText = 'position:fixed;top:-9999px;left:-9999px;width:148mm;height:105mm;border:none';
  document.body.appendChild(iframe);
  iframe.contentDocument.open();
  iframe.contentDocument.write(html);
  iframe.contentDocument.close();
  iframe.onload = () => {
    setTimeout(() => {
      iframe.contentWindow.print();
      setTimeout(() => document.body.removeChild(iframe), 2000);
    }, 600);
  };
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function Tag({ icon: Icon, text, color }) {
  return (
    <span style={{ display:'inline-flex', alignItems:'center', gap:3, color: color||SUBTLE, fontSize:11 }}>
      <Icon size={11} style={{ flexShrink:0 }} />
      <span style={{ overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap', maxWidth:180 }}>{text}</span>
    </span>
  );
}

function Badge({ text, color, bg, border }) {
  return (
    <span style={{
      display:'inline-flex', alignItems:'center', padding:'2px 8px',
      borderRadius:6, fontSize:10, fontWeight:700,
      color, background:bg, border:`1px solid ${border}`,
    }}>{text}</span>
  );
}

function RankChip({ label, selected, colors, onToggle }) {
  const c = selected ? colors.text : colors.text;
  return (
    <button
      onClick={onToggle}
      style={{
        padding:'5px 12px', borderRadius:20, fontSize:11, fontWeight:700, cursor:'pointer',
        border:`${selected?1.5:1}px solid ${selected ? colors.text : colors.border}`,
        background: selected ? colors.text : colors.bg,
        color: selected ? '#fff' : colors.text,
        transition:'all 0.15s', whiteSpace:'nowrap',
      }}
    >{label}</button>
  );
}

function ArmedToggle({ value, onChange }) {
  const opts = [
    { key:'all',     label:'सभी',      icon:UserCircle,   tc:PRIMARY,     bg:SURFACE,              border:BORDER },
    { key:'armed',   label:'सशस्त्र',  icon:Lock,  tc:ARMED_RED,   bg:'#fdecea',            border:'#f0a87a' },
    { key:'unarmed', label:'निःशस्त्र', icon:ShieldOff, tc:UNARMED_BLUE, bg:'#e3f0fb',         border:'#9ac3e6' },
  ];
  return (
    <div style={{ display:'flex', alignItems:'center', gap:8, flexWrap:'wrap' }}>
      <span style={{ color:SUBTLE, fontSize:11, fontWeight:600 }}>शस्त्र:</span>
      {opts.map(o => {
        const sel = value === o.key;
        return (
          <button key={o.key} onClick={() => onChange(o.key)}
            style={{
              display:'inline-flex', alignItems:'center', gap:4,
              padding:'5px 11px', borderRadius:20, cursor:'pointer', transition:'all 0.15s',
              border:`${sel?1.5:1}px solid ${sel ? o.tc : o.border}`,
              background: sel ? o.tc : o.bg,
              color: sel ? '#fff' : o.tc,
              fontSize:11, fontWeight:700,
            }}>
            <o.icon size={12} /> {o.label}
          </button>
        );
      })}
    </div>
  );
}

function Pagination({ page, totalPages, total, onPage }) {
  if (totalPages <= 1) return null;
  const pages = [];
  const delta = 2;
  for (let i = 1; i <= totalPages; i++) {
    if (i === 1 || i === totalPages || (i >= page - delta && i <= page + delta)) {
      pages.push(i);
    } else if (pages[pages.length - 1] !== '...') {
      pages.push('...');
    }
  }

  const btnStyle = (active, disabled) => ({
    minWidth:32, height:32, borderRadius:8, border:`1px solid ${active?PRIMARY:BORDER}`,
    background: active ? PRIMARY : 'white',
    color: active ? 'white' : disabled ? SUBTLE : DARK,
    fontSize:12, fontWeight:700, cursor: disabled ? 'not-allowed' : 'pointer',
    display:'inline-flex', alignItems:'center', justifyContent:'center',
    opacity: disabled ? 0.45 : 1, transition:'all 0.15s',
  });

  return (
    <div style={{
      display:'flex', alignItems:'center', justifyContent:'space-between',
      padding:'10px 16px', background:'white', borderTop:`1px solid ${BORDER}`,
      flexWrap:'wrap', gap:8,
    }}>
      <span style={{ color:SUBTLE, fontSize:12 }}>
        कुल <strong style={{ color:DARK }}>{total}</strong> ड्यूटी — पृष्ठ <strong style={{ color:DARK }}>{page}</strong> / {totalPages}
      </span>
      <div style={{ display:'flex', gap:4, alignItems:'center' }}>
        <button style={btnStyle(false, page===1)} onClick={() => onPage(1)} disabled={page===1}><ChevronsLeft size={14}/></button>
        <button style={btnStyle(false, page===1)} onClick={() => onPage(page-1)} disabled={page===1}><ArrowLeft size={14}/></button>
        {pages.map((p, i) =>
          p === '...'
            ? <span key={`e${i}`} style={{ color:SUBTLE, padding:'0 4px', fontSize:12 }}>…</span>
            : <button key={p} style={btnStyle(p===page, false)} onClick={() => onPage(p)}>{p}</button>
        )}
        <button style={btnStyle(false, page===totalPages)} onClick={() => onPage(page+1)} disabled={page===totalPages}><ArrowRight size={14}/></button>
        <button style={btnStyle(false, page===totalPages)} onClick={() => onPage(totalPages)} disabled={page===totalPages}><ChevronsRight size={14}/></button>
      </div>
    </div>
  );
}

function DutyCard({ s, index, selected, onToggle, onPrint }) {
  const id      = s.id;
  const sel     = selected;
  const sahyogi = (s.sahyogi || []);
  const rank    = s.rank || s.user_rank || '';
  const rc      = rankColor(rank);
  const armed   = isArmedFn(s);
  const busNo   = s.busNo || s.bus_no || '';

  return (
    <div
      onClick={() => onToggle(id)}
      style={{
        background: sel ? `rgba(139,105,20,0.05)` : 'white',
        border:`${sel?1.5:1}px solid ${sel?PRIMARY:'rgba(212,168,67,0.4)'}`,
        borderRadius:12, cursor:'pointer',
        boxShadow:`0 2px 10px rgba(139,105,20,0.06)`,
        transition:'all 0.15s', overflow:'hidden',
      }}
    >
      <div style={{ padding:'12px 14px', display:'flex', alignItems:'flex-start', gap:12 }}>
        {/* Index / Checkbox */}
        <div
          onClick={(e) => { e.stopPropagation(); onToggle(id); }}
          style={{
            width:40, height:40, borderRadius:'50%', flexShrink:0, marginTop:2,
            border:`1.5px solid ${sel?PRIMARY:BORDER}`,
            background: sel ? PRIMARY : SURFACE,
            display:'flex', alignItems:'center', justifyContent:'center', cursor:'pointer',
          }}
        >
          {sel
            ? <CheckSquare size={18} color="white" />
            : <span style={{ color:PRIMARY, fontWeight:800, fontSize:12 }}>{index+1}</span>}
        </div>

        {/* Main info */}
        <div style={{ flex:1, minWidth:0 }}>
          {/* Title row */}
          <div style={{ display:'flex', alignItems:'center', flexWrap:'wrap', gap:6, marginBottom:4 }}>
            <span style={{ color:DARK, fontWeight:700, fontSize:14, marginRight:2 }}>{s.name}</span>

            {/* Armed badge */}
            <span style={{
              display:'inline-flex', alignItems:'center', gap:3,
              padding:'2px 7px', borderRadius:5, fontSize:9.5, fontWeight:700,
              color: armed ? ARMED_RED : UNARMED_BLUE,
              background: armed ? 'rgba(198,40,40,0.08)' : 'rgba(21,101,192,0.08)',
              border:`1px solid ${armed ? 'rgba(198,40,40,0.3)' : 'rgba(21,101,192,0.3)'}`,
            }}>
              {armed ? <Shield size={9}/> : <ShieldOff size={9}/>}
              {armed ? 'सशस्त्र' : 'निःशस्त्र'}
            </span>

            {/* Rank badge */}
            <Badge text={rh(rank)} color={rc.text} bg={rc.bg} border={rc.border} />

            {/* Staff count */}
            {sahyogi.length > 0 && (
              <Badge text={`${sahyogi.length} कर्मचारी`}
                color={SUCCESS} bg="rgba(45,106,30,0.08)" border="rgba(45,106,30,0.25)" />
            )}
          </div>

          {/* Detail rows */}
          <div style={{ display:'flex', flexWrap:'wrap', gap:'4px 16px' }}>
            <Tag icon={BadgeCheck} text={vd(s.pno)} />
            <Tag icon={Phone} text={vd(s.mobile)} />
            {busNo && <Tag icon={Bus} text={`बस–${busNo}`} color={ACCENT} />}
          </div>
          <div style={{ marginTop:3 }}>
            <Tag icon={MapPin} text={`${vd(s.centerName)} • ${vd(s.gpName)}`} color={INFO} />
          </div>
          <div style={{ marginTop:2 }}>
            <Tag icon={Layers} text={`${vd(s.sectorName)} › ${vd(s.zoneName)} › ${vd(s.superZoneName)}`} />
          </div>
        </div>

        {/* Print button */}
        <button
          onClick={(e) => { e.stopPropagation(); onPrint([{ ...s }]); }}
          title="Print duty card"
          style={{
            background:'none', border:`1px solid ${BORDER}`, borderRadius:8,
            padding:'7px 9px', cursor:'pointer', color:PRIMARY, flexShrink:0,
            display:'flex', alignItems:'center', justifyContent:'center',
            transition:'background 0.15s',
          }}
          onMouseEnter={e => e.currentTarget.style.background=SURFACE}
          onMouseLeave={e => e.currentTarget.style.background='none'}
        >
          <Printer size={16} />
        </button>
      </div>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────
export default function DutyCardPage() {
  const [items,       setItems]       = useState([]);
  const [total,       setTotal]       = useState(0);
  const [totalPages,  setTotalPages]  = useState(1);
  const [page,        setPage]        = useState(1);
  const [loading,     setLoading]     = useState(false);

  const [q,           setQ]           = useState('');
  const [inputVal,    setInputVal]    = useState('');
  const [rankFilter,  setRankFilter]  = useState(null);
  const [armedFilter, setArmedFilter] = useState('all');
  const [selected,    setSelected]    = useState(new Set());

  const debouncedSetQ = useCallback(debounce((v) => {
    setQ(v);
    setPage(1);
  }, 400), []);

  // Fetch
  const fetchData = useCallback(async (pg, query) => {
    setLoading(true);
    try {
      const params = new URLSearchParams({ page: pg, limit: LIMIT });
      if (query) params.set('q', query);
      const res     = await api.get(`/admin/duties?${params}`);
      const wrapper = res?.data || res || {};
      const dataArr = (wrapper.data || []).map(e => ({ ...e }));
      setItems(dataArr);
      setTotal(wrapper.total || 0);
      setTotalPages(wrapper.totalPages || 1);
      setSelected(new Set());
    } catch (err) {
      toast.error(`लोड विफल: ${err.message || err}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchData(page, q); }, [page, q]);

  // Client-side filter (rank + armed)
  const visible = useMemo(() => {
    return items.filter(s => {
      if (rankFilter) {
        const rf = rankFilter.toLowerCase();
        const pr = (s.rank || s.user_rank || '').toLowerCase();
        const rankOk = pr === rf ||
          (s.sahyogi || []).some(e => (e.user_rank || e.rank || '').toLowerCase() === rf);
        if (!rankOk) return false;
      }
      if (armedFilter !== 'all') {
        const wantArmed = armedFilter === 'armed';
        if (wantArmed !== isArmedFn(s)) return false;
      }
      return true;
    });
  }, [items, rankFilter, armedFilter]);

  // Print all (fetches all pages)
  const handlePrintAll = async () => {
    try {
      const all = [];
      let pg = 1;
      let tp = totalPages;
      while (pg <= tp) {
        const params = new URLSearchParams({ page: pg, limit: 200 });
        if (q) params.set('q', q);
        const res     = await api.get(`/admin/duties?${params}`);
        const wrapper = res?.data || res || {};
        all.push(...(wrapper.data || []));
        tp = wrapper.totalPages || 1;
        pg++;
      }
      const toPrint = all.filter(s => {
        if (rankFilter) {
          const rf = rankFilter.toLowerCase();
          const pr = (s.rank || s.user_rank || '').toLowerCase();
          const ok = pr === rf || (s.sahyogi||[]).some(e => (e.user_rank||e.rank||'').toLowerCase()===rf);
          if (!ok) return false;
        }
        if (armedFilter !== 'all') {
          const wantArmed = armedFilter === 'armed';
          if (wantArmed !== isArmedFn(s)) return false;
        }
        return true;
      });
      if (!toPrint.length) { toast.error('कोई रिकॉर्ड नहीं'); return; }
      printDutyCards(toPrint);
    } catch (err) {
      toast.error(`प्रिंट विफल: ${err.message || err}`);
    }
  };

  const handlePrintSelected = () => {
    const list = visible.filter(s => selected.has(s.id));
    if (!list.length) return;
    printDutyCards(list);
  };

  const toggleSelect = (id) => {
    setSelected(prev => {
      const n = new Set(prev);
      n.has(id) ? n.delete(id) : n.add(id);
      return n;
    });
  };

  const toggleSelectAll = () => {
    if (selected.size === visible.length) {
      setSelected(new Set());
    } else {
      setSelected(new Set(visible.map(s => s.id)));
    }
  };

  const allSelected = visible.length > 0 && selected.size === visible.length;

  const countLabel = () => {
    const parts = [];
    if (rankFilter) parts.push(`पद: ${rankFilter}`);
    if (armedFilter !== 'all') parts.push(armedFilter === 'armed' ? 'सशस्त्र' : 'निःशस्त्र');
    return parts.length ? parts.join(' • ') : 'कुल ड्यूटी';
  };

  // ── Render ──────────────────────────────────────────────────────────────────
  return (
    <div style={{ display:'flex', flexDirection:'column', height:'100%', background:BG, fontFamily:"'Tiro Devanagari Hindi', Georgia, serif" }}>

      {/* ── Filter bar ───────────────────────────────────────────────────────── */}
      <div style={{ background:SURFACE, padding:'12px 16px', borderBottom:`1px solid ${BORDER}`, flexShrink:0 }}>

        {/* Search */}
        <div style={{ position:'relative', marginBottom:10 }}>
          <Search size={16} style={{ position:'absolute', left:12, top:'50%', transform:'translateY(-50%)', color:SUBTLE }} />
          <input
            value={inputVal}
            onChange={e => { setInputVal(e.target.value); debouncedSetQ(e.target.value.trim()); }}
            placeholder="नाम, PNO, केंद्र, जोन, थाना से खोजें..."
            style={{
              width:'100%', padding:'9px 36px 9px 36px',
              border:`1.2px solid ${BORDER}`, borderRadius:10, outline:'none',
              background:'white', color:DARK, fontSize:13,
              fontFamily:'inherit',
            }}
            onFocus={e => e.target.style.borderColor=PRIMARY}
            onBlur={e => e.target.style.borderColor=BORDER}
          />
          {inputVal && (
            <button onClick={() => { setInputVal(''); setQ(''); setPage(1); }}
              style={{ position:'absolute', right:10, top:'50%', transform:'translateY(-50%)', background:'none', border:'none', cursor:'pointer', color:SUBTLE, display:'flex' }}>
              <X size={16} />
            </button>
          )}
        </div>

        {/* Armed toggle + active filter badge */}
        <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between', flexWrap:'wrap', gap:8, marginBottom:10 }}>
          <ArmedToggle value={armedFilter} onChange={(v) => { setArmedFilter(v); setSelected(new Set()); }} />
          {armedFilter !== 'all' && (
            <span style={{
              padding:'3px 10px', borderRadius:8, fontSize:10, fontWeight:700,
              color: armedFilter==='armed'?ARMED_RED:UNARMED_BLUE,
              background: armedFilter==='armed'?'rgba(198,40,40,0.08)':'rgba(21,101,192,0.08)',
              border:`1px solid ${armedFilter==='armed'?'rgba(198,40,40,0.25)':'rgba(21,101,192,0.25)'}`,
            }}>
              {visible.length} मिले
            </span>
          )}
        </div>

        {/* Rank chips */}
        <div style={{ display:'flex', gap:6, overflowX:'auto', paddingBottom:2 }}>
          <RankChip
            label="सभी पद"
            selected={rankFilter===null}
            colors={{ text:PRIMARY, bg:SURFACE, border:BORDER }}
            onToggle={() => setRankFilter(null)}
          />
          {ALL_RANKS.map(rank => {
            const rc = rankColor(rank);
            return (
              <RankChip
                key={rank}
                label={rank}
                selected={rankFilter===rank}
                colors={rc}
                onToggle={() => { setRankFilter(prev => prev===rank ? null : rank); setSelected(new Set()); }}
              />
            );
          })}
        </div>
      </div>

      {/* ── Action bar ───────────────────────────────────────────────────────── */}
      {!loading && visible.length > 0 && (
        <div style={{
          background:'white', padding:'8px 16px',
          borderBottom:`1px solid ${BORDER}`, display:'flex',
          alignItems:'center', gap:10, flexShrink:0, flexWrap:'wrap',
        }}>
          {/* Count */}
          <div>
            <div style={{ color:DARK, fontWeight:700, fontSize:13 }}>
              {(rankFilter || armedFilter!=='all')
                ? `${visible.length} / ${total}`
                : total > items.length ? `${items.length} / ${total}` : `${total}`}
            </div>
            <div style={{ color:SUBTLE, fontSize:10 }}>{countLabel()}</div>
          </div>

          <div style={{ flex:1 }} />

          {/* Select all */}
          <button
            onClick={toggleSelectAll}
            style={{
              display:'inline-flex', alignItems:'center', gap:5,
              padding:'6px 12px', borderRadius:8, cursor:'pointer',
              border:`1px solid ${BORDER}`, background:'transparent', color:PRIMARY,
              fontSize:11, fontWeight:700,
            }}
          >
            {allSelected ? <CheckSquare size={14}/> : <Square size={14}/>}
            {allSelected ? 'Deselect All' : 'Select All'}
          </button>

          {/* Print selected */}
          {selected.size > 0 && (
            <button onClick={handlePrintSelected} style={{
              display:'inline-flex', alignItems:'center', gap:5,
              padding:'7px 14px', borderRadius:8, cursor:'pointer',
              border:'none', background:PRIMARY, color:'white',
              fontSize:11, fontWeight:700,
            }}>
              <Printer size={13}/> Print ({selected.size})
            </button>
          )}

          {/* Print all */}
          <button onClick={handlePrintAll} style={{
            display:'inline-flex', alignItems:'center', gap:5,
            padding:'7px 14px', borderRadius:8, cursor:'pointer',
            border:'none', background:DARK, color:'white',
            fontSize:11, fontWeight:700,
          }}>
            <Printer size={13}/> Print All ({visible.length})
          </button>

          {/* Refresh */}
          <button onClick={() => fetchData(page, q)} title="Refresh"
            style={{
              background:'none', border:`1px solid ${BORDER}`, borderRadius:8,
              padding:'6px 8px', cursor:'pointer', color:PRIMARY, display:'flex',
            }}>
            <RefreshCw size={14} />
          </button>
        </div>
      )}

      {/* ── List ─────────────────────────────────────────────────────────────── */}
      <div style={{ flex:1, overflowY:'auto', padding:'12px 16px' }}>
        {loading ? (
          <div style={{ display:'flex', alignItems:'center', justifyContent:'center', height:300 }}>
            <div style={{
              width:36, height:36, border:`3px solid ${SURFACE}`,
              borderTop:`3px solid ${PRIMARY}`, borderRadius:'50%',
              animation:'spin 0.8s linear infinite',
            }} />
            <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
          </div>
        ) : visible.length === 0 ? (
          <div style={{ display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center', height:280, color:SUBTLE }}>
            <Filter size={48} style={{ opacity:0.3, marginBottom:12 }} />
            <div style={{ fontSize:15, fontWeight:600 }}>
              {rankFilter || armedFilter!=='all'
                ? `"${[rankFilter, armedFilter!=='all'?(armedFilter==='armed'?'सशस्त्र':'निःशस्त्र'):null].filter(Boolean).join(' + ')}" के लिए कोई ड्यूटी नहीं`
                : 'कोई ड्यूटी नहीं मिली'}
            </div>
          </div>
        ) : (
          <div style={{ display:'flex', flexDirection:'column', gap:8 }}>
            {visible.map((s, i) => (
              <DutyCard
                key={s.id}
                s={s}
                index={i + (page-1)*LIMIT}
                selected={selected.has(s.id)}
                onToggle={toggleSelect}
                onPrint={printDutyCards}
              />
            ))}
          </div>
        )}
      </div>

      {/* ── Pagination ────────────────────────────────────────────────────────── */}
      {!loading && (rankFilter === null && armedFilter === 'all') && (
        <Pagination
          page={page}
          totalPages={totalPages}
          total={total}
          onPage={(p) => { setPage(p); window.scrollTo(0,0); }}
        />
      )}
    </div>
  );
}