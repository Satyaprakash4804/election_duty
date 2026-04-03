import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { FileBarChart2 } from 'lucide-react'
import { superAPI } from '../../services/api'
import { PageHeader, Spinner, EmptyState } from '../../components/ui'
import toast from 'react-hot-toast'

const statFields = [
  { key: 'superZones',     label: 'Super Zones' },
  { key: 'zones',          label: 'Zones'       },
  { key: 'sectors',        label: 'Sectors'     },
  { key: 'gramPanchayats', label: 'GPs'         },
  { key: 'centers',        label: 'Centers'     },
]

export default function SuperFormData() {
  const [data, setData]       = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    superAPI.formData()
      .then(setData)
      .catch(() => toast.error('Failed to load form data'))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <Spinner />

  return (
    <div>
      <PageHeader
        title="District Form Data"
        subtitle="Structure filled by each district admin"
      />

      {data.length === 0 ? (
        <EmptyState message="No form data available" icon={FileBarChart2} />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {data.map((d, i) => (
            <motion.div
              key={d.adminId}
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.04 }}
              className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-5"
            >
              {/* Card header */}
              <div className="flex items-start justify-between mb-4 pb-3 border-b border-[#8b734b]/12">
                <div>
                  <h3 className="text-[15px] font-medium text-[#2c2416]">{d.district}</h3>
                  <p className="text-[12px] text-[#a89878] mt-0.5">{d.adminName}</p>
                </div>
                {d.lastUpdated && (
                  <span className="text-[11px] text-[#a89878] font-mono mt-0.5">
                    {new Date(d.lastUpdated).toLocaleDateString('en-IN')}
                  </span>
                )}
              </div>

              {/* Stat grid */}
              <div className="grid grid-cols-3 gap-2.5">
                {statFields.map(({ key, label }) => (
                  <div
                    key={key}
                    className="bg-[#f0ead8] border border-[#8b734b]/15 rounded-lg p-3 text-center"
                  >
                    <p className="text-[20px] font-medium text-[#8b6914]">{d[key] ?? 0}</p>
                    <p className="text-[11px] text-[#7a6a50] mt-0.5">{label}</p>
                  </div>
                ))}
              </div>
            </motion.div>
          ))}
        </div>
      )}
    </div>
  )
}