import { useState, useCallback, useRef, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import {
  ChevronLeft, ChevronRight, Save, CheckCircle,
  PlusCircle, Info, Gavel, Shield, AlertTriangle,
} from 'lucide-react';
import { adminApi } from '../../api/endpoints';
import toast from 'react-hot-toast';

// ─── Import the full-featured rank editor ─────────────────────────────────────
import ManakRankEditorPage from './ManakRankEditorPage';

// ─────────────────────────────────────────────
//  PALETTE
// ─────────────────────────────────────────────
const C = {
  bg:      '#FDF6E3',
  surface: '#F5E6C8',
  primary: '#8B6914',
  dark:    '#4A3000',
  subtle:  '#AA8844',
  border:  '#D4A843',
  error:   '#C0392B',
  success: '#2D6A1E',
  aux:     '#E65100',
  pac:     '#00695C',
  purple:  '#6A1B9A',
  info:    '#1A5276',
};

// ─────────────────────────────────────────────
//  15 BOOTH TIERS
// ─────────────────────────────────────────────
const BOOTH_TIERS = [
  { count: 1,  label: '1 बूथ' },
  { count: 2,  label: '2 बूथ' },
  { count: 3,  label: '3 बूथ' },
  { count: 4,  label: '4 बूथ' },
  { count: 5,  label: '5 बूथ' },
  { count: 6,  label: '6 बूथ' },
  { count: 7,  label: '7 बूथ' },
  { count: 8,  label: '8 बूथ' },
  { count: 9,  label: '9 बूथ' },
  { count: 10, label: '10 बूथ' },
  { count: 11, label: '11 बूथ' },
  { count: 12, label: '12 बूथ' },
  { count: 13, label: '13 बूथ' },
  { count: 14, label: '14 बूथ' },
  { count: 15, label: '15 और उससे अधिक बूथ' },
];

// ─────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────
function hasAny(r) {
  if (!r) return false;
  return [
    'siArmedCount', 'siUnarmedCount',
    'hcArmedCount', 'hcUnarmedCount',
    'constArmedCount', 'constUnarmedCount',
    'auxArmedCount', 'auxUnarmedCount',
    'pacCount',
  ].some(f => (r[f] ?? 0) > 0);
}

function totalStaff(r) {
  if (!r) return 0;
  return [
    'siArmedCount', 'siUnarmedCount',
    'hcArmedCount', 'hcUnarmedCount',
    'constArmedCount', 'constUnarmedCount',
    'auxArmedCount', 'auxUnarmedCount',
  ].reduce((sum, f) => sum + (r[f] ?? 0), 0);
}

// ─────────────────────────────────────────────
//  UNSAVED CHANGES DIALOG
// ─────────────────────────────────────────────
function UnsavedDialog({ onDiscard, onStay }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: 'rgba(0,0,0,0.45)' }}>
      <div
        className="rounded-2xl overflow-hidden w-full max-w-sm"
        style={{ background: C.bg, border: `1.5px solid ${C.error}` }}
      >
        <div className="p-5">
          <div className="flex items-center gap-2 mb-3">
            <AlertTriangle size={20} style={{ color: C.error }} />
            <h3 className="font-extrabold text-base" style={{ color: C.dark }}>
              बदलाव सहेजे नहीं गए
            </h3>
          </div>
          <p className="text-sm mb-5" style={{ color: C.dark }}>
            आपने कुछ बदलाव किए हैं। क्या आप बिना सेव के बाहर निकलना चाहते हैं?
          </p>
          <div className="flex gap-3">
            <button
              onClick={onStay}
              className="flex-1 py-2.5 rounded-xl text-sm font-semibold border"
              style={{ color: C.subtle, borderColor: C.border }}
            >
              रद्द करें
            </button>
            <button
              onClick={onDiscard}
              className="flex-1 py-2.5 rounded-xl text-sm font-bold text-white"
              style={{ background: C.error }}
            >
              बाहर निकलें
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────
//  CHIP ROW
// ─────────────────────────────────────────────
function ChipRow({ rule, color }) {
  const si  = { a: rule.siArmedCount    ?? 0, u: rule.siUnarmedCount    ?? 0 };
  const hc  = { a: rule.hcArmedCount    ?? 0, u: rule.hcUnarmedCount    ?? 0 };
  const cn  = { a: rule.constArmedCount ?? 0, u: rule.constUnarmedCount ?? 0 };
  const aux = { a: rule.auxArmedCount   ?? 0, u: rule.auxUnarmedCount   ?? 0 };
  const pac =     rule.pacCount         ?? 0;

  function SplitChip({ label, armed, unarmed, chipColor }) {
    if (armed + unarmed === 0) return null;
    return (
      <div
        className="flex items-center gap-1 px-2 py-1 rounded-lg mr-1.5 flex-shrink-0"
        style={{ background: `${chipColor}14`, border: `1px solid ${chipColor}4D` }}
      >
        <span className="text-[10px] font-bold mr-0.5" style={{ color: `${chipColor}DD` }}>
          {label}:
        </span>
        {armed > 0 && (
          <>
            <Gavel  size={9} style={{ color: C.purple }} />
            <span className="text-[11px] font-black" style={{ color: C.purple }}>{armed}</span>
          </>
        )}
        {armed > 0 && unarmed > 0 && (
          <span className="text-[11px]" style={{ color: `${chipColor}80` }}>/</span>
        )}
        {unarmed > 0 && (
          <>
            <Shield size={9} style={{ color: C.info }} />
            <span className="text-[11px] font-black" style={{ color: C.info }}>{unarmed}</span>
          </>
        )}
      </div>
    );
  }

  function SingleChip({ label, value, chipColor }) {
    if (!value) return null;
    return (
      <div
        className="flex items-center gap-1 px-2 py-1 rounded-lg mr-1.5 flex-shrink-0"
        style={{ background: `${chipColor}1A`, border: `1px solid ${chipColor}4D` }}
      >
        <span className="text-[10px] font-bold" style={{ color: `${chipColor}DD` }}>{label}:</span>
        <span className="text-[11px] font-black" style={{ color: chipColor }}>{value}</span>
      </div>
    );
  }

  return (
    <div className="flex overflow-x-auto pb-0.5 mt-2.5" style={{ scrollbarWidth: 'none' }}>
      <SplitChip label="SI"    armed={si.a}  unarmed={si.u}  chipColor={color} />
      <SplitChip label="HC"    armed={hc.a}  unarmed={hc.u}  chipColor={color} />
      <SplitChip label="Const" armed={cn.a}  unarmed={cn.u}  chipColor={color} />
      <SplitChip label="Aux"   armed={aux.a} unarmed={aux.u} chipColor={C.aux} />
      <SingleChip label="PAC"  value={pac}                   chipColor={C.pac} />
    </div>
  );
}

// ─────────────────────────────────────────────
//  BOOTH TIER CARD
// ─────────────────────────────────────────────
function BoothTierCard({ tier, rule, color, onClick, animDelay }) {
  const isSet    = hasAny(rule);
  const staff    = totalStaff(rule);
  const countStr = tier.count === 15 ? '15+' : `${tier.count}`;

  return (
    <button
      onClick={onClick}
      className="w-full text-left rounded-2xl transition-all hover:shadow-md hover:-translate-y-0.5 active:translate-y-0 fade-in"
      style={{
        background:     isSet ? `${color}0A` : 'white',
        border:         `${isSet ? 1.5 : 1}px solid ${isSet ? color + '66' : C.border + '66'}`,
        padding:        '14px',
        animationDelay: `${animDelay}ms`,
      }}
    >
      <div className="flex items-center gap-3">
        <div
          className="w-11 h-11 rounded-xl flex items-center justify-center flex-shrink-0 font-black"
          style={{
            background: isSet ? color : `${C.subtle}26`,
            color:      isSet ? 'white' : C.subtle,
            fontSize:   tier.count === 15 ? 13 : 18,
          }}
        >
          {countStr}
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-bold text-sm" style={{ color: C.dark }}>{tier.label}</p>
          <p className="text-[11px] font-semibold mt-0.5" style={{ color: isSet ? color : C.subtle }}>
            {isSet ? `कुल: ${staff} कर्मचारी` : 'मानक सेट नहीं है'}
          </p>
        </div>
        <div className="flex items-center gap-1 flex-shrink-0">
          {isSet
            ? <CheckCircle size={17} style={{ color: C.success }} />
            : <PlusCircle  size={17} style={{ color: C.subtle  }} />
          }
          <ChevronRight size={18} style={{ color: C.subtle }} />
        </div>
      </div>
      {isSet && <ChipRow rule={rule} color={color} />}
    </button>
  );
}

// ─────────────────────────────────────────────
//  FULL-SCREEN EDITOR OVERLAY
//  Wraps ManakRankEditorPage in a fixed overlay
//  so it feels like a pushed route without
//  actually changing the URL.
// ─────────────────────────────────────────────
function RankEditorOverlay({ tier, color, sensitivity, initial, onSave, onClose }) {
  // Lock body scroll while overlay is open
  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { document.body.style.overflow = prev; };
  }, []);

  // Wrap ManakRankEditorPage.onSave to inject boothCount then close
  const handleSave = useCallback(async (data) => {
    onSave({ ...data, boothCount: tier.count });
    // onClose is called by ManakRankEditorPage via onBack after save,
    // but we also call it here so the overlay dismisses immediately.
  }, [tier.count, onSave]);

  return (
    <div
  style={{
    position: 'fixed', inset: 0, zIndex: 60,
    animation: 'mbo-slideIn 0.22s cubic-bezier(.4,0,.2,1) both',
    display: 'flex', flexDirection: 'column',
    overflow: 'hidden',
  }}
>
      <style>{`
        @keyframes mbo-slideIn {
          from { transform: translateX(100%); opacity: 0; }
          to   { transform: translateX(0);    opacity: 1; }
        }
      `}</style>

      {/*
        ManakRankEditorPage is a self-contained full-page component.
        We pass:
          title      → tier label (e.g. "3 बूथ")
          subtitle   → sensitivity label (e.g. "A — अति संवेदनशील")
          color      → sensitivity accent colour
          initial    → current saved rule object for this tier (keyed by API field names)
          showSankhya→ false (booth rules don't need sankhya)
          onSave     → receives the final API-ready object, we merge boothCount
          onBack     → close the overlay
      */}
      <ManakRankEditorPage
        title={tier.label}
        subtitle={`${sensitivity} मानक — बूथ संपादन`}
        color={color}
        initial={initial ?? {}}
        showSankhya={false}
        onSave={handleSave}
        onBack={onClose}
      />
    </div>
  );
}

// ─────────────────────────────────────────────
//  MAIN PAGE  (ManakBoothPage)
// ─────────────────────────────────────────────
export default function ManakBoothPage() {
  const nav      = useNavigate();
  const location = useLocation();

  const {
    sensitivity  = 'A',
    color        = C.primary,
    hindi        = '',
    initialRules = [],
  } = location.state ?? {};

  // boothData: { [boothCount: number]: ruleObj }
  const [boothData,    setBoothData]    = useState(() => {
    const map = {};
    initialRules.forEach(r => {
      const bc = r.boothCount ?? 0;
      if (bc >= 1 && bc <= 15) map[bc] = { ...r };
    });
    return map;
  });

  const [changed,      setChanged]      = useState(false);
  const [saving,       setSaving]       = useState(false);
  const [editTier,     setEditTier]     = useState(null);   // tier being edited
  const [showUnsaved,  setShowUnsaved]  = useState(false);
  const pendingNavRef = useRef(null);

  const filledCount = BOOTH_TIERS.filter(t => hasAny(boothData[t.count])).length;

  // ── Browser beforeunload guard ──
  useEffect(() => {
    const handler = (e) => {
      if (!changed) return;
      e.preventDefault(); e.returnValue = '';
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [changed]);

  // ── Back navigation guard ──
  const handleBack = useCallback(() => {
    if (!changed) { nav(-1); return; }
    pendingNavRef.current = () => nav(-1);
    setShowUnsaved(true);
  }, [changed, nav]);

  // ── Receive saved data from RankEditorOverlay ──
  // data already has boothCount injected by the overlay
  const handleEditorSave = useCallback((data) => {
    setBoothData(prev => ({ ...prev, [data.boothCount]: data }));
    setChanged(true);
    setEditTier(null);   // close overlay
  }, []);

  // ── Save all to API ──
  const saveAll = async () => {
    setSaving(true);
    try {
      const rules = Object.values(boothData);
      await adminApi.saveBoothRules(sensitivity, rules);
      toast.success(`${sensitivity} मानक सेव हो गया ✓`, {
        style: { background: color, color: 'white', fontWeight: 700 },
      });
      setChanged(false);
      nav(-1);
    } catch (e) {
      toast.error(`सेव विफल: ${e.message}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div
      className="min-h-screen flex flex-col"
      style={{ background: C.bg, fontFamily: "'Tiro Devanagari Hindi', Georgia, serif" }}
    >
      {/* ── App Bar ──────────────────────────────────────────────────────── */}
      <div
        className="flex items-center gap-3 px-4 py-3 sticky top-0 z-30 flex-shrink-0"
        style={{ background: color, boxShadow: `${color}66 0px 4px 20px` }}
      >
        <button
          onClick={handleBack}
          className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0"
          style={{ background: 'rgba(255,255,255,0.15)' }}
        >
          <ChevronLeft size={20} color="white" />
        </button>
        <div className="flex-1 min-w-0">
          <p className="font-extrabold text-white text-base leading-tight">
            {sensitivity} मानक
          </p>
          <p className="text-white/70 text-[11px] font-medium">{hindi}</p>
        </div>
        {changed && (
          <div
            className="flex-shrink-0 px-2.5 py-1 rounded-full text-[10px] font-extrabold text-white"
            style={{ background: 'rgba(255,255,255,0.2)' }}
          >
            अनसेव्ड
          </div>
        )}
      </div>

      {/* ── Info strip ───────────────────────────────────────────────────── */}
      <div
        className="flex items-center gap-2 px-4 py-2.5 flex-shrink-0"
        style={{ background: C.surface, borderBottom: `1px solid ${C.border}66` }}
      >
        <Info size={14} style={{ color, flexShrink: 0 }} />
        <p className="flex-1 text-[11.5px] font-semibold" style={{ color: C.dark }}>
          मतदान केन्द्र पर बूथ संख्या के अनुसार पुलिस बल मानक चुनें
        </p>
        <span className="font-extrabold text-xs flex-shrink-0" style={{ color }}>
          {filledCount}/15
        </span>
      </div>

      {/* ── Tier list ─────────────────────────────────────────────────────── */}
      <div className="flex-1 overflow-y-auto" style={{ paddingBottom: 100 }}>
        <div className="p-4 grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
          {BOOTH_TIERS.map((tier, i) => (
            <BoothTierCard
              key={tier.count}
              tier={tier}
              rule={boothData[tier.count]}
              color={color}
              animDelay={i * 30}
              onClick={() => setEditTier(tier)}
            />
          ))}
        </div>
      </div>

      {/* ── Sticky save bar ───────────────────────────────────────────────── */}
      <div
        className="fixed bottom-0 left-0 right-0 z-30 px-4 py-3 flex-shrink-0"
        style={{
          background: C.bg,
          borderTop: `1px solid ${C.border}66`,
          boxShadow: `0 -4px 20px ${C.primary}14`,
        }}
      >
        {/* Progress bar */}
        <div className="h-1 rounded-full mb-3 overflow-hidden" style={{ background: `${color}26` }}>
          <div
            className="h-full rounded-full transition-all duration-500"
            style={{ width: `${(filledCount / 15) * 100}%`, background: color }}
          />
        </div>

        <button
          onClick={saveAll}
          disabled={saving}
          className="w-full py-3.5 rounded-2xl font-extrabold text-sm text-white flex items-center justify-center gap-2 transition-all"
          style={{
            background: saving ? C.subtle : color,
            boxShadow: saving ? 'none' : `${color}4D 0px 4px 16px`,
          }}
        >
          {saving ? (
            <>
              <div
                className="w-5 h-5 border-2 rounded-full animate-spin"
                style={{ borderColor: 'rgba(255,255,255,0.3)', borderTopColor: 'white' }}
              />
              सेव हो रहा है...
            </>
          ) : (
            <>
              <Save size={17} />
              सभी मानक सेव करें
              <span className="text-white/60 font-semibold text-[11px] ml-1">
                ({filledCount}/15 भरे)
              </span>
            </>
          )}
        </button>
      </div>

      {/* ── Full-screen rank editor overlay ───────────────────────────────── */}
      {editTier && (
        <RankEditorOverlay
          tier={editTier}
          color={color}
          sensitivity={sensitivity}
          initial={boothData[editTier.count]}
          onSave={handleEditorSave}
          onClose={() => setEditTier(null)}
        />
      )}

      {/* ── Unsaved changes dialog ─────────────────────────────────────────── */}
      {showUnsaved && (
        <UnsavedDialog
          onDiscard={() => {
            setShowUnsaved(false);
            pendingNavRef.current?.();
          }}
          onStay={() => setShowUnsaved(false)}
        />
      )}
    </div>
  );
}