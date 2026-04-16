import { useState, useEffect } from 'react';
import {
  MapPin, Users, FileText, Key, Navigation, Shield, ShieldOff,
  User, Phone, Building2, Calendar, CheckCircle, AlertCircle, RefreshCw, Eye, EyeOff, Save
} from 'lucide-react';
import AppShell from '../../components/layout/AppShell';
import { staffApi } from '../../api/endpoints';
import { Empty, Shimmer } from '../../components/common';
import { rankHindi, safeVal } from '../../utils/helpers';
import toast from 'react-hot-toast';

const SENS_CONFIG = {
  'a++': { label: 'अति-अति संवेदनशील', color: '#6C3483', bg: '#f3e5f5' },
  a:     { label: 'अति संवेदनशील', color: '#C0392B', bg: '#fdecea' },
  b:     { label: 'संवेदनशील', color: '#E67E22', bg: '#fef3e2' },
  c:     { label: 'सामान्य', color: '#1A5276', bg: '#e3f0fb' },
};

function InfoRow({ label, value, icon: Icon }) {
  return (
    <div className="flex items-start gap-2.5 py-2 border-b" style={{ borderColor: 'rgba(212,168,67,0.15)' }}>
      {Icon && <Icon size={14} className="shrink-0 mt-0.5 text-subtle" />}
      <div className="flex-1 min-w-0">
        <p className="text-[10px] font-bold text-subtle uppercase tracking-wide">{label}</p>
        <p className="text-sm font-semibold text-dark mt-0.5">{value || '—'}</p>
      </div>
    </div>
  );
}

// ── Dashboard Tab ──────────────────────────────────────────────────────────────
function DashboardTab({ user, duty, loading, noDuty }) {
  if (loading) return (
    <div className="p-4 space-y-3">
      {[1,2,3,4].map(i=><Shimmer key={i} className="h-16 rounded-xl"/>)}
    </div>
  );

  return (
    <div className="p-4 max-w-2xl mx-auto">
      {/* Greeting Card */}
      <div className="rounded-xl p-4 mb-4 relative overflow-hidden"
        style={{ background: 'var(--dark)' }}>
        <div className="absolute top-0 right-0 w-24 h-24 rounded-full opacity-10"
          style={{ background: 'var(--border)', transform: 'translate(30%, -30%)' }} />
        <p className="text-xs font-semibold mb-0.5" style={{ color: 'var(--border)' }}>नमस्ते / Welcome,</p>
        <h2 className="font-black text-white text-lg leading-tight">{user?.name || '—'}</h2>
        <div className="flex items-center gap-2 mt-2">
          <span className="badge text-[10px]" style={{ background: 'rgba(212,168,67,0.2)', color: 'var(--border)' }}>
            {rankHindi(user?.user_rank || user?.rank)} · {user?.pno || ''}
          </span>
          {(user?.is_armed || user?.isArmed)
            ? <span className="badge text-[10px]" style={{ background: '#fdecea', color: '#C0392B' }}><Shield size={9} className="mr-0.5"/>Armed</span>
            : <span className="badge text-[10px]" style={{ background: '#e6f4ea', color: '#2D6A1E' }}><ShieldOff size={9} className="mr-0.5"/>Unarmed</span>
          }
        </div>
      </div>

      {/* Duty Status */}
      {noDuty ? (
        <div className="card p-6 text-center">
          <AlertCircle size={36} className="mx-auto mb-3 text-subtle opacity-50" />
          <p className="font-bold text-dark mb-1">No Duty Assigned</p>
          <p className="text-sm text-subtle">ड्यूटी अभी तक आवंटित नहीं हुई है।</p>
        </div>
      ) : (
        <div className="card p-4">
          <div className="flex items-center gap-2 mb-3">
            <CheckCircle size={16} className="text-success" />
            <p className="font-bold text-dark text-sm">ड्यूटी आवंटित (Duty Assigned)</p>
          </div>
          {/* Sensitivity */}
          {duty?.centerType && (() => {
            const cfg = SENS_CONFIG[(duty.centerType || '').toLowerCase()] || {};
            return (
              <div className="rounded-lg px-3 py-2 mb-3 inline-flex items-center gap-2"
                style={{ background: cfg.bg, border: `1px solid ${cfg.color}30` }}>
                <div className="w-2 h-2 rounded-full" style={{ background: cfg.color }} />
                <span className="text-xs font-bold" style={{ color: cfg.color }}>{cfg.label}</span>
              </div>
            );
          })()}
          <InfoRow label="Booth / Center" value={duty?.centerName} icon={Building2} />
          <InfoRow label="Address" value={duty?.centerAddress} icon={MapPin} />
          <InfoRow label="Super Zone" value={duty?.superZoneName} icon={Building2} />
          <InfoRow label="Zone" value={duty?.zoneName} />
          <InfoRow label="Sector" value={duty?.sectorName} />
          <InfoRow label="Bus Number" value={duty?.busNo} />

          {/* Map link */}
          {duty?.latitude && duty?.longitude && (
            <a href={`https://www.google.com/maps?q=${duty.latitude},${duty.longitude}`}
              target="_blank" rel="noopener noreferrer"
              className="mt-3 flex items-center gap-2 text-sm font-semibold"
              style={{ color: 'var(--info)' }}>
              <Navigation size={14} /> Google Maps पर देखें
            </a>
          )}
        </div>
      )}
    </div>
  );
}

// ── Co-Staff Tab ───────────────────────────────────────────────────────────────
function CoStaffTab({ duty, loading }) {
  if (loading) return <div className="p-4"><Shimmer className="h-64 rounded-xl" /></div>;
  const staff = duty?.allStaff || duty?.all_staff || [];
  return (
    <div className="p-4 max-w-2xl mx-auto">
      <h2 className="font-bold text-dark mb-4">सहयोगी कर्मचारी (Co-Staff)</h2>
      {staff.length === 0
        ? <div className="card"><Empty message="No co-staff assigned" icon={Users} /></div>
        : <div className="space-y-2">
          {staff.map((s, i) => (
            <div key={i} className="card p-3.5 fade-in flex items-center gap-3">
              <div className="w-9 h-9 rounded-full flex items-center justify-center font-bold text-sm shrink-0"
                style={{ background: 'var(--dark)', color: 'var(--border)' }}>
                {(s.name||'?')[0]}
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-bold text-dark text-sm truncate">{s.name || '—'}</p>
                <p className="text-xs text-subtle">{s.pno || ''} · {rankHindi(s.rank || s.user_rank)}</p>
                {s.mobile && <p className="text-[11px] text-subtle font-mono">{s.mobile}</p>}
              </div>
              {(s.isArmed || s.is_armed)
                ? <Shield size={14} style={{ color: '#C0392B' }} />
                : <ShieldOff size={14} style={{ color: '#27AE60' }} />
              }
            </div>
          ))}
        </div>
      }
    </div>
  );
}

// ── Duty Card Tab ──────────────────────────────────────────────────────────────
function DutyCardTab({ duty, user, loading }) {
  if (loading) return <div className="p-4"><Shimmer className="h-96 rounded-xl" /></div>;
  if (!duty) return <div className="p-4 card"><Empty message="No duty assigned" /></div>;

  return (
    <div className="p-4 max-w-2xl mx-auto">
      <div className="card overflow-hidden">
        {/* Header */}
        <div className="p-4 text-center" style={{ background: 'var(--dark)' }}>
          <p className="text-xs font-black tracking-widest" style={{ color: 'var(--border)' }}>ELECTION DUTY CARD</p>
          <p className="text-[10px] mt-0.5" style={{ color: 'rgba(212,168,67,0.6)' }}>उत्तर प्रदेश निर्वाचन कक्ष</p>
        </div>

        <div className="p-4 space-y-2">
          {/* Officer info */}
          <div className="rounded-xl p-3" style={{ background: 'var(--surface)', border: '1px solid rgba(212,168,67,0.3)' }}>
            <div className="grid grid-cols-2 gap-2 text-sm">
              {[
                ['नाम / Name', user?.name],
                ['PNO / बैज', user?.pno],
                ['पद / Rank', rankHindi(user?.user_rank || user?.rank)],
                ['मोबाइल / Mobile', user?.mobile],
                ['थाना / Thana', user?.thana],
                ['जिला / District', user?.district],
              ].map(([k,v]) => (
                <div key={k}>
                  <p className="text-[9px] font-bold text-subtle uppercase">{k}</p>
                  <p className="font-semibold text-dark text-xs mt-0.5">{v || '—'}</p>
                </div>
              ))}
            </div>
          </div>

          {/* Duty info */}
          <div className="rounded-xl p-3" style={{ background: '#fffbe6', border: '1px solid rgba(212,168,67,0.4)' }}>
            <p className="text-[10px] font-black text-primary uppercase tracking-wide mb-2">Booth Details</p>
            <div className="grid grid-cols-2 gap-2 text-xs">
              {[
                ['Center', duty?.centerName],
                ['Address', duty?.centerAddress],
                ['Super Zone', duty?.superZoneName],
                ['Zone', duty?.zoneName],
                ['Sector', duty?.sectorName],
                ['Bus No', duty?.busNo],
              ].map(([k,v]) => (
                <div key={k}>
                  <p className="text-[9px] font-bold text-subtle uppercase">{k}</p>
                  <p className="font-semibold text-dark mt-0.5">{v || '—'}</p>
                </div>
              ))}
            </div>
          </div>

          <p className="text-center text-[10px] text-subtle pt-1">
            Secure Document — UP Police Election Cell © 2026
          </p>
        </div>
      </div>
    </div>
  );
}

// ── Password Tab ───────────────────────────────────────────────────────────────
function PasswordTab() {
  const [form, setForm] = useState({ currentPassword: '', newPassword: '', confirmPassword: '' });
  const [showFields, setShowFields] = useState({ cur: false, new: false, conf: false });
  const [saving, setSaving] = useState(false);
  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));
  const toggle = (k) => setShowFields(p => ({ ...p, [k]: !p[k] }));

  const handleSave = async () => {
    if (!form.currentPassword || !form.newPassword) { toast.error('All fields required'); return; }
    if (form.newPassword !== form.confirmPassword) { toast.error('Passwords do not match'); return; }
    if (form.newPassword.length < 6) { toast.error('Password must be at least 6 characters'); return; }
    setSaving(true);
    try {
      await staffApi.changePassword(form);
      toast.success('Password changed successfully');
      setForm({ currentPassword: '', newPassword: '', confirmPassword: '' });
    } catch (e) { toast.error(e.message || 'Failed to change password'); }
    finally { setSaving(false); }
  };

  return (
    <div className="p-4 max-w-md mx-auto">
      <h2 className="font-bold text-dark mb-4">Change Password</h2>
      <div className="card p-5 space-y-4">
        {[
          ['currentPassword', 'Current Password', 'cur'],
          ['newPassword', 'New Password', 'new'],
          ['confirmPassword', 'Confirm New Password', 'conf'],
        ].map(([k, label, showKey]) => (
          <div key={k}>
            <label className="text-xs font-semibold text-subtle mb-1 block">{label}</label>
            <div className="relative">
              <input className="field pr-10" type={showFields[showKey] ? 'text' : 'password'}
                value={form[k]} onChange={e => set(k, e.target.value)} placeholder="••••••••" />
              <button type="button" className="absolute right-3 top-1/2 -translate-y-1/2"
                onClick={() => toggle(showKey)}>
                {showFields[showKey] ? <EyeOff size={14} className="text-subtle"/> : <Eye size={14} className="text-subtle"/>}
              </button>
            </div>
          </div>
        ))}
        <button className="btn-primary w-full h-11" onClick={handleSave} disabled={saving}>
          {saving ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"/> : <><Save size={15}/> Change Password</>}
        </button>
      </div>
    </div>
  );
}

// ── Main Wrapper ───────────────────────────────────────────────────────────────
export default function StaffDashboard() {
  const [page, setPage] = useState('dashboard');
  const [user, setUser] = useState(null);
  const [duty, setDuty] = useState(null);
  const [loading, setLoading] = useState(true);
  const [noDuty, setNoDuty] = useState(false);

  const loadData = async () => {
    setLoading(true);
    try {
      const [profileRes, dutyRes] = await Promise.all([
        staffApi.profile(), staffApi.myDuty()
      ]);
      setUser(profileRes.data || profileRes);
      const d = dutyRes.data || dutyRes;
      const dutyData = typeof d === 'object' && !Array.isArray(d) ? d : null;
      setDuty(dutyData);
      setNoDuty(!dutyData || (!dutyData.centerName && !dutyData.center_name));
    } catch (e) {
      toast.error('Failed to load profile');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { loadData(); }, []);

  const normalizedDuty = duty ? {
    ...duty,
    centerName:    duty.centerName    || duty.center_name,
    centerAddress: duty.centerAddress || duty.center_address,
    centerType:    duty.centerType    || duty.center_type,
    superZoneName: duty.superZoneName || duty.super_zone_name,
    zoneName:      duty.zoneName      || duty.zone_name,
    sectorName:    duty.sectorName    || duty.sector_name,
    busNo:         duty.busNo         || duty.bus_no,
    allStaff:      duty.allStaff      || duty.all_staff || [],
    latitude:      duty.latitude,
    longitude:     duty.longitude,
  } : null;

  const tabProps = { user, duty: normalizedDuty, loading, noDuty };

  const PAGES = {
    dashboard: () => <DashboardTab {...tabProps} />,
    duty:      () => <DashboardTab {...tabProps} />,
    costaff:   () => <CoStaffTab {...tabProps} />,
    dutycard:  () => <DutyCardTab {...tabProps} />,
    password:  () => <PasswordTab />,
  };

  const Page = PAGES[page] || PAGES.dashboard;

  return (
    <AppShell activePage={page} onNavigate={setPage}>
      <Page />
    </AppShell>
  );
}
