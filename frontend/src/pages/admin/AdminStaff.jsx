import { useEffect, useState, useCallback } from 'react'
import { Plus, Search, CheckCircle2, XCircle, Upload } from 'lucide-react'
import { adminAPI } from '../../services/api'
import { PageHeader, Modal, Spinner } from '../../components/ui'
import toast from 'react-hot-toast'

export default function AdminStaff() {
  const [staff, setStaff]     = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch]   = useState('')
  const [addOpen, setAddOpen] = useState(false)
  const [saving, setSaving]   = useState(false)
  const [form, setForm]       = useState({ name: '', pno: '', mobile: '', thana: '' })

  const loadStaff = useCallback(async (q = '') => {
    setLoading(true)
    try   { setStaff(await adminAPI.getStaff(q)) }
    catch { toast.error('Failed to load staff') }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadStaff() }, [loadStaff])

  useEffect(() => {
    const t = setTimeout(() => loadStaff(search), 400)
    return () => clearTimeout(t)
  }, [search, loadStaff])

  const handleAdd = async (e) => {
    e.preventDefault()
    if (!form.name || !form.pno) return toast.error('Name and PNO are required')
    setSaving(true)
    try {
      await adminAPI.addStaff(form)
      toast.success('Staff added successfully')
      setAddOpen(false)
      setForm({ name: '', pno: '', mobile: '', thana: '' })
      loadStaff(search)
    } catch (err) {
      toast.error(err?.response?.data?.message || 'Failed to add staff')
    } finally {
      setSaving(false)
    }
  }

  const handleBulkPaste = async () => {
    const raw = prompt('Paste CSV data (name,pno,mobile,thana) one per line:')
    if (!raw) return
    const rows = raw.trim().split('\n').map(line => {
      const [name, pno, mobile, thana] = line.split(',').map(s => s.trim())
      return { name, pno, mobile, thana }
    }).filter(s => s.name && s.pno)
    if (!rows.length) return toast.error('No valid rows found')
    try {
      const res = await adminAPI.addStaffBulk(rows)
      toast.success(`${res.data?.added || 0} staff added`)
      loadStaff(search)
    } catch (err) {
      toast.error(err?.response?.data?.message || 'Bulk import failed')
    }
  }

  const assigned   = staff.filter(s => s.isAssigned).length
  const unassigned = staff.filter(s => !s.isAssigned).length

  return (
    <div>
      <PageHeader
        title="Staff Management"
        subtitle="Add and search polling staff in your district"
        action={
          <div className="flex gap-2">
            <button
              onClick={handleBulkPaste}
              className="inline-flex items-center gap-2 bg-[#f0ead8] hover:bg-[#e8e0cc] text-[#7a6a50] border border-[#8b734b]/20 text-[13px] font-medium px-3.5 py-2 rounded-lg transition-colors"
            >
              <Upload size={13} /> Bulk Import
            </button>
            <button
              onClick={() => setAddOpen(true)}
              className="inline-flex items-center gap-2 bg-[#8b6914] hover:opacity-90 text-white text-[13px] font-medium px-4 py-2 rounded-lg transition-opacity"
            >
              <Plus size={14} /> Add Staff
            </button>
          </div>
        }
      />

      {/* Search */}
      <div className="relative mb-4 max-w-sm">
        <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#a89878]" />
        <input
          className="w-full bg-[#fdfaf5] border border-[#8b734b]/25 rounded-lg pl-9 pr-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
          placeholder="Search by name, PNO or mobile…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

      {/* Stats bar */}
      <div className="flex gap-5 mb-5">
        {[
          { label: 'Total',      value: staff.length, color: 'text-[#2c2416]' },
          { label: 'Assigned',   value: assigned,     color: 'text-[#2d5a1e]' },
          { label: 'Unassigned', value: unassigned,   color: 'text-[#7a2020]' },
        ].map(({ label, value, color }) => (
          <div key={label} className="text-[13px] text-[#7a6a50]">
            {label}: <span className={`font-medium ${color}`}>{value}</span>
          </div>
        ))}
      </div>

      {/* Table */}
      {loading ? <Spinner /> : (
        <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl overflow-hidden">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="bg-[#f0ead8]">
                {['Name', 'PNO', 'Mobile', 'Thana', 'Status', 'Assigned Center'].map((h) => (
                  <th key={h} className="px-4 py-2.5 text-left text-[11px] font-medium text-[#7a6a50] uppercase tracking-wide border-b border-[#8b734b]/15 whitespace-nowrap">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {staff.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-10 text-center text-[#a89878] text-[13px]">No staff found</td>
                </tr>
              ) : (
                staff.map((s) => (
                  <tr key={s.id} className="hover:bg-[#f5f0e8] transition-colors border-b border-[#8b734b]/10 last:border-0">
                    <td className="px-4 py-3 font-medium text-[#2c2416]">{s.name}</td>
                    <td className="px-4 py-3 font-mono text-[11px] text-[#a89878]">{s.pno}</td>
                    <td className="px-4 py-3 text-[#7a6a50]">{s.mobile || '—'}</td>
                    <td className="px-4 py-3 text-[#7a6a50]">{s.thana || '—'}</td>
                    <td className="px-4 py-3">
                      {s.isAssigned ? (
                        <span className="inline-flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1 rounded-full bg-[#e6f0e0] text-[#2d5a1e]">
                          <CheckCircle2 size={11} /> Assigned
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1 rounded-full bg-[#f5e8e8] text-[#7a2020]">
                          <XCircle size={11} /> Unassigned
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-[11px] text-[#7a6a50]">{s.centerName || '—'}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* Add modal */}
      <Modal open={addOpen} onClose={() => setAddOpen(false)} title="Add Staff Member">
        <form onSubmit={handleAdd} className="space-y-4">
          {[
            { key: 'name',   label: 'Full name',     required: true },
            { key: 'pno',    label: 'PNO',           required: true },
            { key: 'mobile', label: 'Mobile number'               },
            { key: 'thana',  label: 'Thana'                       },
          ].map(({ key, label, required }) => (
            <div key={key}>
              <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">
                {label}{required && ' *'}
              </label>
              <input
                className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
                value={form[key]}
                onChange={(e) => setForm(p => ({ ...p, [key]: e.target.value }))}
                required={required}
              />
            </div>
          ))}
          <p className="text-[12px] text-[#7a6a50] bg-[#f0ead8] border border-[#8b734b]/15 rounded-lg p-3">
            Default password will be the PNO. Staff can log in with PNO as both username and password.
          </p>
          <button
            type="submit"
            disabled={saving}
            className="w-full bg-[#8b6914] hover:opacity-90 disabled:opacity-60 text-white text-[13px] font-medium py-2.5 rounded-lg transition-opacity"
          >
            {saving ? 'Adding…' : 'Add Staff Member'}
          </button>
        </form>
      </Modal>
    </div>
  )
}