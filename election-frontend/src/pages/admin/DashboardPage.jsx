import { useState, useEffect, useCallback } from 'react';
import { Layers, MapPin, Users, Vote, ChevronRight, Plus, Minus, Save } from 'lucide-react';
import { adminApi } from '../../api/endpoints';
import { StatCard, Shimmer, Modal, SensChip } from '../../components/common';
import { SENSITIVITY_CONFIG, RANKS } from '../../utils/helpers';
import toast from 'react-hot-toast';

const SENSITIVITIES = ['A++', 'A', 'B', 'C'];
const RANK_ROWS = [
  { en: 'ASP', hi: 'अपर पुलिस अधीक्षक', armed: false },
  { en: 'DSP', hi: 'पुलिस उपाधीक्षक', armed: false },
  { en: 'Inspector', hi: 'निरीक्षक', armed: false },
  { en: 'Inspector_Arms', hi: 'निरीक्षक (आर्म्स)', armed: true },
  { en: 'SI', hi: 'उप निरीक्षक', armed: false },
  { en: 'SI_Arms', hi: 'उप निरीक्षक (आर्म्स)', armed: true },
  { en: 'Head Constable', hi: 'मुख्य आरक्षी', armed: false },
  { en: 'HC_Arms', hi: 'मुख्य आरक्षी (आर्म्स)', armed: true },
  { en: 'Constable', hi: 'आरक्षी', armed: false },
  { en: 'Constable_Arms', hi: 'आरक्षी (आर्म्स)', armed: true },
];

// ── Manak (Rules) Modal ───────────────────────────────────────────────────────
function ManakModal({ sensitivity, initialRules, onSave, onClose }) {
  const cfg = SENSITIVITY_CONFIG[sensitivity] || {};
  const [rules, setRules] = useState({ ...initialRules });
  const [saving, setSaving] = useState(false);

  const update = (key, delta) => {
    setRules(prev => ({
      ...prev,
      [key]: Math.max(0, (prev[key] || 0) + delta),
    }));
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await onSave(sensitivity, rules);
      onClose();
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal open onClose={onClose}
      title={`${sensitivity} — ${cfg.label || ''} मानक निर्धारण`}
      maxWidth="max-w-xl">
      <p className="text-xs text-subtle mb-4">Set required police personnel count per booth sensitivity level</p>
      <div className="space-y-2 max-h-80 overflow-y-auto pr-1">
        {RANK_ROWS.map((r) => (
          <div key={r.en} className="flex items-center justify-between py-2 px-3 rounded-lg"
            style={{ background: 'var(--surface)', border: '1px solid rgba(212,168,67,0.25)' }}>
            <div>
              <p className="text-xs font-semibold text-dark">{r.hi}</p>
              <p className="text-[10px] text-subtle">{r.en} {r.armed && '· Armed'}</p>
            </div>
            <div className="flex items-center gap-2">
              <button onClick={() => update(r.en, -1)}
                className="w-7 h-7 rounded-lg flex items-center justify-center border text-primary hover:bg-primary hover:text-white transition-colors"
                style={{ borderColor: 'var(--border)' }}>
                <Minus size={13} />
              </button>
              <span className="w-8 text-center font-bold text-dark text-sm">
                {rules[r.en] || 0}
              </span>
              <button onClick={() => update(r.en, 1)}
                className="w-7 h-7 rounded-lg flex items-center justify-center border text-primary hover:bg-primary hover:text-white transition-colors"
                style={{ borderColor: 'var(--border)' }}>
                <Plus size={13} />
              </button>
            </div>
          </div>
        ))}
      </div>
      <div className="flex gap-3 justify-end mt-5">
        <button className="btn-outline px-4 py-2" onClick={onClose}>Cancel</button>
        <button className="btn-primary px-5 py-2" onClick={handleSave} disabled={saving}>
          {saving ? <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" /> : <><Save size={15}/> Save</>}
        </button>
      </div>
    </Modal>
  );
}

// ── Main Dashboard ────────────────────────────────────────────────────────────
export default function AdminDashboardPage() {
  const [stats, setStats] = useState(null);
  const [loadingStats, setLoadingStats] = useState(true);
  const [rules, setRules] = useState({ 'A++': {}, A: {}, B: {}, C: {} });
  const [loadingRules, setLoadingRules] = useState(true);
  const [modalSens, setModalSens] = useState(null);

  const loadStats = useCallback(async () => {
    setLoadingStats(true);
    try {
      const res = await adminApi.overview();
      setStats(res.data || res);
    } catch (e) { toast.error('Failed to load stats'); }
    finally { setLoadingStats(false); }
  }, []);

  const loadAllRules = useCallback(async () => {
    setLoadingRules(true);
    try {
      await Promise.all(SENSITIVITIES.map(async (s) => {
        try {
          const res = await adminApi.getRules(s);
          const list = Array.isArray(res.data) ? res.data : [];
          const map = {};
          list.forEach(r => {
            const key = (r.isArmed || r.is_armed) ? `${r.rank}_Arms` : r.rank;
            map[key] = r.count || r.required_count || 0;
          });
          setRules(prev => ({ ...prev, [s]: map }));
        } catch (_) {}
      }));
    } finally { setLoadingRules(false); }
  }, []);

  useEffect(() => {
    loadStats();
    loadAllRules();
  }, []);

  const handleSaveRules = async (sensitivity, rankMap) => {
    const rulesArr = Object.entries(rankMap)
      .filter(([, v]) => v > 0)
      .map(([key, count]) => {
        const isArmed = key.endsWith('_Arms');
        const rank = isArmed ? key.slice(0, -5) : key;
        return { rank, count, isArmed };
      });
    await adminApi.saveRules(sensitivity, rulesArr);
    await loadAllRules();
    toast.success(`${sensitivity} rules saved ✓`);
  };

  const statItems = stats ? [
    { label: 'Super Zones', value: stats.superZones ?? 0, icon: Layers, color: '#8B6914' },
    { label: 'Total Booths', value: stats.totalBooths ?? 0, icon: MapPin, color: '#2D6A1E' },
    { label: 'Total Staff', value: stats.totalStaff ?? 0, icon: Users, color: '#B8860B' },
    { label: 'Assigned', value: stats.assignedDuties ?? 0, icon: Vote, color: '#1A5276' },
  ] : [];

  return (
    <div className="p-4 max-w-5xl mx-auto">
      {/* Stats Grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        {loadingStats
          ? [1,2,3,4].map(i => <Shimmer key={i} className="h-24" />)
          : statItems.map(s => (
            <StatCard key={s.label} label={s.label} value={s.value}
              icon={s.icon} color={s.color} />
          ))
        }
      </div>

      {/* Hierarchy Banner */}
      <div className="card p-4 mb-4 cursor-pointer hover:shadow-lg transition-shadow"
        style={{ background: 'linear-gradient(135deg, var(--dark) 0%, #3a2400 100%)' }}>
        <div className="flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold mb-0.5" style={{ color: 'var(--border)' }}>
              HIERARCHY STRUCTURE REPORT
            </p>
            <p className="text-white/70 text-xs">View complete zone → sector → booth hierarchy</p>
          </div>
          <ChevronRight size={20} style={{ color: 'var(--border)' }} />
        </div>
      </div>

      {/* मानक Section */}
      <div className="card p-4">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="font-bold text-dark">मानक निर्धारण (Booth Rules)</h2>
            <p className="text-xs text-subtle mt-0.5">Personnel requirements per sensitivity level</p>
          </div>
          {loadingRules && (
            <div className="w-4 h-4 border-2 border-primary/30 border-t-primary rounded-full animate-spin" />
          )}
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {SENSITIVITIES.map(s => {
            const cfg = SENSITIVITY_CONFIG[s];
            const ruleMap = rules[s] || {};
            const total = Object.values(ruleMap).reduce((a, b) => a + b, 0);
            const entryCount = Object.values(ruleMap).filter(v => v > 0).length;
            return (
              <button key={s}
                onClick={() => setModalSens(s)}
                className="rounded-xl p-3 text-left border transition-all hover:shadow-md hover:-translate-y-0.5"
                style={{ background: cfg?.bg, borderColor: `${cfg?.color}40` }}>
                <div className="flex items-center justify-between mb-2">
                  <SensChip sens={s} />
                  <ChevronRight size={14} style={{ color: cfg?.color }} />
                </div>
                <p className="text-xs font-bold mt-1.5 leading-tight" style={{ color: cfg?.color }}>
                  {cfg?.label}
                </p>
                {loadingRules ? (
                  <Shimmer className="h-3 mt-2 rounded" />
                ) : (
                  <p className="text-[10px] mt-1.5" style={{ color: cfg?.color + '99' }}>
                    {entryCount > 0 ? `${entryCount} ranks · ${total} total` : 'Not configured'}
                  </p>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Manak Modal */}
      {modalSens && (
        <ManakModal
          sensitivity={modalSens}
          initialRules={rules[modalSens] || {}}
          onSave={handleSaveRules}
          onClose={() => setModalSens(null)}
        />
      )}
    </div>
  );
}
