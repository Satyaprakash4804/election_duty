import { useState, useEffect, useCallback } from 'react';
import apiClient from '../../api/client';
import { useNavigate } from 'react-router-dom';
import { printDutyCard, toAdminShape } from '../../components/DutyCardPrint';
import {
  LayoutDashboard,
  MapPin,
  Users,
  ClipboardList,
  Layers,
  Map,
  Ticket,
} from "lucide-react";

// ── PALETTE (matches Flutter exactly) ────────────────────────────────────────
const C = {
  bg: '#FDF6E3',
  surface: '#F5E6C8',
  primary: '#8B6914',
  accent: '#B8860B',
  dark: '#4A3000',
  subtle: '#AA8844',
  border: '#D4A843',
  error: '#C0392B',
  success: '#2D6A1E',
  successBg: '#E6F2DF',
  info: '#1A5276',
  armed: '#1B5E20',
  unarmed: '#37474F',
};

// ── Rank map (Hindi) ──────────────────────────────────────────────────────────
const RANK_MAP = {
  constable: 'आरक्षी', 'head constable': 'मुख्य आरक्षी',
  si: 'उप निरीक्षक', 'sub inspector': 'उप निरीक्षक',
  inspector: 'निरीक्षक', asi: 'सहायक उप निरीक्षक',
  'assistant sub inspector': 'सहायक उप निरीक्षक',
  dsp: 'उपाधीक्षक', asp: 'सहा0 पुलिस अधीक्षक',
  sp: 'पुलिस अधीक्षक',
  'circle officer': 'क्षेत्राधिकारी', co: 'क्षेत्राधिकारी',
};
const CENTER_TYPE_MAP = {
  'a++': 'अत्यति संवेदनशील', a: 'अति संवेदनशील',
  b: 'संवेदनशील', c: 'सामान्य',
};

const rh = (val) => RANK_MAP[(val || '').toLowerCase()] || val || '—';
const v = (x) => (!x || x.toString().trim() === '') ? '—' : x.toString();
const ct = (x) => CENTER_TYPE_MAP[(x || '').toLowerCase()] || x || '—';

const typeColor = (t) => {
  switch ((t || '').toUpperCase()) {
    case 'A++': return '#6C3483';
    case 'A': return C.error;
    case 'B': return C.accent;
    default: return C.info;
  }
};

// ── Nav config per role ───────────────────────────────────────────────────────
const NAV_CONFIG = {
  sector: [
    { key: 'overview', label: 'डैशबोर्ड' },
    { key: 'duty', label: 'ड्यूटी' },
    { key: 'attendance', label: 'बूथ & उपस्थिति' },
    { key: 'rules', label: 'मानक' },
  ],
  zone: [
    { key: 'overview', label: 'डैशबोर्ड' },
    { key: 'duty', label: 'ड्यूटी' },
    { key: 'sectors', label: 'सेक्टर' },
    { key: 'rules', label: 'मानक' },
  ],
  kshetra: [
    { key: 'overview', label: 'डैशबोर्ड' },
    { key: 'duty', label: 'ड्यूटी' },
    { key: 'zones', label: 'जोन' },
    { key: 'rules', label: 'मानक'},
  ],
  booth: [
    { key: 'overview', label: 'डैशबोर्ड' },
    { key: 'duty', label: 'ड्यूटी' },
    { key: 'costaff', label: 'सहयोगी' },
    { key: 'dutycard', label: 'ड्यूटी कार्ड' },
  ],
};

// ── SVG Icons ─────────────────────────────────────────────────────────────────
const Icon = ({ name, size = 16, color = 'currentColor', className = '' }) => {
  const icons = {
    dashboard: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><rect x="3" y="3" width="7" height="7" /><rect x="14" y="3" width="7" height="7" /><rect x="14" y="14" width="7" height="7" /><rect x="3" y="14" width="7" height="7" /></svg>,
    pin: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z" /><circle cx="12" cy="10" r="3" /></svg>,
    users: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M23 21v-2a4 4 0 00-3-3.87" /><path d="M16 3.13a4 4 0 010 7.75" /></svg>,
    badge: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M12 2l3.09 6.26L22 9.27l-5 4.87L18.18 21 12 17.77 5.82 21 7 14.14 2 9.27l6.91-1.01L12 2z" /></svg>,
    key: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 11-7.778 7.778 5.5 5.5 0 017.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4" /></svg>,
    nav: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><polygon points="3 11 22 2 13 21 11 13 3 11" /></svg>,
    shield: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" /></svg>,
    phone: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M22 16.92v3a2 2 0 01-2.18 2 19.79 19.79 0 01-8.63-3.07A19.5 19.5 0 013.07 8.8a19.79 19.79 0 01-3.07-8.63A2 2 0 012 0h3a2 2 0 012 1.72 12.84 12.84 0 00.7 2.81 2 2 0 01-.45 2.11L6.09 7.91a16 16 0 006 6l1.27-1.27a2 2 0 012.11-.45 12.84 12.84 0 002.81.7A2 2 0 0122 14.92z" /></svg>,
    building: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M6 22V2l12 4v16" /><path d="M6 12h12" /><path d="M10 2v20M14 6v16" /></svg>,
    check: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><polyline points="20 6 9 17 4 12" /></svg>,
    x: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" /></svg>,
    refresh: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><polyline points="23 4 23 10 17 10" /><path d="M20.49 15a9 9 0 11-2.12-9.36L23 10" /></svg>,
    logout: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4" /><polyline points="16 17 21 12 16 7" /><line x1="21" y1="12" x2="9" y2="12" /></svg>,
    history: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><polyline points="1 4 1 10 7 10" /><path d="M3.51 15a9 9 0 102.13-9.36L1 10" /></svg>,
    map: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><polygon points="1 6 1 22 8 18 16 22 23 18 23 2 16 6 8 2 1 6" /><line x1="8" y1="2" x2="8" y2="18" /><line x1="16" y1="6" x2="16" y2="22" /></svg>,
    layers: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><polygon points="12 2 2 7 12 12 22 7 12 2" /><polyline points="2 17 12 22 22 17" /><polyline points="2 12 12 17 22 12" /></svg>,
    grid: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><rect x="3" y="3" width="7" height="7" /><rect x="14" y="3" width="7" height="7" /><rect x="14" y="14" width="7" height="7" /><rect x="3" y="14" width="7" height="7" /></svg>,
    eye: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" /><circle cx="12" cy="12" r="3" /></svg>,
    eyeoff: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19m-6.72-1.07a3 3 0 11-4.24-4.24" /><line x1="1" y1="1" x2="23" y2="23" /></svg>,
    save: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z" /><polyline points="17 21 17 13 7 13 7 21" /><polyline points="7 3 7 8 15 8" /></svg>,
    search: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" /></svg>,
    bus: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M8 6v6" /><path d="M15 6v6" /><path d="M2 12h19.6" /><path d="M18 18h3s.5-1.7.8-2.8c.1-.4.2-.8.2-1.2 0-.4-.1-.8-.2-1.2l-1.4-5C20.1 6.8 19.1 6 18 6H4a2 2 0 00-2 2v10h3" /><circle cx="7" cy="18" r="2" /><path d="M9 18h5" /><circle cx="16" cy="18" r="2" /></svg>,
    user: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2" /><circle cx="12" cy="7" r="4" /></svg>,
    lock: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><rect x="3" y="11" width="18" height="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0110 0v4" /></svg>,
    info: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><circle cx="12" cy="12" r="10" /><line x1="12" y1="16" x2="12" y2="12" /><line x1="12" y1="8" x2="12.01" y2="8" /></svg>,
    briefcase: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><rect x="2" y="7" width="20" height="14" rx="2" ry="2" /><path d="M16 21V5a2 2 0 00-2-2h-4a2 2 0 00-2 2v16" /></svg>,
    home: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z" /><polyline points="9 22 9 12 15 12 15 22" /></svg>,
    globe: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><circle cx="12" cy="12" r="10" /><line x1="2" y1="12" x2="22" y2="12" /><path d="M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z" /></svg>,
    star: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" /></svg>,
    vote: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M9 11l3 3L22 4" /><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11" /></svg>,
    hash: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><line x1="4" y1="9" x2="20" y2="9" /><line x1="4" y1="15" x2="20" y2="15" /><line x1="10" y1="3" x2="8" y2="21" /><line x1="16" y1="3" x2="14" y2="21" /></svg>,
    clipboard: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2" /><rect x="9" y="3" width="6" height="4" rx="1" /></svg>,
    printer: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><polyline points="6 9 6 2 18 2 18 9" /><path d="M6 18H4a2 2 0 01-2-2v-5a2 2 0 012-2h16a2 2 0 012 2v5a2 2 0 01-2 2h-2" /><rect x="6" y="14" width="12" height="8" /></svg>,
    alert: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><circle cx="12" cy="12" r="10" /><line x1="12" y1="8" x2="12" y2="12" /><line x1="12" y1="16" x2="12.01" y2="16" /></svg>,
    checkcircle: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><path d="M22 11.08V12a10 10 0 11-5.93-9.14" /><polyline points="22 4 12 14.01 9 11.01" /></svg>,
    loader: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`${className} animate-spin`} style={{ animation: 'spin 1s linear infinite' }}><line x1="12" y1="2" x2="12" y2="6" /><line x1="12" y1="18" x2="12" y2="22" /><line x1="4.93" y1="4.93" x2="7.76" y2="7.76" /><line x1="16.24" y1="16.24" x2="19.07" y2="19.07" /><line x1="2" y1="12" x2="6" y2="12" /><line x1="18" y1="12" x2="22" y2="12" /><line x1="4.93" y1="19.07" x2="7.76" y2="16.24" /><line x1="16.24" y1="7.76" x2="19.07" y2="4.93" /></svg>,
    cpu: <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}><rect x="9" y="9" width="6" height="6" /><rect x="2" y="2" width="20" height="20" rx="2" ry="2" /></svg>,
  };
  return icons[name] || null;
};

// ═══════════════════════════════════════════════════════════════════════════════
//  SHARED COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════════

function SectionCard({ iconName, title, children }) {
  return (
    <div style={{
      borderRadius: 14, overflow: 'hidden', marginBottom: 16,
      background: '#fff', border: `1px solid ${C.border}80`,
      boxShadow: `0 3px 10px ${C.primary}0a`,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10, padding: '12px 16px',
        background: `${C.surface}99`, borderBottom: `1px solid ${C.border}66`,
      }}>
        <div style={{
          width: 28, height: 28, borderRadius: 8, display: 'flex',
          alignItems: 'center', justifyContent: 'center', background: `${C.primary}1f`,
        }}>
          <Icon name={iconName} size={13} color={C.primary} />
        </div>
        <span style={{ fontWeight: 800, fontSize: 14, color: C.dark }}>{title}</span>
      </div>
      <div style={{ padding: 16 }}>{children}</div>
    </div>
  );
}

function InfoTile({ iconName, label, value }) {
  if (!value || value === '—') return null;
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-start', gap: 12,
      padding: '10px 0', borderBottom: `1px solid ${C.border}26`,
    }}>
      <div style={{
        width: 28, height: 28, borderRadius: 8, display: 'flex',
        alignItems: 'center', justifyContent: 'center', background: C.surface, flexShrink: 0, marginTop: 2,
      }}>
        <Icon name={iconName} size={12} color={C.primary} />
      </div>
      <div>
        <p style={{ fontSize: 10, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 2, color: C.subtle }}>{label}</p>
        <p style={{ fontSize: 13, fontWeight: 600, color: C.dark }}>{value}</p>
      </div>
    </div>
  );
}

function StatCard({ iconName, label, value, color }) {
  return (
    <div style={{
      borderRadius: 14, padding: 14, display: 'flex', flexDirection: 'column',
      background: '#fff', border: `1px solid ${C.border}80`,
      boxShadow: `0 3px 8px ${color}12`,
    }}>
      <div style={{
        width: 32, height: 32, borderRadius: 10, display: 'flex',
        alignItems: 'center', justifyContent: 'center', marginBottom: 8,
        background: `${color}1f`,
      }}>
        <Icon name={iconName} size={15} color={color} />
      </div>
      <p style={{ fontSize: 10, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 4, color: C.subtle }}>{label}</p>
      <p style={{ fontSize: 13, fontWeight: 900, color: C.dark, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{value}</p>
    </div>
  );
}

function HeroCard({ user, duty, subtitle, noDuty }) {
  return (
    <div style={{
      borderRadius: 16, padding: 22, marginBottom: 16, position: 'relative', overflow: 'hidden',
      background: `linear-gradient(135deg, ${C.dark} 0%, #6B4E0A 100%)`,
      boxShadow: `0 6px 16px ${C.dark}59`,
    }}>
      <div style={{
        position: 'absolute', top: 0, right: 0, width: 128, height: 128,
        borderRadius: '50%', background: C.border, opacity: 0.1,
        transform: 'translate(40%, -40%)',
      }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 16 }}>
        <div style={{
          width: 48, height: 48, borderRadius: '50%', display: 'flex',
          alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          background: 'rgba(255,255,255,0.12)', border: `1px solid ${C.border}66`,
        }}>
          <Icon name="user" size={22} color="#fff" />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          {subtitle && <p style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.1em', textTransform: 'uppercase', marginBottom: 2, color: C.border }}>{subtitle}</p>}
          <p style={{ fontWeight: 900, color: '#fff', fontSize: 18, lineHeight: 1.2 }}>{user?.name || '—'}</p>
          <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.6)' }}>PNO: {user?.pno || '—'}</p>
        </div>
      </div>
      <div style={{ height: 1, background: 'rgba(255,255,255,0.15)', marginBottom: 12 }} />
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        {user?.thana && <HeroBadge iconName="shield" label={user.thana} />}
        {user?.district && <HeroBadge iconName="building" label={user.district} />}
        <HeroBadge iconName="star" label={rh(user?.rank || user?.user_rank)} />
      </div>
      {!noDuty && duty?.centerName && (
        <>
          <div style={{ height: 1, background: 'rgba(255,255,255,0.15)', margin: '12px 0' }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Icon name="vote" size={13} color="rgba(255,255,255,0.5)" />
            <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.7)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              ड्यूटी: {duty.centerName || duty.sectorName || duty.zoneName || duty.superZoneName || '—'}
            </p>
          </div>
        </>
      )}
    </div>
  );
}

function HeroBadge({ iconName, label }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 5, borderRadius: 20,
      padding: '5px 10px', background: 'rgba(255,255,255,0.1)',
      border: '1px solid rgba(255,255,255,0.24)',
    }}>
      <Icon name={iconName} size={11} color="rgba(255,255,255,0.6)" />
      <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.7)' }}>{label}</span>
    </div>
  );
}

function NavButton({ iconName, label, color, onClick }) {
  return (
    <button onClick={onClick} style={{
      width: '100%', borderRadius: 14, padding: '14px 0', display: 'flex',
      alignItems: 'center', justifyContent: 'center', gap: 8, fontWeight: 700,
      fontSize: 13, color: '#fff', border: 'none', cursor: 'pointer',
      background: color, boxShadow: `0 4px 12px ${color}66`, marginBottom: 12,
    }}>
      <Icon name={iconName} size={15} color="#fff" />
      {label}
    </button>
  );
}

function OfficerCard({ label, officers = [] }) {
  return (
    <SectionCard iconName="badge" title={label}>
      {officers.map((o, i) => (
        <div key={i} style={{
          display: 'flex', alignItems: 'center', gap: 12,
          padding: '10px 0',
          borderBottom: i < officers.length - 1 ? `1px solid ${C.border}66` : 'none',
        }}>
          <div style={{
            width: 36, height: 36, borderRadius: '50%', display: 'flex',
            alignItems: 'center', justifyContent: 'center', flexShrink: 0,
            background: C.surface, border: `1px solid ${C.border}`,
          }}>
            <Icon name="user" size={17} color={C.primary} />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <p style={{ fontWeight: 700, fontSize: 13, color: C.dark, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{v(o.name)}</p>
            <p style={{ fontSize: 10, color: C.subtle }}>{rh(o.user_rank || o.rank)} · PNO: {v(o.pno)}</p>
          </div>
          {o.mobile && (
            <a href={`tel:${o.mobile}`} style={{
              width: 36, height: 36, borderRadius: 10, display: 'flex',
              alignItems: 'center', justifyContent: 'center', background: C.successBg, flexShrink: 0,
            }}>
              <Icon name="phone" size={14} color={C.success} />
            </a>
          )}
        </div>
      ))}
    </SectionCard>
  );
}

function NoDutyState() {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', paddingTop: 64 }}>
      <div style={{
        borderRadius: 24, padding: 40, display: 'flex', flexDirection: 'column',
        alignItems: 'center', textAlign: 'center',
        background: '#fff', border: `1px solid ${C.border}80`,
        boxShadow: `0 4px 16px ${C.primary}0d`,
      }}>
        <div style={{
          width: 64, height: 64, borderRadius: '50%', display: 'flex',
          alignItems: 'center', justifyContent: 'center', marginBottom: 16,
          background: C.surface, border: `1px solid ${C.border}`,
        }}>
          <Icon name="pin" size={28} color={C.primary} />
        </div>
        <p style={{ fontWeight: 900, fontSize: 16, marginBottom: 8, color: C.dark }}>अभी तक ड्यूटी नहीं सौंपी गई</p>
        <p style={{ fontSize: 12, color: C.subtle }}>व्यवस्थापक द्वारा ड्यूटी सौंपे जाने पर यहाँ दिखेगी।</p>
      </div>
    </div>
  );
}

function LoadingSpinner() {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '80px 0' }}>
      <div style={{
        width: 36, height: 36, border: `3px solid ${C.border}`,
        borderTopColor: C.primary, borderRadius: '50%',
        animation: 'spin 0.8s linear infinite',
      }} />
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BOOTH — OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════════
function BoothOverview({ duty, user, onGoToDutyCard, onOpenMap }) {
  if (!duty) return <NoDutyState />;
  return (
    <div>
      <HeroCard user={user} duty={duty} noDuty={false} />
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
        <StatCard iconName="pin" label="मतदान केंद्र" value={v(duty.centerName)} color={C.primary} />
        <StatCard iconName="bus" label="बस संख्या" value={duty.busNo ? `बस–${duty.busNo}` : '—'} color={C.info} />
        <StatCard iconName="map" label="सेक्टर" value={v(duty.sectorName)} color={C.success} />
        <StatCard iconName="users" label="सहयोगी कर्मी" value={`${(duty.allStaff || []).length} कर्मी`} color="#D84315" />
      </div>
      <SectionCard iconName="info" title="संक्षिप्त विवरण">
        <InfoTile iconName="shield" label="थाना" value={v(duty.thana)} />
        <InfoTile iconName="building" label="ग्राम पंचायत" value={v(duty.gpName)} />
        <InfoTile iconName="layers" label="जोन" value={v(duty.zoneName)} />
        <InfoTile iconName="globe" label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile iconName="hash" label="केंद्र प्रकार" value={ct(duty.centerType)} />
      </SectionCard>
      <NavButton iconName="nav" label="Google Maps पर नेविगेट करें" color={C.primary} onClick={onOpenMap} />
      <NavButton iconName="printer" label="ड्यूटी कार्ड प्रिंट करें" color={C.dark} onClick={onGoToDutyCard} />
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BOOTH — DUTY DETAIL
// ═══════════════════════════════════════════════════════════════════════════════
function BoothDutyDetail({ duty, onOpenMap }) {
  if (!duty) return <NoDutyState />;
  return (
    <div>
      <SectionCard iconName="pin" title="ड्यूटी स्थान">
        <InfoTile iconName="vote" label="मतदान केंद्र" value={v(duty.centerName)} />
        <InfoTile iconName="home" label="पता" value={v(duty.centerAddress)} />
        <InfoTile iconName="hash" label="केंद्र प्रकार" value={ct(duty.centerType)} />
        <InfoTile iconName="shield" label="थाना" value={v(duty.thana)} />
        <InfoTile iconName="building" label="ग्राम पंचायत" value={v(duty.gpName)} />
      </SectionCard>
      <SectionCard iconName="map" title="प्रशासनिक विवरण">
        <InfoTile iconName="map" label="सेक्टर" value={v(duty.sectorName)} />
        <InfoTile iconName="layers" label="जोन" value={v(duty.zoneName)} />
        <InfoTile iconName="home" label="जोन मुख्यालय" value={v(duty.zoneHq)} />
        <InfoTile iconName="globe" label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile iconName="bus" label="बस संख्या" value={duty.busNo ? `बस–${duty.busNo}` : null} />
        <InfoTile iconName="user" label="नियुक्त किया" value={v(duty.assignedBy)} />
      </SectionCard>
      {(duty.sectorOfficers || []).length > 0 && <OfficerCard label="सेक्टर अधिकारी" officers={duty.sectorOfficers} />}
      {(duty.zonalOfficers || []).length > 0 && <OfficerCard label="जोनल अधिकारी" officers={duty.zonalOfficers} />}
      {(duty.superOfficers || []).length > 0 && <OfficerCard label="क्षेत्र अधिकारी" officers={duty.superOfficers} />}
      <NavButton iconName="nav" label="Google Maps पर नेविगेट करें" color={C.primary} onClick={onOpenMap} />
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BOOTH — CO-STAFF
// ═══════════════════════════════════════════════════════════════════════════════
function BoothCoStaff({ duty }) {
  if (!duty) return <NoDutyState />;
  const staff = duty.allStaff || [];
  return (
    <SectionCard iconName="users" title={`सहयोगी कर्मी (${staff.length})`}>
      {staff.length === 0 ? (
        <div style={{ padding: '32px 0', textAlign: 'center' }}>
          <p style={{ fontSize: 13, color: C.subtle }}>कोई सहयोगी नहीं</p>
        </div>
      ) : staff.map((s, i) => {
        const armed = s.is_armed === 1 || s.is_armed === true;
        return (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 12, padding: '12px 0',
            borderBottom: i < staff.length - 1 ? `1px solid ${C.border}66` : 'none',
          }}>
            <div style={{
              width: 40, height: 40, borderRadius: '50%', display: 'flex',
              alignItems: 'center', justifyContent: 'center', flexShrink: 0,
              fontSize: 13, fontWeight: 900,
              background: `${armed ? C.armed : C.unarmed}1a`,
              border: `1px solid ${armed ? C.armed : C.unarmed}4d`,
              color: armed ? C.armed : C.unarmed,
            }}>
              {i + 1}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <p style={{ fontWeight: 700, fontSize: 13, color: C.dark }}>{v(s.name)}</p>
              <p style={{ fontSize: 10, color: C.subtle }}>{v(s.pno)} · {v(s.thana)}</p>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 2 }}>
                <span style={{ fontSize: 10, fontWeight: 600, color: C.accent }}>{rh(s.user_rank || s.rank)}</span>
                <span style={{
                  borderRadius: 4, padding: '1px 5px', fontSize: 9, fontWeight: 700,
                  background: `${armed ? C.armed : C.unarmed}1a`,
                  color: armed ? C.armed : C.unarmed,
                }}>{armed ? 'सशस्त्र' : 'निःशस्त्र'}</span>
              </div>
            </div>
            {s.mobile && (
              <a href={`tel:${s.mobile}`} style={{
                width: 36, height: 36, borderRadius: 10, display: 'flex',
                alignItems: 'center', justifyContent: 'center', background: C.successBg,
              }}>
                <Icon name="phone" size={14} color={C.success} />
              </a>
            )}
          </div>
        );
      })}
    </SectionCard>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BOOTH — DUTY CARD
// ═══════════════════════════════════════════════════════════════════════════════
function BoothDutyCard({ duty, user }) {
  const [printing, setPrinting] = useState(false);
  const [hasMarked, setHasMarked] = useState(false);

  if (!duty) return <NoDutyState />;

  const handlePrint = async () => {
    setPrinting(true);
    try {
      await printDutyCard(toAdminShape(duty, user));
      await apiClient.post('/staff/mark-card-downloaded', {});
      setHasMarked(true);
    } catch (e) {
      alert('प्रिंट त्रुटि: ' + e.message);
    } finally {
      setPrinting(false);
    }
  };

  const sahyogi = duty.allStaff || [];
  const rows = [
    ['नाम', user?.name], ['PNO', user?.pno], ['पद', rh(user?.rank || user?.user_rank)],
    ['केंद्र', duty.centerName], ['केंद्र प्रकार', ct(duty.centerType)],
    ['बस', duty.busNo ? `बस–${duty.busNo}` : null],
    ['सेक्टर', duty.sectorName], ['जोन', duty.zoneName],
    ['सहयोगी', `${sahyogi.length} कर्मी`],
  ];

  return (
    <div>
      <div style={{
        borderRadius: 16, padding: 20, marginBottom: 12, position: 'relative', overflow: 'hidden',
        background: `linear-gradient(135deg, ${C.dark} 0%, #5A3E08 100%)`,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <div style={{
            width: 48, height: 48, borderRadius: 14, display: 'flex',
            alignItems: 'center', justifyContent: 'center', background: 'rgba(255,255,255,0.12)',
          }}>
            <Icon name="badge" size={22} color="#fff" />
          </div>
          <div style={{ flex: 1 }}>
            <p style={{ fontWeight: 900, color: '#fff', fontSize: 16 }}>ड्यूटी कार्ड</p>
            <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.6)' }}>आधिकारिक चुनाव ड्यूटी कार्ड</p>
          </div>
          <button onClick={handlePrint} disabled={printing} style={{
            display: 'flex', alignItems: 'center', gap: 6, borderRadius: 12,
            padding: '10px 16px', fontWeight: 700, fontSize: 12, color: '#fff',
            border: 'none', cursor: printing ? 'not-allowed' : 'pointer',
            background: printing ? `${C.primary}99` : C.primary,
          }}>
            {printing ? <div style={{ width: 14, height: 14, border: '2px solid #fff', borderTopColor: 'transparent', borderRadius: '50%', animation: 'spin 0.8s linear infinite' }} /> : <><Icon name="printer" size={13} color="#fff" /> प्रिंट</>}
          </button>
        </div>
      </div>

      {hasMarked && (
        <div style={{
          borderRadius: 10, padding: '12px 16px', marginBottom: 12,
          display: 'flex', alignItems: 'center', gap: 8,
          background: `${C.success}14`, border: `1px solid ${C.success}4d`,
        }}>
          <Icon name="checkcircle" size={17} color={C.success} />
          <span style={{ fontSize: 13, fontWeight: 700, color: C.success }}>ड्यूटी कार्ड डाउनलोड हो गया ✓</span>
        </div>
      )}

      <SectionCard iconName="badge" title="कार्ड विवरण">
        {rows.map(([label, value]) => value && (
          <div key={label} style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '10px 0', borderBottom: `1px solid ${C.border}26`,
          }}>
            <span style={{ fontSize: 12, color: C.subtle }}>{label}</span>
            <span style={{ fontSize: 12, fontWeight: 700, color: C.dark }}>{value}</span>
          </div>
        ))}
      </SectionCard>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SECTOR — OVERVIEW
// ═══════════════════════════════════════════════════════════════════════════════
function SectorOverview({ duty, user }) {
  if (!duty) return <NoDutyState />;
  return (
    <div>
      <HeroCard user={user} duty={duty} noDuty={false} subtitle="सेक्टर अधिकारी" />
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
        <StatCard iconName="vote" label="कुल बूथ" value={`${duty.totalBooths || 0}`} color={C.primary} />
        <StatCard iconName="users" label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} color={C.success} />
        <StatCard iconName="building" label="ग्राम पंचायत" value={`${(duty.gramPanchayats || []).length}`} color={C.info} />
        <StatCard iconName="map" label="जोन" value={v(duty.zoneName)} color={C.accent} />
      </div>
      <SectionCard iconName="info" title="सेक्टर विवरण">
        <InfoTile iconName="grid" label="सेक्टर" value={v(duty.sectorName)} />
        <InfoTile iconName="home" label="मुख्यालय" value={v(duty.hqAddress)} />
        <InfoTile iconName="layers" label="जोन" value={v(duty.zoneName)} />
        <InfoTile iconName="globe" label="सुपर जोन" value={v(duty.superZoneName)} />
      </SectionCard>
    </div>
  );
}

function SectorInfo({ duty }) {
  if (!duty) return <NoDutyState />;
  return (
    <div>
      <SectionCard iconName="grid" title="सेक्टर जानकारी">
        <InfoTile iconName="grid" label="सेक्टर" value={v(duty.sectorName)} />
        <InfoTile iconName="home" label="HQ पता" value={v(duty.hqAddress)} />
        <InfoTile iconName="map" label="जोन" value={v(duty.zoneName)} />
        <InfoTile iconName="globe" label="सुपर जोन" value={v(duty.superZoneName)} />
      </SectionCard>
      {(duty.coOfficers || []).length > 0 && <OfficerCard label="सह-सेक्टर अधिकारी" officers={duty.coOfficers} />}
      {(duty.zonalOfficers || []).length > 0 && <OfficerCard label="जोनल अधिकारी (वरिष्ठ)" officers={duty.zonalOfficers} />}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SECTOR — BOOTH ATTENDANCE
// ═══════════════════════════════════════════════════════════════════════════════
function SectorBoothAttendance({ duty, onRefresh }) {
  const [pendingUpdates, setPendingUpdates] = useState({});
  const [saving, setSaving] = useState(false);
  const [searchQ, setSearchQ] = useState('');

  if (!duty) return <NoDutyState />;

  const centers = duty.centers || [];

  const getAttended = (s) => {
    if (pendingUpdates.hasOwnProperty(s.duty_id)) return pendingUpdates[s.duty_id];
    return s.attended === 1 || s.attended === true;
  };

  const toggle = (dutyId, current) => {
    setPendingUpdates(p => ({ ...p, [dutyId]: !current }));
  };

  const filtered = searchQ
    ? centers.filter(c =>
      (c.name || '').toLowerCase().includes(searchQ.toLowerCase()) ||
      (c.gp_name || '').toLowerCase().includes(searchQ.toLowerCase()) ||
      (c.thana || '').toLowerCase().includes(searchQ.toLowerCase())
    )
    : centers;

  let totalStaff = 0, presentStaff = 0;
  centers.forEach(c => (c.staff || []).forEach(s => {
    totalStaff++;
    if (getAttended(s)) presentStaff++;
  }));

  const saveAll = async () => {
    if (!Object.keys(pendingUpdates).length) return;
    setSaving(true);
    try {
      const updates = Object.entries(pendingUpdates).map(([dutyId, attended]) => ({ dutyId: Number(dutyId), attended }));
      await apiClient.post('/staff/attendance/bulk', { updates });
      setPendingUpdates({});
      onRefresh();
    } catch (e) {
      alert('त्रुटि: ' + e.message);
    } finally { setSaving(false); }
  };

  const pendingCount = Object.keys(pendingUpdates).length;

  return (
    <div>
      <div style={{
        borderRadius: 14, padding: 16, marginBottom: 16,
        background: `linear-gradient(135deg, ${C.dark} 0%, #5A3E08 100%)`,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <Icon name="vote" size={18} color="#fff" />
            <span style={{ fontWeight: 900, color: '#fff', fontSize: 16 }}>बूथ उपस्थिति</span>
          </div>
          {pendingCount > 0 && (
            <button onClick={saveAll} disabled={saving} style={{
              display: 'flex', alignItems: 'center', gap: 6, borderRadius: 10,
              padding: '8px 14px', fontWeight: 700, fontSize: 12, color: '#fff',
              border: 'none', cursor: 'pointer', background: C.success,
            }}>
              {saving ? <div style={{ width: 13, height: 13, border: '2px solid #fff', borderTopColor: 'transparent', borderRadius: '50%', animation: 'spin 0.8s linear infinite' }} /> : <Icon name="save" size={13} color="#fff" />}
              {saving ? '...' : `${pendingCount} सेव करें`}
            </button>
          )}
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
          {[['कुल स्टाफ', totalStaff, C.border], ['उपस्थित', presentStaff, '#4CAF50'], ['अनुपस्थित', totalStaff - presentStaff, '#ef5350']].map(([l, n, col]) => (
            <div key={l} style={{ borderRadius: 10, padding: '12px 0', textAlign: 'center', background: 'rgba(255,255,255,0.1)' }}>
              <p style={{ fontWeight: 900, fontSize: 20, color: col }}>{n}</p>
              <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.7)' }}>{l}</p>
            </div>
          ))}
        </div>
      </div>

      <div style={{ position: 'relative', marginBottom: 12 }}>
        <div style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)' }}>
          <Icon name="search" size={15} color={C.subtle} />
        </div>
        <input
          style={{
            width: '100%', borderRadius: 10, paddingLeft: 36, paddingRight: 12,
            paddingTop: 10, paddingBottom: 10, fontSize: 13, outline: 'none',
            background: '#fff', border: `1px solid ${C.border}`, color: C.dark, boxSizing: 'border-box',
          }}
          placeholder="बूथ/थाना/GP खोजें..."
          value={searchQ} onChange={e => setSearchQ(e.target.value)}
        />
      </div>

      {filtered.map((center, ci) => {
        const staff = center.staff || [];
        const present = staff.filter(s => getAttended(s)).length;
        const tc = typeColor(center.center_type);
        return (
          <div key={ci} style={{
            borderRadius: 14, overflow: 'hidden', marginBottom: 12,
            background: '#fff', border: `1px solid ${C.border}66`,
            boxShadow: `0 3px 8px ${C.primary}0a`,
          }}>
            <div style={{
              display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px',
              background: `${tc}0f`, borderBottom: `1px solid ${tc}33`,
            }}>
              <span style={{
                borderRadius: 6, padding: '4px 8px', fontWeight: 900, fontSize: 11,
                color: '#fff', background: tc,
              }}>{center.center_type || 'C'}</span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <p style={{ fontWeight: 700, fontSize: 13, color: C.dark, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{center.name || '—'}</p>
                <p style={{ fontSize: 10, color: C.subtle }}>{center.gp_name || ''} · {center.thana || ''}</p>
              </div>
              <span style={{
                borderRadius: 20, padding: '4px 10px', fontSize: 11, fontWeight: 900,
                background: present === staff.length && staff.length > 0 ? `${C.success}1a` : `${C.subtle}14`,
                color: present === staff.length && staff.length > 0 ? C.success : C.subtle,
                border: `1px solid ${present === staff.length && staff.length > 0 ? C.success : C.border}4d`,
              }}>{present}/{staff.length}</span>
            </div>
            {staff.length === 0 ? (
              <p style={{ textAlign: 'center', fontSize: 12, padding: '16px 0', color: C.subtle }}>कोई स्टाफ असाइन नहीं</p>
            ) : staff.map((s, si) => {
              const attended = getAttended(s);
              const armed = s.is_armed === 1 || s.is_armed === true;
              return (
                <div key={si} style={{
                  display: 'flex', alignItems: 'center', gap: 12, padding: '10px 14px',
                  borderBottom: si < staff.length - 1 ? `1px solid ${C.border}4d` : 'none',
                }}>
                  <div style={{
                    width: 36, height: 36, borderRadius: '50%', display: 'flex',
                    alignItems: 'center', justifyContent: 'center', flexShrink: 0,
                    background: `${armed ? C.armed : C.unarmed}1a`,
                    border: `1px solid ${armed ? C.armed : C.unarmed}4d`,
                  }}>
                    {armed ? <Icon name="shield" size={14} color={C.armed} /> : <Icon name="user" size={14} color={C.unarmed} />}
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <p style={{ fontWeight: 700, fontSize: 13, color: C.dark }}>{s.name || '—'}</p>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                      <span style={{ fontSize: 10, color: C.subtle }}>{rh(s.user_rank)}</span>
                      <span style={{ fontSize: 10, color: C.subtle }}>·</span>
                      <span style={{ fontSize: 10, color: C.subtle }}>{s.pno || ''}</span>
                      <span style={{
                        borderRadius: 4, padding: '0 4px', fontSize: 9, fontWeight: 700,
                        background: `${armed ? C.armed : C.unarmed}1a`, color: armed ? C.armed : C.unarmed,
                      }}>{armed ? 'सशस्त्र' : 'निःशस्त्र'}</span>
                    </div>
                  </div>
                  <button onClick={() => s.duty_id && toggle(s.duty_id, attended)} style={{
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4,
                    borderRadius: 20, padding: '6px 12px', fontSize: 10, fontWeight: 700,
                    width: 60, cursor: 'pointer', border: `1.5px solid ${attended ? C.success : `${C.error}66`}`,
                    background: attended ? C.success : `${C.error}1a`,
                    color: attended ? '#fff' : C.error,
                  }}>
                    {attended ? <><Icon name="check" size={11} color="#fff" />हाँ</> : <><Icon name="x" size={11} color={C.error} />नहीं</>}
                  </button>
                </div>
              );
            })}
          </div>
        );
      })}

      {filtered.length === 0 && (
        <div style={{ padding: '40px 0', textAlign: 'center' }}>
          <p style={{ fontSize: 13, color: C.subtle }}>कोई बूथ नहीं मिला</p>
        </div>
      )}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ZONE
// ═══════════════════════════════════════════════════════════════════════════════
function ZoneOverview({ duty, user }) {
  if (!duty) return <NoDutyState />;
  return (
    <div>
      <HeroCard user={user} duty={duty} noDuty={false} subtitle="जोनल अधिकारी" />
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
        <StatCard iconName="grid" label="कुल सेक्टर" value={`${duty.totalSectors || 0}`} color={C.primary} />
        <StatCard iconName="vote" label="कुल बूथ" value={`${duty.totalBooths || 0}`} color={C.info} />
        <StatCard iconName="users" label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} color={C.success} />
        <StatCard iconName="globe" label="सुपर जोन" value={v(duty.superZoneName)} color={C.accent} />
      </div>
      <SectionCard iconName="map" title="जोन विवरण">
        <InfoTile iconName="map" label="जोन" value={v(duty.zoneName)} />
        <InfoTile iconName="home" label="मुख्यालय" value={v(duty.hqAddress)} />
        <InfoTile iconName="globe" label="सुपर जोन" value={v(duty.superZoneName)} />
      </SectionCard>
    </div>
  );
}

function ZoneInfo({ duty }) {
  if (!duty) return <NoDutyState />;
  return (
    <div>
      <SectionCard iconName="map" title="जोन विस्तार जानकारी">
        <InfoTile iconName="map" label="जोन" value={v(duty.zoneName)} />
        <InfoTile iconName="home" label="HQ" value={v(duty.hqAddress)} />
        <InfoTile iconName="globe" label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile iconName="grid" label="कुल सेक्टर" value={`${duty.totalSectors || 0}`} />
        <InfoTile iconName="vote" label="कुल बूथ" value={`${duty.totalBooths || 0}`} />
        <InfoTile iconName="users" label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} />
      </SectionCard>
      {(duty.coOfficers || []).length > 0 && <OfficerCard label="जोनल अधिकारी" officers={duty.coOfficers} />}
      {(duty.superOfficers || []).length > 0 && <OfficerCard label="क्षेत्र अधिकारी (वरिष्ठ)" officers={duty.superOfficers} />}
    </div>
  );
}

function ZoneSectors({ duty }) {
  if (!duty) return <NoDutyState />;
  const sectors = duty.sectors || [];
  return (
    <SectionCard iconName="grid" title={`सेक्टर (${sectors.length})`}>
      {sectors.length === 0 ? (
        <p style={{ textAlign: 'center', fontSize: 13, padding: '20px 0', color: C.subtle }}>कोई सेक्टर नहीं</p>
      ) : sectors.map((s, i) => (
        <div key={i} style={{ padding: '12px 0', borderBottom: i < sectors.length - 1 ? `1px solid ${C.border}66` : 'none' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{
              width: 36, height: 36, borderRadius: 10, display: 'flex',
              alignItems: 'center', justifyContent: 'center', flexShrink: 0,
              background: `${C.primary}1a`,
            }}>
              <Icon name="grid" size={14} color={C.primary} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <p style={{ fontWeight: 700, fontSize: 13, color: C.dark }}>{s.name || '—'}</p>
              <p style={{ fontSize: 11, color: C.subtle }}>{s.gp_count || 0} GP · {s.center_count || 0} बूथ · {s.staff_assigned || 0} स्टाफ</p>
            </div>
          </div>
          {(s.officers || []).length > 0 && (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 8 }}>
              {(s.officers || []).map((o, j) => (
                <span key={j} style={{
                  borderRadius: 20, padding: '4px 10px', fontSize: 10, fontWeight: 600,
                  background: `${C.primary}14`, border: `1px solid ${C.primary}33`, color: C.primary,
                }}>{o.name} ({rh(o.user_rank || o.rank)})</span>
              ))}
            </div>
          )}
        </div>
      ))}
    </SectionCard>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  KSHETRA
// ═══════════════════════════════════════════════════════════════════════════════
function KshetraOverview({ duty, user }) {
  if (!duty) return <NoDutyState />;
  return (
    <div>
      <HeroCard user={user} duty={duty} noDuty={false} subtitle="क्षेत्र अधिकारी" />
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
        <StatCard iconName="map" label="कुल जोन" value={`${duty.totalZones || 0}`} color={C.primary} />
        <StatCard iconName="grid" label="कुल सेक्टर" value={`${duty.totalSectors || 0}`} color={C.info} />
        <StatCard iconName="vote" label="कुल बूथ" value={`${duty.totalBooths || 0}`} color={C.success} />
        <StatCard iconName="users" label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} color={C.accent} />
      </div>
      <SectionCard iconName="layers" title="क्षेत्र विवरण">
        <InfoTile iconName="layers" label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile iconName="building" label="जिला" value={v(duty.district)} />
        <InfoTile iconName="briefcase" label="ब्लॉक" value={v(duty.block)} />
      </SectionCard>
    </div>
  );
}

function KshetraInfo({ duty }) {
  if (!duty) return <NoDutyState />;
  return (
    <div>
      <SectionCard iconName="layers" title="क्षेत्र जानकारी">
        <InfoTile iconName="layers" label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile iconName="building" label="जिला" value={v(duty.district)} />
        <InfoTile iconName="briefcase" label="ब्लॉक" value={v(duty.block)} />
        <InfoTile iconName="map" label="कुल जोन" value={`${duty.totalZones || 0}`} />
        <InfoTile iconName="grid" label="कुल सेक्टर" value={`${duty.totalSectors || 0}`} />
        <InfoTile iconName="vote" label="कुल बूथ" value={`${duty.totalBooths || 0}`} />
        <InfoTile iconName="users" label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} />
      </SectionCard>
      {(duty.coOfficers || []).length > 0 && <OfficerCard label="सह-क्षेत्र अधिकारी" officers={duty.coOfficers} />}
    </div>
  );
}

function KshetraZones({ duty }) {
  if (!duty) return <NoDutyState />;
  const zones = duty.zones || [];
  return (
    <SectionCard iconName="map" title={`जोन (${zones.length})`}>
      {zones.length === 0 ? (
        <p style={{ textAlign: 'center', fontSize: 13, padding: '20px 0', color: C.subtle }}>कोई जोन नहीं</p>
      ) : zones.map((z, i) => (
        <div key={i} style={{ padding: '12px 0', borderBottom: i < zones.length - 1 ? `1px solid ${C.border}66` : 'none' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{
              width: 36, height: 36, borderRadius: 10, display: 'flex',
              alignItems: 'center', justifyContent: 'center', flexShrink: 0,
              background: `${C.info}1a`,
            }}>
              <Icon name="map" size={14} color={C.info} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <p style={{ fontWeight: 700, fontSize: 13, color: C.dark }}>{z.name || '—'}</p>
              <p style={{ fontSize: 11, color: C.subtle }}>{z.sector_count || 0} सेक्टर · {z.center_count || 0} बूथ · {z.staff_assigned || 0} स्टाफ</p>
              {z.hq_address && <p style={{ fontSize: 10, color: C.subtle }}>HQ: {z.hq_address}</p>}
            </div>
          </div>
          {(z.officers || []).length > 0 && (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 8 }}>
              {(z.officers || []).map((o, j) => (
                <span key={j} style={{
                  borderRadius: 20, padding: '4px 10px', fontSize: 10, fontWeight: 600,
                  background: `${C.primary}14`, border: `1px solid ${C.primary}33`, color: C.primary,
                }}>{o.name} ({rh(o.user_rank || o.rank)})</span>
              ))}
            </div>
          )}
        </div>
      ))}
    </SectionCard>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RULES
// ═══════════════════════════════════════════════════════════════════════════════
const RULES_CONFIG = {
  'A++': { label: 'अत्यति संवेदनशील', color: '#6C3483' },
  A: { label: 'अति संवेदनशील', color: C.error },
  B: { label: 'संवेदनशील', color: C.accent },
  C: { label: 'सामान्य', color: C.info },
};

function RulesSection({ rules = [] }) {
  const grouped = {};
  rules.forEach(r => {
    const s = (r.sensitivity || '?').toString();
    if (!grouped[s]) grouped[s] = [];
    grouped[s].push(r);
  });

  return (
    <div>
      <div style={{
        borderRadius: 14, padding: 16, marginBottom: 16,
        background: `linear-gradient(135deg, ${C.dark} 0%, #5A3E08 100%)`,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <Icon name="clipboard" size={18} color="#fff" />
          <div>
            <p style={{ fontWeight: 900, color: '#fff', fontSize: 16 }}>बूथ स्टाफ मानक</p>
            <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.6)' }}>संवेदनशीलता के अनुसार आवश्यक स्टाफ</p>
          </div>
        </div>
      </div>

      {rules.length === 0 ? (
        <SectionCard iconName="info" title="मानक">
          <p style={{ textAlign: 'center', fontSize: 13, padding: '20px 0', color: C.subtle }}>कोई मानक सेट नहीं है</p>
        </SectionCard>
      ) : ['A++', 'A', 'B', 'C'].filter(s => grouped[s]).map(s => {
        const { label, color } = RULES_CONFIG[s] || { label: s, color: C.primary };
        const list = grouped[s];
        const total = list.reduce((a, r) => a + ((r.count || 0)), 0);
        return (
          <div key={s} style={{
            borderRadius: 14, overflow: 'hidden', marginBottom: 12,
            background: '#fff', border: `1px solid ${color}4d`,
          }}>
            <div style={{
              display: 'flex', alignItems: 'center', gap: 12, padding: '12px 16px',
              background: `${color}12`, borderBottom: `1px solid ${color}33`,
            }}>
              <span style={{ borderRadius: 6, padding: '4px 10px', fontWeight: 900, fontSize: 12, color: '#fff', background: color }}>{s}</span>
              <span style={{ flex: 1, fontWeight: 700, fontSize: 13, color }}>{label}</span>
              <span style={{ fontWeight: 900, fontSize: 13, color }}>{total} कर्मी</span>
            </div>
            <div style={{ padding: 12, display: 'flex', flexDirection: 'column', gap: 8 }}>
              {list.map((r, i) => {
                const isArmed = r.isArmed === true || r.is_armed === 1;
                return (
                  <div key={i} style={{
                    display: 'flex', alignItems: 'center', gap: 12, borderRadius: 10,
                    padding: '10px 12px', background: C.bg, border: `1px solid ${C.border}66`,
                  }}>
                    {isArmed ? <Icon name="shield" size={14} color={C.armed} /> : <Icon name="user" size={14} color={C.unarmed} />}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <p style={{ fontWeight: 700, fontSize: 13, color: C.dark }}>{rh(r.rank)}</p>
                      <p style={{ fontSize: 10, color: isArmed ? C.armed : C.unarmed }}>{isArmed ? 'सशस्त्र' : 'निःशस्त्र'}</p>
                    </div>
                    <span style={{
                      borderRadius: 20, padding: '6px 12px', fontWeight: 900, fontSize: 14,
                      background: `${color}1a`, border: `1px solid ${color}4d`, color,
                    }}>{r.count}</span>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CHANGE PASSWORD
// ═══════════════════════════════════════════════════════════════════════════════
function ChangePassword() {
  const [form, setForm] = useState({ currentPassword: '', newPassword: '', confirmPassword: '' });
  const [show, setShow] = useState({ cur: false, new_: false, conf: false });
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState(false);

  const strength = (() => {
    const p = form.newPassword;
    return (p.length >= 6 ? 1 : 0) + (p.length >= 10 ? 1 : 0)
      + (/[A-Z0-9]/.test(p) ? 1 : 0) + (/[^A-Za-z0-9]/.test(p) ? 1 : 0);
  })();
  const strengthColor = [null, '#ef5350', '#FFA726', '#FFD700', C.success][strength] || 'transparent';
  const strengthLabel = ['', 'बहुत छोटा', 'ठीक है', 'अच्छा', 'बहुत मजबूत'][strength];

  const handleSubmit = async () => {
    if (!form.currentPassword || !form.newPassword || !form.confirmPassword) return;
    if (form.newPassword.length < 6) return;
    if (form.newPassword !== form.confirmPassword) return;
    setSaving(true);
    try {
      await apiClient.post('/staff/change-password', {
        currentPassword: form.currentPassword, newPassword: form.newPassword,
      });
      setDone(true);
      setForm({ currentPassword: '', newPassword: '', confirmPassword: '' });
    } catch (e) {
      alert('त्रुटि: ' + e.message);
    } finally { setSaving(false); }
  };

  const fields = [
    ['currentPassword', 'वर्तमान पासवर्ड *', 'cur', 'मौजूदा पासवर्ड'],
    ['newPassword', 'नया पासवर्ड *', 'new_', 'न्यूनतम 6 अक्षर'],
    ['confirmPassword', 'पासवर्ड दोबारा डालें *', 'conf', 'पुष्टि करें'],
  ];

  return (
    <div>
      <div style={{
        borderRadius: 16, padding: 20, marginBottom: 16, position: 'relative', overflow: 'hidden',
        background: `linear-gradient(135deg, ${C.dark} 0%, #5A3E08 100%)`,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <div style={{
            width: 44, height: 44, borderRadius: 14, display: 'flex',
            alignItems: 'center', justifyContent: 'center', background: 'rgba(255,255,255,0.12)',
          }}>
            <Icon name="lock" size={20} color="#fff" />
          </div>
          <div>
            <p style={{ fontWeight: 900, color: '#fff', fontSize: 16 }}>पासवर्ड बदलें</p>
            <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.6)' }}>अपना लॉगिन पासवर्ड अपडेट करें</p>
          </div>
        </div>
      </div>

      {done && (
        <div style={{
          borderRadius: 10, padding: '12px 16px', marginBottom: 12,
          display: 'flex', alignItems: 'center', gap: 8,
          background: C.successBg, border: `1px solid ${C.success}4d`,
        }}>
          <Icon name="checkcircle" size={15} color={C.success} />
          <span style={{ fontSize: 13, fontWeight: 600, color: C.success }}>पासवर्ड सफलतापूर्वक बदल दिया गया!</span>
        </div>
      )}

      <SectionCard iconName="key" title="नया पासवर्ड">
        {fields.map(([key, label, showKey, placeholder]) => (
          <div key={key} style={{ marginBottom: 16 }}>
            <label style={{ display: 'block', fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 6, color: C.subtle }}>{label}</label>
            <div style={{ position: 'relative' }}>
              <input
                type={show[showKey] ? 'text' : 'password'}
                value={form[key]}
                onChange={e => setForm(p => ({ ...p, [key]: e.target.value }))}
                placeholder={placeholder}
                style={{
                  width: '100%', borderRadius: 12, padding: '12px 40px 12px 14px',
                  fontSize: 13, outline: 'none', boxSizing: 'border-box',
                  background: C.bg, border: `1px solid ${C.border}80`, color: C.dark,
                }}
              />
              <button type="button" onClick={() => setShow(p => ({ ...p, [showKey]: !p[showKey] }))} style={{
                position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)',
                background: 'none', border: 'none', cursor: 'pointer', padding: 0,
              }}>
                <Icon name={show[showKey] ? 'eyeoff' : 'eye'} size={16} color={C.subtle} />
              </button>
            </div>
            {key === 'newPassword' && form.newPassword && (
              <div style={{ marginTop: 8 }}>
                <div style={{ display: 'flex', gap: 4, marginBottom: 4 }}>
                  {[0, 1, 2, 3].map(i => (
                    <div key={i} style={{
                      flex: 1, height: 4, borderRadius: 2,
                      background: i < strength ? strengthColor : `${C.border}40`,
                    }} />
                  ))}
                </div>
                <p style={{ fontSize: 10, fontWeight: 600, color: strengthColor }}>{strengthLabel}</p>
              </div>
            )}
          </div>
        ))}
        <button onClick={handleSubmit} disabled={saving} style={{
          width: '100%', borderRadius: 12, padding: '14px 0', fontWeight: 900,
          fontSize: 13, color: '#fff', border: 'none', cursor: saving ? 'not-allowed' : 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          background: saving ? `${C.primary}99` : C.primary,
          boxShadow: `0 4px 10px ${C.primary}59`,
        }}>
          {saving ? <div style={{ width: 16, height: 16, border: '2px solid #fff', borderTopColor: 'transparent', borderRadius: '50%', animation: 'spin 0.8s linear infinite' }} /> : <><Icon name="key" size={14} color="#fff" />पासवर्ड बदलें</>}
        </button>
      </SectionCard>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  POST ELECTION VIEW
// ═══════════════════════════════════════════════════════════════════════════════
function PostElectionView({ user, electionDate, onOpenHistory }) {
  return (
    <div style={{ padding: '0 0 24px' }}>
      <div style={{
        padding: 24, borderRadius: 18, marginBottom: 20,
        background: 'linear-gradient(135deg, #1B5E20 0%, #2E7D32 100%)',
        boxShadow: `0 6px 16px ${C.success}4d`,
        textAlign: 'center',
      }}>
        <div style={{
          width: 64, height: 64, borderRadius: '50%', margin: '0 auto 16px',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: 'rgba(255,255,255,0.15)', border: '2px solid rgba(255,255,255,0.3)',
        }}>
          <Icon name="vote" size={32} color="#fff" />
        </div>
        <p style={{ color: '#fff', fontSize: 20, fontWeight: 900, marginBottom: 6 }}>चुनाव सम्पन्न हो गया</p>
        {electionDate && <p style={{ color: 'rgba(255,255,255,0.7)', fontSize: 13, marginBottom: 8 }}>तिथि: {electionDate}</p>}
        <p style={{ color: 'rgba(255,255,255,0.6)', fontSize: 12 }}>{user?.name || ''} जी, आपकी ड्यूटी का रिकॉर्ड इतिहास में सुरक्षित है।</p>
      </div>

      <div style={{
        padding: 18, borderRadius: 16, marginBottom: 16,
        background: '#fff', border: `1px solid ${C.border}80`,
        boxShadow: `0 3px 10px ${C.primary}0a`,
        display: 'flex', alignItems: 'center', gap: 14,
      }}>
        <div style={{
          width: 50, height: 50, borderRadius: '50%', flexShrink: 0,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: C.surface, border: `1px solid ${C.border}`,
        }}>
          <Icon name="user" size={24} color={C.primary} />
        </div>
        <div>
          <p style={{ fontWeight: 900, fontSize: 16, color: C.dark }}>{user?.name || '—'}</p>
          <p style={{ fontSize: 11, color: C.subtle }}>PNO: {user?.pno || '—'} · {rh(user?.rank || user?.user_rank)}</p>
          <p style={{ fontSize: 11, color: C.subtle }}>{user?.thana || ''}{user?.district ? ` · ${user.district}` : ''}</p>
        </div>
      </div>

      <button onClick={onOpenHistory} style={{
        width: '100%', padding: '18px 0', borderRadius: 16, border: 'none', cursor: 'pointer',
        background: `linear-gradient(135deg, ${C.dark} 0%, #5A3E08 100%)`,
        boxShadow: `0 5px 14px ${C.dark}66`,
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{
            width: 40, height: 40, borderRadius: 12, display: 'flex',
            alignItems: 'center', justifyContent: 'center', background: 'rgba(255,255,255,0.12)',
          }}>
            <Icon name="history" size={22} color="#fff" />
          </div>
          <div style={{ textAlign: 'left' }}>
            <p style={{ color: '#fff', fontSize: 16, fontWeight: 900 }}>ड्यूटी इतिहास देखें</p>
            <p style={{ color: 'rgba(255,255,255,0.54)', fontSize: 11 }}>Duty History</p>
          </div>
        </div>
        <div style={{
          padding: '5px 14px', borderRadius: 20,
          background: 'rgba(255,255,255,0.1)', border: '1px solid rgba(255,255,255,0.24)',
        }}>
          <p style={{ color: 'rgba(255,255,255,0.7)', fontSize: 11 }}>सभी ड्यूटी रिकॉर्ड देखने के लिए क्लिक करें</p>
        </div>
      </button>

      <div style={{
        padding: 14, borderRadius: 12, marginTop: 16,
        background: `${C.info}0f`, border: `1px solid ${C.info}33`,
        display: 'flex', gap: 8, alignItems: 'flex-start',
      }}>
        <Icon name="info" size={16} color={C.info} />
        <p style={{ fontSize: 12, color: C.info }}>चुनाव समाप्त हो जाने के बाद यहाँ कोई सक्रिय ड्यूटी नहीं दिखाई जाती। आपकी सभी पुरानी ड्यूटियाँ "इतिहास" में उपलब्ध हैं।</p>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LOGOUT DIALOG
// ═══════════════════════════════════════════════════════════════════════════════
function LogoutDialog({ onConfirm, onCancel }) {
  return (
    <div style={{
      position: 'fixed', inset: 0, zIndex: 50, display: 'flex',
      alignItems: 'center', justifyContent: 'center', padding: 16,
      background: 'rgba(0,0,0,0.5)',
    }}>
      <div style={{
        borderRadius: 16, padding: 24, width: '100%', maxWidth: 360,
        background: C.bg, border: `1.5px solid ${C.error}`,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
          <Icon name="logout" size={18} color={C.error} />
          <p style={{ fontWeight: 900, fontSize: 16, color: C.error }}>लॉग आउट</p>
        </div>
        <p style={{ fontSize: 13, marginBottom: 20, color: C.dark }}>क्या आप लॉग आउट करना चाहते हैं?</p>
        <div style={{ display: 'flex', gap: 12 }}>
          <button onClick={onCancel} style={{
            flex: 1, borderRadius: 12, padding: '10px 0', fontWeight: 700, fontSize: 13,
            color: C.subtle, border: `1px solid ${C.border}`, background: 'transparent', cursor: 'pointer',
          }}>रद्द</button>
          <button onClick={onConfirm} style={{
            flex: 1, borderRadius: 12, padding: '10px 0', fontWeight: 700, fontSize: 13,
            color: '#fff', border: 'none', background: C.error, cursor: 'pointer',
          }}>लॉग आउट</button>
        </div>
      </div>
    </div>
  );
}



// ═══════════════════════════════════════════════════════════════════════════════
//  MAIN DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════
export default function StaffDashboardPage() {
  const [activeTab, setActiveTab] = useState('overview');
  const [duty, setDuty] = useState(null);
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [roleType, setRoleType] = useState('booth');
  const [electionDate, setElectionDate] = useState(null);
  const [isAfterElection, setIsAfterElection] = useState(false);
  const [showLogout, setShowLogout] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const nav = useNavigate();

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [userRes, dutyRes, electionRes] = await Promise.all([
        apiClient.get('/staff/profile'),
        apiClient.get('/staff/my-duty'),
        apiClient.get('/staff/election-date'),
      ]);

      const userData = userRes?.data || userRes || {};
      let dutyData = dutyRes?.data || dutyRes || null;
      if (dutyData && typeof dutyData === 'object' && !Array.isArray(dutyData)) {
        dutyData = {
          ...dutyData,
          centerName: dutyData.centerName || dutyData.center_name,
          centerAddress: dutyData.centerAddress || dutyData.center_address,
          centerType: dutyData.centerType || dutyData.center_type,
          superZoneName: dutyData.superZoneName || dutyData.super_zone_name,
          zoneName: dutyData.zoneName || dutyData.zone_name,
          sectorName: dutyData.sectorName || dutyData.sector_name,
          busNo: dutyData.busNo || dutyData.bus_no,
          allStaff: dutyData.allStaff || dutyData.all_staff || [],
          sectorOfficers: dutyData.sectorOfficers || dutyData.sector_officers || [],
          zonalOfficers: dutyData.zonalOfficers || dutyData.zonal_officers || [],
          superOfficers: dutyData.superOfficers || dutyData.super_officers || [],
          coOfficers: dutyData.coOfficers || dutyData.co_officers || [],
          boothRules: dutyData.boothRules || dutyData.booth_rules || [],
        };
      }

      const role = (dutyData?.roleType || dutyData?.role_type || 'booth').toString().toLowerCase();
      const ed = electionRes?.data || electionRes;
      let isAfter = false;
      if (ed) {
        const parsed = new Date(ed);
        if (!isNaN(parsed)) isAfter = new Date() > parsed;
      }

      setUser(userData);
      setDuty(dutyData);
      setRoleType(role);
      setElectionDate(ed);
      setIsAfterElection(isAfter);
    } catch (e) {
      setError(e.message || 'Error loading data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadData(); }, [loadData]);
  useEffect(() => { setActiveTab('overview'); }, [roleType]);

  const handleLogout = () => {
    localStorage.clear();
    sessionStorage.clear();
    window.location.href = '/login';
  };

  const openMap = () => {
    if (!duty?.latitude || !duty?.longitude) {
      alert('इस केंद्र की GPS लोकेशन अभी तक दर्ज नहीं है।');
      return;
    }
    window.open(`https://www.google.com/maps/dir/?api=1&destination=${duty.latitude},${duty.longitude}&travelmode=driving`, '_blank');
  };

  const navItems = NAV_CONFIG[roleType] || NAV_CONFIG.booth;

  const roleLabel = { sector: 'सेक्टर अधिकारी', zone: 'जोनल अधिकारी', kshetra: 'क्षेत्र अधिकारी', booth: 'बूथ स्टाफ' }[roleType] || 'सक्रिय';

  const roleIconName = { sector: 'grid', zone: 'map', kshetra: 'layers', booth: 'vote' }[roleType] || 'vote';

  const renderSection = () => {
    if (loading) return <LoadingSpinner />;
    if (error) return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '64px 16px', textAlign: 'center' }}>
        <Icon name="alert" size={48} color={C.error} />
        <p style={{ fontWeight: 900, fontSize: 16, marginTop: 16, marginBottom: 8, color: C.dark }}>डेटा लोड करने में त्रुटि</p>
        <p style={{ fontSize: 12, marginBottom: 20, color: C.subtle }}>{error}</p>
        <button onClick={loadData} style={{
          display: 'flex', alignItems: 'center', gap: 8, borderRadius: 12,
          padding: '10px 20px', fontWeight: 700, fontSize: 13, color: '#fff',
          border: 'none', cursor: 'pointer', background: C.primary,
        }}>
          <Icon name="refresh" size={14} color="#fff" /> पुनः प्रयास करें
        </button>
      </div>
    );

    if (isAfterElection) {
      return <PostElectionView user={user} electionDate={electionDate} onOpenHistory={() => nav('/staff/history')} />;
    }

    if (roleType === 'sector') {
      switch (activeTab) {
        case 'overview': return <SectorOverview duty={duty} user={user} />;
        case 'duty': return <SectorInfo duty={duty} />;
        case 'attendance': return <SectorBoothAttendance duty={duty} onRefresh={loadData} />;
        case 'rules': return <RulesSection rules={duty?.boothRules || []} />;
      }
    } else if (roleType === 'zone') {
      switch (activeTab) {
        case 'overview': return <ZoneOverview duty={duty} user={user} />;
        case 'duty': return <ZoneInfo duty={duty} />;
        case 'sectors': return <ZoneSectors duty={duty} />;
        case 'rules': return <RulesSection rules={duty?.boothRules || []} />;
      }
    } else if (roleType === 'kshetra') {
      switch (activeTab) {
        case 'overview': return <KshetraOverview duty={duty} user={user} />;
        case 'duty': return <KshetraInfo duty={duty} />;
        case 'zones': return <KshetraZones duty={duty} />;
        case 'rules': return <RulesSection rules={duty?.boothRules || []} />;
      }
    } else {
      switch (activeTab) {
        case 'overview': return <BoothOverview duty={duty} user={user} noDuty={!duty} onGoToDutyCard={() => setActiveTab('dutycard')} onOpenMap={openMap} />;
        case 'duty': return <BoothDutyDetail duty={duty} onOpenMap={openMap} />;
        case 'costaff': return <BoothCoStaff duty={duty} />;
        case 'dutycard': return <BoothDutyCard duty={duty} user={user} />;
      }
    }
    return null;
  };

  return (
    <>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;500;600;700;800;900&display=swap');
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Noto Sans Devanagari', sans-serif; }
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-track { background: ${C.surface}; }
        ::-webkit-scrollbar-thumb { background: ${C.border}; border-radius: 3px; }
        ::-webkit-scrollbar-thumb:hover { background: ${C.primary}; }
        button { font-family: 'Noto Sans Devanagari', sans-serif; }
        input { font-family: 'Noto Sans Devanagari', sans-serif; }
        a { text-decoration: none; }
      `}</style>

      <div style={{
        display: 'flex', height: '100vh', background: C.bg,
        fontFamily: "'Noto Sans Devanagari', sans-serif",
      }}>

        {/* ── SIDEBAR ── */}
        <div style={{
          width: sidebarCollapsed ? 64 : 240, flexShrink: 0,
          background: C.dark, display: 'flex', flexDirection: 'column',
          transition: 'width 0.25s ease', overflow: 'hidden',
          boxShadow: `4px 0 20px ${C.dark}40`,
        }}>
          {/* Sidebar Header */}
          <div style={{
            padding: sidebarCollapsed ? '20px 0' : 20,
            borderBottom: `1px solid rgba(255,255,255,0.1)`,
            display: 'flex', alignItems: 'center', gap: 12,
            justifyContent: sidebarCollapsed ? 'center' : 'flex-start',
          }}>
            <div style={{
              width: 40, height: 40, borderRadius: '50%', display: 'flex',
              alignItems: 'center', justifyContent: 'center', flexShrink: 0,
              background: C.primary, border: `1px solid ${C.border}`,
            }}>
              <Icon name={roleIconName} size={18} color="#fff" />
            </div>
            {!sidebarCollapsed && (
              <div style={{ flex: 1, minWidth: 0 }}>
                <p style={{ fontWeight: 900, color: '#fff', fontSize: 14, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {user?.name || 'Staff Portal'}
                </p>
                <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 2 }}>
                  <div style={{ width: 6, height: 6, borderRadius: '50%', background: C.success }} />
                  <span style={{ fontSize: 10, fontWeight: 700, color: C.success }}>{roleLabel}</span>
                </div>
              </div>
            )}
          </div>

          {/* Role Switcher */}
          {!sidebarCollapsed && (
            <div style={{ padding: '12px 16px', borderBottom: `1px solid rgba(255,255,255,0.08)` }}>
              <p style={{ fontSize: 9, fontWeight: 700, color: 'rgba(255,255,255,0.4)', textTransform: 'uppercase', letterSpacing: '0.1em', marginBottom: 6 }}>भूमिका</p>
              <select
                value={roleType}
                onChange={e => setRoleType(e.target.value)}
                style={{
                  width: '100%', borderRadius: 8, padding: '6px 10px', fontSize: 12,
                  background: 'rgba(255,255,255,0.1)', border: `1px solid rgba(255,255,255,0.2)`,
                  color: '#fff', cursor: 'pointer', outline: 'none',
                  fontFamily: "'Noto Sans Devanagari', sans-serif",
                }}
              >
                <option value="booth" style={{ background: C.dark }}>बूथ स्टाफ</option>
                <option value="sector" style={{ background: C.dark }}>सेक्टर अधिकारी</option>
                <option value="zone" style={{ background: C.dark }}>जोनल अधिकारी</option>
                <option value="kshetra" style={{ background: C.dark }}>क्षेत्र अधिकारी</option>
              </select>
            </div>
          )}

          {/* Nav Items */}
          <div style={{ flex: 1, overflowY: 'auto', padding: '8px 0' }}>
            {navItems.map(({ key, label, icon }) => {
              const active = activeTab === key;
              return (
                <button key={key} onClick={() => setActiveTab(key)} title={sidebarCollapsed ? label : ''} style={{
                  width: '100%', display: 'flex', alignItems: 'center',
                  gap: sidebarCollapsed ? 0 : 12,
                  justifyContent: sidebarCollapsed ? 'center' : 'flex-start',
                  padding: sidebarCollapsed ? '12px 0' : '12px 20px',
                  background: active ? `${C.primary}33` : 'transparent',
                  borderLeft: `3px solid ${active ? C.border : 'transparent'}`,
                  border: 'none', cursor: 'pointer', transition: 'all 0.15s',
                }}>
                  <span style={{ fontSize: 18, lineHeight: 1 }}>{icon}</span>
                  {!sidebarCollapsed && (
                    <span style={{
                      fontSize: 13, fontWeight: active ? 700 : 400,
                      color: active ? '#fff' : 'rgba(255,255,255,0.6)',
                      fontFamily: "'Noto Sans Devanagari', sans-serif",
                    }}>{label}</span>
                  )}
                  {active && !sidebarCollapsed && (
                    <div style={{ marginLeft: 'auto', width: 6, height: 6, borderRadius: '50%', background: C.border }} />
                  )}
                </button>
              );
            })}
          </div>

          {/* Sidebar Footer */}
          <div style={{ borderTop: `1px solid rgba(255,255,255,0.1)`, padding: '8px 0' }}>
            {/* History */}
            <button onClick={() => nav('/staff/history')} title={sidebarCollapsed ? 'इतिहास' : ''} style={{
              width: '100%', display: 'flex', alignItems: 'center',
              gap: sidebarCollapsed ? 0 : 12,
              justifyContent: sidebarCollapsed ? 'center' : 'flex-start',
              padding: sidebarCollapsed ? '10px 0' : '10px 20px',
              background: 'transparent', border: 'none', cursor: 'pointer',
            }}>
              <Icon name="history" size={18} color="rgba(255,255,255,0.6)" />
              {!sidebarCollapsed && <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.6)', fontFamily: "'Noto Sans Devanagari', sans-serif" }}>इतिहास</span>}
            </button>

            {/* Logout */}
            <button onClick={() => setShowLogout(true)} title={sidebarCollapsed ? 'लॉग आउट' : ''} style={{
              width: '100%', display: 'flex', alignItems: 'center',
              gap: sidebarCollapsed ? 0 : 12,
              justifyContent: sidebarCollapsed ? 'center' : 'flex-start',
              padding: sidebarCollapsed ? '10px 0' : '10px 20px',
              background: 'transparent', border: 'none', cursor: 'pointer',
            }}>
              <Icon name="logout" size={18} color={`${C.error}cc`} />
              {!sidebarCollapsed && <span style={{ fontSize: 13, color: `${C.error}cc`, fontFamily: "'Noto Sans Devanagari', sans-serif" }}>लॉग आउट</span>}
            </button>
          </div>
        </div>

        {/* ── MAIN AREA ── */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>

          {/* Top Bar */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 12, padding: '0 24px',
            height: 60, flexShrink: 0, background: C.dark,
            borderBottom: `1px solid rgba(255,255,255,0.1)`,
            boxShadow: `0 2px 8px ${C.dark}40`,
          }}>
            {/* Collapse Toggle */}
            <button onClick={() => setSidebarCollapsed(p => !p)} style={{
              width: 34, height: 34, borderRadius: 8, display: 'flex',
              alignItems: 'center', justifyContent: 'center',
              background: 'rgba(255,255,255,0.08)', border: `1px solid rgba(255,255,255,0.15)`,
              cursor: 'pointer', flexShrink: 0,
            }}>
              <svg width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.7)" strokeWidth="2" strokeLinecap="round">
                <line x1="3" y1="6" x2="21" y2="6" /><line x1="3" y1="12" x2="21" y2="12" /><line x1="3" y1="18" x2="21" y2="18" />
              </svg>
            </button>

            <div style={{ flex: 1, minWidth: 0 }}>
              <p style={{ fontWeight: 900, color: '#fff', fontSize: 15 }}>
                {navItems.find(n => n.key === activeTab)?.label || 'डैशबोर्ड'}
              </p>
              <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.5)' }}>
                {user?.name || ''} · {roleLabel}
              </p>
            </div>

            {/* Election banner inline */}
            {electionDate && (
              <div style={{
                display: 'flex', alignItems: 'center', gap: 8, borderRadius: 20,
                padding: '5px 12px',
                background: isAfterElection ? `${C.success}22` : `${C.info}22`,
                border: `1px solid ${isAfterElection ? C.success : C.info}44`,
              }}>
                <Icon name={isAfterElection ? 'checkcircle' : 'history'} size={13} color={isAfterElection ? C.success : C.info} />
                <span style={{ fontSize: 11, fontWeight: 600, color: isAfterElection ? C.success : C.info }}>
                  {isAfterElection ? 'चुनाव संपन्न' : `चुनाव: ${electionDate}`}
                </span>
              </div>
            )}

            {/* PNO badge */}
            {user?.pno && (
              <div style={{
                borderRadius: 8, padding: '4px 10px',
                background: 'rgba(255,255,255,0.08)', border: `1px solid rgba(255,255,255,0.15)`,
              }}>
                <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.7)', fontWeight: 600 }}>PNO: {user.pno}</span>
              </div>
            )}

            {/* Refresh */}
            <button onClick={loadData} style={{
              width: 34, height: 34, borderRadius: 8, display: 'flex',
              alignItems: 'center', justifyContent: 'center',
              background: 'rgba(255,255,255,0.08)', border: `1px solid rgba(255,255,255,0.15)`,
              cursor: 'pointer',
            }}>
              <div style={loading ? { animation: 'spin 0.8s linear infinite' } : {}}>
                <Icon name="refresh" size={15} color="rgba(255,255,255,0.7)" />
              </div>
            </button>
          </div>

          {/* Content */}
          <div style={{ flex: 1, overflowY: 'auto', padding: 24 }}>
            <div style={{ maxWidth: 720, margin: '0 auto' }}>
              {renderSection()}
            </div>
          </div>
        </div>
      </div>

      {showLogout && (
        <LogoutDialog onConfirm={handleLogout} onCancel={() => setShowLogout(false)} />
      )}
    </>
  );
}