import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { Database, Users, Server, Clock } from 'lucide-react'
import { masterAPI } from '../../services/api'
import { Spinner, PageHeader } from '../../components/ui'
import toast from 'react-hot-toast'

const statCards = (supers, stats) => [
  { icon: Users,    label: 'Super Admins',  value: supers.length,       iconBg: 'bg-amber-100',  iconColor: 'text-amber-800' },
  { icon: Database, label: 'DB Size',       value: stats?.dbSize,       iconBg: 'bg-blue-100',   iconColor: 'text-blue-800'  },
  { icon: Server,   label: 'Total Records', value: stats?.totalRecords, iconBg: 'bg-green-100',  iconColor: 'text-green-800' },
  { icon: Clock,    label: 'System Uptime', value: stats?.uptime,       iconBg: 'bg-orange-100', iconColor: 'text-orange-800'},
]

export default function MasterOverview() {
  const [stats, setStats]   = useState(null)
  const [supers, setSupers] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    Promise.all([masterAPI.overview(), masterAPI.getSuperAdmins()])
      .then(([s, sa]) => { setStats(s); setSupers(sa) })
      .catch(() => toast.error('Failed to load overview'))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <Spinner />

  return (
    <div>
      <PageHeader
        title="Master Control Panel"
        subtitle="System-wide oversight — full platform control"
      />

      {/* Stat cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3 mb-6">
        {statCards(supers, stats).map(({ icon: Icon, label, value, iconBg, iconColor }) => (
          <div key={label} className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-4">
            <div className={`w-8 h-8 rounded-lg ${iconBg} flex items-center justify-center mb-3`}>
              <Icon size={15} className={iconColor} />
            </div>
            <p className="text-[11px] font-medium text-[#7a6a50] uppercase tracking-wide mb-1">{label}</p>
            <p className="text-[22px] font-medium text-[#2c2416]">{value ?? '—'}</p>
          </div>
        ))}
      </div>

      {/* Info cards */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.15 }}
          className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-5"
        >
          <h2 className="text-[15px] font-medium text-[#2c2416] mb-3 pb-3 border-b border-[#8b734b]/15">
            System info
          </h2>
          {[
            { label: 'Backend',       value: stats?.backend      || 'Flask' },
            { label: 'Last Backup',   value: stats?.lastBackup   || 'Never' },
            { label: 'React Build', value: stats?.flutterBuild || '—'    },
          ].map(({ label, value }) => (
            <div key={label} className="flex justify-between items-center py-2.5 border-b border-[#8b734b]/10 last:border-0 text-[13px]">
              <span className="text-[#7a6a50]">{label}</span>
              <span className="font-medium text-[#2c2416]">{value}</span>
            </div>
          ))}
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.25 }}
          className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-5"
        >
          <h2 className="text-[15px] font-medium text-[#2c2416] mb-3 pb-3 border-b border-[#8b734b]/15">
            Super Admins ({supers.length})
          </h2>
          {supers.length === 0 ? (
            <p className="text-[#7a6a50] text-[13px]">No super admins created yet.</p>
          ) : (
            supers.slice(0, 5).map((sa) => (
              <div key={sa.id} className="flex justify-between items-center py-2.5 border-b border-[#8b734b]/10 last:border-0">
                <div>
                  <p className="text-[13px] font-medium text-[#2c2416]">{sa.name}</p>
                  <p className="text-[11px] text-[#a89878] font-mono mt-0.5">{sa.username}</p>
                </div>
                <div className="text-right">
                  <span className={`inline-flex items-center text-[11px] font-medium px-2.5 py-0.5 rounded-full ${
                    sa.isActive
                      ? 'bg-[#e6f0e0] text-[#2d5a1e]'
                      : 'bg-[#f5e8e8] text-[#7a2020]'
                  }`}>
                    {sa.isActive ? 'Active' : 'Inactive'}
                  </span>
                  <p className="text-[11px] text-[#a89878] mt-1">{sa.adminsUnder} admins</p>
                </div>
              </div>
            ))
          )}
        </motion.div>
      </div>
    </div>
  )
}