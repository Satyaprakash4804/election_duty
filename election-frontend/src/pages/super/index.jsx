import { useState, useEffect } from 'react';
import {
  Users, MapPin, Vote, Plus, Pencil, Trash2,
  Eye, EyeOff, Save, Shield, CheckCircle, XCircle,
  ChevronRight, Layers, Grid, Building2, Landmark,
  LocateFixed, UserCog, Calendar, X
} from 'lucide-react';
import AppShell from '../../components/layout/AppShell';
import { superApi } from '../../api/endpoints';
import { StatCard, Modal, ConfirmDialog, Empty, Shimmer, SectionHeader, SearchBar } from '../../components/common';
import { UP_DISTRICTS } from '../../utils/helpers';
import toast from 'react-hot-toast';
import MapViewButton from '../../components/common/Mapviewbutton';
import { useNavigate } from 'react-router-dom';

// ─────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────
function fmtDate(iso) {
  if (!iso) return '—';
  try {
    const d = new Date(iso);
    return d.toLocaleDateString('en-IN', { day: '2-digit', month: '2-digit', year: 'numeric' });
  } catch { return iso; }
}

function Pill({ children, color }) {
  return (
    <span
      className="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-bold border"
      style={{ color, background: color + '18', borderColor: color + '44' }}
    >
      {children}
    </span>
  );
}

// ─────────────────────────────────────────────
//  CREATE / EDIT ADMIN MODAL
// ─────────────────────────────────────────────
function AdminModal({ initial, onSave, onClose }) {
  const isEdit = !!initial;
  const [form, setForm] = useState({
    name: '', username: '', password: '', confirmPassword: '', district: '',
    ...(initial || {})
  });
  const [showPass, setShowPass] = useState(false);
  const [saving, setSaving]     = useState(false);
  const [err, setErr]           = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handleSave = async () => {
    if (!form.name || !form.username)                           { setErr('Name and username are required'); return; }
    if (!isEdit && !form.password)                             { setErr('Password is required'); return; }
    if (!isEdit && form.password.length < 6)                   { setErr('Password must be at least 6 characters'); return; }
    if (!isEdit && form.password !== form.confirmPassword)     { setErr('Passwords do not match'); return; }
    if (!form.district)                                        { setErr('Please select a district'); return; }
    setSaving(true); setErr('');
    try { await onSave(form); onClose(); }
    catch (e) { setErr(e.message || 'Failed to save'); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose} title={isEdit ? 'Edit Admin' : 'Create New Admin'}>
      <div className="space-y-3">
        {err && (
          <div className="text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg p-2.5 flex items-center gap-2">
            <X size={12} /> {err}
          </div>
        )}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {/* Full Name */}
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Full Name *</label>
            <input className="field" value={form.name} onChange={e => set('name', e.target.value)} placeholder="Admin full name" />
          </div>
          {/* Username */}
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Admin User ID *</label>
            <input className="field" value={form.username} onChange={e => set('username', e.target.value)} placeholder="Login ID" />
          </div>
          {/* District */}
          <div className={isEdit ? 'sm:col-span-2' : ''}>
            <label className="text-xs font-semibold text-subtle mb-1 block">District *</label>
            <select className="field" value={form.district} onChange={e => set('district', e.target.value)}>
              <option value="">Select district</option>
              {UP_DISTRICTS.map(d => <option key={d} value={d}>{d}</option>)}
            </select>
          </div>
          {/* Password fields — only on create */}
          {!isEdit && (
            <>
              <div className="relative">
                <label className="text-xs font-semibold text-subtle mb-1 block">Password *</label>
                <input
                  className="field pr-9"
                  type={showPass ? 'text' : 'password'}
                  value={form.password}
                  onChange={e => set('password', e.target.value)}
                  placeholder="Min 6 characters"
                />
                <button type="button" className="absolute right-3 top-[34px]" onClick={() => setShowPass(s => !s)}>
                  {showPass ? <EyeOff size={14} className="text-subtle" /> : <Eye size={14} className="text-subtle" />}
                </button>
              </div>
              <div>
                <label className="text-xs font-semibold text-subtle mb-1 block">Confirm Password *</label>
                <input
                  className="field"
                  type={showPass ? 'text' : 'password'}
                  value={form.confirmPassword}
                  onChange={e => set('confirmPassword', e.target.value)}
                  placeholder="Repeat password"
                />
              </div>
            </>
          )}
        </div>
        <div className="flex gap-3 justify-end pt-1">
          <button className="btn-outline px-4 py-2 text-sm" onClick={onClose}>Cancel</button>
          <button className="btn-primary px-5 py-2 text-sm flex items-center gap-2" onClick={handleSave} disabled={saving}>
            {saving
              ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              : <><Save size={14} /> {isEdit ? 'Save' : 'Create Admin'}</>
            }
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────
//  FORM DATA DETAIL MODAL  ← NEW (was missing)
// ─────────────────────────────────────────────
function FormDetailModal({ entry, onClose }) {
  const miniStats = [
    { label: 'Super Zones',    value: entry.superZones,     icon: Layers },
    { label: 'Zones',          value: entry.zones,          icon: Grid },
    { label: 'Sectors',        value: entry.sectors,        icon: Building2 },
    { label: 'Gram Panchayats',value: entry.gramPanchayats, icon: Landmark },
    { label: 'Centers',        value: entry.centers,        icon: LocateFixed },
  ];

  return (
    <Modal open onClose={onClose} title={`${entry.district} — Form Data`}>
      <div className="space-y-4">
        {/* Meta rows */}
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-sm">
            <UserCog size={14} className="text-subtle flex-shrink-0" />
            <span className="text-subtle font-semibold">Admin:</span>
            <span className="text-dark font-bold">{entry.adminName}</span>
          </div>
          {entry.lastUpdated && (
            <div className="flex items-center gap-2 text-sm">
              <Calendar size={14} className="text-subtle flex-shrink-0" />
              <span className="text-subtle font-semibold">Last Updated:</span>
              <span className="text-dark font-bold">{fmtDate(entry.lastUpdated)}</span>
            </div>
          )}
        </div>

        {/* Divider */}
        <div style={{ borderTop: '1px solid rgba(212,168,67,0.35)' }} />

        {/* Mini stat grid */}
        <div className="grid grid-cols-3 gap-2">
          {miniStats.map(({ label, value, icon: Icon }) => (
            <div
              key={label}
              className="flex flex-col items-center justify-center rounded-xl py-3 px-2 text-center"
              style={{ background: 'var(--surface)', border: '1px solid rgba(212,168,67,0.3)' }}
            >
              <Icon size={16} className="mb-1.5" style={{ color: 'var(--primary)' }} />
              <span className="text-lg font-black" style={{ color: 'var(--dark)' }}>{value ?? 0}</span>
              <span className="text-[9px] font-bold text-subtle leading-tight mt-0.5">{label}</span>
            </div>
          ))}
        </div>

        {/* Close button */}
        <button
          onClick={onClose}
          className="w-full py-2.5 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2"
          style={{ background: 'var(--dark)' }}
        >
          <X size={14} /> Close
        </button>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────
//  TAB 0 — OVERVIEW
// ─────────────────────────────────────────────
function OverviewTab() {
  const [overview, setOverview] = useState(null);
  const [admins,   setAdmins]   = useState([]);
  const [loading,  setLoading]  = useState(true);
  const nav = useNavigate();

  const load = () => {
    setLoading(true);
    Promise.all([superApi.overview(), superApi.getAdmins()])
      .then(([ovRes, admRes]) => {
        setOverview(ovRes.data || ovRes);
        setAdmins(admRes.data || []);
      })
      .catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);

  const statItems = overview ? [
    { label: 'Total Admins',    value: admins.length              ?? 0, icon: Shield, color: '#8B6914' },
    { label: 'Total Booths',    value: overview.totalBooths       ?? 0, icon: MapPin, color: '#1565C0' },
    { label: 'Total Staff',     value: overview.totalStaff        ?? 0, icon: Users,  color: '#B8860B' },
    { label: 'Assigned Duties', value: overview.assignedDuties    ?? 0, icon: Vote,   color: '#2D6A1E' },
  ] : [];

  return (
    <div className="p-4 max-w-4xl mx-auto">
      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
        {loading
          ? [1, 2, 3, 4].map(i => <Shimmer key={i} className="h-24" />)
          : statItems.map(s => <StatCard key={s.label} {...s} />)
        }
      </div>

      {/* Election info */}
      {overview?.electionInfo && Object.values(overview.electionInfo).some(Boolean) && (
        <div className="card p-4 mb-4">
          <h3 className="font-bold text-dark mb-3 text-sm">Election Information</h3>
          <div className="grid grid-cols-2 gap-3">
            {Object.entries(overview.electionInfo).filter(([, v]) => v).map(([k, v]) => (
              <div key={k} className="rounded-lg p-2.5" style={{ background: 'var(--surface)', border: '1px solid rgba(212,168,67,0.2)' }}>
                <p className="text-[10px] font-bold text-subtle uppercase">{k.replace(/_/g, ' ')}</p>
                <p className="text-sm font-semibold text-dark mt-0.5">{v}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Goswara Report banner — golden gradient matching Flutter */}
      <div
        onClick={() => nav('/goswara-page')}
        className="rounded-xl p-4 mb-3 cursor-pointer hover:shadow-lg transition-shadow"
        style={{ background: 'linear-gradient(135deg, #8B6914 0%, #B8860B 100%)', boxShadow: 'rgba(139,105,20,0.3) 0px 5px 14px' }}
      >
        <div className="flex items-center gap-4">
          <div className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ background: 'rgba(255,255,255,0.15)' }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
              <polyline points="14 2 14 8 20 8" />
              <line x1="16" y1="13" x2="8" y2="13" />
              <line x1="16" y1="17" x2="8" y2="17" />
              <polyline points="10 9 9 9 8 9" />
            </svg>
          </div>
          <div className="flex-1">
            <p className="font-extrabold text-white text-sm">Goswara Report</p>
            <p className="text-white/60 text-xs mt-0.5">Summary Report of Booth Staff</p>
          </div>
          <ChevronRight size={20} className="text-white/60 flex-shrink-0" />
        </div>
      </div>

      {/* Hierarchy Report banner */}
      <div
        onClick={() => nav('/heirarchy-report')}
        className="rounded-xl p-4 mb-3 cursor-pointer hover:shadow-lg transition-shadow"
        style={{ background: 'linear-gradient(135deg, #0F2B5B 0%, #1A3D7C 100%)' }}
      >
        <div className="flex items-center gap-4">
          <div className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ background: 'rgba(255,255,255,0.1)' }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/>
              <rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/>
            </svg>
          </div>
          <div className="flex-1">
            <p className="font-extrabold text-white text-sm">Hierarchy Report</p>
            <p className="text-white/60 text-xs mt-0.5">Super Zone · Sector · Panchayat</p>
          </div>
          <ChevronRight size={20} className="text-white/60 flex-shrink-0" />
        </div>
      </div>

      {/* Map View */}
      <MapViewButton className="w-full mb-5" />

      {/* ── District Summary ← NEW (was missing) ── */}
      {!loading && admins.length > 0 && (
        <>
          <div className="flex items-center gap-2 mb-3">
            <div className="w-1 h-[18px] rounded-full" style={{ background: 'var(--primary)' }} />
            <h3 className="font-extrabold text-dark text-sm">District Summary</h3>
          </div>
          <div className="space-y-2.5">
            {admins.map(a => (
              <div
                key={a.id}
                className="flex items-center gap-3 rounded-xl px-4 py-3"
                style={{ background: 'white', border: '1px solid rgba(212,168,67,0.35)' }}
              >
                {/* Icon */}
                <div
                  className="w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0"
                  style={{ background: 'var(--surface)', border: '1px solid var(--border)' }}
                >
                  <Building2 size={18} style={{ color: 'var(--primary)' }} />
                </div>
                {/* Text */}
                <div className="flex-1 min-w-0">
                  <p className="font-bold text-dark text-sm truncate">{a.district || '—'}</p>
                  <p className="text-xs text-subtle truncate">{a.name}</p>
                </div>
                {/* Pills */}
                <div className="flex flex-col items-end gap-1 flex-shrink-0">
                  <Pill color="#8B6914">{a.totalBooths ?? 0} Booths</Pill>
                  <Pill color="#B8860B">{a.assignedStaff ?? 0} Staff</Pill>
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────
//  TAB 1 — ADMINS
// ─────────────────────────────────────────────
function AdminsTab() {
  const [admins,   setAdmins]   = useState([]);
  const [loading,  setLoading]  = useState(true);
  const [q,        setQ]        = useState('');
  const [modal,    setModal]    = useState(null);
  const [selected, setSelected] = useState(null);
  const [deleteId, setDeleteId] = useState(null);

  const load = () => {
    setLoading(true);
    superApi.getAdmins()
      .then(r => setAdmins(r.data || []))
      .catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);

  const filtered = admins.filter(a =>
    !q ||
    a.name?.toLowerCase().includes(q.toLowerCase()) ||
    a.district?.toLowerCase().includes(q.toLowerCase())
  );

  const handleSave = async (form) => {
    if (selected) await superApi.updateAdmin(selected.id, form);
    else          await superApi.createAdmin(form);
    toast.success(selected ? 'Admin updated ✓' : 'Admin created ✓');
    load();
  };

  const handleDelete = async () => {
    await superApi.deleteAdmin(deleteId);
    toast.success('Admin removed');
    setDeleteId(null);
    load();
  };

  const closeModal = () => { setModal(null); setSelected(null); };

  return (
    <div className="p-4">
      <SectionHeader
        title="Admin Accounts"
        subtitle={`${admins.length} admin(s) registered`}
        action={
          <button
            className="btn-primary text-xs px-3 py-2 flex items-center gap-1.5"
            onClick={() => { setSelected(null); setModal('form'); }}
          >
            <Plus size={14} /> New Admin
          </button>
        }
      />
      <div className="mb-4">
        <SearchBar value={q} onChange={setQ} placeholder="Search by name or district…" />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {loading
          ? Array.from({ length: 6 }).map((_, i) => <Shimmer key={i} className="h-32 rounded-xl" />)
          : filtered.length === 0
            ? <div className="col-span-3 card"><Empty message="No admins found" icon={Shield} /></div>
            : filtered.map(a => (
              <div key={a.id} className="card overflow-hidden fade-in">
                {/* Card header */}
                <div
                  className="px-4 py-3 flex items-center gap-3"
                  style={{ background: 'var(--surface)', borderBottom: '1px solid rgba(212,168,67,0.25)' }}
                >
                  {/* ID badge */}
                  <span
                    className="text-[10px] font-black tracking-wide px-2 py-1 rounded-md flex-shrink-0"
                    style={{ background: 'var(--primary)', color: 'white' }}
                  >
                    ADM{String(a.id).padStart(3, '0')}
                  </span>
                  <p className="font-bold text-dark text-sm flex-1 truncate">{a.name}</p>
                  {/* Actions */}
                  <div className="flex gap-1 flex-shrink-0">
                    <button className="p-1.5 rounded hover:bg-white text-primary" title="Edit"
                      onClick={() => { setSelected(a); setModal('form'); }}>
                      <Pencil size={13} />
                    </button>
                    <button className="p-1.5 rounded hover:bg-red-50 text-red-500" title="Delete"
                      onClick={() => setDeleteId(a.id)}>
                      <Trash2 size={13} />
                    </button>
                  </div>
                </div>

                {/* Card body */}
                <div className="px-4 py-3 space-y-1.5">
                  <div className="flex items-center gap-1.5 text-xs text-subtle">
                    <Building2 size={12} />
                    <span>{a.district || 'No district'}</span>
                  </div>
                  {a.createdAt && (
                    <div className="flex items-center gap-1.5 text-xs text-subtle">
                      <Calendar size={12} />
                      <span>Created {fmtDate(a.createdAt)}</span>
                    </div>
                  )}
                  <div className="flex flex-wrap gap-1.5 pt-1">
                    <Pill color={a.isActive ? '#2D6A1E' : '#C0392B'}>
                      {a.isActive ? <CheckCircle size={9} className="inline mr-0.5" /> : <XCircle size={9} className="inline mr-0.5" />}
                      {a.isActive ? 'Active' : 'Inactive'}
                    </Pill>
                    {(a.totalBooths ?? 0) > 0 && <Pill color="#1565C0">{a.totalBooths} Booths</Pill>}
                    {(a.assignedStaff ?? 0) > 0 && <Pill color="#B8860B">{a.assignedStaff} Staff</Pill>}
                  </div>
                </div>
              </div>
            ))
        }
      </div>

      {modal === 'form' && (
        <AdminModal initial={selected} onSave={handleSave} onClose={closeModal} />
      )}
      <ConfirmDialog
        open={!!deleteId}
        danger
        title="Remove Admin?"
        message="This will remove all data under this admin."
        onConfirm={handleDelete}
        onCancel={() => setDeleteId(null)}
      />
    </div>
  );
}

// ─────────────────────────────────────────────
//  TAB 2 — FORM DATA
// ─────────────────────────────────────────────
function FormDataTab() {
  const [data,    setData]    = useState([]);
  const [loading, setLoading] = useState(true);
  const [detail,  setDetail]  = useState(null); // ← NEW: selected entry for detail modal

  const load = () => {
    setLoading(true);
    superApi.getFormData()
      .then(r => setData(r.data || []))
      .catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);

  return (
    <div className="p-4">
      <SectionHeader title="District Form Data" subtitle="Admin-wise structure entries" />

      {/* ── Card list matching Flutter's _formDataCard ── */}
      {loading
        ? Array.from({ length: 4 }).map((_, i) => <Shimmer key={i} className="h-36 rounded-xl mb-3" />)
        : data.length === 0
          ? <div className="card"><Empty message="No form data submitted yet" /></div>
          : data.map((d, i) => (
            <div
              key={d.adminId || i}
              className="rounded-xl overflow-hidden mb-3 fade-in"
              style={{ border: '1px solid rgba(212,168,67,0.4)', boxShadow: 'rgba(139,105,20,0.06) 0px 4px 10px' }}
            >
              {/* Header */}
              <div
                className="px-4 py-3 flex items-center gap-3"
                style={{ background: 'var(--dark)' }}
              >
                <MapPin size={15} style={{ color: 'var(--border)', flexShrink: 0 }} />
                <p className="font-bold text-white text-sm flex-1 truncate">
                  District: {d.district || '—'}
                </p>
                {d.lastUpdated && (
                  <span className="text-white/60 text-[11px] flex-shrink-0">
                    Updated: {fmtDate(d.lastUpdated)}
                  </span>
                )}
              </div>

              {/* Body */}
              <div className="px-4 py-3" style={{ background: 'white' }}>
                {/* Admin row */}
                <div className="flex items-center gap-1.5 text-xs text-subtle mb-3">
                  <UserCog size={13} />
                  <span>Admin: <strong className="text-dark">{d.adminName || '—'}</strong></span>
                </div>

                {/* Stat chips */}
                <div className="flex flex-wrap gap-2 mb-3">
                  {[
                    { label: 'Super Zones',    val: d.superZones,     color: '#8B6914' },
                    { label: 'Zones',          val: d.zones,          color: '#B8860B' },
                    { label: 'Sectors',        val: d.sectors,        color: '#1565C0' },
                    { label: 'Gram Panchayats',val: d.gramPanchayats, color: '#2D6A1E' },
                    { label: 'Centers',        val: d.centers,        color: '#6A1E2D' },
                  ].map(({ label, val, color }) => (
                    <div
                      key={label}
                      className="px-2.5 py-1.5 rounded-lg"
                      style={{ background: 'var(--surface)', border: '1px solid rgba(212,168,67,0.4)' }}
                    >
                      <span className="font-black text-sm" style={{ color }}>{val ?? 0} </span>
                      <span className="text-[10px] font-semibold text-subtle">{label}</span>
                    </div>
                  ))}
                </div>

                {/* View Full Details button ← NEW */}
                <button
                  onClick={() => setDetail(d)}
                  className="w-full py-2 rounded-lg text-xs font-bold flex items-center justify-center gap-2 border transition-colors hover:bg-surface"
                  style={{ color: 'var(--primary)', borderColor: 'var(--border)' }}
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>
                    <polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>
                  </svg>
                  View Full Details
                </button>
              </div>
            </div>
          ))
      }

      {/* Form Detail Modal ← NEW */}
      {detail && <FormDetailModal entry={detail} onClose={() => setDetail(null)} />}
    </div>
  );
}

// ─────────────────────────────────────────────
//  ROOT
// ─────────────────────────────────────────────
const TABS = {
  overview: OverviewTab,
  admins:   AdminsTab,
  formdata: FormDataTab,
};

export default function SuperDashboard() {
  const [page, setPage] = useState('overview');
  const Page = TABS[page] || OverviewTab;
  return (
    <AppShell activePage={page} onNavigate={setPage}>
      <Page />
    </AppShell>
  );
}