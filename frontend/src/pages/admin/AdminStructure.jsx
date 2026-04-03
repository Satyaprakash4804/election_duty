import { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { ChevronRight, ChevronDown, Plus, Trash2, Building2, Map, Grid3X3, Landmark, MapPin } from 'lucide-react'
import { adminAPI } from '../../services/api'
import { PageHeader, Modal, Spinner, EmptyState, ConfirmDialog } from '../../components/ui'
import toast from 'react-hot-toast'

const iconColor = {
  Building2: 'text-[#8b6914]',
  Map:       'text-[#5c8b3a]',
  Grid3X3:   'text-[#1a3d6e]',
  Landmark:  'text-[#4a1a6e]',
  MapPin:    'text-[#7a2020]',
}

function TreeRow({ icon: Icon, label, subLabel, onDelete, onExpand, expanded, children, depth = 0, iconKey }) {
  return (
    <div>
      <div
        className={`flex items-center gap-2 px-3 py-2.5 rounded-lg cursor-pointer transition-colors group ${expanded ? 'bg-[#f0ead8]' : 'hover:bg-[#f5f0e8]'}`}
        style={{ marginLeft: depth * 16 }}
        onClick={onExpand}
      >
        <span className="text-[#a89878]">
          {expanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
        </span>
        <div className="w-6 h-6 rounded-md bg-[#f0ead8] flex items-center justify-center flex-shrink-0">
          <Icon size={12} className={iconKey ? iconColor[iconKey] : 'text-[#8b6914]'} />
        </div>
        <span className="flex-1 text-[13px] font-medium text-[#2c2416]">{label}</span>
        {subLabel && <span className="text-[11px] text-[#a89878]">{subLabel}</span>}
        <button
          onClick={(e) => { e.stopPropagation(); onDelete() }}
          className="opacity-0 group-hover:opacity-100 w-6 h-6 rounded-md flex items-center justify-center text-[#a89878] hover:bg-[#f5e8e8] hover:text-[#7a2020] transition-all ml-1"
        >
          <Trash2 size={12} />
        </button>
      </div>
      <AnimatePresence>
        {expanded && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="overflow-hidden"
          >
            {children}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}

function AddForm({ fields, onSubmit, loading }) {
  const [vals, setVals] = useState({})
  return (
    <form onSubmit={e => { e.preventDefault(); onSubmit(vals) }} className="space-y-4">
      {fields.map(({ key, label, placeholder, required }) => (
        <div key={key}>
          <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">
            {label}{required && ' *'}
          </label>
          <input
            className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
            placeholder={placeholder || label}
            value={vals[key] || ''}
            onChange={e => setVals(p => ({ ...p, [key]: e.target.value }))}
            required={required}
          />
        </div>
      ))}
      <button
        type="submit"
        disabled={loading}
        className="w-full bg-[#8b6914] hover:opacity-90 disabled:opacity-60 text-white text-[13px] font-medium py-2.5 rounded-lg transition-opacity"
      >
        {loading ? 'Adding…' : 'Add'}
      </button>
    </form>
  )
}

const modalConfig = {
  sz:     { title: 'Add Super Zone', fields: [{ key: 'name', label: 'Name', required: true }] },
  zone:   { title: 'Add Zone', fields: [
    { key: 'name',          label: 'Zone Name',      required: true },
    { key: 'hqAddress',     label: 'HQ Address'                    },
    { key: 'officerName',   label: 'Officer Name'                  },
    { key: 'officerPno',    label: 'Officer PNO'                   },
    { key: 'officerMobile', label: 'Officer Mobile'                },
  ]},
  sector: { title: 'Add Sector', fields: [{ key: 'name', label: 'Sector Name', required: true }] },
  gp:     { title: 'Add Gram Panchayat', fields: [
    { key: 'name',    label: 'GP Name', required: true },
    { key: 'address', label: 'Address'                },
  ]},
  center: { title: 'Add Center', fields: [
    { key: 'name',       label: 'Center Name', required: true },
    { key: 'address',    label: 'Address'                     },
    { key: 'thana',      label: 'Thana'                       },
    { key: 'centerType', label: 'Type (C/S/SS)', placeholder: 'C' },
    { key: 'busNo',      label: 'Bus No'                      },
  ]},
}

export default function AdminStructure() {
  const [superZones, setSuperZones] = useState([])
  const [zones,   setZones]   = useState({})
  const [sectors, setSectors] = useState({})
  const [gps,     setGps]     = useState({})
  const [centers, setCenters] = useState({})
  const [expanded, setExpanded] = useState({})
  const [loading, setLoading]   = useState(true)
  const [modal,   setModal]     = useState(null)
  const [saving,  setSaving]    = useState(false)
  const [confirm, setConfirm]   = useState(null)

  const toggle = (key) => setExpanded(p => ({ ...p, [key]: !p[key] }))

  useEffect(() => {
    adminAPI.getSuperZones()
      .then(setSuperZones)
      .catch(() => toast.error('Failed to load structure'))
      .finally(() => setLoading(false))
  }, [])

  const loadZones   = async (id) => { if (!zones[id])   setZones(p   => ({ ...p, [id]: [] })); const d = await adminAPI.getZones(id).catch(() => []);   setZones(p   => ({ ...p, [id]: d })) }
  const loadSectors = async (id) => { if (!sectors[id]) setSectors(p => ({ ...p, [id]: [] })); const d = await adminAPI.getSectors(id).catch(() => []); setSectors(p => ({ ...p, [id]: d })) }
  const loadGPs     = async (id) => { if (!gps[id])     setGps(p     => ({ ...p, [id]: [] })); const d = await adminAPI.getGPs(id).catch(() => []);     setGps(p     => ({ ...p, [id]: d })) }
  const loadCenters = async (id) => { if (!centers[id]) setCenters(p => ({ ...p, [id]: [] })); const d = await adminAPI.getCenters(id).catch(() => []); setCenters(p => ({ ...p, [id]: d })) }

  const handleAdd = async (type, parentId, vals) => {
    setSaving(true)
    try {
      if (type === 'sz') {
        const res = await adminAPI.addSuperZone(vals.name)
        setSuperZones(p => [...p, { id: res.data.id, name: vals.name, zoneCount: 0 }])
        toast.success('Super Zone added')
      } else if (type === 'zone') {
        const res = await adminAPI.addZone(parentId, vals)
        setZones(p => ({ ...p, [parentId]: [...(p[parentId] || []), { id: res.data.id, ...vals, sectorCount: 0 }] }))
        toast.success('Zone added')
      } else if (type === 'sector') {
        const res = await adminAPI.addSector(parentId, { name: vals.name })
        setSectors(p => ({ ...p, [parentId]: [...(p[parentId] || []), { id: res.data.id, name: vals.name, gpCount: 0 }] }))
        toast.success('Sector added')
      } else if (type === 'gp') {
        const res = await adminAPI.addGP(parentId, vals)
        setGps(p => ({ ...p, [parentId]: [...(p[parentId] || []), { id: res.data.id, ...vals, centerCount: 0 }] }))
        toast.success('Gram Panchayat added')
      } else if (type === 'center') {
        const res = await adminAPI.addCenter(parentId, vals)
        setCenters(p => ({ ...p, [parentId]: [...(p[parentId] || []), { id: res.data.id, ...vals }] }))
        toast.success('Center added')
      }
      setModal(null)
    } catch (e) {
      toast.error(e?.response?.data?.message || 'Failed to add')
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = (type, id, parentId) => {
    setConfirm({
      message: `Delete this ${type}? All nested data will be removed.`,
      action: async () => {
        try {
          const apiMap = {
            'super zone': () => { adminAPI.deleteSuperZone(id); setSuperZones(p => p.filter(z => z.id !== id)) },
            'zone':       () => { adminAPI.deleteZone(id);      setZones(p   => ({ ...p, [parentId]: p[parentId]?.filter(z => z.id !== id) })) },
            'sector':     () => { adminAPI.deleteSector(id);    setSectors(p => ({ ...p, [parentId]: p[parentId]?.filter(s => s.id !== id) })) },
            'gram panchayat': () => { adminAPI.deleteGP(id);   setGps(p     => ({ ...p, [parentId]: p[parentId]?.filter(g => g.id !== id) })) },
            'center':     () => { adminAPI.deleteCenter(id);   setCenters(p => ({ ...p, [parentId]: p[parentId]?.filter(c => c.id !== id) })) },
          }
          await apiMap[type]?.()
          toast.success('Deleted successfully')
        } catch { toast.error('Delete failed') }
        setConfirm(null)
      },
    })
  }

  if (loading) return <Spinner />

  const addBtn = (label, onClick) => (
    <button
      onClick={onClick}
      className="inline-flex items-center gap-1 text-[12px] text-[#8b6914] hover:underline px-3 py-1 ml-2"
    >
      <Plus size={11} /> {label}
    </button>
  )

  return (
    <div>
      <PageHeader
        title="Election Structure"
        subtitle="Super Zone → Zone → Sector → GP → Center"
        action={
          <button
            onClick={() => setModal({ type: 'sz' })}
            className="inline-flex items-center gap-2 bg-[#8b6914] hover:opacity-90 text-white text-[13px] font-medium px-4 py-2 rounded-lg transition-opacity"
          >
            <Plus size={14} /> Add Super Zone
          </button>
        }
      />

      {superZones.length === 0 && (
        <EmptyState message="No super zones yet. Add one to get started." icon={Building2} />
      )}

      <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-3 space-y-0.5">
        {superZones.map(sz => (
          <TreeRow
            key={sz.id} icon={Building2} iconKey="Building2"
            label={sz.name} subLabel={`${sz.zoneCount} zones`}
            expanded={expanded[`sz_${sz.id}`]}
            onExpand={async () => { toggle(`sz_${sz.id}`); await loadZones(sz.id) }}
            onDelete={() => handleDelete('super zone', sz.id, null)}
          >
            <div className="ml-5 mt-0.5 mb-1 space-y-0.5">
              {addBtn('Add Zone', () => setModal({ type: 'zone', parentId: sz.id }))}
              {(zones[sz.id] || []).map(z => (
                <TreeRow
                  key={z.id} icon={Map} iconKey="Map"
                  label={z.name} subLabel={`${z.sectorCount} sectors`}
                  expanded={expanded[`z_${z.id}`]}
                  onExpand={async () => { toggle(`z_${z.id}`); await loadSectors(z.id) }}
                  onDelete={() => handleDelete('zone', z.id, sz.id)}
                >
                  <div className="ml-5 mt-0.5 mb-1 space-y-0.5">
                    {addBtn('Add Sector', () => setModal({ type: 'sector', parentId: z.id }))}
                    {(sectors[z.id] || []).map(s => (
                      <TreeRow
                        key={s.id} icon={Grid3X3} iconKey="Grid3X3"
                        label={s.name} subLabel={`${s.gpCount} GPs`}
                        expanded={expanded[`s_${s.id}`]}
                        onExpand={async () => { toggle(`s_${s.id}`); await loadGPs(s.id) }}
                        onDelete={() => handleDelete('sector', s.id, z.id)}
                      >
                        <div className="ml-5 mt-0.5 mb-1 space-y-0.5">
                          {addBtn('Add Gram Panchayat', () => setModal({ type: 'gp', parentId: s.id }))}
                          {(gps[s.id] || []).map(gp => (
                            <TreeRow
                              key={gp.id} icon={Landmark} iconKey="Landmark"
                              label={gp.name} subLabel={`${gp.centerCount} centers`}
                              expanded={expanded[`gp_${gp.id}`]}
                              onExpand={async () => { toggle(`gp_${gp.id}`); await loadCenters(gp.id) }}
                              onDelete={() => handleDelete('gram panchayat', gp.id, s.id)}
                            >
                              <div className="ml-5 mt-0.5 mb-2 space-y-0.5">
                                {addBtn('Add Center', () => setModal({ type: 'center', parentId: gp.id }))}
                                {(centers[gp.id] || []).map(c => (
                                  <div
                                    key={c.id}
                                    className="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-[#f5f0e8] group ml-2 transition-colors"
                                  >
                                    <div className="w-5 h-5 rounded-md bg-[#f5e8e8] flex items-center justify-center flex-shrink-0">
                                      <MapPin size={10} className="text-[#7a2020]" />
                                    </div>
                                    <span className="flex-1 text-[13px] text-[#2c2416]">{c.name}</span>
                                    {c.centerType && (
                                      <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-[#e6eef8] text-[#1a3d6e]">{c.centerType}</span>
                                    )}
                                    {c.dutyCount > 0 && (
                                      <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-[#e6f0e0] text-[#2d5a1e]">{c.dutyCount} duties</span>
                                    )}
                                    <button
                                      onClick={() => handleDelete('center', c.id, gp.id)}
                                      className="opacity-0 group-hover:opacity-100 w-6 h-6 rounded-md flex items-center justify-center text-[#a89878] hover:bg-[#f5e8e8] hover:text-[#7a2020] transition-all"
                                    >
                                      <Trash2 size={11} />
                                    </button>
                                  </div>
                                ))}
                              </div>
                            </TreeRow>
                          ))}
                        </div>
                      </TreeRow>
                    ))}
                  </div>
                </TreeRow>
              ))}
            </div>
          </TreeRow>
        ))}
      </div>

      {modal && (
        <Modal open={!!modal} onClose={() => setModal(null)} title={modalConfig[modal.type]?.title}>
          <AddForm
            fields={modalConfig[modal.type]?.fields || []}
            loading={saving}
            onSubmit={(vals) => handleAdd(modal.type, modal.parentId, vals)}
          />
        </Modal>
      )}

      <ConfirmDialog
        open={!!confirm}
        onClose={() => setConfirm(null)}
        onConfirm={confirm?.action}
        message={confirm?.message}
      />
    </div>
  )
}