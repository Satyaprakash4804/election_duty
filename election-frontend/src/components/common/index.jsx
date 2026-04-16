import { Loader2, AlertTriangle, CheckCircle, XCircle, Info, Search } from 'lucide-react';

// ── Spinner ────────────────────────────────────────────────────────────────────
export function Spinner({ size = 20, color = 'text-primary' }) {
  return (
    <Loader2 size={size} className={`${color} animate-spin`} />
  );
}

// ── Shimmer block ──────────────────────────────────────────────────────────────
export function Shimmer({ className = '' }) {
  return <div className={`shimmer rounded-lg ${className}`} />;
}

// ── Stat Card ─────────────────────────────────────────────────────────────────
export function StatCard({ label, value, icon: Icon, color, loading }) {
  if (loading) return <Shimmer className="h-24" />;
  return (
    <div className="card p-4 fade-in">
      <div className="flex items-start justify-between">
        <div>
          <p className="text-xs text-subtle font-semibold uppercase tracking-wide mb-1">{label}</p>
          <p className="text-3xl font-bold" style={{ color }}>{value ?? '—'}</p>
        </div>
        <div className="p-2.5 rounded-xl" style={{ background: `${color}18` }}>
          <Icon size={22} style={{ color }} />
        </div>
      </div>
    </div>
  );
}

// ── Badge ─────────────────────────────────────────────────────────────────────
export function Badge({ children, color = '#8B6914', bg = '#f5e6c8' }) {
  return (
    <span className="badge" style={{ background: bg, color }}>
      {children}
    </span>
  );
}

// ── Empty State ───────────────────────────────────────────────────────────────
export function Empty({ message = 'No data found', icon: Icon = Info }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-subtle gap-3">
      <Icon size={40} className="opacity-40" />
      <p className="text-sm">{message}</p>
    </div>
  );
}

// ── Error Banner ──────────────────────────────────────────────────────────────
export function ErrorBanner({ message }) {
  if (!message) return null;
  return (
    <div className="flex items-start gap-2 p-3 rounded-lg border text-sm"
      style={{ background: '#fdecea', borderColor: '#f5c6cb', color: '#C0392B' }}>
      <XCircle size={16} className="mt-0.5 shrink-0" />
      <span>{message}</span>
    </div>
  );
}

// ── Success Banner ────────────────────────────────────────────────────────────
export function SuccessBanner({ message }) {
  if (!message) return null;
  return (
    <div className="flex items-start gap-2 p-3 rounded-lg border text-sm"
      style={{ background: '#e6f4ea', borderColor: '#a8d5b1', color: '#2D6A1E' }}>
      <CheckCircle size={16} className="mt-0.5 shrink-0" />
      <span>{message}</span>
    </div>
  );
}

// ── Confirm Dialog ────────────────────────────────────────────────────────────
export function ConfirmDialog({ open, title, message, onConfirm, onCancel, danger }) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: 'rgba(0,0,0,0.5)' }}>
      <div className="card p-6 max-w-sm w-full fade-in">
        <div className="flex items-center gap-3 mb-3">
          <AlertTriangle size={22} className={danger ? 'text-error' : 'text-primary'} />
          <h3 className="font-bold text-dark text-base">{title}</h3>
        </div>
        <p className="text-sm text-subtle mb-5">{message}</p>
        <div className="flex gap-3 justify-end">
          <button className="btn-outline text-sm px-4 py-2" onClick={onCancel}>Cancel</button>
          <button
            className={danger ? 'btn-danger' : 'btn-primary'}
            onClick={onConfirm}
          >
            Confirm
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modal Wrapper ─────────────────────────────────────────────────────────────
export function Modal({ open, onClose, title, children, maxWidth = 'max-w-lg' }) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 overflow-y-auto"
      style={{ background: 'rgba(0,0,0,0.5)' }}>
      <div className={`card w-full ${maxWidth} my-4 fade-in`}>
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b"
          style={{ borderColor: 'var(--border)', background: 'var(--dark)', borderRadius: '14px 14px 0 0' }}>
          <h3 className="font-bold text-white text-sm tracking-wide">{title}</h3>
          <button onClick={onClose}
            className="text-white/60 hover:text-white transition-colors text-lg leading-none">✕</button>
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  );
}

// ── Pagination ────────────────────────────────────────────────────────────────
export function Pagination({ page, totalPages, onPage }) {
  if (totalPages <= 1) return null;
  return (
    <div className="flex items-center gap-2 justify-center pt-4">
      <button disabled={page <= 1} onClick={() => onPage(page - 1)}
        className="btn-outline px-3 py-1.5 text-xs disabled:opacity-40">‹ Prev</button>
      <span className="text-xs text-subtle">Page {page} of {totalPages}</span>
      <button disabled={page >= totalPages} onClick={() => onPage(page + 1)}
        className="btn-outline px-3 py-1.5 text-xs disabled:opacity-40">Next ›</button>
    </div>
  );
}

// ── Search Bar ────────────────────────────────────────────────────────────────
export function SearchBar({ value, onChange, placeholder = 'Search…' }) {
  return (
    <div className="relative">
      <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2"/>
      <input
        type="text" value={value} onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="field !pl-9 pr-4 py-2 text-sm h-9"
      />
    </div>
  );
}

// ── Section Header ────────────────────────────────────────────────────────────
export function SectionHeader({ title, subtitle, action }) {
  return (
    <div className="flex items-center justify-between mb-4">
      <div>
        <h2 className="font-bold text-dark text-base">{title}</h2>
        {subtitle && <p className="text-xs text-subtle mt-0.5">{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}

// ── Sensitivity Chip ──────────────────────────────────────────────────────────
import { SENSITIVITY_CONFIG } from '../../utils/helpers';
export function SensChip({ sens }) {
  const cfg = SENSITIVITY_CONFIG[sens] || { color: '#666', bg: '#eee' };
  return (
    <span className="badge font-bold text-xs px-2 py-0.5 rounded-full"
      style={{ background: cfg.bg, color: cfg.color }}>
      {sens}
    </span>
  );
}
