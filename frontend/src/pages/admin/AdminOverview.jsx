import { useEffect, useState } from 'react'
import { Building2, MapPin, Users, ClipboardCheck, ClipboardList, LayoutDashboard } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { adminAPI } from '../../services/api'
import { Spinner, PageHeader } from '../../components/ui'
import toast from 'react-hot-toast'

const STATS = [
  { key: 'superZones',     label: 'सुपर ज़ोन',        bg: '#faeeda', Icon: Building2,     iconColor: 'text-amber-800'  },
  { key: 'totalBooths',    label: 'कुल बूथ',          bg: '#e6f1fb', Icon: MapPin,         iconColor: 'text-blue-800'   },
  { key: 'totalStaff',     label: 'कुल कर्मचारी',     bg: '#eaf3de', Icon: Users,          iconColor: 'text-green-800'  },
  { key: 'assignedDuties', label: 'आवंटित ड्यूटियाँ', bg: '#eeedfe', Icon: ClipboardCheck, iconColor: 'text-purple-800' },
]

const TILES = [
  { href: '/admin/structure', Icon: Building2,      label: 'संरचना',     sub: 'ज़ोन → केंद्र',  bg: '#faeeda', iconColor: 'text-amber-700'  },
  { href: '/admin/centers',   Icon: MapPin,          label: 'सभी केंद्र', sub: 'बूथ सूची',       bg: '#e6f1fb', iconColor: 'text-blue-700'   },
  { href: '/admin/staff',     Icon: Users,           label: 'कर्मचारी',   sub: 'जोड़ें / खोजें', bg: '#eaf3de', iconColor: 'text-green-700'  },
  { href: '/admin/duties',    Icon: ClipboardList,   label: 'ड्यूटी',     sub: 'आवंटन करें',     bg: '#eeedfe', iconColor: 'text-purple-700' },
  { href: '/admin/hierarchy', Icon: LayoutDashboard, label: 'पदानुक्रम', sub: 'संगठन चार्ट',    bg: '#e1f5ee', iconColor: 'text-teal-700'   },
]

export default function AdminOverview() {
  const [stats, setStats]     = useState(null)
  const [loading, setLoading] = useState(true)
  const navigate              = useNavigate()

  useEffect(() => {
    adminAPI.overview()
      .then(setStats)
      .catch(() => toast.error('अवलोकन लोड करने में विफल'))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <Spinner />

  return (
    <div className="space-y-8">

      <PageHeader
        title="व्यवस्थापक डैशबोर्ड"
        subtitle="आपके जिले की चुनाव व्यवस्था का अवलोकन"
      />

      {/* ── Stat cards ── */}
      <div className="grid grid-cols-2 xl:grid-cols-4 gap-4">
        {STATS.map(({ key, label, bg, Icon, iconColor }) => (
          <div
            key={key}
            className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-2xl p-5"
          >
            <div
              className="w-10 h-10 rounded-xl flex items-center justify-center mb-3"
              style={{ background: bg }}
            >
              <Icon size={20} className={iconColor} />
            </div>
            <p className="text-[12px] uppercase tracking-wide text-[#7a6a50] mb-1">
              {label}
            </p>
            <p className="text-[28px] font-medium text-[#2c2416]">
              {stats?.[key] ?? '—'}
            </p>
          </div>
        ))}
      </div>

      {/* ── Big navigation tiles ── */}
      <div>
        <p className="text-[12px] uppercase tracking-widest text-[#7a6a50] font-medium mb-4">
          त्वरित नेविगेशन
        </p>
        <div className="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-5 gap-4">
          {TILES.map(({ href, Icon, label, sub, bg, iconColor }) => (
            <button
              key={href}
              onClick={() => navigate(href)}
              className="flex flex-col items-center gap-3 rounded-2xl py-8 px-4 border border-[#8b734b]/20 bg-[#fdfaf5] hover:bg-[#f0ead8] hover:border-[#8b734b]/40 hover:shadow-sm active:scale-95 transition-all text-center w-full"
            >
              <div
                className="w-20 h-20 rounded-2xl flex items-center justify-center"
                style={{ background: bg }}
              >
                <Icon size={36} className={iconColor} />
              </div>
              <span className="text-[15px] font-medium text-[#2c2416] leading-tight">
                {label}
              </span>
              <span className="text-[12px] text-[#7a6a50]">{sub}</span>
            </button>
          ))}
        </div>
      </div>

    </div>
  )
}