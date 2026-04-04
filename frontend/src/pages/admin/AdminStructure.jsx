import { useEffect, useState, useCallback } from 'react'
import {
  Plus, Trash2, Building2, Map as MapIcon, Grid3X3, Landmark, MapPin,
  ChevronLeft, ChevronRight, Languages, RefreshCw, Filter,
  X, Check, AlertTriangle, BookOpen, ChevronDown, Search, UserPlus, User
} from 'lucide-react'
import { adminAPI } from '../../services/api'
import toast from 'react-hot-toast'
import { useMap } from 'react-leaflet'
import { GeoSearchControl, OpenStreetMapProvider } from 'leaflet-geosearch'


// ══════════════════════════════════════════════════════════════════════════════
//  CONSTANTS & CONFIG
// ══════════════════════════════════════════════════════════════════════════════

import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet'
import L from 'leaflet'


// Fix marker icon issue
delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
})

// Click handler
function LocationMarker({ setLatLng }) {
  const [position, setPosition] = useState(null)

  useMapEvents({
    click(e) {
      const { lat, lng } = e.latlng
      setPosition(e.latlng)
      setLatLng(lat, lng)
    },
  })

  return position ? <Marker position={position} /> : null
}


const PAGE_SIZE = 10

const TABS = [
  { key: 'sz',     label: 'सुपर जोन',     icon: Building2, color: '#8b6914', bg: '#fdf5e6', light: '#fef9ee' },
  { key: 'zone',   label: 'जोन',          icon: MapIcon,       color: '#2d6a4f', bg: '#f0f7eb', light: '#f7fbf5' },
  { key: 'sector', label: 'सेक्टर',        icon: Grid3X3,   color: '#1a3d6e', bg: '#e8f0fb', light: '#f2f6fd' },
  { key: 'gp',     label: 'ग्राम पंचायत', icon: Landmark,  color: '#6b2fa0', bg: '#f3ebfb', light: '#f9f4fd' },
  { key: 'sthal',  label: 'मतदान स्थल',   icon: MapPin,    color: '#9b2226', bg: '#fbeaea', light: '#fdf5f5' },
  { key: 'booth',  label: 'बूथ',           icon: BookOpen,  color: '#0f5132', bg: '#e8f5ef', light: '#f3fbf6' },
  { key: 'search', label: 'खोज',          icon: Search,    color: '#374151', bg: '#f3f4f6', light: '#f9fafb' },
]

const FIELDS = {
  sz: [
    { key: 'name',     label: 'सुपर जोन का नाम', required: true, half: false },
    { key: 'district', label: 'जिला',             required: false },
    { key: 'block',    label: 'ब्लॉक',            required: false },
  ],
  zone: [
    { key: 'name',      label: 'जोन का नाम',    required: true },
    { key: 'hqAddress', label: 'मुख्यालय पता', required: false },
  ],
  sector: [
    { key: 'name', label: 'सेक्टर का नाम', required: true },
  ],
  gp: [
    { key: 'name',    label: 'ग्राम पंचायत का नाम', required: true },
    { key: 'address', label: 'पता',                  required: false },
  ],
  sthal: [
    { key: 'name',       label: 'मतदान स्थल का नाम',   required: true  },
    { key: 'address',    label: 'पता',                   required: false },
    { key: 'thana',      label: 'थाना',                  required: false },
    { key: 'centerType', label: 'केंद्र प्रकार (A/B/C)', required: false, placeholder: 'C' },
    { key: 'busNo',      label: 'बस संख्या',             required: false },
    { key: 'latitude',   label: 'अक्षांश',              required: false, type: 'number' },
    { key: 'longitude',  label: 'देशांतर',              required: false, type: 'number' },
  ],
  booth: [
    { key: 'roomNumber', label: 'कक्ष संख्या', required: true },
  ],
}

// Officer fields config per tab
const OFFICER_CONFIG = {
  sz:     { table: 'kshetra_officers',  label: 'क्षेत्र अधिकारी' },
  zone:   { table: 'zonal_officers',   label: 'ज़ोनल अधिकारी' },
  sector: { table: 'sector_officers',  label: 'सेक्टर अधिकारी' },
}

const COLUMNS = {
  sz:     [{ key: 'name', label: 'नाम' }, { key: 'district', label: 'जिला' }, { key: 'block', label: 'ब्लॉक' }, { key: 'zoneCount', label: 'जोन', badge: true }],
  zone:   [{ key: 'name', label: 'नाम' }, { key: 'hqAddress', label: 'मुख्यालय पता' }, { key: 'sectorCount', label: 'सेक्टर', badge: true }],
  sector: [{ key: 'name', label: 'नाम' }, { key: 'gpCount', label: 'ग्राम पंचायत', badge: true }],
  gp:     [{ key: 'name', label: 'नाम' }, { key: 'address', label: 'पता' }, { key: 'centerCount', label: 'केंद्र', badge: true }],
  sthal:  [{ key: 'name', label: 'नाम' }, { key: 'address', label: 'पता' }, { key: 'thana', label: 'थाना' }, { key: 'centerType', label: 'प्रकार', type: 'tag' }, { key: 'busNo', label: 'बस नं' }, { key: 'dutyCount', label: 'ड्यूटी', badge: true }],
  booth:  [{ key: 'roomNumber', label: 'कक्ष संख्या' }],
}

// ══════════════════════════════════════════════════════════════════════════════
//  TRANSLATION ENGINE
// ══════════════════════════════════════════════════════════════════════════════

const isHindi = s => Boolean(s && /[\u0900-\u097F]/.test(s))
const txCache = new Map()

async function translateBatch(texts) {
  const pending = [...new Set(texts.filter(t => t && t.trim() && !isHindi(t) && !txCache.has(t)))]
  if (!pending.length) return false
  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1000,
        messages: [{
          role: 'user',
          content: `Translate these Indian election/administrative place names to Hindi (Devanagari script). Return ONLY valid JSON with original text as key and Hindi as value. No explanation or markdown.\n${JSON.stringify(pending)}`
        }]
      })
    })
    const d = await res.json()
    const raw = (d.content?.[0]?.text || '{}').replace(/```json|```/g, '').trim()
    Object.entries(JSON.parse(raw)).forEach(([k, v]) => txCache.set(k, v))
    return true
  } catch { return false }
}

const tx = s => {
  if (!s) return ''
  if (isHindi(s)) return s
  return txCache.get(s) || s
}

// ══════════════════════════════════════════════════════════════════════════════
//  OFFICER FORM COMPONENT
// ══════════════════════════════════════════════════════════════════════════════

const EMPTY_OFFICER = { name: '', pno: '', mobile: '', rank: '', userId: null }

function OfficerForm({ officers, onChange, color, bg, light, availableStaff = [] }) {
  const addOfficer = () => onChange([...officers, { ...EMPTY_OFFICER }])
  const removeOfficer = idx => onChange(officers.filter((_, i) => i !== idx))
  const updateOfficer = (idx, field, val) => {
    const updated = officers.map((o, i) => i === idx ? { ...o, [field]: val } : o)
    onChange(updated)
  }

  // When selecting from staff dropdown, autofill fields
  const selectStaff = (idx, userId) => {
    const staff = availableStaff.find(s => String(s.id) === String(userId))
    if (staff) {
      const updated = officers.map((o, i) => i === idx ? {
        ...o,
        userId: staff.id,
        name: staff.name || '',
        pno: staff.pno || '',
        mobile: staff.mobile || '',
        rank: staff.rank || '',
      } : o)
      onChange(updated)
    } else {
      updateOfficer(idx, 'userId', null)
    }
  }

  return (
    <div className="mt-4 border-t pt-4" style={{ borderColor: '#e8d9c0' }}>
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <div className="w-5 h-5 rounded flex items-center justify-center" style={{ background: bg }}>
            <User size={11} style={{ color }} />
          </div>
          <span className="text-[12px] font-semibold text-[#6b5c42] uppercase tracking-wide">अधिकारी जानकारी</span>
        </div>
        <button
          type="button"
          onClick={addOfficer}
          className="flex items-center gap-1 text-[11px] font-medium px-2.5 py-1.5 rounded-lg transition-colors"
          style={{ background: bg, color }}
        >
          <UserPlus size={11} /> अधिकारी जोड़ें
        </button>
      </div>

      {officers.length === 0 && (
        <p className="text-[12px] text-[#a89878] text-center py-3 rounded-lg" style={{ background: light }}>
          कोई अधिकारी नहीं — ऊपर "अधिकारी जोड़ें" दबाएं
        </p>
      )}

      <div className="space-y-3">
        {officers.map((officer, idx) => (
          <div key={idx} className="rounded-xl border p-3 relative" style={{ borderColor: '#e8d9c0', background: light }}>
            <button
              type="button"
              onClick={() => removeOfficer(idx)}
              className="absolute top-2.5 right-2.5 w-6 h-6 rounded flex items-center justify-center text-[#a89878] hover:bg-[#fbeaea] hover:text-[#7a2020] transition-all"
            >
              <X size={11} />
            </button>

            <p className="text-[10px] font-bold text-[#a89878] uppercase tracking-wider mb-2">
              अधिकारी #{idx + 1}
            </p>

            {/* Staff picker (optional) */}
            {availableStaff.length > 0 && (
              <div className="mb-2">
                <label className="block text-[10px] font-semibold text-[#6b5c42] uppercase tracking-wide mb-1">
                  स्टाफ से चुनें (वैकल्पिक)
                </label>
                <div className="relative">
                  <select
                    value={officer.userId || ''}
                    onChange={e => selectStaff(idx, e.target.value)}
                    className="w-full appearance-none bg-white border border-[#ddd0b8] rounded-lg px-2.5 py-2 text-[12px] text-[#2c2416] focus:outline-none pr-6"
                    onFocus={e => { e.target.style.borderColor = color; e.target.style.boxShadow = `0 0 0 2px ${color}20` }}
                    onBlur={e => { e.target.style.borderColor = '#ddd0b8'; e.target.style.boxShadow = 'none' }}
                  >
                    <option value="">— मैन्युअल दर्ज करें —</option>
                    {availableStaff.map(s => (
                      <option key={s.id} value={s.id}>{s.name} ({s.pno})</option>
                    ))}
                  </select>
                  <ChevronDown size={11} className="absolute right-2 top-1/2 -translate-y-1/2 text-[#9a8870] pointer-events-none" />
                </div>
              </div>
            )}

            <div className="grid grid-cols-2 gap-2">
              {[
                { key: 'name',   label: 'नाम',      req: true },
                { key: 'rank',   label: 'पद/रैंक',  req: false },
                { key: 'pno',    label: 'PNO',       req: false },
                { key: 'mobile', label: 'मोबाइल',   req: false },
              ].map(f => (
                <div key={f.key}>
                  <label className="block text-[10px] font-semibold text-[#6b5c42] uppercase tracking-wide mb-1">
                    {f.label}{f.req && <span className="text-red-500 ml-0.5">*</span>}
                  </label>
                  <input
                    type="text"
                    className="w-full bg-white border border-[#ddd0b8] rounded-lg px-2.5 py-2 text-[12px] text-[#2c2416] focus:outline-none transition-all"
                    value={officer[f.key] || ''}
                    onChange={e => updateOfficer(idx, f.key, e.target.value)}
                    onFocus={e => { e.target.style.borderColor = color; e.target.style.boxShadow = `0 0 0 2px ${color}20` }}
                    onBlur={e => { e.target.style.borderColor = '#ddd0b8'; e.target.style.boxShadow = 'none' }}
                  />
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

// ══════════════════════════════════════════════════════════════════════════════
//  SEARCH TAB COMPONENT
// ══════════════════════════════════════════════════════════════════════════════

function SearchTab({ szList, zoneMap, sectMap, gpMap, sthalMap, boothMap }) {
  const [query, setQuery] = useState('')
  const [scope, setScope] = useState('all') // all | sz | zone | sector | gp | sthal | booth
  const [results, setResults] = useState([])

  const SCOPE_OPTIONS = [
    { key: 'all',    label: 'सभी' },
    { key: 'sz',     label: 'सुपर जोन',     color: '#8b6914' },
    { key: 'zone',   label: 'जोन',          color: '#2d6a4f' },
    { key: 'sector', label: 'सेक्टर',        color: '#1a3d6e' },
    { key: 'gp',     label: 'ग्राम पंचायत', color: '#6b2fa0' },
    { key: 'sthal',  label: 'मतदान स्थल',   color: '#9b2226' },
    { key: 'booth',  label: 'बूथ',           color: '#0f5132' },
  ]

  useEffect(() => {
    if (!query.trim()) { setResults([]); return }
    const q = query.toLowerCase()
    const found = []

    const match = str => str && str.toLowerCase().includes(q)

    if (scope === 'all' || scope === 'sz') {
      szList.forEach(item => {
        if (match(item.name) || match(item.district) || match(item.block)) {
          found.push({ type: 'sz', label: 'सुपर जोन', color: '#8b6914', bg: '#fdf5e6', item, display: tx(item.name) || item.name })
        }
      })
    }

    if (scope === 'all' || scope === 'zone') {
      Object.values(zoneMap).flat().forEach(item => {
        if (match(item.name) || match(item.hqAddress)) {
          found.push({ type: 'zone', label: 'जोन', color: '#2d6a4f', bg: '#f0f7eb', item, display: tx(item.name) || item.name })
        }
      })
    }

    if (scope === 'all' || scope === 'sector') {
      Object.values(sectMap).flat().forEach(item => {
        if (match(item.name)) {
          found.push({ type: 'sector', label: 'सेक्टर', color: '#1a3d6e', bg: '#e8f0fb', item, display: tx(item.name) || item.name })
        }
      })
    }

    if (scope === 'all' || scope === 'gp') {
      Object.values(gpMap).flat().forEach(item => {
        if (match(item.name) || match(item.address)) {
          found.push({ type: 'gp', label: 'ग्राम पंचायत', color: '#6b2fa0', bg: '#f3ebfb', item, display: tx(item.name) || item.name })
        }
      })
    }

    if (scope === 'all' || scope === 'sthal') {
      Object.values(sthalMap).flat().forEach(item => {
        if (match(item.name) || match(item.address) || match(item.thana)) {
          found.push({ type: 'sthal', label: 'मतदान स्थल', color: '#9b2226', bg: '#fbeaea', item, display: tx(item.name) || item.name })
        }
      })
    }

    if (scope === 'all' || scope === 'booth') {
      Object.values(boothMap).flat().forEach(item => {
        if (match(item.roomNumber)) {
          found.push({ type: 'booth', label: 'बूथ', color: '#0f5132', bg: '#e8f5ef', item, display: item.roomNumber })
        }
      })
    }

    setResults(found.slice(0, 50))
  }, [query, scope, szList, zoneMap, sectMap, gpMap, sthalMap, boothMap])

  return (
    <div className="space-y-4">
      {/* Search Box */}
      <div className="bg-white rounded-2xl border border-[#e8d9c0] shadow-sm overflow-hidden">
        <div className="p-4 sm:p-5">
          <div className="relative mb-3">
            <Search size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-[#a89878]" />
            <input
              type="text"
              className="w-full bg-[#faf6ef] border border-[#ddd0b8] rounded-xl pl-10 pr-4 py-3 text-[14px] text-[#2c2416] placeholder-[#b8a888] focus:outline-none transition-all"
              placeholder="नाम, पता, थाना आदि खोजें..."
              value={query}
              onChange={e => setQuery(e.target.value)}
              onFocus={e => { e.target.style.borderColor = '#374151'; e.target.style.boxShadow = '0 0 0 3px #37415120' }}
              onBlur={e => { e.target.style.borderColor = '#ddd0b8'; e.target.style.boxShadow = 'none' }}
              autoFocus
            />
            {query && (
              <button
                onClick={() => setQuery('')}
                className="absolute right-3 top-1/2 -translate-y-1/2 w-6 h-6 rounded-full flex items-center justify-center text-[#a89878] hover:bg-[#f0e8d8] transition-colors"
              >
                <X size={12} />
              </button>
            )}
          </div>

          {/* Scope filters */}
          <div className="flex flex-wrap gap-2">
            {SCOPE_OPTIONS.map(opt => (
              <button
                key={opt.key}
                onClick={() => setScope(opt.key)}
                className="text-[11px] font-semibold px-3 py-1.5 rounded-full transition-all border"
                style={scope === opt.key
                  ? { background: opt.color || '#374151', color: 'white', borderColor: opt.color || '#374151' }
                  : { background: '#faf6ef', color: '#7a6a50', borderColor: '#ddd0b8' }
                }
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Results */}
      {query.trim() && (
        <div className="bg-white rounded-2xl border border-[#e8d9c0] shadow-sm overflow-hidden">
          <div className="flex items-center gap-2 px-4 sm:px-5 py-3 border-b border-[#f0e8d8]">
            <span className="text-[13px] font-semibold text-[#2c2416]">खोज परिणाम</span>
            <span className="text-[11px] font-medium px-2 py-0.5 rounded-full bg-[#f3f4f6] text-[#374151]">
              {results.length} मिले
            </span>
          </div>

          {results.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 text-center">
              <div className="w-12 h-12 rounded-2xl bg-[#f3f4f6] flex items-center justify-center mb-3">
                <Search size={20} className="text-[#9ca3af]" />
              </div>
              <p className="text-[#7a6a50] text-sm font-medium">"{query}" के लिए कोई परिणाम नहीं</p>
              <p className="text-[#a89878] text-xs mt-1">अलग कीवर्ड या श्रेणी आज़माएं</p>
            </div>
          ) : (
            <div className="divide-y divide-[#f5f0e8]">
              {results.map((r, idx) => (
                <div key={idx} className="flex items-center gap-3 px-4 sm:px-5 py-3.5 hover:bg-[#faf6ef] transition-colors">
                  <span
                    className="text-[10px] font-bold px-2 py-1 rounded-md flex-shrink-0 whitespace-nowrap"
                    style={{ background: r.bg, color: r.color }}
                  >
                    {r.label}
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className="text-[13px] font-semibold text-[#2c2416] truncate">{r.display}</p>
                    {r.item.address && (
                      <p className="text-[11px] text-[#a89878] truncate mt-0.5">{tx(r.item.address) || r.item.address}</p>
                    )}
                    {r.item.thana && (
                      <p className="text-[11px] text-[#a89878] truncate mt-0.5">थाना: {r.item.thana}</p>
                    )}
                  </div>
                  {r.item.district && (
                    <span className="text-[11px] text-[#a89878] flex-shrink-0">{r.item.district}</span>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {!query.trim() && (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <div className="w-16 h-16 rounded-2xl bg-[#f3f4f6] flex items-center justify-center mb-4">
            <Search size={28} className="text-[#9ca3af]" />
          </div>
          <p className="text-[#7a6a50] text-sm font-medium">पूरे चुनाव ढांचे में खोजें</p>
          <p className="text-[#a89878] text-xs mt-1">
            सुपर जोन से लेकर बूथ तक — सभी में एक साथ खोज
          </p>
        </div>
      )}
    </div>
  )
}

// ══════════════════════════════════════════════════════════════════════════════
//  SUB-COMPONENTS
// ══════════════════════════════════════════════════════════════════════════════

function HindiSelect({ label, value, onChange, options, disabled, color, placeholder }) {
  return (
    <div className="flex flex-col gap-1">
      <label className="text-[11px] font-semibold text-[#6b5c42] uppercase tracking-wide">{label}</label>
      <div className="relative">
        <select
          value={value}
          onChange={e => onChange(Number(e.target.value))}
          disabled={disabled || !options.length}
          className="w-full appearance-none bg-[#faf6ef] border border-[#ddd0b8] rounded-lg px-3 py-2.5 text-[13px] text-[#2c2416] focus:outline-none focus:ring-2 disabled:opacity-50 disabled:cursor-not-allowed pr-8 transition-all"
          onFocus={e => { e.target.style.borderColor = color; e.target.style.boxShadow = `0 0 0 2px ${color}25` }}
          onBlur={e => { e.target.style.borderColor = '#ddd0b8'; e.target.style.boxShadow = 'none' }}
        >
          <option value="">— {placeholder || label} चुनें —</option>
          {options.map(o => (
            <option key={o.id} value={o.id}>{tx(o.name) || o.name}</option>
          ))}
        </select>
        <ChevronDown size={13} className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[#9a8870] pointer-events-none" />
      </div>
    </div>
  )
}

function Spinner({ color }) {
  return (
    <div
      className="w-5 h-5 rounded-full border-2 border-t-transparent animate-spin"
      style={{ borderColor: `${color}40`, borderTopColor: color }}
    />
  )
}

function EmptyState({ tab }) {
  const Icon = tab.icon
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center">
      <div className="w-16 h-16 rounded-2xl flex items-center justify-center mb-4" style={{ background: tab.bg }}>
        <Icon size={28} style={{ color: tab.color, opacity: 0.5 }} />
      </div>
      <p className="text-[#7a6a50] text-sm font-medium">कोई {tab.label} नहीं मिला</p>
      <p className="text-[#a89878] text-xs mt-1">ऊपर "+ जोड़ें" बटन से नया जोड़ें</p>
    </div>
  )
}

function NeedsParentState({ message }) {
  return (
    <div className="flex flex-col items-center justify-center py-16">
      <div className="w-12 h-12 rounded-full bg-[#fef3e2] flex items-center justify-center mb-3">
        <Filter size={20} className="text-[#c97b2a]" />
      </div>
      <p className="text-[#7a6a50] text-sm">{message}</p>
    </div>
  )
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN COMPONENT
// ══════════════════════════════════════════════════════════════════════════════

export default function AdminStructure() {
  const [activeTab,  setActiveTab]  = useState('sz')

  // Data keyed by parent ID; szList is flat
  const [szList,    setSzList]    = useState([])
  const [zoneMap,   setZoneMap]   = useState({})
  const [sectMap,   setSectMap]   = useState({})
  const [gpMap,     setGpMap]     = useState({})
  const [sthalMap,  setSthalMap]  = useState({})
  const [boothMap,  setBoothMap]  = useState({})

  // Selected filters (cascade)
  const [selSZ,     setSelSZ]     = useState('')
  const [selZone,   setSelZone]   = useState('')
  const [selSect,   setSelSect]   = useState('')
  const [selGP,     setSelGP]     = useState('')
  const [selSthal,  setSelSthal]  = useState('')

  // Pagination per tab
  const [pages, setPages] = useState({ sz: 1, zone: 1, sector: 1, gp: 1, sthal: 1, booth: 1 })

  // UI state
  const [showForm,  setShowForm]  = useState(false)
  const [formVals,  setFormVals]  = useState({})
  const [officers,  setOfficers]  = useState([])      // officer rows in add form
  const [availableStaff, setAvailableStaff] = useState([])  // for officer picker
  const [saving,    setSaving]    = useState(false)
  const [loading,   setLoading]   = useState({ init: true, tab: false })
  const [txState,   setTxState]   = useState({ busy: false, tick: 0 })
  const [confirm,   setConfirm]   = useState(null)
  const [mapRef, setMapRef] = useState(null)

  // ── Initial load ────────────────────────────────────────────────────────────
  useEffect(() => { fetchSZ() }, [])

  // ── Fetch available staff when form opens for SZ/zone/sector ────────────────
  useEffect(() => {
    if (showForm && ['sz', 'zone', 'sector'].includes(activeTab)) {
      adminAPI.getStaff && adminAPI.getStaff().then(d => {
        setAvailableStaff(Array.isArray(d) ? d : [])
      }).catch(() => setAvailableStaff([]))
    }
  }, [showForm, activeTab])

  const fetchSZ = async () => {
    setLoading(l => ({ ...l, init: true }))
    try {
      const d = await adminAPI.getSuperZones()
      const arr = Array.isArray(d) ? d : []
      setSzList(arr)
      autoTranslate(arr)
    } catch { toast.error('सुपर जोन लोड नहीं हो सका') }
    finally { setLoading(l => ({ ...l, init: false })) }
  }

  // ── Auto-translate items ─────────────────────────────────────────────────────
  const autoTranslate = useCallback(async (items) => {
    if (!items?.length) return
    const names = items.flatMap(i => [i.name, i.address, i.hqAddress, i.district, i.block, i.thana].filter(Boolean))
    if (!names.length) return
    setTxState(s => ({ ...s, busy: true }))
    const changed = await translateBatch(names)
    setTxState(s => ({ busy: false, tick: changed ? s.tick + 1 : s.tick }))
  }, [])

  // ── Lazy loaders ─────────────────────────────────────────────────────────────
  const loadZones = useCallback(async (szId, force = false) => {
    if (!szId) return
    if (!force && zoneMap[szId]) return
    setLoading(l => ({ ...l, tab: true }))
    try {
      const d = await adminAPI.getZones(szId)
      const arr = Array.isArray(d) ? d : []
      setZoneMap(p => ({ ...p, [szId]: arr }))
      autoTranslate(arr)
    } catch { toast.error('जोन लोड नहीं हो सका') }
    finally { setLoading(l => ({ ...l, tab: false })) }
  }, [zoneMap, autoTranslate])

  const loadSectors = useCallback(async (zId, force = false) => {
    if (!zId) return
    if (!force && sectMap[zId]) return
    setLoading(l => ({ ...l, tab: true }))
    try {
      const d = await adminAPI.getSectors(zId)
      const arr = Array.isArray(d) ? d : []
      setSectMap(p => ({ ...p, [zId]: arr }))
      autoTranslate(arr)
    } catch { toast.error('सेक्टर लोड नहीं हो सका') }
    finally { setLoading(l => ({ ...l, tab: false })) }
  }, [sectMap, autoTranslate])

  const loadGPs = useCallback(async (sId, force = false) => {
    if (!sId) return
    if (!force && gpMap[sId]) return
    setLoading(l => ({ ...l, tab: true }))
    try {
      const d = await adminAPI.getGPs(sId)
      const arr = Array.isArray(d) ? d : []
      setGpMap(p => ({ ...p, [sId]: arr }))
      autoTranslate(arr)
    } catch { toast.error('ग्राम पंचायत लोड नहीं हो सका') }
    finally { setLoading(l => ({ ...l, tab: false })) }
  }, [gpMap, autoTranslate])

  const loadSthal = useCallback(async (gpId, force = false) => {
    if (!gpId) return
    if (!force && sthalMap[gpId]) return
    setLoading(l => ({ ...l, tab: true }))
    try {
      const d = await adminAPI.getCenters(gpId)
      const arr = Array.isArray(d) ? d : []
      setSthalMap(p => ({ ...p, [gpId]: arr }))
      autoTranslate(arr)
    } catch { toast.error('मतदान स्थल लोड नहीं हो सका') }
    finally { setLoading(l => ({ ...l, tab: false })) }
  }, [sthalMap, autoTranslate])

  const loadBooths = useCallback(async (cId, force = false) => {
    if (!cId) return
    if (!force && boothMap[cId]) return
    setLoading(l => ({ ...l, tab: true }))
    try {
      const d = await adminAPI.getRooms(cId)
      const arr = Array.isArray(d) ? d : []
      setBoothMap(p => ({ ...p, [cId]: arr }))
    } catch { toast.error('बूथ लोड नहीं हो सका') }
    finally { setLoading(l => ({ ...l, tab: false })) }
  }, [boothMap])

  // ── Cascade selection handlers ───────────────────────────────────────────────
  const onSelectSZ = v => {
  const selected = szList.find(s => String(s.id) === String(v))

  if (!selected) return

  setSelSZ(selected.id)   // ✅ ALWAYS STORE ID
  setSelZone('')
  setSelSect('')
  setSelGP('')
  setSelSthal('')

  loadZones(selected.id)
}
  const onSelectZone = v => {
    setSelZone(v); setSelSect(''); setSelGP(''); setSelSthal('')
    if (v) loadSectors(v)
  }
  const onSelectSect = v => {
    setSelSect(v); setSelGP(''); setSelSthal('')
    if (v) loadGPs(v)
  }
  const onSelectGP = v => {
    setSelGP(v); setSelSthal('')
    if (v) loadSthal(v)
  }
  const onSelectSthal = v => {
    setSelSthal(v)
    if (v) loadBooths(v)
  }

  // ── Reset form on tab change ─────────────────────────────────────────────────
  useEffect(() => {
    setShowForm(false)
    setFormVals({})
    setOfficers([])
    setPages(p => ({ ...p, [activeTab]: 1 }))
  }, [activeTab])

  // ── Derive current list ──────────────────────────────────────────────────────
  const getList = () => {
    switch (activeTab) {
      case 'sz':     return szList
      case 'zone':   return selSZ    ? (zoneMap[selSZ]   || []) : null
      case 'sector': return selZone  ? (sectMap[selZone] || []) : null
      case 'gp':     return selSect  ? (gpMap[selSect]   || []) : null
      case 'sthal':  return selGP    ? (sthalMap[selGP]  || []) : null
      case 'booth':  return selSthal ? (boothMap[selSthal] || []) : null
      default: return []
    }
  }

console.log("selSZ:", selSZ)

  const allItems   = getList()
  const curPage    = pages[activeTab] || 1
  const totalPages = allItems ? Math.max(1, Math.ceil(allItems.length / PAGE_SIZE)) : 1
  const pageItems  = allItems ? allItems.slice((curPage - 1) * PAGE_SIZE, curPage * PAGE_SIZE) : []
  const tabObj     = TABS.find(t => t.key === activeTab)

  // ── Parent requirement checks ────────────────────────────────────────────────
  const parentMessages = {
    zone:   'पहले ऊपर से सुपर जोन चुनें',
    sector: 'पहले ऊपर से जोन चुनें',
    gp:     'पहले ऊपर से सेक्टर चुनें',
    sthal:  'पहले ऊपर से ग्राम पंचायत चुनें',
    booth:  'पहले ऊपर से मतदान स्थल चुनें',
  }
  const needsParent = allItems === null

  // ── Has officer section? ─────────────────────────────────────────────────────
  const hasOfficers = ['sz', 'zone', 'sector'].includes(activeTab)

  // ── Form submission ──────────────────────────────────────────────────────────
  const handleAdd = async () => {
    for (const f of FIELDS[activeTab].filter(f => f.required)) {
      if (!formVals[f.key]?.toString().trim()) {
        toast.error(`"${f.label}" आवश्यक है`)
        return
      }
    }

    // Validate officers (name required if officer row exists)
    for (let i = 0; i < officers.length; i++) {
      if (!officers[i].name?.trim()) {
        toast.error(`अधिकारी #${i + 1} का नाम आवश्यक है`)
        return
      }
    }

    const parentCheck = {
      zone: selSZ, sector: selZone, gp: selSect, sthal: selGP, booth: selSthal
    }
    if (activeTab !== 'sz' && !parentCheck[activeTab]) {
      toast.error(parentMessages[activeTab])
      return
    }

    setSaving(true)
    try {
      // Include officers in payload for sz/zone/sector
      const payload = { ...formVals }
      if (hasOfficers && officers.length > 0) {
        payload.officers = officers
      }

      let newItem = null
      if (activeTab === 'sz') {
        const res = await adminAPI.addSuperZone(payload)
        newItem = { id: res?.data?.id ?? res?.id, ...formVals, zoneCount: 0, officers }
        setSzList(p => [...p, newItem])

      } else if (activeTab === 'zone') {
        const res = await adminAPI.addZone(selSZ, payload)
        newItem = { id: res?.data?.id ?? res?.id, ...formVals, sectorCount: 0, officers }
        setZoneMap(p => ({ ...p, [selSZ]: [...(p[selSZ] || []), newItem] }))

      } else if (activeTab === 'sector') {
        const res = await adminAPI.addSector(selZone, payload)
        newItem = { id: res?.data?.id ?? res?.id, ...formVals, gpCount: 0, officers }
        setSectMap(p => ({ ...p, [selZone]: [...(p[selZone] || []), newItem] }))

      } else if (activeTab === 'gp') {
        const res = await adminAPI.addGP(selSect, formVals)
        newItem = { id: res?.data?.id ?? res?.id, ...formVals, centerCount: 0 }
        setGpMap(p => ({ ...p, [selSect]: [...(p[selSect] || []), newItem] }))

      } else if (activeTab === 'sthal') {
        const res = await adminAPI.addCenter(selGP, formVals)
        newItem = { id: res?.data?.id ?? res?.id, ...formVals, dutyCount: 0 }
        setSthalMap(p => ({ ...p, [selGP]: [...(p[selGP] || []), newItem] }))

      } else if (activeTab === 'booth') {
        const res = await adminAPI.addRoom(selSthal, formVals)
        newItem = { id: res?.data?.id ?? res?.id, ...formVals }
        setBoothMap(p => ({ ...p, [selSthal]: [...(p[selSthal] || []), newItem] }))
      }

      if (newItem) autoTranslate([newItem])
      toast.success(`${tabObj.label} सफलतापूर्वक जोड़ा गया ✓`)
      setFormVals({})
      setOfficers([])
      setShowForm(false)
    } catch (e) {
      toast.error(e?.response?.data?.message || 'जोड़ने में समस्या हुई')
    } finally {
      setSaving(false)
    }
  }

  // ── Delete handler ───────────────────────────────────────────────────────────
  const handleDelete = item => {
    setConfirm({
      item,
      action: async () => {
        try {
          if (activeTab === 'sz')     { await adminAPI.deleteSuperZone(item.id); setSzList(p => p.filter(x => x.id !== item.id)) }
          if (activeTab === 'zone')   { await adminAPI.deleteZone(item.id);      setZoneMap(p  => ({ ...p, [selSZ]:    (p[selSZ]    || []).filter(x => x.id !== item.id) })) }
          if (activeTab === 'sector') { await adminAPI.deleteSector(item.id);    setSectMap(p  => ({ ...p, [selZone]:  (p[selZone]  || []).filter(x => x.id !== item.id) })) }
          if (activeTab === 'gp')     { await adminAPI.deleteGP(item.id);        setGpMap(p    => ({ ...p, [selSect]:  (p[selSect]  || []).filter(x => x.id !== item.id) })) }
          if (activeTab === 'sthal')  { await adminAPI.deleteCenter(item.id);    setSthalMap(p => ({ ...p, [selGP]:    (p[selGP]    || []).filter(x => x.id !== item.id) })) }
          if (activeTab === 'booth')  { await adminAPI.deleteRoom(item.id);      setBoothMap(p => ({ ...p, [selSthal]: (p[selSthal] || []).filter(x => x.id !== item.id) })) }
          toast.success('सफलतापूर्वक हटाया गया')
        } catch { toast.error('हटाने में समस्या हुई') }
        setConfirm(null)
      }
    })
  }

  const setField = (k, v) => setFormVals(p => ({ ...p, [k]: v }))
  const setPage  = v => setPages(p => ({ ...p, [activeTab]: v }))
  const TabIcon  = tabObj?.icon

  // ── Refresh current tab ──────────────────────────────────────────────────────
  const handleRefresh = () => {
    if (activeTab === 'sz') { setSzList([]); fetchSZ() }
    else if (activeTab === 'zone'   && selSZ)    loadZones(selSZ, true)
    else if (activeTab === 'sector' && selZone)  loadSectors(selZone, true)
    else if (activeTab === 'gp'     && selSect)  loadGPs(selSect, true)
    else if (activeTab === 'sthal'  && selGP)    loadSthal(selGP, true)
    else if (activeTab === 'booth'  && selSthal) loadBooths(selSthal, true)
  }

  if (loading.init) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <div className="w-10 h-10 border-3 border-[#8b6914] border-t-transparent rounded-full animate-spin mx-auto mb-3" style={{ borderWidth: 3 }} />
          <p className="text-[#7a6a50] text-sm">चुनाव संरचना लोड हो रही है...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#f7f3ec]">

      {/* ━━━━ PAGE HEADER ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <div className="bg-white border-b border-[#e8d9c0] px-4 sm:px-6 lg:px-8 py-4">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 className="text-lg sm:text-xl font-bold text-[#2c2416] leading-tight">
              चुनाव संरचना प्रबंधन
            </h1>
            <p className="text-xs sm:text-sm text-[#7a6a50] mt-0.5 flex flex-wrap items-center gap-1">
              {TABS.filter(t => t.key !== 'search').map((t, i, arr) => (
                <span key={t.key} className="flex items-center gap-1">
                  <span className="font-medium" style={{ color: t.color }}>{t.label}</span>
                  {i < arr.length - 1 && <span className="text-[#c8b898]">→</span>}
                </span>
              ))}
            </p>
          </div>
          {txState.busy && (
            <div className="flex items-center gap-2 text-xs text-[#2d6a4f] bg-[#f0f7eb] border border-[#c3e6cb] px-3 py-1.5 rounded-full self-start sm:self-auto">
              <Languages size={12} className="animate-pulse" />
              हिंदी अनुवाद हो रहा है...
            </div>
          )}
        </div>
      </div>

      {/* ━━━━ TAB BAR ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <div className="bg-white border-b border-[#e8d9c0] px-2 sm:px-6 lg:px-8 sticky top-0 z-10 shadow-sm">
        <div className="flex overflow-x-auto" style={{ scrollbarWidth: 'none' }}>
          {TABS.map(tab => {
            const TIcon = tab.icon
            const active = activeTab === tab.key
            const isSearch = tab.key === 'search'
            return (
              <button
                key={tab.key}
                onClick={() => setActiveTab(tab.key)}
                className="flex items-center gap-1.5 sm:gap-2 px-3 sm:px-5 py-3.5 text-xs sm:text-sm font-medium whitespace-nowrap border-b-[3px] transition-all flex-shrink-0"
                style={{
                  borderColor: active ? tab.color : 'transparent',
                  color: active ? tab.color : '#7a6a50',
                  background: active ? tab.light : 'transparent',
                  marginLeft: isSearch ? 'auto' : 0,
                }}
              >
                <TIcon size={14} />
                <span className="hidden xs:inline sm:inline">{tab.label}</span>
              </button>
            )
          })}
        </div>
      </div>

      {/* ━━━━ CONTENT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      <div className="px-4 sm:px-6 lg:px-8 py-5 max-w-7xl mx-auto space-y-4">

        {/* ── SEARCH TAB ────────────────────────────────────────────────── */}
        {activeTab === 'search' && (
          <SearchTab
            szList={szList}
            zoneMap={zoneMap}
            sectMap={sectMap}
            gpMap={gpMap}
            sthalMap={sthalMap}
            boothMap={boothMap}
          />
        )}

        {activeTab !== 'search' && (
          <>
            {/* ── FILTER / PARENT SELECTOR PANEL ──────────────────────── */}
            {activeTab !== 'sz' && (
              <div className="bg-white rounded-2xl border border-[#e8d9c0] shadow-sm overflow-hidden">
                <div className="flex items-center gap-2 px-4 sm:px-5 py-3 border-b border-[#f0e8d8]">
                  <div className="w-6 h-6 rounded-md flex items-center justify-center" style={{ background: tabObj.bg }}>
                    <Filter size={12} style={{ color: tabObj.color }} />
                  </div>
                  <span className="text-[13px] font-semibold text-[#2c2416]">फ़िल्टर — उच्च स्तर चुनें</span>
                </div>
                <div className="p-4 sm:p-5">
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-3 sm:gap-4">
                    {['zone','sector','gp','sthal','booth'].includes(activeTab) && (
                      <HindiSelect label="सुपर जोन" value={selSZ} onChange={onSelectSZ} options={szList} color={TABS[0].color} />
                    )}
                    {['sector','gp','sthal','booth'].includes(activeTab) && (
                      <HindiSelect label="जोन" value={selZone} onChange={onSelectZone} options={selSZ ? (zoneMap[selSZ] || []) : []} disabled={!selSZ} color={TABS[1].color} placeholder={!selSZ ? 'पहले सुपर जोन चुनें' : 'जोन'} />
                    )}
                    {['gp','sthal','booth'].includes(activeTab) && (
                      <HindiSelect label="सेक्टर" value={selSect} onChange={onSelectSect} options={selZone ? (sectMap[selZone] || []) : []} disabled={!selZone} color={TABS[2].color} placeholder={!selZone ? 'पहले जोन चुनें' : 'सेक्टर'} />
                    )}
                    {['sthal','booth'].includes(activeTab) && (
                      <HindiSelect label="ग्राम पंचायत" value={selGP} onChange={onSelectGP} options={selSect ? (gpMap[selSect] || []) : []} disabled={!selSect} color={TABS[3].color} placeholder={!selSect ? 'पहले सेक्टर चुनें' : 'ग्राम पंचायत'} />
                    )}
                    {activeTab === 'booth' && (
                      <HindiSelect label="मतदान स्थल" value={selSthal} onChange={onSelectSthal} options={selGP ? (sthalMap[selGP] || []) : []} disabled={!selGP} color={TABS[4].color} placeholder={!selGP ? 'पहले GP चुनें' : 'मतदान स्थल'} />
                    )}
                  </div>
                </div>
              </div>
            )}

            {/* ── ADD FORM CARD ────────────────────────────────────────── */}
            <div className="bg-white rounded-2xl border border-[#e8d9c0] shadow-sm overflow-hidden">
              {/* Form toggle header */}
              <div className="flex items-center justify-between px-4 sm:px-5 py-3.5">
                <div className="flex items-center gap-2.5">
                  <div className="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0" style={{ background: tabObj.bg }}>
                    <TabIcon size={14} style={{ color: tabObj.color }} />
                  </div>
                  <div>
                    <span className="text-[13px] font-semibold text-[#2c2416]">
                      नया {tabObj.label} जोड़ें
                    </span>
                    {needsParent && (
                      <span className="ml-2 text-[11px] text-[#c97b2a] bg-[#fef3e2] px-2 py-0.5 rounded-full">
                        ↑ पहले फ़िल्टर चुनें
                      </span>
                    )}
                  </div>
                </div>
                <button
                  onClick={() => { setShowForm(f => !f); if (showForm) { setFormVals({}); setOfficers([]) } }}
                  className="flex items-center gap-1.5 text-[13px] font-medium px-3.5 py-2 rounded-xl transition-all"
                  style={showForm
                    ? { background: '#fbeaea', color: '#7a2020' }
                    : { background: tabObj.color, color: 'white' }
                  }
                >
                  {showForm
                    ? <><X size={13} /> बंद करें</>
                    : <><Plus size={13} /> जोड़ें</>
                  }
                </button>
              </div>

              {/* Form body */}
              {showForm && (
                <div className="border-t border-[#f0e8d8] px-4 sm:px-5 py-4 sm:py-5" style={{ background: tabObj.light }}>
                  {needsParent ? (
                    <div className="flex items-center gap-3 text-sm text-[#7a6a50] py-2">
                      <AlertTriangle size={18} className="text-[#c97b2a] flex-shrink-0" />
                      {parentMessages[activeTab]}
                    </div>
                  ) : (
                    <div>
                      {/* Basic fields */}
                      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4 mb-4">
                        {FIELDS[activeTab].map(field => (
                          <div key={field.key}>
                            <label className="block text-[11px] font-semibold text-[#6b5c42] uppercase tracking-wide mb-1.5">
                              {field.label}
                              {field.required && <span className="text-red-500 ml-1 normal-case">*</span>}
                            </label>
                            <input
                              type={field.type || 'text'}
                              className="w-full bg-white border border-[#ddd0b8] rounded-lg px-3 py-2.5 text-[13px] text-[#2c2416] placeholder-[#b8a888] focus:outline-none transition-all"
                              placeholder={field.placeholder || ''}
                              value={formVals[field.key] || ''}
                              onChange={e => setField(field.key, e.target.value)}
                              onFocus={e => { e.target.style.borderColor = tabObj.color; e.target.style.boxShadow = `0 0 0 3px ${tabObj.color}20` }}
                              onBlur={e => { e.target.style.borderColor = '#ddd0b8'; e.target.style.boxShadow = 'none' }}
                            />
                          </div>
                        ))}
                      </div>

                      {activeTab === 'sthal' && (
                        <div className="mt-4">
                          <label className="block text-[11px] font-semibold mb-2 text-[#6b5c42]">
                            📍 मैप से लोकेशन चुनें
                          </label>

                          <div className="mb-2 flex gap-2">
                            <input
                              type="text"
                              placeholder="🔍 जगह खोजें (Enter दबाएं)"
                              className="flex-1 border px-3 py-2 rounded-lg text-sm"
                              onKeyDown={async (e) => {
                                if (e.key === 'Enter') {
                                  const query = e.target.value

                                  const res = await fetch(
                                    `https://nominatim.openstreetmap.org/search?format=json&q=${query}`
                                  )
                                  const data = await res.json()

                                  if (data && data.length > 0 && mapRef) {
                                    const lat = parseFloat(data[0].lat)
                                    const lon = parseFloat(data[0].lon)

                                    // 🔥 MOVE MAP
                                    mapRef.setView([lat, lon], 15)
                                  }
                                }
                              }}
                            />
                          </div>

                          <div className="h-64 rounded-xl overflow-hidden border">
                            <MapContainer
                              center={[28.6139, 77.2090]}
                              zoom={10}
                              whenCreated={setMapRef}
                              style={{ height: '100%', width: '100%' }}
                            >
                              <TileLayer
                                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                              />

                              <LocationMarker
                                setLatLng={(lat, lng) => {
                                  setFormVals(prev => ({
                                    ...prev,
                                    latitude: lat,
                                    longitude: lng,
                                  }))
                                }}
                              />
                            </MapContainer>
                          </div>

                          <p className="text-xs text-gray-500 mt-1">
                            मैप पर क्लिक करें → latitude/longitude ऑटो भर जाएगा
                          </p>
                        </div>
                      )}

                      {/* Officer section — only for SZ, Zone, Sector */}
                      {hasOfficers && (
                        <OfficerForm
                          officers={officers}
                          onChange={setOfficers}
                          color={tabObj.color}
                          bg={tabObj.bg}
                          light={tabObj.light}
                          availableStaff={availableStaff}
                        />
                      )}

                      {/* Submit buttons */}
                      <div className="flex flex-wrap gap-3 mt-4">
                        <button
                          onClick={handleAdd}
                          disabled={saving}
                          className="flex items-center gap-2 text-white text-[13px] font-semibold px-5 py-2.5 rounded-xl transition-opacity disabled:opacity-60 shadow-sm"
                          style={{ background: tabObj.color }}
                        >
                          {saving
                            ? <><Spinner color="white" /> सहेज रहे हैं...</>
                            : <><Check size={14} /> सहेजें</>
                          }
                        </button>
                        <button
                          onClick={() => { setShowForm(false); setFormVals({}); setOfficers([]) }}
                          className="text-[13px] text-[#7a6a50] px-4 py-2.5 rounded-xl hover:bg-[#f0e8d8] transition-colors font-medium"
                        >
                          रद्द करें
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* ── DATA TABLE CARD ─────────────────────────────────────── */}
            <div className="bg-white rounded-2xl border border-[#e8d9c0] shadow-sm overflow-hidden">
              <div className="flex items-center justify-between px-4 sm:px-5 py-3.5 border-b border-[#f0e8d8]">
                <div className="flex items-center gap-2">
                  <span className="text-[13px] font-semibold text-[#2c2416]">
                    {tabObj.label} सूची
                  </span>
                  {allItems && allItems.length > 0 && (
                    <span className="text-[11px] font-medium px-2 py-0.5 rounded-full"
                      style={{ background: tabObj.bg, color: tabObj.color }}>
                      कुल {allItems.length}
                    </span>
                  )}
                </div>
                <button
                  onClick={handleRefresh}
                  className="w-8 h-8 rounded-lg flex items-center justify-center text-[#7a6a50] hover:bg-[#f5f0e8] transition-colors"
                  title="पुनः लोड करें"
                >
                  <RefreshCw size={13} className={loading.tab ? 'animate-spin' : ''} />
                </button>
              </div>

              {loading.tab ? (
                <div className="flex items-center justify-center h-36 gap-3 text-[#7a6a50]">
                  <Spinner color={tabObj.color} />
                  <span className="text-sm">लोड हो रहा है...</span>
                </div>
              ) : needsParent ? (
                <NeedsParentState message={parentMessages[activeTab]} />
              ) : !allItems || allItems.length === 0 ? (
                <EmptyState tab={tabObj} />
              ) : (
                <>
                  {/* Desktop Table */}
                  <div className="hidden md:block overflow-x-auto">
                    <table className="w-full">
                      <thead>
                        <tr style={{ background: tabObj.light }}>
                          <th className="text-left px-5 py-3 text-[11px] font-bold text-[#6b5c42] uppercase tracking-wider w-10">#</th>
                          {COLUMNS[activeTab].map(col => (
                            <th key={col.key} className="text-left px-5 py-3 text-[11px] font-bold text-[#6b5c42] uppercase tracking-wider">
                              {col.label}
                            </th>
                          ))}
                          {/* Officers column for sz/zone/sector */}
                          {hasOfficers && (
                            <th className="text-left px-5 py-3 text-[11px] font-bold text-[#6b5c42] uppercase tracking-wider">
                              अधिकारी
                            </th>
                          )}
                          <th className="px-5 py-3 w-12"></th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-[#f5f0e8]">
                        {pageItems.map((item, idx) => (
                          <tr key={item.id} className="hover:bg-[#faf6ef] transition-colors group">
                            <td className="px-5 py-3.5 text-[12px] text-[#a89878] font-medium">
                              {(curPage - 1) * PAGE_SIZE + idx + 1}
                            </td>
                            {COLUMNS[activeTab].map(col => (
                              <td key={col.key} className="px-5 py-3.5">
                                {col.key === 'name' ? (
                                  <span className="text-[13px] font-semibold text-[#2c2416]">
                                    {tx(item.name) || tx(item.roomNumber) || '—'}
                                  </span>
                                ) : col.type === 'tag' ? (
                                  item[col.key] ? (
                                    <span className="text-[11px] font-bold px-2 py-0.5 rounded-md"
                                      style={{ background: tabObj.bg, color: tabObj.color }}>
                                      {item[col.key]}
                                    </span>
                                  ) : <span className="text-[#c8b898]">—</span>
                                ) : col.badge && typeof item[col.key] === 'number' ? (
                                  <span className="text-[12px] font-bold px-2.5 py-0.5 rounded-full"
                                    style={{ background: tabObj.bg, color: tabObj.color }}>
                                    {item[col.key]}
                                  </span>
                                ) : (
                                  <span className="text-[13px] text-[#7a6a50]">
                                    {item[col.key] ? tx(item[col.key]) : '—'}
                                  </span>
                                )}
                              </td>
                            ))}
                            {/* Officers inline display */}
                            {hasOfficers && (
                              <td className="px-5 py-3.5">
                                {item.officers && item.officers.length > 0 ? (
                                  <div className="flex flex-wrap gap-1">
                                    {item.officers.slice(0, 2).map((o, oi) => (
                                      <span key={oi} className="text-[11px] px-2 py-0.5 rounded-full"
                                        style={{ background: tabObj.bg, color: tabObj.color }}>
                                        {o.name}
                                      </span>
                                    ))}
                                    {item.officers.length > 2 && (
                                      <span className="text-[11px] text-[#a89878]">+{item.officers.length - 2}</span>
                                    )}
                                  </div>
                                ) : (
                                  <span className="text-[#c8b898] text-[12px]">—</span>
                                )}
                              </td>
                            )}
                            <td className="px-5 py-3.5 text-right">
                              <button
                                onClick={() => handleDelete(item)}
                                className="w-7 h-7 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-[#fbeaea] hover:text-[#7a2020] transition-all opacity-0 group-hover:opacity-100 ml-auto"
                              >
                                <Trash2 size={12} />
                              </button>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>

                  {/* Mobile Cards */}
                  <div className="md:hidden divide-y divide-[#f5f0e8]">
                    {pageItems.map((item, idx) => {
                      const TIcon = tabObj.icon
                      return (
                        <div key={item.id} className="p-4 flex items-start gap-3 hover:bg-[#faf6ef] transition-colors">
                          <div className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 mt-0.5"
                            style={{ background: tabObj.bg }}>
                            <TIcon size={13} style={{ color: tabObj.color }} />
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 mb-0.5">
                              <span className="text-[10px] text-[#a89878]">#{(curPage - 1) * PAGE_SIZE + idx + 1}</span>
                              {item.centerType && (
                                <span className="text-[10px] font-bold px-1.5 py-0.5 rounded"
                                  style={{ background: tabObj.bg, color: tabObj.color }}>
                                  {item.centerType}
                                </span>
                              )}
                            </div>
                            <p className="text-[14px] font-semibold text-[#2c2416] truncate">
                              {tx(item.name) || tx(item.roomNumber) || '—'}
                            </p>
                            <div className="flex flex-wrap gap-x-3 gap-y-0.5 mt-1">
                              {COLUMNS[activeTab]
                                .filter(c => !['name','roomNumber'].includes(c.key) && item[c.key] != null && item[c.key] !== '')
                                .map(col => (
                                  <span key={col.key} className="text-[11px] text-[#7a6a50]">
                                    <span className="text-[#a89878]">{col.label}: </span>
                                    {col.badge ? (
                                      <span className="font-semibold" style={{ color: tabObj.color }}>{item[col.key]}</span>
                                    ) : (
                                      tx(item[col.key])
                                    )}
                                  </span>
                                ))}
                            </div>
                            {/* Officers on mobile */}
                            {hasOfficers && item.officers && item.officers.length > 0 && (
                              <div className="flex flex-wrap gap-1 mt-1.5">
                                {item.officers.map((o, oi) => (
                                  <span key={oi} className="text-[10px] px-1.5 py-0.5 rounded-full"
                                    style={{ background: tabObj.bg, color: tabObj.color }}>
                                    {o.name}
                                  </span>
                                ))}
                              </div>
                            )}
                          </div>
                          <button
                            onClick={() => handleDelete(item)}
                            className="w-8 h-8 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-[#fbeaea] hover:text-[#7a2020] transition-all flex-shrink-0"
                          >
                            <Trash2 size={13} />
                          </button>
                        </div>
                      )
                    })}
                  </div>

                  {/* Pagination */}
                  {totalPages > 1 && (
                    <div className="flex flex-col sm:flex-row items-center justify-between gap-3 px-4 sm:px-5 py-3.5 border-t border-[#f0e8d8]"
                      style={{ background: tabObj.light }}>
                      <p className="text-[12px] text-[#7a6a50] order-2 sm:order-1">
                        पृष्ठ <strong className="text-[#2c2416]">{curPage}</strong> / {totalPages}
                        <span className="text-[#a89878] ml-2">• कुल {allItems.length} प्रविष्टियाँ</span>
                      </p>
                      <div className="flex items-center gap-1 order-1 sm:order-2">
                        <button
                          onClick={() => setPage(Math.max(1, curPage - 1))}
                          disabled={curPage === 1}
                          className="w-8 h-8 rounded-lg flex items-center justify-center text-[#7a6a50] hover:bg-white disabled:opacity-40 disabled:cursor-not-allowed transition-all border border-transparent hover:border-[#ddd0b8]"
                        >
                          <ChevronLeft size={15} />
                        </button>

                        {(() => {
                          const win = 2, pgs = []
                          let start = Math.max(1, curPage - win)
                          let end   = Math.min(totalPages, curPage + win)
                          if (end - start < win * 2) {
                            if (start === 1) end = Math.min(totalPages, start + win * 2)
                            else start = Math.max(1, end - win * 2)
                          }
                          if (start > 1) pgs.push('...')
                          for (let i = start; i <= end; i++) pgs.push(i)
                          if (end < totalPages) pgs.push('...')
                          return pgs.map((p, i) =>
                            p === '...' ? (
                              <span key={`e${i}`} className="w-8 h-8 flex items-center justify-center text-[12px] text-[#a89878]">…</span>
                            ) : (
                              <button
                                key={p}
                                onClick={() => setPage(p)}
                                className="w-8 h-8 rounded-lg text-[12px] font-medium transition-all"
                                style={curPage === p
                                  ? { background: tabObj.color, color: 'white' }
                                  : { color: '#7a6a50' }
                                }
                              >
                                {p}
                              </button>
                            )
                          )
                        })()}

                        <button
                          onClick={() => setPage(Math.min(totalPages, curPage + 1))}
                          disabled={curPage === totalPages}
                          className="w-8 h-8 rounded-lg flex items-center justify-center text-[#7a6a50] hover:bg-white disabled:opacity-40 disabled:cursor-not-allowed transition-all border border-transparent hover:border-[#ddd0b8]"
                        >
                          <ChevronRight size={15} />
                        </button>
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          </>
        )}
      </div>

      {/* ━━━━ CONFIRM DELETE DIALOG ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */}
      {confirm && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-end sm:items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-md shadow-2xl">
            <div className="flex items-start gap-4 mb-5">
              <div className="w-11 h-11 rounded-xl bg-[#fbeaea] flex items-center justify-center flex-shrink-0">
                <Trash2 size={18} className="text-[#7a2020]" />
              </div>
              <div>
                <h3 className="font-bold text-[#2c2416] text-base">हटाने की पुष्टि करें</h3>
                <p className="text-[13px] text-[#7a6a50] mt-1 leading-relaxed">
                  क्या आप{' '}
                  <strong className="text-[#2c2416] font-semibold">
                    "{tx(confirm.item?.name) || confirm.item?.roomNumber}"
                  </strong>{' '}
                  को हटाना चाहते हैं? इससे जुड़ा सभी डेटा स्थायी रूप से हट जाएगा।
                </p>
              </div>
            </div>
            <div className="flex gap-3">
              <button
                onClick={confirm.action}
                className="flex-1 bg-[#7a2020] hover:opacity-90 text-white text-[13px] font-semibold py-3 rounded-xl transition-opacity"
              >
                हाँ, हटाएं
              </button>
              <button
                onClick={() => setConfirm(null)}
                className="flex-1 bg-[#f5f0e8] hover:bg-[#ede5d8] text-[#5a4a36] text-[13px] font-semibold py-3 rounded-xl transition-colors"
              >
                रद्द करें
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}