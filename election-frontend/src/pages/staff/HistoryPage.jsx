import { useState, useEffect, useCallback } from 'react';
import apiClient from '../../api/client';

// ── Palette (mirrors Flutter + CSS vars) ──────────────────────────────────────
const STATUS = {
  All:      { label: 'सभी',          emoji: '📋', color: '#8B6914', bg: 'rgba(139,105,20,0.1)',  border: 'rgba(139,105,20,0.3)' },
  Upcoming: { label: ' आगामी',      emoji: '🗓', color: '#1A5276', bg: 'rgba(26,82,118,0.1)',   border: 'rgba(26,82,118,0.3)'  },
  Present:  { label: ' उपस्थित',    emoji: '✅', color: '#2D6A1E', bg: 'rgba(45,106,30,0.1)',   border: 'rgba(45,106,30,0.3)'  },
  Absent:   { label: ' अनुपस्थित',  emoji: '❌', color: '#C0392B', bg: 'rgba(192,57,43,0.1)',   border: 'rgba(192,57,43,0.3)'  },
};

const RANK_COLORS = {
  'SP': '#6A1B9A', 'ASP': '#1565C0', 'DSP': '#1A5276',
  'Inspector': '#2E7D32', 'SI': '#558B2F', 'ASI': '#8B6914',
  'Head Constable': '#B8860B', 'Constable': '#6D4C41',
};

// ── Helpers ───────────────────────────────────────────────────────────────────
function isUpcoming(dateStr) {
  if (!dateStr) return false;
  try { return new Date(dateStr) > new Date(); } catch { return false; }
}

function formatDate(dateStr) {
  if (!dateStr) return 'तारीख अज्ञात';
  try {
    const d = new Date(dateStr);
    const months = ['', 'जन', 'फर', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुलाई', 'अग', 'सित', 'अक्ट', 'नव', 'दिस'];
    return `${d.getDate()} ${months[d.getMonth() + 1]} ${d.getFullYear()}`;
  } catch { return dateStr; }
}

function getStatusConfig(duty) {
  if (isUpcoming(duty.date))             return { key: 'Upcoming', ...STATUS.Upcoming, icon: '⏳', text: 'आगामी' };
  if (!duty.date)                        return { key: 'Unknown',  color: '#AA8844',   bg: 'rgba(170,136,68,0.1)', border: 'rgba(170,136,68,0.3)', icon: '❓', text: 'अज्ञात' };
  if (duty.present)                      return { key: 'Present',  ...STATUS.Present,  icon: '✅', text: 'उपस्थित' };
  return                                        { key: 'Absent',   ...STATUS.Absent,   icon: '❌', text: 'अनुपस्थित' };
}

// ── Summary Chip ──────────────────────────────────────────────────────────────
function SummaryChip({ label, count, color }) {
  return (
    <div className="flex-1 flex flex-col items-center py-2 rounded-xl border"
         style={{ background: `${color}14`, borderColor: `${color}33` }}>
      <span className="font-black text-xl leading-tight" style={{ color }}>{count}</span>
      <span className="text-xs mt-0.5" style={{ color: '#AA8844' }}>{label}</span>
    </div>
  );
}

// ── Hierarchy Breadcrumb ──────────────────────────────────────────────────────
const HIER = [
  { key: 'superZone',     label: 'सुपर जोन', color: '#6A1B9A' },
  { key: 'zone',          label: 'जोन',       color: '#1565C0' },
  { key: 'sector',        label: 'सेक्टर',   color: '#2E7D32' },
  { key: 'gramPanchayat', label: 'ग्रा.प.',   color: '#6D4C41' },
];

function HierarchyRow({ duty }) {
  const items = HIER.filter(h => duty[h.key]);
  if (!items.length) return null;
  return (
    <div className="flex items-center gap-1 overflow-x-auto pb-1 mt-1 scrollbar-none">
      {items.map((h, i) => (
        <span key={h.key} className="flex items-center gap-1 shrink-0">
          {i > 0 && <span className="text-xs" style={{ color: '#AA8844' }}>›</span>}
          <span className="text-xs font-semibold px-2 py-0.5 rounded-md border"
                style={{ color: h.color, background: `${h.color}11`, borderColor: `${h.color}33`, maxWidth: 100, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', display: 'inline-block' }}>
            {duty[h.key]}
          </span>
        </span>
      ))}
    </div>
  );
}

// ── Detail Row ────────────────────────────────────────────────────────────────
function DetailRow({ icon, label, value, color }) {
  if (!value) return null;
  return (
    <div className="flex items-start gap-3 mb-2">
      <div className="w-7 h-7 rounded-lg flex items-center justify-center shrink-0 text-sm"
           style={{ background: `${color}18` }}>
        <span>{icon}</span>
      </div>
      <div className="flex-1 min-w-0">
        <div className="text-xs" style={{ color: '#AA8844' }}>{label}</div>
        <div className="text-sm font-bold truncate" style={{ color: '#4A3000' }}>{value}</div>
      </div>
    </div>
  );
}

// ── Staff Badge ───────────────────────────────────────────────────────────────
function StaffBadge({ staff }) {
  const rc = RANK_COLORS[staff.rank] || '#8B6914';
  return (
    <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-lg border text-xs"
          style={{ background: 'white', borderColor: 'rgba(212,168,67,0.4)' }}>
      <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: rc }} />
      <span className="font-semibold truncate max-w-[80px]" style={{ color: '#4A3000' }}>{staff.name}</span>
      <span style={{ color: rc }}>({staff.rank})</span>
    </span>
  );
}

// ── Duty Card ─────────────────────────────────────────────────────────────────
function DutyCard({ duty }) {
  const [expanded, setExpanded] = useState(false);
  const sc = getStatusConfig(duty);
  const assigned = duty.assignedStaff || [];

  return (
    <div className="rounded-2xl border-[1.5px] mb-3 overflow-hidden transition-shadow duration-200"
         style={{
           background: 'white',
           borderColor: `${sc.color}40`,
           boxShadow: `0 3px 12px ${sc.color}12`,
         }}>

      {/* Header */}
      <button className="w-full text-left px-4 py-3 flex items-center gap-3 focus:outline-none"
              onClick={() => setExpanded(e => !e)}>
        {/* Status circle */}
        <div className="w-11 h-11 rounded-full flex items-center justify-center shrink-0 text-xl border-[1.5px]"
             style={{ background: sc.bg, borderColor: sc.border }}>
          {sc.icon}
        </div>

        {/* Info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1 flex-wrap">
            <span className="text-xs font-black px-2 py-0.5 rounded-md"
                  style={{ color: sc.color, background: sc.bg }}>
              {sc.text}
            </span>
            <span className="text-xs flex items-center gap-1" style={{ color: '#AA8844' }}>
              📅 {formatDate(duty.date)}
            </span>
          </div>
          <div className="font-bold text-sm truncate" style={{ color: '#4A3000' }}>
            {duty.booth || 'बूथ अज्ञात'}
          </div>
        </div>

        {/* Arrow */}
        <span className="shrink-0 text-lg transition-transform duration-200"
              style={{ transform: expanded ? 'rotate(180deg)' : 'rotate(0deg)', color: sc.color }}>
          ⌄
        </span>
      </button>

      {/* Hierarchy */}
      <div className="px-4 pb-2">
        <HierarchyRow duty={duty} />
      </div>

      {/* Expanded detail */}
      {expanded && (
        <div className="mx-3 mb-3 p-3 rounded-xl border"
             style={{ background: '#FDF6E3', borderColor: 'rgba(212,168,67,0.3)' }}>
          <DetailRow icon="📍" label="मतदान केंद्र"   value={duty.booth}         color="#C0392B" />
          <DetailRow icon="🏛"  label="ग्राम पंचायत" value={duty.gramPanchayat} color="#6D4C41" />
          <DetailRow icon="🗂"  label="सेक्टर"        value={duty.sector}        color="#2E7D32" />
          <DetailRow icon="🔷" label="जोन"            value={duty.zone}          color="#1565C0" />
          <DetailRow icon="🏔"  label="सुपर जोन"      value={duty.superZone}     color="#6A1B9A" />
          <DetailRow icon="🚌" label="बस संख्या"      value={duty.busNo}         color="#B8860B" />
          <DetailRow icon="🏠"  label="पता"           value={duty.address}       color="#AA8844" />
          <DetailRow icon="🏫" label="थाना"           value={duty.thana}         color="#AA8844" />
          <DetailRow icon="📋" label="केंद्र प्रकार" value={duty.centerType}    color="#1A5276" />
          <DetailRow icon="🏙"  label="जिला"          value={duty.district}      color="#4A3000" />
          <DetailRow icon="🧩" label="ब्लॉक"          value={duty.block}         color="#4A3000" />
          <DetailRow icon="🏢" label="जोन मुख्यालय"  value={duty.zoneHq}        color="#1565C0" />

          {assigned.length > 0 && (
            <>
              <div className="border-t my-2" style={{ borderColor: 'rgba(212,168,67,0.3)' }} />
              <div className="text-xs font-bold mb-2 flex items-center gap-1" style={{ color: '#AA8844' }}>
                👥 इस बूथ पर तैनात सभी स्टाफ
              </div>
              <div className="flex flex-wrap gap-1.5">
                {assigned.map((s, i) => <StaffBadge key={i} staff={s} />)}
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}

// ── Skeleton ──────────────────────────────────────────────────────────────────
function Skeleton() {
  return (
    <div className="space-y-3 p-3">
      {[1, 2, 3, 4].map(i => (
        <div key={i} className="rounded-2xl border p-4 space-y-3"
             style={{ borderColor: 'rgba(212,168,67,0.3)', background: 'white' }}>
          <div className="flex gap-3 items-center">
            <div className="w-11 h-11 rounded-full shimmer" />
            <div className="flex-1 space-y-2">
              <div className="h-3 w-24 rounded shimmer" />
              <div className="h-4 w-40 rounded shimmer" />
            </div>
          </div>
          <div className="flex gap-2">
            <div className="h-5 w-16 rounded shimmer" />
            <div className="h-5 w-20 rounded shimmer" />
          </div>
        </div>
      ))}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN PAGE
// ══════════════════════════════════════════════════════════════════════════════
export default function DutyHistoryPage() {
  const [duties, setDuties]       = useState([]);
  const [loading, setLoading]     = useState(true);
  const [error, setError]         = useState(null);
  const [filter, setFilter]       = useState('All');

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiClient.get('/staff/history');
      // apiClient interceptor already returns res.data; handle both shapes
      const list = Array.isArray(data) ? data : (data?.data ?? []);
      setDuties(list);
    } catch (e) {
      setError(e.message || 'कुछ गड़बड़ हो गई');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  // Filtered list
  const filtered = (() => {
    switch (filter) {
      case 'Present':  return duties.filter(d => d.present === true);
      case 'Absent':   return duties.filter(d => d.present === false && d.date);
      case 'Upcoming': return duties.filter(d => isUpcoming(d.date));
      default:         return duties;
    }
  })();

  // Stats
  const stats = {
    total:    duties.length,
    present:  duties.filter(d => d.present === true).length,
    absent:   duties.filter(d => d.present === false && d.date).length,
    upcoming: duties.filter(d => isUpcoming(d.date)).length,
  };

  return (
    <div className="min-h-screen" style={{ background: '#FDF6E3', fontFamily: "'Tiro Devanagari Hindi', Georgia, serif" }}>

      {/* AppBar */}
      <div className="sticky top-0 z-20 flex items-center gap-3 px-4 py-3"
           style={{ background: '#4A3000', boxShadow: '0 2px 12px rgba(0,0,0,0.25)' }}>
        <button onClick={() => window.history.back()}
                className="w-8 h-8 flex items-center justify-center rounded-lg text-white opacity-80 hover:opacity-100 transition-opacity">
          ‹
        </button>
        <div className="flex-1">
          <div className="text-white font-black text-base leading-tight">ड्यूटी इतिहास</div>
          <div className="text-xs" style={{ color: 'rgba(255,255,255,0.5)' }}>Duty History</div>
        </div>
        <button onClick={load}
                className="w-8 h-8 flex items-center justify-center rounded-lg text-white opacity-80 hover:opacity-100 transition-opacity hover:bg-white/10"
                title="Refresh">
          <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
        </button>
      </div>

      {/* Filter chips */}
      <div className="sticky top-[57px] z-10 flex gap-2 px-3 py-2.5 overflow-x-auto scrollbar-none"
           style={{ background: '#F5E6C8', borderBottom: '1px solid rgba(212,168,67,0.3)' }}>
        {Object.entries(STATUS).map(([key, cfg]) => {
          const isSel = filter === key;
          return (
            <button key={key}
                    onClick={() => setFilter(key)}
                    className="shrink-0 px-3 py-1.5 rounded-full text-xs font-bold border transition-all duration-150"
                    style={{
                      background:   isSel ? cfg.color : 'white',
                      borderColor:  isSel ? cfg.color : 'rgba(212,168,67,0.5)',
                      color:        isSel ? 'white'   : '#4A3000',
                      boxShadow:    isSel ? `0 2px 8px ${cfg.color}40` : 'none',
                    }}>
              {cfg.label}
            </button>
          );
        })}
      </div>

      {/* Summary row */}
      {!loading && !error && (
        <div className="flex gap-2 px-3 py-2.5" style={{ background: '#FDF6E3', borderBottom: '1px solid rgba(212,168,67,0.15)' }}>
          <SummaryChip label="कुल"        count={stats.total}    color="#8B6914" />
          <SummaryChip label="उपस्थित"   count={stats.present}  color="#2D6A1E" />
          <SummaryChip label="अनुपस्थित" count={stats.absent}   color="#C0392B" />
          <SummaryChip label="आगामी"     count={stats.upcoming} color="#1A5276" />
        </div>
      )}

      {/* Body */}
      <div className="pb-16">
        {loading ? (
          <Skeleton />
        ) : error ? (
          <div className="flex flex-col items-center justify-center px-8 py-16 text-center">
            <div className="text-5xl mb-4">⚠️</div>
            <div className="font-bold text-base mb-1" style={{ color: '#4A3000' }}>डेटा लोड नहीं हो सका</div>
            <div className="text-sm mb-6" style={{ color: '#AA8844' }}>{error}</div>
            <button onClick={load}
                    className="btn-primary flex items-center gap-2 px-5 py-2.5 rounded-xl font-bold text-sm text-white"
                    style={{ background: '#8B6914', boxShadow: '0 4px 12px rgba(139,105,20,0.3)' }}>
              🔄 दोबारा कोशिश
            </button>
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center px-10 py-16 text-center">
            <div className="text-5xl mb-4 opacity-40">📋</div>
            <div className="text-sm" style={{ color: '#AA8844' }}>
              {filter === 'All' ? 'कोई ड्यूटी रिकॉर्ड नहीं' : 'इस फ़िल्टर में कोई रिकॉर्ड नहीं'}
            </div>
          </div>
        ) : (
          <div className="p-3">
            {filtered.map((d, i) => (
              <DutyCard key={d.dutyId ?? i} duty={d} />
            ))}
          </div>
        )}
      </div>

      {/* Shimmer keyframe */}
      <style>{`
        @keyframes shimmer {
          0%   { background-position: -468px 0; }
          100% { background-position:  468px 0; }
        }
        .shimmer {
          background: linear-gradient(to right, #F5E6C8 8%, #FDF6E3 18%, #F5E6C8 33%);
          background-size: 800px 104px;
          animation: shimmer 1.4s linear infinite;
        }
        .scrollbar-none::-webkit-scrollbar { display: none; }
        .scrollbar-none { -ms-overflow-style: none; scrollbar-width: none; }
      `}</style>
    </div>
  );
}