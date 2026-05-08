import { useState, useEffect, useCallback } from 'react';
import toast from 'react-hot-toast';
import { pdf, Document, Page, Text, View, StyleSheet } from '@react-pdf/renderer';
import {
  RefreshCw, Printer, MapPin, Layers, Grid,
  Scale, Home, AlertCircle, Save, Loader2, TableProperties,
  ArrowLeft,
} from 'lucide-react';
import { goswaraApi } from '../../api/endpoints';
import { useAuthStore } from '../../store/authStore';
import { useNavigate } from 'react-router-dom';

const formatElectionDate = (dateStr) => {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  if (isNaN(d)) return dateStr;
  return d.toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });
};

// ─── PDF Styles ───────────────────────────────────────────────────────────────
const pdfStyles = StyleSheet.create({
  page: { padding: 24, fontFamily: 'Helvetica', backgroundColor: '#FEFCF7' },
  header: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 12 },
  titleBlock: { flexDirection: 'column' },
  title: { fontSize: 20, fontFamily: 'Helvetica-Bold', color: '#4A3000' },
  subtitle: { fontSize: 8, color: '#AA8844', marginTop: 3 },
  metaBlock: { alignItems: 'flex-end' },
  metaText: { fontSize: 9, color: '#4A3000', fontFamily: 'Helvetica-Bold' },
  metaSub: { fontSize: 8, color: '#AA8844' },
  divider: { borderBottomWidth: 0.8, borderColor: '#D4A843', marginBottom: 12 },
  table: { borderWidth: 0.6, borderColor: '#C8A84B' },
  headerRow: { flexDirection: 'row', backgroundColor: '#4A3000' },
  evenRow: { flexDirection: 'row', backgroundColor: '#FEFCF7' },
  oddRow: { flexDirection: 'row', backgroundColor: '#F9F0DC' },
  totalRow: { flexDirection: 'row', backgroundColor: '#EFE0B0' },
  hCell: { padding: 6, fontSize: 8, color: '#D4A843', fontFamily: 'Helvetica-Bold', textAlign: 'center', borderRightWidth: 0.6, borderColor: '#6B5300' },
  cell: { padding: 6, fontSize: 9, color: '#4A3000', textAlign: 'center', borderRightWidth: 0.6, borderColor: '#C8A84B' },
  cellLeft: { padding: 6, fontSize: 9, color: '#4A3000', textAlign: 'left', borderRightWidth: 0.6, borderColor: '#C8A84B' },
  cellBold: { padding: 6, fontSize: 9, color: '#4A3000', fontFamily: 'Helvetica-Bold', textAlign: 'center', borderRightWidth: 0.6, borderColor: '#C8A84B' },
  footer: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 12 },
  footerText: { fontSize: 7, color: '#AA8844' },
  w1: { width: 28 }, w2: { width: 115 }, w3: { width: 55 },
  w4: { width: 80 }, w5: { width: 108 }, w6: { width: 85 },
  w7: { width: 82 }, w8: { width: 82 },
});

// ─── PDF Document ─────────────────────────────────────────────────────────────
const GoswaraPDF = ({ data, electionDate, phase, district, nyayValues }) => {
  const sum = (key) => data.reduce((s, r) => s + (r[key] || 0), 0);
  const nyayTotal = data.reduce(
    (s, r) => s + (nyayValues[r.block_name] || r.nyay_panchayat_count || 0), 0
  );
  const today = new Date();
  const dateStr = `${String(today.getDate()).padStart(2, '0')}/${String(today.getMonth() + 1).padStart(2, '0')}/${today.getFullYear()}`;
  const colWidths = [pdfStyles.w1, pdfStyles.w2, pdfStyles.w3, pdfStyles.w4, pdfStyles.w5, pdfStyles.w6, pdfStyles.w7, pdfStyles.w8];
  const headers = ['Sn.', 'Block', 'Phase', 'Date', 'Zonal', 'Sector', 'Nyay', 'GP'];

  return (
    <Document>
      <Page size="A4" orientation="landscape" style={pdfStyles.page}>
        <View style={pdfStyles.header}>
          <View style={pdfStyles.titleBlock}>
            <Text style={pdfStyles.title}>Goswara</Text>
            <Text style={pdfStyles.subtitle}>Block-wise Zonal, Sector, Nyay Panchayat &amp; Gram Panchayat details</Text>
          </View>
          <View style={pdfStyles.metaBlock}>
            {phase ? <Text style={pdfStyles.metaText}>Phase: {phase}</Text> : null}
            {electionDate ? <Text style={pdfStyles.metaSub}>{formatElectionDate(electionDate)}</Text> : null}
            {district ? <Text style={pdfStyles.metaText}>District: {district}</Text> : null}
          </View>
        </View>
        <View style={pdfStyles.divider} />
        <View style={pdfStyles.table}>
          <View style={pdfStyles.headerRow}>
            {headers.map((h, i) => (
              <View key={i} style={colWidths[i]}><Text style={pdfStyles.hCell}>{h}</Text></View>
            ))}
          </View>
          {data.map((row, i) => {
            const nyay = nyayValues[row.block_name] ?? row.nyay_panchayat_count ?? 0;
            const rowStyle = i % 2 === 0 ? pdfStyles.evenRow : pdfStyles.oddRow;
            return (
              <View key={i} style={rowStyle}>
                <View style={pdfStyles.w1}><Text style={pdfStyles.cell}>{i + 1}</Text></View>
                <View style={pdfStyles.w2}><Text style={pdfStyles.cellLeft}>{row.block_name}</Text></View>
                <View style={pdfStyles.w3}><Text style={pdfStyles.cell}>{i === 0 ? phase : ''}</Text></View>
                <View style={pdfStyles.w4}><Text style={pdfStyles.cell}>{i === 0 ? electionDate : ''}</Text></View>
                <View style={pdfStyles.w5}><Text style={pdfStyles.cell}>{row.zonal_count || 0}</Text></View>
                <View style={pdfStyles.w6}><Text style={pdfStyles.cell}>{row.sector_count || 0}</Text></View>
                <View style={pdfStyles.w7}><Text style={pdfStyles.cell}>{nyay}</Text></View>
                <View style={pdfStyles.w8}><Text style={pdfStyles.cell}>{row.gram_panchayat_count || 0}</Text></View>
              </View>
            );
          })}
          <View style={pdfStyles.totalRow}>
            <View style={pdfStyles.w1}><Text style={pdfStyles.cell}></Text></View>
            <View style={pdfStyles.w2}><Text style={pdfStyles.cellBold}>TOTAL</Text></View>
            <View style={pdfStyles.w3}><Text style={pdfStyles.cell}></Text></View>
            <View style={pdfStyles.w4}><Text style={pdfStyles.cell}></Text></View>
            <View style={pdfStyles.w5}><Text style={pdfStyles.cellBold}>{sum('zonal_count')}</Text></View>
            <View style={pdfStyles.w6}><Text style={pdfStyles.cellBold}>{sum('sector_count')}</Text></View>
            <View style={pdfStyles.w7}><Text style={pdfStyles.cellBold}>{nyayTotal}</Text></View>
            <View style={pdfStyles.w8}><Text style={pdfStyles.cellBold}>{sum('gram_panchayat_count')}</Text></View>
          </View>
        </View>
        <View style={pdfStyles.footer}>
          <Text style={pdfStyles.footerText}>Goswara — District Election Details</Text>
          <Text style={pdfStyles.footerText}>Printed: {dateStr}</Text>
        </View>
      </Page>
    </Document>
  );
};

// ─── Main Component ───────────────────────────────────────────────────────────
export default function GoswaraPage() {
  const { user } = useAuthStore();

  const nav = useNavigate()

  const [rows, setRows] = useState([]);
  const [electionDate, setElectionDate] = useState('');
  const [phase, setPhase] = useState('');
  const [loading, setLoading] = useState(true);
  const [fetchError, setFetchError] = useState('');
  const [nyayInputs, setNyayInputs] = useState({});
  const [savingBlock, setSavingBlock] = useState(null);
  const [printLoading, setPrintLoading] = useState(false);

  const userRole = user?.role || '';
  const userDistrict = user?.district || '';
  const isSuperAdmin = ['super_admin', 'SUPER_ADMIN'].includes(userRole);

  // ── Fetch ─────────────────────────────────────────────────────────────────
  const fetchData = useCallback(async () => {
    setLoading(true);
    setFetchError('');
    try {
      const res = await goswaraApi.getGoswara();
      console.log(res);

      const body = res;
      const data = body?.data || [];

      setRows(data);
      setElectionDate(body?.electionDate || '');
      setPhase(body?.phase || '');

      setNyayInputs(prev => {
        const next = { ...prev };
        data.forEach(r => {
          if (!(r.block_name in next)) {
            next[r.block_name] = String(r.nyay_panchayat_count ?? 0);
          }
        });
        return next;
      });
    } catch (e) {
      const msg = e?.response?.data?.message || e.message || 'Unknown error';
      setFetchError(msg);
      toast.error(`Failed to load: ${msg}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  // ── Save nyay ─────────────────────────────────────────────────────────────
  const handleSaveNyay = async (blockName) => {
    const count = parseInt(nyayInputs[blockName] || '0') || 0;
    setSavingBlock(blockName);
    try {
      await goswaraApi.saveNyayPanchayat({ blockName, nyayCount: count });
      setRows(prev =>
        prev.map(r => r.block_name === blockName ? { ...r, nyay_panchayat_count: count } : r)
      );
      toast.success(`${blockName} — Nyay Panchayat saved ✓`);
    } catch (e) {
      toast.error(`Save failed: ${e?.response?.data?.message || e.message}`);
    } finally {
      setSavingBlock(null);
    }
  };

  // ── PDF ───────────────────────────────────────────────────────────────────
  const handlePrint = () => {
    if (!rows.length) return;

    const formattedDate = formatElectionDate(electionDate);
    const today = new Date().toLocaleDateString('en-IN', {
      day: '2-digit', month: 'short', year: 'numeric'
    });

    const tableRows = rows.map((row, i) => {
      const nyay = parseInt(nyayInputs[row.block_name] || row.nyay_panchayat_count || '0') || 0;
      return `
      <tr class="${i % 2 === 0 ? 'even' : 'odd'}">
        <td class="center">${i + 1}</td>
        <td class="left bold">${row.block_name}</td>
        <td class="center">${i === 0 ? phase : ''}</td>
        <td class="center">${i === 0 ? formattedDate : ''}</td>
        <td class="center blue">${row.zonal_count || 0}</td>
        <td class="center green">${row.sector_count || 0}</td>
        <td class="center purple">${nyay}</td>
        <td class="center gold">${row.gram_panchayat_count || 0}</td>
      </tr>`;
    }).join('');

    const totalNyay = rows.reduce((s, r) => s + (parseInt(nyayInputs[r.block_name] || '0') || 0), 0);
    const sumZonal = rows.reduce((s, r) => s + (r.zonal_count || 0), 0);
    const sumSector = rows.reduce((s, r) => s + (r.sector_count || 0), 0);
    const sumGP = rows.reduce((s, r) => s + (r.gram_panchayat_count || 0), 0);

    const html = `<!DOCTYPE html>
<html lang="hi">
<head>
  <meta charset="UTF-8"/>
  <title>गोसवारा — ${userDistrict}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com"/>
  <link href="https://fonts.googleapis.com/css2?family=Tiro+Devanagari+Hindi&family=Noto+Sans+Devanagari:wght@400;700&display=swap" rel="stylesheet"/>
  <style>
    @page {
      size: A4 landscape;
      margin: 14mm 12mm 14mm 12mm;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Noto Sans Devanagari', 'Noto Serif Devanagari', Arial, sans-serif;
      font-size: 11px;
      color: #2c1a00;
      background: #fff;
    }
    .header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 8px;
      padding-bottom: 8px;
      border-bottom: 1.5px solid #c8a84b;
    }
    .title-block h1 {
      font-family: 'Tiro Devanagari Hindi', 'Noto Serif Devanagari', serif;
      font-size: 22px;
      color: #4a3000;
      line-height: 1.2;
    }
    .title-block p {
      font-size: 9px;
      color: #aa8844;
      margin-top: 2px;
    }
    .meta-block {
      text-align: right;
      font-size: 10px;
      color: #4a3000;
    }
    .meta-block .tag {
      display: inline-block;
      background: #f0e0a0;
      border: 1px solid #c8a84b;
      border-radius: 4px;
      padding: 2px 8px;
      margin: 2px 0;
      font-weight: 700;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      border: 1px solid #c8a84b;
      margin-top: 10px;
    }
    thead tr {
      background: #1a2332;
    }
    thead th {
      padding: 7px 6px;
      font-size: 9px;
      font-weight: 700;
      color: #d4a843;
      text-align: center;
      border-right: 1px solid #2d3d55;
      white-space: nowrap;
      letter-spacing: 0.3px;
    }
    thead th:last-child { border-right: none; }
    tbody tr.even { background: #fefcf7; }
    tbody tr.odd  { background: #f9f0dc; }
    tbody td {
      padding: 6px 6px;
      border-right: 1px solid rgba(200,168,75,0.3);
      border-bottom: 1px solid rgba(200,168,75,0.15);
      font-size: 10px;
    }
    tbody td:last-child { border-right: none; }
    td.center { text-align: center; }
    td.left   { text-align: left; }
    td.bold   { font-weight: 700; }
    td.blue   { color: #1565c0; font-weight: 700; }
    td.green  { color: #2e7d32; font-weight: 700; }
    td.purple { color: #6a1b9a; font-weight: 700; }
    td.gold   { color: #8b6914; font-weight: 700; }
    .total-row {
      background: #efe0b0 !important;
      border-top: 1.5px solid #c8a84b;
    }
    .total-row td {
      font-weight: 900;
      font-size: 10.5px;
      border-right: 1px solid rgba(200,168,75,0.4);
    }
    .footer {
      display: flex;
      justify-content: space-between;
      margin-top: 10px;
      font-size: 8px;
      color: #aa8844;
    }
    /* Column widths — fixed for landscape A4 */
    col.c1 { width: 5%; }
    col.c2 { width: 18%; }
    col.c3 { width: 8%; }
    col.c4 { width: 14%; }
    col.c5 { width: 17%; }
    col.c6 { width: 13%; }
    col.c7 { width: 13%; }
    col.c8 { width: 12%; }
  </style>
</head>
<body>
  <div class="header">
    <div class="title-block">
      <h1>गोसवारा</h1>
      <p>विकास खण्डवार जोनल एवं सेक्टर, न्याय पंचायत एवं ग्राम पंचायतों का विवरण</p>
    </div>
    <div class="meta-block">
      ${phase ? `<div class="tag">Phase: ${phase}</div>` : ''}
      ${formattedDate ? `<div class="tag">${formattedDate}</div>` : ''}
      ${userDistrict ? `<div class="tag">District: ${userDistrict}</div>` : ''}
    </div>
  </div>

  <table>
    <colgroup>
      <col class="c1"/><col class="c2"/><col class="c3"/><col class="c4"/>
      <col class="c5"/><col class="c6"/><col class="c7"/><col class="c8"/>
    </colgroup>
    <thead>
      <tr>
        <th>Sn.</th>
        <th>Block Name</th>
        <th>Phase</th>
        <th>Election Date</th>
        <th>Zonal Magistrate / Police Officer</th>
        <th>Sector Magistrate</th>
        <th>Nyay Panchayat</th>
        <th>Gram Panchayat</th>
      </tr>
    </thead>
    <tbody>
      ${tableRows}
      <tr class="total-row">
        <td></td>
        <td class="center">TOTAL</td>
        <td></td><td></td>
        <td class="center blue">${sumZonal}</td>
        <td class="center green">${sumSector}</td>
        <td class="center purple">${totalNyay}</td>
        <td class="center gold">${sumGP}</td>
      </tr>
    </tbody>
  </table>

  <div class="footer">
    <span>गोसवारा — जिला निर्वाचन विवरण</span>
    <span>Printed: ${today}</span>
  </div>

  <script>window.onload = () => { window.print(); }</script>
</body>
</html>`;

    const win = window.open('', '_blank');
    win.document.write(html);
    win.document.close();
  };

  // ── Helpers ───────────────────────────────────────────────────────────────
  const sum = (key) => rows.reduce((s, r) => s + (r[key] || 0), 0);
  const nyaySum = rows.reduce((s, r) => s + (parseInt(nyayInputs[r.block_name] || '0') || 0), 0);

  const stats = [
    { value: sum('zonal_count'), label: 'Zonal Officers', icon: Layers, color: '#1565C0', bg: 'rgba(21,101,192,0.1)' },
    { value: sum('sector_count'), label: 'Sectors', icon: Grid, color: '#2E7D32', bg: 'rgba(46,125,50,0.1)' },
    { value: nyaySum, label: 'Nyay Panchayat', icon: Scale, color: '#6A1B9A', bg: 'rgba(106,27,154,0.1)' },
    { value: sum('gram_panchayat_count'), label: 'Gram Panchayat', icon: Home, color: '#8B6914', bg: 'rgba(139,105,20,0.1)' },
  ];

  const tdBorder = { borderRight: '1px solid rgba(212,168,67,0.15)' };
  const totalBorder = { borderRight: '1px solid rgba(212,168,67,0.3)' };

  // ─── Render ───────────────────────────────────────────────────────────────
  return (
    <div className="min-h-screen" style={{ background: 'var(--bg)' }}>

      {/* Sticky top bar */}
      <div
        className="sticky top-0 z-20 px-4 sm:px-6 py-3 flex items-center justify-between gap-4"
        style={{ background: '#1A3A6B', borderBottom: '1px solid #122d56' }}
      >
        <button onClick={() => nav("/")} className="p-1.5 rounded-lg hover:bg-white/10">
              <ArrowLeft size={18} className="text-white" />
            </button>
        <div>
          <h1
            className="text-white font-black text-lg leading-tight"
            style={{ fontFamily: "'Tiro Devanagari Hindi', Georgia, serif" }}
          >
            गोसवारा
          </h1>
          <p className="text-xs" style={{ color: 'rgba(255,255,255,0.5)' }}>
            {phase ? `Phase: ${phase}  •  ${formatElectionDate(electionDate)}` : loading ? 'Loading…' : 'Goswara'}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={fetchData}
            disabled={loading}
            className="flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-semibold transition-all disabled:opacity-50"
            style={{ background: 'rgba(255,255,255,0.1)', color: 'white', border: '1px solid rgba(255,255,255,0.15)' }}
          >
            <RefreshCw size={13} className={loading ? 'animate-spin' : ''} />
            <span className="hidden sm:inline">Refresh</span>
          </button>
          <button
            onClick={handlePrint}
            disabled={!rows.length || printLoading}
            className="flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-bold transition-all disabled:opacity-50"
            style={{ background: '#D4A017', color: '#1A2332' }}
          >
            {printLoading ? <Loader2 size={13} className="animate-spin" /> : <Printer size={13} />}
            <span className="hidden sm:inline">Print PDF</span>
          </button>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 space-y-5">

        {/* Hero banner */}
        <div
          className="rounded-2xl shadow-lg overflow-hidden"
          style={{ background: 'linear-gradient(135deg, #1A3A6B 0%, #2651A3 100%)' }}
        >
          <div className="p-6 sm:p-8 flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
            <div>
              <h2
                className="text-white font-black text-2xl sm:text-3xl mb-1"
                style={{ fontFamily: "'Tiro Devanagari Hindi', Georgia, serif" }}
              >
                गोसवारा
              </h2>
              <p className="text-sm" style={{ color: 'rgba(255,255,255,0.65)' }}>
                विकास खण्डवार जोनल एवं सेक्टर, न्याय पंचायत एवं ग्राम पंचायतों का विवरण
              </p>
              <div className="flex flex-wrap gap-2 mt-4">
                {phase && (
                  <span className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold text-white"
                    style={{ background: 'rgba(255,255,255,0.15)' }}>
                    <Layers size={11} /> Phase: {phase}
                  </span>
                )}
                {electionDate && (
                  <span className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold text-white"
                    style={{ background: 'rgba(255,255,255,0.15)' }}>
                    📅 {formatElectionDate(electionDate)}
                  </span>
                )}
              </div>
            </div>
            {isSuperAdmin && userDistrict && (
              <div className="flex items-center gap-2 px-4 py-2 rounded-xl self-start flex-shrink-0"
                style={{ background: 'rgba(255,255,255,0.12)', border: '1px solid rgba(255,255,255,0.2)' }}>
                <MapPin size={14} style={{ color: 'rgba(255,255,255,0.7)' }} />
                <span className="text-white text-sm font-bold">District: {userDistrict}</span>
              </div>
            )}
          </div>
        </div>

        {/* Loading skeleton */}
        {loading && (
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            {[...Array(4)].map((_, i) => (
              <div key={i} className="rounded-2xl h-28 shimmer" style={{ border: '1px solid var(--border)' }} />
            ))}
          </div>
        )}

        {/* Error state */}
        {!loading && fetchError && (
          <div className="rounded-2xl p-10 flex flex-col items-center gap-4 text-center"
            style={{ background: 'var(--bg)', border: '1px solid var(--border)' }}>
            <div className="w-16 h-16 rounded-full flex items-center justify-center"
              style={{ background: 'rgba(192,57,43,0.1)' }}>
              <AlertCircle size={28} color="#C0392B" />
            </div>
            <div>
              <p className="font-bold text-base mb-1" style={{ color: '#4A3000' }}>Failed to load data</p>
              <p className="text-xs max-w-xs" style={{ color: '#AA8844' }}>{fetchError}</p>
            </div>
            <button onClick={fetchData} className="btn-primary">
              <RefreshCw size={14} /> Retry
            </button>
          </div>
        )}

        {/* Stats grid */}
        {!loading && rows.length > 0 && (
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            {stats.map(({ value, label, icon: Icon, color, bg }, i) => (
              <div key={i} className="rounded-2xl p-5 flex flex-col items-center gap-2 fade-in"
                style={{
                  background: 'var(--bg)',
                  border: `1px solid ${color}33`,
                  boxShadow: `0 4px 16px ${color}14`,
                  animationDelay: `${i * 60}ms`,
                }}>
                <div className="w-10 h-10 rounded-full flex items-center justify-center" style={{ background: bg }}>
                  <Icon size={18} color={color} />
                </div>
                <span className="text-3xl font-black leading-none" style={{ color }}>{value}</span>
                <span className="text-xs text-center font-medium leading-tight" style={{ color: '#AA8844' }}>{label}</span>
              </div>
            ))}
          </div>
        )}

        {/* Data table */}
        {!loading && rows.length > 0 && (
          <div className="rounded-2xl overflow-hidden shadow-md fade-in"
            style={{ background: 'var(--bg)', border: '1px solid var(--border)' }}>
            <div className="px-5 py-4 flex items-center justify-between"
              style={{ background: 'rgba(139,105,20,0.06)', borderBottom: '1px solid var(--border)' }}>
              <div className="flex items-center gap-2">
                <TableProperties size={16} color="#8B6914" />
                <span className="font-black text-sm" style={{ color: '#8B6914' }}>Detailed Summary</span>
              </div>
              <span className="text-xs" style={{ color: '#AA8844' }}>{rows.length} Blocks</span>
            </div>
            <div className="overflow-x-auto">
              <table style={{ width: '100%', borderCollapse: 'collapse', minWidth: 720, fontSize: 13 }}>
                <thead>
                  <tr style={{ background: '#1A2332' }}>
                    {['Sn.', 'Block Name', 'Phase', 'Election Date',
                      'Zonal Magistrate / Police Officer', 'Sector Magistrate',
                      'Nyay Panchayat', 'Gram Panchayat'].map((h, i) => (
                        <th key={i}
                          className="px-4 py-3 text-center text-xs font-bold tracking-wide whitespace-nowrap"
                          style={{ color: '#D4A843', borderRight: '1px solid #2d3d55' }}>
                          {h}
                        </th>
                      ))}
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row, i) => {
                    const nyay = parseInt(nyayInputs[row.block_name] || row.nyay_panchayat_count || '0') || 0;
                    const isEven = i % 2 === 0;
                    return (
                      <tr key={row.block_name}
                        style={{ background: isEven ? 'var(--bg)' : 'var(--surface)' }}
                        className="transition-colors">
                        <td className="px-4 py-3 text-center text-xs font-medium" style={{ color: '#AA8844', ...tdBorder }}>{i + 1}</td>
                        <td className="px-4 py-3 font-bold text-sm" style={{ color: '#4A3000', ...tdBorder }}>{row.block_name}</td>
                        <td className="px-4 py-3 text-center text-xs" style={{ color: '#4A3000', ...tdBorder }}>{i === 0 ? phase : ''}</td>
                        <td className="px-4 py-3 text-center text-xs font-semibold" style={{ color: '#8B6914', ...tdBorder }}>{i === 0 ? formatElectionDate(electionDate) : ''}</td>
                        <td className="px-4 py-3 text-center font-bold" style={{ color: '#1565C0', ...tdBorder }}>{row.zonal_count || 0}</td>
                        <td className="px-4 py-3 text-center font-bold" style={{ color: '#2E7D32', ...tdBorder }}>{row.sector_count || 0}</td>
                        <td className="px-4 py-3 text-center font-bold" style={{ color: '#6A1B9A', ...tdBorder }}>{nyay}</td>
                        <td className="px-4 py-3 text-center font-bold" style={{ color: '#8B6914' }}>{row.gram_panchayat_count || 0}</td>
                      </tr>
                    );
                  })}
                  <tr style={{ background: '#EFE0B0' }}>
                    <td className="px-4 py-3" style={totalBorder} />
                    <td className="px-4 py-3 font-black text-sm" style={{ color: '#4A3000', ...totalBorder }}>TOTAL</td>
                    <td style={totalBorder} /><td style={totalBorder} />
                    <td className="px-4 py-3 text-center font-black" style={{ color: '#1565C0', ...totalBorder }}>{sum('zonal_count')}</td>
                    <td className="px-4 py-3 text-center font-black" style={{ color: '#2E7D32', ...totalBorder }}>{sum('sector_count')}</td>
                    <td className="px-4 py-3 text-center font-black" style={{ color: '#6A1B9A', ...totalBorder }}>{nyaySum}</td>
                    <td className="px-4 py-3 text-center font-black" style={{ color: '#8B6914' }}>{sum('gram_panchayat_count')}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* Nyay edit section */}
        {!loading && rows.length > 0 && (
          <div className="rounded-2xl overflow-hidden shadow-md fade-in"
            style={{ background: 'var(--bg)', border: '1px solid var(--border)' }}>
            <div className="px-5 py-4 flex items-center justify-between"
              style={{ background: 'rgba(106,27,154,0.06)', borderBottom: '1px solid var(--border)' }}>
              <div className="flex items-center gap-2">
                <Scale size={16} color="#6A1B9A" />
                <span className="font-black text-sm" style={{ color: '#6A1B9A' }}>Update Nyay Panchayat Count</span>
              </div>
              <span className="px-2 py-1 rounded-lg text-xs font-semibold"
                style={{ background: 'rgba(106,27,154,0.1)', color: '#6A1B9A' }}>
                Block-wise
              </span>
            </div>
            <div className="p-5 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
              {rows.map((row) => {
                const block = row.block_name;
                const isSaving = savingBlock === block;
                return (
                  <div key={block} className="flex items-end gap-2">
                    <div className="flex-1 min-w-0">
                      <label className="block text-xs font-bold mb-1.5 truncate"
                        style={{ color: '#4A3000' }} title={block}>{block}</label>
                      <input
                        type="number"
                        min="0"
                        value={nyayInputs[block] ?? ''}
                        onChange={e => setNyayInputs(prev => ({ ...prev, [block]: e.target.value }))}
                        onKeyDown={e => e.key === 'Enter' && !isSaving && handleSaveNyay(block)}
                        className="field"
                        style={{ paddingTop: 8, paddingBottom: 8 }}
                        placeholder="0"
                      />
                    </div>
                    <button
                      onClick={() => handleSaveNyay(block)}
                      disabled={isSaving}
                      className="flex-shrink-0 w-10 h-10 rounded-xl flex items-center justify-center transition-all"
                      style={{
                        background: isSaving ? 'rgba(106,27,154,0.2)' : '#6A1B9A',
                        cursor: isSaving ? 'not-allowed' : 'pointer',
                      }}
                    >
                      {isSaving
                        ? <Loader2 size={15} className="animate-spin" style={{ color: '#6A1B9A' }} />
                        : <Save size={15} color="white" />}
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Empty state */}
        {!loading && !fetchError && rows.length === 0 && (
          <div className="rounded-2xl p-16 flex flex-col items-center gap-3"
            style={{ background: 'var(--bg)', border: '1px solid var(--border)' }}>
            <TableProperties size={48} color="#AA8844" strokeWidth={1} />
            <p className="font-bold text-base" style={{ color: '#4A3000' }}>No data available</p>
            <p className="text-xs" style={{ color: '#AA8844' }}>No block data found for this district</p>
          </div>
        )}

      </div>
    </div>
  );
}