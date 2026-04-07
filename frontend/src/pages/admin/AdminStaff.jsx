import { useEffect, useState, useCallback, useRef } from "react";
import {
  Plus, Search, CheckCircle2, XCircle, Upload, Users, UserCheck,
  UserX, ChevronLeft, ChevronRight, X, Loader2, RefreshCw,
  Phone, MapPin, Hash, Shield, Building2, Trash2, Edit3,
  FileSpreadsheet, Star, Award, User, BadgeCheck, Sword, ShieldOff
} from "lucide-react";

const BASE_URL = "http://127.0.0.1:5000/api/admin";

const apiFetch = async (path, options = {}) => {
  const token = localStorage.getItem("token");
  const res = await fetch(`${BASE_URL}${path}`, {
    headers: { "Content-Type": "application/json", Authorization: token ? `Bearer ${token}` : "" },
    ...options,
  });
  const json = await res.json();
  if (!res.ok) throw { response: { data: json } };
  return json;
};

const adminAPI = {
  getStaff: (q = "") => apiFetch(`/staff${q ? `?q=${encodeURIComponent(q)}` : ""}`),
  addStaff: (body) => apiFetch("/staff", { method: "POST", body: JSON.stringify(body) }),
  addStaffBulk: (rows) => apiFetch("/staff/bulk", { method: "POST", body: JSON.stringify({ staff: rows }) }),
  updateStaff: (id, body) => apiFetch(`/staff/${id}`, { method: "PUT", body: JSON.stringify(body) }),
  deleteStaff: (id) => apiFetch(`/staff/${id}`, { method: "DELETE" }),
};

// ─── Rank config ──────────────────────────────────────────────────────────────
const RANKS = [
  { key: "all",       label: "सभी कर्मचारी", short: "सभी",       rankKeys: [],                                                                   icon: Users,     accent: "#78716c", headerBg: "bg-stone-700"   },
  { key: "sp",        label: "पुलिस अधीक्षक", short: "एसपी",     rankKeys: ["sp","पुलिस अधीक्षक"],                                              icon: Star,      accent: "#7c3aed", headerBg: "bg-violet-700"  },
  { key: "inspector", label: "निरीक्षक",       short: "निरीक्षक", rankKeys: ["inspector","निरीक्षक"],                                            icon: Award,     accent: "#1d4ed8", headerBg: "bg-blue-700"    },
  { key: "si",        label: "उप-निरीक्षक",   short: "एसआई",     rankKeys: ["si","sub-inspector","sub inspector","उप-निरीक्षक","उप निरीक्षक"], icon: BadgeCheck, accent: "#0e7490", headerBg: "bg-cyan-700"    },
  { key: "hc",        label: "हेड कांस्टेबल", short: "हेड कां.", rankKeys: ["hc","head constable","हेड कांस्टेबल"],                             icon: Shield,    accent: "#047857", headerBg: "bg-emerald-700" },
  { key: "constable", label: "कांस्टेबल",     short: "कांस्टेबल",rankKeys: ["constable","कांस्टेबल"],                                           icon: User,      accent: "#b45309", headerBg: "bg-amber-600"   },
  { key: "chaukidar", label: "चौकीदार",       short: "चौकीदार",  rankKeys: ["chaukidar","चौकीदार","watchman","guard"],                          icon: MapPin,    accent: "#be123c", headerBg: "bg-rose-700"    },
];

const matchRank = (staffRank, rankKeys) => {
  if (!rankKeys.length) return true;
  const r = (staffRank || "").toLowerCase().trim();
  return rankKeys.some((k) => r === k.toLowerCase() || r.includes(k.toLowerCase()));
};

// ─── Pagination ───────────────────────────────────────────────────────────────
const PAGE_SIZE = 10;
const paginate  = (list, page) => list.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

const PaginationBar = ({ page, totalPages, total, onChange }) => {
  const pages = [];
  for (let i = 1; i <= totalPages; i++) {
    if (i === 1 || i === totalPages || Math.abs(i - page) <= 1) pages.push(i);
    else if (pages[pages.length - 1] !== "...") pages.push("...");
  }
  const from = total === 0 ? 0 : (page - 1) * PAGE_SIZE + 1;
  const to   = Math.min(page * PAGE_SIZE, total);
  return (
    <div className="px-4 sm:px-6 py-4 border-t border-stone-100 flex flex-col sm:flex-row items-center justify-between gap-3">
      <p className="text-[12px] text-stone-400">
        {total === 0 ? "कोई परिणाम नहीं" : `${from}–${to} / कुल ${total}`}
      </p>
      {totalPages > 1 && (
        <div className="flex items-center gap-1 flex-wrap">
          <button disabled={page === 1} onClick={() => onChange(page - 1)}
            className="p-1.5 rounded-lg border border-stone-200 hover:bg-amber-50 disabled:opacity-40 disabled:cursor-not-allowed transition">
            <ChevronLeft size={14} className="text-stone-600" />
          </button>
          {pages.map((p, i) =>
            p === "..." ? (
              <span key={i} className="px-2 text-stone-400 text-sm">…</span>
            ) : (
              <button key={p} onClick={() => onChange(p)}
                className={`w-8 h-8 rounded-lg text-[13px] font-medium transition ${p === page ? "bg-amber-600 text-white shadow-sm" : "border border-stone-200 text-stone-600 hover:bg-amber-50"}`}>
                {p}
              </button>
            )
          )}
          <button disabled={page === totalPages} onClick={() => onChange(page + 1)}
            className="p-1.5 rounded-lg border border-stone-200 hover:bg-amber-50 disabled:opacity-40 disabled:cursor-not-allowed transition">
            <ChevronRight size={14} className="text-stone-600" />
          </button>
        </div>
      )}
    </div>
  );
};

const Spinner = () => (
  <div className="flex justify-center items-center py-16">
    <Loader2 size={28} className="animate-spin text-amber-600" />
  </div>
);

const Toast = ({ msg, type, onDone }) => {
  useEffect(() => { const t = setTimeout(onDone, 3000); return () => clearTimeout(t); }, [onDone]);
  return (
    <div className={`fixed bottom-6 right-6 z-[100] flex items-center gap-2.5 px-4 py-3 rounded-xl shadow-xl text-[13px] font-medium text-white ${type === "error" ? "bg-red-600" : "bg-emerald-600"}`}>
      {type === "error" ? <XCircle size={15} /> : <CheckCircle2 size={15} />}
      {msg}
    </div>
  );
};

// ─── Rank Table Section ───────────────────────────────────────────────────────
const RankSection = ({ allStaff, rankCfg, onEdit, onDelete }) => {
  const [search,      setSearch]      = useState("");
  const [page,        setPage]        = useState(1);
  const [armedFilter, setArmedFilter] = useState("all"); // "all" | "armed" | "unarmed"

  const filtered = allStaff
    .filter((s) => matchRank(s.rank, rankCfg.rankKeys))
    .filter((s) => {
      if (!search.trim()) return true;
      const q = search.toLowerCase();
      return (
        (s.name   || "").toLowerCase().includes(q) ||
        (s.pno    || "").toLowerCase().includes(q) ||
        (s.mobile || "").toLowerCase().includes(q) ||
        (s.thana  || "").toLowerCase().includes(q)
      );
    })
    .filter((s) => {
      if (armedFilter === "all")     return true;
      if (armedFilter === "armed")   return s.isArmed === true;
      if (armedFilter === "unarmed") return s.isArmed !== true;
      return true;
    });

  useEffect(() => { setPage(1); }, [search, rankCfg.key, armedFilter]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paged      = paginate(filtered, page);
  const assigned   = filtered.filter((s) => s.isAssigned).length;
  const unassigned = filtered.length - assigned;
  const armedCount   = filtered.filter((s) => s.isArmed === true).length;
  const unarmedCount = filtered.length - armedCount;

  return (
    <>
      {/* Search + armed filter + stats bar */}
      <div className="px-4 sm:px-6 py-3.5 border-b border-stone-100 flex flex-col gap-3">

        {/* Row 1: search + armed toggle */}
        <div className="flex flex-col sm:flex-row sm:items-center gap-3">
          {/* Search input */}
          <div className="relative flex-1 max-w-sm">
            <Search size={14} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-stone-400" />
            <input
              value={search} onChange={(e) => setSearch(e.target.value)}
              placeholder="नाम, PNO, मोबाइल या थाना खोजें…"
              className="w-full bg-stone-50 border border-stone-200 rounded-xl pl-9 pr-8 py-2.5 text-[13px] text-stone-800 placeholder-stone-400 focus:outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-100 transition"
            />
            {search && (
              <button onClick={() => setSearch("")} className="absolute right-2.5 top-1/2 -translate-y-1/2 text-stone-400 hover:text-stone-600">
                <X size={13} />
              </button>
            )}
          </div>

          {/* Armed / Unarmed filter pill */}
          <div className="flex items-center gap-1 bg-stone-100 rounded-xl p-1 shrink-0 self-start sm:self-auto">
            {[
              { key: "all",      label: "सभी",       icon: null       },
              { key: "armed",    label: "सशस्त्र",   icon: Sword      },
              { key: "unarmed",  label: "निःशस्त्र", icon: ShieldOff  },
            ].map(({ key, label, icon: Icon }) => (
              <button
                key={key}
                onClick={() => setArmedFilter(key)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[11px] font-bold transition-all ${
                  armedFilter === key
                    ? "bg-white text-stone-800 shadow-sm"
                    : "text-stone-500 hover:text-stone-700"
                }`}
              >
                {Icon && <Icon size={11} className={armedFilter === key ? "text-stone-700" : "text-stone-400"} />}
                {label}
                {/* count badge */}
                <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-bold min-w-[18px] text-center transition-all ${
                  armedFilter === key
                    ? key === "armed"
                      ? "bg-blue-100 text-blue-700"
                      : key === "unarmed"
                        ? "bg-stone-200 text-stone-600"
                        : "bg-amber-100 text-amber-700"
                    : "bg-stone-200/60 text-stone-400"
                }`}>
                  {key === "all"
                    ? allStaff.filter((s) => matchRank(s.rank, rankCfg.rankKeys)).length
                    : key === "armed"
                      ? allStaff.filter((s) => matchRank(s.rank, rankCfg.rankKeys) && s.isArmed === true).length
                      : allStaff.filter((s) => matchRank(s.rank, rankCfg.rankKeys) && s.isArmed !== true).length}
                </span>
              </button>
            ))}
          </div>
        </div>

        {/* Row 2: stats chips */}
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-[11px] px-2.5 py-1 rounded-full bg-stone-100 text-stone-600 font-semibold">कुल {filtered.length}</span>
          <span className="text-[11px] px-2.5 py-1 rounded-full bg-emerald-50 border border-emerald-200 text-emerald-700 font-semibold flex items-center gap-1">
            <CheckCircle2 size={10} /> नियुक्त {assigned}
          </span>
          <span className="text-[11px] px-2.5 py-1 rounded-full bg-red-50 border border-red-200 text-red-600 font-semibold flex items-center gap-1">
            <XCircle size={10} /> अनियुक्त {unassigned}
          </span>
          {/* Armed / Unarmed counts — always visible as info chips */}
          <span className="text-[11px] px-2.5 py-1 rounded-full bg-blue-50 border border-blue-200 text-blue-700 font-semibold flex items-center gap-1">
            <Sword size={10} /> सशस्त्र {armedCount}
          </span>
          <span className="text-[11px] px-2.5 py-1 rounded-full bg-stone-100 border border-stone-200 text-stone-600 font-semibold flex items-center gap-1">
            <ShieldOff size={10} /> निःशस्त्र {unarmedCount}
          </span>
          <span className="text-[12px] text-stone-400 ml-auto">पृष्ठ {page}/{totalPages}</span>
        </div>
      </div>

      {/* Table */}
      {paged.length === 0 ? (
        <div className="py-20 text-center">
          <div className="w-16 h-16 bg-stone-100 rounded-full flex items-center justify-center mx-auto mb-3">
            <Users size={28} className="text-stone-300" />
          </div>
          <p className="text-stone-500 font-medium">कोई कर्मचारी नहीं मिला</p>
          <p className="text-stone-400 text-[12px] mt-1">{search ? "खोज बदलकर देखें" : "नया कर्मचारी जोड़ें"}</p>
        </div>
      ) : (
        <>
          {/* Desktop table */}
          <div className="hidden md:block overflow-x-auto">
            <table className="w-full border-collapse text-[13px]">
              <thead>
                <tr className="bg-stone-50/80">
                  {["नाम","PNO","मोबाइल","थाना","जिला","पद","शस्त्र","स्थिति","नियुक्त केंद्र","क्रिया"].map((h) => (
                    <th key={h} className="px-4 py-3 text-left text-[10px] font-bold text-stone-400 uppercase tracking-widest border-b border-stone-100 whitespace-nowrap">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {paged.map((s, i) => (
                  <tr key={s.id}
                    className={`row-anim border-b border-stone-50 transition-colors group ${s.isAssigned ? "bg-emerald-50/50 hover:bg-emerald-50/80" : "hover:bg-amber-50/30"}`}
                    style={{ animationDelay: `${i * 20}ms` }}>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2.5">
                        <div className="w-8 h-8 rounded-full flex items-center justify-center text-white text-[11px] font-bold shrink-0"
                          style={{ background: `linear-gradient(135deg, ${rankCfg.accent}99, ${rankCfg.accent})` }}>
                          {(s.name || "?")[0]}
                        </div>
                        <span className="font-semibold text-stone-800 whitespace-nowrap">{s.name}</span>
                      </div>
                    </td>
                    <td className="px-4 py-3 font-mono text-[11px] text-stone-400 whitespace-nowrap">{s.pno}</td>
                    <td className="px-4 py-3 whitespace-nowrap">
                      {s.mobile ? <span className="flex items-center gap-1 text-stone-600"><Phone size={11} className="text-stone-400" />{s.mobile}</span>
                                : <span className="text-stone-300">—</span>}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap">
                      {s.thana ? <span className="flex items-center gap-1 text-stone-600"><MapPin size={11} className="text-stone-400" />{s.thana}</span>
                               : <span className="text-stone-300">—</span>}
                    </td>
                    <td className="px-4 py-3 text-stone-500 whitespace-nowrap">{s.district || "—"}</td>
                    <td className="px-4 py-3 whitespace-nowrap">
                      <span className="text-[11px] px-2 py-1 rounded-lg font-medium text-white"
                        style={{ backgroundColor: rankCfg.accent }}>
                        {s.rank || rankCfg.short}
                      </span>
                    </td>
                    {/* ── Armed column ── */}
                    <td className="px-4 py-3 whitespace-nowrap">
                      {s.isArmed
                        ? <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold bg-blue-50 text-blue-700 border border-blue-200">
                            <Sword size={10} /> सशस्त्र
                          </span>
                        : <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold bg-stone-100 text-stone-500 border border-stone-200">
                            <ShieldOff size={10} /> निःशस्त्र
                          </span>}
                    </td>
                    <td className="px-4 py-3">
                      {s.isAssigned
                        ? <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold bg-emerald-100 text-emerald-700 border border-emerald-200"><CheckCircle2 size={10} /> नियुक्त</span>
                        : <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold bg-red-50 text-red-600 border border-red-200"><XCircle size={10} /> अनियुक्त</span>}
                    </td>
                    <td className="px-4 py-3">
                      {s.centerName
                        ? <span className="flex items-center gap-1 text-[12px] text-stone-600 max-w-[160px]"><Building2 size={11} className="text-amber-500 shrink-0" /><span className="truncate">{s.centerName}</span></span>
                        : <span className="text-stone-300 text-[12px]">—</span>}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity duration-150">
                        <button onClick={() => onEdit(s)}
                          className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-amber-50 border border-amber-200 text-amber-700 text-[11px] font-semibold hover:bg-amber-100 hover:border-amber-300 transition-colors">
                          <Edit3 size={12} /> संपादित
                        </button>
                        <button onClick={() => onDelete(s)}
                          className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-red-50 border border-red-200 text-red-600 text-[11px] font-semibold hover:bg-red-100 hover:border-red-300 transition-colors">
                          <Trash2 size={12} /> हटाएं
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Mobile list */}
          <div className="md:hidden divide-y divide-stone-50">
            {paged.map((s) => (
              <div key={s.id} className={`px-4 py-4 transition ${s.isAssigned ? "bg-emerald-50/40" : "hover:bg-amber-50/30"}`}>
                <div className="flex items-start gap-3">
                  <div className="w-10 h-10 rounded-full flex items-center justify-center text-white font-bold shrink-0"
                    style={{ background: `linear-gradient(135deg, ${rankCfg.accent}99, ${rankCfg.accent})` }}>
                    {(s.name || "?")[0]}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap mb-1">
                      <span className="font-bold text-stone-800 text-[14px]">{s.name}</span>
                      {s.isAssigned
                        ? <span className="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-700 border border-emerald-200"><CheckCircle2 size={9} /> नियुक्त</span>
                        : <span className="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full bg-red-50 text-red-600 border border-red-200"><XCircle size={9} /> अनियुक्त</span>}
                      {/* Armed badge in mobile */}
                      {s.isArmed
                        ? <span className="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200"><Sword size={9} /> सशस्त्र</span>
                        : <span className="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full bg-stone-100 text-stone-500 border border-stone-200"><ShieldOff size={9} /> निःशस्त्र</span>}
                    </div>
                    <div className="flex flex-wrap gap-x-3 gap-y-1 text-[12px] text-stone-500">
                      <span className="flex items-center gap-1"><Hash size={10} />{s.pno}</span>
                      {s.mobile && <span className="flex items-center gap-1"><Phone size={10} />{s.mobile}</span>}
                      {s.thana  && <span className="flex items-center gap-1"><MapPin size={10} />{s.thana}</span>}
                    </div>
                    {s.rank && (
                      <span className="inline-block mt-1.5 text-[10px] px-2 py-0.5 rounded-md font-semibold text-white"
                        style={{ backgroundColor: rankCfg.accent }}>{s.rank}</span>
                    )}
                    {s.centerName && (
                      <div className="mt-1.5 flex items-center gap-1 text-[12px] text-emerald-700">
                        <Building2 size={11} /><span className="truncate">{s.centerName}</span>
                      </div>
                    )}
                  </div>
                  <div className="flex flex-col gap-1.5 shrink-0">
                    <button onClick={() => onEdit(s)} className="inline-flex items-center gap-1 px-2.5 py-2 rounded-xl bg-amber-50 border border-amber-200 text-amber-700 text-[11px] font-semibold hover:bg-amber-100 transition">
                      <Edit3 size={13} /> संपादित
                    </button>
                    <button onClick={() => onDelete(s)} className="inline-flex items-center gap-1 px-2.5 py-2 rounded-xl bg-red-50 border border-red-200 text-red-600 text-[11px] font-semibold hover:bg-red-100 transition">
                      <Trash2 size={13} /> हटाएं
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      <PaginationBar page={page} totalPages={totalPages} total={filtered.length} onChange={setPage} />
    </>
  );
};

// ─── Add / Edit Modal ─────────────────────────────────────────────────────────
const RANK_OPTIONS = [
  { value: "sp",        label: "एसपी — पुलिस अधीक्षक" },
  { value: "inspector", label: "निरीक्षक" },
  { value: "si",        label: "उप-निरीक्षक (एसआई)" },
  { value: "hc",        label: "हेड कांस्टेबल" },
  { value: "constable", label: "कांस्टेबल" },
  { value: "chaukidar", label: "चौकीदार" },
];

const StaffModal = ({ open, onClose, onSave, initial = null }) => {
  const blank = { name: "", pno: "", mobile: "", thana: "", rank: "" };
  const [form,   setForm]   = useState(blank);
  const [saving, setSaving] = useState(false);
  const [error,  setError]  = useState("");

  useEffect(() => {
    if (open) {
      setForm(initial ? { name: initial.name || "", pno: initial.pno || "", mobile: initial.mobile || "", thana: initial.thana || "", rank: initial.rank || "" } : blank);
      setError("");
    }
  }, [open, initial]);

  if (!open) return null;

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!form.name.trim() || !form.pno.trim()) { setError("नाम और PNO आवश्यक हैं"); return; }
    setSaving(true); setError("");
    try { await onSave(form); onClose(); }
    catch (err) { setError(err?.response?.data?.message || "सहेजने में त्रुटि हुई"); }
    finally { setSaving(false); }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md border border-amber-100 animate-in">
        <div className="flex items-center justify-between px-6 py-4 border-b border-stone-100">
          <h2 className="text-[15px] font-bold text-stone-800">{initial ? "✏️ कर्मचारी संपादित करें" : "➕ नया कर्मचारी जोड़ें"}</h2>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-stone-100 transition"><X size={16} /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {[
            { key: "name",   label: "पूरा नाम",    req: true,  ph: "जैसे: राम कुमार शर्मा" },
            { key: "pno",    label: "PNO",          req: true,  ph: "जैसे: PNO01234", disabled: !!initial },
            { key: "mobile", label: "मोबाइल नंबर", ph: "जैसे: 9876543210" },
            { key: "thana",  label: "थाना",         ph: "जैसे: कोतवाली" },
          ].map(({ key, label, req, ph, disabled }) => (
            <div key={key}>
              <label className="block text-[11px] font-bold text-stone-400 mb-1.5 uppercase tracking-wider">
                {label}{req && <span className="text-red-500 ml-0.5">*</span>}
              </label>
              <input
                className={`w-full border rounded-xl px-3.5 py-2.5 text-[13px] text-stone-800 placeholder-stone-400 focus:outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-100 transition ${disabled ? "bg-stone-100 opacity-60 cursor-not-allowed border-stone-200" : "bg-stone-50 border-stone-200"}`}
                value={form[key]} onChange={(e) => setForm((p) => ({ ...p, [key]: e.target.value }))}
                placeholder={ph} required={req} disabled={disabled} />
            </div>
          ))}
          <div>
            <label className="block text-[11px] font-bold text-stone-400 mb-1.5 uppercase tracking-wider">पद / रैंक</label>
            <select className="w-full bg-stone-50 border border-stone-200 rounded-xl px-3.5 py-2.5 text-[13px] text-stone-800 focus:outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-100 transition"
              value={form.rank} onChange={(e) => setForm((p) => ({ ...p, rank: e.target.value }))}>
              <option value="">— पद चुनें —</option>
              {RANK_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </div>
          {!initial && <div className="bg-amber-50 border border-amber-200 rounded-xl p-3 text-[12px] text-amber-700">🔑 डिफ़ॉल्ट पासवर्ड PNO होगा।</div>}
          {error && <p className="text-[12px] text-red-600 bg-red-50 border border-red-200 rounded-xl px-3 py-2">{error}</p>}
          <div className="flex gap-3 pt-1">
            <button type="button" onClick={onClose} className="flex-1 py-2.5 rounded-xl border border-stone-200 text-[13px] text-stone-600 hover:bg-stone-50 transition">रद्द करें</button>
            <button type="submit" disabled={saving} className="flex-1 py-2.5 rounded-xl bg-amber-600 text-white text-[13px] font-semibold hover:bg-amber-700 disabled:opacity-60 transition flex items-center justify-center gap-2">
              {saving && <Loader2 size={14} className="animate-spin" />}
              {saving ? "सहेज रहे हैं…" : initial ? "अपडेट करें" : "जोड़ें"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

// ─── Bulk Modal ───────────────────────────────────────────────────────────────
const BULK_COLS = [
  { key: "name", label: "नाम", req: true }, { key: "pno", label: "PNO", req: true },
  { key: "mobile", label: "मोबाइल" }, { key: "thana", label: "थाना" }, { key: "rank", label: "पद" },
];

const normalizeHeader = (h = "") => {
  const s = h.toLowerCase().trim();
  if (["name","नाम","full name","fullname","employee name"].includes(s)) return "name";
  if (["pno","p.no","p no","police number","id"].includes(s)) return "pno";
  if (["mobile","mobile number","phone","mob","contact","मोबाइल"].includes(s)) return "mobile";
  if (["thana","थाना","station","police station","ps"].includes(s)) return "thana";
  if (["rank","पद","designation","post","grade"].includes(s)) return "rank";
  return null;
};

const parseCSV = (text) => {
  const lines = text.trim().split(/\r?\n/);
  if (lines.length < 2) return [];
  const colMap = lines[0].split(",").map((h) => normalizeHeader(h.trim()));
  return lines.slice(1).map((line) => {
    const cells = line.split(",").map((c) => c.trim());
    const row = { name: "", pno: "", mobile: "", thana: "", rank: "" };
    colMap.forEach((key, i) => { if (key) row[key] = cells[i] || ""; });
    return row;
  }).filter((r) => r.name || r.pno);
};

const loadXLSX = () => new Promise((resolve, reject) => {
  if (window.XLSX) { resolve(window.XLSX); return; }
  const s = document.createElement("script");
  s.src = "https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js";
  s.onload = () => resolve(window.XLSX); s.onerror = reject;
  document.head.appendChild(s);
});

const parseExcel = async (file) => {
  const XLSX = await loadXLSX();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const wb  = XLSX.read(e.target.result, { type: "binary" });
        const ws  = wb.Sheets[wb.SheetNames[0]];
        const raw = XLSX.utils.sheet_to_json(ws, { header: 1, defval: "" });
        if (raw.length < 2) { resolve([]); return; }
        const colMap = raw[0].map((h) => normalizeHeader(String(h)));
        const rows = raw.slice(1).map((cells) => {
          const row = { name: "", pno: "", mobile: "", thana: "", rank: "" };
          colMap.forEach((key, i) => { if (key) row[key] = String(cells[i] || "").trim(); });
          return row;
        }).filter((r) => r.name || r.pno);
        resolve(rows);
      } catch (err) { reject(err); }
    };
    reader.onerror = reject; reader.readAsBinaryString(file);
  });
};

const BulkModal = ({ open, onClose, onImport }) => {
  const [stage, setStage]         = useState("upload");
  const [rows, setRows]           = useState([]);
  const [importing, setImporting] = useState(false);
  const [result, setResult]       = useState(null);
  const [fileError, setFileError] = useState("");
  const [fileName, setFileName]   = useState("");
  const [parsing, setParsing]     = useState(false);
  const fileInputRef = useRef(null);

  useEffect(() => { if (open) { setStage("upload"); setRows([]); setResult(null); setFileError(""); setFileName(""); } }, [open]);
  if (!open) return null;

  const handleFile = async (file) => {
    if (!file) return;
    setFileError(""); setParsing(true); setFileName(file.name);
    try {
      let parsed = [];
      if (file.name.endsWith(".csv") || file.type === "text/csv") parsed = parseCSV(await file.text());
      else if (file.name.match(/\.xlsx?$/) || file.type.includes("spreadsheet") || file.type.includes("excel")) parsed = await parseExcel(file);
      else { setFileError("केवल .xlsx, .xls या .csv फ़ाइलें स्वीकार की जाती हैं"); setParsing(false); return; }
      if (!parsed.length) { setFileError("फ़ाइल में कोई मान्य डेटा नहीं मिला"); setParsing(false); return; }
      setRows(parsed); setStage("preview");
    } catch (e) { setFileError("फ़ाइल पढ़ने में त्रुटि: " + (e?.message || "अज्ञात")); }
    finally { setParsing(false); }
  };

  const updateCell   = (i, key, val) => setRows((p) => p.map((r, j) => j === i ? { ...r, [key]: val } : r));
  const removeRow    = (i)           => setRows((p) => p.filter((_, j) => j !== i));
  const validRows    = rows.filter((r) => r.name.trim() && r.pno.trim());
  const invalidCount = rows.length - validRows.length;

  const handleImport = async () => {
    if (!validRows.length) return;
    setImporting(true);
    try {
      const res = await onImport(validRows);
      setResult({ added: res.data?.added ?? 0, skipped: res.data?.skipped ?? [], total: res.data?.total ?? validRows.length });
      setStage("result");
    } catch (e) { setResult({ error: e?.response?.data?.message || "आयात विफल" }); setStage("result"); }
    finally { setImporting(false); }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <div className="bg-white rounded-2xl shadow-2xl border border-amber-100 flex flex-col"
        style={{ width: stage === "preview" ? "min(96vw, 860px)" : "min(96vw, 520px)", maxHeight: "90vh" }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-stone-100 shrink-0">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-lg bg-amber-100 flex items-center justify-center"><FileSpreadsheet size={16} className="text-amber-700" /></div>
            <h2 className="text-[15px] font-bold text-stone-800">
              {stage === "upload" && "📋 थोक आयात — फ़ाइल चुनें"}
              {stage === "preview" && `📋 डेटा संपादित करें — ${rows.length} पंक्तियाँ`}
              {stage === "result" && "📋 आयात परिणाम"}
            </h2>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-stone-100 transition"><X size={16} /></button>
        </div>

        <div className="overflow-y-auto flex-1 p-6">
          {stage === "upload" && (
            <div className="space-y-5">
              <div className="bg-blue-50 border border-blue-200 rounded-xl p-4 text-[12px] text-blue-700 space-y-2">
                <p className="font-bold text-[13px]">Excel / CSV प्रारूप</p>
                <div className="grid grid-cols-5 gap-1">
                  {["name","pno","mobile","thana","rank"].map((h) => (
                    <code key={h} className="bg-blue-100 rounded px-2 py-1 text-center font-mono text-[11px] text-blue-800">{h}</code>
                  ))}
                </div>
                <p className="text-[11px] opacity-70">हिंदी हेडर भी मान्य हैं। mobile, thana, rank वैकल्पिक हैं।</p>
              </div>
              <div className="relative border-2 border-dashed rounded-2xl p-10 text-center cursor-pointer border-stone-200 hover:border-amber-400 hover:bg-amber-50/40 transition"
                onDragOver={(e) => e.preventDefault()} onDrop={(e) => { e.preventDefault(); handleFile(e.dataTransfer.files[0]); }}
                onClick={() => !parsing && fileInputRef.current?.click()}>
                <input ref={fileInputRef} type="file" accept=".xlsx,.xls,.csv" className="hidden" onChange={(e) => handleFile(e.target.files[0])} />
                {parsing ? (
                  <div className="flex flex-col items-center gap-3"><Loader2 size={32} className="animate-spin text-amber-600" /><p className="text-[13px] text-amber-700 font-medium">फ़ाइल पढ़ी जा रही है…</p></div>
                ) : (
                  <div className="flex flex-col items-center gap-3">
                    <div className="w-14 h-14 rounded-2xl bg-amber-100 flex items-center justify-center"><FileSpreadsheet size={28} className="text-amber-600" /></div>
                    <div>
                      <p className="text-[14px] font-semibold text-stone-700">Excel या CSV फ़ाइल यहाँ खींचें</p>
                      <p className="text-[12px] text-stone-400 mt-1">या क्लिक करके फ़ाइल चुनें (.xlsx, .xls, .csv)</p>
                    </div>
                    <button type="button" className="mt-1 px-5 py-2 rounded-xl bg-amber-600 text-white text-[13px] font-semibold hover:bg-amber-700 transition flex items-center gap-2"><Upload size={14} /> फ़ाइल चुनें</button>
                  </div>
                )}
              </div>
              {fileError && <div className="bg-red-50 border border-red-200 rounded-xl px-4 py-3 text-[12px] text-red-700">{fileError}</div>}
            </div>
          )}

          {stage === "preview" && (
            <div className="space-y-4">
              <div className="flex flex-wrap items-center gap-3">
                <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-emerald-50 border border-emerald-200"><CheckCircle2 size={13} className="text-emerald-600" /><span className="text-[12px] font-semibold text-emerald-700">{validRows.length} मान्य पंक्तियाँ</span></div>
                {invalidCount > 0 && <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-red-50 border border-red-200"><XCircle size={13} className="text-red-500" /><span className="text-[12px] font-semibold text-red-600">{invalidCount} अमान्य</span></div>}
                <span className="text-[12px] text-stone-400 ml-auto">{fileName}</span>
              </div>
              <div className="text-[12px] text-stone-500 bg-stone-50 border border-stone-200 rounded-xl px-3 py-2.5">💡 किसी भी सेल पर क्लिक करके संपादित करें। 🗑️ बटन से पंक्ति हटाएं।</div>
              <div className="rounded-xl border border-stone-200 overflow-hidden">
                <div className="overflow-x-auto">
                  <table className="w-full text-[12px] border-collapse">
                    <thead>
                      <tr className="bg-stone-50 border-b border-stone-200">
                        <th className="px-3 py-2.5 text-left text-[10px] font-bold text-stone-400 uppercase w-8">#</th>
                        {BULK_COLS.map((c) => <th key={c.key} className="px-3 py-2.5 text-left text-[10px] font-bold text-stone-400 uppercase whitespace-nowrap">{c.label}{c.req && <span className="text-red-400 ml-0.5">*</span>}</th>)}
                        <th className="px-3 py-2.5 w-10"></th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((row, i) => {
                        const invalid = !row.name.trim() || !row.pno.trim();
                        return (
                          <tr key={i} className={`border-b border-stone-100 ${invalid ? "bg-red-50/60" : "hover:bg-amber-50/30"}`}>
                            <td className="px-3 py-1.5 text-stone-400 text-[11px]">{i + 1}</td>
                            {BULK_COLS.map((c) => (
                              <td key={c.key} className="px-2 py-1">
                                <input value={row[c.key]} onChange={(e) => updateCell(i, c.key, e.target.value)}
                                  className={`w-full min-w-[80px] rounded-lg border px-2 py-1.5 text-[12px] text-stone-800 focus:outline-none focus:border-amber-500 transition ${invalid && c.req ? "border-red-300 bg-red-50" : "border-stone-200 bg-white"}`}
                                  placeholder={c.label} />
                              </td>
                            ))}
                            <td className="px-2 py-1.5 text-center"><button onClick={() => removeRow(i)} className="p-1.5 rounded-lg hover:bg-red-100 text-red-400 hover:text-red-600 transition"><Trash2 size={13} /></button></td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          )}

          {stage === "result" && (
            <div className="text-center py-6 space-y-4">
              {result?.error ? (
                <div className="text-red-600 bg-red-50 border border-red-200 rounded-xl p-4 text-[13px]">{result.error}</div>
              ) : (
                <>
                  <div className="w-16 h-16 bg-emerald-100 rounded-full flex items-center justify-center mx-auto"><CheckCircle2 size={32} className="text-emerald-600" /></div>
                  <div>
                    <p className="text-[18px] font-bold text-stone-800">{result?.added} कर्मचारी जोड़े गए!</p>
                    <p className="text-[13px] text-stone-500 mt-1">कुल {result?.total} में से {result?.added} सफल</p>
                  </div>
                  {result?.skipped?.length > 0 && (
                    <div className="bg-amber-50 border border-amber-200 rounded-xl p-3 text-left">
                      <p className="text-[12px] font-bold text-amber-700 mb-1">{result.skipped.length} छोड़े गए (पहले से मौजूद PNO):</p>
                      <p className="text-[11px] text-amber-600 font-mono break-all">{result.skipped.join(", ")}</p>
                    </div>
                  )}
                </>
              )}
            </div>
          )}
        </div>

        <div className="shrink-0 px-6 py-4 border-t border-stone-100 flex gap-3">
          {stage === "upload"  && <button onClick={onClose} className="flex-1 py-2.5 rounded-xl border border-stone-200 text-[13px] text-stone-600 hover:bg-stone-50 transition">रद्द करें</button>}
          {stage === "preview" && (
            <>
              <button onClick={() => { setStage("upload"); setRows([]); setFileName(""); }} className="px-5 py-2.5 rounded-xl border border-stone-200 text-[13px] text-stone-600 hover:bg-stone-50 transition flex items-center gap-2"><ChevronLeft size={14} /> वापस</button>
              <button onClick={handleImport} disabled={importing || !validRows.length} className="flex-1 py-2.5 rounded-xl bg-amber-600 text-white text-[13px] font-semibold hover:bg-amber-700 disabled:opacity-60 transition flex items-center justify-center gap-2">
                {importing ? <Loader2 size={14} className="animate-spin" /> : <Upload size={14} />}
                {importing ? "आयात हो रहा है…" : `${validRows.length} कर्मचारी DB में सहेजें`}
              </button>
            </>
          )}
          {stage === "result" && <button onClick={onClose} className="flex-1 py-2.5 rounded-xl bg-amber-600 text-white text-[13px] font-semibold hover:bg-amber-700 transition">बंद करें</button>}
        </div>
      </div>
    </div>
  );
};

// ─── Delete Confirm ───────────────────────────────────────────────────────────
const DeleteConfirm = ({ staff, onConfirm, onClose, deleting }) => (
  <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
    <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm border border-red-100 p-6 text-center space-y-4">
      <div className="w-14 h-14 bg-red-100 rounded-full flex items-center justify-center mx-auto"><Trash2 size={24} className="text-red-600" /></div>
      <div>
        <p className="font-bold text-stone-800 text-[15px]">कर्मचारी हटाएं?</p>
        <p className="text-[13px] text-stone-500 mt-1.5"><span className="font-semibold text-stone-700">{staff.name}</span> ({staff.pno}) को स्थायी रूप से हटाया जाएगा।</p>
      </div>
      <div className="flex gap-3">
        <button onClick={onClose} disabled={deleting} className="flex-1 py-2.5 rounded-xl border border-stone-200 text-[13px] hover:bg-stone-50 disabled:opacity-60 transition">रद्द करें</button>
        <button onClick={onConfirm} disabled={deleting} className="flex-1 py-2.5 rounded-xl bg-red-600 text-white text-[13px] font-semibold hover:bg-red-700 disabled:opacity-60 transition flex items-center justify-center gap-2">
          {deleting && <Loader2 size={13} className="animate-spin" />}
          {deleting ? "हटा रहे हैं…" : "हाँ, हटाएं"}
        </button>
      </div>
    </div>
  </div>
);

// ─── Main Page ────────────────────────────────────────────────────────────────
export default function AdminStaff() {
  const [allStaff,     setAllStaff]     = useState([]);
  const [loading,      setLoading]      = useState(true);
  const [activeRank,   setActiveRank]   = useState("all");
  const [addOpen,      setAddOpen]      = useState(false);
  const [editTarget,   setEditTarget]   = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting,     setDeleting]     = useState(false);
  const [bulkOpen,     setBulkOpen]     = useState(false);
  const [toast,        setToast]        = useState(null);

  const showToast = (msg, type = "success") => setToast({ msg, type });

  const loadStaff = useCallback(async () => {
    setLoading(true);
    try { const res = await adminAPI.getStaff(); setAllStaff(res.data || []); }
    catch { showToast("कर्मचारी लोड करने में त्रुटि", "error"); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { loadStaff(); }, [loadStaff]);

  const countFor = (cfg) => !cfg.rankKeys.length ? allStaff.length : allStaff.filter((s) => matchRank(s.rank, cfg.rankKeys)).length;

  const stats = {
    total:      allStaff.length,
    assigned:   allStaff.filter((s) => s.isAssigned).length,
    unassigned: allStaff.filter((s) => !s.isAssigned).length,
  };

  const handleAdd    = async (form) => { await adminAPI.addStaff(form); showToast(`${form.name} को सफलतापूर्वक जोड़ा गया`); loadStaff(); };
  const handleEdit   = async (form) => { await adminAPI.updateStaff(editTarget.id, form); showToast("कर्मचारी जानकारी अपडेट हुई"); setEditTarget(null); loadStaff(); };
  const handleDelete = async () => {
    setDeleting(true);
    try { await adminAPI.deleteStaff(deleteTarget.id); showToast(`${deleteTarget.name} को हटाया गया`); setDeleteTarget(null); loadStaff(); }
    catch (e) { showToast(e?.response?.data?.message || "हटाने में त्रुटि", "error"); }
    finally { setDeleting(false); }
  };
  const handleBulk = async (rows) => { const res = await adminAPI.addStaffBulk(rows); loadStaff(); return res; };

  const activeRankCfg = RANKS.find((r) => r.key === activeRank) || RANKS[0];

  return (
    <div className="min-h-screen bg-gradient-to-br from-amber-50 via-stone-50 to-orange-50">
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;500;600;700;800&display=swap');
        * { font-family: 'Noto Sans Devanagari', system-ui, sans-serif; }
        .animate-in { animation: modalIn .18s ease; }
        @keyframes modalIn { from{opacity:0;transform:translateY(10px) scale(.97)} to{opacity:1;transform:none} }
        .row-anim { animation: rowIn .22s ease both; }
        @keyframes rowIn { from{opacity:0;transform:translateX(-5px)} to{opacity:1;transform:none} }
      `}</style>

      {/* Header */}
      <div className="bg-white border-b border-amber-100 shadow-sm sticky top-0 z-30">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4 flex flex-col sm:flex-row sm:items-center gap-3">
          <div className="flex items-center gap-3 flex-1">
            <div className="w-10 h-10 bg-amber-600 rounded-xl flex items-center justify-center shadow"><Shield size={20} className="text-white" /></div>
            <div>
              <h1 className="text-[17px] font-bold text-stone-800 leading-tight">कर्मचारी प्रबंधन</h1>
              <p className="text-[11px] text-stone-400">जिले के मतदान कर्मचारियों की सूची — पद के अनुसार</p>
            </div>
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <button onClick={loadStaff} className="p-2.5 rounded-xl border border-stone-200 hover:bg-amber-50 transition" title="ताज़ा करें"><RefreshCw size={15} className="text-stone-500" /></button>
            <button onClick={() => setBulkOpen(true)} className="inline-flex items-center gap-2 px-3.5 py-2.5 rounded-xl border border-amber-300 bg-amber-50 text-amber-700 text-[12px] font-semibold hover:bg-amber-100 transition"><Upload size={13} /> थोक आयात</button>
            <button onClick={() => setAddOpen(true)} className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-amber-600 text-white text-[12px] font-semibold hover:bg-amber-700 shadow-sm transition"><Plus size={14} /> कर्मचारी जोड़ें</button>
          </div>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 space-y-5">

        {/* Stats */}
        <div className="grid grid-cols-3 gap-3 sm:gap-4">
          {[
            { label: "कुल कर्मचारी", val: stats.total,      icon: Users,     bg: "bg-stone-800",   sub: "पंजीकृत"      },
            { label: "नियुक्त",      val: stats.assigned,   icon: UserCheck, bg: "bg-emerald-600", sub: "केंद्र आवंटित" },
            { label: "अनियुक्त",    val: stats.unassigned, icon: UserX,     bg: "bg-red-500",     sub: "प्रतीक्षारत"   },
          ].map(({ label, val, icon: Icon, bg, sub }) => (
            <div key={label} className={`${bg} rounded-2xl p-4 sm:p-5 shadow-md`}>
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-[11px] font-medium text-white/70">{label}</p>
                  <p className="text-2xl sm:text-3xl font-bold text-white mt-0.5">{loading ? "—" : val}</p>
                  <p className="text-[10px] text-white/50 mt-0.5">{sub}</p>
                </div>
                <div className="w-9 h-9 rounded-xl bg-white/15 flex items-center justify-center"><Icon size={18} className="text-white" /></div>
              </div>
            </div>
          ))}
        </div>

        {/* Main table card */}
        <div className="bg-white rounded-2xl border border-stone-100 shadow-sm overflow-hidden">

          {/* Rank tab bar */}
          <div className="overflow-x-auto border-b border-stone-100">
            <div className="flex min-w-max">
              {RANKS.map((cfg) => {
                const Icon   = cfg.icon;
                const count  = loading ? "…" : countFor(cfg);
                const active = activeRank === cfg.key;
                return (
                  <button key={cfg.key} onClick={() => setActiveRank(cfg.key)}
                    className={`flex items-center gap-2 px-4 sm:px-5 py-3.5 text-[12px] font-bold whitespace-nowrap transition-all border-b-[3px] ${active ? "border-amber-600 text-amber-700 bg-amber-50/60" : "border-transparent text-stone-500 hover:text-stone-700 hover:bg-stone-50"}`}>
                    <Icon size={13} className={active ? "text-amber-600" : "text-stone-400"} />
                    {cfg.short}
                    <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-bold min-w-[20px] text-center ${active ? "bg-amber-600 text-white" : "bg-stone-100 text-stone-500"}`}>{count}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Active rank strip */}
          <div className={`px-5 py-3 ${activeRankCfg.headerBg} flex items-center gap-3`}>
            {(() => { const Icon = activeRankCfg.icon; return <Icon size={16} className="text-white/80" />; })()}
            <span className="text-[14px] font-bold text-white">{activeRankCfg.label}</span>
            <span className="ml-auto text-[12px] text-white/60">{loading ? "…" : `${countFor(activeRankCfg)} कर्मचारी`}</span>
          </div>

          {/* Table content */}
          {loading ? <Spinner /> : (
            <RankSection key={activeRank} allStaff={allStaff} rankCfg={activeRankCfg} onEdit={setEditTarget} onDelete={setDeleteTarget} />
          )}
        </div>

        {/* Legend */}
        <div className="flex items-center gap-5 text-[12px] text-stone-500 px-1 flex-wrap">
          <div className="flex items-center gap-2"><div className="w-5 h-3 rounded bg-emerald-100 border border-emerald-300" /><span>हरी पंक्ति = नियुक्त</span></div>
          <div className="flex items-center gap-2"><div className="w-5 h-3 rounded bg-white border border-stone-200" /><span>सफेद पंक्ति = अनियुक्त</span></div>
          <div className="flex items-center gap-2"><Sword size={12} className="text-blue-500" /><span>सशस्त्र = armed staff</span></div>
          <div className="flex items-center gap-2"><ShieldOff size={12} className="text-stone-400" /><span>निःशस्त्र = unarmed staff</span></div>
        </div>
      </div>

      {/* Modals */}
      <StaffModal open={addOpen}      onClose={() => setAddOpen(false)}    onSave={handleAdd} />
      <StaffModal open={!!editTarget} onClose={() => setEditTarget(null)}  onSave={handleEdit} initial={editTarget} />
      <BulkModal  open={bulkOpen}     onClose={() => setBulkOpen(false)}   onImport={handleBulk} />
      {deleteTarget && <DeleteConfirm staff={deleteTarget} onConfirm={handleDelete} onClose={() => setDeleteTarget(null)} deleting={deleting} />}
      {toast && <Toast msg={toast.msg} type={toast.type} onDone={() => setToast(null)} />}
    </div>
  );
}