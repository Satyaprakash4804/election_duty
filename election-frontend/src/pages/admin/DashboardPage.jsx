import { useState, useEffect, useCallback } from 'react';
import {
  Layers, MapPin, Users, Vote, ChevronRight,
  CheckCircle, PlusCircle, Shield, FileText,
  TableProperties, AlertCircle
} from 'lucide-react';
import { adminApi } from '../../api/endpoints';
import { StatCard, Shimmer } from '../../components/common';
import { SENSITIVITY_CONFIG } from '../../utils/helpers';
import toast from 'react-hot-toast';
import MapViewButton from '../../components/common/Mapviewbutton';
import { useNavigate } from 'react-router-dom';

// ─────────────────────────────────────────────
//  PALETTE (mirrors Flutter kXxx)
// ─────────────────────────────────────────────
const C = {
  bg:      '#FDF6E3',
  surface: '#F5E6C8',
  primary: '#8B6914',
  accent:  '#B8860B',
  dark:    '#4A3000',
  subtle:  '#AA8844',
  border:  '#D4A843',
  error:   '#C0392B',
  success: '#2D6A1E',
  info:    '#1A5276',
};

// ─────────────────────────────────────────────
//  SENSITIVITY CONFIG (matches Flutter _kSensitivities)
// ─────────────────────────────────────────────
const SENS_CONFIG = [
  { key: 'A++', hi: 'अति-अति संवेदनशील', color: '#6C3483' },
  { key: 'A',   hi: 'अति संवेदनशील',      color: '#C0392B' },
  { key: 'B',   hi: 'संवेदनशील',           color: '#E67E22' },
  { key: 'C',   hi: 'सामान्य',             color: '#1A5276' },
];

// Staff fields that count for "has data" check
// Mirrors Flutter's _hasAny / _rowTotalStaff
const STAFF_FIELDS = [
  'siArmedCount', 'siUnarmedCount',
  'hcArmedCount', 'hcUnarmedCount',
  'constArmedCount', 'constUnarmedCount',
  'auxForceCount', 'pacCount',
];

function rowHasAny(row) {
  return STAFF_FIELDS.some(f => ((row[f] ?? 0)) > 0);
}

function rowTotalStaff(row) {
  // pacCount excluded from total in Flutter's _rowTotalStaff
  return ['siArmedCount','siUnarmedCount','hcArmedCount','hcUnarmedCount',
          'constArmedCount','constUnarmedCount','auxForceCount']
    .reduce((sum, f) => sum + ((row[f] ?? 0)), 0);
}

function districtRowHasAny(row) {
  return ['sankhya', ...STAFF_FIELDS]
    .some(f => ((row[f] ?? 0)) > 0);
}

// ─────────────────────────────────────────────
//  GRADIENT BANNER  (Flutter: _gradientNav)
// ─────────────────────────────────────────────
function GradientBanner({ label, subtitle, icon: Icon, colors, onClick, badge }) {
  const [from, to] = colors;
  return (
    <button
      onClick={onClick}
      className="w-full rounded-2xl overflow-hidden text-left transition-all hover:shadow-xl hover:-translate-y-0.5 active:translate-y-0"
      style={{
        background: `linear-gradient(135deg, ${from} 0%, ${to} 100%)`,
        boxShadow: `${from}4D 0px 5px 14px`,
      }}
    >
      <div className="flex items-center gap-4 px-4 py-3.5">
        {/* Icon box */}
        <div
          className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
          style={{ background: 'rgba(255,255,255,0.15)' }}
        >
          <Icon size={20} color="white" />
        </div>
        {/* Text */}
        <div className="flex-1 min-w-0">
          <p className="font-extrabold text-white text-sm leading-tight">{label}</p>
          <p className="text-white/60 text-[11px] mt-0.5">{subtitle}</p>
        </div>
        {/* Optional badge */}
        {badge && (
          <div
            className="flex items-center gap-1 px-2 py-1 rounded-full mr-1 flex-shrink-0"
            style={{ background: 'rgba(255,255,255,0.18)' }}
          >
            <CheckCircle size={11} color="white" />
            <span className="text-white text-[10px] font-extrabold">{badge}</span>
          </div>
        )}
        <ChevronRight size={22} color="rgba(255,255,255,0.54)" className="flex-shrink-0" />
      </div>
    </button>
  );
}

// ─────────────────────────────────────────────
//  STATUS BADGE  (Flutter: _StatusBadge)
// ─────────────────────────────────────────────
function StatusBadge({ allSet }) {
  return (
    <div
      className="flex items-center gap-1.5 px-2.5 py-1 rounded-full border flex-shrink-0"
      style={{
        background: allSet ? `${C.success}1A` : `${C.error}14`,
        borderColor: allSet ? `${C.success}4D` : `${C.error}33`,
      }}
    >
      {allSet
        ? <CheckCircle  size={11} style={{ color: C.success }} />
        : <AlertCircle  size={11} style={{ color: C.error   }} />
      }
      <span
        className="text-[10px] font-bold"
        style={{ color: allSet ? C.success : C.error }}
      >
        {allSet ? 'सभी सेट' : 'अधूरे'}
      </span>
    </div>
  );
}

// ─────────────────────────────────────────────
//  SENSITIVITY TILE  (Flutter: _SensTile)
// ─────────────────────────────────────────────
function SensTile({ sensKey, hindi, color, isSet, totalStaff, filledRowCount, onClick }) {
  return (
    <button
      onClick={onClick}
      className="rounded-xl p-3 text-left transition-all hover:shadow-md hover:-translate-y-0.5 active:translate-y-0"
      style={{
        background: isSet ? `${color}12` : `${C.error}08`,
        border: `1px solid ${isSet ? color + '4D' : C.error + '33'}`,
      }}
    >
      {/* Top row: badge + check/edit icon */}
      <div className="flex items-center justify-between mb-1.5">
        <div
          className="px-2 py-0.5 rounded-md text-[11px] font-black text-white flex-shrink-0"
          style={{ background: isSet ? color : C.error }}
        >
          {sensKey}
        </div>
        {isSet
          ? <CheckCircle  size={14} style={{ color: C.success }} />
          : <PlusCircle   size={14} style={{ color: C.subtle  }} />
        }
      </div>

      {/* Hindi label */}
      <p
        className="text-[10px] font-semibold mb-2 truncate"
        style={{ color: isSet ? color : C.subtle }}
      >
        {hindi}
      </p>

      {/* Stats or CTA */}
      {isSet ? (
        <>
          <p className="font-black text-sm" style={{ color }}>
            {totalStaff} कर्मचारी
          </p>
          <p className="text-[10px] mt-0.5" style={{ color: C.subtle }}>
            {filledRowCount}/15 बूथ-स्तर
          </p>
        </>
      ) : (
        <div className="flex items-center gap-1 mt-1">
          <PlusCircle size={11} style={{ color: C.subtle }} />
          <span className="text-[10px] font-semibold" style={{ color: C.subtle }}>
            सेट करें
          </span>
        </div>
      )}
    </button>
  );
}

// ─────────────────────────────────────────────
//  बूथ मानक SECTION  (Flutter: _BoothManakSection)
// ─────────────────────────────────────────────
function BoothManakSection({ boothRules, loading, onTapSens }) {
  // allSet: every sensitivity has ≥1 row with data
  const allSet = SENS_CONFIG.every(s => {
    const rows = boothRules[s.key] ?? [];
    return rows.some(rowHasAny);
  });

  return (
    <div
      className="rounded-2xl overflow-hidden"
      style={{
        background: 'white',
        border: `1px solid ${C.border}66`,
        boxShadow: `${C.primary}0F 0px 4px 12px`,
      }}
    >
      {/* Section header */}
      <div
        className="flex items-center gap-3 px-4 py-3"
        style={{
          background: `${C.surface}99`,
          borderBottom: `1px solid ${C.border}4D`,
        }}
      >
        <div
          className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0"
          style={{ background: `${C.primary}1A` }}
        >
          <Vote size={18} style={{ color: C.primary }} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-extrabold text-sm" style={{ color: C.dark }}>बूथ मानक</p>
          <p className="text-[10px]" style={{ color: C.subtle }}>
            संवेदनशीलता × बूथ संख्या के अनुसार पुलिस बल
          </p>
        </div>
        <StatusBadge allSet={allSet} />
      </div>

      {/* 2×2 tile grid */}
      {loading ? (
        <div className="flex items-center justify-center py-8">
          <div
            className="w-6 h-6 border-2 rounded-full animate-spin"
            style={{ borderColor: `${C.primary}40`, borderTopColor: C.primary }}
          />
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-2.5 p-3">
          {SENS_CONFIG.map(s => {
            const rows         = boothRules[s.key] ?? [];
            const filledRows   = rows.filter(rowHasAny);
            const isSet        = filledRows.length > 0;
            const totalStaff   = filledRows.reduce((sum, r) => sum + rowTotalStaff(r), 0);
            return (
              <SensTile
                key={s.key}
                sensKey={s.key}
                hindi={s.hi}
                color={s.color}
                isSet={isSet}
                totalStaff={totalStaff}
                filledRowCount={filledRows.length}
                onClick={() => onTapSens(s.key, s.color, s.hi)}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────
//  जनपदीय मानक SECTION  (Flutter: _DistrictManakSection)
// ─────────────────────────────────────────────
function DistrictManakSection({ rules, loading, onClick }) {
  const filledCount = rules.filter(districtRowHasAny).length;
  const totalDuties = rules.length;
  const totalStaff  = rules.reduce((sum, r) =>
    sum + STAFF_FIELDS.reduce((s2, f) => s2 + ((r[f] ?? 0)), 0), 0);
  const isSet = filledCount > 0;

  return (
    <GradientBanner
      label="जनपदीय कानून व्यवस्था मानक"
      subtitle={
        loading
          ? 'लोड हो रहा है...'
          : isSet
            ? `${totalStaff} कर्मचारी • ${filledCount}/${totalDuties} ड्यूटी प्रकार`
            : 'कानून व्यवस्था ड्यूटी मानक सेट करें'
      }
      icon={Shield}
      colors={['#6C3483', '#884EA0']}
      badge={isSet ? 'सेट' : null}
      onClick={loading ? undefined : onClick}
    />
  );
}

// ─────────────────────────────────────────────
//  MAIN DASHBOARD
// ─────────────────────────────────────────────
export default function AdminDashboardPage() {
  const nav = useNavigate();

  const [stats,          setStats]          = useState(null);
  const [loadingStats,   setLoadingStats]   = useState(true);

  // boothRules: { 'A++': [ rowObj, ... ], 'A': [...], 'B': [...], 'C': [...] }
  // Each rowObj has siArmedCount, siUnarmedCount, hcArmedCount, etc.
  const [boothRules,     setBoothRules]     = useState({ 'A++': [], A: [], B: [], C: [] });
  const [loadingBooth,   setLoadingBooth]   = useState(true);

  // districtRules: list of duty-type rows
  const [districtRules,  setDistrictRules]  = useState([]);
  const [loadingDistrict,setLoadingDistrict] = useState(true);

  // ── Load stats ──────────────────────────────
  const loadStats = useCallback(async () => {
    setLoadingStats(true);
    try {
      const res = await adminApi.overview();
      setStats(res.data || res);
    } catch (e) {
      toast.error('Failed to load stats');
    } finally {
      setLoadingStats(false);
    }
  }, []);

  // ── Load booth rules (all 4 sensitivities) ──
  const loadAllBoothRules = useCallback(async () => {
    setLoadingBooth(true);
    try {
      const res  = await adminApi.getBoothRules();          // GET /admin/booth-rules
      const data = res.data ?? {};                          // { 'A++': [...], A: [...], ... }
      setBoothRules({
        'A++': data['A++'] ?? [],
        A:     data['A']   ?? [],
        B:     data['B']   ?? [],
        C:     data['C']   ?? [],
      });
    } catch (e) {
      // silent — dashboard still usable
      console.warn('booth rules load:', e);
    } finally {
      setLoadingBooth(false);
    }
  }, []);

  // ── Load district rules ─────────────────────
  const loadDistrictRules = useCallback(async () => {
    setLoadingDistrict(true);
    try {
      const res  = await adminApi.getDistrictRules();       // GET /admin/district-rules
      setDistrictRules(res.data ?? []);
    } catch (e) {
      console.warn('district rules load:', e);
    } finally {
      setLoadingDistrict(false);
    }
  }, []);

  // ── Initial load ────────────────────────────
  useEffect(() => {
    loadStats();
    loadAllBoothRules();
    loadDistrictRules();
  }, []);

  // ── Navigate to booth manak page ────────────
  // Flutter: _openBoothManak → ManakBoothPage, then reload on return
  const openBoothManak = (sensKey, color, hindi) => {
    nav('/manak-booth', { state: { sensitivity: sensKey, color, hindi, initialRules: boothRules[sensKey] ?? [] } });
    // On return the page remounts; if you use layout-level keep-alive,
    // call loadAllBoothRules() in a focus effect instead.
  };

  // ── Navigate to district manak page ─────────
  // Flutter: _openDistrictManak → ManakDistrictPage
  const openDistrictManak = () => {
    nav('/manak-district', { state: { initialRules: districtRules } });
  };

  const statItems = stats ? [
    { label: 'Super Zones',    value: stats.superZones      ?? 0, icon: Layers, color: C.primary },
    { label: 'Total Booths',   value: stats.totalBooths     ?? 0, icon: MapPin, color: C.success },
    { label: 'Total Staff',    value: stats.totalStaff      ?? 0, icon: Users,  color: C.accent  },
    { label: 'Assigned',       value: stats.assignedDuties  ?? 0, icon: Vote,   color: C.info    },
  ] : [];

  return (
    <div
      className="p-4 max-w-5xl mx-auto space-y-3.5"
      style={{ paddingBottom: 30 }}
    >
      {/* ── Stats Grid ── */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {loadingStats
          ? [1,2,3,4].map(i => <Shimmer key={i} className="h-24 rounded-xl" />)
          : statItems.map(s => (
              <StatCard
                key={s.label}
                label={s.label}
                value={s.value}
                icon={s.icon}
                color={s.color}
              />
            ))
        }
      </div>

      {/* ── Goswara Report banner (Flutter: golden gradient _gradientNav) ── */}
      <GradientBanner
        label="Goswara Report"
        subtitle="Summary Report of Booth Staff"
        icon={FileText}
        colors={['#8B6914', '#B8860B']}
        onClick={() => nav('/goswara-page')}
      />

      {/* ── Hierarchy Report banner (Flutter: _HierarchyBanner, dark blue) ── */}
      <GradientBanner
        label="प्रशासनिक पदानुक्रम रिपोर्ट"
        subtitle="Super Zone · Sector · Panchayat · Booth Tables"
        icon={TableProperties}
        colors={['#0F2B5B', '#1E4D9B']}
        onClick={() => nav('/heirarchy-report')}
      />

      {/* ── Election Map View (Flutter: blue _gradientNav) ── */}
      <GradientBanner
        label="Election Map View"
        subtitle="District → Zone → Live Map"
        icon={MapPin}
        colors={['#1A5276', '#2874A6']}
        onClick={() => nav('/map-view')}
      />

      {/* ── बूथ मानक SECTION (Flutter: _BoothManakSection) ── */}
      <BoothManakSection
        boothRules={boothRules}
        loading={loadingBooth}
        onTapSens={openBoothManak}
      />

      {/* ── जनपदीय मानक SECTION (Flutter: _DistrictManakSection) ── */}
      <DistrictManakSection
        rules={districtRules}
        loading={loadingDistrict}
        onClick={openDistrictManak}
      />
    </div>
  );
}