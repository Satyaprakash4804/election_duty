import { useEffect, useState, useRef } from 'react'
import { Printer, ChevronDown, Edit2, Save, X, Loader2, Building2, Map, Landmark } from 'lucide-react'
import { Spinner } from '../../components/ui'
import toast from 'react-hot-toast'

// ─── API ─────────────────────────────────────────────────────────────────────

const API = 'http://127.0.0.1:5000/api/admin'

function authHeaders() {
  return { 'Content-Type': 'application/json' }
}

async function patchRecord(table, id, body) {
  const res = await fetch(API + '/hierarchy/update', {
    method: 'PATCH',
    headers: authHeaders(),
    body: JSON.stringify({ table, id, ...body }),
  })
  if (!res.ok) throw new Error('Update failed')
  return res.json()
}

// ─── API DATA ACCESSORS ───────────────────────────────────────────────────────
// The API returns officers[] arrays. These helpers extract the first officer
// for display in the hierarchy tables.

function firstOfficer(officers) {
  return officers?.[0] || null
}

function officerName(officers) {
  return firstOfficer(officers)?.name || '—'
}

function officerMobile(officers) {
  return firstOfficer(officers)?.mobile || ''
}

function officerPno(officers) {
  return firstOfficer(officers)?.pno || ''
}

function officerRank(officers) {
  return firstOfficer(officers)?.user_rank || ''
}

// For sectors, the API returns officers[] which includes both the magistrate
// and the sector police officer entries. We show all of them.
function allOfficers(officers) {
  return officers || []
}

// ─── TABLE CELL STYLES ────────────────────────────────────────────────────────

const pTh = (extra = {}) => ({
  border: '1px solid #888',
  padding: '5px 6px',
  background: '#f5ead0',
  fontWeight: '700',
  fontSize: '10px',
  textAlign: 'center',
  verticalAlign: 'middle',
  lineHeight: 1.3,
  color: '#1a1a1a',
  ...extra,
})

const pTd = (extra = {}) => ({
  border: '1px solid #bbb',
  padding: '4px 6px',
  fontSize: '10px',
  verticalAlign: 'top',
  lineHeight: 1.4,
  color: '#1a1a1a',
  ...extra,
})

// ─── EDIT PANEL ───────────────────────────────────────────────────────────────

function EditPanel({ item, table, fields, onClose, onSaved }) {
  const [vals, setVals] = useState({ ...item })
  const [saving, setSaving] = useState(false)

  const handleSave = async () => {
    setSaving(true)
    try {
      await patchRecord(table, item.id, vals)
      toast.success('सफलतापूर्वक सहेजा गया')
      onSaved(vals)
      onClose()
    } catch {
      toast.error('सहेजने में विफल')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 50, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,.5)' }}>
      <div style={{ background: '#fff', borderRadius: 16, boxShadow: '0 24px 64px rgba(15,43,91,.18)', width: 500, maxHeight: '88vh', display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 20px', borderBottom: '1px solid #e8edf7' }}>
          <span style={{ fontWeight: 700, fontSize: 14, color: '#0f2b5b' }}>रिकॉर्ड संपादित करें</span>
          <button onClick={onClose} style={{ width: 28, height: 28, borderRadius: 8, border: 'none', background: '#f0f2f5', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#6b7c93' }}>
            <X size={14} />
          </button>
        </div>
        <div style={{ overflowY: 'auto', flex: 1, padding: '16px 20px' }}>
          {fields.map(({ key, label, multiline, section }) => (
            <div key={key || section}>
              {section && (
                <div style={{ fontSize: 10, fontWeight: 700, color: '#0f2b5b', textTransform: 'uppercase', letterSpacing: '1px', background: '#f0f4ff', padding: '4px 8px', borderRadius: 6, margin: '12px 0 8px', borderLeft: '3px solid #0f2b5b' }}>
                  {section}
                </div>
              )}
              {key && (
                <div style={{ marginBottom: 12 }}>
                  <label style={{ display: 'block', fontSize: 10, fontWeight: 600, color: '#6b7c93', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 4 }}>{label}</label>
                  {multiline ? (
                    <textarea
                      rows={3}
                      value={vals[key] || ''}
                      onChange={e => setVals(p => ({ ...p, [key]: e.target.value }))}
                      style={{ width: '100%', background: '#f7f8fa', border: '1px solid #d6dbe4', borderRadius: 8, padding: '8px 10px', fontSize: 12, color: '#1a2332', outline: 'none', resize: 'vertical', boxSizing: 'border-box', fontFamily: "'Noto Sans Devanagari', sans-serif" }}
                    />
                  ) : (
                    <input
                      value={vals[key] || ''}
                      onChange={e => setVals(p => ({ ...p, [key]: e.target.value }))}
                      style={{ width: '100%', background: '#f7f8fa', border: '1px solid #d6dbe4', borderRadius: 8, padding: '8px 10px', fontSize: 12, color: '#1a2332', outline: 'none', boxSizing: 'border-box', fontFamily: "'Noto Sans Devanagari', sans-serif" }}
                    />
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
        <div style={{ padding: '12px 20px', borderTop: '1px solid #e8edf7' }}>
          <button
            onClick={handleSave}
            disabled={saving}
            style={{ width: '100%', background: saving ? '#8a9ab0' : '#0f2b5b', color: '#fff', border: 'none', borderRadius: 10, padding: '11px', fontSize: 13, fontWeight: 600, cursor: saving ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontFamily: "'Noto Sans Devanagari', sans-serif" }}
          >
            {saving ? <Loader2 size={14} style={{ animation: 'spin 1s linear infinite' }} /> : <Save size={14} />}
            {saving ? 'सहेज रहा है…' : 'परिवर्तन सहेजें'}
          </button>
        </div>
      </div>
    </div>
  )
}

// ─── FILTER SELECT ────────────────────────────────────────────────────────────

function FilterSelect({ label, value, onChange, options, placeholder = 'All' }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 155 }}>
      <label style={{ fontSize: 10, fontWeight: 700, color: '#6b7c93', textTransform: 'uppercase', letterSpacing: '0.5px' }}>{label}</label>
      <div style={{ position: 'relative' }}>
        <select
          value={value}
          onChange={e => onChange(e.target.value)}
          style={{ width: '100%', appearance: 'none', background: '#fff', border: '1.5px solid #d6dbe4', borderRadius: 8, padding: '7px 32px 7px 12px', fontSize: 12, fontWeight: 500, color: value ? '#0f2b5b' : '#8a9ab0', cursor: 'pointer', outline: 'none', fontFamily: "'Noto Sans Devanagari', sans-serif" }}
        >
          <option value="">{placeholder}</option>
          {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
        <ChevronDown size={13} style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: '#8a9ab0', pointerEvents: 'none' }} />
      </div>
    </div>
  )
}

// ─── PRINT HOOK ───────────────────────────────────────────────────────────────

function usePrint() {
  const ref = useRef()
  const print = (title) => {
    const win = window.open('', '_blank')
    win.document.write(`
      <html><head><title>${title}</title>
      <style>
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;600;700;900&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: 'Noto Sans Devanagari', sans-serif; font-size: 11px; color: #1a1a1a; padding: 16px; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
        th, td { border: 1px solid #aaa; padding: 4px 6px; vertical-align: top; }
        th { background: #f5ead0; font-weight: 700; text-align: center; vertical-align: middle; }
        @media print { body { padding: 8px; } @page { margin: 10mm; } }
      </style></head><body>
      ${ref.current?.innerHTML || ''}
      </body></html>
    `)
    win.document.close()
    setTimeout(() => { win.print(); win.close() }, 400)
  }
  return { ref, print }
}

// ─── HELPERS ──────────────────────────────────────────────────────────────────

function EmptyState({ text }) {
  return (
    <div style={{ textAlign: 'center', padding: '56px 24px', color: '#8a9ab0' }}>
      <div style={{ fontSize: 36, marginBottom: 12 }}>📋</div>
      <div style={{ fontSize: 14, fontWeight: 500 }}>{text}</div>
    </div>
  )
}

function CardShell({ header, children }) {
  return (
    <div style={{ background: '#fff', borderRadius: 12, border: '1px solid #e8edf7', overflow: 'hidden', boxShadow: '0 2px 12px rgba(15,43,91,.06)', marginBottom: 24 }}>
      {header}
      <div style={{ overflowX: 'auto' }}>{children}</div>
    </div>
  )
}

function Chip({ label, accent = '#fbbf24' }) {
  return (
    <div style={{ background: 'rgba(255,255,255,.15)', borderRadius: 7, padding: '4px 10px', fontSize: 11, fontWeight: 700, color: accent }}>
      {label}
    </div>
  )
}

function EditBtn({ onClick, label = '' }) {
  return (
    <button
      onClick={onClick}
      title={label || 'संपादित करें'}
      style={{ background: 'rgba(255,255,255,.18)', border: 'none', borderRadius: 7, minWidth: 28, height: 28, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 4, cursor: 'pointer', color: '#fff', padding: '0 8px', fontSize: 11, fontFamily: "'Noto Sans Devanagari', sans-serif" }}
    >
      <Edit2 size={12} />
      {label && <span>{label}</span>}
    </button>
  )
}

function SmallEditBtn({ onClick, title = 'संपादित करें' }) {
  return (
    <button
      onClick={onClick}
      title={title}
      style={{ background: '#e8f0fe', border: 'none', borderRadius: 4, width: 20, height: 20, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#0f2b5b', flexShrink: 0 }}
    >
      <Edit2 size={10} />
    </button>
  )
}

const printBtnStyle = {
  marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 6,
  background: '#0f2b5b', color: '#fff', border: 'none', borderRadius: 9,
  padding: '8px 18px', fontSize: 12, fontWeight: 600, cursor: 'pointer',
  fontFamily: "'Noto Sans Devanagari', sans-serif",
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 1 — सुपर जोन  (Image 1)
// API shape:  sz.officers[], z.officers[], s.officers[], s.panchayats[].name, gp.thana
// ════════════════════════════════════════════════════════════════════════════

function SuperZoneTab({ data, onEdit }) {
  const [selSZ, setSelSZ] = useState('')
  const { ref, print } = usePrint()

  const szOpts = data.map(sz => ({ value: sz.id, label: `सुपर जोन–${sz.name}` }))
  const visible = selSZ ? data.filter(sz => sz.id === selSZ) : data

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 16, marginBottom: 20, flexWrap: 'wrap' }}>
        <FilterSelect label="सुपर जोन चुनें" value={selSZ} onChange={setSelSZ} options={szOpts} placeholder="सभी सुपर जोन" />
        <button onClick={() => print('सुपर जोन — रिपोर्ट')} style={printBtnStyle}>
          <Printer size={13} /> प्रिंट करें
        </button>
      </div>
      <div ref={ref} style={{ fontFamily: "'Noto Sans Devanagari', sans-serif" }}>
        {visible.length === 0 && <EmptyState text="कोई डेटा नहीं मिला" />}
        {visible.map(sz => <SuperZoneBlock key={sz.id} sz={sz} onEdit={onEdit} />)}
      </div>
    </div>
  )
}

function SuperZoneBlock({ sz, onEdit }) {
  // officer from API officers[]
  const szOfficer = firstOfficer(sz.officers)

  const totalGPs = sz.zones?.reduce((a, z) =>
    a + (z.sectors?.reduce((b, s) => b + (s.panchayats?.length || 0), 0) || 0), 0) || 0

  // Build one row per sector, globally numbered
  const rows = []
  let sNum = 0
  sz.zones?.forEach((z, zi) => {
    const zLen = z.sectors?.length || 1
    z.sectors?.forEach((s, si) => {
      sNum++
      rows.push({ z, zi, si, s, sNum, zLen })
    })
    if (!z.sectors || z.sectors.length === 0) {
      rows.push({ z, zi, si: 0, s: null, sNum: null, zLen: 1 })
    }
  })

  return (
    <CardShell
      header={
        <div style={{ background: 'linear-gradient(135deg, #0f2b5b 0%, #1a3d7c 100%)', padding: '12px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
          <div>
            <div style={{ fontSize: 15, fontWeight: 800, color: '#fff' }}>
              सुपर जोन–{sz.name}
              {sz.block && <span style={{ color: '#fbbf24', marginLeft: 8, fontWeight: 700 }}>ब्लाक {sz.block}</span>}
              {sz.district && <span style={{ color: 'rgba(255,255,255,.6)', fontSize: 11, fontWeight: 400, marginLeft: 8 }}>({sz.district})</span>}
            </div>
            {szOfficer && (
              <div style={{ fontSize: 11, color: 'rgba(255,255,255,.7)', marginTop: 2 }}>
                {szOfficer.user_rank && <span>{szOfficer.user_rank} </span>}
                {szOfficer.name}
                {szOfficer.mobile && <span style={{ marginLeft: 8 }}>· {szOfficer.mobile}</span>}
              </div>
            )}
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Chip label={`कुल ग्राम पंचायत: ${totalGPs}`} accent="#fbbf24" />
            <EditBtn onClick={() => onEdit(sz, 'super_zones')} />
          </div>
        </div>
      }
    >
      <table style={{ width: '100%', borderCollapse: 'collapse', tableLayout: 'fixed', minWidth: 780 }}>
        <colgroup>
          <col style={{ width: 52 }} /><col style={{ width: 38 }} />
          <col style={{ width: 130 }} /><col style={{ width: 110 }} />
          <col style={{ width: 42 }} /><col style={{ width: 130 }} />
          <col style={{ width: 110 }} /><col /><col style={{ width: 70 }} />
        </colgroup>
        <thead>
          <tr>
            <th style={pTh()}>सुपर<br />जोन</th>
            <th style={pTh()}>जोन</th>
            <th style={pTh()}>जोनल अधिकारी</th>
            <th style={pTh()}>मुख्यालय</th>
            <th style={pTh()}>सैक्टर</th>
            <th style={pTh()}>सैक्टर पुलिस अधिकारी<br />का नाम</th>
            <th style={pTh()}>मुख्यालय</th>
            <th style={pTh()}>सैक्टर में लगने वाले ग्राम पंचायत का नाम</th>
            <th style={pTh()}>थाना</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(({ z, zi, si, s, sNum, zLen }, ri) => {
            // Zone officer from API officers[]
            const zOfficer = firstOfficer(z.officers)
            // Sector officer from API officers[] — first entry
            const sOfficer = s ? firstOfficer(s.officers) : null

            const gpNames = s?.panchayats?.map(gp => gp.name).join(', ') || '—'
            const thanas  = [...new Set(s?.panchayats?.flatMap(gp => gp.thana ? [gp.thana] : []))].join(', ') || '—'
            const isFirstRow = ri === 0

            return (
              <tr key={`${z.id}-${si}`} style={{ background: (sNum || 0) % 2 === 0 ? '#fffdf8' : '#fff' }}>
                {/* Super Zone — vertical, spans all rows */}
                {isFirstRow && (
                  <td rowSpan={rows.length} style={pTd({ textAlign: 'center', verticalAlign: 'middle', padding: '6px 2px' })}>
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
                      <div style={{ writingMode: 'vertical-rl', transform: 'rotate(180deg)', fontWeight: 700, fontSize: 9, color: '#cc0000' }}>
                        सुपर जोनल अधिकारी
                      </div>
                      {szOfficer?.name && (
                        <div style={{ writingMode: 'vertical-rl', transform: 'rotate(180deg)', fontSize: 8, color: '#cc0000' }}>
                          {szOfficer.name}
                        </div>
                      )}
                      <SmallEditBtn onClick={() => onEdit(sz, 'super_zones')} title="सुपर जोन संपादित करें" />
                    </div>
                  </td>
                )}
                {/* Zone — spans its sectors */}
                {si === 0 && (
                  <>
                    <td rowSpan={zLen} style={pTd({ textAlign: 'center', fontWeight: 900, fontSize: 18, verticalAlign: 'middle', color: '#0f2b5b' })}>
                      <div>{zi + 1}</div>
                      <div style={{ margin: '4px auto 0', display: 'flex', justifyContent: 'center' }}>
                        <SmallEditBtn onClick={() => onEdit(z, 'zones')} title="जोन संपादित करें" />
                      </div>
                    </td>
                    {/* Zone officer name from officers[] */}
                    <td rowSpan={zLen} style={pTd({ verticalAlign: 'middle', fontWeight: 600 })}>
                      {zOfficer ? (
                        <div>
                          {zOfficer.user_rank && <div style={{ fontSize: 9, color: '#6b7c93' }}>{zOfficer.user_rank}</div>}
                          <div>{zOfficer.name}</div>
                          {zOfficer.pno && <div style={{ fontSize: 9, color: '#8a9ab0' }}>PNO: {zOfficer.pno}</div>}
                        </div>
                      ) : '—'}
                    </td>
                    {/* HQ from zone.hq_address */}
                    <td rowSpan={zLen} style={pTd({ verticalAlign: 'middle', color: '#3d4f63' })}>
                      {z.hq_address || '—'}
                    </td>
                  </>
                )}
                {/* Sector number */}
                <td style={pTd({ textAlign: 'center', fontWeight: 700, fontSize: 12, color: '#186a3b', verticalAlign: 'middle' })}>
                  {sNum || '—'}
                </td>
                {/* Sector officer name from officers[] */}
                <td style={pTd()}>
                  <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 4 }}>
                    <div>
                      {sOfficer ? (
                        <>
                          {sOfficer.user_rank && <div style={{ fontSize: 9, color: '#6b7c93' }}>{sOfficer.user_rank}</div>}
                          <div style={{ fontWeight: 600 }}>{sOfficer.name}</div>
                          {sOfficer.pno && <div style={{ fontSize: 9, color: '#8a9ab0' }}>PNO: {sOfficer.pno}</div>}
                        </>
                      ) : (s?.name || '—')}
                    </div>
                    {s && <SmallEditBtn onClick={() => onEdit(s, 'sectors')} title="सैक्टर संपादित करें" />}
                  </div>
                </td>
                {/* Sector HQ — sector.name used as HQ label since API has no hq field on sectors */}
                <td style={pTd({ color: '#3d4f63' })}>{s?.name || '—'}</td>
                {/* Gram Panchayat names */}
                <td style={pTd()}>{gpNames}</td>
                {/* Thana derived from GPs */}
                <td style={pTd({ color: '#3d4f63' })}>{thanas}</td>
              </tr>
            )
          })}
          {rows.length === 0 && (
            <tr><td colSpan={9} style={pTd({ textAlign: 'center', color: '#8a9ab0', padding: 14 })}>कोई सेक्टर नहीं</td></tr>
          )}
        </tbody>
      </table>
    </CardShell>
  )
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 2 — सैक्टर  (Image 2 — detailed sector view with matdan sthal)
// API: z.officers[], s.officers[], gp.centers[], center.kendras[], center.duty_officers[]
// ════════════════════════════════════════════════════════════════════════════

function SectorTab({ data, onEdit }) {
  const [selSZ, setSelSZ]     = useState('')
  const [selZone, setSelZone] = useState('')
  const { ref, print }        = usePrint()

  const szOpts     = data.map(sz => ({ value: sz.id, label: `सुपर जोन–${sz.name}` }))
  const activeSZ   = data.find(sz => sz.id === selSZ)
  const zoneOpts   = (activeSZ?.zones || []).map(z => ({ value: z.id, label: z.name }))

  const pairs = []
  const szPool = selSZ ? data.filter(sz => sz.id === selSZ) : data
  szPool.forEach(sz => {
    const zPool = selZone ? sz.zones?.filter(z => z.id === selZone) : sz.zones || []
    zPool.forEach((z, zi) => {
      const globalZi = sz.zones?.findIndex(x => x.id === z.id) ?? zi
      pairs.push({ sz, z, zoneIdx: globalZi + 1 })
    })
  })

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 16, marginBottom: 20, flexWrap: 'wrap' }}>
        <FilterSelect label="सुपर जोन" value={selSZ} onChange={v => { setSelSZ(v); setSelZone('') }} options={szOpts} placeholder="सभी" />
        <FilterSelect label="जोन" value={selZone} onChange={setSelZone} options={zoneOpts} placeholder="सभी" />
        <button onClick={() => print('सैक्टर रिपोर्ट')} style={printBtnStyle}>
          <Printer size={13} /> प्रिंट करें
        </button>
      </div>
      <div ref={ref} style={{ fontFamily: "'Noto Sans Devanagari', sans-serif" }}>
        {pairs.length === 0 && <EmptyState text="कोई डेटा नहीं मिला" />}
        {pairs.map(({ sz, z, zoneIdx }) => (
          <SectorBlock key={z.id} zone={z} sz={sz} zoneIdx={zoneIdx} onEdit={onEdit} />
        ))}
      </div>
    </div>
  )
}

function SectorBlock({ zone, sz, zoneIdx, onEdit }) {
  const zOfficer = firstOfficer(zone.officers)

  // Flat rows: one per matdan_sthal (center)
  const allRows = []
  let sSeq = 0
  zone.sectors?.forEach((s, si) => {
    sSeq++
    if (!s.panchayats || s.panchayats.length === 0) {
      allRows.push({ s, si, sSeq, gp: null, c: null })
    } else {
      s.panchayats.forEach(gp => {
        if (!gp.centers || gp.centers.length === 0) {
          allRows.push({ s, si, sSeq, gp, c: null })
        } else {
          gp.centers.forEach(c => allRows.push({ s, si, sSeq, gp, c }))
        }
      })
    }
  })

  return (
    <CardShell
      header={
        <div style={{ background: 'linear-gradient(135deg, #186a3b 0%, #1e8449 100%)', padding: '12px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
          <div>
            <div style={{ fontSize: 14, fontWeight: 800, color: '#fff' }}>
              जोन: {zone.name}
              <span style={{ fontWeight: 400, fontSize: 12, color: 'rgba(255,255,255,.7)', marginLeft: 10 }}>
                — सुपर जोन: {sz.name} ({sz.block})
              </span>
            </div>
            {zOfficer && (
              <div style={{ fontSize: 11, color: 'rgba(255,255,255,.75)', marginTop: 2 }}>
                {zOfficer.user_rank && <span>{zOfficer.user_rank} </span>}
                जोनल अधिकारी: {zOfficer.name}
                {zOfficer.mobile && <span style={{ marginLeft: 8 }}>· {zOfficer.mobile}</span>}
              </div>
            )}
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <Chip label={`${zone.sectors?.length || 0} सैक्टर`} accent="rgba(255,255,255,.9)" />
            <EditBtn onClick={() => onEdit(zone, 'zones')} />
          </div>
        </div>
      }
    >
      {/* Intro banner */}
      <div style={{ background: '#f7f8fa', borderBottom: '1px solid #e8edf7', padding: '7px 16px', fontSize: 10, color: '#4a5568' }}>
        श्री ............................................. — अपर पुलिस अधीक्षक जनपद {sz.district || '...................'} — ब्लाक {sz.block || sz.name} / {zone.name}
      </div>

      <table style={{ width: '100%', borderCollapse: 'collapse', tableLayout: 'fixed', minWidth: 720 }}>
        <colgroup>
          <col style={{ width: 140 }} /><col style={{ width: 36 }} /><col style={{ width: 36 }} />
          <col style={{ width: 190 }} /><col style={{ width: 100 }} /><col /><col style={{ width: 110 }} />
        </colgroup>
        <thead>
          <tr>
            <th style={pTh()}>सुपर जोन व अधिकारी</th>
            <th style={pTh()}>जोन<br />नं.</th>
            <th style={pTh()}>सैक्टर</th>
            <th style={pTh()}>सैक्टर मजिस्ट्रेट /<br />सैक्टर पुलिस अधिकारी</th>
            <th style={pTh()}>ग्राम<br />पंचायत</th>
            <th style={pTh()}>मतदेय स्थल</th>
            <th style={pTh()}>मतदान केन्द्र</th>
          </tr>
        </thead>
        <tbody>
          {allRows.map((row, ri) => {
            const { s, si, sSeq, gp, c } = row
            const isFirst    = ri === 0
            const isFirstSec = ri === 0 || allRows[ri - 1].s.id !== s.id
            const isFirstGP  = isFirstSec || (gp && ri > 0 && allRows[ri - 1].gp?.id !== gp?.id)
            const secLen     = allRows.filter(r => r.s.id === s.id).length
            const gpLen      = gp ? allRows.filter(r => r.gp?.id === gp.id && r.s.id === s.id).length : 1

            // All officers for sector (API returns array — show all)
            const sOfficers = allOfficers(s?.officers)
            const szOfficer = firstOfficer(sz.officers)

            return (
              <tr key={ri} style={{ background: ri % 2 === 0 ? '#fff' : '#fffdf8' }}>
                {/* Super Zone + Zone info — spans ALL rows */}
                {isFirst && (
                  <td rowSpan={allRows.length} style={pTd({ verticalAlign: 'top', padding: '8px 6px' })}>
                    <div style={{ fontWeight: 800, fontSize: 11, color: '#0f2b5b', marginBottom: 2 }}>
                      सुपर जोन–{sz.name}
                    </div>
                    {szOfficer && (
                      <>
                        {szOfficer.user_rank && <div style={{ fontSize: 9, color: '#6b7c93' }}>{szOfficer.user_rank}</div>}
                        <div style={{ fontSize: 10, fontWeight: 600, marginTop: 2 }}>{szOfficer.name}</div>
                        {szOfficer.mobile && <div style={{ fontSize: 9, color: '#6b7c93', marginTop: 1 }}>मो.– {szOfficer.mobile}</div>}
                      </>
                    )}
                    <div style={{ borderTop: '1px dashed #d6dbe4', margin: '6px 0' }} />
                    <div style={{ fontWeight: 700, fontSize: 10, color: '#186a3b' }}>{zone.name}</div>
                    {zOfficer && (
                      <>
                        <div style={{ fontSize: 9, marginTop: 2 }}>{zOfficer.name}</div>
                        {zOfficer.mobile && <div style={{ fontSize: 9, color: '#6b7c93', marginTop: 1 }}>मो.– {zOfficer.mobile}</div>}
                      </>
                    )}
                    <button
                      onClick={() => onEdit(sz, 'super_zones')}
                      style={{ marginTop: 6, background: '#e8f0fe', border: 'none', borderRadius: 4, width: '100%', padding: '3px 0', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4, color: '#0f2b5b', fontSize: 9 }}
                    >
                      <Edit2 size={9} /> संपादित
                    </button>
                  </td>
                )}
                {/* Zone number */}
                {isFirst && (
                  <td rowSpan={allRows.length} style={pTd({ textAlign: 'center', verticalAlign: 'middle', fontWeight: 900, fontSize: 16, color: '#0f2b5b' })}>
                    {zoneIdx}
                  </td>
                )}
                {/* Sector number */}
                {isFirstSec && (
                  <td rowSpan={secLen} style={pTd({ textAlign: 'center', fontWeight: 700, color: '#186a3b', fontSize: 12, verticalAlign: 'top', paddingTop: 6 })}>
                    {sSeq}
                  </td>
                )}
                {/* Sector officers — all entries from officers[] */}
                {isFirstSec && (
                  <td rowSpan={secLen} style={pTd({ verticalAlign: 'top' })}>
                    {sOfficers.length > 0 ? sOfficers.map((o, oi) => (
                      <div key={o.id} style={{ marginBottom: oi < sOfficers.length - 1 ? 6 : 0, paddingBottom: oi < sOfficers.length - 1 ? 6 : 0, borderBottom: oi < sOfficers.length - 1 ? '1px dashed #e2e8f0' : 'none' }}>
                        {o.user_rank && <div style={{ fontSize: 9, color: '#6b7c93' }}>{o.user_rank}</div>}
                        <div style={{ fontWeight: 600, fontSize: 10 }}>{o.name}</div>
                        {o.pno && <div style={{ fontSize: 9, color: '#0f2b5b' }}>PNO: {o.pno}</div>}
                        {o.mobile && <div style={{ fontSize: 9, color: '#6b7c93' }}>मो.– {o.mobile}</div>}
                      </div>
                    )) : <span style={{ color: '#8a9ab0' }}>—</span>}
                    {s?.name && (
                      <div style={{ fontSize: 9, color: '#8a9ab0', marginTop: 4 }}>सैक्टर: {s.name}</div>
                    )}
                    {s && (
                      <button
                        onClick={() => onEdit(s, 'sectors')}
                        style={{ marginTop: 5, background: '#e8f0fe', border: 'none', borderRadius: 4, width: '100%', padding: '3px 0', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4, color: '#0f2b5b', fontSize: 9 }}
                      >
                        <Edit2 size={9} /> सैक्टर संपादित
                      </button>
                    )}
                  </td>
                )}
                {/* GP */}
                {gp && isFirstGP && (
                  <td rowSpan={gpLen} style={pTd({ verticalAlign: 'middle', fontWeight: 600 })}>
                    <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 4 }}>
                      <span>{gp.name}</span>
                      <SmallEditBtn onClick={() => onEdit(gp, 'gram_panchayats')} title="संपादित करें" />
                    </div>
                  </td>
                )}
                {!gp && isFirstSec && (
                  <td rowSpan={secLen} style={pTd({ color: '#8a9ab0', textAlign: 'center', verticalAlign: 'middle' })}>—</td>
                )}
                {/* Matdey Sthal — center.name from API */}
                <td style={pTd()}>
                  {c ? (
                    <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 4 }}>
                      <div>
                        <div style={{ fontWeight: 600 }}>{c.name || '—'}</div>
                        {c.address && <div style={{ fontSize: 9, color: '#6b7c93', marginTop: 1 }}>{c.address}</div>}
                        {c.thana && <div style={{ fontSize: 9, color: '#8a9ab0' }}>थाना: {c.thana}</div>}
                      </div>
                      <SmallEditBtn onClick={() => onEdit(c, 'matdan_sthal')} title="संपादित करें" />
                    </div>
                  ) : '—'}
                </td>
                {/* Matdan Kendra — room numbers from kendras[] */}
                <td style={pTd({ color: '#3d4f63' })}>
                  {c?.kendras?.length > 0
                    ? c.kendras.map((k, ki) => (
                        <div key={k.id} style={{ fontSize: 9, lineHeight: 1.6 }}>
                          क.नं.{k.room_number || ki + 1}
                        </div>
                      ))
                    : (c ? <span style={{ color: '#8a9ab0' }}>—</span> : '—')
                  }
                </td>
              </tr>
            )
          })}
          {allRows.length === 0 && (
            <tr><td colSpan={7} style={pTd({ textAlign: 'center', color: '#8a9ab0', padding: 14 })}>कोई डेटा नहीं</td></tr>
          )}
        </tbody>
      </table>
    </CardShell>
  )
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 3 — पंचायत / बूथ ड्यूटी  (Image 3)
// API: center.name, center.center_type, center.bus_no, center.thana,
//      center.kendras[], center.duty_officers[], center.address
// ════════════════════════════════════════════════════════════════════════════

function PanchayatTab({ data, onEdit }) {
  const [selSZ, setSelSZ]     = useState('')
  const [selZone, setSelZone] = useState('')
  const [selSec, setSelSec]   = useState('')
  const [selGP, setSelGP]     = useState('')
  const { ref, print }        = usePrint()

  const szOpts    = data.map(sz => ({ value: sz.id, label: `सुपर जोन–${sz.name}` }))
  const activeSZ  = data.find(sz => sz.id === selSZ)
  const zoneOpts  = (activeSZ?.zones || []).map(z => ({ value: z.id, label: z.name }))
  const activeZ   = activeSZ?.zones?.find(z => z.id === selZone)
  const secOpts   = (activeZ?.sectors || []).map(s => ({ value: s.id, label: s.name }))
  const activeS   = activeZ?.sectors?.find(s => s.id === selSec)
  const gpOpts    = (activeS?.panchayats || []).map(gp => ({ value: gp.id, label: gp.name }))

  const items = []
  const szPool = selSZ ? data.filter(sz => sz.id === selSZ) : data
  szPool.forEach(sz => {
    const zPool = selZone ? sz.zones?.filter(z => z.id === selZone) : sz.zones || []
    zPool.forEach(z => {
      const sPool = selSec ? z.sectors?.filter(s => s.id === selSec) : z.sectors || []
      sPool.forEach((s, si) => {
        const zIdx = sz.zones?.findIndex(x => x.id === z.id) + 1 || 1
        const sIdx = z.sectors?.findIndex(x => x.id === s.id) + 1 || si + 1
        const gpPool = selGP ? s.panchayats?.filter(gp => gp.id === selGP) : s.panchayats || []
        gpPool.forEach(gp => items.push({ sz, zone: z, sector: s, gp, zoneIdx: zIdx, sectorIdx: sIdx }))
      })
    })
  })

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 16, marginBottom: 20, flexWrap: 'wrap' }}>
        <FilterSelect label="सुपर जोन" value={selSZ} onChange={v => { setSelSZ(v); setSelZone(''); setSelSec(''); setSelGP('') }} options={szOpts} placeholder="सभी" />
        <FilterSelect label="जोन" value={selZone} onChange={v => { setSelZone(v); setSelSec(''); setSelGP('') }} options={zoneOpts} placeholder="सभी" />
        <FilterSelect label="सैक्टर" value={selSec} onChange={v => { setSelSec(v); setSelGP('') }} options={secOpts} placeholder="सभी" />
        <FilterSelect label="ग्राम पंचायत" value={selGP} onChange={setSelGP} options={gpOpts} placeholder="सभी" />
        <button onClick={() => print('बूथ ड्यूटी — पंचायत रिपोर्ट')} style={printBtnStyle}>
          <Printer size={13} /> प्रिंट करें
        </button>
      </div>
      <div ref={ref} style={{ fontFamily: "'Noto Sans Devanagari', sans-serif" }}>
        {items.length === 0 && <EmptyState text="कोई पंचायत नहीं मिली" />}
        {items.map(({ sz, zone, sector, gp, zoneIdx, sectorIdx }) => (
          <PanchayatBlock key={gp.id} gp={gp} sector={sector} zone={zone} sz={sz} zoneIdx={zoneIdx} sectorIdx={sectorIdx} onEdit={onEdit} />
        ))}
      </div>
    </div>
  )
}

function PanchayatBlock({ gp, sector, zone, sz, zoneIdx, sectorIdx, onEdit }) {
  // Flat rows: one per kendra. Center spans its kendra rows.
  const flatRows = []
  let kIdx = 0
  gp.centers?.forEach((center, ci) => {
    if (!center.kendras || center.kendras.length === 0) {
      kIdx++
      flatRows.push({ center, ci, kendra: null, kIdx })
    } else {
      center.kendras.forEach(kendra => {
        kIdx++
        flatRows.push({ center, ci, kendra, kIdx })
      })
    }
  })

  const totalBooths = kIdx

  return (
    <CardShell
      header={
        <div style={{ background: 'linear-gradient(135deg, #6c3483 0%, #7d3c98 100%)', padding: '12px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
          <div>
            <div style={{ fontSize: 14, fontWeight: 800, color: '#fff' }}>
              बूथ ड्यूटी —
              <span style={{ textDecoration: 'underline', marginLeft: 6, color: '#fbbf24' }}>ब्लॉक {sz.block || sz.name}</span>
              <span style={{ fontSize: 11, fontWeight: 400, color: 'rgba(255,255,255,.7)', marginLeft: 10 }}>
                मतदान दिनांक: ..../......./ 2026
              </span>
            </div>
            <div style={{ fontSize: 11, color: 'rgba(255,255,255,.75)', marginTop: 3, display: 'flex', gap: 14, flexWrap: 'wrap' }}>
              <span>मतदान केन्द्र: <strong>{gp.name}</strong></span>
              <span>सैक्टर: {sector.name}</span>
              <span>जोन: {zone.name}</span>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <Chip label={`मतदेय स्थल: ${gp.centers?.length || 0}`} accent="#fbbf24" />
            <Chip label={`कुल बूथ: ${totalBooths}`} accent="rgba(255,255,255,.9)" />
            <EditBtn onClick={() => onEdit(gp, 'gram_panchayats')} />
          </div>
        </div>
      }
    >
      {/* Sub-header matching Image 3 */}
      <div style={{ background: '#f7f8fa', borderBottom: '1px solid #e8edf7', padding: '6px 16px', fontSize: 10, color: '#4a5568', display: 'flex', gap: 24 }}>
        <span>मतदान केन्द्र–{gp.centers?.[0]?.name || gp.name}</span>
        <span>मतदेय स्थल–{gp.centers?.reduce((a, c) => a + (c.kendras?.length || 1), 0)}</span>
      </div>

      <table style={{ width: '100%', borderCollapse: 'collapse', tableLayout: 'fixed', minWidth: 800 }}>
        <colgroup>
          <col style={{ width: 38 }} /><col style={{ width: 130 }} /><col style={{ width: 40 }} />
          <col style={{ width: 130 }} /><col style={{ width: 34 }} /><col style={{ width: 40 }} />
          <col style={{ width: 65 }} /><col /><col style={{ width: 90 }} /><col style={{ width: 36 }} />
        </colgroup>
        <thead>
          <tr>
            <th style={pTh()}>मतदान<br />केन्द्र<br />की<br />संख्या</th>
            <th style={pTh()}>मतदान<br />केन्द्र<br />का नाम</th>
            <th style={pTh()}>मतदेय<br />स्थल<br />सं०</th>
            <th style={pTh()}>मतदेय<br />स्थल का<br />नाम</th>
            <th style={pTh()}>जोन<br />सं.</th>
            <th style={pTh()}>सेक्टर<br />सं.</th>
            <th style={pTh()}>थाना</th>
            <th style={pTh()}>ड्यूटी पर लगाया पुलिस का नाम</th>
            <th style={pTh()}>मोबाईल<br />नंबर</th>
            <th style={pTh()}>बस<br />नं</th>
          </tr>
        </thead>
        <tbody>
          {flatRows.map((row, ri) => {
            const { center, ci, kendra, kIdx: kNum } = row
            const isFirstOfCenter = ri === 0 || flatRows[ri - 1].center.id !== center.id
            const centerLen       = flatRows.filter(r => r.center.id === center.id).length

            // duty_officers from API (array)
            const dutyOfficers = center.duty_officers || []
            const dutyText = dutyOfficers.length > 0
              ? dutyOfficers.map(o =>
                  [o.user_rank, o.name, o.pno ? `– ${o.pno}` : ''].filter(Boolean).join(' ')
                ).join('\n')
              : '—'

            const dutyMobile = dutyOfficers.length > 0
              ? dutyOfficers.map(o => o.mobile).filter(Boolean).join('\n')
              : '—'

            // bus_no: from duty_officers[0].bus_no OR center.bus_no
            const busNo = center.bus_no || dutyOfficers[0]?.bus_no || '—'

            return (
              <tr key={ri} style={{ background: ci % 2 === 0 ? '#fff' : '#fffdf8' }}>
                {/* Center serial */}
                {isFirstOfCenter && (
                  <td rowSpan={centerLen} style={pTd({ textAlign: 'center', fontWeight: 700, verticalAlign: 'middle', fontSize: 12 })}>
                    {ci + 1}
                  </td>
                )}
                {/* Center name + type */}
                {isFirstOfCenter && (
                  <td rowSpan={centerLen} style={pTd({ verticalAlign: 'top' })}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 4 }}>
                      <div>
                        <div style={{ fontWeight: 600 }}>{center.name}</div>
                        {center.center_type && (
                          <div style={{
                            fontWeight: 800, fontSize: 12, marginTop: 3,
                            color: center.center_type === 'A' ? '#c0392b' : center.center_type === 'B' ? '#2980b9' : '#27ae60'
                          }}>
                            {center.center_type}
                          </div>
                        )}
                      </div>
                      <SmallEditBtn onClick={() => onEdit(center, 'matdan_sthal')} title="केन्द्र संपादित करें" />
                    </div>
                  </td>
                )}
                {/* Kendra sequential number */}
                <td style={pTd({ textAlign: 'center', verticalAlign: 'middle', fontWeight: 600 })}>
                  {kNum}
                </td>
                {/* Kendra sthal name — center.name + room_number from API */}
                <td style={pTd({ verticalAlign: 'middle' })}>
                  {kendra
                    ? `${center.name}${kendra.room_number ? ' क.नं. ' + kendra.room_number : ''}`
                    : (center.address || center.name || '—')
                  }
                </td>
                {/* Zone no */}
                {isFirstOfCenter && (
                  <td rowSpan={centerLen} style={pTd({ textAlign: 'center', verticalAlign: 'middle' })}>
                    {zoneIdx}
                  </td>
                )}
                {/* Sector no */}
                {isFirstOfCenter && (
                  <td rowSpan={centerLen} style={pTd({ textAlign: 'center', verticalAlign: 'middle' })}>
                    {sectorIdx}
                  </td>
                )}
                {/* Thana — from center.thana or gp.thana */}
                {isFirstOfCenter && (
                  <td rowSpan={centerLen} style={pTd({ verticalAlign: 'middle' })}>
                    {center.thana || gp.thana || '—'}
                  </td>
                )}
                {/* Duty officers */}
                {isFirstOfCenter && (
                  <td rowSpan={centerLen} style={pTd()}>
                    {dutyText.split('\n').map((line, i) => (
                      <div key={i} style={{ marginBottom: i < dutyText.split('\n').length - 1 ? 3 : 0 }}>{line}</div>
                    ))}
                  </td>
                )}
                {/* Mobile */}
                {isFirstOfCenter && (
                  <td rowSpan={centerLen} style={pTd({ fontFamily: 'monospace', fontSize: 9, verticalAlign: 'middle' })}>
                    {dutyMobile.split('\n').map((m, i) => <div key={i}>{m}</div>)}
                  </td>
                )}
                {/* Bus no */}
                {isFirstOfCenter && (
                  <td rowSpan={centerLen} style={pTd({ textAlign: 'center', verticalAlign: 'middle' })}>
                    {busNo}
                  </td>
                )}
              </tr>
            )
          })}
          {flatRows.length === 0 && (
            <tr>
              <td colSpan={10} style={pTd({ textAlign: 'center', color: '#8a9ab0', padding: 14, fontStyle: 'italic' })}>
                कोई केंद्र नहीं मिला
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </CardShell>
  )
}

// ─── EDIT FIELD DEFINITIONS (aligned with DB columns from Flask routes) ───────

const EDIT_FIELDS = {
  super_zones: [
    { key: 'name',     label: 'सुपर जोन नाम / नं.' },
    { key: 'block',    label: 'ब्लाक नाम' },
    { key: 'district', label: 'जनपद' },
  ],
  zones: [
    { key: 'name',        label: 'जोन नाम' },
    { key: 'hq_address',  label: 'मुख्यालय पता' },
  ],
  sectors: [
    { key: 'name', label: 'सैक्टर नाम / कोड' },
  ],
  gram_panchayats: [
    { key: 'name',    label: 'ग्राम पंचायत का नाम' },
    { key: 'address', label: 'पता' },
    { key: 'thana',   label: 'थाना' },
  ],
  matdan_sthal: [
    { key: 'name',         label: 'मतदान केन्द्र का नाम' },
    { key: 'center_type',  label: 'केन्द्र का प्रकार (A / B / C)' },
    { key: 'thana',        label: 'थाना' },
    { key: 'address',      label: 'पता', multiline: true },
    { key: 'bus_no',       label: 'बस नं.' },
  ],
}

// ─── DEEP STATE PATCHER ───────────────────────────────────────────────────────

function patchNested(data, table, id, vals) {
  return data.map(sz => {
    if (table === 'super_zones' && sz.id === id) return { ...sz, ...vals }
    return {
      ...sz,
      zones: sz.zones?.map(z => {
        if (table === 'zones' && z.id === id) return { ...z, ...vals }
        return {
          ...z,
          sectors: z.sectors?.map(s => {
            if (table === 'sectors' && s.id === id) return { ...s, ...vals }
            return {
              ...s,
              panchayats: s.panchayats?.map(gp => {
                if (table === 'gram_panchayats' && gp.id === id) return { ...gp, ...vals }
                return {
                  ...gp,
                  centers: gp.centers?.map(c =>
                    table === 'matdan_sthal' && c.id === id ? { ...c, ...vals } : c
                  ),
                }
              }),
            }
          }),
        }
      }),
    }
  })
}

// ─── TAB DEFINITIONS ──────────────────────────────────────────────────────────

const TABS = [
  { id: 'superzone', hi: 'सुपर जोन', en: 'Super Zone', Icon: Building2, color: '#e85d04' },
  { id: 'sector',    hi: 'सैक्टर',   en: 'Sector',     Icon: Map,       color: '#186a3b' },
  { id: 'panchayat', hi: 'पंचायत',   en: 'Booth Duty', Icon: Landmark,  color: '#6c3483' },
]

// ─── MAIN COMPONENT ──────────────────────────────────────────────────────────

export default function AdminHierarchy() {
  const [data, setData]           = useState([])
  const [loading, setLoading]     = useState(true)
  const [activeTab, setActiveTab] = useState('superzone')
  const [editState, setEditState] = useState(null)

  useEffect(() => {
   fetch(API + '/hierarchy/full/h', {
  method: "GET",
  headers: authHeaders(),
  credentials: "include"   // 🔥 THIS IS THE FIX
})
      .then(r => r.json())
      .then(r => { setData(Array.isArray(r) ? r : r.data || []); setLoading(false) })
      .catch(() => { toast.error('डेटा लोड करने में विफल'); setLoading(false) })
  }, [])

  const handleEdit = (item, table) => {
    const fields = EDIT_FIELDS[table] || [{ key: 'name', label: 'Name' }]
    setEditState({
      item, table, fields,
      onSaved: vals => setData(prev => patchNested(prev, table, item.id, vals)),

    })
  }

  if (loading) return <Spinner />

  // Summary counts
  const totalZones   = data.reduce((a, sz) => a + (sz.zones?.length || 0), 0)
  const totalSectors = data.reduce((a, sz) => a + (sz.zones?.reduce((b, z) => b + (z.sectors?.length || 0), 0) || 0), 0)
  const totalGPs     = data.reduce((a, sz) => a + (sz.zones?.reduce((b, z) => b + (z.sectors?.reduce((c, s) => c + (s.panchayats?.length || 0), 0) || 0), 0) || 0), 0)

  const activeTabMeta = TABS.find(t => t.id === activeTab)

  return (
    <div style={{ fontFamily: "'Noto Sans Devanagari', sans-serif", minHeight: '100vh', background: '#f0f2f5' }}>

      {/* PAGE HEADER */}
      <div style={{ background: 'linear-gradient(135deg, #0f2b5b 0%, #1a3d7c 100%)', borderBottom: '3px solid #e85d04', boxShadow: '0 4px 20px rgba(15,43,91,.18)' }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', padding: '18px 28px 0', flexWrap: 'wrap', gap: 12 }}>
          <div>
            <h1 style={{ fontSize: 20, fontWeight: 900, color: '#fff', margin: 0, letterSpacing: '0.3px' }}>
              प्रशासनिक पदानुक्रम
            </h1>
            <p style={{ fontSize: 11, color: 'rgba(255,255,255,.55)', margin: '3px 0 0', fontWeight: 400 }}>
              Administrative Hierarchy · UP Police Election Management
            </p>
          </div>
          {/* Summary chips */}
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {[
              { label: 'सुपर जोन', count: data.length,  color: '#e85d04' },
              { label: 'जोन',      count: totalZones,    color: '#38bdf8' },
              { label: 'सैक्टर',  count: totalSectors,  color: '#a78bfa' },
              { label: 'ग्राम पंचायत', count: totalGPs, color: '#4ade80' },
            ].map(s => (
              <div key={s.label} style={{ background: 'rgba(255,255,255,.1)', borderRadius: 10, padding: '6px 14px', textAlign: 'center', minWidth: 60 }}>
                <div style={{ fontSize: 17, fontWeight: 900, color: s.color }}>{s.count}</div>
                <div style={{ fontSize: 9, color: 'rgba(255,255,255,.55)', marginTop: 1 }}>{s.label}</div>
              </div>
            ))}
          </div>
        </div>

        {/* TAB BAR */}
        <div style={{ display: 'flex', gap: 3, padding: '16px 28px 0', overflowX: 'auto' }}>
          {TABS.map(tab => {
            const isActive = activeTab === tab.id
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                style={{
                  display: 'flex', alignItems: 'center', gap: 8,
                  padding: '10px 24px',
                  border: 'none', borderRadius: '10px 10px 0 0',
                  cursor: 'pointer',
                  fontFamily: "'Noto Sans Devanagari', sans-serif",
                  fontSize: 13, fontWeight: isActive ? 800 : 500,
                  background: isActive ? '#f0f2f5' : 'rgba(255,255,255,.07)',
                  color: isActive ? tab.color : 'rgba(255,255,255,.65)',
                  borderBottom: isActive ? `3px solid ${tab.color}` : '3px solid transparent',
                  position: 'relative', bottom: -3,
                  transition: 'all .16s ease',
                  whiteSpace: 'nowrap',
                }}
              >
                <tab.Icon size={15} />
                <span>{tab.hi}</span>
                <span style={{ fontSize: 10, opacity: 0.6, fontFamily: 'system-ui, sans-serif', fontWeight: 400 }}>
                  {tab.en}
                </span>
              </button>
            )
          })}
        </div>
      </div>

      {/* TAB CONTENT */}
      <div style={{ padding: '24px 28px', maxWidth: 1440, margin: '0 auto' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 18 }}>
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 7,
            background: activeTabMeta.color + '15',
            border: `1.5px solid ${activeTabMeta.color}35`,
            borderRadius: 20, padding: '5px 14px',
            fontSize: 12, fontWeight: 700, color: activeTabMeta.color,
          }}>
            <activeTabMeta.Icon size={13} />
            {activeTabMeta.hi} — {activeTabMeta.en}
          </div>
        </div>

        {activeTab === 'superzone' && <SuperZoneTab data={data} onEdit={handleEdit} />}
        {activeTab === 'sector'    && <SectorTab    data={data} onEdit={handleEdit} />}
        {activeTab === 'panchayat' && <PanchayatTab data={data} onEdit={handleEdit} />}
      </div>

      {/* Edit Modal */}
      {editState && (
        <EditPanel
          item={editState.item}
          table={editState.table}
          fields={editState.fields}
          onClose={() => setEditState(null)}
          onSaved={editState.onSaved}
        />
      )}
    </div>
  )
}