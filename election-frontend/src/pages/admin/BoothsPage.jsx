import { useState, useEffect, useRef, useCallback } from 'react';
import { adminApi } from '../../api/endpoints';
import apiClient from '../../api/client';

/* ─────────────────────────────────────────────────────────────────────────────
   THEME  — warm saffron / parchment palette (mirrors Flutter constants)
───────────────────────────────────────────────────────────────────────────── */
const C = {
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
  armed:   '#6A1B9A',
  unarmed: '#1A5276',
};

const CT_LABEL = {
  'A++': 'अत्यति संवेदनशील',
  'A':   'अति संवेदनशील',
  'B':   'संवेदनशील',
  'C':   'सामान्य',
};

const PAGE_LIMIT   = 50;
const STAFF_LIMIT  = 30;
const DUTIES_LIMIT = 30;

/* ─────────────────────────────────────────────────────────────────────────────
   UTILS
───────────────────────────────────────────────────────────────────────────── */
function rgba(hex, alpha) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

function parseArmed(v) {
  if (v == null) return false;
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number')  return v === 1;
  if (typeof v === 'string') {
    const s = v.trim().toLowerCase();
    return s === '1' || s === 'true' || s === 'yes';
  }
  return false;
}

function isArmedVal(d) {
  return parseArmed(d?.isArmed ?? d?.is_armed);
}

function typeColor(type) {
  switch (type) {
    case 'A++': return '#6C3483';
    case 'A':   return C.error;
    case 'B':   return C.accent;
    default:    return C.info;
  }
}

function rankColor(rank) {
  const m = {
    'SP':             '#6A1B9A',
    'ASP':            '#1565C0',
    'DSP':            '#1A5276',
    'Inspector':      '#2E7D32',
    'SI':             '#558B2F',
    'ASI':            '#8B6914',
    'Head Constable': '#B8860B',
    'Constable':      '#6D4C41',
  };
  return m[rank] || C.primary;
}

function initials(name = '') {
  return name.split(' ')
    .filter(w => w)
    .slice(0, 2)
    .map(w => w[0])
    .join('')
    .toUpperCase() || '?';
}

/* ─────────────────────────────────────────────────────────────────────────────
   GLOBAL STYLES (injected once)
───────────────────────────────────────────────────────────────────────────── */
const GLOBAL_CSS = `
  @import url('https://fonts.googleapis.com/css2?family=Tiro+Devanagari+Hindi&family=Mukta:wght@400;600;700;800;900&display=swap');
  @keyframes spin { to { transform: rotate(360deg); } }
  @keyframes fadeIn { from { opacity:0; transform:translateY(6px); } to { opacity:1; transform:translateY(0); } }
  @keyframes slideUp { from { opacity:0; transform:translateY(20px); } to { opacity:1; transform:translateY(0); } }
  @keyframes scaleIn { from { opacity:0; transform:scale(0.95); } to { opacity:1; transform:scale(1); } }
  .booth-card { transition: box-shadow .18s, border-color .18s, transform .18s; }
  .booth-card:hover { box-shadow: 0 8px 28px ${rgba(C.primary, 0.14)} !important; border-color: ${rgba(C.border, 0.8)} !important; transform: translateY(-1px); }
  .filter-chip { transition: all .15s ease; }
  .filter-chip:hover { filter: brightness(1.08); }
  .staff-row { transition: background .12s; }
  .staff-row:hover { background: ${rgba(C.primary, 0.04)}; }
  .btn-primary { transition: opacity .15s, transform .1s; }
  .btn-primary:hover:not(:disabled) { opacity: 0.88; transform: translateY(-1px); }
  .btn-primary:active { transform: translateY(0); }
  .btn-outline:hover { background: ${rgba(C.border, 0.18)} !important; }
  .remove-btn:hover { background: ${rgba(C.error, 0.16)} !important; }
  ::-webkit-scrollbar { width: 5px; height: 5px; }
  ::-webkit-scrollbar-track { background: ${C.surface}; border-radius: 10px; }
  ::-webkit-scrollbar-thumb { background: ${C.border}; border-radius: 10px; }
  ::-webkit-scrollbar-thumb:hover { background: ${C.accent}; }
  .scroll-list { scrollbar-width: thin; scrollbar-color: ${C.border} ${C.surface}; }
`;

/* ─────────────────────────────────────────────────────────────────────────────
   ATOMS
───────────────────────────────────────────────────────────────────────────── */
function Spinner({ size = 20, color = C.primary }) {
  return (
    <div style={{
      width: size, height: size, flexShrink: 0,
      border: `2px solid ${rgba(color, 0.2)}`,
      borderTop: `2px solid ${color}`,
      borderRadius: '50%',
      animation: 'spin .7s linear infinite',
      display: 'inline-block',
    }} />
  );
}

function Pill({ label, color }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center',
      padding: '3px 10px', borderRadius: 20,
      fontSize: 11, fontWeight: 700,
      color, background: rgba(color, 0.1),
      border: `1px solid ${rgba(color, 0.3)}`,
      whiteSpace: 'nowrap',
    }}>{label}</span>
  );
}

function TypeBadge({ type }) {
  const color = typeColor(type);
  return (
    <span style={{
      padding: '2px 8px', borderRadius: 6,
      fontSize: type === 'A++' ? 11 : 13, fontWeight: 900,
      color, background: rgba(color, 0.12),
      border: `1px solid ${rgba(color, 0.4)}`,
      whiteSpace: 'nowrap',
    }}>{type}</span>
  );
}

function ArmedChip({ isArmed }) {
  const color = isArmed ? C.armed : C.unarmed;
  const label = isArmed ? 'सशस्त्र' : 'निःशस्त्र';
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 3,
      padding: '2px 7px', borderRadius: 6,
      fontSize: 9, fontWeight: 700,
      color, background: rgba(color, 0.1),
      border: `1px solid ${rgba(color, 0.35)}`,
      whiteSpace: 'nowrap',
    }}>
      {isArmed ? '⚔' : '🛡'} {label}
    </span>
  );
}

function InfoChip({ icon, text }) {
  if (!text || text === 'null' || text === 'undefined' || text === 'null' ) return null;
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, fontSize: 11, color: C.subtle }}>
      <span style={{ fontSize: 11 }}>{icon}</span>{text}
    </span>
  );
}

function Avatar({ name, color = C.primary, size = 36 }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%', flexShrink: 0,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: rgba(color, 0.12), border: `1.5px solid ${rgba(color, 0.35)}`,
      color, fontSize: size * 0.33, fontWeight: 900, fontFamily: 'Mukta, sans-serif',
    }}>
      {initials(name)}
    </div>
  );
}

function CountBadge({ count }) {
  return (
    <div style={{
      padding: '7px 10px', borderRadius: 10, textAlign: 'center',
      background: count > 0 ? rgba(C.success, 0.1) : C.surface,
      border: `1px solid ${count > 0 ? rgba(C.success, 0.4) : rgba(C.border, 0.4)}`,
      minWidth: 52,
    }}>
      <div style={{ color: count > 0 ? C.success : C.subtle, fontSize: 18, fontWeight: 900, lineHeight: 1 }}>{count}</div>
      <div style={{ color: count > 0 ? C.success : C.subtle, fontSize: 10 }}>स्टाफ</div>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   ARMED FILTER BAR
───────────────────────────────────────────────────────────────────────────── */
function ArmedFilterBar({ current, totalCount, armedCount, unarmedCount, onChange }) {
  const chips = [
    { key: 'all',     label: `सभी (${totalCount})`,           color: C.primary  },
    { key: 'armed',   label: `⚔ सशस्त्र (${armedCount})`,    color: C.armed    },
    { key: 'unarmed', label: `🛡 निःशस्त्र (${unarmedCount})`, color: C.unarmed  },
  ];
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
      <span style={{ fontSize: 11, color: C.subtle, fontWeight: 700 }}>🛡 शस्त्र:</span>
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        {chips.map(c => {
          const sel = current === c.key;
          return (
            <button
              key={c.key}
              onClick={() => onChange(c.key)}
              className="filter-chip"
              style={{
                padding: '4px 12px', borderRadius: 20, fontSize: 11, fontWeight: 700,
                cursor: 'pointer', border: 'none', outline: 'none', fontFamily: 'Mukta, sans-serif',
                color:      sel ? '#fff' : c.color,
                background: sel ? c.color : rgba(c.color, 0.08),
                boxShadow:  sel ? `0 2px 8px ${rgba(c.color, 0.3)}` : 'none',
                border:     `1px solid ${sel ? c.color : rgba(c.color, 0.35)}`,
              }}>{c.label}</button>
          );
        })}
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   RULE SUMMARY STRIP  (shown on CenterCard bottom)
───────────────────────────────────────────────────────────────────────────── */
function RuleSummaryStrip({ rule, typeColor: tColor }) {
  const n = v => ((v ?? 0));
  const siA  = n(rule.siArmedCount);
  const siU  = n(rule.siUnarmedCount);
  const hcA  = n(rule.hcArmedCount);
  const hcU  = n(rule.hcUnarmedCount);
  const cA   = n(rule.constArmedCount);
  const cU   = n(rule.constUnarmedCount);
  const auxA = n(rule.auxArmedCount);
  const auxU = n(rule.auxUnarmedCount);
  const pac  = n(rule.pacCount);
  const total = siA + siU + hcA + hcU + cA + cU + auxA + auxU;
  if (total === 0 && pac === 0) return null;

  function RuleChip({ label, armed, unarmed, color }) {
    if (armed + unarmed === 0) return null;
    return (
      <span style={{
        display: 'inline-flex', alignItems: 'center', gap: 2,
        padding: '2px 6px', borderRadius: 5, marginRight: 4,
        background: rgba(color, 0.08), border: `1px solid ${rgba(color, 0.25)}`,
        fontSize: 9, fontWeight: 700, color: rgba(color, 0.8),
        whiteSpace: 'nowrap',
      }}>
        {label}:
        {armed > 0  && <><span style={{ color: C.armed,   fontSize: 9, fontWeight: 900 }}>⚔{armed}</span></>}
        {armed > 0 && unarmed > 0 && <span style={{ color: rgba(color, 0.5) }}>/</span>}
        {unarmed > 0 && <><span style={{ color: C.unarmed, fontSize: 9, fontWeight: 900 }}>🛡{unarmed}</span></>}
      </span>
    );
  }

  function SingleChip({ label, val, color }) {
    return (
      <span style={{
        display: 'inline-flex', padding: '2px 6px', borderRadius: 5, marginRight: 4,
        background: rgba(color, 0.08), border: `1px solid ${rgba(color, 0.25)}`,
        fontSize: 9, fontWeight: 700, color, whiteSpace: 'nowrap',
      }}>{label}: {val}</span>
    );
  }

  return (
    <div style={{
      padding: '6px 12px 8px',
      background: rgba(tColor, 0.04),
      borderTop: `1px solid ${rgba(tColor, 0.15)}`,
      borderRadius: '0 0 12px 12px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
        <span style={{ fontSize: 10, color: rgba(tColor, 0.7), fontWeight: 700 }}>📋 मानक:</span>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 2, flex: 1 }}>
          <RuleChip label="SI"  armed={siA}  unarmed={siU}  color={tColor} />
          <RuleChip label="HC"  armed={hcA}  unarmed={hcU}  color={tColor} />
          <RuleChip label="CO"  armed={cA}   unarmed={cU}   color={tColor} />
          <RuleChip label="Aux" armed={auxA} unarmed={auxU} color="#E65100" />
          {pac > 0 && <SingleChip label="PAC" val={pac} color="#00695C" />}
        </div>
        <span style={{ fontSize: 10, color: tColor, fontWeight: 800, whiteSpace: 'nowrap' }}>कुल {total}</span>
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   INLINE RULE PREVIEW  (inside duties dialog)
───────────────────────────────────────────────────────────────────────────── */
function InlineRulePreview({ rule, tColor }) {
  const n = v => ((v ?? 0));
  const chips = [
    { label: 'SI सशस्त्र',    count: n(rule.siArmedCount),    color: C.armed    },
    { label: 'SI निःशस्त्र',  count: n(rule.siUnarmedCount),  color: C.unarmed  },
    { label: 'HC सशस्त्र',    count: n(rule.hcArmedCount),    color: C.armed    },
    { label: 'HC निःशस्त्र',  count: n(rule.hcUnarmedCount),  color: C.unarmed  },
    { label: 'CO सशस्त्र',    count: n(rule.constArmedCount), color: C.armed    },
    { label: 'CO निःशस्त्र',  count: n(rule.constUnarmedCount),color: C.unarmed },
    { label: 'Aux सशस्त्र',   count: n(rule.auxArmedCount),   color: C.armed    },
    { label: 'Aux निःशस्त्र', count: n(rule.auxUnarmedCount), color: C.unarmed  },
  ].filter(c => c.count > 0);

  const total = chips.reduce((s, c) => s + c.count, 0);
  if (total === 0) return null;

  return (
    <div style={{
      padding: '8px 10px', borderRadius: 8,
      background: rgba(tColor, 0.06), border: `1px solid ${rgba(tColor, 0.2)}`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 6 }}>
        <span style={{ fontSize: 11, color: tColor, fontWeight: 800 }}>📋 बूथ मानक (Rule)</span>
        <span style={{ flex: 1 }} />
        <span style={{ fontSize: 11, color: tColor, fontWeight: 700 }}>कुल {total} स्टाफ</span>
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
        {chips.map(c => (
          <span key={c.label} style={{
            display: 'inline-flex', alignItems: 'center', gap: 3,
            padding: '3px 7px', borderRadius: 5,
            background: rgba(c.color, 0.1), border: `1px solid ${rgba(c.color, 0.3)}`,
            fontSize: 10, fontWeight: 700, color: c.color,
          }}>
            {c.color === C.armed ? '⚔' : '🛡'} {c.label}: {c.count}
          </span>
        ))}
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   SEARCH INPUT
───────────────────────────────────────────────────────────────────────────── */
function SearchInput({ value, onChange, placeholder }) {
  return (
    <div style={{ position: 'relative' }}>
      <span style={{
        position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)',
        fontSize: 15, pointerEvents: 'none', color: C.subtle,
      }}>🔍</span>
      <input
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        style={{
          width: '100%', boxSizing: 'border-box',
          background: '#fff', border: `1.5px solid ${C.border}`, borderRadius: 10,
          padding: '9px 36px 9px 36px', color: C.dark, fontSize: 13,
          outline: 'none', fontFamily: 'Mukta, sans-serif',
          transition: 'border-color .15s',
        }}
        onFocus={e => e.target.style.borderColor = C.primary}
        onBlur={e => e.target.style.borderColor = C.border}
      />
      {value && (
        <button onClick={() => onChange('')} style={{
          position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)',
          background: 'none', border: 'none', cursor: 'pointer',
          color: C.subtle, fontSize: 14, lineHeight: 1, padding: 4,
        }}>✕</button>
      )}
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   DIALOG HEADER
───────────────────────────────────────────────────────────────────────────── */
function DialogHeader({ title, icon, onClose }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '14px 16px', background: C.dark,
      borderRadius: '16px 16px 0 0',
    }}>
      <div style={{
        padding: 6, borderRadius: 7,
        background: rgba(C.primary, 0.25), fontSize: 16,
      }}>{icon}</div>
      <span style={{
        color: '#fff', fontWeight: 700, fontSize: 15, flex: 1,
        overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        fontFamily: 'Mukta, sans-serif',
      }}>{title}</span>
      {onClose && (
        <button onClick={onClose} style={{
          background: 'none', border: 'none', cursor: 'pointer',
          color: 'rgba(255,255,255,0.6)', fontSize: 20, lineHeight: 1, padding: 4,
        }}>✕</button>
      )}
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   OVERLAY
───────────────────────────────────────────────────────────────────────────── */
function Overlay({ children, onClose }) {
  useEffect(() => {
    const esc = e => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', esc);
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', esc);
      document.body.style.overflow = '';
    };
  }, [onClose]);

  return (
    <div
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}
      style={{
        position: 'fixed', inset: 0, zIndex: 1000,
        background: 'rgba(74,48,0,0.45)', backdropFilter: 'blur(4px)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 16, animation: 'fadeIn .18s ease',
      }}>
      {children}
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   TOAST
───────────────────────────────────────────────────────────────────────────── */
function Toast({ msg, error }) {
  return (
    <div style={{
      position: 'fixed', bottom: 24, left: '50%', transform: 'translateX(-50%)',
      background: error ? C.error : C.success,
      color: '#fff', borderRadius: 10, padding: '9px 18px',
      fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap', zIndex: 2000,
      boxShadow: `0 4px 16px ${rgba(error ? C.error : C.success, 0.4)}`,
      animation: 'slideUp .2s ease',
      fontFamily: 'Mukta, sans-serif',
    }}>{msg}</div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   CENTER CARD
───────────────────────────────────────────────────────────────────────────── */
function CenterCard({ center, onClick }) {
  const type       = center.centerType || 'C';
  const dutyCount  = center.dutyCount  || 0;
  const boothCount = center.boothCount || 1;
  const tColor     = typeColor(type);
  const rule       = center.boothRule;

  return (
    <div
      onClick={onClick}
      className="booth-card"
      style={{
        display: 'flex', flexDirection: 'column', cursor: 'pointer',
        background: '#fff', borderRadius: 12, marginBottom: 8,
        border: `1px solid ${rgba(C.border, 0.4)}`,
        boxShadow: `0 3px 8px ${rgba(C.primary, 0.05)}`,
        overflow: 'hidden', animation: 'fadeIn .2s ease',
      }}>
      {/* Main row */}
      <div style={{ display: 'flex', alignItems: 'stretch' }}>
        {/* Type + booth count column */}
        <div style={{
          width: 64, display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center', padding: '14px 0',
          background: rgba(tColor, 0.1),
          borderRight: `1px solid ${rgba(tColor, 0.3)}`,
          flexShrink: 0,
        }}>
          {/* Sensitivity badge */}
          <div style={{
            padding: '1px 5px', borderRadius: 5, marginBottom: 5,
            background: rgba(tColor, 0.18),
          }}>
            <span style={{
              color: tColor, fontWeight: 900,
              fontSize: type === 'A++' ? 11 : 15, lineHeight: 1,
            }}>{type}</span>
          </div>
          {/* Booth count */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
            <span style={{ fontSize: 10, color: tColor }}>🗳</span>
            <span style={{ color: tColor, fontSize: 15, fontWeight: 900, lineHeight: 1 }}>{boothCount}</span>
          </div>
          <span style={{ color: rgba(tColor, 0.7), fontSize: 9, fontWeight: 600 }}>बूथ</span>
        </div>

        {/* Center info */}
        <div style={{ flex: 1, padding: '10px 12px', minWidth: 0 }}>
          <div style={{
            color: C.dark, fontWeight: 700, fontSize: 14, marginBottom: 4,
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>{center.name}</div>
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginBottom: 2 }}>
            <InfoChip icon="🚔" text={center.thana} />
            <InfoChip icon="🏛" text={center.gpName} />
          </div>
          <InfoChip icon="📍" text={[center.sectorName, center.zoneName, center.superZoneName].filter(Boolean).join(' › ')} />
          {center.blockName && (
            <div style={{ marginTop: 2 }}>
              <InfoChip icon="🏙" text={`ब्लॉक: ${center.blockName}`} />
            </div>
          )}
          {center.busNo && (
            <div style={{ marginTop: 2 }}>
              <InfoChip icon="🚌" text={`बस: ${center.busNo}`} />
            </div>
          )}
        </div>

        {/* Duty count badge */}
        <div style={{ display: 'flex', alignItems: 'center', padding: '0 12px', flexShrink: 0 }}>
          <CountBadge count={dutyCount} />
        </div>
      </div>

      {/* Rule summary strip */}
      {rule && <RuleSummaryStrip rule={rule} typeColor={tColor} />}
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   DUTY CARD
───────────────────────────────────────────────────────────────────────────── */
function DutyCard({ duty, isLocked, onRemove }) {
  const name   = duty.name || '';
  const rank   = duty.rank || duty.user_rank || '';
  const pno    = duty.pno || '';
  const thana  = duty.staffThana || duty.thana || '';
  const armed  = isArmedVal(duty);
  const rColor = rankColor(rank);
  const aColor = armed ? C.armed : C.unarmed;

  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '10px 8px 10px 12px', borderRadius: 10, marginBottom: 8,
      background: '#fff',
      border: `1px solid ${rgba(aColor, 0.3)}`,
      boxShadow: `0 1px 4px ${rgba(aColor, 0.08)}`,
      animation: 'fadeIn .15s ease',
    }}>
      {/* Left accent bar */}
      <div style={{
        width: 3, height: 40, borderRadius: 2, flexShrink: 0,
        background: aColor,
      }} />

      <Avatar name={name} color={rColor} size={36} />

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
          <span style={{
            color: C.dark, fontWeight: 700, fontSize: 13, flex: 1,
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>{name || '—'}</span>
          <ArmedChip isArmed={armed} />
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '2px 8px' }}>
          {rank && (
            <span style={{
              padding: '1px 5px', borderRadius: 4, fontSize: 9, fontWeight: 700,
              color: rColor, background: rgba(rColor, 0.1), border: `1px solid ${rgba(rColor, 0.3)}`,
            }}>{rank}</span>
          )}
          {pno && (
            <span style={{ color: C.subtle, fontSize: 10 }}>🪪 {pno}</span>
          )}
          {thana && (
            <span style={{
              color: C.subtle, fontSize: 10,
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 120,
            }}>🚔 {thana}</span>
          )}
        </div>
      </div>

      <button
        onClick={isLocked ? undefined : onRemove}
        className={isLocked ? '' : 'remove-btn'}
        title={isLocked ? 'Locked' : 'ड्यूटी हटाएं'}
        style={{
          width: 32, height: 32, borderRadius: 8, flexShrink: 0,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: isLocked ? rgba(C.subtle, 0.06) : rgba(C.error, 0.08),
          border: `1px solid ${isLocked ? rgba(C.subtle, 0.2) : rgba(C.error, 0.25)}`,
          cursor: isLocked ? 'not-allowed' : 'pointer',
          color: isLocked ? C.subtle : C.error,
          fontSize: 14, transition: 'background .15s',
        }}>
        {isLocked ? '🔒' : '✕'}
      </button>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   STAFF PICKER ROW
───────────────────────────────────────────────────────────────────────────── */
function StaffPickerRow({ staff, selected, onToggle }) {
  const armed  = isArmedVal(staff);
  const rank   = staff.rank || staff.user_rank || '';
  const rColor = rankColor(rank);

  return (
    <div
      onClick={onToggle}
      className="staff-row"
      style={{
        display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer',
        padding: '9px 14px',
        background: selected ? rgba(C.primary, 0.07) : 'transparent',
        borderBottom: `1px solid ${rgba(C.border, 0.25)}`,
      }}>
      {/* Checkbox circle */}
      <div style={{
        width: 26, height: 26, borderRadius: '50%', flexShrink: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: selected ? C.primary : C.surface,
        border: `1.5px solid ${selected ? C.primary : C.border}`,
        transition: 'all .15s', color: '#fff', fontSize: 13, fontWeight: 700,
      }}>{selected ? '✓' : ''}</div>

      <Avatar name={staff.name} color={rColor} size={34} />

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 2 }}>
          <span style={{
            color: selected ? C.primary : C.dark, fontSize: 13, fontWeight: 600, flex: 1,
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>{staff.name}</span>
          <ArmedChip isArmed={armed} />
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '2px 8px' }}>
          {rank && (
            <span style={{
              padding: '1px 5px', borderRadius: 4, fontSize: 9, fontWeight: 700,
              color: rColor, background: rgba(rColor, 0.1), border: `1px solid ${rgba(rColor, 0.3)}`,
            }}>{rank}</span>
          )}
          {staff.pno && <span style={{ color: C.subtle, fontSize: 10 }}>PNO: {staff.pno}</span>}
          {staff.thana && (
            <span style={{
              color: C.subtle, fontSize: 10,
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 140,
            }}>• {staff.thana}</span>
          )}
        </div>
      </div>
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   DUTIES DIALOG
───────────────────────────────────────────────────────────────────────────── */
function DutiesDialog({ center, onClose, onOpenAssign, onDutyRemoved }) {
  const [duties, setDuties]           = useState([]);
  const [total, setTotal]             = useState(0);
  const [loading, setLoading]         = useState(false);
  const [hasMore, setHasMore]         = useState(true);
  const [armedFilter, setArmedFilter] = useState('all');
  const [toast, setToast]             = useState(null);
  const pageRef    = useRef(1);
  const loadingRef = useRef(false);
  const scrollRef  = useRef(null);

  const showToast = (msg, error = false) => {
    setToast({ msg, error });
    setTimeout(() => setToast(null), 2500);
  };

  const load = useCallback(async (reset = false) => {
    if (loadingRef.current) return;
    const currentPage = reset ? 1 : pageRef.current;
    if (!reset && !hasMore) return;
    loadingRef.current = true;
    setLoading(true);
    try {
      const res = await adminApi.getDuties({ center_id: center.id, page: currentPage, limit: DUTIES_LIMIT });
      const wrapper = res?.data || {};
      const items   = wrapper.data || [];
      const tot     = (wrapper.total) || 0;
      const pages   = (wrapper.totalPages) || 1;
      setDuties(prev => reset ? items : [...prev, ...items]);
      setTotal(tot);
      setHasMore(currentPage < pages);
      pageRef.current = reset ? 2 : currentPage + 1;
    } catch (e) { /* silent */ }
    finally { loadingRef.current = false; setLoading(false); }
  }, [center.id, hasMore]);

  useEffect(() => { load(true); }, [center.id]);

  const onScroll = e => {
    const el = e.target;
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 150 && !loading && hasMore) load();
  };

  const removeDuty = async d => {
    try {
      await adminApi.removeAssignment(d.id);
      onDutyRemoved();
      load(true);
      showToast('ड्यूटी हटा दी गई');
    } catch (e) {
      showToast(`त्रुटि: ${e.message}`, true);
    }
  };

  const type    = center.centerType || 'C';
  const tColor  = typeColor(type);
  const bc      = center.boothCount || 1;
  const rule    = center.boothRule;
  const isLocked = center.isLocked === true || center.is_locked === 1;

  const armedCount   = duties.filter(d => isArmedVal(d)).length;
  const unarmedCount = duties.length - armedCount;
  const filtered = duties.filter(d => {
    if (armedFilter === 'all') return true;
    const ia = isArmedVal(d);
    return armedFilter === 'armed' ? ia : !ia;
  });

  return (
    <Overlay onClose={onClose}>
      <div style={{
        background: C.bg, borderRadius: 16, width: '100%', maxWidth: 520,
        display: 'flex', flexDirection: 'column',
        maxHeight: '88vh', overflow: 'hidden',
        border: `1.2px solid ${C.border}`,
        boxShadow: `0 8px 40px ${rgba(C.primary, 0.2)}`,
        animation: 'scaleIn .2s ease',
      }}>
        <DialogHeader title={center.name} icon="📍" onClose={onClose} />

        {/* Meta section */}
        <div style={{ padding: '12px 16px 0', overflowY: 'auto' }}>
          {/* Type + booth count + sensitivity label + total badge */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8, flexWrap: 'wrap' }}>
            <TypeBadge type={type} />
            <div style={{
              display: 'flex', alignItems: 'center', gap: 4,
              padding: '2px 10px', borderRadius: 8,
              background: rgba(tColor, 0.12), border: `1px solid ${rgba(tColor, 0.4)}`,
            }}>
              <span style={{ fontSize: 11 }}>🗳</span>
              <span style={{ color: tColor, fontSize: 12, fontWeight: 800 }}>{bc} बूथ</span>
            </div>
            <span style={{ color: C.subtle, fontSize: 12, fontWeight: 600, flex: 1 }}>
              {CT_LABEL[type] || type}
            </span>
            <Pill label={`${total} स्टाफ`} color={total > 0 ? C.success : C.subtle} />
          </div>

          {/* Location chips */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 10px', marginBottom: 8 }}>
            <InfoChip icon="🚔" text={center.thana} />
            <InfoChip icon="🏛" text={center.gpName} />
            <InfoChip icon="🗺" text={`सेक्टर: ${center.sectorName}`} />
            <InfoChip icon="🔲" text={`जोन: ${center.zoneName}`} />
            <InfoChip icon="🌐" text={`SZ: ${center.superZoneName}`} />
            {center.blockName && <InfoChip icon="🏙" text={`ब्लॉक: ${center.blockName}`} />}
            {center.busNo     && <InfoChip icon="🚌" text={`बस: ${center.busNo}`} />}
          </div>

          {/* Inline rule preview */}
          {rule && (
            <div style={{ marginBottom: 10 }}>
              <InlineRulePreview rule={rule} tColor={tColor} />
            </div>
          )}

          <ArmedFilterBar
            current={armedFilter} totalCount={duties.length}
            armedCount={armedCount} unarmedCount={unarmedCount}
            onChange={setArmedFilter}
          />
          <div style={{ height: 10 }} />
        </div>

        <div style={{ height: 1, background: C.border }} />

        {/* Duties list */}
        <div
          className="scroll-list"
          style={{ flex: 1, overflowY: 'auto', padding: '10px 14px' }}
          onScroll={onScroll}
          ref={scrollRef}>
          {loading && duties.length === 0 ? (
            <div style={{ display: 'flex', justifyContent: 'center', padding: 40 }}>
              <Spinner />
            </div>
          ) : filtered.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '40px 20px', color: C.subtle }}>
              <div style={{ fontSize: 40, marginBottom: 10, opacity: .5 }}>👥</div>
              <div style={{ fontSize: 13 }}>
                {duties.length === 0 ? 'इस बूथ पर कोई स्टाफ नहीं'
                  : armedFilter === 'armed' ? 'कोई सशस्त्र स्टाफ नहीं'
                  : 'कोई निःशस्त्र स्टाफ नहीं'}
              </div>
            </div>
          ) : (
            <>
              {filtered.map(d => (
                <DutyCard key={d.id} duty={d} isLocked={isLocked} onRemove={() => removeDuty(d)} />
              ))}
              {hasMore && (
                <div style={{ display: 'flex', justifyContent: 'center', padding: 12 }}>
                  <Spinner size={18} />
                </div>
              )}
            </>
          )}
        </div>

        {/* Footer */}
        <div style={{
          padding: 14, borderTop: `1px solid ${C.border}`,
          display: 'flex', gap: 12,
        }}>
          <button onClick={onClose} className="btn-outline" style={outlineBtnStyle}>बंद करें</button>
          <button
            className="btn-primary"
            disabled={isLocked}
            onClick={() => { onClose(); onOpenAssign(); }}
            style={{
              ...primaryBtnStyle, flex: 1,
              opacity: isLocked ? 0.5 : 1,
              cursor: isLocked ? 'not-allowed' : 'pointer',
            }}>
            ➕ स्टाफ जोड़ें
          </button>
        </div>

        {toast && <Toast msg={toast.msg} error={toast.error} />}
      </div>
    </Overlay>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   ASSIGN DIALOG
───────────────────────────────────────────────────────────────────────────── */
function AssignDialog({ center, onClose, onAssigned }) {
  const [staff, setStaff]             = useState([]);
  const [staffTotal, setStaffTotal]   = useState(0);
  const [staffLoading, setStaffLoading] = useState(false);
  const [staffHasMore, setStaffHasMore] = useState(true);
  const [staffQ, setStaffQ]           = useState('');
  const [selected, setSelected]       = useState(new Set());
  const [busNo, setBusNo]             = useState(center.busNo || '');
  const [saving, setSaving]           = useState(false);
  const [armedFilter, setArmedFilter] = useState('all');
  const [toast, setToast]             = useState(null);

  const pageRef    = useRef(1);
  const searchRef  = useRef('');
  const loadingRef = useRef(false);
  const debounce   = useRef(null);

  const showToast = (msg, error = false) => {
    setToast({ msg, error });
    setTimeout(() => setToast(null), 2500);
  };

  const loadStaff = useCallback(async (reset = false, q = searchRef.current) => {
    if (loadingRef.current) return;
    const currentPage = reset ? 1 : pageRef.current;
    loadingRef.current = true;
    setStaffLoading(true);
    try {
      const res = await adminApi.getStaff({ assigned: 'no', page: currentPage, limit: STAFF_LIMIT, q });
      const wrapper = res?.data || {};
      const items   = wrapper.data || [];
      const tot     = (wrapper.total) || 0;
      const pages   = (wrapper.totalPages) || 1;
      setStaff(prev => reset ? items : [...prev, ...items]);
      setStaffTotal(tot);
      setStaffHasMore(currentPage < pages);
      pageRef.current = reset ? 2 : currentPage + 1;
    } catch (e) { /* silent */ }
    finally { loadingRef.current = false; setStaffLoading(false); }
  }, []);

  useEffect(() => { loadStaff(true, ''); }, []);

  const onSearchChange = val => {
    setStaffQ(val);
    searchRef.current = val;
    clearTimeout(debounce.current);
    debounce.current = setTimeout(() => loadStaff(true, val), 300);
  };

  const onScroll = e => {
    const el = e.target;
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 150 && !staffLoading && staffHasMore) {
      loadStaff(false, searchRef.current);
    }
  };

  const toggleSelect = id => {
    setSelected(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const assign = async () => {
    if (!selected.size || saving) return;
    setSaving(true);
    try {
      const ids = [...selected];
      if (ids.length === 1) {
        await adminApi.assignDuty({ staffId: ids[0], centerId: center.id, busNo, mode: 'manual' });
      } else {
        await apiClient.post('/admin/staff/bulk-assign', { staffIds: ids, centerId: center.id, busNo });
      }
      onAssigned();
      onClose();
    } catch (e) {
      showToast(`त्रुटि: ${e.message}`, true);
      setSaving(false);
    }
  };

  const type = center.centerType || 'C';
  const bc   = center.boothCount || 1;

  const armedCount   = staff.filter(s => isArmedVal(s)).length;
  const unarmedCount = staff.length - armedCount;
  const filteredStaff = staff.filter(s => {
    if (armedFilter === 'all') return true;
    const ia = isArmedVal(s);
    return armedFilter === 'armed' ? ia : !ia;
  });

  return (
    <Overlay onClose={onClose}>
      <div style={{
        background: C.bg, borderRadius: 16, width: '100%', maxWidth: 540,
        display: 'flex', flexDirection: 'column',
        maxHeight: '90vh', overflow: 'hidden',
        border: `1.2px solid ${C.border}`,
        boxShadow: `0 8px 40px ${rgba(C.primary, 0.2)}`,
        animation: 'scaleIn .2s ease',
      }}>
        <DialogHeader title="स्टाफ असाइन करें" icon="➕" onClose={onClose} />

        {/* Center info strip */}
        <div style={{ padding: '10px 16px', background: rgba(C.surface, 0.6), flexShrink: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <TypeBadge type={type} />
            {/* Booth count chip */}
            <div style={{
              display: 'flex', alignItems: 'center', gap: 3,
              padding: '2px 8px', borderRadius: 6,
              background: rgba(typeColor(type), 0.12),
              border: `1px solid ${rgba(typeColor(type), 0.3)}`,
            }}>
              <span style={{ fontSize: 11 }}>🗳</span>
              <span style={{ color: typeColor(type), fontSize: 11, fontWeight: 700 }}>{bc} बूथ</span>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{
                color: C.dark, fontWeight: 700, fontSize: 13,
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
              }}>{center.name}</div>
              <div style={{
                color: C.subtle, fontSize: 11,
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
              }}>{[center.thana, center.gpName, center.sectorName].filter(Boolean).join('  •  ')}</div>
            </div>
            {selected.size > 0 && <Pill label={`${selected.size} चुने`} color={C.primary} />}
          </div>
        </div>

        <div style={{ height: 1, background: C.border }} />

        {/* Search + filter */}
        <div style={{ padding: '10px 14px 0', flexShrink: 0 }}>
          <SearchInput
            value={staffQ}
            onChange={onSearchChange}
            placeholder={`नाम, PNO, थाना से खोजें... (${staffTotal} उपलब्ध)`}
          />
          <div style={{ height: 10 }} />
          <ArmedFilterBar
            current={armedFilter} totalCount={staff.length}
            armedCount={armedCount} unarmedCount={unarmedCount}
            onChange={v => { setArmedFilter(v); setSelected(new Set()); }}
          />
          <div style={{ height: 8 }} />
        </div>

        {/* Staff list */}
        <div
          className="scroll-list"
          style={{ flex: 1, overflowY: 'auto', borderTop: `1px solid ${rgba(C.border, 0.3)}` }}
          onScroll={onScroll}>
          {staffLoading && staff.length === 0 ? (
            <div style={{ display: 'flex', justifyContent: 'center', padding: 40 }}>
              <Spinner />
            </div>
          ) : filteredStaff.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '40px 20px', color: C.subtle, fontSize: 13 }}>
              <div style={{ fontSize: 36, marginBottom: 8, opacity: .4 }}>👥</div>
              {staff.length === 0 ? 'सभी स्टाफ पहले से असाइन हैं'
                : staffQ ? `"${staffQ}" नहीं मिला`
                : armedFilter === 'armed' ? 'कोई सशस्त्र स्टाफ उपलब्ध नहीं'
                : 'कोई निःशस्त्र स्टाफ उपलब्ध नहीं'}
            </div>
          ) : (
            <>
              {filteredStaff.map(s => (
                <StaffPickerRow
                  key={s.id} staff={s}
                  selected={selected.has(s.id)}
                  onToggle={() => toggleSelect(s.id)}
                />
              ))}
              {staffHasMore && (
                <div style={{ display: 'flex', justifyContent: 'center', padding: 10 }}>
                  <Spinner size={16} />
                </div>
              )}
            </>
          )}
        </div>

        {/* Footer */}
        <div style={{ padding: '10px 14px 14px', borderTop: `1px solid ${C.border}`, flexShrink: 0 }}>
          {/* Bus number */}
          <div style={{ position: 'relative', marginBottom: 10 }}>
            <span style={{
              position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)',
              fontSize: 15, pointerEvents: 'none',
            }}>🚌</span>
            <input
              value={busNo}
              onChange={e => setBusNo(e.target.value)}
              placeholder="बस संख्या (वैकल्पिक)"
              style={{
                width: '100%', boxSizing: 'border-box',
                background: '#fff', border: `1.5px solid ${C.border}`, borderRadius: 10,
                padding: '9px 12px 9px 36px', color: C.dark, fontSize: 13,
                outline: 'none', fontFamily: 'Mukta, sans-serif',
              }}
              onFocus={e => e.target.style.borderColor = C.primary}
              onBlur={e => e.target.style.borderColor = C.border}
            />
          </div>

          <div style={{ display: 'flex', gap: 12 }}>
            <button onClick={onClose} className="btn-outline" style={outlineBtnStyle}>रद्द</button>
            {selected.size > 0 && (
              <button
                onClick={assign}
                disabled={saving}
                className="btn-primary"
                style={{ ...primaryBtnStyle, flex: 1 }}>
                {saving
                  ? <Spinner size={16} color="#fff" />
                  : selected.size === 1 ? 'असाइन करें' : `${selected.size} असाइन करें`}
              </button>
            )}
          </div>
        </div>

        {toast && <Toast msg={toast.msg} error={toast.error} />}
      </div>
    </Overlay>
  );
}

/* ─────────────────────────────────────────────────────────────────────────────
   SHARED BUTTON STYLES
───────────────────────────────────────────────────────────────────────────── */
const primaryBtnStyle = {
  display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
  padding: '11px 18px', borderRadius: 10, fontWeight: 700, fontSize: 13,
  color: '#fff', background: C.primary, border: 'none', cursor: 'pointer',
  fontFamily: 'Mukta, sans-serif',
};

const outlineBtnStyle = {
  display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
  padding: '11px 18px', borderRadius: 10, fontWeight: 600, fontSize: 13,
  color: C.subtle, background: 'transparent',
  border: `1px solid ${C.border}`, cursor: 'pointer', flex: 1,
  fontFamily: 'Mukta, sans-serif',
};

/* ─────────────────────────────────────────────────────────────────────────────
   MAIN — BoothPage
───────────────────────────────────────────────────────────────────────────── */
export default function BoothPage() {
  const [centers, setCenters]       = useState([]);
  const [total, setTotal]           = useState(0);
  const [loading, setLoading]       = useState(false);
  const [hasMore, setHasMore]       = useState(true);
  const [q, setQ]                   = useState('');
  const [dutiesCenter, setDutiesCenter] = useState(null);
  const [assignCenter, setAssignCenter] = useState(null);
  const [toast, setToast]           = useState(null);

  const pageRef    = useRef(1);
  const qRef       = useRef('');
  const loadingRef = useRef(false);
  const hasMoreRef = useRef(true);
  const debounce   = useRef(null);

  const showToast = (msg, error = false) => {
    setToast({ msg, error });
    setTimeout(() => setToast(null), 2500);
  };

  const loadCenters = useCallback(async (reset = false) => {
    if (loadingRef.current) return;
    const currentPage = reset ? 1 : pageRef.current;
    if (!reset && !hasMoreRef.current) return;
    loadingRef.current = true;
    setLoading(true);
    try {
      const res = await adminApi.getCenters({ page: currentPage, limit: PAGE_LIMIT, q: qRef.current });
      const wrapper = res?.data || {};
      const items   = wrapper.data || [];
      const tot     = (wrapper.total) || 0;
      const pages   = (wrapper.totalPages) || 1;
      const more    = currentPage < pages;
      setCenters(prev => reset ? items : [...prev, ...items]);
      setTotal(tot);
      setHasMore(more);
      hasMoreRef.current  = more;
      pageRef.current     = reset ? 2 : currentPage + 1;
    } catch (e) {
      showToast(`लोड विफल: ${e.message}`, true);
    } finally {
      loadingRef.current = false;
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadCenters(true); }, []);

  const onSearchChange = val => {
    setQ(val);
    qRef.current = val;
    clearTimeout(debounce.current);
    debounce.current = setTimeout(() => {
      pageRef.current = 1;
      hasMoreRef.current = true;
      setCenters([]);
      setHasMore(true);
      loadCenters(true);
    }, 350);
  };

  const refresh = () => {
    pageRef.current = 1;
    hasMoreRef.current = true;
    setCenters([]);
    setHasMore(true);
    loadCenters(true);
  };

  const onScroll = e => {
    const el = e.target;
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 300 && !loading && hasMore) {
      loadCenters(false);
    }
  };

  return (
    <>
      {/* Inject global CSS */}
      <style>{GLOBAL_CSS}</style>

      <div style={{
        display: 'flex', flexDirection: 'column', height: '100%',
        background: C.bg,
        fontFamily: "'Mukta', 'Tiro Devanagari Hindi', Georgia, serif",
      }}>

        {/* ── Search bar ── */}
        <div style={{ background: C.surface, padding: '10px 16px', flexShrink: 0 }}>
          <SearchInput value={q} onChange={onSearchChange} placeholder="नाम, थाना, GP, सेक्टर, जोन से खोजें..." />
        </div>

        {/* ── Stats strip ── */}
        <div style={{
          background: C.bg, padding: '7px 16px',
          display: 'flex', alignItems: 'center', gap: 10,
          borderBottom: `1px solid ${rgba(C.border, 0.35)}`,
          flexShrink: 0,
        }}>
          <Pill label={`${total} बूथ`} color={C.primary} />
          <div style={{ flex: 1 }} />
          {loading && centers.length > 0 && <Spinner size={14} />}
          <button
            onClick={refresh}
            title="ताज़ा करें"
            style={{
              background: 'none', border: 'none', cursor: 'pointer',
              color: C.subtle, fontSize: 16, padding: 4, lineHeight: 1,
              borderRadius: 6, transition: 'color .15s',
            }}
            onMouseEnter={e => e.target.style.color = C.primary}
            onMouseLeave={e => e.target.style.color = C.subtle}>
            ↻
          </button>
        </div>

        {/* ── List ── */}
        <div
          className="scroll-list"
          onScroll={onScroll}
          style={{ flex: 1, overflowY: 'auto', padding: '10px 12px 80px' }}>
          {centers.length === 0 && loading ? (
            <div style={{ display: 'flex', justifyContent: 'center', padding: 60 }}>
              <Spinner size={32} />
            </div>
          ) : centers.length === 0 ? (
            <div style={{ textAlign: 'center', padding: 60, color: C.subtle }}>
              <div style={{ fontSize: 48, marginBottom: 12, opacity: .4 }}>📍</div>
              <div style={{ fontSize: 14 }}>
                {q ? `"${q}" के लिए कोई बूथ नहीं` : 'कोई बूथ नहीं मिला'}
              </div>
            </div>
          ) : (
            <>
              {centers.map(c => (
                <CenterCard
                  key={c.id}
                  center={c}
                  onClick={() => setDutiesCenter(c)}
                />
              ))}
              {hasMore && loading && (
                <div style={{ display: 'flex', justifyContent: 'center', padding: 16 }}>
                  <Spinner size={22} />
                </div>
              )}
            </>
          )}
        </div>
      </div>

      {/* ── Duties Dialog ── */}
      {dutiesCenter && (
        <DutiesDialog
          center={dutiesCenter}
          onClose={() => setDutiesCenter(null)}
          onOpenAssign={() => setAssignCenter(dutiesCenter)}
          onDutyRemoved={() => loadCenters(true)}
        />
      )}

      {/* ── Assign Dialog ── */}
      {assignCenter && (
        <AssignDialog
          center={assignCenter}
          onClose={() => setAssignCenter(null)}
          onAssigned={() => {
            setAssignCenter(null);
            loadCenters(true);
          }}
        />
      )}

      {toast && <Toast msg={toast.msg} error={toast.error} />}
    </>
  );
}