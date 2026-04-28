import { useState, useEffect, useRef, useCallback } from 'react';
import {
  Plus, Upload, Pencil, Trash2, Search, X, Save, RefreshCw,
  Shield, ShieldOff, Badge, Phone, MapPin, Building2,
  Star, CheckCircle, AlertTriangle, ChevronLeft, ChevronRight,
  UserPlus, UserMinus, Vote, Lock, Bus,
  FileSpreadsheet, FileText, Info, Layers, Grid, CheckSquare, Square,
  Download
} from 'lucide-react';
import { adminApi } from '../../api/endpoints';
import { RANKS, debounce } from '../../utils/helpers';
import { useAuthStore } from '../../store/authStore';
import toast from 'react-hot-toast';

// ── Constants ─────────────────────────────────────────────────────────────────
const PAGE_SIZE = 50;

const ARMED_VALS = new Set(['1', 'yes', 'हाँ', 'han', 'sastra', 'सशस्त्र', 'armed', 'true']);

const REQUIRED_HEADERS = [
  { col: 'pno', label: 'PNO / बैज नंबर', req: true },
  { col: 'name', label: 'नाम', req: true },
  { col: 'mobile', label: 'मोबाइल', req: false },
  { col: 'thana', label: 'थाना', req: false },
  { col: 'district', label: 'जिला', req: false },
  { col: 'rank', label: 'पद / रैंक', req: false },
  { col: 'sastra', label: 'सशस्त्र (1/yes/हाँ)', req: false },
];

const ALL_RANKS = ['All', ...RANKS];

// ── Color helpers ─────────────────────────────────────────────────────────────
const colors = {
  bg: '#FDF6E3',
  surface: '#F5E6C8',
  primary: '#8B6914',
  accent: '#B8860B',
  dark: '#4A3000',
  subtle: '#AA8844',
  border: '#D4A843',
  error: '#C0392B',
  success: '#2D6A1E',
  info: '#1A5276',
  armed: '#1B5E20',
  unarmed: '#37474F',
};

// ── Upload Progress State (singleton-like) ────────────────────────────────────
// We use a simple module-level event system
let _uploadListeners = [];
let _uploadState = { phase: 'idle', parsePct: 0, hashPct: 0, insertPct: 0, added: 0, total: 0, statusMsg: '', errorMsg: '' };

function setUploadState(patch) {
  _uploadState = { ..._uploadState, ...patch };
  _uploadListeners.forEach(fn => fn(_uploadState));
}

function resetUpload() {
  setUploadState({ phase: 'idle', parsePct: 0, hashPct: 0, insertPct: 0, added: 0, total: 0, statusMsg: '', errorMsg: '' });
}

function useUploadProgress() {
  const [state, setState] = useState(_uploadState);
  useEffect(() => {
    const fn = (s) => setState({ ...s });
    _uploadListeners.push(fn);
    return () => { _uploadListeners = _uploadListeners.filter(f => f !== fn); };
  }, []);
  return state;
}

// ── Upload Progress Banner ────────────────────────────────────────────────────
function UploadProgressBanner() {
  const up = useUploadProgress();
  if (up.phase === 'idle') return null;

  const isErr = up.phase === 'error';
  const isDone = up.phase === 'done';
  const overall = Math.min(1, (up.parsePct * 0.15) + (up.hashPct * 0.30) + (up.insertPct * 0.55));
  const color = isErr ? colors.error : isDone ? colors.success : colors.primary;

  return (
    <div style={{
      position: 'fixed', bottom: 20, left: 16, right: 16, zIndex: 9999,
      background: colors.dark, borderRadius: 14,
      border: `1.5px solid ${color}88`,
      padding: '12px 14px', boxShadow: '0 8px 32px rgba(0,0,0,0.3)',
      maxWidth: 520, margin: '0 auto',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
        <div style={{ width: 24, height: 24, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          {isErr ? <AlertTriangle size={20} color={colors.error} />
            : isDone ? <CheckCircle size={20} color={colors.success} />
              : <UploadSpinner color={color} />}
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ color, fontWeight: 800, fontSize: 13 }}>
            {isErr ? 'अपलोड विफल' : isDone ? 'अपलोड पूर्ण!' : 'बल्क अपलोड'}
          </div>
          <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: 11, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {up.statusMsg}
          </div>
        </div>
        {up.total > 0 && (
          <span style={{ color, fontWeight: 900, fontSize: 12 }}>{up.added}/{up.total}</span>
        )}
        {(isDone || isErr) && (
          <button onClick={resetUpload} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 4 }}>
            <X size={16} color="rgba(255,255,255,0.5)" />
          </button>
        )}
      </div>

      {/* Main progress bar */}
      <div style={{ background: 'rgba(255,255,255,0.1)', borderRadius: 4, height: 6, overflow: 'hidden', marginBottom: (!isErr && !isDone) ? 8 : 0 }}>
        <div style={{ width: `${overall * 100}%`, height: '100%', background: isErr ? colors.error : isDone ? colors.success : color, borderRadius: 4, transition: 'width 0.3s ease' }} />
      </div>

      {/* Phase breakdown */}
      {!isErr && !isDone && (
        <div style={{ display: 'flex', gap: 8 }}>
          {[['Parse', up.parsePct, colors.accent], ['Hash', up.hashPct, colors.info], ['Insert', up.insertPct, colors.primary]].map(([label, pct, c]) => (
            <div key={label} style={{ flex: 1 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 2 }}>
                <span style={{ color: 'rgba(255,255,255,0.4)', fontSize: 9 }}>{label}</span>
                <span style={{ color: c, fontSize: 9, fontWeight: 700 }}>{Math.round(pct * 100)}%</span>
              </div>
              <div style={{ background: `${c}25`, borderRadius: 2, height: 3, overflow: 'hidden' }}>
                <div style={{ width: `${pct * 100}%`, height: '100%', background: pct >= 1 ? colors.success : c, transition: 'width 0.3s ease' }} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function UploadSpinner({ color }) {
  return (
    <div style={{
      width: 18, height: 18, border: `2px solid transparent`,
      borderTop: `2px solid ${color}`,
      borderRight: `2px solid ${color}`,
      borderRadius: '50%',
      animation: 'spin 1s linear infinite',
    }} />
  );
}

// ── Field Component ───────────────────────────────────────────────────────────
function Field({ label, value, onChange, placeholder, type = 'text', icon: Icon, required, as: As = 'input', children }) {
  return (
    <div style={{ marginBottom: 10 }}>
      <label style={{ fontSize: 11, color: colors.subtle, fontWeight: 600, display: 'block', marginBottom: 4 }}>{label}</label>
      <div style={{ position: 'relative' }}>
        {Icon && (
          <div style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none' }}>
            <Icon size={16} color={colors.primary} />
          </div>
        )}
        {As === 'select' ? (
          <select value={value} onChange={onChange} style={fieldStyle(!!Icon)}>
            {children}
          </select>
        ) : (
          <input
            type={type} value={value} onChange={onChange}
            placeholder={placeholder}
            style={fieldStyle(!!Icon)}
          />
        )}
      </div>
    </div>
  );
}

function fieldStyle(hasIcon) {
  return {
    width: '100%', boxSizing: 'border-box',
    padding: `9px 12px 9px ${hasIcon ? 34 : 12}px`,
    border: `1px solid ${colors.border}`,
    borderRadius: 10, fontSize: 13, color: colors.dark,
    background: 'white', outline: 'none',
    fontFamily: 'inherit',
  };
}

// ── Armed Toggle ──────────────────────────────────────────────────────────────
function ArmedToggle({ value, onChange }) {
  const c = value ? colors.armed : colors.unarmed;
  return (
    <div style={{
      marginBottom: 10, padding: '12px 14px',
      background: value ? `${colors.armed}0F` : `${colors.unarmed}0A`,
      borderRadius: 10, border: `1px solid ${value ? colors.armed + '4D' : colors.border + '80'}`,
      display: 'flex', alignItems: 'center', gap: 10,
    }}>
      {value ? <Shield size={20} color={c} /> : <ShieldOff size={20} color={c} />}
      <div style={{ flex: 1 }}>
        <div style={{ fontWeight: 700, fontSize: 13, color: c }}>
          {value ? 'सशस्त्र पुलिस' : 'निःशस्त्र पुलिस'}
        </div>
        <div style={{ fontSize: 10, color: colors.subtle }}>
          {value ? 'Armed Police' : 'Unarmed Police'}
        </div>
      </div>
      <div
        onClick={() => onChange(!value)}
        style={{
          width: 44, height: 24, borderRadius: 12, cursor: 'pointer', position: 'relative',
          background: value ? colors.armed : '#9E9E9E', transition: 'background 0.2s',
        }}
      >
        <div style={{
          position: 'absolute', top: 3, left: value ? 23 : 3,
          width: 18, height: 18, background: 'white', borderRadius: '50%',
          boxShadow: '0 1px 3px rgba(0,0,0,0.3)', transition: 'left 0.2s',
        }} />
      </div>
    </div>
  );
}

// ── Confirm Dialog ────────────────────────────────────────────────────────────
function ConfirmDialog({ open, title, message, confirmText = 'Confirm', danger = true, onConfirm, onCancel }) {
  if (!open) return null;
  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 10000, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,0.5)' }}>
      <div style={{ background: colors.bg, borderRadius: 14, border: `1.2px solid ${colors.error}`, padding: '20px 24px', maxWidth: 380, width: '90%', boxShadow: '0 8px 32px rgba(0,0,0,0.2)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
          <AlertTriangle size={20} color={colors.error} />
          <span style={{ fontWeight: 800, fontSize: 15, color: colors.error }}>{title}</span>
        </div>
        <p style={{ color: colors.dark, fontSize: 13, lineHeight: 1.6, marginBottom: 20 }}>{message}</p>
        <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button onClick={onCancel} style={{ padding: '8px 16px', border: `1px solid ${colors.border}`, borderRadius: 8, background: 'transparent', color: colors.subtle, cursor: 'pointer', fontSize: 13 }}>रद्द</button>
          <button onClick={onConfirm} style={{ padding: '8px 16px', background: colors.error, color: 'white', border: 'none', borderRadius: 8, cursor: 'pointer', fontSize: 13, fontWeight: 700 }}>{confirmText}</button>
        </div>
      </div>
    </div>
  );
}

// ── Dialog Wrapper ────────────────────────────────────────────────────────────
function Dialog({ open, title, icon: Icon, onClose, children, maxWidth = 460 }) {
  if (!open) return null;
  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 9000, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,0.5)', padding: '16px 12px' }}>
      <div style={{
        background: colors.bg, borderRadius: 16, border: `1.2px solid ${colors.border}`,
        width: '100%', maxWidth, maxHeight: '92vh', display: 'flex', flexDirection: 'column',
        boxShadow: `0 8px 24px ${colors.primary}26`,
      }}>
        {/* Header */}
        <div style={{ background: colors.dark, borderRadius: '15px 15px 0 0', padding: '13px 12px 13px 16px', display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0 }}>
          {Icon && (
            <div style={{ background: `${colors.primary}40`, borderRadius: 7, padding: 6 }}>
              <Icon size={16} color={colors.border} />
            </div>
          )}
          <span style={{ flex: 1, color: 'white', fontWeight: 700, fontSize: 15 }}>{title}</span>
          <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 4 }}>
            <X size={20} color="rgba(255,255,255,0.6)" />
          </button>
        </div>
        <div style={{ overflow: 'auto', flex: 1 }}>
          {children}
        </div>
      </div>
    </div>
  );
}

// ── Staff Form Dialog ─────────────────────────────────────────────────────────
function StaffFormDialog({ initial, onSave, onClose }) {
  const isEdit = !!initial;
  const [form, setForm] = useState({
    name: '', pno: '', mobile: '', thana: '', district: '', rank: '', isArmed: false,
    ...(initial || {}),
  });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k) => (e) => setForm(p => ({ ...p, [k]: typeof e === 'boolean' ? e : e.target.value }));

  const handleSave = async () => {
    if (!form.pno.trim() || !form.name.trim()) { setErr('PNO और नाम आवश्यक'); return; }
    setSaving(true); setErr('');
    try { await onSave(form); onClose(); }
    catch (e) { setErr(e.message || 'Save failed'); setSaving(false); }
  };

  return (
    <Dialog open title={isEdit ? 'स्टाफ संपादित करें' : 'स्टाफ जोड़ें'} icon={isEdit ? Pencil : UserPlus} onClose={onClose}>
      <div style={{ padding: '16px 20px 0' }}>
        {err && <div style={{ background: '#fdecea', border: `1px solid ${colors.error}33`, borderRadius: 8, padding: '8px 12px', color: colors.error, fontSize: 12, marginBottom: 10 }}>{err}</div>}
        {!isEdit && <Field label="PNO *" value={form.pno} onChange={set('pno')} placeholder="Badge number" icon={Badge} />}
        {isEdit && <Field label="PNO *" value={form.pno} onChange={set('pno')} placeholder="Badge number" icon={Badge} />}
        <Field label="पूरा नाम *" value={form.name} onChange={set('name')} placeholder="Officer name" icon={UserPlus} />
        <Field label="मोबाइल" value={form.mobile} onChange={set('mobile')} placeholder="Mobile number" icon={Phone} type="tel" />
        <Field label="थाना" value={form.thana} onChange={set('thana')} placeholder="Police station" icon={MapPin} />
        <Field label="जिला" value={form.district} onChange={set('district')} placeholder="District" icon={Building2} />
        <Field label="पद/रैंक" value={form.rank} onChange={set('rank')} placeholder="Rank" icon={Star} />
        <ArmedToggle value={!!form.isArmed} onChange={(v) => setForm(p => ({ ...p, isArmed: v }))} />
      </div>
      <div style={{ padding: '0 20px 20px', display: 'flex', gap: 12 }}>
        <button onClick={onClose} disabled={saving} style={{ flex: 1, padding: '13px', border: `1px solid ${colors.border}`, borderRadius: 10, background: 'transparent', color: colors.subtle, cursor: 'pointer', fontSize: 13 }}>रद्द</button>
        <button onClick={handleSave} disabled={saving} style={{ flex: 1, padding: '13px', background: colors.primary, color: 'white', border: 'none', borderRadius: 10, cursor: 'pointer', fontSize: 13, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          {saving ? <Spinner /> : (isEdit ? 'अपडेट' : 'जोड़ें')}
        </button>
      </div>
    </Dialog>
  );
}

// ── Assign Dialog ─────────────────────────────────────────────────────────────
function AssignDialog({ title, staffCard, onAssign, onClose, assignLabel = 'ड्यूटी असाइन करें' }) {
  const [centerQ, setCenterQ] = useState('');
  const [centerList, setCenterList] = useState([]);
  const [cLoading, setCLoading] = useState(false);
  const [cPage, setCPage] = useState(1);
  const [cHasMore, setCHasMore] = useState(true);
  const [selectedCenter, setSelectedCenter] = useState(null);
  const [busNo, setBusNo] = useState('');
  const [saving, setSaving] = useState(false);
  const scrollRef = useRef();

  const loadCenters = useCallback(async (reset = false, q = centerQ) => {
    if (cLoading) return;
    const pg = reset ? 1 : cPage;
    if (!reset && !cHasMore) return;
    setCLoading(true);
    try {
      const res = await adminApi.getCenters({ q, page: pg, limit: 30 });
      const w = res.data || {};
      const data = Array.isArray(w.data) ? w.data : Array.isArray(w) ? w : [];
      const total = w.total || data.length;
      setCenterList(prev => reset ? data : [...prev, ...data]);
      setCHasMore((reset ? data.length : centerList.length + data.length) < total);
      setCPage(pg + 1);
    } catch (_) { }
    setCLoading(false);
  }, [cLoading, cPage, cHasMore, centerQ, centerList.length]);

  useEffect(() => { loadCenters(true, ''); }, []);

  const debouncedSearch = useCallback(debounce((v) => loadCenters(true, v), 350), []);

  const handleScroll = (e) => {
    const el = e.target;
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 80) loadCenters();
  };

  const doAssign = async () => {
    if (!selectedCenter) return;
    setSaving(true);
    try { await onAssign(selectedCenter, busNo); onClose(); }
    catch (e) { toast.error(e.message || 'Failed'); setSaving(false); }
  };

  return (
    <Dialog open title={title} icon={Vote} onClose={onClose} maxWidth={500}>
      <div style={{ padding: '16px' }}>
        {staffCard && <div style={{ marginBottom: 16 }}>{staffCard}</div>}

        {selectedCenter && (
          <div style={{ background: `${colors.success}0D`, border: `1px solid ${colors.success}4D`, borderRadius: 10, padding: 10, marginBottom: 12, display: 'flex', alignItems: 'flex-start', gap: 8 }}>
            <CheckCircle size={18} color={colors.success} style={{ flexShrink: 0, marginTop: 1 }} />
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 700, fontSize: 13, color: colors.dark }}>{selectedCenter.name}</div>
              <div style={{ fontSize: 11, color: colors.subtle }}>{selectedCenter.thana} • {selectedCenter.gpName}</div>
            </div>
            <button onClick={() => setSelectedCenter(null)} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 2 }}>
              <X size={14} color={colors.subtle} />
            </button>
          </div>
        )}

        <SectionLabel>मतदान केंद्र चुनें</SectionLabel>

        {/* Center Search */}
        <div style={{ position: 'relative', marginBottom: 8 }}>
          <Search size={16} color={colors.subtle} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none' }} />
          <input
            placeholder="केंद्र, थाना, GP से खोजें..."
            onChange={e => { setCenterQ(e.target.value); debouncedSearch(e.target.value); }}
            style={{ ...fieldStyle(true), width: '100%', boxSizing: 'border-box' }}
          />
        </div>

        {/* Center List */}
        <div ref={scrollRef} onScroll={handleScroll} style={{ height: 200, border: `1px solid ${colors.border}`, borderRadius: 10, overflow: 'auto', background: 'white', marginBottom: 14 }}>
          {cLoading && centerList.length === 0
            ? <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}><Spinner color={colors.primary} /></div>
            : centerList.length === 0
              ? <div style={{ textAlign: 'center', padding: 24, color: colors.subtle, fontSize: 12 }}>कोई केंद्र नहीं मिला</div>
              : centerList.map(c => {
                const isSel = selectedCenter?.id === c.id;
                const type = String(c.centerType || 'C');
                const tc = type === 'A' ? colors.error : type === 'B' ? colors.accent : colors.info;
                return (
                  <div key={c.id} onClick={() => setSelectedCenter(c)}
                    style={{ margin: '4px 6px', padding: 10, borderRadius: 8, cursor: 'pointer', border: `${isSel ? 1.5 : 1}px solid ${isSel ? colors.primary : colors.border + '66'}`, background: isSel ? `${colors.primary}14` : 'transparent', display: 'flex', alignItems: 'center', gap: 10, transition: 'all 0.12s' }}>
                    <div style={{ width: 28, height: 28, borderRadius: '50%', background: `${tc}1E`, border: `1px solid ${tc}66`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                      <span style={{ color: tc, fontSize: 10, fontWeight: 900 }}>{type}</span>
                    </div>
                    <div style={{ flex: 1, overflow: 'hidden' }}>
                      <div style={{ fontWeight: 700, fontSize: 13, color: isSel ? colors.primary : colors.dark, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.name}</div>
                      <div style={{ fontSize: 10, color: colors.subtle, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.thana} • {c.gpName}</div>
                    </div>
                    {isSel && <CheckCircle size={18} color={colors.primary} />}
                  </div>
                );
              })
          }
          {cLoading && centerList.length > 0 && (
            <div style={{ padding: 10, display: 'flex', justifyContent: 'center' }}><Spinner size={18} /></div>
          )}
        </div>

        <SectionLabel>बस संख्या (वैकल्पिक)</SectionLabel>
        <div style={{ position: 'relative', marginBottom: 0 }}>
          <Bus size={16} color={colors.primary} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none' }} />
          <input value={busNo} onChange={e => setBusNo(e.target.value)} placeholder="बस नंबर" style={{ ...fieldStyle(true), width: '100%', boxSizing: 'border-box' }} />
        </div>
      </div>

      <div style={{ padding: '0 16px 16px', display: 'flex', gap: 12 }}>
        <button onClick={onClose} style={{ flex: 1, padding: 13, border: `1px solid ${colors.border}`, borderRadius: 10, background: 'transparent', color: colors.subtle, cursor: 'pointer', fontSize: 13 }}>रद्द</button>
        <button onClick={doAssign} disabled={!selectedCenter || saving} style={{ flex: 1, padding: 13, background: !selectedCenter ? colors.subtle : colors.primary, color: 'white', border: 'none', borderRadius: 10, cursor: !selectedCenter ? 'default' : 'pointer', fontSize: 13, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          {saving ? <Spinner /> : assignLabel}
        </button>
      </div>
    </Dialog>
  );
}

const downloadSampleCSV = () => {
  const headers = REQUIRED_HEADERS.map(h => h.col);

  // 👉 Example data row (customize based on your columns)
  const sampleRow = headers.map((col) => {
    switch (col.toLowerCase()) {
      case 'name':
        return 'Ishant Tyagi';
      case 'mobile':
      case 'phone':
        return '93183XXXXX';
      case 'rank':
        return 'SI';
      case 'sastra':
      case 'is_armed':
        return '1'; // armed example
      case 'booth':
      case 'booth_no':
        return '101';
      case 'zone':
        return 'Zone 1';
      default:
        return 'Sample';
    }
  });

  const csvContent =
    headers.join(',') + '\n' +   // header row
    sampleRow.join(',');         // sample data row

  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });

  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = 'sample_upload_format.csv';

  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
};

// ── Upload Hint + File Preview Dialog ────────────────────────────────────────
function UploadHintDialog({ onConfirm, onClose }) {
  return (
    <Dialog open title="फ़ाइल अपलोड करें" icon={Upload} onClose={onClose} maxWidth={420}>
      <div style={{ padding: '16px' }}>
        <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
          {[['Excel', '.xlsx / .xls', colors.success], ['CSV', '.csv', colors.info]].map(([fmt, ext, c]) => (
            <div className='cursor-pointer' key={fmt} onClick={downloadSampleCSV} style={{ flex: 1, padding: '8px 10px', background: `${c}12`, border: `1px solid ${c}40`, borderRadius: 8, display: 'flex', alignItems: 'center', gap: 8 }}>
              <FileSpreadsheet size={16} color={c} />
              <div>
                <div style={{ color: c, fontWeight: 800, fontSize: 12 }}>{fmt}</div>
                <div style={{ color: colors.subtle, fontSize: 10 }}>{ext}</div>
              </div>
            </div>
          ))}
        </div>

        <div style={{ fontWeight: 800, fontSize: 13, color: colors.dark, marginBottom: 8 }}>आवश्यक कॉलम / Required Columns</div>
        <div style={{ background: 'white', borderRadius: 10, border: `1px solid ${colors.border}66`, overflow: 'hidden', marginBottom: 10 }}>
          {REQUIRED_HEADERS.map((h, idx) => (
            <div key={h.col} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 12px', background: idx % 2 === 0 ? 'transparent' : `${colors.surface}4D` }}>
              <code style={{ background: '#2C3E5014', color: '#2C3E50', padding: '2px 6px', borderRadius: 4, fontSize: 11, fontWeight: 700 }}>{h.col}</code>
              <span style={{ flex: 1, color: colors.dark, fontSize: 12 }}>{h.label}</span>
              <span style={{ padding: '2px 6px', borderRadius: 4, fontSize: 10, fontWeight: 700, background: h.req ? `${colors.error}1A` : `${colors.success}1A`, color: h.req ? colors.error : colors.success }}>
                {h.req ? 'ज़रूरी' : 'वैकल्पिक'}
              </span>
            </div>
          ))}
        </div>

        <div style={{ background: `${colors.armed}0F`, border: `1px solid ${colors.armed}33`, borderRadius: 8, padding: 10, display: 'flex', gap: 8, marginBottom: 4 }}>
          <Info size={14} color={colors.armed} style={{ flexShrink: 0, marginTop: 1 }} />
          <span style={{ color: colors.dark, fontSize: 11 }}>sastra कॉलम में: 1, yes, हाँ, सशस्त्र, armed → सशस्त्र<br />बाकी सब या खाली → निःशस्त्र</span>
        </div>
      </div>
      <div style={{ padding: '0 16px 16px', display: 'flex', gap: 12 }}>
        <button onClick={onClose} style={{ flex: 1, padding: 12, border: `1px solid ${colors.border}`, borderRadius: 10, background: 'transparent', color: colors.subtle, cursor: 'pointer' }}>रद्द</button>
        <button onClick={onConfirm} style={{ flex: 1, padding: 12, background: colors.primary, color: 'white', border: 'none', borderRadius: 10, cursor: 'pointer', fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          <Upload size={15} /> फ़ाइल चुनें
        </button>
      </div>
    </Dialog>
  );
}

// ── Preview Dialog ─────────────────────────────────────────────────────────────
function PreviewDialog({ rows: initialRows, onUpload, onClose }) {
  const [workRows, setWorkRows] = useState([...initialRows]);
  const [q, setQ] = useState('');
  const [page, setPage] = useState(1);
  const ppSize = 50;

  const filtered = q === '' ? workRows : workRows.filter(r =>
    (r.name || '').toLowerCase().includes(q.toLowerCase()) ||
    (r.pno || '').toLowerCase().includes(q.toLowerCase()) ||
    (r.thana || '').toLowerCase().includes(q.toLowerCase())
  );
  const totalPages = Math.max(1, Math.ceil(filtered.length / ppSize));
  const pg = Math.min(page, totalPages);
  const pageRows = filtered.slice((pg - 1) * ppSize, pg * ppSize);

  const valid = workRows.filter(r => (r.pno || '').trim() && (r.name || '').trim()).length;
  const armedCount = workRows.filter(r => r.is_armed === 1).length;

  const removeRow = (row) => {
    setWorkRows(p => p.filter(r => r !== row));
  };

  return (
    <Dialog open title={`Preview — ${workRows.length}/${initialRows.length} rows`} icon={FileText} onClose={onClose} maxWidth={560}>
      {/* Stats */}
      <div style={{ padding: '10px 14px 4px', display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center' }}>
        <Pill label={`${valid} मान्य`} color={colors.success} />
        <Pill label={`${workRows.length - valid} त्रुटि`} color={colors.error} />
        <Pill label={`🔫 ${armedCount} सशस्त्र`} color={colors.armed} />
        <Pill label={`🛡 ${workRows.length - armedCount} निःशस्त्र`} color={colors.unarmed} />
        <div style={{ marginLeft: 'auto', color: colors.subtle, fontSize: 10 }}>× से हटाएं</div>
      </div>

      {/* Search */}
      <div style={{ padding: '4px 12px 8px', position: 'relative' }}>
        <Search size={15} color={colors.subtle} style={{ position: 'absolute', left: 22, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none' }} />
        <input value={q} onChange={e => { setQ(e.target.value); setPage(1); }} placeholder="नाम, PNO, थाना से खोजें..."
          style={{ ...fieldStyle(true), width: '100%', boxSizing: 'border-box' }} />
      </div>

      {/* Row list */}
      <div style={{ maxHeight: 360, overflowY: 'auto', padding: '0 12px' }}>
        {pageRows.length === 0
          ? <div style={{ textAlign: 'center', padding: 24, color: colors.subtle }}>कोई row नहीं</div>
          : pageRows.map((r, i) => {
            const isOk = (r.pno || '').trim() && (r.name || '').trim();
            const armed = r.is_armed === 1;
            return (
              <div key={i} style={{
                marginBottom: 6, borderRadius: 9,
                border: `1px solid ${isOk ? colors.border + '66' : colors.error + '59'}`,
                background: isOk ? 'white' : `${colors.error}0A`,
                display: 'flex', overflow: 'hidden',
              }}>
                <div style={{ width: 32, display: 'flex', alignItems: 'center', justifyContent: 'center', background: isOk ? `${colors.surface}99` : `${colors.error}0F`, flexShrink: 0 }}>
                  <span style={{ color: isOk ? colors.subtle : colors.error, fontSize: 10, fontWeight: 700 }}>{r._row}</span>
                </div>
                <div style={{ flex: 1, padding: '8px 10px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
                    <span style={{ fontWeight: 700, fontSize: 13, color: (r.name || '').trim() ? colors.dark : colors.error, flex: 1 }}>
                      {(r.name || '').trim() || '⚠ नाम आवश्यक'}
                    </span>
                    <span style={{ padding: '2px 6px', borderRadius: 4, fontSize: 9, fontWeight: 700, background: armed ? `${colors.armed}1E` : `${colors.unarmed}14`, color: armed ? colors.armed : colors.unarmed }}>
                      {armed ? '🔫 सशस्त्र' : '🛡 निःशस्त्र'}
                    </span>
                  </div>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                    <MiniTag icon={Badge} text={(r.pno || '').trim() ? `PNO: ${r.pno}` : '⚠ PNO आवश्यक'} color={(r.pno || '').trim() ? undefined : colors.error} />
                    {(r.mobile || '').trim() && <MiniTag icon={Phone} text={r.mobile} />}
                    {(r.thana || '').trim() && <MiniTag icon={MapPin} text={r.thana} />}
                    {(r.rank || '').trim() && <MiniTag icon={Star} text={r.rank} color={colors.info} />}
                  </div>
                </div>
                <button onClick={() => removeRow(r)} style={{ width: 36, background: 'none', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <X size={14} color={colors.error} />
                </button>
              </div>
            );
          })
        }
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div style={{ padding: '8px 12px', borderTop: `1px solid ${colors.border}4D`, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
          <PageBtn icon={ChevronLeft} enabled={pg > 1} onClick={() => setPage(pg - 1)} />
          <span style={{ padding: '5px 12px', background: `${colors.primary}1A`, borderRadius: 8, border: `1px solid ${colors.border}66`, fontSize: 12, fontWeight: 700, color: colors.dark }}>
            {pg} / {totalPages} ({filtered.length} rows)
          </span>
          <PageBtn icon={ChevronRight} enabled={pg < totalPages} onClick={() => setPage(pg + 1)} />
        </div>
      )}

      {/* Actions */}
      <div style={{ padding: '8px 14px 16px', display: 'flex', gap: 12 }}>
        <button onClick={onClose} style={{ flex: 1, padding: 13, border: `1px solid ${colors.border}`, borderRadius: 10, background: 'transparent', color: colors.subtle, cursor: 'pointer' }}>रद्द</button>
        <button onClick={() => onUpload(workRows.filter(r => (r.pno || '').trim() && (r.name || '').trim()).map(({ _row, ...rest }) => rest))} disabled={valid === 0}
          style={{ flex: 1, padding: 13, background: valid === 0 ? colors.subtle : colors.primary, color: 'white', border: 'none', borderRadius: 10, cursor: valid === 0 ? 'default' : 'pointer', fontWeight: 700, fontSize: 13, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          <Upload size={15} /> {valid} अपलोड करें
        </button>
      </div>
    </Dialog>
  );
}

// ── Small helpers ─────────────────────────────────────────────────────────────
function Spinner({ color = 'white', size = 18 }) {
  return <div style={{ width: size, height: size, border: `2px solid transparent`, borderTop: `2px solid ${color}`, borderRadius: '50%', animation: 'spin 0.8s linear infinite', flexShrink: 0 }} />;
}
function Pill({ label, color }) {
  return <span style={{ padding: '4px 10px', borderRadius: 20, background: `${color}1A`, border: `1px solid ${color}4D`, fontSize: 11, fontWeight: 700, color }}>{label}</span>;
}
function MiniTag({ icon: Icon, text, color = colors.subtle }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color, fontSize: 10 }}>
      <Icon size={10} /> {text}
    </span>
  );
}
function SectionLabel({ children }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 8 }}>
      <div style={{ width: 3, height: 14, background: colors.primary, borderRadius: 2 }} />
      <span style={{ color: colors.dark, fontSize: 13, fontWeight: 800 }}>{children}</span>
    </div>
  );
}
function PageBtn({ icon: Icon, enabled, onClick }) {
  return (
    <button onClick={enabled ? onClick : undefined} style={{ width: 32, height: 32, borderRadius: 8, border: `1px solid ${enabled ? colors.border : '#ccc'}`, background: enabled ? `${colors.primary}1A` : '#f5f5f5', cursor: enabled ? 'pointer' : 'default', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <Icon size={18} color={enabled ? colors.primary : '#9E9E9E'} />
    </button>
  );
}
function Badge2({ label, color }) {
  return <span style={{ padding: '2px 7px', borderRadius: 7, background: `${color}1A`, border: `1px solid ${color}4D`, fontSize: 10, fontWeight: 800, color }}>{label}</span>;
}

// ── CSV / Excel parsing helpers ───────────────────────────────────────────────
function parseCSVLine(line) {
  const result = [];
  let inQuote = false, buf = '';
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (inQuote && i + 1 < line.length && line[i + 1] === '"') { buf += '"'; i++; }
      else inQuote = !inQuote;
    } else if (ch === ',' && !inQuote) { result.push(buf.trim()); buf = ''; }
    else buf += ch;
  }
  result.push(buf.trim());
  return result;
}

function detectCols(headers) {
  let iPno, iName, iMob, iThana, iDist, iRank, iArmed;
  headers.forEach((h, ci) => {
    const v = h.toLowerCase();
    if (iPno == null && (v.includes('pno') || v.includes('p.no'))) iPno = ci;
    if (iName == null && (v.includes('name') || v.includes('नाम'))) iName = ci;
    if (iMob == null && (v.includes('mobile') || v.includes('mob') || v.includes('phone'))) iMob = ci;
    if (iThana == null && (v.includes('thana') || v.includes('थाना') || v === 'ps')) iThana = ci;
    if (iDist == null && (v.includes('district') || v.includes('dist') || v.includes('जिला'))) iDist = ci;
    if (iRank == null && (v.includes('rank') || v.includes('post') || v.includes('पद'))) iRank = ci;
    if (iArmed == null && (v.includes('sastra') || v.includes('armed') || v.includes('weapon') || v.includes('सशस्त्र'))) iArmed = ci;
  });
  return {
    iPno: iPno ?? 0, iName: iName ?? 1, iMob: iMob ?? 2,
    iThana: iThana ?? 3, iDist: iDist ?? 4, iRank: iRank ?? 5, iArmed,
  };
}

async function parseCSV(bytes) {
  const text = new TextDecoder('utf-8').decode(new Uint8Array(bytes)).replace(/^\uFEFF/, '');
  const lines = text.split(/\r?\n/);
  if (lines.length < 2) return [];
  const headers = parseCSVLine(lines[0]).map(h => h.toLowerCase());
  const cols = detectCols(headers);
  const cell = (row, idx) => idx != null && idx < row.length ? row[idx].trim() : '';
  const result = [];
  lines.slice(1).forEach((line, ri) => {
    if (!line.trim()) return;
    const row = parseCSVLine(line);
    const pno = cell(row, cols.iPno), name = cell(row, cols.iName);
    if (!pno && !name) return;
    const armedRaw = cols.iArmed != null ? cell(row, cols.iArmed).toLowerCase() : '';
    result.push({ pno, name, mobile: cell(row, cols.iMob), thana: cell(row, cols.iThana), district: cell(row, cols.iDist), rank: cell(row, cols.iRank), is_armed: ARMED_VALS.has(armedRaw) ? 1 : 0, _row: ri + 2 });
  });
  return result;
}

async function parseExcel(bytes) {
  // Dynamically import xlsx (SheetJS) if available, else fallback to empty
  try {
    const XLSX = await import('https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs').catch(() => null);
    if (!XLSX) return { rows: [], needSheetPick: false, sheets: [] };
    const wb = XLSX.read(new Uint8Array(bytes), { type: 'array' });
    const sheetName = wb.SheetNames[0];
    const ws = wb.Sheets[sheetName];
    const raw = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });
    if (raw.length < 2) return { rows: [], sheets: wb.SheetNames };
    const headers = raw[0].map(h => String(h || '').toLowerCase());
    const cols = detectCols(headers);
    const cell = (row, idx) => idx != null && idx < row.length ? String(row[idx] ?? '').trim() : '';
    const rows = [];
    raw.slice(1).forEach((row, ri) => {
      if (row.every(c => !String(c ?? '').trim())) return;
      const pno = cell(row, cols.iPno), name = cell(row, cols.iName);
      if (!pno && !name) return;
      const armedRaw = cols.iArmed != null ? cell(row, cols.iArmed).toLowerCase() : '';
      rows.push({ pno, name, mobile: cell(row, cols.iMob), thana: cell(row, cols.iThana), district: cell(row, cols.iDist), rank: cell(row, cols.iRank), is_armed: ARMED_VALS.has(armedRaw) ? 1 : 0, _row: ri + 2 });
    });
    return { rows, sheets: wb.SheetNames };
  } catch (e) {
    return { rows: [], sheets: [] };
  }
}

// ── Background SSE upload ─────────────────────────────────────────────────────
async function startBackgroundUpload(rows, token) {

  const baseUrl = (await import('../../api/client')).default.defaults.baseURL || '';
  setUploadState({ phase: 'uploading', total: rows.length, added: 0, parsePct: 0, hashPct: 0, insertPct: 0, statusMsg: 'सर्वर पर भेज रहे हैं...' });
  try {
    const res = await fetch(`${baseUrl}/admin/staff/bulk`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({ staff: rows }),
    });
    if (!res.ok) throw new Error(`Server error ${res.status}`);
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      while (buf.includes('\n')) {
        const idx = buf.indexOf('\n');
        const line = buf.slice(0, idx).trim();
        buf = buf.slice(idx + 1);
        if (!line.startsWith('data:')) continue;
        let data;
        try { data = JSON.parse(line.slice(5).trim()); } catch { continue; }
        const phase = data.phase || '', pct = Number(data.pct) || 0;
        if (phase === 'parse') {
          setUploadState({ phase: 'uploading', parsePct: Math.min(1, pct / 100), statusMsg: data.msg || '...' });
        } else if (phase === 'hash') {
          setUploadState({ parsePct: 1, hashPct: Math.min(1, (pct - 25) / 30), statusMsg: data.msg || '...' });
        } else if (phase === 'insert') {
          setUploadState({ parsePct: 1, hashPct: 1, insertPct: Math.min(1, (pct - 55) / 43), added: Number(data.added) || 0, total: Number(data.total) || rows.length, statusMsg: `${data.added || 0}/${data.total || rows.length} rows` });
        } else if (phase === 'done') {
          const added = Number(data.added) || 0;
          const skipped = (data.skipped || []).length;
          setUploadState({ phase: 'done', parsePct: 1, hashPct: 1, insertPct: 1, added, statusMsg: `${added} जोड़े गए, ${skipped} छोड़े गए` });
          return;
        } else if (phase === 'error') {
          throw new Error(data.message || 'Server error');
        }
      }
    }
  } catch (e) {
    setUploadState({ phase: 'error', statusMsg: e.message, errorMsg: e.message });
  }
}

// ── Assignment chip ───────────────────────────────────────────────────────────
function AssignmentChip({ staff: s }) {
  const type = String(s.assignType || '');
  const label = String(s.assignLabel || '');
  const detail = String(s.assignDetail || '');
  if (!label) return null;
  const cfg = {
    booth: { color: colors.success, bg: `${colors.success}0F`, label: 'बूथ' },
    kshetra: { color: '#6A1B9A', bg: '#f3e5f5', label: 'क्षेत्र' },
    zone: { color: '#1565C0', bg: '#e3f0fb', label: 'जोन' },
    sector: { color: '#2E7D32', bg: '#e6f4ea', label: 'सेक्टर' },
  }[type] || { color: colors.success, bg: `${colors.success}0F`, label: '' };
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, padding: '4px 8px', background: cfg.bg, border: `1px solid ${cfg.color}33`, borderRadius: 6, fontSize: 11, flexWrap: 'wrap' }}>
      {cfg.label && <span style={{ padding: '1px 5px', background: `${cfg.color}1E`, borderRadius: 4, fontSize: 9, fontWeight: 800, color: cfg.color }}>{cfg.label}</span>}
      <span style={{ color: cfg.color, fontWeight: 600 }}>{label}</span>
      {detail && <><span style={{ color: `${cfg.color}80`, fontSize: 10 }}> • </span><span style={{ color: `${cfg.color}B3`, fontSize: 10 }}>{detail}</span></>}
    </span>
  );
}

// ── Staff Card ────────────────────────────────────────────────────────────────
function StaffCard({ s, assigned, selected, onToggle, onEdit, onDelete, onAssign, onRemoveDuty, selectMode }) {
  const id = s.id;
  const isSelected = selected;
  const name = String(s.name || '');
  const initials = name.trim().split(' ').filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join('') || 'S';
  const avatarColor = assigned ? colors.success : colors.accent;
  const armed = s.isArmed === true || s.isArmed === 1 || s.is_armed === 1;
  const assignType = String(s.assignType || '');

  return (
    <div
      style={{
        marginBottom: 8, borderRadius: 12, overflow: 'hidden',
        border: `${isSelected ? 2 : 1}px solid ${isSelected ? colors.primary
          : colors.border + '66'
          }`,
        background: isSelected ? `${colors.primary}0A`
          : 'white',
        boxShadow: `0 2px 6px ${colors.primary}0A`,
        transition: 'all 0.15s',
      }}
      onClick={selectMode ? () => onToggle(id) : undefined}
      onContextMenu={e => { e.preventDefault(); onToggle(id); }}
    >
      <div style={{ display: 'flex', alignItems: 'flex-start', padding: '10px 8px 10px 12px', gap: 10 }}>
        {/* Avatar / Checkbox */}
        <div style={{ cursor: 'pointer', flexShrink: 0 }} onClick={e => { e.stopPropagation(); onToggle(id); }}>
          {selectMode
            ? <div style={{ width: 44, height: 44, borderRadius: '50%', background: isSelected ? colors.primary : 'white', border: `2px solid ${isSelected ? colors.primary : colors.border}`, display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'all 0.2s' }}>
              {isSelected && <CheckCircle size={22} color="white" />}
            </div>
            : <div style={{ width: 44, height: 44, borderRadius: '50%', background: `${avatarColor}1E`, border: `1px solid ${avatarColor}59`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <span style={{ color: avatarColor, fontWeight: 900, fontSize: initials.length <= 1 ? 18 : 13 }}>{initials}</span>
            </div>
          }
        </div>

        {/* Info */}
        <div style={{ flex: 1, overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4, marginBottom: 5, flexWrap: 'wrap' }}>
            <span style={{ fontWeight: 700, fontSize: 14, color: colors.dark, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name || '—'}</span>
            <Badge2 label={assigned ? 'असाइन' : 'रिज़र्व'} color={assigned ? colors.success : colors.accent} />
            <Badge2 label={armed ? '🔫 सशस्त्र' : '🛡 निःशस्त्र'} color={armed ? colors.armed : colors.unarmed} />
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 8px', marginBottom: s.assignLabel ? 5 : 0 }}>
            {s.pno && <MiniTag icon={Badge} text={`PNO: ${s.pno}`} />}
            {s.mobile && <MiniTag icon={Phone} text={s.mobile} />}
            {s.thana && <MiniTag icon={MapPin} text={s.thana} />}
            {s.district && <MiniTag icon={Building2} text={s.district} />}
            {(s.rank || s.user_rank) && <MiniTag icon={Star} text={s.rank || s.user_rank} color={colors.info} />}
          </div>
          {s.assignLabel && <AssignmentChip staff={s} />}
        </div>

        {/* Actions */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, flexShrink: 0 }}>
          <IconBtn icon={Pencil} color={colors.info} onClick={() => onEdit(s)} />
          <IconBtn icon={Trash2} color={colors.error} onClick={() => onDelete(s)} />
          {!assigned && <IconBtn icon={Vote} color={colors.primary} onClick={() => onAssign(s)} />}
          {assigned && assignType === 'booth' && <IconBtn icon={UserMinus} color={colors.error} onClick={() => onRemoveDuty(s)} />}
          {assigned && assignType !== 'booth' && <IconBtn icon={Lock} color={`${colors.subtle}80`} onClick={() => toast('अधिकारी असाइनमेंट संरचना पेज से बदलें')} />}
        </div>
      </div>
    </div>
  );
}

function IconBtn({ icon: Icon, color, onClick }) {
  return (
    <button onClick={e => { e.stopPropagation(); onClick(); }} style={{ width: 34, height: 34, borderRadius: 8, background: `${color}14`, border: `1px solid ${color}40`, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <Icon size={15} color={color} />
    </button>
  );
}

// ── Staff Info Card (for assign dialog) ───────────────────────────────────────
function StaffInfoCard({ s }) {
  const name = String(s.name || '');
  const initials = name.trim().split(' ').filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join('') || 'S';
  const armed = s.isArmed === true || s.isArmed === 1;
  return (
    <div style={{ background: colors.surface, border: `1px solid ${colors.border}80`, borderRadius: 10, padding: 12, display: 'flex', alignItems: 'center', gap: 10 }}>
      <div style={{ width: 40, height: 40, borderRadius: '50%', background: `${colors.accent}1E`, border: `1px solid ${colors.accent}59`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <span style={{ color: colors.accent, fontWeight: 800, fontSize: 14 }}>{initials}</span>
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <span style={{ fontWeight: 700, fontSize: 14, color: colors.dark }}>{name}</span>
          <Badge2 label={armed ? '🔫 सशस्त्र' : '🛡 निःशस्त्र'} color={armed ? colors.armed : colors.unarmed} />
        </div>
        <div style={{ display: 'flex', gap: 8, marginTop: 2 }}>
          <MiniTag icon={Badge} text={`PNO: ${s.pno || '—'}`} />
          {s.thana && <MiniTag icon={MapPin} text={s.thana} />}
        </div>
      </div>
    </div>
  );
}

// ── Selection Bar ─────────────────────────────────────────────────────────────
function SelectionBar({ count, isAssignedTab, onSelectAll, onClear, onBulkDelete, onBulkUnassign, onBulkAssign }) {
  if (count === 0) return null;
  return (
    <div style={{ margin: '0 12px 8px', padding: '10px 14px', background: colors.dark, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 6, boxShadow: `0 4px 12px ${colors.dark}4D`, flexWrap: 'wrap' }}>
      <span style={{ padding: '4px 10px', borderRadius: 20, background: `${colors.border}40`, color: colors.border, fontWeight: 800, fontSize: 13 }}>{count} चुने</span>
      <button onClick={onSelectAll} style={miniActionStyle('rgba(255,255,255,0.7)')}>
        <Grid size={12} /> सभी
      </button>
      <div style={{ flex: 1 }} />
      {!isAssignedTab && (
        <button onClick={onBulkAssign} style={miniActionStyle(colors.border)}>
          <Vote size={12} /> असाइन
        </button>
      )}
      {isAssignedTab && (
        <button onClick={onBulkUnassign} style={miniActionStyle(colors.accent)}>
          <UserMinus size={12} /> रिज़र्व
        </button>
      )}
      <button onClick={onBulkDelete} style={miniActionStyle(colors.error)}>
        <Trash2 size={12} /> हटाएं
      </button>
      <button onClick={onClear} style={{ background: 'rgba(255,255,255,0.12)', border: 'none', borderRadius: 8, padding: 7, cursor: 'pointer', display: 'flex', alignItems: 'center' }}>
        <X size={16} color="rgba(255,255,255,0.7)" />
      </button>
    </div>
  );
}
function miniActionStyle(color) {
  return { padding: '6px 10px', background: `${color}26`, border: `1px solid ${color}66`, borderRadius: 8, color, cursor: 'pointer', fontSize: 11, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 4 };
}

// ── Summary Chip ──────────────────────────────────────────────────────────────
function SummaryChip({ label, count, color }) {
  return (
    <span style={{ padding: '4px 8px', background: `${color}1A`, border: `1px solid ${color}40`, borderRadius: 8, fontSize: 13, fontWeight: 900, color, display: 'inline-flex', gap: 4 }}>
      {count} <span style={{ fontWeight: 500, fontSize: 11, color: colors.subtle }}>{label}</span>
    </span>
  );
}

// ── Rank Filter Chip ──────────────────────────────────────────────────────────
function RankChip({ rank, selected, onClick }) {
  return (
    <div onClick={onClick} style={{
      padding: '6px 12px', borderRadius: 20, cursor: 'pointer', marginRight: 6, flexShrink: 0,
      background: selected ? colors.primary : 'white',
      border: `1px solid ${selected ? colors.primary : colors.border + '80'}`,
      color: selected ? 'white' : colors.dark,
      fontSize: 11, fontWeight: selected ? 800 : 500,
      boxShadow: selected ? `0 2px 4px ${colors.primary}33` : 'none',
      transition: 'all 0.15s',
    }}>
      {rank}
    </div>
  );
}

// Add this component above StaffPage
function Pagination({ page, totalPages, onPage }) {
  if (totalPages <= 1) return null;
  const pages = [];
  for (let i = 1; i <= totalPages; i++) {
    if (i === 1 || i === totalPages || (i >= page - 2 && i <= page + 2)) {
      pages.push(i);
    } else if (pages[pages.length - 1] !== '...') {
      pages.push('...');
    }
  }
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4, padding: '10px 12px', background: colors.surface, borderTop: `1px solid ${colors.border}33`, flexShrink: 0, flexWrap: 'wrap' }}>
      <button
        onClick={() => onPage(page - 1)} disabled={page === 1}
        style={{ minWidth: 30, height: 30, borderRadius: 8, border: `1px solid ${colors.border}`, background: 'white', color: page === 1 ? colors.subtle : colors.dark, cursor: page === 1 ? 'default' : 'pointer', fontSize: 12, opacity: page === 1 ? 0.4 : 1 }}>
        ‹
      </button>
      {pages.map((p, i) =>
        p === '...'
          ? <span key={`e${i}`} style={{ color: colors.subtle, fontSize: 12, padding: '0 2px' }}>…</span>
          : <button key={p} onClick={() => onPage(p)}
            style={{ minWidth: 30, height: 30, borderRadius: 8, border: `1px solid ${p === page ? colors.primary : colors.border}`, background: p === page ? colors.primary : 'white', color: p === page ? 'white' : colors.dark, cursor: 'pointer', fontSize: 12, fontWeight: p === page ? 800 : 400 }}>
            {p}
          </button>
      )}
      <button
        onClick={() => onPage(page + 1)} disabled={page === totalPages}
        style={{ minWidth: 30, height: 30, borderRadius: 8, border: `1px solid ${colors.border}`, background: 'white', color: page === totalPages ? colors.subtle : colors.dark, cursor: page === totalPages ? 'default' : 'pointer', fontSize: 12, opacity: page === totalPages ? 0.4 : 1 }}>
        ›
      </button>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN STAFF PAGE
// ══════════════════════════════════════════════════════════════════════════════
export default function StaffPage() {
  const { token } = useAuthStore();

  const [activeTab, setActiveTab] = useState(0);

  const [assigned, setAssigned] = useState([]);
  const [assignedTotal, setAssignedTotal] = useState(0);
  const [assignedPage, setAssignedPage] = useState(1);
  const [assignedLoading, setAssignedLoading] = useState(false);

  const [reserve, setReserve] = useState([]);
  const [reserveTotal, setReserveTotal] = useState(0);
  const [reservePage, setReservePage] = useState(1);
  const [reserveLoading, setReserveLoading] = useState(false);

  const [q, setQ] = useState('');
  const [rankFilter, setRankFilter] = useState('All');
  const [armedFilter, setArmedFilter] = useState('All');
  const [cardFilter, setCardFilter] = useState('All');

  const [selected, setSelected] = useState(new Set());
  const selectMode = selected.size > 0;

  const [modal, setModal] = useState(null);
  const [editTarget, setEditTarget] = useState(null);
  const [assignTarget, setAssignTarget] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [bulkDeleteConfirm, setBulkDeleteConfirm] = useState(false);
  const [bulkUnassignConfirm, setBulkUnassignConfirm] = useState(false);
  const [showBulkAssign, setShowBulkAssign] = useState(false);
  const [showUploadHint, setShowUploadHint] = useState(false);
  const [previewRows, setPreviewRows] = useState(null);
  const [fileLoading, setFileLoading] = useState(false);
  const fileRef = useRef();

  const up = useUploadProgress();

  const debouncedQ = useCallback(debounce((v) => { setQ(v); }, 350), []);

  const armedParam = armedFilter === 'Armed' ? 'yes' : armedFilter === 'Unarmed' ? 'no' : '';
  const rankParam = rankFilter === 'All' ? '' : rankFilter;
  const cardParam = cardFilter === 'All' ? '' : cardFilter;

  // ── Load functions (pg = explicit page number) ────────────────────────────
  const loadAssigned = useCallback(async (pg) => {
    if (assignedLoading) return;
    setAssignedLoading(true);
    try {
      const res = await adminApi.getStaff({ assigned: 'yes', page: pg, limit: PAGE_SIZE, q, rank: rankParam, armed: armedParam });
      const w = res.data || {};
      const items = Array.isArray(w.data) ? w.data : [];
      const total = w.total || 0;
      setAssigned(items);
      setAssignedTotal(total);
      setAssignedPage(pg);
    } catch (e) { toast.error(e.message || 'Load failed'); }
    setAssignedLoading(false);
  }, [assignedLoading, q, rankParam, armedParam, cardParam]);

  const loadReserve = useCallback(async (pg) => {
    if (reserveLoading) return;
    setReserveLoading(true);
    try {
      const res = await adminApi.getStaff({ assigned: 'no', page: pg, limit: PAGE_SIZE, q, rank: rankParam, armed: armedParam });
      const w = res.data || {};
      const items = Array.isArray(w.data) ? w.data : [];
      const total = w.total || 0;
      setReserve(items);
      setReserveTotal(total);
      setReservePage(pg);
    } catch (e) { toast.error(e.message || 'Load failed'); }
    setReserveLoading(false);
  }, [reserveLoading, q, rankParam, armedParam, cardParam]);

  // ── Reload page 1 when filters change ────────────────────────────────────
  useEffect(() => {
    setAssignedPage(1);
    setReservePage(1);
    loadAssigned(1);
    loadReserve(1);
  }, [q, rankFilter, armedFilter, cardFilter]);

  // ── Upload done → reload ──────────────────────────────────────────────────
  useEffect(() => {
    if (up.phase === 'done') {
      loadAssigned(1);
      loadReserve(1);
    }
  }, [up.phase]);

  // ── Helpers ───────────────────────────────────────────────────────────────
  const reloadBoth = () => { loadAssigned(assignedPage); loadReserve(reservePage); };

  const toggleSelect = (id) => setSelected(prev => {
    const next = new Set(prev);
    next.has(id) ? next.delete(id) : next.add(id);
    return next;
  });
  const selectAll = () => {
    const list = activeTab === 0 ? assigned : reserve;
    setSelected(prev => { const next = new Set(prev); list.forEach(s => next.add(s.id)); return next; });
  };
  const clearSelection = () => setSelected(new Set());

  // ── CRUD ──────────────────────────────────────────────────────────────────
  const handleAdd = async (form) => {
    await adminApi.addStaff(form);
    toast.success(`${form.name} जोड़ा गया`);
    loadAssigned(1); loadReserve(1);
  };

  const handleEdit = async (form) => {
    await adminApi.updateStaff(editTarget.id, form);
    toast.success('स्टाफ अपडेट किया गया');
    setEditTarget(null);
    reloadBoth();
  };

  const handleDelete = async () => {
    const s = deleteTarget;
    try {
      await adminApi.deleteStaff(s.id);
      toast.success(`${s.name} हटाया गया`);
      loadAssigned(1); loadReserve(1);
    } catch (e) { toast.error(e.message); }
    setDeleteTarget(null);
  };

  const handleRemoveDuty = async (s) => {
    if (String(s.assignType) !== 'booth') { toast.error('अधिकारी असाइनमेंट संरचना पेज से बदलें'); return; }
    try {
      if (s.dutyId) await adminApi.removeAssignment(s.dutyId);
      else await adminApi.deleteStaff(`${s.id}/duty`);
      toast.success(`${s.name} रिज़र्व में भेजा गया`);
      loadAssigned(assignedPage); loadReserve(reservePage);
    } catch (e) { toast.error(e.message); }
  };

  const handleBulkDelete = async () => {
    try {
      const resp = await fetch(`${(await import('../../api/client')).default.defaults.baseURL}/admin/staff/bulk-delete`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({ staffIds: [...selected] }),
      });
      const data = await resp.json();
      toast.success(`${data.data?.deleted ?? 0} स्टाफ हटाए गए`);
      clearSelection(); loadAssigned(1); loadReserve(1);
    } catch (e) { toast.error(e.message); }
    setBulkDeleteConfirm(false);
  };

  const handleBulkUnassign = async () => {
    const currentList = activeTab === 0 ? assigned : reserve;
    const boothIds = currentList.filter(s => selected.has(s.id) && String(s.assignType) === 'booth').map(s => s.id);
    if (!boothIds.length) { toast.error('केवल बूथ स्टाफ ही हटाए जा सकते हैं'); setBulkUnassignConfirm(false); return; }
    try {
      const baseUrl = (await import('../../api/client')).default.defaults.baseURL || '';
      const resp = await fetch(`${baseUrl}/admin/staff/bulk-unassign`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({ staffIds: boothIds }),
      });
      const data = await resp.json();
      toast.success(`${data.data?.removed ?? 0} बूथ स्टाफ रिज़र्व में`);
      clearSelection(); loadAssigned(1); loadReserve(1);
    } catch (e) { toast.error(e.message); }
    setBulkUnassignConfirm(false);
  };

  const handleBulkAssign = async (center, busNo) => {
    const baseUrl = (await import('../../api/client')).default.defaults.baseURL || '';
    const resp = await fetch(`${baseUrl}/admin/staff/bulk-assign`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify({ staffIds: [...selected], centerId: center.id, busNo }),
    });
    const data = await resp.json();
    toast.success(`${data.data?.assigned ?? 0} स्टाफ असाइन`);
    clearSelection(); loadAssigned(1); loadReserve(1);
  };

  const handleAssign = async (s, center, busNo) => {
    await adminApi.assignDuty({ staffId: s.id, centerId: center.id, busNo });
    toast.success(`${s.name} असाइन किया गया`);
    loadAssigned(assignedPage); loadReserve(reservePage);
  };

  const handleFileChange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    fileRef.current.value = '';
    setFileLoading(true);
    const bytes = await file.arrayBuffer().then(b => new Uint8Array(b));
    const ext = file.name.split('.').pop().toLowerCase();
    let rows = [];
    if (ext === 'csv') rows = await parseCSV(bytes);
    else { const result = await parseExcel(bytes); rows = result.rows || []; }
    setFileLoading(false);
    if (!rows.length) { toast.error('कोई डेटा नहीं मिला'); return; }
    setPreviewRows(rows);
  };

  const doUpload = async (rows) => {
    setPreviewRows(null);
    await startBackgroundUpload(rows, token);
  };

  const totalAll = assignedTotal + reserveTotal;
  const assignedTotalPages = Math.ceil(assignedTotal / PAGE_SIZE) || 1;
  const reserveTotalPages = Math.ceil(reserveTotal / PAGE_SIZE) || 1;

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <>
      <style>{`@keyframes spin { to { transform: rotate(360deg); } } * { box-sizing: border-box; }`}</style>

      <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: colors.bg, fontFamily: 'system-ui, sans-serif' }}>

        {/* Top toolbar */}
        <div style={{ background: colors.surface, padding: '10px 12px 8px', display: 'flex', gap: 8, alignItems: 'center', flexShrink: 0 }}>
          <div style={{ flex: 1, position: 'relative' }}>
            <Search size={16} color={colors.subtle} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none' }} />
            <input placeholder="नाम, PNO, मोबाइल, थाना खोजें..." onChange={e => debouncedQ(e.target.value)}
              style={{ ...fieldStyle(true), width: '100%', paddingRight: 36 }} />
          </div>
          <button onClick={() => setModal('add')} style={{ padding: '9px 11px', background: colors.primary, color: 'white', border: 'none', borderRadius: 10, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, fontWeight: 700, flexShrink: 0 }}>
            <Plus size={14} /> जोड़ें
          </button>
          {fileLoading || up.phase === 'parsing'
            ? <div style={{ padding: '9px 11px', background: colors.dark, borderRadius: 10, display: 'flex', alignItems: 'center', gap: 6 }}><Spinner size={14} /><span style={{ color: 'white', fontSize: 12, fontWeight: 700 }}>लोड...</span></div>
            : up.phase !== 'idle' && up.phase !== 'done' && up.phase !== 'error'
              ? <div style={{ padding: '9px 11px', background: colors.dark, borderRadius: 10, display: 'flex', alignItems: 'center', gap: 6 }}>
                <div style={{ width: 14, height: 14, border: `2px solid ${colors.border}40`, borderTop: `2px solid ${colors.border}`, borderRadius: '50%', animation: 'spin 0.8s linear infinite' }} />
                <span style={{ color: 'white', fontSize: 12, fontWeight: 700 }}>{Math.round(((up.parsePct * 0.15) + (up.hashPct * 0.30) + (up.insertPct * 0.55)) * 100)}%</span>
              </div>
              : <button onClick={() => setShowUploadHint(true)} style={{ padding: '9px 11px', background: colors.dark, color: 'white', border: 'none', borderRadius: 10, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, fontWeight: 700, flexShrink: 0 }}>
                <Upload size={14} /> Upload
              </button>
          }
          <input ref={fileRef} type="file" accept=".csv,.xlsx,.xls" hidden onChange={handleFileChange} />
        </div>

        {/* Rank chips */}
        <div style={{ background: colors.bg, padding: '6px 12px 4px', overflowX: 'auto', display: 'flex', flexShrink: 0 }}>
          {ALL_RANKS.map(rank => (
            <RankChip key={rank} rank={rank} selected={rankFilter === rank} onClick={() => setRankFilter(rank)} />
          ))}
        </div>

        {/* Armed filter */}
        <div style={{ background: colors.bg, padding: '2px 12px 6px', display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
          <Shield size={13} color={colors.subtle} />
          {['All', 'Armed', 'Unarmed'].map(opt => {
            const isSel = armedFilter === opt;
            const c = opt === 'Armed' ? colors.armed : opt === 'Unarmed' ? colors.unarmed : colors.subtle;
            const label = opt === 'All' ? 'सभी' : opt === 'Armed' ? '🔫 सशस्त्र' : '🛡 निःशस्त्र';
            return (
              <div key={opt} onClick={() => setArmedFilter(opt)} style={{ padding: '5px 10px', borderRadius: 16, cursor: 'pointer', background: isSel ? `${c}26` : 'white', border: `${isSel ? 1.5 : 1}px solid ${isSel ? c : colors.border + '66'}`, color: isSel ? c : colors.subtle, fontSize: 11, fontWeight: isSel ? 800 : 500, transition: 'all 0.15s' }}>
                {label}
              </div>
            );
          })}
        </div>

        {/* Summary */}
        <div style={{ background: colors.bg, padding: '2px 12px 6px', display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
          <SummaryChip label="कुल" count={totalAll} color={colors.primary} />
          <SummaryChip label="असाइन" count={assignedTotal} color={colors.success} />
          <SummaryChip label="रिज़र्व" count={reserveTotal} color={colors.accent} />
          <div style={{ flex: 1 }} />
          {(q || rankFilter !== 'All' || armedFilter !== 'All' || cardFilter !== 'All') && (
            <span style={{ padding: '3px 8px', background: `${colors.info}14`, border: `1px solid ${colors.info}33`, borderRadius: 6, fontSize: 10, fontWeight: 700, color: colors.info }}>फ़िल्टर सक्रिय</span>
          )}
          <button onClick={() => { setRankFilter('All'); setArmedFilter('All'); setCardFilter('All'); setQ(''); }} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 4 }} title="रिफ्रेश">
            <RefreshCw size={16} color={colors.subtle} />
          </button>
        </div>

        {/* Tabs */}
        <div style={{ background: colors.bg, display: 'flex', borderBottom: `2px solid ${colors.border}33`, flexShrink: 0 }}>
          {[`असाइन (${assignedTotal})`, `रिज़र्व (${reserveTotal})`].map((label, idx) => (
            <div key={idx} onClick={() => { setActiveTab(idx); if (idx === 1 && cardFilter === 'Pending') setCardFilter('All'); }}
              style={{ flex: 1, padding: '10px 16px', textAlign: 'center', cursor: 'pointer', fontWeight: activeTab === idx ? 800 : 500, fontSize: 12, color: activeTab === idx ? colors.primary : colors.subtle, borderBottom: `3px solid ${activeTab === idx ? colors.primary : 'transparent'}`, transition: 'all 0.15s', marginBottom: -2 }}>
              {label}
            </div>
          ))}
        </div>

        {/* Selection bar */}
        {selectMode && (
          <div style={{ flexShrink: 0, paddingTop: 8 }}>
            <SelectionBar count={selected.size} isAssignedTab={activeTab === 0}
              onSelectAll={selectAll} onClear={clearSelection}
              onBulkDelete={() => setBulkDeleteConfirm(true)}
              onBulkUnassign={() => setBulkUnassignConfirm(true)}
              onBulkAssign={() => setShowBulkAssign(true)} />
          </div>
        )}

        {/* ── Staff list ── */}
        <div style={{ flex: 1, overflowY: 'auto', padding: '10px 12px 16px' }}>
          {(() => {
            const list = activeTab === 0 ? assigned : reserve;
            const loading = activeTab === 0 ? assignedLoading : reserveLoading;
            const emptyMsg = activeTab === 0
              ? (q ? `"${q}" के लिए कोई result नहीं` : 'कोई असाइन स्टाफ नहीं')
              : (q ? `"${q}" के लिए कोई result नहीं` : 'सभी स्टाफ असाइन हैं!');

            if (list.length === 0 && loading)
              return <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 40 }}><Spinner color={colors.primary} size={32} /></div>;

            if (list.length === 0)
              return (
                <div style={{ textAlign: 'center', padding: 40 }}>
                  <FileText size={52} color={`${colors.subtle}66`} style={{ margin: '0 auto 14px' }} />
                  <p style={{ color: colors.subtle, fontSize: 13 }}>{emptyMsg}</p>
                </div>
              );

            return list.map(s => (
              <StaffCard key={s.id} s={s}
                assigned={activeTab === 0}
                selected={selected.has(s.id)}
                selectMode={selectMode}
                onToggle={toggleSelect}
                onEdit={(s) => { setEditTarget(s); setModal('edit'); }}
                onDelete={(s) => setDeleteTarget(s)}
                onAssign={(s) => setAssignTarget({ type: 'single', staff: s })}
                onRemoveDuty={handleRemoveDuty} />
            ));
          })()}
        </div>

        {/* ── Pagination ── */}
        {(() => {
          const totalPages = activeTab === 0 ? assignedTotalPages : reserveTotalPages;
          const page = activeTab === 0 ? assignedPage : reservePage;
          const onPage = (p) => activeTab === 0 ? loadAssigned(p) : loadReserve(p);
          return <Pagination page={page} totalPages={totalPages} onPage={onPage} />;
        })()}

      </div>

      {/* Modals */}
      {modal === 'add' && <StaffFormDialog onSave={handleAdd} onClose={() => setModal(null)} />}
      {modal === 'edit' && editTarget && <StaffFormDialog initial={editTarget} onSave={handleEdit} onClose={() => { setModal(null); setEditTarget(null); }} />}

      {assignTarget?.type === 'single' && (
        <AssignDialog title="ड्यूटी असाइन करें" staffCard={<StaffInfoCard s={assignTarget.staff} />}
          onAssign={(center, busNo) => { setAssignTarget(null); handleAssign(assignTarget.staff, center, busNo); }}
          onClose={() => setAssignTarget(null)} assignLabel="ड्यूटी असाइन करें" />
      )}

      {showBulkAssign && (
        <AssignDialog title={`${selected.size} स्टाफ को असाइन करें`}
          onAssign={async (center, busNo) => { setShowBulkAssign(false); await handleBulkAssign(center, busNo); }}
          onClose={() => setShowBulkAssign(false)} assignLabel={`${selected.size} असाइन करें`} />
      )}

      {showUploadHint && <UploadHintDialog onConfirm={() => { setShowUploadHint(false); fileRef.current?.click(); }} onClose={() => setShowUploadHint(false)} />}
      {previewRows && <PreviewDialog rows={previewRows} onUpload={doUpload} onClose={() => setPreviewRows(null)} />}

      <ConfirmDialog open={!!deleteTarget} title="स्टाफ हटाएं" message={`"${deleteTarget?.name}" को स्थायी रूप से हटाएं?`} confirmText="हटाएं" onConfirm={handleDelete} onCancel={() => setDeleteTarget(null)} />
      <ConfirmDialog open={bulkDeleteConfirm} title={`${selected.size} स्टाफ हटाएं`} message={`${selected.size} स्टाफ को स्थायी रूप से हटाएं?`} confirmText="हटाएं" onConfirm={handleBulkDelete} onCancel={() => setBulkDeleteConfirm(false)} />
      <ConfirmDialog open={bulkUnassignConfirm} title="ड्यूटी हटाएं" message="चुने गए बूथ स्टाफ रिज़र्व में जाएंगे।" confirmText="हटाएं" onConfirm={handleBulkUnassign} onCancel={() => setBulkUnassignConfirm(false)} />

      <UploadProgressBanner />
    </>
  );
}