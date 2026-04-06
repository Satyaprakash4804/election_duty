import { useEffect, useState, useCallback } from 'react'
import { RefreshCw, Activity } from 'lucide-react'
import { masterAPI } from '../../services/api'
import { PageHeader, Spinner, EmptyState } from '../../components/ui'
import toast from 'react-hot-toast'

const LEVELS = ['ALL', 'INFO', 'WARN', 'ERROR']
const LIMITS = [50, 100, 200, 500]

const levelStyle = {
  INFO:  'bg-[#e6eef8] text-[#1a3d6e]',
  WARN:  'bg-[#faebd7] text-[#7a4a0a]',
  ERROR: 'bg-[#f5e8e8] text-[#7a2020]',
}

export default function MasterLogs() {
  const [logs, setLogs]       = useState([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter]   = useState('ALL')
  const [limit, setLimit]     = useState(100)

  const load = useCallback(() => {
    setLoading(true)
    const params = new URLSearchParams()
    if (filter !== 'ALL') params.set('level', filter)
    params.set('limit', limit)
    masterAPI.getLogs(`?${params.toString()}`)
      .then(setLogs)
      .catch(() => toast.error('Failed to load logs'))
      .finally(() => setLoading(false))
  }, [filter, limit])

  useEffect(() => { load() }, [load])

  if (loading) return <Spinner />

  return (
    <div>
      <PageHeader
        title="System Logs"
        subtitle={`${logs.length} entries`}
        action={
          <button
            onClick={load}
            className="inline-flex items-center gap-2 bg-[#f0ead8] hover:bg-[#e8e0cc] text-[#7a6a50] border border-[#8b734b]/20 text-[13px] font-medium px-3.5 py-2 rounded-lg transition-colors"
          >
            <RefreshCw size={13} /> Refresh
          </button>
        }
      />

      {/* Filters row */}
      <div className="flex flex-wrap items-center gap-2 mb-5">
        {/* Level filters */}
        {LEVELS.map((l) => (
          <button
            key={l}
            onClick={() => setFilter(l)}
            className={`px-3.5 py-1.5 rounded-full text-[12px] font-medium border transition-all ${
              filter === l
                ? 'bg-[#2c2416] text-white border-[#2c2416]'
                : 'bg-[#fdfaf5] text-[#7a6a50] border-[#8b734b]/20 hover:border-[#8b734b]/40 hover:text-[#2c2416]'
            }`}
          >
            {l}
          </button>
        ))}

        {/* Limit selector */}
        <select
          value={limit}
          onChange={(e) => setLimit(Number(e.target.value))}
          className="ml-auto text-[12px] border border-[#8b734b]/20 rounded-full px-3 py-1.5 bg-[#fdfaf5] text-[#7a6a50] focus:outline-none focus:ring-1 focus:ring-[#8b734b]/40"
        >
          {LIMITS.map((n) => (
            <option key={n} value={n}>Last {n}</option>
          ))}
        </select>
      </div>

      {logs.length === 0 ? (
        <EmptyState message="No logs found" icon={Activity} />
      ) : (
        <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl overflow-hidden">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="bg-[#f0ead8]">
                {['Level', 'Module', 'Message', 'Time'].map((h) => (
                  <th
                    key={h}
                    className="px-4 py-2.5 text-left text-[11px] font-medium text-[#7a6a50] uppercase tracking-wide border-b border-[#8b734b]/15"
                  >
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {logs.map((l, i) => (
                <tr key={l.id ?? i} className="hover:bg-[#f5f0e8] transition-colors border-b border-[#8b734b]/10 last:border-0">
                  <td className="px-4 py-2.5">
                    <span className={`inline-block text-[10px] font-medium px-2 py-0.5 rounded-full ${levelStyle[l.level] || 'bg-[#f0ead8] text-[#7a6a50]'}`}>
                      {l.level}
                    </span>
                  </td>
                  <td className="px-4 py-2.5 font-mono text-[11px] text-[#a89878]">{l.module}</td>
                  <td className="px-4 py-2.5 text-[#2c2416]">{l.message}</td>
                  <td className="px-4 py-2.5 font-mono text-[11px] text-[#a89878] whitespace-nowrap">
                    {l.time ? new Date(l.time).toLocaleString('en-IN') : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}