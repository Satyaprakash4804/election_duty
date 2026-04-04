import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { Building2, MapPin, Users, ClipboardCheck } from 'lucide-react'
import { adminAPI } from '../../services/api'
import { Spinner, PageHeader } from '../../components/ui'
import toast from 'react-hot-toast'

const STATS = [
  { key: 'superZones',     label: 'सुपर ज़ोन',       iconBg: 'bg-amber-100',  iconColor: 'text-amber-800',  Icon: Building2      },
  { key: 'totalBooths',    label: 'कुल बूथ',         iconBg: 'bg-blue-100',   iconColor: 'text-blue-800',   Icon: MapPin          },
  { key: 'totalStaff',     label: 'कुल कर्मचारी',    iconBg: 'bg-green-100',  iconColor: 'text-green-800',  Icon: Users           },
  { key: 'assignedDuties', label: 'आवंटित ड्यूटियाँ', iconBg: 'bg-orange-100', iconColor: 'text-orange-800', Icon: ClipboardCheck  },
]

const ACTIONS = [
  { label: 'संरचना प्रबंधित करें (ज़ोन → केंद्र)', href: '/admin/structure', Icon: Building2      },
  { label: 'सभी केंद्र देखें',                      href: '/admin/centers',   Icon: MapPin          },
  { label: 'कर्मचारी जोड़ें / खोजें',               href: '/admin/staff',     Icon: Users           },
  { label: 'ड्यूटी आवंटित करें',                    href: '/admin/duties',    Icon: ClipboardCheck  },
  { label: 'पदानुक्रम दृश्य',                       href: '/admin/hierarchy', Icon: Building2       },
]

function StatCard({ item, value }) {
  const Ic = item.Icon
  return (
    <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-4">
      <div className={'w-8 h-8 rounded-lg flex items-center justify-center mb-3 ' + item.iconBg}>
        <Ic size={15} className={item.iconColor} />
      </div>
      <p className="text-[11px] font-medium text-[#7a6a50] uppercase tracking-wide mb-1">{item.label}</p>
      <p className="text-[22px] font-medium text-[#2c2416]">{value ?? '—'}</p>
    </div>
  )
}

function ActionLink({ item }) {
  const Ic = item.Icon
  return (
    <a
      href={item.href}
      className="flex items-center gap-3 p-3 rounded-lg border border-[#8b734b]/15 hover:bg-[#f0ead8] hover:border-[#8b734b]/30 transition-colors text-[13px] font-medium text-[#2c2416]"
    >
      <div className="w-7 h-7 rounded-lg bg-[#f0ead8] flex items-center justify-center flex-shrink-0">
        <Ic size={14} className="text-[#8b6914]" />
      </div>
      {item.label}
    </a>
  )
}

export default function AdminOverview() {
  const [stats, setStats]     = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    adminAPI.overview()
      .then(setStats)
      .catch(() => toast.error('अवलोकन लोड करने में विफल'))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <Spinner />

  const assigned = stats?.assignedDuties ?? 0
  const booths   = stats?.totalBooths    ?? 0
  const staff    = stats?.totalStaff     ?? 0
  const boothPct = booths ? (assigned / booths) * 100 : 0
  const staffPct = staff  ? (assigned / staff)  * 100 : 0

  const bars = [
    { label: 'ड्यूटी आवंटित बूथ', pct: boothPct, a: assigned, b: booths, color: 'bg-[#8b6914]' },
    { label: 'आवंटित कर्मचारी',    pct: staffPct, a: assigned, b: staff,  color: 'bg-[#5c8b3a]' },
  ]

  return (
    <div>
      <PageHeader
        title="व्यवस्थापक डैशबोर्ड"
        subtitle="आपके जिले की चुनाव व्यवस्था का अवलोकन"
      />

      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3 mb-6">
        {STATS.map((item) => (
          <StatCard key={item.key} item={item} value={stats ? stats[item.key] : null} />
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.15 }}
          className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-5"
        >
          <h2 className="text-[15px] font-medium text-[#2c2416] mb-4 pb-3 border-b border-[#8b734b]/15">
            आवंटन की प्रगति
          </h2>
          <div className="space-y-5">
            {bars.map((bar) => (
              <div key={bar.label}>
                <div className="flex justify-between text-[13px] mb-2">
                  <span className="text-[#7a6a50]">{bar.label}</span>
                  <span className="font-medium text-[#2c2416]">{bar.a} / {bar.b}</span>
                </div>
                <div className="h-2 bg-[#f0ead8] rounded-full overflow-hidden">
                  <motion.div
                    initial={{ width: 0 }}
                    animate={{ width: bar.pct + '%' }}
                    transition={{ duration: 1, ease: 'easeOut' }}
                    className={'h-full rounded-full ' + bar.color}
                  />
                </div>
              </div>
            ))}
          </div>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.25 }}
          className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-5"
        >
          <h2 className="text-[15px] font-medium text-[#2c2416] mb-4 pb-3 border-b border-[#8b734b]/15">
            त्वरित कार्य
          </h2>
          <div className="space-y-2">
            {ACTIONS.map((item) => (
              <ActionLink key={item.href} item={item} />
            ))}
          </div>
        </motion.div>
      </div>
    </div>
  )
}