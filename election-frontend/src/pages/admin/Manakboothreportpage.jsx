/**
 * ManakBoothReportPage.jsx
 *
 * Dependencies:
 *   npm install react-hot-toast lucide-react
 *
 * Tailwind CSS required (via CDN or configured).
 * CSS variables (--bg, --primary, etc.) must be defined globally — see globals.css.
 *
 * Print: A4 Landscape, all 4 sensitivity tables, no column cutoff.
 */

import { useState, useEffect, useCallback } from "react";
import toast, { Toaster } from "react-hot-toast";
import {
  RefreshCw, CheckCircle2, Clock,
  LayoutGrid, TableProperties, BarChart3, Shield, Printer,
  ArrowLeft,
} from "lucide-react";
import { useNavigate } from "react-router-dom";

// ── Print styles injected into <head> ────────────────────────────────────────
const PRINT_STYLES = `
@media print {
  @page {
    size: A4 landscape;
    margin: 8mm 6mm;
  }

  /* Hide everything not meant for print */
  .no-print { display: none !important; }

  /* Reset body */
  body {
    background: #fff !important;
    color: #000 !important;
    font-family: 'Tiro Devanagari Hindi', Georgia, serif !important;
  }

  /* Page wrapper */
  .print-root {
    padding: 0 !important;
    margin: 0 !important;
    max-width: 100% !important;
  }

  /* Each sensitivity block starts on a new page */
  .sens-block {
    page-break-before: always;
    break-before: page;
    border: none !important;
    box-shadow: none !important;
    border-radius: 0 !important;
    overflow: visible !important;
    width: 100% !important;
  }
  .sens-block:first-child {
    page-break-before: avoid;
    break-before: avoid;
  }

  /* Block header */
  .sens-header {
    padding: 4mm 3mm 2mm 3mm !important;
    border-bottom: 1pt solid #ccc !important;
    background: #f9f4e8 !important;
  }

  /* Hide summary chips & status pill in print */
  .sens-chips { display: none !important; }
  .status-pill { display: none !important; }

  /* Table full width, no overflow */
  .report-table-wrap {
    overflow: visible !important;
    width: 100% !important;
  }

  table {
    width: 100% !important;
    min-width: 0 !important;
    table-layout: fixed !important;
    border-collapse: collapse !important;
    font-size: 7.5pt !important;
  }

  th, td {
    padding: 2px 3px !important;
    font-size: 7.5pt !important;
    border: 0.3pt solid #aaa !important;
    word-break: break-word !important;
    white-space: normal !important;
  }

  thead tr:first-child th {
    font-size: 7pt !important;
  }

  tfoot td {
    font-size: 7.5pt !important;
    font-weight: 700 !important;
  }

  /* Print title shown only during print */
  .print-title {
    display: block !important;
    font-size: 9pt;
    font-weight: 700;
    text-align: center;
    margin-bottom: 3mm;
    color: #000;
  }

  /* Make sensitivity badge visible + styled */
  .sens-badge {
    display: inline-block !important;
    padding: 1mm 3mm !important;
    border-radius: 2mm !important;
    font-weight: 700 !important;
    font-size: 8pt !important;
    color: #fff !important;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }

  /* Force background colours to print */
  * {
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }

  /* Remove hover/transition effects */
  tr { transition: none !important; }
}

/* Screen only — hide print-title */
@media screen {
  .print-title { display: none; }
}
`;

// ── Inject print styles once ──────────────────────────────────────────────────
if (typeof document !== "undefined") {
  const id = "__manak_print_styles__";
  if (!document.getElementById(id)) {
    const style = document.createElement("style");
    style.id = id;
    style.textContent = PRINT_STYLES;
    document.head.appendChild(style);
  }
}

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
  { key: "A++", hi: "अति-अति संवेदनशील", color: "#6C3483", bg: "#f3e5f5" },
  { key: "A", hi: "अति संवेदनशील", color: "#C0392B", bg: "#fdecea" },
  { key: "B", hi: "संवेदनशील", color: "#E67E22", bg: "#fff3e0" },
  { key: "C", hi: "सामान्य", color: "#1A5276", bg: "#e3f2fd" },
];

// ── Value helpers ─────────────────────────────────────────────────────────────
const getVal = (r, key, alt) =>
  Number(r?.[key] ?? (alt ? r?.[alt] : null) ?? 0);
const getPAC = (r) => Number(r?.pacCount ?? r?.pac_count ?? 0);
const fmtPac = (v) =>
  v === 0 ? "0" : v % 1 === 0 ? `${Math.round(v)}` : v.toFixed(1);

// ── Compute all row data + totals for one sensitivity ────────────────────────
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
    mC_A += c_a; mC_U += c_u;
    mAx_A += ax_a; mAx_U += ax_u;
    mPAC += pac;
    tSI_A += c * si_a;
    tHC_A += c * hc_a; tHC_U += c * hc_u;
    tC_A += c * c_a; tC_U += c * c_u;
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
export default function ManakBoothReportPage() {
  const [rules, setRules] = useState({ "A++": [], A: [], B: [], C: [] });
  const [centerCounts, setCenterCounts] = useState({ "A++": {}, A: {}, B: {}, C: {} });
  const [districtName, setDistrictName] = useState("");
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState("all");

  const nav = useNavigate()

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      const rulesRes = await apiFetch("/admin/booth-rules");
      
      const rulesData = rulesRes?.data ?? {};
      const newRules = { "A++": [], A: [], B: [], C: [] };
      for (const s of ["A++", "A", "B", "C"]) {
        newRules[s] = (rulesData[s] ?? []).map((e) => ({ ...e }));
      }
      setRules(newRules);

      let newCounts = { "A++": {}, A: {}, B: {}, C: {} };
      try {
        const ccRes = await apiFetch("/admin/booth-rules/center-counts-by-type");
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
          const centers = centersRes?.data ?? [];
          const counts = { "A++": {}, A: {}, B: {}, C: {} };
          for (const c of centers) {
            const ct = c.centerType ?? "C";
            const bc = Math.min(Math.max(Number(c.boothCount ?? 1), 1), 15);
            if (counts[ct]) counts[ct][bc] = (counts[ct][bc] ?? 0) + 1;
          }
          newCounts = counts;
        } catch { }
      }
      setCenterCounts(newCounts);

      try {
        const profileRes = await apiFetch("/auth/me");
        setDistrictName(profileRes?.data?.district ?? "");
      } catch { }
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

  const handlePrint = () => {
    // Switch to "all" tab so all blocks are visible, then print
    setActiveTab("all");
    setTimeout(() => window.print(), 120);
  };

  const tabs = [
    { key: "all", label: "सभी", icon: <LayoutGrid size={13} /> },
    ...SENSITIVITIES.map((s) => ({
      key: s.key,
      label: `${s.key} — ${s.hi.split(" ")[0]}`,
      color: s.color,
    })),
  ];

  return (
    <div className="min-h-screen"
      style={{
        background: "var(--bg,#FDF6E3)", color: "var(--dark,#4A3000)",
        fontFamily: "'Tiro Devanagari Hindi', Georgia, serif"
      }}>
      <Toaster position="top-right"
        toastOptions={{ style: { fontFamily: "inherit", fontSize: 13, borderRadius: 10 } }} />

      {/* ── AppBar (hidden in print) ── */}
      <div className="no-print sticky top-0 z-50 shadow-lg"
        style={{ background: "var(--primary,#8B6914)", color: "white" }}>
        <div className="px-4 md:px-6 py-3 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0">
            <button onClick={() => nav("/")} className="p-1.5 rounded-lg hover:bg-white/10">
              <ArrowLeft size={18} className="text-white" />
            </button>
            <div className="flex items-center justify-center w-9 h-9 rounded-xl shrink-0"
              style={{ background: "rgba(255,255,255,0.15)" }}>

              <TableProperties size={18} />
            </div>
            <div className="min-w-0">

              <div className="font-extrabold text-base md:text-lg leading-tight truncate">
                मानक बूथ रिपोर्ट
              </div>
              <div className="text-xs opacity-70 truncate">
                बूथ-वार पुलिस व्यवस्थापन{districtName ? ` — ${districtName}` : ""}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <button onClick={loadData} disabled={loading}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold transition-all hover:bg-white/20"
              style={{ background: "rgba(255,255,255,0.12)", border: "1px solid rgba(255,255,255,0.2)" }}>
              <RefreshCw size={13} className={loading ? "animate-spin" : ""} />
              <span className="hidden sm:inline">रिफ्रेश</span>
            </button>

            {/* Print button replaces PDF download */}
            <button onClick={handlePrint} disabled={loading}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold transition-all hover:bg-white/20 disabled:opacity-50"
              style={{ background: "rgba(255,255,255,0.12)", border: "1px solid rgba(255,255,255,0.2)" }}>
              <Printer size={13} />
              <span className="hidden sm:inline">प्रिंट करें</span>
            </button>
          </div>
        </div>

        {/* Tab bar */}
        <div className="flex overflow-x-auto scrollbar-none"
          style={{ borderTop: "1px solid rgba(255,255,255,0.15)" }}>
          {tabs.map((tab) => (
            <button key={tab.key} onClick={() => setActiveTab(tab.key)}
              className="flex items-center gap-1.5 px-4 py-2.5 text-xs font-semibold whitespace-nowrap transition-all shrink-0"
              style={{
                color: activeTab === tab.key ? "white" : "rgba(255,255,255,0.55)",
                borderBottom: activeTab === tab.key
                  ? "2.5px solid white" : "2.5px solid transparent",
                background: activeTab === tab.key ? "rgba(255,255,255,0.1)" : "transparent",
              }}>
              {tab.icon ?? <Shield size={13} />}
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* ── Body ── */}
      <div className="p-4 md:p-6 max-w-screen-2xl mx-auto print-root">
        {/* Print-only master title */}
        <div className="print-title">
          त्रिस्तरीय पंचायत सामान्य निर्वाचन — बूथ एवं कानून व्यवस्था ड्यूटी हेतु पुलिस व्यवस्थापन का विवरण
          {districtName ? ` | जनपद: ${districtName}` : ""}
        </div>

        {loading ? (
          <LoadingSkeleton />
        ) : activeTab === "all" ? (
          <div className="space-y-6">
            {SENSITIVITIES.map((s) => (
              <SensBlock key={s.key} sens={s}
                ruleFor={(bc) => ruleFor(s.key, bc)}
                centerCounts={centerCounts[s.key] ?? {}}
                filledCount={filledCount(s.key)} />
            ))}
          </div>
        ) : (
          SENSITIVITIES.filter((s) => s.key === activeTab).map((s) => (
            <SensBlock key={s.key} sens={s}
              ruleFor={(bc) => ruleFor(s.key, bc)}
              centerCounts={centerCounts[s.key] ?? {}}
              filledCount={filledCount(s.key)} />
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
  let tCenters = 0, tSI = 0, tHC = 0, tC = 0, tAx = 0, tPAC = 0;
  for (let i = 1; i <= 15; i++) {
    const r = ruleFor(i);
    const c = centerCounts[i] ?? 0;
    tCenters += c;
    tSI += c * (getVal(r, "siArmedCount", "si_armed_count") + getVal(r, "siUnarmedCount", "si_unarmed_count"));
    tHC += c * (getVal(r, "hcArmedCount", "hc_armed_count") + getVal(r, "hcUnarmedCount", "hc_unarmed_count"));
    tC += c * (getVal(r, "constArmedCount", "const_armed_count") + getVal(r, "constUnarmedCount", "const_unarmed_count"));
    tAx += c * (getVal(r, "auxArmedCount", "aux_armed_count") + getVal(r, "auxUnarmedCount", "aux_unarmed_count"));
    tPAC += c * getPAC(r);
  }

  return (
    <div className="sens-block rounded-2xl overflow-hidden"
      style={{
        background: "white", border: "1px solid rgba(212,168,67,0.3)",
        boxShadow: `0 4px 20px ${sens.color}14`
      }}>
      {/* Header */}
      <div className="sens-header px-4 md:px-5 py-3 flex flex-wrap items-center gap-3"
        style={{ background: sens.bg, borderBottom: "1px solid rgba(212,168,67,0.2)" }}>
        <span className="sens-badge px-3 py-1 rounded-lg text-white text-sm font-black"
          style={{ background: sens.color }}>{sens.key}</span>
        <div className="flex-1 min-w-0">
          <div className="font-extrabold text-sm" style={{ color: "var(--dark,#4A3000)" }}>
            {sens.hi} श्रेणी
          </div>
          <div className="text-xs mt-0.5" style={{ color: "var(--subtle,#AA8844)" }}>
            {filledCount}/15 मानक सेट
            <span className="mx-1.5">•</span>
            <span style={{ color: sens.color, fontWeight: 700 }}>{tCenters} केन्द्र</span>
          </div>
        </div>
        <div className="status-pill">
          <StatusPill isSet={isSet} />
        </div>
      </div>

      {/* Summary chips — screen only */}
      {isSet && (
        <div className="sens-chips no-print px-4 md:px-5 py-2 flex flex-wrap gap-2"
          style={{ background: `${sens.color}08`, borderBottom: "1px solid rgba(212,168,67,0.15)" }}>
          <Chip label="केन्द्र" value={tCenters} color="#555555" />
          <Chip label="SI" value={tSI} color={sens.color} />
          <Chip label="HC" value={tHC} color={sens.color} />
          <Chip label="Const." value={tC} color={sens.color} />
          <Chip label="Aux." value={tAx} color="#E65100" />
          {tPAC > 0 && <Chip label="PAC" value={fmtPac(tPAC)} color="#00695C" />}
          <Chip label="कुल बल" value={tSI + tHC + tC + tAx} color="#2D6A1E" bold />
        </div>
      )}

      {/* Table / empty */}
      {!isSet
        ? <EmptyState sens={sens} />
        : <ReportTable sens={sens} ruleFor={ruleFor} centerCounts={centerCounts} />}
    </div>
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  REPORT TABLE  (screen — 17 cols, same structure as print)
// ═════════════════════════════════════════════════════════════════════════════
function ReportTable({ sens, ruleFor, centerCounts }) {
  const { rows, totals: T } = computeRows(ruleFor, centerCounts);

  const bL = { borderLeft: `2px solid ${sens.color}40` };
  const bR = { borderRight: `2px solid ${sens.color}40` };

  /* ── micro-components ── */
  const TH = ({ ch, left = false, sx = {} }) => (
    <th className="text-[9.5px] font-bold px-2 py-2 leading-tight whitespace-pre-line"
      style={{ color: "var(--dark,#4A3000)", textAlign: left ? "left" : "center", ...sx }}>
      {ch}
    </th>
  );

  const TD = ({ ch, left = false, bold = false, clr, sx = {} }) => (
    <td className="px-2 py-[5px] text-[11px] leading-tight"
      style={{
        textAlign: left ? "left" : "center",
        fontWeight: bold ? 700 : 400,
        color: clr ?? (bold ? "var(--dark,#4A3000)" : "rgba(74,48,0,0.8)"),
        ...sx
      }}>
      {ch}
    </td>
  );

  const Nv = ({ v, sx = {} }) => (
    <td className="px-2 py-[5px] text-[11px] text-center leading-tight"
      style={{
        fontWeight: v > 0 ? 700 : 400,
        color: v > 0 ? "var(--dark,#4A3000)" : "rgba(170,136,68,0.35)",
        ...sx
      }}>
      {v}
    </td>
  );

  return (
    <div className="report-table-wrap overflow-x-auto">
      <table className="w-full border-collapse" style={{ minWidth: 940, borderTop: "1px solid rgba(212,168,67,0.2)" }}>
        <thead>
          {/* Group row */}
          <tr style={{ background: `${sens.color}12` }}>
            <TH ch="" />
            <TH ch="" left />
            <TH ch="" />
            {/* Scale group */}
            <th colSpan={5} className="text-[9px] font-bold px-2 py-1.5 text-center"
              style={{ ...bL, ...bR, color: sens.color }}>
              मानक (Scale)
            </th>
            {/* Deployed group */}
            <th colSpan={9} className="text-[9px] font-bold px-2 py-1.5 text-center"
              style={{ ...bL, color: sens.color }}>
              मानक के अनुसार व्यवस्थापित पुलिस बल (कुल)
            </th>
          </tr>
          {/* Column headers */}
          <tr style={{ background: "var(--surface,#F5E6C8)" }}>
            <TH ch={"क्र.\nस."} sx={{ width: 32 }} />
            <TH ch={"मतदान\nकेन्द्र का प्रकार"} left sx={{ minWidth: 100 }} />
            <TH ch={"पोलिंग\nसेन्टर\nसंख्या"} sx={{ minWidth: 50 }} />
            {/* Scale */}
            <TH ch="SI" sx={{ ...bL, minWidth: 32 }} />
            <TH ch="HC" sx={{ minWidth: 32 }} />
            <TH ch="Const." sx={{ minWidth: 36 }} />
            <TH ch={"Aux.\nForce"} sx={{ minWidth: 40 }} />
            <TH ch={"PAC\n(sec.)"} sx={{ ...bR, minWidth: 44 }} />
            {/* Deployed */}
            <TH ch={"SI\nसश°"} sx={{ ...bL, minWidth: 38 }} />
            <TH ch="HC" sx={{ minWidth: 38 }} />
            <TH ch={"HC\nसश°"} sx={{ minWidth: 40 }} />
            <TH ch={"HC\nनिः°"} sx={{ minWidth: 40 }} />
            <TH ch="Const." sx={{ minWidth: 42 }} />
            <TH ch={"Const.\nसश°"} sx={{ minWidth: 48 }} />
            <TH ch={"Const.\nनिः°"} sx={{ minWidth: 48 }} />
            <TH ch={"Aux.\nForce"} sx={{ minWidth: 46 }} />
            <TH ch={"PAC\n(sec.)"} sx={{ minWidth: 44 }} />
          </tr>
        </thead>
        <tbody>
          {rows.map(({ i, label, c, si_a, si_u, hc_a, hc_u, c_a, c_u, ax_a, ax_u, pac }, idx) => {
            const isEven = idx % 2 === 1;
            const hC = c > 0;
            return (
              <tr key={i}
                className="transition-colors hover:bg-amber-50/50"
                style={{
                  background: isEven ? "rgba(253,246,227,0.5)" : "white",
                  borderBottom: "1px solid rgba(212,168,67,0.18)"
                }}>
                <TD ch={i < 15 ? i : "15+"} clr="var(--subtle,#AA8844)" bold />
                <TD ch={label} left />
                <TD ch={hC ? c : "—"} bold={hC} clr={hC ? sens.color : "rgba(170,136,68,0.4)"} />
                {/* Scale */}
                <Nv v={si_a + si_u} sx={bL} />
                <Nv v={hc_a + hc_u} />
                <Nv v={c_a + c_u} />
                <Nv v={ax_a + ax_u} />
                <td className="px-2 py-[5px] text-[11px] text-center"
                  style={{
                    ...bR,
                    fontWeight: pac > 0 ? 700 : 400,
                    color: pac > 0 ? "var(--dark,#4A3000)" : "rgba(170,136,68,0.35)"
                  }}>
                  {fmtPac(pac)}
                </td>
                {/* Deployed */}
                <Nv v={c * si_a} sx={bL} />
                <Nv v={c * (hc_a + hc_u)} />
                <Nv v={c * hc_a} />
                <Nv v={c * hc_u} />
                <Nv v={c * (c_a + c_u)} />
                <Nv v={c * c_a} />
                <Nv v={c * c_u} />
                <Nv v={c * (ax_a + ax_u)} />
                <td className="px-2 py-[5px] text-[11px] text-center"
                  style={{
                    fontWeight: (c * pac) > 0 ? 700 : 400,
                    color: (c * pac) > 0 ? "var(--dark,#4A3000)" : "rgba(170,136,68,0.35)"
                  }}>
                  {fmtPac(c * pac)}
                </td>
              </tr>
            );
          })}
          {/* Total row — inside tbody so it prints ONLY ONCE at the actual end, not repeated on every page */}
          <tr style={{ background: `${sens.color}12`, borderTop: `2px solid ${sens.color}40` }}>
            <td />
            <td className="px-2 py-2 text-xs font-black text-left" style={{ color: "var(--dark,#4A3000)" }}>योग</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: sens.color }}>{T.tCenters}</td>
            {/* Scale */}
            <td className="px-2 py-2 text-xs font-black text-center" style={{ ...bL, color: "var(--dark,#4A3000)" }}>{T.mSI_A + T.mSI_U}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.mHC_A + T.mHC_U}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.mC_A + T.mC_U}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.mAx_A + T.mAx_U}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ ...bR, color: "var(--dark,#4A3000)" }}>{fmtPac(T.mPAC)}</td>
            {/* Deployed */}
            <td className="px-2 py-2 text-xs font-black text-center" style={{ ...bL, color: "var(--dark,#4A3000)" }}>{T.tSI_A}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.tHC_A + T.tHC_U}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.tHC_A}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.tHC_U}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.tC_A + T.tC_U}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.tC_A}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.tC_U}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{T.tAx_A + T.tAx_U}</td>
            <td className="px-2 py-2 text-xs font-black text-center" style={{ color: "var(--dark,#4A3000)" }}>{fmtPac(T.tPAC)}</td>
          </tr>
        </tbody>
      </table>
    </div>
  );
}

// ── Small helpers ─────────────────────────────────────────────────────────────
function Chip({ label, value, color, bold = false }) {
  return (
    <div className="flex items-center gap-1 px-2 py-1 rounded-lg text-xs shrink-0"
      style={{ background: `${color}12`, border: `1px solid ${color}30` }}>
      <span style={{ color: `${color}cc`, fontWeight: 600 }}>{label}:</span>
      <span style={{ color, fontWeight: bold ? 900 : 800 }}>{value}</span>
    </div>
  );
}

function StatusPill({ isSet }) {
  return (
    <div className="flex items-center gap-1 px-3 py-1 rounded-full text-xs font-bold shrink-0"
      style={{
        background: isSet ? "rgba(45,106,30,0.1)" : "rgba(192,57,43,0.08)",
        border: `1px solid ${isSet ? "rgba(45,106,30,0.3)" : "rgba(192,57,43,0.2)"}`,
        color: isSet ? "#2D6A1E" : "#C0392B",
      }}>
      {isSet ? <CheckCircle2 size={11} /> : <Clock size={11} />}
      {isSet ? "सेट" : "अधूरा"}
    </div>
  );
}

function EmptyState({ sens }) {
  return (
    <div className="flex flex-col items-center justify-center py-14 gap-3">
      <div className="w-14 h-14 rounded-2xl flex items-center justify-center"
        style={{ background: `${sens.color}12` }}>
        <BarChart3 size={28} style={{ color: `${sens.color}50` }} />
      </div>
      <p className="text-sm font-semibold text-center" style={{ color: "var(--subtle,#AA8844)" }}>
        {sens.hi} ({sens.key}) के लिए कोई मानक सेट नहीं है।
      </p>
      <p className="text-xs" style={{ color: "var(--subtle,#AA8844)" }}>
        डैशबोर्ड से मानक सेट करें।
      </p>
    </div>
  );
}

function LoadingSkeleton() {
  return (
    <div className="space-y-6">
      <style>{`
        .shimmer {
          background: linear-gradient(to right,#F5E6C8 8%,#FDF6E3 18%,#F5E6C8 33%);
          background-size: 800px 104px;
          animation: shimmer 1.4s linear infinite;
        }
        @keyframes shimmer {
          0%   { background-position: -468px 0; }
          100% { background-position:  468px 0; }
        }
      `}</style>
      {[1, 2, 3, 4].map((i) => (
        <div key={i} className="rounded-2xl overflow-hidden"
          style={{ border: "1px solid rgba(212,168,67,0.25)" }}>
          <div className="h-16 shimmer" />
          <div className="h-10 shimmer opacity-60" />
          <div className="h-64 shimmer opacity-40" />
        </div>
      ))}
    </div>
  );
}