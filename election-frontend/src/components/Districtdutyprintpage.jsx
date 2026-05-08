/**
 * DistrictDutyPrintPage.jsx
 *
 * Full print/PDF report page — React equivalent of Flutter's DistrictDutyPrintPage.
 *
 * Features:
 *  - 3 tabs: मानक (Manak), असाइनमेंट (Assignment Summary), ड्यूटी विवरण (Duty-wise batches)
 *  - Per-tab "Print" button + global "सभी प्रिंट" (print all)
 *  - Search within Duty tab
 *  - Expandable batch-grouped staff table (mirrors Flutter's batch-header rows)
 *  - PDF generation via browser print (window.print) — no extra npm package needed
 *    Grand totals footer row in each table
 *
 * API endpoints used (all existing):
 *   GET /admin/district-duty/:dutyType/batches  — batches passed in via props (allBatches)
 *
 * Props:
 *   duties      array   [ { type, labelHi, label, isDefault, sankhya } ]
 *   byDuty      object  { [dutyType]: ruleObject }
 *   summary     object  { [dutyType]: { totalAssigned, batchCount } }
 *   allBatches  object  { [dutyType]: [ batchObject ] }
 *   onBack      fn()
 */

import { useState, useMemo, useRef } from "react";
import {
  ArrowLeft, Printer, Search, X, ChevronDown, ChevronUp,
  Shield, Users, Hash, Bus, StickyNote, CheckCircle2,
  AlertTriangle, FileText, BarChart3, ClipboardList,
  TrendingUp, Layers, RefreshCw
} from "lucide-react";

// ── Palette (same as ManakDistrictPage) ──────────────────────────────────────
const C = {
  bg: "#FDF6E3",
  surface: "#F5E6C8",
  primary: "#8B6914",
  dark: "#4A3000",
  subtle: "#AA8844",
  border: "#D4A843",
  error: "#C0392B",
  success: "#2D6A1E",
  district: "#6C3483",
  custom: "#00796B",
  assign: "#1565C0",
  orange: "#E65100",
};

const rankColor = (rank) =>
  ({
    SP: "#6A1B9A", ASP: "#1565C0", DSP: "#1A5276",
    Inspector: "#2E7D32", SI: "#558B2F", ASI: "#8B6914",
    "Head Constable": "#B8860B", Constable: "#6D4C41",
  }[rank] || C.primary);

// ── Helpers ───────────────────────────────────────────────────────────────────
const n = (r, k) => r ? ((r[k] || 0)) : 0;
const ns = (v) => (v === 0 ? "-" : String(v));
const totalStaffRule = (r) => {
  if (!r) return 0;
  return ["siArmedCount", "siUnarmedCount", "hcArmedCount", "hcUnarmedCount",
    "constArmedCount", "constUnarmedCount", "auxArmedCount", "auxUnarmedCount"]
    .reduce((s, k) => s + (r[k] || 0), 0);
};
const dateStr = () => {
  const d = new Date();
  return `${String(d.getDate()).padStart(2, "0")}/${String(d.getMonth() + 1).padStart(2, "0")}/${d.getFullYear()}  ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};

// ── Grand Totals ──────────────────────────────────────────────────────────────
const computeTotals = (duties, byDuty, summary) => {
  let san = 0, siA = 0, siU = 0, hcA = 0, hcU = 0,
    cA = 0, cU = 0, auxA = 0, auxU = 0, pac = 0, asgn = 0, batch = 0;
  duties.forEach(d => {
    const r = byDuty[d.type];
    san += d.sankhya || 0;
    siA += n(r, "siArmedCount"); siU += n(r, "siUnarmedCount");
    hcA += n(r, "hcArmedCount"); hcU += n(r, "hcUnarmedCount");
    cA += n(r, "constArmedCount"); cU += n(r, "constUnarmedCount");
    auxA += n(r, "auxArmedCount"); auxU += n(r, "auxUnarmedCount");
    pac += (r?.pacCount || 0);
    const s = summary[d.type] || {};
    asgn += (s.totalAssigned || 0);
    batch += (s.batchCount || 0);
  });
  return { san, siA, siU, hcA, hcU, cA, cU, auxA, auxU, pac, asgn, batch };
};

// ── Status helper ─────────────────────────────────────────────────────────────
const assignStatus = (req, asgn) => {
  if (req === 0) return { label: "मानक नहीं", color: C.subtle };
  if (asgn > req) return { label: "अधिक", color: "#6A1B9A" };
  if (asgn >= req) return { label: "पूर्ण ✓", color: C.success };
  if (asgn === 0) return { label: "खाली", color: C.error };
  return { label: "आंशिक", color: C.orange };
};

// ── Print Section Header Bar ──────────────────────────────────────────────────
const SectionBar = ({ title, subtitle, icon: Icon, color, onPrint, generating }) => (
  <div style={{ background: `${color}08`, padding: "10px 20px", display: "flex", alignItems: "center", gap: 12, borderBottom: `1px solid ${color}22`, flexShrink: 0 }}>
    <div style={{ width: 36, height: 36, background: color, borderRadius: 9, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
      <Icon size={17} color="white" />
    </div>
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ color, fontSize: 13.5, fontWeight: 800, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{title}</div>
      <div style={{ color: C.subtle, fontSize: 10.5, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{subtitle}</div>
    </div>
    {generating ? (
      <div style={{ width: 18, height: 18, border: `2px solid ${color}`, borderTopColor: "transparent", borderRadius: "50%", animation: "spin 1s linear infinite" }} />
    ) : (
      <button onClick={onPrint} style={{
        background: color, border: "none", borderRadius: 8, padding: "7px 14px",
        color: "white", fontSize: 12, fontWeight: 800, cursor: "pointer",
        display: "flex", alignItems: "center", gap: 6, fontFamily: "inherit"
      }}>
        <Printer size={14} />प्रिंट
      </button>
    )}
  </div>
);

// ── Stat Row ──────────────────────────────────────────────────────────────────
const StatRow = ({ items }) => (
  <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginBottom: 16 }}>
    {items.map(({ label, value, color }) => (
      <div key={label} style={{
        flex: "1 1 72px", background: `${color}10`, border: `1px solid ${color}28`,
        borderRadius: 10, padding: "10px 14px", textAlign: "center"
      }}>
        <div style={{ color, fontSize: 20, fontWeight: 900, lineHeight: 1 }}>{value}</div>
        <div style={{ color, fontSize: 10, fontWeight: 600, opacity: .8, marginTop: 3 }}>{label}</div>
      </div>
    ))}
  </div>
);

// ── Government-style Table ────────────────────────────────────────────────────
const GovTable = ({ headers, rows, footerRow, statusColIdx, flexColIdx = 1 }) => (
  <div style={{
    borderRadius: 10, overflow: "hidden",
    border: `1px solid ${C.border}55`,
    boxShadow: `0 2px 12px ${C.district}08`,
    overflowX: "auto",
    marginBottom: 0,
  }}>
    <table style={{ width: "100%", borderCollapse: "collapse", minWidth: 480 }}>
      <thead>
        <tr style={{ background: "#1A1A2E" }}>
          {headers.map((h, i) => (
            <th key={i} style={{
              padding: "8px 10px", color: "white", fontSize: 10.5, fontWeight: 800,
              textAlign: i === flexColIdx ? "left" : "center",
              whiteSpace: "nowrap", borderRight: i < headers.length - 1 ? "1px solid rgba(255,255,255,.1)" : "none"
            }}>{h}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((row, ri) => {
          if (row._isBatchHeader) {
            return (
              <tr key={`bh-${ri}`} style={{ background: "#EDE3F8" }}>
                <td style={{ padding: "6px 10px", color: "#4A2A6A", fontWeight: 900, fontSize: 11, textAlign: "center", borderRight: "1px solid rgba(0,0,0,.06)" }}>B{row._batchNo}</td>
                <td colSpan={headers.length - 1} style={{ padding: "6px 10px", color: "#4A2A6A", fontWeight: 800, fontSize: 11 }}>{row._label}</td>
              </tr>
            );
          }
          return (
            <tr key={ri} style={{ background: ri % 2 === 0 ? "white" : "#FAF8F0", borderTop: "1px solid rgba(0,0,0,.04)" }}>
              {row.map((cell, ci) => {
                let textColor = "#2C2C2C";
                if (ci === statusColIdx) {
                  if (cell?.includes?.("✓")) textColor = C.success;
                  else if (cell === "खाली") textColor = C.error;
                  else if (cell === "आंशिक") textColor = C.orange;
                  else if (cell === "अधिक") textColor = "#6A1B9A";
                  else if (cell === "मानक नहीं") textColor = C.subtle;
                }
                return (
                  <td key={ci} style={{
                    padding: "7px 10px", fontSize: 11.5,
                    textAlign: ci === flexColIdx ? "left" : "center",
                    color: textColor,
                    fontWeight: ci === 0 || ci === statusColIdx ? 700 : "normal",
                    borderRight: ci < row.length - 1 ? "1px solid rgba(0,0,0,.05)" : "none",
                    whiteSpace: ci === flexColIdx ? "normal" : "nowrap",
                  }}>{cell}</td>
                );
              })}
            </tr>
          );
        })}
        {footerRow && (
          <tr style={{ background: "#ECE5F5", borderTop: "2px solid rgba(108,52,131,.2)" }}>
            {footerRow.map((cell, ci) => (
              <td key={ci} style={{
                padding: "8px 10px", fontSize: 11.5, fontWeight: 900,
                textAlign: ci === flexColIdx ? "left" : "center",
                color: "#2C2C2C",
                borderRight: ci < footerRow.length - 1 ? "1px solid rgba(0,0,0,.06)" : "none",
              }}>{cell}</td>
            ))}
          </tr>
        )}
      </tbody>
    </table>
  </div>
);

// ── Duty Preview Card (Tab 3) ─────────────────────────────────────────────────
const DutyPreviewCard = ({ duty, batches, rule, onPrint, generating }) => {
  const [expanded, setExpanded] = useState(false);
  const total = batches.reduce((s, b) => s + (b.staffCount || 0), 0);
  const color = duty.isDefault ? C.district : C.custom;
  const isDone = total >= (duty.sankhya || 0) && (duty.sankhya || 0) > 0;

  // Build batch-grouped rows for the table
  const groupedRows = useMemo(() => {
    const rows = [];
    let globalSrl = 0;
    batches.forEach(b => {
      const bNo = b.batchNo || 0;
      const staff = b.staff || [];
      const busNo = b.busNo || "";
      const note = b.note || "";
      const label = `Batch ${bNo}  •  ${staff.length} staff${busNo ? `  •  Bus: ${busNo}` : ""}${note ? `  •  ${note}` : ""}`;
      rows.push({ _isBatchHeader: true, _batchNo: bNo, _label: label });
      staff.forEach(s => {
        globalSrl++;
        rows.push([
          String(globalSrl),
          s.name || "-",
          s.pno || "-",
          s.rank || "-",
          s.thana || "-",
          s.mobile || "-",
          s.isArmed ? "हाँ" : "नहीं",
          busNo || "-",
        ]);
      });
    });
    return rows;
  }, [batches]);

  return (
    <div style={{
      background: "white", borderRadius: 12,
      border: `1px solid ${color}30`,
      boxShadow: `0 2px 10px ${color}0a`,
      overflow: "hidden", marginBottom: 14,
    }}>
      {/* Header */}
      <div onClick={() => setExpanded(e => !e)} style={{
        background: `${color}08`, padding: "12px 16px",
        display: "flex", alignItems: "center", gap: 12, cursor: "pointer"
      }}>
        <div style={{ width: 34, height: 34, background: color, borderRadius: 9, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
          <FileText size={16} color="white" />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ color, fontSize: 13, fontWeight: 800, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{duty.labelHi || duty.label}</div>
          <div style={{ color: C.subtle, fontSize: 10.5 }}>
            {batches.length} Batches  •  {total} Assigned{duty.sankhya > 0 ? `  •  संख्या: ${duty.sankhya}` : ""}
          </div>
        </div>
        {isDone && (
          <span style={{ background: `${C.success}12`, color: C.success, fontSize: 10, fontWeight: 700, borderRadius: 6, padding: "3px 8px", whiteSpace: "nowrap" }}>✓ पूर्ण</span>
        )}
        {generating ? (
          <div style={{ width: 16, height: 16, border: `2px solid ${color}`, borderTopColor: "transparent", borderRadius: "50%", animation: "spin 1s linear infinite", marginRight: 6 }} />
        ) : (
          <button onClick={e => { e.stopPropagation(); onPrint(); }} style={{
            background: color, border: "none", borderRadius: 7, width: 30, height: 30,
            display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", flexShrink: 0
          }}>
            <Printer size={14} color="white" />
          </button>
        )}
        <div style={{ marginLeft: 4, color, flexShrink: 0 }}>
          {expanded ? <ChevronUp size={18} /> : <ChevronDown size={18} />}
        </div>
      </div>

      {/* Expanded: batch-grouped table */}
      {expanded && (
        <div style={{ padding: 12 }}>
          {batches.length === 0 ? (
            <div style={{ textAlign: "center", padding: 20, color: C.subtle, fontSize: 12 }}>कोई batch नहीं है।</div>
          ) : (
            <GovTable
              headers={["क्र.", "नाम", "PNO", "पद", "थाना", "मोबाइल", "Armed", "बस"]}
              rows={groupedRows}
              flexColIdx={1}
            />
          )}
        </div>
      )}
    </div>
  );
};

// ══════════════════════════════════════════════════════════════════════════════
//  PRINT HELPERS — generates printable HTML and triggers window.print()
// ══════════════════════════════════════════════════════════════════════════════
function buildPrintHtml({ duties, byDuty, summary, allBatches, section = "all" }) {
  const totals = computeTotals(duties, byDuty, summary);
  const ds = dateStr();

  const style = `
    @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;600;700;800;900&display=swap');
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Noto Sans Devanagari', serif; font-size: 11px; color: #2C2C2C; background: white; }
    @page { size: A4; margin: 12mm 14mm 16mm; }
    @media print { body { -webkit-print-color-adjust: exact; print-color-adjust: exact; } .no-print { display: none; } }
    .page { page-break-after: always; padding: 0; }
    .page:last-child { page-break-after: avoid; }
    h1 { font-size: 13px; font-weight: 900; color: #1A1A2E; }
    h2 { font-size: 11px; font-weight: 800; color: #3A3A5C; margin-top: 3px; }
    .meta { font-size: 9px; color: #888; }
    .rule-double { border-top: 2px solid black; border-bottom: 0.5px solid #666; padding-top: 3px; margin: 6px 0 10px; }
    .stats { display: flex; gap: 12px; margin-bottom: 12px; flex-wrap: wrap; }
    .stat-box { border: 0.6px solid #999; border-radius: 4px; padding: 6px 12px; text-align: center; background: #F8F8FF; }
    .stat-v { font-size: 15px; font-weight: 900; }
    .stat-l { font-size: 8px; color: #666; margin-top: 1px; }
    .sec-bar { background: #3A3A5C; color: white; padding: 5px 10px; font-size: 9px; font-weight: 800; margin: 8px 0 4px; }
    table { width: 100%; border-collapse: collapse; }
    th { background: #1A1A2E; color: white; padding: 5px 7px; font-size: 8.5px; font-weight: 800; text-align: center; }
    th.left { text-align: left; }
    td { padding: 5px 7px; font-size: 9px; text-align: center; border: 0.4px solid #ccc; }
    td.left { text-align: left; }
    tr:nth-child(even) td { background: #F6F3FF; }
    tr.footer td { background: #E8E0F5; font-weight: 900; font-size: 9.5px; }
    tr.batch-hdr td { background: #EDE3F8; font-weight: 900; color: #4A2A6A; font-size: 8.5px; }
    .footer-bar { margin-top: 8px; border-top: 0.5px solid #aaa; padding-top: 3px; display: flex; justify-content: space-between; font-size: 8px; color: #888; }
    .conf { font-weight: 800; }
  `;

  const header = (title, sub = "") => `
    <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:4px">
      <div>
        <h1>जनपदीय कानून व्यवस्था — ड्यूटी विवरण</h1>
        <h2>${title}</h2>
        ${sub ? `<div class="meta">${sub}</div>` : ""}
      </div>
      <div style="text-align:right">
        <div class="meta">दिनांक: ${ds}</div>
        <div class="meta conf">गोपनीय</div>
      </div>
    </div>
    <div class="rule-double"></div>
  `;

  const footer = `<div class="footer-bar"><span>जनपदीय कानून व्यवस्था — गोपनीय</span><span class="conf">रिपोर्ट</span></div>`;

  let pages = "";

  // ── Page 1: Manak ──────────────────────────────────────────────────────────
  if (section === "all" || section === "manak") {
    const totalStaff = totals.siA + totals.siU + totals.hcA + totals.hcU + totals.cA + totals.cU + totals.auxA + totals.auxU;
    let rows = "";
    duties.forEach((d, i) => {
      const r = byDuty[d.type];
      const pac = r?.pacCount || 0;
      const bg = i % 2 === 0 ? "" : "background:#F6F3FF";
      rows += `<tr style="${bg}">
        <td>${i + 1}</td>
        <td class="left">${d.labelHi || d.label}</td>
        <td>${(d.sankhya || 0) > 0 ? d.sankhya : "-"}</td>
        <td>${ns(n(r, "siArmedCount"))}</td>
        <td>${ns(n(r, "siUnarmedCount"))}</td>
        <td>${ns(n(r, "hcArmedCount"))}</td>
        <td>${ns(n(r, "hcUnarmedCount"))}</td>
        <td>${ns(n(r, "constArmedCount"))}</td>
        <td>${ns(n(r, "constUnarmedCount"))}</td>
        <td>${ns(n(r, "auxArmedCount"))}</td>
        <td>${ns(n(r, "auxUnarmedCount"))}</td>
        <td>${pac === 0 ? "-" : Math.floor(pac)}</td>
        <td><strong>${r ? totalStaffRule(r) : "-"}</strong></td>
      </tr>`;
    });
    pages += `<div class="page">
      ${header("मानक विवरण — पृष्ठ १")}
      <div class="stats">
        <div class="stat-box"><div class="stat-v">${duties.length}</div><div class="stat-l">कुल ड्यूटी</div></div>
        <div class="stat-box"><div class="stat-v">${totals.san}</div><div class="stat-l">संख्या योग</div></div>
        <div class="stat-box"><div class="stat-v">${totalStaff}</div><div class="stat-l">पुलिस बल</div></div>
      </div>
      <div class="sec-bar">ड्यूटी प्रकारवार पुलिस बल मानक</div>
      <table>
        <thead><tr>
          <th style="width:28px">क्र.</th>
          <th class="left" style="width:130px">ड्यूटी प्रकार</th>
          <th style="width:42px">संख्या</th>
          <th>SI स.</th><th>SI नि.</th>
          <th>HC स.</th><th>HC नि.</th>
          <th>Con स.</th><th>Con नि.</th>
          <th>Aux स.</th><th>Aux नि.</th>
          <th>PAC</th><th>कुल</th>
        </tr></thead>
        <tbody>${rows}</tbody>
        <tfoot><tr class="footer">
          <td></td><td class="left">योग</td>
          <td>${totals.san}</td>
          <td>${totals.siA}</td><td>${totals.siU}</td>
          <td>${totals.hcA}</td><td>${totals.hcU}</td>
          <td>${totals.cA}</td><td>${totals.cU}</td>
          <td>${totals.auxA}</td><td>${totals.auxU}</td>
          <td>${totals.pac === 0 ? "-" : Math.floor(totals.pac)}</td>
          <td>${totalStaff}</td>
        </tr></tfoot>
      </table>
      ${footer}
    </div>`;
  }

  // ── Page 2: Assignment Summary ─────────────────────────────────────────────
  if (section === "all" || section === "assign") {
    let rows = "";
    duties.forEach((d, i) => {
      const s = summary[d.type] || {};
      const asgn = s.totalAssigned || 0;
      const batchCnt = s.batchCount || 0;
      const req = d.sankhya || 0;
      const rem = Math.max(0, req - asgn);
      const st = assignStatus(req, asgn);
      const bg = i % 2 === 0 ? "" : "background:#F6F3FF";
      rows += `<tr style="${bg}">
        <td>${i + 1}</td>
        <td class="left">${d.labelHi || d.label}</td>
        <td>${req > 0 ? req : "-"}</td>
        <td><strong>${asgn}</strong></td>
        <td>${batchCnt}</td>
        <td>${req > 0 ? rem : "-"}</td>
        <td style="color:${st.color};font-weight:800">${st.label}</td>
      </tr>`;
    });
    const remAll = Math.max(0, totals.san - totals.asgn);
    pages += `<div class="page">
      ${header("असाइनमेंट सारांश — पृष्ठ २")}
      <div class="stats">
        <div class="stat-box"><div class="stat-v">${totals.san}</div><div class="stat-l">आवश्यक</div></div>
        <div class="stat-box"><div class="stat-v">${totals.asgn}</div><div class="stat-l">Assigned</div></div>
        <div class="stat-box"><div class="stat-v">${totals.batch}</div><div class="stat-l">Batches</div></div>
        <div class="stat-box"><div class="stat-v">${remAll}</div><div class="stat-l">शेष</div></div>
      </div>
      <div class="sec-bar">ड्यूटी असाइनमेंट स्थिति</div>
      <table>
        <thead><tr>
          <th style="width:28px">क्र.</th>
          <th class="left">ड्यूटी प्रकार</th>
          <th>आवश्यक</th>
          <th>Assigned</th>
          <th>Batches</th>
          <th>शेष</th>
          <th>स्थिति</th>
        </tr></thead>
        <tbody>${rows}</tbody>
        <tfoot><tr class="footer">
          <td></td><td class="left">योग</td>
          <td>${totals.san}</td>
          <td>${totals.asgn}</td>
          <td>${totals.batch}</td>
          <td>${remAll}</td>
          <td></td>
        </tr></tfoot>
      </table>
      ${footer}
    </div>`;
  }

  // ── Pages 3+: Per-duty batch-grouped staff ─────────────────────────────────
  const dutiesToPrint = (section === "all" || section === "duty")
    ? duties
    : duties.filter(d => d.type === section);

  dutiesToPrint.forEach(d => {
    const batches = allBatches[d.type] || [];
    if (!batches.length) return;
    const rule = byDuty[d.type];
    const total = batches.reduce((s, b) => s + (b.staffCount || 0), 0);

    // Rule string
    const rParts = [];
    [["siArmedCount", "SI स."], ["siUnarmedCount", "SI नि."], ["hcArmedCount", "HC स."],
    ["hcUnarmedCount", "HC नि."], ["constArmedCount", "Con स."], ["constUnarmedCount", "Con नि."],
    ["auxArmedCount", "Aux स."], ["auxUnarmedCount", "Aux नि."]].forEach(([k, l]) => {
      if (n(rule, k) > 0) rParts.push(`${l} ${n(rule, k)}`);
    });
    const pac = rule?.pacCount || 0;
    if (pac > 0) rParts.push(`PAC ${Math.floor(pac)}`);
    const rStr = rParts.join("  |  ");

    let staffRows = "";
    let globalSrl = 0;
    batches.forEach(b => {
      const bNo = b.batchNo || 0;
      const staff = b.staff || [];
      const busNo = b.busNo || "";
      const note = b.note || "";
      staffRows += `<tr class="batch-hdr">
        <td>B${bNo}</td>
        <td colspan="7" class="left">Batch ${bNo}  •  ${staff.length} staff${busNo ? `  •  Bus: ${busNo}` : ""}${note ? `  •  ${note}` : ""}</td>
      </tr>`;
      staff.forEach(s => {
        globalSrl++;
        const bgS = globalSrl % 2 === 0 ? "background:#F6F3FF" : "";
        staffRows += `<tr style="${bgS}">
          <td>${globalSrl}</td>
          <td class="left">${s.name || "-"}</td>
          <td>${s.pno || "-"}</td>
          <td>${s.rank || "-"}</td>
          <td class="left">${s.thana || "-"}</td>
          <td>${s.mobile || "-"}</td>
          <td>${s.isArmed ? "हाँ" : "नहीं"}</td>
          <td>${busNo || "-"}</td>
        </tr>`;
      });
    });

    const stLabel = total >= (d.sankhya || 0) && (d.sankhya || 0) > 0 ? "पूर्ण ✓" : "आंशिक";
    pages += `<div class="page">
      ${header(d.labelHi || d.label, `${batches.length} Batches  •  ${total} Assigned  •  संख्या: ${d.sankhya || 0}`)}
      <div class="stats">
        <div class="stat-box"><div class="stat-v">${d.sankhya || 0}</div><div class="stat-l">संख्या</div></div>
        <div class="stat-box"><div class="stat-v">${total}</div><div class="stat-l">Assigned</div></div>
        <div class="stat-box"><div class="stat-v">${batches.length}</div><div class="stat-l">Batches</div></div>
        <div class="stat-box"><div class="stat-v">${stLabel}</div><div class="stat-l">स्थिति</div></div>
      </div>
      ${rStr ? `<div style="border:0.5px solid #ccc;border-radius:3px;background:#F8F8FF;padding:5px 8px;font-size:8.5px;margin-bottom:8px">पुलिस बल मानक: ${rStr}</div>` : ""}
      <div class="sec-bar">${d.labelHi || d.label} — Batch-wise Staff विवरण</div>
      <table>
        <thead><tr>
          <th style="width:28px">क्र.</th>
          <th class="left">नाम</th>
          <th>PNO</th>
          <th>पद</th>
          <th class="left">थाना</th>
          <th>मोबाइल</th>
          <th>Armed</th>
          <th>बस</th>
        </tr></thead>
        <tbody>${staffRows}</tbody>
      </table>
      ${footer}
    </div>`;
  });

  if (!pages) {
    pages = `<div class="page"><div style="text-align:center;padding:60px;color:#888;font-size:14px">कोई डेटा नहीं</div></div>`;
  }

  return `<!DOCTYPE html><html><head><meta charset="utf-8"><title>जनपदीय ड्यूटी विवरण</title><style>${style}</style></head><body>${pages}</body></html>`;
}

function triggerPrint(html) {
  const win = window.open("", "_blank", "width=900,height=700");
  if (!win) { alert("Popup blocked. Please allow popups for this site."); return; }
  win.document.write(html);
  win.document.close();
  win.focus();
  setTimeout(() => { win.print(); }, 600);
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN PRINT PAGE
// ══════════════════════════════════════════════════════════════════════════════
export default function DistrictDutyPrintPage({ duties, byDuty, summary, allBatches, onBack }) {
  const [tab, setTab] = useState("manak");
  const [generating, setGenerating] = useState("");
  const [searchQ, setSearchQ] = useState("");

  const totals = useMemo(() => computeTotals(duties, byDuty, summary), [duties, byDuty, summary]);

  const print = (section) => {
    setGenerating(section);
    try {
      const html = buildPrintHtml({ duties, byDuty, summary, allBatches, section });
      triggerPrint(html);
    } finally {
      setTimeout(() => setGenerating(""), 800);
    }
  };

  // ── Manak tab rows ──────────────────────────────────────────────────────────
  const maakRows = useMemo(() => duties.map((d, i) => {
    const r = byDuty[d.type];
    const pac = r?.pacCount || 0;
    return [
      String(i + 1),
      d.labelHi || d.label,
      (d.sankhya || 0) > 0 ? String(d.sankhya) : "-",
      ns(n(r, "siArmedCount") + n(r, "siUnarmedCount")),
      ns(n(r, "hcArmedCount") + n(r, "hcUnarmedCount")),
      ns(n(r, "constArmedCount") + n(r, "constUnarmedCount")),
      ns(n(r, "auxArmedCount") + n(r, "auxUnarmedCount")),
      pac === 0 ? "-" : String((pac)),
      r ? String(totalStaffRule(r)) : "-",
    ];
  }), [duties, byDuty]);

  const maakFooter = useMemo(() => {
    const ts = totals.siA + totals.siU + totals.hcA + totals.hcU + totals.cA + totals.cU + totals.auxA + totals.auxU;
    return ["", "योग", String(totals.san),
      String(totals.siA + totals.siU), String(totals.hcA + totals.hcU),
      String(totals.cA + totals.cU), String(totals.auxA + totals.auxU),
      totals.pac === 0 ? "-" : String((totals.pac)),
      String(ts)];
  }, [totals]);

  // ── Assignment tab rows ─────────────────────────────────────────────────────
  const assignRows = useMemo(() => duties.map((d, i) => {
    const s = summary[d.type] || {};
    const asgn = s.totalAssigned || 0;
    const batchCnt = s.batchCount || 0;
    const req = d.sankhya || 0;
    const rem = Math.max(0, req - asgn);
    return [
      String(i + 1),
      d.labelHi || d.label,
      req > 0 ? String(req) : "-",
      String(asgn),
      String(batchCnt),
      req > 0 ? String(rem) : "-",
      assignStatus(req, asgn).label,
    ];
  }), [duties, summary]);

  const assignFooter = useMemo(() => [
    "", "योग", String(totals.san), String(totals.asgn), String(totals.batch),
    String(Math.max(0, totals.san - totals.asgn)), ""
  ], [totals]);

  // ── Filtered duties for tab 3 ───────────────────────────────────────────────
  const filteredDuties = useMemo(() => {
    if (!searchQ.trim()) return duties;
    const q = searchQ.toLowerCase();
    return duties.filter(d => (d.labelHi || d.label || "").toLowerCase().includes(q));
  }, [duties, searchQ]);

  const totalStaffAll = totals.siA + totals.siU + totals.hcA + totals.hcU + totals.cA + totals.cU + totals.auxA + totals.auxU;

  return (
    <div style={{ height: "100vh", display: "flex", flexDirection: "column", background: C.bg, fontFamily: "'Noto Sans Devanagari',Georgia,serif" }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;600;700;800;900&family=Playfair+Display:wght@700;800;900&display=swap');
        @keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
        *{box-sizing:border-box}
        button,input{font-family:inherit}
        ::-webkit-scrollbar{width:5px;height:5px}
        ::-webkit-scrollbar-track{background:${C.surface}}
        ::-webkit-scrollbar-thumb{background:${C.border};border-radius:3px}
      `}</style>

      {/* AppBar */}
      <div style={{ background: C.district, flexShrink: 0 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 14, padding: "14px 24px 0" }}>
          <button onClick={onBack} style={{ background: "rgba(255,255,255,.15)", border: "none", borderRadius: 9, width: 36, height: 36, display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
            <ArrowLeft size={18} color="white" />
          </button>
          <div style={{ flex: 1 }}>
            <div style={{ color: "white", fontWeight: 800, fontSize: 17 }}>प्रिंट रिपोर्ट</div>
            <div style={{ color: "rgba(255,255,255,.6)", fontSize: 11 }}>सेक्शन चुनें → प्रिंट करें</div>
          </div>
          {generating === "all" ? (
            <div style={{ width: 20, height: 20, border: "2px solid white", borderTopColor: "transparent", borderRadius: "50%", animation: "spin 1s linear infinite" }} />
          ) : (
            <button onClick={() => print("all")} style={{
              background: "rgba(255,255,255,.18)", border: "none", borderRadius: 8, padding: "7px 16px",
              color: "white", fontWeight: 800, fontSize: 12, cursor: "pointer",
              display: "flex", alignItems: "center", gap: 6, fontFamily: "inherit"
            }}>
              <Printer size={15} />सभी
            </button>
          )}
        </div>
        {/* Tabs */}
        <div style={{ display: "flex", padding: "0 24px", marginTop: 8, gap: 2 }}>
          {[["manak", "मानक"], ["assign", "असाइनमेंट"], ["duty", "ड्यूटी विवरण"]].map(([v, l]) => (
            <button key={v} onClick={() => setTab(v)} style={{
              padding: "10px 20px", border: "none", background: "transparent",
              color: tab === v ? "white" : "rgba(255,255,255,.55)", fontWeight: tab === v ? 800 : 500, fontSize: 13,
              cursor: "pointer", borderBottom: tab === v ? "3px solid white" : "3px solid transparent",
              transition: "all .18s", fontFamily: "inherit"
            }}>{l}</button>
          ))}
        </div>
      </div>

      {/* Body */}
      <div style={{ flex: 1, overflow: "hidden", display: "flex", flexDirection: "column" }}>

        {/* ── Tab 1: Manak ── */}
        {tab === "manak" && (
          <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
            <SectionBar
              title="मानक विवरण — पृष्ठ १"
              subtitle={`${duties.length} ड्यूटी  •  संख्या: ${totals.san}`}
              icon={Shield} color={C.district}
              onPrint={() => print("manak")}
              generating={generating === "manak"}
            />
            <div style={{ flex: 1, overflowY: "auto", padding: "20px 24px" }}>
              <StatRow items={[
                { label: "ड्यूटी", value: duties.length, color: C.district },
                { label: "संख्या", value: totals.san, color: C.orange },
                { label: "पुलिस बल", value: totalStaffAll, color: C.assign },
              ]} />
              <GovTable
                headers={["क्र.", "ड्यूटी प्रकार", "संख्या", "SI", "HC", "Con", "Aux", "PAC", "कुल"]}
                rows={maakRows}
                footerRow={maakFooter}
                flexColIdx={1}
              />
            </div>
          </div>
        )}

        {/* ── Tab 2: Assignment Summary ── */}
        {tab === "assign" && (
          <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
            <SectionBar
              title="असाइनमेंट सारांश — पृष्ठ २"
              subtitle={`${totals.asgn} Assigned  •  ${totals.batch} Batches`}
              icon={Users} color={C.assign}
              onPrint={() => print("assign")}
              generating={generating === "assign"}
            />
            <div style={{ flex: 1, overflowY: "auto", padding: "20px 24px" }}>
              <StatRow items={[
                { label: "आवश्यक", value: totals.san, color: C.district },
                { label: "Assigned", value: totals.asgn, color: C.success },
                { label: "Batches", value: totals.batch, color: C.orange },
                { label: "शेष", value: Math.max(0, totals.san - totals.asgn), color: C.error },
              ]} />
              <GovTable
                headers={["क्र.", "ड्यूटी प्रकार", "आवश्यक", "Assigned", "Batches", "शेष", "स्थिति"]}
                rows={assignRows}
                footerRow={assignFooter}
                statusColIdx={6}
                flexColIdx={1}
              />
            </div>
          </div>
        )}

        {/* ── Tab 3: Duty-wise ── */}
        {tab === "duty" && (
          <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
            <div style={{ background: "white", padding: "12px 20px", borderBottom: `1px solid ${C.border}33`, flexShrink: 0 }}>
              <div style={{ position: "relative", marginBottom: 8 }}>
                <Search size={14} color={C.subtle} style={{ position: "absolute", left: 11, top: "50%", transform: "translateY(-50%)" }} />
                <input
                  value={searchQ}
                  onChange={e => setSearchQ(e.target.value)}
                  placeholder="ड्यूटी नाम खोजें..."
                  style={{
                    width: "100%", border: `1px solid ${C.border}`, borderRadius: 10,
                    padding: "9px 12px 9px 34px", background: `${C.district}05`,
                    color: C.dark, fontSize: 13, outline: "none", boxSizing: "border-box"
                  }}
                />
                {searchQ && (
                  <button onClick={() => setSearchQ("")} style={{ position: "absolute", right: 10, top: "50%", transform: "translateY(-50%)", background: "none", border: "none", cursor: "pointer", padding: 0 }}>
                    <X size={14} color={C.subtle} />
                  </button>
                )}
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <span style={{ color: C.subtle, fontSize: 11 }}>{filteredDuties.length} ड्यूटी प्रकार</span>
                {generating === "duty" ? (
                  <div style={{ width: 18, height: 18, border: `2px solid ${C.orange}`, borderTopColor: "transparent", borderRadius: "50%", animation: "spin 1s linear infinite" }} />
                ) : (
                  <button onClick={() => print("duty")} style={{
                    background: C.orange, border: "none", borderRadius: 8, padding: "6px 14px",
                    color: "white", fontSize: 11, fontWeight: 800, cursor: "pointer",
                    display: "flex", alignItems: "center", gap: 5, fontFamily: "inherit"
                  }}>
                    <Printer size={13} />सभी Duty प्रिंट
                  </button>
                )}
              </div>
            </div>

            <div style={{ flex: 1, overflowY: "auto", padding: "12px 20px" }}>
              {filteredDuties.length === 0 ? (
                <div style={{ textAlign: "center", padding: 48, color: C.subtle }}>
                  <Search size={40} style={{ opacity: .3 }} />
                  <div style={{ marginTop: 10, fontSize: 13 }}>"{searchQ}" नहीं मिला</div>
                </div>
              ) : filteredDuties.map(d => (
                <DutyPreviewCard
                  key={d.type}
                  duty={d}
                  batches={allBatches[d.type] || []}
                  rule={byDuty[d.type]}
                  onPrint={() => print(d.type)}
                  generating={generating === d.type}
                />
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}