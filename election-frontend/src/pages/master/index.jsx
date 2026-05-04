import { useState, useEffect, useRef } from 'react';
import {
  Shield, Users, MapPin, Vote, Activity, Plus, Pencil, Trash2,
  Eye, EyeOff, Save, AlertCircle, RefreshCw, ChevronRight, Lock,
  Database, Settings, ToggleLeft, ToggleRight, Key, Zap, Wrench,
  Info, LogOut, Terminal, Archive, Map, BarChart3, List,
  HardDrive, ChevronLeft, ChevronsLeft, ChevronsRight, Search,
  X, MoreVertical, CheckSquare, Square, Flag, Calendar,
  Sun, Moon, FileText, Cpu, Layers, Globe, AlertTriangle,
  Building2, Hash, Clock, User, AtSign, Power
} from 'lucide-react';

// ─────────────────────────────────────────────────────────
//  CSS (injected once)
// ─────────────────────────────────────────────────────────
const STYLE = `
  @import url('https://fonts.googleapis.com/css2?family=Tiro+Devanagari+Hindi&family=JetBrains+Mono:wght@400;700&display=swap');

  :root {
    --bg: #FDF6E3;
    --surface: #F5E6C8;
    --primary: #8B6914;
    --accent: #B8860B;
    --dark: #4A3000;
    --subtle: #AA8844;
    --border: #D4A843;
    --error: #C0392B;
    --success: #2D6A1E;
    --info: #1A5276;
    --warning: #E65100;
    --dev: #00695C;
    --devLight: #E0F2F1;
    --masterBg: #1A0A00;
  }

  * { box-sizing: border-box; }
  
  body { font-family: 'Tiro Devanagari Hindi', Georgia, serif; }

  .md-field {
    width: 100%;
    background: white;
    border: 1.2px solid var(--border);
    border-radius: 8px;
    padding: 9px 13px;
    color: var(--dark);
    font-size: 13px;
    outline: none;
    transition: border-color 0.2s, box-shadow 0.2s;
    font-family: inherit;
  }
  .md-field::placeholder { color: var(--subtle); }
  .md-field:focus {
    border-color: var(--primary);
    box-shadow: 0 0 0 3px rgba(139,105,20,0.12);
  }
  .md-field.error { border-color: var(--error); }

  .md-btn-primary {
    display: inline-flex; align-items: center; justify-content: center; gap: 6px;
    padding: 9px 18px; border-radius: 8px; font-weight: 700;
    color: white; font-size: 13px;
    background: var(--dev); border: none; cursor: pointer;
    transition: all 0.18s; white-space: nowrap;
  }
  .md-btn-primary:hover:not(:disabled) { background: #00564A; }
  .md-btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }

  .md-btn-outline {
    display: inline-flex; align-items: center; justify-content: center; gap: 6px;
    padding: 8px 16px; border-radius: 8px; font-weight: 600;
    color: var(--subtle); font-size: 13px;
    background: transparent; border: 1.2px solid var(--border); cursor: pointer;
    transition: all 0.18s;
  }
  .md-btn-outline:hover { background: var(--surface); }

  .md-btn-danger {
    display: inline-flex; align-items: center; justify-content: center; gap: 6px;
    padding: 8px 16px; border-radius: 8px; font-weight: 700;
    color: white; font-size: 13px;
    background: var(--error); border: none; cursor: pointer;
    transition: all 0.18s;
  }
  .md-btn-danger:hover { background: #a93226; }

  .md-card {
    background: var(--bg);
    border: 1px solid rgba(212,168,67,0.45);
    border-radius: 12px;
    box-shadow: 0 2px 12px rgba(139,105,20,0.07);
  }

  .md-table { width: 100%; border-collapse: collapse; font-size: 13px; }
  .md-table th {
    padding: 10px 14px; text-align: left;
    font-size: 10.5px; font-weight: 800; text-transform: uppercase; letter-spacing: 0.07em;
    background: var(--dark); color: #D4A843; white-space: nowrap;
  }
  .md-table th:first-child { border-radius: 12px 0 0 0; }
  .md-table th:last-child { border-radius: 0 12px 0 0; }
  .md-table td {
    padding: 10px 14px;
    border-bottom: 1px solid rgba(212,168,67,0.18);
    color: var(--dark);
  }
  .md-table tr:last-child td { border-bottom: none; }
  .md-table tr:hover td { background: rgba(245,230,200,0.4); }

  .md-tab {
    display: flex; align-items: center; gap: 7px;
    padding: 10px 16px; cursor: pointer; white-space: nowrap;
    border-bottom: 3px solid transparent;
    transition: all 0.18s;
    color: var(--subtle); font-size: 12.5px; font-weight: 500;
    background: transparent; border-top: none; border-left: none; border-right: none;
  }
  .md-tab:hover { color: var(--dev); background: rgba(0,105,92,0.04); }
  .md-tab.active {
    color: var(--dev); font-weight: 700;
    border-bottom-color: var(--dev);
    background: rgba(0,105,92,0.06);
  }

  .md-modal-overlay {
    position: fixed; inset: 0; z-index: 1000;
    background: rgba(0,0,0,0.55);
    display: flex; align-items: center; justify-content: center;
    padding: 16px;
    animation: mdFadeIn 0.18s ease;
  }
  .md-modal {
    background: var(--bg);
    border: 1.2px solid var(--border);
    border-radius: 14px;
    width: 100%; max-width: 520px;
    max-height: 90vh;
    overflow: hidden;
    display: flex; flex-direction: column;
    box-shadow: 0 20px 60px rgba(0,0,0,0.35);
  }
  .md-modal-header {
    background: var(--dark);
    padding: 14px 18px;
    display: flex; align-items: center; gap: 10px;
    border-radius: 13px 13px 0 0;
    flex-shrink: 0;
  }
  .md-modal-body {
    padding: 20px;
    overflow-y: auto;
    flex: 1;
  }

  @keyframes mdFadeIn { from { opacity: 0; } to { opacity: 1; } }
  @keyframes mdSlideIn {
    from { opacity: 0; transform: translateY(12px); }
    to   { opacity: 1; transform: translateY(0); }
  }
  .md-slide-in { animation: mdSlideIn 0.25s ease-out; }

  .md-shimmer {
    background: linear-gradient(to right, #F5E6C8 8%, #FDF6E3 18%, #F5E6C8 33%);
    background-size: 800px 104px;
    animation: mdShimmer 1.4s linear infinite;
    border-radius: 8px;
  }
  @keyframes mdShimmer {
    0% { background-position: -468px 0; }
    100% { background-position: 468px 0; }
  }

  .md-status-active {
    display: inline-flex; align-items: center;
    padding: 2px 10px; border-radius: 20px;
    font-size: 10px; font-weight: 800; letter-spacing: 0.5px;
    background: rgba(45,106,30,0.12); color: #2D6A1E;
    border: 1px solid #2D6A1E; cursor: pointer;
  }
  .md-status-inactive {
    display: inline-flex; align-items: center;
    padding: 2px 10px; border-radius: 20px;
    font-size: 10px; font-weight: 800; letter-spacing: 0.5px;
    background: rgba(192,57,43,0.1); color: var(--error);
    border: 1px solid var(--error); cursor: pointer;
  }

  .md-select {
    width: 100%; background: white;
    border: 1.2px solid var(--border); border-radius: 8px;
    padding: 9px 13px; color: var(--dark); font-size: 13px;
    outline: none; cursor: pointer; font-family: inherit;
  }
  .md-select:focus { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(139,105,20,0.12); }

  .md-search {
    display: flex; align-items: center; gap: 8px;
    background: white; border: 1.2px solid var(--border);
    border-radius: 8px; padding: 8px 12px;
    transition: border-color 0.2s;
  }
  .md-search:focus-within { border-color: var(--dev); }
  .md-search input {
    border: none; outline: none; background: transparent;
    color: var(--dark); font-size: 13px; width: 100%;
    font-family: inherit;
  }

  .md-popup-menu {
    position: absolute; right: 0; top: 100%;
    background: white; border: 1px solid var(--border);
    border-radius: 10px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);
    z-index: 100; min-width: 160px; overflow: hidden;
    animation: mdSlideIn 0.15s ease;
  }
  .md-popup-item {
    display: flex; align-items: center; gap: 8px;
    padding: 10px 14px; cursor: pointer;
    font-size: 13px; font-weight: 600;
    transition: background 0.15s;
    background: white; border: none; width: 100%; text-align: left;
  }
  .md-popup-item:hover { background: var(--surface); }

  .md-confirm-overlay {
    position: fixed; inset: 0; z-index: 1100;
    background: rgba(0,0,0,0.6);
    display: flex; align-items: center; justify-content: center;
    padding: 16px;
  }
  .md-confirm-box {
    background: var(--bg);
    border: 1.5px solid var(--error); border-radius: 14px;
    width: 100%; max-width: 380px; overflow: hidden;
    box-shadow: 0 20px 60px rgba(0,0,0,0.35);
  }

  .md-pill {
    display: inline-flex; align-items: center;
    padding: 3px 10px; border-radius: 20px;
    font-size: 11px; font-weight: 700;
  }

  .md-id-badge {
    padding: 3px 8px; border-radius: 6px;
    background: var(--dark); color: var(--border);
    font-size: 10px; font-weight: 900; letter-spacing: 0.8px;
    font-family: 'JetBrains Mono', monospace;
  }

  .md-filter-chip {
    display: flex; align-items: center; gap: 5px;
    padding: 5px 12px; border-radius: 20px;
    font-size: 11px; font-weight: 700;
    background: white; border: 1px solid rgba(212,168,67,0.5);
    cursor: pointer; transition: all 0.15s; white-space: nowrap;
  }

  .md-filter-chip.active {
    background: var(--dev); color: white; border-color: var(--dev);
  }

  .md-expansion-row {
    background: rgba(245,230,200,0.3);
    border-top: 1px solid rgba(212,168,67,0.2);
  }

  ::-webkit-scrollbar { width: 5px; height: 5px; }
  ::-webkit-scrollbar-track { background: var(--surface); }
  ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }

  .md-toggle {
    position: relative; display: inline-flex;
    width: 44px; height: 24px; cursor: pointer;
  }
  .md-toggle input { opacity: 0; width: 0; height: 0; }
  .md-toggle-track {
    position: absolute; inset: 0; border-radius: 24px;
    background: #ccc; transition: 0.2s;
  }
  .md-toggle input:checked + .md-toggle-track { background: var(--dev); }
  .md-toggle-thumb {
    position: absolute; height: 18px; width: 18px;
    left: 3px; top: 3px; border-radius: 50%;
    background: white; transition: 0.2s;
    box-shadow: 0 1px 4px rgba(0,0,0,0.2);
  }
  .md-toggle input:checked ~ .md-toggle-thumb { transform: translateX(20px); }

  .md-config-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: 13px 16px;
    border-bottom: 1px solid rgba(212,168,67,0.2);
  }
  .md-config-row:last-child { border-bottom: none; }

  .md-dev-action {
    display: flex; align-items: center; gap: 12px;
    padding: 12px 16px; cursor: pointer; transition: background 0.15s;
    border-bottom: 1px solid rgba(212,168,67,0.2);
    background: white;
  }
  .md-dev-action:last-child { border-bottom: none; }
  .md-dev-action:hover { background: var(--surface); }
`;

// ─────────────────────────────────────────────────────────
//  CONFIG
// ─────────────────────────────────────────────────────────
const BASE_URL = (typeof import.meta !== 'undefined' && import.meta.env?.VITE_API_URL) || 'http://localhost:5000/api';

const UP_DISTRICTS = [
  'आगरा','आज़मगढ़','बिजनौर','इटावा','अलीगढ़','बागपत','बदायूं','फर्रुखाबाद',
  'अंबेडकर नगर','बहराइच','बुलंदशहर','फतेहपुर','अमेठी','बलिया','चंदौली','फिरोजाबाद',
  'अमरोहा','बलरामपुर','चित्रकूट','गौतम बुद्ध नगर','औरैया','बांदा','देवरिया','गाज़ियाबाद',
  'अयोध्या','बाराबंकी','एटा','गाज़ीपुर','गोंडा','जालौन','कासगंज','लखनऊ',
  'गोरखपुर','जौनपुर','कौशांबी','महाराजगंज','हमीरपुर','झांसी','कुशीनगर','महोबा',
  'हापुड़','कन्नौज','लखीमपुर खीरी','मैनपुरी','हरदोई','कानपुर देहात','ललितपुर','मथुरा',
  'हाथरस','कानपुर नगर','मऊ','पीलीभीत','संभल','सोनभद्र','मेरठ','प्रतापगढ़',
  'संतकबीर नगर','सुल्तानपुर','मिर्जापुर','प्रयागराज','भदोही (संत रविदास नगर)','उन्नाव',
  'मुरादाबाद','रायबरेली','शाहजहाँपुर','वाराणसी','मुजफ्फरनगर','रामपुर','शामली','सहारनपुर',
  'श्रावस्ती','सिद्धार्थनगर','सीतापुर',
];

const ELECTION_TYPES = [
  'लोक सभा निर्वाचन','विधान सभा निर्वाचन','पंचायत निर्वाचन',
  'नगर निकाय निर्वाचन','विधान परिषद निर्वाचन','उप-निर्वाचन',
];
const ELECTION_PHASES = [
  'प्रथम चरण','द्वितीय चरण','तृतीय चरण','चतुर्थ चरण',
  'पंचम चरण','षष्ठम चरण','सप्तम चरण',
];

// ─────────────────────────────────────────────────────────
//  API HELPER
// ─────────────────────────────────────────────────────────
const getToken = () => localStorage.getItem('AUTH_TOKEN');

const api = async (method, path, body, params) => {
  const token = getToken();
  const url = new URL(`${BASE_URL}${path}`);
  if (params) Object.entries(params).forEach(([k, v]) => v !== undefined && url.searchParams.set(k, v));
  const res = await fetch(url.toString(), {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    credentials: 'include',
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.message || data.error || 'Error');
  return data;
};

const masterApi = {
  overview:          () => api('GET', '/master/overview'),
  systemStats:       () => api('GET', '/master/system-stats'),
  getConfig:         () => api('GET', '/master/config'),
  updateConfig:      (body) => api('POST', '/master/config', body),

  getSuperAdmins:    () => api('GET', '/master/super-admins'),
  createSuperAdmin:  (b) => api('POST', '/master/super-admins', b),
  updateSuperAdmin:  (id, b) => api('PUT', `/master/super-admins/${id}`, b),
  deleteSuperAdmin:  (id) => api('DELETE', `/master/super-admins/${id}`),
  toggleSuperAdmin:  (id, b) => api('PATCH', `/master/super-admins/${id}/status`, b),
  resetSuperAdminPw: (id, b) => api('PATCH', `/master/super-admins/${id}/reset-password`, b),

  getAdmins:         () => api('GET', '/master/admins'),
  createAdmin:       (b) => api('POST', '/master/admins', b),
  deleteAdmin:       (id) => api('DELETE', `/master/admins/${id}`),
  toggleAdmin:       (id, b) => api('PATCH', `/master/admins/${id}/status`, b),
  resetAdminPw:      (id, b) => api('PATCH', `/master/admins/${id}/reset-password`, b),

  getElectionConfigs:   (archived) => api('GET', `/master/election-configs?includeArchived=${archived ? 1 : 0}`),
  createElectionConfig: (b) => api('POST', '/master/election-configs', b),
  updateElectionConfig: (id, b) => api('PUT', `/master/election-configs/${id}`, b),
  archiveElectionConfig: (id) => api('PATCH', `/master/election-configs/${id}/archive`, {}),
  deleteElectionConfig:  (id) => api('DELETE', `/master/election-configs/${id}`),
  autoArchive:           () => api('POST', '/master/election-configs/auto-archive', {}),

  getLogs:           (params) => api('GET', '/master/logs', null, params),
  getApiLogs:        (params) => api('GET', '/master/api-logs', null, params),
  clearApiLogs:      (days) => api('DELETE', `/master/api-logs/clear?days=${days}`),

  dbBackup:          () => api('POST', '/master/db/backup', {}),
  flushCache:        () => api('POST', '/master/db/flush-cache', {}),
  runMigrations:     () => api('POST', '/master/migrate', {}),
  forceLogout:       (b) => api('POST', '/master/force-logout', b),
  changeMasterPw:    (b) => api('PATCH', '/master/change-password', b),
};

// ─────────────────────────────────────────────────────────
//  TOAST
// ─────────────────────────────────────────────────────────
let _toastFn = null;
function Toast({ onRegister }) {
  const [toasts, setToasts] = useState([]);
  useEffect(() => {
    _toastFn = (msg, color = '#2D6A1E') => {
      const id = Date.now();
      setToasts(p => [...p, { id, msg, color }]);
      setTimeout(() => setToasts(p => p.filter(t => t.id !== id)), 3500);
    };
    onRegister?.();
  }, []);
  return (
    <div style={{ position: 'fixed', bottom: 20, right: 20, zIndex: 9999, display: 'flex', flexDirection: 'column', gap: 8 }}>
      {toasts.map(t => (
        <div key={t.id} className="md-slide-in" style={{
          background: t.color, color: 'white', padding: '10px 16px',
          borderRadius: 10, fontWeight: 700, fontSize: 13, boxShadow: '0 4px 16px rgba(0,0,0,0.25)',
          maxWidth: 320,
        }}>{t.msg}</div>
      ))}
    </div>
  );
}
const toast = (msg, color) => _toastFn?.(msg, color);
const toastSuccess = (msg) => toast(msg, '#2D6A1E');
const toastError   = (msg) => toast(msg, '#C0392B');
const toastInfo    = (msg) => toast(msg, '#1A5276');

// ─────────────────────────────────────────────────────────
//  UTILS
// ─────────────────────────────────────────────────────────
const fmt = (dateStr) => {
  if (!dateStr) return '—';
  const d = new Date(dateStr);
  return `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')}/${d.getFullYear()}`;
};
const fmtTime = (dateStr) => {
  if (!dateStr) return '—';
  const d = new Date(dateStr);
  return `${fmt(dateStr)} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}:${String(d.getSeconds()).padStart(2,'0')}`;
};

// ─────────────────────────────────────────────────────────
//  REUSABLE PRIMITIVES
// ─────────────────────────────────────────────────────────
function Shimmer({ h = 20, w = '100%' }) {
  return <div className="md-shimmer" style={{ height: h, width: w }} />;
}

function Field({ label, children }) {
  return (
    <div>
      <label style={{ fontSize: 11, fontWeight: 700, color: 'var(--subtle)', display: 'block', marginBottom: 5 }}>{label}</label>
      {children}
    </div>
  );
}

function PwField({ label, value, onChange, placeholder }) {
  const [show, setShow] = useState(false);
  return (
    <Field label={label}>
      <div style={{ position: 'relative' }}>
        <input className="md-field" type={show ? 'text' : 'password'} value={value}
          onChange={e => onChange(e.target.value)} placeholder={placeholder || 'Password'}
          style={{ paddingRight: 38 }} />
        <button type="button" onClick={() => setShow(s => !s)} style={{
          position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)',
          background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)'
        }}>
          {show ? <EyeOff size={14} /> : <Eye size={14} />}
        </button>
      </div>
    </Field>
  );
}

function StatusBadge({ isActive, onClick }) {
  return (
    <span className={isActive ? 'md-status-active' : 'md-status-inactive'} onClick={onClick} style={{ cursor: 'pointer' }}>
      {isActive ? 'सक्रिय' : 'निष्क्रिय'}
    </span>
  );
}

function Toggle({ value, onChange }) {
  return (
    <label className="md-toggle" onClick={() => onChange(!value)}>
      <input type="checkbox" checked={value} onChange={() => {}} />
      <span className="md-toggle-track" />
      <span className="md-toggle-thumb" />
    </label>
  );
}

function Modal({ open, onClose, title, icon: Icon, children, wide }) {
  if (!open) return null;
  return (
    <div className="md-modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="md-modal md-slide-in" style={{ maxWidth: wide ? 640 : 520 }}>
        <div className="md-modal-header">
          {Icon && <Icon size={16} color="var(--border)" />}
          <span style={{ color: 'white', fontWeight: 700, fontSize: 14, flex: 1 }}>{title}</span>
          <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'rgba(255,255,255,0.5)' }}>
            <X size={18} />
          </button>
        </div>
        <div className="md-modal-body">{children}</div>
      </div>
    </div>
  );
}

function ConfirmDialog({ open, title, message, onConfirm, onCancel, danger = true }) {
  if (!open) return null;
  return (
    <div className="md-confirm-overlay">
      <div className="md-confirm-box md-slide-in">
        <div style={{ padding: '14px 18px', background: danger ? 'rgba(192,57,43,0.06)' : 'rgba(0,105,92,0.06)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <AlertTriangle size={18} color={danger ? 'var(--error)' : 'var(--dev)'} />
            <span style={{ fontWeight: 800, fontSize: 15, color: danger ? 'var(--error)' : 'var(--dev)' }}>{title}</span>
          </div>
        </div>
        <div style={{ padding: '14px 18px' }}>
          <p style={{ color: 'var(--dark)', fontSize: 13 }}>{message}</p>
        </div>
        <div style={{ padding: '10px 18px 16px', display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button className="md-btn-outline" style={{ padding: '8px 14px' }} onClick={onCancel}>रद्द करें</button>
          <button className={danger ? 'md-btn-danger' : 'md-btn-primary'} onClick={onConfirm}>पुष्टि करें</button>
        </div>
      </div>
    </div>
  );
}

function PopupMenu({ items }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  useEffect(() => {
    const handler = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);
  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <button onClick={() => setOpen(o => !o)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)', padding: 4, borderRadius: 6, display: 'flex' }}>
        <MoreVertical size={16} />
      </button>
      {open && (
        <div className="md-popup-menu">
          {items.map(it => (
            <button key={it.label} className="md-popup-item"
              style={{ color: it.color || 'var(--dark)' }}
              onClick={() => { setOpen(false); it.onClick(); }}>
              {it.icon && <it.icon size={14} />}
              {it.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function ErrBox({ msg }) {
  if (!msg) return null;
  return (
    <div style={{ background: 'rgba(192,57,43,0.08)', border: '1px solid rgba(192,57,43,0.3)', borderRadius: 8, padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: 'var(--error)' }}>
      <AlertCircle size={14} /> {msg}
    </div>
  );
}

function SectionLabel({ text }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
      <div style={{ width: 4, height: 16, background: 'var(--dev)', borderRadius: 2 }} />
      <span style={{ fontWeight: 800, fontSize: 14, color: 'var(--dark)' }}>{text}</span>
    </div>
  );
}

function StatCard({ label, value, icon: Icon, color }) {
  return (
    <div className="md-card" style={{ padding: '14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div style={{ width: 28, height: 28, borderRadius: 7, background: `${color}18`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Icon size={14} color={color} />
      </div>
      <div>
        <div style={{ fontWeight: 900, fontSize: 22, color }}>{value}</div>
        <div style={{ fontSize: 10.5, color: 'var(--subtle)', fontWeight: 600 }}>{label}</div>
      </div>
    </div>
  );
}

function ListHeader({ title, onRefresh, onAdd, addLabel = 'नया' }) {
  return (
    <div style={{ background: 'var(--surface)', padding: '10px 16px', display: 'flex', alignItems: 'center', gap: 10, borderBottom: '1px solid rgba(212,168,67,0.3)' }}>
      <span style={{ fontWeight: 700, fontSize: 13, color: 'var(--dark)', flex: 1 }}>{title}</span>
      {onRefresh && <button onClick={onRefresh} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)', display: 'flex' }}><RefreshCw size={16} /></button>}
      {onAdd && <button className="md-btn-primary" style={{ padding: '7px 14px' }} onClick={onAdd}><Plus size={13} />{addLabel}</button>}
    </div>
  );
}

function Empty({ msg = 'कोई डेटा नहीं', icon: Icon = Database }) {
  return (
    <div style={{ padding: '60px 20px', textAlign: 'center' }}>
      <Icon size={40} color="var(--border)" style={{ marginBottom: 12 }} />
      <p style={{ color: 'var(--dark)', fontWeight: 700, fontSize: 14 }}>{msg}</p>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
//  RESET PASSWORD MODAL
// ─────────────────────────────────────────────────────────
function ResetPasswordModal({ name, onSave, onClose }) {
  const [pw, setPw] = useState('');
  const [conf, setConf] = useState('');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');

  const handle = async () => {
    if (pw.length < 6) { setErr('न्यूनतम 6 अक्षर'); return; }
    if (pw !== conf) { setErr('पासवर्ड समान नहीं'); return; }
    setSaving(true); setErr('');
    try { await onSave(pw); onClose(); }
    catch (e) { setErr(e.message); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} title={`पासवर्ड रीसेट — ${name}`} icon={Lock}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <ErrBox msg={err} />
        <PwField label="नया पासवर्ड *" value={pw} onChange={setPw} placeholder="न्यूनतम 6 अक्षर" />
        <PwField label="पुष्टि करें *" value={conf} onChange={setConf} placeholder="दोबारा दर्ज करें" />
        <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', paddingTop: 4 }}>
          <button className="md-btn-outline" onClick={onClose}>रद्द करें</button>
          <button className="md-btn-primary" onClick={handle} disabled={saving}>
            {saving ? <RefreshCw size={13} style={{ animation: 'spin 1s linear infinite' }} /> : <><Lock size={13} />रीसेट करें</>}
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────────────────
//  SUPER ADMIN / ADMIN FORM MODAL
// ─────────────────────────────────────────────────────────
function UserFormModal({ title, initial, onSave, onClose, showDistrict = true }) {
  const [form, setForm] = useState({ name: '', username: '', password: '', district: '', ...(initial || {}) });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handle = async () => {
    if (!form.name || !form.username) { setErr('नाम और यूज़रनेम आवश्यक'); return; }
    if (!initial && !form.password) { setErr('पासवर्ड आवश्यक'); return; }
    if (showDistrict && !form.district) { setErr('जनपद चुनें'); return; }
    setSaving(true); setErr('');
    try { await onSave(form); onClose(); }
    catch (e) { setErr(e.message); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} title={title} icon={User}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <ErrBox msg={err} />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <Field label="पूरा नाम *">
            <input className="md-field" value={form.name} onChange={e => set('name', e.target.value)} placeholder="पूरा नाम" />
          </Field>
          <Field label="यूज़रनेम *">
            <input className="md-field" value={form.username} onChange={e => set('username', e.target.value)} placeholder="यूज़रनेम" />
          </Field>
          {showDistrict && (
            <Field label="जनपद *">
              <select className="md-select" value={form.district} onChange={e => set('district', e.target.value)}>
                <option value="">जनपद चुनें</option>
                {UP_DISTRICTS.map(d => <option key={d} value={d}>{d}</option>)}
              </select>
            </Field>
          )}
          {!initial && (
            <PwField label="पासवर्ड *" value={form.password || ''} onChange={v => set('password', v)} />
          )}
        </div>
        <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', paddingTop: 4 }}>
          <button className="md-btn-outline" onClick={onClose}>रद्द करें</button>
          <button className="md-btn-primary" onClick={handle} disabled={saving}>
            {saving ? <RefreshCw size={13} /> : <><Save size={13} />सहेजें</>}
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────────────────
//  ELECTION CONFIG MODAL
// ─────────────────────────────────────────────────────────
function ElectionConfigModal({ existing, onClose, onRefresh }) {
  const isEdit = !!existing;
  const [form, setForm] = useState({
    district: existing?.district || '',
    state: existing?.state || 'उत्तर प्रदेश',
    electionType: existing?.electionType || '',
    phase: existing?.phase || '',
    electionYear: existing?.electionYear || String(new Date().getFullYear()),
    electionDate: existing?.electionDate || '',
    pratahSamay: existing?.pratahSamay || '',
    sayaSamay: existing?.sayaSamay || '',
    instructions: existing?.instructions || '',
  });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handle = async () => {
    if (!form.district || !form.electionType || !form.phase || !form.electionYear || !form.electionDate) {
      setErr('सभी आवश्यक फ़ील्ड भरें'); return;
    }
    setSaving(true); setErr('');
    try {
      const body = { ...form, electionName: `${form.electionType} ${form.electionYear}` };
      if (isEdit) await masterApi.updateElectionConfig(existing.id, body);
      else await masterApi.createElectionConfig(body);
      toastSuccess(isEdit ? 'कॉन्फ़िग अपडेट हुई ✓' : 'नई कॉन्फ़िग सहेजी ✓');
      onRefresh(); onClose();
    } catch (e) { setErr(e.message); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} title={isEdit ? 'कॉन्फ़िग संपादित करें' : 'नई निर्वाचन कॉन्फ़िग'} icon={Vote} wide>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <ErrBox msg={err} />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <Field label="जनपद *">
            <select className="md-select" value={form.district} onChange={e => set('district', e.target.value)} disabled={isEdit}>
              <option value="">जनपद चुनें</option>
              {UP_DISTRICTS.map(d => <option key={d} value={d}>{d}</option>)}
            </select>
          </Field>
          <Field label="राज्य">
            <select className="md-select" value={form.state} onChange={e => set('state', e.target.value)}>
              <option>उत्तर प्रदेश</option>
            </select>
          </Field>
          <Field label="निर्वाचन प्रकार *">
            <select className="md-select" value={form.electionType} onChange={e => set('electionType', e.target.value)}>
              <option value="">प्रकार चुनें</option>
              {ELECTION_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
            </select>
          </Field>
          <Field label="चरण *">
            <select className="md-select" value={form.phase} onChange={e => set('phase', e.target.value)}>
              <option value="">चरण चुनें</option>
              {ELECTION_PHASES.map(p => <option key={p} value={p}>{p}</option>)}
            </select>
          </Field>
          <Field label="वर्ष *">
            <input className="md-field" value={form.electionYear} onChange={e => set('electionYear', e.target.value)} placeholder="2027" maxLength={4} />
          </Field>
          <Field label="मतदान तिथि *">
            <input className="md-field" type="date" value={form.electionDate} onChange={e => set('electionDate', e.target.value)} />
          </Field>
          <Field label="प्रातः समय">
            <input className="md-field" type="time" value={form.pratahSamay} onChange={e => set('pratahSamay', e.target.value)} />
          </Field>
          <Field label="सायं समय">
            <input className="md-field" type="time" value={form.sayaSamay} onChange={e => set('sayaSamay', e.target.value)} />
          </Field>
        </div>
        <Field label="विशेष निर्देश (वैकल्पिक)">
          <textarea className="md-field" rows={3} value={form.instructions} onChange={e => set('instructions', e.target.value)} placeholder="निर्देश यहाँ लिखें..." style={{ resize: 'vertical' }} />
        </Field>
        <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', paddingTop: 4 }}>
          <button className="md-btn-outline" onClick={onClose}>रद्द करें</button>
          <button className="md-btn-primary" onClick={handle} disabled={saving}>
            {saving ? <RefreshCw size={13} /> : <><Save size={13} />{isEdit ? 'अपडेट करें' : 'सहेजें'}</>}
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────────────────
//  CHANGE MASTER PASSWORD MODAL
// ─────────────────────────────────────────────────────────
function ChangeMasterPwModal({ onClose }) {
  const [form, setForm] = useState({ old: '', newPw: '', conf: '' });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handle = async () => {
    if (!form.old) { setErr('वर्तमान पासवर्ड आवश्यक'); return; }
    if (form.newPw.length < 6) { setErr('न्यूनतम 6 अक्षर'); return; }
    if (form.newPw !== form.conf) { setErr('पासवर्ड समान नहीं'); return; }
    setSaving(true); setErr('');
    try {
      await masterApi.changeMasterPw({ oldPassword: form.old, newPassword: form.newPw });
      toastSuccess('पासवर्ड बदला गया ✓');
      onClose();
    } catch (e) { setErr(e.message); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} title="मास्टर पासवर्ड बदलें" icon={Key}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <ErrBox msg={err} />
        <PwField label="वर्तमान पासवर्ड *" value={form.old} onChange={v => set('old', v)} />
        <PwField label="नया पासवर्ड *" value={form.newPw} onChange={v => set('newPw', v)} placeholder="न्यूनतम 6 अक्षर" />
        <PwField label="पुष्टि करें *" value={form.conf} onChange={v => set('conf', v)} />
        <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', paddingTop: 4 }}>
          <button className="md-btn-outline" onClick={onClose}>रद्द करें</button>
          <button className="md-btn-primary" onClick={handle} disabled={saving}>
            {saving ? <RefreshCw size={13} /> : <><Key size={13} />बदलें</>}
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────────────────
//  FORCE LOGOUT MODAL
// ─────────────────────────────────────────────────────────
function ForceLogoutModal({ onClose }) {
  const [roles, setRoles] = useState({ super_admin: false, admin: false, staff: false });
  const [reason, setReason] = useState('');
  const [confirm, setConfirm] = useState(false);
  const [saving, setSaving] = useState(false);

  const selectedRoles = Object.entries(roles).filter(([, v]) => v).map(([k]) => k);

  const handle = async () => {
    if (!selectedRoles.length) { toastError('कम से कम एक भूमिका चुनें'); return; }
    setSaving(true);
    try {
      await masterApi.forceLogout({ roles: selectedRoles, reason });
      toastSuccess(`${selectedRoles.length} भूमिका(एं) लॉगआउट हुईं ✓`);
      onClose();
    } catch (e) { toastError(e.message); }
    finally { setSaving(false); }
  };

  const roleOptions = [
    { key: 'super_admin', label: 'सुपर एडमिन', icon: Shield, color: '#00695C' },
    { key: 'admin', label: 'एडमिन', icon: Users, color: 'var(--primary)' },
    { key: 'staff', label: 'स्टाफ', icon: User, color: 'var(--info)' },
  ];

  return (
    <Modal open onClose={onClose} title="सभी उपयोगकर्ताओं को लॉगआउट करें" icon={LogOut}>
      {confirm ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div style={{ background: 'rgba(192,57,43,0.08)', border: '1px solid rgba(192,57,43,0.3)', borderRadius: 8, padding: 12, fontSize: 13, color: 'var(--error)' }}>
            {selectedRoles.join(', ')} के सभी सत्र समाप्त होंगे। क्या आप सुनिश्चित हैं?
          </div>
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button className="md-btn-outline" onClick={() => setConfirm(false)}>वापस जाएँ</button>
            <button className="md-btn-danger" onClick={handle} disabled={saving}>
              {saving ? <RefreshCw size={13} /> : <><LogOut size={13} />हाँ, लॉगआउट करें</>}
            </button>
          </div>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div style={{ background: 'rgba(192,57,43,0.06)', border: '1px solid rgba(192,57,43,0.25)', borderRadius: 8, padding: 12, display: 'flex', gap: 8, alignItems: 'flex-start' }}>
            <AlertTriangle size={16} color="var(--error)" style={{ flexShrink: 0, marginTop: 1 }} />
            <p style={{ fontSize: 12, color: 'var(--error)', fontWeight: 600 }}>चयनित भूमिकाओं के सभी सक्रिय सत्र तुरंत समाप्त होंगे।</p>
          </div>
          <p style={{ fontWeight: 800, fontSize: 13, color: 'var(--dark)' }}>भूमिकाएँ चुनें:</p>
          {roleOptions.map(r => (
            <label key={r.key} style={{
              display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px',
              borderRadius: 10, cursor: 'pointer',
              background: roles[r.key] ? `${r.color}10` : 'white',
              border: `1px solid ${roles[r.key] ? r.color : 'rgba(212,168,67,0.4)'}`,
            }}>
              <input type="checkbox" checked={roles[r.key]} onChange={e => setRoles(p => ({ ...p, [r.key]: e.target.checked }))} style={{ width: 16, height: 16, accentColor: r.color }} />
              <r.icon size={16} color={r.color} />
              <span style={{ fontWeight: 700, fontSize: 13, color: 'var(--dark)' }}>{r.label}</span>
            </label>
          ))}
          <Field label="कारण (वैकल्पिक)">
            <input className="md-field" value={reason} onChange={e => setReason(e.target.value)} placeholder="कारण लिखें..." />
          </Field>
          <p style={{ fontSize: 11, color: 'var(--subtle)', fontStyle: 'italic' }}>मास्टर अकाउंट सुरक्षित है — लॉगआउट नहीं होगा।</p>
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button className="md-btn-outline" onClick={onClose}>रद्द करें</button>
            <button className="md-btn-danger" onClick={() => { if (!selectedRoles.length) { toastError('कम से कम एक भूमिका चुनें'); return; } setConfirm(true); }}>
              <LogOut size={13} />लॉगआउट करें
            </button>
          </div>
        </div>
      )}
    </Modal>
  );
}

// ─────────────────────────────────────────────────────────
//  TAB 0 — OVERVIEW
// ─────────────────────────────────────────────────────────
function OverviewTab() {
  const [ov, setOv] = useState(null);
  const [sys, setSys] = useState(null);
  const [configs, setConfigs] = useState([]);
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    try {
      const [ovRes, sysRes, cfgRes, logRes] = await Promise.allSettled([
        masterApi.overview(), masterApi.systemStats(), masterApi.getElectionConfigs(false), masterApi.getLogs({ limit: 5 })
      ]);
      if (ovRes.status === 'fulfilled') setOv(ovRes.value?.data || ovRes.value);
      if (sysRes.status === 'fulfilled') setSys(sysRes.value?.data || sysRes.value);
      if (cfgRes.status === 'fulfilled') setConfigs(cfgRes.value?.data || []);
      if (logRes.status === 'fulfilled') setLogs(logRes.value?.data || []);
    } finally { setLoading(false); }
  };

  useEffect(() => { load(); }, []);

  const activeConfigs = configs.filter(c => c.isActive && !c.isArchived);

  const stats = [
    { label: 'सक्रिय निर्वाचन', value: ov?.activeElectionConfigs ?? activeConfigs.length, icon: Vote, color: '#00695C' },
    { label: 'सुपर एडमिन', value: ov?.totalSuperAdmins ?? 0, icon: Shield, color: '#1A5276' },
    { label: 'एडमिन', value: ov?.totalAdmins ?? 0, icon: Users, color: 'var(--accent)' },
    { label: 'स्टाफ', value: ov?.totalStaff ?? 0, icon: User, color: '#6A1B9A' },
    { label: 'बूथ', value: ov?.totalBooths ?? 0, icon: MapPin, color: '#2D6A1E' },
    { label: 'इतिहास', value: ov?.archivedElectionConfigs ?? 0, icon: Archive, color: 'var(--subtle)' },
  ];

  const logColor = (lvl) => lvl === 'ERROR' ? 'var(--error)' : lvl === 'WARN' ? 'var(--warning)' : 'var(--info)';

  return (
    <div style={{ padding: 20, maxWidth: 1100, margin: '0 auto' }}>
      {/* Election Banner */}
      <div style={{
        background: 'linear-gradient(135deg, #1A0A00 0%, #3D1A00 100%)',
        border: '1px solid rgba(212,168,67,0.5)', borderRadius: 14,
        padding: 18, marginBottom: 20, display: 'flex', alignItems: 'center', gap: 14,
      }}>
        <Vote size={28} color="var(--border)" style={{ flexShrink: 0 }} />
        <div style={{ flex: 1 }}>
          {activeConfigs.length > 0 ? (
            <>
              <p style={{ color: 'var(--border)', fontWeight: 800, fontSize: 14 }}>
                {activeConfigs.length} जनपद में सक्रिय निर्वाचन
              </p>
              <p style={{ color: 'rgba(255,255,255,0.55)', fontSize: 11.5, marginTop: 4 }}>
                {activeConfigs.slice(0, 4).map(c => c.district).join('  •  ')}
              </p>
            </>
          ) : (
            <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 13 }}>कोई सक्रिय निर्वाचन कॉन्फ़िग नहीं</p>
          )}
        </div>
      </div>

      {/* Stats Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: 12, marginBottom: 20 }}>
        {loading ? [1,2,3,4,5,6].map(i => <Shimmer key={i} h={90} />) :
          stats.map(s => <StatCard key={s.label} {...s} />)}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        {/* System Stats */}
        {sys && (
          <div>
            <SectionLabel text="सिस्टम जानकारी" />
            <div className="md-card" style={{ overflow: 'hidden' }}>
              {Object.entries(sys).filter(([, v]) => v != null).map(([k, v], i, arr) => (
                <div key={k} style={{
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                  padding: '11px 16px',
                  borderBottom: i < arr.length - 1 ? '1px solid rgba(212,168,67,0.18)' : 'none',
                }}>
                  <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--subtle)' }}>{k.replace(/_/g, ' ')}</span>
                  <span style={{ fontSize: 12, fontWeight: 800, color: 'var(--dark)', fontFamily: 'JetBrains Mono, monospace' }}>{String(v)}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Recent Logs */}
        <div>
          <SectionLabel text="हालिया गतिविधि" />
          <div className="md-card" style={{ overflow: 'hidden' }}>
            {loading ? [1,2,3].map(i => <div key={i} style={{ padding: 12 }}><Shimmer h={18} /></div>) :
              logs.length === 0 ? <Empty msg="कोई लॉग नहीं" icon={FileText} /> :
              logs.map((l, i) => (
                <div key={l.id || i} style={{
                  display: 'flex', alignItems: 'flex-start', gap: 10, padding: '10px 14px',
                  borderBottom: i < logs.length - 1 ? '1px solid rgba(212,168,67,0.18)' : 'none',
                }}>
                  <span style={{
                    background: logColor(l.level), color: 'white', fontSize: 9, fontWeight: 900,
                    padding: '2px 6px', borderRadius: 4, marginTop: 2, flexShrink: 0, letterSpacing: 0.5,
                  }}>{l.level}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <p style={{ fontSize: 12, fontWeight: 600, color: 'var(--dark)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{l.message}</p>
                    <p style={{ fontSize: 10.5, color: 'var(--subtle)', marginTop: 2 }}>{l.module} · {fmtTime(l.time)}</p>
                  </div>
                </div>
              ))
            }
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
//  TAB 1 — ELECTION CONFIGS
// ─────────────────────────────────────────────────────────
function ElectionConfigsTab() {
  const [configs, setConfigs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showArchived, setShowArchived] = useState(false);
  const [modal, setModal] = useState(null); // null | 'create' | existing
  const [confirm, setConfirm] = useState(null);

  const load = async () => {
    setLoading(true);
    try { const r = await masterApi.getElectionConfigs(showArchived); setConfigs(r?.data || []); }
    catch (e) { toastError(e.message); }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); }, [showArchived]);

  const handleArchive = async (id) => {
    try { await masterApi.archiveElectionConfig(id); toastSuccess('आर्काइव हुई ✓'); load(); }
    catch { toastError('आर्काइव विफल'); }
  };

  const handleDelete = async (id) => {
    try { await masterApi.deleteElectionConfig(id); toastSuccess('हटाई गई'); load(); }
    catch { toastError('विफल'); }
  };

  const handleAutoArchive = async () => {
    try { const r = await masterApi.autoArchive(); toastSuccess(`${r?.data?.archived ?? 0} कॉन्फ़िग आर्काइव हुईं ✓`); load(); }
    catch { toastError('विफल'); }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ background: 'var(--surface)', padding: '10px 16px', display: 'flex', alignItems: 'center', gap: 10, borderBottom: '1px solid rgba(212,168,67,0.3)', flexShrink: 0 }}>
        <span style={{ fontWeight: 700, fontSize: 13, color: 'var(--dark)', flex: 1 }}>
          {configs.filter(c => !c.isArchived).length} सक्रिय  ·  {configs.filter(c => c.isArchived).length} इतिहास
        </span>
        <button onClick={() => setShowArchived(s => !s)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)', display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, fontWeight: 600 }}>
          {showArchived ? <EyeOff size={14} /> : <Archive size={14} />}
          {showArchived ? 'इतिहास छुपाएँ' : 'इतिहास दिखाएँ'}
        </button>
        <button onClick={load} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)', display: 'flex' }}><RefreshCw size={15} /></button>
        <button className="md-btn-primary" style={{ padding: '7px 14px' }} onClick={() => setModal('create')}><Plus size={13} />नई कॉन्फ़िग</button>
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
        {loading ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))', gap: 14 }}>
            {[1,2,3].map(i => <Shimmer key={i} h={200} />)}
          </div>
        ) : configs.length === 0 ? <Empty msg="कोई कॉन्फ़िग नहीं" icon={Vote} /> : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(360px, 1fr))', gap: 14 }}>
            {configs.map(cfg => {
              const isHistory = cfg.isArchived;
              return (
                <div key={cfg.id} className="md-card" style={{ overflow: 'hidden' }}>
                  <div style={{
                    padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 10,
                    background: isHistory ? 'rgba(170,136,68,0.1)' : 'rgba(0,105,92,0.08)',
                    borderBottom: '1px solid rgba(212,168,67,0.3)',
                  }}>
                    <Vote size={17} color={isHistory ? 'var(--subtle)' : 'var(--dev)'} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <p style={{ fontWeight: 800, fontSize: 14.5, color: 'var(--dark)' }}>{cfg.district}</p>
                      <p style={{ fontSize: 11.5, color: 'var(--subtle)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{cfg.electionName}</p>
                    </div>
                    <span style={{
                      padding: '2px 10px', borderRadius: 20, fontSize: 10, fontWeight: 800,
                      background: isHistory ? 'rgba(170,136,68,0.15)' : 'rgba(45,106,30,0.1)',
                      color: isHistory ? 'var(--subtle)' : '#2D6A1E',
                      border: `1px solid ${isHistory ? 'var(--subtle)' : '#2D6A1E'}`,
                    }}>{isHistory ? 'इतिहास' : 'सक्रिय'}</span>
                    {!isHistory && (
                      <PopupMenu items={[
                        { label: 'संपादित करें', icon: Pencil, onClick: () => setModal(cfg) },
                        { label: 'आर्काइव', icon: Archive, onClick: () => setConfirm({ type: 'archive', id: cfg.id, district: cfg.district }) },
                        { label: 'हटाएँ', icon: Trash2, color: 'var(--error)', onClick: () => setConfirm({ type: 'delete', id: cfg.id, district: cfg.district }) },
                      ]} />
                    )}
                  </div>
                  <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 7 }}>
                    {[
                      [Flag, 'चरण', cfg.phase],
                      [Vote, 'प्रकार', cfg.electionType],
                      [Calendar, 'तिथि', `${cfg.electionDate} · ${cfg.electionYear}`],
                      cfg.pratahSamay && [Clock, 'समय', `प्रातः ${cfg.pratahSamay}  |  सायं ${cfg.sayaSamay}`],
                      cfg.instructions && [FileText, 'निर्देश', cfg.instructions],
                    ].filter(Boolean).map(([Icon2, k, v]) => (
                      <div key={k} style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
                        <Icon2 size={13} color="var(--subtle)" style={{ marginTop: 2, flexShrink: 0 }} />
                        <span style={{ fontSize: 11.5, color: 'var(--subtle)', fontWeight: 600, width: 60, flexShrink: 0 }}>{k}</span>
                        <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--dark)', flex: 1 }}>{v || '—'}</span>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {(modal === 'create' || (modal && typeof modal === 'object')) && (
        <ElectionConfigModal
          existing={modal !== 'create' ? modal : null}
          onClose={() => setModal(null)}
          onRefresh={load}
        />
      )}

      <ConfirmDialog
        open={!!confirm}
        title={confirm?.type === 'delete' ? 'स्थायी रूप से हटाएँ?' : 'आर्काइव करें?'}
        message={`${confirm?.district} की कॉन्फ़िग ${confirm?.type === 'delete' ? 'हमेशा के लिए हटाई जाएगी।' : 'इतिहास में जाएगी।'}`}
        onConfirm={() => { confirm.type === 'delete' ? handleDelete(confirm.id) : handleArchive(confirm.id); setConfirm(null); }}
        onCancel={() => setConfirm(null)}
      />
    </div>
  );
}

// ─────────────────────────────────────────────────────────
//  TAB 2 — SUPER ADMINS
// ─────────────────────────────────────────────────────────
function SuperAdminsTab() {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(null);
  const [resetTarget, setResetTarget] = useState(null);
  const [deleteId, setDeleteId] = useState(null);
  const [q, setQ] = useState('');

  const load = async () => {
    setLoading(true);
    try { const r = await masterApi.getSuperAdmins(); setList(r?.data || []); }
    catch (e) { toastError(e.message); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);

  const filtered = list.filter(x => !q || x.name?.toLowerCase().includes(q.toLowerCase()) || x.username?.toLowerCase().includes(q.toLowerCase()));

  const handleSave = async (form) => {
    if (modal?.id) await masterApi.updateSuperAdmin(modal.id, form);
    else await masterApi.createSuperAdmin(form);
    toastSuccess(modal?.id ? 'अपडेट हुआ ✓' : 'सुपर एडमिन जोड़ा ✓');
    load();
  };

  const handleDelete = async () => {
    try { await masterApi.deleteSuperAdmin(deleteId); toastSuccess('हटाया गया'); load(); }
    catch { toastError('विफल'); }
    setDeleteId(null);
  };

  const handleToggle = async (sa) => {
    try { await masterApi.toggleSuperAdmin(sa.id, { isActive: !sa.isActive }); load(); }
    catch { toastError('स्थिति अपडेट विफल'); }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <ListHeader title={`${list.length} सुपर एडमिन`} onRefresh={load} onAdd={() => setModal({})} addLabel="नया सुपर एडमिन" />
      <div style={{ padding: '12px 16px', background: 'var(--bg)', borderBottom: '1px solid rgba(212,168,67,0.2)' }}>
        <div className="md-search">
          <Search size={14} color="var(--subtle)" />
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="सुपर एडमिन खोजें..." />
          {q && <button onClick={() => setQ('')} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)', display: 'flex' }}><X size={13} /></button>}
        </div>
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
        {loading ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 12 }}>
            {[1,2,3,4].map(i => <Shimmer key={i} h={140} />)}
          </div>
        ) : filtered.length === 0 ? <Empty msg="कोई सुपर एडमिन नहीं" icon={Shield} /> : (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: 12 }}>
            {filtered.map(sa => (
              <div key={sa.id} className="md-card" style={{ overflow: 'hidden' }}>
                <div style={{
                  padding: '11px 14px', display: 'flex', alignItems: 'center', gap: 10,
                  background: sa.isActive ? 'rgba(0,105,92,0.07)' : 'rgba(192,57,43,0.05)',
                  borderBottom: '1px solid rgba(212,168,67,0.25)',
                }}>
                  <span className="md-id-badge">SA{String(sa.id).padStart(3,'0')}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <p style={{ fontWeight: 700, fontSize: 13.5, color: 'var(--dark)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{sa.name}</p>
                    {sa.district && <p style={{ fontSize: 11, color: 'var(--subtle)' }}>{sa.district}</p>}
                  </div>
                  <StatusBadge isActive={sa.isActive} onClick={() => handleToggle(sa)} />
                  <PopupMenu items={[
                    { label: 'संपादित करें', icon: Pencil, onClick: () => setModal(sa) },
                    { label: 'पासवर्ड रीसेट', icon: Lock, onClick: () => setResetTarget(sa) },
                    { label: 'हटाएँ', icon: Trash2, color: 'var(--error)', onClick: () => setDeleteId(sa.id) },
                  ]} />
                </div>
                <div style={{ padding: '10px 14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: 'var(--subtle)' }}>
                      <AtSign size={12} /> @{sa.username}
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: 'var(--subtle)' }}>
                      <Calendar size={12} /> जोड़ा {fmt(sa.createdAt)}
                    </div>
                  </div>
                  <span className="md-pill" style={{ background: 'rgba(139,105,20,0.1)', color: 'var(--accent)', border: '1px solid rgba(139,105,20,0.3)' }}>
                    {sa.adminsUnder || 0} एडमिन
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {modal !== null && (
        <UserFormModal
          title={modal?.id ? 'सुपर एडमिन संपादित करें' : 'नया सुपर एडमिन'}
          initial={modal?.id ? modal : null}
          onSave={handleSave}
          onClose={() => setModal(null)}
        />
      )}
      {resetTarget && (
        <ResetPasswordModal
          name={resetTarget.name}
          onSave={async (pw) => { await masterApi.resetSuperAdminPw(resetTarget.id, { password: pw }); toastSuccess('पासवर्ड रीसेट ✓'); }}
          onClose={() => setResetTarget(null)}
        />
      )}
      <ConfirmDialog
        open={!!deleteId}
        title="सुपर एडमिन हटाएँ?"
        message="इससे अधीन सभी एडमिन प्रभावित होंगे।"
        onConfirm={handleDelete}
        onCancel={() => setDeleteId(null)}
      />
    </div>
  );
}

// ─────────────────────────────────────────────────────────
//  TAB 3 — ADMINS
// ─────────────────────────────────────────────────────────
function AdminsTab() {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [resetTarget, setResetTarget] = useState(null);
  const [deleteId, setDeleteId] = useState(null);
  const [q, setQ] = useState('');

  const load = async () => {
    setLoading(true);
    try { const r = await masterApi.getAdmins(); setList(r?.data || []); }
    catch (e) { toastError(e.message); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);

  const filtered = list.filter(x => !q || x.name?.toLowerCase().includes(q.toLowerCase()) || x.username?.toLowerCase().includes(q.toLowerCase()));

  const handleCreate = async (form) => {
    await masterApi.createAdmin(form);
    toastSuccess('एडमिन जोड़ा गया ✓');
    load();
  };

  const handleDelete = async () => {
    try { await masterApi.deleteAdmin(deleteId); toastSuccess('हटाया गया'); load(); }
    catch { toastError('विफल'); }
    setDeleteId(null);
  };

  const handleToggle = async (admin) => {
    try { await masterApi.toggleAdmin(admin.id, { isActive: !admin.isActive }); load(); }
    catch { toastError('स्थिति अपडेट विफल'); }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <ListHeader title={`${list.length} एडमिन`} onRefresh={load} onAdd={() => setShowCreate(true)} addLabel="नया एडमिन" />
      <div style={{ padding: '12px 16px', background: 'var(--bg)', borderBottom: '1px solid rgba(212,168,67,0.2)' }}>
        <div className="md-search">
          <Search size={14} color="var(--subtle)" />
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="एडमिन खोजें..." />
          {q && <button onClick={() => setQ('')} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)', display: 'flex' }}><X size={13} /></button>}
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'auto' }}>
        <div className="md-card" style={{ margin: 16, overflow: 'hidden' }}>
          <div style={{ overflowX: 'auto' }}>
            <table className="md-table">
              <thead>
                <tr>
                  <th>ID</th><th>नाम</th><th>यूज़रनेम</th><th>जनपद</th>
                  <th>द्वारा बनाया</th><th style={{ textAlign: 'center' }}>ज़ोन</th>
                  <th>स्थिति</th><th style={{ textAlign: 'center' }}>कार्यवाही</th>
                </tr>
              </thead>
              <tbody>
                {loading ? Array.from({ length: 6 }).map((_, i) => (
                  <tr key={i}>{[1,2,3,4,5,6,7,8].map(j => <td key={j}><Shimmer h={14} /></td>)}</tr>
                )) : filtered.length === 0 ? (
                  <tr><td colSpan={8}><Empty msg="कोई एडमिन नहीं" /></td></tr>
                ) : filtered.map(a => (
                  <tr key={a.id}>
                    <td><span className="md-id-badge">AD{String(a.id).padStart(3,'0')}</span></td>
                    <td style={{ fontWeight: 700, fontSize: 13 }}>{a.name}</td>
                    <td style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 12, color: 'var(--subtle)' }}>@{a.username}</td>
                    <td style={{ fontSize: 12, color: 'var(--subtle)' }}>{a.district || '—'}</td>
                    <td style={{ fontSize: 12, color: 'var(--subtle)' }}>{a.createdBy || '—'}</td>
                    <td style={{ textAlign: 'center', fontWeight: 800, color: 'var(--primary)' }}>{a.superZoneCount || 0}</td>
                    <td><StatusBadge isActive={a.isActive} onClick={() => handleToggle(a)} /></td>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4 }}>
                        <button onClick={() => setResetTarget(a)} title="पासवर्ड रीसेट" style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#B8860B', padding: 4, borderRadius: 4, display: 'flex' }}>
                          <Lock size={14} />
                        </button>
                        <button onClick={() => setDeleteId(a.id)} title="हटाएँ" style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--error)', padding: 4, borderRadius: 4, display: 'flex' }}>
                          <Trash2 size={14} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {showCreate && (
        <UserFormModal title="नया एडमिन" onSave={handleCreate} onClose={() => setShowCreate(false)} />
      )}
      {resetTarget && (
        <ResetPasswordModal
          name={resetTarget.name}
          onSave={async (pw) => { await masterApi.resetAdminPw(resetTarget.id, { password: pw }); toastSuccess('पासवर्ड रीसेट ✓'); }}
          onClose={() => setResetTarget(null)}
        />
      )}
      <ConfirmDialog
        open={!!deleteId}
        title="एडमिन हटाएँ?"
        message="एडमिन स्थायी रूप से हटाया जाएगा।"
        onConfirm={handleDelete}
        onCancel={() => setDeleteId(null)}
      />
    </div>
  );
}

// ─────────────────────────────────────────────────────────
//  TAB 4 — API LOGS
// ─────────────────────────────────────────────────────────
const API_LOGS_LIMIT = 50;

function ApiLogsTab() {
  const [logs, setLogs] = useState([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState(null);
  const [filters, setFilters] = useState({ level: 'ALL', method: 'ALL', status: 'ALL', role: 'ALL', q: '' });
  const [qInput, setQInput] = useState('');

  const load = async (p = page, f = filters) => {
    setLoading(true);
    try {
      const params = {
        limit: API_LOGS_LIMIT, offset: p * API_LOGS_LIMIT,
        ...(f.level !== 'ALL' && { level: f.level }),
        ...(f.method !== 'ALL' && { method: f.method }),
        ...(f.status !== 'ALL' && { status: f.status }),
        ...(f.role !== 'ALL' && { role: f.role }),
        ...(f.q && { q: f.q }),
      };
      const r = await masterApi.getApiLogs(params);
      const d = r?.data || {};
      setLogs(d.items || []);
      setTotal(d.total || 0);
    } catch (e) { toastError(e.message); }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); }, []);

  const applyFilter = (key, val) => {
    const nf = { ...filters, [key]: val };
    setFilters(nf); setPage(0); load(0, nf);
  };

  const applySearch = () => { const nf = { ...filters, q: qInput }; setFilters(nf); setPage(0); load(0, nf); };

  const totalPages = Math.max(1, Math.ceil(total / API_LOGS_LIMIT));

  const methodColor = (m) => ({ GET: '#1565C0', POST: '#2E7D32', PUT: '#E65100', PATCH: '#6A1B9A', DELETE: '#C0392B' }[m] || '#666');
  const statusColor = (s) => s >= 500 ? '#C0392B' : s >= 400 ? '#E65100' : '#2E7D32';
  const roleColor = (r) => ({ master: '#00695C', super_admin: '#4A3000', admin: '#8B6914', staff: '#1A5276' }[r] || '#666');

  const FILTER_OPTS = {
    level: ['ALL','INFO','WARN','ERROR'],
    method: ['ALL','GET','POST','PUT','PATCH','DELETE'],
    status: ['ALL','2xx','4xx','5xx','200','401','403','500'],
    role: ['ALL','master','super_admin','admin','staff'],
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Search */}
      <div style={{ padding: '10px 16px', background: 'var(--surface)', borderBottom: '1px solid rgba(212,168,67,0.3)', display: 'flex', gap: 8 }}>
        <div className="md-search" style={{ flex: 1 }}>
          <Search size={14} color="var(--subtle)" />
          <input value={qInput} onChange={e => setQInput(e.target.value)} onKeyDown={e => e.key === 'Enter' && applySearch()} placeholder="पथ, यूज़र, या त्रुटि खोजें…" />
          {qInput && <button onClick={() => { setQInput(''); applyFilter('q', ''); }} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)', display: 'flex' }}><X size={13} /></button>}
        </div>
        <button className="md-btn-primary" style={{ padding: '8px 14px' }} onClick={applySearch}><Search size={13} />खोजें</button>
        <button onClick={() => load(page)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)', display: 'flex', alignItems: 'center' }}><RefreshCw size={15} /></button>
      </div>

      {/* Filter chips */}
      <div style={{ padding: '8px 16px', background: 'var(--surface)', borderBottom: '1px solid rgba(212,168,67,0.2)', display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        {Object.entries(FILTER_OPTS).map(([key, opts]) => (
          <div key={key} style={{ display: 'flex', alignItems: 'center', gap: 4, background: 'white', border: '1px solid rgba(212,168,67,0.5)', borderRadius: 20, padding: '3px 10px' }}>
            <span style={{ fontSize: 10.5, color: 'var(--subtle)', fontWeight: 600 }}>{key}:</span>
            <select value={filters[key]} onChange={e => applyFilter(key, e.target.value)} style={{ border: 'none', outline: 'none', fontSize: 11.5, fontWeight: 700, color: 'var(--dark)', background: 'transparent', cursor: 'pointer' }}>
              {opts.map(o => <option key={o} value={o}>{o}</option>)}
            </select>
          </div>
        ))}
        <span style={{ marginLeft: 'auto', fontSize: 11.5, color: 'var(--subtle)', fontWeight: 700, alignSelf: 'center' }}>
          कुल: {total}  ·  पृष्ठ {page + 1}/{totalPages}
        </span>
      </div>

      {/* Logs */}
      <div style={{ flex: 1, overflow: 'auto', padding: 12 }}>
        {loading ? Array.from({ length: 8 }).map((_, i) => <div key={i} style={{ marginBottom: 6 }}><Shimmer h={52} /></div>) :
          logs.length === 0 ? <Empty msg="कोई API लॉग नहीं मिला" icon={Cpu} /> : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
            {logs.map(log => {
              const isErr = log.statusCode >= 400;
              const isOpen = expanded === log.id;
              return (
                <div key={log.id} className="md-card" style={{ overflow: 'hidden', border: isErr ? '1px solid rgba(192,57,43,0.3)' : undefined }}>
                  <div style={{ padding: '9px 12px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8 }} onClick={() => setExpanded(isOpen ? null : log.id)}>
                    <span style={{ background: methodColor(log.method), color: 'white', fontSize: 9, fontWeight: 900, padding: '2px 6px', borderRadius: 4, letterSpacing: 0.4, flexShrink: 0 }}>{log.method}</span>
                    <span style={{ background: statusColor(log.statusCode), color: 'white', fontSize: 9.5, fontWeight: 900, padding: '2px 6px', borderRadius: 4, flexShrink: 0 }}>{log.statusCode}</span>
                    <span style={{ flex: 1, fontSize: 12, fontWeight: 700, color: 'var(--dark)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontFamily: 'JetBrains Mono, monospace' }}>{log.path}</span>
                    <span style={{ fontSize: 10, fontWeight: 700, color: 'var(--subtle)', flexShrink: 0 }}>{log.durationMs}ms</span>
                    {log.username && <span style={{ fontSize: 10.5, color: 'var(--subtle)', flexShrink: 0 }}>@{log.username}</span>}
                    {log.role && <span className="md-pill" style={{ background: `${roleColor(log.role)}18`, color: roleColor(log.role), border: `1px solid ${roleColor(log.role)}40`, fontSize: 9.5, padding: '1px 7px', flexShrink: 0 }}>{log.role}</span>}
                    <span style={{ fontSize: 10, color: 'var(--subtle)', flexShrink: 0 }}>{fmtTime(log.createdAt)}</span>
                    <ChevronRight size={13} color="var(--subtle)" style={{ transform: isOpen ? 'rotate(90deg)' : 'none', transition: '0.2s', flexShrink: 0 }} />
                  </div>
                  {isOpen && (
                    <div className="md-expansion-row" style={{ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 7 }}>
                      {log.errorMessage && <div style={{ display: 'flex', gap: 8 }}><span style={{ fontSize: 10.5, fontWeight: 700, color: 'var(--subtle)', width: 70, flexShrink: 0 }}>त्रुटि</span><span style={{ fontSize: 11, color: 'var(--error)', fontFamily: 'JetBrains Mono, monospace', fontWeight: 600, wordBreak: 'break-all' }}>{log.errorMessage}</span></div>}
                      {log.requestBody && <div style={{ display: 'flex', gap: 8 }}><span style={{ fontSize: 10.5, fontWeight: 700, color: 'var(--subtle)', width: 70, flexShrink: 0 }}>बॉडी</span><span style={{ fontSize: 11, color: 'var(--dark)', fontFamily: 'JetBrains Mono, monospace', wordBreak: 'break-all' }}>{log.requestBody}</span></div>}
                      {log.ipAddress && <div style={{ display: 'flex', gap: 8 }}><span style={{ fontSize: 10.5, fontWeight: 700, color: 'var(--subtle)', width: 70, flexShrink: 0 }}>IP</span><span style={{ fontSize: 11, color: 'var(--dark)', fontFamily: 'JetBrains Mono, monospace' }}>{log.ipAddress}</span></div>}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Pagination */}
      {total > 0 && (
        <div style={{ background: 'var(--surface)', padding: '8px 16px', borderTop: '1px solid rgba(212,168,67,0.3)', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
          {[
            [ChevronsLeft, 0, page > 0],
            [ChevronLeft, page - 1, page > 0],
          ].map(([Ic, p, en]) => (
            <button key={p} disabled={!en} onClick={() => { setPage(p); load(p); }} style={{ background: 'none', border: 'none', cursor: en ? 'pointer' : 'not-allowed', color: en ? 'var(--dev)' : 'rgba(170,136,68,0.4)', display: 'flex' }}>
              <Ic size={20} />
            </button>
          ))}
          <span style={{ background: 'var(--dev)', color: 'white', fontWeight: 800, fontSize: 12, padding: '5px 16px', borderRadius: 20 }}>
            {page + 1} / {totalPages}
          </span>
          {[
            [ChevronRight, page + 1, page < totalPages - 1],
            [ChevronsRight, totalPages - 1, page < totalPages - 1],
          ].map(([Ic, p, en]) => (
            <button key={p} disabled={!en} onClick={() => { setPage(p); load(p); }} style={{ background: 'none', border: 'none', cursor: en ? 'pointer' : 'not-allowed', color: en ? 'var(--dev)' : 'rgba(170,136,68,0.4)', display: 'flex' }}>
              <Ic size={20} />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────
//  TAB 5 — SYSTEM LOGS
// ─────────────────────────────────────────────────────────
function SystemLogsTab() {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('ALL');

  const load = async (f = filter) => {
    setLoading(true);
    try { const r = await masterApi.getLogs({ level: f === 'ALL' ? undefined : f, limit: 100 }); setLogs(r?.data || []); }
    catch (e) { toastError(e.message); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);

  const logColor = (lvl) => ({ ERROR: 'var(--error)', WARN: 'var(--warning)', DEBUG: '#666' }[lvl] || 'var(--info)');

  const filtered = filter === 'ALL' ? logs : logs.filter(l => l.level === filter);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ background: 'var(--surface)', padding: '10px 16px', display: 'flex', alignItems: 'center', gap: 8, borderBottom: '1px solid rgba(212,168,67,0.3)', flexWrap: 'wrap' }}>
        <span style={{ fontWeight: 700, fontSize: 13, color: 'var(--dark)', flex: 1 }}>{logs.length} लॉग</span>
        {['ALL','INFO','WARN','ERROR'].map(f => (
          <button key={f} className={`md-filter-chip${filter === f ? ' active' : ''}`}
            style={filter === f ? {} : { color: logColor(f) }}
            onClick={() => { setFilter(f); load(f); }}>
            {f}
          </button>
        ))}
        <button onClick={() => load()} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--subtle)', display: 'flex' }}><RefreshCw size={15} /></button>
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: 12 }}>
        {loading ? Array.from({ length: 8 }).map((_, i) => <div key={i} style={{ marginBottom: 8 }}><Shimmer h={56} /></div>) :
          filtered.length === 0 ? <Empty msg="कोई लॉग नहीं" icon={FileText} /> : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
            {filtered.map((l, i) => {
              const color = logColor(l.level);
              return (
                <div key={l.id || i} style={{
                  display: 'flex', alignItems: 'flex-start', gap: 10,
                  padding: '10px 14px', borderRadius: 10,
                  background: `${color}08`, border: `1px solid ${color}22`,
                }}>
                  <span style={{ background: color, color: 'white', fontSize: 9, fontWeight: 900, padding: '2px 6px', borderRadius: 4, marginTop: 2, flexShrink: 0, letterSpacing: 0.5 }}>{l.level}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <p style={{ fontSize: 12.5, fontWeight: 600, color: 'var(--dark)' }}>{l.message}</p>
                    <p style={{ fontSize: 11, color: 'var(--subtle)', marginTop: 3 }}>{l.module} · {fmtTime(l.time)}</p>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────
//  TAB 6 — SETTINGS / CONFIG
// ─────────────────────────────────────────────────────────
function ConfigTab() {
  const [config, setConfig] = useState({});
  const [loading, setLoading] = useState(true);
  const [masterPwModal, setMasterPwModal] = useState(false);

  const load = async () => {
    setLoading(true);
    try { const r = await masterApi.getConfig(); setConfig(r?.data || r || {}); }
    catch (e) { toastError(e.message); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);

  const updateConfig = async (key, value) => {
    try { await masterApi.updateConfig({ key, value }); toastSuccess('अपडेट हुई ✓'); load(); }
    catch { toastError('विफल'); }
  };

  const runMigration = async () => {
    try { await masterApi.runMigrations(); toastSuccess('माइग्रेशन पूरा ✓'); }
    catch { toastError('माइग्रेशन विफल'); }
  };

  const autoArchive = async () => {
    try { const r = await masterApi.autoArchive(); toastSuccess(`${r?.data?.archived ?? 0} आर्काइव हुईं ✓`); }
    catch { toastError('विफल'); }
  };

  const clearApiLogs = async () => {
    try { const r = await masterApi.clearApiLogs(30); toastSuccess(`${r?.data?.deleted ?? 0} लॉग हटाए`); }
    catch { toastError('विफल'); }
  };

  if (loading) return <div style={{ padding: 20 }}>{[1,2,3].map(i => <div key={i} style={{ marginBottom: 12 }}><Shimmer h={80} /></div>)}</div>;

  const TOGGLE_KEYS = [
    { key: 'maintenanceMode', label: 'मेंटेनेंस मोड', sub: 'सभी उपयोगकर्ताओं के लिए ऐप अक्षम करें' },
    { key: 'allowStaffLogin', label: 'स्टाफ लॉगिन', sub: 'स्टाफ का लॉगिन सक्षम/अक्षम करें', inverted: true },
    { key: 'forcePasswordReset', label: 'पासवर्ड रीसेट अनिवार्य', sub: 'अगले लॉगिन पर सभी एडमिन को रीसेट' },
  ];

  const KNOWN_KEYS = ['maintenanceMode', 'allowStaffLogin', 'forcePasswordReset'];
  const otherKeys = Object.keys(config).filter(k => !KNOWN_KEYS.includes(k));

  const devActions = [
    { icon: Archive, label: 'पुरानी कॉन्फ़िग आर्काइव करें', sub: 'समाप्त निर्वाचन तिथियों को इतिहास में', fn: autoArchive },
    { icon: Wrench, label: 'DB माइग्रेशन चलाएँ', sub: 'डेटाबेस स्कीमा अपडेट', fn: runMigration },
    { icon: Key, label: 'मास्टर पासवर्ड बदलें', sub: 'मास्टर अकाउंट का पासवर्ड', fn: () => setMasterPwModal(true) },
    { icon: Trash2, label: 'पुराने API लॉग साफ़ करें', sub: '30 दिन से पुराने लॉग हटाएँ', fn: clearApiLogs },
  ];

  return (
    <div style={{ padding: 20, maxWidth: 760, margin: '0 auto', overflowY: 'auto', height: '100%' }}>
      {/* Application toggles */}
      <SectionLabel text="एप्लिकेशन सेटिंग्स" />
      <div className="md-card" style={{ overflow: 'hidden', marginBottom: 24 }}>
        {TOGGLE_KEYS.map(({ key, label, sub, inverted }) => {
          const raw = config[key]?.toString();
          const isOn = inverted ? raw !== 'false' : raw === 'true';
          return (
            <div key={key} className="md-config-row">
              <div>
                <p style={{ fontWeight: 700, fontSize: 13, color: 'var(--dark)' }}>{label}</p>
                <p style={{ fontSize: 11.5, color: 'var(--subtle)' }}>{sub}</p>
              </div>
              <Toggle value={isOn} onChange={(v) => updateConfig(key, inverted ? String(!v) : String(v))} />
            </div>
          );
        })}
      </div>

      {/* All config keys */}
      {otherKeys.length > 0 && (
        <>
          <SectionLabel text="सभी कॉन्फ़िग कीज़" />
          <div className="md-card" style={{ overflow: 'hidden', marginBottom: 24 }}>
            {otherKeys.map((k, i) => (
              <div key={k} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '11px 16px', borderBottom: i < otherKeys.length - 1 ? '1px solid rgba(212,168,67,0.2)' : 'none' }}>
                <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--subtle)', fontFamily: 'JetBrains Mono, monospace' }}>{k}</span>
                <span style={{ fontSize: 12, fontWeight: 800, color: 'var(--dark)', fontFamily: 'JetBrains Mono, monospace' }}>{String(config[k] ?? '')}</span>
              </div>
            ))}
          </div>
        </>
      )}

      {/* Developer tools */}
      <SectionLabel text="डेवलपर टूल्स" />
      <div className="md-card" style={{ overflow: 'hidden', marginBottom: 24 }}>
        {devActions.map(({ icon: Icon, label, sub, fn }) => (
          <button key={label} className="md-dev-action" onClick={fn} style={{ width: '100%', textAlign: 'left' }}>
            <div style={{ width: 34, height: 34, borderRadius: 8, background: 'var(--devLight)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <Icon size={16} color="var(--dev)" />
            </div>
            <div style={{ flex: 1 }}>
              <p style={{ fontWeight: 700, fontSize: 13, color: 'var(--dark)' }}>{label}</p>
              <p style={{ fontSize: 11, color: 'var(--subtle)' }}>{sub}</p>
            </div>
            <ChevronRight size={15} color="var(--subtle)" />
          </button>
        ))}
      </div>

      {masterPwModal && <ChangeMasterPwModal onClose={() => setMasterPwModal(false)} />}
    </div>
  );
}

// ─────────────────────────────────────────────────────────
//  MAIN DASHBOARD
// ─────────────────────────────────────────────────────────
const TABS = [
  { key: 'overview',    label: 'सारांश',       icon: BarChart3,   component: OverviewTab },
  { key: 'elections',   label: 'निर्वाचन',      icon: Vote,        component: ElectionConfigsTab },
  { key: 'superadmins', label: 'सुपर एडमिन',   icon: Shield,      component: SuperAdminsTab },
  { key: 'admins',      label: 'एडमिन',         icon: Users,       component: AdminsTab },
  { key: 'apilogs',     label: 'API लॉग',       icon: Cpu,         component: ApiLogsTab },
  { key: 'syslogs',     label: 'सिस्टम लॉग',    icon: FileText,    component: SystemLogsTab },
  { key: 'config',      label: 'सेटिंग्स',       icon: Settings,    component: ConfigTab },
];

export default function MasterDashboard() {
  const [activeTab, setActiveTab] = useState('overview');
  const [forceLogoutModal, setForceLogoutModal] = useState(false);
  const [dbToolsModal, setDbToolsModal] = useState(false);
  const [dbLoading, setDbLoading] = useState(null);

  const ActivePage = TABS.find(t => t.key === activeTab)?.component || OverviewTab;

  const runDbTool = async (key, fn, successMsg) => {
    setDbLoading(key);
    try { await fn(); toastSuccess(successMsg); }
    catch { toastError('विफल'); }
    finally { setDbLoading(null); setDbToolsModal(false); }
  };

  const logout = () => {
    localStorage.clear();
    sessionStorage.clear();
    window.location.href = '/login';
  };

  return (
    <>
      <style>{STYLE}</style>
      <Toast />

      <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', background: 'var(--bg)', fontFamily: 'Tiro Devanagari Hindi, Georgia, serif' }}>

        {/* TOP BAR */}
        <div style={{ background: '#1A0A00', padding: '0 14px', display: 'flex', alignItems: 'center', gap: 10, height: 48, flexShrink: 0, borderBottom: '1px solid rgba(212,168,67,0.3)' }}>
          <div style={{ background: 'var(--dev)', borderRadius: 6, padding: '3px 8px', display: 'flex', alignItems: 'center', gap: 5, flexShrink: 0 }}>
            <Terminal size={11} color="white" />
            <span style={{ color: 'white', fontSize: 10, fontWeight: 900, letterSpacing: 1.5 }}>MASTER</span>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <p style={{ color: 'var(--border)', fontSize: 11, fontWeight: 800, letterSpacing: 1.2 }}>मास्टर एडमिन कंसोल</p>
            <p style={{ color: 'rgba(255,255,255,0.45)', fontSize: 9.5, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>Election Management — Developer Access</p>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <TopBarBtn icon={LogOut} label="लॉगआउट सभी" onClick={() => setForceLogoutModal(true)} />
            <TopBarBtn icon={Database} label="DB" onClick={() => setDbToolsModal(true)} />
            <TopBarBtn icon={RefreshCw} label="रिफ्रेश" onClick={() => window.location.reload()} />
            <button onClick={logout} title="लॉगआउट" style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'rgba(255,255,255,0.45)', display: 'flex', padding: 6, borderRadius: 6 }}>
              <Power size={17} />
            </button>
          </div>
        </div>

        {/* TAB BAR */}
        <div style={{ background: 'var(--surface)', borderBottom: '1px solid rgba(212,168,67,0.35)', overflowX: 'auto', flexShrink: 0, display: 'flex' }}>
          {TABS.map(t => (
            <button key={t.key} className={`md-tab${activeTab === t.key ? ' active' : ''}`} onClick={() => setActiveTab(t.key)}>
              <t.icon size={14} />
              {t.label}
            </button>
          ))}
        </div>

        {/* CONTENT */}
        <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
          <ActivePage key={activeTab} />
        </div>
      </div>

      {/* FORCE LOGOUT MODAL */}
      {forceLogoutModal && <ForceLogoutModal onClose={() => setForceLogoutModal(false)} />}

      {/* DB TOOLS MODAL */}
      {dbToolsModal && (
        <Modal open onClose={() => setDbToolsModal(false)} title="डेटाबेस टूल्स" icon={Database}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {[
              { key: 'backup', icon: HardDrive, color: '#2D6A1E', bg: '#e6f4ea', label: 'बैकअप बनाएँ', sub: 'पूरा MySQL डंप सर्वर पर', fn: () => runDbTool('backup', masterApi.dbBackup, 'बैकअप पूरा ✓') },
              { key: 'flush', icon: Zap, color: '#1A5276', bg: '#e8f4fd', label: 'कैश साफ़ करें', sub: 'सर्वर रिस्पॉन्स कैश', fn: () => runDbTool('flush', masterApi.flushCache, 'कैश साफ़ हुआ ✓') },
              { key: 'migrate', icon: Wrench, color: '#E65100', bg: '#fef5e7', label: 'माइग्रेशन चलाएँ', sub: 'DB स्कीमा अपडेट', fn: () => runDbTool('migrate', masterApi.runMigrations, 'माइग्रेशन पूरा ✓') },
            ].map(t => (
              <button key={t.key} onClick={t.fn} disabled={!!dbLoading} style={{
                width: '100%', display: 'flex', alignItems: 'center', gap: 12,
                padding: '12px 14px', borderRadius: 10, cursor: 'pointer', border: '1px solid rgba(212,168,67,0.3)',
                background: dbLoading === t.key ? t.bg : 'white', textAlign: 'left',
              }}>
                <div style={{ width: 36, height: 36, borderRadius: 8, background: t.bg, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  {dbLoading === t.key ? <RefreshCw size={15} color={t.color} style={{ animation: 'spin 1s linear infinite' }} /> : <t.icon size={16} color={t.color} />}
                </div>
                <div style={{ flex: 1 }}>
                  <p style={{ fontWeight: 700, fontSize: 13, color: 'var(--dark)' }}>{t.label}</p>
                  <p style={{ fontSize: 11, color: 'var(--subtle)' }}>{t.sub}</p>
                </div>
                <ChevronRight size={14} color="var(--subtle)" />
              </button>
            ))}
          </div>
        </Modal>
      )}

      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </>
  );
}

function TopBarBtn({ icon: Icon, label, onClick }) {
  return (
    <button onClick={onClick} style={{
      background: 'none', border: 'none', cursor: 'pointer',
      color: 'var(--border)', display: 'flex', alignItems: 'center', gap: 4,
      padding: '4px 7px', borderRadius: 6, fontSize: 10.5, fontWeight: 700,
      transition: 'background 0.15s',
    }}
      onMouseEnter={e => e.currentTarget.style.background = 'rgba(212,168,67,0.12)'}
      onMouseLeave={e => e.currentTarget.style.background = 'none'}>
      <Icon size={13} />
      {label}
    </button>
  );
}