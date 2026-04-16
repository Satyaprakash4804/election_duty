import { useState, useEffect } from 'react';
import {
  Shield, Users, MapPin, Vote, Activity, Plus, Pencil, Trash2,
  Eye, EyeOff, Save, AlertCircle, CheckCircle, XCircle, RefreshCw
} from 'lucide-react';
import AppShell from '../../components/layout/AppShell';
import { masterApi } from '../../api/endpoints';
import { StatCard, Modal, ConfirmDialog, Empty, Shimmer, SectionHeader, SearchBar } from '../../components/common';
import toast from 'react-hot-toast';

function UserModal({ title, initial, onSave, onClose, fields = [] }) {
  const [form, setForm] = useState({ name: '', username: '', password: '', ...(initial || {}) });
  const [showPass, setShowPass] = useState(false);
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));
  const handleSave = async () => {
    if (!form.name || !form.username) { setErr('Name and username required'); return; }
    setSaving(true); setErr('');
    try { await onSave(form); onClose(); }
    catch (e) { setErr(e.message || 'Failed'); }
    finally { setSaving(false); }
  };
  return (
    <Modal open onClose={onClose} title={title}>
      <div className="space-y-3">
        {err && <div className="text-xs text-error bg-red-50 p-2 rounded-lg border border-red-200">{err}</div>}
        <div className="grid grid-cols-2 gap-3">
          {[['name','Full Name',false],['username','Username',false],...fields].map(([k,label]) => (
            <div key={k}>
              <label className="text-xs font-semibold text-subtle mb-1 block">{label}</label>
              <input className="field" value={form[k] || ''} onChange={e => set(k, e.target.value)} placeholder={label} />
            </div>
          ))}
          {!initial && (
            <div className="relative">
              <label className="text-xs font-semibold text-subtle mb-1 block">Password *</label>
              <input className="field pr-9" type={showPass ? 'text' : 'password'}
                value={form.password || ''} onChange={e => set('password', e.target.value)} placeholder="Password" />
              <button type="button" className="absolute right-3 bottom-3" onClick={() => setShowPass(!showPass)}>
                {showPass ? <EyeOff size={14} className="text-subtle"/> : <Eye size={14} className="text-subtle"/>}
              </button>
            </div>
          )}
        </div>
        <div className="flex gap-3 justify-end">
          <button className="btn-outline px-4 py-2" onClick={onClose}>Cancel</button>
          <button className="btn-primary px-5 py-2" onClick={handleSave} disabled={saving}>
            {saving ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"/> : <><Save size={14}/>Save</>}
          </button>
        </div>
      </div>
    </Modal>
  );
}

// ── Overview ───────────────────────────────────────────────────────────────────
function OverviewTab() {
  const [ov, setOv] = useState(null);
  const [sys, setSys] = useState(null);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    Promise.all([masterApi.overview(), masterApi.getSystemStats()])
      .then(([ovRes, sysRes]) => { setOv(ovRes.data || ovRes); setSys(sysRes.data || sysRes); })
      .catch(e => toast.error(e.message)).finally(() => setLoading(false));
  }, []);

  const items = ov ? [
    { label: 'Super Admins', value: ov.totalSuperAdmins ?? 0, icon: Shield, color: '#1A5276' },
    { label: 'Total Admins', value: ov.totalAdmins ?? 0, icon: Users, color: '#8B6914' },
    { label: 'Total Staff', value: ov.totalStaff ?? 0, icon: Users, color: '#B8860B' },
    { label: 'Assigned Duties', value: ov.assignedDuties ?? 0, icon: Vote, color: '#2D6A1E' },
  ] : [];

  return (
    <div className="p-4 max-w-4xl mx-auto">
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        {loading ? [1,2,3,4].map(i=><Shimmer key={i} className="h-24"/>) : items.map(s=><StatCard key={s.label} {...s}/>)}
      </div>
      {sys && (
        <div className="card p-4">
          <h3 className="font-bold text-dark mb-3 text-sm flex items-center gap-2">
            <Activity size={16} className="text-primary"/> System Statistics
          </h3>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {Object.entries(sys).filter(([,v]) => v != null).map(([k, v]) => (
              <div key={k} className="rounded-lg p-2.5" style={{background:'var(--surface)',border:'1px solid rgba(212,168,67,0.2)'}}>
                <p className="text-[10px] font-bold text-subtle uppercase tracking-wide">{k.replace(/_/g,' ')}</p>
                <p className="font-bold text-dark text-sm mt-0.5">{String(v)}</p>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ── Super Admins ───────────────────────────────────────────────────────────────
function SuperAdminsTab() {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(null);
  const [selected, setSelected] = useState(null);
  const [deleteId, setDeleteId] = useState(null);
  const [q, setQ] = useState('');

  const load = () => {
    setLoading(true);
    masterApi.getSuperAdmins().then(r => setList(r.data || [])).catch(e => toast.error(e.message)).finally(() => setLoading(false));
  };
  useEffect(load, []);

  const filtered = list.filter(x => !q || x.name?.toLowerCase().includes(q.toLowerCase()) || x.username?.toLowerCase().includes(q.toLowerCase()));

  const handleSave = async (form) => {
    if (selected) await masterApi.updateSuperAdmin(selected.id, form);
    else await masterApi.createSuperAdmin(form);
    toast.success(selected ? 'Super Admin updated' : 'Super Admin created'); load();
  };
  const handleDelete = async () => {
    await masterApi.deleteSuperAdmin(deleteId);
    toast.success('Deleted'); setDeleteId(null); load();
  };

  return (
    <div className="p-4">
      <SectionHeader title="Super Admins" subtitle={`${list.length} accounts`}
        action={<button className="btn-primary text-xs px-3 py-2" onClick={() => {setSelected(null); setModal('form');}}>
          <Plus size={14}/> Create
        </button>}/>
      <div className="mb-4"><SearchBar value={q} onChange={setQ} placeholder="Search…"/></div>
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {loading ? Array.from({length:4}).map((_,i)=><Shimmer key={i} className="h-24 rounded-xl"/>)
          : filtered.length === 0
            ? <div className="col-span-3 card"><Empty message="No super admins" icon={Shield}/></div>
            : filtered.map(u => (
              <div key={u.id} className="card p-4 fade-in">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full flex items-center justify-center font-bold text-sm"
                      style={{background:'#1A5276',color:'#90caf9'}}>
                      {(u.name||'?')[0]}
                    </div>
                    <div>
                      <p className="font-bold text-dark text-sm">{u.name}</p>
                      <p className="text-xs text-subtle">@{u.username}</p>
                      {u.adminsUnder > 0 && <p className="text-[10px] text-subtle">{u.adminsUnder} admins</p>}
                    </div>
                  </div>
                  <div className="flex gap-1">
                    <button className="p-1.5 rounded hover:bg-surface text-primary" onClick={() => {setSelected(u); setModal('form');}}>
                      <Pencil size={13}/>
                    </button>
                    <button className="p-1.5 rounded hover:bg-red-50 text-error" onClick={() => setDeleteId(u.id)}>
                      <Trash2 size={13}/>
                    </button>
                  </div>
                </div>
                <div className="mt-2">
                  <span className="badge text-[10px]" style={{background: u.isActive ? '#e6f4ea':'#fdecea', color: u.isActive?'#2D6A1E':'#C0392B'}}>
                    {u.isActive ? 'Active':'Inactive'}
                  </span>
                </div>
              </div>
            ))
        }
      </div>
      {modal === 'form' && (
        <UserModal title={selected ? 'Edit Super Admin' : 'Create Super Admin'} initial={selected}
          onSave={handleSave} onClose={() => {setModal(null); setSelected(null);}} />
      )}
      <ConfirmDialog open={!!deleteId} danger title="Delete Super Admin" message="This action is permanent."
        onConfirm={handleDelete} onCancel={() => setDeleteId(null)} />
    </div>
  );
}

// ── Admins ─────────────────────────────────────────────────────────────────────
function AdminsTab() {
  const [list, setList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const load = () => {
    setLoading(true);
    masterApi.getAdmins().then(r => setList(r.data || [])).catch(e => toast.error(e.message)).finally(() => setLoading(false));
  };
  useEffect(load, []);
  const filtered = list.filter(x => !q || x.name?.toLowerCase().includes(q.toLowerCase()));
  return (
    <div className="p-4">
      <SectionHeader title="All Admin Accounts" subtitle={`${list.length} total`}/>
      <div className="mb-4"><SearchBar value={q} onChange={setQ} placeholder="Search admins…"/></div>
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="tbl">
            <thead><tr><th>Name</th><th>Username</th><th>District</th><th>Created By</th><th className="text-center">Zones</th><th>Status</th></tr></thead>
            <tbody>
              {loading ? Array.from({length:6}).map((_,i)=>(
                <tr key={i}>{[1,2,3,4,5,6].map(j=><td key={j}><Shimmer className="h-4 rounded"/></td>)}</tr>
              ))
              : filtered.map(a => (
                <tr key={a.id} className="fade-in">
                  <td className="font-semibold text-dark text-sm">{a.name}</td>
                  <td className="font-mono text-xs text-subtle">@{a.username}</td>
                  <td className="text-xs text-subtle">{a.district || '—'}</td>
                  <td className="text-xs text-subtle">{a.createdBy || '—'}</td>
                  <td className="text-center font-bold text-primary">{a.superZoneCount || 0}</td>
                  <td>
                    <span className="badge text-[10px]" style={{background: a.isActive ? '#e6f4ea':'#fdecea', color: a.isActive?'#2D6A1E':'#C0392B'}}>
                      {a.isActive ? 'Active':'Inactive'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

// ── System Logs ────────────────────────────────────────────────────────────────
function LogsTab() {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('ALL');
  const load = (f = filter) => {
    setLoading(true);
    masterApi.getLogs({ level: f === 'ALL' ? undefined : f, limit: 100 })
      .then(r => setLogs(r.data || [])).catch(e => toast.error(e.message)).finally(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);
  const levelColors = { INFO: '#1A5276', WARN: '#E67E22', ERROR: '#C0392B', DEBUG: '#666' };
  return (
    <div className="p-4">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="font-bold text-dark">System Logs</h2>
          <p className="text-xs text-subtle">{logs.length} entries</p>
        </div>
        <div className="flex items-center gap-2">
          {['ALL','INFO','WARN','ERROR'].map(l => (
            <button key={l}
              className={`text-xs px-3 py-1.5 rounded-lg font-semibold border transition-colors ${filter===l ? 'text-white border-transparent' : 'btn-outline'}`}
              style={filter===l ? {background: levelColors[l]||'var(--primary)', borderColor: 'transparent'} : {}}
              onClick={() => { setFilter(l); load(l); }}>
              {l}
            </button>
          ))}
          <button className="btn-outline p-2" onClick={() => load()}><RefreshCw size={14}/></button>
        </div>
      </div>
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="tbl">
            <thead><tr><th>Level</th><th>Message</th><th>Module</th><th>Time</th></tr></thead>
            <tbody>
              {loading ? Array.from({length:8}).map((_,i)=>(
                <tr key={i}>{[1,2,3,4].map(j=><td key={j}><Shimmer className="h-4 rounded"/></td>)}</tr>
              ))
              : logs.length === 0
                ? <tr><td colSpan={4}><Empty message="No logs"/></td></tr>
                : logs.map(l => (
                  <tr key={l.id} className="fade-in">
                    <td>
                      <span className="badge text-[10px] font-bold"
                        style={{background: (levelColors[l.level]||'#666')+'18', color: levelColors[l.level]||'#666'}}>
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

const TABS = { overview: OverviewTab, superadmins: SuperAdminsTab, admins: AdminsTab, logs: LogsTab };

export default function MasterDashboard() {
  const [page, setPage] = useState('overview');
  const Page = TABS[page] || OverviewTab;
  return (
    <AppShell activePage={page} onNavigate={setPage}>
      <Page />
    </AppShell>
  );
}
