import { useEffect, useState, useRef, useMemo } from 'react'
import { Plus, Trash2, Search, Printer, X, ChevronDown, ChevronLeft, ChevronRight, Check, Users } from 'lucide-react'
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
   Inline cell helpers keep card JSX clean
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

/* ─────────────────────────────────────────────
   Officer block (reused for zonal/sector/super)
───────────────────────────────────────────── */
function OfficerBlock({ label, officers }) {
  return (
    <table style={{ borderCollapse:'collapse', width:'100%', fontSize:'9.5px' }}>
      <tbody>
        <tr>
          <td colSpan={4} style={{ border:'1px solid #000', background:'#e8e8e8', fontWeight:700,
            textAlign:'center', padding:'2px 4px' }}>{label}</td>
        </tr>
        {(!officers || officers.length === 0) ? (
          <tr><td colSpan={4} style={{ border:'1px solid #000', padding:'2px 4px',
            color:'#999', textAlign:'center' }}>—</td></tr>
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
   Duty Card Print Modal
───────────────────────────────────────────── */
function DutyCardPrint({ duty, onClose }) {
  const printRef = useRef()
  const logoUrl  = `${window.location.origin}/logo/logo.jpeg`

  const handlePrint = () => {
    const content = printRef.current.innerHTML
    const win = window.open('', '_blank', 'width=960,height=720')
    win.document.write(`
      <!DOCTYPE html><html><head>
      <meta charset="UTF-8"/>
      <title>ड्यूटी कार्ड – ${duty.name}</title>
      <link rel="preconnect" href="https://fonts.googleapis.com"/>
      <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;600;700&display=swap" rel="stylesheet"/>
      <style>
        *{margin:0;padding:0;box-sizing:border-box;}
        body{font-family:'Noto Sans Devanagari',Arial,sans-serif;background:#fff;-webkit-print-color-adjust:exact;print-color-adjust:exact;}
        @page{size:A4 portrait;margin:8mm;}
        table{border-collapse:collapse;width:100%;}
        td{border:1px solid #000;font-size:10px;padding:3px 5px;vertical-align:middle;}
        img{display:block;}
      </style>
      </head><body>${content}</body></html>
    `)
    win.document.close()
    win.onload = () => { win.print(); win.close() }
  }

  const sahyogi  = duty.sahyogi        || []
  const zonal    = duty.zonalOfficers  || []
  const sector   = duty.sectorOfficers || []
  const superOff = duty.superOfficers  || []

  // Minimum 8 sahyogi rows
  const sahRows = Array.from({ length: Math.max(8, sahyogi.length) }, (_, i) => sahyogi[i] || null)

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-5xl max-h-[92vh] overflow-y-auto">

        {/* Toolbar */}
        <div className="sticky top-0 bg-white border-b border-gray-200 px-5 py-3 flex items-center justify-between rounded-t-2xl z-10">
          <div>
            <p className="text-[13px] font-semibold text-[#2c2416]">ड्यूटी कार्ड पूर्वावलोकन</p>
            <p className="text-[11px] text-[#a89878]">{duty.name} · {duty.pno} · {duty.centerName}</p>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={handlePrint}
              className="inline-flex items-center gap-2 bg-[#8b6914] hover:opacity-90 text-white text-[12px] font-medium px-4 py-2 rounded-lg transition-opacity">
              <Printer size={13} /> प्रिंट करें
            </button>
            <button onClick={onClose}
              className="w-8 h-8 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-gray-100 transition-colors">
              <X size={15} />
            </button>
          </div>
        </div>

        {/* Card */}
        <div className="p-6">
          <div ref={printRef}>
            <table style={{ border:'2px solid #000', fontFamily:"'Noto Sans Devanagari',Arial,sans-serif",
              fontSize:'10px', borderCollapse:'collapse', width:'100%' }}>
              <tbody>

                {/* ══ HEADER ══ */}
                <tr>
                  <td colSpan={10} style={{ border:'2px solid #000', padding:'6px 10px' }}>
                    <div style={{ display:'flex', alignItems:'center', gap:10 }}>

                      {/* LEFT — logo image (matches StaffDutyPage) */}
                      <img
                        src={logoUrl}
                        alt="लोगो"
                        style={{ width:60, height:60, objectFit:'contain', flexShrink:0 }}
                      />

                      {/* CENTER — titles */}
                      <div style={{ flex:1, textAlign:'center' }}>
                        <div style={{ fontSize:17, fontWeight:700, letterSpacing:1 }}>ड्यूटी कार्ड</div>
                        <div style={{ fontSize:13, fontWeight:600 }}>लोकसभा सामान्य निर्वाचन–2024</div>
                        <div style={{ fontSize:11 }}>जनपद – {v(duty.district)}</div>
                        <div style={{ fontSize:10, fontWeight:600, borderTop:'1px solid #aaa', marginTop:3, paddingTop:2 }}>
                          मतदान चरण–द्वितीय &nbsp;|&nbsp; दिनांक: 26.04.2024 &nbsp;|&nbsp; प्रातः 07:00 से सांय 06:00 बजे तक
                        </div>
                      </div>

                      {/* RIGHT — UP Police circle */}
                      <div style={{
                        width:60, height:60, border:'2px solid #000', borderRadius:'50%',
                        display:'flex', alignItems:'center', justifyContent:'center',
                        fontSize:7, fontWeight:700, textAlign:'center', padding:3, flexShrink:0
                      }}>
                        उत्तर<br/>प्रदेश<br/>पुलिस
                      </div>

                    </div>
                  </td>
                </tr>

                {/* ══ PRIMARY OFFICER – headers ══ */}
                <tr>
                  <TH>पद</TH>
                  <TH>बैज / पुलिस नं0</TH>
                  <TH colSpan={2}>नाम</TH>
                  <TH>मोबाइल</TH>
                  <TH>थाना</TH>
                  <TH>जनपद</TH>
                  <TH>श्रेणी</TH>
                  <TH colSpan={2}>वाहन संख्या</TH>
                </tr>

                {/* ══ PRIMARY OFFICER – data ══ */}
                <tr>
                  <TD center bold>{rh(duty.rank)}</TD>
                  <TD center mono>{v(duty.pno)}</TD>
                  <TD colSpan={2} bold>{v(duty.name)}</TD>
                  <TD center>{v(duty.mobile)}</TD>
                  <TD center>{v(duty.staffThana)}</TD>
                  <TD center>{v(duty.district)}</TD>
                  <TD center>सशस्त्र</TD>
                  <TD colSpan={2} center bold>बस–{v(duty.busNo)}</TD>
                </tr>

                {/* ══ DUTY LOCATION – headers ══ */}
                <tr>
                  <TH colSpan={2}>ड्यूटी स्थान (केंद्र)</TH>
                  <TH>ग्राम पंचायत</TH>
                  <TH>सेक्टर</TH>
                  <TH>जोन</TH>
                  <TH colSpan={2}>सुपर जोन</TH>
                  <TH>ड्यूटी प्रकार</TH>
                  <TH colSpan={2}>केंद्र प्रकार</TH>
                </tr>

                {/* ══ DUTY LOCATION – data ══ */}
                <tr>
                  <TD colSpan={2} bold>{v(duty.centerName)}</TD>
                  <TD>{v(duty.gpName)}</TD>
                  <TD center>{v(duty.sectorName)}</TD>
                  <TD center>{v(duty.zoneName)}</TD>
                  <TD colSpan={2} center>{v(duty.superZoneName)}</TD>
                  <TD center>बूथ ड्यूटी</TD>
                  <TD colSpan={2} center>{v(duty.centerType)}</TD>
                </tr>

                {/* ══ SAHYOGI – header ══ */}
                <tr><TH colSpan={10}>सहयोगी कर्मचारी गण (एक ही केंद्र पर तैनात)</TH></tr>
                <tr style={{ background:'#f4f4f4' }}>
                  <TH>क्र0</TH>
                  <TH>पद</TH>
                  <TH colSpan={2}>नाम</TH>
                  <TH>बैज / पुलिस नं0</TH>
                  <TH>मोबाइल</TH>
                  <TH colSpan={2}>थाना</TH>
                  <TH colSpan={2}>जनपद</TH>
                </tr>

                {/* ══ SAHYOGI – rows ══ */}
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

                {/* ══ OFFICERS SECTION ══ */}
                <tr><TH colSpan={10}>अधिकारी विवरण</TH></tr>
                <tr>
                  <td colSpan={5} style={{ border:'1px solid #000', padding:0, verticalAlign:'top' }}>
                    <OfficerBlock label="जोनल अधिकारी" officers={zonal} />
                  </td>
                  <td colSpan={5} style={{ border:'1px solid #000', padding:0, verticalAlign:'top' }}>
                    <OfficerBlock label="सेक्टर अधिकारी" officers={sector} />
                  </td>
                </tr>
                {superOff.length > 0 && (
                  <tr>
                    <td colSpan={10} style={{ border:'1px solid #000', padding:0, verticalAlign:'top' }}>
                      <OfficerBlock label="क्षेत्र अधिकारी (सुपर जोन)" officers={superOff} />
                    </td>
                  </tr>
                )}

                {/* ══ FOOTER ══ */}
                <tr style={{ background:'#f8f8f8' }}>
                  <TD bold>सेक्टर नं0</TD>
                  <TD center>{v(duty.sectorName)}</TD>
                  <TD bold>जोन नं0</TD>
                  <TD center>{v(duty.zoneName)}</TD>
                  <TD bold>सुपर जोन</TD>
                  <TD colSpan={2} center>{v(duty.superZoneName)}</TD>
                  <TD colSpan={3} center style={{ fontSize:9, color:'#555' }}>
                    यह कार्ड चुनाव ड्यूटी का प्रमाण है। कृपया इसे सुरक्षित रखें।
                    &nbsp;|&nbsp; <strong>पुलिस अधीक्षक हस्ताक्षर: __________</strong>
                  </TD>
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
                  p === page ? 'bg-[#8b6914] text-white border-[#8b6914]'
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
   Main AdminDuties
───────────────────────────────────────────── */
export default function AdminDuties() {
  const [duties, setDuties]         = useState([])
  const [centers, setCenters]       = useState([])
  const [staff, setStaff]           = useState([])
  const [loading, setLoading]       = useState(true)
  const [addOpen, setAddOpen]       = useState(false)
  const [saving, setSaving]         = useState(false)
  const [confirm, setConfirm]       = useState(null)
  const [printDuty, setPrintDuty]   = useState(null)

  // Search & filter – all client-side; data is loaded once
  const [searchText, setSearchText] = useState('')
  const [filterCenter, setFilterCenter] = useState('')
  const [filterZone, setFilterZone]     = useState('')
  const [page, setPage]             = useState(1)

  // Assign modal
  const [form, setForm]             = useState({ selectedIds: [], centerId: '', busNo: '' })
  const [staffSearch, setStaffSearch] = useState('')

  /* ── Load once ── */
  useEffect(() => {
    Promise.all([adminAPI.getDuties(), adminAPI.allCenters(), adminAPI.getStaff()])
      .then(([d, c, s]) => { setDuties(d); setCenters(c); setStaff(s) })
      .catch(() => toast.error('डेटा लोड करने में विफल'))
      .finally(() => setLoading(false))
  }, [])

  const reload = () =>
    adminAPI.getDuties()
      .then(d => { setDuties(d); setPage(1) })
      .catch(() => toast.error('रीफ्रेश विफल'))

  /* ── Zone options derived from loaded duties ── */
  const zoneOptions = useMemo(() =>
    [...new Set(duties.map(d => d.zoneName).filter(Boolean))].sort()
  , [duties])

  /* ── Client-side filter ── */
  const filtered = useMemo(() => {
    const q = searchText.trim().toLowerCase()
    return duties.filter(d => {
      const matchQ = !q || [d.name, d.pno, d.mobile, d.staffThana, d.centerName, d.gpName, d.district]
        .some(f => f && String(f).toLowerCase().includes(q))
      const matchC = !filterCenter || d.centerName === filterCenter
      const matchZ = !filterZone   || d.zoneName   === filterZone
      return matchQ && matchC && matchZ
    })
  }, [duties, searchText, filterCenter, filterZone])

  const pagedDuties = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)
  const hasFilter   = searchText || filterCenter || filterZone

  /* ── Helpers that reset page on filter change ── */
  const setQ = (val) => { setSearchText(val);   setPage(1) }
  const setC = (val) => { setFilterCenter(val); setPage(1) }
  const setZ = (val) => { setFilterZone(val);   setPage(1) }
  const clearFilters = () => { setQ(''); setC(''); setZ('') }

  /* ── Already-assigned staff ids (hidden in modal list) ── */
  const assignedIds = useMemo(() => new Set(duties.map(d => d.staffId)), [duties])

  const filteredStaff = useMemo(() =>
    staff.filter(s =>
      !assignedIds.has(s.id) && (
        !staffSearch ||
        s.name.toLowerCase().includes(staffSearch.toLowerCase()) ||
        s.pno.includes(staffSearch)
      )
    )
  , [staff, assignedIds, staffSearch])

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

  /* ── Assign duty ── */
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

  /* ── Remove duty ── */
  const handleRemove = (id) => {
    setConfirm({
      message: 'क्या आप यह ड्यूटी हटाना चाहते हैं?',
      action: async () => {
        try {
          await adminAPI.removeDuty(id)
          setDuties(p => p.filter(d => d.id !== id))
          toast.success('ड्यूटी हटाई गई')
        } catch { toast.error('हटाने में विफल') }
        setConfirm(null)
      },
    })
  }

  const selectedCenter = centers.find(c => String(c.id) === String(form.centerId))

  if (loading) return <Spinner />

  return (
    <div>
      <PageHeader
        title="ड्यूटी आवंटन"
        subtitle={`कुल ${duties.length} आवंटन`}
        action={
          <button onClick={() => setAddOpen(true)}
            className="inline-flex items-center gap-2 bg-[#8b6914] hover:opacity-90 text-white text-[13px] font-medium px-4 py-2 rounded-lg transition-opacity">
            <Plus size={14} /> ड्यूटी लगाएं
          </button>
        }
      />

      {/* ══ SEARCH + FILTER BAR ══ */}
      <div className="mb-5 flex flex-wrap items-center gap-2">

        {/* Full-text search */}
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-[#a89878] pointer-events-none" />
          <input
            className="w-full bg-[#fdfaf5] border border-[#8b734b]/25 rounded-lg pl-8 pr-8 py-2 text-[13px] text-[#2c2416] placeholder-[#a89878] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition"
            placeholder="नाम, पुलिस नं0, मोबाइल, थाना, केंद्र…"
            value={searchText}
            onChange={e => setQ(e.target.value)}
          />
          {searchText && (
            <button onClick={() => setQ('')}
              className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[#a89878] hover:text-[#2c2416]">
              <X size={12} />
            </button>
          )}
        </div>

        {/* Center filter */}
        <div className="relative">
          <ChevronDown size={13} className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[#a89878] pointer-events-none" />
          <select
            value={filterCenter} onChange={e => setC(e.target.value)}
            className="appearance-none bg-[#fdfaf5] border border-[#8b734b]/25 rounded-lg px-3 py-2 pr-7 text-[13px] text-[#2c2416] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition">
            <option value="">सभी केंद्र</option>
            {[...new Set(duties.map(d => d.centerName).filter(Boolean))].sort().map(n => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>
        </div>

        {/* Zone filter */}
        <div className="relative">
          <ChevronDown size={13} className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[#a89878] pointer-events-none" />
          <select
            value={filterZone} onChange={e => setZ(e.target.value)}
            className="appearance-none bg-[#fdfaf5] border border-[#8b734b]/25 rounded-lg px-3 py-2 pr-7 text-[13px] text-[#2c2416] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition">
            <option value="">सभी जोन</option>
            {zoneOptions.map(z => <option key={z} value={z}>{z}</option>)}
          </select>
        </div>

        {hasFilter && (
          <>
            <button onClick={clearFilters}
              className="text-[12px] text-[#8b6914] hover:underline flex items-center gap-1 whitespace-nowrap">
              <X size={11} /> फ़िल्टर हटाएं
            </button>
            <span className="text-[11px] bg-[#f0ead8] text-[#7a6a50] px-2 py-1 rounded-full whitespace-nowrap">
              {filtered.length} परिणाम
            </span>
          </>
        )}
      </div>

      {/* ══ DESKTOP TABLE ══ */}
      <div className="hidden md:block bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-[13px] min-w-[820px]">
            <thead>
              <tr className="bg-[#f0ead8]">
                {['कर्मचारी का नाम', 'पुलिस नं0', 'मोबाइल', 'थाना', 'केंद्र', 'जोन / सुपर जोन', 'बस नं0', ''].map(h => (
                  <th key={h} className="px-4 py-2.5 text-left text-[11px] font-medium text-[#7a6a50] uppercase tracking-wide border-b border-[#8b734b]/15 whitespace-nowrap">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {pagedDuties.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-4 py-10 text-center text-[#a89878] text-[13px]">
                    {hasFilter ? 'खोज से कोई परिणाम नहीं मिला' : 'कोई ड्यूटी आवंटन नहीं मिला'}
                  </td>
                </tr>
              ) : pagedDuties.map(d => (
                <tr key={d.id} className="hover:bg-[#f5f0e8] transition-colors border-b border-[#8b734b]/10 last:border-0">
                  <td className="px-4 py-3">
                    <p className="font-medium text-[#2c2416]">{d.name}</p>
                    <p className="text-[11px] text-[#a89878]">{rh(d.rank)}</p>
                  </td>
                  <td className="px-4 py-3 font-mono text-[11px] text-[#a89878]">{d.pno}</td>
                  <td className="px-4 py-3 text-[#7a6a50]">{d.mobile || '—'}</td>
                  <td className="px-4 py-3 text-[#7a6a50]">{d.staffThana || '—'}</td>
                  <td className="px-4 py-3">
                    <p className="font-medium text-[#2c2416]">{d.centerName}</p>
                    <p className="text-[11px] text-[#a89878]">{d.gpName} · {d.sectorName}</p>
                  </td>
                  <td className="px-4 py-3">
                    <p className="text-[12px] text-[#7a6a50]">{d.zoneName || '—'}</p>
                    <p className="text-[11px] text-[#a89878]">{d.superZoneName || ''}</p>
                  </td>
                  <td className="px-4 py-3 text-[11px] text-[#7a6a50]">{d.busNo ? `बस-${d.busNo}` : '—'}</td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1.5">
                      <button onClick={() => setPrintDuty(d)} title="ड्यूटी कार्ड प्रिंट करें"
                        className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-medium bg-[#f0ead8] text-[#8b6914] hover:bg-[#8b6914] hover:text-white border border-[#8b6914]/30 transition-all">
                        <Printer size={11} /><span className="hidden lg:inline">प्रिंट</span>
                      </button>
                      <button onClick={() => handleRemove(d.id)}
                        className="w-7 h-7 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-[#f5e8e8] hover:text-[#7a2020] transition-all">
                        <Trash2 size={13} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* ══ MOBILE CARDS ══ */}
      <div className="md:hidden space-y-3">
        {pagedDuties.length === 0 ? (
          <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl px-4 py-10 text-center text-[#a89878] text-[13px]">
            {hasFilter ? 'खोज से कोई परिणाम नहीं मिला' : 'कोई ड्यूटी आवंटन नहीं मिला'}
          </div>
        ) : pagedDuties.map(d => (
          <div key={d.id} className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-4">
            <div className="flex items-start justify-between mb-2">
              <div>
                <p className="text-[14px] font-semibold text-[#2c2416]">{d.name}</p>
                <p className="text-[11px] text-[#a89878]">{rh(d.rank)} · {d.pno}</p>
              </div>
              <div className="flex items-center gap-1.5">
                <button onClick={() => setPrintDuty(d)}
                  className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-medium bg-[#f0ead8] text-[#8b6914] hover:bg-[#8b6914] hover:text-white border border-[#8b6914]/30 transition-all">
                  <Printer size={11} /> प्रिंट
                </button>
                <button onClick={() => handleRemove(d.id)}
                  className="w-7 h-7 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-[#f5e8e8] hover:text-[#7a2020] transition-all">
                  <Trash2 size={13} />
                </button>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-[12px]">
              <div><span className="text-[#a89878]">मोबाइल:</span> <span className="text-[#2c2416]">{d.mobile || '—'}</span></div>
              <div><span className="text-[#a89878]">थाना:</span> <span className="text-[#2c2416]">{d.staffThana || '—'}</span></div>
              <div className="col-span-2"><span className="text-[#a89878]">केंद्र:</span> <span className="text-[#2c2416] font-medium">{d.centerName}</span></div>
              <div><span className="text-[#a89878]">जोन:</span> <span className="text-[#2c2416]">{d.zoneName || '—'}</span></div>
              <div><span className="text-[#a89878]">बस:</span> <span className="text-[#2c2416]">{d.busNo ? `बस-${d.busNo}` : '—'}</span></div>
            </div>
          </div>
        ))}
      </div>

      <Pagination total={filtered.length} page={page} onChange={setPage} />

      {/* ══ ASSIGN MODAL ══ */}
      <Modal open={addOpen} onClose={closeModal} title="ड्यूटी लगाएं">
        <form onSubmit={handleAssign} className="space-y-4">

          {/* Staff multi-select */}
          <div>
            <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">
              कर्मचारी चुनें <span className="text-red-500">*</span>
              {form.selectedIds.length > 0 && (
                <span className="ml-2 bg-[#8b6914] text-white text-[10px] px-2 py-0.5 rounded-full">
                  {form.selectedIds.length} चयनित
                </span>
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
              {filteredStaff.length === 0 ? (
                <p className="text-center text-[12px] text-[#a89878] py-4">कोई उपलब्ध कर्मचारी नहीं</p>
              ) : filteredStaff.map(s => {
                const isSel = form.selectedIds.includes(s.id)
                return (
                  <button key={s.id} type="button" onClick={() => toggleStaff(s.id)}
                    className={`w-full text-left px-3 py-2 text-[12px] transition-colors border-b border-[#8b734b]/10 last:border-0 flex items-center justify-between ${
                      isSel ? 'bg-[#8b6914] text-white' : 'text-[#2c2416] hover:bg-[#ede5d0]'}`}>
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

          {/* Center */}
          <div>
            <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">
              केंद्र चुनें <span className="text-red-500">*</span>
            </label>
            <div className="relative">
              <ChevronDown size={13} className="absolute right-3 top-1/2 -translate-y-1/2 text-[#a89878] pointer-events-none" />
              <select
                value={form.centerId}
                onChange={e => setForm(p => ({ ...p, centerId: e.target.value }))}
                required
                className="appearance-none w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-lg px-3 py-2 text-[13px] text-[#2c2416] focus:outline-none focus:border-[#8b6914] focus:ring-1 focus:ring-[#8b6914]/30 transition pr-8">
                <option value="">— केंद्र चुनें —</option>
                {centers.map(c => <option key={c.id} value={c.id}>{c.name} ({c.sectorName})</option>)}
              </select>
            </div>
            {selectedCenter && (
              <div className="mt-2 bg-[#f0ead8] rounded-lg px-3 py-2 text-[11px] text-[#7a6a50]">
                <p className="font-semibold text-[#2c2416]">{selectedCenter.name}</p>
                {selectedCenter.address  && <p>{selectedCenter.address}</p>}
                {selectedCenter.sectorName && <p>सेक्टर: {selectedCenter.sectorName}</p>}
              </div>
            )}
          </div>

          {/* Bus */}
          <div>
            <label className="block text-[12px] font-medium text-[#7a6a50] mb-1.5">
              बस नं0 <span className="text-[#a89878] font-normal">(वैकल्पिक)</span>
            </label>
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
              className="flex-1 bg-[#8b6914] hover:opacity-90 disabled:opacity-50 text-white text-[13px] font-medium py-2.5 rounded-lg transition-opacity flex items-center justify-center gap-2">
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