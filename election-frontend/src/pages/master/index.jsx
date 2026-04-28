import { useState, useEffect } from 'react';
import {
  Shield, Users, MapPin, Vote, Activity, Plus, Pencil, Trash2,
  Eye, EyeOff, Save, AlertCircle, CheckCircle, XCircle, RefreshCw,
  ChevronRight, Lock, Database, Settings, ToggleLeft, ToggleRight,
  Terminal, Key, Zap, Wrench, Info, LogOut
} from 'lucide-react';
import AppShell from '../../components/layout/AppShell';
import { masterApi } from '../../api/endpoints';
import { StatCard, Modal, ConfirmDialog, Empty, Shimmer, SectionHeader, SearchBar } from '../../components/common';
import toast from 'react-hot-toast';
import MapViewButton from '../../components/common/Mapviewbutton';
import { useNavigate } from 'react-router-dom';

// ─────────────────────────────────────────────
//  UP DISTRICTS LIST
// ─────────────────────────────────────────────
const UP_DISTRICTS = [
  'आगरा','आज़मगढ़','बिजनौर','इटावा','अलीगढ़','बागपत','बदायूं','फर्रुखाबाद',
  'अंबेडकर नगर','बहराइच','बुलंदशहर','फतेहपुर','अमेठी','बलिया','चंदौली',
  'फिरोजाबाद','अमरोहा','बलरामपुर','चित्रकूट','गौतम बुद्ध नगर','औरैया','बांदा',
  'देवरिया','गाज़ियाबाद','अयोध्या','बाराबंकी','एटा','गाज़ीपुर','गोंडा','जालौन',
  'कासगंज','लखनऊ','गोरखपुर','जौनपुर','कौशांबी','महाराजगंज','हमीरपुर','झांसी',
  'कुशीनगर','महोबा','हापुड़','कन्नौज','लखीमपुर खीरी','मैनपुरी','हरदोई',
  'कानपुर देहात','ललितपुर','मथुरा','हाथरस','कानपुर नगर','मऊ','पीलीभीत',
  'संभल','सोनभद्र','मेरठ','प्रतापगढ़','संतकबीर नगर','सुल्तानपुर','मिर्जापुर',
  'प्रयागराज','भदोही (संत रविदास नगर)','उन्नाव','मुरादाबाद','रायबरेली','शाहजहाँपुर',
  'वाराणसी','मुजफ्फरनगर','रामपुर','शामली','सहारनपुर','श्रावस्ती','सिद्धार्थनगर','सीतापुर',
];

// ─────────────────────────────────────────────
//  SHARED FIELD COMPONENT
// ─────────────────────────────────────────────
function Field({ label, children }) {
  return (
    <div>
      <label className="text-xs font-semibold text-subtle mb-1 block">{label}</label>
      {children}
    </div>
  );
}

function PasswordField({ label, value, onChange, placeholder = 'Password' }) {
  const [show, setShow] = useState(false);
  return (
    <Field label={label}>
      <div className="relative">
        <input
          className="field pr-9"
          type={show ? 'text' : 'password'}
          value={value}
          onChange={e => onChange(e.target.value)}
          placeholder={placeholder}
        />
        <button type="button" className="absolute right-3 top-1/2 -translate-y-1/2" onClick={() => setShow(s => !s)}>
          {show ? <EyeOff size={14} className="text-subtle" /> : <Eye size={14} className="text-subtle" />}
        </button>
      </div>
    </Field>
  );
}

// ─────────────────────────────────────────────
//  USER FORM MODAL (create/edit with district)
// ─────────────────────────────────────────────
function UserModal({ title, initial, onSave, onClose, showDistrict = false }) {
  const [form, setForm] = useState({
    name: '', username: '', password: '', district: '', ...(initial || {})
  });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handleSave = async () => {
    if (!form.name || !form.username) { setErr('Name and username are required'); return; }
    if (!initial && !form.password) { setErr('Password is required'); return; }
    if (showDistrict && !form.district) { setErr('Please select a district'); return; }
    setSaving(true); setErr('');
    try { await onSave(form); onClose(); }
    catch (e) { setErr(e.message || 'Failed to save'); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} title={title}>
      <div className="space-y-3">
        {err && (
          <div className="text-xs text-red-700 bg-red-50 p-2.5 rounded-lg border border-red-200 flex items-center gap-2">
            <AlertCircle size={13} /> {err}
          </div>
        )}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Field label="Full Name *">
            <input className="field" value={form.name} onChange={e => set('name', e.target.value)} placeholder="Full Name" />
          </Field>
          <Field label="Username *">
            <input className="field" value={form.username} onChange={e => set('username', e.target.value)} placeholder="Username" />
          </Field>
          {showDistrict && (
            <Field label="District *">
              <select className="field" value={form.district} onChange={e => set('district', e.target.value)}>
                <option value="">Select District</option>
                {UP_DISTRICTS.map(d => <option key={d} value={d}>{d}</option>)}
              </select>
            </Field>
          )}
          {!initial && (
            <PasswordField label="Password *" value={form.password || ''} onChange={v => set('password', v)} />
          )}
        </div>
        <div className="flex gap-3 justify-end pt-1">
          <button className="btn-outline px-4 py-2 text-sm" onClick={onClose}>Cancel</button>
          <button className="btn-primary px-5 py-2 text-sm flex items-center gap-2" onClick={handleSave} disabled={saving}>
            {saving
              ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              : <><Save size={14} /> Save</>
            }
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────
//  RESET PASSWORD MODAL
// ─────────────────────────────────────────────
function ResetPasswordModal({ name, onSave, onClose }) {
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');

  const handleSave = async () => {
    if (password.length < 6) { setErr('Password must be at least 6 characters'); return; }
    if (password !== confirm) { setErr('Passwords do not match'); return; }
    setSaving(true); setErr('');
    try { await onSave(password); onClose(); }
    catch (e) { setErr(e.message || 'Failed'); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} title={`Reset Password — ${name}`}>
      <div className="space-y-3">
        {err && (
          <div className="text-xs text-red-700 bg-red-50 p-2.5 rounded-lg border border-red-200 flex items-center gap-2">
            <AlertCircle size={13} /> {err}
          </div>
        )}
        <PasswordField label="New Password" value={password} onChange={setPassword} placeholder="Min 6 characters" />
        <PasswordField label="Confirm Password" value={confirm} onChange={setConfirm} placeholder="Repeat password" />
        <div className="flex gap-3 justify-end pt-1">
          <button className="btn-outline px-4 py-2 text-sm" onClick={onClose}>Cancel</button>
          <button className="btn-primary px-5 py-2 text-sm flex items-center gap-2" onClick={handleSave} disabled={saving}>
            {saving
              ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              : <><Lock size={14} /> Reset</>
            }
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────
//  CHANGE MASTER PASSWORD MODAL
// ─────────────────────────────────────────────
function ChangeMasterPasswordModal({ onClose }) {
  const [form, setForm] = useState({ oldPassword: '', newPassword: '', confirm: '' });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handleSave = async () => {
    if (!form.oldPassword) { setErr('Current password required'); return; }
    if (form.newPassword.length < 6) { setErr('New password must be at least 6 characters'); return; }
    if (form.newPassword !== form.confirm) { setErr('Passwords do not match'); return; }
    setSaving(true); setErr('');
    try {
      await masterApi.changePassword({ oldPassword: form.oldPassword, newPassword: form.newPassword });
      toast.success('Password changed ✓');
      onClose();
    } catch (e) { setErr(e.message || 'Failed'); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} title="Change Master Password">
      <div className="space-y-3">
        {err && (
          <div className="text-xs text-red-700 bg-red-50 p-2.5 rounded-lg border border-red-200 flex items-center gap-2">
            <AlertCircle size={13} /> {err}
          </div>
        )}
        <PasswordField label="Current Password" value={form.oldPassword} onChange={v => set('oldPassword', v)} placeholder="Current password" />
        <PasswordField label="New Password" value={form.newPassword} onChange={v => set('newPassword', v)} placeholder="Min 6 characters" />
        <PasswordField label="Confirm New Password" value={form.confirm} onChange={v => set('confirm', v)} placeholder="Repeat new password" />
        <div className="flex gap-3 justify-end pt-1">
          <button className="btn-outline px-4 py-2 text-sm" onClick={onClose}>Cancel</button>
          <button className="btn-primary px-5 py-2 text-sm flex items-center gap-2" onClick={handleSave} disabled={saving}>
            {saving
              ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              : <><Key size={14} /> Change</>
            }
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────
//  DB TOOLS MODAL
// ─────────────────────────────────────────────
function DbToolsModal({ onClose }) {
  const [loading, setLoading] = useState(null);

  const runTool = async (key, apiFn, successMsg, errorMsg) => {
    setLoading(key);
    try {
      await apiFn();
      toast.success(successMsg);
    } catch {
      toast.error(errorMsg);
    } finally {
      setLoading(null);
      onClose();
    }
  };

  const tools = [
    {
      key: 'backup',
      icon: Database,
      color: '#2D6A1E',
      bg: '#e6f4ea',
      title: 'Backup Database',
      subtitle: 'Export full MySQL dump to server',
      action: () => runTool('backup', () => masterApi.dbBackup(), 'Backup completed ✓', 'Backup failed'),
    },
    {
      key: 'flush',
      icon: Zap,
      color: '#1A5276',
      bg: '#e8f4fd',
      title: 'Flush Cache',
      subtitle: 'Clear server-side response cache',
      action: () => runTool('flush', () => masterApi.flushCache(), 'Cache flushed ✓', 'Failed to flush cache'),
    },
    {
      key: 'migrate',
      icon: Wrench,
      color: '#E67E22',
      bg: '#fef5e7',
      title: 'Run Migrations',
      subtitle: 'Apply DB schema updates safely',
      action: () => runTool('migrate', () => masterApi.runMigrations(), 'Migrations completed ✓', 'Migration failed'),
    },
  ];

  return (
    <Modal open onClose={onClose} title="Database Tools">
      <div className="space-y-2">
        {tools.map(t => (
          <button
            key={t.key}
            onClick={t.action}
            disabled={!!loading}
            className="w-full flex items-center gap-3 p-3 rounded-xl border hover:shadow-sm transition-all text-left"
            style={{ borderColor: 'rgba(212,168,67,0.25)', background: loading === t.key ? t.bg : 'white' }}
          >
            <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0" style={{ background: t.bg }}>
              {loading === t.key
                ? <div className="w-4 h-4 border-2 border-current rounded-full animate-spin" style={{ color: t.color }} />
                : <t.icon size={16} style={{ color: t.color }} />
              }
            </div>
            <div className="flex-1">
              <p className="text-sm font-bold text-dark">{t.title}</p>
              <p className="text-xs text-subtle">{t.subtitle}</p>
            </div>
            <ChevronRight size={14} className="text-subtle" />
          </button>
        ))}
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────
//  ELECTION BANNER (Overview)
// ─────────────────────────────────────────────
function ElectionBanner({ overview, config, onEdit }) {
  const ei = overview?.electionInfo || {};
  const state  = ei.state  || config?.state  || '';
  const year   = ei.electionYear || config?.electionYear || '';
  const date   = ei.electionDate || config?.electionDate || '';
  const phase  = ei.phase  || config?.phase  || '';
  const hasData = state || year;

  return (
    <div className="rounded-xl p-4 mb-4 flex items-center gap-4"
      style={{ background: 'linear-gradient(135deg, #1A0A00 0%, #3D1A00 100%)', border: '1px solid rgba(212,168,67,0.4)' }}>
      <Vote size={28} style={{ color: 'var(--border, #D4A843)', flexShrink: 0 }} />
      <div className="flex-1 min-w-0">
        {hasData ? (
          <>
            <p className="font-bold text-sm" style={{ color: '#D4A843' }}>{state} Election {year}</p>
            {(phase || date) && <p className="text-xs text-white/60 mt-0.5">{phase}{phase && date ? '  •  ' : ''}{date}</p>}
          </>
        ) : (
          <p className="text-white/60 text-sm">No election details configured yet</p>
        )}
      </div>
      <button
        onClick={onEdit}
        className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold text-white flex-shrink-0"
        style={{ background: '#00695C' }}
      >
        <Pencil size={11} /> Edit
      </button>
    </div>
  );
}

// ─────────────────────────────────────────────
//  ELECTION CONFIG MODAL
// ─────────────────────────────────────────────
function ElectionConfigModal({ initial, onSave, onClose }) {
  const [form, setForm] = useState({
    state: '', electionYear: '', electionDate: '', phase: '', ...(initial || {})
  });
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handleSave = async () => {
    if (!form.state || !form.electionYear || !form.electionDate || !form.phase) {
      setErr('All fields are required'); return;
    }
    setSaving(true); setErr('');
    try { await onSave(form); onClose(); }
    catch (e) { setErr(e.message || 'Failed'); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} title="Edit Election Settings">
      <div className="space-y-3">
        {err && (
          <div className="text-xs text-red-700 bg-red-50 p-2.5 rounded-lg border border-red-200 flex items-center gap-2">
            <AlertCircle size={13} /> {err}
          </div>
        )}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Field label="State *">
            <input className="field" value={form.state} onChange={e => set('state', e.target.value)} placeholder="e.g. Uttar Pradesh" />
          </Field>
          <Field label="Election Year *">
            <input className="field" value={form.electionYear} onChange={e => set('electionYear', e.target.value)} placeholder="e.g. 2027" />
          </Field>
          <Field label="Election Date *">
            <input className="field" type="date" value={form.electionDate} onChange={e => set('electionDate', e.target.value)} />
          </Field>
          <Field label="Phase *">
            <input className="field" value={form.phase} onChange={e => set('phase', e.target.value)} placeholder="e.g. Phase 1" />
          </Field>
        </div>
        <div className="flex gap-3 justify-end pt-1">
          <button className="btn-outline px-4 py-2 text-sm" onClick={onClose}>Cancel</button>
          <button className="btn-primary px-5 py-2 text-sm flex items-center gap-2" onClick={handleSave} disabled={saving}>
            {saving
              ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              : <><Save size={14} /> Save</>
            }
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────
//  STATUS BADGE
// ─────────────────────────────────────────────
function StatusBadge({ isActive, onClick }) {
  return (
    <button
      onClick={onClick}
      title="Toggle status"
      className="badge text-[10px] font-bold cursor-pointer hover:opacity-80 transition-opacity"
      style={{
        background: isActive ? '#e6f4ea' : '#fdecea',
        color: isActive ? '#2D6A1E' : '#C0392B',
        border: `1px solid ${isActive ? '#2D6A1E' : '#C0392B'}`,
        padding: '3px 8px',
        borderRadius: 20,
      }}
    >
      {isActive ? 'ACTIVE' : 'INACTIVE'}
    </button>
  );
}

// ─────────────────────────────────────────────
//  TAB 0 — OVERVIEW
// ─────────────────────────────────────────────
function OverviewTab() {
  const [ov, setOv] = useState(null);
  const [sys, setSys] = useState(null);
  const [config, setConfig] = useState(null);
  const [loading, setLoading] = useState(true);
  const [showElectionModal, setShowElectionModal] = useState(false);
  const nav = useNavigate();

  const load = () => {
    setLoading(true);
    Promise.all([masterApi.overview(), masterApi.getSystemStats(), masterApi.getConfig()])
      .then(([ovRes, sysRes, cfgRes]) => {
        setOv(ovRes.data || ovRes);
        setSys(sysRes.data || sysRes);
        setConfig(cfgRes.data || cfgRes);
      })
      .catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  const handleSaveElection = async (form) => {
    await masterApi.updateConfig(form);
    toast.success('Election settings updated ✓');
    load();
  };

  const statItems = ov ? [
    { label: 'Super Admins',    value: ov.totalSuperAdmins ?? 0,  icon: Shield, color: '#1A5276' },
    { label: 'Total Admins',    value: ov.totalAdmins      ?? 0,  icon: Users,  color: '#8B6914' },
    { label: 'Total Staff',     value: ov.totalStaff       ?? 0,  icon: Users,  color: '#B8860B' },
    { label: 'Assigned Duties', value: ov.assignedDuties   ?? 0,  icon: Vote,   color: '#2D6A1E' },
  ] : [];

  return (
    <div className="p-4 max-w-4xl mx-auto">
      {/* Election Banner */}
      <ElectionBanner
        overview={ov}
        config={config}
        onEdit={() => setShowElectionModal(true)}
      />

      {/* Stats Grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        {loading
          ? [1, 2, 3, 4].map(i => <Shimmer key={i} className="h-24" />)
          : statItems.map(s => <StatCard key={s.label} {...s} />)
        }
      </div>

      {/* System Stats */}
      {sys && (
        <div className="card p-4 mb-4">
          <h3 className="font-bold text-dark mb-3 text-sm flex items-center gap-2">
            <Activity size={16} className="text-primary" /> System Statistics
          </h3>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {Object.entries(sys).filter(([, v]) => v != null).map(([k, v]) => (
              <div key={k} className="rounded-lg p-2.5" style={{ background: 'var(--surface)', border: '1px solid rgba(212,168,67,0.2)' }}>
                <p className="text-[10px] font-bold text-subtle uppercase tracking-wide">{k.replace(/_/g, ' ')}</p>
                <p className="font-bold text-dark text-sm mt-0.5 font-mono">{String(v)}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Hierarchy Banner */}
      <div
        onClick={() => nav('/heirarchy-report')}
        className="card p-4 mb-3 cursor-pointer hover:shadow-lg transition-shadow"
        style={{ background: 'linear-gradient(135deg, #0F2B5B 0%, #1A3D7C 100%)' }}
      >
        <div className="flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold mb-0.5" style={{ color: '#D4A843' }}>HIERARCHY STRUCTURE REPORT</p>
            <p className="text-white/70 text-xs">View complete zone → sector → booth hierarchy</p>
          </div>
          <ChevronRight size={20} style={{ color: '#D4A843' }} />
        </div>
      </div>

      {/* Map View */}
      <MapViewButton className="w-full" />

      {/* Election Config Modal */}
      {showElectionModal && (
        <ElectionConfigModal
          initial={config}
          onSave={handleSaveElection}
          onClose={() => setShowElectionModal(false)}
        />
      )}
    </div>
  );
}

// ─────────────────────────────────────────────
//  TAB 1 — SUPER ADMINS
// ─────────────────────────────────────────────
function SuperAdminsTab() {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(null); // 'form' | 'reset' | null
  const [selected, setSelected] = useState(null);
  const [deleteId, setDeleteId] = useState(null);
  const [q, setQ] = useState('');

  const load = () => {
    setLoading(true);
    masterApi.getSuperAdmins()
      .then(r => setList(r.data || []))
      .catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);

  const filtered = list.filter(x =>
    !q || x.name?.toLowerCase().includes(q.toLowerCase()) || x.username?.toLowerCase().includes(q.toLowerCase())
  );

  const handleSave = async (form) => {
    if (selected) await masterApi.updateSuperAdmin(selected.id, form);
    else await masterApi.createSuperAdmin(form);
    toast.success(selected ? 'Super Admin updated ✓' : 'Super Admin created ✓');
    load();
  };

  const handleDelete = async () => {
    await masterApi.deleteSuperAdmin(deleteId);
    toast.success('Super Admin removed');
    setDeleteId(null);
    load();
  };

  const handleToggleStatus = async (sa) => {
    try {
      await masterApi.updateSuperAdminStatus(sa.id, { isActive: !sa.isActive });
      load();
    } catch {
      toast.error('Failed to update status');
    }
  };

  const handleResetPassword = async (id, password) => {
    await masterApi.resetSuperAdminPassword(id, { password });
    toast.success('Password reset ✓');
  };

  const closeModal = () => { setModal(null); setSelected(null); };

  return (
    <div className="p-4">
      <SectionHeader
        title="Super Admins"
        subtitle={`${list.length} accounts`}
        action={
          <button className="btn-primary text-xs px-3 py-2 flex items-center gap-1.5"
            onClick={() => { setSelected(null); setModal('form'); }}>
            <Plus size={14} /> Create
          </button>
        }
      />
      <div className="mb-4"><SearchBar value={q} onChange={setQ} placeholder="Search super admins…" /></div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {loading
          ? Array.from({ length: 4 }).map((_, i) => <Shimmer key={i} className="h-32 rounded-xl" />)
          : filtered.length === 0
            ? <div className="col-span-3 card"><Empty message="No super admins" icon={Shield} /></div>
            : filtered.map(u => (
              <div key={u.id} className="card overflow-hidden fade-in">
                {/* Card Header */}
                <div className="px-4 py-3 flex items-center gap-3"
                  style={{ background: u.isActive ? 'rgba(26,82,118,0.07)' : 'rgba(192,57,43,0.06)' }}>
                  <div className="w-9 h-9 rounded-full flex items-center justify-center font-bold text-sm flex-shrink-0"
                    style={{ background: '#1A5276', color: '#90caf9' }}>
                    {(u.name || '?')[0]}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-bold text-dark text-sm truncate">{u.name}</p>
                    <p className="text-xs text-subtle">@{u.username}</p>
                  </div>
                  {/* Actions */}
                  <div className="flex items-center gap-1 flex-shrink-0">
                    <button className="p-1.5 rounded hover:bg-surface text-primary" title="Edit"
                      onClick={() => { setSelected(u); setModal('form'); }}>
                      <Pencil size={13} />
                    </button>
                    <button className="p-1.5 rounded hover:bg-yellow-50 text-yellow-600" title="Reset Password"
                      onClick={() => { setSelected(u); setModal('reset'); }}>
                      <Lock size={13} />
                    </button>
                    <button className="p-1.5 rounded hover:bg-red-50 text-red-500" title="Delete"
                      onClick={() => setDeleteId(u.id)}>
                      <Trash2 size={13} />
                    </button>
                  </div>
                </div>
                {/* Card Body */}
                <div className="px-4 py-3 flex items-center justify-between">
                  <div className="text-xs text-subtle space-y-0.5">
                    {u.adminsUnder > 0 && <p>{u.adminsUnder} admin(s) under</p>}
                    {u.district && <p className="flex items-center gap-1"><MapPin size={10} />{u.district}</p>}
                  </div>
                  <StatusBadge isActive={u.isActive} onClick={() => handleToggleStatus(u)} />
                </div>
              </div>
            ))
        }
      </div>

      {modal === 'form' && (
        <UserModal
          title={selected ? 'Edit Super Admin' : 'Create Super Admin'}
          initial={selected}
          showDistrict
          onSave={handleSave}
          onClose={closeModal}
        />
      )}
      {modal === 'reset' && selected && (
        <ResetPasswordModal
          name={selected.name}
          onSave={(pw) => handleResetPassword(selected.id, pw)}
          onClose={closeModal}
        />
      )}
      <ConfirmDialog
        open={!!deleteId}
        danger
        title="Remove Super Admin?"
        message="This will affect all admins under this super admin."
        onConfirm={handleDelete}
        onCancel={() => setDeleteId(null)}
      />
    </div>
  );
}

// ─────────────────────────────────────────────
//  TAB 2 — ADMINS
// ─────────────────────────────────────────────
function AdminsTab() {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(null); // 'form' | 'reset' | null
  const [selected, setSelected] = useState(null);
  const [deleteId, setDeleteId] = useState(null);
  const [q, setQ] = useState('');

  const load = () => {
    setLoading(true);
    masterApi.getAdmins()
      .then(r => setList(r.data || []))
      .catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);

  const filtered = list.filter(x =>
    !q || x.name?.toLowerCase().includes(q.toLowerCase()) || x.username?.toLowerCase().includes(q.toLowerCase())
  );

  const handleSave = async (form) => {
    await masterApi.createAdmin(form);
    toast.success('Admin created ✓');
    load();
  };

  const handleDelete = async () => {
    await masterApi.deleteAdmin(deleteId);
    toast.success('Admin deleted');
    setDeleteId(null);
    load();
  };

  const handleToggleStatus = async (admin) => {
    try {
      await masterApi.updateAdminStatus(admin.id, { isActive: !admin.isActive });
      load();
    } catch {
      toast.error('Failed to update status');
    }
  };

  const handleResetPassword = async (id, password) => {
    await masterApi.resetAdminPassword(id, { password });
    toast.success('Password reset ✓');
  };

  const closeModal = () => { setModal(null); setSelected(null); };

  return (
    <div className="p-4">
      <SectionHeader
        title="All Admin Accounts"
        subtitle={`${list.length} total`}
        action={
          <button className="btn-primary text-xs px-3 py-2 flex items-center gap-1.5"
            onClick={() => { setSelected(null); setModal('form'); }}>
            <Plus size={14} /> Create Admin
          </button>
        }
      />
      <div className="mb-4"><SearchBar value={q} onChange={setQ} placeholder="Search admins…" /></div>

      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="tbl">
            <thead>
              <tr>
                <th>Name</th>
                <th>Username</th>
                <th>District</th>
                <th>Created By</th>
                <th className="text-center">Zones</th>
                <th>Status</th>
                <th className="text-center">Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading
                ? Array.from({ length: 6 }).map((_, i) => (
                  <tr key={i}>{[1, 2, 3, 4, 5, 6, 7].map(j => <td key={j}><Shimmer className="h-4 rounded" /></td>)}</tr>
                ))
                : filtered.length === 0
                  ? <tr><td colSpan={7}><Empty message="No admins found" /></td></tr>
                  : filtered.map(a => (
                    <tr key={a.id} className="fade-in">
                      <td className="font-semibold text-dark text-sm">{a.name}</td>
                      <td className="font-mono text-xs text-subtle">@{a.username}</td>
                      <td className="text-xs text-subtle">{a.district || '—'}</td>
                      <td className="text-xs text-subtle">{a.createdBy || '—'}</td>
                      <td className="text-center font-bold text-primary">{a.superZoneCount || 0}</td>
                      <td>
                        <StatusBadge isActive={a.isActive} onClick={() => handleToggleStatus(a)} />
                      </td>
                      <td>
                        <div className="flex items-center justify-center gap-1">
                          <button className="p-1.5 rounded hover:bg-yellow-50 text-yellow-600" title="Reset Password"
                            onClick={() => { setSelected(a); setModal('reset'); }}>
                            <Lock size={13} />
                          </button>
                          <button className="p-1.5 rounded hover:bg-red-50 text-red-500" title="Delete"
                            onClick={() => setDeleteId(a.id)}>
                            <Trash2 size={13} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))
              }
            </tbody>
          </table>
        </div>
      </div>

      {modal === 'form' && (
        <UserModal
          title="Create Admin"
          showDistrict
          onSave={handleSave}
          onClose={closeModal}
        />
      )}
      {modal === 'reset' && selected && (
        <ResetPasswordModal
          name={selected.name}
          onSave={(pw) => handleResetPassword(selected.id, pw)}
          onClose={closeModal}
        />
      )}
      <ConfirmDialog
        open={!!deleteId}
        danger
        title="Delete Admin?"
        message={`Admin will be permanently removed.`}
        onConfirm={handleDelete}
        onCancel={() => setDeleteId(null)}
      />
    </div>
  );
}

// ─────────────────────────────────────────────
//  TAB 3 — SYSTEM LOGS
// ─────────────────────────────────────────────
function LogsTab() {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('ALL');

  const load = (f = filter) => {
    setLoading(true);
    masterApi.getLogs({ level: f === 'ALL' ? undefined : f, limit: 100 })
      .then(r => setLogs(r.data || []))
      .catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  const levelColors = { INFO: '#1A5276', WARN: '#E67E22', ERROR: '#C0392B', DEBUG: '#666' };

  return (
    <div className="p-4">
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div>
          <h2 className="font-bold text-dark">System Logs</h2>
          <p className="text-xs text-subtle">{logs.length} entries</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          {['ALL', 'INFO', 'WARN', 'ERROR'].map(l => (
            <button key={l}
              className={`text-xs px-3 py-1.5 rounded-lg font-semibold border transition-colors ${filter === l ? 'text-white border-transparent' : 'btn-outline'}`}
              style={filter === l ? { background: levelColors[l] || 'var(--primary)' } : {}}
              onClick={() => { setFilter(l); load(l); }}>
              {l}
            </button>
          ))}
          <button className="btn-outline p-2" onClick={() => load()}><RefreshCw size={14} /></button>
        </div>
      </div>
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="tbl">
            <thead><tr><th>Level</th><th>Message</th><th>Module</th><th>Time</th></tr></thead>
            <tbody>
              {loading
                ? Array.from({ length: 8 }).map((_, i) => (
                  <tr key={i}>{[1, 2, 3, 4].map(j => <td key={j}><Shimmer className="h-4 rounded" /></td>)}</tr>
                ))
                : logs.length === 0
                  ? <tr><td colSpan={4}><Empty message="No logs" /></td></tr>
                  : logs.map(l => (
                    <tr key={l.id} className="fade-in">
                      <td>
                        <span className="badge text-[10px] font-bold"
                          style={{ background: (levelColors[l.level] || '#666') + '18', color: levelColors[l.level] || '#666' }}>
                          {l.level}
                        </span>
                      </td>
                      <td className="text-xs max-w-xs truncate">{l.message}</td>
                      <td className="text-xs font-mono text-subtle">{l.module}</td>
                      <td className="text-[10px] text-subtle">{l.time ? new Date(l.time).toLocaleString('en-IN') : '—'}</td>
                    </tr>
                  ))
              }
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────
//  TAB 4 — CONFIG
// ─────────────────────────────────────────────
function ConfigTab() {
  const [config, setConfig] = useState({});
  const [loading, setLoading] = useState(true);
  const [showElectionModal, setShowElectionModal] = useState(false);
  const [showMasterPwModal, setShowMasterPwModal] = useState(false);

  const load = () => {
    setLoading(true);
    masterApi.getConfig()
      .then(r => setConfig(r.data || r))
      .catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);

  const handleSaveElection = async (form) => {
    await masterApi.updateConfig(form);
    toast.success('Election settings updated ✓');
    load();
  };

  const updateConfig = async (key, value) => {
    try {
      await masterApi.updateConfig({ key, value });
      toast.success('Config updated ✓');
      load();
    } catch {
      toast.error('Failed to update config');
    }
  };

  const runMigration = async () => {
    try {
      await masterApi.runMigrations();
      toast.success('Migrations completed ✓');
    } catch {
      toast.error('Migration failed');
    }
  };

  if (loading) return (
    <div className="p-4 space-y-3">
      {[1, 2, 3].map(i => <Shimmer key={i} className="h-24 rounded-xl" />)}
    </div>
  );

  const electionKeys = ['state', 'electionYear', 'electionDate', 'phase'];
  const appToggleKeys = ['maintenanceMode', 'allowStaffLogin', 'forcePasswordReset'];
  const otherKeys = Object.keys(config).filter(k => !electionKeys.includes(k) && !appToggleKeys.includes(k));

  return (
    <div className="p-4 max-w-3xl mx-auto space-y-6">

      {/* ── Election Settings ── */}
      <section>
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <div className="w-1 h-4 rounded-full" style={{ background: '#00695C' }} />
            <h3 className="font-bold text-dark text-sm">Election Settings</h3>
          </div>
          <button
            onClick={() => setShowElectionModal(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold text-white"
            style={{ background: '#00695C' }}
          >
            <Pencil size={11} /> Edit
          </button>
        </div>
        <div className="card divide-y" style={{ borderColor: 'rgba(212,168,67,0.25)' }}>
          {electionKeys.map(k => (
            <div key={k} className="flex items-center justify-between px-4 py-3">
              <span className="text-xs font-semibold text-subtle capitalize">{k.replace(/([A-Z])/g, ' $1')}</span>
              <span className="text-sm font-bold text-dark">{config[k] || <span className="text-subtle font-normal italic">Not set</span>}</span>
            </div>
          ))}
        </div>
      </section>

      {/* ── Application Toggles ── */}
      <section>
        <div className="flex items-center gap-2 mb-3">
          <div className="w-1 h-4 rounded-full" style={{ background: '#00695C' }} />
          <h3 className="font-bold text-dark text-sm">Application Settings</h3>
        </div>
        <div className="card divide-y" style={{ borderColor: 'rgba(212,168,67,0.25)' }}>
          {[
            { key: 'maintenanceMode',    label: 'Maintenance Mode',       sub: 'Disable app for all users' },
            { key: 'allowStaffLogin',    label: 'Allow Staff Login',      sub: 'Enable/disable staff access' },
            { key: 'forcePasswordReset', label: 'Force Password Reset',   sub: 'Prompt all admins to reset on next login' },
          ].map(({ key, label, sub }) => {
            const isOn = key === 'allowStaffLogin'
              ? config[key]?.toString() !== 'false'
              : config[key]?.toString() === 'true';
            return (
              <div key={key} className="flex items-center justify-between px-4 py-3">
                <div>
                  <p className="text-sm font-bold text-dark">{label}</p>
                  <p className="text-xs text-subtle">{sub}</p>
                </div>
                <button
                  onClick={() => updateConfig(key, String(!isOn))}
                  className="flex-shrink-0 ml-4"
                  title={isOn ? 'Turn off' : 'Turn on'}
                >
                  {isOn
                    ? <ToggleRight size={28} style={{ color: '#00695C' }} />
                    : <ToggleLeft size={28} className="text-subtle" />
                  }
                </button>
              </div>
            );
          })}
        </div>
      </section>

      {/* ── All Config Keys ── */}
      {otherKeys.length > 0 && (
        <section>
          <div className="flex items-center gap-2 mb-3">
            <div className="w-1 h-4 rounded-full" style={{ background: '#00695C' }} />
            <h3 className="font-bold text-dark text-sm">All Config Keys</h3>
          </div>
          <div className="card divide-y" style={{ borderColor: 'rgba(212,168,67,0.25)' }}>
            {otherKeys.map(k => (
              <div key={k} className="flex items-center justify-between px-4 py-3">
                <span className="text-xs font-semibold text-subtle font-mono">{k}</span>
                <span className="text-xs font-bold text-dark font-mono">{String(config[k] ?? '')}</span>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* ── Developer Tools ── */}
      <section>
        <div className="flex items-center gap-2 mb-3">
          <div className="w-1 h-4 rounded-full" style={{ background: '#00695C' }} />
          <h3 className="font-bold text-dark text-sm">Developer Tools</h3>
        </div>
        <div className="card divide-y" style={{ borderColor: 'rgba(212,168,67,0.25)' }}>
          {[
            {
              icon: Wrench, color: '#E67E22', bg: '#fef5e7',
              title: 'Run DB Migrations',
              sub: 'Apply schema updates to the database',
              action: runMigration,
            },
            {
              icon: Key, color: '#00695C', bg: '#e0f2f1',
              title: 'Change Master Password',
              sub: 'Update master account password',
              action: () => setShowMasterPwModal(true),
            },
            {
              icon: Info, color: '#1A5276', bg: '#e8f4fd',
              title: 'System Info',
              sub: 'Flask · MySQL 8 · SHA256+Salt auth',
              action: () => toast('Flask · MySQL 8 · SHA256+Salt', { icon: 'ℹ️' }),
            },
          ].map(({ icon: Icon, color, bg, title, sub, action }) => (
            <button key={title} onClick={action}
              className="w-full flex items-center gap-3 px-4 py-3 hover:bg-surface transition-colors text-left">
              <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0" style={{ background: bg }}>
                <Icon size={16} style={{ color }} />
              </div>
              <div className="flex-1">
                <p className="text-sm font-bold text-dark">{title}</p>
                <p className="text-xs text-subtle">{sub}</p>
              </div>
              <ChevronRight size={14} className="text-subtle" />
            </button>
          ))}
        </div>
      </section>

      {/* Modals */}
      {showElectionModal && (
        <ElectionConfigModal
          initial={config}
          onSave={handleSaveElection}
          onClose={() => setShowElectionModal(false)}
        />
      )}
      {showMasterPwModal && (
        <ChangeMasterPasswordModal onClose={() => setShowMasterPwModal(false)} />
      )}
    </div>
  );
}

// ─────────────────────────────────────────────
//  ROOT DASHBOARD
// ─────────────────────────────────────────────
const TABS = {
  overview:    OverviewTab,
  superadmins: SuperAdminsTab,
  admins:      AdminsTab,
  logs:        LogsTab,
  config:      ConfigTab,        // ← NEW
};

export default function MasterDashboard() {
  const [page, setPage] = useState('overview');
  const [showDbTools, setShowDbTools] = useState(false);
  const Page = TABS[page] || OverviewTab;

  return (
    <AppShell activePage={page} onNavigate={setPage}>
      {/* DB Tools button injected into header — wire to your AppShell headerActions prop if supported */}
      <Page />
      {showDbTools && <DbToolsModal onClose={() => setShowDbTools(false)} />}
    </AppShell>
  );
}

// Export DbToolsModal so AppShell/TopBar can trigger it via a ref or prop if needed
export { DbToolsModal };