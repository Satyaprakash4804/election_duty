import { useEffect, useState, useRef } from 'react'
import { Printer, ChevronDown, Edit2, Save, X, Loader2, Building2, Map, Landmark } from 'lucide-react'
import { Spinner } from '../../components/ui'
import toast from 'react-hot-toast'

// ─── API ─────────────────────────────────────────────────────────────────────

const API = 'http://127.0.0.1:5000/api/admin'

function authHeaders() {
  return { Authorization: 'Bearer ' + localStorage.getItem('token'), 'Content-Type': 'application/json' }
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

// ─── PRINT TABLE HELPERS ──────────────────────────────────────────────────────

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
      toast.success('Saved successfully')
      onSaved(vals)
      onClose()
    } catch {
      toast.error('Save failed')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 50, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,.5)' }}>
      <div style={{ background: '#fff', borderRadius: 16, boxShadow: '0 24px 64px rgba(15,43,91,.18)', width: 480, maxHeight: '85vh', display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 20px', borderBottom: '1px solid #e8edf7' }}>
          <span style={{ fontWeight: 700, fontSize: 14, color: '#0f2b5b' }}>Edit Record</span>
          <button onClick={onClose} style={{ width: 28, height: 28, borderRadius: 8, border: 'none', background: '#f0f2f5', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#6b7c93' }}>
            <X size={14} />
          </button>
        </div>
        <div style={{ overflowY: 'auto', flex: 1, padding: '16px 20px' }}>
          {fields.map(({ key, label, multiline }) => (
            <div key={key} style={{ marginBottom: 12 }}>
              <label style={{ display: 'block', fontSize: 10, fontWeight: 600, color: '#6b7c93', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: 4 }}>{label}</label>
              {multiline ? (
                <textarea
                  rows={3}
                  value={vals[key] || ''}
                  onChange={e => setVals(p => ({ ...p, [key]: e.target.value }))}
                  style={{ width: '100%', background: '#f7f8fa', border: '1px solid #d6dbe4', borderRadius: 8, padding: '8px 10px', fontSize: 12, color: '#1a2332', outline: 'none', resize: 'vertical' }}
                />
              ) : (
                <input
                  value={vals[key] || ''}
                  onChange={e => setVals(p => ({ ...p, [key]: e.target.value }))}
                  style={{ width: '100%', background: '#f7f8fa', border: '1px solid #d6dbe4', borderRadius: 8, padding: '8px 10px', fontSize: 12, color: '#1a2332', outline: 'none' }}
                />
              )}
            </div>
          ))}
        </div>
        <div style={{ padding: '12px 20px', borderTop: '1px solid #e8edf7' }}>
          <button
            onClick={handleSave}
            disabled={saving}
            style={{ width: '100%', background: saving ? '#8a9ab0' : '#0f2b5b', color: '#fff', border: 'none', borderRadius: 10, padding: '11px', fontSize: 13, fontWeight: 600, cursor: saving ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}
          >
            {saving ? <Loader2 size={14} style={{ animation: 'spin 1s linear infinite' }} /> : <Save size={14} />}
            {saving ? 'Saving…' : 'Save Changes'}
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
          style={{
            width: '100%', appearance: 'none', background: '#fff',
            border: '1.5px solid #d6dbe4', borderRadius: 8,
            padding: '7px 32px 7px 12px', fontSize: 12, fontWeight: 500,
            color: value ? '#0f2b5b' : '#8a9ab0', cursor: 'pointer', outline: 'none',
            fontFamily: "'Noto Sans Devanagari', sans-serif",
          }}
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
        .sz-block { margin-bottom: 28px; page-break-inside: avoid; }
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

// ─── EMPTY STATE ──────────────────────────────────────────────────────────────

function EmptyState({ text }) {
  return (
    <div style={{ textAlign: 'center', padding: '56px 24px', color: '#8a9ab0' }}>
      <div style={{ fontSize: 36, marginBottom: 12 }}>📋</div>
      <div style={{ fontSize: 14, fontWeight: 500 }}>{text}</div>
    </div>
  )
}

// ─── CARD SHELL ───────────────────────────────────────────────────────────────

function CardShell({ header, children }) {
  return (
    <div style={{ background: '#fff', borderRadius: 12, border: '1px solid #e8edf7', overflow: 'hidden', boxShadow: '0 2px 12px rgba(15,43,91,.06)', marginBottom: 24 }}>
      {header}
      <div style={{ overflowX: 'auto' }}>{children}</div>
    </div>
  )
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 1 — सुपर जोन  (Image 1)
// One row per sector. GPs comma-separated. Zone officer spans its sectors.
// ════════════════════════════════════════════════════════════════════════════

function SuperZoneTab({ data, onEdit }) {
  const [selSZ, setSelSZ] = useState('')
  const { ref, print } = usePrint()

  const szOpts = data.map(sz => ({ value: sz.id, label: sz.name }))
  const visible = selSZ ? data.filter(sz => sz.id === selSZ) : data

  return (
    <div>
      {/* Controls */}
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
  const totalGPs = sz.zones?.reduce((a, z) => a + (z.sectors?.reduce((b, s) => b + (s.panchayats?.length || 0), 0) || 0), 0)

  // Flatten to one row per sector, carry cumulative sector number
  const rows = []
  let sNum = 0
  sz.zones?.forEach((z, zi) => {
    z.sectors?.forEach((s, si) => {
      sNum++
      rows.push({ z, zi, si, s, sNum, zLen: z.sectors?.length || 1 })
    })
  })

  return (
    <CardShell
      header={
        <div style={{ background: 'linear-gradient(135deg, #0f2b5b 0%, #1a3d7c 100%)', padding: '12px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div>
            <div style={{ fontSize: 15, fontWeight: 800, color: '#fff' }}>
              सुपर जोन–{sz.name}
              {sz.block_name && <span style={{ color: '#fbbf24', marginLeft: 8 }}>ब्लाक {sz.block_name}</span>}
            </div>
            {sz.thana_areas && <div style={{ fontSize: 11, color: 'rgba(255,255,255,.65)', marginTop: 2 }}>थाना क्षेत्र–{sz.thana_areas}</div>}
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Chip label={`कुल ग्राम पंचायत: ${totalGPs}`} accent="#fbbf24" />
            <EditBtn onClick={() => onEdit(sz, 'super_zones')} />
          </div>
        </div>
      }
    >
      <table style={{ width: '100%', borderCollapse: 'collapse', tableLayout: 'fixed', minWidth: 760 }}>
        <colgroup>
          <col style={{ width: 50 }} /><col style={{ width: 36 }} />
          <col style={{ width: 120 }} /><col style={{ width: 100 }} />
          <col style={{ width: 40 }} /><col style={{ width: 120 }} />
          <col style={{ width: 100 }} /><col /><col style={{ width: 65 }} />
        </colgroup>
        <thead>
          <tr>
            <th style={pTh()}>सुपर<br />जोन</th>
            <th style={pTh()}>जोन</th>
            <th style={pTh()}>जोनल अधिकारी</th>
            <th style={pTh()}>मुख्यालय</th>
            <th style={pTh()}>सैक्टर</th>
            <th style={pTh()}>सैक्टर पुलिस अधिकारी का नाम</th>
            <th style={pTh()}>मुख्यालय</th>
            <th style={pTh()}>सैक्टर में लगने वाले ग्राम पंचायत का नाम</th>
            <th style={pTh()}>थाना</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(({ z, zi, si, s, sNum, zLen }) => {
            const gpNames = s.panchayats?.map(gp => gp.name).join(', ') || '—'
            const thanas = [...new Set(s.panchayats?.map(gp => gp.thana).filter(Boolean))].join(', ') || '—'
            return (
              <tr key={s.id} style={{ background: sNum % 2 === 0 ? '#fffdf8' : '#fff' }}>
                {/* Super Zone — vertical text, spans all */}
                {zi === 0 && si === 0 && (
                  <td rowSpan={rows.length} style={pTd({ textAlign: 'center', verticalAlign: 'middle', padding: '6px 2px', width: 50 })}>
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
                      <div style={{ writingMode: 'vertical-rl', transform: 'rotate(180deg)', fontWeight: 700, fontSize: 9, color: '#cc0000' }}>
                        सुपर जोनल अधिकारी
                      </div>
                      {/* <div style={{ fontSize: 22, fontWeight: 900, color: '#0f2b5b', lineHeight: 1 }}>{sz.name}</div> */}
                      {sz.officer_name && (
                        <div style={{ writingMode: 'vertical-rl', transform: 'rotate(180deg)', fontSize: 8, color: '#cc0000' }}>
                          {sz.officer_name}
                        </div>
                      )}
                    </div>
                  </td>
                )}
                {/* Zone — spans its sectors */}
                {si === 0 && (
                  <>
                    <td rowSpan={zLen} style={pTd({ textAlign: 'center', fontWeight: 900, fontSize: 18, verticalAlign: 'middle', color: '#0f2b5b' })}>
                      {zi + 1}
                    </td>
                    <td rowSpan={zLen} style={pTd({ verticalAlign: 'middle', fontWeight: 600 })}>
                      {z.officer_name || z.officerName || '—'}
                    </td>
                    <td rowSpan={zLen} style={pTd({ verticalAlign: 'middle', color: '#3d4f63' })}>
                      {z.hq_address || z.hqAddress || '—'}
                    </td>
                  </>
                )}
                {/* Sector row */}
                <td style={pTd({ textAlign: 'center', fontWeight: 700, fontSize: 12, color: '#186a3b', verticalAlign: 'middle' })}>{sNum}</td>
                <td style={pTd()}>{s.name}</td>
                <td style={pTd({ color: '#3d4f63' })}>{s.hq || '—'}</td>
                <td style={pTd()}>{gpNames}</td>
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
// TAB 2 — सैक्टर  (Image 2)
// One table per zone. Super Zone officer left-spans, sector officer, GP → sthal → kendra
// ════════════════════════════════════════════════════════════════════════════

function SectorTab({ data, onEdit }) {
  const [selSZ, setSelSZ] = useState('')
  const [selZone, setSelZone] = useState('')
  const { ref, print } = usePrint()

  const szOpts = data.map(sz => ({ value: sz.id, label: sz.name }))
  const activeSZ = data.find(sz => sz.id === selSZ)
  const zoneOpts = (activeSZ?.zones || []).map(z => ({ value: z.id, label: z.name }))

  const pairs = []
  const szPool = selSZ ? data.filter(sz => sz.id === selSZ) : data
  szPool.forEach(sz => {
    const zPool = selZone ? sz.zones?.filter(z => z.id === selZone) : sz.zones || []
    zPool.forEach(z => pairs.push({ sz, z }))
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
        {pairs.map(({ sz, z }) => <SectorBlock key={z.id} zone={z} sz={sz} onEdit={onEdit} />)}
      </div>
    </div>
  )
}

function SectorBlock({ zone, sz, onEdit }) {
  // Build one flat row per matdan center (or per GP if no centers)
  const allRows = []
  let sSeq = 0
  zone.sectors?.forEach((s, si) => {
    sSeq++
    const sRows = []
    if (!s.panchayats || s.panchayats.length === 0) {
      sRows.push({ s, si, sSeq, gp: null, c: null })
    } else {
      s.panchayats.forEach(gp => {
        if (!gp.centers || gp.centers.length === 0) sRows.push({ s, si, sSeq, gp, c: null })
        else gp.centers.forEach(c => sRows.push({ s, si, sSeq, gp, c }))
      })
    }
    allRows.push(...sRows)
  })

  return (
    <CardShell
      header={
        <div style={{ background: 'linear-gradient(135deg, #186a3b 0%, #1e8449 100%)', padding: '12px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div>
            <div style={{ fontSize: 14, fontWeight: 800, color: '#fff' }}>
              जोन: {zone.name}
              <span style={{ fontWeight: 400, fontSize: 12, color: 'rgba(255,255,255,.7)', marginLeft: 10 }}>— सुपर जोन: {sz.name}</span>
            </div>
            {(zone.officer_name || zone.officerName) && (
              <div style={{ fontSize: 11, color: 'rgba(255,255,255,.75)', marginTop: 2 }}>
                जोनल अधिकारी: {zone.officer_name || zone.officerName}
                {zone.officer_mobile && <span style={{ marginLeft: 8 }}>· {zone.officer_mobile}</span>}
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
      {/* Intro text like Image 2 */}
      <div style={{ background: '#f7f8fa', borderBottom: '1px solid #e8edf7', padding: '7px 16px', fontSize: 10, color: '#6b7c93', fontStyle: 'italic' }}>
        श्री ............................................. — अपर पुलिस अधीक्षक जनपद ....................... — ब्लाक {sz.block_name || sz.name} / {zone.name}
      </div>

      <table style={{ width: '100%', borderCollapse: 'collapse', tableLayout: 'fixed', minWidth: 680 }}>
        <colgroup>
          <col style={{ width: 130 }} /><col style={{ width: 32 }} /><col style={{ width: 32 }} />
          <col style={{ width: 160 }} /><col style={{ width: 90 }} /><col /><col style={{ width: 90 }} />
        </colgroup>
        <thead>
          <tr>
            <th style={pTh()}>सुपर जोन व अधिकारी</th>
            <th style={pTh()}>जोन<br />सं.</th>
            <th style={pTh()}>सैक्टर<br />सं.</th>
            <th style={pTh()}>सैक्टर मजिस्ट्रेट / सैक्टर पुलिस अधिकारी</th>
            <th style={pTh()}>ग्राम पंचायत</th>
            <th style={pTh()}>मतदेय स्थल</th>
            <th style={pTh()}>मतदान केन्द्र</th>
          </tr>
        </thead>
        <tbody>
          {allRows.map((row, ri) => {
            const { s, si, sSeq, gp, c } = row
            const isFirst = ri === 0
            const isFirstSec = ri === 0 || allRows[ri - 1].s.id !== s.id
            const isFirstGP = isFirstSec || (gp && ri > 0 && allRows[ri - 1].gp?.id !== gp?.id)
            const secLen = allRows.filter(r => r.s.id === s.id).length
            const gpLen = gp ? allRows.filter(r => r.gp?.id === gp.id && r.s.id === s.id).length : 1

            return (
              <tr key={ri} style={{ background: ri % 2 === 0 ? '#fff' : '#fffdf8' }}>
                {/* Super Zone + Zone officer — spans all rows */}
                {isFirst && (
                  <td rowSpan={allRows.length} style={pTd({ verticalAlign: 'top', padding: '8px 6px' })}>
                    <div style={{ fontWeight: 700, fontSize: 11, color: '#0f2b5b', marginBottom: 1 }}>{sz.name}</div>
                    {sz.officer_designation && <div style={{ fontSize: 9, color: '#6b7c93' }}>{sz.officer_designation}</div>}
                    {sz.officer_name && <div style={{ fontSize: 10, marginTop: 2 }}>{sz.officer_name}</div>}
                    {sz.officer_mobile && <div style={{ fontSize: 9, color: '#6b7c93', marginTop: 1 }}>मो.– {sz.officer_mobile}</div>}
                    <div style={{ borderTop: '1px dashed #d6dbe4', margin: '6px 0' }} />
                    <div style={{ fontWeight: 600, fontSize: 10, color: '#186a3b' }}>{zone.name}</div>
                    {(zone.officer_name || zone.officerName) && <div style={{ fontSize: 9, marginTop: 2 }}>{zone.officer_name || zone.officerName}</div>}
                    {zone.officer_mobile && <div style={{ fontSize: 9, color: '#6b7c93', marginTop: 1 }}>मो.– {zone.officer_mobile}</div>}
                  </td>
                )}
                {/* Zone number — spans all */}
                {isFirst && (
                  <td rowSpan={allRows.length} style={pTd({ textAlign: 'center', verticalAlign: 'middle', fontWeight: 900, fontSize: 16, color: '#0f2b5b' })}>1</td>
                )}
                {/* Sector number — spans sector rows */}
                {isFirstSec && (
                  <td rowSpan={secLen} style={pTd({ textAlign: 'center', fontWeight: 700, color: '#186a3b', fontSize: 12, verticalAlign: 'top', paddingTop: 6 })}>
                    {sSeq}
                  </td>
                )}
                {/* Sector officer — spans sector rows */}
                {isFirstSec && (
                  <td rowSpan={secLen} style={pTd({ verticalAlign: 'top' })}>
                    {s.magistrate_name && (
                      <div style={{ fontWeight: 600, marginBottom: 2, fontSize: 10 }}>
                        {s.magistrate_name}
                        {s.magistrate_designation && <span style={{ fontWeight: 400, color: '#6b7c93' }}> – {s.magistrate_designation}</span>}
                        {s.magistrate_mobile && <span style={{ color: '#6b7c93' }}>–{s.magistrate_mobile}</span>}
                      </div>
                    )}
                    <div style={{ fontWeight: 600 }}>{s.name}</div>
                    {s.officer_mobile && <div style={{ fontSize: 9, color: '#6b7c93', marginTop: 1 }}>{s.officer_mobile}</div>}
                    {s.hamrah && <div style={{ fontSize: 9, color: '#555', marginTop: 3, whiteSpace: 'pre-line' }}>{s.hamrah}</div>}
                    {s.hq && <div style={{ fontSize: 9, color: '#8a9ab0', marginTop: 2 }}>मु.: {s.hq}</div>}
                  </td>
                )}
                {/* GP — spans its centers */}
                {gp && isFirstGP ? (
                  <td rowSpan={gpLen} style={pTd({ verticalAlign: 'top', fontWeight: 600 })}>{gp.name}</td>
                ) : !gp && isFirstSec ? (
                  <td rowSpan={secLen} style={pTd({ color: '#8a9ab0' })}>—</td>
                ) : null}
                {/* Matdey Sthal */}
                <td style={pTd()}>
                  {c ? <><div>{c.name}</div>{c.address && <div style={{ fontSize: 9, color: '#6b7c93', marginTop: 1 }}>{c.address}</div>}</> : '—'}
                </td>
                {/* Matdan Kendra number */}
                <td style={pTd({ textAlign: 'center', verticalAlign: 'middle', fontWeight: 600 })}>
                  {c?.center_number || c?.centerNumber || '—'}
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
// TAB 3 — पंचायत  (Image 3)
// One table per GP — Booth Duty format with center type, police duty info
// ════════════════════════════════════════════════════════════════════════════

function PanchayatTab({ data, onEdit }) {
  const [selSZ, setSelSZ] = useState('')
  const [selZone, setSelZone] = useState('')
  const [selSec, setSelSec] = useState('')
  const [selGP, setSelGP] = useState('')
  const { ref, print } = usePrint()

  const szOpts = data.map(sz => ({ value: sz.id, label: sz.name }))
  const activeSZ = data.find(sz => sz.id === selSZ)
  const zoneOpts = (activeSZ?.zones || []).map(z => ({ value: z.id, label: z.name }))
  const activeZone = activeSZ?.zones?.find(z => z.id === selZone)
  const secOpts = (activeZone?.sectors || []).map(s => ({ value: s.id, label: s.name }))
  const activeSec = activeZone?.sectors?.find(s => s.id === selSec)
  const gpOpts = (activeSec?.panchayats || []).map(gp => ({ value: gp.id, label: gp.name }))

  const items = []
  const szPool = selSZ ? data.filter(sz => sz.id === selSZ) : data
  szPool.forEach(sz => {
    const zPool = selZone ? sz.zones?.filter(z => z.id === selZone) : sz.zones || []
    zPool.forEach(z => {
      const sPool = selSec ? z.sectors?.filter(s => s.id === selSec) : z.sectors || []
      sPool.forEach(s => {
        const gpPool = selGP ? s.panchayats?.filter(gp => gp.id === selGP) : s.panchayats || []
        gpPool.forEach(gp => items.push({ sz, zone: z, sector: s, gp }))
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
        {items.map(({ sz, zone, sector, gp }) => (
          <PanchayatBlock key={gp.id} gp={gp} sector={sector} zone={zone} sz={sz} onEdit={onEdit} />
        ))}
      </div>
    </div>
  )
}

function PanchayatBlock({ gp, sector, zone, sz, onEdit }) {
  return (
    <CardShell
      header={
        <div style={{ background: 'linear-gradient(135deg, #6c3483 0%, #7d3c98 100%)', padding: '12px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
          <div>
            <div style={{ fontSize: 14, fontWeight: 800, color: '#fff' }}>
              बूथ ड्यूटी —
              <span style={{ textDecoration: 'underline', marginLeft: 6, color: '#fbbf24' }}>ब्लॉक {sz.block_name || sz.name}</span>
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
            <EditBtn onClick={() => onEdit(gp, 'gram_panchayats')} />
          </div>
        </div>
      }
    >
      <table style={{ width: '100%', borderCollapse: 'collapse', tableLayout: 'fixed', minWidth: 760 }}>
        <colgroup>
          <col style={{ width: 38 }} /><col style={{ width: 110 }} /><col style={{ width: 38 }} />
          <col style={{ width: 110 }} /><col style={{ width: 32 }} /><col style={{ width: 38 }} />
          <col style={{ width: 60 }} /><col /><col style={{ width: 80 }} /><col style={{ width: 32 }} />
        </colgroup>
        <thead>
          <tr>
            <th style={pTh()}>मतदान<br />केन्द्र<br />की<br />संख्या</th>
            <th style={pTh()}>मतदान<br />केन्द्र<br />का नाम</th>
            <th style={pTh()}>मतदेय<br />स्थ्ल<br />सं०</th>
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
          {gp.centers?.map((c, ci) => (
            <tr key={c.id} style={{ background: ci % 2 === 0 ? '#fff' : '#fffdf8' }}>
              <td style={pTd({ textAlign: 'center', fontWeight: 700, verticalAlign: 'middle', fontSize: 12 })}>{ci + 1}</td>
              <td style={pTd({ verticalAlign: 'top' })}>
                <div>{c.name}</div>
                {c.center_type && <div style={{ fontWeight: 700, fontSize: 11, marginTop: 3 }}>{c.center_type}</div>}
              </td>
              <td style={pTd({ textAlign: 'center', verticalAlign: 'middle' })}>{c.center_number || c.centerNumber || ci + 1}</td>
              <td style={pTd()}>{c.sthal_name || c.address || '—'}</td>
              <td style={pTd({ textAlign: 'center', verticalAlign: 'middle' })}>{c.zone_no || '—'}</td>
              <td style={pTd({ textAlign: 'center', verticalAlign: 'middle' })}>{c.sector_no || '—'}</td>
              <td style={pTd()}>{c.thana || gp.thana || '—'}</td>
              <td style={pTd()}>
                {c.duty_officer
                  ? c.duty_officer.split('\n').map((line, i) => <div key={i}>{line}</div>)
                  : '—'}
              </td>
              <td style={pTd({ fontFamily: 'monospace', fontSize: 9, verticalAlign: 'middle' })}>{c.mobile || '—'}</td>
              <td style={pTd({ textAlign: 'center', verticalAlign: 'middle' })}>{c.bus_no || c.busNo || '—'}</td>
            </tr>
          ))}
          {(!gp.centers || gp.centers.length === 0) && (
            <tr><td colSpan={10} style={pTd({ textAlign: 'center', color: '#8a9ab0', padding: 14, fontStyle: 'italic' })}>कोई केंद्र नहीं मिला</td></tr>
          )}
        </tbody>
      </table>
    </CardShell>
  )
}

// ─── SMALL UI ATOMS ───────────────────────────────────────────────────────────

function Chip({ label, accent = '#fbbf24' }) {
  return (
    <div style={{ background: 'rgba(255,255,255,.15)', borderRadius: 7, padding: '4px 10px', fontSize: 11, fontWeight: 700, color: accent }}>
      {label}
    </div>
  )
}

function EditBtn({ onClick }) {
  return (
    <button onClick={onClick} style={{ background: 'rgba(255,255,255,.15)', border: 'none', borderRadius: 7, width: 28, height: 28, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', color: '#fff' }}>
      <Edit2 size={12} />
    </button>
  )
}

const printBtnStyle = {
  marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 6,
  background: '#0f2b5b', color: '#fff', border: 'none', borderRadius: 9,
  padding: '8px 18px', fontSize: 12, fontWeight: 600, cursor: 'pointer',
  fontFamily: "'Noto Sans Devanagari', sans-serif",
}

// ─── TAB DEFINITIONS ──────────────────────────────────────────────────────────

const TABS = [
  { id: 'superzone', hi: 'सुपर जोन', en: 'Super Zone', Icon: Building2, color: '#e85d04', grad: 'linear-gradient(135deg,#0f2b5b,#1a3d7c)' },
  { id: 'sector',    hi: 'सैक्टर',   en: 'Sector',     Icon: Map,       color: '#1d5fa8', grad: 'linear-gradient(135deg,#186a3b,#1e8449)' },
  { id: 'panchayat', hi: 'पंचायत',   en: 'Panchayat',  Icon: Landmark,  color: '#6c3483', grad: 'linear-gradient(135deg,#6c3483,#7d3c98)' },
]

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

// ─── MAIN COMPONENT ──────────────────────────────────────────────────────────

export default function AdminHierarchy() {
  const [data, setData]           = useState([])
  const [loading, setLoading]     = useState(true)
  const [activeTab, setActiveTab] = useState('superzone')
  const [editState, setEditState] = useState(null)

  useEffect(() => {
    fetch(API + '/hierarchy/full', { headers: authHeaders() })
      .then(r => r.json())
      .then(r => { setData(r.data || r || []); setLoading(false) })
      .catch(() => { toast.error('Failed to load hierarchy'); setLoading(false) })
  }, [])

  const handleEdit = (item, table) => {
    const fieldMap = {
      super_zones:      [
        { key: 'name', label: 'Name' }, { key: 'block_name', label: 'Block Name' },
        { key: 'thana_areas', label: 'Thana Areas' }, { key: 'officer_name', label: 'Officer Name' },
        { key: 'officer_designation', label: 'Designation' }, { key: 'officer_mobile', label: 'Mobile' },
      ],
      zones:            [
        { key: 'name', label: 'Zone Name' }, { key: 'hq_address', label: 'HQ Address' },
        { key: 'officer_name', label: 'Officer Name' }, { key: 'officer_designation', label: 'Designation' },
        { key: 'officer_pno', label: 'PNO' }, { key: 'officer_mobile', label: 'Mobile' },
      ],
      sectors:          [
        { key: 'name', label: 'Sector Officer Name' }, { key: 'hq', label: 'HQ' },
        { key: 'officer_mobile', label: 'Officer Mobile' },
        { key: 'magistrate_name', label: 'Magistrate Name' },
        { key: 'magistrate_designation', label: 'Magistrate Designation' },
        { key: 'magistrate_mobile', label: 'Magistrate Mobile' },
        { key: 'hamrah', label: 'Hamrah / Escort Details', multiline: true },
      ],
      gram_panchayats:  [
        { key: 'name', label: 'GP Name' }, { key: 'address', label: 'Address' }, { key: 'thana', label: 'Thana' },
      ],
      matdan_sthal:     [
        { key: 'name', label: 'Center Name' }, { key: 'sthal_name', label: 'Matdey Sthal Name' },
        { key: 'address', label: 'Address', multiline: true }, { key: 'thana', label: 'Thana' },
        { key: 'center_type', label: 'Type (A/B/C)' }, { key: 'center_number', label: 'Matdey Sthal No' },
        { key: 'zone_no', label: 'Zone No' }, { key: 'sector_no', label: 'Sector No' },
        { key: 'duty_officer', label: 'Duty Officer(s) — one per line', multiline: true },
        { key: 'mobile', label: 'Mobile' }, { key: 'bus_no', label: 'Bus No' },
      ],
    }
    setEditState({
      item, table,
      fields: fieldMap[table] || [{ key: 'name', label: 'Name' }],
      onSaved: vals => setData(prev => patchNested(prev, table, item.id, vals)),
    })
  }

  if (loading) return <Spinner />

  const activeTabMeta = TABS.find(t => t.id === activeTab)

  // Summary counts
  const totalZones = data.reduce((a, sz) => a + (sz.zones?.length || 0), 0)
  const totalSectors = data.reduce((a, sz) => a + sz.zones?.reduce((b, z) => b + (z.sectors?.length || 0), 0), 0)
  const totalGPs = data.reduce((a, sz) => a + sz.zones?.reduce((b, z) => b + z.sectors?.reduce((c, s) => c + (s.panchayats?.length || 0), 0), 0), 0)

  return (
    <div style={{ fontFamily: "'Noto Sans Devanagari', sans-serif", minHeight: '100vh', background: '#f0f2f5' }}>

      {/* ══ PAGE HEADER ══ */}
      <div style={{ background: 'linear-gradient(135deg, #0f2b5b 0%, #1a3d7c 100%)', borderBottom: '3px solid #e85d04', boxShadow: '0 4px 20px rgba(15,43,91,.18)' }}>

        {/* Title row */}
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
              { label: 'सुपर जोन', count: data.length, color: '#e85d04' },
              { label: 'जोन', count: totalZones, color: '#38bdf8' },
              { label: 'सैक्टर', count: totalSectors, color: '#a78bfa' },
              { label: 'ग्राम पंचायत', count: totalGPs, color: '#4ade80' },
            ].map(s => (
              <div key={s.label} style={{ background: 'rgba(255,255,255,.1)', borderRadius: 10, padding: '6px 14px', textAlign: 'center', minWidth: 60 }}>
                <div style={{ fontSize: 17, fontWeight: 900, color: s.color }}>{s.count}</div>
                <div style={{ fontSize: 9, color: 'rgba(255,255,255,.55)', marginTop: 1 }}>{s.label}</div>
              </div>
            ))}
          </div>
        </div>

        {/* ── TAB BAR ── */}
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

      {/* ══ TAB CONTENT ══ */}
      <div style={{ padding: '24px 28px', maxWidth: 1440, margin: '0 auto' }}>

        {/* Active tab label */}
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

        {activeTab === 'superzone' && <SuperZoneTab  data={data} onEdit={handleEdit} />}
        {activeTab === 'sector'    && <SectorTab     data={data} onEdit={handleEdit} />}
        {activeTab === 'panchayat' && <PanchayatTab  data={data} onEdit={handleEdit} />}
      </div>

      {/* ── Edit Panel ── */}
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