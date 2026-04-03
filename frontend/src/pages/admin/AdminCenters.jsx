import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { MapPin, Search } from 'lucide-react'
import { adminAPI } from '../../services/api'
import { PageHeader, Spinner, EmptyState } from '../../components/ui'
import toast from 'react-hot-toast'

const TYPE_STYLE = {
  C:  'bg-[#e6eef8] text-[#1a3d6e]',
  S:  'bg-[#f0e8f8] text-[#4a1a6e]',
  SS: 'bg-[#faebd7] text-[#7a4a0a]',
}

function CenterCard({ c, index }) {
  const typeClass  = TYPE_STYLE[c.centerType] || 'bg-[#f0ead8] text-[#7a6a50]'
  const dutyClass  = c.dutyCount > 0 ? 'bg-[#e6f0e0] text-[#2d5a1e]' : 'bg-[#f5e8e8] text-[#7a2020]'
  const dutyLabel  = c.dutyCount + (c.dutyCount === 1 ? ' duty' : ' duties')
  const gpSector   = c.gpName + ' → ' + c.sectorName
  const zoneSuper  = c.zoneName + ' → ' + c.superZoneName
  const mapsHref   = 'https://www.google.com/maps?q=' + c.latitude + ',' + c.longitude
  const hasMap     = c.latitude && c.longitude

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: index * 0.02 }}
      className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-4 hover:border-[#8b734b]/40 transition-colors"
    >
      <div className="flex items-start justify-between gap-2 mb-3">
        <div className="flex items-start gap-2">
          <div className="w-7 h-7 rounded-lg bg-[#f0ead8] flex items-center justify-center flex-shrink-0 mt-0.5">
            <MapPin size={13} className="text-[#8b6914]" />
          </div>
          <h3 className="text-[13px] font-medium text-[#2c2416] leading-tight">{c.name}</h3>
        </div>
        <span className={'text-[10px] font-medium px-2 py-0.5 rounded-full flex-shrink-0 ' + typeClass}>
          {c.centerType || 'C'}
        </span>
      </div>

      <div className="space-y-1 text-[12px] text-[#7a6a50] pl-9">
        {c.address && <p>{c.address}</p>}
        {c.thana   && <p>Thana: <span className="text-[#2c2416]">{c.thana}</span></p>}
        <p className="text-[11px]">{gpSector}</p>
        <p className="text-[11px]">{zoneSuper}</p>
      </div>

      <div className="flex items-center justify-between mt-3 pt-3 border-t border-[#8b734b]/12">
  <span className={'text-[11px] font-medium px-2.5 py-1 rounded-full ' + dutyClass}>
    {dutyLabel}
  </span>

  {hasMap && (
    <a
      href={mapsHref}
      target="_blank"
      rel="noreferrer"
      className="text-[11px] text-[#8b6914] hover:underline flex items-center gap-1"
    >
      <MapPin size={10} /> View map
    </a>
  )}
</div>
    </motion.div>
  )
}

export default function AdminCenters() {
  const [centers, setCenters] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch]   = useState('')

  useEffect(() => {
    adminAPI.allCenters()
      .then(setCenters)
      .catch(() => toast.error('Failed to load centers'))
      .finally(() => setLoading(false))
  }, [])

  const filtered = centers.filter((c) => {
    if (!search) return true
    const q = search.toLowerCase()
    return (
      c.name.toLowerCase().includes(q) ||
      (c.thana && c.thana.toLowerCase().includes(q)) ||
      (c.sectorName && c.sectorName.toLowerCase().includes(q))
    )
  })

  if (loading) return <Spinner />

  const subtitle = centers.length + ' matdan sthal in your district'
  const showing  = 'Showing'

  return (
    <div>
      <PageHeader title="All Centers" subtitle={subtitle} />

      <div className="flex items-center gap-4 mb-5">
        <div className="relative flex-1 max-w-sm">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#a89878]" />
          <input
            className="w-full bg-[#fdfaf5] border border-[#8b734b]/25 rounded-lg pl-9 pr-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
            placeholder="Search by name, thana, sector..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <p className="text-[13px] text-[#a89878]">
          {showing} <span className="font-medium text-[#2c2416]">{filtered.length}</span> of {centers.length}
        </p>
      </div>

      {filtered.length === 0 ? (
        <EmptyState message="No centers found" icon={MapPin} />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {filtered.map((c, i) => (
            <CenterCard key={c.id} c={c} index={i} />
          ))}
        </div>
      )}
    </div>
  )
}