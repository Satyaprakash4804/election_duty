import { useState, useEffect, useRef, useCallback } from "react";
import {
  Layers, Map, Vote, ArrowLeft, Printer, PlusCircle, RefreshCw,
  Edit2, Trash2, UserPlus, Plus, X, ChevronDown, Users,
  Inbox, AlertCircle, CheckCircle, Bus, BadgeCheck, Phone,
  PlusSquare, MinusCircle, Search, Loader2
} from "lucide-react";
import apiClient from "../api/client";
import { useNavigate } from "react-router-dom";
import { printHierarchy } from "../components/HeirarchyPrint";

// ── Palette constants (mirrors Flutter) ──────────────────────────────────────
const COLORS = {
  primary: "#0F2B5B",
  green: "#186A3B",
  purple: "#6C3483",
  red: "#C0392B",
  dark: "#1A2332",
  subtle: "#6B7C93",
  border: "#DDE3EE",
  accent: "#FBBF24",
  gold: "#FFF8E7",
  orange: "#E67E22",
};

const SENSITIVITY_COLOR = {
  "A++": "#6C3483",
  "A": "#C0392B",
  "B": "#E67E22",
  "C": "#1A5276",
};

const CENTER_TYPES = ["A++", "A", "B", "C"];

const RANKS = [
  { en: "SP", hi: "पुलिस अधीक्षक" },
  { en: "ASP", hi: "सह0 पुलिस अधीक्षक" },
  { en: "DSP", hi: "पुलिस उपाधीक्षक" },
  { en: "Inspector", hi: "निरीक्षक" },
  { en: "SI", hi: "उप निरीक्षक" },
  { en: "ASI", hi: "सह0 उप निरीक्षक" },
  { en: "Head Constable", hi: "मुख्य आरक्षी" },
  { en: "Constable", hi: "आरक्षी" },
];

// ── Tiny helpers ──────────────────────────────────────────────────────────────
function sColor(type) {
  return SENSITIVITY_COLOR[type] || "#1A5276";
}

function Toast({ toasts, onRemove }) {
  return (
    <div className="fixed top-4 right-4 z-[9999] flex flex-col gap-2 pointer-events-none">
      {toasts.map(t => (
        <div
          key={t.id}
          className="pointer-events-auto flex items-center gap-2 px-4 py-2.5 rounded-xl shadow-lg text-white text-sm font-semibold animate-fade-in"
          style={{ background: t.type === "success" ? COLORS.green : COLORS.red }}
        >
          {t.type === "success"
            ? <CheckCircle size={15} />
            : <AlertCircle size={15} />}
          {t.msg}
        </div>
      ))}
    </div>
  );
}

function useToast() {
  const [toasts, setToasts] = useState([]);
  const show = useCallback((msg, type = "success") => {
    const id = Date.now();
    setToasts(p => [...p, { id, msg, type }]);
    setTimeout(() => setToasts(p => p.filter(t => t.id !== id)), 3000);
  }, []);
  return { toasts, show };
}

// ── Confirm Dialog ────────────────────────────────────────────────────────────
function ConfirmDialog({ message, onConfirm, onCancel }) {
  return (
    <div className="fixed inset-0 bg-black/40 z-[900] flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-2xl p-6 w-full max-w-sm">
        <h3 className="font-bold text-base text-gray-800 mb-2">पुष्टि करें</h3>
        <p className="text-sm text-gray-600 mb-5">{message}</p>
        <div className="flex gap-3">
          <button onClick={onCancel} className="flex-1 py-2 rounded-lg border border-gray-200 text-gray-600 text-sm font-medium hover:bg-gray-50">रद्द</button>
          <button onClick={onConfirm} className="flex-1 py-2 rounded-lg text-white text-sm font-bold" style={{ background: COLORS.red }}>हटाएं</button>
        </div>
      </div>
    </div>
  );
}

function useConfirm() {
  const [state, setState] = useState(null);
  const confirm = (message) => new Promise(resolve => {
    setState({ message, resolve });
  });
  const dialog = state ? (
    <ConfirmDialog
      message={state.message}
      onConfirm={() => { state.resolve(true); setState(null); }}
      onCancel={() => { state.resolve(false); setState(null); }}
    />
  ) : null;
  return { confirm, dialog };
}

// ── Filter Dropdown ───────────────────────────────────────────────────────────
function FDrop({ label, value, placeholder, items, onChange }) {
  return (
    <div className="flex flex-col">
      <span className="text-[9px] font-bold uppercase tracking-wide mb-1" style={{ color: COLORS.subtle }}>{label}</span>
      <div className="relative">
        <select
          value={value || ""}
          onChange={e => onChange(e.target.value || null)}
          className="appearance-none pl-3 pr-7 py-2 rounded-lg border text-xs font-medium bg-white min-w-[120px] max-w-[165px] cursor-pointer outline-none focus:ring-2"
          style={{
            borderColor: value ? COLORS.primary : COLORS.border,
            borderWidth: "1.5px",
            color: value ? COLORS.dark : COLORS.subtle,
            ringColor: COLORS.primary,
          }}
        >
          <option value="">{placeholder}</option>
          {items.map(i => (
            <option key={i.value} value={i.value}>{i.label}</option>
          ))}
        </select>
        <ChevronDown size={12} className="absolute right-2 top-1/2 -translate-y-1/2 pointer-events-none" style={{ color: COLORS.subtle }} />
      </div>
    </div>
  );
}

// ── Icon Action Button ────────────────────────────────────────────────────────
function IAB({ icon: Icon, color, onClick, title = "" }) {
  return (
    <button
      title={title}
      onClick={onClick}
      className="p-1 rounded-md hover:opacity-70 transition-opacity"
    >
      <Icon size={17} style={{ color }} />
    </button>
  );
}

// ── Sensitivity Badge ─────────────────────────────────────────────────────────
function SBadge({ type }) {
  const c = sColor(type);
  return (
    <span
      className="inline-block px-1.5 py-0.5 rounded text-[10px] font-extrabold border"
      style={{ color: c, borderColor: `${c}66`, background: `${c}18` }}
    >
      {type || "C"}
    </span>
  );
}

// ── Mini chip ─────────────────────────────────────────────────────────────────
function MC({ label, bg }) {
  return (
    <span className="px-2 py-0.5 rounded-full text-[10px] font-bold" style={{ background: `${bg}33`, color: bg }}>
      {label}
    </span>
  );
}

// ── Empty state ───────────────────────────────────────────────────────────────
function Empty({ text }) {
  return (
    <div className="flex flex-col items-center justify-center py-10 gap-2">
      <Inbox size={40} style={{ color: COLORS.subtle }} />
      <p className="text-sm" style={{ color: COLORS.subtle }}>{text}</p>
    </div>
  );
}

// ── Error view ────────────────────────────────────────────────────────────────
function ErrorView({ error, onRetry }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 gap-3 px-8 text-center">
      <AlertCircle size={48} style={{ color: COLORS.red }} />
      <p className="font-bold text-base" style={{ color: COLORS.dark }}>डेटा लोड करने में त्रुटि</p>
      <p className="text-xs" style={{ color: COLORS.subtle }}>{error}</p>
      <button onClick={onRetry} className="flex items-center gap-2 px-4 py-2 rounded-lg text-white text-sm font-bold" style={{ background: COLORS.primary }}>
        <RefreshCw size={14} /> पुनः प्रयास
      </button>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// OFFICERS DIALOG
// ══════════════════════════════════════════════════════════════════════════════
function OfficersDialog({ title, color, endpoint, officers: initOfficers, onSave, onClose }) {
  const [officers, setOfficers] = useState(initOfficers.map(o => ({ ...o })));
  const [saving, setSaving] = useState(false);
  const { toasts, show } = useToast();

  const add = () => setOfficers(p => [...p, { name: "", pno: "", mobile: "", user_rank: "" }]);
  const remove = i => setOfficers(p => p.filter((_, j) => j !== i));
  const update = (i, key, val) => setOfficers(p => p.map((o, j) => j === i ? { ...o, [key]: val } : o));

  const save = async () => {
    setSaving(true);
    try {
      const payload = officers
        .filter(o => o.name?.trim())
        .map(o => ({ name: o.name, pno: o.pno, mobile: o.mobile, rank: o.user_rank }));

      const parts = endpoint.split("/");
      let type = "", id = "";
      if (endpoint.includes("super-zones")) { type = "super-zone"; id = parts[3]; }
      else if (endpoint.includes("zones")) { type = "zone"; id = parts[3]; }
      else if (endpoint.includes("sectors")) { type = "sector"; id = parts[3]; }

      await apiClient.post(`/admin/hierarchy/${type}/${id}/officers/replace`, { officers: payload });
      onSave(officers);
      onClose();
    } catch (e) {
      show(`त्रुटि: ${e.message}`, "error");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/40 z-[800] flex items-center justify-center p-4">
      <Toast toasts={toasts} />
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-lg max-h-[85vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center gap-2 px-4 py-3.5 rounded-t-2xl" style={{ background: color }}>
          <Users size={18} className="text-white" />
          <span className="flex-1 text-white font-extrabold text-sm">{title}</span>
          <button onClick={onClose}><X size={18} className="text-white" /></button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto p-4 space-y-3">
          {officers.map((o, i) => (
            <div key={i} className="rounded-xl border p-3 space-y-2" style={{ borderColor: COLORS.border, background: "#FAFAFA" }}>
              <div className="flex items-center justify-between">
                <span className="w-6 h-6 rounded-full flex items-center justify-center text-xs font-black" style={{ background: `${color}22`, color }}>{i + 1}</span>
                <button onClick={() => remove(i)} className="p-1 rounded-md" style={{ background: `${COLORS.red}14` }}>
                  <Trash2 size={14} style={{ color: COLORS.red }} />
                </button>
              </div>
              <input placeholder="नाम" value={o.name || ""} onChange={e => update(i, "name", e.target.value)}
                className="w-full border rounded-lg px-3 py-2 text-xs outline-none focus:ring-1" style={{ borderColor: COLORS.border }} />
              <div className="flex gap-2">
                <input placeholder="PNO" value={o.pno || ""} onChange={e => update(i, "pno", e.target.value)}
                  className="flex-1 border rounded-lg px-3 py-2 text-xs outline-none" style={{ borderColor: COLORS.border }} />
                <input placeholder="मोबाइल" value={o.mobile || ""} onChange={e => update(i, "mobile", e.target.value)}
                  className="flex-1 border rounded-lg px-3 py-2 text-xs outline-none" style={{ borderColor: COLORS.border }} />
              </div>
              <select value={o.user_rank || ""} onChange={e => update(i, "user_rank", e.target.value)}
                className="w-full border rounded-lg px-3 py-2 text-xs outline-none" style={{ borderColor: COLORS.border }}>
                <option value="">पद चुनें</option>
                {RANKS.map(r => <option key={r.en} value={r.en}>{r.hi} ({r.en})</option>)}
              </select>
            </div>
          ))}
          <button onClick={add} className="w-full py-2 rounded-xl border-2 border-dashed text-xs font-bold flex items-center justify-center gap-1"
            style={{ borderColor: color, color }}>
            <Plus size={14} /> अधिकारी जोड़ें
          </button>
        </div>

        {/* Footer */}
        <div className="flex gap-3 px-4 pb-4">
          <button onClick={onClose} className="flex-1 py-2 rounded-xl border text-sm font-medium" style={{ borderColor: COLORS.border }}>रद्द</button>
          <button onClick={save} disabled={saving}
            className="flex-1 py-2 rounded-xl text-white text-sm font-bold flex items-center justify-center gap-2"
            style={{ background: color }}>
            {saving ? <Loader2 size={15} className="animate-spin" /> : null}
            सहेजें
          </button>
        </div>
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// CENTER DIALOG
// ══════════════════════════════════════════════════════════════════════════════
function CenterDialog({ center, gpId, onClose, onSaved }) {
  const [form, setForm] = useState({
    name: center?.name || "",
    address: center?.address || "",
    thana: center?.thana || "",
    centerType: CENTER_TYPES.includes(center?.center_type) ? center.center_type : "C",
    busNo: center?.bus_no || center?.busNo || "",
  });
  const [saving, setSaving] = useState(false);
  const { show } = useToast();

  const save = async () => {
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      const data = { ...form, center_type: form.centerType };
      if (center) await apiClient.put(`/admin/hierarchy/sthal/${center.id}`, data);
      else await apiClient.post(`/admin/gram-panchayats/${gpId}/centers`, data);
      onSaved();
      onClose();
    } catch (e) {
      show(`त्रुटि: ${e.message}`, "error");
    } finally {
      setSaving(false);
    }
  };

  const F = ({ label, k, ...rest }) => (
    <div>
      <label className="block text-xs text-gray-500 mb-1">{label}</label>
      <input value={form[k] || ""} onChange={e => setForm(p => ({ ...p, [k]: e.target.value }))}
        className="w-full border rounded-lg px-3 py-2 text-sm outline-none focus:ring-1"
        style={{ borderColor: COLORS.border }}
        {...rest} />
    </div>
  );

  return (
    <div className="fixed inset-0 bg-black/40 z-[800] flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between px-5 py-4 border-b" style={{ borderColor: COLORS.border }}>
          <h3 className="font-extrabold text-sm" style={{ color: COLORS.dark }}>
            {center ? "मतदेय स्थल संपादित करें" : "मतदेय स्थल जोड़ें"}
          </h3>
          <button onClick={onClose}><X size={18} style={{ color: COLORS.subtle }} /></button>
        </div>
        <div className="p-5 space-y-3">
          <F label="नाम *" k="name" />
          <F label="पता" k="address" />
          <F label="थाना" k="thana" />
          <div>
            <label className="block text-xs text-gray-500 mb-2">संवेदनशीलता</label>
            <div className="flex flex-wrap gap-2">
              {CENTER_TYPES.map(t => (
                <button key={t} onClick={() => setForm(p => ({ ...p, centerType: t }))}
                  className="px-4 py-1.5 rounded-lg text-xs font-extrabold border-2 transition-all"
                  style={{
                    background: form.centerType === t ? sColor(t) : "#F5F5F5",
                    borderColor: sColor(t),
                    color: form.centerType === t ? "white" : sColor(t),
                  }}>
                  {t}
                </button>
              ))}
            </div>
          </div>
          <F label="बस संख्या" k="busNo" />
        </div>
        <div className="flex gap-3 px-5 pb-5">
          <button onClick={onClose} className="flex-1 py-2 rounded-xl border text-sm font-medium" style={{ borderColor: COLORS.border }}>रद्द</button>
          <button onClick={save} disabled={saving}
            className="flex-1 py-2 rounded-xl text-white text-sm font-bold flex items-center justify-center gap-2"
            style={{ background: COLORS.purple }}>
            {saving && <Loader2 size={14} className="animate-spin" />}
            सहेजें
          </button>
        </div>
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// GENERIC TEXT FIELD DIALOG
// ══════════════════════════════════════════════════════════════════════════════
function FieldDialog({ title, color, fields, initial = {}, onSave, onClose }) {
  const [form, setForm] = useState(
    Object.fromEntries(fields.map(f => [f.key, initial[f.key] || ""]))
  );
  const [saving, setSaving] = useState(false);
  const { show } = useToast();

  const save = async () => {
    if (fields.some(f => f.required && !form[f.key]?.trim())) return;
    setSaving(true);
    try {
      await onSave(form);
      onClose();
    } catch (e) {
      show(`त्रुटि: ${e.message}`, "error");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/40 z-[800] flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm">
        <div className="flex items-center gap-2 px-5 py-4 border-b" style={{ borderColor: COLORS.border }}>
          <span className="flex-1 font-extrabold text-sm" style={{ color: COLORS.dark }}>{title}</span>
          <button onClick={onClose}><X size={18} style={{ color: COLORS.subtle }} /></button>
        </div>
        <div className="p-5 space-y-3">
          {fields.map(f => (
            <div key={f.key}>
              <label className="block text-xs text-gray-500 mb-1">{f.label}{f.required ? " *" : ""}</label>
              <input value={form[f.key]} onChange={e => setForm(p => ({ ...p, [f.key]: e.target.value }))}
                className="w-full border rounded-lg px-3 py-2 text-sm outline-none focus:ring-1"
                style={{ borderColor: COLORS.border }} />
            </div>
          ))}
        </div>
        <div className="flex gap-3 px-5 pb-5">
          <button onClick={onClose} className="flex-1 py-2 rounded-xl border text-sm font-medium" style={{ borderColor: COLORS.border }}>रद्द</button>
          <button onClick={save} disabled={saving}
            className="flex-1 py-2 rounded-xl text-white text-sm font-bold flex items-center justify-center gap-2"
            style={{ background: color }}>
            {saving && <Loader2 size={14} className="animate-spin" />}
            सहेजें
          </button>
        </div>
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGINATED STAFF DIALOG
// ══════════════════════════════════════════════════════════════════════════════
function StaffDialog({ center, onChanged, onClose }) {
  const [staff, setStaff] = useState([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [q, setQ] = useState("");
  const [selectedId, setSelectedId] = useState(null);
  const [busNo, setBusNo] = useState(center.bus_no || "");
  const [assigned, setAssigned] = useState(center.duty_officers || []);
  const [saving, setSaving] = useState(false);
  const { show } = useToast();
  const scrollRef = useRef(null);
  const debounce = useRef(null);
  const pageRef = useRef(1);
  const hasMoreRef = useRef(true);

  const loadStaff = useCallback(async (reset = false, searchQ = q) => {
    if (loading) return;
    if (!reset && !hasMoreRef.current) return;
    const pg = reset ? 1 : pageRef.current;
    setLoading(true);
    try {
      const res = await apiClient.get(`/admin/staff?assigned=no&page=${pg}&limit=30&q=${encodeURIComponent(searchQ)}`);
      const wrapper = res?.data || {};
      const items = wrapper.data || [];
      const tot = wrapper.total || 0;
      const totalPages = wrapper.totalPages || 1;
      setStaff(p => reset ? items : [...p, ...items]);
      setTotal(tot);
      hasMoreRef.current = pg < totalPages;
      setHasMore(pg < totalPages);
      pageRef.current = pg + 1;
    } catch (e) { }
    setLoading(false);
  }, []);

  useEffect(() => {
    loadStaff(true);
  }, []);

  const onSearch = (val) => {
    setQ(val);
    clearTimeout(debounce.current);
    debounce.current = setTimeout(() => {
      setStaff([]); setPage(1); pageRef.current = 1; hasMoreRef.current = true;
      loadStaff(true, val);
    }, 300);
  };

  const onScroll = (e) => {
    const el = e.target;
    if (el.scrollTop + el.clientHeight >= el.scrollHeight - 100 && !loading && hasMoreRef.current) {
      loadStaff(false);
    }
  };

  const assign = async () => {
    if (!selectedId || saving) return;
    setSaving(true);
    try {
      await apiClient.post("/admin/duties", { staffId: selectedId, centerId: center.id, busNo });
      onChanged();
      onClose();
    } catch (e) {
      show(`त्रुटि: ${e.message}`, "error");
    } finally {
      setSaving(false);
    }
  };

  const removeDuty = async (d) => {
    try {
      await apiClient.delete(`/admin/duties/${d.id}`);
      onChanged();
      setAssigned(p => p.filter(a => a.id !== d.id));
    } catch (e) {
      show(`त्रुटि: ${e.message}`, "error");
    }
  };

  return (
    <div className="fixed inset-0 bg-black/40 z-[800] flex items-center justify-center p-4">
      <Toast toasts={[]} />
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-lg flex flex-col max-h-[88vh]">
        {/* Header */}
        <div className="flex items-center gap-2 px-4 py-3.5 rounded-t-2xl" style={{ background: COLORS.purple }}>
          <Users size={18} className="text-white" />
          <span className="flex-1 text-white font-extrabold text-sm truncate">स्टाफ – {center.name}</span>
          <button onClick={onClose}><X size={18} className="text-white" /></button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {/* Assigned */}
          {assigned.length > 0 && (
            <div>
              <p className="text-[10px] font-bold uppercase tracking-wide mb-2" style={{ color: COLORS.subtle }}>असाइन किए गए स्टाफ:</p>
              {assigned.map(d => (
                <div key={d.id} className="flex items-center gap-2 p-3 rounded-xl border mb-2" style={{ background: "#F3E5F5", borderColor: `${COLORS.purple}44` }}>
                  <div className="flex-1">
                    <p className="font-bold text-sm" style={{ color: COLORS.dark }}>{d.name}</p>
                    <p className="text-[10px]" style={{ color: COLORS.subtle }}>PNO: {d.pno} • {d.user_rank} • {d.mobile}</p>
                  </div>
                  <button onClick={() => removeDuty(d)}>
                    <MinusCircle size={18} style={{ color: COLORS.red }} />
                  </button>
                </div>
              ))}
              <div className="border-t my-2" style={{ borderColor: COLORS.border }} />
            </div>
          )}

          {/* Search */}
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wide mb-2" style={{ color: COLORS.subtle }}>नया स्टाफ जोड़ें:</p>
            <div className="relative mb-2">
              <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2" style={{ color: COLORS.subtle }} />
              <input
                value={q} onChange={e => onSearch(e.target.value)}
                placeholder={`नाम, PNO, थाना से खोजें... (${total} उपलब्ध)`}
                className="w-full pl-8 pr-8 py-2.5 border rounded-xl text-xs outline-none"
                style={{ borderColor: COLORS.border }}
              />
              {q && <button onClick={() => onSearch("")} className="absolute right-3 top-1/2 -translate-y-1/2"><X size={12} style={{ color: COLORS.subtle }} /></button>}
            </div>

            <div
              ref={scrollRef}
              onScroll={onScroll}
              className="h-52 overflow-y-auto rounded-xl border"
              style={{ borderColor: COLORS.border }}
            >
              {loading && staff.length === 0 ? (
                <div className="h-full flex items-center justify-center">
                  <Loader2 size={22} className="animate-spin" style={{ color: COLORS.purple }} />
                </div>
              ) : staff.length === 0 ? (
                <div className="h-full flex items-center justify-center text-xs" style={{ color: COLORS.subtle }}>
                  {q ? `"${q}" नहीं मिला` : "सभी स्टाफ असाइन किए जा चुके हैं"}
                </div>
              ) : (
                <div>
                  {staff.map((s, i) => {
                    const sel = selectedId === s.id;
                    return (
                      <div
                        key={s.id}
                        onClick={() => setSelectedId(sel ? null : s.id)}
                        className="flex items-center gap-3 px-3 py-2.5 cursor-pointer border-b last:border-b-0 hover:bg-purple-50 transition-colors"
                        style={{ borderColor: COLORS.border, background: sel ? "#F3E5F5" : undefined }}
                      >
                        <div className="w-5 h-5 rounded-full border-2 flex items-center justify-center flex-shrink-0 transition-all"
                          style={{ borderColor: sel ? COLORS.purple : COLORS.border, background: sel ? COLORS.purple : "white" }}>
                          {sel && <CheckCircle size={11} className="text-white" />}
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-xs font-semibold truncate" style={{ color: sel ? COLORS.purple : COLORS.dark }}>{s.name}</p>
                          <p className="text-[10px] truncate" style={{ color: COLORS.subtle }}>PNO: {s.pno} • {s.thana} • {s.rank}</p>
                        </div>
                      </div>
                    );
                  })}
                  {loading && (
                    <div className="flex justify-center py-2">
                      <Loader2 size={14} className="animate-spin" style={{ color: COLORS.purple }} />
                    </div>
                  )}
                </div>
              )}
            </div>
            {hasMore && !loading && (
              <p className="text-[10px] mt-1" style={{ color: COLORS.subtle }}>↓ स्क्रॉल करें — और स्टाफ लोड होंगे</p>
            )}
          </div>

          {/* Bus No */}
          <div>
            <label className="text-xs text-gray-500 mb-1 block flex items-center gap-1">
              <Bus size={12} /> बस संख्या
            </label>
            <input value={busNo} onChange={e => setBusNo(e.target.value)}
              className="w-full border rounded-lg px-3 py-2 text-sm outline-none"
              style={{ borderColor: COLORS.border }} />
          </div>
        </div>

        {/* Footer */}
        <div className="flex gap-3 px-4 pb-4">
          <button onClick={onClose} className="flex-1 py-2 rounded-xl border text-sm font-medium" style={{ borderColor: COLORS.border }}>बंद करें</button>
          {selectedId && (
            <button onClick={assign} disabled={saving}
              className="flex-1 py-2 rounded-xl text-white text-sm font-bold flex items-center justify-center gap-2"
              style={{ background: COLORS.purple }}>
              {saving && <Loader2 size={14} className="animate-spin" />}
              असाइन करें
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — Super Zone table
// ══════════════════════════════════════════════════════════════════════════════
function Tab1Card({ sz, onEdit, onDelete, onAddZone, onManageOfficers }) {
  const zones = sz.zones || [];
  let gpTotal = 0, sTotal = 0;
  zones.forEach(z => {
    const secs = z.sectors || [];
    sTotal += secs.length;
    secs.forEach(s => { gpTotal += (s.panchayats || []).length; });
  });

  const rows = [];
  let globalSec = 0;
  zones.forEach((z, zi) => {
    const sectors = z.sectors || [];
    const zOff = z.officers || [];
    if (sectors.length === 0) {
      rows.push({ zi, z, s: null, sGlobal: null, zOff, gpNames: "—", thanas: "—" });
    } else {
      sectors.forEach(s => {
        globalSec++;
        const gps = s.panchayats || [];
        rows.push({
          zi, z, s, sGlobal: globalSec, zOff,
          gpNames: gps.map(g => g.name).join("، ") || "—",
          thanas: [...new Set(gps.map(g => g.thana).filter(Boolean))].join("، ") || "—",
        });
      });
    }
  });

  return (
    <div className="mb-4 rounded-2xl border overflow-hidden shadow-md" style={{ borderColor: COLORS.border }}>
      {/* Header */}
      <div className="px-4 py-3" style={{ background: "linear-gradient(to right, #0F2B5B, #1E3F80)" }}>
        <div className="flex items-start gap-2">
          <div className="flex-1">
            <p className="text-white font-extrabold text-sm">सुपर जोन–{sz.name}  ब्लाक {sz.block || "—"}</p>
            <p className="text-white/60 text-[11px]">जिला: {sz.district || "—"}  |  कुल ग्राम पंचायत: {gpTotal}</p>
          </div>
          <div className="flex items-center gap-0.5">
            <IAB icon={UserPlus} color="#81E6D9" onClick={onManageOfficers} title="अधिकारी" />
            <IAB icon={PlusCircle} color={COLORS.accent} onClick={onAddZone} title="जोन जोड़ें" />
            <IAB icon={Edit2} color={COLORS.accent} onClick={onEdit} />
            <IAB icon={Trash2} color="#FC8181" onClick={onDelete} />
          </div>
        </div>
        <div className="flex gap-1.5 mt-2 flex-wrap">
          <MC label={`${zones.length} जोन`} bg="#60A5FA" />
          <MC label={`${sTotal} सैक्टर`} bg="#34D399" />
          <MC label={`${gpTotal} ग्राम पंचायत`} bg="#FB923C" />
        </div>
      </div>

      {/* Officers strip */}
      {(sz.officers || []).length > 0 && (
        <div className="px-4 py-2" style={{ background: COLORS.gold }}>
          <p className="text-[10px] font-bold mb-1" style={{ color: COLORS.subtle }}>सुपर जोन / क्षेत्र अधिकारी:</p>
          {sz.officers.map((o, i) => (
            <p key={i} className="text-[11px] flex items-center gap-1" style={{ color: COLORS.dark }}>
              <BadgeCheck size={11} style={{ color: COLORS.primary }} />
              {o.name} {o.user_rank} {o.pno ? `PNO: ${o.pno}` : ""} {o.mobile ? `मो: ${o.mobile}` : ""}
            </p>
          ))}
        </div>
      )}

      {/* Table */}
      {rows.length === 0 ? <Empty text="कोई जोन/सैक्टर नहीं" /> : (
        <div className="overflow-x-auto p-2">
          <table className="w-full text-[11px] border-collapse" style={{ minWidth: 900 }}>
            <thead>
              <tr style={{ background: "#F5EAD0" }}>
                {["सुपर\nजोन", "जोन", "जोनल अधिकारी\n/ जोनल पुलिस\nअधिकारी", "मुख्यालय", "सैक्टर\nसं.", "सैक्टर पुलिस\nअधिकारी का नाम", "मुख्यालय", "ग्राम पंचायत का नाम", "थाना"]
                  .map((h, i) => (
                    <th key={i} className="border p-1.5 text-center font-extrabold whitespace-pre-line leading-tight"
                      style={{ borderColor: COLORS.border, color: COLORS.dark, fontSize: 10 }}>{h}</th>
                  ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => {
                const isFirstInZone = i === 0 || rows[i - 1].zi !== r.zi;
                const bg = r.zi % 2 === 0 ? "#FFFDF7" : "white";
                const zOffText = (r.zOff || []).map(o => `${o.name || ""}\n${o.user_rank || ""}`).join("\n") || "—";
                const sOff = r.s?.officers || [];
                const sText = sOff.map(o => `${o.name || ""}\n${o.user_rank || ""}\n${o.mobile || ""}`).join("\n") || "—";
                return (
                  <tr key={i} style={{ background: bg }}>
                    <td className="border p-1.5 text-center align-middle" style={{ borderColor: COLORS.border }}>
                      {i === 0 && <span className="font-bold text-[9px]" style={{ color: COLORS.primary, writingMode: "vertical-lr" }}>सुपर जोन–{sz.name}</span>}
                    </td>
                    <td className="border p-1.5 text-center align-top font-black text-base" style={{ borderColor: COLORS.border, color: COLORS.primary }}>
                      {isFirstInZone ? r.zi + 1 : ""}
                    </td>
                    <td className="border p-1.5 align-top whitespace-pre-line" style={{ borderColor: COLORS.border }}>{isFirstInZone ? zOffText : ""}</td>
                    <td className="border p-1.5 align-top" style={{ borderColor: COLORS.border }}>{isFirstInZone ? (r.z.hq_address || r.z.hqAddress || "—") : ""}</td>
                    <td className="border p-1.5 text-center align-top font-extrabold" style={{ borderColor: COLORS.border, color: COLORS.green }}>{r.sGlobal || ""}</td>
                    <td className="border p-1.5 align-top whitespace-pre-line" style={{ borderColor: COLORS.border }}>{sText}</td>
                    <td className="border p-1.5 align-top" style={{ borderColor: COLORS.border }}>{r.s?.hq || r.z.hq_address || "—"}</td>
                    <td className="border p-1.5 align-top" style={{ borderColor: COLORS.border }}>{r.gpNames}</td>
                    <td className="border p-1.5 align-top" style={{ borderColor: COLORS.border }}>{r.thanas}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — Zone/Sector card
// ══════════════════════════════════════════════════════════════════════════════
function Tab2Card({ sz, z, onEditZone, onDeleteZone, onAddSector, onManageZoneOfficers, onEditSector, onDeleteSector, onAddGP, onManageSectorOfficers }) {
  const sectors = z.sectors || [];
  const zOff = z.officers || [];

  const rows = [];
  let sSeq = 0;
  sectors.forEach(s => {
    sSeq++;
    const gps = s.panchayats || [];
    const sOff = s.officers || [];
    const magStr = sOff.length > 0 ? `${sOff[0].name || ""}\n${sOff[0].user_rank || ""}\n${sOff[0].mobile || ""}` : "—";
    const polStr = sOff.length > 1 ? `${sOff[1].name || ""}\n${sOff[1].user_rank || ""}\n${sOff[1].mobile || ""}` : magStr;
    if (gps.length === 0) {
      rows.push({ s, sSeq, mag: magStr, pol: polStr, gp: null, first: true });
    } else {
      gps.forEach((gp, gi) => {
        rows.push({ s, sSeq, mag: gi === 0 ? magStr : "", pol: gi === 0 ? polStr : "", gp, first: gi === 0 });
      });
    }
  });

  return (
    <div className="mb-4 rounded-2xl border overflow-hidden shadow-md" style={{ borderColor: COLORS.border }}>
      <div className="px-4 py-3" style={{ background: "linear-gradient(to right, #186A3B, #239B56)" }}>
        <div className="flex items-start gap-2">
          <div className="flex-1">
            <p className="text-white font-extrabold text-sm">जोन: {z.name}</p>
            <p className="text-white/60 text-[11px]">सुपर जोन: {sz.name}  |  ब्लॉक: {sz.block || "—"}</p>
          </div>
          <div className="flex items-center gap-0.5">
            <IAB icon={UserPlus} color="#81E6D9" onClick={onManageZoneOfficers} title="अधिकारी" />
            <IAB icon={PlusCircle} color={COLORS.accent} onClick={onAddSector} title="सैक्टर जोड़ें" />
            <IAB icon={Edit2} color={COLORS.accent} onClick={onEditZone} />
            <IAB icon={Trash2} color="#FC8181" onClick={onDeleteZone} />
          </div>
        </div>
        {zOff.length > 0 && (
          <div className="mt-2 border-t border-white/20 pt-2">
            <p className="text-white/70 text-[10px] mb-1">जोनल अधिकारी:</p>
            {zOff.map((o, i) => (
              <p key={i} className="text-white text-[11px]">• {o.name} {o.user_rank} PNO: {o.pno || "—"} मो: {o.mobile || "—"}</p>
            ))}
          </div>
        )}
      </div>

      {rows.length === 0 ? <Empty text="कोई सैक्टर नहीं" /> : (
        <div className="overflow-x-auto p-2">
          <table className="w-full text-[11px] border-collapse" style={{ minWidth: 900 }}>
            <thead>
              <tr style={{ background: "#E8F5E9" }}>
                {["सैक्टर\nसं.", "सैक्टर मजिस्ट्रेट\n(नाम/पद/मोबाइल)", "सैक्टर पुलिस अधिकारी\n(नाम/पद/मोबाइल)", "ग्राम पंचायत", "मतदेय स्थल", "मतदान केन्द्र", "एक्शन"]
                  .map((h, i) => (
                    <th key={i} className="border p-1.5 text-center font-extrabold whitespace-pre-line leading-tight"
                      style={{ borderColor: COLORS.border, color: "#1B5E20", fontSize: 10 }}>{h}</th>
                  ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => {
                const gp = r.gp;
                const centers = gp?.centers || [];
                const sthalStr = centers.map(c => c.name).join("\n") || "—";
                const kStr = centers.flatMap(c => (c.kendras || []).map(k => k.room_number)).join(", ") || "—";
                const bg = i % 2 === 0 ? "white" : "#F1F8E9";
                return (
                  <tr key={i} style={{ background: bg }}>
                    <td className="border p-1.5 text-center font-black text-base align-top" style={{ borderColor: COLORS.border, color: COLORS.green }}>{r.first ? r.sSeq : ""}</td>
                    <td className="border p-1.5 align-top whitespace-pre-line" style={{ borderColor: COLORS.border }}>{r.mag}</td>
                    <td className="border p-1.5 align-top whitespace-pre-line" style={{ borderColor: COLORS.border }}>{r.pol}</td>
                    <td className="border p-1.5 align-top" style={{ borderColor: COLORS.border }}>{gp?.name || "—"}</td>
                    <td className="border p-1.5 align-top whitespace-pre-line" style={{ borderColor: COLORS.border }}>{sthalStr}</td>
                    <td className="border p-1.5 align-top" style={{ borderColor: COLORS.border }}>{kStr}</td>
                    <td className="border p-1.5 align-top" style={{ borderColor: COLORS.border }}>
                      {r.first && (
                        <div className="flex flex-wrap gap-0.5">
                          <IAB icon={UserPlus} color="teal" onClick={() => onManageSectorOfficers(r.s)} title="अधिकारी" />
                          <IAB icon={Plus} color={COLORS.green} onClick={() => onAddGP(r.s)} title="GP जोड़ें" />
                          <IAB icon={Edit2} color={COLORS.green} onClick={() => onEditSector(r.s)} />
                          <IAB icon={Trash2} color={COLORS.red} onClick={() => onDeleteSector(r.s)} />
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 — Booth Duty card
// ══════════════════════════════════════════════════════════════════════════════
function Tab3Card({ sz, z, s, gp, onAddCenter, onEditCenter, onDeleteCenter, onAddKendra, onDeleteKendra, onManageStaff }) {
  const centers = gp.centers || [];
  let totalKendra = 0;
  centers.forEach(c => {
    const k = c.kendras || [];
    totalKendra += k.length === 0 ? 1 : k.length;
  });

  const rows = [];
  let sthalNo = 1, kendraG = 1;
  centers.forEach(c => {
    const kendras = c.kendras || [];
    if (kendras.length === 0) {
      rows.push({ c, k: null, kNo: kendraG, sNo: sthalNo, first: true });
      sthalNo++; kendraG++;
    } else {
      kendras.forEach((k, ki) => {
        rows.push({ c, k, kNo: kendraG, sNo: ki === 0 ? sthalNo : null, first: ki === 0 });
        kendraG++;
      });
      sthalNo++;
    }
  });

  return (
    <div className="mb-4 rounded-2xl border overflow-hidden shadow-md" style={{ borderColor: COLORS.border }}>
      <div className="px-4 py-3" style={{ background: "linear-gradient(to right, #6C3483, #8E44AD)" }}>
        <div className="flex items-start gap-2">
          <div className="flex-1">
            <p className="text-white font-extrabold text-sm">बूथ ड्यूटी – ब्लॉक {sz.block || sz.name}</p>
            <div className="flex flex-wrap gap-3 mt-0.5">
              <span className="text-white/70 text-[11px]">ग्राम पंचायत: {gp.name}</span>
              <span className="text-white/60 text-[11px]">सैक्टर: {s.name}</span>
              <span className="text-white/60 text-[11px]">जोन: {z.name}</span>
            </div>
          </div>
          <div className="flex flex-col items-end gap-1">
            <span className="px-2.5 py-1 rounded-lg text-[11px] font-bold text-amber-300" style={{ background: "rgba(255,255,255,0.15)" }}>
              मतदेय स्थल: {centers.length}
            </span>
            <span className="px-2.5 py-1 rounded-lg text-[11px] font-bold text-amber-300" style={{ background: "rgba(255,255,255,0.15)" }}>
              मतदान केन्द्र: {totalKendra}
            </span>
          </div>
        </div>
        <button onClick={onAddCenter} className="mt-2 flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-white text-[11px] font-semibold"
          style={{ background: "rgba(255,255,255,0.2)" }}>
          <Plus size={13} /> मतदेय स्थल जोड़ें
        </button>
      </div>

      {rows.length === 0 ? <Empty text="कोई मतदेय स्थल नहीं" /> : (
        <div className="overflow-x-auto p-2">
          <table className="w-full text-[11px] border-collapse" style={{ minWidth: 1050 }}>
            <thead>
              <tr style={{ background: "#F3E5F5" }}>
                {["मतदान\nकेन्द्र की\nसंख्या", "मतदान केन्द्र\nका नाम", "मतदेय\nसं.", "मतदान स्थल\nका नाम", "जोन\nसंख्या", "सैक्टर\nसंख्या", "थाना", "ड्यूटी पर लगाया\nपुलिस का नाम", "मोबाईल\nनम्बर", "बस\nनं.", "एक्शन"]
                  .map((h, i) => (
                    <th key={i} className="border p-1.5 text-center font-extrabold whitespace-pre-line leading-tight"
                      style={{ borderColor: COLORS.border, color: COLORS.purple, fontSize: 9.5 }}>{h}</th>
                  ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => {
                const c = r.c;
                const k = r.k;
                const duty = c.duty_officers || [];
                const dText = duty.map(d => `${d.name || ""} ${d.pno || ""}\n${d.user_rank || ""}`).join("\n") || "—";
                const mText = duty.map(d => d.mobile || "").filter(Boolean).join("\n") || "—";
                const kLabel = k ? `${c.name} क.नं. ${k.room_number}` : c.name;
                const bg = i % 2 === 0 ? "white" : "#FDF4FF";
                return (
                  <tr key={i} style={{ background: bg }}>
                    <td className="border p-1.5 text-center font-extrabold text-sm" style={{ borderColor: COLORS.border, color: COLORS.purple }}>{r.kNo}</td>
                    <td className="border p-1.5 align-top" style={{ borderColor: COLORS.border }}>
                      <p className="text-[11px]" style={{ color: COLORS.dark }}>{kLabel}</p>
                      <SBadge type={c.center_type} />
                    </td>
                    <td className="border p-1.5 text-center font-bold align-top" style={{ borderColor: COLORS.border, color: COLORS.dark }}>{r.first && r.sNo ? r.sNo : ""}</td>
                    <td className="border p-1.5 align-top" style={{ borderColor: COLORS.border }}>
                      {r.first ? (
                        <>
                          <p>{c.name}</p>
                          {c.address && <p className="text-[9px]" style={{ color: COLORS.subtle }}>{c.address}</p>}
                        </>
                      ) : ""}
                    </td>
                    <td className="border p-1.5 text-center" style={{ borderColor: COLORS.border }}>{z.name}</td>
                    <td className="border p-1.5 text-center" style={{ borderColor: COLORS.border }}>{s.name}</td>
                    <td className="border p-1.5" style={{ borderColor: COLORS.border }}>{c.thana || gp.thana || "—"}</td>
                    <td className="border p-1.5 whitespace-pre-line" style={{ borderColor: COLORS.border }}>{dText}</td>
                    <td className="border p-1.5 whitespace-pre-line font-mono" style={{ borderColor: COLORS.border }}>{mText}</td>
                    <td className="border p-1.5 text-center font-bold" style={{ borderColor: COLORS.border }}>{c.bus_no || "—"}</td>
                    <td className="border p-1.5" style={{ borderColor: COLORS.border }}>
                      <div className="flex flex-wrap gap-0.5">
                        <IAB icon={Users} color={COLORS.green} onClick={() => onManageStaff(c)} title="स्टाफ" />
                        <IAB icon={PlusSquare} color={COLORS.primary} onClick={() => onAddKendra(c)} title="कक्ष जोड़ें" />
                        <IAB icon={Edit2} color={COLORS.purple} onClick={() => onEditCenter(c)} />
                        <IAB icon={Trash2} color={COLORS.red} onClick={() => onDeleteCenter(c)} />
                        {k && <IAB icon={MinusCircle} color={COLORS.orange} onClick={() => onDeleteKendra(k)} title="कक्ष हटाएं" />}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN PAGE
// ══════════════════════════════════════════════════════════════════════════════
export default function HierarchyReportPage({ role, onBack }) {
  const [tab, setTab] = useState(0);
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const nav = useNavigate()

  // Filters
  const [fSZ, setFSZ] = useState(null);
  const [fZone, setFZone] = useState(null);
  const [fSect, setFSect] = useState(null);
  const [fGP, setFGP] = useState(null);

  // Active dialog
  const [dialog, setDialog] = useState(null); // { type, props }

  const { toasts, show } = useToast();
  const { confirm, dialog: confirmDialog } = useConfirm();

  // ── Load ──────────────────────────────────────────────────────────────────
  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const res = await apiClient.get("/admin/hierarchy/full");
      setData(Array.isArray(res) ? res : (res?.data || []));
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, []);

  // Reset child filters on tab change
  const switchTab = (i) => {
    setTab(i);
    setFSZ(null); setFZone(null); setFSect(null); setFGP(null);
  };

  // ── Filtered lists ────────────────────────────────────────────────────────
  const filteredSZ = fSZ ? data.filter(s => `${s.id}` === fSZ) : data;
  const allZones = filteredSZ.flatMap(s => s.zones || []);
  const filteredZones = fZone ? allZones.filter(z => `${z.id}` === fZone) : allZones;
  const allSectors = allZones.flatMap(z => z.sectors || []);
  const filteredSectors = fSect ? allSectors.filter(s => `${s.id}` === fSect) : allSectors;
  const allGPs = allSectors.flatMap(s => s.panchayats || []);

  // ── Delete helper ─────────────────────────────────────────────────────────
  const del = async (ep, id, name) => {
    const ok = await confirm(`"${name}" को हटाना चाहते हैं?`);
    if (!ok) return;
    try {
      await apiClient.delete(`${ep}/${id}`);
      load(); show("सफलतापूर्वक हटाया गया");
    } catch (e) { show(`त्रुटि: ${e.message}`, "error"); }
  };

  // ── CRUD dialog openers ───────────────────────────────────────────────────
  const openField = (title, color, fields, initial, onSave) =>
    setDialog({ type: "field", props: { title, color, fields, initial, onSave } });

  const openOfficer = (title, color, endpoint, officers) =>
    setDialog({ type: "officer", props: { title, color, endpoint, officers } });

  const addSuperZone = () => openField(
    "सुपर जोन जोड़ें", COLORS.primary,
    [{ key: "name", label: "नाम", required: true }, { key: "district", label: "जिला" }, { key: "block", label: "ब्लॉक" }],
    {}, async (d) => { await apiClient.post("/admin/super-zones", d); load(); show("सफलतापूर्वक सहेजा गया"); }
  );
  const editSZ = (sz) => openField(
    "सुपर जोन संपादित करें", COLORS.primary,
    [{ key: "name", label: "नाम", required: true }, { key: "district", label: "जिला" }, { key: "block", label: "ब्लॉक" }],
    { name: sz.name, district: sz.district, block: sz.block },
    async (d) => { await apiClient.put(`/admin/hierarchy/super-zone/${sz.id}`, d); load(); show("सफलतापूर्वक सहेजा गया"); }
  );
  const addZone = (sz) => openField(
    `जोन जोड़ें – ${sz.name}`, COLORS.green,
    [{ key: "name", label: "जोन का नाम", required: true }, { key: "hqAddress", label: "मुख्यालय पता" }],
    {}, async (d) => { await apiClient.post(`/admin/super-zones/${sz.id}/zones`, d); load(); show("सफलतापूर्वक सहेजा गया"); }
  );
  const editZone = (z) => openField(
    "जोन संपादित करें", COLORS.green,
    [{ key: "name", label: "जोन का नाम", required: true }, { key: "hqAddress", label: "मुख्यालय पता" }],
    { name: z.name, hqAddress: z.hq_address || z.hqAddress },
    async (d) => { await apiClient.put(`/admin/zones/${z.id}`, d); load(); show("सफलतापूर्वक सहेजा गया"); }
  );
  const addSector = (z) => openField(
    `सैक्टर जोड़ें – ${z.name}`, COLORS.green,
    [{ key: "name", label: "सैक्टर का नाम", required: true }],
    {}, async (d) => { await apiClient.post(`/admin/zones/${z.id}/sectors`, d); load(); show("सफलतापूर्वक सहेजा गया"); }
  );
  const editSector = (s) => openField(
    "सैक्टर संपादित करें", COLORS.green,
    [{ key: "name", label: "सैक्टर का नाम", required: true }],
    { name: s.name },
    async (d) => { await apiClient.put(`/admin/hierarchy/sector/${s.id}`, d); load(); show("सफलतापूर्वक सहेजा गया"); }
  );
  const addGP = (s) => openField(
    `ग्राम पंचायत जोड़ें – ${s.name}`, COLORS.purple,
    [{ key: "name", label: "ग्राम पंचायत का नाम", required: true }, { key: "address", label: "पता" }],
    {}, async (d) => { await apiClient.post(`/admin/sectors/${s.id}/gram-panchayats`, d); load(); show("सफलतापूर्वक सहेजा गया"); }
  );
  const addKendra = (c) => openField(
    "मतदेय स्थल (कक्ष) जोड़ें", COLORS.purple,
    [{ key: "roomNumber", label: "कक्ष संख्या", required: true }],
    {}, async (d) => { await apiClient.post(`/admin/centers/${c.id}/rooms`, d); load(); show("सफलतापूर्वक सहेजा गया"); }
  );
  const openCenter = (center, gpId) => setDialog({ type: "center", props: { center, gpId } });
  const openStaff = (center) => setDialog({ type: "staff", props: { center } });

  const closeDialog = () => setDialog(null);

  // ── Tab 2 zone-sector iteration ───────────────────────────────────────────
  const tab2Items = [];
  filteredSZ.forEach(sz => {
    (sz.zones || []).forEach(z => {
      if (fZone && `${z.id}` !== fZone) return;
      tab2Items.push({ sz, z });
    });
  });

  const tab3Items = [];
  filteredSZ.forEach(sz => {
    (sz.zones || []).forEach(z => {
      if (fZone && `${z.id}` !== fZone) return;
      (z.sectors || []).forEach(s => {
        if (fSect && `${s.id}` !== fSect) return;
        (s.panchayats || []).forEach(gp => {
          if (fGP && `${gp.id}` !== fGP) return;
          tab3Items.push({ sz, z, s, gp });
        });
      });
    });
  });

  // ── Render ────────────────────────────────────────────────────────────────
  const TABS = [
    { label: "सुपर जोन", icon: Layers },
    { label: "जोन/सैक्टर", icon: Map },
    { label: "बूथ ड्यूटी", icon: Vote },
  ];

  return (
    <div className="min-h-screen flex flex-col" style={{ background: "#FAFAFA" }}>
      <Toast toasts={toasts} />
      {confirmDialog}

      {/* Dialogs */}
      {dialog?.type === "field" && (
        <FieldDialog {...dialog.props} onClose={closeDialog} />
      )}
      {dialog?.type === "officer" && (
        <OfficersDialog {...dialog.props}
          onSave={() => load()}
          onClose={closeDialog} />
      )}
      {dialog?.type === "center" && (
        <CenterDialog {...dialog.props}
          onSaved={() => { load(); show("सफलतापूर्वक सहेजा गया"); }}
          onClose={closeDialog} />
      )}
      {dialog?.type === "staff" && (
        <StaffDialog {...dialog.props}
          onChanged={() => load()}
          onClose={closeDialog} />
      )}

      {/* AppBar */}
      <div className="flex flex-col" style={{ background: COLORS.primary }}>
        <div className="flex items-center gap-2 px-3 py-3">
          {onBack && (
            <button onClick={() => nav("/")} className="p-1.5 rounded-lg hover:bg-white/10">
              <ArrowLeft size={18} className="text-white" />
            </button>
          )}
          <div className="flex-1">
            <p className="text-white font-extrabold text-[15px] leading-tight">प्रशासनिक पदानुक्रम</p>
            <p className="text-white/50 text-[10px]">Administrative Hierarchy Report</p>
          </div>
          <button
            onClick={() => printHierarchy(tab, filteredSZ, fZone, fSect, fGP)}
            className="p-1.5 rounded-lg hover:bg-white/10"
            title="प्रिंट"
          >
            <Printer size={18} className="text-white" />
          </button>
          <button onClick={addSuperZone} className="p-1.5 rounded-lg hover:bg-white/10" title="सुपर जोन जोड़ें">
            <PlusCircle size={18} className="text-white" />
          </button>
          <button onClick={load} className="p-1.5 rounded-lg hover:bg-white/10">
            <RefreshCw size={18} className="text-white" />
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-t border-white/10">
          {TABS.map((t, i) => {
            const Icon = t.icon;
            return (
              <button
                key={i}
                onClick={() => switchTab(i)}
                className="flex-1 flex flex-col items-center gap-0.5 py-2 text-[11px] font-bold transition-all relative"
                style={{ color: tab === i ? "white" : "rgba(255,255,255,0.38)" }}
              >
                <Icon size={15} />
                {t.label}
                {tab === i && (
                  <span className="absolute bottom-0 left-0 right-0 h-0.5 rounded-t" style={{ background: COLORS.accent }} />
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Filter bar */}
      <div className="bg-white border-b px-3 py-2 flex gap-2 overflow-x-auto" style={{ borderColor: COLORS.border }}>
        <FDrop label="सुपर जोन" value={fSZ} placeholder="सभी सुपर जोन"
          items={data.map(s => ({ value: `${s.id}`, label: s.name }))}
          onChange={v => { setFSZ(v); setFZone(null); setFSect(null); setFGP(null); }} />
        {tab >= 1 && (
          <FDrop label="जोन" value={fZone} placeholder="सभी जोन"
            items={allZones.map(z => ({ value: `${z.id}`, label: z.name }))}
            onChange={v => { setFZone(v); setFSect(null); setFGP(null); }} />
        )}
        {tab >= 2 && (
          <>
            <FDrop label="सैक्टर" value={fSect} placeholder="सभी सैक्टर"
              items={allSectors.map(s => ({ value: `${s.id}`, label: s.name }))}
              onChange={v => { setFSect(v); setFGP(null); }} />
            <FDrop label="ग्राम पंचायत" value={fGP} placeholder="सभी GP"
              items={allGPs.map(g => ({ value: `${g.id}`, label: g.name }))}
              onChange={v => setFGP(v)} />
          </>
        )}
      </div>

      {/* Body */}
      <div className="flex-1 overflow-auto p-3">
        {loading ? (
          <div className="flex items-center justify-center h-64">
            <Loader2 size={36} className="animate-spin" style={{ color: COLORS.primary }} />
          </div>
        ) : error ? (
          <ErrorView error={error} onRetry={load} />
        ) : (
          <>
            {/* TAB 0 */}
            {tab === 0 && (
              filteredSZ.length === 0 ? <Empty text="कोई सुपर जोन नहीं मिला" /> :
                filteredSZ.map(sz => (
                  <Tab1Card
                    key={sz.id} sz={sz}
                    onEdit={() => editSZ(sz)}
                    onDelete={() => del("/admin/hierarchy/super-zone", sz.id, sz.name)}
                    onAddZone={() => addZone(sz)}
                    onManageOfficers={() => openOfficer("सुपर जोन अधिकारी", COLORS.primary, `/admin/super-zones/${sz.id}/officers`, sz.officers || [])}
                  />
                ))
            )}

            {/* TAB 1 */}
            {tab === 1 && (
              tab2Items.length === 0 ? <Empty text="कोई जोन नहीं मिला" /> :
                tab2Items.map(({ sz, z }) => (
                  <Tab2Card
                    key={z.id} sz={sz} z={z}
                    onEditZone={() => editZone(z)}
                    onDeleteZone={() => del("/admin/zones", z.id, z.name)}
                    onAddSector={() => addSector(z)}
                    onManageZoneOfficers={() => openOfficer("जोनल अधिकारी", COLORS.green, `/admin/zones/${z.id}/officers`, z.officers || [])}
                    onEditSector={editSector}
                    onDeleteSector={s => del("/admin/hierarchy/sector", s.id, s.name)}
                    onAddGP={addGP}
                    onManageSectorOfficers={s => openOfficer("सैक्टर अधिकारी", COLORS.green, `/admin/sectors/${s.id}/officers`, s.officers || [])}
                  />
                ))
            )}

            {/* TAB 2 */}
            {tab === 2 && (
              tab3Items.length === 0 ? <Empty text="कोई पंचायत नहीं मिली" /> :
                tab3Items.map(({ sz, z, s, gp }) => (
                  <Tab3Card
                    key={gp.id} sz={sz} z={z} s={s} gp={gp}
                    onAddCenter={() => openCenter(null, gp.id)}
                    onEditCenter={c => openCenter(c, null)}
                    onDeleteCenter={c => del("/admin/hierarchy/sthal", c.id, c.name)}
                    onAddKendra={addKendra}
                    onDeleteKendra={k => del("/admin/rooms", k.id, k.room_number)}
                    onManageStaff={openStaff}
                  />
                ))
            )}
          </>
        )}
      </div>

      <style>{`
        @keyframes fade-in {
          from { opacity: 0; transform: translateY(-6px); }
          to { opacity: 1; transform: translateY(0); }
        }
        .animate-fade-in { animation: fade-in 0.25s ease-out; }
      `}</style>
    </div>
  );
}