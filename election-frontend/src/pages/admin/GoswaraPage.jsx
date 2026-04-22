import { useState, useEffect, useCallback } from "react";
import { ArrowLeft, Printer, RefreshCw, MapPin, AlertCircle, Loader2, Save } from "lucide-react";
import { useNavigate } from "react-router-dom";
import apiClient from "../../api/client";
import { useAuthStore } from "../../store/authStore";

// ── helpers ──────────────────────────────────────────────────────────────────
function sum(data, key) {
    return data.reduce((s, r) => s + (r[key] ?? 0), 0);
}

// ── Print function (mirrors Flutter PDF layout) ───────────────────────────────
function printGoswara({ data, electionDate, phase, isSuperAdmin, userDistrict }) {
    const win = window.open("", "_blank");
    if (!win) return;

    const esc = (s) =>
        String(s ?? "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");

    const totalZonal = sum(data, "zonal_count");
    const totalSector = sum(data, "sector_count");
    const totalNyay = sum(data, "nyay_panchayat_count");
    const totalGram = sum(data, "gram_panchayat_count");

    const dataRows = data
        .map((r, i) => `
      <tr>
        <td class="center">${i + 1}</td>
        <td>${esc(r.block_name ?? "")}</td>
        <td class="center">${i === 0 ? esc(phase) : ""}</td>
        <td class="center">${i === 0 ? esc(electionDate) : ""}</td>
        <td class="center">${r.zonal_count ?? 0}</td>
        <td class="center">${r.sector_count ?? 0}</td>
        <td class="center">${r.nyay_panchayat_count ?? 0}</td>
        <td class="center">${r.gram_panchayat_count ?? 0}</td>
      </tr>`)
        .join("");

    win.document.write(`<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>गोसवारा</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700&display=swap" rel="stylesheet">
  <style>
    @page { size: A4 landscape; margin: 24mm 20mm; }
    * { box-sizing: border-box; }
    body {
      font-family: 'Noto Sans Devanagari', Arial, sans-serif;
      font-size: 10pt;
      color: #1a1a1a;
      margin: 0; padding: 0;
    }
    h1 {
      text-align: center;
      font-size: 16pt;
      font-weight: 700;
      margin: 0 0 5pt;
    }
    .subtitle {
      text-align: center;
      font-size: 9pt;
      color: #444;
      margin: 0 0 4pt;
    }
    .district {
      text-align: center;
      font-size: 10pt;
      font-weight: 700;
      margin: 4pt 0 12pt;
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    th, td {
      border: 0.7pt solid #555;
      padding: 5pt 5pt;
      font-size: 10pt;
      vertical-align: middle;
    }
    th {
      background: #d1d5db;
      font-weight: 700;
      text-align: center;
      white-space: pre-line;
      line-height: 1.3;
    }
    td.center { text-align: center; }
    .total-row td {
      background: #d1d5db;
      font-weight: 700;
      text-align: center;
    }
    col.sno   { width: 30pt; }
    col.block { width: 110pt; }
    col.phase { width: 65pt; }
    col.date  { width: 80pt; }
    col.zonal { width: 115pt; }
    col.sect  { width: 95pt; }
    col.nyay  { width: 90pt; }
    col.gram  { width: 90pt; }
    @media print {
      body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    }
  </style>
</head>
<body>
  <h1>गोसवारा</h1>
  <p class="subtitle">विकास खण्डवार जोनल एवं सेक्टर, न्याय पंचायत एवं ग्राम पंचायतों का विवरण</p>
  ${isSuperAdmin && userDistrict ? `<p class="district">जनपद: ${esc(userDistrict)}</p>` : ""}
  <table>
    <colgroup>
      <col class="sno">
      <col class="block">
      <col class="phase">
      <col class="date">
      <col class="zonal">
      <col class="sect">
      <col class="nyay">
      <col class="gram">
    </colgroup>
    <thead>
      <tr>
        <th>क्र०\nसं०</th>
        <th>विकास खण्ड</th>
        <th>चरण</th>
        <th>मतदान\nतिथि</th>
        <th>जोनल मजिस्ट्रेट /\nपुलिस अधिकारी</th>
        <th>सेक्टर\nमजिस्ट्रेट</th>
        <th>न्याय\nपंचायत</th>
        <th>ग्राम\nपंचायत</th>
      </tr>
    </thead>
    <tbody>
      ${dataRows}
      <tr class="total-row">
        <td></td>
        <td>योग</td>
        <td></td>
        <td></td>
        <td>${totalZonal}</td>
        <td>${totalSector}</td>
        <td>${totalNyay}</td>
        <td>${totalGram}</td>
      </tr>
    </tbody>
  </table>
  <script>
    document.fonts.ready.then(() => { window.print(); window.close(); });
  <\/script>
</body>
</html>`);
    win.document.close();
}

// ── Main component ────────────────────────────────────────────────────────────
export default function GoswaraPage() {
    const navigate = useNavigate();
    const { user, role } = useAuthStore();

    const [data, setData] = useState([]);
    const [electionDate, setElectionDate] = useState("");
    const [phase, setPhase] = useState("");
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    const isSuperAdmin = role === "SUPER_ADMIN";
    const userDistrict = user?.district ?? "";

    const [editingNyay, setEditingNyay] = useState({});
    const [savingRow, setSavingRow] = useState(null);

    const fetchData = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const res = await apiClient.get("/admin/goswara");
            setData(res.data ?? res ?? []);
            setElectionDate(res.electionDate ?? "");
            setPhase(res.phase ?? "");
        } catch (e) {
            setError(e.message);
        } finally {
            setLoading(false);
        }
    }, []);

    const saveNyay = async (blockName) => {
        const nyayCount = editingNyay[blockName];

        if (nyayCount === undefined) return;

        try {
            setSavingRow(blockName);

            await apiClient.post("/admin/goswara/nyay-panchayat", {
                blockName,
                nyayCount: Number(nyayCount),
            });

            // update UI instantly
            setData((prev) =>
                prev.map((r) =>
                    r.block_name === blockName
                        ? { ...r, nyay_panchayat_count: Number(nyayCount) }
                        : r
                )
            );
        } catch (e) {
            console.error(e);
        } finally {
            setSavingRow(null);
        }
    };

    useEffect(() => { fetchData(); }, [fetchData]);

    const totalZonal = sum(data, "zonal_count");
    const totalSector = sum(data, "sector_count");
    const totalNyay = sum(data, "nyay_panchayat_count");
    const totalGram = sum(data, "gram_panchayat_count");

    // ── header cols ───────────────────────────────────────────────────────────
    const headers = [
        { label: "क्र०सं०", w: "w-[42px]" },
        { label: "विकास खण्ड", w: "w-[130px]" },
        { label: "चरण", w: "w-[80px]" },
        { label: "मतदान की\nतिथि", w: "w-[110px]" },
        { label: "जोनल मजिस्ट्रेट /\nपुलिस अधिकारी", w: "w-[130px]" },
        { label: "सेक्टर\nमजिस्ट्रेट", w: "w-[100px]" },
        { label: "न्याय\nपंचायत", w: "w-[100px]" },
        { label: "ग्राम\nपंचायत", w: "w-[100px]" },
    ];

    return (
        <div className="min-h-screen bg-white flex flex-col">

            {/* ── AppBar ─────────────────────────────────────────────────────────── */}
            <div className="bg-white border-b border-gray-200 shadow-sm flex items-center gap-2 px-3 py-3">
                <button
                    onClick={() => navigate(-1)}
                    className="p-1.5 rounded-lg hover:bg-gray-100 transition-colors"
                >
                    <ArrowLeft size={18} className="text-gray-700" />
                </button>

                <h1 className="flex-1 text-[17px] font-bold text-gray-800">गोसवारा</h1>

                <button
                    onClick={fetchData}
                    className="p-1.5 rounded-lg hover:bg-gray-100 transition-colors"
                    title="ताज़ा करें"
                >
                    <RefreshCw size={17} className="text-gray-600" />
                </button>

                <button
                    onClick={() =>
                        printGoswara({ data, electionDate, phase, isSuperAdmin, userDistrict })
                    }
                    className="p-1.5 rounded-lg hover:bg-gray-100 transition-colors"
                    title="Print / Save PDF"
                >
                    <Printer size={17} className="text-gray-600" />
                </button>
            </div>

            {/* ── Body ──────────────────────────────────────────────────────────── */}
            <div className="flex-1 overflow-auto">
                {loading ? (
                    <div className="flex items-center justify-center h-64">
                        <Loader2 size={36} className="animate-spin text-gray-400" />
                    </div>
                ) : error ? (
                    <div className="flex flex-col items-center justify-center h-64 gap-3 px-8 text-center">
                        <AlertCircle size={44} className="text-red-500" />
                        <p className="font-bold text-gray-800">डेटा लोड करने में त्रुटि</p>
                        <p className="text-xs text-gray-500">{error}</p>
                        <button
                            onClick={fetchData}
                            className="flex items-center gap-2 px-4 py-2 rounded-lg bg-gray-800 text-white text-sm font-semibold"
                        >
                            <RefreshCw size={14} /> पुनः प्रयास
                        </button>
                    </div>
                ) : (
                    <div className="py-4 px-2 flex flex-col items-stretch">

                        {/* ── Page title ──────────────────────────────────────────────── */}
                        <h2 className="text-center text-[22px] font-bold text-gray-800 mb-1">
                            गोसवारा
                        </h2>
                        <p className="text-center text-[13px] text-gray-500 mb-3">
                            -:: विकास खण्डवार जोनल एवं सेक्टर, न्याय पंचायत एवं ग्राम पंचायतों का विवरण ::-
                        </p>

                        {/* ── District badge (super_admin only) ───────────────────────── */}
                        {isSuperAdmin && userDistrict && (
                            <div className="flex justify-center mb-4">
                                <div className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-blue-50 border border-blue-200">
                                    <MapPin size={13} className="text-blue-700" />
                                    <span className="text-[12px] font-semibold text-blue-700">
                                        जनपद: {userDistrict}
                                    </span>
                                </div>
                            </div>
                        )}

                        {/* ── Table ───────────────────────────────────────────────────── */}
                        <div className="overflow-x-auto mx-auto">
                            <table
                                className="border-collapse text-[13px] text-gray-800"
                                style={{ borderColor: "#888", minWidth: 772 }}
                            >
                                {/* colgroup for fixed widths */}
                                <colgroup>
                                    {headers.map((h, i) => (
                                        <col key={i} style={{ width: parseInt(h.w.replace("w-[", "").replace("px]", "")) }} />
                                    ))}
                                </colgroup>

                                <thead>
                                    <tr className="bg-gray-200">
                                        {headers.map((h, i) => (
                                            <th
                                                key={i}
                                                className="border border-gray-500 px-1.5 py-[7px] font-bold text-center leading-snug whitespace-pre-line"
                                                style={{ fontSize: 12 }}
                                            >
                                                {h.label}
                                            </th>
                                        ))}
                                    </tr>
                                </thead>

                                <tbody>
                                    {data.map((r, i) => (
                                        <tr key={i} className="hover:bg-gray-50 transition-colors">
                                            <td className="border border-gray-400 px-1.5 py-[7px] text-center">{i + 1}</td>
                                            <td className="border border-gray-400 px-1.5 py-[7px]">{r.block_name ?? ""}</td>
                                            <td className="border border-gray-400 px-1.5 py-[7px] text-center">{i === 0 ? phase : ""}</td>
                                            <td className="border border-gray-400 px-1.5 py-[7px] text-center">{i === 0 ? electionDate : ""}</td>
                                            <td className="border border-gray-400 px-1.5 py-[7px] text-center">{r.zonal_count ?? 0}</td>
                                            <td className="border border-gray-400 px-1.5 py-[7px] text-center">{r.sector_count ?? 0}</td>
                                            <td className="border border-gray-400 px-1.5 py-[5px] text-center">
                                                <div className="flex items-center justify-center gap-1">

                                                    <input
                                                        type="number"
                                                        value={
                                                            editingNyay[r.block_name] ??
                                                            r.nyay_panchayat_count ??
                                                            0
                                                        }
                                                        onChange={(e) =>
                                                            setEditingNyay((prev) => ({
                                                                ...prev,
                                                                [r.block_name]: e.target.value,
                                                            }))
                                                        }
                                                        className="w-[60px] text-center border border-gray-300 rounded px-1 py-[2px] text-[12px]"
                                                    />

                                                    <button
                                                        onClick={() => saveNyay(r.block_name)}
                                                        className="p-1 rounded hover:bg-gray-100"
                                                        title="Save"
                                                    >
                                                        {savingRow === r.block_name ? (
                                                            <Loader2 size={14} className="animate-spin text-gray-500" />
                                                        ) : (
                                                            <Save size={14} className="text-green-600" />
                                                        )}
                                                    </button>

                                                </div>
                                            </td>
                                            <td className="border border-gray-400 px-1.5 py-[7px] text-center">{r.gram_panchayat_count ?? 0}</td>
                                        </tr>
                                    ))}

                                    {/* Total row */}
                                    <tr className="bg-gray-200 font-bold">
                                        <td className="border border-gray-500 px-1.5 py-[7px] text-center"></td>
                                        <td className="border border-gray-500 px-1.5 py-[7px] text-center">योग</td>
                                        <td className="border border-gray-500 px-1.5 py-[7px] text-center"></td>
                                        <td className="border border-gray-500 px-1.5 py-[7px] text-center"></td>
                                        <td className="border border-gray-500 px-1.5 py-[7px] text-center">{totalZonal}</td>
                                        <td className="border border-gray-500 px-1.5 py-[7px] text-center">{totalSector}</td>
                                        <td className="border border-gray-500 px-1.5 py-[7px] text-center">{totalNyay}</td>
                                        <td className="border border-gray-500 px-1.5 py-[7px] text-center">{totalGram}</td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>

                        <div className="h-6" />
                    </div>
                )}
            </div>
        </div>
    );
}