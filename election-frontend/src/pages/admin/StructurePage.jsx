import { useState, useEffect, useRef, useCallback } from 'react';
import {
  Layers, Grid, LayoutGrid, Landmark, MapPin, ChevronRight,
  Plus, Pencil, Trash2, Search, X, Check, AlertTriangle, Info,
  User, Badge, Phone, ShieldCheck, DoorOpen, ListChecks,
  ArrowDownUp, PersonStanding, CheckCircle2, XCircle, Ban
} from 'lucide-react';
import { adminApi } from '../../api/endpoints';
import apiClient from '../../api/client';          // ← axios instance
import { RANKS, debounce,UP_DISTRICTS  } from '../../utils/helpers';
import toast from 'react-hot-toast';
import { useAuthStore } from '../../store/authStore';

// ── Palette ──────────────────────────────────────────────────────────────────
const C = {
  bg: '#FDF6E3', surface: '#F5E6C8', primary: '#8B6914', accent: '#B8860B',
  dark: '#4A3000', subtle: '#AA8844', border: '#D4A843',
  error: '#C0392B', success: '#2D6A1E', info: '#1A5276',
};

// ── Step definitions ─────────────────────────────────────────────────────────
const STEPS = [
  { id: 0, label: 'Super Zone', Icon: Layers, color: '#6A1B9A' },
  { id: 1, label: 'Zone', Icon: Grid, color: '#1565C0' },
  { id: 2, label: 'Sector', Icon: LayoutGrid, color: '#2E7D32' },
  { id: 3, label: 'GP', Icon: Landmark, color: '#6D4C41' },
  { id: 4, label: 'Center', Icon: MapPin, color: '#C62828' },
];

const RANK_COLORS = {
  SP: '#6A1B9A', ASP: '#1565C0', DSP: '#1A5276', Inspector: '#2E7D32',
  SI: '#558B2F', ASI: '#8B6914', 'Head Constable': '#B8860B', Constable: '#6D4C41',
};

const RANK_HIERARCHY = ['SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable'];

const LEVEL_RANKS = {
  0: ['SP', 'ASP', 'DSP'],
  1: ['Inspector', 'SI'],
  2: ['ASI', 'Head Constable', 'Constable'],
};

const LEVEL_OFFICER_TITLE = {
  0: 'क्षेत्र अधिकारी (Kshetra Adhikari)',
  1: 'निरीक्षक (Nirakshak)',
  2: 'उप-निरीक्षक / पुलिस अधिकारी',
};

const CENTER_TYPES = ['A++', 'A', 'B', 'C'];
const TYPE_COLORS = { 'A++': '#6A1B9A', A: '#C62828', B: '#E65100', C: '#1A5276' };
const TYPE_LABELS = { 'A++': 'अति-अति', A: 'अति', B: 'संवेदनशील', C: 'सामान्य' };

// ── Tiny helpers ─────────────────────────────────────────────────────────────
const initials = (name = '') =>
  name.trim().split(' ').filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase() || '?';

function hex(color, alpha) {
  const n = parseInt(color.slice(1), 16);
  const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  return `rgba(${r},${g},${b},${alpha})`;
}

// ── Shared UI atoms ──────────────────────────────────────────────────────────
function Tag({ icon: Icon, text }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: C.subtle, fontSize: 11 }}>
      {Icon && <Icon size={10} />} {text}
    </span>
  );
}

function IconBtn({ icon: Icon, color, onClick, title }) {
  return (
    <button title={title} onClick={onClick} style={{
      width: 32, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: hex(color, 0.08), border: `1px solid ${hex(color, 0.25)}`,
      borderRadius: 8, cursor: 'pointer', flexShrink: 0,
    }}>
      <Icon size={14} color={color} />
    </button>
  );
}

function Spinner({ size = 18, color = 'white' }) {
  return (
    <div style={{
      width: size, height: size, border: `2px solid ${hex('#ffffff', 0.3)}`,
      borderTop: `2px solid ${color}`, borderRadius: '50%',
      animation: 'spin 0.7s linear infinite',
    }} />
  );
}

function EmptyState({ label, Icon: I, color }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '60px 20px', gap: 12 }}>
      <div style={{ padding: 20, background: hex(color, 0.08), borderRadius: '50%' }}>
        <I size={48} color={hex(color, 0.5)} />
      </div>
      <p style={{ color: C.dark, fontWeight: 700, fontSize: 14 }}>कोई {label} नहीं</p>
      <p style={{ color: C.subtle, fontSize: 12 }}>ऊपर जोड़ें बटन दबाएं</p>
    </div>
  );
}

function FieldInput({ label, icon: Icon, color, value, onChange, type = 'text', placeholder }) {
  const [focused, setFocused] = useState(false);
  return (
    <div style={{ marginBottom: 10 }}>
      <div style={{ position: 'relative' }}>
        <div style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none' }}>
          {Icon && <Icon size={16} color={color} />}
        </div>
        <input
          type={type} value={value} placeholder={placeholder || label}
          onChange={e => onChange(e.target.value)}
          onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
          style={{
            width: '100%', padding: '10px 12px 10px 34px',
            background: 'white', border: `1.5px solid ${focused ? color : C.border}`,
            borderRadius: 10, fontSize: 13, color: C.dark, outline: 'none',
            boxShadow: focused ? `0 0 0 3px ${hex(color, 0.12)}` : 'none',
            transition: 'all 0.2s', fontFamily: 'inherit',
          }}
        />
        {label && (
          <label style={{
            position: 'absolute', left: 34, top: focused || value ? -7 : 10,
            fontSize: focused || value ? 10 : 12, color: focused ? color : C.subtle,
            background: 'white', padding: '0 3px', transition: 'all 0.15s', pointerEvents: 'none',
            fontWeight: 600,
          }}>
            {label}
          </label>
        )}
      </div>
    </div>
  );
}

// ── Modal wrapper ────────────────────────────────────────────────────────────
function Modal({ open, onClose, children, maxWidth = 520, maxHeight = '90vh' }) {
  if (!open) return null;
  return (
    <div style={{
      position: 'fixed', inset: 0, zIndex: 1000,
      background: 'rgba(74,48,0,0.45)', backdropFilter: 'blur(4px)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16,
    }} onClick={e => { if (e.target === e.currentTarget) onClose?.(); }}>
      <div style={{
        background: C.bg, borderRadius: 16, border: `1.2px solid ${C.border}`,
        boxShadow: '0 20px 60px rgba(0,0,0,0.25)',
        width: '100%', maxWidth, maxHeight, overflow: 'hidden',
        display: 'flex', flexDirection: 'column', animation: 'slideUp 0.22s ease-out',
      }}>
        {children}
      </div>
    </div>
  );
}

function ModalHeader({ title, subtitle, Icon: I, color, onClose }) {
  return (
    <div style={{ background: C.dark, padding: '13px 16px', display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0 }}>
      {I && (
        <div style={{ padding: 6, background: hex(color, 0.25), borderRadius: 7 }}>
          <I size={16} color={color} />
        </div>
      )}
      <div style={{ flex: 1 }}>
        <p style={{ color: 'white', fontWeight: 700, fontSize: 15 }}>{title}</p>
        {subtitle && <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 11 }}>{subtitle}</p>}
      </div>
      {onClose && (
        <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'rgba(255,255,255,0.6)', padding: 4 }}>
          <X size={20} />
        </button>
      )}
    </div>
  );
}

// ── Confirm dialog ────────────────────────────────────────────────────────────
function ConfirmDialog({ open, message, onConfirm, onCancel }) {
  if (!open) return null;
  return (
    <Modal open onClose={onCancel} maxWidth={380}>
      <ModalHeader title="Confirm Delete" Icon={AlertTriangle} color={C.error} onClose={onCancel} />
      <div style={{ padding: 20 }}>
        <p style={{ color: C.dark, fontSize: 13, marginBottom: 20 }}>{message}</p>
        <div style={{ display: 'flex', gap: 10 }}>
          <button onClick={onCancel} style={{
            flex: 1, padding: '10px 0', border: `1px solid ${C.border}`, borderRadius: 10,
            background: 'transparent', color: C.subtle, cursor: 'pointer', fontSize: 13, fontWeight: 600,
          }}>रद्द</button>
          <button onClick={onConfirm} style={{
            flex: 1, padding: '10px 0', border: 'none', borderRadius: 10,
            background: C.error, color: 'white', cursor: 'pointer', fontSize: 13, fontWeight: 700,
          }}>हटाएं</button>
        </div>
      </div>
    </Modal>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// STAFF PICKER SHEET (bottom sheet style modal)
// ══════════════════════════════════════════════════════════════════════════════
function StaffPickerSheet({ allowedRanks, color, onPick, onClose }) {
  const [staff, setStaff] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [q, setQ] = useState('');
  const [rankFilter, setRankFilter] = useState(allowedRanks[0] || '');
  const scrollRef = useRef(null);
  const pageRef = useRef(1);
  const hasMoreRef = useRef(true);

  const load = useCallback(async (reset = false, qVal = q, rf = rankFilter) => {
    if (!reset && !hasMoreRef.current) return;
    if (reset) {
      pageRef.current = 1;
      hasMoreRef.current = true;
      setStaff([]);
      setLoading(true);
    } else {
      setLoadingMore(true);
    }
    try {
      const params = { assigned: 'no', page: pageRef.current, limit: 20, q: qVal };
      if (rf) params.rank = rf;
      // adminApi.getStaff uses api.get('/admin/staff', { params })
      const res = await adminApi.getStaff(params);
      const w = res.data?.data || res.data || [];
      const pages = res.data?.totalPages || res.totalPages || 1;
      hasMoreRef.current = pageRef.current < pages;
      setHasMore(pageRef.current < pages);
      pageRef.current++;
      setStaff(prev => reset ? w : [...prev, ...w]);
    } catch (e) {
      toast.error(`Staff load error: ${e.message}`);
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, []);

  useEffect(() => { load(true, q, rankFilter); }, []);

  const debouncedSearch = useCallback(debounce((v, rf) => load(true, v, rf), 300), []);

  const handleScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 100) load(false, q, rankFilter);
  };

  return (
    <Modal open onClose={onClose} maxWidth={480} maxHeight="80vh">
      <div style={{ width: 40, height: 4, background: hex(C.border, 0.5), borderRadius: 2, margin: '10px auto 4px' }} />
      <div style={{ padding: '6px 16px 10px' }}>
        <p style={{ color: C.dark, fontWeight: 800, fontSize: 15, marginBottom: 10 }}>Staff से चुनें (अनसाइन)</p>
        {allowedRanks.length > 0 && (
          <div style={{ display: 'flex', gap: 6, overflowX: 'auto', paddingBottom: 6, marginBottom: 8 }}>
            {[{ label: 'सभी', value: '' }, ...allowedRanks.map(r => ({ label: r, value: r }))].map(({ label, value }) => {
              const sel = rankFilter === value;
              const rc = value ? (RANK_COLORS[value] || C.primary) : C.primary;
              return (
                <button key={value} onClick={() => { setRankFilter(value); load(true, q, value); }} style={{
                  padding: '5px 10px', borderRadius: 20, fontSize: 11, flexShrink: 0,
                  fontWeight: sel ? 700 : 500, cursor: 'pointer',
                  background: sel ? rc : 'white',
                  color: sel ? 'white' : C.dark,
                  border: `1px solid ${sel ? rc : hex(C.border, 0.5)}`,
                }}>
                  {label}
                </button>
              );
            })}
          </div>
        )}
        <div style={{ position: 'relative' }}>
          <Search size={16} color={C.subtle} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)' }} />
          <input
            value={q} placeholder="नाम, PNO खोजें..."
            onChange={e => { setQ(e.target.value); debouncedSearch(e.target.value, rankFilter); }}
            style={{
              width: '100%', padding: '9px 12px 9px 32px', background: 'white',
              border: `1.2px solid ${C.border}`, borderRadius: 10, fontSize: 13, color: C.dark,
              outline: 'none', fontFamily: 'inherit',
            }}
          />
        </div>
      </div>
      <div ref={scrollRef} onScroll={handleScroll} style={{ flex: 1, overflowY: 'auto', padding: '0 16px 20px' }}>
        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 40 }}><Spinner color={C.primary} /></div>
        ) : staff.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 40, color: C.subtle, fontSize: 13 }}>
            <User size={40} color={hex(C.subtle, 0.4)} style={{ marginBottom: 10 }} />
            <p>{rankFilter || 'कोई'} अनसाइन स्टाफ नहीं</p>
          </div>
        ) : (
          staff.map(s => {
            const rc = RANK_COLORS[s.rank] || C.primary;
            return (
              <div key={s.id} onClick={() => onPick(s)} style={{
                display: 'flex', alignItems: 'center', gap: 10, padding: '10px 0',
                borderBottom: `1px solid ${hex(C.border, 0.2)}`, cursor: 'pointer',
              }}>
                <div style={{
                  width: 40, height: 40, borderRadius: '50%', flexShrink: 0,
                  background: hex(rc, 0.12), border: `1px solid ${hex(rc, 0.3)}`,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 13, fontWeight: 900, color: rc,
                }}>
                  {initials(s.name)}
                </div>
                <div style={{ flex: 1 }}>
                  <p style={{ fontWeight: 700, fontSize: 13, color: C.dark }}>{s.name}</p>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    {s.pno && <span style={{ fontSize: 11, color: C.subtle }}>{s.pno}</span>}
                    <span style={{
                      padding: '1px 6px', borderRadius: 5, fontSize: 10, fontWeight: 700,
                      background: hex(rc, 0.1), color: rc, border: `1px solid ${hex(rc, 0.3)}`,
                    }}>{s.rank}</span>
                  </div>
                </div>
                <button style={{
                  padding: '5px 10px', background: color, color: 'white',
                  border: 'none', borderRadius: 8, fontSize: 11, fontWeight: 700, cursor: 'pointer',
                }}>चुनें</button>
              </div>
            );
          })
        )}
        {loadingMore && <div style={{ display: 'flex', justifyContent: 'center', padding: 12 }}><Spinner color={C.primary} size={16} /></div>}
      </div>
    </Modal>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// OFFICER CARD
// ══════════════════════════════════════════════════════════════════════════════
function OfficerCard({ index, officer, color, allowedRanks, canRemove, onChange, onRemove }) {
  const [expanded, setExpanded] = useState(true);
  const [showPicker, setShowPicker] = useState(false);

  const hasData = !!officer.name.trim();

  return (
    <div style={{
      marginBottom: 10, border: `1px solid ${hasData ? hex(color, 0.3) : hex(C.border, 0.4)}`,
      borderRadius: 10, background: hasData ? hex(color, 0.04) : 'white', overflow: 'hidden',
    }}>
      {/* Header row */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 10px 10px 12px', cursor: 'pointer' }}
        onClick={() => setExpanded(e => !e)}>
        <div style={{
          width: 28, height: 28, borderRadius: '50%', background: hex(color, 0.12),
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 12, fontWeight: 900, color, flexShrink: 0,
        }}>
          {index + 1}
        </div>
        <div style={{ flex: 1 }}>
          <p style={{ fontWeight: 700, fontSize: 13, color: hasData ? C.dark : C.subtle }}>
            {hasData ? officer.name : `अधिकारी ${index + 1}`}
          </p>
          {hasData && officer.rank && <p style={{ fontSize: 11, color }}>{officer.rank}</p>}
        </div>
        <button onClick={e => { e.stopPropagation(); setShowPicker(true); }} style={{
          padding: '4px 8px', background: hex(C.info, 0.08), border: `1px solid ${hex(C.info, 0.3)}`,
          borderRadius: 6, fontSize: 10, fontWeight: 700, color: C.info, cursor: 'pointer',
          display: 'flex', alignItems: 'center', gap: 3,
        }}>
          <Search size={11} /> Staff से चुनें
        </button>
        <span style={{ color: C.subtle, fontSize: 18 }}>{expanded ? '▲' : '▼'}</span>
        {canRemove && (
          <button onClick={e => { e.stopPropagation(); onRemove(); }} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2 }}>
            <XCircle size={18} color={C.error} />
          </button>
        )}
      </div>

      {/* Expanded fields */}
      {expanded && (
        <div style={{ padding: '0 12px 12px' }}>
          {allowedRanks.length > 0 && (
            <div style={{ marginBottom: 8 }}>
              <label style={{ fontSize: 11, color: C.subtle, fontWeight: 600, display: 'block', marginBottom: 4 }}>पद / Rank</label>
              <select value={officer.rank} onChange={e => onChange({ ...officer, rank: e.target.value })} style={{
                width: '100%', padding: '9px 12px 9px 12px', background: 'white',
                border: `1.2px solid ${C.border}`, borderRadius: 10, fontSize: 13, color: C.dark,
                outline: 'none', fontFamily: 'inherit', cursor: 'pointer',
              }}>
                <option value="">-- Rank चुनें --</option>
                {allowedRanks.map(r => <option key={r} value={r}>{r}</option>)}
              </select>
            </div>
          )}
          {[
            { field: 'name', label: 'पूरा नाम *', icon: User },
            { field: 'pno', label: 'PNO', icon: Badge },
            { field: 'mobile', label: 'मोबाइल', icon: Phone, type: 'tel' },
          ].map(({ field, label, icon, type = 'text' }) => (
            <FieldInput key={field} label={label} icon={icon} color={color} type={type}
              value={officer[field]} onChange={v => onChange({ ...officer, [field]: v })} />
          ))}
        </div>
      )}

      {showPicker && (
        <StaffPickerSheet allowedRanks={allowedRanks} color={color}
          onPick={s => { onChange({ ...officer, name: s.name, pno: s.pno || '', mobile: s.mobile || '', rank: s.rank || '', userId: s.id }); setShowPicker(false); }}
          onClose={() => setShowPicker(false)} />
      )}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// ITEM DIALOG (Super Zone / Zone / Sector / GP)
// ══════════════════════════════════════════════════════════════════════════════
function ItemDialog({ title, color, Icon: I, fields, officerTitle, officerRanks, existing, createUrl, updateUrlFn, onDone, onClose }) {
  const blankOfficer = () => ({ name: '', pno: '', mobile: '', rank: '', userId: null });
  const initOfficers = () => {
    if (existing?.officers?.length) return existing.officers.map(o => ({ name: o.name || '', pno: o.pno || '', mobile: o.mobile || '', rank: o.rank || '', userId: o.userId || null, id: o.id }));
    if (officerRanks.length) return [blankOfficer()];
    return [];
  };

  const [form, setForm] = useState(() => {
    const f = {};
    fields.forEach(fld => f[fld] = existing?.[fld] || '');
    return f;
  });
  const [officers, setOfficers] = useState(initOfficers);
  const [saving, setSaving] = useState(false);

  const fieldLabel = f => ({ name: 'नाम *', district: 'जिला', block: 'ब्लॉक', hqAddress: 'मुख्यालय / HQ Address', address: 'पता' }[f] || f);
  const fieldIcon = f => ({ name: Badge, district: Landmark, block: LayoutGrid, hqAddress: MapPin, address: MapPin }[f] || Badge);

  const save = async () => {
    if (!form.name?.trim()) { toast.error('नाम आवश्यक है'); return; }
    setSaving(true);
    try {
      const body = { ...form, officers: officers.filter(o => o.name.trim()).map(o => ({ ...o })) };
      if (existing) {
        // e.g. updateUrlFn(id) => '/admin/super-zones/5'  →  PUT /admin/super-zones/5
        await apiClient.put(updateUrlFn(existing.id), body);
      } else {
        // createUrl e.g. '/admin/super-zones'  →  POST /admin/super-zones
        await apiClient.post(createUrl, body);
      }
      onDone();
      onClose();
    } catch (e) { toast.error(`Error: ${e.message}`); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} maxWidth={520}>
      <ModalHeader title={title} Icon={I} color={color} onClose={onClose} />
      <div style={{ overflowY: 'auto', flex: 1, padding: 16 }}>
        {fields.map(f => {
          if (f === 'district') {
            return (
              <div key="district" style={{ marginBottom: 10 }}>
                <label style={{ fontSize: 11, color: C.subtle, fontWeight: 600, display: 'block', marginBottom: 4 }}>
                  जिला *
                </label>
                <select
                  value={form[f]}
                  onChange={e => setForm(p => ({ ...p, district: e.target.value }))}
                  style={{
                    width: '100%', padding: '10px 12px', background: 'white',
                    border: `1.5px solid ${color}`, borderRadius: 10,
                    fontSize: 13, color: form[f] ? C.dark : C.subtle,
                    outline: 'none', fontFamily: 'inherit', cursor: 'pointer',
                  }}
                >
                  <option value="">-- जिला चुनें --</option>
                  {UP_DISTRICTS.map(d => (
                    <option key={d} value={d}>{d}</option>
                  ))}
                </select>
              </div>
            );
          }
          return (
            <FieldInput key={f} label={fieldLabel(f)} icon={fieldIcon(f)} color={color}
              value={form[f]} onChange={v => setForm(p => ({ ...p, [f]: v }))} />
          );
        })}

        {officerRanks.length > 0 && (
          <>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10, marginTop: 6 }}>
              <div style={{ width: 3, height: 14, background: color, borderRadius: 2 }} />
              <p style={{ flex: 1, color, fontSize: 12, fontWeight: 800 }}>{officerTitle}</p>
              <button onClick={() => setOfficers(p => [...p, blankOfficer()])} style={{
                padding: '4px 8px', background: hex(color, 0.1), border: `1px solid ${hex(color, 0.3)}`,
                borderRadius: 7, fontSize: 11, fontWeight: 700, color, cursor: 'pointer',
                display: 'flex', alignItems: 'center', gap: 4,
              }}>
                <Plus size={12} /> जोड़ें
              </button>
            </div>
            {officers.map((o, i) => (
              <OfficerCard key={i} index={i} officer={o} color={color} allowedRanks={officerRanks}
                canRemove={officers.length > 1}
                onChange={updated => setOfficers(p => p.map((x, j) => j === i ? updated : x))}
                onRemove={() => setOfficers(p => p.filter((_, j) => j !== i))} />
            ))}
          </>
        )}
      </div>
      <div style={{ padding: '8px 16px 16px', display: 'flex', gap: 12 }}>
        <button onClick={onClose} style={{
          flex: 1, padding: '12px 0', border: `1px solid ${C.border}`, borderRadius: 10,
          background: 'transparent', color: C.subtle, cursor: 'pointer', fontSize: 13, fontWeight: 600,
        }}>रद्द</button>
        <button onClick={save} disabled={saving} style={{
          flex: 1, padding: '12px 0', border: 'none', borderRadius: 10,
          background: color, color: 'white', cursor: 'pointer', fontSize: 13, fontWeight: 700,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          opacity: saving ? 0.7 : 1,
        }}>
          {saving ? <Spinner /> : 'सेव करें'}
        </button>
      </div>
    </Modal>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MATDAN STHAL DIALOG
// ══════════════════════════════════════════════════════════════════════════════
function MatdanSthalDialog({ centerId, centerName, onClose }) {
  const [rooms, setRooms] = useState([]);
  const [loading, setLoading] = useState(true);
  const [roomNum, setRoomNum] = useState('');
  const [adding, setAdding] = useState(false);

  const loadRooms = async () => {
    setLoading(true);
    try {
      // GET /admin/centers/:id/rooms
      const res = await apiClient.get(`/admin/centers/${centerId}/rooms`);
      setRooms(Array.isArray(res.data) ? res.data : res.data?.data || []);
    } catch (_) { }
    finally { setLoading(false); }
  };

  useEffect(() => { loadRooms(); }, []);

  const addRoom = async () => {
    if (!roomNum.trim()) return;
    setAdding(true);
    try {
      // POST /admin/centers/:id/rooms
      await apiClient.post(`/admin/centers/${centerId}/rooms`, { roomNumber: roomNum.trim() });
      setRoomNum('');
      await loadRooms();
    } catch (e) { toast.error(`Error: ${e.message}`); }
    finally { setAdding(false); }
  };

  const deleteRoom = async (roomId) => {
    try {
      // DELETE /admin/rooms/:roomId
      await apiClient.delete(`/admin/rooms/${roomId}`);
      await loadRooms();
    } catch (e) { toast.error(`Error: ${e.message}`); }
  };

  return (
    <Modal open onClose={onClose} maxWidth={480}>
      <ModalHeader title="मतदान स्थल (Matdan Sthal)" subtitle={centerName} Icon={DoorOpen} color="#C62828" onClose={onClose} />
      <div style={{ padding: '12px 16px 0', overflowY: 'auto', flex: 1 }}>
        <div style={{ background: hex(C.info, 0.07), border: `1px solid ${hex(C.info, 0.2)}`, borderRadius: 8, padding: 10, marginBottom: 12, display: 'flex', gap: 8 }}>
          <Info size={14} color={C.info} style={{ flexShrink: 0, marginTop: 1 }} />
          <p style={{ fontSize: 11, color: C.info }}>प्रत्येक कमरा एक मतदान स्थल है। एक केंद्र में कितने कमरे हैं वो यहाँ दर्ज करें।</p>
        </div>
        <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
          <input value={roomNum} onChange={e => setRoomNum(e.target.value)} onKeyDown={e => e.key === 'Enter' && addRoom()}
            placeholder="कमरा नंबर / Room Number"
            style={{ flex: 1, padding: '10px 12px', background: 'white', border: `1.2px solid ${C.border}`, borderRadius: 10, fontSize: 13, color: C.dark, outline: 'none', fontFamily: 'inherit' }} />
          <button onClick={addRoom} disabled={adding} style={{
            padding: '10px 14px', background: C.primary, color: 'white', border: 'none', borderRadius: 10, cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            {adding ? <Spinner size={16} /> : <Plus size={18} />}
          </button>
        </div>
        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 30 }}><Spinner color={C.primary} /></div>
        ) : rooms.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 30 }}>
            <DoorOpen size={40} color={hex(C.subtle, 0.4)} />
            <p style={{ color: C.subtle, fontSize: 13, marginTop: 10 }}>कोई कमरा नहीं जोड़ा गया</p>
          </div>
        ) : (
          rooms.map((room, i) => (
            <div key={room.id} style={{
              display: 'flex', alignItems: 'center', gap: 12, padding: '10px 14px',
              background: 'white', border: `1px solid ${hex(C.border, 0.4)}`, borderRadius: 10, marginBottom: 8,
            }}>
              <div style={{ width: 32, height: 32, background: hex(C.primary, 0.1), borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, fontWeight: 800, color: C.primary }}>
                {i + 1}
              </div>
              <DoorOpen size={15} color={C.subtle} />
              <p style={{ flex: 1, fontWeight: 600, fontSize: 13, color: C.dark }}>कमरा: {room.roomNumber}</p>
              <button onClick={() => deleteRoom(room.id)} style={{
                width: 30, height: 30, background: hex(C.error, 0.08), border: `1px solid ${hex(C.error, 0.25)}`,
                borderRadius: 7, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Trash2 size={14} color={C.error} />
              </button>
            </div>
          ))
        )}
      </div>
      <div style={{ padding: '8px 16px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ padding: '8px 12px', background: hex(C.success, 0.08), border: `1px solid ${hex(C.success, 0.3)}`, borderRadius: 8, display: 'flex', alignItems: 'center', gap: 6 }}>
          <DoorOpen size={14} color={C.success} />
          <span style={{ color: C.success, fontWeight: 700, fontSize: 12 }}>कुल {rooms.length} कमरे</span>
        </div>
        <button onClick={onClose} style={{ padding: '9px 20px', border: `1px solid ${C.border}`, borderRadius: 10, background: 'transparent', color: C.subtle, cursor: 'pointer', fontSize: 13 }}>
          बंद करें
        </button>
      </div>
    </Modal>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// CUSTOM RANK RULES DIALOG
// ══════════════════════════════════════════════════════════════════════════════
function CustomRankRulesDialog({ centerId, centerName, centerType, existingRules, onConfirm, onClose }) {
  const color = TYPE_COLORS[centerType] || C.info;
  const [rules, setRules] = useState(() =>
    existingRules.length
      ? existingRules.map(r => ({ rank: r.rank || RANKS[RANKS.length - 1], count: r.count || 1 }))
      : [{ rank: RANKS[RANKS.length - 1], count: 1 }]
  );

  const confirm = () => { onConfirm(rules); onClose(); };

  return (
    <Modal open onClose={onClose} maxWidth={480}>
      <ModalHeader title="Custom Rank Rules" subtitle={centerName} Icon={ListChecks} color={color} onClose={onClose} />
      <div style={{ overflowY: 'auto', flex: 1, padding: 16 }}>
        <div style={{ background: hex(color, 0.07), border: `1px solid ${hex(color, 0.2)}`, borderRadius: 8, padding: 10, marginBottom: 14, display: 'flex', gap: 8 }}>
          <Info size={14} color={color} style={{ flexShrink: 0, marginTop: 1 }} />
          <p style={{ fontSize: 11, color }}>इस center के लिए custom rank और staff संख्या सेट करें। Auto-assign इसी के अनुसार काम करेगा।</p>
        </div>
        {rules.map((rule, i) => (
          <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: 10, background: 'white', border: `1px solid ${hex(C.border, 0.4)}`, borderRadius: 10, marginBottom: 10 }}>
            <div style={{ width: 26, height: 26, background: hex(color, 0.1), borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 11, fontWeight: 800, color, flexShrink: 0 }}>
              {i + 1}
            </div>
            <select value={rule.rank} onChange={e => setRules(p => p.map((r, j) => j === i ? { ...r, rank: e.target.value } : r))} style={{
              flex: 1, padding: '8px 10px', background: 'white', border: `1.2px solid ${C.border}`, borderRadius: 8, fontSize: 12, color: C.dark, outline: 'none', fontFamily: 'inherit',
            }}>
              {RANKS.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
            <input type="number" min="1" value={rule.count}
              onChange={e => { const n = parseInt(e.target.value); if (n > 0) setRules(p => p.map((r, j) => j === i ? { ...r, count: n } : r)); }}
              style={{ width: 70, padding: '8px 10px', background: 'white', border: `1.2px solid ${C.border}`, borderRadius: 8, fontSize: 13, color: C.dark, outline: 'none', fontFamily: 'inherit' }} />
            {rules.length > 1 && (
              <button onClick={() => setRules(p => p.filter((_, j) => j !== i))} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2 }}>
                <XCircle size={20} color={C.error} />
              </button>
            )}
          </div>
        ))}
        <button onClick={() => setRules(p => [...p, { rank: RANKS[RANKS.length - 1], count: 1 }])} style={{
          width: '100%', padding: 11, background: hex(color, 0.06), border: `1px solid ${hex(color, 0.3)}`,
          borderRadius: 10, fontSize: 12, fontWeight: 700, color, cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
        }}>
          <Plus size={16} /> और Rank जोड़ें
        </button>
      </div>
      <div style={{ padding: '8px 16px 16px', display: 'flex', gap: 12 }}>
        <button onClick={onClose} style={{ flex: 1, padding: '12px 0', border: `1px solid ${C.border}`, borderRadius: 10, background: 'transparent', color: C.subtle, cursor: 'pointer', fontSize: 13 }}>रद्द</button>
        <button onClick={confirm} style={{ flex: 1, padding: '12px 0', border: 'none', borderRadius: 10, background: color, color: 'white', cursor: 'pointer', fontSize: 12, fontWeight: 700 }}>
          Confirm &amp; Auto-Assign
        </button>
      </div>
    </Modal>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// ASSIGN RESULT VIEW
// ══════════════════════════════════════════════════════════════════════════════
function AssignResultView({ assignedStaff, missingRanks, lowerRankAssignments, centerType, centerId, onAssignManual, onManageRooms, onCustomRules }) {
  const [assigningRank, setAssigningRank] = useState(null);

  return (
    <div>
      {/* Success */}
      <div style={{ padding: 12, background: hex(C.success, 0.07), border: `1px solid ${hex(C.success, 0.3)}`, borderRadius: 10, display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
        <CheckCircle2 size={20} color={C.success} />
        <div>
          <p style={{ color: C.success, fontWeight: 800, fontSize: 13 }}>Center बन गया!</p>
          <p style={{ color: C.subtle, fontSize: 11 }}>{assignedStaff.length} स्टाफ "{centerType}" मानक के अनुसार असाइन हुए</p>
        </div>
      </div>

      {/* Quick actions */}
      <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
        <button onClick={onManageRooms} style={{ flex: 1, padding: 10, background: hex(C.primary, 0.07), border: `1px solid ${hex(C.primary, 0.25)}`, borderRadius: 8, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5, color: C.primary, fontSize: 11, fontWeight: 700 }}>
          <DoorOpen size={14} /> Matdan Sthal
        </button>
        <button onClick={onCustomRules} style={{ flex: 1, padding: 10, background: hex(C.info, 0.07), border: `1px solid ${hex(C.info, 0.25)}`, borderRadius: 8, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5, color: C.info, fontSize: 11, fontWeight: 700 }}>
          <ListChecks size={14} /> Custom Rules
        </button>
      </div>

      {/* Lower rank substitutions */}
      {lowerRankAssignments.length > 0 && (
        <div style={{ padding: 10, background: hex('#FF6F00', 0.07), border: `1px solid ${hex('#FF6F00', 0.35)}`, borderRadius: 10, marginBottom: 14 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
            <ArrowDownUp size={16} color="#FF6F00" />
            <p style={{ color: '#FF6F00', fontWeight: 800, fontSize: 12 }}>Lower Rank से असाइन किया गया</p>
          </div>
          {lowerRankAssignments.map((lr, i) => (
            <div key={i} style={{ padding: '7px 10px', background: hex('#FF6F00', 0.06), borderRadius: 8, marginBottom: 4, fontSize: 11, color: C.dark }}>
              <span style={{ fontWeight: 700 }}>{lr.requiredRank}</span> <span style={{ color: C.subtle }}>नहीं मिला —</span> <span style={{ color: '#FF6F00', fontWeight: 700 }}>{lr.assignedRank}</span> <span style={{ color: C.subtle }}>से assigned</span>
            </div>
          ))}
        </div>
      )}

      {/* Assigned staff */}
      {assignedStaff.length > 0 && (
        <>
          <p style={{ color: C.dark, fontWeight: 800, fontSize: 13, marginBottom: 8 }}>असाइन किए गए स्टाफ</p>
          {assignedStaff.map((s, i) => {
            const rc = RANK_COLORS[s.rank] || C.primary;
            const isLower = s.isLowerRank;
            return (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '9px 12px', background: 'white', border: `1px solid ${hex(C.border, 0.4)}`, borderRadius: 9, marginBottom: 6 }}>
                {isLower ? <ArrowDownUp size={16} color="#FF6F00" /> : <CheckCircle2 size={16} color={C.success} />}
                <div style={{ flex: 1 }}>
                  <p style={{ fontWeight: 700, fontSize: 13, color: C.dark }}>{s.name}</p>
                  {isLower && s.originalRank && <p style={{ fontSize: 10, color: '#FF6F00' }}>In place of: {s.originalRank}</p>}
                </div>
                <span style={{ padding: '2px 7px', background: hex(rc, 0.1), borderRadius: 6, fontSize: 10, fontWeight: 700, color: rc }}>{s.rank}</span>
              </div>
            );
          })}
        </>
      )}

      {/* Missing ranks */}
      {missingRanks.length > 0 && (
        <>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8, marginTop: 14 }}>
            <AlertTriangle size={16} color={C.error} />
            <p style={{ color: C.error, fontWeight: 800, fontSize: 13 }}>अनुपलब्ध रैंक — मैन्युअल असाइन करें</p>
          </div>
          {missingRanks.map((m, i) => (
            <div key={i} style={{ padding: 12, background: hex(C.error, 0.04), border: `1px solid ${hex(C.error, 0.25)}`, borderRadius: 10, marginBottom: 8 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: m.lowerRankSuggestion ? 6 : 8 }}>
                <User size={14} color={C.error} />
                <p style={{ flex: 1, fontWeight: 700, fontSize: 13, color: C.error }}>{m.rank}</p>
                <span style={{ fontSize: 11, color: C.error }}>{m.required} चाहिए, {m.available} उपलब्ध</span>
              </div>
              {m.lowerRankSuggestion && (
                <div style={{ padding: '4px 8px', background: hex('#FF6F00', 0.08), borderRadius: 6, marginBottom: 8, fontSize: 10, color: '#FF6F00', fontWeight: 600 }}>
                  सुझाव: {m.lowerRankSuggestion} rank से assign करें
                </div>
              )}
              <div style={{ display: 'flex', gap: 8 }}>
                <button onClick={() => onAssignManual(m.rank, centerId)} style={{
                  flex: 1, padding: '8px 0', border: `1px solid ${C.border}`, borderRadius: 8,
                  background: 'transparent', color: C.primary, cursor: 'pointer', fontSize: 12, fontWeight: 600,
                  display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4,
                }}>
                  <Plus size={14} /> {m.rank} मैन्युअल असाइन
                </button>
                <button style={{ padding: '8px 12px', border: `1px solid ${hex(C.subtle, 0.5)}`, borderRadius: 8, background: 'transparent', color: C.subtle, cursor: 'pointer', fontSize: 12 }}>
                  छोड़ें
                </button>
              </div>
            </div>
          ))}
        </>
      )}

      {assigningRank && (
        <StaffPickerSheet allowedRanks={[assigningRank, ...RANK_HIERARCHY.slice(RANK_HIERARCHY.indexOf(assigningRank) + 1)]} color={C.primary}
          onPick={async s => {
            try {
              // POST /admin/duties
              await apiClient.post('/admin/duties', { staffId: s.id, centerId });
              toast.success(`${s.name} असाइन किया गया`);
            } catch (e) { toast.error(`Error: ${e.message}`); }
            setAssigningRank(null);
          }}
          onClose={() => setAssigningRank(null)} />
      )}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// CENTER DIALOG
// ══════════════════════════════════════════════════════════════════════════════
function CenterDialog({ gpId, existing, onDone, onClose }) {
  const [form, setForm] = useState({
    name: existing?.name || '',
    address: existing?.address || '',
    thana: existing?.thana || '',
    busNo: existing?.busNo || '',
    latitude: existing?.latitude?.toString() || '',
    longitude: existing?.longitude?.toString() || '',
    centerType: existing?.centerType || 'C',
  });
  const prevType = useRef(existing?.centerType || 'C');
  const [saving, setSaving] = useState(false);
  const [autoAssigning, setAutoAssigning] = useState(false);
  const [autoAssigned, setAutoAssigned] = useState(false);
  const [savedCenterId, setSavedCenterId] = useState(0);
  const [assignedStaff, setAssignedStaff] = useState([]);
  const [missingRanks, setMissingRanks] = useState([]);
  const [lowerRankAssignments, setLowerRankAssignments] = useState([]);
  const [customRules, setCustomRules] = useState([]);
  const [showRooms, setShowRooms] = useState(false);
  const [showCustomRules, setShowCustomRules] = useState(false);
  const [customRulesCenterId, setCustomRulesCenterId] = useState(0);

  const color = TYPE_COLORS[form.centerType] || C.info;

  const runAutoAssign = async (centerId, { isReassign = false, rules = null } = {}) => {
    setAutoAssigning(true);
    try {
      if (isReassign) {
        // POST /admin/centers/:id/clear-assignments
        try { await apiClient.post(`/admin/centers/${centerId}/clear-assignments`, {}); } catch (_) { }
      }
      const body = {};
      if (rules?.length) body.customRules = rules.map(r => ({ rank: r.rank, count: r.count }));
      // POST /admin/auto-assign/:centerId
      const res = await apiClient.post(`/admin/auto-assign/${centerId}`, body);
      const d = res.data || res || {};
      setAssignedStaff(d.assigned || []);
      setMissingRanks(d.missing || []);
      setLowerRankAssignments(d.lowerRankUsed || []);
      setSavedCenterId(centerId);
      setAutoAssigning(false);
      setAutoAssigned(true);
    } catch (e) {
      toast.error(`Auto-assign failed: ${e.message}`);
      setAutoAssigning(false);
      onClose(); onDone();
    }
  };

  const save = async () => {
    if (!form.name.trim()) { toast.error('नाम आवश्यक है'); return; }
    setSaving(true);
    try {
      const body = {
        name: form.name.trim(), address: form.address.trim(), thana: form.thana.trim(),
        busNo: form.busNo.trim(), centerType: form.centerType,
        latitude: form.latitude ? parseFloat(form.latitude) : null,
        longitude: form.longitude ? parseFloat(form.longitude) : null,
      };
      if (existing) {
        // PUT /admin/centers/:id
        await apiClient.put(`/admin/centers/${existing.id}`, body);
        setSaving(false);
        const typeChanged = form.centerType !== prevType.current;
        if (typeChanged) {
          await runAutoAssign(existing.id, { isReassign: true });
        } else {
          onClose(); onDone();
        }
      } else {
        // POST /admin/gram-panchayats/:gpId/centers
        const res = await apiClient.post(`/admin/gram-panchayats/${gpId}/centers`, body);
        const centerId = res.data?.id || res.id || 0;
        setSaving(false);
        if (centerId > 0) {
          await runAutoAssign(centerId);
        } else {
          onClose(); onDone();
        }
      }
    } catch (e) {
      setSaving(false);
      toast.error(`Error: ${e.message}`);
    }
  };

  const formField = (key, label, Icon, opts = {}) => (
    <FieldInput label={label} icon={Icon} color={color} value={form[key]} onChange={v => setForm(p => ({ ...p, [key]: v }))} {...opts} />
  );

  return (
    <>
      <Modal open onClose={autoAssigned ? undefined : onClose} maxWidth={520}>
        <ModalHeader
          title={existing ? 'Center संपादित करें' : 'Election Center जोड़ें'}
          Icon={MapPin} color={color}
          onClose={autoAssigned ? undefined : onClose}
        />
        <div style={{ overflowY: 'auto', flex: 1, padding: 16 }}>
          {autoAssigning ? (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '40px 0', gap: 16 }}>
              <Spinner color={C.primary} size={32} />
              <p style={{ color: C.subtle, fontSize: 13, textAlign: 'center' }}>मानक के अनुसार स्टाफ असाइन हो रहा है...</p>
            </div>
          ) : autoAssigned ? (
            <AssignResultView
              assignedStaff={assignedStaff} missingRanks={missingRanks} lowerRankAssignments={lowerRankAssignments}
              centerType={form.centerType} centerId={savedCenterId}
              onAssignManual={(rank) => { }}
              onManageRooms={() => setShowRooms(true)}
              onCustomRules={() => { setCustomRulesCenterId(savedCenterId); setShowCustomRules(true); }}
            />
          ) : (
            <>
              {formField('name', 'Center का नाम *', MapPin)}
              {formField('address', 'पता', MapPin)}
              <div style={{ display: 'flex', gap: 10 }}>
                <div style={{ flex: 1 }}>{formField('thana', 'थाना', ShieldCheck)}</div>
                <div style={{ flex: 1 }}>{formField('busNo', 'Bus No', Badge)}</div>
              </div>
              <div style={{ display: 'flex', gap: 10 }}>
                <div style={{ flex: 1 }}>{formField('latitude', 'Latitude (optional)', MapPin)}</div>
                <div style={{ flex: 1 }}>{formField('longitude', 'Longitude (optional)', MapPin)}</div>
              </div>

              {/* Rooms shortcut on edit */}
              {existing && (
                <button onClick={() => setShowRooms(true)} style={{
                  width: '100%', padding: 12, background: hex(C.info, 0.06), border: `1px solid ${hex(C.info, 0.25)}`,
                  borderRadius: 10, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12, textAlign: 'left',
                }}>
                  <DoorOpen size={16} color={C.info} />
                  <div style={{ flex: 1 }}>
                    <p style={{ color: C.info, fontWeight: 700, fontSize: 13 }}>मतदान स्थल (Matdan Sthal) / कमरे</p>
                    <p style={{ color: C.subtle, fontSize: 11 }}>{existing.roomCount || 0} कमरे दर्ज हैं — प्रबंधन के लिए टैप करें</p>
                  </div>
                  <ChevronRight size={14} color={C.info} />
                </button>
              )}

              {/* Center type */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
                <div style={{ width: 3, height: 14, background: color, borderRadius: 2 }} />
                <p style={{ color: C.dark, fontSize: 13, fontWeight: 700 }}>संवेदनशीलता / Center Type</p>
              </div>
              <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
                {CENTER_TYPES.map(t => {
                  const tc = TYPE_COLORS[t];
                  const sel = form.centerType === t;
                  return (
                    <button key={t} onClick={() => setForm(p => ({ ...p, centerType: t }))} style={{
                      flex: 1, padding: '10px 0', border: `${sel ? 2 : 1}px solid ${tc}`,
                      borderRadius: 10, cursor: 'pointer', background: sel ? tc : 'white',
                      transition: 'all 0.15s',
                    }}>
                      <p style={{ color: sel ? 'white' : tc, fontWeight: 900, fontSize: 14 }}>{t}</p>
                      <p style={{ color: sel ? 'rgba(255,255,255,0.7)' : hex(tc, 0.7), fontSize: 9 }}>{TYPE_LABELS[t]}</p>
                    </button>
                  );
                })}
              </div>

              {/* Type change warning */}
              {existing && form.centerType !== prevType.current && (
                <div style={{ padding: 10, background: hex('#FF6F00', 0.08), border: `1px solid ${hex('#FF6F00', 0.35)}`, borderRadius: 8, display: 'flex', gap: 8, marginBottom: 10 }}>
                  <AlertTriangle size={14} color="#FF6F00" style={{ flexShrink: 0 }} />
                  <p style={{ fontSize: 11, color: '#FF6F00' }}>Center Type बदलने पर सभी पुराने assignments हट जाएंगे और नए नियमों से auto-assign होगा।</p>
                </div>
              )}

              <div style={{ padding: 10, background: hex(C.info, 0.06), border: `1px solid ${hex(C.info, 0.2)}`, borderRadius: 8, display: 'flex', gap: 8 }}>
                <Info size={14} color={C.info} style={{ flexShrink: 0 }} />
                <p style={{ fontSize: 11, color: C.info }}>Center जोड़ने के बाद मानक के अनुसार स्टाफ स्वतः असाइन होगा। Custom rules भी सेट कर सकते हैं।</p>
              </div>
            </>
          )}
        </div>

        {!autoAssigning && (
          <div style={{ padding: '8px 16px 16px', display: 'flex', gap: 8 }}>
            {autoAssigned ? (
              <>
                <button onClick={() => setShowRooms(true)} style={{ flex: 1, padding: '10px 0', border: `1px solid ${C.border}`, borderRadius: 10, background: 'transparent', color: C.primary, cursor: 'pointer', fontSize: 12, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4 }}>
                  <DoorOpen size={13} /> Matdan Sthal
                </button>
                <button onClick={() => { setCustomRulesCenterId(savedCenterId); setShowCustomRules(true); }} style={{ flex: 1, padding: '10px 0', border: `1px solid ${C.border}`, borderRadius: 10, background: 'transparent', color: C.info, cursor: 'pointer', fontSize: 12, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4 }}>
                  <ListChecks size={13} /> Custom Rules
                </button>
                <button onClick={() => { onClose(); onDone(); }} style={{ flex: 1, padding: '10px 0', border: 'none', borderRadius: 10, background: C.success, color: 'white', cursor: 'pointer', fontSize: 12, fontWeight: 700 }}>
                  बंद करें
                </button>
              </>
            ) : (
              <>
                <button onClick={onClose} style={{ flex: 1, padding: '12px 0', border: `1px solid ${C.border}`, borderRadius: 10, background: 'transparent', color: C.subtle, cursor: 'pointer', fontSize: 13 }}>रद्द</button>
                <button onClick={save} disabled={saving} style={{ flex: 1, padding: '12px 0', border: 'none', borderRadius: 10, background: color, color: 'white', cursor: 'pointer', fontSize: 13, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, opacity: saving ? 0.7 : 1 }}>
                  {saving ? <Spinner /> : (existing ? (form.centerType !== prevType.current ? 'Update + Reassign' : 'अपडेट करें') : 'जोड़ें + Auto-Assign')}
                </button>
              </>
            )}
          </div>
        )}
      </Modal>

      {showRooms && (
        <MatdanSthalDialog centerId={savedCenterId || existing?.id} centerName={form.name} onClose={() => setShowRooms(false)} />
      )}
      {showCustomRules && (
        <CustomRankRulesDialog
          centerId={customRulesCenterId} centerName={form.name} centerType={form.centerType}
          existingRules={customRules.map(r => ({ rank: r.rank, count: r.count }))}
          onConfirm={async (rules) => {
            setCustomRules(rules);
            await runAutoAssign(customRulesCenterId, { rules });
          }}
          onClose={() => setShowCustomRules(false)} />
      )}
    </>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// ITEM CARD
// ══════════════════════════════════════════════════════════════════════════════
function ItemCard({ item, color, Icon: I, isSelected, onTap, onEdit, onDelete }) {
  const officers = item.officers || [];
  return (
    <div onClick={onTap} style={{
      marginBottom: 8, padding: '10px 8px 10px 12px',
      background: isSelected ? hex(color, 0.07) : 'white',
      border: `${isSelected ? 2 : 1}px solid ${isSelected ? color : hex(C.border, 0.4)}`,
      borderRadius: 12, cursor: 'pointer', transition: 'all 0.15s',
      boxShadow: `0 2px 6px ${hex(color, 0.05)}`,
      display: 'flex', alignItems: 'flex-start', gap: 10,
    }}>
      <div style={{
        width: 38, height: 38, borderRadius: '50%', flexShrink: 0,
        background: hex(color, 0.12), border: `1px solid ${hex(color, 0.3)}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {isSelected ? <Check size={18} color={color} /> : <I size={18} color={color} />}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
          <p style={{ flex: 1, fontWeight: 700, fontSize: 14, color: isSelected ? color : C.dark, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{item.name}</p>
          {isSelected && <span style={{ padding: '2px 7px', background: hex(color, 0.12), border: `1px solid ${hex(color, 0.3)}`, borderRadius: 6, fontSize: 10, fontWeight: 700, color, flexShrink: 0 }}>चुना गया</span>}
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 10px' }}>
          {item.district && <Tag icon={Landmark} text={item.district} />}
          {item.block && <Tag icon={LayoutGrid} text={item.block} />}
          {item.hqAddress && <Tag icon={MapPin} text={item.hqAddress} />}
          {item.zoneCount != null && <Tag icon={Grid} text={`${item.zoneCount} Zones`} />}
          {item.sectorCount != null && <Tag icon={LayoutGrid} text={`${item.sectorCount} Sectors`} />}
          {item.gpCount != null && <Tag icon={Landmark} text={`${item.gpCount} GPs`} />}
          {item.centerCount != null && <Tag icon={MapPin} text={`${item.centerCount} Centers`} />}
        </div>
        {officers.slice(0, 3).length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 5px', marginTop: 6 }}>
            {officers.slice(0, 3).map((o, i) => (
              <span key={i} style={{ display: 'inline-flex', alignItems: 'center', gap: 3, padding: '3px 7px', background: hex(color, 0.06), border: `1px solid ${hex(color, 0.2)}`, borderRadius: 6, fontSize: 10, color }}>
                <User size={10} /> {o.name} {o.rank && <span style={{ color: C.subtle }}>({o.rank})</span>}
              </span>
            ))}
            {officers.length > 3 && <span style={{ fontSize: 10, color }}>+{officers.length - 3} more</span>}
          </div>
        )}
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4, flexShrink: 0 }}>
        <IconBtn icon={Pencil} color={C.info} onClick={e => { e.stopPropagation(); onEdit(); }} title="Edit" />
        <IconBtn icon={Trash2} color={C.error} onClick={e => { e.stopPropagation(); onDelete(); }} title="Delete" />
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// CENTER CARD
// ══════════════════════════════════════════════════════════════════════════════
function CenterCard({ center, onEdit, onDelete }) {
  const type = center.centerType || 'C';
  const tc = TYPE_COLORS[type] || C.info;
  const assigned = center.assignedStaff || [];
  const missing = center.missingRanks || [];
  const dutyCount = center.dutyCount ?? assigned.length;
  const roomCount = center.roomCount ?? 0;

  return (
    <div style={{ marginBottom: 10, background: 'white', border: `1px solid ${hex(C.border, 0.4)}`, borderRadius: 12, boxShadow: `0 2px 6px ${hex(tc, 0.06)}` }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10, padding: '10px 8px 10px 12px' }}>
        <div style={{ width: 42, height: 42, background: hex(tc, 0.1), border: `1px solid ${hex(tc, 0.3)}`, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <span style={{ color: tc, fontWeight: 900, fontSize: type.length > 1 ? 11 : 16 }}>{type}</span>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <p style={{ fontWeight: 700, fontSize: 14, color: C.dark, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', marginBottom: 3 }}>{center.name}</p>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '3px 8px' }}>
            {center.thana && <Tag icon={ShieldCheck} text={center.thana} />}
            {center.busNo && <Tag icon={Badge} text={`Bus: ${center.busNo}`} />}
            <Tag icon={User} text={`${dutyCount} स्टाफ`} />
            {roomCount > 0 && <Tag icon={DoorOpen} text={`${roomCount} कमरे`} />}
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <IconBtn icon={Pencil} color={C.info} onClick={onEdit} />
          <IconBtn icon={Trash2} color={C.error} onClick={onDelete} />
        </div>
      </div>
      {missing.length > 0 && (
        <div style={{ margin: '0 12px 8px', padding: '8px 10px', background: hex(C.error, 0.05), border: `1px solid ${hex(C.error, 0.25)}`, borderRadius: 8 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 5 }}>
            <AlertTriangle size={13} color={C.error} />
            <p style={{ fontSize: 12, fontWeight: 700, color: C.error }}>कुछ रैंक उपलब्ध नहीं</p>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 6px' }}>
            {missing.map((m, i) => (
              <span key={i} style={{ padding: '3px 7px', background: hex(C.error, 0.08), borderRadius: 6, fontSize: 10, fontWeight: 600, color: C.error }}>
                {m.rank}: {m.required} आवश्यक, {m.available} उपलब्ध
              </span>
            ))}
          </div>
        </div>
      )}
      {assigned.length > 0 && (
        <div style={{ padding: '0 12px 10px', display: 'flex', flexWrap: 'wrap', gap: '5px 6px' }}>
          {assigned.map((s, i) => {
            const rc = RANK_COLORS[s.rank] || C.primary;
            return (
              <span key={i} style={{ display: 'inline-flex', alignItems: 'center', gap: 4, padding: '4px 7px', background: hex(C.success, 0.06), border: `1px solid ${hex(C.success, 0.25)}`, borderRadius: 7 }}>
                <CheckCircle2 size={11} color={C.success} />
                <span style={{ fontSize: 11, fontWeight: 600, color: C.dark, maxWidth: 80, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{s.name}</span>
                <span style={{ padding: '1px 4px', background: hex(rc, 0.12), borderRadius: 4, fontSize: 9, fontWeight: 700, color: rc }}>{s.rank}</span>
              </span>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// GENERIC STEP LIST (Super Zone / Zone / Sector / GP)
// ══════════════════════════════════════════════════════════════════════════════
function StepList({ title, Icon: I, color, officerTitle, officerRanks, fetchUrl, createUrl, updateUrlFn, deleteUrlFn, fields, onSelect, selectedId }) {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [q, setQ] = useState('');
  const [dialog, setDialog] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const scrollRef = useRef(null);
  const pageRef = useRef(1);
  const hasMoreRef = useRef(true);
  const qRef = useRef('');
  const LIMIT = 20;

  const load = useCallback(async (reset = false) => {
    if (!reset && !hasMoreRef.current) return;
    if (reset) {
      pageRef.current = 1;
      hasMoreRef.current = true;
      setItems([]);
      setLoading(true);
    } else {
      setLoadingMore(true);
    }
    try {
      // fetchUrl is already the path without leading /api, e.g. '/admin/super-zones'
      const res = await apiClient.get(fetchUrl, {
        params: { page: pageRef.current, limit: LIMIT, q: qRef.current },
      });
      let fetched = [], totalPages = 1;
      if (Array.isArray(res.data)) { fetched = res.data; }
      else if (res.data?.data) { fetched = res.data.data; totalPages = res.data.totalPages || 1; }
      else if (Array.isArray(res)) { fetched = res; }
      hasMoreRef.current = pageRef.current < totalPages;
      setHasMore(pageRef.current < totalPages);
      pageRef.current++;
      setItems(prev => reset ? fetched : [...prev, ...fetched]);
    } catch (_) { }
    finally { setLoading(false); setLoadingMore(false); }
  }, [fetchUrl]);

  useEffect(() => { qRef.current = ''; load(true); }, [fetchUrl]);

  const debouncedSearch = useCallback(debounce((v) => { qRef.current = v; load(true); }, 350), [load]);

  const handleScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 200 && !loadingMore) load();
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    try {
      // deleteUrlFn(id) e.g. '/admin/super-zones/5'
      await apiClient.delete(deleteUrlFn(deleteTarget.id));
      toast.success('Deleted');
      setDeleteTarget(null);
      load(true);
    } catch (e) { toast.error(`Delete failed: ${e.message}`); }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Header */}
      <div style={{ background: C.surface, padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0 }}>
        <div style={{ padding: 7, background: hex(color, 0.12), borderRadius: 8 }}>
          <I size={16} color={color} />
        </div>
        <p style={{ flex: 1, color: C.dark, fontWeight: 800, fontSize: 15 }}>{title}</p>
        <button onClick={() => setDialog('add')} style={{
          padding: '7px 12px', background: color, color: 'white', border: 'none', borderRadius: 9, cursor: 'pointer',
          fontSize: 12, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 4,
        }}>
          <Plus size={14} /> जोड़ें
        </button>
      </div>

      {/* Search */}
      <div style={{ background: C.bg, padding: '8px 12px', flexShrink: 0 }}>
        <div style={{ position: 'relative' }}>
          <Search size={16} color={C.subtle} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)' }} />
          <input
            placeholder={`${title} खोजें...`}
            onChange={e => { setQ(e.target.value); debouncedSearch(e.target.value); }}
            style={{ width: '100%', padding: '9px 32px 9px 32px', background: 'white', border: `1.2px solid ${C.border}`, borderRadius: 10, fontSize: 13, color: C.dark, outline: 'none', fontFamily: 'inherit', boxSizing: 'border-box' }}
          />
          {q && <button onClick={() => { setQ(''); qRef.current = ''; load(true); }} style={{ position: 'absolute', right: 8, top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', cursor: 'pointer' }}><X size={14} color={C.subtle} /></button>}
        </div>
      </div>

      {/* List */}
      <div ref={scrollRef} onScroll={handleScroll} style={{ flex: 1, overflowY: 'auto', padding: '8px 12px 80px' }}>
        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 40 }}><Spinner color={C.primary} /></div>
        ) : items.length === 0 ? (
          <EmptyState label={title} Icon={I} color={color} />
        ) : (
          items.map(item => (
            <ItemCard key={item.id} item={item} color={color} Icon={I}
              isSelected={selectedId === item.id}
              onTap={() => onSelect(item)}
              onEdit={() => setDialog(item)}
              onDelete={() => setDeleteTarget(item)} />
          ))
        )}
        {loadingMore && <div style={{ display: 'flex', justifyContent: 'center', padding: 12 }}><Spinner color={C.primary} size={16} /></div>}
      </div>

      {/* Dialogs */}
      {dialog && (
        <ItemDialog
          title={dialog === 'add' ? `${title.replace(/s$/, '')} जोड़ें` : 'संपादित करें'}
          color={color} Icon={I}
          fields={fields}
          officerTitle={officerTitle} officerRanks={officerRanks}
          existing={dialog === 'add' ? null : dialog}
          createUrl={createUrl}
          updateUrlFn={updateUrlFn}
          onDone={() => load(true)}
          onClose={() => setDialog(null)} />
      )}
      <ConfirmDialog open={!!deleteTarget} message={`Delete "${deleteTarget?.name}"?`} onConfirm={handleDelete} onCancel={() => setDeleteTarget(null)} />
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// CENTER STEP
// ══════════════════════════════════════════════════════════════════════════════
function CenterStep({ gpId }) {
  const [centers, setCenters] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [q, setQ] = useState('');
  const [dialog, setDialog] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const scrollRef = useRef(null);
  const pageRef = useRef(1);
  const hasMoreRef = useRef(true);
  const qRef = useRef('');

  const load = useCallback(async (reset = false) => {
    if (!reset && !hasMoreRef.current) return;
    if (reset) { pageRef.current = 1; hasMoreRef.current = true; setCenters([]); setLoading(true); }
    else setLoadingMore(true);
    try {
      const res = await apiClient.get(`/admin/gram-panchayats/${gpId}/centers`, {
        params: { page: pageRef.current, limit: 20, q: qRef.current },
      });
      let items = [], totalPages = 1;
      if (Array.isArray(res.data)) { items = res.data; }
      else if (res.data?.data) { items = res.data.data; totalPages = res.data.totalPages || 1; }
      else if (Array.isArray(res)) { items = res; }
      hasMoreRef.current = pageRef.current < totalPages;
      setHasMore(pageRef.current < totalPages);
      pageRef.current++;
      setCenters(prev => reset ? items : [...prev, ...items]);
    } catch (_) { }
    finally { setLoading(false); setLoadingMore(false); }
  }, [gpId]);

  useEffect(() => { qRef.current = ''; load(true); }, [gpId]);

  const debouncedSearch = useCallback(debounce((v) => { qRef.current = v; load(true); }, 350), [load]);

  const handleScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 200) load();
  };

  const handleDelete = async () => {
    try {
      // DELETE /admin/centers/:id
      await apiClient.delete(`/admin/centers/${deleteTarget.id}`);
      toast.success('Deleted'); setDeleteTarget(null); load(true);
    } catch (e) { toast.error(`Delete failed: ${e.message}`); }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ background: C.surface, padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0 }}>
        <div style={{ padding: 7, background: hex('#C62828', 0.12), borderRadius: 8 }}>
          <MapPin size={16} color="#C62828" />
        </div>
        <p style={{ flex: 1, color: C.dark, fontWeight: 800, fontSize: 15 }}>Election Centers</p>
        <button onClick={() => setDialog('add')} style={{ padding: '7px 12px', background: '#C62828', color: 'white', border: 'none', borderRadius: 9, cursor: 'pointer', fontSize: 12, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 4 }}>
          <Plus size={14} /> जोड़ें
        </button>
      </div>
      <div style={{ background: C.bg, padding: '8px 12px', flexShrink: 0 }}>
        <div style={{ position: 'relative' }}>
          <Search size={16} color={C.subtle} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)' }} />
          <input placeholder="Center खोजें..." onChange={e => { setQ(e.target.value); debouncedSearch(e.target.value); }}
            style={{ width: '100%', padding: '9px 32px', background: 'white', border: `1.2px solid ${C.border}`, borderRadius: 10, fontSize: 13, color: C.dark, outline: 'none', fontFamily: 'inherit', boxSizing: 'border-box' }} />
        </div>
      </div>
      <div ref={scrollRef} onScroll={handleScroll} style={{ flex: 1, overflowY: 'auto', padding: '8px 12px 80px' }}>
        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 40 }}><Spinner color={C.primary} /></div>
        ) : centers.length === 0 ? (
          <EmptyState label="Election Centers" Icon={MapPin} color="#C62828" />
        ) : (
          centers.map(c => (
            <CenterCard key={c.id} center={c}
              onEdit={() => setDialog(c)}
              onDelete={() => setDeleteTarget(c)} />
          ))
        )}
        {loadingMore && <div style={{ display: 'flex', justifyContent: 'center', padding: 12 }}><Spinner color={C.primary} size={16} /></div>}
      </div>
      {dialog && (
        <CenterDialog gpId={gpId} existing={dialog === 'add' ? null : dialog} onDone={() => load(true)} onClose={() => setDialog(null)} />
      )}
      <ConfirmDialog open={!!deleteTarget} message={`Delete "${deleteTarget?.name}"?`} onConfirm={handleDelete} onCancel={() => setDeleteTarget(null)} />
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// BREADCRUMB
// ══════════════════════════════════════════════════════════════════════════════
function Breadcrumb({ step, szName, zoneName, sectorName, gpName, onTap }) {
  const crumbs = [];
  if (szName) crumbs.push({ name: szName, Icon: Layers, color: '#6A1B9A', step: 0 });
  if (zoneName) crumbs.push({ name: zoneName, Icon: Grid, color: '#1565C0', step: 1 });
  if (sectorName) crumbs.push({ name: sectorName, Icon: LayoutGrid, color: '#2E7D32', step: 2 });
  if (gpName) crumbs.push({ name: gpName, Icon: Landmark, color: '#6D4C41', step: 3 });
  if (!crumbs.length) return null;

  return (
    <div style={{ background: hex(C.surface, 0.7), padding: '6px 12px', display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0, overflowX: 'auto' }}>
      {crumbs.map((c, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
          {i > 0 && <ChevronRight size={14} color={C.subtle} />}
          <button onClick={() => onTap(c.step)} style={{
            padding: '3px 8px', background: hex(c.color, i === crumbs.length - 1 ? 0.12 : 0.06),
            border: `1px solid ${hex(c.color, i === crumbs.length - 1 ? 0.4 : 0.2)}`,
            borderRadius: 6, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4, maxWidth: 120,
          }}>
            <c.Icon size={11} color={c.color} />
            <span style={{ fontSize: 11, fontWeight: i === crumbs.length - 1 ? 700 : 500, color: c.color, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {c.name}
            </span>
          </button>
        </div>
      ))}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP BAR
// ══════════════════════════════════════════════════════════════════════════════
function StepBar({ currentStep, onTap, szName, zoneName, sectorName, gpName }) {
  const isEnabled = (step) => {
    if (step === 0) return true;
    if (step === 1) return !!szName;
    if (step === 2) return !!zoneName;
    if (step === 3) return !!sectorName;
    if (step === 4) return !!gpName;
    return false;
  };

  return (
    <div style={{ background: C.dark, padding: '10px 8px', display: 'flex', gap: 4, flexShrink: 0 }}>
      {STEPS.map(({ id, label, Icon: I, color }) => {
        const isCur = currentStep === id;
        const isDone = currentStep > id;
        const isEn = isEnabled(id);
        return (
          <button key={id} onClick={() => isEn && onTap(id)} disabled={!isEn} style={{
            flex: 1, padding: '7px 0',
            background: isCur ? color : isDone ? hex(color, 0.2) : 'rgba(255,255,255,0.07)',
            border: `1px solid ${isCur ? color : isDone ? hex(color, 0.4) : 'rgba(255,255,255,0.15)'}`,
            borderRadius: 10, cursor: isEn ? 'pointer' : 'default',
            transition: 'all 0.2s', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
          }}>
            {isDone
              ? <Check size={16} color={isCur ? 'white' : color} />
              : <I size={16} color={isCur ? 'white' : isDone ? color : 'rgba(255,255,255,0.3)'} />
            }
            <span style={{ fontSize: 9, fontWeight: isCur ? 800 : 500, color: isCur ? 'white' : isDone ? color : 'rgba(255,255,255,0.35)' }}>
              {label}
            </span>
          </button>
        );
      })}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN FORM PAGE
// ══════════════════════════════════════════════════════════════════════════════
export default function FormPage() {
  const [step, setStep] = useState(0);
  const [selected, setSelected] = useState({ szId: null, szName: null, zoneId: null, zoneName: null, sectorId: null, sectorName: null, gpId: null, gpName: null });

  const goToStep = (s) => {
    setStep(s);
    setSelected(prev => {
      const n = { ...prev };
      if (s <= 0) { n.szId = null; n.szName = null; }
      if (s <= 1) { n.zoneId = null; n.zoneName = null; }
      if (s <= 2) { n.sectorId = null; n.sectorName = null; }
      if (s <= 3) { n.gpId = null; n.gpName = null; }
      return n;
    });
  };

  const onSZSelected = (item) => {
    setSelected({ szId: item.id, szName: item.name, zoneId: null, zoneName: null, sectorId: null, sectorName: null, gpId: null, gpName: null });
    setStep(1);
  };
  const onZoneSelected = (item) => {
    setSelected(p => ({ ...p, zoneId: item.id, zoneName: item.name, sectorId: null, sectorName: null, gpId: null, gpName: null }));
    setStep(2);
  };
  const onSectorSelected = (item) => {
    setSelected(p => ({ ...p, sectorId: item.id, sectorName: item.name, gpId: null, gpName: null }));
    setStep(3);
  };
  const onGPSelected = (item) => {
    setSelected(p => ({ ...p, gpId: item.id, gpName: item.name }));
    setStep(4);
  };

  const renderStep = () => {
    switch (step) {
      case 0: return (
        <StepList key="sz" title="Super Zones" Icon={Layers} color="#6A1B9A"
          officerTitle={LEVEL_OFFICER_TITLE[0]} officerRanks={LEVEL_RANKS[0]}
          fetchUrl="/admin/super-zones" createUrl="/admin/super-zones"
          updateUrlFn={id => `/admin/super-zones/${id}`}
          deleteUrlFn={id => `/admin/super-zones/${id}`}
          fields={['name', 'district', 'block']}
          onSelect={onSZSelected} selectedId={selected.szId} />
      );
      case 1: return (
        <StepList key={`zone_${selected.szId}`} title="Zones" Icon={Grid} color="#1565C0"
          officerTitle={LEVEL_OFFICER_TITLE[1]} officerRanks={LEVEL_RANKS[1]}
          fetchUrl={`/admin/super-zones/${selected.szId}/zones`}
          createUrl={`/admin/super-zones/${selected.szId}/zones`}
          updateUrlFn={id => `/admin/zones/${id}`}
          deleteUrlFn={id => `/admin/zones/${id}`}
          fields={['name', 'hqAddress']}
          onSelect={onZoneSelected} selectedId={selected.zoneId} />
      );
      case 2: return (
        <StepList key={`sector_${selected.zoneId}`} title="Sectors" Icon={LayoutGrid} color="#2E7D32"
          officerTitle={LEVEL_OFFICER_TITLE[2]} officerRanks={LEVEL_RANKS[2]}
          fetchUrl={`/admin/zones/${selected.zoneId}/sectors`}
          createUrl={`/admin/zones/${selected.zoneId}/sectors`}
          updateUrlFn={id => `/admin/sectors/${id}`}
          deleteUrlFn={id => `/admin/sectors/${id}`}
          fields={['name', 'hqAddress']}
          onSelect={onSectorSelected} selectedId={selected.sectorId} />
      );
      case 3: return (
        <StepList key={`gp_${selected.sectorId}`} title="Gram Panchayats" Icon={Landmark} color="#6D4C41"
          officerTitle="" officerRanks={[]}
          fetchUrl={`/admin/sectors/${selected.sectorId}/gram-panchayats`}
          createUrl={`/admin/sectors/${selected.sectorId}/gram-panchayats`}
          updateUrlFn={id => `/admin/gram-panchayats/${id}`}
          deleteUrlFn={id => `/admin/gram-panchayats/${id}`}
          fields={['name', 'address']}
          onSelect={onGPSelected} selectedId={selected.gpId} />
      );
      case 4: return <CenterStep key={`center_${selected.gpId}`} gpId={selected.gpId} />;
      default: return null;
    }
  };

  return (
    <>
      <style>{`
        @keyframes spin { to { transform: rotate(360deg); } }
        @keyframes slideUp { from { opacity:0; transform:translateY(16px); } to { opacity:1; transform:translateY(0); } }
        * { box-sizing: border-box; }
        ::-webkit-scrollbar { width:5px; height:5px; }
        ::-webkit-scrollbar-track { background:${C.surface}; }
        ::-webkit-scrollbar-thumb { background:${C.border}; border-radius:4px; }
      `}</style>
      <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: C.bg, fontFamily: "'Tiro Devanagari Hindi', Georgia, serif" }}>
        <StepBar
          currentStep={step} onTap={goToStep}
          szName={selected.szName} zoneName={selected.zoneName}
          sectorName={selected.sectorName} gpName={selected.gpName}
        />
        {step > 0 && (
          <Breadcrumb
            step={step}
            szName={selected.szName} zoneName={selected.zoneName}
            sectorName={selected.sectorName} gpName={selected.gpName}
            onTap={goToStep}
          />
        )}
        <div style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
          {renderStep()}
        </div>
      </div>
    </>
  );
}
