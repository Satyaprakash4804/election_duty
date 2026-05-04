import { useState, useEffect, useCallback } from 'react';
import {
  Users, MapPin, Vote, Plus, Pencil, Trash2,
  Eye, EyeOff, Save, Shield, CheckCircle, XCircle,
  ChevronRight, Layers, Grid, Building2, Landmark,
  LocateFixed, UserCog, Calendar, X, Lock, LockOpen,
  HourglassIcon, AlertTriangle, ExternalLink, Clock,
  FileText, Map
} from 'lucide-react';
import AppShell from '../../components/layout/AppShell';
import { superApi } from '../../api/endpoints';
import {
  StatCard, Modal, ConfirmDialog, Empty, Shimmer,
  SectionHeader, SearchBar
} from '../../components/common';
import { UP_DISTRICTS } from '../../utils/helpers';
import toast from 'react-hot-toast';
import MapViewButton from '../../components/common/Mapviewbutton';
import { useNavigate } from 'react-router-dom';

// ─────────────────────────────────────────────
//  PALETTE (mirrors Flutter kXxx constants)
// ─────────────────────────────────────────────
const C = {
  bg: '#FDF6E3',
  surface: '#F5E6C8',
  primary: '#8B6914',
  accent: '#B8860B',
  dark: '#4A3000',
  subtle: '#AA8844',
  border: '#D4A843',
  error: '#C0392B',
  success: '#2E7D32',
  info: '#1565C0',
  orange: '#E65100',
  purple: '#6A1B9A',
};

// ─────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────
function fmtDate(iso) {
  if (!iso) return '—';
  try {
    const d = new Date(iso);
    return d.toLocaleDateString('en-IN', {
      day: '2-digit', month: '2-digit', year: 'numeric'
    });
  } catch { return iso; }
}

function Pill({ children, color }) {
  return (
    <span
      className="inline-flex items-center gap-0.5 px-2 py-0.5 rounded-full text-[10px] font-bold border"
      style={{ color, background: color + '18', borderColor: color + '44' }}
    >
      {children}
    </span>
  );
}

function SummaryPill({ count, label, color }) {
  return (
    <div
      className="flex items-center gap-1.5 px-3 py-1.5 rounded-full border"
      style={{ color, background: color + '1A', borderColor: color + '4D' }}
    >
      <span className="text-base font-black">{count}</span>
      <span className="text-[11px] font-semibold">{label}</span>
    </div>
  );
}

// Status config for unlock requests
function unlockStatusCfg(status) {
  if (status === 'pending') return { color: C.orange, icon: HourglassIcon, label: 'PENDING' };
  if (status === 'approved') return { color: C.success, icon: CheckCircle, label: 'APPROVED' };
  return { color: C.error, icon: XCircle, label: 'REJECTED' };
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
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState('');
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handleSave = async () => {
    if (!form.name || !form.username) { setErr('Name and username are required'); return; }
    if (!isEdit && !form.password) { setErr('Password is required'); return; }
    if (!isEdit && form.password.length < 6) { setErr('Password must be at least 6 characters'); return; }
    if (!isEdit && form.password !== form.confirmPassword) { setErr('Passwords do not match'); return; }
    if (!form.district) { setErr('Please select a district'); return; }
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
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Full Name *</label>
            <input className="field" value={form.name}
              onChange={e => set('name', e.target.value)} placeholder="Admin full name" />
          </div>
          <div>
            <label className="text-xs font-semibold text-subtle mb-1 block">Admin User ID *</label>
            <input className="field" value={form.username}
              onChange={e => set('username', e.target.value)} placeholder="Login ID" />
          </div>
          <div className={isEdit ? 'sm:col-span-2' : ''}>
            <label className="text-xs font-semibold text-subtle mb-1 block">District *</label>
            <select className="field" value={form.district}
              onChange={e => set('district', e.target.value)}>
              <option value="">Select district</option>
              {UP_DISTRICTS.map(d => <option key={d} value={d}>{d}</option>)}
            </select>
          </div>
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
                <button type="button" className="absolute right-3 top-[34px]"
                  onClick={() => setShowPass(s => !s)}>
                  {showPass
                    ? <EyeOff size={14} className="text-subtle" />
                    : <Eye size={14} className="text-subtle" />}
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
          <button
            className="btn-primary px-5 py-2 text-sm flex items-center gap-2"
            onClick={handleSave}
            disabled={saving}
          >
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
//  FORM DATA DETAIL MODAL
// ─────────────────────────────────────────────
function FormDetailModal({ entry, onClose }) {
  const miniStats = [
    { label: 'Super Zones', value: entry.superZones, icon: Layers },
    { label: 'Zones', value: entry.zones, icon: Grid },
    { label: 'Sectors', value: entry.sectors, icon: Building2 },
    { label: 'Gram Panchayats', value: entry.gramPanchayats, icon: Landmark },
    { label: 'Centers', value: entry.centers, icon: LocateFixed },
  ];
  return (
    <Modal open onClose={onClose} title={`${entry.district} — Form Data`}>
      <div className="space-y-4">
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
        <div style={{ borderTop: '1px solid rgba(212,168,67,0.35)' }} />
        <div className="grid grid-cols-3 gap-2">
          {miniStats.map(({ label, value, icon: Icon }) => (
            <div
              key={label}
              className="flex flex-col items-center justify-center rounded-xl py-3 px-2 text-center"
              style={{ background: C.surface, border: `1px solid ${C.border}4D` }}
            >
              <Icon size={16} className="mb-1.5" style={{ color: C.primary }} />
              <span className="text-lg font-black" style={{ color: C.dark }}>{value ?? 0}</span>
              <span className="text-[9px] font-bold leading-tight mt-0.5" style={{ color: C.subtle }}>{label}</span>
            </div>
          ))}
        </div>
        <button
          onClick={onClose}
          className="w-full py-2.5 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2"
          style={{ background: C.dark }}
        >
          <X size={14} /> Close
        </button>
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────
//  UNLOCK REQUEST DETAIL MODAL  ← NEW (Flutter: _showUnlockDetail)
// ─────────────────────────────────────────────
function UnlockDetailModal({ req, onAction, onClose }) {
  const isPending = req.status === 'pending';
  const { color: statusColor } = unlockStatusCfg(req.status);
  const [acting, setActing] = useState(null);

  const doAction = async (action) => {
    setActing(action);
    try { await onAction(req, action); onClose(); }
    catch (_) { }
    finally { setActing(null); }
  };

  return (
    <Modal open onClose={onClose} title="Unlock Request Detail">
      <div className="space-y-4">
        {/* Super Zone chip */}
        <div
          className="flex items-center gap-3 rounded-xl p-3.5"
          style={{ background: C.purple + '10', border: `1px solid ${C.purple}40` }}
        >
          <div
            className="w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0"
            style={{ background: C.purple + '20' }}
          >
            <Layers size={18} style={{ color: C.purple }} />
          </div>
          <div>
            <p className="font-extrabold text-sm" style={{ color: C.dark }}>{req.superZoneName}</p>
            <p className="text-[11px]" style={{ color: C.subtle }}>Super Zone ID: {req.superZoneId}</p>
          </div>
        </div>

        {/* Meta rows */}
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-sm">
            <UserCog size={14} style={{ color: C.subtle }} className="flex-shrink-0" />
            <span className="font-semibold" style={{ color: C.subtle }}>Requested By:</span>
            <span className="font-bold" style={{ color: C.dark }}>{req.adminName}</span>
          </div>
          <div className="flex items-center gap-2 text-sm">
            <Clock size={14} style={{ color: C.subtle }} className="flex-shrink-0" />
            <span className="font-semibold" style={{ color: C.subtle }}>Requested At:</span>
            <span className="font-bold" style={{ color: C.dark }}>{fmtDate(req.createdAt)}</span>
          </div>
        </div>

        {/* Reason */}
        <div>
          <p className="text-xs font-semibold mb-1.5" style={{ color: C.subtle }}>कारण (Reason)</p>
          <div
            className="w-full rounded-xl p-3 text-sm"
            style={{
              background: 'white',
              border: `1px solid ${C.border}80`,
              color: req.reason ? C.dark : C.subtle,
            }}
          >
            {req.reason || '(कोई कारण नहीं दिया)'}
          </div>
        </div>

        {/* Action buttons */}
        {isPending ? (
          <div className="flex gap-3">
            <button
              className="flex-1 py-3 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2"
              style={{ background: C.error }}
              onClick={() => doAction('reject')}
              disabled={!!acting}
            >
              {acting === 'reject'
                ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                : <><XCircle size={14} /> Reject</>}
            </button>
            <button
              className="flex-1 py-3 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2"
              style={{ background: C.success }}
              onClick={() => doAction('approve')}
              disabled={!!acting}
            >
              {acting === 'approve'
                ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                : <><LockOpen size={14} /> Approve Unlock</>}
            </button>
          </div>
        ) : (
          <button
            onClick={onClose}
            className="w-full py-2.5 rounded-xl text-sm font-bold border flex items-center justify-center"
            style={{ color: C.subtle, borderColor: C.border }}
          >
            बंद करें
          </button>
        )}
      </div>
    </Modal>
  );
}

// ─────────────────────────────────────────────
//  INLINE UNLOCK REQUEST MINI-CARD
//  (used inside admin cards — Flutter: inline block in _adminCard)
// ─────────────────────────────────────────────
function InlineUnlockCard({ req, onAction, onDetail }) {
  const [acting, setActing] = useState(null);
  const doAction = async (action) => {
    setActing(action);
    try { await onAction(req, action); }
    catch (_) { }
    finally { setActing(null); }
  };

  return (
    <div
      className="rounded-xl p-2.5 mb-2"
      style={{
        background: C.orange + '0D',
        border: `1px solid ${C.orange}4D`,
      }}
    >
      <div className="flex items-start gap-2 mb-2">
        <Layers size={12} style={{ color: C.purple }} className="mt-0.5 flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="font-bold text-xs truncate" style={{ color: C.dark }}>{req.superZoneName}</p>
          {req.reason && (
            <p className="text-[10px] mt-0.5 line-clamp-2" style={{ color: C.subtle }}>{req.reason}</p>
          )}
        </div>
        <span className="text-[9px] flex-shrink-0" style={{ color: C.subtle }}>{fmtDate(req.createdAt)}</span>
      </div>

      <div className="flex gap-1.5">
        {/* Reject */}
        <button
          className="flex-1 py-1.5 rounded-lg text-[11px] font-bold flex items-center justify-center gap-1 border transition-colors"
          style={{
            color: C.error,
            background: C.error + '14',
            borderColor: C.error + '4D',
          }}
          onClick={() => doAction('reject')}
          disabled={!!acting}
        >
          {acting === 'reject'
            ? <div className="w-3 h-3 border-2 rounded-full animate-spin" style={{ borderColor: C.error + '40', borderTopColor: C.error }} />
            : <><XCircle size={11} /> Reject</>}
        </button>
        {/* Approve */}
        <button
          className="flex-1 py-1.5 rounded-lg text-[11px] font-bold flex items-center justify-center gap-1 border transition-colors"
          style={{
            color: C.success,
            background: C.success + '14',
            borderColor: C.success + '59',
          }}
          onClick={() => doAction('approve')}
          disabled={!!acting}
        >
          {acting === 'approve'
            ? <div className="w-3 h-3 border-2 rounded-full animate-spin" style={{ borderColor: C.success + '40', borderTopColor: C.success }} />
            : <><LockOpen size={11} /> Approve</>}
        </button>
        {/* Detail */}
        <button
          className="w-8 h-8 rounded-lg flex items-center justify-center border flex-shrink-0"
          style={{
            background: C.info + '14',
            borderColor: C.info + '4D',
          }}
          onClick={() => onDetail(req)}
          title="View detail"
        >
          <ExternalLink size={12} style={{ color: C.info }} />
        </button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────
//  UNLOCK REQUEST FULL CARD  (Tab 2 list)
// ─────────────────────────────────────────────
function UnlockRequestCard({ req, onAction, onDetail }) {
  const { color, icon: StatusIcon, label } = unlockStatusCfg(req.status);
  const isPending = req.status === 'pending';
  const isApproved = req.status === 'approved';
  const [acting, setActing] = useState(null);

  const doAction = async (action) => {
    setActing(action);
    try { await onAction(req, action); }
    catch (_) { }
    finally { setActing(null); }
  };

  return (
    <div
      className="rounded-2xl overflow-hidden mb-3"
      style={{
        border: `1.2px solid ${color}66`,
        boxShadow: `${color}0F 0px 3px 8px`,
      }}
    >
      {/* Header strip */}
      <div
        className="flex items-center gap-3 px-4 py-2.5"
        style={{ background: color + '12' }}
      >
        {/* Status badge */}
        <div
          className="flex items-center gap-1.5 px-2.5 py-1 rounded-md text-[10px] font-extrabold text-white flex-shrink-0"
          style={{ background: color }}
        >
          <StatusIcon size={10} />
          {label}
        </div>
        <span className="text-sm font-bold flex-1" style={{ color }}>Request #{req.id}</span>
        <span className="text-[11px]" style={{ color: C.subtle }}>{fmtDate(req.createdAt)}</span>
      </div>

      <div className="p-4 space-y-3" style={{ background: 'white' }}>
        {/* Super Zone */}
        <div
          className="flex items-center gap-3 rounded-xl p-3"
          style={{ background: C.purple + '0D', border: `1px solid ${C.purple}33` }}
        >
          <div
            className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0"
            style={{ background: C.purple + '20' }}
          >
            <Layers size={16} style={{ color: C.purple }} />
          </div>
          <div className="min-w-0">
            <p className="font-extrabold text-sm truncate" style={{ color: C.dark }}>{req.superZoneName}</p>
            <p className="text-[11px]" style={{ color: C.subtle }}>Super Zone ID: {req.superZoneId}</p>
          </div>
        </div>

        {/* Admin info */}
        <div className="flex items-center gap-1.5 text-xs">
          <UserCog size={13} style={{ color: C.subtle }} />
          <span style={{ color: C.subtle }}>Admin: </span>
          <span className="font-bold" style={{ color: C.dark }}>{req.adminName}</span>
        </div>

        {/* Reason */}
        {req.reason && (
          <div
            className="rounded-xl p-3 text-sm"
            style={{ background: 'white', border: `1px solid ${C.border}66` }}
          >
            <p className="text-[10px] font-semibold mb-1" style={{ color: C.subtle }}>Reason</p>
            <p style={{ color: C.dark }}>{req.reason}</p>
          </div>
        )}

        {/* Actions */}
        {isPending ? (
          <div className="flex gap-2">
            <button
              className="flex-1 py-2.5 rounded-xl text-xs font-bold text-white flex items-center justify-center gap-1.5"
              style={{ background: C.error }}
              onClick={() => doAction('reject')}
              disabled={!!acting}
            >
              {acting === 'reject'
                ? <div className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                : <><XCircle size={13} /> Reject</>}
            </button>
            <button
              className="flex-1 py-2.5 rounded-xl text-xs font-bold text-white flex items-center justify-center gap-1.5"
              style={{ background: C.success }}
              onClick={() => doAction('approve')}
              disabled={!!acting}
            >
              {acting === 'approve'
                ? <div className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                : <><LockOpen size={13} /> Approve</>}
            </button>
            <button
              className="w-10 h-10 rounded-xl flex items-center justify-center border flex-shrink-0"
              style={{ background: C.info + '14', borderColor: C.info + '4D' }}
              onClick={() => onDetail(req)}
            >
              <ExternalLink size={15} style={{ color: C.info }} />
            </button>
          </div>
        ) : (
          <div className="flex items-center gap-2">
            {isApproved
              ? <LockOpen size={13} style={{ color }} />
              : <Lock size={13} style={{ color }} />}
            <span className="text-xs font-semibold flex-1" style={{ color }}>
              {isApproved ? 'Zone was successfully unlocked' : 'Request was rejected'}
            </span>
            <button
              className="text-xs font-semibold"
              style={{ color: C.info }}
              onClick={() => onDetail(req)}
            >
              Details →
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────
//  ROOT COMPONENT — manages shared state
// ─────────────────────────────────────────────
export default function SuperDashboard() {
  const [activeTab, setActiveTab] = useState('overview');

  // ── Shared data (unlock requests needed in multiple tabs) ──
  const [unlockRequests, setUnlockRequests] = useState([]);
  const [loadingUnlocks, setLoadingUnlocks] = useState(true);

  const pendingCount = unlockRequests.filter(r => r.status === 'pending').length;

  const fetchUnlockRequests = useCallback(async () => {
    setLoadingUnlocks(true);
    try {
      const res = await superApi.getUnlockRequests();
      setUnlockRequests(res.data || []);
    } catch (e) {
      toast.error(e.message || 'Failed to load unlock requests');
    } finally {
      setLoadingUnlocks(false);
    }
  }, []);

  useEffect(() => { fetchUnlockRequests(); }, [fetchUnlockRequests]);

  // ── Action: approve / reject ──
  const handleUnlockAction = useCallback(async (req, action) => {
    try {
      await superApi.actionUnlockRequest(req.id, action);
      toast.success(
        action === 'approve' ? '✅ Unlock Approved!' : '❌ Request Rejected',
        { style: { background: action === 'approve' ? C.success : C.error, color: 'white' } }
      );
      await fetchUnlockRequests();
    } catch (e) {
      toast.error(e.message || 'Action failed');
      throw e;
    }
  }, [fetchUnlockRequests]);

  // ── Tab definitions ──
  const TABS = [
    { id: 'overview', label: 'Overview', icon: <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="7" height="7" /><rect x="14" y="3" width="7" height="7" /><rect x="3" y="14" width="7" height="7" /><rect x="14" y="14" width="7" height="7" /></svg>, badge: null },
    { id: 'admins', label: 'Admins', icon: <Shield size={15} />, badge: null },
    { id: 'unlocks', label: 'Unlocks', icon: <LockOpen size={15} />, badge: pendingCount },
    { id: 'formdata', label: 'Form Data', icon: <FileText size={15} />, badge: null },
  ];

  const [page, setPage] = useState('overview');

  return (
    <AppShell activePage={activeTab}
  onNavigate={(p) => {
    setPage(p);
    setActiveTab(p);
  }}>
      {/* ── Top Bar ── */}
      <div
        className="flex items-center gap-3 px-4 py-3 sticky top-0 z-30"
        style={{ background: C.dark }}
      >
        {/* Logo */}
        <div
          className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 border"
          style={{ background: C.primary, borderColor: C.border }}
        >
          <Vote size={18} color="white" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-[10px] font-extrabold tracking-widest" style={{ color: C.border }}>
            SUPER ADMIN PANEL
          </p>
          <p className="text-xs" style={{ color: 'rgba(255,255,255,0.6)' }}>
            UP Election Cell — District Monitoring
          </p>
        </div>
        {/* Pending unlocks indicator */}
        {pendingCount > 0 && (
          <button
            onClick={() => setActiveTab('unlocks')}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-full text-white text-[11px] font-extrabold flex-shrink-0"
            style={{ background: C.orange }}
          >
            <LockOpen size={11} />
            {pendingCount}
          </button>
        )}
      </div>

      {/* ── Tab Content ── */}
      <div className="animate-[fadeIn_0.35s_ease-out]">
        {activeTab === 'overview' && (
          <OverviewTab
            unlockRequests={unlockRequests}
            pendingCount={pendingCount}
            onGoToUnlocks={() => setActiveTab('unlocks')}
          />
        )}
        {activeTab === 'admins' && (
          <AdminsTab
            unlockRequests={unlockRequests}
            pendingCount={pendingCount}
            onGoToUnlocks={() => setActiveTab('unlocks')}
            onUnlockAction={handleUnlockAction}
          />
        )}
        {activeTab === 'unlocks' && (
          <UnlocksTab
            unlockRequests={unlockRequests}
            loading={loadingUnlocks}
            onRefresh={fetchUnlockRequests}
            onAction={handleUnlockAction}
          />
        )}
        {activeTab === 'formdata' && <FormDataTab />}
      </div>
    </AppShell>
  );
}

// ─────────────────────────────────────────────
//  TAB 0 — OVERVIEW
// ─────────────────────────────────────────────
function OverviewTab({ unlockRequests, pendingCount, onGoToUnlocks }) {
  const [overview, setOverview] = useState(null);
  const [admins, setAdmins] = useState([]);
  const [loading, setLoading] = useState(true);
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
    { label: 'Total Admins', value: admins.length, icon: Shield, color: C.primary },
    { label: 'Total Booths', value: overview.totalBooths ?? 0, icon: MapPin, color: C.info },
    { label: 'Total Staff', value: overview.totalStaff ?? 0, icon: Users, color: C.accent },
    { label: 'Assigned Duties', value: overview.assignedDuties ?? 0, icon: Vote, color: C.success },
  ] : [];

  return (
    <div className="p-4 max-w-4xl mx-auto">

      {/* ── Pending Unlock Banner (Flutter: pending unlock banner in overview) ── */}
      {pendingCount > 0 && (
        <button
          onClick={onGoToUnlocks}
          className="w-full flex items-center gap-3 rounded-xl px-4 py-3 mb-4 text-left transition-opacity hover:opacity-90"
          style={{
            background: C.orange + '1A',
            border: `1px solid ${C.orange}80`,
          }}
        >
          <div
            className="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0"
            style={{ background: C.orange }}
          >
            <LockOpen size={17} color="white" />
          </div>
          <div className="flex-1">
            <p className="font-extrabold text-sm" style={{ color: C.orange }}>
              {pendingCount} Pending Unlock Request{pendingCount > 1 ? 's' : ''}
            </p>
            <p className="text-xs" style={{ color: C.orange }}>
              Tap to review and approve/reject
            </p>
          </div>
          <ChevronRight size={18} style={{ color: C.orange }} />
        </button>
      )}

      {/* ── Stats grid ── */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        {loading
          ? [1, 2, 3, 4].map(i => <Shimmer key={i} className="h-24 rounded-xl" />)
          : statItems.map(s => <StatCard key={s.label} {...s} />)
        }
      </div>

      {/* ── Goswara Report banner ── */}
      <div
        onClick={() => nav('/goswara-page')}
        className="rounded-xl p-4 mb-3 cursor-pointer hover:opacity-95 transition-opacity"
        style={{
          background: 'linear-gradient(135deg, #8B6914 0%, #B8860B 100%)',
          boxShadow: 'rgba(139,105,20,0.3) 0px 5px 14px',
        }}
      >
        <div className="flex items-center gap-4">
          <div
            className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ background: 'rgba(255,255,255,0.15)' }}
          >
            <FileText size={20} color="white" />
          </div>
          <div className="flex-1">
            <p className="font-extrabold text-white text-sm">Goswara Report</p>
            <p className="text-white/60 text-xs mt-0.5">Summary Report of Booth Staff</p>
          </div>
          <ChevronRight size={20} className="text-white/60 flex-shrink-0" />
        </div>
      </div>

      {/* ── Hierarchy Report banner ── */}
      <div
        onClick={() => nav('/heirarchy-report')}
        className="rounded-xl p-4 mb-3 cursor-pointer hover:opacity-95 transition-opacity"
        style={{ background: 'linear-gradient(135deg, #0F2B5B 0%, #1A3D7C 100%)' }}
      >
        <div className="flex items-center gap-4">
          <div
            className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ background: 'rgba(255,255,255,0.1)' }}
          >
            <Grid size={20} color="white" />
          </div>
          <div className="flex-1">
            <p className="font-extrabold text-white text-sm">Hierarchy Report</p>
            <p className="text-white/60 text-xs mt-0.5">Super Zone · Sector · Panchayat</p>
          </div>
          <ChevronRight size={20} className="text-white/60 flex-shrink-0" />
        </div>
      </div>

      {/* ── Map View ── */}
      <MapViewButton className="w-full mb-5" />

      {/* ── District Summary (Flutter: _districtCard list) ── */}
      {!loading && admins.length > 0 && (
        <>
          <div className="flex items-center gap-2 mb-3">
            <div className="w-1 h-[18px] rounded-full" style={{ background: C.primary }} />
            <h3 className="font-extrabold text-sm" style={{ color: C.dark }}>District Summary</h3>
          </div>
          <div className="space-y-2.5">
            {admins.map(a => (
              <div
                key={a.id}
                className="flex items-center gap-3 rounded-xl px-4 py-3"
                style={{ background: 'white', border: `1px solid ${C.border}66` }}
              >
                <div
                  className="w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0"
                  style={{ background: C.surface, border: `1px solid ${C.border}` }}
                >
                  <Building2 size={18} style={{ color: C.primary }} />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-bold text-sm truncate" style={{ color: C.dark }}>{a.district || '—'}</p>
                  <p className="text-xs truncate" style={{ color: C.subtle }}>{a.name}</p>
                </div>
                <div className="flex flex-col items-end gap-1 flex-shrink-0">
                  <Pill color={C.primary}>{a.totalBooths ?? 0} Booths</Pill>
                  <Pill color={C.accent}>{a.assignedStaff ?? 0} Staff</Pill>
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
function AdminsTab({ unlockRequests, pendingCount, onGoToUnlocks, onUnlockAction }) {
  const [admins, setAdmins] = useState([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [modal, setModal] = useState(null);
  const [selected, setSelected] = useState(null);
  const [deleteId, setDeleteId] = useState(null);
  const [detailReq, setDetailReq] = useState(null); // unlock detail modal

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
    else await superApi.createAdmin(form);
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
      {/* Header row */}
      <div
        className="flex items-center justify-between gap-3 mb-3 px-1"
      >
        <p className="font-bold text-sm" style={{ color: C.dark }}>
          {admins.length} Admin(s) Registered
        </p>
        <button
          className="btn-primary text-xs px-3 py-2 flex items-center gap-1.5"
          onClick={() => { setSelected(null); setModal('form'); }}
        >
          <Plus size={14} /> New Admin
        </button>
      </div>

      {/* ── Pending unlocks strip (Flutter: pending strip in admin tab) ── */}
      {pendingCount > 0 && (
        <button
          onClick={onGoToUnlocks}
          className="w-full flex items-center gap-3 px-4 py-2.5 mb-3 rounded-xl text-left"
          style={{ background: C.orange + '14', border: `1px solid ${C.orange}33` }}
        >
          <LockOpen size={15} style={{ color: C.orange }} className="flex-shrink-0" />
          <span className="flex-1 text-sm font-bold" style={{ color: C.orange }}>
            {pendingCount} unlock request{pendingCount > 1 ? 's' : ''} pending approval
          </span>
          <div
            className="px-2.5 py-1 rounded-lg text-[11px] font-extrabold text-white flex-shrink-0"
            style={{ background: C.orange }}
          >
            Review →
          </div>
        </button>
      )}

      <div className="mb-4">
        <SearchBar value={q} onChange={setQ} placeholder="Search by name or district…" />
      </div>

      <div className="space-y-3">
        {loading
          ? Array.from({ length: 4 }).map((_, i) => <Shimmer key={i} className="h-32 rounded-2xl" />)
          : filtered.length === 0
            ? <div className="card"><Empty message="No admins found" icon={Shield} /></div>
            : filtered.map(a => {
              // Pending unlock requests for this admin
              const adminPending = unlockRequests.filter(
                r => r.status === 'pending' && r.adminName === a.name
              );

              return (
                <div
                  key={a.id}
                  className="rounded-2xl overflow-hidden"
                  style={{
                    border: `1px solid ${adminPending.length > 0 ? C.orange + '80' : C.border + '80'}`,
                    boxShadow: adminPending.length > 0
                      ? `${C.orange}14 0px 4px 10px`
                      : `${C.primary}0F 0px 4px 10px`,
                  }}
                >
                  {/* Card header */}
                  <div
                    className="flex items-center gap-3 px-4 py-2.5"
                    style={{
                      background: adminPending.length > 0 ? C.orange + '0F' : C.surface,
                      borderBottom: `1px solid ${C.border}40`,
                    }}
                  >
                    <span
                      className="text-[10px] font-black tracking-wide px-2 py-1 rounded-md flex-shrink-0"
                      style={{ background: C.primary, color: 'white' }}
                    >
                      ADM{String(a.id).padStart(3, '0')}
                    </span>
                    <p className="font-bold text-sm flex-1 truncate" style={{ color: C.dark }}>{a.name}</p>

                    {/* Admin-level pending badge */}
                    {adminPending.length > 0 && (
                      <button
                        onClick={onGoToUnlocks}
                        className="flex items-center gap-1 px-2 py-1 rounded-lg text-[10px] font-extrabold text-white mr-1 flex-shrink-0"
                        style={{ background: C.orange }}
                      >
                        <LockOpen size={10} />
                        {adminPending.length} Unlock
                      </button>
                    )}

                    <div className="flex gap-1 flex-shrink-0">
                      <button
                        className="p-1.5 rounded hover:bg-white transition-colors"
                        style={{ color: C.primary }}
                        onClick={() => { setSelected(a); setModal('form'); }}
                        title="Edit"
                      >
                        <Pencil size={13} />
                      </button>
                      <button
                        className="p-1.5 rounded hover:bg-red-50 transition-colors"
                        style={{ color: C.error }}
                        onClick={() => setDeleteId(a.id)}
                        title="Delete"
                      >
                        <Trash2 size={13} />
                      </button>
                    </div>
                  </div>

                  {/* Card body */}
                  <div className="px-4 py-3 space-y-1.5" style={{ background: 'white' }}>
                    <div className="flex items-center gap-1.5 text-xs" style={{ color: C.subtle }}>
                      <Building2 size={12} />
                      <span>{a.district || 'No district'}</span>
                    </div>
                    {a.createdAt && (
                      <div className="flex items-center gap-1.5 text-xs" style={{ color: C.subtle }}>
                        <Calendar size={12} />
                        <span>Created {fmtDate(a.createdAt)}</span>
                      </div>
                    )}
                    <div className="flex flex-wrap gap-1.5 pt-1">
                      <Pill color={a.isActive ? C.success : C.error}>
                        {a.isActive
                          ? <CheckCircle size={9} className="inline mr-0.5" />
                          : <XCircle size={9} className="inline mr-0.5" />}
                        {a.isActive ? 'Active' : 'Inactive'}
                      </Pill>
                      {(a.totalBooths ?? 0) > 0 && <Pill color={C.info}>{a.totalBooths} Booths</Pill>}
                      {(a.assignedStaff ?? 0) > 0 && <Pill color={C.accent}>{a.assignedStaff} Staff</Pill>}
                    </div>
                  </div>

                  {/* ── Inline pending unlock requests (Flutter: inline block in _adminCard) ── */}
                  {adminPending.length > 0 && (
                    <div
                      className="px-4 pb-4 pt-3"
                      style={{
                        background: 'white',
                        borderTop: `1px solid ${C.orange}33`,
                      }}
                    >
                      <div className="flex items-center gap-1.5 mb-2">
                        <LockOpen size={12} style={{ color: C.orange }} />
                        <span className="text-xs font-bold" style={{ color: C.orange }}>
                          Pending Unlock Requests
                        </span>
                      </div>
                      {adminPending.map(req => (
                        <InlineUnlockCard
                          key={req.id}
                          req={req}
                          onAction={onUnlockAction}
                          onDetail={setDetailReq}
                        />
                      ))}
                    </div>
                  )}
                </div>
              );
            })
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
      {detailReq && (
        <UnlockDetailModal
          req={detailReq}
          onAction={onUnlockAction}
          onClose={() => setDetailReq(null)}
        />
      )}
    </div>
  );
}

// ─────────────────────────────────────────────
//  TAB 2 — UNLOCK REQUESTS  ← ENTIRELY NEW
// ─────────────────────────────────────────────
function UnlocksTab({ unlockRequests, loading, onRefresh, onAction }) {
  const [detailReq, setDetailReq] = useState(null);

  const pending = unlockRequests.filter(r => r.status === 'pending');
  const resolved = unlockRequests.filter(r => r.status !== 'pending');
  const approved = resolved.filter(r => r.status === 'approved').length;
  const rejected = resolved.filter(r => r.status === 'rejected').length;

  if (loading) {
    return (
      <div className="p-4 space-y-3">
        {[1, 2, 3].map(i => <Shimmer key={i} className="h-40 rounded-2xl" />)}
      </div>
    );
  }

  return (
    <div className="relative">
      {/* Summary bar */}
      <div
        className="flex items-center gap-2 px-4 py-3 sticky top-[105px] z-10"
        style={{ background: C.surface, borderBottom: `1px solid ${C.border}40` }}
      >
        <SummaryPill count={pending.length} label="Pending" color={C.orange} />
        <SummaryPill count={approved} label="Approved" color={C.success} />
        <SummaryPill count={rejected} label="Rejected" color={C.error} />
        <button
          className="ml-auto text-xs font-bold px-2.5 py-1.5 rounded-lg border transition-colors hover:bg-white"
          style={{ color: C.primary, borderColor: C.border }}
          onClick={onRefresh}
        >
          Refresh
        </button>
      </div>

      <div className="p-4">
        {unlockRequests.length === 0 ? (
          <div
            className="flex flex-col items-center justify-center py-20 rounded-2xl"
            style={{ background: 'white', border: `1px solid ${C.border}40` }}
          >
            <LockOpen size={52} style={{ color: C.orange + '66' }} />
            <p className="font-bold mt-4 text-sm" style={{ color: C.subtle }}>
              कोई Unlock Request नहीं
            </p>
            <p className="text-xs mt-1.5 text-center max-w-xs" style={{ color: C.subtle }}>
              All zones are currently locked or unlocked normally.
            </p>
          </div>
        ) : (
          <>
            {/* Pending section */}
            {pending.length > 0 && (
              <>
                <div className="flex items-center gap-2 mb-3">
                  <div className="w-1 h-4 rounded-full" style={{ background: C.orange }} />
                  <h3 className="font-extrabold text-sm" style={{ color: C.orange }}>
                    Pending Approval ({pending.length})
                  </h3>
                </div>
                {pending.map(req => (
                  <UnlockRequestCard
                    key={req.id}
                    req={req}
                    onAction={onAction}
                    onDetail={setDetailReq}
                  />
                ))}
              </>
            )}

            {/* Resolved section */}
            {resolved.length > 0 && (
              <>
                <div className="flex items-center gap-2 mb-3 mt-4">
                  <div className="w-1 h-4 rounded-full" style={{ background: C.subtle }} />
                  <h3 className="font-extrabold text-sm" style={{ color: C.subtle }}>
                    Resolved ({resolved.length})
                  </h3>
                </div>
                {resolved.map(req => (
                  <UnlockRequestCard
                    key={req.id}
                    req={req}
                    onAction={onAction}
                    onDetail={setDetailReq}
                  />
                ))}
              </>
            )}
          </>
        )}
      </div>

      {detailReq && (
        <UnlockDetailModal
          req={detailReq}
          onAction={onAction}
          onClose={() => setDetailReq(null)}
        />
      )}
    </div>
  );
}

// ─────────────────────────────────────────────
//  TAB 3 — FORM DATA
// ─────────────────────────────────────────────
function FormDataTab() {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [detail, setDetail] = useState(null);

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
      <div className="flex items-center gap-2 mb-4">
        <div className="w-1 h-[18px] rounded-full" style={{ background: C.primary }} />
        <h3 className="font-extrabold text-sm" style={{ color: C.dark }}>District Form Data</h3>
        <span className="text-xs ml-1" style={{ color: C.subtle }}>Admin-wise structure entries</span>
      </div>

      {loading
        ? Array.from({ length: 4 }).map((_, i) => <Shimmer key={i} className="h-36 rounded-2xl mb-3" />)
        : data.length === 0
          ? <div className="card"><Empty message="No form data submitted yet" /></div>
          : data.map((d, i) => (
            <div
              key={d.adminId || i}
              className="rounded-2xl overflow-hidden mb-3 fade-in"
              style={{
                border: `1px solid ${C.border}66`,
                boxShadow: `${C.primary}0F 0px 4px 10px`,
              }}
            >
              {/* Header */}
              <div
                className="flex items-center gap-3 px-4 py-3"
                style={{ background: C.dark }}
              >
                <MapPin size={14} style={{ color: C.border, flexShrink: 0 }} />
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
                <div className="flex items-center gap-1.5 text-xs mb-3" style={{ color: C.subtle }}>
                  <UserCog size={13} />
                  <span>Admin: <strong style={{ color: C.dark }}>{d.adminName || '—'}</strong></span>
                </div>

                {/* Stat chips */}
                <div className="flex flex-wrap gap-2 mb-3">
                  {[
                    { label: 'Super Zones', val: d.superZones, color: C.primary },
                    { label: 'Zones', val: d.zones, color: C.accent },
                    { label: 'Sectors', val: d.sectors, color: C.info },
                    { label: 'Gram Panchayats', val: d.gramPanchayats, color: C.success },
                    { label: 'Centers', val: d.centers, color: C.purple },
                  ].map(({ label, val, color }) => (
                    <div
                      key={label}
                      className="px-2.5 py-1.5 rounded-lg"
                      style={{ background: C.surface, border: `1px solid ${C.border}66` }}
                    >
                      <span className="font-black text-sm" style={{ color }}>{val ?? 0} </span>
                      <span className="text-[10px] font-semibold" style={{ color: C.subtle }}>{label}</span>
                    </div>
                  ))}
                </div>

                {/* View Full Details */}
                <button
                  onClick={() => setDetail(d)}
                  className="w-full py-2 rounded-xl text-xs font-bold flex items-center justify-center gap-2 border transition-colors hover:bg-surface"
                  style={{ color: C.primary, borderColor: C.border }}
                >
                  <ExternalLink size={12} />
                  View Full Details
                </button>
              </div>
            </div>
          ))
      }

      {detail && <FormDetailModal entry={detail} onClose={() => setDetail(null)} />}
    </div>
  );
}

