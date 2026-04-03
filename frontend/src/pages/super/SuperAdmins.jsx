import { useEffect, useState } from 'react'
import { Plus, Trash2, ShieldCheck, ShieldOff } from 'lucide-react'
import { superAPI } from '../../services/api'
import { PageHeader, Modal, Spinner, ConfirmDialog } from '../../components/ui'
import toast from 'react-hot-toast'

export default function SuperAdmins() {
  const [admins, setAdmins]   = useState([])
  const [loading, setLoading] = useState(true)
  const [addOpen, setAddOpen] = useState(false)
  const [saving, setSaving]   = useState(false)
  const [confirm, setConfirm] = useState(null)
  const [form, setForm]       = useState({ name: '', username: '', district: '', password: '' })

  useEffect(() => {
    superAPI.getAdmins()
      .then(setAdmins)
      .catch(() => toast.error('Failed to load admins'))
      .finally(() => setLoading(false))
  }, [])

  const handleCreate = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const res = await superAPI.createAdmin(form)
      toast.success('Admin created successfully')
      setAdmins(p => [{ ...res.data, isActive: true, totalBooths: 0, assignedStaff: 0 }, ...p])
      setAddOpen(false)
      setForm({ name: '', username: '', district: '', password: '' })
    } catch (err) {
      toast.error(err?.response?.data?.message || 'Failed to create admin')
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = (admin) => {
    setConfirm({
      message: `Delete admin "${admin.name}" (${admin.district})? This cannot be undone.`,
      action: async () => {
        try {
          await superAPI.deleteAdmin(admin.id)
          setAdmins(p => p.filter(a => a.id !== admin.id))
          toast.success('Admin deleted')
        } catch { toast.error('Delete failed') }
        setConfirm(null)
      },
    })
  }

  if (loading) return <Spinner />

  return (
    <div>
      <PageHeader
        title="District Admins"
        subtitle={`${admins.length} admins registered`}
        action={
          <button
            onClick={() => setAddOpen(true)}
            className="inline-flex items-center gap-2 bg-[#8b6914] hover:opacity-90 text-white text-[13px] font-medium px-4 py-2 rounded-lg transition-opacity"
          >
            <Plus size={14} /> Create Admin
          </button>
        }
      />

      {/* Table */}
      <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl overflow-hidden">
        <table className="w-full border-collapse text-[13px]">
          <thead>
            <tr className="bg-[#f0ead8]">
              {['Name', 'Username', 'District', 'Status', 'Booths', 'Assigned Staff', ''].map((h) => (
                <th
                  key={h}
                  className="px-4 py-2.5 text-left text-[11px] font-medium text-[#7a6a50] uppercase tracking-wide border-b border-[#8b734b]/15 whitespace-nowrap"
                >
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {admins.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-10 text-center text-[#a89878] text-[13px]">
                  No admins created yet
                </td>
              </tr>
            ) : (
              admins.map((a) => (
                <tr key={a.id} className="hover:bg-[#f5f0e8] transition-colors border-b border-[#8b734b]/10 last:border-0">
                  <td className="px-4 py-3 font-medium text-[#2c2416]">{a.name}</td>
                  <td className="px-4 py-3 font-mono text-[11px] text-[#a89878]">{a.username}</td>
                  <td className="px-4 py-3 text-[#2c2416]">{a.district}</td>
                  <td className="px-4 py-3">
                    {a.isActive ? (
                      <span className="inline-flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1 rounded-full bg-[#e6f0e0] text-[#2d5a1e]">
                        <ShieldCheck size={11} /> Active
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1 rounded-full bg-[#f5e8e8] text-[#7a2020]">
                        <ShieldOff size={11} /> Inactive
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-center font-medium text-[#2c2416]">{a.totalBooths}</td>
                  <td className="px-4 py-3 text-center font-medium text-[#2c2416]">{a.assignedStaff}</td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => handleDelete(a)}
                      className="w-7 h-7 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-[#f5e8e8] hover:text-[#7a2020] transition-all"
                    >
                      <Trash2 size={13} />
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* Create modal */}
      <Modal open={addOpen} onClose={() => setAddOpen(false)} title="Create District Admin">
        <form onSubmit={handleCreate} className="space-y-4">
          {[
            { key: 'name',     label: 'Full name',        type: 'text',     required: true },
            { key: 'username', label: 'Username',         type: 'text',     required: true },
            { key: 'district', label: 'District',         type: 'text',     required: true },
            { key: 'password', label: 'Password (min 6)', type: 'password', required: true },
          ].map(({ key, label, type, required }) => (
            <div key={key}>
              <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">
                {label}{required && ' *'}
              </label>
              <input
                className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
                type={type}
                value={form[key]}
                onChange={(e) => setForm(p => ({ ...p, [key]: e.target.value }))}
                required={required}
              />
            </div>
          ))}
          <button
            type="submit"
            disabled={saving}
            className="w-full bg-[#8b6914] hover:opacity-90 disabled:opacity-60 text-white text-[13px] font-medium py-2.5 rounded-lg transition-opacity mt-1"
          >
            {saving ? 'Creating…' : 'Create Admin'}
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