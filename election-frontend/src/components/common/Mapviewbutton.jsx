// MapViewButton.jsx
// A standalone button to navigate to the MapViewPage.
// Place this wherever you want in your app (sidebar, dashboard, navbar, etc.)
// It does NOT import MapViewPage directly — uses React Router navigate.

import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';

// ── Palette (matches app theme) ───────────────────────────────────────────────
const C = {
  primary: '#0F2B5B',
  accent:  '#FBBF24',
  surface: '#FFFFFF',
  border:  '#DDE3EE',
  dark:    '#1A2332',
};

// ══════════════════════════════════════════════════════════════════════════════
//  MapViewButton — default export
//  Props:
//    variant: 'full' | 'icon' | 'sidebar'   (default: 'full')
//    className: optional extra class
//    style: optional extra inline styles
// ══════════════════════════════════════════════════════════════════════════════
export default function MapViewButton({ variant = 'full', className = '', style = {} }) {
  const navigate  = useNavigate();
  const [hovered, setHovered] = useState(false);
  const [pressed, setPressed] = useState(false);

  const go = () => navigate('/map-view');

  // ── Variant: 'icon' — compact circular FAB-style ──────────────────────────
  if (variant === 'icon') {
    return (
      <button
        onClick={go}
        title="चुनाव नक्शा देखें"
        className={className}
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        onMouseDown={() => setPressed(true)}
        onMouseUp={() => setPressed(false)}
        style={{
          width: 44, height: 44, borderRadius: '50%',
          background: hovered ? C.primary + 'E6' : C.primary,
          border: 'none', cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: hovered
            ? '0 6px 20px rgba(15,43,91,0.4)'
            : '0 3px 10px rgba(15,43,91,0.25)',
          transform: pressed ? 'scale(0.94)' : hovered ? 'scale(1.05)' : 'scale(1)',
          transition: 'all 0.18s cubic-bezier(0.34,1.56,0.64,1)',
          ...style,
        }}
      >
        <MapPinIcon size={20} color="#fff" />
      </button>
    );
  }

  // ── Variant: 'sidebar' — full-width nav item style ────────────────────────
  if (variant === 'sidebar') {
    return (
      <button
        onClick={go}
        className={`nav-item ${className}`}
        onMouseEnter={() => setHovered(true)}
        onMouseLeave={() => setHovered(false)}
        style={{
          width: '100%', background: 'none', border: 'none', cursor: 'pointer',
          display: 'flex', alignItems: 'center', gap: 12,
          padding: '10px 12px', borderRadius: 10, margin: '2px 0',
          backgroundColor: hovered ? 'rgba(212,168,67,0.12)' : 'transparent',
          transition: 'background 0.18s',
          ...style,
        }}
      >
        <MapPinIcon size={18} color="rgba(255,255,255,0.4)" />
        <span style={{ color: 'rgba(255,255,255,0.5)', fontSize: 13, fontFamily: 'inherit' }}>
          चुनाव नक्शा
        </span>
      </button>
    );
  }

  // ── Variant: 'full' (default) — rich dashboard card-style button ──────────
  return (
    <button
      onClick={go}
      className={className}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onMouseDown={() => setPressed(true)}
      onMouseUp={() => setPressed(false)}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 10,
        padding: '12px 20px', borderRadius: 12, border: 'none', cursor: 'pointer',
        background: hovered
          ? `linear-gradient(135deg, #0F2B5B, #1E3F80)`
          : `linear-gradient(135deg, #0F2B5B, #162F6B)`,
        boxShadow: hovered
          ? '0 8px 24px rgba(15,43,91,0.45)'
          : '0 4px 14px rgba(15,43,91,0.30)',
        transform: pressed ? 'scale(0.97) translateY(1px)' : hovered ? 'translateY(-2px)' : 'none',
        transition: 'all 0.2s cubic-bezier(0.34,1.56,0.64,1)',
        fontFamily: "'Noto Sans Devanagari', 'Segoe UI', sans-serif",
        ...style,
      }}
    >
      {/* Icon container */}
      <div style={{
        width: 36, height: 36, borderRadius: 8,
        background: 'rgba(251,191,36,0.18)',
        border: '1px solid rgba(251,191,36,0.35)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
        transform: hovered ? 'scale(1.08) rotate(-3deg)' : 'scale(1)',
        transition: 'transform 0.2s ease',
      }}>
        <MapPinIcon size={18} color={C.accent} />
      </div>

      {/* Text */}
      <div style={{ textAlign: 'left' }}>
        <div style={{ color: '#fff', fontSize: 13, fontWeight: 800, lineHeight: 1.2 }}>
          चुनाव नक्शा
        </div>
        <div style={{ color: 'rgba(255,255,255,0.55)', fontSize: 10, marginTop: 2 }}>
          मतदान केन्द्र देखें
        </div>
      </div>

      {/* Arrow */}
      <div style={{
        marginLeft: 4,
        opacity: hovered ? 1 : 0.5,
        transform: hovered ? 'translateX(3px)' : 'translateX(0)',
        transition: 'all 0.18s ease',
      }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={C.accent} strokeWidth="2.5" strokeLinecap="round">
          <polyline points="9 18 15 12 9 6"/>
        </svg>
      </div>
    </button>
  );
}

// ── SVG icon ─────────────────────────────────────────────────────────────────
function MapPinIcon({ size = 20, color = 'white' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/>
      <circle cx="12" cy="10" r="3"/>
    </svg>
  );
}