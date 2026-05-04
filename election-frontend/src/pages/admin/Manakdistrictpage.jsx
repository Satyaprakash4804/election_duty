import { useState, useEffect, useRef, useCallback } from "react";
import {
  Shield, Car, Building2, PlusCircle, Save, RefreshCw, Trash2,
  Zap, Users, ChevronRight, Edit3, X, Check, AlertTriangle,
  Eye, PersonStanding, Plus, Loader2, Bus, StickyNote,
  Search, CheckCircle2, Info, Gavel, ShieldCheck, ArrowLeft,
  PersonStandingIcon, UserMinus, BadgeCheck, Phone, Hash,
  Layers, BarChart3, ClipboardList, Wand2, DeleteIcon,
  RotateCcw, Vote, TreePine, Settings2, Home, Siren,
  AlertCircle, TrendingUp, Activity,
  ChevronLeft
} from "lucide-react";
import { useNavigate } from "react-router-dom";

// ── Palette ───────────────────────────────────────────────────────────────────
const C = {
  bg: "#FDF6E3",
  surface: "#F5E6C8",
  primary: "#8B6914",
  dark: "#4A3000",
  subtle: "#AA8844",
  border: "#D4A843",
  error: "#C0392B",
  success: "#2D6A1E",
  district: "#6C3483",
  custom: "#00796B",
  assign: "#1565C0",
  orange: "#E65100",
};

// ── Mock data ─────────────────────────────────────────────────────────────────
const DUTY_TYPES = [
  { type: "cluster_mobile", labelHi: "क्लस्टर मोबाईल", isDefault: true, icon: "car" },
  { type: "thana_mobile", labelHi: "थाना मोबाईल", isDefault: true, icon: "siren" },
  { type: "thana_reserve", labelHi: "थाना रिजर्व", isDefault: true, icon: "savings" },
  { type: "thana_extra_mobile", labelHi: "थाना अतिरिक्त मोबाईल", isDefault: true, icon: "plus" },
  { type: "sector_pol_mag_mobile", labelHi: "सेक्टर पोल मैग मोबाईल", isDefault: true, icon: "gavel" },
  { type: "zonal_pol_mag_mobile", labelHi: "जोनल पोल मैग मोबाईल", isDefault: true, icon: "tree" },
  { type: "sdm_co_mobile", labelHi: "SDM/CO मोबाईल", isDefault: true, icon: "settings" },
  { type: "chowki_mobile", labelHi: "चौकी मोबाईल", isDefault: true, icon: "home" },
  { type: "barrier_picket", labelHi: "बैरियर/पिकेट", isDefault: true, icon: "block" },
  { type: "evm_security", labelHi: "EVM सुरक्षा", isDefault: true, icon: "vote" },
  { type: "hq_reserve", labelHi: "HQ रिजर्व", isDefault: true, icon: "building" },
];

const MOCK_RULES = {
  cluster_mobile: { siArmedCount: 2, siUnarmedCount: 1, hcArmedCount: 3, hcUnarmedCount: 0, constArmedCount: 8, constUnarmedCount: 4, auxArmedCount: 0, auxUnarmedCount: 0, pacCount: 0, sankhya: 18 },
  thana_mobile: { siArmedCount: 1, siUnarmedCount: 0, hcArmedCount: 2, hcUnarmedCount: 1, constArmedCount: 6, constUnarmedCount: 2, auxArmedCount: 0, auxUnarmedCount: 0, pacCount: 0, sankhya: 12 },
  thana_reserve: { siArmedCount: 1, siUnarmedCount: 1, hcArmedCount: 1, hcUnarmedCount: 0, constArmedCount: 4, constUnarmedCount: 2, auxArmedCount: 0, auxUnarmedCount: 0, pacCount: 0, sankhya: 9 },
  barrier_picket: { siArmedCount: 0, siUnarmedCount: 1, hcArmedCount: 0, hcUnarmedCount: 2, constArmedCount: 0, constUnarmedCount: 6, auxArmedCount: 2, auxUnarmedCount: 0, pacCount: 2, sankhya: 13 },
  evm_security: { siArmedCount: 1, siUnarmedCount: 0, hcArmedCount: 2, hcUnarmedCount: 0, constArmedCount: 5, constUnarmedCount: 0, auxArmedCount: 0, auxUnarmedCount: 0, pacCount: 0, sankhya: 8 },
};

const MOCK_SUMMARY = {
  cluster_mobile: { totalAssigned: 15, batchCount: 3 },
  thana_mobile: { totalAssigned: 12, batchCount: 2 },
  thana_reserve: { totalAssigned: 9, batchCount: 1 },
  evm_security: { totalAssigned: 10, batchCount: 2 },
  hq_reserve: { totalAssigned: 4, batchCount: 1 },
};

const MOCK_STAFF = Array.from({ length: 40 }, (_, i) => ({
  id: i + 1,
  name: ["राम प्रसाद", "सुरेश कुमार", "अजय सिंह", "विकास यादव", "रमेश पटेल", "नरेंद्र मिश्रा", "ललित वर्मा", "दिनेश तिवारी"][i % 8] + ` ${i + 1}`,
  rank: ["SI", "ASI", "Head Constable", "Constable"][i % 4],
  pno: `UP${1000 + i}`,
  thana: ["कोतवाली", "सिविल लाइंस", "ट्रांसपोर्ट नगर", "सहारनपुर"][i % 4],
  mobile: `98765${String(i).padStart(5, "0")}`,
  isArmed: i % 3 === 0,
}));

const MOCK_BATCHES = {
  cluster_mobile: [
    { batchNo: 1, staffCount: 5, busNo: "UP32-1234", note: "Morning shift", staff: MOCK_STAFF.slice(0, 5).map((s, i) => ({ ...s, assignmentId: 100 + i })) },
    { batchNo: 2, staffCount: 5, busNo: "UP32-5678", note: "", staff: MOCK_STAFF.slice(5, 10).map((s, i) => ({ ...s, assignmentId: 200 + i })) },
    { batchNo: 3, staffCount: 5, busNo: "", note: "Reserve", staff: MOCK_STAFF.slice(10, 15).map((s, i) => ({ ...s, assignmentId: 300 + i })) },
  ],
};

// ── Rank color ────────────────────────────────────────────────────────────────
const rankColor = (rank) => ({
  "SP": "#6A1B9A", "ASP": "#1565C0", "DSP": "#1A5276",
  "Inspector": "#2E7D32", "SI": "#558B2F", "ASI": "#8B6914",
  "Head Constable": "#B8860B", "Constable": "#6D4C41",
}[rank] || C.primary);

// ── Icon resolver ─────────────────────────────────────────────────────────────
const DutyIcon = ({ type, size = 20, color }) => {
  const m = {
    car: Car, siren: Siren, savings: BarChart3, plus: PlusCircle, gavel: Gavel,
    tree: TreePine, settings: Settings2, home: Home, block: Shield, vote: Vote, building: Building2
  };
  const Ic = m[type] || ClipboardList;
  return <Ic size={size} color={color} />;
};

// ── Helpers ───────────────────────────────────────────────────────────────────
const hasAny = (r) => r && ["siArmedCount", "siUnarmedCount", "hcArmedCount", "hcUnarmedCount",
  "constArmedCount", "constUnarmedCount", "auxArmedCount", "auxUnarmedCount", "pacCount"]
  .some(k => ((r[k] || 0) > 0));

const totalStaff = (r) => {
  if (!r) return 0;
  return ["siArmedCount", "siUnarmedCount", "hcArmedCount", "hcUnarmedCount",
    "constArmedCount", "constUnarmedCount", "auxArmedCount", "auxUnarmedCount"]
    .reduce((s, k) => s + ((r[k] || 0)), 0);
};

// ── Chip Row ──────────────────────────────────────────────────────────────────
function ChipRow({ rule, color }) {
  const chips = [];
  const pairs = [
    ["SI", "siArmedCount", "siUnarmedCount"],
    ["HC", "hcArmedCount", "hcUnarmedCount"],
    ["Const", "constArmedCount", "constUnarmedCount"],
    ["Aux", "auxArmedCount", "auxUnarmedCount"],
  ];
  pairs.forEach(([label, ak, uk]) => {
    const a = (rule[ak] || 0), u = (rule[uk] || 0);
    if (a + u > 0) chips.push({ label, a, u });
  });
  const pac = rule.pacCount || 0;

  return (
    <div className="flex gap-2 flex-wrap mt-2">
      {chips.map(({ label, a, u }) => (
        <span key={label} style={{ background: `${color}14`, border: `1px solid ${color}44`, color, borderRadius: 6, padding: "2px 8px", fontSize: 11, fontWeight: 700, display: "inline-flex", alignItems: "center", gap: 4 }}>
          {label}:&nbsp;
          {a > 0 && <span style={{ color: "#6A1B9A", fontWeight: 900 }}>⚔{a}</span>}
          {a > 0 && u > 0 && <span style={{ opacity: .5 }}>/</span>}
          {u > 0 && <span style={{ color: "#1A5276", fontWeight: 900 }}>🛡{u}</span>}
        </span>
      ))}
      {pac > 0 && (
        <span style={{ background: "#00695C14", border: "1px solid #00695C44", color: "#00695C", borderRadius: 6, padding: "2px 8px", fontSize: 11, fontWeight: 700 }}>
          PAC: {pac}
        </span>
      )}
    </div>
  );
}

// ── Stat Chip ─────────────────────────────────────────────────────────────────
function StatChip({ label, value, color }) {
  return (
    <div style={{ background: `${color}14`, border: `1px solid ${color}33`, borderRadius: 8, padding: "6px 12px", textAlign: "center" }}>
      <div style={{ color, fontSize: 18, fontWeight: 900, lineHeight: 1 }}>{value}</div>
      <div style={{ color, fontSize: 10, fontWeight: 600, opacity: .75, marginTop: 2 }}>{label}</div>
    </div>
  );
}

// ── Progress Bar ──────────────────────────────────────────────────────────────
function ProgressBar({ value, color, height = 5 }) {
  return (
    <div style={{ background: `${color}20`, borderRadius: 4, overflow: "hidden", height }}>
      <div style={{ width: `${Math.min(value * 100, 100)}%`, background: color, height: "100%", borderRadius: 4, transition: "width .4s ease" }} />
    </div>
  );
}

// ── Modal ─────────────────────────────────────────────────────────────────────
function Modal({ open, onClose, title, children, actions, color = C.district, icon: Icon }) {
  if (!open) return null;
  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 1000, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.45)", backdropFilter: "blur(3px)" }}
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div style={{ background: C.bg, borderRadius: 18, padding: 28, width: "100%", maxWidth: 440, boxShadow: "0 24px 80px rgba(0,0,0,.25)", border: `1px solid ${color}55`, animation: "fadeIn .2s ease" }}>
        {title && (
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 18 }}>
            {Icon && <div style={{ width: 38, height: 38, background: `${color}18`, borderRadius: 10, display: "flex", alignItems: "center", justifyContent: "center" }}>
              <Icon size={18} color={color} />
            </div>}
            <span style={{ color: C.dark, fontWeight: 800, fontSize: 15 }}>{title}</span>
          </div>
        )}
        {children}
        {actions && <div style={{ display: "flex", justifyContent: "flex-end", gap: 10, marginTop: 22 }}>{actions}</div>}
      </div>
    </div>
  );
}

// ── Btn ───────────────────────────────────────────────────────────────────────
function Btn({ children, onClick, color, variant = "solid", size = "md", icon: Icon, disabled, loading, style = {} }) {
  const pad = size === "sm" ? "6px 14px" : "10px 20px";
  const fs = size === "sm" ? 12 : 13;
  const bg = variant === "solid" ? color : "transparent";
  const cl = variant === "solid" ? "#fff" : color;
  const bo = variant === "outline" ? `1.5px solid ${color}` : "none";
  return (
    <button onClick={onClick} disabled={disabled || loading}
      style={{
        display: "inline-flex", alignItems: "center", gap: 6, padding: pad, borderRadius: 10,
        fontWeight: 700, fontSize: fs, background: disabled ? "#ccc" : bg, color: disabled ? "#999" : cl,
        border: bo, cursor: disabled ? "not-allowed" : "pointer", transition: "all .18s", opacity: disabled ? .6 : 1, ...style
      }}>
      {loading ? <Loader2 size={15} style={{ animation: "spin 1s linear infinite" }} /> : Icon && <Icon size={15} />}
      {children}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  DUTY RULE CARD (Manak Tab)
// ─────────────────────────────────────────────────────────────────────────────
function DutyRuleCard({ entry, rule, isSet, onEdit, onEditLabel, onDelete }) {
  const color = entry.isDefault ? C.district : C.custom;
  const san = isSet ? (rule.sankhya || 0) : 0;
  const ts = totalStaff(rule);

  return (
    <div onClick={onEdit}
      style={{
        background: isSet ? `${color}09` : "white", border: `${isSet ? 1.5 : 1}px solid ${isSet ? color + "55" : C.border + "66"}`,
        borderRadius: 14, padding: "14px 16px", cursor: "pointer", transition: "all .18s",
        boxShadow: isSet ? `0 2px 12px ${color}18` : "0 1px 4px rgba(0,0,0,.05)"
      }}>
      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
        {/* Icon */}
        <div style={{
          width: 46, height: 46, background: isSet ? color : `${C.subtle}22`, borderRadius: 12,
          display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0
        }}>
          <DutyIcon type={entry.icon} size={22} color={isSet ? "white" : C.subtle} />
        </div>
        {/* Info */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span style={{ color: C.dark, fontWeight: 700, fontSize: 14, flexShrink: 0 }}>{entry.labelHi}</span>
            {!entry.isDefault && <span style={{ background: `${C.custom}18`, color: C.custom, fontSize: 9, fontWeight: 800, borderRadius: 5, padding: "1px 6px" }}>कस्टम</span>}
          </div>
          {isSet ? (
            <div style={{ display: "flex", gap: 10, marginTop: 3 }}>
              <span style={{ color, fontSize: 11, fontWeight: 800 }}>संख्या: {san}</span>
              <span style={{ color: C.subtle, fontSize: 11 }}>• कुल स्टाफ: {ts}</span>
            </div>
          ) : <span style={{ color: C.subtle, fontSize: 11 }}>मानक सेट नहीं है</span>}
        </div>
        {/* Status + actions */}
        <div style={{ display: "flex", alignItems: "center", gap: 6, flexShrink: 0 }} onClick={e => e.stopPropagation()}>
          {isSet
            ? <CheckCircle2 size={18} color={C.success} />
            : <PlusCircle size={18} color={C.subtle} />}
          {!entry.isDefault && (
            <>
              <button onClick={e => { e.stopPropagation(); onEditLabel(); }}
                style={{
                  width: 30, height: 30, background: `${C.custom}14`, border: `1px solid ${C.custom}33`, borderRadius: 7,
                  display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer"
                }}>
                <Edit3 size={13} color={C.custom} />
              </button>
              <button onClick={e => { e.stopPropagation(); onDelete(); }}
                style={{
                  width: 30, height: 30, background: `${C.error}10`, border: `1px solid ${C.error}33`, borderRadius: 7,
                  display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer"
                }}>
                <Trash2 size={13} color={C.error} />
              </button>
            </>
          )}
          {entry.isDefault && <ChevronRight size={18} color={C.subtle} />}
        </div>
      </div>
      {/* Chips */}
      {isSet && rule && <ChipRow rule={rule} color={color} />}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  DUTY ASSIGN CARD (Duty Tab)
// ─────────────────────────────────────────────────────────────────────────────
function DutyAssignCard({ entry, summary, sankhya, onTap }) {
  const color = entry.isDefault ? C.district : C.custom;
  const assigned = summary?.totalAssigned || 0;
  const batches = summary?.batchCount || 0;
  const pct = sankhya > 0 ? assigned / sankhya : 0;
  const isOver = assigned > sankhya && sankhya > 0;
  const isFull = sankhya > 0 && assigned >= sankhya;
  const barColor = isOver ? C.error : isFull ? C.success : pct > .5 ? C.orange : C.assign;

  return (
    <div onClick={onTap}
      style={{
        background: assigned > 0 ? `${color}06` : "white",
        border: `${assigned > 0 ? 1.5 : 1}px solid ${assigned > 0 ? color + "44" : C.border + "55"}`,
        borderRadius: 14, padding: "14px 16px", cursor: "pointer", transition: "all .2s",
        boxShadow: assigned > 0 ? `0 2px 12px ${color}14` : "none"
      }}>
      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
        <div style={{
          width: 44, height: 44, background: assigned > 0 ? color : `${C.subtle}18`, borderRadius: 11,
          display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0
        }}>
          <DutyIcon type={entry.icon} size={21} color={assigned > 0 ? "white" : C.subtle} />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ color: C.dark, fontWeight: 700, fontSize: 13.5, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{entry.labelHi}</div>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 3, flexWrap: "wrap" }}>
            {sankhya > 0
              ? <span style={{ color: barColor, fontWeight: 800, fontSize: 11 }}>{assigned}/{sankhya}</span>
              : <span style={{ color, fontWeight: 700, fontSize: 11 }}>{assigned} assigned</span>}
            {batches > 0 && <span style={{ background: `${C.assign}14`, color: C.assign, fontSize: 9, fontWeight: 700, borderRadius: 5, padding: "1px 6px" }}>{batches} batch{batches > 1 ? "es" : ""}</span>}
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 8, flexShrink: 0 }}>
          {isFull && !isOver && <span style={{ background: `${C.success}14`, color: C.success, fontSize: 10, fontWeight: 700, borderRadius: 8, padding: "3px 8px", display: "flex", alignItems: "center", gap: 3 }}><CheckCircle2 size={11} />Full</span>}
          {isOver && <span style={{ background: `${C.error}12`, color: C.error, fontSize: 10, fontWeight: 700, borderRadius: 8, padding: "3px 8px", display: "flex", alignItems: "center", gap: 3 }}><AlertTriangle size={11} />Over</span>}
          <div style={{ background: C.assign, borderRadius: 9, padding: "6px 10px", display: "flex", alignItems: "center", gap: 4 }}>
            <Users size={13} color="white" />
            <span style={{ color: "white", fontSize: 11, fontWeight: 700 }}>देखें</span>
          </div>
        </div>
      </div>
      {sankhya > 0 && <div style={{ marginTop: 10 }}><ProgressBar value={pct} color={barColor} /></div>}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  BATCH CARD
// ─────────────────────────────────────────────────────────────────────────────
function BatchCard({ batch, color, onDelete, onView }) {
  const staffList = batch.staff || [];
  return (
    <div style={{
      background: "white", borderRadius: 14, border: `1px solid ${color}33`,
      boxShadow: `0 2px 10px ${color}10`, overflow: "hidden"
    }}>
      {/* Header */}
      <div style={{ background: `${color}0e`, padding: "12px 14px", display: "flex", alignItems: "center", gap: 12 }}>
        <div style={{ width: 36, height: 36, background: color, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", color: "white", fontWeight: 900, fontSize: 15, flexShrink: 0 }}>
          {batch.batchNo}
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ color, fontWeight: 800, fontSize: 13 }}>Batch {batch.batchNo}</div>
          <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
            <span style={{ color: C.subtle, fontSize: 11 }}>{batch.staffCount} staff</span>
            {batch.busNo && <span style={{ color: C.subtle, fontSize: 10, display: "flex", alignItems: "center", gap: 3 }}><Bus size={10} />{batch.busNo}</span>}
            {batch.note && <span style={{ color: C.subtle, fontSize: 10, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 120 }}>{batch.note}</span>}
          </div>
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          <button onClick={onView} style={{ background: color, border: "none", borderRadius: 8, padding: "6px 12px", color: "white", fontSize: 11, fontWeight: 700, cursor: "pointer" }}>विवरण</button>
          <button onClick={onDelete} style={{ width: 32, height: 32, background: `${C.error}10`, border: `1px solid ${C.error}33`, borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <Trash2 size={14} color={C.error} />
          </button>
        </div>
      </div>
      {/* Staff preview */}
      {staffList.length > 0 && (
        <div style={{ padding: "10px 12px", display: "flex", flexWrap: "wrap", gap: 6 }}>
          {staffList.slice(0, 6).map(s => {
            const rc = rankColor(s.rank);
            const initials = (s.name || "").split(" ").filter(Boolean).slice(0, 2).map(w => w[0]).join("").toUpperCase();
            return (
              <div key={s.assignmentId} style={{ display: "inline-flex", alignItems: "center", gap: 5, background: `${rc}10`, border: `1px solid ${rc}28`, borderRadius: 8, padding: "4px 8px" }}>
                <div style={{ width: 22, height: 22, background: `${rc}20`, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", color: rc, fontWeight: 900, fontSize: 10 }}>{initials}</div>
                <span style={{ color: C.dark, fontSize: 11, fontWeight: 600, maxWidth: 72, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{s.name}</span>
                <span style={{ background: `${rc}18`, color: rc, fontSize: 8, fontWeight: 700, borderRadius: 4, padding: "1px 4px" }}>{s.rank}</span>
              </div>
            );
          })}
          {staffList.length > 6 && <span style={{ background: `${C.subtle}12`, color: C.subtle, fontSize: 11, borderRadius: 8, padding: "4px 8px" }}>+{staffList.length - 6} और</span>}
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  STAFF DETAIL CARD
// ─────────────────────────────────────────────────────────────────────────────
function StaffDetailCard({ staff, index, color, onRemove }) {
  const rc = rankColor(staff.rank);
  const initials = (staff.name || "").split(" ").filter(Boolean).slice(0, 2).map(w => w[0]).join("").toUpperCase();
  return (
    <div style={{
      background: "white", borderRadius: 12, border: `1px solid ${rc}28`, padding: 14,
      marginBottom: 8, display: "flex", alignItems: "center", gap: 12,
      boxShadow: `0 1px 6px ${rc}08`
    }}>
      <div style={{ width: 30, height: 30, background: `${color}14`, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", color, fontWeight: 900, fontSize: 12, flexShrink: 0 }}>{index + 1}</div>
      <div style={{ width: 40, height: 40, background: `${rc}18`, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", color: rc, fontWeight: 900, fontSize: 14, border: `1px solid ${rc}33`, flexShrink: 0 }}>{initials}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
          <span style={{ color: C.dark, fontWeight: 700, fontSize: 13, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 180 }}>{staff.name}</span>
          {staff.isArmed && <span style={{ background: "#6A1B9A18", color: "#6A1B9A", fontSize: 9, fontWeight: 700, borderRadius: 5, padding: "1px 6px" }}>⚔ Armed</span>}
        </div>
        <div style={{ display: "flex", gap: 8, marginTop: 4, flexWrap: "wrap", alignItems: "center" }}>
          <span style={{ background: `${rc}14`, color: rc, fontSize: 9, fontWeight: 700, borderRadius: 5, padding: "2px 6px", border: `1px solid ${rc}30` }}>{staff.rank}</span>
          {staff.pno && <span style={{ color: C.subtle, fontSize: 10, display: "flex", alignItems: "center", gap: 2 }}><Hash size={9} />{staff.pno}</span>}
          {staff.thana && <span style={{ color: C.subtle, fontSize: 10, display: "flex", alignItems: "center", gap: 2 }}><Shield size={9} />{staff.thana}</span>}
          {staff.mobile && <span style={{ color: C.subtle, fontSize: 10, display: "flex", alignItems: "center", gap: 2 }}><Phone size={9} />{staff.mobile}</span>}
        </div>
      </div>
      <button onClick={onRemove} style={{ width: 32, height: 32, background: `${C.error}10`, border: `1px solid ${C.error}28`, borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", flexShrink: 0 }}>
        <UserMinus size={15} color={C.error} />
      </button>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  RANK EDITOR MODAL (replaces ManakRankEditorPage)
// ─────────────────────────────────────────────────────────────────────────────
function RankEditorModal({ open, onClose, entry, initial, onSave }) {
  const color = entry?.isDefault ? C.district : C.custom;
  const [form, setForm] = useState({
    sankhya: 0, siArmedCount: 0, siUnarmedCount: 0, hcArmedCount: 0,
    hcUnarmedCount: 0, constArmedCount: 0, constUnarmedCount: 0,
    auxArmedCount: 0, auxUnarmedCount: 0, pacCount: 0,
  });

  useEffect(() => {
    if (open && initial) {
      setForm({
        sankhya: initial.sankhya || 0,
        siArmedCount: initial.siArmedCount || 0,
        siUnarmedCount: initial.siUnarmedCount || 0,
        hcArmedCount: initial.hcArmedCount || 0,
        hcUnarmedCount: initial.hcUnarmedCount || 0,
        constArmedCount: initial.constArmedCount || 0,
        constUnarmedCount: initial.constUnarmedCount || 0,
        auxArmedCount: initial.auxArmedCount || 0,
        auxUnarmedCount: initial.auxUnarmedCount || 0,
        pacCount: initial.pacCount || 0,
      });
    }
  }, [open, initial]);

  const Field = ({ label, k }) => (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "8px 0", borderBottom: `1px solid ${C.border}22` }}>
      <span style={{ color: C.dark, fontSize: 13, fontWeight: 600 }}>{label}</span>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <button onClick={() => setForm(f => ({ ...f, [k]: Math.max(0, (f[k] || 0) - 1) }))}
          style={{ width: 28, height: 28, borderRadius: 7, background: `${color}14`, border: `1px solid ${color}33`, cursor: "pointer", fontWeight: 900, color, fontSize: 14, display: "flex", alignItems: "center", justifyContent: "center" }}>−</button>
        <span style={{ width: 36, textAlign: "center", color: C.dark, fontWeight: 800, fontSize: 15 }}>{form[k] || 0}</span>
        <button onClick={() => setForm(f => ({ ...f, [k]: (f[k] || 0) + 1 }))}
          style={{ width: 28, height: 28, borderRadius: 7, background: `${color}14`, border: `1px solid ${color}33`, cursor: "pointer", fontWeight: 900, color, fontSize: 14, display: "flex", alignItems: "center", justifyContent: "center" }}>+</button>
      </div>
    </div>
  );

  if (!open || !entry) return null;
  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 1000, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.45)", backdropFilter: "blur(3px)" }}
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div style={{
        background: C.bg, borderRadius: 18, padding: 0, width: "100%", maxWidth: 500, maxHeight: "90vh", overflowY: "auto",
        boxShadow: "0 24px 80px rgba(0,0,0,.25)", border: `1.5px solid ${color}44`, animation: "fadeIn .2s ease"
      }}>
        {/* Header */}
        <div style={{ background: color, padding: "18px 22px", borderRadius: "18px 18px 0 0", display: "flex", alignItems: "center", gap: 12, position: "sticky", top: 0, zIndex: 1 }}>
          <div style={{ flex: 1 }}>
            <div style={{ color: "white", fontWeight: 800, fontSize: 15 }}>{entry.labelHi}</div>
            <div style={{ color: "rgba(255,255,255,.7)", fontSize: 11 }}>जनपदीय कानून व्यवस्था — मानक सेट करें</div>
          </div>
          <button onClick={onClose} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 32, height: 32, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <X size={16} color="white" />
          </button>
        </div>
        <div style={{ padding: "20px 22px" }}>
          {/* Sankhya */}
          <div style={{ background: `${color}0c`, border: `1px solid ${color}33`, borderRadius: 12, padding: "12px 16px", marginBottom: 18 }}>
            <div style={{ color: color, fontWeight: 700, fontSize: 12, marginBottom: 6 }}>कुल संख्या (Sankhya)</div>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <button onClick={() => setForm(f => ({ ...f, sankhya: Math.max(0, f.sankhya - 1) }))}
                style={{ width: 36, height: 36, borderRadius: 10, background: `${color}18`, border: `1px solid ${color}44`, cursor: "pointer", fontWeight: 900, color, fontSize: 18, display: "flex", alignItems: "center", justifyContent: "center" }}>−</button>
              <span style={{ flex: 1, textAlign: "center", color, fontWeight: 900, fontSize: 28 }}>{form.sankhya}</span>
              <button onClick={() => setForm(f => ({ ...f, sankhya: f.sankhya + 1 }))}
                style={{ width: 36, height: 36, borderRadius: 10, background: `${color}18`, border: `1px solid ${color}44`, cursor: "pointer", fontWeight: 900, color, fontSize: 18, display: "flex", alignItems: "center", justifyContent: "center" }}>+</button>
            </div>
          </div>
          {/* Rank fields */}
          <div style={{ fontWeight: 700, color: C.subtle, fontSize: 11, textTransform: "uppercase", letterSpacing: .8, marginBottom: 8 }}>रैंकवार स्टाफ संख्या</div>
          <Field label="SI (Armed)" k="siArmedCount" />
          <Field label="SI (Unarmed)" k="siUnarmedCount" />
          <Field label="HC (Armed)" k="hcArmedCount" />
          <Field label="HC (Unarmed)" k="hcUnarmedCount" />
          <Field label="Constable (Armed)" k="constArmedCount" />
          <Field label="Constable (Unarmed)" k="constUnarmedCount" />
          <Field label="Aux (Armed)" k="auxArmedCount" />
          <Field label="Aux (Unarmed)" k="auxUnarmedCount" />
          <Field label="PAC" k="pacCount" />
          {/* Save */}
          <div style={{ marginTop: 20, display: "flex", gap: 10, justifyContent: "flex-end" }}>
            <Btn onClick={onClose} color={C.subtle} variant="outline">रद्द</Btn>
            <Btn onClick={() => onSave(form)} color={color} icon={Save}>सेव करें</Btn>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  ASSIGN STAFF SHEET
// ─────────────────────────────────────────────────────────────────────────────
function AssignStaffSheet({ open, onClose, entry, onAssign }) {
  const color = entry?.isDefault ? C.district : C.custom;
  const [selected, setSelected] = useState(new Set());
  const [q, setQ] = useState("");
  const [rankFilter, setRankFilter] = useState("");
  const [busNo, setBusNo] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);

  const filtered = MOCK_STAFF.filter(s => {
    const matchQ = !q || s.name.toLowerCase().includes(q.toLowerCase()) || s.pno.includes(q);
    const matchR = !rankFilter || s.rank === rankFilter;
    return matchQ && matchR;
  });

  const toggle = (id) => setSelected(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n; });

  const handleAssign = async () => {
    setSaving(true);
    await new Promise(r => setTimeout(r, 1000));
    onAssign({ staffIds: [...selected], busNo, note });
    setSaving(false);
    setSelected(new Set());
    onClose();
  };

  if (!open || !entry) return null;
  const RANKS = ["SI", "ASI", "Head Constable", "Constable"];

  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 1000, display: "flex", alignItems: "flex-end", background: "rgba(0,0,0,.45)", backdropFilter: "blur(3px)" }}
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div style={{
        background: C.bg, borderRadius: "20px 20px 0 0", width: "100%", height: "88vh", display: "flex", flexDirection: "column",
        boxShadow: "0 -8px 40px rgba(0,0,0,.25)", border: `1px solid ${color}33`, animation: "slideUp .25s ease"
      }}>
        {/* Drag handle */}
        <div style={{ width: 40, height: 4, background: `${C.border}88`, borderRadius: 2, margin: "10px auto 6px" }} />
        {/* Header area */}
        <div style={{ padding: "0 18px 14px", borderBottom: `1px solid ${C.border}33` }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 12 }}>
            <div style={{ width: 40, height: 40, background: `${color}14`, borderRadius: 10, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
              <DutyIcon type={entry.icon} size={20} color={color} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ color: C.dark, fontWeight: 800, fontSize: 15 }}>Staff Assign करें</div>
              <div style={{ color: C.subtle, fontSize: 12 }}>{entry.labelHi}</div>
            </div>
            {selected.size > 0 && <div style={{ background: color, borderRadius: 20, padding: "4px 12px", color: "white", fontSize: 12, fontWeight: 800 }}>{selected.size} चुने</div>}
          </div>
          {/* Rank filter */}
          <div style={{ display: "flex", gap: 6, overflowX: "auto", paddingBottom: 4, marginBottom: 10 }}>
            {["सभी", ...RANKS].map((r, i) => {
              const v = i === 0 ? "" : r; const sel = rankFilter === v;
              const c = i === 0 ? C.district : rankColor(r);
              return <button key={r} onClick={() => setRankFilter(v)}
                style={{
                  padding: "4px 12px", borderRadius: 20, border: `1px solid ${sel ? c : C.border + "66"}`,
                  background: sel ? c : "white", color: sel ? "white" : C.dark, fontSize: 11, fontWeight: sel ? 700 : 500,
                  cursor: "pointer", whiteSpace: "nowrap", transition: "all .15s"
                }}>{r}</button>;
            })}
          </div>
          {/* Search */}
          <div style={{ position: "relative", marginBottom: 8 }}>
            <Search size={16} color={C.subtle} style={{ position: "absolute", left: 12, top: "50%", transform: "translateY(-50%)" }} />
            <input value={q} onChange={e => setQ(e.target.value)} placeholder="नाम, PNO खोजें..."
              style={{
                width: "100%", border: `1px solid ${C.border}`, borderRadius: 10, padding: "9px 12px 9px 36px",
                background: "white", color: C.dark, fontSize: 13, outline: "none", boxSizing: "border-box"
              }} />
          </div>
          {/* Bus / note */}
          <div style={{ display: "flex", gap: 8 }}>
            {[{ ctrl: busNo, set: setBusNo, placeholder: "Bus No (optional)", icon: Bus }, { ctrl: note, set: setNote, placeholder: "Note (optional)", icon: StickyNote }].map(({ ctrl, set, placeholder, icon: Ic }, i) => (
              <div key={i} style={{ flex: 1, position: "relative" }}>
                <Ic size={13} color={color} style={{ position: "absolute", left: 10, top: "50%", transform: "translateY(-50%)" }} />
                <input value={ctrl} onChange={e => set(e.target.value)} placeholder={placeholder}
                  style={{
                    width: "100%", border: `1px solid ${C.border}`, borderRadius: 9, padding: "8px 10px 8px 28px",
                    background: "white", color: C.dark, fontSize: 12, outline: "none", boxSizing: "border-box"
                  }} />
              </div>
            ))}
          </div>
        </div>
        {/* Staff list */}
        <div style={{ flex: 1, overflowY: "auto", padding: "8px 14px" }}>
          {filtered.length === 0
            ? <div style={{ textAlign: "center", padding: 40, color: C.subtle }}>कोई staff नहीं मिला</div>
            : filtered.map(s => {
              const isSel = selected.has(s.id);
              const rc = rankColor(s.rank);
              const initials = (s.name || "").split(" ").filter(Boolean).slice(0, 2).map(w => w[0]).join("").toUpperCase();
              return (
                <div key={s.id} onClick={() => toggle(s.id)}
                  style={{
                    display: "flex", alignItems: "center", gap: 12, padding: "10px 12px", borderRadius: 10,
                    border: `${isSel ? 1.8 : 1}px solid ${isSel ? color : C.border + "55"}`,
                    background: isSel ? `${color}08` : "white", marginBottom: 6, cursor: "pointer", transition: "all .15s"
                  }}>
                  <div style={{
                    width: 22, height: 22, borderRadius: "50%", border: `1.5px solid ${isSel ? color : C.border}`,
                    background: isSel ? color : "white", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0
                  }}>
                    {isSel && <Check size={12} color="white" />}
                  </div>
                  <div style={{
                    width: 38, height: 38, background: `${rc}18`, borderRadius: "50%", border: `1px solid ${rc}30`,
                    display: "flex", alignItems: "center", justifyContent: "center", color: rc, fontWeight: 900, fontSize: 13, flexShrink: 0
                  }}>{initials}</div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ color: isSel ? color : C.dark, fontWeight: 700, fontSize: 13, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{s.name}</div>
                    <div style={{ display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap" }}>
                      <span style={{ background: `${rc}14`, color: rc, fontSize: 9, fontWeight: 700, borderRadius: 4, padding: "1px 5px", border: `1px solid ${rc}30` }}>{s.rank}</span>
                      <span style={{ color: C.subtle, fontSize: 10 }}>{s.pno}</span>
                      <span style={{ color: C.subtle, fontSize: 10, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 100 }}>{s.thana}</span>
                    </div>
                  </div>
                </div>
              );
            })}
        </div>
        {/* Bottom action */}
        <div style={{ padding: "10px 14px 16px", borderTop: `1px solid ${C.border}33` }}>
          <button onClick={selected.size > 0 && !saving ? handleAssign : undefined} disabled={selected.size === 0 || saving}
            style={{
              width: "100%", height: 50, borderRadius: 12, border: "none",
              background: selected.size === 0 ? C.subtle : color, color: "white",
              fontWeight: 800, fontSize: 13, cursor: selected.size === 0 ? "not-allowed" : "pointer",
              display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
              opacity: selected.size === 0 ? .7 : 1, transition: "all .2s"
            }}>
            {saving ? <Loader2 size={18} style={{ animation: "spin 1s linear infinite" }} /> : <CheckCircle2 size={18} />}
            {saving ? "Assigning..." : selected.size === 0 ? "Staff चुनें" : `${selected.size} Staff Assign करें (New Batch)`}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  BATCH DETAIL VIEW (panel)
// ─────────────────────────────────────────────────────────────────────────────
function BatchDetailView({ dutyType, dutyLabel, batch, color, onBack, onRefresh }) {
  const [staff, setStaff] = useState((batch.staff || []).map(s => ({ ...s })));
  const removeStaff = (s) => {
    if (confirm(`${s.name} को हटाएं?`)) {
      setStaff(prev => prev.filter(x => x.assignmentId !== s.assignmentId));
      onRefresh();
    }
  };
  const rankCounts = {};
  staff.forEach(s => { const r = s.rank || ""; if (r) rankCounts[r] = (rankCounts[r] || 0) + 1; });

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      {/* Header */}
      <div style={{ background: color, padding: "16px 20px", display: "flex", alignItems: "center", gap: 12 }}>
        <button onClick={onBack} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
          <ArrowLeft size={18} color="white" />
        </button>
        <div style={{ flex: 1 }}>
          <div style={{ color: "white", fontWeight: 800, fontSize: 14 }}>{dutyLabel}</div>
          <div style={{ color: "rgba(255,255,255,.7)", fontSize: 11 }}>Batch {batch.batchNo} • {staff.length} Staff{batch.busNo ? ` • Bus: ${batch.busNo}` : ""}</div>
        </div>
        <div style={{ width: 38, height: 38, background: color, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", border: "2px solid rgba(255,255,255,.4)" }}>
          <span style={{ color: "white", fontWeight: 900, fontSize: 16 }}>{batch.batchNo}</span>
        </div>
      </div>
      {/* Rank summary */}
      {staff.length > 0 && (
        <div style={{ background: `${C.surface}88`, padding: "8px 16px", display: "flex", gap: 8, overflowX: "auto" }}>
          {Object.entries(rankCounts).map(([r, c]) => {
            const rc = rankColor(r);
            return <span key={r} style={{ background: `${rc}14`, border: `1px solid ${rc}33`, color: rc, borderRadius: 6, padding: "3px 8px", fontSize: 10, fontWeight: 700, whiteSpace: "nowrap" }}>{r}: {c}</span>;
          })}
        </div>
      )}
      {/* Info */}
      <div style={{ background: `${C.assign}0a`, padding: "8px 16px", display: "flex", alignItems: "center", gap: 6 }}>
        <Info size={13} color={C.assign} />
        <span style={{ color: C.assign, fontSize: 11 }}>इस batch के सभी staff एक साथ इस ड्यूटी पर तैनात हैं।</span>
      </div>
      {/* List */}
      <div style={{ flex: 1, overflowY: "auto", padding: "10px 14px" }}>
        {staff.length === 0
          ? <div style={{ textAlign: "center", padding: 40, color: C.subtle }}>कोई staff नहीं</div>
          : staff.map((s, i) => <StaffDetailCard key={s.assignmentId} staff={s} index={i} color={color} onRemove={() => removeStaff(s)} />)}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  DUTY DETAIL VIEW (right panel)
// ─────────────────────────────────────────────────────────────────────────────
function DutyDetailView({ entry, rule, batches, summary, onBack, onRefresh, onAssign }) {
  const [viewBatch, setViewBatch] = useState(null);
  const color = entry.isDefault ? C.district : C.custom;
  const sankhya = entry.sankhya || 0;
  const totalAsgn = batches.reduce((s, b) => s + ((b.staffCount || 0)), 0);

  if (viewBatch) return (
    <BatchDetailView dutyType={entry.type} dutyLabel={entry.labelHi}
      batch={viewBatch} color={color} onBack={() => setViewBatch(null)} onRefresh={onRefresh} />
  );

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      {/* Header */}
      <div style={{ background: color, padding: "16px 20px", display: "flex", alignItems: "center", gap: 12 }}>
        <button onClick={onBack} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
          <ArrowLeft size={18} color="white" />
        </button>
        <div style={{ flex: 1 }}>
          <div style={{ color: "white", fontWeight: 800, fontSize: 14, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{entry.labelHi}</div>
          <div style={{ color: "rgba(255,255,255,.7)", fontSize: 11 }}>{batches.length} Batches • {totalAsgn} Assigned</div>
        </div>
        <button onClick={onAssign} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 10, padding: "8px 14px", color: "white", fontWeight: 700, fontSize: 12, cursor: "pointer", display: "flex", alignItems: "center", gap: 6 }}>
          <Plus size={15} />Assign
        </button>
      </div>
      {/* Stats strip */}
      <div style={{ background: `${color}08`, padding: "12px 16px", display: "flex", gap: 10, alignItems: "center" }}>
        <StatChip label="आवश्यक" value={sankhya} color={color} />
        <StatChip label="Assigned" value={totalAsgn} color={totalAsgn >= sankhya && sankhya > 0 ? C.success : C.assign} />
        <StatChip label="Batches" value={batches.length} color={C.orange} />
        <div style={{ flex: 1 }} />
        {sankhya > 0 && <span style={{ color: totalAsgn >= sankhya ? C.success : C.error, fontWeight: 800, fontSize: 12 }}>
          {totalAsgn >= sankhya ? "✓ पूर्ण" : `${sankhya - totalAsgn} बाकी`}
        </span>}
      </div>
      {/* Rule chips */}
      {rule && hasAny(rule) && (
        <div style={{ background: `${color}05`, padding: "8px 16px", borderBottom: `1px solid ${C.border}22` }}>
          <ChipRow rule={rule} color={color} />
        </div>
      )}
      {/* Batch list */}
      <div style={{ flex: 1, overflowY: "auto", padding: "12px 14px" }}>
        {batches.length === 0
          ? <div style={{ textAlign: "center", padding: 48, color: C.subtle }}>
            <DutyIcon type={entry.icon} size={48} color={`${C.subtle}44`} />
            <div style={{ marginTop: 12, fontSize: 13 }}>कोई staff assign नहीं है</div>
            <div style={{ marginTop: 4, fontSize: 11 }}>ऊपर "Assign" बटन दबाएं</div>
          </div>
          : batches.map(batch => (
            <div key={batch.batchNo} style={{ marginBottom: 14 }}>
              <BatchCard batch={batch} color={color}
                onDelete={() => alert(`Batch ${batch.batchNo} हटाया जाएगा`)}
                onView={() => setViewBatch(batch)} />
            </div>
          ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  AUTO ASSIGN BANNER
// ─────────────────────────────────────────────────────────────────────────────
function AutoAssignBanner({ status, pct, assigned, skipped, onDismiss }) {
  const isRunning = status === "running" || status === "pending";
  const color = isRunning ? C.orange : C.success;
  return (
    <div style={{ background: `${color}12`, borderBottom: `1px solid ${color}33`, padding: "10px 18px" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        {isRunning
          ? <Loader2 size={16} color={C.orange} style={{ animation: "spin 1s linear infinite" }} />
          : <CheckCircle2 size={16} color={C.success} />}
        <span style={{ flex: 1, color, fontSize: 12, fontWeight: 800 }}>
          {isRunning ? `Auto-assign चल रही है... ${pct}%` : `${assigned} Staff assign हुए, ${skipped} skip`}
        </span>
        <button onClick={onDismiss} style={{ background: "none", border: "none", cursor: "pointer", padding: 2 }}><X size={14} color={color} /></button>
      </div>
      {isRunning && <div style={{ marginTop: 8 }}><ProgressBar value={pct / 100} color={C.orange} height={4} /></div>}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  MAIN PAGE
// ─────────────────────────────────────────────────────────────────────────────
export default function ManakDistrictPage() {
  const nav = useNavigate()

  const [tab, setTab] = useState("manak"); // "manak" | "duty"
  const [duties, setDuties] = useState(DUTY_TYPES.map(d => ({ ...d, sankhya: MOCK_RULES[d.type]?.sankhya || 0 })));
  const [rules, setRules] = useState({ ...MOCK_RULES });
  const [summary, setSummary] = useState({ ...MOCK_SUMMARY });
  const [batches, setBatches] = useState({ ...MOCK_BATCHES });
  const [changed, setChanged] = useState(false);
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(false);

  // Modals
  const [editEntry, setEditEntry] = useState(null);
  const [editorOpen, setEditorOpen] = useState(false);
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [addLabel, setAddLabel] = useState("");
  const [editingCustom, setEditingCustom] = useState(null);

  // Detail panel
  const [detailEntry, setDetailEntry] = useState(null);
  const [assignSheetEntry, setAssignSheetEntry] = useState(null);

  // Auto assign
  const [jobStatus, setJobStatus] = useState("");
  const [jobPct, setJobPct] = useState(0);
  const [jobAssigned, setJobAssigned] = useState(0);
  const [jobSkipped, setJobSkipped] = useState(0);

  const filledCount = duties.filter(d => hasAny(rules[d.type])).length;
  const totalAll = duties.filter(d => hasAny(rules[d.type])).reduce((s, d) => s + totalStaff(rules[d.type]), 0);
  const assignedAll = duties.reduce((s, d) => s + (summary[d.type]?.totalAssigned || 0), 0);
  const isJobRunning = jobStatus === "running" || jobStatus === "pending";

  const simulateLoad = async () => {
    setLoading(true); await new Promise(r => setTimeout(r, 700)); setLoading(false);
  };

  const startAutoAssign = () => {
    if (!confirm("Auto-assign शुरू करें? सभी पुराने assignments हट जाएंगे।")) return;
    setJobStatus("running"); setJobPct(0);
    let p = 0;
    const iv = setInterval(() => {
      p += 8;
      if (p >= 100) { clearInterval(iv); setJobStatus("done"); setJobAssigned(42); setJobSkipped(3); }
      else setJobPct(p);
    }, 200);
  };

  const clearAll = () => {
    if (!confirm("सभी assignments हटाएं?")) return;
    setBatches({}); setSummary({});
    alert("सभी assignments हटाए गए ✓");
  };

  const openRankEditor = (entry) => { setEditEntry(entry); setEditorOpen(true); };

  const saveRule = (form) => {
    setRules(r => ({ ...r, [editEntry.type]: { ...r[editEntry.type], ...form } }));
    setDuties(d => d.map(x => x.type === editEntry.type ? { ...x, sankhya: form.sankhya } : x));
    setChanged(true); setEditorOpen(false);
  };

  const saveAll = async () => {
    setSaving(true); await new Promise(r => setTimeout(r, 900)); setSaving(false); setChanged(false);
    alert("जनपदीय मानक सेव हो गया ✓");
  };

  const addDuty = () => {
    if (!addLabel.trim()) return;
    if (editingCustom) {
      setDuties(d => d.map(x => x.type === editingCustom.type ? { ...x, labelHi: addLabel } : x));
    } else {
      const type = `custom_${Date.now()}`;
      setDuties(d => [...d, { type, labelHi: addLabel, isDefault: false, icon: "clipboard", sankhya: 0 }]);
    }
    setAddLabel(""); setAddDialogOpen(false); setEditingCustom(null);
  };

  const deleteDuty = (entry) => {
    if (!confirm(`"${entry.labelHi}" हटाएं?`)) return;
    setDuties(d => d.filter(x => x.type !== entry.type));
    setRules(r => { const n = { ...r }; delete n[entry.type]; return n; });
  };

  const handleAssign = ({ staffIds, busNo, note }) => {
    const type = assignSheetEntry?.type;
    if (!type) return;
    const existing = batches[type] || [];
    const batchNo = (existing[existing.length - 1]?.batchNo || 0) + 1;
    const staff = MOCK_STAFF.filter(s => staffIds.includes(s.id)).map((s, i) => ({ ...s, assignmentId: Date.now() + i }));
    const newBatch = { batchNo, staffCount: staff.length, busNo, note, staff };
    setBatches(b => ({ ...b, [type]: [...existing, newBatch] }));
    setSummary(s => ({ ...s, [type]: { totalAssigned: (s[type]?.totalAssigned || 0) + staff.length, batchCount: (s[type]?.batchCount || 0) + 1 } }));
  };

  return (
    <div style={{ height: "100vh", display: "flex", flexDirection: "column", background: C.bg, fontFamily: "'Noto Sans Devanagari', Georgia, serif" }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;600;700;800;900&display=swap');
        @keyframes fadeIn{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}
        @keyframes slideUp{from{transform:translateY(100%)}to{transform:translateY(0)}}
        @keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
        *{box-sizing:border-box}
        button{font-family:inherit}
        input{font-family:inherit}
        ::-webkit-scrollbar{width:5px;height:5px}
        ::-webkit-scrollbar-track{background:${C.surface}}
        ::-webkit-scrollbar-thumb{background:${C.border};border-radius:3px}
      `}</style>

      {/* ── AppBar ── */}
      <div style={{ background: C.district, padding: "0 20px", flexShrink: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 14, padding: "14px 0 0" }}>
          <button
            onClick={() => nav("/")}
            className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0"
            style={{ background: 'rgba(255,255,255,0.15)' }}
          >
            <ChevronLeft size={20} color="white" />
          </button>
          <div style={{ flex: 1 }}>
            <div style={{ color: "white", fontWeight: 800, fontSize: 16 }}>जनपदीय कानून व्यवस्था</div>
            <div style={{ color: "rgba(255,255,255,.65)", fontSize: 11 }}>मानक + ड्यूटी असाइनमेंट</div>
          </div>
          {/* Actions */}
          <div style={{ display: "flex", gap: 4, alignItems: "center" }}>
            <button onClick={simulateLoad} style={{ background: "rgba(255,255,255,.15)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
              <RefreshCw size={16} color="white" />
            </button>
            <button onClick={clearAll} style={{ background: "rgba(255,255,255,.15)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
              <Trash2 size={16} color="white" />
            </button>
            {changed && <span style={{ background: "rgba(255,255,255,.18)", color: "white", fontSize: 10, fontWeight: 800, borderRadius: 20, padding: "3px 10px" }}>अनसेव्ड</span>}
          </div>
        </div>
        {/* Tabs */}
        <div style={{ display: "flex", marginTop: 12, gap: 2 }}>
          {[["manak", "मानक"], ["duty", "ड्यूटी"]].map(([v, l]) => (
            <button key={v} onClick={() => { setTab(v); setDetailEntry(null); }}
              style={{
                padding: "10px 24px", border: "none", background: "transparent",
                color: tab === v ? "white" : "rgba(255,255,255,.6)", fontWeight: tab === v ? 800 : 500,
                fontSize: 13, cursor: "pointer", borderBottom: tab === v ? "3px solid white" : "3px solid transparent",
                transition: "all .2s", fontFamily: "inherit"
              }}>
              {l}
            </button>
          ))}
        </div>
      </div>

      {/* ── Auto assign banner ── */}
      {(isJobRunning || jobStatus === "done") &&
        <AutoAssignBanner status={jobStatus} pct={jobPct} assigned={jobAssigned} skipped={jobSkipped}
          onDismiss={() => setJobStatus("")} />}

      {/* ── Body ── */}
      <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>
        {loading
          ? <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center" }}>
            <Loader2 size={32} color={C.district} style={{ animation: "spin 1s linear infinite" }} />
          </div>
          : <div style={{ flex: 1, overflow: "hidden", display: "flex" }}>

            {/* ── MANAK TAB ── */}
            {tab === "manak" && (
              <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
                {/* Summary strip */}
                <div style={{ background: C.surface, padding: "10px 18px", display: "flex", alignItems: "center", gap: 8, borderBottom: `1px solid ${C.border}33`, flexShrink: 0 }}>
                  <Shield size={14} color={C.district} />
                  <span style={{ color: C.dark, fontSize: 11.5, fontWeight: 600, flex: 1 }}>ड्यूटी प्रकार पर टैप करके पुलिस बल सेट करें</span>
                  <span style={{ color: C.district, fontWeight: 800, fontSize: 11.5 }}>{totalAll}</span>
                  <span style={{ color: C.subtle, fontSize: 11 }}>({filledCount}/{duties.length})</span>
                </div>
                {/* List */}
                <div style={{ flex: 1, overflowY: "auto", padding: "14px 16px 16px" }}>
                  {duties.map((entry, i) => (
                    <div key={entry.type} style={{ marginBottom: 10 }}>
                      <DutyRuleCard
                        entry={entry} rule={rules[entry.type]} isSet={hasAny(rules[entry.type])}
                        onEdit={() => openRankEditor(entry)}
                        onEditLabel={() => { setEditingCustom(entry); setAddLabel(entry.labelHi); setAddDialogOpen(true); }}
                        onDelete={() => deleteDuty(entry)} />
                    </div>
                  ))}
                  <div style={{ height: 100 }} />
                </div>
              </div>
            )}

            {/* ── DUTY TAB ── */}
            {tab === "duty" && (
              <div style={{ flex: 1, display: "flex", overflow: "hidden" }}>
                {/* List panel */}
                <div style={{
                  flex: detailEntry ? 0 : 1, minWidth: detailEntry ? "320px" : "100%", maxWidth: detailEntry ? "380px" : "100%",
                  display: "flex", flexDirection: "column", borderRight: detailEntry ? `1px solid ${C.border}33` : "none",
                  transition: "all .3s", overflow: "hidden"
                }}>
                  {/* Summary strip */}
                  <div style={{ background: `${C.assign}0a`, padding: "10px 18px", display: "flex", alignItems: "center", gap: 8, borderBottom: `1px solid ${C.assign}22`, flexShrink: 0 }}>
                    <Users size={14} color={C.assign} />
                    <span style={{ color: C.dark, fontSize: 11.5, fontWeight: 600, flex: 1 }}>ड्यूटी प्रकार पर टैप करें</span>
                    <span style={{ background: `${C.assign}14`, color: C.assign, fontSize: 11, fontWeight: 800, borderRadius: 8, padding: "3px 10px" }}>{assignedAll} Assigned</span>
                  </div>
                  <div style={{ flex: 1, overflowY: "auto", padding: "14px 16px 16px" }}>
                    {duties.map(entry => (
                      <div key={entry.type} style={{ marginBottom: 10 }}>
                        <DutyAssignCard
                          entry={entry} summary={summary[entry.type]}
                          sankhya={entry.sankhya}
                          onTap={() => setDetailEntry(entry)} />
                      </div>
                    ))}
                    <div style={{ height: 100 }} />
                  </div>
                </div>

                {/* Detail panel */}
                {detailEntry && (
                  <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden", animation: "fadeIn .25s ease" }}>
                    <DutyDetailView
                      entry={detailEntry}
                      rule={rules[detailEntry.type]}
                      batches={batches[detailEntry.type] || []}
                      summary={summary[detailEntry.type]}
                      onBack={() => setDetailEntry(null)}
                      onRefresh={() => { }}
                      onAssign={() => setAssignSheetEntry(detailEntry)} />
                  </div>
                )}
              </div>
            )}
          </div>}
      </div>

      {/* ── Bottom Nav ── */}
      <div style={{ background: C.bg, borderTop: `1px solid ${C.border}44`, padding: "10px 16px 14px", flexShrink: 0 }}>
        {/* Auto assign */}
        <button onClick={isJobRunning ? null : startAutoAssign} disabled={isJobRunning}
          style={{
            width: "100%", height: 46, borderRadius: 12, border: "none",
            background: isJobRunning ? C.subtle : C.orange, color: "white", fontWeight: 800,
            fontSize: 13, cursor: isJobRunning ? "not-allowed" : "pointer",
            display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
            marginBottom: 10, opacity: isJobRunning ? .7 : 1
          }}>
          {isJobRunning ? <Loader2 size={17} style={{ animation: "spin 1s linear infinite" }} /> : <Wand2 size={17} />}
          {isJobRunning ? `Running... ${jobPct}%` : "Auto Assign"}
        </button>
        {/* Add + Save */}
        <div style={{ display: "flex", gap: 10 }}>
          <button onClick={() => { setEditingCustom(null); setAddLabel(""); setAddDialogOpen(true); }}
            style={{
              height: 50, padding: "0 16px", borderRadius: 12, border: `1px solid ${C.custom}55`,
              background: `${C.custom}0e`, color: C.custom, fontWeight: 700, fontSize: 13,
              cursor: "pointer", display: "flex", alignItems: "center", gap: 6, whiteSpace: "nowrap"
            }}>
            <Plus size={18} />नया जोड़ें
          </button>
          <button onClick={saving ? null : saveAll} disabled={saving}
            style={{
              flex: 1, height: 50, borderRadius: 12, border: "none",
              background: saving ? C.subtle : C.district, color: "white", fontWeight: 800,
              fontSize: 13, cursor: saving ? "not-allowed" : "pointer",
              display: "flex", alignItems: "center", justifyContent: "center", gap: 8
            }}>
            {saving ? <Loader2 size={17} style={{ animation: "spin 1s linear infinite" }} /> : <Save size={17} />}
            {saving ? "सेव हो रहा है..." : "मानक सेव करें"}
          </button>
        </div>
      </div>

      {/* ── Rank Editor Modal ── */}
      <RankEditorModal open={editorOpen} onClose={() => setEditorOpen(false)}
        entry={editEntry} initial={editEntry ? rules[editEntry.type] : {}} onSave={saveRule} />

      {/* ── Add/Edit Custom Duty Modal ── */}
      <Modal open={addDialogOpen} onClose={() => { setAddDialogOpen(false); setEditingCustom(null); }}
        title={editingCustom ? "ड्यूटी प्रकार संपादित करें" : "नया ड्यूटी प्रकार जोड़ें"}
        color={C.custom} icon={editingCustom ? Edit3 : Plus}
        actions={
          <>
            <Btn onClick={() => { setAddDialogOpen(false); setEditingCustom(null); }} color={C.subtle} variant="outline">रद्द करें</Btn>
            <Btn onClick={addLabel.trim() ? addDuty : null} color={C.custom} icon={editingCustom ? Check : Plus}>{editingCustom ? "अपडेट करें" : "जोड़ें"}</Btn>
          </>
        }>
        <div>
          <div style={{ color: C.subtle, fontSize: 12, fontWeight: 600, marginBottom: 6 }}>ड्यूटी का नाम (हिंदी में)</div>
          <input value={addLabel} onChange={e => setAddLabel(e.target.value)}
            onKeyDown={e => e.key === "Enter" && addLabel.trim() && addDuty()}
            placeholder="जैसे: विशेष मोबाईल ड्यूटी" autoFocus
            style={{
              width: "100%", border: `1.5px solid ${C.border}`, borderRadius: 10,
              padding: "10px 14px", background: "white", color: C.dark, fontSize: 15,
              fontWeight: 700, outline: "none", boxSizing: "border-box"
            }} />
        </div>
      </Modal>

      {/* ── Assign Staff Sheet ── */}
      <AssignStaffSheet open={!!assignSheetEntry} entry={assignSheetEntry}
        onClose={() => setAssignSheetEntry(null)} onAssign={handleAssign} />
    </div>
  );
}