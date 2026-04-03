import { useEffect, useState } from 'react'
import { Users, MapPin, ClipboardCheck } from 'lucide-react'
import { superAPI } from '../../services/api'
import { Spinner, PageHeader } from '../../components/ui'
import toast from 'react-hot-toast'

const statCards = (stats) => [
  { icon: Users,          label: 'Total Admins',    value: stats?.totalAdmins,    iconBg: 'bg-amber-100',  iconColor: 'text-amber-800'  },
  { icon: MapPin,         label: 'Total Booths',    value: stats?.totalBooths,    iconBg: 'bg-blue-100',   iconColor: 'text-blue-800'   },
  { icon: Users,          label: 'Total Staff',     value: stats?.totalStaff,     iconBg: 'bg-green-100',  iconColor: 'text-green-800'  },
  { icon: ClipboardCheck, label: 'Assigned Duties', value: stats?.assignedDuties, iconBg: 'bg-orange-100', iconColor: 'text-orange-800' },
]

export function SuperOverview() {
  const [stats, setStats]     = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    superAPI.overview()
      .then(setStats)
      .catch(() => toast.error('Failed to load overview'))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <Spinner />

  return (
    <div>
      <PageHeader
        title="Super Admin Dashboard"
        subtitle="System-wide election management overview"
      />

      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3">
        {statCards(stats).map(({ icon: Icon, label, value, iconBg, iconColor }) => (
          <div key={label} className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-4">
            <div className={`w-8 h-8 rounded-lg ${iconBg} flex items-center justify-center mb-3`}>
              <Icon size={15} className={iconColor} />
            </div>
            <p className="text-[11px] font-medium text-[#7a6a50] uppercase tracking-wide mb-1">{label}</p>
            <p className="text-[22px] font-medium text-[#2c2416]">{value ?? '—'}</p>
          </div>
        ))}
      </div>
    </div>
  )
}

export default SuperOverview