import { useState, useEffect, useCallback } from 'react';
import { MapPin, Plus, Pencil, Trash2 } from 'lucide-react';
import { adminApi } from '../../api/endpoints';
import { Modal, ConfirmDialog, Empty, Shimmer, SectionHeader, SearchBar, Pagination, SensChip } from '../../components/common';
import { debounce } from '../../utils/helpers';
import toast from 'react-hot-toast';

const SENSITIVITY_OPTIONS = ['A++', 'A', 'B', 'C'];

function CenterForm({ initial, onSave, onClose }) {
  const [form, setForm] = useState({
    name: '', address: '', centerType: 'C', latitude: '', longitude: '',
    totalBooths: '', ...(initial || {})
  });
  const [saving, setSaving] = useState(false);
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));
  const handleSave = async () => {
    if (!form.name.trim()) { toast.error('Name required'); return; }
    setSaving(true);
    try { await onSave(form); onClose(); }
    catch (e) { toast.error(e.message); }
    finally { setSaving(false); }
  };
  return (
    <Modal open onClose={onClose} title={initial ? 'Edit Booth / Center' : 'Add Booth / Center'}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div className="col-span-2">
            <label className="text-xs font-semibold text-subtle mb-1 block">Center Name *</label>
            <input className="field" value={form.name} onChange={e => set('name', e.target.value)} placeholder="Center / booth name" />
          </div>
          <div className="col-span-2">
            <label className="text-xs font-semibold text-subtle mb-1 block">Address</label>
            <input className="field" value={form.address} onChange={e => set('address', e.target.value)} placeholder="Full address" />
          </div>
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Sensitivity</label>
            <select className="field" value={form.centerType} onChange={e => set('centerType', e.target.value)}>
              {SENSITIVITY_OPTIONS.map(s => <option key={s} value={s}>{s}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Total Booths</label>
            <input className="field" type="number" value={form.totalBooths} onChange={e => set('totalBooths', e.target.value)} placeholder="0" />
          </div>
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Latitude</label>
            <input className="field" type="number" step="any" value={form.latitude} onChange={e => set('latitude', e.target.value)} placeholder="26.8467" />
          </div>
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Longitude</label>
            <input className="field" type="number" step="any" value={form.longitude} onChange={e => set('longitude', e.target.value)} placeholder="80.9462" />
          </div>
        </div>
        <div className="flex gap-3 justify-end">
          <button className="btn-outline px-4 py-2" onClick={onClose}>Cancel</button>
          <button className="btn-primary px-5 py-2" onClick={handleSave} disabled={saving}>
            {saving ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"/> : 'Save'}
          </button>
        </div>
      </div>
    </Modal>
  );
}

export default function BoothsPage() {
  const [centers, setCenters] = useState([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [modal, setModal] = useState(null);
  const [selected, setSelected] = useState(null);
  const [deleteId, setDeleteId] = useState(null);

  const load = useCallback(async (pg = 1, search = '') => {
    setLoading(true);
    try {
      const res = await adminApi.getCenters({ page: pg, limit: 50, q: search });
      const wrapper = res.data?.data || res.data || {};
      const arr = Array.isArray(wrapper) ? wrapper : wrapper.data || [];
      setCenters(arr);
      setTotal(wrapper.total || arr.length);
      setPage(pg);
    } catch (e) { toast.error('Failed to load centers'); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, []);

  const debouncedSearch = useCallback(debounce((v) => load(1, v), 350), []);
  const handleSearch = (v) => { setQ(v); debouncedSearch(v); };

  const handleAdd = async (form) => {
    await adminApi.addCenter(form);
    toast.success('Center added'); load(1);
  };
  const handleEdit = async (form) => {
    await adminApi.updateCenter(selected.id, form);
    toast.success('Center updated'); load(page);
  };
  const handleDelete = async () => {
    await adminApi.deleteCenter(deleteId);
    toast.success('Center deleted'); setDeleteId(null); load(1);
  };

  return (
    <div className="p-4">
      <SectionHeader
        title="Booths / Centers"
        subtitle={`${total} centers total`}
        action={
          <button className="btn-primary text-xs px-3 py-2"
            onClick={() => { setSelected(null); setModal('add'); }}>
            <Plus size={14} /> Add Center
          </button>
        }
      />

      <div className="mb-4">
        <SearchBar value={q} onChange={handleSearch} placeholder="Search center name, address…" />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {loading
          ? Array.from({ length: 9 }).map((_, i) => <Shimmer key={i} className="h-28 rounded-xl" />)
          : centers.length === 0
            ? <div className="col-span-3 card"><Empty message="No centers found" icon={MapPin} /></div>
            : centers.map(c => (
              <div key={c.id} className="card p-3.5 fade-in hover:shadow-card transition-shadow">
                <div className="flex items-start justify-between gap-2">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1.5">
                      <SensChip sens={c.centerType || c.center_type || 'C'} />
                      {c.totalBooths > 0 && (
                        <span className="text-[10px] text-subtle">{c.totalBooths} booths</span>
                      )}
                    </div>
                    <p className="font-bold text-dark text-sm leading-tight truncate">{c.name || '—'}</p>
                    <p className="text-[11px] text-subtle mt-0.5 truncate">{c.address || '—'}</p>
                    {(c.latitude && c.longitude) && (
                      <p className="font-mono text-[10px] text-subtle/70 mt-1">
                        {Number(c.latitude).toFixed(4)}, {Number(c.longitude).toFixed(4)}
                      </p>
                    )}
                  </div>
                  <div className="flex flex-col gap-1 shrink-0">
                    <button className="p-1.5 rounded hover:bg-surface text-primary"
                      onClick={() => { setSelected(c); setModal('edit'); }}>
                      <Pencil size={13} />
                    </button>
                    <button className="p-1.5 rounded hover:bg-red-50 text-error"
                      onClick={() => setDeleteId(c.id)}>
                      <Trash2 size={13} />
                    </button>
                  </div>
                </div>
              </div>
            ))
        }
      </div>

      <div className="mt-4">
        <Pagination page={page} totalPages={Math.ceil(total / 50)} onPage={(p) => load(p)} />
      </div>

      {modal === 'add' && <CenterForm onSave={handleAdd} onClose={() => setModal(null)} />}
      {modal === 'edit' && selected && (
        <CenterForm initial={selected} onSave={handleEdit} onClose={() => { setModal(null); setSelected(null); }} />
      )}
      <ConfirmDialog
        open={!!deleteId} danger
        title="Delete Center"
        message="This will permanently remove the booth/center."
        onConfirm={handleDelete}
        onCancel={() => setDeleteId(null)}
      />
    </div>
  );
}
