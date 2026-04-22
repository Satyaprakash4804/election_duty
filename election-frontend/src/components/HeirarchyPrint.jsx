// ── printHierarchy — mirrors Flutter PDF output exactly ───────────────────
// Usage: replace window.print() button with:
//   onClick={() => printHierarchy(tab, filteredSZ, fZone, fSect, fGP)}

export function printHierarchy(tab, filteredSZ, fZone, fSect, fGP) {
    const win = window.open("", "_blank");
    if (!win) return;

    // ── shared style ────────────────────────────────────────────────────────
    const BASE_STYLE = `
    @page { size: A4 landscape; margin: 14mm; }
    * { box-sizing: border-box; font-family: 'Noto Sans Devanagari', Arial, sans-serif; }
    body { margin: 0; padding: 0; font-size: 8pt; color: #1A2332; }
    h2 { font-size: 11pt; font-weight: 700; margin: 0 0 4px; }
    p { margin: 0; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 14pt; }
    th, td { border: 0.5pt solid #DDE3EE; padding: 3pt 4pt; vertical-align: top; font-size: 7pt; }
    th { font-weight: 700; text-align: center; white-space: pre-line; line-height: 1.3; }
    .sz-block { margin-bottom: 20pt; page-break-inside: avoid; }
    .zone-block { page-break-before: always; }
    .zone-block:first-child { page-break-before: avoid; }
    .gp-block { page-break-before: always; }
    .gp-block:first-child { page-break-before: avoid; }
    .meta { font-size: 9pt; margin-bottom: 4pt; }
    .officer-line { font-size: 8pt; color: #1A2332; margin: 2pt 0; }
    .center { text-align: center; }
    .muted { color: #6B7C93; font-size: 7pt; }
    @media print { body { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
  `;

    // ── helpers ─────────────────────────────────────────────────────────────
    const esc = (s) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const dash = (s) => s || "—";
    const offStr = (officers, multiLine = true) =>
        officers.length === 0 ? "—"
            : officers.map(o => `${o.name ?? ""} ${o.user_rank ?? ""}${o.mobile ? " " + o.mobile : ""}`).join(multiLine ? "\n" : ", ");

    // ════════════════════════════════════════════════════════════════════════
    // TAB 0 — Super Zone  (all SZs on one page)
    // ════════════════════════════════════════════════════════════════════════
    function buildTab0() {
        let html = "";
        for (const sz of filteredSZ) {
            const zones = sz.zones ?? [];
            let gpTotal = 0;
            zones.forEach(z => (z.sectors ?? []).forEach(s => { gpTotal += (s.panchayats ?? []).length; }));

            const rows = [];
            let globalSector = 0;
            zones.forEach((z, zi) => {
                const sectors = z.sectors ?? [];
                const zOff = z.officers ?? [];
                const zOffStr = zOff.map(o => `${o.name ?? ""}\n${o.user_rank ?? ""}`).join("\n") || "—";
                const hq = dash(z.hq_address ?? z.hqAddress);
                if (sectors.length === 0) {
                    rows.push({ zNo: zi + 1, zOff: zOffStr, hq, sNo: "", sOff: "—", sHq: hq, gps: "—", thanas: "—" });
                } else {
                    sectors.forEach(s => {
                        globalSector++;
                        const gps = s.panchayats ?? [];
                        const sOff = (s.officers ?? []).map(o => `${o.name ?? ""}\n${o.user_rank ?? ""}\n${o.mobile ?? ""}`).join("\n") || "—";
                        rows.push({
                            zNo: zi + 1, zOff: zOffStr, hq,
                            sNo: globalSector, sOff, sHq: dash(s.hq ?? z.hq_address),
                            gps: dash(gps.map(g => g.name).join("، ")),
                            thanas: dash([...new Set(gps.map(g => g.thana).filter(Boolean))].join("، ")),
                        });
                    });
                }
            });

            html += `<div class="sz-block">
        <h2>सुपर जोन–${esc(sz.name)}  ब्लाक ${esc(sz.block ?? "")}  |  कुल ग्राम पंचायत–${gpTotal}</h2>
        <table>
          <thead><tr>
            <th style="width:36pt">सुपर\nजोन</th>
            <th style="width:36pt">जोन</th>
            <th style="width:14%">जोनल अधिकारी /\nजोनल पुलिस अधिकारी</th>
            <th style="width:11%">मुख्यालय</th>
            <th style="width:28pt">सैक्टर\nसं.</th>
            <th style="width:18%">सैक्टर पुलिस अधिकारी\nका नाम</th>
            <th style="width:11%">मुख्यालय</th>
            <th style="width:22%">सैक्टर में लगने वाले\nग्राम पंचायत का नाम</th>
            <th style="width:10%">थाना</th>
          </tr></thead>
          <tbody>`;
            let prevZone = null;
            rows.forEach((r, i) => {
                const firstInZone = r.zNo !== prevZone;
                prevZone = r.zNo;
                const bg = i % 2 === 0 ? "#FFFDF7" : "#fff";
                html += `<tr style="background:${bg}">
          <td class="center" style="white-space:pre-line;font-size:6pt;color:#0F2B5B;font-weight:700">${i === 0 ? `सुपर जोन–${esc(sz.name)}` : ""}</td>
          <td class="center" style="font-size:13pt;font-weight:900;color:#0F2B5B">${firstInZone ? r.zNo : ""}</td>
          <td style="white-space:pre-line">${firstInZone ? esc(r.zOff) : ""}</td>
          <td>${firstInZone ? esc(r.hq) : ""}</td>
          <td class="center" style="font-weight:800;color:#186A3B">${r.sNo || ""}</td>
          <td style="white-space:pre-line">${esc(r.sOff)}</td>
          <td>${esc(r.sHq)}</td>
          <td>${esc(r.gps)}</td>
          <td>${esc(r.thanas)}</td>
        </tr>`;
            });
            html += `</tbody></table></div>`;
        }
        return html;
    }

    // ════════════════════════════════════════════════════════════════════════
    // TAB 1 — Zone / Sector  (one page per zone)
    // ════════════════════════════════════════════════════════════════════════
    function buildTab1() {
        let html = "";
        let first = true;
        for (const sz of filteredSZ) {
            for (const z of (sz.zones ?? [])) {
                if (fZone && `${z.id}` !== fZone) continue;
                const zOff = (z.officers ?? []).map(o =>
                    `${o.name ?? ""} (${o.user_rank ?? ""}) मो: ${o.mobile ?? ""}`).join("\n");
                const szOff = (sz.officers ?? []).map(o =>
                    `${o.name ?? ""} (${o.user_rank ?? ""}) मो: ${o.mobile ?? ""}`).join("\n");

                const rows = [];
                let sSeq = 0;
                for (const s of (z.sectors ?? [])) {
                    sSeq++;
                    const sOff = s.officers ?? [];
                    const magStr = sOff.length > 0
                        ? `${sOff[0].name ?? ""}\n${sOff[0].user_rank ?? ""}\n${sOff[0].mobile ?? ""}`
                        : "—";
                    const polStr = sOff.length > 1
                        ? `${sOff[1].name ?? ""}\n${sOff[1].user_rank ?? ""}\n${sOff[1].mobile ?? ""}`
                        : magStr;
                    const gps = s.panchayats ?? [];
                    if (gps.length === 0) {
                        rows.push({ sSeq, mag: magStr, pol: polStr, gp: null, first: true });
                    } else {
                        gps.forEach((gp, gi) => rows.push({
                            sSeq, mag: gi === 0 ? magStr : "", pol: gi === 0 ? polStr : "",
                            gp, first: gi === 0,
                        }));
                    }
                }

                html += `<div class="${first ? "zone-block" : "zone-block"}" style="${first ? "" : "page-break-before:always"}">
          <h2>जोन: ${esc(z.name)}  |  सुपर जोन: ${esc(sz.name)}  |  ब्लॉक: ${esc(sz.block ?? "—")}</h2>
          ${zOff ? `<p class="officer-line">जोनल अधिकारी: ${esc(zOff)}</p>` : ""}
          ${szOff ? `<p class="officer-line">सुपर जोन अधिकारी: ${esc(szOff)}</p>` : ""}
          <table style="margin-top:6pt">
            <thead><tr>
              <th style="width:30pt">सैक्टर\nसं.</th>
              <th style="width:22%">सैक्टर मजिस्ट्रेट\n(नाम/पद/मोबाइल)</th>
              <th style="width:22%">सैक्टर पुलिस अधिकारी\n(नाम/पद/मोबाइल)</th>
              <th style="width:14%">ग्राम पंचायत</th>
              <th style="width:22%">मतदेय स्थल</th>
              <th style="width:12%">मतदान केन्द्र</th>
            </tr></thead>
            <tbody>`;
                rows.forEach((r, i) => {
                    const gp = r.gp;
                    const centers = gp?.centers ?? [];
                    const sthal = centers.map(c => c.name).join("\n") || "—";
                    const kendras = centers.flatMap(c => (c.kendras ?? []).map(k => k.room_number)).join(", ") || "—";
                    const bg = i % 2 === 0 ? "#fff" : "#F1F8E9";
                    html += `<tr style="background:${bg}">
            <td class="center" style="font-size:12pt;font-weight:900;color:#186A3B">${r.first ? r.sSeq : ""}</td>
            <td style="white-space:pre-line">${r.first ? esc(r.mag) : ""}</td>
            <td style="white-space:pre-line">${r.first ? esc(r.pol) : ""}</td>
            <td>${esc(gp?.name ?? "—")}</td>
            <td style="white-space:pre-line">${esc(sthal)}</td>
            <td>${esc(kendras)}</td>
          </tr>`;
                });
                html += `</tbody></table></div>`;
                first = false;
            }
        }
        return html;
    }

    // ════════════════════════════════════════════════════════════════════════
    // TAB 2 — Booth Duty  (one page per GP)
    // ════════════════════════════════════════════════════════════════════════
    function buildTab2() {
        let html = "";
        let first = true;
        for (const sz of filteredSZ) {
            for (const z of (sz.zones ?? [])) {
                if (fZone && `${z.id}` !== fZone) continue;
                for (const s of (z.sectors ?? [])) {
                    if (fSect && `${s.id}` !== fSect) continue;
                    for (const gp of (s.panchayats ?? [])) {
                        if (fGP && `${gp.id}` !== fGP) continue;
                        const centers = gp.centers ?? [];
                        let totalKendra = 0;
                        centers.forEach(c => { const k = c.kendras ?? []; totalKendra += k.length === 0 ? 1 : k.length; });

                        const rows = [];
                        let sthalNo = 1, kendraG = 1;
                        centers.forEach(c => {
                            const kendras = c.kendras ?? [];
                            const duty = c.duty_officers ?? [];
                            const dutyText = duty.map(d => `${d.name ?? ""} ${d.pno ?? ""}\n${d.user_rank ?? ""}`).join("\n") || "—";
                            const mobileText = duty.map(d => d.mobile ?? "").filter(Boolean).join("\n") || "—";
                            if (kendras.length === 0) {
                                rows.push({ c, k: null, kNo: kendraG, sNo: sthalNo, first: true, dutyText, mobileText });
                                sthalNo++; kendraG++;
                            } else {
                                kendras.forEach((k, ki) => {
                                    rows.push({
                                        c, k, kNo: kendraG, sNo: ki === 0 ? sthalNo : null, first: ki === 0,
                                        dutyText: ki === 0 ? dutyText : "", mobileText: ki === 0 ? mobileText : ""
                                    });
                                    kendraG++;
                                });
                                sthalNo++;
                            }
                        });

                        html += `<div style="${first ? "" : "page-break-before:always"}">
              <div style="display:flex;justify-content:space-between;align-items:baseline;margin-bottom:2pt">
                <h2>बूथ ड्यूटी – ब्लॉक ${esc(sz.block ?? sz.name)}  <span style="font-size:9pt;font-weight:400">मतदान दिनांकः ....../......./2026</span></h2>
                <span style="font-size:9pt;font-weight:700">मतदान केन्द्र–${totalKendra}  मतदेय स्थल–${centers.length}</span>
              </div>
              <p class="meta">ग्राम पंचायत: ${esc(gp.name)}  |  सैक्टर: ${esc(s.name)}  |  जोन: ${esc(z.name)}</p>
              <table style="margin-top:6pt">
                <thead><tr>
                  <th style="width:28pt">मतदान\nकेन्द्र की\nसंख्या</th>
                  <th style="width:18%">मतदान केन्द्र\nका नाम</th>
                  <th style="width:26pt">मतदेय\nसं.</th>
                  <th style="width:16%">मतदान स्थल\nका नाम</th>
                  <th style="width:32pt">जोन\nसंख्या</th>
                  <th style="width:36pt">सैक्टर\nसंख्या</th>
                  <th style="width:10%">थाना</th>
                  <th style="width:20%">ड्यूटी पर लगाया\nपुलिस का नाम</th>
                  <th style="width:10%">मोबाईल\nनम्बर</th>
                  <th style="width:32pt">बस\nनं.</th>
                </tr></thead>
                <tbody>`;
                        rows.forEach((r, i) => {
                            const c = r.c; const k = r.k;
                            const kLabel = k ? `${c.name} क.नं. ${k.room_number}` : c.name;
                            const bg = i % 2 === 0 ? "#fff" : "#FDF4FF";
                            html += `<tr style="background:${bg}">
                <td class="center" style="font-size:11pt;font-weight:800;color:#6C3483">${r.kNo}</td>
                <td>
                  ${esc(kLabel)}<br>
                  <span style="display:inline-block;margin-top:2pt;padding:1pt 4pt;border-radius:3pt;
                    background:${bgForType(c.center_type)};color:${colorForType(c.center_type)};
                    font-weight:800;font-size:6.5pt">${esc(c.center_type ?? "C")}</span>
                </td>
                <td class="center" style="font-weight:700">${r.first && r.sNo ? r.sNo : ""}</td>
                <td>${r.first ? esc(c.name) : ""}</td>
                <td class="center">${esc(z.name)}</td>
                <td class="center">${esc(s.name)}</td>
                <td>${esc(c.thana ?? gp.thana ?? "—")}</td>
                <td style="white-space:pre-line">${esc(r.dutyText)}</td>
                <td style="white-space:pre-line;font-family:monospace">${esc(r.mobileText)}</td>
                <td class="center" style="font-weight:700">${esc(c.bus_no ?? "—")}</td>
              </tr>`;
                        });
                        html += `</tbody></table></div>`;
                        first = false;
                    }
                }
            }
        }
        return html;
    }

    // ── sensitivity color helpers ──────────────────────────────────────────
    function colorForType(t) {
        return { "A++": "#6C3483", "A": "#C0392B", "B": "#E67E22", "C": "#1A5276" }[t] ?? "#1A5276";
    }
    function bgForType(t) {
        const c = colorForType(t);
        return c + "22";
    }

    // ── assemble ───────────────────────────────────────────────────────────
    let body = "";
    if (tab === 0) body = buildTab0();
    else if (tab === 1) body = buildTab1();
    else body = buildTab2();

    win.document.write(`<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>प्रशासनिक पदानुक्रम</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700;900&display=swap" rel="stylesheet">
  <style>${BASE_STYLE}</style>
</head>
<body>
${body}
<script>
  document.fonts.ready.then(() => { window.print(); window.close(); });
<\/script>
</body>
</html>`);
    win.document.close();
}