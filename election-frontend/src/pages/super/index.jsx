import { useState, useEffect } from 'react';
import {
  Users, MapPin, Vote, BarChart3, Plus, Pencil, Trash2,
  Eye, EyeOff, Save, Shield, CheckCircle, XCircle
} from 'lucide-react';
import AppShell from '../../components/layout/AppShell';
import { superApi } from '../../api/endpoints';
import { StatCard, Modal, ConfirmDialog, Empty, Shimmer, SectionHeader, SearchBar } from '../../components/common';
import { UP_DISTRICTS } from '../../utils/helpers';
import toast from 'react-hot-toast';

// ── Create/Edit Admin Modal ────────────────────────────────────────────────────
function AdminModal({ initial, onSave, onClose }) {
  const isEdit = !!initial;
  const [form, setForm] = useState({
    name: '', username: '', password: '', confirmPassword: '',
    district: '', ...(initial || {})
  });
  const [showPass, setShowPass] = useState(false);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handleSave = async () => {
    if (!isEdit && form.password !== form.confirmPassword) {
      setErr('Passwords do not match'); return;
    }
    if (!form.name || !form.username) { setErr('Name and username required'); return; }
    setSaving(true); setErr('');
    try { await onSave(form); onClose(); }
    catch (e) { setErr(e.message || 'Failed to save'); }
    finally { setSaving(false); }
  };

  return (
    <Modal open onClose={onClose}
      title={isEdit ? 'Edit Admin' : 'Create New Admin'}>
      <div className="space-y-3">
        {err && <div className="text-xs text-error bg-red-50 border border-red-200 rounded-lg p-2">{err}</div>}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Full Name *</label>
            <input className="field" value={form.name} onChange={e => set('name', e.target.value)} placeholder="Admin name" />
          </div>
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Username *</label>
            <input className="field" value={form.username} onChange={e => set('username', e.target.value)} placeholder="Login ID" />
          </div>
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">District</label>
            <select className="field" value={form.district} onChange={e => set('district', e.target.value)}>
              <option value="">Select district</option>
              {UP_DISTRICTS.map(d => <option key={d}>{d}</option>)}
            </select>
          </div>
          {!isEdit && (
            <>
              <div className="relative">
                <label className="text-xs font-semibold text-subtle mb-1 block">Password *</label>
                <input className="field pr-9" type={showPass ? 'text' : 'password'}
                  value={form.password} onChange={e => set('password', e.target.value)} placeholder="Password" />
                <button type="button" className="absolute right-3 bottom-3" onClick={() => setShowPass(!showPass)}>
                  {showPass ? <EyeOff size={14} className="text-subtle" /> : <Eye size={14} className="text-subtle" />}
                </button>
              </div>
              <div>
                <label className="text-xs font-semibold text-subtle mb-1 block">Confirm Password *</label>
                <input className="field" type={showPass ? 'text' : 'password'}
                  value={form.confirmPassword} onChange={e => set('confirmPassword', e.target.value)} placeholder="Repeat password" />
              </div>
            </>
          )}
        </div>
        <div className="flex gap-3 justify-end pt-2">
          <button className="btn-outline px-4 py-2" onClick={onClose}>Cancel</button>
          <button className="btn-primary px-5 py-2" onClick={handleSave} disabled={saving}>
            {saving ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"/> : <><Save size={14}/> Save</>}
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ── Overview Tab ───────────────────────────────────────────────────────────────
function OverviewTab() {
  const [overview, setOverview] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    superApi.overview().then(r => setOverview(r.data || r)).catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  }, []);

  const items = overview ? [
    { label: 'Total Admins', value: overview.totalAdmins ?? 0, icon: Shield, color: '#8B6914' },
    { label: 'Total Staff', value: overview.totalStaff ?? 0, icon: Users, color: '#B8860B' },
    { label: 'Total Booths', value: overview.totalBooths ?? 0, icon: MapPin, color: '#2D6A1E' },
    { label: 'Assigned Duties', value: overview.assignedDuties ?? 0, icon: Vote, color: '#1A5276' },
  ] : [];

  return (
    <div className="p-4 max-w-4xl mx-auto">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        {loading ? [1,2,3,4].map(i => <Shimmer key={i} className="h-24" />)
          : items.map(s => <StatCard key={s.label} {...s} />)}
      </div>

      {overview?.electionInfo && (
        <div className="card p-4">
          <h3 className="font-bold text-dark mb-3 text-sm">Election Information</h3>
          <div className="grid grid-cols-2 gap-3">
            {Object.entries(overview.electionInfo).filter(([,v]) => v).map(([k, v]) => (
              <div key={k} className="rounded-lg p-2.5" style={{ background: 'var(--surface)' }}>
                <p className="text-[10px] font-bold text-subtle uppercase">{k.replace(/_/g, ' ')}</p>
                <p className="text-sm font-semibold text-dark mt-0.5">{v}</p>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ── Admins Tab ─────────────────────────────────────────────────────────────────
function AdminsTab() {
  const [admins, setAdmins] = useState([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [modal, setModal] = useState(null);
  const [selected, setSelected] = useState(null);
  const [deleteId, setDeleteId] = useState(null);

  const load = () => {
    setLoading(true);
    superApi.getAdmins().then(r => setAdmins(r.data || [])).catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);

  const filtered = admins.filter(a =>
    !q || a.name?.toLowerCase().includes(q.toLowerCase()) || a.district?.toLowerCase().includes(q.toLowerCase())
  );

  const handleSave = async (form) => {
    if (selected) await superApi.updateAdmin(selected.id, form);
    else await superApi.createAdmin(form);
    toast.success(selected ? 'Admin updated' : 'Admin created');
    load();
  };
  const handleDelete = async () => {
    await superApi.deleteAdmin(deleteId);
    toast.success('Admin deleted'); setDeleteId(null); load();
  };

  return (
    <div className="p-4">
      <SectionHeader title="Admin Accounts" subtitle={`${admins.length} admins`}
        action={
          <button className="btn-primary text-xs px-3 py-2"
            onClick={() => { setSelected(null); setModal('form'); }}>
            <Plus size={14} /> Create Admin
          </button>
        }
      />
      <div className="mb-4"><SearchBar value={q} onChange={setQ} placeholder="Search by name or district…" /></div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {loading ? Array.from({length:6}).map((_,i) => <Shimmer key={i} className="h-28 rounded-xl"/>)
          : filtered.length === 0
            ? <div className="col-span-3 card"><Empty message="No admins found" icon={Shield} /></div>
            : filtered.map(a => (
              <div key={a.id} className="card p-4 fade-in">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full flex items-center justify-center font-bold text-sm"
                      style={{ background: 'var(--dark)', color: 'var(--border)' }}>
                      {(a.name||'?')[0]}
                    </div>
                    <div>
                      <p className="font-bold text-dark text-sm">{a.name}</p>
                      <p className="text-xs text-subtle">@{a.username}</p>
                    </div>
                  </div>
                  <div className="flex gap-1">
                    <button className="p-1.5 rounded hover:bg-surface text-primary"
                      onClick={() => { setSelected(a); setModal('form'); }}>
                      <Pencil size={13} />
                    </button>
                    <button className="p-1.5 rounded hover:bg-red-50 text-error"
                      onClick={() => setDeleteId(a.id)}>
                      <Trash2 size={13} />
                    </button>
                  </div>
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  <span className="badge text-[10px]" style={{ background: 'var(--surface)', color: 'var(--primary)' }}>
                    📍 {a.district || 'No district'}
                  </span>
                  <span className="badge text-[10px]" style={{ background: a.isActive ? '#e6f4ea' : '#fdecea', color: a.isActive ? '#2D6A1E' : '#C0392B' }}>
                    {a.isActive ? <CheckCircle size={10} className="mr-1"/> : <XCircle size={10} className="mr-1"/>}
                    {a.isActive ? 'Active' : 'Inactive'}
                  </span>
                  {a.totalBooths > 0 && (
                    <span className="badge text-[10px]" style={{ background: 'var(--surface)', color: 'var(--info)' }}>
                      {a.totalBooths} booths
                    </span>
                  )}
                </div>
              </div>
            ))
        }
      </div>

      {modal === 'form' && (
        <AdminModal initial={selected} onSave={handleSave} onClose={() => { setModal(null); setSelected(null); }} />
      )}
      <ConfirmDialog open={!!deleteId} danger title="Delete Admin"
        message="This will permanently remove the admin account."
        onConfirm={handleDelete} onCancel={() => setDeleteId(null)} />
    </div>
  );
}

// ── Form Data Tab ──────────────────────────────────────────────────────────────
function FormDataTab() {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    superApi.getFormData().then(r => setData(r.data || [])).catch(e => toast.error(e.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="p-4">
      <SectionHeader title="District Form Data" subtitle="Admin-wise structure entries" />
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="tbl">
            <thead>
              <tr>
                <th>Admin</th>
                <th>District</th>
                <th className="text-center">Super Zones</th>
                <th className="text-center">Zones</th>
                <th className="text-center">Sectors</th>
                <th className="text-center">Centers</th>
                <th className="hidden md:table-cell">Last Updated</th>
              </tr>
            </thead>
            <tbody>
              {loading ? Array.from({length:5}).map((_,i) => (
                <tr key={i}>{[1,2,3,4,5,6,7].map(j => <td key={j}><Shimmer className="h-4 rounded"/></td>)}</tr>
              ))
              : data.length === 0
                ? <tr><td colSpan={7}><Empty message="No form data" /></td></tr>
                : data.map((d, i) => (
                  <tr key={d.adminId || i} className="fade-in">
                    <td className="font-semibold text-dark text-sm">{d.adminName || '—'}</td>
                    <td className="text-xs text-subtle">{d.district || '—'}</td>
                    <td className="text-center font-bold" style={{ color: 'var(--primary)' }}>{d.superZones || 0}</td>
                    <td className="text-center font-bold" style={{ color: 'var(--accent)' }}>{d.zones || 0}</td>
                    <td className="text-center font-bold" style={{ color: 'var(--info)' }}>{d.sectors || 0}</td>
                    <td className="text-center font-bold" style={{ color: 'var(--success)' }}>{d.centers || 0}</td>
                    <td className="hidden md:table-cell text-xs text-subtle">{d.lastUpdated ? new Date(d.lastUpdated).toLocaleDateString('en-IN') : '—'}</td>
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

const TABS = { overview: OverviewTab, admins: AdminsTab, formdata: FormDataTab };

export default function SuperDashboard() {
  const [page, setPage] = useState('overview');
  const Page = TABS[page] || OverviewTab;
  return (
    <AppShell activePage={page} onNavigate={setPage}>
      <Page />
    </AppShell>
  );
}
