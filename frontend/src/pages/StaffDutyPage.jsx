import { useEffect, useState, useRef } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import {
  MapPin, Bus, User, Users, Phone, Building2, Map,
  LogOut, Vote, Printer, ChevronRight, Menu, X,
  ShieldCheck, FileText, Home, KeyRound, Eye, EyeOff, Lock
} from 'lucide-react'
import { staffAPI } from '../services/api'
import { Spinner } from '../components/ui'
import { useAuth } from '../context/AuthContext'
import { useNavigate } from 'react-router-dom'
import toast from 'react-hot-toast'

const rankMap = {
  'constable': 'आरक्षी', 'head constable': 'मुख्य आरक्षी',
  'si': 'उप निरीक्षक', 'sub inspector': 'उप निरीक्षक',
  'inspector': 'निरीक्षक', 'asi': 'सहायक उप निरीक्षक',
  'assistant sub inspector': 'सहायक उप निरीक्षक',
  'dsp': 'उपाधीक्षक', 'sp': 'पुलिस अधीक्षक',
  'circle officer': 'क्षेत्राधिकारी', 'co': 'क्षेत्राधिकारी',
}
const rh = (val) => rankMap[(val || '').toLowerCase()] || val || '—'
const v  = (x) => x || '—'
const centerTypeMap = {
  'sensitive': 'संवेदनशील', 'normal': 'सामान्य',
  'critical': 'अति संवेदनशील', 'general': 'सामान्य',
}
const ct = (x) => centerTypeMap[(x || '').toLowerCase()] || x || '—'

const NAV = [
  { id: 'overview',  label: 'अवलोकन',        icon: Home      },
  { id: 'duty',      label: 'ड्यूटी विवरण',  icon: MapPin    },
  { id: 'staff',     label: 'सहयोगी कर्मी',  icon: Users     },
  { id: 'dutycard',  label: 'ड्यूटी कार्ड',  icon: FileText  },
  { id: 'password',  label: 'पासवर्ड बदलें',  icon: KeyRound  },
]

// ─── Inline cell helpers (identical to AdminDuties) ───────────
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

// ─── Officer Block (identical to AdminDuties) ─────────────────
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

// ─── Duty Card Print (identical layout to AdminDuties) ────────
function DutyCardPrint({ duty, user, onClose }) {
  const printRef = useRef()

  const handlePrint = () => {
    const content = printRef.current.innerHTML
    const win = window.open('', '_blank', 'width=960,height=720')
    win.document.write(`<!DOCTYPE html><html><head>
      <meta charset="UTF-8"/>
      <title>ड्यूटी कार्ड – ${duty.centerName || ''}</title>
      <link rel="preconnect" href="https://fonts.googleapis.com"/>
      <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;600;700&display=swap" rel="stylesheet"/>
      <style>
        *{margin:0;padding:0;box-sizing:border-box;}
        body{font-family:'Noto Sans Devanagari',Arial,sans-serif;background:#fff;-webkit-print-color-adjust:exact;print-color-adjust:exact;}
        @page{size:A4 portrait;margin:8mm;}
        table{border-collapse:collapse;width:100%;}
        td{border:1px solid #000;font-size:10px;padding:3px 5px;vertical-align:middle;}
      </style></head><body>${content}</body></html>`)
    win.document.close()
    win.onload = () => { win.print(); win.close() }
  }

  const allStaff = duty.allStaff        || []
  const zonal    = duty.zonalOfficers   || []
  const sector   = duty.sectorOfficers  || []
  const superOff = duty.superOfficers   || []
  const sahRows  = Array.from({ length: Math.max(8, allStaff.length) }, (_, i) => allStaff[i] || null)

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-3">
      <motion.div
        initial={{ scale:0.95, opacity:0 }} animate={{ scale:1, opacity:1 }}
        className="bg-white rounded-2xl shadow-2xl w-full max-w-5xl max-h-[93vh] flex flex-col overflow-hidden"
      >
        {/* Toolbar */}
        <div className="flex-shrink-0 bg-[#f8f5ef] border-b border-[#ddd5c0] px-5 py-3 flex items-center justify-between">
          <div>
            <p className="text-[13px] font-bold text-[#2c2416]">ड्यूटी कार्ड पूर्वावलोकन</p>
            <p className="text-[11px] text-[#a89878]">{v(user?.name)} · {v(user?.pno)} · {v(duty.centerName)}</p>
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

        {/* Card Preview */}
        <div className="overflow-y-auto p-6">
          <div ref={printRef}>
            <table style={{
              border:'2px solid #000',
              fontFamily:"'Noto Sans Devanagari',Arial,sans-serif",
              fontSize:'10px', borderCollapse:'collapse', width:'100%'
            }}>
              <tbody>

                {/* ══ HEADER ══ */}
                <tr>
                  <td colSpan={10} style={{ border:'2px solid #000', padding:'6px 10px' }}>
                    <div style={{ display:'flex', alignItems:'center', gap:10 }}>

                      {/* LEFT — logo (circular, identical to AdminDuties) */}
                      <div style={{ width:54, height:54, border:'2px solid #000', borderRadius:'50%',
                        overflow:'hidden', flexShrink:0, display:'flex', alignItems:'center', justifyContent:'center' }}>
                        <img src="/logo/logo.jpeg" alt="Logo"
                          style={{ width:'100%', height:'100%', objectFit:'cover', display:'block' }} />
                      </div>

                      {/* CENTER — titles */}
                      <div style={{ flex:1, textAlign:'center' }}>
                        <div style={{ fontSize:17, fontWeight:700, letterSpacing:1 }}>ड्यूटी कार्ड</div>
                        <div style={{ fontSize:13, fontWeight:600 }}>लोकसभा सामान्य निर्वाचन–2024</div>
                        <div style={{ fontSize:11 }}>जनपद – {v(duty.district || user?.district)}</div>
                        <div style={{ fontSize:10, fontWeight:600, borderTop:'1px solid #aaa', marginTop:3, paddingTop:2 }}>
                          मतदान चरण–द्वितीय &nbsp;|&nbsp; दिनांक: 26.04.2024 &nbsp;|&nbsp; प्रातः 07:00 से सांय 06:00 बजे तक
                        </div>
                      </div>

                      {/* RIGHT — UP Police circle */}
                      <div style={{
                        width:54, height:54, border:'2px solid #000', borderRadius:'50%',
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
                  <TD center bold>{rh(user?.rank)}</TD>
                  <TD center mono>{v(user?.pno)}</TD>
                  <TD colSpan={2} bold>{v(user?.name)}</TD>
                  <TD center>{v(user?.mobile)}</TD>
                  <TD center>{v(user?.thana)}</TD>
                  <TD center>{v(user?.district)}</TD>
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
                  <TD colSpan={2} center>{ct(duty.centerType)}</TD>
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
                  <tr key={i} style={{ background: i%2===0 ? '#fff' : '#fafafa' }}>
                    <TD center style={{ color:'#888', fontSize:9 }}>{i+1}</TD>
                    <TD center style={{ color: s?'#000':'#ccc' }}>{s ? rh(s.rank) : '—'}</TD>
                    <TD colSpan={2} style={{ color: s?'#000':'#ccc', fontWeight: s?500:400 }}>{s ? v(s.name) : '—'}</TD>
                    <TD center mono style={{ color: s?'#000':'#ccc' }}>{s ? v(s.pno) : '—'}</TD>
                    <TD center style={{ color: s?'#000':'#ccc' }}>{s ? v(s.mobile) : '—'}</TD>
                    <TD colSpan={2} center style={{ color: s?'#000':'#ccc' }}>{s ? v(s.thana) : '—'}</TD>
                    <TD colSpan={2} center style={{ color: s?'#000':'#ccc' }}>{s ? v(s.district) : '—'}</TD>
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
      </motion.div>
    </div>
  )
}

// ─── Password Input ───────────────────────────────────────────
function PasswordInput({ label, value, onChange, placeholder }) {
  const [show, setShow] = useState(false)
  return (
    <div>
      <label className="block text-[12px] font-semibold text-[#7a6a50] mb-1.5">{label}</label>
      <div className="relative">
        <input
          type={show ? 'text' : 'password'}
          value={value}
          onChange={onChange}
          placeholder={placeholder}
          required
          className="w-full bg-[#f5f0e8] border border-[#8b734b]/25 rounded-xl px-3 py-2.5 pr-10 text-[13px] text-[#2c2416] placeholder-[#c4b49a] focus:outline-none focus:border-[#8b6914] focus:ring-2 focus:ring-[#8b6914]/20 transition"
        />
        <button type="button" onClick={() => setShow(s => !s)}
          className="absolute right-3 top-1/2 -translate-y-1/2 text-[#a89878] hover:text-[#8b6914] transition-colors">
          {show ? <EyeOff size={15} /> : <Eye size={15} />}
        </button>
      </div>
    </div>
  )
}

// ─── Change Password Section ──────────────────────────────────
function ChangePasswordSection() {
  const [form, setForm]     = useState({ current: '', next: '', confirm: '' })
  const [saving, setSaving] = useState(false)
  const [done, setDone]     = useState(false)
  const set = (key) => (e) => setForm(p => ({ ...p, [key]: e.target.value }))

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (form.next.length < 6) { toast.error('नया पासवर्ड कम से कम 6 अक्षर का होना चाहिए'); return }
    if (form.next !== form.confirm) { toast.error('नया पासवर्ड और पुष्टि पासवर्ड मेल नहीं खाते'); return }
    setSaving(true)
    try {
      await staffAPI.changePassword({ currentPassword: form.current, newPassword: form.next })
      toast.success('पासवर्ड सफलतापूर्वक बदल दिया गया')
      setDone(true)
      setForm({ current: '', next: '', confirm: '' })
    } catch (err) {
      toast.error(err?.response?.data?.message || 'पासवर्ड बदलने में विफल')
    } finally {
      setSaving(false)
    }
  }

  const score = (() => {
    const p = form.next
    return (p.length >= 6 ? 1 : 0) + (p.length >= 10 ? 1 : 0) +
           (/[A-Z]/.test(p) || /[0-9]/.test(p) ? 1 : 0) + (/[^A-Za-z0-9]/.test(p) ? 1 : 0)
  })()
  const scoreColors = ['bg-red-400','bg-orange-400','bg-yellow-400','bg-green-500']
  const scoreLabels = ['','बहुत छोटा','ठीक है','अच्छा','बहुत मजबूत']

  return (
    <div className="space-y-4">
      <div className="bg-gradient-to-br from-[#2c2416] to-[#4a3a1e] rounded-2xl p-5 text-white">
        <div className="flex items-center gap-3 mb-2">
          <div className="w-10 h-10 rounded-xl bg-white/10 flex items-center justify-center">
            <Lock size={18} className="text-white" />
          </div>
          <div>
            <p className="font-bold text-[15px]">पासवर्ड बदलें</p>
            <p className="text-white/60 text-[11px]">अपना लॉगिन पासवर्ड अपडेट करें</p>
          </div>
        </div>
        <p className="text-white/50 text-[11px] mt-3 leading-relaxed">
          सुरक्षा के लिए नियमित रूप से अपना पासवर्ड बदलते रहें। पासवर्ड कम से कम 6 अक्षर का होना चाहिए।
        </p>
      </div>

      <AnimatePresence>
        {done && (
          <motion.div initial={{ opacity:0, y:-8 }} animate={{ opacity:1, y:0 }} exit={{ opacity:0 }}
            className="flex items-center gap-3 bg-[#e6f0e0] border border-[#2d5a1e]/20 rounded-xl px-4 py-3">
            <ShieldCheck size={16} className="text-[#2d5a1e] flex-shrink-0" />
            <p className="text-[#2d5a1e] text-[13px] font-semibold">पासवर्ड सफलतापूर्वक बदल दिया गया!</p>
          </motion.div>
        )}
      </AnimatePresence>

      <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-2xl overflow-hidden">
        <div className="flex items-center gap-2.5 px-5 py-3.5 bg-[#f0ead8] border-b border-[#8b734b]/15">
          <div className="w-7 h-7 rounded-lg bg-[#8b6914]/10 flex items-center justify-center">
            <KeyRound size={14} className="text-[#8b6914]" />
          </div>
          <h2 className="font-bold text-[#2c2416] text-[14px]">नया पासवर्ड सेट करें</h2>
        </div>
        <form onSubmit={handleSubmit} className="px-5 py-5 space-y-4">
          <PasswordInput label="वर्तमान पासवर्ड *" value={form.current} onChange={set('current')} placeholder="अपना मौजूदा पासवर्ड डालें" />
          <div className="border-t border-[#8b734b]/10 pt-4 space-y-4">
            <PasswordInput label="नया पासवर्ड * (न्यूनतम 6 अक्षर)" value={form.next} onChange={set('next')} placeholder="नया पासवर्ड डालें" />
            <PasswordInput label="नया पासवर्ड पुनः डालें *" value={form.confirm} onChange={set('confirm')} placeholder="पासवर्ड की पुष्टि करें" />
          </div>

          {form.next.length > 0 && (
            <div>
              <p className="text-[11px] text-[#a89878] mb-1.5">पासवर्ड मजबूती</p>
              <div className="flex gap-1">
                {[1,2,3,4].map(i => (
                  <div key={i} className={`h-1.5 flex-1 rounded-full transition-all duration-300 ${
                    i <= score ? scoreColors[score-1] : 'bg-[#e0d8c8]'
                  }`} />
                ))}
              </div>
              <p className="text-[10px] mt-1 text-[#a89878]">{scoreLabels[score] || ''}</p>
            </div>
          )}

          {form.confirm.length > 0 && (
            <div className={`flex items-center gap-2 text-[12px] font-medium ${
              form.next === form.confirm ? 'text-[#2d5a1e]' : 'text-[#c0392b]'
            }`}>
              {form.next === form.confirm
                ? <><ShieldCheck size={13} /> पासवर्ड मेल खाते हैं</>
                : <><X size={13} /> पासवर्ड मेल नहीं खाते</>}
            </div>
          )}

          <button type="submit" disabled={saving}
            className="w-full bg-[#8b6914] hover:opacity-90 disabled:opacity-60 text-white text-[13px] font-bold py-2.5 rounded-xl transition-opacity flex items-center justify-center gap-2 mt-2">
            {saving
              ? <><div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" /> बदल रहा है…</>
              : <><KeyRound size={14} /> पासवर्ड बदलें</>}
          </button>
        </form>
      </div>

      <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-2xl px-5 py-4">
        <p className="text-[12px] font-bold text-[#7a6a50] mb-2.5 uppercase tracking-wide">सुरक्षा सुझाव</p>
        <div className="space-y-2">
          {[
            'पासवर्ड कम से कम 6 अक्षर का रखें',
            'अक्षर, अंक और विशेष चिह्न मिलाकर उपयोग करें',
            'अपना पासवर्ड किसी के साथ साझा न करें',
            'नियमित रूप से पासवर्ड बदलते रहें',
          ].map((tip, i) => (
            <div key={i} className="flex items-start gap-2">
              <div className="w-1.5 h-1.5 rounded-full bg-[#8b6914]/50 mt-1.5 flex-shrink-0" />
              <p className="text-[12px] text-[#a89878]">{tip}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

// ─── Info Row ─────────────────────────────────────────────────
function InfoRow({ icon: Icon, label, value, mono }) {
  if (!value || value === '—') return null
  return (
    <div className="flex items-start gap-3 py-3 border-b border-[#8b734b]/10 last:border-0">
      <div className="w-8 h-8 rounded-lg bg-[#f0ead8] flex items-center justify-center flex-shrink-0 mt-0.5">
        <Icon size={14} className="text-[#8b6914]" />
      </div>
      <div className="min-w-0">
        <p className="text-[10px] font-semibold text-[#a89878] uppercase tracking-wider mb-0.5">{label}</p>
        <p className={`text-[#2c2416] font-semibold text-sm break-words ${mono ? 'font-mono' : ''}`}>{value}</p>
      </div>
    </div>
  )
}

// ─── Section Wrapper ──────────────────────────────────────────
function Section({ title, icon: Icon, children }) {
  return (
    <motion.div initial={{ opacity:0, y:12 }} animate={{ opacity:1, y:0 }} transition={{ duration:0.3 }}
      className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-2xl overflow-hidden">
      <div className="flex items-center gap-2.5 px-5 py-3.5 bg-[#f0ead8] border-b border-[#8b734b]/15">
        <div className="w-7 h-7 rounded-lg bg-[#8b6914]/10 flex items-center justify-center">
          <Icon size={14} className="text-[#8b6914]" />
        </div>
        <h2 className="font-bold text-[#2c2416] text-[14px]">{title}</h2>
      </div>
      <div className="px-5 py-1">{children}</div>
    </motion.div>
  )
}

// ─── Main Page ────────────────────────────────────────────────
export default function StaffDutyPage() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()
  const [duty, setDuty]       = useState(null)
  const [loading, setLoading] = useState(true)
  const [noDuty, setNoDuty]   = useState(false)
  const [activeSection, setActiveSection] = useState('overview')
  const [sidebarOpen, setSidebarOpen]     = useState(false)
  const [showPrint, setShowPrint]         = useState(false)

  useEffect(() => {
    staffAPI.myDuty()
      .then((data) => { if (!data) { setNoDuty(true); return }; setDuty(data) })
      .catch(() => toast.error('ड्यूटी लोड करने में विफल'))
      .finally(() => setLoading(false))
  }, [])

  const handleLogout = () => { logout(); toast.success('लॉग आउट हो गए'); navigate('/login') }
  const goTo = (id) => { setActiveSection(id); setSidebarOpen(false) }

  const SidebarContent = () => (
    <div className="flex flex-col h-full">
      <div className="px-5 py-5 border-b border-[#8b734b]/20">
        <div className="flex items-center gap-3">
          <img src="/logo/logo.jpeg" alt="लोगो"
            className="w-9 h-9 rounded-xl object-contain" />
          <div>
            <p className="text-[#2c2416] font-bold text-[13px] leading-tight">चुनाव प्रकोष्ठ</p>
            <p className="text-[#a89878] text-[10px]">मतदान ड्यूटी पोर्टल</p>
          </div>
        </div>
      </div>

      <nav className="flex-1 px-3 py-4 space-y-1">
        {NAV.map(({ id, label, icon: Icon }) => (
          <button key={id} onClick={() => goTo(id)}
            className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-[13px] font-medium transition-all ${
              activeSection === id
                ? 'bg-[#8b6914] text-white shadow-sm'
                : 'text-[#7a6a50] hover:bg-[#f0ead8] hover:text-[#2c2416]'
            }`}>
            <Icon size={15} />
            {label}
            {activeSection === id && <ChevronRight size={13} className="ml-auto" />}
          </button>
        ))}
      </nav>

      <div className="px-4 py-4 border-t border-[#8b734b]/20">
        <div className="flex items-center gap-2.5 mb-3">
          <div className="w-8 h-8 rounded-full bg-[#8b6914]/15 flex items-center justify-center">
            <User size={14} className="text-[#8b6914]" />
          </div>
          <div className="min-w-0">
            <p className="text-[#2c2416] font-semibold text-[12px] truncate">{user?.name}</p>
            <p className="text-[#a89878] text-[10px] font-mono">{user?.pno}</p>
          </div>
        </div>
        <button onClick={handleLogout}
          className="w-full flex items-center justify-center gap-2 py-2 rounded-xl border border-[#8b734b]/25 text-[#a89878] hover:border-[#c0392b]/40 hover:text-[#c0392b] hover:bg-[#fdf0f0] text-[12px] font-medium transition-all">
          <LogOut size={13} /> लॉग आउट
        </button>
      </div>
    </div>
  )

  const renderContent = () => {
    if (loading) return <div className="flex items-center justify-center h-64"><Spinner /></div>

    if (activeSection === 'password') return <ChangePasswordSection />

    if (activeSection === 'overview') return (
      <div className="space-y-4">
        <motion.div initial={{ opacity:0, y:10 }} animate={{ opacity:1, y:0 }}
          className="bg-gradient-to-br from-[#8b6914] to-[#6b500f] rounded-2xl p-5 text-white">
          <p className="text-white/60 text-[11px] uppercase tracking-widest font-semibold mb-1">स्वागत है</p>
          <h1 className="text-xl font-bold mb-0.5">{user?.name}</h1>
          <p className="text-white/70 text-[12px] font-mono">{user?.pno}</p>
          <div className="mt-4 pt-4 border-t border-white/20 flex items-center gap-2">
            <ShieldCheck size={14} className="text-white/60" />
            <span className="text-white/70 text-[12px]">
              {noDuty ? 'कोई ड्यूटी नहीं सौंपी गई' : `ड्यूटी: ${duty?.centerName || '—'}`}
            </span>
          </div>
        </motion.div>

        {!noDuty && duty && (
          <div className="grid grid-cols-2 gap-3">
            {[
              { label:'बूथ / केंद्र',  value: duty.centerName,                        icon: MapPin  },
              { label:'बस संख्या',     value: duty.busNo ? `बस–${duty.busNo}` : '—',  icon: Bus     },
              { label:'सेक्टर',        value: duty.sectorName,                         icon: Map     },
              { label:'सहयोगी कर्मी', value: `${duty.allStaff?.length||0} कर्मी`,     icon: Users   },
            ].map(({ label, value, icon: Icon }) => (
              <motion.div key={label} initial={{ opacity:0, scale:0.97 }} animate={{ opacity:1, scale:1 }}
                className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-xl p-3.5">
                <div className="w-7 h-7 rounded-lg bg-[#f0ead8] flex items-center justify-center mb-2">
                  <Icon size={13} className="text-[#8b6914]" />
                </div>
                <p className="text-[10px] text-[#a89878] font-medium uppercase tracking-wide">{label}</p>
                <p className="text-[13px] font-bold text-[#2c2416] mt-0.5 truncate">{value || '—'}</p>
              </motion.div>
            ))}
          </div>
        )}

        {noDuty && (
          <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-2xl p-8 text-center">
            <MapPin size={36} className="mx-auto mb-3 text-[#a89878] opacity-40" />
            <p className="text-[#2c2416] font-bold text-base mb-1">अभी तक ड्यूटी नहीं सौंपी गई</p>
            <p className="text-[#a89878] text-sm">व्यवस्थापक द्वारा ड्यूटी सौंपे जाने पर यहाँ दिखेगी।</p>
          </div>
        )}
      </div>
    )

    if (activeSection === 'duty') {
      if (noDuty) return (
        <div className="bg-[#fdfaf5] border border-[#8b734b]/20 rounded-2xl p-8 text-center">
          <MapPin size={36} className="mx-auto mb-3 text-[#a89878] opacity-40" />
          <p className="text-[#2c2416] font-bold">ड्यूटी नहीं सौंपी गई</p>
        </div>
      )
      return (
        <div className="space-y-4">
          <Section title="ड्यूटी स्थान विवरण" icon={MapPin}>
            <InfoRow icon={MapPin}    label="मतदान केंद्र"   value={duty.centerName} />
            <InfoRow icon={MapPin}    label="केंद्र पता"     value={duty.centerAddress} />
            <InfoRow icon={Building2} label="केंद्र प्रकार" value={ct(duty.centerType)} />
            <InfoRow icon={Building2} label="थाना"           value={duty.thana} />
            <InfoRow icon={Building2} label="ग्राम पंचायत"  value={duty.gpName} />
          </Section>
          <Section title="प्रशासनिक विवरण" icon={Map}>
            <InfoRow icon={Map}  label="सेक्टर"       value={duty.sectorName} />
            <InfoRow icon={Map}  label="जोन"           value={duty.zoneName} />
            <InfoRow icon={Map}  label="जोन मुख्यालय" value={duty.zoneHq} />
            <InfoRow icon={Map}  label="सुपर जोन"     value={duty.superZoneName} />
            <InfoRow icon={Bus}  label="बस संख्या"    value={duty.busNo ? `बस–${duty.busNo}` : null} />
            <InfoRow icon={User} label="नियुक्त किया"  value={duty.assignedBy} />
          </Section>
          {duty.latitude && duty.longitude && (
            <a href={`https://www.google.com/maps?q=${duty.latitude},${duty.longitude}`}
              target="_blank" rel="noreferrer"
              className="flex items-center justify-center gap-2 w-full py-3 rounded-xl bg-[#8b6914] text-white text-[13px] font-bold hover:opacity-90 transition-opacity">
              <MapPin size={15} /> गूगल मैप्स पर खोलें
            </a>
          )}
        </div>
      )
    }

    if (activeSection === 'staff') {
      const staff = duty?.allStaff || []
      return (
        <Section title={`सहयोगी कर्मी (${staff.length})`} icon={Users}>
          {staff.length === 0 ? (
            <div className="py-8 text-center">
              <Users size={32} className="mx-auto mb-2 text-[#a89878] opacity-40" />
              <p className="text-[#a89878] text-sm">कोई सहयोगी कर्मी नहीं मिला</p>
            </div>
          ) : (
            <div className="divide-y divide-[#8b734b]/10">
              {staff.map((s, i) => (
                <div key={i} className="flex items-center justify-between py-3">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-[#f0ead8] flex items-center justify-center flex-shrink-0">
                      <span className="text-[#8b6914] text-[11px] font-bold">{i+1}</span>
                    </div>
                    <div>
                      <p className="text-[#2c2416] text-[13px] font-semibold">{s.name}</p>
                      <p className="text-[#a89878] text-[11px] font-mono">{v(s.pno)} · {v(s.thana)}</p>
                    </div>
                  </div>
                  {s.mobile && (
                    <a href={`tel:${s.mobile}`}
                      className="w-8 h-8 rounded-xl bg-[#e6f0e0] flex items-center justify-center text-[#2d5a1e] hover:bg-[#d0e8c8] transition-colors">
                      <Phone size={14} />
                    </a>
                  )}
                </div>
              ))}
            </div>
          )}
        </Section>
      )
    }

    if (activeSection === 'dutycard') return (
      <div className="space-y-4">
        <Section title="ड्यूटी कार्ड" icon={FileText}>
          <div className="py-4 text-center space-y-3">
            <div className="w-16 h-16 rounded-2xl bg-[#f0ead8] flex items-center justify-center mx-auto overflow-hidden">
              <img src="/logo/logo.jpeg" alt="लोगो" className="w-full h-full object-contain" />
            </div>
            <div>
              <p className="text-[#2c2416] font-bold text-base">ड्यूटी कार्ड प्रिंट करें</p>
              <p className="text-[#a89878] text-[12px] mt-1 max-w-xs mx-auto">
                आधिकारिक चुनाव ड्यूटी कार्ड देखें और प्रिंट करें।
              </p>
            </div>
            {noDuty ? (
              <p className="text-[#c0392b] text-[12px] font-medium">ड्यूटी सौंपे जाने के बाद ही कार्ड उपलब्ध होगा।</p>
            ) : (
              <button onClick={() => setShowPrint(true)}
                className="inline-flex items-center gap-2 bg-[#8b6914] hover:opacity-90 text-white text-[13px] font-bold px-6 py-2.5 rounded-xl transition-opacity">
                <Printer size={15} /> ड्यूटी कार्ड देखें / प्रिंट करें
              </button>
            )}
          </div>
        </Section>

        {!noDuty && duty && (
          <Section title="कार्ड में शामिल जानकारी" icon={ShieldCheck}>
            {[
              ['कर्मी का नाम',  user?.name],
              ['पुलिस नं0',     user?.pno],
              ['मतदान केंद्र',  duty.centerName],
              ['बस संख्या',     duty.busNo ? `बस–${duty.busNo}` : '—'],
              ['सेक्टर / जोन',  `${duty.sectorName} / ${duty.zoneName}`],
              ['सुपर जोन',      duty.superZoneName],
              ['सहयोगी कर्मी', `${duty.allStaff?.length||0} कर्मी`],
            ].map(([label, val]) => (
              <div key={label} className="flex items-center justify-between py-2.5 border-b border-[#8b734b]/10 last:border-0">
                <span className="text-[#a89878] text-[12px]">{label}</span>
                <span className="text-[#2c2416] text-[12px] font-semibold text-right max-w-[55%]">{val || '—'}</span>
              </div>
            ))}
          </Section>
        )}
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#f5f0e8] flex">

      {/* Desktop Sidebar */}
      <aside className="hidden lg:flex flex-col w-64 bg-[#fdfaf5] border-r border-[#8b734b]/20 fixed inset-y-0 left-0 z-30">
        <SidebarContent />
      </aside>

      {/* Mobile Sidebar */}
      <AnimatePresence>
        {sidebarOpen && (
          <>
            <motion.div initial={{ opacity:0 }} animate={{ opacity:1 }} exit={{ opacity:0 }}
              onClick={() => setSidebarOpen(false)}
              className="fixed inset-0 bg-black/40 z-40 lg:hidden" />
            <motion.aside
              initial={{ x:-280 }} animate={{ x:0 }} exit={{ x:-280 }}
              transition={{ type:'spring', damping:28, stiffness:280 }}
              className="fixed inset-y-0 left-0 w-64 bg-[#fdfaf5] border-r border-[#8b734b]/20 z-50 flex flex-col lg:hidden">
              <div className="absolute top-3 right-3">
                <button onClick={() => setSidebarOpen(false)}
                  className="w-8 h-8 rounded-lg flex items-center justify-center text-[#a89878] hover:bg-[#f0ead8]">
                  <X size={16} />
                </button>
              </div>
              <SidebarContent />
            </motion.aside>
          </>
        )}
      </AnimatePresence>

      {/* Main Content */}
      <div className="flex-1 lg:ml-64 flex flex-col min-h-screen">
        <header className="sticky top-0 z-20 bg-[#fdfaf5]/90 backdrop-blur-md border-b border-[#8b734b]/15 px-4 py-3 flex items-center gap-3">
          <button onClick={() => setSidebarOpen(true)}
            className="lg:hidden w-8 h-8 rounded-lg flex items-center justify-center text-[#7a6a50] hover:bg-[#f0ead8]">
            <Menu size={18} />
          </button>
          <div className="flex-1">
            <p className="text-[#2c2416] font-bold text-[14px]">
              {NAV.find(n => n.id === activeSection)?.label}
            </p>
            <p className="text-[#a89878] text-[10px] hidden sm:block">{user?.name} · {user?.pno}</p>
          </div>
          <div className="flex items-center gap-1.5">
            <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
            <span className="text-[11px] text-[#a89878] hidden sm:inline">सक्रिय</span>
          </div>
        </header>

        <main className="flex-1 px-4 py-5 max-w-2xl mx-auto w-full">
          <AnimatePresence mode="wait">
            <motion.div key={activeSection}
              initial={{ opacity:0, x:8 }} animate={{ opacity:1, x:0 }} exit={{ opacity:0, x:-8 }}
              transition={{ duration:0.2 }}>
              {renderContent()}
            </motion.div>
          </AnimatePresence>
        </main>
      </div>

      {/* Print Modal */}
      <AnimatePresence>
        {showPrint && duty && (
          <DutyCardPrint duty={duty} user={user} onClose={() => setShowPrint(false)} />
        )}
      </AnimatePresence>
    </div>
  )
}