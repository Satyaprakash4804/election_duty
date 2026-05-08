import { useState, useEffect, useRef, useCallback } from "react";
import {
  Shield, Car, Building2, PlusCircle, Save, RefreshCw, Trash2,
  Zap, Users, ChevronRight, Edit3, X, Check, AlertTriangle,
  Eye, Plus, Loader2, Bus, StickyNote,
  Search, CheckCircle2, Info, Gavel, ArrowLeft,
  UserMinus, Phone, Hash,
  BarChart3, ClipboardList, Wand2,
  RotateCcw, Vote, TreePine, Settings2, Home, Siren,
  Printer, ChevronLeft, AlertCircle, TrendingUp,
  Wrench, Minus, Table2, FileText, Activity,
  ChevronDown, ChevronUp, Filter,
  ShieldOff, UserCheck, Layers, ShieldCheck
} from "lucide-react";
import toast, { Toaster } from "react-hot-toast";
import api from "../../api/client";

// Import the rank editor page (replaces inline ManakRankEditorPage)
import ManakRankEditorPage from "./ManakRankEditorPage";
import DistrictDutyPrintPage from "../../components/Districtdutyprintpage";
import { useNavigate } from "react-router-dom";
// Import the print report page
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

// ── Icon map ──────────────────────────────────────────────────────────────────
const ICON_MAP = {
  cluster_mobile: Car,
  thana_mobile: Siren,
  thana_reserve: BarChart3,
  thana_extra_mobile: PlusCircle,
  sector_pol_mag_mobile: Gavel,
  zonal_pol_mag_mobile: TreePine,
  sdm_co_mobile: Settings2,
  chowki_mobile: Home,
  barrier_picket: Shield,
  evm_security: Vote,
  adm_sp_mobile: Shield,
  dm_sp_mobile: Shield,
  observer_security: Eye,
  hq_reserve: Building2,
};

const DutyIcon = ({ type, size = 20, color }) => {
  const Ic = ICON_MAP[type] || ClipboardList;
  return <Ic size={size} color={color} />;
};

// ── Rank color ────────────────────────────────────────────────────────────────
const rankColor = (rank) =>
({
  SP: "#6A1B9A", ASP: "#1565C0", DSP: "#1A5276",
  Inspector: "#2E7D32", SI: "#558B2F", ASI: "#8B6914",
  "Head Constable": "#B8860B", Constable: "#6D4C41",
}[rank] || C.primary);

// ── Helpers ───────────────────────────────────────────────────────────────────
const hasAny = (r) =>
  r && ["siArmedCount", "siUnarmedCount", "hcArmedCount", "hcUnarmedCount",
    "constArmedCount", "constUnarmedCount", "auxArmedCount", "auxUnarmedCount", "pacCount"]
    .some(k => (r[k] || 0) > 0);

const totalStaffRule = (r) => {
  if (!r) return 0;
  return ["siArmedCount", "siUnarmedCount", "hcArmedCount", "hcUnarmedCount",
    "constArmedCount", "constUnarmedCount", "auxArmedCount", "auxUnarmedCount"]
    .reduce((s, k) => s + (r[k] || 0), 0);
};

// ── Progress Bar ──────────────────────────────────────────────────────────────
const ProgressBar = ({ value, color, height = 5 }) => (
  <div style={{ background: `${color}22`, borderRadius: 4, overflow: "hidden", height }}>
    <div style={{
      width: `${Math.min((value || 0) * 100, 100)}%`, background: color,
      height: "100%", borderRadius: 4, transition: "width .4s ease"
    }} />
  </div>
);

// ── Stat Chip ─────────────────────────────────────────────────────────────────
const StatChip = ({ label, value, color }) => (
  <div style={{
    background: `${color}14`, border: `1px solid ${color}33`, borderRadius: 10,
    padding: "8px 14px", textAlign: "center", minWidth: 72
  }}>
    <div style={{ color, fontSize: 20, fontWeight: 900, lineHeight: 1 }}>{value}</div>
    <div style={{ color, fontSize: 10, fontWeight: 600, opacity: .75, marginTop: 2 }}>{label}</div>
  </div>
);

// ── Chip Row ──────────────────────────────────────────────────────────────────
const ChipRow = ({ rule, color }) => {
  const chips = [];
  [["SI", "siArmedCount", "siUnarmedCount"], ["HC", "hcArmedCount", "hcUnarmedCount"],
  ["Const", "constArmedCount", "constUnarmedCount"], ["Aux", "auxArmedCount", "auxUnarmedCount"]]
    .forEach(([label, ak, uk]) => {
      const a = rule[ak] || 0, u = rule[uk] || 0;
      if (a + u > 0) chips.push({ label, a, u });
    });
  const pac = rule.pacCount || 0;
  if (!chips.length && !pac) return null;
  return (
    <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginTop: 8 }}>
      {chips.map(({ label, a, u }) => (
        <span key={label} style={{
          background: `${color}12`, border: `1px solid ${color}40`, color,
          borderRadius: 6, padding: "2px 8px", fontSize: 11, fontWeight: 700,
          display: "inline-flex", alignItems: "center", gap: 4
        }}>
          {label}:&nbsp;
          {a > 0 && <span style={{ color: "#6A1B9A", fontWeight: 900 }}>⚔{a}</span>}
          {a > 0 && u > 0 && <span style={{ opacity: .4 }}>/</span>}
          {u > 0 && <span style={{ color: "#1A5276", fontWeight: 900 }}>🛡{u}</span>}
        </span>
      ))}
      {pac > 0 && (
        <span style={{
          background: "#00695C14", border: "1px solid #00695C44", color: "#00695C",
          borderRadius: 6, padding: "2px 8px", fontSize: 11, fontWeight: 700
        }}>PAC: {pac}</span>
      )}
    </div>
  );
};

// ── Confirm Dialog ────────────────────────────────────────────────────────────
const ConfirmDialog = ({ open, title, message, onConfirm, onCancel, confirmText = "हटाएं", confirmColor = C.error, icon: Icon = AlertTriangle }) => {
  if (!open) return null;
  return (
    <div style={{
      position: "fixed", inset: 0, zIndex: 2000, display: "flex", alignItems: "center",
      justifyContent: "center", background: "rgba(0,0,0,.5)", backdropFilter: "blur(4px)"
    }}>
      <div style={{
        background: C.bg, borderRadius: 18, padding: 28, width: "100%", maxWidth: 420,
        boxShadow: "0 24px 80px rgba(0,0,0,.3)", border: `1.5px solid ${confirmColor}55`
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
          <div style={{ width: 38, height: 38, background: `${confirmColor}18`, borderRadius: 10, display: "flex", alignItems: "center", justifyContent: "center" }}>
            <Icon size={18} color={confirmColor} />
          </div>
          <span style={{ color: confirmColor, fontWeight: 800, fontSize: 15 }}>{title}</span>
        </div>
        <p style={{ color: C.dark, fontSize: 13, lineHeight: 1.6, marginBottom: 22 }}>{message}</p>
        <div style={{ display: "flex", justifyContent: "flex-end", gap: 10 }}>
          <button onClick={onCancel} style={{
            padding: "8px 18px", borderRadius: 9, border: `1px solid ${C.border}`,
            background: "transparent", color: C.subtle, fontWeight: 600, fontSize: 13, cursor: "pointer", fontFamily: "inherit"
          }}>रद्द</button>
          <button onClick={onConfirm} style={{
            padding: "8px 18px", borderRadius: 9, border: "none",
            background: confirmColor, color: "white", fontWeight: 700, fontSize: 13, cursor: "pointer", fontFamily: "inherit"
          }}>{confirmText}</button>
        </div>
      </div>
    </div>
  );
};

// ── Auto Assign Banner ────────────────────────────────────────────────────────
const AutoAssignBanner = ({ status, pct, assigned, skipped, onDismiss }) => {
  const isRunning = status === "running" || status === "pending";
  const color = isRunning ? C.orange : C.success;
  return (
    <div style={{ background: `${color}10`, borderBottom: `1px solid ${color}30`, padding: "10px 20px", flexShrink: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        {isRunning
          ? <Loader2 size={16} color={C.orange} style={{ animation: "spin 1s linear infinite" }} />
          : <CheckCircle2 size={16} color={C.success} />}
        <span style={{ flex: 1, color, fontSize: 12, fontWeight: 800 }}>
          {isRunning ? `Auto-assign चल रही है... ${pct}%` : `${assigned} Staff assign हुए, ${skipped} skip`}
        </span>
        <button onClick={onDismiss} style={{ background: "none", border: "none", cursor: "pointer", padding: 2 }}>
          <X size={14} color={color} />
        </button>
      </div>
      {isRunning && <div style={{ marginTop: 8 }}><ProgressBar value={pct / 100} color={C.orange} height={4} /></div>}
    </div>
  );
};

// ── Shortage chip label ───────────────────────────────────────────────────────
const shortageLabel = (s) => {
  const rank = s.rank || "";
  const short = rank === "Head Constable" ? "HC" : rank === "Constable" ? "Const" : rank;
  return `${short}-${s.armed ? "स." : "नि."} ×${s.missing || 0}`;
};

// ══════════════════════════════════════════════════════════════════════════════
//  ASSIGN STAFF PANEL
// ══════════════════════════════════════════════════════════════════════════════
const AssignStaffPanel = ({ entry, onClose, onAssigned }) => {
  const color = entry?.isDefault ? C.district : C.custom;
  const [staff, setStaff] = useState([]);
  const [selected, setSelected] = useState(new Set());
  const [q, setQ] = useState("");
  const [rankFilter, setRankFilter] = useState("");
  const [busNo, setBusNo] = useState("");
  const [note, setNote] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const debounce = useRef(null);
  const listRef = useRef(null);

  const load = useCallback(async (reset = false) => {
    if (!entry) return;
    const p = reset ? 1 : page;
    if (!hasMore && !reset) return;
    reset ? setLoading(true) : setLoadingMore(true);
    try {
      let url = `/admin/district-duty/${entry.type}/available-staff?page=${p}&limit=20&q=${encodeURIComponent(q)}`;
      if (rankFilter) url += `&rank=${encodeURIComponent(rankFilter)}`;
      const res = await api.get(url);
      const d = res.data?.data || res.data || {};
      const items = d.data || [];
      const totalPages = d.totalPages || 1;
      if (reset) setStaff(items); else setStaff(prev => [...prev, ...items]);
      setHasMore(p < totalPages);
      setPage(p + 1);
    } catch { }
    finally { setLoading(false); setLoadingMore(false); }
  }, [entry, page, q, rankFilter, hasMore]);

  useEffect(() => {
    if (entry) { setStaff([]); setPage(1); setHasMore(true); setSelected(new Set()); load(true); }
  }, [entry?.type, q, rankFilter]);

  const handleScroll = () => {
    if (!listRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = listRef.current;
    if (scrollHeight - scrollTop - clientHeight < 120 && hasMore && !loadingMore) load(false);
  };

  const toggle = (id) => setSelected(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n; });

  const handleAssign = async () => {
    if (!selected.size) return;
    setSaving(true);
    try {
      const res = await api.post(`/admin/district-duty/${entry.type}/assign`, {
        staffIds: [...selected], busNo: busNo.trim(), note: note.trim()
      });
      const d = res.data?.data || res.data || {};
      toast.success(`Batch ${d.batchNo || ""} बना: ${d.assigned || selected.size} Assigned`);
      onAssigned();
      onClose();
    } catch (e) {
      toast.error("Assign विफल: " + (e?.response?.data?.message || e.message));
    } finally { setSaving(false); }
  };

  const RANKS_FILTER = ["SI", "ASI", "Head Constable", "Constable"];
  if (!entry) return null;

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", background: C.bg }}>
      <div style={{ background: color, padding: "16px 20px", display: "flex", alignItems: "center", gap: 12, flexShrink: 0 }}>
        <button onClick={onClose} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
          <ArrowLeft size={18} color="white" />
        </button>
        <div style={{ flex: 1 }}>
          <div style={{ color: "white", fontWeight: 800, fontSize: 14 }}>Staff Assign करें</div>
          <div style={{ color: "rgba(255,255,255,.65)", fontSize: 11 }}>{entry.labelHi || entry.label}</div>
        </div>
        {selected.size > 0 && <div style={{ background: "rgba(255,255,255,.2)", borderRadius: 20, padding: "4px 12px", color: "white", fontSize: 12, fontWeight: 800 }}>{selected.size} चुने</div>}
      </div>
      <div style={{ padding: "12px 16px", borderBottom: `1px solid ${C.border}33`, flexShrink: 0 }}>
        <div style={{ display: "flex", gap: 6, overflowX: "auto", marginBottom: 10, paddingBottom: 2 }}>
          {["सभी", ...RANKS_FILTER].map((r, i) => {
            const v = i === 0 ? "" : r; const sel = rankFilter === v;
            const c = i === 0 ? C.district : rankColor(r);
            return <button key={r} onClick={() => setRankFilter(v)} style={{
              padding: "4px 12px", borderRadius: 20, border: `1px solid ${sel ? c : C.border + "66"}`,
              background: sel ? c : "white", color: sel ? "white" : C.dark, fontSize: 11, fontWeight: sel ? 700 : 500,
              cursor: "pointer", whiteSpace: "nowrap", transition: "all .15s", fontFamily: "inherit"
            }}>{r}</button>;
          })}
        </div>
        <div style={{ position: "relative", marginBottom: 8 }}>
          <Search size={15} color={C.subtle} style={{ position: "absolute", left: 11, top: "50%", transform: "translateY(-50%)" }} />
          <input
            onChange={e => { clearTimeout(debounce.current); debounce.current = setTimeout(() => setQ(e.target.value), 300); }}
            placeholder="नाम, PNO खोजें..."
            style={{ width: "100%", border: `1px solid ${C.border}`, borderRadius: 9, padding: "9px 12px 9px 34px", background: "white", color: C.dark, fontSize: 13, outline: "none", boxSizing: "border-box", fontFamily: "inherit" }}
          />
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          {[{ val: busNo, set: setBusNo, ph: "Bus No (optional)", Icon: Bus }, { val: note, set: setNote, ph: "Note (optional)", Icon: StickyNote }].map(({ val, set, ph, Icon }, i) => (
            <div key={i} style={{ flex: 1, position: "relative" }}>
              <Icon size={12} color={color} style={{ position: "absolute", left: 9, top: "50%", transform: "translateY(-50%)" }} />
              <input value={val} onChange={e => set(e.target.value)} placeholder={ph}
                style={{ width: "100%", border: `1px solid ${C.border}`, borderRadius: 8, padding: "7px 10px 7px 26px", background: "white", color: C.dark, fontSize: 12, outline: "none", boxSizing: "border-box", fontFamily: "inherit" }} />
            </div>
          ))}
        </div>
      </div>
      <div ref={listRef} onScroll={handleScroll} style={{ flex: 1, overflowY: "auto", padding: "8px 12px" }}>
        {loading ? (
          <div style={{ textAlign: "center", padding: 48 }}><Loader2 size={28} color={C.district} style={{ animation: "spin 1s linear infinite" }} /></div>
        ) : staff.length === 0 ? (
          <div style={{ textAlign: "center", padding: 48, color: C.subtle, fontSize: 13 }}>कोई unassigned staff नहीं मिला</div>
        ) : staff.map(s => {
          const isSel = selected.has(s.id);
          const rc = rankColor(s.rank);
          const initials = (s.name || "").split(" ").filter(Boolean).slice(0, 2).map(w => w[0]).join("").toUpperCase();
          return (
            <div key={s.id} onClick={() => toggle(s.id)} style={{
              display: "flex", alignItems: "center", gap: 10, padding: "9px 10px", borderRadius: 9,
              border: `${isSel ? 1.8 : 1}px solid ${isSel ? color : C.border + "44"}`,
              background: isSel ? `${color}08` : "white", marginBottom: 5, cursor: "pointer", transition: "all .14s"
            }}>
              <div style={{
                width: 22, height: 22, borderRadius: "50%", border: `1.5px solid ${isSel ? color : C.border}`,
                background: isSel ? color : "white", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0
              }}>{isSel && <Check size={12} color="white" />}</div>
              <div style={{ width: 36, height: 36, background: `${rc}18`, borderRadius: "50%", border: `1px solid ${rc}28`, display: "flex", alignItems: "center", justifyContent: "center", color: rc, fontWeight: 900, fontSize: 12, flexShrink: 0 }}>{initials}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ color: isSel ? color : C.dark, fontWeight: 700, fontSize: 13, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{s.name}</div>
                <div style={{ display: "flex", gap: 6, alignItems: "center", flexWrap: "wrap", marginTop: 2 }}>
                  <span style={{ background: `${rc}14`, color: rc, fontSize: 9, fontWeight: 700, borderRadius: 4, padding: "1px 5px", border: `1px solid ${rc}28` }}>{s.rank}</span>
                  {s.pno && <span style={{ color: C.subtle, fontSize: 10 }}>{s.pno}</span>}
                  {s.thana && <span style={{ color: C.subtle, fontSize: 10, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 120 }}>{s.thana}</span>}
                </div>
              </div>
            </div>
          );
        })}
        {loadingMore && <div style={{ textAlign: "center", padding: 10 }}><Loader2 size={18} color={C.district} style={{ animation: "spin 1s linear infinite" }} /></div>}
      </div>
      <div style={{ padding: "10px 14px 16px", borderTop: `1px solid ${C.border}33`, flexShrink: 0 }}>
        <button onClick={selected.size > 0 && !saving ? handleAssign : undefined} disabled={selected.size === 0 || saving}
          style={{
            width: "100%", height: 48, borderRadius: 11, border: "none",
            background: selected.size === 0 ? C.subtle : color, color: "white", fontWeight: 800, fontSize: 13,
            cursor: selected.size === 0 ? "not-allowed" : "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
            opacity: selected.size === 0 ? .7 : 1, transition: "all .2s", fontFamily: "inherit"
          }}>
          {saving ? <Loader2 size={17} style={{ animation: "spin 1s linear infinite" }} /> : <CheckCircle2 size={17} />}
          {saving ? "Assigning..." : selected.size === 0 ? "Staff चुनें" : `${selected.size} Staff Assign करें (New Batch)`}
        </button>
      </div>
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════════
//  SHORTAGE REPORT MODAL
// ══════════════════════════════════════════════════════════════════════════════
const ShortageReportModal = ({ open, report, duties, onClose, onFix }) => {
  if (!open) return null;
  const entries = Object.entries(report || {}).filter(([, v]) => v?.shortages?.length > 0);
  const rShort = (r) => r === "Head Constable" ? "HC" : r === "Constable" ? "Const" : r;

  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 1500, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.5)", backdropFilter: "blur(4px)" }}>
      <div style={{ background: C.bg, borderRadius: 18, width: "100%", maxWidth: 560, maxHeight: "82vh", display: "flex", flexDirection: "column", boxShadow: "0 24px 80px rgba(0,0,0,.3)", border: `1.5px solid ${C.error}55` }}>
        <div style={{ background: C.error, padding: "16px 20px", borderRadius: "18px 18px 0 0", display: "flex", alignItems: "center", gap: 10 }}>
          <AlertTriangle size={22} color="white" />
          <div style={{ flex: 1 }}>
            <div style={{ color: "white", fontWeight: 800, fontSize: 15 }}>स्टाफ की कमी की रिपोर्ट</div>
            <div style={{ color: "rgba(255,255,255,.7)", fontSize: 11 }}>इन ड्यूटी में पूरा बैच नहीं बन पाया</div>
          </div>
          <button onClick={onClose} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <X size={16} color="white" />
          </button>
        </div>
        <div style={{ flex: 1, overflowY: "auto", padding: "14px 16px" }}>
          {entries.length === 0 ? (
            <div style={{ textAlign: "center", padding: 32, color: C.success, fontWeight: 700 }}>कोई कमी नहीं — सभी batches पूरे बने ✓</div>
          ) : entries.map(([dutyType, v]) => {
            const label = (v.label || dutyType);
            const made = v.batches_made || 0, target = v.batches_target || 0;
            const list = (v.shortages || []);
            return (
              <div key={dutyType} style={{ background: "white", borderRadius: 12, border: `1px solid ${C.error}30`, padding: 14, marginBottom: 10 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
                  <span style={{ color: C.dark, fontWeight: 800, fontSize: 13, flex: 1 }}>{label}</span>
                  <span style={{ background: `${made >= target ? C.success : C.orange}14`, color: made >= target ? C.success : C.orange, fontSize: 10.5, fontWeight: 800, borderRadius: 6, padding: "3px 8px" }}>{made}/{target} batches</span>
                </div>
                <div style={{ color: C.subtle, fontSize: 10.5, fontWeight: 700, marginBottom: 6 }}>गायब staff (per batch):</div>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 12 }}>
                  {list.map((s, i) => {
                    const rc = rankColor(s.rank || "");
                    return (
                      <span key={i} style={{ background: `${rc}12`, border: `1px solid ${rc}30`, borderRadius: 6, padding: "4px 8px", display: "inline-flex", alignItems: "center", gap: 5 }}>
                        <span style={{ color: rc, fontSize: 10.5, fontWeight: 700 }}>{rShort(s.rank)} {s.armed ? "सशस्त्र" : "निःशस्त्र"}</span>
                        <span style={{ background: C.error, color: "white", borderRadius: 4, padding: "1px 5px", fontSize: 9.5, fontWeight: 900 }}>×{s.missing}</span>
                      </span>
                    );
                  })}
                </div>
                <button onClick={() => { onClose(); onFix(dutyType, label); }} style={{
                  width: "100%", padding: "8px", borderRadius: 8, border: `1px solid ${C.district}44`,
                  background: `${C.district}0e`, color: C.district, fontWeight: 800, fontSize: 12, cursor: "pointer",
                  display: "flex", alignItems: "center", justifyContent: "center", gap: 6, fontFamily: "inherit"
                }}>
                  <Wrench size={13} />कमी ठीक करें
                </button>
              </div>
            );
          })}
        </div>
        <div style={{ background: C.surface, padding: "10px 16px", borderRadius: "0 0 18px 18px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <Info size={13} color={C.primary} />
            <span style={{ color: C.primary, fontSize: 11, fontWeight: 600 }}>मानक बदलें या नया staff add करें, फिर auto-assign चलाएं</span>
          </div>
        </div>
      </div>
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════════
//  SHORTAGE RESOLVER PANEL
// ══════════════════════════════════════════════════════════════════════════════
const ShortageResolverPanel = ({ dutyType, dutyLabel, isDefault, onBack, onResolved }) => {
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [data, setData] = useState(null);
  const [overrideMode, setOverrideMode] = useState(false);
  const [override, setOverride] = useState({});

  useEffect(() => { if (dutyType) loadData(); }, [dutyType]);

  const loadData = async () => {
    setLoading(true); setError("");
    try {
      const res = await api.get(`/admin/district-duty/${dutyType}/availability`);
      const d = res.data?.data || res.data;
      setData(d);
      const initOverride = {};
      (d.breakdown || []).forEach(s => {
        const camel = snakeToCamel(s.ruleField || "");
        initOverride[camel] = s.perBatch || 0;
      });
      setOverride(initOverride);
    } catch (e) { setError(e?.response?.data?.message || e.message); }
    finally { setLoading(false); }
  };

  const snakeToCamel = (s) => {
    const parts = s.split("_");
    return parts[0] + parts.slice(1).map(p => p ? p[0].toUpperCase() + p.slice(1) : "").join("");
  };

  const slots = (data?.breakdown || []).map(s => ({ ...s, camelField: snakeToCamel(s.ruleField || "") }));
  const pool = {};
  (data?.availablePool || []).forEach(p => { pool[`${p.rank}|${p.armed ? 1 : 0}`] = p; });
  const sankhya = data?.sankhya || 0;
  const totalAssigned = slots.reduce((a, s) => a + (s.assigned || 0), 0);
  const totalPerBatch = slots.reduce((a, s) => a + (s.perBatch || 0), 0);
  const batchesMade = totalPerBatch > 0 ? Math.floor(totalAssigned / totalPerBatch) : 0;
  const batchesGap = Math.max(0, sankhya - batchesMade);
  const overridePerBatch = Object.values(override).reduce((a, v) => a + (v || 0), 0);

  const slotRemaining = (s) => {
    const key = `${s.rank}|${s.armed ? 1 : 0}`;
    const p = pool[key]; if (!p) return 0;
    let used = 0;
    slots.forEach(other => {
      if (other.camelField === s.camelField) return;
      if (`${other.rank}|${other.armed ? 1 : 0}` === key) used += (override[other.camelField] || 0) * batchesGap;
    });
    return Math.max(0, (p.free || 0) - used);
  };

  const validateOverride = () => {
    const errors = [];
    const consumed = {};
    slots.forEach(s => {
      const n = override[s.camelField] || 0;
      if (n <= 0) return;
      const key = `${s.rank}|${s.armed ? 1 : 0}`;
      consumed[key] = (consumed[key] || 0) + n * batchesGap;
    });
    Object.entries(consumed).forEach(([key, need]) => {
      const p = pool[key]; if (!p) return;
      if (need > (p.free || 0)) errors.push(`${p.rank} ${p.armed ? "सशस्त्र" : "निःशस्त्र"} — ज़रूरत ${need}, उपलब्ध ${p.free || 0}`);
    });
    if (overridePerBatch === 0) errors.push("कम से कम एक रैंक चुनें");
    return errors;
  };

  const handleAutoFit = async () => {
    if (batchesGap <= 0) { toast("सभी batches पहले से बने हैं"); return; }
    const newPB = {};
    const remFree = {};
    Object.entries(pool).forEach(([k, p]) => remFree[k] = p.free || 0);
    slots.forEach(s => {
      const key = `${s.rank}|${s.armed ? 1 : 0}`;
      const free = remFree[key] || 0;
      const maxFromPool = Math.floor(free / batchesGap);
      const val = Math.min(s.perBatch || 0, maxFromPool);
      newPB[s.camelField] = Math.max(0, val);
      remFree[key] = Math.max(0, free - val * batchesGap);
    });
    const totalPB = Object.values(newPB).reduce((a, v) => a + v, 0);
    if (totalPB === 0) { toast.error("मानक auto-fit नहीं हो सकता — staff उपलब्ध नहीं"); return; }
    if (!confirm("मानक को उपलब्ध staff के हिसाब से auto-fit करें?")) return;
    setBusy(true);
    try {
      await api.put(`/admin/district-rules/${dutyType}/adjust`, newPB);
      toast.success("मानक update हो गया ✓");
      await loadData();
      onResolved();
    } catch (e) { toast.error("Update विफल: " + (e?.response?.data?.message || e.message)); }
    finally { setBusy(false); }
  };

  const handleOverrideAssign = async () => {
    const errors = validateOverride();
    if (errors.length) { toast.error(errors[0]); return; }
    if (!confirm(`${batchesGap} batches में ${overridePerBatch} staff/batch assign करें?`)) return;
    setBusy(true);
    try {
      const res = await api.post(`/admin/district-duty/${dutyType}/auto-assign-override`, {
        perBatch: override, syncManak: true
      });
      const d = res.data?.data || res.data || {};
      const partial = (d.shortages || []).length > 0;
      toast[partial ? "error" : "success"](`${d.batchesMade || 0} batches • ${d.assigned || 0} staff assign ${partial ? "• अब भी कमी" : "✓"}`);
      await loadData();
      onResolved();
    } catch (e) { toast.error("Assign विफल: " + (e?.response?.data?.message || e.message)); }
    finally { setBusy(false); }
  };

  if (loading) return <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "100%", background: C.bg }}><Loader2 size={32} color={C.error} style={{ animation: "spin 1s linear infinite" }} /></div>;
  if (error) return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", background: C.bg }}>
      <div style={{ background: C.error, padding: "16px 20px", display: "flex", alignItems: "center", gap: 10 }}>
        <button onClick={onBack} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><ArrowLeft size={18} color="white" /></button>
        <span style={{ color: "white", fontWeight: 800, fontSize: 14 }}>कमी ठीक करें</span>
      </div>
      <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 12, padding: 32 }}>
        <AlertCircle size={48} color={C.error} />
        <div style={{ color: C.error, fontWeight: 800, fontSize: 14 }}>लोड नहीं हो पाया</div>
        <div style={{ color: C.subtle, fontSize: 12, textAlign: "center" }}>{error}</div>
        <button onClick={loadData} style={{ padding: "9px 20px", borderRadius: 9, border: "none", background: C.error, color: "white", fontWeight: 700, fontSize: 13, cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "inherit" }}><RefreshCw size={14} />फिर से</button>
      </div>
    </div>
  );

  const isDone = batchesGap <= 0;
  const canSubmitOverride = overrideMode && validateOverride().length === 0 && batchesGap > 0 && overridePerBatch > 0;

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", background: C.bg, position: "relative" }}>
      {busy && <div style={{ position: "absolute", inset: 0, zIndex: 10, background: "rgba(0,0,0,.45)", display: "flex", alignItems: "center", justifyContent: "center" }}><Loader2 size={32} color="white" style={{ animation: "spin 1s linear infinite" }} /></div>}
      <div style={{ background: C.error, padding: "16px 20px", display: "flex", alignItems: "center", gap: 12, flexShrink: 0 }}>
        <button onClick={onBack} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><ArrowLeft size={18} color="white" /></button>
        <div style={{ flex: 1 }}>
          <div style={{ color: "white", fontWeight: 800, fontSize: 14 }}>कमी ठीक करें</div>
          <div style={{ color: "rgba(255,255,255,.65)", fontSize: 11 }}>{dutyLabel}</div>
        </div>
        <button onClick={loadData} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><RefreshCw size={15} color="white" /></button>
      </div>
      <div style={{ flex: 1, overflowY: "auto", padding: "16px" }}>
        {/* Summary card */}
        <div style={{ background: isDone ? `${C.success}0c` : `${C.error}0c`, border: `1px solid ${isDone ? C.success : C.error}30`, borderRadius: 12, padding: 14, marginBottom: 14 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 10 }}>
            {isDone ? <CheckCircle2 size={18} color={C.success} /> : <AlertTriangle size={18} color={C.error} />}
            <span style={{ color: isDone ? C.success : C.error, fontWeight: 800, fontSize: 13 }}>{isDone ? "सभी batches पूर्ण" : "अधूरी ड्यूटी"}</span>
          </div>
          <div style={{ display: "flex", gap: 8 }}>
            {[["batches", `${batchesMade}/${sankhya}`, isDone ? C.success : C.error], ["staff", `${totalAssigned}`, C.district], ["संख्या", `${sankhya}`, C.orange], batchesGap > 0 && ["बाकी", `${batchesGap}`, C.error]].filter(Boolean).map(([l, v, c]) => (
              <div key={l} style={{ flex: 1, background: "rgba(255,255,255,.7)", borderRadius: 8, padding: "6px 4px", textAlign: "center" }}>
                <div style={{ color: c, fontSize: 16, fontWeight: 900 }}>{v}</div>
                <div style={{ color: C.subtle, fontSize: 9.5, fontWeight: 600 }}>{l}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Breakdown table */}
        <div style={{ background: "white", borderRadius: 12, border: `1px solid ${C.border}40`, overflow: "hidden", marginBottom: 16 }}>
          <div style={{ background: "#1A1A2E", padding: "10px 14px", display: "flex", alignItems: "center", gap: 6 }}>
            <Table2 size={13} color="white" /><span style={{ color: "white", fontWeight: 800, fontSize: 12 }}>रैंक-वार विवरण</span>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "100px 1fr 1fr 1fr 1fr", background: "#F8F4FF", padding: "7px 10px", fontSize: 10.5, fontWeight: 800, color: C.dark }}>
            <span>रैंक</span><span style={{ textAlign: "center" }}>आवश्यक</span><span style={{ textAlign: "center" }}>Assigned</span><span style={{ textAlign: "center" }}>कमी</span><span style={{ textAlign: "center" }}>Free</span>
          </div>
          {slots.map((s, i) => {
            const hasGap = (s.gap || 0) > 0;
            const cantFill = (s.gap || 0) > (s.freeInSystem || 0);
            const rc = rankColor(s.rank || "");
            return (
              <div key={i} style={{ display: "grid", gridTemplateColumns: "100px 1fr 1fr 1fr 1fr", padding: "8px 10px", background: i % 2 === 0 ? "white" : "#FDFBFF", borderTop: `1px solid ${C.border}18` }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <div style={{ width: 3, height: 16, background: rc, borderRadius: 2 }} />
                  <div>
                    <div style={{ color: C.dark, fontSize: 11.5, fontWeight: 800 }}>{s.labelShort || s.rank}</div>
                    <div style={{ color: C.subtle, fontSize: 9 }}>{s.armed ? "सशस्त्र" : "निःशस्त्र"}</div>
                  </div>
                </div>
                <div style={{ textAlign: "center", color: C.dark, fontSize: 11.5, fontWeight: 700 }}>{s.required || 0}</div>
                <div style={{ textAlign: "center", color: (s.assigned || 0) >= (s.required || 0) ? C.success : C.dark, fontSize: 11.5, fontWeight: 800 }}>{s.assigned || 0}</div>
                <div style={{ textAlign: "center", color: hasGap ? C.error : C.success, fontSize: 11.5, fontWeight: 900 }}>{hasGap ? (s.gap || 0) : "-"}</div>
                <div style={{ textAlign: "center", color: cantFill && hasGap ? C.error : (s.freeInSystem || 0) > 0 ? C.success : C.subtle, fontSize: 11.5, fontWeight: 700 }}>{s.freeInSystem || 0}</div>
              </div>
            );
          })}
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12 }}>
          <div style={{ width: 30, height: 30, background: `${C.orange}14`, borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center" }}><Wrench size={15} color={C.orange} /></div>
          <span style={{ color: C.dark, fontWeight: 800, fontSize: 13 }}>समाधान चुनें</span>
        </div>

        {/* Option A: Add staff */}
        {slots.some(s => (s.gap || 0) > (s.freeInSystem || 0)) && (
          <div style={{ background: "white", borderRadius: 12, border: `1px solid ${C.orange}33`, padding: 14, marginBottom: 12 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
              <div style={{ width: 28, height: 28, background: `${C.orange}14`, borderRadius: 7, display: "flex", alignItems: "center", justifyContent: "center" }}><Users size={14} color={C.orange} /></div>
              <span style={{ color: C.dark, fontWeight: 800, fontSize: 13, flex: 1 }}>इन रैंक का नया staff add करें</span>
              <span style={{ background: `${C.orange}12`, color: C.orange, fontSize: 9, fontWeight: 800, borderRadius: 5, padding: "2px 6px" }}>विकल्प A</span>
            </div>
            {slots.filter(s => (s.gap || 0) > (s.freeInSystem || 0)).map((s, i) => {
              const realShort = (s.gap || 0) - (s.freeInSystem || 0);
              return (
                <div key={i} style={{ display: "flex", alignItems: "center", gap: 8, padding: "4px 0" }}>
                  <div style={{ width: 3, height: 16, background: rankColor(s.rank), borderRadius: 2 }} />
                  <span style={{ flex: 1, color: C.dark, fontSize: 12, fontWeight: 700 }}>{s.labelShort || s.rank} {s.armed ? "सशस्त्र" : "निःशस्त्र"}</span>
                  <span style={{ background: `${C.error}12`, color: C.error, border: `1px solid ${C.error}30`, borderRadius: 5, padding: "2px 8px", fontSize: 10.5, fontWeight: 800 }}>+{realShort} जोड़ें</span>
                </div>
              );
            })}
            <div style={{ background: `${C.surface}88`, borderRadius: 8, padding: 8, marginTop: 10, display: "flex", gap: 6 }}>
              <Info size={12} color={C.primary} /><span style={{ color: C.primary, fontSize: 11 }}>Dashboard → Staff section में जाकर नया staff add करें, फिर auto-assign चलाएं।</span>
            </div>
          </div>
        )}

        {/* Option B: Auto-fit manak */}
        <div style={{ background: "white", borderRadius: 12, border: `1px solid ${C.district}33`, padding: 14, marginBottom: 12 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
            <div style={{ width: 28, height: 28, background: `${C.district}14`, borderRadius: 7, display: "flex", alignItems: "center", justifyContent: "center" }}><Settings2 size={14} color={C.district} /></div>
            <span style={{ color: C.dark, fontWeight: 800, fontSize: 13, flex: 1 }}>मानक auto-fit करें</span>
            <span style={{ background: `${C.district}12`, color: C.district, fontSize: 9, fontWeight: 800, borderRadius: 5, padding: "2px 6px" }}>विकल्प B</span>
          </div>
          <p style={{ color: C.subtle, fontSize: 11.5, marginBottom: 12, lineHeight: 1.5 }}>मानक को घटाकर उपलब्ध staff के बराबर लाया जाएगा।</p>
          <button onClick={handleAutoFit} disabled={busy || isDone} style={{
            width: "100%", padding: "10px", borderRadius: 9, border: "none", background: isDone ? C.subtle : C.district, color: "white", fontWeight: 800, fontSize: 13, cursor: isDone ? "not-allowed" : "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: 6, fontFamily: "inherit"
          }}><Settings2 size={15} />मानक auto-fit करें</button>
        </div>

        {/* Option C: Override assign */}
        <div style={{ background: "white", borderRadius: 12, border: `1px solid ${C.success}33`, padding: 14 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
            <div style={{ width: 28, height: 28, background: `${C.success}14`, borderRadius: 7, display: "flex", alignItems: "center", justifyContent: "center" }}><RotateCcw size={14} color={C.success} /></div>
            <span style={{ color: C.dark, fontWeight: 800, fontSize: 13, flex: 1 }}>अलग रैंक से assign करें</span>
            <span style={{ background: `${C.success}12`, color: C.success, fontSize: 9, fontWeight: 800, borderRadius: 5, padding: "2px 6px" }}>विकल्प C</span>
          </div>
          <p style={{ color: C.subtle, fontSize: 11.5, marginBottom: 12, lineHeight: 1.5 }}>हर रैंक की संख्या मैन्युअल सेट करें — मानक auto-update होगा।</p>
          {!overrideMode ? (
            <button onClick={() => setOverrideMode(true)} disabled={isDone} style={{
              width: "100%", padding: "9px", borderRadius: 9, border: `1.5px solid ${C.success}55`, background: "transparent", color: C.success, fontWeight: 700, fontSize: 12, cursor: isDone ? "not-allowed" : "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: 6, fontFamily: "inherit"
            }}><Edit3 size={14} />{isDone ? "सभी batches पूर्ण" : "Override के लिए खोलें"}</button>
          ) : (
            <>
              <div style={{ background: C.bg, borderRadius: 8, border: `1px solid ${C.border}40`, padding: "6px 8px", marginBottom: 10 }}>
                {slots.map((s, i) => {
                  const rem = slotRemaining(s);
                  const val = override[s.camelField] || 0;
                  const invalid = rem < 0;
                  const rc = rankColor(s.rank);
                  return (
                    <div key={i} style={{ display: "flex", alignItems: "center", gap: 8, padding: "7px 4px", borderBottom: i < slots.length - 1 ? `1px solid ${C.border}22` : "none" }}>
                      <div style={{ width: 3, height: 24, background: rc, borderRadius: 2 }} />
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ color: rc, fontSize: 12, fontWeight: 800 }}>{s.labelShort || s.rank}</div>
                        <div style={{ color: C.subtle, fontSize: 10 }}>{s.armed ? "सशस्त्र" : "निःशस्त्र"}</div>
                      </div>
                      <span style={{ background: `${rem > 0 ? C.success : C.error}12`, color: rem > 0 ? C.success : C.error, fontSize: 9.5, fontWeight: 800, borderRadius: 5, padding: "2px 7px" }}>Free:{rem}</span>
                      <button onClick={() => setOverride(o => ({ ...o, [s.camelField]: Math.max(0, val - 1) }))} style={{ width: 26, height: 26, borderRadius: 6, background: `${C.district}12`, border: `1px solid ${C.district}30`, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", fontFamily: "inherit" }}><Minus size={12} color={C.district} /></button>
                      <span style={{ width: 28, textAlign: "center", color: invalid ? C.error : C.dark, fontWeight: 900, fontSize: 14 }}>{val}</span>
                      <button onClick={() => rem > 0 && setOverride(o => ({ ...o, [s.camelField]: val + 1 }))} disabled={rem <= 0} style={{ width: 26, height: 26, borderRadius: 6, background: rem > 0 ? `${C.district}12` : `${C.subtle}10`, border: `1px solid ${rem > 0 ? C.district + "30" : C.subtle + "20"}`, cursor: rem > 0 ? "pointer" : "not-allowed", display: "flex", alignItems: "center", justifyContent: "center", fontFamily: "inherit" }}><Plus size={12} color={rem > 0 ? C.district : C.subtle} /></button>
                    </div>
                  );
                })}
              </div>
              <div style={{ background: `${C.assign}08`, border: `1px solid ${C.assign}28`, borderRadius: 8, padding: 10, marginBottom: 10 }}>
                <div style={{ color: C.assign, fontSize: 11, fontWeight: 700 }}>
                  प्रति-batch: {overridePerBatch} staff • total: {overridePerBatch * batchesGap} in {batchesGap} batches
                </div>
                {validateOverride().map((e, i) => (
                  <div key={i} style={{ display: "flex", alignItems: "center", gap: 5, marginTop: 6, color: C.error, fontSize: 11, fontWeight: 700 }}>
                    <AlertCircle size={11} />{e}
                  </div>
                ))}
              </div>
              <div style={{ display: "flex", gap: 8 }}>
                <button onClick={() => { setOverrideMode(false); const o = {}; slots.forEach(s => o[s.camelField] = s.perBatch || 0); setOverride(o); }} style={{ flex: 1, padding: "9px", borderRadius: 9, border: `1px solid ${C.border}`, background: "transparent", color: C.subtle, fontWeight: 600, fontSize: 12, cursor: "pointer", fontFamily: "inherit" }}>रद्द</button>
                <button onClick={canSubmitOverride && !busy ? handleOverrideAssign : undefined} disabled={!canSubmitOverride || busy} style={{ flex: 2, padding: "9px", borderRadius: 9, border: "none", background: canSubmitOverride ? C.success : C.subtle, color: "white", fontWeight: 800, fontSize: 12, cursor: canSubmitOverride ? "pointer" : "not-allowed", display: "flex", alignItems: "center", justifyContent: "center", gap: 6, fontFamily: "inherit" }}>
                  <CheckCircle2 size={14} />Assign करें + मानक update
                </button>
              </div>
            </>
          )}
        </div>
        <div style={{ height: 20 }} />
      </div>
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY DETAIL PANEL
// ══════════════════════════════════════════════════════════════════════════════
const DutyDetailPanel = ({ entry, rule, onBack, onRefresh }) => {
  const color = entry.isDefault ? C.district : C.custom;
  const [batches, setBatches] = useState([]);
  const [loading, setLoading] = useState(true);
  const [subView, setSubView] = useState(null);
  const [viewBatch, setViewBatch] = useState(null);

  useEffect(() => { loadBatches(); }, [entry.type]);

  const loadBatches = async () => {
    setLoading(true);
    try {
      const res = await api.get(`/admin/district-duty/${entry.type}/batches`);
      setBatches(res.data?.data || res.data || []);
    } catch (e) { toast.error("लोड विफल: " + e.message); }
    finally { setLoading(false); }
  };

  const deleteBatch = async (batchNo) => {
    if (!confirm(`Batch ${batchNo} के सभी staff हटाएं?`)) return;
    try {
      await api.delete(`/admin/district-duty/${entry.type}/batch/${batchNo}`);
      toast.success(`Batch ${batchNo} हटाया गया`);
      loadBatches(); onRefresh();
    } catch (e) { toast.error("Error: " + e.message); }
  };

  const clearAll = async () => {
    if (!confirm(`"${entry.labelHi || entry.label}" के सभी assignments हटाएं?`)) return;
    try {
      await api.delete(`/admin/district-duty/${entry.type}/clear`);
      toast.success("सभी assignments हटाए गए");
      loadBatches(); onRefresh();
    } catch (e) { toast.error("Error: " + e.message); }
  };

  const totalAsgn = batches.reduce((s, b) => s + (b.staffCount || 0), 0);
  const sankhya = entry.sankhya || 0;

  if (subView === "assign") return (
    <AssignStaffPanel entry={entry} onClose={() => setSubView(null)} onAssigned={() => { loadBatches(); onRefresh(); }} />
  );
  if (subView === "shortage") return (
    <ShortageResolverPanel dutyType={entry.type} dutyLabel={entry.labelHi || entry.label} isDefault={entry.isDefault}
      onBack={() => setSubView(null)} onResolved={() => { loadBatches(); onRefresh(); setSubView(null); }} />
  );
  if (viewBatch) return <BatchDetailView batch={viewBatch} dutyLabel={entry.labelHi || entry.label} color={color} onBack={() => setViewBatch(null)} onRefresh={() => { loadBatches(); onRefresh(); }} />;

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", background: C.bg }}>
      <div style={{ background: color, padding: "16px 20px", display: "flex", alignItems: "center", gap: 12, flexShrink: 0 }}>
        <button onClick={onBack} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><ArrowLeft size={18} color="white" /></button>
        <div style={{ flex: 1 }}>
          <div style={{ color: "white", fontWeight: 800, fontSize: 14, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{entry.labelHi || entry.label}</div>
          <div style={{ color: "rgba(255,255,255,.65)", fontSize: 11 }}>{batches.length} Batches • {totalAsgn} Assigned</div>
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          {batches.length > 0 && <button onClick={clearAll} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><Trash2 size={15} color="white" /></button>}
          <button onClick={() => setSubView("assign")} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 9, padding: "7px 14px", color: "white", fontWeight: 700, fontSize: 12, cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "inherit" }}>
            <Plus size={15} />Assign
          </button>
        </div>
      </div>
      <div style={{ background: `${color}08`, padding: "12px 18px", display: "flex", gap: 10, alignItems: "center", flexShrink: 0, borderBottom: `1px solid ${color}18` }}>
        <StatChip label="आवश्यक" value={sankhya} color={color} />
        <StatChip label="Assigned" value={totalAsgn} color={totalAsgn >= sankhya && sankhya > 0 ? C.success : C.assign} />
        <StatChip label="Batches" value={batches.length} color={C.orange} />
        <div style={{ flex: 1 }} />
        {sankhya > 0 && <span style={{ color: totalAsgn >= sankhya ? C.success : C.error, fontWeight: 800, fontSize: 12 }}>{totalAsgn >= sankhya ? "✓ पूर्ण" : `${sankhya - totalAsgn} बाकी`}</span>}
      </div>
      {rule && hasAny(rule) && <div style={{ background: `${color}05`, padding: "8px 18px", borderBottom: `1px solid ${C.border}22` }}><ChipRow rule={rule} color={color} /></div>}
      {entry.shortages?.length > 0 && (
        <button onClick={() => setSubView("shortage")} style={{ margin: "10px 14px 0", padding: "9px 14px", borderRadius: 9, border: `1px solid ${C.error}40`, background: `${C.error}08`, color: C.error, fontWeight: 700, fontSize: 12, cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "inherit" }}>
          <AlertTriangle size={13} />स्टाफ की कमी है — ठीक करें
        </button>
      )}
      <div style={{ flex: 1, overflowY: "auto", padding: "12px 14px" }}>
        {loading ? <div style={{ textAlign: "center", padding: 48 }}><Loader2 size={28} color={color} style={{ animation: "spin 1s linear infinite" }} /></div>
          : batches.length === 0 ? (
            <div style={{ textAlign: "center", padding: 48, color: C.subtle }}>
              <DutyIcon type={entry.type} size={48} color={`${C.subtle}44`} />
              <div style={{ marginTop: 12, fontSize: 13 }}>कोई staff assign नहीं है</div>
              <div style={{ marginTop: 4, fontSize: 11 }}>"Assign" बटन दबाएं</div>
            </div>
          ) : batches.map(batch => (
            <div key={batch.batchNo} style={{ marginBottom: 14 }}>
              <BatchCard batch={batch} color={color}
                onDelete={() => deleteBatch(batch.batchNo)}
                onView={() => setViewBatch(batch)} />
            </div>
          ))}
      </div>
    </div>
  );
};

// ── Batch Card ────────────────────────────────────────────────────────────────
const BatchCard = ({ batch, color, onDelete, onView }) => {
  const staffList = batch.staff || [];
  return (
    <div style={{ background: "white", borderRadius: 14, border: `1px solid ${color}30`, boxShadow: `0 2px 10px ${color}0e`, overflow: "hidden" }}>
      <div style={{ background: `${color}0e`, padding: "12px 14px", display: "flex", alignItems: "center", gap: 12 }}>
        <div style={{ width: 36, height: 36, background: color, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", color: "white", fontWeight: 900, fontSize: 15, flexShrink: 0 }}>{batch.batchNo}</div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ color, fontWeight: 800, fontSize: 13 }}>Batch {batch.batchNo}</div>
          <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
            <span style={{ color: C.subtle, fontSize: 11 }}>{batch.staffCount || staffList.length} staff</span>
            {batch.busNo && <span style={{ color: C.subtle, fontSize: 10, display: "flex", alignItems: "center", gap: 3 }}><Bus size={10} />{batch.busNo}</span>}
            {batch.note && <span style={{ color: C.subtle, fontSize: 10 }}>{batch.note}</span>}
          </div>
        </div>
        <button onClick={onView} style={{ background: color, border: "none", borderRadius: 8, padding: "6px 12px", color: "white", fontSize: 11, fontWeight: 700, cursor: "pointer", fontFamily: "inherit" }}>विवरण</button>
        <button onClick={onDelete} style={{ width: 32, height: 32, background: `${C.error}10`, border: `1px solid ${C.error}30`, borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><Trash2 size={14} color={C.error} /></button>
      </div>
      {staffList.length > 0 && (
        <div style={{ padding: "10px 12px", display: "flex", flexWrap: "wrap", gap: 6 }}>
          {staffList.slice(0, 6).map(s => {
            const rc = rankColor(s.rank || "");
            const initials = (s.name || "").split(" ").filter(Boolean).slice(0, 2).map(w => w[0]).join("").toUpperCase();
            return (
              <div key={s.assignmentId || s.id} style={{ display: "inline-flex", alignItems: "center", gap: 5, background: `${rc}10`, border: `1px solid ${rc}25`, borderRadius: 8, padding: "4px 8px" }}>
                <div style={{ width: 22, height: 22, background: `${rc}22`, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", color: rc, fontWeight: 900, fontSize: 10 }}>{initials}</div>
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
};

// ── Batch Detail View ─────────────────────────────────────────────────────────
const BatchDetailView = ({ batch, dutyLabel, color, onBack, onRefresh }) => {
  const [staff, setStaff] = useState((batch.staff || []).map(s => ({ ...s })));

  const removeStaff = async (s) => {
    if (!confirm(`${s.name} को हटाएं?`)) return;
    try {
      await api.delete(`/admin/district-duty/assignment/${s.assignmentId}`);
      setStaff(prev => prev.filter(x => x.assignmentId !== s.assignmentId));
      onRefresh(); toast.success(`${s.name} हटाया गया`);
    } catch (e) { toast.error("Error: " + e.message); }
  };

  const rankCounts = {};
  staff.forEach(s => { const r = s.rank || ""; if (r) rankCounts[r] = (rankCounts[r] || 0) + 1; });

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", background: C.bg }}>
      <div style={{ background: color, padding: "16px 20px", display: "flex", alignItems: "center", gap: 12, flexShrink: 0 }}>
        <button onClick={onBack} style={{ background: "rgba(255,255,255,.2)", border: "none", borderRadius: 8, width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><ArrowLeft size={18} color="white" /></button>
        <div style={{ flex: 1 }}>
          <div style={{ color: "white", fontWeight: 800, fontSize: 14 }}>{dutyLabel}</div>
          <div style={{ color: "rgba(255,255,255,.65)", fontSize: 11 }}>Batch {batch.batchNo} • {staff.length} Staff{batch.busNo ? ` • Bus: ${batch.busNo}` : ""}</div>
        </div>
        <div style={{ width: 38, height: 38, background: "rgba(255,255,255,.2)", borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <span style={{ color: "white", fontWeight: 900, fontSize: 16 }}>{batch.batchNo}</span>
        </div>
      </div>
      {staff.length > 0 && (
        <div style={{ background: `${C.surface}88`, padding: "7px 16px", display: "flex", gap: 8, overflowX: "auto", flexShrink: 0 }}>
          {Object.entries(rankCounts).map(([r, c]) => {
            const rc = rankColor(r);
            return <span key={r} style={{ background: `${rc}14`, border: `1px solid ${rc}30`, color: rc, borderRadius: 6, padding: "3px 8px", fontSize: 10, fontWeight: 700, whiteSpace: "nowrap" }}>{r}: {c}</span>;
          })}
        </div>
      )}
      <div style={{ flex: 1, overflowY: "auto", padding: "10px 14px" }}>
        {staff.length === 0 ? <div style={{ textAlign: "center", padding: 48, color: C.subtle, fontSize: 13 }}>कोई staff नहीं</div>
          : staff.map((s, i) => {
            const rc = rankColor(s.rank || "");
            const initials = (s.name || "").split(" ").filter(Boolean).slice(0, 2).map(w => w[0]).join("").toUpperCase();
            return (
              <div key={s.assignmentId || i} style={{ background: "white", borderRadius: 12, border: `1px solid ${rc}25`, padding: 14, marginBottom: 8, display: "flex", alignItems: "center", gap: 12 }}>
                <div style={{ width: 30, height: 30, background: `${color}14`, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", color, fontWeight: 900, fontSize: 12, flexShrink: 0 }}>{i + 1}</div>
                <div style={{ width: 40, height: 40, background: `${rc}18`, borderRadius: "50%", border: `1px solid ${rc}30`, display: "flex", alignItems: "center", justifyContent: "center", color: rc, fontWeight: 900, fontSize: 14, flexShrink: 0 }}>{initials}</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
                    <span style={{ color: C.dark, fontWeight: 700, fontSize: 13 }}>{s.name}</span>
                    {s.isArmed && <span style={{ background: "#6A1B9A18", color: "#6A1B9A", fontSize: 9, fontWeight: 700, borderRadius: 5, padding: "1px 6px" }}>⚔ Armed</span>}
                  </div>
                  <div style={{ display: "flex", gap: 8, marginTop: 4, flexWrap: "wrap", alignItems: "center" }}>
                    <span style={{ background: `${rc}14`, color: rc, fontSize: 9, fontWeight: 700, borderRadius: 5, padding: "2px 6px" }}>{s.rank}</span>
                    {s.pno && <span style={{ color: C.subtle, fontSize: 10 }}><Hash size={9} />{s.pno}</span>}
                    {s.thana && <span style={{ color: C.subtle, fontSize: 10 }}>{s.thana}</span>}
                    {s.mobile && <span style={{ color: C.subtle, fontSize: 10 }}><Phone size={9} />{s.mobile}</span>}
                  </div>
                </div>
                <button onClick={() => removeStaff(s)} style={{ width: 32, height: 32, background: `${C.error}10`, border: `1px solid ${C.error}25`, borderRadius: 8, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", flexShrink: 0 }}><UserMinus size={15} color={C.error} /></button>
              </div>
            );
          })}
      </div>
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════════
//  MANAK TAB
// ══════════════════════════════════════════════════════════════════════════════
const ManakTab = ({ duties, rules, onEdit, onEditLabel, onDelete }) => {
  const filledCount = duties.filter(d => hasAny(rules[d.type])).length;
  const totalAll = duties.filter(d => hasAny(rules[d.type])).reduce((s, d) => s + totalStaffRule(rules[d.type]), 0);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      <div style={{ background: C.surface, padding: "10px 20px", display: "flex", alignItems: "center", gap: 8, borderBottom: `1px solid ${C.border}33`, flexShrink: 0 }}>
        <Shield size={14} color={C.district} />
        <span style={{ color: C.dark, fontSize: 11.5, fontWeight: 600, flex: 1 }}>ड्यूटी प्रकार पर क्लिक करके पुलिस बल सेट करें</span>
        <span style={{ color: C.district, fontWeight: 800, fontSize: 12 }}>{totalAll}</span>
        <span style={{ color: C.subtle, fontSize: 11 }}>({filledCount}/{duties.length})</span>
      </div>
      <div style={{ flex: 1, overflowY: "auto", padding: "16px 20px" }}>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(340px,1fr))", gap: 12 }}>
          {duties.map((entry) => {
            const rule = rules[entry.type];
            const isSet = hasAny(rule);
            const color = entry.isDefault ? C.district : C.custom;
            return (
              <div key={entry.type} onClick={() => onEdit(entry)} style={{
                background: isSet ? `${color}08` : "white", border: `${isSet ? 1.5 : 1}px solid ${isSet ? color + "50" : C.border + "55"}`,
                borderRadius: 14, padding: "14px 16px", cursor: "pointer", transition: "all .18s",
                boxShadow: isSet ? `0 2px 14px ${color}16` : "0 1px 4px rgba(0,0,0,.04)"
              }}>
                <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
                  <div style={{ width: 46, height: 46, background: isSet ? color : `${C.subtle}20`, borderRadius: 12, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                    <DutyIcon type={entry.type} size={22} color={isSet ? "white" : C.subtle} />
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap" }}>
                      <span style={{ color: C.dark, fontWeight: 700, fontSize: 14 }}>{entry.labelHi || entry.label}</span>
                      {!entry.isDefault && <span style={{ background: `${C.custom}18`, color: C.custom, fontSize: 9, fontWeight: 800, borderRadius: 5, padding: "1px 6px" }}>कस्टम</span>}
                    </div>
                    {isSet ? (
                      <div style={{ display: "flex", gap: 10, marginTop: 3 }}>
                        <span style={{ color, fontSize: 11, fontWeight: 800 }}>संख्या: {rule.sankhya || 0}</span>
                        <span style={{ color: C.subtle, fontSize: 11 }}>• स्टाफ: {totalStaffRule(rule)}</span>
                      </div>
                    ) : <span style={{ color: C.subtle, fontSize: 11 }}>मानक सेट नहीं है</span>}
                  </div>
                  <div style={{ display: "flex", alignItems: "center", gap: 6, flexShrink: 0 }} onClick={e => e.stopPropagation()}>
                    {isSet ? <CheckCircle2 size={18} color={C.success} /> : <PlusCircle size={18} color={C.subtle} />}
                    {!entry.isDefault && (
                      <>
                        <button onClick={e => { e.stopPropagation(); onEditLabel(entry); }} style={{ width: 30, height: 30, background: `${C.custom}12`, border: `1px solid ${C.custom}30`, borderRadius: 7, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><Edit3 size={13} color={C.custom} /></button>
                        <button onClick={e => { e.stopPropagation(); onDelete(entry); }} style={{ width: 30, height: 30, background: `${C.error}10`, border: `1px solid ${C.error}30`, borderRadius: 7, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><Trash2 size={13} color={C.error} /></button>
                      </>
                    )}
                    {entry.isDefault && <ChevronRight size={18} color={C.subtle} />}
                  </div>
                </div>
                {isSet && rule && <ChipRow rule={rule} color={color} />}
              </div>
            );
          })}
        </div>
        <div style={{ height: 20 }} />
      </div>
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY TAB
// ══════════════════════════════════════════════════════════════════════════════
const DutyTab = ({ duties, summary, rules, shortageReport, isJobRunning, onOpenDetail, onSingleAuto, onShowAllShortages }) => {
  const assignedAll = duties.reduce((s, d) => s + (summary[d.type]?.totalAssigned || 0), 0);
  const shortageCount = Object.values(shortageReport || {}).filter(v => v?.shortages?.length > 0).length;

  const shortagesFor = (dt) => {
    const v = shortageReport?.[dt]; if (!v?.shortages?.length) return [];
    return v.shortages;
  };

  if (!duties.length) return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", color: C.subtle }}>
      <ClipboardList size={56} style={{ opacity: .3 }} />
      <div style={{ marginTop: 14, fontSize: 13 }}>पहले मानक टैब में ड्यूटी प्रकार सेट करें</div>
    </div>
  );

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      <div style={{ background: `${C.assign}08`, padding: "10px 20px", display: "flex", alignItems: "center", gap: 8, borderBottom: `1px solid ${C.assign}22`, flexShrink: 0 }}>
        <Users size={14} color={C.assign} />
        <span style={{ color: C.dark, fontSize: 11.5, fontWeight: 600, flex: 1 }}>ड्यूटी पर क्लिक करके assign/view करें</span>
        <span style={{ background: `${C.assign}14`, color: C.assign, fontSize: 11, fontWeight: 800, borderRadius: 8, padding: "3px 10px" }}>{assignedAll} Assigned</span>
      </div>
      {shortageCount > 0 && (
        <button onClick={onShowAllShortages} style={{ background: `${C.error}08`, borderBottom: `1px solid ${C.error}25`, border: "none", padding: "9px 20px", display: "flex", alignItems: "center", gap: 8, cursor: "pointer", width: "100%", fontFamily: "inherit" }}>
          <AlertTriangle size={15} color={C.error} />
          <span style={{ flex: 1, color: C.error, fontSize: 12, fontWeight: 700, textAlign: "left" }}>{shortageCount} ड्यूटी में स्टाफ की कमी है — विवरण देखें</span>
          <ChevronRight size={15} color={C.error} />
        </button>
      )}
      <div style={{ flex: 1, overflowY: "auto", padding: "16px 20px" }}>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(320px,1fr))", gap: 12 }}>
          {duties.map(entry => {
            const s = summary[entry.type] || {};
            const assigned = s.totalAssigned || 0;
            const batches = s.batchCount || 0;
            const san = entry.sankhya || 0;
            const pct = san > 0 ? assigned / san : 0;
            const isOver = assigned > san && san > 0;
            const isFull = san > 0 && assigned >= san;
            const barColor = isOver ? C.error : isFull ? C.success : pct > .5 ? C.orange : C.assign;
            const color = entry.isDefault ? C.district : C.custom;
            const shortages = shortagesFor(entry.type);
            const hasShortage = shortages.length > 0;

            return (
              <div key={entry.type} onClick={() => onOpenDetail({ ...entry, shortages })} style={{
                background: hasShortage ? `${C.error}05` : assigned > 0 ? `${color}05` : "white",
                border: `${(hasShortage || assigned > 0) ? 1.5 : 1}px solid ${hasShortage ? C.error + "44" : assigned > 0 ? color + "40" : C.border + "44"}`,
                borderRadius: 14, padding: "14px 16px", cursor: "pointer", transition: "all .2s"
              }}>
                <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
                  <div style={{ width: 44, height: 44, background: assigned > 0 ? color : `${C.subtle}18`, borderRadius: 11, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
                    <DutyIcon type={entry.type} size={21} color={assigned > 0 ? "white" : C.subtle} />
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ color: C.dark, fontWeight: 700, fontSize: 13.5, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{entry.labelHi || entry.label}</div>
                    <div style={{ display: "flex", gap: 8, marginTop: 3, flexWrap: "wrap", alignItems: "center" }}>
                      {san > 0 ? <span style={{ color: barColor, fontWeight: 800, fontSize: 11 }}>{assigned}/{san}</span> : <span style={{ color, fontSize: 11, fontWeight: 700 }}>{assigned} assigned</span>}
                      {batches > 0 && <span style={{ background: `${C.assign}14`, color: C.assign, fontSize: 9, fontWeight: 700, borderRadius: 5, padding: "1px 6px" }}>{batches} batch{batches > 1 ? "es" : ""}</span>}
                    </div>
                  </div>
                  <div style={{ display: "flex", alignItems: "center", gap: 6, flexShrink: 0 }}>
                    {isFull && !hasShortage && <span style={{ background: `${C.success}12`, color: C.success, fontSize: 10, fontWeight: 700, borderRadius: 8, padding: "3px 8px" }}>✓ Full</span>}
                    {isOver && <span style={{ background: `${C.error}12`, color: C.error, fontSize: 10, fontWeight: 700, borderRadius: 8, padding: "3px 8px" }}>Over</span>}
                    <div style={{ background: C.assign, borderRadius: 9, padding: "6px 10px", display: "flex", alignItems: "center", gap: 4 }}>
                      <Users size={13} color="white" />
                      <span style={{ color: "white", fontSize: 11, fontWeight: 700 }}>देखें</span>
                    </div>
                  </div>
                </div>
                {san > 0 && <div style={{ marginTop: 10 }}><ProgressBar value={pct} color={barColor} /></div>}
                {hasShortage && (
                  <div style={{ background: `${C.error}08`, border: `1px solid ${C.error}28`, borderRadius: 8, padding: 9, marginTop: 10 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 5, marginBottom: 6 }}>
                      <AlertTriangle size={12} color={C.error} />
                      <span style={{ color: C.error, fontSize: 10.5, fontWeight: 800 }}>स्टाफ की कमी</span>
                    </div>
                    <div style={{ display: "flex", flexWrap: "wrap", gap: 5 }}>
                      {shortages.map((s, i) => (
                        <span key={i} style={{ background: `${C.error}14`, border: `1px solid ${C.error}28`, borderRadius: 5, padding: "2px 7px", color: C.error, fontSize: 10, fontWeight: 700 }}>{shortageLabel(s)}</span>
                      ))}
                    </div>
                  </div>
                )}
                {san > 0 && (
                  <div style={{ display: "flex", gap: 8, marginTop: 10 }} onClick={e => e.stopPropagation()}>
                    {hasShortage ? (
                      <>
                        <button onClick={() => onOpenDetail({ ...entry, shortages, openShortage: true })} disabled={isJobRunning} style={{ flex: 1, padding: "8px", borderRadius: 8, border: "none", background: isJobRunning ? `${C.subtle}22` : C.error, color: isJobRunning ? C.subtle : "white", fontWeight: 800, fontSize: 12, cursor: isJobRunning ? "not-allowed" : "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: 5, fontFamily: "inherit" }}>
                          <Wrench size={13} />कमी ठीक करें
                        </button>
                        <button onClick={() => onSingleAuto(entry)} disabled={isJobRunning} style={{ padding: "8px 12px", borderRadius: 8, border: `1px solid ${C.orange}40`, background: `${C.orange}10`, color: isJobRunning ? C.subtle : C.orange, fontWeight: 700, fontSize: 12, cursor: isJobRunning ? "not-allowed" : "pointer", display: "flex", alignItems: "center", gap: 4, fontFamily: "inherit" }}>
                          <RefreshCw size={12} />फिर से
                        </button>
                      </>
                    ) : (
                      <button onClick={() => !isJobRunning && !isFull && onSingleAuto(entry)} disabled={isJobRunning || isFull} style={{
                        flex: 1, padding: "8px", borderRadius: 8, border: `1px solid ${isJobRunning || isFull ? C.subtle + "30" : C.orange + "40"}`,
                        background: isJobRunning || isFull ? `${C.subtle}10` : `${C.orange}10`,
                        color: isJobRunning || isFull ? C.subtle : C.orange, fontWeight: 800, fontSize: 12, cursor: isJobRunning || isFull ? "not-allowed" : "pointer",
                        display: "flex", alignItems: "center", justifyContent: "center", gap: 5, fontFamily: "inherit"
                      }}>
                        {isFull ? <CheckCircle2 size={13} /> : <Wand2 size={13} />}
                        {isFull ? "पूर्ण" : "इस duty को auto-assign करें"}
                      </button>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
        <div style={{ height: 20 }} />
      </div>
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN PAGE
// ══════════════════════════════════════════════════════════════════════════════
export default function ManakDistrictPage({ onBack }) {
  const [tab, setTab] = useState("manak");
  const [duties, setDuties] = useState([]);
  const [rules, setRules] = useState({});
  const [summary, setSummary] = useState({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [changed, setChanged] = useState(false);

  // ── Rank Editor: uses imported ManakRankEditorPage ────────────────────────
  const [editorEntry, setEditorEntry] = useState(null);

  const [addOpen, setAddOpen] = useState(false);
  const [addLabel, setAddLabel] = useState("");
  const [addSaving, setAddSaving] = useState(false);
  const [editingCustom, setEditingCustom] = useState(null);
  const [detailEntry, setDetailEntry] = useState(null);
  const [confirmState, setConfirmState] = useState(null);

  // Print page
  const [printOpen, setPrintOpen] = useState(false);
  const [printLoading, setPrintLoading] = useState(false);
  const [allBatches, setAllBatches] = useState({});

  // Auto assign
  const [jobId, setJobId] = useState(null);
  const [jobStatus, setJobStatus] = useState("");
  const [jobPct, setJobPct] = useState(0);
  const [jobAssigned, setJobAssigned] = useState(0);
  const [jobSkipped, setJobSkipped] = useState(0);
  const [shortageReport, setShortageReport] = useState({});
  const [shortageModalOpen, setShortageModalOpen] = useState(false);
  const pollRef = useRef(null);

  const nav = useNavigate()

  useEffect(() => { loadAll(); return () => clearInterval(pollRef.current); }, []);

  const loadAll = async () => {
    setLoading(true);
    try {
      const [rulesRes, summaryRes, latestRes] = await Promise.all([
        api.get("/admin/district-rules"),
        api.get("/admin/district-duty/summary"),
        api.get("/admin/district-duty/auto-assign/latest"),
      ]);

      const list = rulesRes.data?.data || rulesRes.data || [];
      const summaryData = summaryRes.data?.data || summaryRes.data || {};
      const latestJob = latestRes.data?.data || latestRes.data || {};

      const newDuties = [], newRules = {};
      list.forEach(r => {
        newDuties.push({
          type: r.dutyType,
          labelHi: r.dutyLabelHi,
          label: r.dutyLabelHi,
          isDefault: r.isDefault || false,
          sankhya: r.sankhya || 0,
        });
        newRules[r.dutyType] = r;
      });
      setDuties(newDuties);
      setRules(newRules);
      setSummary(summaryData);

      const status = latestJob.status || "";
      if (status === "running" || status === "pending") {
        setJobId(latestJob.jobId);
        setJobStatus(status);
        setJobPct(latestJob.pct || 0);
        startPolling(latestJob.jobId);
      } else if (status === "done") {
        if (latestJob.shortageReport) setShortageReport(latestJob.shortageReport);
      }
    } catch (e) { toast.error("लोड विफल: " + e.message); }
    finally { setLoading(false); }
  };

  const startPolling = (jid) => {
    clearInterval(pollRef.current);
    pollRef.current = setInterval(async () => {
      try {
        const res = await api.get(`/admin/district-duty/auto-assign/status/${jid}`);
        const d = res.data?.data || res.data || {};
        setJobStatus(d.status || "");
        setJobPct(d.pct || 0);
        setJobAssigned(d.assigned || 0);
        setJobSkipped(d.skipped || 0);
        if (d.status === "done" || d.status === "error") {
          clearInterval(pollRef.current);
          if (d.status === "done") {
            if (d.shortageReport) setShortageReport(d.shortageReport);
            await loadAll();
            const hasShortages = Object.values(d.shortageReport || {}).some(v => v?.shortages?.length > 0);
            if (hasShortages) { toast.error(`${d.assigned} staff assign • कुछ ड्यूटी में कमी है`); setShortageModalOpen(true); }
            else toast.success(`${d.assigned} staff assign हुए ✓`);
          } else { toast.error("Error: " + (d.errorMsg || "Unknown error")); }
        }
      } catch { }
    }, 2000);
  };

  const isJobRunning = jobStatus === "running" || jobStatus === "pending";

  const startAutoAssign = async () => {
    try {
      const res = await api.post("/admin/district-duty/auto-assign/start", {});
      const jid = (res.data?.data || res.data)?.jobId;
      if (!jid) { toast.error("Job शुरू नहीं हुआ"); return; }
      setJobId(jid); setJobStatus("running"); setJobPct(0); setJobAssigned(0); setJobSkipped(0);
      startPolling(jid);
      toast.success("Auto-assign शुरू हो गई!");
    } catch (e) { toast.error("Error: " + e.message); }
  };

  const confirmAutoAssign = () => {
    setConfirmState({
      title: "Auto Assign District Duty",
      message: "मानक के अनुसार सभी ड्यूटी पर staff auto-assign होगा। पहले के assignments हट जाएंगे।",
      confirmText: "Start करें", confirmColor: C.district, icon: Wand2,
      onConfirm: () => { setConfirmState(null); startAutoAssign(); }
    });
  };

  const runSingleDutyAutoAssign = async (entry) => {
    if ((entry.sankhya || 0) <= 0) { toast.error("पहले मानक में संख्या सेट करें"); return; }
    try {
      const res = await api.post(`/admin/district-duty/${entry.type}/auto-assign`, {});
      const jid = (res.data?.data || res.data)?.jobId;
      if (!jid) { toast.error("Job शुरू नहीं हुआ"); return; }
      setJobId(jid); setJobStatus("running"); setJobPct(0); setJobAssigned(0); setJobSkipped(0);
      startPolling(jid);
      toast.success(`${entry.labelHi || entry.label}: auto-assign शुरू!`);
    } catch (e) { toast.error("Error: " + e.message); }
  };

  const clearAllAssignments = () => {
    setConfirmState({
      title: "ड्यूटी रीफ्रेश करें?",
      message: "सभी ड्यूटी assignments हट जाएंगे। आप दोबारा Auto Assign कर सकते हैं।",
      confirmText: "रीफ्रेश करें", confirmColor: C.error, icon: RotateCcw,
      onConfirm: async () => {
        setConfirmState(null);
        try {
          await api.delete("/admin/district-duty/auto-assign/clear-all");
          toast.success("ड्यूटी रीफ्रेश हो गई ✓");
          loadAll();
        } catch (e) { toast.error("Error: " + e.message); }
      }
    });
  };

  // ── Open print report ─────────────────────────────────────────────────────
  const openPrintReport = async () => {
    setPrintLoading(true);
    try {
      const batchesMap = {};
      await Promise.all(duties.map(async (duty) => {
        try {
          const res = await api.get(`/admin/district-duty/${duty.type}/batches`);
          batchesMap[duty.type] = res.data?.data || res.data || [];
        } catch {
          batchesMap[duty.type] = [];
        }
      }));
      setAllBatches(batchesMap);
      setPrintOpen(true);
    } catch (e) {
      toast.error("रिपोर्ट लोड विफल: " + e.message);
    } finally {
      setPrintLoading(false);
    }
  };

  // ── Rank Editor ───────────────────────────────────────────────────────────
  const openRankEditor = (entry) => {
    setEditorEntry(entry);
  };

  const saveRule = async (form) => {
    const entry = editorEntry;
    const updated = { ...rules[entry.type], ...form, dutyType: entry.type, dutyLabelHi: entry.labelHi || entry.label };
    setRules(r => ({ ...r, [entry.type]: updated }));
    setDuties(d => d.map(x => x.type === entry.type ? { ...x, sankhya: form.sankhya ?? x.sankhya } : x));
    setChanged(true);
    setEditorEntry(null);
    toast.success("मानक अपडेट हो गया ✓");
  };

  const saveAll = async () => {
    setSaving(true);
    try {
      const rulesList = duties.map((d, i) => ({
        ...rules[d.type] || { dutyType: d.type, dutyLabelHi: d.labelHi || d.label, sankhya: 0 },
        dutyType: d.type, dutyLabelHi: d.labelHi || d.label, sortOrder: (i + 1) * 10,
      }));
      await api.post("/admin/district-rules", { rules: rulesList });
      setChanged(false); toast.success("जनपदीय मानक सेव हो गया ✓");
    } catch (e) { toast.error("सेव विफल: " + e.message); }
    finally { setSaving(false); }
  };

  const addOrEditCustom = async () => {
    if (!addLabel.trim()) return;
    setAddSaving(true);
    try {
      if (editingCustom) {
        await api.put(`/admin/district-rules/custom/${editingCustom.type}`, { labelHi: addLabel });
        setDuties(d => d.map(x => x.type === editingCustom.type ? { ...x, labelHi: addLabel, label: addLabel } : x));
        toast.success("नाम अपडेट हो गया ✓");
      } else {
        const res = await api.post("/admin/district-rules/custom", { labelHi: addLabel });
        const data = res.data?.data || res.data || {};
        setDuties(d => [...d, { type: data.dutyType, labelHi: data.dutyLabelHi, label: data.dutyLabelHi, isDefault: false, sankhya: 0 }]);
        toast.success("नया ड्यूटी प्रकार जोड़ा गया ✓");
      }
    } catch (e) { toast.error("विफल: " + e.message); }
    finally { setAddSaving(false); setAddOpen(false); setEditingCustom(null); setAddLabel(""); }
  };

  const deleteCustomDuty = (entry) => {
    setConfirmState({
      title: "ड्यूटी प्रकार हटाएं?",
      message: `"${entry.labelHi || entry.label}" और इसका मानक हटा दिया जाएगा।`,
      confirmText: "हटाएं", confirmColor: C.error, icon: Trash2,
      onConfirm: async () => {
        setConfirmState(null);
        try {
          await api.delete(`/admin/district-rules/custom/${entry.type}`);
          setDuties(d => d.filter(x => x.type !== entry.type));
          setRules(r => { const n = { ...r }; delete n[entry.type]; return n; });
          toast.success("हटाया गया ✓");
        } catch (e) { toast.error("विफल: " + e.message); }
      }
    });
  };

  const handleOpenDetail = (entry) => {
    if (entry.openShortage) { setDetailEntry({ ...entry, _subView: "shortage" }); }
    else setDetailEntry(entry);
  };

  const handleFixShortage = (dutyType, label) => {
    const entry = duties.find(d => d.type === dutyType) || { type: dutyType, label, labelHi: label, isDefault: ICON_MAP.hasOwnProperty(dutyType) };
    setDetailEntry({ ...entry, _subView: "shortage" });
    setTab("duty");
  };

  const editorColor = editorEntry ? (editorEntry.isDefault ? C.district : C.custom) : C.district;

  // Show print page
  if (printOpen) {
    return (
      <DistrictDutyPrintPage
        duties={duties}
        byDuty={rules}
        summary={summary}
        allBatches={allBatches}
        onBack={() => setPrintOpen(false)}
      />
    );
  }

  return (
    <div style={{ height: "100vh", display: "flex", flexDirection: "column", background: C.bg, fontFamily: "'Noto Sans Devanagari',Georgia,serif", position: "relative" }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;600;700;800;900&family=Playfair+Display:wght@700;800;900&display=swap');
        @keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
        @keyframes fadeIn{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:translateY(0)}}
        *{box-sizing:border-box}
        button,input,select{font-family:inherit}
        ::-webkit-scrollbar{width:5px;height:5px}
        ::-webkit-scrollbar-track{background:${C.surface}}
        ::-webkit-scrollbar-thumb{background:${C.border};border-radius:3px}
      `}</style>

      <Toaster position="top-right" toastOptions={{
        style: { background: C.bg, color: C.dark, border: `1px solid ${C.border}`, fontFamily: "inherit", fontSize: 13 },
        success: { iconTheme: { primary: C.success, secondary: "white" } },
        error: { iconTheme: { primary: C.error, secondary: "white" } }
      }} />

      {/* AppBar */}
      <div style={{ background: C.district, flexShrink: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 14, padding: "14px 24px 0" }}>
          {onBack && (
            <button onClick={onBack} style={{ background: "rgba(255,255,255,.15)", border: "none", borderRadius: 10, width: 36, height: 36, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", flexShrink: 0 }}>
              <ChevronLeft size={20} color="white" />
            </button>
          )}
          <button onClick={() => nav("/")} className="p-1.5 rounded-lg hover:bg-white/10">
            <ArrowLeft size={18} className="text-white" />
          </button>
          <div style={{ flex: 1 }}>
            <div style={{ color: "white", fontWeight: 800, fontSize: 17 }}>जनपदीय कानून व्यवस्था</div>
            <div style={{ color: "rgba(255,255,255,.6)", fontSize: 11 }}>मानक + ड्यूटी असाइनमेंट</div>
          </div>
          <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
            <button onClick={printLoading ? null : openPrintReport} disabled={printLoading} title="रिपोर्ट प्रिंट करें" style={{ background: "rgba(255,255,255,.15)", border: "none", borderRadius: 9, width: 36, height: 36, display: "flex", alignItems: "center", justifyContent: "center", cursor: printLoading ? "not-allowed" : "pointer" }}>
              {printLoading ? <Loader2 size={16} color="white" style={{ animation: "spin 1s linear infinite" }} /> : <Printer size={16} color="white" />}
            </button>
            <button onClick={loadAll} title="पुनः लोड" style={{ background: "rgba(255,255,255,.15)", border: "none", borderRadius: 9, width: 36, height: 36, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}><RefreshCw size={16} color="white" /></button>
            <button onClick={clearAllAssignments} disabled={isJobRunning} title="सभी assignments हटाएं" style={{ background: "rgba(255,255,255,.15)", border: "none", borderRadius: 9, width: 36, height: 36, display: "flex", alignItems: "center", justifyContent: "center", cursor: isJobRunning ? "not-allowed" : "pointer", opacity: isJobRunning ? .6 : 1 }}><Trash2 size={16} color="white" /></button>
            {changed && <span style={{ background: "rgba(255,255,255,.18)", color: "white", fontSize: 10, fontWeight: 800, borderRadius: 20, padding: "3px 10px" }}>अनसेव्ड</span>}
          </div>
        </div>
        {/* Tabs */}
        <div style={{ display: "flex", padding: "0 24px", marginTop: 8, gap: 2 }}>
          {[["manak", "मानक"], ["duty", "ड्यूटी"]].map(([v, l]) => (
            <button key={v} onClick={() => { setTab(v); if (v === "manak") { setDetailEntry(null); setEditorEntry(null); } }} style={{
              padding: "10px 26px", border: "none", background: "transparent",
              color: tab === v ? "white" : "rgba(255,255,255,.55)", fontWeight: tab === v ? 800 : 500, fontSize: 13,
              cursor: "pointer", borderBottom: tab === v ? "3px solid white" : "3px solid transparent",
              transition: "all .18s", fontFamily: "inherit"
            }}>{l}</button>
          ))}
        </div>
      </div>

      {/* Auto assign banner */}
      {(isJobRunning || jobStatus === "done") && (
        <AutoAssignBanner status={jobStatus} pct={jobPct} assigned={jobAssigned} skipped={jobSkipped} onDismiss={() => setJobStatus("")} />
      )}

      {/* Body */}
      <div style={{ flex: 1, overflow: "hidden", display: "flex", position: "relative" }}>
        {loading ? (
          <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center" }}>
            <Loader2 size={36} color={C.district} style={{ animation: "spin 1s linear infinite" }} />
          </div>
        ) : (
          <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden", minWidth: 0, position: "relative" }}>
            {tab === "manak" && (
              <ManakTab duties={duties} rules={rules}
                onEdit={openRankEditor}
                onEditLabel={(entry) => { setEditingCustom(entry); setAddLabel(entry.labelHi || entry.label); setAddOpen(true); }}
                onDelete={deleteCustomDuty} />
            )}
            {tab === "duty" && (
              detailEntry ? (
                <div style={{ flex: 1, overflow: "hidden", animation: "fadeIn .25s ease" }}>
                  {detailEntry._subView === "shortage" ? (
                    <ShortageResolverPanel
                      dutyType={detailEntry.type}
                      dutyLabel={detailEntry.labelHi || detailEntry.label}
                      isDefault={detailEntry.isDefault}
                      onBack={() => setDetailEntry(null)}
                      onResolved={() => { loadAll(); setDetailEntry(null); }} />
                  ) : (
                    <DutyDetailPanel
                      entry={detailEntry}
                      rule={rules[detailEntry.type]}
                      onBack={() => setDetailEntry(null)}
                      onRefresh={loadAll} />
                  )}
                </div>
              ) : (
                <DutyTab
                  duties={duties} summary={summary} rules={rules}
                  shortageReport={shortageReport}
                  isJobRunning={isJobRunning}
                  onOpenDetail={handleOpenDetail}
                  onSingleAuto={runSingleDutyAutoAssign}
                  onShowAllShortages={() => setShortageModalOpen(true)} />
              )
            )}

            {/* ── Inline Rank Editor Page (uses imported ManakRankEditorPage) ── */}
            {editorEntry && (
              <div style={{ position: "absolute", inset: 0, zIndex: 500, animation: "fadeIn .2s ease" }}>
                <ManakRankEditorPage
                  title={editorEntry.labelHi || editorEntry.label}
                  subtitle="जनपदीय कानून व्यवस्था — मानक सेट करें"
                  color={editorColor}
                  initial={rules[editorEntry.type] || {}}
                  showSankhya={true}
                  onSave={saveRule}
                  onBack={() => setEditorEntry(null)}
                />
              </div>
            )}
          </div>
        )}
      </div>

      {/* Bottom Action Bar */}
      {!loading && !detailEntry && !editorEntry && (
        <div style={{ background: C.bg, borderTop: `1px solid ${C.border}44`, padding: "12px 24px 16px", flexShrink: 0, display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
          <button onClick={isJobRunning ? null : confirmAutoAssign} disabled={isJobRunning}
            style={{
              height: 48, padding: "0 24px", borderRadius: 12, border: "none",
              background: isJobRunning ? C.subtle : C.orange, color: "white", fontWeight: 800, fontSize: 13,
              cursor: isJobRunning ? "not-allowed" : "pointer", display: "flex", alignItems: "center", gap: 8,
              opacity: isJobRunning ? .7 : 1, transition: "all .2s", fontFamily: "inherit"
            }}>
            {isJobRunning ? <Loader2 size={17} style={{ animation: "spin 1s linear infinite" }} /> : <Wand2 size={17} />}
            {isJobRunning ? `Running... ${jobPct}%` : "Auto Assign"}
          </button>
          <button onClick={() => { setEditingCustom(null); setAddLabel(""); setAddOpen(true); }}
            style={{ height: 48, padding: "0 20px", borderRadius: 12, border: `1px solid ${C.custom}50`, background: `${C.custom}0e`, color: C.custom, fontWeight: 700, fontSize: 13, cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "inherit" }}>
            <Plus size={18} />नया जोड़ें
          </button>
          <div style={{ flex: 1 }} />
          <button onClick={saving ? null : saveAll} disabled={saving}
            style={{ height: 48, padding: "0 28px", borderRadius: 12, border: "none", background: saving ? C.subtle : C.district, color: "white", fontWeight: 800, fontSize: 13, cursor: saving ? "not-allowed" : "pointer", display: "flex", alignItems: "center", gap: 8, fontFamily: "inherit" }}>
            {saving ? <Loader2 size={17} style={{ animation: "spin 1s linear infinite" }} /> : <Save size={17} />}
            {saving ? "सेव हो रहा है..." : "मानक सेव करें"}
          </button>
        </div>
      )}

      {/* Add/Edit Custom Duty Modal */}
      {addOpen && (
        <div style={{ position: "fixed", inset: 0, zIndex: 1000, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.5)", backdropFilter: "blur(4px)" }}
          onClick={e => { if (e.target === e.currentTarget) { setAddOpen(false); setEditingCustom(null); } }}>
          <div style={{ background: C.bg, borderRadius: 18, padding: 28, width: "100%", maxWidth: 440, boxShadow: "0 24px 80px rgba(0,0,0,.3)", border: `1.5px solid ${C.custom}44` }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
              <div style={{ width: 38, height: 38, background: `${C.custom}18`, borderRadius: 10, display: "flex", alignItems: "center", justifyContent: "center" }}>
                {editingCustom ? <Edit3 size={18} color={C.custom} /> : <Plus size={18} color={C.custom} />}
              </div>
              <span style={{ color: C.dark, fontWeight: 800, fontSize: 15 }}>{editingCustom ? "ड्यूटी प्रकार संपादित करें" : "नया ड्यूटी प्रकार जोड़ें"}</span>
            </div>
            <div style={{ color: C.subtle, fontSize: 12, fontWeight: 600, marginBottom: 6 }}>ड्यूटी का नाम (हिंदी में)</div>
            <input value={addLabel} onChange={e => setAddLabel(e.target.value)}
              onKeyDown={e => e.key === "Enter" && addLabel.trim() && addOrEditCustom()}
              placeholder="जैसे: विशेष मोबाईल ड्यूटी" autoFocus
              style={{ width: "100%", border: `1.5px solid ${C.border}`, borderRadius: 10, padding: "11px 14px", background: "white", color: C.dark, fontSize: 15, fontWeight: 700, outline: "none", boxSizing: "border-box", marginBottom: 22 }} />
            <div style={{ display: "flex", justifyContent: "flex-end", gap: 10 }}>
              <button onClick={() => { setAddOpen(false); setEditingCustom(null); }} style={{ padding: "9px 18px", borderRadius: 9, border: `1px solid ${C.border}`, background: "transparent", color: C.subtle, fontWeight: 600, fontSize: 13, cursor: "pointer", fontFamily: "inherit" }}>रद्द करें</button>
              <button onClick={addLabel.trim() && !addSaving ? addOrEditCustom : undefined} disabled={!addLabel.trim() || addSaving}
                style={{ padding: "9px 18px", borderRadius: 9, border: "none", background: C.custom, color: "white", fontWeight: 700, fontSize: 13, cursor: "pointer", display: "flex", alignItems: "center", gap: 6, fontFamily: "inherit" }}>
                {addSaving ? <Loader2 size={14} style={{ animation: "spin 1s linear infinite" }} /> : editingCustom ? <Check size={14} /> : <Plus size={14} />}
                {editingCustom ? "अपडेट करें" : "जोड़ें"}
              </button>
            </div>
          </div>
        </div>
      )}

      <ConfirmDialog open={!!confirmState}
        title={confirmState?.title} message={confirmState?.message}
        confirmText={confirmState?.confirmText} confirmColor={confirmState?.confirmColor}
        icon={confirmState?.icon}
        onConfirm={confirmState?.onConfirm}
        onCancel={() => setConfirmState(null)} />

      <ShortageReportModal open={shortageModalOpen} report={shortageReport}
        duties={duties} onClose={() => setShortageModalOpen(false)}
        onFix={handleFixShortage} />
    </div>
  );
}