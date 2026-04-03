import { useEffect, useState } from 'react'
import { Plus, Trash2, Search } from 'lucide-react'
import { adminAPI } from '../../services/api'
import { PageHeader, Modal, Spinner, ConfirmDialog } from '../../components/ui'
import toast from 'react-hot-toast'

export default function AdminDuties() {
  const [duties, setDuties]       = useState([])
  const [centers, setCenters]     = useState([])
  const [staff, setStaff]         = useState([])
  const [loading, setLoading]     = useState(true)
  const [addOpen, setAddOpen]     = useState(false)
  const [saving, setSaving]       = useState(false)
  const [confirm, setConfirm]     = useState(null)
  const [form, setForm]           = useState({ staffId: '', centerId: '', busNo: '' })
  const [staffSearch, setStaffSearch] = useState('')
  const [filterCenter, setFilterCenter] = useState('')

  useEffect(() => {
    Promise.all([adminAPI.getDuties(), adminAPI.allCenters(), adminAPI.getStaff()])
      .then(([d, c, s]) => { setDuties(d); setCenters(c); setStaff(s) })
      .catch(() => toast.error('Failed to load duties'))
      .finally(() => setLoading(false))
  }, [])

  const reload = () => {
    adminAPI.getDuties(filterCenter || null).then(setDuties).catch(() => {})
  }

  useEffect(() => { if (!loading) reload() }, [filterCenter])

  const handleAssign = async (e) => {
    e.preventDefault()
    if (!form.staffId || !form.centerId) return toast.error('Select both staff and center')
    setSaving(true)
    try {
      await adminAPI.assignDuty({
        staffId:  parseInt(form.staffId),
        centerId: parseInt(form.centerId),
        busNo: form.busNo || null,
      })
      toast.success('Duty assigned')
      setAddOpen(false)
      setForm({ staffId: '', centerId: '', busNo: '' })
      reload()
    } catch (err) {
      toast.error(err?.response?.data?.message || 'Assignment failed')
    } finally {
      setSaving(false)
    }
  }

  const handleRemove = (id) => {
    setConfirm({
      message: 'Remove this duty assignment?',
      action: async () => {
        try {
          await adminAPI.removeDuty(id)
          setDuties(p => p.filter(d => d.id !== id))
          toast.success('Duty removed')
        } catch { toast.error('Remove failed') }
        setConfirm(null)
      },
    })
  }

  const filteredStaff = staff.filter(s =>
    !staffSearch ||
    s.name.toLowerCase().includes(staffSearch.toLowerCase()) ||
    s.pno.includes(staffSearch)
  )

  if (loading) return <Spinner />

  return (
    <div>
      <PageHeader
        title="Duty Assignments"
        subtitle={`${duties.length} assignments total`}
        action={
          <button
            onClick={() => setAddOpen(true)}
            className="inline-flex items-center gap-2 bg-[#8b6914] hover:opacity-90 text-white text-[13px] font-medium px-4 py-2 rounded-lg transition-opacity"
          >
            <Plus size={14} /> Assign Duty
          </button>
        }
      />

      {/* Filter */}
      <div className="mb-5">
        <select
          className="bg-[#fdfaf5] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition max-w-xs w-full"
          value={filterCenter}
          onChange={(e) => setFilterCenter(e.target.value)}
        >
          <option value="">All Centers</option>
          {centers.map(c => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </select>
      </div>

      {/* Table */}
      <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl overflow-hidden">
        <table className="w-full border-collapse text-[13px]">
          <thead>
            <tr className="bg-[#f0ead8]">
              {['Staff Name', 'PNO', 'Mobile', 'Thana', 'Center', 'Zone', 'Bus No', ''].map((h) => (
                <th key={h} className="px-4 py-2.5 text-left text-[11px] font-medium text-[#7a6a50] uppercase tracking-wide border-b border-[#8b734b]/15 whitespace-nowrap">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {duties.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-10 text-center text-[#a89878] text-[13px]">
                  No duty assignments found
                </td>
              </tr>
            ) : (
              duties.map((d) => (
                <tr key={d.id} className="hover:bg-[#f5f0e8] transition-colors border-b border-[#8b734b]/10 last:border-0">
                  <td className="px-4 py-3 font-medium text-[#2c2416]">{d.name}</td>
                  <td className="px-4 py-3 font-mono text-[11px] text-[#a89878]">{d.pno}</td>
                  <td className="px-4 py-3 text-[#7a6a50]">{d.mobile || '—'}</td>
                  <td className="px-4 py-3 text-[#7a6a50]">{d.staffThana || '—'}</td>
                  <td className="px-4 py-3">
                    <p className="font-medium text-[#2c2416]">{d.centerName}</p>
                    <p className="text-[11px] text-[#a89878]">{d.gpName} · {d.sectorName}</p>
                  </td>
                  <td className="px-4 py-3 text-[11px] text-[#7a6a50]">{d.zoneName}</td>
                  <td className="px-4 py-3 text-[11px] text-[#7a6a50]">{d.busNo || '—'}</td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => handleRemove(d.id)}
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

      {/* Assign modal */}
      <Modal open={addOpen} onClose={() => setAddOpen(false)} title="Assign Duty">
        <form onSubmit={handleAssign} className="space-y-4">
          {/* Staff search */}
          <div>
            <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">Search & select staff *</label>
            <div className="relative mb-2">
              <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#a89878]" />
              <input
                className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg pl-8 pr-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
                placeholder="Search by name or PNO…"
                value={staffSearch}
                onChange={(e) => setStaffSearch(e.target.value)}
              />
            </div>
            <select
              className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
              value={form.staffId}
              onChange={(e) => setForm(p => ({ ...p, staffId: e.target.value }))}
              required
              size={4}
            >
              <option value="">— Select staff —</option>
              {filteredStaff.map(s => (
                <option key={s.id} value={s.id}>
                  {s.name} ({s.pno}){s.isAssigned ? ' ✓' : ''}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">Select center *</label>
            <select
              className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
              value={form.centerId}
              onChange={(e) => setForm(p => ({ ...p, centerId: e.target.value }))}
              required
            >
              <option value="">— Select center —</option>
              {centers.map(c => (
                <option key={c.id} value={c.id}>{c.name} ({c.sectorName})</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">Bus no</label>
            <input
              className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
              placeholder="Optional"
              value={form.busNo}
              onChange={(e) => setForm(p => ({ ...p, busNo: e.target.value }))}
            />
          </div>

          <button
            type="submit"
            disabled={saving}
            className="w-full bg-[#8b6914] hover:opacity-90 disabled:opacity-60 text-white text-[13px] font-medium py-2.5 rounded-lg transition-opacity"
          >
            {saving ? 'Assigning…' : 'Assign Duty'}
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