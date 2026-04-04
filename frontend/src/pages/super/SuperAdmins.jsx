import { useEffect, useState, useCallback } from 'react'
import { Plus, Trash2, ShieldCheck, ShieldOff, Search, Pencil, KeyRound } from 'lucide-react'
import { superAPI } from '../../services/api'
import { PageHeader, Modal, Spinner, ConfirmDialog } from '../../components/ui'
import toast from 'react-hot-toast'

const PAGE_SIZE = 10

export default function SuperAdmins() {
  const [admins, setAdmins]       = useState([])
  const [total, setTotal]         = useState(0)
  const [loading, setLoading]     = useState(true)
  const [addOpen, setAddOpen]     = useState(false)
  const [editAdmin, setEditAdmin] = useState(null)   // admin object being edited
  const [resetAdmin, setResetAdmin] = useState(null) // admin object for password reset
  const [saving, setSaving]       = useState(false)
  const [confirm, setConfirm]     = useState(null)
  const [search, setSearch]       = useState('')
  const [page, setPage]           = useState(1)
  const [form, setForm]           = useState({ name: '', username: '', district: '', password: '' })
  const [editForm, setEditForm]   = useState({ name: '', username: '', district: '' })
  const [newPassword, setNewPassword] = useState('')

  const fetchAdmins = useCallback(async (q = search, p = page) => {
    setLoading(true)
    try {
      const res = await superAPI.getAdmins({ search: q, page: p, limit: PAGE_SIZE })
      setAdmins(res.admins ?? res)
      setTotal(res.total ?? res.length ?? 0)
    } catch {
      toast.error('व्यवस्थापक लोड करने में विफल')
    } finally {
      setLoading(false)
    }
  }, [search, page])

  useEffect(() => { fetchAdmins(search, page) }, [search, page])

  const handleSearch = (val) => { setSearch(val); setPage(1) }

  // ── Create ──────────────────────────────────────────────────
  const handleCreate = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await superAPI.createAdmin(form)
      toast.success('व्यवस्थापक सफलतापूर्वक बनाया गया')
      fetchAdmins(search, page)
      setAddOpen(false)
      setForm({ name: '', username: '', district: '', password: '' })
    } catch (err) {
      toast.error(err?.response?.data?.message || 'व्यवस्थापक बनाने में विफल')
    } finally {
      setSaving(false)
    }
  }

  // ── Delete ──────────────────────────────────────────────────
  const handleDelete = (admin) => {
    setConfirm({
      message: `व्यवस्थापक "${admin.name}" (${admin.district}) को हटाएं? यह क्रिया पूर्ववत नहीं की जा सकती।`,
      action: async () => {
        try {
          await superAPI.deleteAdmin(admin.id)
          toast.success('व्यवस्थापक हटाया गया')
          fetchAdmins(search, page)
        } catch { toast.error('हटाने में विफल') }
        setConfirm(null)
      },
    })
  }

  // ── Toggle active ────────────────────────────────────────────
  const handleToggle = (admin) => {
    const action = admin.isActive ? 'निष्क्रिय' : 'सक्रिय'
    setConfirm({
      message: `"${admin.name}" को ${action} करें?`,
      action: async () => {
        try {
          const res = await superAPI.toggleAdmin(admin.id)  // PATCH /super/admins/:id/toggle
          setAdmins(prev => prev.map(a => a.id === admin.id ? { ...a, isActive: res.isActive } : a))
          toast.success(`व्यवस्थापक ${action} किया गया`)
        } catch { toast.error('स्थिति बदलने में विफल') }
        setConfirm(null)
      },
    })
  }

  // ── Edit ────────────────────────────────────────────────────
  const openEdit = (admin) => {
    setEditAdmin(admin)
    setEditForm({ name: admin.name, username: admin.username, district: admin.district })
  }

  const handleEdit = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await superAPI.updateAdmin(editAdmin.id, editForm)  // PUT /super/admins/:id
      toast.success('व्यवस्थापक अपडेट किया गया')
      fetchAdmins(search, page)
      setEditAdmin(null)
    } catch (err) {
      toast.error(err?.response?.data?.message || 'अपडेट करने में विफल')
    } finally {
      setSaving(false)
    }
  }

  // ── Reset password ───────────────────────────────────────────
  const handleResetPassword = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      await superAPI.resetAdminPassword(resetAdmin.id, { password: newPassword })  // PATCH /super/admins/:id/reset-password
      toast.success('पासवर्ड रीसेट हो गया')
      setResetAdmin(null)
      setNewPassword('')
    } catch (err) {
      toast.error(err?.response?.data?.message || 'पासवर्ड रीसेट विफल')
    } finally {
      setSaving(false)
    }
  }

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const CREATE_FIELDS = [
    { key: 'name',     label: 'पूरा नाम',             type: 'text',     required: true },
    { key: 'username', label: 'उपयोगकर्ता नाम',       type: 'text',     required: true },
    { key: 'district', label: 'जिला',                  type: 'text',     required: true },
    { key: 'password', label: 'पासवर्ड (न्यूनतम 6)',  type: 'password', required: true },
  ]

  const EDIT_FIELDS = [
    { key: 'name',     label: 'पूरा नाम',       type: 'text', required: true },
    { key: 'username', label: 'उपयोगकर्ता नाम', type: 'text', required: true },
    { key: 'district', label: 'जिला',            type: 'text', required: true },
  ]

  const inputCls = "w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
  const labelCls = "block text-[12px] font-medium text-[#7a6a50] mb-1.5"
  const submitCls = "w-full bg-[#8b6914] hover:opacity-90 disabled:opacity-60 text-white text-[13px] font-medium py-2.5 rounded-lg transition-opacity mt-1"

  return (
    <div>
      <PageHeader
        title="जिला व्यवस्थापक"
        subtitle={`${total} व्यवस्थापक पंजीकृत`}
        action={
          <button
            onClick={() => setAddOpen(true)}
            className="inline-flex items-center gap-2 bg-[#8b6914] hover:opacity-90 text-white text-[13px] font-medium px-4 py-2 rounded-lg transition-opacity"
          >
            <Plus size={14} /> व्यवस्थापक बनाएं
          </button>
        }
      />

      {/* Search */}
      <div className="relative max-w-sm mb-4">
        <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#a89878]" />
        <input
          className="w-full bg-[#fdfaf5] border border-[#8b734b]/25 rounded-lg pl-9 pr-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
          placeholder="नाम, उपयोगकर्ता नाम या जिले से खोजें…"
          value={search}
          onChange={(e) => handleSearch(e.target.value)}
        />
      </div>

      {/* Table */}
      <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl overflow-hidden">
        {loading ? (
          <div className="flex justify-center py-16"><Spinner /></div>
        ) : (
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="bg-[#f0ead8]">
                {['नाम', 'उपयोगकर्ता नाम', 'जिला', 'स्थिति', 'बूथ', 'आवंटित कर्मचारी', 'क्रियाएं'].map((h) => (
                  <th key={h} className="px-4 py-2.5 text-left text-[11px] font-medium text-[#7a6a50] uppercase tracking-wide border-b border-[#8b734b]/15 whitespace-nowrap">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {admins.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-10 text-center text-[#a89878] text-[13px]">
                    {search ? 'कोई परिणाम नहीं मिला' : 'अभी तक कोई व्यवस्थापक नहीं बनाया गया'}
                  </td>
                </tr>
              ) : (
                admins.map((a) => (
                  <tr key={a.id} className="hover:bg-[#f5f0e8] transition-colors border-b border-[#8b734b]/10 last:border-0">
                    <td className="px-4 py-3 font-medium text-[#2c2416]">{a.name}</td>
                    <td className="px-4 py-3 font-mono text-[11px] text-[#a89878]">{a.username}</td>
                    <td className="px-4 py-3 text-[#2c2416]">{a.district}</td>

                    {/* Status — click to toggle */}
                    <td className="px-4 py-3">
                      <button
                        onClick={() => handleToggle(a)}
                        title={a.isActive ? 'निष्क्रिय करने के लिए क्लिक करें' : 'सक्रिय करने के लिए क्लिक करें'}
                        className="inline-flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1 rounded-full transition-opacity hover:opacity-75 cursor-pointer"
                        style={a.isActive
                          ? { background: '#e6f0e0', color: '#2d5a1e' }
                          : { background: '#f5e8e8', color: '#7a2020' }}
                      >
                        {a.isActive
                          ? <><ShieldCheck size={11} /> सक्रिय</>
                          : <><ShieldOff  size={11} /> निष्क्रिय</>}
                      </button>
                    </td>

                    <td className="px-4 py-3 text-center font-medium text-[#2c2416]">{a.totalBooths}</td>
                    <td className="px-4 py-3 text-center font-medium text-[#2c2416]">{a.assignedStaff}</td>

                    {/* Actions */}
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-1">
                        {/* Edit */}
                        <button
                          onClick={() => openEdit(a)}
                          title="संपादित करें"
                          className="w-7 h-7 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-[#f0ead8] hover:text-[#8b6914] transition-all"
                        >
                          <Pencil size={13} />
                        </button>
                        {/* Reset password */}
                        <button
                          onClick={() => { setResetAdmin(a); setNewPassword('') }}
                          title="पासवर्ड रीसेट करें"
                          className="w-7 h-7 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-[#e8f0f5] hover:text-[#1e4a7a] transition-all"
                        >
                          <KeyRound size={13} />
                        </button>
                        {/* Delete */}
                        <button
                          onClick={() => handleDelete(a)}
                          title="हटाएं"
                          className="w-7 h-7 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-[#f5e8e8] hover:text-[#7a2020] transition-all"
                        >
                          <Trash2 size={13} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between mt-4 text-[13px]">
          <p className="text-[#a89878]">
            पृष्ठ <span className="font-medium text-[#2c2416]">{page}</span> / {totalPages}
            {' '}— कुल <span className="font-medium text-[#2c2416]">{total}</span> व्यवस्थापक
          </p>
          <div className="flex gap-2">
            <button
              disabled={page === 1}
              onClick={() => setPage(p => p - 1)}
              className="px-3 py-1.5 rounded-lg border border-[#8b734b]/20 text-[#2c2416] disabled:opacity-40 hover:bg-[#f0ead8] transition-colors"
            >
              ← पिछला
            </button>
            {Array.from({ length: totalPages }, (_, i) => i + 1)
              .filter(n => n === 1 || n === totalPages || Math.abs(n - page) <= 1)
              .reduce((acc, n, idx, arr) => {
                if (idx > 0 && n - arr[idx - 1] > 1) acc.push('…')
                acc.push(n)
                return acc
              }, [])
              .map((n, i) =>
                n === '…' ? (
                  <span key={`dots-${i}`} className="px-2 py-1.5 text-[#a89878]">…</span>
                ) : (
                  <button
                    key={n}
                    onClick={() => setPage(n)}
                    className={`px-3 py-1.5 rounded-lg border transition-colors ${
                      page === n
                        ? 'bg-[#8b6914] text-white border-[#8b6914]'
                        : 'border-[#8b734b]/20 text-[#2c2416] hover:bg-[#f0ead8]'
                    }`}
                  >
                    {n}
                  </button>
                )
              )}
            <button
              disabled={page === totalPages}
              onClick={() => setPage(p => p + 1)}
              className="px-3 py-1.5 rounded-lg border border-[#8b734b]/20 text-[#2c2416] disabled:opacity-40 hover:bg-[#f0ead8] transition-colors"
            >
              अगला →
            </button>
          </div>
        </div>
      )}

      {/* ── Create modal ── */}
      <Modal open={addOpen} onClose={() => setAddOpen(false)} title="जिला व्यवस्थापक बनाएं">
        <form onSubmit={handleCreate} className="space-y-4">
          {CREATE_FIELDS.map(({ key, label, type, required }) => (
            <div key={key}>
              <label className={labelCls}>{label}{required && ' *'}</label>
              <input
                className={inputCls}
                type={type}
                value={form[key]}
                onChange={(e) => setForm(p => ({ ...p, [key]: e.target.value }))}
                required={required}
              />
            </div>
          ))}
          <button type="submit" disabled={saving} className={submitCls}>
            {saving ? 'बन रहा है…' : 'व्यवस्थापक बनाएं'}
          </button>
        </form>
      </Modal>

      {/* ── Edit modal ── */}
      <Modal open={!!editAdmin} onClose={() => setEditAdmin(null)} title="व्यवस्थापक संपादित करें">
        <form onSubmit={handleEdit} className="space-y-4">
          {EDIT_FIELDS.map(({ key, label, type, required }) => (
            <div key={key}>
              <label className={labelCls}>{label}{required && ' *'}</label>
              <input
                className={inputCls}
                type={type}
                value={editForm[key]}
                onChange={(e) => setEditForm(p => ({ ...p, [key]: e.target.value }))}
                required={required}
              />
            </div>
          ))}
          <button type="submit" disabled={saving} className={submitCls}>
            {saving ? 'सहेज रहा है…' : 'बदलाव सहेजें'}
          </button>
        </form>
      </Modal>

      {/* ── Reset password modal ── */}
      <Modal open={!!resetAdmin} onClose={() => setResetAdmin(null)} title={`पासवर्ड रीसेट — ${resetAdmin?.name}`}>
        <form onSubmit={handleResetPassword} className="space-y-4">
          <div>
            <label className={labelCls}>नया पासवर्ड (न्यूनतम 6) *</label>
            <input
              className={inputCls}
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              required
              minLength={6}
            />
          </div>
          <button type="submit" disabled={saving} className={submitCls}>
            {saving ? 'रीसेट हो रहा है…' : 'पासवर्ड रीसेट करें'}
          </button>
        </form>
      </Modal>

      <ConfirmDialog
        open={!!confirm}
        onClose={() => setConfirm(null)}
        onConfirm={confirm?.action}
        message={confirm?.message}
      />
    </div>
  )
}