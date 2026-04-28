import { useState, useEffect, useCallback, useRef } from "react";
import {
  ArrowLeft, Plus, Search, Table2, Trash2, ChevronLeft,
  ChevronRight, X, Check, Download, RefreshCw,
  PlusCircle, FileSpreadsheet, AlertTriangle, Loader2,
  Eye, Hash, Type, Calendar, ToggleLeft, Edit2,
  Database, MoreHorizontal, Settings, Columns,
  ChevronDown, GripVertical,
} from "lucide-react";
import { useNavigate } from "react-router-dom";
import apiClient from "../api/client";

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────
const api = {
  getTables:     (p, l, q) => apiClient.get(`/dynamic?page=${p}&limit=${l}&search=${encodeURIComponent(q)}`),
  getTable:      (name, p, l, q) => apiClient.get(`/dynamic/${name}?page=${p}&limit=${l}&search=${encodeURIComponent(q)}`),
  createTable:   (body) => apiClient.post("/dynamic", body),
  deleteTable:   (id) => apiClient.delete(`/dynamic/${id}`),
  addRow:        (tableId, data) => apiClient.post(`/dynamic/${tableId}/rows`, { data }),
  updateRow:     (rowId, data) => apiClient.put(`/dynamic/rows/${rowId}`, { data }),
  deleteRow:     (rowId) => apiClient.delete(`/dynamic/rows/${rowId}`),
  addColumn:     (tableId, col) => apiClient.post(`/dynamic/${tableId}/columns`, col),
  renameColumn:  (tableId, key, patch) => apiClient.patch(`/dynamic/${tableId}/columns/${key}`, patch),
  deleteColumn:  (tableId, key) => apiClient.delete(`/dynamic/${tableId}/columns/${key}`),
};

// ─────────────────────────────────────────────────────────────────────────────
// Toast
// ─────────────────────────────────────────────────────────────────────────────
function useToast() {
  const [toasts, setToasts] = useState([]);
  const show = useCallback((msg, type = "success") => {
    const id = Date.now();
    setToasts(p => [...p, { id, msg, type }]);
    setTimeout(() => setToasts(p => p.filter(t => t.id !== id)), 3000);
  }, []);
  return { toasts, show };
}

function ToastStack({ toasts }) {
  return (
    <div className="fixed bottom-5 right-5 z-[9999] flex flex-col gap-2 pointer-events-none">
      {toasts.map(t => (
        <div key={t.id} className={`
          flex items-center gap-2.5 px-4 py-3 rounded-xl shadow-2xl text-sm font-semibold
          pointer-events-auto border
          ${t.type === "error"
            ? "bg-red-600 text-white border-red-500"
            : "bg-emerald-600 text-white border-emerald-500"}
        `}
          style={{ animation: "slideUp 0.25s ease-out" }}>
          {t.type === "error" ? <AlertTriangle size={14} /> : <Check size={14} />}
          {t.msg}
        </div>
      ))}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPE config
// ─────────────────────────────────────────────────────────────────────────────
const TYPES = {
  text:    { icon: <Type    size={11} />, label: "Text",    color: "#8B6914" },
  number:  { icon: <Hash    size={11} />, label: "Number",  color: "#1565C0" },
  date:    { icon: <Calendar size={11}/>, label: "Date",    color: "#2D6A1E" },
  boolean: { icon: <ToggleLeft size={11}/>, label: "Boolean", color: "#6A1E6A" },
};

function TypeBadge({ type }) {
  const t = TYPES[type] || TYPES.text;
  return (
    <span className="inline-flex items-center gap-1 text-[10px] font-bold px-1.5 py-0.5 rounded"
      style={{ background: t.color + "18", color: t.color }}>
      {t.icon} {t.label}
    </span>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Confirm Dialog
// ─────────────────────────────────────────────────────────────────────────────
function ConfirmDialog({ title, message, onConfirm, onCancel, danger = true }) {
  return (
    <div className="fixed inset-0 z-[900] bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm overflow-hidden"
        style={{ border: danger ? "1.5px solid #fca5a5" : "1.5px solid var(--border)" }}>
        <div className="p-5">
          <div className="flex items-start gap-3 mb-4">
            <div className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${danger ? "bg-red-50" : "bg-amber-50"}`}>
              <AlertTriangle size={18} className={danger ? "text-red-500" : "text-amber-500"} />
            </div>
            <div>
              <p className="font-bold text-slate-800 text-sm">{title}</p>
              <p className="text-slate-500 text-xs mt-0.5 leading-relaxed">{message}</p>
            </div>
          </div>
          <div className="flex gap-2">
            <button onClick={onCancel}
              className="flex-1 py-2 rounded-xl border text-slate-600 text-sm font-semibold hover:bg-slate-50 transition-colors"
              style={{ borderColor: "var(--border)" }}>
              Cancel
            </button>
            <button onClick={onConfirm}
              className={`flex-1 py-2 rounded-xl text-white text-sm font-bold transition-colors ${danger ? "bg-red-600 hover:bg-red-700" : "bg-amber-500 hover:bg-amber-600"}`}>
              Confirm
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Column Modal (add / edit)
// ─────────────────────────────────────────────────────────────────────────────
function ColumnModal({ existing, onSave, onClose }) {
  const isEdit = !!existing;
  const [label, setLabel] = useState(existing?.label || "");
  const [key,   setKey]   = useState(existing?.key   || "");
  const [type,  setType]  = useState(existing?.type  || "text");
  const [saving, setSaving] = useState(false);

  const autoKey = (l) => l.toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_]/g, "");

  const handleSave = async () => {
    if (!label.trim() || !key.trim()) return;
    setSaving(true);
    try {
      await onSave({ key: key.trim(), label: label.trim(), type });
      onClose();
    } catch (e) {
      // parent handles toast
    } finally { setSaving(false); }
  };

  return (
    <div className="fixed inset-0 z-[800] bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm overflow-hidden"
        style={{ border: "1.5px solid var(--border)" }}>
        {/* Header */}
        <div className="flex items-center gap-3 px-5 py-4"
          style={{ borderBottom: "1px solid var(--border)", background: "var(--surface)" }}>
          <div className="w-8 h-8 rounded-lg flex items-center justify-center"
            style={{ background: "rgba(212,168,67,0.2)" }}>
            <Columns size={14} style={{ color: "var(--primary)" }} />
          </div>
          <h3 className="font-bold text-sm flex-1" style={{ color: "var(--dark)" }}>
            {isEdit ? "Edit Column" : "Add Column"}
          </h3>
          <button onClick={onClose} className="p-1 rounded-lg hover:bg-white/50">
            <X size={15} style={{ color: "var(--subtle)" }} />
          </button>
        </div>

        <div className="p-5 space-y-3">
          <div>
            <label className="text-xs font-bold text-slate-500 uppercase tracking-wide block mb-1.5">Column Label *</label>
            <input
              className="field w-full"
              value={label}
              placeholder="e.g. Employee Name"
              onChange={e => {
                setLabel(e.target.value);
                if (!isEdit) setKey(autoKey(e.target.value));
              }}
            />
          </div>
          <div>
            <label className="text-xs font-bold text-slate-500 uppercase tracking-wide block mb-1.5">Column Key *</label>
            <input
              className="field w-full font-mono text-sm"
              value={key}
              placeholder="employee_name"
              onChange={e => setKey(e.target.value)}
              readOnly={isEdit}
              style={isEdit ? { background: "var(--surface)", color: "var(--subtle)" } : {}}
            />
            {isEdit && <p className="text-xs text-slate-400 mt-1">Key cannot be changed after creation</p>}
          </div>
          <div>
            <label className="text-xs font-bold text-slate-500 uppercase tracking-wide block mb-1.5">Data Type</label>
            <div className="grid grid-cols-2 gap-2">
              {Object.entries(TYPES).map(([val, t]) => (
                <button key={val} onClick={() => setType(val)}
                  className="flex items-center gap-2 px-3 py-2 rounded-xl border text-sm font-semibold transition-all"
                  style={type === val
                    ? { background: t.color + "18", borderColor: t.color, color: t.color }
                    : { borderColor: "var(--border)", color: "var(--subtle)" }}>
                  {t.icon} {t.label}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="flex gap-2 px-5 pb-5">
          <button onClick={onClose} className="flex-1 py-2 rounded-xl border text-sm font-semibold"
            style={{ borderColor: "var(--border)", color: "var(--subtle)" }}>
            Cancel
          </button>
          <button onClick={handleSave} disabled={!label || !key || saving}
            className="flex-1 py-2 rounded-xl text-white text-sm font-bold flex items-center justify-center gap-2 transition-colors disabled:opacity-50"
            style={{ background: "var(--primary)" }}>
            {saving ? <Loader2 size={13} className="animate-spin" /> : <Check size={13} />}
            {isEdit ? "Save" : "Add Column"}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Table Modal
// ─────────────────────────────────────────────────────────────────────────────
function CreateTableModal({ onClose, onCreated, show }) {
  const [name, setName] = useState("");
  const [columns, setColumns] = useState([
    { key: "name", label: "Name", type: "text" }
  ]);
  const [saving, setSaving] = useState(false);

  const autoKey = (l) => l.toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_]/g, "");

  const addCol = () => setColumns(p => [...p, { key: "", label: "", type: "text" }]);
  const removeCol = (i) => columns.length > 1 && setColumns(p => p.filter((_, j) => j !== i));
  const updateCol = (i, f, v) => setColumns(p => p.map((c, j) => j === i ? { ...c, [f]: v } : c));

  const submit = async () => {
    if (!name.trim()) { show("Table name required", "error"); return; }
    const valid = columns.filter(c => c.key.trim() && c.label.trim());
    if (valid.length === 0) { show("Add at least one column", "error"); return; }
    setSaving(true);
    try {
      await api.createTable({ table_name: name.trim(), columns: valid });
      show("Table created!");
      onCreated();
      onClose();
    } catch (e) {
      show(e.message || "Failed to create", "error");
    } finally { setSaving(false); }
  };

  return (
    <div className="fixed inset-0 z-[800] bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-lg flex flex-col max-h-[90vh]"
        style={{ border: "1.5px solid var(--border)" }}>
        {/* Header */}
        <div className="flex items-center gap-3 px-5 py-4 flex-shrink-0"
          style={{ borderBottom: "1px solid var(--border)", background: "var(--surface)" }}>
          <div className="w-9 h-9 rounded-xl flex items-center justify-center"
            style={{ background: "rgba(212,168,67,0.2)" }}>
            <Table2 size={16} style={{ color: "var(--primary)" }} />
          </div>
          <div className="flex-1">
            <h3 className="font-bold text-sm" style={{ color: "var(--dark)" }}>Create New Table</h3>
            <p className="text-xs" style={{ color: "var(--subtle)" }}>Name your table and define its columns</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-white/60">
            <X size={16} style={{ color: "var(--subtle)" }} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-5 space-y-5">
          {/* Table name */}
          <div>
            <label className="text-xs font-bold text-slate-500 uppercase tracking-wide block mb-1.5">Table Name *</label>
            <input
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="e.g. Employee Register"
              className="field w-full"
              onKeyDown={e => e.key === "Enter" && submit()}
            />
          </div>

          {/* Columns */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <label className="text-xs font-bold text-slate-500 uppercase tracking-wide">Columns</label>
              <button onClick={addCol}
                className="flex items-center gap-1 text-xs font-bold transition-colors px-2 py-1 rounded-lg"
                style={{ color: "var(--primary)", background: "rgba(212,168,67,0.1)" }}>
                <Plus size={11} /> Add
              </button>
            </div>
            <div className="space-y-2">
              {/* Column headers */}
              <div className="grid gap-2 px-1" style={{ gridTemplateColumns: "1fr 110px 100px 28px" }}>
                <span className="text-[10px] font-bold text-slate-400 uppercase">Label</span>
                <span className="text-[10px] font-bold text-slate-400 uppercase">Key</span>
                <span className="text-[10px] font-bold text-slate-400 uppercase">Type</span>
                <span />
              </div>
              {columns.map((col, i) => (
                <div key={i} className="grid gap-2 items-center"
                  style={{ gridTemplateColumns: "1fr 110px 100px 28px" }}>
                  <input
                    placeholder="Column label"
                    value={col.label}
                    onChange={e => {
                      updateCol(i, "label", e.target.value);
                      if (!col.key || col.key === autoKey(col.label)) {
                        updateCol(i, "key", autoKey(e.target.value));
                      }
                    }}
                    className="field text-sm"
                    style={{ padding: "7px 10px" }}
                  />
                  <input
                    placeholder="key"
                    value={col.key}
                    onChange={e => updateCol(i, "key", e.target.value)}
                    className="field font-mono text-xs"
                    style={{ padding: "7px 8px", color: "var(--subtle)" }}
                  />
                  <select
                    value={col.type}
                    onChange={e => updateCol(i, "type", e.target.value)}
                    className="field text-xs"
                    style={{ padding: "7px 6px" }}
                  >
                    {Object.entries(TYPES).map(([v, t]) => (
                      <option key={v} value={v}>{t.label}</option>
                    ))}
                  </select>
                  <button onClick={() => removeCol(i)} disabled={columns.length === 1}
                    className="flex items-center justify-center w-7 h-7 rounded-lg transition-colors disabled:opacity-20"
                    style={{ color: "var(--subtle)" }}
                    onMouseEnter={e => { if (columns.length > 1) e.currentTarget.style.color = "#e74c3c"; }}
                    onMouseLeave={e => e.currentTarget.style.color = "var(--subtle)"}>
                    <X size={13} />
                  </button>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="flex gap-2 p-5 flex-shrink-0" style={{ borderTop: "1px solid var(--border)" }}>
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl border text-sm font-semibold"
            style={{ borderColor: "var(--border)", color: "var(--subtle)" }}>
            Cancel
          </button>
          <button onClick={submit} disabled={saving}
            className="flex-1 py-2.5 rounded-xl text-white text-sm font-bold flex items-center justify-center gap-2"
            style={{ background: "var(--primary)" }}>
            {saving ? <Loader2 size={14} className="animate-spin" /> : <Database size={14} />}
            Create Table
          </button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline Cell Editor
// FIX: Only call .select() on input elements, not on <select> elements
// ─────────────────────────────────────────────────────────────────────────────
function CellEditor({ value, type, onSave, onCancel }) {
  const [val, setVal] = useState(value ?? "");
  const ref = useRef(null);

  useEffect(() => {
    ref.current?.focus();
    // .select() is only available on input/textarea, not on <select> elements
    if (ref.current && typeof ref.current.select === "function") {
      ref.current.select();
    }
  }, []);

  const commit = () => onSave(val);
  const onKey = (e) => {
    if (e.key === "Enter") commit();
    if (e.key === "Escape") onCancel();
  };

  if (type === "boolean") {
    return (
      <select
        ref={ref}
        value={val}
        onChange={e => setVal(e.target.value)}
        onBlur={commit}
        onKeyDown={onKey}
        className="w-full h-full border-0 outline-none bg-amber-50 text-xs font-semibold px-2"
        style={{ color: "var(--dark)" }}
      >
        <option value="">—</option>
        <option value="true">True</option>
        <option value="false">False</option>
      </select>
    );
  }

  return (
    <input
      ref={ref}
      type={type === "number" ? "number" : type === "date" ? "date" : "text"}
      value={val}
      onChange={e => setVal(e.target.value)}
      onBlur={commit}
      onKeyDown={onKey}
      className="w-full h-full border-0 outline-none bg-amber-50 text-xs px-2"
      style={{ color: "var(--dark)" }}
    />
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Column Header Menu
// ─────────────────────────────────────────────────────────────────────────────
function ColHeaderMenu({ col, onEdit, onDelete, onClose }) {
  const ref = useRef(null);
  useEffect(() => {
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) onClose(); };
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, []);

  return (
    <div ref={ref}
      className="absolute top-full left-0 mt-1 z-50 bg-white rounded-xl shadow-2xl overflow-hidden py-1"
      style={{ minWidth: 140, border: "1.5px solid var(--border)" }}>
      <button onClick={onEdit}
        className="w-full flex items-center gap-2 px-3 py-2 text-xs font-semibold hover:bg-amber-50 transition-colors text-left"
        style={{ color: "var(--dark)" }}>
        <Edit2 size={11} style={{ color: "var(--primary)" }} /> Rename
      </button>
      <div style={{ height: 1, background: "var(--border)", margin: "2px 0" }} />
      <button onClick={onDelete}
        className="w-full flex items-center gap-2 px-3 py-2 text-xs font-semibold hover:bg-red-50 transition-colors text-left text-red-600">
        <Trash2 size={11} /> Delete Column
      </button>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SPREADSHEET VIEW
// ─────────────────────────────────────────────────────────────────────────────
function SpreadsheetView({ tableId, tableName, onBack, show }) {
  const [tableData, setTableData]   = useState(null);
  const [rows,      setRows]        = useState([]);
  const [total,     setTotal]       = useState(0);
  const [page,      setPage]        = useState(1);
  const [search,    setSearch]      = useState("");
  const [dSearch,   setDSearch]     = useState("");
  const [loading,   setLoading]     = useState(true);

  // Zoom state (Excel-like: 50% – 200%, default 100%)
  const [zoom, setZoom] = useState(100);
  const ZOOM_MIN = 50;
  const ZOOM_MAX = 200;
  const ZOOM_STEP = 10;
  const sheetRef = useRef(null);

  // Editing state
  const [editingCell,  setEditingCell]  = useState(null);
  const [editingRow,   setEditingRow]   = useState(null);
  const [newRowData,   setNewRowData]   = useState({});
  const [savingCell,   setSavingCell]   = useState(null);
  const [addingRow,    setAddingRow]    = useState(false);

  // Column management
  const [colModal,  setColModal]  = useState(null);
  const [colMenu,   setColMenu]   = useState(null);
  const [confirm,   setConfirm]   = useState(null);

  const LIMIT = 50;

  // ── Ctrl+Scroll zoom (Excel-style) ──
  useEffect(() => {
    const el = sheetRef.current;
    if (!el) return;
    const handleWheel = (e) => {
      if (!e.ctrlKey && !e.metaKey) return;
      e.preventDefault();
      setZoom(prev => {
        const delta = e.deltaY < 0 ? ZOOM_STEP : -ZOOM_STEP;
        return Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, prev + delta));
      });
    };
    el.addEventListener("wheel", handleWheel, { passive: false });
    return () => el.removeEventListener("wheel", handleWheel);
  }, []);

  const load = useCallback(async (pg = page, q = dSearch) => {
    setLoading(true);
    try {
      const res = await api.getTable(tableName, pg, LIMIT, q);
      const d = res.data ?? res;
      setTableData(d.table);
      setRows(d.rows ?? []);
      setTotal(d.total ?? 0);
    } catch (e) {
      show(e.message, "error");
    } finally { setLoading(false); }
  }, [tableName, page, dSearch]);

  useEffect(() => { load(); }, [page, dSearch]);
  useEffect(() => {
    const t = setTimeout(() => { setDSearch(search); setPage(1); }, 350);
    return () => clearTimeout(t);
  }, [search]);

  const columns = tableData?.columns ?? [];

  // ── Cell save ──
  const saveCell = async (rowId, colKey, value) => {
    setSavingCell(`${rowId}-${colKey}`);
    const row = rows.find(r => r._id === rowId);
    const newData = { ...(row?.data ?? {}), [colKey]: value };
    try {
      await api.updateRow(rowId, newData);
      setRows(p => p.map(r => r._id === rowId ? { ...r, data: newData } : r));
    } catch (e) { show(e.message, "error"); }
    finally { setSavingCell(null); setEditingCell(null); }
  };

  // ── New row ──
  const commitNewRow = async () => {
    if (Object.values(newRowData).every(v => !v)) return;
    setAddingRow(true);
    try {
      await api.addRow(tableData._id, newRowData);
      show("Row added!");
      setNewRowData({});
      setEditingRow(null);
      load(1, dSearch);
      setPage(1);
    } catch (e) { show(e.message, "error"); }
    finally { setAddingRow(false); }
  };

  // ── Delete row ──
  const deleteRow = async (rowId) => {
    try {
      await api.deleteRow(rowId);
      show("Row deleted");
      load();
    } catch (e) { show(e.message, "error"); }
  };

  // ── Add column ──
  const addColumn = async (col) => {
    try {
      await api.addColumn(tableData._id, col);
      show("Column added!");
      load();
    } catch (e) { show(e.message || "Failed", "error"); throw e; }
  };

  // ── Rename column ──
  const renameColumn = async (col) => {
    try {
      await api.renameColumn(tableData._id, col.key, { label: col.label });
      show("Column updated!");
      load();
    } catch (e) { show(e.message || "Failed", "error"); throw e; }
  };

  // ── Delete column ──
  const deleteColumn = async (key) => {
    try {
      await api.deleteColumn(tableData._id, key);
      show("Column deleted");
      load();
    } catch (e) { show(e.message, "error"); }
  };

  // ── CSV export ──
  const exportCSV = () => {
    if (!rows.length) return;
    const header = columns.map(c => `"${c.label}"`).join(",");
    const body = rows.map(r =>
      columns.map(c => `"${r.data?.[c.key] ?? ""}"`).join(",")
    ).join("\n");
    const blob = new Blob([header + "\n" + body], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a"); a.href = url;
    a.download = `${tableName}.csv`; a.click();
    URL.revokeObjectURL(url);
    show("CSV exported!");
  };

  const totalPages = Math.ceil(total / LIMIT);

  const renderCellValue = (col, val) => {
    if (val === undefined || val === null || val === "") return <span style={{ color: "var(--border)" }}>—</span>;
    if (col.type === "boolean") {
      return val === "true" || val === true
        ? <span className="inline-flex items-center gap-1 text-[10px] font-bold px-1.5 py-0.5 rounded"
            style={{ background: "#2D6A1E18", color: "#2D6A1E" }}>✓ True</span>
        : <span className="inline-flex items-center gap-1 text-[10px] font-bold px-1.5 py-0.5 rounded"
            style={{ background: "var(--surface)", color: "var(--subtle)" }}>✗ False</span>;
    }
    return <span className="truncate">{String(val)}</span>;
  };

  return (
    <div className="flex flex-col h-screen" style={{ background: "var(--bg)" }}>

      {/* Modals */}
      {colModal && (
        <ColumnModal
          existing={colModal === "add" ? null : colModal}
          onSave={colModal === "add" ? addColumn : renameColumn}
          onClose={() => setColModal(null)}
        />
      )}
      {confirm?.type === "row" && (
        <ConfirmDialog
          title="Delete Row"
          message="This row will be permanently deleted."
          onConfirm={() => { deleteRow(confirm.id); setConfirm(null); }}
          onCancel={() => setConfirm(null)}
        />
      )}
      {confirm?.type === "col" && (
        <ConfirmDialog
          title={`Delete column "${confirm.label}"?`}
          message="This column and all its data will be removed from every row. This cannot be undone."
          onConfirm={() => { deleteColumn(confirm.key); setConfirm(null); }}
          onCancel={() => setConfirm(null)}
        />
      )}

      {/* ── Toolbar ── */}
      <div className="flex-shrink-0 border-b px-4 h-12 flex items-center gap-3"
        style={{ background: "var(--bg)", borderColor: "var(--border)" }}>
        <button onClick={onBack}
          className="flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg transition-colors"
          style={{ color: "var(--subtle)" }}
          onMouseEnter={e => e.currentTarget.style.background = "var(--surface)"}
          onMouseLeave={e => e.currentTarget.style.background = "transparent"}>
          <ArrowLeft size={13} /> Tables
        </button>

        <div className="w-px h-5" style={{ background: "var(--border)" }} />

        {/* Table name */}
        <div className="flex items-center gap-2">
          <div className="w-6 h-6 rounded flex items-center justify-center"
            style={{ background: "rgba(212,168,67,0.2)" }}>
            <FileSpreadsheet size={11} style={{ color: "var(--primary)" }} />
          </div>
          <span className="font-bold text-sm" style={{ color: "var(--dark)" }}>{tableName}</span>
          <span className="text-xs px-2 py-0.5 rounded-full font-medium"
            style={{ background: "var(--surface)", color: "var(--subtle)" }}>
            {total} rows
          </span>
          <span className="text-xs px-2 py-0.5 rounded-full font-medium"
            style={{ background: "var(--surface)", color: "var(--subtle)" }}>
            {columns.length} cols
          </span>
        </div>

        <div className="flex-1" />

        {/* Search */}
        <div className="relative hidden sm:flex items-center">
          <Search size={12} className="absolute left-2.5" style={{ color: "var(--subtle)" }} />
          <input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search…"
            className="field !pl-7 pr-3 py-1.5 text-xs w-44"
          />
          {search && <button onClick={() => setSearch("")} className="absolute right-2.5">
            <X size={11} style={{ color: "var(--subtle)" }} />
          </button>}
        </div>

        {/* Actions */}
        <button onClick={exportCSV}
          className="hidden sm:flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg border transition-colors"
          style={{ borderColor: "var(--border)", color: "var(--subtle)" }}
          onMouseEnter={e => e.currentTarget.style.background = "var(--surface)"}
          onMouseLeave={e => e.currentTarget.style.background = "transparent"}>
          <Download size={12} /> Export
        </button>

        <button onClick={() => setColModal("add")}
          className="flex items-center gap-1.5 text-xs font-bold px-3 py-1.5 rounded-lg border transition-colors"
          style={{ borderColor: "var(--primary)", color: "var(--primary)", background: "rgba(212,168,67,0.08)" }}
          onMouseEnter={e => e.currentTarget.style.background = "rgba(212,168,67,0.18)"}
          onMouseLeave={e => e.currentTarget.style.background = "rgba(212,168,67,0.08)"}>
          <Columns size={12} /> Column
        </button>

        <button
          onClick={() => { setEditingRow("new"); setNewRowData(Object.fromEntries(columns.map(c => [c.key, ""]))); }}
          className="flex items-center gap-1.5 text-xs font-bold px-3 py-1.5 rounded-lg text-white transition-colors"
          style={{ background: "var(--primary)" }}
          onMouseEnter={e => e.currentTarget.style.opacity = "0.88"}
          onMouseLeave={e => e.currentTarget.style.opacity = "1"}>
          <Plus size={12} /> Row
        </button>

        <button onClick={() => {
            setSearch("")
            load()}}
          className="p-2 rounded-lg transition-colors"
          style={{ color: "var(--subtle)" }}
          onMouseEnter={e => e.currentTarget.style.background = "var(--surface)"}
          onMouseLeave={e => e.currentTarget.style.background = "transparent"}>
          <RefreshCw size={13} />
        </button>
      </div>

      {/* ── Spreadsheet (zoom wrapper) ── */}
      <div ref={sheetRef} className="flex-1 overflow-auto relative">
        {loading && (
          <div className="absolute inset-0 flex items-center justify-center z-10"
            style={{ background: "var(--bg)" }}>
            <div className="flex flex-col items-center gap-3">
              <Loader2 size={28} className="animate-spin" style={{ color: "var(--accent)" }} />
              <p className="text-sm" style={{ color: "var(--subtle)" }}>Loading…</p>
            </div>
          </div>
        )}

        {!loading && columns.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full gap-4"
            style={{ color: "var(--subtle)" }}>
            <Columns size={40} style={{ color: "var(--border)" }} />
            <p className="text-sm font-medium">No columns yet</p>
            <button onClick={() => setColModal("add")}
              className="btn-primary text-sm flex items-center gap-2">
              <Plus size={14} /> Add First Column
            </button>
          </div>
        )}

        {!loading && columns.length > 0 && (
          /* zoom container — scales table content, scroll stays on outer div */
          <div
            style={{
              transformOrigin: "top left",
              transform: `scale(${zoom / 100})`,
              // Expand the layout area so the scrollbar reflects zoomed size
              width: `${(100 / zoom) * 100}%`,
              height: zoom < 100 ? `${(100 / zoom) * 100}%` : "auto",
            }}
          >
            <table className="border-collapse" style={{ width: "max-content", minWidth: "100%" }}>
              <thead className="sticky top-0 z-20">
                <tr style={{ background: "var(--surface)" }}>
                  {/* Row number col */}
                  <th className="sticky left-0 z-30 w-10 text-center text-[10px] font-bold select-none"
                    style={{
                      background: "var(--surface)",
                      borderRight: "2px solid var(--border)",
                      borderBottom: "2px solid var(--border)",
                      color: "var(--subtle)",
                      padding: "8px 6px",
                      minWidth: 40,
                    }}>
                    #
                  </th>

                  {columns.map(col => (
                    <th key={col.key}
                      className="relative group text-left select-none"
                      style={{
                        borderRight: "1px solid var(--border)",
                        borderBottom: "2px solid var(--border)",
                        padding: 0,
                        minWidth: 140,
                        maxWidth: 280,
                      }}>
                      <div className="flex items-center gap-2 px-3 py-2">
                        <span style={{ color: TYPES[col.type]?.color || "var(--subtle)", flexShrink: 0 }}>
                          {TYPES[col.type]?.icon}
                        </span>
                        <span className="text-xs font-bold truncate flex-1" style={{ color: "var(--dark)" }}>
                          {col.label}
                        </span>
                        <button
                          onClick={e => { e.stopPropagation(); setColMenu(colMenu === col.key ? null : col.key); }}
                          className="opacity-0 group-hover:opacity-100 flex-shrink-0 p-0.5 rounded transition-all"
                          style={{ color: "var(--subtle)" }}>
                          <ChevronDown size={11} />
                        </button>
                      </div>
                      {colMenu === col.key && (
                        <ColHeaderMenu
                          col={col}
                          onEdit={() => { setColModal(col); setColMenu(null); }}
                          onDelete={() => { setConfirm({ type: "col", key: col.key, label: col.label }); setColMenu(null); }}
                          onClose={() => setColMenu(null)}
                        />
                      )}
                    </th>
                  ))}

                  {/* Add column button in header */}
                  <th style={{
                    borderBottom: "2px solid var(--border)",
                    padding: "0",
                    minWidth: 44,
                  }}>
                    <button onClick={() => setColModal("add")}
                      className="w-full h-full flex items-center justify-center py-2.5 px-3 transition-colors"
                      style={{ color: "var(--border)" }}
                      onMouseEnter={e => { e.currentTarget.style.background = "rgba(212,168,67,0.1)"; e.currentTarget.style.color = "var(--primary)"; }}
                      onMouseLeave={e => { e.currentTarget.style.background = "transparent"; e.currentTarget.style.color = "var(--border)"; }}
                      title="Add column">
                      <Plus size={14} />
                    </button>
                  </th>

                  {/* Actions col header */}
                  <th style={{
                    borderBottom: "2px solid var(--border)",
                    padding: "8px 12px",
                    minWidth: 60,
                    textAlign: "center",
                    fontSize: 10,
                    fontWeight: 700,
                    color: "var(--subtle)",
                    letterSpacing: "0.05em",
                  }}>
                    ACTIONS
                  </th>
                </tr>
              </thead>

              <tbody>
                {/* New row input */}
                {editingRow === "new" && (
                  <tr style={{ background: "rgba(212,168,67,0.06)" }}>
                    <td className="sticky left-0 text-center text-[10px] font-bold"
                      style={{
                        background: "rgba(212,168,67,0.1)",
                        borderRight: "2px solid var(--border)",
                        borderBottom: "1px solid var(--border)",
                        color: "var(--primary)",
                        padding: "6px",
                      }}>
                      NEW
                    </td>
                    {columns.map(col => (
                      <td key={col.key} style={{ borderRight: "1px solid var(--border)", borderBottom: "1px solid var(--border)", padding: 0, height: 34 }}>
                        <CellEditor
                          value={newRowData[col.key] ?? ""}
                          type={col.type}
                          onSave={v => setNewRowData(p => ({ ...p, [col.key]: v }))}
                          onCancel={() => {}}
                        />
                      </td>
                    ))}
                    <td style={{ borderBottom: "1px solid var(--border)", borderRight: "1px solid var(--border)" }} />
                    <td style={{ borderBottom: "1px solid var(--border)", padding: "0 8px" }}>
                      <div className="flex items-center gap-1 justify-center">
                        <button onClick={commitNewRow} disabled={addingRow}
                          className="flex items-center gap-1 text-[10px] font-bold px-2 py-1 rounded text-white"
                          style={{ background: "var(--primary)" }}>
                          {addingRow ? <Loader2 size={10} className="animate-spin" /> : <Check size={10} />} Save
                        </button>
                        <button onClick={() => setEditingRow(null)}
                          className="p-1 rounded transition-colors"
                          style={{ color: "var(--subtle)" }}>
                          <X size={12} />
                        </button>
                      </div>
                    </td>
                  </tr>
                )}

                {rows.length === 0 && !editingRow ? (
                  <tr>
                    <td colSpan={columns.length + 3}
                      className="text-center py-16 text-sm"
                      style={{ color: "var(--subtle)", borderBottom: "1px solid var(--border)" }}>
                      <div className="flex flex-col items-center gap-2">
                        <Database size={32} style={{ color: "var(--border)" }} />
                        <p>No data yet — click <strong>+ Row</strong> to add your first entry</p>
                      </div>
                    </td>
                  </tr>
                ) : (
                  rows.map((row, i) => (
                    <tr key={row._id} className="group"
                      style={{ background: i % 2 === 0 ? "white" : "var(--bg)" }}
                      onMouseEnter={e => e.currentTarget.style.background = "rgba(212,168,67,0.04)"}
                      onMouseLeave={e => e.currentTarget.style.background = i % 2 === 0 ? "white" : "var(--bg)"}>
                      {/* Row number */}
                      <td className="sticky left-0 text-center text-[10px] font-mono select-none"
                        style={{
                          background: "var(--surface)",
                          borderRight: "2px solid var(--border)",
                          borderBottom: "1px solid rgba(212,168,67,0.2)",
                          color: "var(--subtle)",
                          padding: "0 6px",
                          width: 40,
                        }}>
                        {(page - 1) * LIMIT + i + 1}
                      </td>

                      {columns.map(col => {
                        const isEditing = editingCell?.rowId === row._id && editingCell?.colKey === col.key;
                        const isSaving  = savingCell === `${row._id}-${col.key}`;
                        return (
                          <td key={col.key}
                            onClick={() => !isEditing && setEditingCell({ rowId: row._id, colKey: col.key })}
                            style={{
                              borderRight: "1px solid rgba(212,168,67,0.2)",
                              borderBottom: "1px solid rgba(212,168,67,0.2)",
                              padding: 0,
                              height: 34,
                              cursor: "text",
                              position: "relative",
                              outline: isEditing ? "2px solid var(--primary)" : "none",
                              outlineOffset: -2,
                            }}>
                            {isEditing ? (
                              <CellEditor
                                value={row.data?.[col.key]}
                                type={col.type}
                                onSave={v => saveCell(row._id, col.key, v)}
                                onCancel={() => setEditingCell(null)}
                              />
                            ) : (
                              <div className="flex items-center px-2.5 h-full text-xs gap-1.5"
                                style={{ color: "var(--dark)", maxWidth: 280 }}>
                                {isSaving
                                  ? <Loader2 size={10} className="animate-spin" style={{ color: "var(--primary)" }} />
                                  : renderCellValue(col, row.data?.[col.key])
                                }
                              </div>
                            )}
                          </td>
                        );
                      })}

                      {/* Spacer for add-column th */}
                      <td style={{ borderBottom: "1px solid rgba(212,168,67,0.2)", borderRight: "1px solid rgba(212,168,67,0.2)" }} />

                      {/* Row actions */}
                      <td style={{ borderBottom: "1px solid rgba(212,168,67,0.2)", padding: "0 8px" }}>
                        <div className="flex items-center gap-1 justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            onClick={() => setConfirm({ type: "row", id: row._id })}
                            className="p-1.5 rounded-lg transition-colors"
                            style={{ color: "var(--subtle)" }}
                            onMouseEnter={e => { e.currentTarget.style.background = "rgba(192,57,43,0.1)"; e.currentTarget.style.color = "#e74c3c"; }}
                            onMouseLeave={e => { e.currentTarget.style.background = "transparent"; e.currentTarget.style.color = "var(--subtle)"; }}>
                            <Trash2 size={12} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* ── Pagination + status bar (includes zoom control) ── */}
      {!loading && columns.length > 0 && (
        <div className="flex-shrink-0 border-t flex items-center justify-between px-4 py-2 gap-3"
          style={{ borderColor: "var(--border)", background: "var(--surface)" }}>
          {/* Row count */}
          <p className="text-[11px] font-medium flex-shrink-0" style={{ color: "var(--subtle)" }}>
            {total === 0 ? "No rows" : `${Math.min((page - 1) * LIMIT + 1, total)}–${Math.min(page * LIMIT, total)} of ${total} rows`}
            {search && <span className="ml-2 italic">filtered by "{search}"</span>}
          </p>

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center gap-1">
              <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
                className="p-1.5 rounded-lg border transition-colors disabled:opacity-30"
                style={{ borderColor: "var(--border)", color: "var(--dark)" }}>
                <ChevronLeft size={12} />
              </button>
              {Array.from({ length: Math.min(5, totalPages) }, (_, i) => {
                const pg = Math.max(1, Math.min(page - 2 + i, totalPages));
                return (
                  <button key={pg} onClick={() => setPage(pg)}
                    className="w-7 h-7 rounded-lg text-[11px] font-bold border transition-colors"
                    style={pg === page
                      ? { background: "var(--primary)", color: "white", borderColor: "var(--primary)" }
                      : { borderColor: "var(--border)", color: "var(--dark)" }}>
                    {pg}
                  </button>
                );
              })}
              <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                className="p-1.5 rounded-lg border transition-colors disabled:opacity-30"
                style={{ borderColor: "var(--border)", color: "var(--dark)" }}>
                <ChevronRight size={12} />
              </button>
            </div>
          )}

          {/* ── Zoom control (Excel-style) ── */}
          <div className="flex items-center gap-2 flex-shrink-0 ml-auto">
            <button
              onClick={() => setZoom(z => Math.max(ZOOM_MIN, z - ZOOM_STEP))}
              disabled={zoom <= ZOOM_MIN}
              className="w-6 h-6 rounded flex items-center justify-center border font-bold text-sm transition-colors disabled:opacity-30"
              style={{ borderColor: "var(--border)", color: "var(--dark)" }}
              title="Zoom out">
              −
            </button>
            <input
              type="range"
              min={ZOOM_MIN}
              max={ZOOM_MAX}
              step={ZOOM_STEP}
              value={zoom}
              onChange={e => setZoom(Number(e.target.value))}
              style={{
                width: 80,
                accentColor: "var(--primary)",
                cursor: "pointer",
              }}
              title={`Zoom: ${zoom}%`}
            />
            <button
              onClick={() => setZoom(z => Math.min(ZOOM_MAX, z + ZOOM_STEP))}
              disabled={zoom >= ZOOM_MAX}
              className="w-6 h-6 rounded flex items-center justify-center border font-bold text-sm transition-colors disabled:opacity-30"
              style={{ borderColor: "var(--border)", color: "var(--dark)" }}
              title="Zoom in">
              +
            </button>
            <button
              onClick={() => setZoom(100)}
              className="text-[11px] font-bold px-2 py-0.5 rounded border transition-colors"
              style={{
                borderColor: zoom !== 100 ? "var(--primary)" : "var(--border)",
                color: zoom !== 100 ? "var(--primary)" : "var(--subtle)",
                minWidth: 42,
                textAlign: "center",
              }}
              title="Reset zoom">
              {zoom}%
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TABLES LIST HOME
// ─────────────────────────────────────────────────────────────────────────────
export default function DynamicTablesPage() {
  const navigate = useNavigate();
  const [tables,      setTables]      = useState([]);
  const [total,       setTotal]       = useState(0);
  const [page,        setPage]        = useState(1);
  const [search,      setSearch]      = useState("");
  const [dSearch,     setDSearch]     = useState("");
  const [loading,     setLoading]     = useState(true);
  const [createOpen,  setCreateOpen]  = useState(false);
  const [activeTable, setActiveTable] = useState(null);
  const [confirm,     setConfirm]     = useState(null);
  const { toasts, show } = useToast();
  const LIMIT = 12;

  const loadTables = useCallback(async (pg = page, q = dSearch) => {
    setLoading(true);
    try {
      const res = await api.getTables(pg, LIMIT, q);
      const d = res.data ?? res;
      setTables(d.tables ?? []);
      setTotal(d.total ?? 0);
    } catch (e) { show(e.message, "error"); }
    finally { setLoading(false); }
  }, [page, dSearch]);

  useEffect(() => { loadTables(); }, [page, dSearch]);
  useEffect(() => {
    const t = setTimeout(() => { setDSearch(search); setPage(1); }, 350);
    return () => clearTimeout(t);
  }, [search]);

  const deleteTable = async (id, name) => {
    try {
      await api.deleteTable(id);
      show(`"${name}" deleted`);
      loadTables(1, dSearch);
      setPage(1);
    } catch (e) { show(e.message || "Delete failed", "error"); }
  };

  const totalPages = Math.ceil(total / LIMIT);

  if (activeTable) {
    return (
      <>
        <ToastStack toasts={toasts} />
        <SpreadsheetView
          tableId={activeTable.id}
          tableName={activeTable.name}
          onBack={() => { setActiveTable(null); loadTables(); }}
          show={show}
        />
      </>
    );
  }

  return (
    <div className="min-h-screen" style={{ background: "var(--bg)" }}>
      <ToastStack toasts={toasts} />

      {createOpen && (
        <CreateTableModal
          onClose={() => setCreateOpen(false)}
          onCreated={() => loadTables(1, dSearch)}
          show={show}
        />
      )}
      {confirm && (
        <ConfirmDialog
          title={`Delete "${confirm.name}"?`}
          message="All rows and columns in this table will be permanently deleted. This cannot be undone."
          onConfirm={() => { deleteTable(confirm.id, confirm.name); setConfirm(null); }}
          onCancel={() => setConfirm(null)}
        />
      )}

      {/* ── Header ── */}
      <div className="border-b sticky top-0 z-40"
        style={{ background: "var(--bg)", borderColor: "var(--border)" }}>
        <div className="max-w-6xl mx-auto px-4 sm:px-6 h-14 flex items-center gap-3">
          <button onClick={() => navigate(-1)}
            className="p-2 rounded-xl transition-colors flex-shrink-0"
            style={{ color: "var(--subtle)" }}
            onMouseEnter={e => e.currentTarget.style.background = "var(--surface)"}
            onMouseLeave={e => e.currentTarget.style.background = "transparent"}>
            <ArrowLeft size={15} />
          </button>

          <div className="flex items-center gap-2.5 flex-1">
            <div className="w-8 h-8 rounded-lg flex items-center justify-center"
              style={{ background: "rgba(212,168,67,0.2)" }}>
              <Database size={14} style={{ color: "var(--primary)" }} />
            </div>
            <div>
              <h1 className="font-bold text-sm leading-tight" style={{ color: "var(--dark)" }}>Dynamic Tables</h1>
              <p className="text-[10px] hidden sm:block" style={{ color: "var(--subtle)" }}>{total} table{total !== 1 ? "s" : ""}</p>
            </div>
          </div>

          <div className="relative hidden sm:flex items-center">
            <Search size={12} className="absolute left-2.5" style={{ color: "var(--subtle)" }} />
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Search tables…"
              className="field !pl-7 pr-3 py-1.5 text-xs w-44"
            />
          </div>

          <button onClick={() => setCreateOpen(true)}
            className="btn-primary flex-shrink-0 text-xs flex items-center gap-1.5">
            <Plus size={13} />
            <span className="hidden sm:inline">New Table</span>
          </button>

          <button onClick={() => loadTables()}
            className="p-2 rounded-xl transition-colors"
            style={{ color: "var(--subtle)" }}
            onMouseEnter={e => e.currentTarget.style.background = "var(--surface)"}
            onMouseLeave={e => e.currentTarget.style.background = "transparent"}>
            <RefreshCw size={13} />
          </button>
        </div>

        {/* Mobile search */}
        <div className="sm:hidden px-4 pb-3">
          <div className="relative">
            <Search size={12} className="absolute left-3 top-1/2 -translate-y-1/2" style={{ color: "var(--subtle)" }} />
            <input value={search} onChange={e => setSearch(e.target.value)}
              placeholder="Search tables…" className="field w-full !pl-8 pr-3 py-2 text-xs" />
          </div>
        </div>
      </div>

      {/* ── Content ── */}
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-6">
        {loading ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} className="rounded-2xl overflow-hidden animate-pulse"
                style={{ background: "var(--surface)", border: "1.5px solid var(--border)", height: 140 }} />
            ))}
          </div>
        ) : tables.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-24 gap-5 text-center">
            <div className="w-20 h-20 rounded-3xl flex items-center justify-center"
              style={{ background: "rgba(212,168,67,0.12)", border: "2px dashed var(--border)" }}>
              <Table2 size={32} style={{ color: "var(--border)" }} />
            </div>
            <div>
              <p className="font-bold text-base" style={{ color: "var(--dark)" }}>
                {dSearch ? "No tables match your search" : "No tables yet"}
              </p>
              <p className="text-sm mt-1" style={{ color: "var(--subtle)" }}>
                {dSearch ? "Try a different keyword" : "Create your first table to get started"}
              </p>
            </div>
            {!dSearch && (
              <button onClick={() => setCreateOpen(true)} className="btn-primary flex items-center gap-2">
                <PlusCircle size={15} /> Create First Table
              </button>
            )}
          </div>
        ) : (
          <>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
              {tables.map((t, idx) => (
                <div
                  key={t._id}
                  className="rounded-2xl overflow-hidden cursor-pointer group transition-all"
                  style={{
                    background: "white",
                    border: "1.5px solid var(--border)",
                    boxShadow: "0 2px 12px rgba(139,105,20,0.06)",
                    animationDelay: `${idx * 40}ms`,
                    animation: "fadeIn 0.3s ease-out both",
                  }}
                  onClick={() => setActiveTable({ id: t._id, name: t.table_name })}
                  onMouseEnter={e => {
                    e.currentTarget.style.borderColor = "var(--accent)";
                    e.currentTarget.style.boxShadow = "0 6px 24px rgba(139,105,20,0.16)";
                    e.currentTarget.style.transform = "translateY(-2px)";
                  }}
                  onMouseLeave={e => {
                    e.currentTarget.style.borderColor = "var(--border)";
                    e.currentTarget.style.boxShadow = "0 2px 12px rgba(139,105,20,0.06)";
                    e.currentTarget.style.transform = "translateY(0)";
                  }}
                >
                  {/* Card top accent */}
                  <div style={{ height: 3, background: "linear-gradient(90deg, var(--primary), var(--accent))" }} />

                  <div className="p-4">
                    {/* Icon + delete */}
                    <div className="flex items-start justify-between mb-3">
                      <div className="w-10 h-10 rounded-xl flex items-center justify-center"
                        style={{ background: "rgba(212,168,67,0.12)" }}>
                        <FileSpreadsheet size={18} style={{ color: "var(--primary)" }} />
                      </div>
                      <button
                        onClick={e => { e.stopPropagation(); setConfirm({ id: t._id, name: t.table_name }); }}
                        className="p-1.5 rounded-lg opacity-0 group-hover:opacity-100 transition-all"
                        style={{ color: "var(--border)" }}
                        onMouseEnter={e => { e.stopPropagation(); e.currentTarget.style.background = "rgba(192,57,43,0.1)"; e.currentTarget.style.color = "#e74c3c"; }}
                        onMouseLeave={e => { e.currentTarget.style.background = "transparent"; e.currentTarget.style.color = "var(--border)"; }}>
                        <Trash2 size={13} />
                      </button>
                    </div>

                    {/* Name */}
                    <h3 className="font-bold text-sm truncate mb-1" style={{ color: "var(--dark)" }}>
                      {t.table_name}
                    </h3>

                    {/* Column type pills */}
                    <div className="flex flex-wrap gap-1 mb-3 min-h-[20px]">
                      {(t.columns ?? []).slice(0, 3).map(col => (
                        <TypeBadge key={col.key} type={col.type} />
                      ))}
                      {(t.columns ?? []).length > 3 && (
                        <span className="text-[10px] font-bold px-1.5 py-0.5 rounded"
                          style={{ background: "var(--surface)", color: "var(--subtle)" }}>
                          +{t.columns.length - 3}
                        </span>
                      )}
                      {(t.columns ?? []).length === 0 && (
                        <span className="text-[10px] italic" style={{ color: "var(--border)" }}>No columns</span>
                      )}
                    </div>

                    {/* Footer */}
                    <div className="flex items-center justify-between pt-3"
                      style={{ borderTop: "1px solid var(--border)" }}>
                      <span className="text-[11px] font-semibold" style={{ color: "var(--subtle)" }}>
                        {(t.columns ?? []).length} column{t.columns?.length !== 1 ? "s" : ""}
                      </span>
                      <span className="flex items-center gap-1 text-[11px] font-bold opacity-0 group-hover:opacity-100 transition-opacity"
                        style={{ color: "var(--primary)" }}>
                        <Eye size={11} /> Open
                      </span>
                    </div>
                  </div>
                </div>
              ))}

              {/* Create new card */}
              <button onClick={() => setCreateOpen(true)}
                className="rounded-2xl p-4 transition-all flex flex-col items-center justify-center gap-3 min-h-[140px] border-2 border-dashed"
                style={{ borderColor: "var(--border)", background: "transparent" }}
                onMouseEnter={e => { e.currentTarget.style.borderColor = "var(--primary)"; e.currentTarget.style.background = "rgba(212,168,67,0.05)"; }}
                onMouseLeave={e => { e.currentTarget.style.borderColor = "var(--border)"; e.currentTarget.style.background = "transparent"; }}>
                <div className="w-10 h-10 rounded-xl flex items-center justify-center"
                  style={{ background: "var(--surface)" }}>
                  <Plus size={20} style={{ color: "var(--subtle)" }} />
                </div>
                <div className="text-center">
                  <p className="text-sm font-bold" style={{ color: "var(--subtle)" }}>New Table</p>
                  <p className="text-[11px] mt-0.5" style={{ color: "var(--border)" }}>Define columns & add data</p>
                </div>
              </button>
            </div>

            {/* Pagination */}
            {totalPages > 1 && (
              <div className="flex items-center justify-between mt-6">
                <p className="text-xs" style={{ color: "var(--subtle)" }}>Page {page} of {totalPages}</p>
                <div className="flex items-center gap-1">
                  <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
                    className="p-2 rounded-xl border transition-colors disabled:opacity-40"
                    style={{ borderColor: "var(--border)", color: "var(--dark)" }}>
                    <ChevronLeft size={13} />
                  </button>
                  {Array.from({ length: Math.min(5, totalPages) }, (_, i) => {
                    const pg = Math.max(1, Math.min(page - 2 + i, totalPages));
                    return (
                      <button key={pg} onClick={() => setPage(pg)}
                        className="w-8 h-8 rounded-xl text-xs font-bold border transition-colors"
                        style={pg === page
                          ? { background: "var(--primary)", color: "white", borderColor: "var(--primary)" }
                          : { borderColor: "var(--border)", color: "var(--dark)" }}>
                        {pg}
                      </button>
                    );
                  })}
                  <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                    className="p-2 rounded-xl border transition-colors disabled:opacity-40"
                    style={{ borderColor: "var(--border)", color: "var(--dark)" }}>
                    <ChevronRight size={13} />
                  </button>
                </div>
              </div>
            )}
          </>
        )}
      </div>

      <style>{`
        @keyframes slideUp { from { opacity:0; transform:translateY(8px); } to { opacity:1; transform:translateY(0); } }
        @keyframes fadeIn  { from { opacity:0; transform:translateY(4px); } to { opacity:1; transform:translateY(0); } }
      `}</style>
    </div>
  );
}