/**
 * StaffManakBoothReportPage.jsx
 *
 *
 * Tailwind CSS required.
 * CSS variables (--bg, --primary, etc.) must be defined globally.
 *
 * Brown-themed, clean UI. No print functionality.
 */

import { useState, useEffect, useCallback } from "react";
import toast, { Toaster } from "react-hot-toast";
import {
  RefreshCw, CheckCircle2, Clock,
  LayoutGrid, TableProperties, BarChart3, Shield,
  ArrowLeft, TrendingUp, Users, AlertTriangle, Info,
} from "lucide-react";
import { useNavigate } from "react-router-dom";

// ── API Base ──────────────────────────────────────────────────────────────────
const API_BASE =
  (typeof import.meta !== "undefined" && import.meta.env?.VITE_API_URL) || "/api";

async function apiFetch(path, options = {}) {
  const token = localStorage.getItem("AUTH_TOKEN");
  const res = await fetch(`${API_BASE}${path}`, {
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...options,
  });
  if (!res.ok) throw new Error(`API error ${res.status}`);
  return res.json();
}

// ── Constants ─────────────────────────────────────────────────────────────────
const BOOTH_TIERS = [
  { count: 1, label: "1 बूथ" },
  { count: 2, label: "2 बूथ" },
  { count: 3, label: "3 बूथ" },
  { count: 4, label: "4 बूथ" },
  { count: 5, label: "5 बूथ" },
  { count: 6, label: "6 बूथ" },
  { count: 7, label: "7 बूथ" },
  { count: 8, label: "8 बूथ" },
  { count: 9, label: "9 बूथ" },
  { count: 10, label: "10 बूथ" },
  { count: 11, label: "11 बूथ" },
  { count: 12, label: "12 बूथ" },
  { count: 13, label: "13 बूथ" },
  { count: 14, label: "14 बूथ" },
  { count: 15, label: "15 और उससे अधिक बूथ" },
];

const SENSITIVITIES = [
  { key: "A++", hi: "अति-अति संवेदनशील", color: "#5B2C8D", bg: "#f3e5f5", accent: "#7D3DAF" },
  { key: "A",   hi: "अति संवेदनशील",     color: "#922B21", bg: "#fdecea", accent: "#C0392B" },
  { key: "B",   hi: "संवेदनशील",          color: "#784212", bg: "#fdf0d5", accent: "#A04000" },
  { key: "C",   hi: "सामान्य",            color: "#1A5276", bg: "#e8f4fd", accent: "#2471A3" },
];

// ── Value helpers ─────────────────────────────────────────────────────────────
const getVal = (r, key, alt) =>
  Number(r?.[key] ?? (alt ? r?.[alt] : null) ?? 0);
const getPAC = (r) => Number(r?.pacCount ?? r?.pac_count ?? 0);
const fmtPac = (v) =>
  v === 0 ? "0" : v % 1 === 0 ? `${Math.round(v)}` : v.toFixed(1);

// ── Compute rows + totals ─────────────────────────────────────────────────────
function computeRows(ruleFor, centerCounts) {
  let tCenters = 0;
  let mSI_A = 0, mSI_U = 0, mHC_A = 0, mHC_U = 0;
  let mC_A = 0, mC_U = 0, mAx_A = 0, mAx_U = 0, mPAC = 0;
  let tSI_A = 0, tHC_A = 0, tHC_U = 0;
  let tC_A = 0, tC_U = 0, tAx_A = 0, tAx_U = 0, tPAC = 0;

  const rows = BOOTH_TIERS.map((tier, idx) => {
    const i = idx + 1;
    const r = ruleFor(i);
    const c = centerCounts[i] ?? 0;
    const si_a = getVal(r, "siArmedCount", "si_armed_count");
    const si_u = getVal(r, "siUnarmedCount", "si_unarmed_count");
    const hc_a = getVal(r, "hcArmedCount", "hc_armed_count");
    const hc_u = getVal(r, "hcUnarmedCount", "hc_unarmed_count");
    const c_a = getVal(r, "constArmedCount", "const_armed_count");
    const c_u = getVal(r, "constUnarmedCount", "const_unarmed_count");
    const ax_a = getVal(r, "auxArmedCount", "aux_armed_count");
    const ax_u = getVal(r, "auxUnarmedCount", "aux_unarmed_count");
    const pac = getPAC(r);

    tCenters += c;
    mSI_A += si_a; mSI_U += si_u;
    mHC_A += hc_a; mHC_U += hc_u;
    mC_A += c_a;   mC_U += c_u;
    mAx_A += ax_a; mAx_U += ax_u;
    mPAC += pac;
    tSI_A += c * si_a;
    tHC_A += c * hc_a; tHC_U += c * hc_u;
    tC_A += c * c_a;   tC_U += c * c_u;
    tAx_A += c * ax_a; tAx_U += c * ax_u;
    tPAC += c * pac;

    return { i, label: tier.label, c, si_a, si_u, hc_a, hc_u, c_a, c_u, ax_a, ax_u, pac };
  });

  return {
    rows,
    totals: {
      tCenters,
      mSI_A, mSI_U, mHC_A, mHC_U, mC_A, mC_U, mAx_A, mAx_U, mPAC,
      tSI_A, tHC_A, tHC_U, tC_A, tC_U, tAx_A, tAx_U, tPAC,
    },
  };
}

// ═════════════════════════════════════════════════════════════════════════════
//  MAIN PAGE
// ═════════════════════════════════════════════════════════════════════════════
export default function StaffManakBoothReportPage() {
  const [rules, setRules] = useState({ "A++": [], A: [], B: [], C: [] });
  const [centerCounts, setCenterCounts] = useState({ "A++": {}, A: {}, B: {}, C: {} });
  const [districtName, setDistrictName] = useState("");
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState("all");

  const nav = useNavigate();

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const rulesRes = await apiFetch("/admin/booth-rules");
      console.log(rulesRes);
      
      const rulesData = rulesRes?.data ?? {};
      const newRules = { "A++": [], A: [], B: [], C: [] };
      for (const s of ["A++", "A", "B", "C"]) {
        newRules[s] = (rulesData[s] ?? []).map((e) => ({ ...e }));
      }
      setRules(newRules);

      let newCounts = { "A++": {}, A: {}, B: {}, C: {} };
      try {
        const ccRes = await apiFetch("/admin/booth-rules/center-counts-by-type");
        console.log(ccRes);
        
        const ccData = ccRes?.data ?? {};
        for (const sens of ["A++", "A", "B", "C"]) {
          const sd = ccData[sens] ?? {};
          const counts = {};
          Object.entries(sd).forEach(([k, v]) => {
            const bc = parseInt(k, 10);
            if (bc >= 1 && bc <= 15) counts[bc] = Number(v);
          });
          newCounts[sens] = counts;
        }
      } catch {
        try {
          const centersRes = await apiFetch("/admin/centers/all?limit=9999");
          console.log(centersRes);
          
          const centers = centersRes?.data ?? [];
          const counts = { "A++": {}, A: {}, B: {}, C: {} };
          for (const c of centers) {
            const ct = c.centerType ?? "C";
            const bc = Math.min(Math.max(Number(c.boothCount ?? 1), 1), 15);
            if (counts[ct]) counts[ct][bc] = (counts[ct][bc] ?? 0) + 1;
          }
          newCounts = counts;
        } catch {}
      }
      setCenterCounts(newCounts);

      try {
        const profileRes = await apiFetch("/auth/me");
        setDistrictName(profileRes?.data?.district ?? "");
      } catch {}
    } catch (e) {
      toast.error(`लोड विफल: ${e.message}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadData(); }, [loadData]);

  const ruleFor = (sens, boothCount) =>
    (rules[sens] ?? []).find(
      (r) => Number(r.boothCount ?? r.booth_count ?? 0) === boothCount
    ) ?? null;

  const hasAny = (r) =>
    !!(r && (
      getVal(r, "siArmedCount", "si_armed_count") > 0 ||
      getVal(r, "hcArmedCount", "hc_armed_count") > 0 ||
      getVal(r, "constArmedCount", "const_armed_count") > 0 ||
      getVal(r, "auxArmedCount", "aux_armed_count") > 0 ||
      getPAC(r) > 0
    ));

  const filledCount = (sens) => {
    let c = 0;
    for (let i = 1; i <= 15; i++) if (hasAny(ruleFor(sens, i))) c++;
    return c;
  };

  const tabs = [
    { key: "all", label: "सभी", icon: LayoutGrid },
    ...SENSITIVITIES.map((s) => ({
      key: s.key,
      label: s.key,
      sublabel: s.hi.split(" ")[0],
      color: s.color,
    })),
  ];

  return (
    <div
      className="min-h-screen"
      style={{
        background: "linear-gradient(135deg, #fdf6ec 0%, #f5e6cc 50%, #fdf0d8 100%)",
        fontFamily: "'Tiro Devanagari Hindi', Georgia, serif",
      }}
    >
      <Toaster
        position="top-right"
        toastOptions={{
          style: {
            fontFamily: "inherit",
            fontSize: 13,
            borderRadius: 12,
            background: "#3D1A00",
            color: "#fff",
          },
        }}
      />

      {/* ── AppBar ── */}
      <div
        className="sticky top-0 z-50"
        style={{
          background: "linear-gradient(90deg, #4A1800 0%, #6B2D00 60%, #5C2200 100%)",
          boxShadow: "0 4px 24px rgba(74,24,0,0.35)",
        }}
      >
        {/* Top row */}
        <div className="px-4 md:px-6 py-3.5 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0">
            <button
              onClick={() => nav("/")}
              className="p-2 rounded-xl transition-all hover:bg-white/10 active:scale-95"
            >
              <ArrowLeft size={18} className="text-amber-200" />
            </button>

            <div
              className="flex items-center justify-center w-10 h-10 rounded-2xl shrink-0"
              style={{ background: "rgba(255,200,100,0.15)", border: "1px solid rgba(255,200,100,0.25)" }}
            >
              <TableProperties size={18} className="text-amber-300" />
            </div>

            <div className="min-w-0">
              <div className="font-extrabold text-base md:text-lg leading-tight text-white truncate">
                मानक बूथ रिपोर्ट
              </div>
              <div className="text-xs text-amber-300/70 truncate">
                बूथ-वार पुलिस व्यवस्थापन
                {districtName ? ` · ${districtName}` : ""}
              </div>
            </div>
          </div>

          <button
            onClick={loadData}
            disabled={loading}
            className="flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold transition-all hover:bg-white/15 active:scale-95 disabled:opacity-50"
            style={{
              background: "rgba(255,200,100,0.12)",
              border: "1px solid rgba(255,200,100,0.25)",
              color: "#FBBF24",
            }}
          >
            <RefreshCw size={13} className={loading ? "animate-spin" : ""} />
            <span className="hidden sm:inline">रिफ्रेश</span>
          </button>
        </div>

        {/* Tab bar */}
        <div
          className="flex overflow-x-auto"
          style={{
            borderTop: "1px solid rgba(255,200,100,0.15)",
            scrollbarWidth: "none",
          }}
        >
          {tabs.map((tab) => {
            const active = activeTab === tab.key;
            const Icon = tab.icon;
            return (
              <button
                key={tab.key}
                onClick={() => setActiveTab(tab.key)}
                className="flex items-center gap-1.5 px-5 py-3 text-xs font-bold whitespace-nowrap transition-all shrink-0 relative"
                style={{
                  color: active ? "#FCD34D" : "rgba(252,211,77,0.45)",
                  background: active ? "rgba(255,200,100,0.1)" : "transparent",
                }}
              >
                {Icon && <Icon size={12} />}
                {tab.label}
                {tab.sublabel && (
                  <span className="opacity-60 font-normal">{tab.sublabel}</span>
                )}
                {active && (
                  <span
                    className="absolute bottom-0 left-0 right-0 h-0.5 rounded-t-full"
                    style={{ background: "#FCD34D" }}
                  />
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* ── Body ── */}
      <div className="p-4 md:p-6 max-w-screen-2xl mx-auto">
        {loading ? (
          <LoadingSkeleton />
        ) : activeTab === "all" ? (
          <div className="space-y-5">
            {SENSITIVITIES.map((s) => (
              <SensBlock
                key={s.key}
                sens={s}
                ruleFor={(bc) => ruleFor(s.key, bc)}
                centerCounts={centerCounts[s.key] ?? {}}
                filledCount={filledCount(s.key)}
              />
            ))}
          </div>
        ) : (
          SENSITIVITIES.filter((s) => s.key === activeTab).map((s) => (
            <SensBlock
              key={s.key}
              sens={s}
              ruleFor={(bc) => ruleFor(s.key, bc)}
              centerCounts={centerCounts[s.key] ?? {}}
              filledCount={filledCount(s.key)}
            />
          ))
        )}
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  SENS BLOCK
// ═════════════════════════════════════════════════════════════════════════════
function SensBlock({ sens, ruleFor, centerCounts, filledCount }) {
  const isSet = filledCount > 0;
  const [expanded, setExpanded] = useState(true);

  let tCenters = 0, tSI = 0, tHC = 0, tC = 0, tAx = 0, tPAC = 0;
  for (let i = 1; i <= 15; i++) {
    const r = ruleFor(i);
    const c = centerCounts[i] ?? 0;
    tCenters += c;
    tSI  += c * (getVal(r, "siArmedCount",    "si_armed_count")    + getVal(r, "siUnarmedCount",    "si_unarmed_count"));
    tHC  += c * (getVal(r, "hcArmedCount",    "hc_armed_count")    + getVal(r, "hcUnarmedCount",    "hc_unarmed_count"));
    tC   += c * (getVal(r, "constArmedCount", "const_armed_count") + getVal(r, "constUnarmedCount", "const_unarmed_count"));
    tAx  += c * (getVal(r, "auxArmedCount",   "aux_armed_count")   + getVal(r, "auxUnarmedCount",   "aux_unarmed_count"));
    tPAC += c * getPAC(r);
  }

  const totalForce = tSI + tHC + tC + tAx;

  return (
    <div
      className="rounded-2xl overflow-hidden"
      style={{
        background: "rgba(255,255,255,0.92)",
        border: `1px solid ${sens.color}30`,
        boxShadow: `0 2px 20px ${sens.color}10, 0 1px 4px rgba(0,0,0,0.06)`,
      }}
    >
      {/* Header */}
      <div
        className="px-5 py-4 flex flex-wrap items-center gap-3 cursor-pointer select-none"
        style={{
          background: `linear-gradient(135deg, ${sens.bg} 0%, rgba(255,255,255,0.8) 100%)`,
          borderBottom: `1px solid ${sens.color}20`,
        }}
        onClick={() => setExpanded((p) => !p)}
      >
        {/* Badge */}
        <span
          className="px-3 py-1.5 rounded-xl text-white text-xs font-black tracking-wide shrink-0"
          style={{ background: sens.color, letterSpacing: "0.05em" }}
        >
          {sens.key}
        </span>

        <div className="flex-1 min-w-0">
          <div className="font-bold text-sm" style={{ color: "#3D1A00" }}>
            {sens.hi} श्रेणी
          </div>
          <div className="flex items-center gap-2 mt-0.5 flex-wrap">
            <span className="text-xs" style={{ color: "#8B5E2A" }}>
              {filledCount}/15 मानक
            </span>
            <span className="text-xs" style={{ color: "#8B5E2A" }}>·</span>
            <span className="text-xs font-bold" style={{ color: sens.color }}>
              {tCenters} केन्द्र
            </span>
            {isSet && totalForce > 0 && (
              <>
                <span className="text-xs" style={{ color: "#8B5E2A" }}>·</span>
                <span className="text-xs font-bold" style={{ color: "#2D6A1E" }}>
                  {totalForce} कुल बल
                </span>
              </>
            )}
          </div>
        </div>

        <div className="flex items-center gap-2 shrink-0">
          {/* Status pill */}
          <div
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-bold"
            style={{
              background: isSet ? "rgba(45,106,30,0.08)" : "rgba(192,57,43,0.07)",
              border: `1px solid ${isSet ? "rgba(45,106,30,0.25)" : "rgba(192,57,43,0.2)"}`,
              color: isSet ? "#2D6A1E" : "#C0392B",
            }}
          >
            {isSet ? <CheckCircle2 size={11} /> : <Clock size={11} />}
            {isSet ? "सेट" : "अधूरा"}
          </div>

          {/* Chevron */}
          <div
            className="transition-transform duration-200"
            style={{ transform: expanded ? "rotate(90deg)" : "rotate(0deg)" }}
          >
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M6 4l4 4-4 4" stroke={sens.color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </div>
        </div>
      </div>

      {/* Summary stat chips */}
      {isSet && expanded && (
        <div
          className="px-5 py-2.5 flex flex-wrap gap-2"
          style={{
            background: `${sens.color}06`,
            borderBottom: `1px solid ${sens.color}15`,
          }}
        >
          <StatChip label="केन्द्र" value={tCenters} color="#6B4226" />
          <StatChip label="SI" value={tSI} color={sens.color} />
          <StatChip label="HC" value={tHC} color={sens.color} />
          <StatChip label="Const." value={tC} color={sens.color} />
          <StatChip label="Aux." value={tAx} color="#A04000" />
          {tPAC > 0 && <StatChip label="PAC" value={fmtPac(tPAC)} color="#00695C" />}
          <StatChip label="कुल बल" value={totalForce} color="#2D6A1E" bold />
        </div>
      )}

      {/* Table / empty */}
      {expanded && (
        !isSet
          ? <EmptyState sens={sens} />
          : <ReportTable sens={sens} ruleFor={ruleFor} centerCounts={centerCounts} />
      )}
    </div>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  REPORT TABLE
// ═════════════════════════════════════════════════════════════════════════════
function ReportTable({ sens, ruleFor, centerCounts }) {
  const { rows, totals: T } = computeRows(ruleFor, centerCounts);

  const bL = { borderLeft: `2px solid ${sens.color}25` };
  const bR = { borderRight: `2px solid ${sens.color}25` };

  const TH = ({ ch, left = false, sx = {} }) => (
    <th
      className="text-[9.5px] font-bold px-2 py-2.5 leading-tight whitespace-pre-line"
      style={{
        color: "#5C3317",
        textAlign: left ? "left" : "center",
        background: `${sens.color}0A`,
        ...sx,
      }}
    >
      {ch}
    </th>
  );

  const TD = ({ ch, left = false, bold = false, clr, sx = {} }) => (
    <td
      className="px-2 py-[5px] text-[11px] leading-tight"
      style={{
        textAlign: left ? "left" : "center",
        fontWeight: bold ? 700 : 400,
        color: clr ?? (bold ? "#3D1A00" : "rgba(74,48,0,0.75)"),
        ...sx,
      }}
    >
      {ch}
    </td>
  );

  const Nv = ({ v, sx = {} }) => (
    <td
      className="px-2 py-[5px] text-[11px] text-center leading-tight"
      style={{
        fontWeight: v > 0 ? 700 : 400,
        color: v > 0 ? "#3D1A00" : "rgba(170,120,68,0.3)",
        ...sx,
      }}
    >
      {v > 0 ? v : "—"}
    </td>
  );

  return (
    <div className="overflow-x-auto">
      <table
        className="w-full border-collapse"
        style={{ minWidth: 940, borderTop: `1px solid ${sens.color}15` }}
      >
        <thead>
          {/* Group header row */}
          <tr>
            <TH ch="" />
            <TH ch="" left />
            <TH ch="" />
            <th
              colSpan={5}
              className="text-[9px] font-extrabold px-2 py-2 text-center tracking-wide"
              style={{ ...bL, ...bR, color: sens.color, background: `${sens.color}08` }}
            >
              मानक (Scale)
            </th>
            <th
              colSpan={9}
              className="text-[9px] font-extrabold px-2 py-2 text-center tracking-wide"
              style={{ ...bL, color: sens.color, background: `${sens.color}08` }}
            >
              मानक के अनुसार व्यवस्थापित पुलिस बल (कुल)
            </th>
          </tr>

          {/* Column headers */}
          <tr>
            <TH ch={"क्र.\nस."} sx={{ width: 32 }} />
            <TH ch={"मतदान केन्द्र प्रकार"} left sx={{ minWidth: 110 }} />
            <TH ch={"केन्द्र\nसंख्या"} sx={{ minWidth: 52 }} />
            <TH ch="SI"        sx={{ ...bL, minWidth: 32 }} />
            <TH ch="HC"        sx={{ minWidth: 32 }} />
            <TH ch="Const."    sx={{ minWidth: 38 }} />
            <TH ch={"Aux.\nForce"} sx={{ minWidth: 42 }} />
            <TH ch={"PAC\n(sec.)"} sx={{ ...bR, minWidth: 46 }} />
            <TH ch={"SI\nसश°"}    sx={{ ...bL, minWidth: 38 }} />
            <TH ch="HC"            sx={{ minWidth: 38 }} />
            <TH ch={"HC\nसश°"}    sx={{ minWidth: 40 }} />
            <TH ch={"HC\nनिः°"}   sx={{ minWidth: 40 }} />
            <TH ch="Const."        sx={{ minWidth: 44 }} />
            <TH ch={"Const.\nसश°"} sx={{ minWidth: 50 }} />
            <TH ch={"Const.\nनिः°"} sx={{ minWidth: 50 }} />
            <TH ch={"Aux.\nForce"} sx={{ minWidth: 46 }} />
            <TH ch={"PAC\n(sec.)"} sx={{ minWidth: 46 }} />
          </tr>
        </thead>

        <tbody>
          {rows.map(({ i, label, c, si_a, si_u, hc_a, hc_u, c_a, c_u, ax_a, ax_u, pac }, idx) => {
            const isEven = idx % 2 === 1;
            const hC = c > 0;
            return (
              <tr
                key={i}
                className="transition-colors"
                style={{
                  background: isEven ? "rgba(253,240,216,0.45)" : "white",
                  borderBottom: "1px solid rgba(180,120,60,0.1)",
                }}
                onMouseEnter={(e) => { e.currentTarget.style.background = `${sens.color}08`; }}
                onMouseLeave={(e) => { e.currentTarget.style.background = isEven ? "rgba(253,240,216,0.45)" : "white"; }}
              >
                <TD
                  ch={i < 15 ? i : "15+"}
                  bold
                  clr="rgba(139,94,42,0.55)"
                />
                <TD ch={label} left />
                <TD
                  ch={hC ? c : "—"}
                  bold={hC}
                  clr={hC ? sens.color : "rgba(170,120,68,0.35)"}
                />
                {/* Scale */}
                <Nv v={si_a + si_u}  sx={bL} />
                <Nv v={hc_a + hc_u} />
                <Nv v={c_a  + c_u} />
                <Nv v={ax_a + ax_u} />
                <td
                  className="px-2 py-[5px] text-[11px] text-center"
                  style={{
                    ...bR,
                    fontWeight: pac > 0 ? 700 : 400,
                    color: pac > 0 ? "#3D1A00" : "rgba(170,120,68,0.3)",
                  }}
                >
                  {pac > 0 ? fmtPac(pac) : "—"}
                </td>
                {/* Deployed */}
                <Nv v={c * si_a}                sx={bL} />
                <Nv v={c * (hc_a + hc_u)} />
                <Nv v={c * hc_a} />
                <Nv v={c * hc_u} />
                <Nv v={c * (c_a + c_u)} />
                <Nv v={c * c_a} />
                <Nv v={c * c_u} />
                <Nv v={c * (ax_a + ax_u)} />
                <td
                  className="px-2 py-[5px] text-[11px] text-center"
                  style={{
                    fontWeight: (c * pac) > 0 ? 700 : 400,
                    color: (c * pac) > 0 ? "#3D1A00" : "rgba(170,120,68,0.3)",
                  }}
                >
                  {(c * pac) > 0 ? fmtPac(c * pac) : "—"}
                </td>
              </tr>
            );
          })}

          {/* Total row */}
          <tr
            style={{
              background: `${sens.color}10`,
              borderTop: `2px solid ${sens.color}30`,
            }}
          >
            <td />
            <td className="px-2 py-2.5 text-xs font-black text-left" style={{ color: "#3D1A00" }}>
              योग
            </td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: sens.color }}>
              {T.tCenters}
            </td>
            {/* Scale totals */}
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ ...bL, color: "#3D1A00" }}>{T.mSI_A + T.mSI_U}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.mHC_A + T.mHC_U}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.mC_A + T.mC_U}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.mAx_A + T.mAx_U}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ ...bR, color: "#3D1A00" }}>{fmtPac(T.mPAC)}</td>
            {/* Deployed totals */}
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ ...bL, color: "#3D1A00" }}>{T.tSI_A}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.tHC_A + T.tHC_U}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.tHC_A}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.tHC_U}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.tC_A + T.tC_U}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.tC_A}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.tC_U}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{T.tAx_A + T.tAx_U}</td>
            <td className="px-2 py-2.5 text-xs font-black text-center" style={{ color: "#3D1A00" }}>{fmtPac(T.tPAC)}</td>
          </tr>
        </tbody>
      </table>
    </div>
  );
}

// ── Small helpers ─────────────────────────────────────────────────────────────
function StatChip({ label, value, color, bold = false }) {
  return (
    <div
      className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-xl text-xs shrink-0"
      style={{
        background: `${color}10`,
        border: `1px solid ${color}25`,
      }}
    >
      <span style={{ color: `${color}99`, fontWeight: 600 }}>{label}</span>
      <span style={{ color, fontWeight: bold ? 900 : 700 }}>{value}</span>
    </div>
  );
}

function EmptyState({ sens }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 gap-3">
      <div
        className="w-14 h-14 rounded-2xl flex items-center justify-center"
        style={{ background: `${sens.color}10` }}
      >
        <BarChart3 size={26} style={{ color: `${sens.color}45` }} />
      </div>
      <p className="text-sm font-semibold text-center" style={{ color: "#8B5E2A" }}>
        {sens.hi} ({sens.key}) के लिए कोई मानक सेट नहीं है।
      </p>
      <p className="text-xs" style={{ color: "rgba(139,94,42,0.6)" }}>
        डैशबोर्ड से मानक सेट करें।
      </p>
    </div>
  );
}

function LoadingSkeleton() {
  return (
    <div className="space-y-5">
      <style>{`
        .manak-shimmer {
          background: linear-gradient(to right, #f0dfc0 8%, #fdf6ec 22%, #f0dfc0 36%);
          background-size: 800px 104px;
          animation: manak-shimmer 1.5s ease-in-out infinite;
        }
        @keyframes manak-shimmer {
          0%   { background-position: -468px 0; }
          100% { background-position:  468px 0; }
        }
      `}</style>
      {[1, 2, 3, 4].map((i) => (
        <div
          key={i}
          className="rounded-2xl overflow-hidden"
          style={{ border: "1px solid rgba(180,120,60,0.2)" }}
        >
          <div className="h-[72px] manak-shimmer" />
          <div className="h-10 manak-shimmer opacity-70" />
          <div className="h-52 manak-shimmer opacity-40" />
        </div>
      ))}
    </div>
  );
}