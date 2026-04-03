import { motion, AnimatePresence } from 'framer-motion'
import { X, Loader2, AlertTriangle } from 'lucide-react'

// ── Stat Card ────────────────────────────────────────
export function StatCard({ icon: Icon, label, value, color = 'text-primary' }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      className="card p-5 flex items-center gap-4"
    >
      <div className={`p-3 rounded-xl bg-bg ${color}`}>
        <Icon size={24} />
      </div>
      <div>
        <p className="text-subtle text-sm font-medium">{label}</p>
        <p className="text-dark text-2xl font-bold">{value ?? '—'}</p>
      </div>
    </motion.div>
  )
}

// ── Page Header ──────────────────────────────────────
export function PageHeader({ title, subtitle, action }) {
  return (
    <div className="flex items-start justify-between mb-6">
      <div>
        <h1 className="text-2xl font-extrabold text-dark">{title}</h1>
        {subtitle && <p className="text-subtle text-sm mt-0.5">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}

// ── Loading Spinner ──────────────────────────────────
export function Spinner({ size = 24 }) {
  return (
    <div className="flex justify-center items-center py-12">
      <Loader2 size={size} className="animate-spin text-primary" />
    </div>
  )
}

// ── Empty State ──────────────────────────────────────
export function EmptyState({ message = 'No data found', icon: Icon = AlertTriangle }) {
  return (
    <div className="text-center py-16 text-subtle">
      <Icon size={40} className="mx-auto mb-3 opacity-40" />
      <p className="font-medium">{message}</p>
    </div>
  )
}

// ── Modal ────────────────────────────────────────────
export function Modal({ open, onClose, title, children }) {
  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-dark/40 z-40 backdrop-blur-sm"
            onClick={onClose}
          />
          <motion.div
            initial={{ opacity: 0, scale: 0.95, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 20 }}
            className="fixed inset-0 z-50 flex items-center justify-center p-4"
          >
            <div className="bg-bg border border-border rounded-2xl shadow-2xl w-full max-w-md">
              <div className="flex items-center justify-between px-6 py-4 border-b border-border">
                <h2 className="font-bold text-dark text-lg">{title}</h2>
                <button onClick={onClose} className="text-subtle hover:text-dark transition-colors">
                  <X size={20} />
                </button>
              </div>
              <div className="p-6">{children}</div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}

// ── Confirm Dialog ───────────────────────────────────
export function ConfirmDialog({ open, onClose, onConfirm, message = 'Are you sure?' }) {
  return (
    <Modal open={open} onClose={onClose} title="Confirm Action">
      <p className="text-dark mb-6">{message}</p>
      <div className="flex gap-3 justify-end">
        <button onClick={onClose} className="btn-ghost">Cancel</button>
        <button onClick={onConfirm} className="btn-danger">Confirm</button>
      </div>
    </Modal>
  )
}

// ── Badge ────────────────────────────────────────────
export function Badge({ label, variant = 'default' }) {
  const styles = {
    default: 'bg-surface text-primary border border-border',
    success: 'bg-green-100 text-green-800',
    danger:  'bg-red-100 text-red-700',
    info:    'bg-blue-100 text-blue-800',
  }
  return (
    <span className={`badge ${styles[variant]}`}>{label}</span>
  )
}

// ── Table ────────────────────────────────────────────
export function Table({ headers, rows, empty = 'No records' }) {
  if (!rows?.length) return <EmptyState message={empty} />
  return (
    <div className="overflow-x-auto rounded-xl border border-border">
      <table className="w-full text-sm">
        <thead className="bg-dark text-white">
          <tr>
            {headers.map((h) => (
              <th key={h} className="px-4 py-3 text-left font-semibold whitespace-nowrap">{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <motion.tr
              key={i}
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: i * 0.03 }}
              className={`border-t border-border ${i % 2 === 0 ? 'bg-bg' : 'bg-surface'} hover:bg-border/20 transition-colors`}
            >
              {row}
            </motion.tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

// ── Search Input ─────────────────────────────────────
export function SearchInput({ value, onChange, placeholder = 'Search...' }) {
  return (
    <input
      className="input max-w-sm"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
    />
  )
}
