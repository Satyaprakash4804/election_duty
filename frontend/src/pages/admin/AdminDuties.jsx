import { useEffect, useState, useRef, useMemo } from 'react'
import {
  Plus, Trash2, Search, Printer, X, ChevronDown, ChevronLeft, ChevronRight,
  Check, Users, Shield, UserCheck, UserX, LayoutGrid,
} from 'lucide-react'
import { adminAPI } from '../../services/api'
import { PageHeader, Modal, Spinner, ConfirmDialog } from '../../components/ui'
import toast from 'react-hot-toast'

/* ─────────────────────────────────────────────
   Rank translation map
───────────────────────────────────────────── */
const RANK_HI = {
  'Constable':      'कांस्टेबल',
  'Head Constable': 'हेड कांस्टेबल',
  'HC':             'हेड कांस्टेबल',
  'ASI':            'सहायक उप-निरीक्षक',
  'SI':             'उप-निरीक्षक',
  'Sub Inspector':  'उप-निरीक्षक',
  'Inspector':      'निरीक्षक',
  'DSP':            'उपाधीक्षक',
  'CO':             'सर्किल अधिकारी',
}
const rh = (val) => (val && RANK_HI[val]) ? RANK_HI[val] : (val || '—')
const v  = (x)   => x || '—'

/* ─────────────────────────────────────────────
   Print card helpers (unchanged)
───────────────────────────────────────────── */
const TD = ({ children, bold, center, mono, colSpan, rowSpan, style = {} }) => (
  <td colSpan={colSpan} rowSpan={rowSpan}
    style={{ border:'1px solid #000', padding:'3px 5px', fontSize:'10px', verticalAlign:'middle',
      textAlign: center ? 'center' : 'left', fontWeight: bold ? 700 : 400,
      fontFamily: mono ? 'monospace' : 'inherit', ...style }}>
    {children}
  </td>
)
const TH = ({ children, colSpan, rowSpan, style = {} }) => (
  <td colSpan={colSpan} rowSpan={rowSpan}
    style={{ border:'1px solid #000', padding:'3px 5px', fontSize:'10px', fontWeight:700,
      textAlign:'center', verticalAlign:'middle', background:'#e8e8e8', ...style }}>
    {children}
  </td>
)

function OfficerBlock({ label, officers }) {
  return (
    <table style={{ borderCollapse:'collapse', width:'100%', fontSize:'9.5px' }}>
      <tbody>
        <tr>
          <td colSpan={4} style={{ border:'1px solid #000', background:'#e8e8e8', fontWeight:700,
            textAlign:'center', padding:'2px 4px' }}>{label}</td>
        </tr>
        {(!officers || officers.length === 0) ? (
          <tr><td colSpan={4} style={{ border:'1px solid #000', padding:'2px 4px', color:'#999', textAlign:'center' }}>—</td></tr>
        ) : officers.map((o, i) => (
          <tr key={i}>
            <td style={{ border:'1px solid #000', padding:'2px 4px', width:'24%' }}>{rh(o.user_rank)}</td>
            <td style={{ border:'1px solid #000', padding:'2px 4px', fontWeight:600 }}>{v(o.name)}</td>
            <td style={{ border:'1px solid #000', padding:'2px 4px', fontFamily:'monospace', width:'20%' }}>{v(o.pno)}</td>
            <td style={{ border:'1px solid #000', padding:'2px 4px', width:'22%' }}>{v(o.mobile)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

/* ─────────────────────────────────────────────
   Duty Card Print Modal (unchanged)
───────────────────────────────────────────── */
function DutyCardPrint({ duty, onClose }) {
  const printRef = useRef()
  const handlePrint = () => {
    const content = printRef.current.innerHTML
    const win = window.open('', '_blank', 'width=960,height=720')
    win.document.write(`<!DOCTYPE html><html><head>
      <meta charset="UTF-8"/>
      <title>ड्यूटी कार्ड – ${duty.name}</title>
      <link rel="preconnect" href="https://fonts.googleapis.com"/>
      <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;600;700&display=swap" rel="stylesheet"/>
      <style>*{margin:0;padding:0;box-sizing:border-box;}body{font-family:'Noto Sans Devanagari',Arial,sans-serif;background:#fff;-webkit-print-color-adjust:exact;}@page{size:A4 portrait;margin:8mm;}table{border-collapse:collapse;width:100%;}td{border:1px solid #000;font-size:10px;padding:3px 5px;vertical-align:middle;}</style>
      </head><body>${content}</body></html>`)
    win.document.close()
    win.onload = () => { win.print(); win.close() }
  }
  const sahyogi  = duty.sahyogi        || []
  const zonal    = duty.zonalOfficers  || []
  const sector   = duty.sectorOfficers || []
  const superOff = duty.superOfficers  || []
  const sahRows  = Array.from({ length: Math.max(8, sahyogi.length) }, (_, i) => sahyogi[i] || null)

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-5xl max-h-[92vh] overflow-y-auto">
        <div className="sticky top-0 bg-white border-b border-gray-200 px-5 py-3 flex items-center justify-between rounded-t-2xl z-10">
          <div>
            <p className="text-[13px] font-semibold text-[#2c2416]">ड्यूटी कार्ड पूर्वावलोकन</p>
            <p className="text-[11px] text-[#a89878]">{duty.name} · {duty.pno} · {duty.centerName}</p>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={handlePrint} className="inline-flex items-center gap-2 bg-[#8b6914] hover:opacity-90 text-white text-[12px] font-medium px-4 py-2 rounded-lg transition-opacity">
              <Printer size={13} /> प्रिंट करें
            </button>
            <button onClick={onClose} className="w-8 h-8 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-gray-100 transition-colors">
              <X size={15} />
            </button>
          </div>
        </div>
        <div className="p-6">
          <div ref={printRef}>
            <table style={{ border:'2px solid #000', fontFamily:"'Noto Sans Devanagari',Arial,sans-serif", fontSize:'10px', borderCollapse:'collapse', width:'100%' }}>
              <tbody>
                <tr>
                  <td colSpan={10} style={{ border:'2px solid #000', padding:'6px 10px' }}>
                    <div style={{ display:'flex', alignItems:'center', gap:10 }}>
                      <div style={{ width:54, height:54, border:'2px solid #000', borderRadius:'50%', overflow:'hidden', flexShrink:0, display:'flex', alignItems:'center', justifyContent:'center' }}>
                        <img src="/logo/logo.jpeg" alt="Logo" style={{ width:'100%', height:'100%', objectFit:'cover', display:'block' }} />
                      </div>
                      <div style={{ flex:1, textAlign:'center' }}>
                        <div style={{ fontSize:17, fontWeight:700, letterSpacing:1 }}>ड्यूटी कार्ड</div>
                        <div style={{ fontSize:13, fontWeight:600 }}>लोकसभा सामान्य निर्वाचन–2024</div>
                        <div style={{ fontSize:11 }}>जनपद – {v(duty.district)}</div>
                        <div style={{ fontSize:10, fontWeight:600, borderTop:'1px solid #aaa', marginTop:3, paddingTop:2 }}>मतदान चरण–द्वितीय &nbsp;|&nbsp; दिनांक: 26.04.2024 &nbsp;|&nbsp; प्रातः 07:00 से सांय 06:00 बजे तक</div>
                      </div>
                      <div style={{ width:54, height:54, border:'2px solid #000', borderRadius:'50%', display:'flex', alignItems:'center', justifyContent:'center', fontSize:7, fontWeight:700, textAlign:'center', padding:3, flexShrink:0 }}>उत्तर<br/>प्रदेश<br/>पुलिस</div>
                    </div>
                  </td>
                </tr>
                <tr><TH>पद</TH><TH>बैज / पुलिस नं0</TH><TH colSpan={2}>नाम</TH><TH>मोबाइल</TH><TH>थाना</TH><TH>जनपद</TH><TH>श्रेणी</TH><TH colSpan={2}>वाहन संख्या</TH></tr>
                <tr>
                  <TD center bold>{rh(duty.user_rank)}</TD><TD center mono>{v(duty.pno)}</TD>
                  <TD colSpan={2} bold>{v(duty.name)}</TD><TD center>{v(duty.mobile)}</TD>
                  <TD center>{v(duty.thana)}</TD><TD center>{v(duty.district)}</TD>
                  <TD center>सशस्त्र</TD><TD colSpan={2} center bold>बस–{v(duty.busNo)}</TD>
                </tr>
                <tr><TH colSpan={2}>ड्यूटी स्थान (केंद्र)</TH><TH>ग्राम पंचायत</TH><TH>सेक्टर</TH><TH>जोन</TH><TH colSpan={2}>सुपर जोन</TH><TH>ड्यूटी प्रकार</TH><TH colSpan={2}>केंद्र प्रकार</TH></tr>
                <tr>
                  <TD colSpan={2} bold>{v(duty.centerName)}</TD><TD>{v(duty.gpName)}</TD>
                  <TD center>{v(duty.sectorName)}</TD><TD center>{v(duty.zoneName)}</TD>
                  <TD colSpan={2} center>{v(duty.superZoneName)}</TD><TD center>बूथ ड्यूटी</TD>
                  <TD colSpan={2} center>{v(duty.centerType)}</TD>
                </tr>
                <tr><TH colSpan={10}>सहयोगी कर्मचारी गण (एक ही केंद्र पर तैनात)</TH></tr>
                <tr style={{ background:'#f4f4f4' }}><TH>क्र0</TH><TH>पद</TH><TH colSpan={2}>नाम</TH><TH>बैज / पुलिस नं0</TH><TH>मोबाइल</TH><TH colSpan={2}>थाना</TH><TH colSpan={2}>जनपद</TH></tr>
                {sahRows.map((s, i) => (
                  <tr key={i} style={{ background: i % 2 === 0 ? '#fff' : '#fafafa' }}>
                    <TD center style={{ color:'#888', fontSize:9 }}>{i + 1}</TD>
                    <TD center style={{ color: s ? '#000' : '#ccc' }}>{s ? rh(s.user_rank) : '—'}</TD>
                    <TD colSpan={2} style={{ color: s ? '#000' : '#ccc', fontWeight: s ? 500 : 400 }}>{s ? v(s.name) : '—'}</TD>
                    <TD center mono style={{ color: s ? '#000' : '#ccc' }}>{s ? v(s.pno) : '—'}</TD>
                    <TD center style={{ color: s ? '#000' : '#ccc' }}>{s ? v(s.mobile) : '—'}</TD>
                    <TD colSpan={2} center style={{ color: s ? '#000' : '#ccc' }}>{s ? v(s.thana) : '—'}</TD>
                    <TD colSpan={2} center style={{ color: s ? '#000' : '#ccc' }}>{s ? v(s.district) : '—'}</TD>
                  </tr>
                ))}
                <tr><TH colSpan={10}>अधिकारी विवरण</TH></tr>
                <tr>
                  <td colSpan={5} style={{ border:'1px solid #000', padding:0, verticalAlign:'top' }}><OfficerBlock label="जोनल अधिकारी" officers={zonal} /></td>
                  <td colSpan={5} style={{ border:'1px solid #000', padding:0, verticalAlign:'top' }}><OfficerBlock label="सेक्टर अधिकारी" officers={sector} /></td>
                </tr>
                {superOff.length > 0 && (
                  <tr><td colSpan={10} style={{ border:'1px solid #000', padding:0, verticalAlign:'top' }}><OfficerBlock label="क्षेत्र अधिकारी (सुपर जोन)" officers={superOff} /></td></tr>
                )}
                <tr style={{ background:'#f8f8f8' }}>
                  <TD bold>सेक्टर नं0</TD><TD center>{v(duty.sectorName)}</TD>
                  <TD bold>जोन नं0</TD><TD center>{v(duty.zoneName)}</TD>
                  <TD bold>सुपर जोन</TD><TD colSpan={2} center>{v(duty.superZoneName)}</TD>
                  <TD colSpan={3} center style={{ fontSize:9, color:'#555' }}>यह कार्ड चुनाव ड्यूटी का प्रमाण है। कृपया इसे सुरक्षित रखें। &nbsp;|&nbsp; <strong>पुलिस अधीक्षक हस्ताक्षर: __________</strong></TD>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}

/* ─────────────────────────────────────────────
   Pagination
───────────────────────────────────────────── */
const PAGE_SIZE = 15

function Pagination({ total, page, onChange }) {
  const totalPages = Math.ceil(total / PAGE_SIZE)
  if (totalPages <= 1) return null
  const pages = Array.from({ length: totalPages }, (_, i) => i + 1)
    .filter(p => p === 1 || p === totalPages || Math.abs(p - page) <= 1)
    .reduce((acc, p, idx, arr) => {
      if (idx > 0 && p - arr[idx - 1] > 1) acc.push('…')
      acc.push(p); return acc
    }, [])
  return (
    <div className="flex items-center justify-between mt-4 px-1">
      <p className="text-[12px] text-[#a89878]">
        कुल <span className="font-semibold text-[#7a6a50]">{total}</span> रिकॉर्ड
        &nbsp;·&nbsp; पृष्ठ <span className="font-semibold text-[#7a6a50]">{page}</span> / {totalPages}
      </p>
      <div className="flex items-center gap-1">
        <button onClick={() => onChange(page - 1)} disabled={page === 1}
          className="w-8 h-8 rounded-lg flex items-center justify-center text-[#7a6a50] hover:bg-[#f0ead8] disabled:opacity-30 transition-colors border border-[#8b734b]/20">
          <ChevronLeft size={14} />
        </button>
        {pages.map((p, i) =>
          p === '…'
            ? <span key={`d${i}`} className="px-1 text-[#a89878] text-[12px]">…</span>
            : <button key={p} onClick={() => onChange(p)}
                className={`w-8 h-8 rounded-lg text-[12px] font-medium transition-colors border ${
                  p === page
                    ? 'bg-[#8b6914] text-white border-[#8b6914]'
                    : 'text-[#7a6a50] hover:bg-[#f0ead8] border-[#8b734b]/20'}`}>
                {p}
              </button>
        )}
        <button onClick={() => onChange(page + 1)} disabled={page === totalPages}
          className="w-8 h-8 rounded-lg flex items-center justify-center text-[#7a6a50] hover:bg-[#f0ead8] disabled:opacity-30 transition-colors border border-[#8b734b]/20">
          <ChevronRight size={14} />
        </button>
      </div>
    </div>
  )
}

/* ─────────────────────────────────────────────
   Rank Badge — light colored chips
───────────────────────────────────────────── */
function RankBadge({ rank }) {
  const cls = {
    'Inspector':      'bg-amber-100 text-amber-800 border-amber-300',
    'DSP':            'bg-purple-100 text-purple-800 border-purple-300',
    'CO':             'bg-blue-100 text-blue-800 border-blue-300',
    'SI':             'bg-emerald-100 text-emerald-800 border-emerald-300',
    'Sub Inspector':  'bg-emerald-100 text-emerald-800 border-emerald-300',
    'ASI':            'bg-sky-100 text-sky-800 border-sky-300',
    'HC':             'bg-yellow-100 text-yellow-800 border-yellow-300',
    'Head Constable': 'bg-yellow-100 text-yellow-800 border-yellow-300',
    'Constable':      'bg-gray-100 text-gray-600 border-gray-300',
  }[rank] || 'bg-[#f5f0e8] text-[#7a6a50] border-[#d4c5a0]'
  return (
    <span className={`inline-block text-[9px] font-semibold px-1.5 py-0.5 rounded border tracking-wide ${cls}`}>
      {rh(rank)}
    </span>
  )
}

/* ─────────────────────────────────────────────
   Search Bar
───────────────────────────────────────────── */
function SearchBar({ value, onChange, placeholder }) {
  return (
    <div className="relative flex-1 min-w-[200px] max-w-sm">
      <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#a89878] pointer-events-none" />
      <input
        className="w-full bg-white border border-[#8b734b]/25 rounded-lg pl-8 pr-8 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition shadow-sm"
        placeholder={placeholder}
        value={value}
        onChange={e => onChange(e.target.value)}
      />
      {value && (
        <button onClick={() => onChange('')} className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[#a89878] hover:text-[#2c2416]">
          <X size={12} />
        </button>
      )}
    </div>
  )
}

/* ─────────────────────────────────────────────
   Table Shell
───────────────────────────────────────────── */
function TableShell({ children }) {
  return (
    <div className="bg-white border border-[#8b734b]/20 rounded-xl overflow-hidden shadow-sm">
      <div className="overflow-x-auto">
        <table className="w-full border-collapse text-[13px] min-w-[700px]">
          {children}
        </table>
      </div>
    </div>
  )
}

function EmptyRow({ colSpan, msg }) {
  return (
    <tr>
      <td colSpan={colSpan} className="px-4 py-12 text-center text-[#a89878] text-[13px]">{msg}</td>
    </tr>
  )
}

/* ─────────────────────────────────────────────
   Tab style
───────────────────────────────────────────── */
const tabCls = (active) =>
  `inline-flex items-center gap-2 px-5 py-2.5 text-[13px] font-semibold border-b-2 transition-all cursor-pointer select-none ${
    active
      ? 'text-[#8b6914] border-[#8b6914]'
      : 'text-[#a89878] border-transparent hover:text-[#7a6a50] hover:bg-[#f5f0e8] rounded-t-lg'
  }`

/* ─────────────────────────────────────────────
   Main AdminDuties
───────────────────────────────────────────── */
export default function AdminDuties() {
  const [duties, setDuties]       = useState([])
  const [centers, setCenters]     = useState([])
  const [staff, setStaff]         = useState([])
  const [loading, setLoading]     = useState(true)
  const [addOpen, setAddOpen]     = useState(false)
  const [saving, setSaving]       = useState(false)
  const [confirm, setConfirm]     = useState(null)
  const [printDuty, setPrintDuty] = useState(null)

  const [activeTab, setActiveTab]           = useState('assigned')

  const [assignedSearch, setAssignedSearch] = useState('')
  const [assignedCenter, setAssignedCenter] = useState('')
  const [assignedZone, setAssignedZone]     = useState('')
  const [assignedPage, setAssignedPage]     = useState(1)

  const [unassignedSearch, setUnassignedSearch] = useState('')
  const [unassignedPage, setUnassignedPage]     = useState(1)

  const [allSearch, setAllSearch] = useState('')
  const [allPage, setAllPage]     = useState(1)

  const [form, setForm]               = useState({ selectedIds: [], centerId: '', busNo: '' })
  const [staffSearch, setStaffSearch] = useState('')

  /* ── Load ── */
  useEffect(() => {
    Promise.all([adminAPI.getDuties(), adminAPI.allCenters(), adminAPI.getStaff()])
      .then(([d, c, s]) => { setDuties(d); setCenters(c); setStaff(s) })
      .catch(() => toast.error('डेटा लोड करने में विफल'))
      .finally(() => setLoading(false))
  }, [])

  const reload = () =>
    Promise.all([adminAPI.getDuties(), adminAPI.getStaff()])
      .then(([d, s]) => { setDuties(d); setStaff(s); setAssignedPage(1); setUnassignedPage(1); setAllPage(1) })
      .catch(() => toast.error('रीफ्रेश विफल'))

  /* ── Derived ── */
  const assignedIds = useMemo(() => new Set(duties.map(d => d.staffId)), [duties])

  const enrichedStaff = useMemo(() => {
    const dutyMap = {}
    duties.forEach(d => { dutyMap[d.staffId] = d })
    return staff.map(s => ({
      ...s,
      isAssigned: s.isAssigned || assignedIds.has(s.id),
      dutyId:     dutyMap[s.id]?.id,
      centerName: s.centerName || dutyMap[s.id]?.centerName || '',
      busNo:      dutyMap[s.id]?.busNo || '',
      zoneName:   dutyMap[s.id]?.zoneName || '',
      sectorName: dutyMap[s.id]?.sectorName || '',
    }))
  }, [staff, duties, assignedIds])

  const assignedStaff   = useMemo(() => enrichedStaff.filter(s => s.isAssigned),  [enrichedStaff])
  const unassignedStaff = useMemo(() => enrichedStaff.filter(s => !s.isAssigned), [enrichedStaff])

  const zoneOptions   = useMemo(() => [...new Set(duties.map(d => d.zoneName).filter(Boolean))].sort(),   [duties])
  const centerOptions = useMemo(() => [...new Set(duties.map(d => d.centerName).filter(Boolean))].sort(), [duties])

  const filterFn = (list, q) => {
    if (!q) return list
    const ql = q.toLowerCase()
    return list.filter(s =>
      [s.name, s.pno, s.mobile, s.thana, s.district, s.centerName, s.zoneName]
        .some(f => f && String(f).toLowerCase().includes(ql))
    )
  }

  const filteredAssigned = useMemo(() => {
    let l = assignedStaff
    if (assignedSearch) l = filterFn(l, assignedSearch)
    if (assignedCenter) l = l.filter(s => s.centerName === assignedCenter)
    if (assignedZone)   l = l.filter(s => s.zoneName   === assignedZone)
    return l
  }, [assignedStaff, assignedSearch, assignedCenter, assignedZone])

  const filteredUnassigned = useMemo(() => filterFn(unassignedStaff, unassignedSearch), [unassignedStaff, unassignedSearch])
  const filteredAll        = useMemo(() => filterFn(enrichedStaff,   allSearch),        [enrichedStaff,   allSearch])

  const pagedAssigned   = filteredAssigned.slice((assignedPage - 1)   * PAGE_SIZE, assignedPage   * PAGE_SIZE)
  const pagedUnassigned = filteredUnassigned.slice((unassignedPage - 1) * PAGE_SIZE, unassignedPage * PAGE_SIZE)
  const pagedAll        = filteredAll.slice((allPage - 1)             * PAGE_SIZE, allPage         * PAGE_SIZE)

  const modalStaff = useMemo(() =>
    unassignedStaff.filter(s =>
      !staffSearch ||
      s.name.toLowerCase().includes(staffSearch.toLowerCase()) ||
      s.pno.includes(staffSearch)
    )
  , [unassignedStaff, staffSearch])

  const toggleStaff = (id) =>
    setForm(p => ({
      ...p,
      selectedIds: p.selectedIds.includes(id)
        ? p.selectedIds.filter(x => x !== id)
        : [...p.selectedIds, id],
    }))

  const closeModal = () => {
    setAddOpen(false); setStaffSearch(''); setForm({ selectedIds: [], centerId: '', busNo: '' })
  }

  const handleAssign = async (e) => {
    e.preventDefault()
    if (!form.selectedIds.length || !form.centerId) return toast.error('कर्मचारी और केंद्र चुनें')
    setSaving(true)
    try {
      await Promise.all(
        form.selectedIds.map(staffId =>
          adminAPI.assignDuty({ staffId: parseInt(staffId), centerId: parseInt(form.centerId), busNo: form.busNo || null })
        )
      )
      toast.success(`${form.selectedIds.length} कर्मचारी की ड्यूटी लगाई गई`)
      closeModal(); reload()
    } catch (err) {
      toast.error(err?.response?.data?.message || 'ड्यूटी लगाने में विफल')
    } finally { setSaving(false) }
  }

  const handleRemove = (id) => {
    setConfirm({
      message: 'क्या आप यह ड्यूटी हटाना चाहते हैं?',
      action: async () => {
        try {
          await adminAPI.removeDuty(id)
          toast.success('ड्यूटी हटाई गई')
          reload()
        } catch { toast.error('हटाने में विफल') }
        setConfirm(null)
      },
    })
  }

  const findDutyForStaff = (s) => duties.find(d => d.staffId === s.id) || s
  const selectedCenter   = centers.find(c => String(c.id) === String(form.centerId))

  if (loading) return <Spinner />

  const stats = [
    { icon: <Users size={20} />,     label: 'कुल कर्मचारी',  count: enrichedStaff.length,   color: 'text-blue-700',     bg: 'bg-blue-50',     border: 'border-blue-200' },
    { icon: <UserCheck size={20} />, label: 'ड्यूटी लगाए गए', count: assignedStaff.length,   color: 'text-emerald-700',  bg: 'bg-emerald-50',  border: 'border-emerald-200' },
    { icon: <UserX size={20} />,     label: 'ड्यूटी बाकी',    count: unassignedStaff.length, color: 'text-rose-700',     bg: 'bg-rose-50',     border: 'border-rose-200' },
    { icon: <Shield size={20} />,    label: 'मतदान केंद्र',   count: centers.length,         color: 'text-[#8b6914]',    bg: 'bg-[#fdf6e3]',   border: 'border-[#d4b96a]/50' },
  ]

  return (
    <div>
      {/* ══ HEADER ══ */}
      <div className="bg-white border-b border-[#e8dfc8] px-6 py-5 mb-4">
        <div className="flex items-center justify-between flex-wrap gap-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-[#8b6914] flex items-center justify-center shadow-sm">
              <Shield size={18} className="text-white" />
            </div>
            <div>
              <p className="text-[10px] font-bold tracking-[2px] text-[#a89878] uppercase">उत्तर प्रदेश पुलिस · निर्वाचन प्रणाली</p>
              <h1 className="text-[19px] font-bold text-[#2c2416] leading-tight">ड्यूटी आवंटन प्रबंधन</h1>
            </div>
          </div>
          <button onClick={() => setAddOpen(true)}
            className="inline-flex items-center gap-2 bg-[#8b6914] hover:bg-[#7a5c10] text-white text-[13px] font-semibold px-5 py-2.5 rounded-lg transition-colors shadow-sm active:scale-95">
            <Plus size={15} /> ड्यूटी लगाएं
          </button>
        </div>
      </div>

      {/* ══ STAT CARDS ══ */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-5">
        {stats.map((s, i) => (
          <div key={i} className={`${s.bg} border ${s.border} rounded-xl px-4 py-3.5 flex items-center gap-3`}>
            <div className={s.color}>{s.icon}</div>
            <div>
              <p className={`text-[22px] font-bold ${s.color} leading-none`}>{s.count}</p>
              <p className="text-[11px] text-[#7a6a50] mt-0.5">{s.label}</p>
            </div>
          </div>
        ))}
      </div>

      {/* ══ TABS ══ */}
      <div className="flex items-end gap-0 border-b border-[#e8dfc8] mb-4">
        <button className={tabCls(activeTab === 'assigned')} onClick={() => setActiveTab('assigned')}>
          <UserCheck size={14} className={activeTab === 'assigned' ? 'text-emerald-600' : ''} />
          ड्यूटी लगाए गए
          <span className={`text-[10px] px-2 py-0.5 rounded-full font-bold border ${
            activeTab === 'assigned'
              ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
              : 'bg-[#f5f0e8] text-[#a89878] border-[#e8dfc8]'}`}>
            {assignedStaff.length}
          </span>
        </button>
        <button className={tabCls(activeTab === 'unassigned')} onClick={() => setActiveTab('unassigned')}>
          <UserX size={14} className={activeTab === 'unassigned' ? 'text-rose-600' : ''} />
          ड्यूटी बाकी
          <span className={`text-[10px] px-2 py-0.5 rounded-full font-bold border ${
            activeTab === 'unassigned'
              ? 'bg-rose-50 text-rose-700 border-rose-200'
              : 'bg-[#f5f0e8] text-[#a89878] border-[#e8dfc8]'}`}>
            {unassignedStaff.length}
          </span>
        </button>
        <button className={tabCls(activeTab === 'all')} onClick={() => setActiveTab('all')}>
          <LayoutGrid size={14} className={activeTab === 'all' ? 'text-[#8b6914]' : ''} />
          सभी अधिकारी
          <span className={`text-[10px] px-2 py-0.5 rounded-full font-bold border ${
            activeTab === 'all'
              ? 'bg-[#fdf6e3] text-[#8b6914] border-[#d4b96a]/50'
              : 'bg-[#f5f0e8] text-[#a89878] border-[#e8dfc8]'}`}>
            {enrichedStaff.length}
          </span>
        </button>
      </div>

      {/* ══ ASSIGNED TAB ══ */}
      {activeTab === 'assigned' && (
        <div>
          <div className="flex flex-wrap items-center gap-2 mb-4">
            <SearchBar value={assignedSearch} onChange={v => { setAssignedSearch(v); setAssignedPage(1) }}
              placeholder="नाम, पुलिस नं0, मोबाइल, केंद्र…" />

            <div className="relative">
              <ChevronDown size={13} className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[#a89878] pointer-events-none" />
              <select value={assignedCenter} onChange={e => { setAssignedCenter(e.target.value); setAssignedPage(1) }}
                className="appearance-none bg-white border border-[#8b734b]/25 rounded-lg px-3 py-2 pr-7 text-[13px] text-[#2c2416] focus:outline-none focus:border-[#8b6914] shadow-sm transition">
                <option value="">सभी केंद्र</option>
                {centerOptions.map(n => <option key={n} value={n}>{n}</option>)}
              </select>
            </div>

            <div className="relative">
              <ChevronDown size={13} className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[#a89878] pointer-events-none" />
              <select value={assignedZone} onChange={e => { setAssignedZone(e.target.value); setAssignedPage(1) }}
                className="appearance-none bg-white border border-[#8b734b]/25 rounded-lg px-3 py-2 pr-7 text-[13px] text-[#2c2416] focus:outline-none focus:border-[#8b6914] shadow-sm transition">
                <option value="">सभी जोन</option>
                {zoneOptions.map(z => <option key={z} value={z}>{z}</option>)}
              </select>
            </div>

            {(assignedSearch || assignedCenter || assignedZone) && (
              <>
                <button onClick={() => { setAssignedSearch(''); setAssignedCenter(''); setAssignedZone(''); setAssignedPage(1) }}
                  className="text-[12px] text-[#8b6914] hover:underline flex items-center gap-1">
                  <X size={11} /> फ़िल्टर हटाएं
                </button>
                <span className="text-[11px] bg-[#f0ead8] text-[#7a6a50] px-2 py-1 rounded-full">{filteredAssigned.length} परिणाम</span>
              </>
            )}
          </div>

          <TableShell>
            <thead>
              <tr className="bg-[#fdfaf5] border-b border-[#e8dfc8]">
                {['कर्मचारी', 'पुलिस नं0', 'मोबाइल', 'थाना', 'जनपद', 'केंद्र', ''].map(h => (
                  <th key={h} className="px-4 py-2.5 text-left text-[10px] font-bold text-[#a89878] uppercase tracking-widest whitespace-nowrap">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {pagedAssigned.length === 0
                ? <EmptyRow colSpan={7} msg="कोई आवंटित कर्मचारी नहीं मिला" />
                : pagedAssigned.map(s => (
                  <tr key={s.id} className="border-b border-[#f5f0e8] hover:bg-[#fdfaf5] transition-colors group last:border-0">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-full bg-emerald-50 border border-emerald-200 flex items-center justify-center text-emerald-700 text-[11px] font-bold shrink-0">
                          {(s.name || '?')[0]}
                        </div>
                        <div>
                          <p className="font-semibold text-[13px] text-[#2c2416]">{s.name}</p>
                          <RankBadge rank={s.rank} />
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 font-mono text-[11px] text-[#8b6914]">{s.pno}</td>
                    <td className="px-4 py-3 text-[12px] text-[#7a6a50]">{s.mobile || '—'}</td>
                    <td className="px-4 py-3 text-[12px] text-[#7a6a50]">{s.thana || '—'}</td>
                    <td className="px-4 py-3 text-[12px] text-[#7a6a50]">{s.district || '—'}</td>
                    <td className="px-4 py-3">
                      <p className="text-[12px] font-medium text-[#2c2416]">{s.centerName || '—'}</p>
                      {s.zoneName && <p className="text-[10px] text-[#a89878]">{s.zoneName}</p>}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button onClick={() => setPrintDuty(findDutyForStaff(s))}
                          className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-medium bg-[#f0ead8] text-[#8b6914] hover:bg-[#8b6914] hover:text-white border border-[#8b6914]/30 transition-all">
                          <Printer size={11} /><span className="hidden lg:inline">प्रिंट</span>
                        </button>
                        {s.dutyId && (
                          <button onClick={() => handleRemove(s.dutyId)}
                            className="w-7 h-7 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-rose-50 hover:text-rose-600 transition-all">
                            <Trash2 size={13} />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))
              }
            </tbody>
          </TableShell>
          <Pagination total={filteredAssigned.length} page={assignedPage} onChange={setAssignedPage} />
        </div>
      )}

      {/* ══ UNASSIGNED TAB ══ */}
      {activeTab === 'unassigned' && (
        <div>
          <div className="flex flex-wrap items-center gap-2 mb-4">
            <SearchBar value={unassignedSearch} onChange={v => { setUnassignedSearch(v); setUnassignedPage(1) }}
              placeholder="नाम, पुलिस नं0, मोबाइल, थाना…" />
            {unassignedSearch && (
              <span className="text-[11px] bg-[#f0ead8] text-[#7a6a50] px-2 py-1 rounded-full">{filteredUnassigned.length} परिणाम</span>
            )}
          </div>

          <TableShell>
            <thead>
              <tr className="bg-[#fdfaf5] border-b border-[#e8dfc8]">
                {['कर्मचारी', 'पुलिस नं0', 'मोबाइल', 'थाना', 'जनपद', 'स्थिति', ''].map(h => (
                  <th key={h} className="px-4 py-2.5 text-left text-[10px] font-bold text-[#a89878] uppercase tracking-widest whitespace-nowrap">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {pagedUnassigned.length === 0
                ? <EmptyRow colSpan={7} msg="सभी कर्मचारियों की ड्यूटी लगाई जा चुकी है 🎉" />
                : pagedUnassigned.map(s => (
                  <tr key={s.id} className="border-b border-[#f5f0e8] hover:bg-[#fdfaf5] transition-colors group last:border-0">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-full bg-rose-50 border border-rose-200 flex items-center justify-center text-rose-600 text-[11px] font-bold shrink-0">
                          {(s.name || '?')[0]}
                        </div>
                        <div>
                          <p className="font-semibold text-[13px] text-[#2c2416]">{s.name}</p>
                          <RankBadge rank={s.rank} />
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 font-mono text-[11px] text-[#8b6914]">{s.pno}</td>
                    <td className="px-4 py-3 text-[12px] text-[#7a6a50]">{s.mobile || '—'}</td>
                    <td className="px-4 py-3 text-[12px] text-[#7a6a50]">{s.thana || '—'}</td>
                    <td className="px-4 py-3 text-[12px] text-[#7a6a50]">{s.district || '—'}</td>
                    <td className="px-4 py-3">
                      <span className="inline-flex items-center gap-1.5 text-[10px] font-semibold px-2 py-1 rounded-full bg-rose-50 text-rose-600 border border-rose-200">
                        <span className="w-1.5 h-1.5 rounded-full bg-rose-500 animate-pulse" />
                        ड्यूटी नहीं
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <button
                        onClick={() => { setForm(p => ({ ...p, selectedIds: [s.id] })); setAddOpen(true) }}
                        className="opacity-0 group-hover:opacity-100 inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-medium bg-[#f0ead8] text-[#8b6914] hover:bg-[#8b6914] hover:text-white border border-[#8b6914]/30 transition-all">
                        <Plus size={11} /> लगाएं
                      </button>
                    </td>
                  </tr>
                ))
              }
            </tbody>
          </TableShell>
          <Pagination total={filteredUnassigned.length} page={unassignedPage} onChange={setUnassignedPage} />
        </div>
      )}

      {/* ══ ALL TAB ══ */}
      {activeTab === 'all' && (
        <div>
          <div className="flex flex-wrap items-center gap-2 mb-4">
            <SearchBar value={allSearch} onChange={v => { setAllSearch(v); setAllPage(1) }}
              placeholder="नाम, पुलिस नं0, मोबाइल, थाना, जनपद, केंद्र…" />
            {allSearch && (
              <span className="text-[11px] bg-[#f0ead8] text-[#7a6a50] px-2 py-1 rounded-full">{filteredAll.length} परिणाम</span>
            )}
          </div>

          <TableShell>
            <thead>
              <tr className="bg-[#fdfaf5] border-b border-[#e8dfc8]">
                {['कर्मचारी', 'पुलिस नं0', 'मोबाइल', 'थाना', 'जनपद', 'केंद्र / स्थिति', ''].map(h => (
                  <th key={h} className="px-4 py-2.5 text-left text-[10px] font-bold text-[#a89878] uppercase tracking-widest whitespace-nowrap">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {pagedAll.length === 0
                ? <EmptyRow colSpan={7} msg="कोई कर्मचारी नहीं मिला" />
                : pagedAll.map(s => (
                  <tr key={s.id} className="border-b border-[#f5f0e8] hover:bg-[#fdfaf5] transition-colors group last:border-0">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <div className={`w-8 h-8 rounded-full border flex items-center justify-center text-[11px] font-bold shrink-0 ${
                          s.isAssigned
                            ? 'bg-emerald-50 border-emerald-200 text-emerald-700'
                            : 'bg-rose-50 border-rose-200 text-rose-600'}`}>
                          {(s.name || '?')[0]}
                        </div>
                        <div>
                          <p className="font-semibold text-[13px] text-[#2c2416]">{s.name}</p>
                          <RankBadge rank={s.rank} />
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 font-mono text-[11px] text-[#8b6914]">{s.pno}</td>
                    <td className="px-4 py-3 text-[12px] text-[#7a6a50]">{s.mobile || '—'}</td>
                    <td className="px-4 py-3 text-[12px] text-[#7a6a50]">{s.thana || '—'}</td>
                    <td className="px-4 py-3 text-[12px] text-[#7a6a50]">{s.district || '—'}</td>
                    <td className="px-4 py-3">
                      {s.isAssigned ? (
                        <div>
                          <p className="text-[12px] font-medium text-[#2c2416]">{s.centerName || '—'}</p>
                          {s.zoneName && <p className="text-[10px] text-[#a89878]">{s.zoneName}</p>}
                        </div>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 text-[10px] font-semibold px-2 py-1 rounded-full bg-rose-50 text-rose-600 border border-rose-200">
                          <span className="w-1.5 h-1.5 rounded-full bg-rose-500 animate-pulse" />
                          ड्यूटी नहीं
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity">
                        {s.isAssigned && (
                          <>
                            <button onClick={() => setPrintDuty(findDutyForStaff(s))}
                              className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-medium bg-[#f0ead8] text-[#8b6914] hover:bg-[#8b6914] hover:text-white border border-[#8b6914]/30 transition-all">
                              <Printer size={11} /> प्रिंट
                            </button>
                            {s.dutyId && (
                              <button onClick={() => handleRemove(s.dutyId)}
                                className="w-7 h-7 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-rose-50 hover:text-rose-600 transition-all">
                                <Trash2 size={13} />
                              </button>
                            )}
                          </>
                        )}
                        {!s.isAssigned && (
                          <button onClick={() => { setForm(p => ({ ...p, selectedIds: [s.id] })); setAddOpen(true) }}
                            className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-medium bg-[#f0ead8] text-[#8b6914] hover:bg-[#8b6914] hover:text-white border border-[#8b6914]/30 transition-all">
                            <Plus size={11} /> लगाएं
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))
              }
            </tbody>
          </TableShell>
          <Pagination total={filteredAll.length} page={allPage} onChange={setAllPage} />
        </div>
      )}

      {/* ══ ASSIGN MODAL ══ */}
      <Modal open={addOpen} onClose={closeModal} title="ड्यूटी लगाएं">
        <form onSubmit={handleAssign} className="space-y-4">
          <div>
            <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">
              कर्मचारी चुनें <span className="text-red-500">*</span>
              {form.selectedIds.length > 0 && (
                <span className="ml-2 bg-[#8b6914] text-white text-[10px] px-2 py-0.5 rounded-full">{form.selectedIds.length} चयनित</span>
              )}
            </label>
            <div className="relative mb-2">
              <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#a89878]" />
              <input
                className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg pl-8 pr-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
                placeholder="नाम या पुलिस नं0 से खोजें…"
                value={staffSearch}
                onChange={e => setStaffSearch(e.target.value)}
              />
            </div>
            <div className="border border-[#8b734b]/25 rounded-lg overflow-hidden bg-[#f5f0e8] max-h-44 overflow-y-auto">
              {modalStaff.length === 0 ? (
                <p className="text-center text-[12px] text-[#a89878] py-4">कोई उपलब्ध कर्मचारी नहीं</p>
              ) : modalStaff.map(s => {
                const isSel = form.selectedIds.includes(s.id)
                return (
                  <button key={s.id} type="button" onClick={() => toggleStaff(s.id)}
                    className={`w-full text-left px-3 py-2 text-[12px] transition-colors border-b border-[#8b734b]/10 last:border-0 flex items-center justify-between ${isSel ? 'bg-[#8b6914] text-white' : 'text-[#2c2416] hover:bg-[#ede5d0]'}`}>
                    <span>
                      <span className="font-medium">{s.name}</span>
                      <span className={`ml-2 font-mono text-[11px] ${isSel ? 'text-white/70' : 'text-[#a89878]'}`}>{s.pno}</span>
                    </span>
                    {isSel && <Check size={13} className="shrink-0" />}
                  </button>
                )
              })}
            </div>
            {form.selectedIds.length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1.5">
                {form.selectedIds.map(id => {
                  const s = staff.find(x => x.id === id)
                  return s ? (
                    <span key={id} className="inline-flex items-center gap-1 bg-[#8b6914]/10 text-[#8b6914] text-[11px] font-medium px-2 py-0.5 rounded-full border border-[#8b6914]/20">
                      {s.name}
                      <button type="button" onClick={() => toggleStaff(id)} className="hover:text-red-600"><X size={10} /></button>
                    </span>
                  ) : null
                })}
              </div>
            )}
          </div>

          <div>
            <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">केंद्र चुनें <span className="text-red-500">*</span></label>
            <div className="relative">
              <ChevronDown size={13} className="absolute right-3 top-1/2 -translate-y-1/2 text-[#a89878] pointer-events-none" />
              <select value={form.centerId} onChange={e => setForm(p => ({ ...p, centerId: e.target.value }))} required
                className="appearance-none w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition pr-8">
                <option value="">— केंद्र चुनें —</option>
                {centers.map(c => <option key={c.id} value={c.id}>{c.name} ({c.sectorName})</option>)}
              </select>
            </div>
            {selectedCenter && (
              <div className="mt-2 bg-[#f0ead8] rounded-lg px-3 py-2 text-[11px] text-[#7a6a50]">
                <p className="font-semibold text-[#2c2416]">{selectedCenter.name}</p>
                {selectedCenter.address    && <p>{selectedCenter.address}</p>}
                {selectedCenter.sectorName && <p>सेक्टर: {selectedCenter.sectorName}</p>}
              </div>
            )}
          </div>

          <div>
            <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">बस नं0 <span className="text-[#a89878] font-normal">(वैकल्पिक)</span></label>
            <input
              className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
              placeholder="जैसे: BUS-3"
              value={form.busNo}
              onChange={e => setForm(p => ({ ...p, busNo: e.target.value }))}
            />
          </div>

          {form.selectedIds.length > 0 && form.centerId && (
            <div className="bg-[#f0ead8] rounded-lg px-3 py-2 text-[11px] text-[#7a6a50] flex items-center gap-2">
              <Users size={12} className="text-[#8b6914]" />
              <span>
                <strong className="text-[#8b6914]">{form.selectedIds.length}</strong> कर्मचारी को{' '}
                <strong className="text-[#2c2416]">{selectedCenter?.name}</strong> पर नियुक्त किया जाएगा
              </span>
            </div>
          )}

          <div className="flex gap-2 pt-1">
            <button type="button" onClick={closeModal}
              className="flex-1 bg-[#f5f0e8] hover:bg-[#ede5d0] text-[#7a6a50] text-[13px] font-medium py-2.5 rounded-lg transition-colors">
              रद्द करें
            </button>
            <button type="submit" disabled={saving || !form.selectedIds.length || !form.centerId}
              className="flex-1 bg-[#8b6914] hover:bg-[#7a5c10] disabled:opacity-50 text-white text-[13px] font-medium py-2.5 rounded-lg transition-colors flex items-center justify-center gap-2">
              {saving && <span className="w-3.5 h-3.5 border-2 border-white border-t-transparent rounded-full animate-spin" />}
              {saving ? 'लगाया जा रहा है…' : `ड्यूटी लगाएं${form.selectedIds.length > 1 ? ` (${form.selectedIds.length})` : ''}`}
            </button>
          </div>
        </form>
      </Modal>

      <ConfirmDialog open={!!confirm} onClose={() => setConfirm(null)} onConfirm={confirm?.action} message={confirm?.message} />
      {printDuty && <DutyCardPrint duty={printDuty} onClose={() => setPrintDuty(null)} />}
    </div>
  )
}