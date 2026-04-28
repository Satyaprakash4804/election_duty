/**
 * DutyCardPrint.js - exact format match of admin printDutyCards
 *
 * USAGE:
 *   import { printDutyCard, toAdminShape } from './DutyCardPrint';
 *
 *   const handlePrint = async () => {
 *     setPrinting(true);
 *     try {
 *       await printDutyCard(toAdminShape(duty, user));
 *       await apiClient.post('/staff/mark-card-downloaded', {});
 *       setHasMarked(true);
 *     } catch (e) { alert('print error: ' + e.message); }
 *     finally { setPrinting(false); }
 *   };
 */

export function toAdminShape(duty, user) {
  duty = duty || {};
  user = user || {};
  const sahyogi = duty.allStaff || duty.sahyogi || [];
  return {
    name: user.name || '', pno: user.pno || '', mobile: user.mobile || '',
    rank: user.rank || user.user_rank || '', user_rank: user.rank || user.user_rank || '',
    isArmed: user.isArmed || false, staffThana: user.thana || '', thana: user.thana || '',
    district: user.district || '', adminDistrict: user.district || '',
    centerName: duty.centerName || '', centerType: duty.centerType || '',
    gpName: duty.gpName || duty.gramPanchayat || '',
    sectorName: duty.sectorName || duty.sector || '',
    zoneName: duty.zoneName || duty.zone || '',
    superZoneName: duty.superZoneName || duty.superZone || '',
    busNo: duty.busNo || duty.bus_no || '', bus_no: duty.busNo || duty.bus_no || '',
    zoneHq: duty.zoneHq || '', centerId: duty.centerId || duty.sthal_id || '',
    boothNo: duty.boothNo || '',
    zonalOfficers: duty.zonalOfficers || [], sectorOfficers: duty.sectorOfficers || [],
    superOfficers: duty.superOfficers || [], sahyogi, allStaff: sahyogi,
  };
}

export function printDutyCard(staffShape) {
  return printDutyCards([staffShape]);
}

export function printDutyCards(list) {
  if (!list.length) return Promise.resolve();
  return new Promise((resolve) => {
    const vd = (v) => (v === null || v === undefined || v === '') ? '\u2014' : String(v);
    const rh = (v) => vd(v);
    const isArmedFn = (e) => e.isArmed === true || e.is_armed === true || e.is_armed === 1;

    const officerBlock = (title, name, mobile, rank) => `
      <div style="border-bottom:0.4px solid #ccc">
        <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5px;border-bottom:0.4px solid #ccc">${title}</div>
        <div style="padding:2px;text-align:center;font-size:4.5px;line-height:1.4">${[rank, name, mobile].filter(Boolean).join('<br>')}</div>
      </div>`;

    const cardsHTML = list.map((s) => {
      const sahyogi        = s.sahyogi || s.allStaff || s.all_staff || [];
      const totalRows      = Math.max(12, sahyogi.length);
      const zonalOfficers  = s.zonalOfficers  || s.zonal_officers  || [];
      const sectorOfficers = s.sectorOfficers || s.sector_officers || [];
      const superOfficers  = s.superOfficers  || s.super_officers  || [];
      const zonalMag       = zonalOfficers[0]  || null;
      const sectorMag      = sectorOfficers[0] || null;
      const zonalPolice    = superOfficers[0]  || null;
      const sectorPolice   = sectorOfficers[1] || sectorOfficers[0] || null;
      const busNo          = s.busNo || s.bus_no || '';
      const busLabel       = busNo ? '\u092c\u0938\u2013' + busNo : '\u2014';
      const armed          = isArmedFn(s) ? '\u0938\u0936\u0938\u094d\u0924\u094d\u0930' : '\u0928\u093f\u0903\u0936\u0938\u094d\u0924\u094d\u0930';

      const staffRows = Array.from({ length: totalRows }).map((_, i) => {
        const e = sahyogi[i] || null;
        const bg = i % 2 === 0 ? '#fff' : '#f5f5f5';
        const tdBase = 'font-size:4.8px;padding:0.5px 1px;border-bottom:0.3px solid #eee;border-right:0.3px solid #ddd;overflow:hidden;white-space:nowrap;text-overflow:ellipsis';
        return `<tr style="background:${bg}">
          <td style="${tdBase}">${e ? rh(e.user_rank || e.rank) : ''}</td>
          <td style="${tdBase}">${e ? vd(e.pno) : ''}</td>
          <td style="${tdBase};font-weight:${e ? '700' : '400'}">${e ? vd(e.name) : ''}</td>
          <td style="${tdBase}">${e ? vd(e.mobile) : ''}</td>
          <td style="${tdBase}">${e ? vd(e.thana) : ''}</td>
          <td style="${tdBase}">${e ? vd(e.district) : ''}</td>
          <td style="font-size:4.8px;padding:0.5px 1px;border-bottom:0.3px solid #eee;text-align:center;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">${e ? (isArmedFn(e) ? '\u0938\u0936\u0938\u094d\u0924\u094d\u0930' : '\u0928\u093f\u0903\u0936\u0938\u094d\u0924\u094d\u0930') : ''}</td>
        </tr>`;
      }).join('');

      const metaRows = [
        ['\u092e0 \u0915\u0947\u0902\u0926\u094d\u0930 \u0938\u09020', vd(s.centerId  || s.center_id)],
        ['\u092c\u0942\u0925 \u0938\u09020',       vd(s.boothNo   || s.booth_no)],
        ['\u0925\u093e\u0928\u093e',               vd(s.staffThana || s.thana)],
        ['\u091c\u094b\u0928 \u0928\u00b00',       vd(s.zoneName   || s.zone_name)],
        ['\u0938\u0947\u0915\u094d\u0924\u0930 \u0928\u00b00', vd(s.sectorName || s.sector_name)],
        ['\u0935\u093f0\u0938\u09300',             '\u2014'],
        ['\u0936\u094d\u0930\u0947\u0923\u0940',   vd(s.centerType || s.center_type)],
      ].map(([k, v]) => `
        <div style="display:flex;border-bottom:0.3px solid #ddd">
          <span style="background:#eee;flex:2;padding:1px;font-weight:700;border-right:0.3px solid #ccc;font-size:4.5px;line-height:1.2">${k}</span>
          <span style="flex:3;padding:1px;font-size:4.5px;line-height:1.2">${v}</span>
        </div>`).join('');

      return `<div class="card">

        <!-- HEADER -->
        <div style="display:flex;border-bottom:0.8px solid #333;flex-shrink:0">
          <div style="width:42px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:8px;padding:3px;text-align:center;border-right:0.5px solid #333">ECI</div>
          <div style="flex:1;padding:2px 4px;text-align:center">
            <div style="font-size:11px;font-weight:700;text-decoration:underline;line-height:1.2">\u0921\u094d\u092f\u0942\u091f\u0940 \u0915\u093e\u0930\u094d\u0921</div>
            <div style="font-size:7px;font-weight:700;line-height:1.2">\u0932\u094b\u0915\u0938\u092d\u093e \u0938\u093e\u092e\u093e\u0928\u094d\u092f \u0928\u093f\u0930\u094d\u0935\u093e\u091a\u0928\u20132024</div>
            <div style="font-size:6.5px;line-height:1.2">\u091c\u0928\u092a\u0926 ${vd(s.adminDistrict || s.district || '')}</div>
            <div style="font-size:5.5px;font-weight:700;border-top:0.5px solid #999;margin-top:1px;padding-top:1px;line-height:1.2">\u092e\u0924\u0926\u093e\u0928 \u091a\u0930\u0923\u2013\u0926\u094d\u0935\u093f\u0924\u0940\u092f &nbsp; \u0926\u093f\u0928\u093e\u0902\u0915 26.04.2024 &nbsp; \u092a\u094d\u0930\u093e\u0924\u0903 07:00 \u0938\u0947 \u0938\u093e\u0902\u092f 06:00 \u0924\u0915</div>
          </div>
          <div style="width:42px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:7px;padding:3px;text-align:center;border-left:0.5px solid #333;line-height:1.3">\u09090\u092a\u094d\u09300<br>\u092a\u0941\u0932\u093f\u0938</div>
        </div>

        <!-- PRIMARY TABLE -->
        <table style="width:100%;border-collapse:collapse;border:0.5px solid #999;flex-shrink:0;table-layout:fixed">
          <colgroup>
            <col style="width:14%"><col style="width:8%"><col style="width:10%">
            <col style="width:18%"><col style="width:11%"><col style="width:11%">
            <col style="width:10%"><col style="width:8%"><col style="width:10%">
          </colgroup>
          <thead>
            <tr>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">\u0928\u093e\u092e \u0905\u0927\u093f0/<br>\u0915\u0930\u094d\u092e0 \u0917\u0923</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">\u092a\u0926</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">\u092c\u0948\u091c \u0928\u0902\u092c\u0930</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">\u0928\u093e\u092e \u0905\u0927\u093f0/\u0915\u0930\u094d\u092e0</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">\u092e\u094b\u092c\u093e\u0907\u0932 \u0928\u00b00</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">\u0924\u0948\u0928\u093e\u0924\u0940</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">\u091c\u0928\u092a\u0926</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">\u09380/<br>\u0928\u093f0</th>
              <th style="background:#ddd;font-weight:700;font-size:5.5px;text-align:center;padding:1px 2px;border:0.5px solid #999;line-height:1.2">\u0935\u093e\u0939\u0928<br>\u0938\u0902\u0916\u094d\u092f\u093e</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px"></td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;font-weight:700;text-align:center">${rh(s.rank || s.user_rank)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center">${vd(s.pno)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;font-weight:700">${vd(s.name)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center">${vd(s.mobile)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center">${vd(s.staffThana || s.thana)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center">${vd(s.district)}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:4.5px;text-align:center">${armed}</td>
              <td style="border:0.5px solid #999;padding:1px 2px;font-size:5.5px;text-align:center;font-weight:700">${busLabel}</td>
            </tr>
          </tbody>
        </table>

        <!-- MIDDLE -->
        <div style="display:flex;flex:1;border-top:0.5px solid #999;overflow:hidden;min-height:0">

          <!-- Duty location -->
          <div style="width:50px;border-right:0.5px solid #999;display:flex;flex-direction:column;flex-shrink:0">
            <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5.5px;border-bottom:0.5px solid #999;line-height:1.2;flex-shrink:0">\u0921\u093f\u092f\u0942\u091f\u0940 \u0938\u094d\u0925\u093e\u0928</div>
            <div style="flex:1;padding:2px;text-align:center;font-weight:700;font-size:5.5px;display:flex;align-items:center;justify-content:center;line-height:1.3">${vd(s.centerName || s.center_name)}</div>
            <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5.5px;border-bottom:0.5px solid #999;border-top:0.5px solid #999;line-height:1.2;flex-shrink:0">\u0921\u093f\u092f\u0942\u091f\u0940 \u092a\u094d\u0930\u0915\u093e\u0930</div>
            <div style="flex:1;padding:2px;text-align:center;font-weight:700;font-size:5.5px;display:flex;align-items:center;justify-content:center;line-height:1.3">\u092c\u0942\u0925 \u0921\u093f\u092f\u0942\u091f\u0940</div>
          </div>

          <!-- Sahyogi table -->
          <div style="flex:1;overflow:hidden;display:flex;flex-direction:column">
            <table style="width:100%;border-collapse:collapse;table-layout:fixed">
              <colgroup>
                <col style="width:9%"><col style="width:14%"><col style="width:23%">
                <col style="width:16%"><col style="width:16%"><col style="width:14%"><col style="width:8%">
              </colgroup>
              <thead>
                <tr>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">\u092a\u0926</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">\u092c\u0948\u091c \u0928\u0902\u092c\u0930</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">\u0928\u093e\u092e</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">\u092e\u094b\u092c\u093e\u0907\u0932 \u0928\u00b00</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">\u0924\u0948\u0928\u093e\u0924\u0940</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-right:0.3px solid #bbb;border-bottom:0.5px solid #999;line-height:1.2">\u091c\u0928\u092a\u0926</th>
                  <th style="background:#ddd;font-size:4.8px;font-weight:700;text-align:center;padding:1px;border-bottom:0.5px solid #999;line-height:1.2">\u09380/\u0928\u093f0</th>
                </tr>
              </thead>
              <tbody>${staffRows}</tbody>
            </table>
          </div>

          <!-- Bus panel -->
          <div style="width:28px;border-left:0.5px solid #999;display:flex;flex-direction:column;flex-shrink:0;font-size:5px">
            <div style="background:#ddd;padding:1px;text-align:center;font-weight:700;font-size:5px;border-bottom:0.5px solid #999;line-height:1.2">${busLabel}</div>
            <div style="padding:2px;text-align:center;font-size:4.8px;line-height:1.3">\u0926\u093f\u0928\u093e\u0902\u0915<br><strong>15.2.17</strong></div>
            <div style="padding:2px;text-align:center;font-size:4.8px;line-height:1.3;border-top:0.5px solid #bbb">\u0938\u0940\u092a\u0940\u090f\u092e \u090f\u092b</div>
            <div style="padding:2px;text-align:center;font-size:4.8px;line-height:1.3;border-top:0.5px solid #bbb">1/2 \u0938\u09480</div>
          </div>

        </div>

        <!-- FOOTER -->
        <div style="display:flex;border-top:0.8px solid #333;flex-shrink:0">

          <!-- Meta -->
          <div style="width:50px;border-right:0.5px solid #999;flex-shrink:0">${metaRows}</div>

          <!-- Zonal officers -->
          <div style="flex:1;border-right:0.5px solid #999">
            ${officerBlock('\u091c\u094b\u0928\u0932 \u092e\u091c\u093f\u0938\u094d\u0920\u094d\u0930\u0947\u091f',    zonalMag    ? zonalMag.name    : null, zonalMag    ? zonalMag.mobile    : null, null)}
            ${officerBlock('\u091c\u094b\u0928\u0932 \u092a\u0941\u0932\u093f\u0938 \u0905\u0927\u093f\u0915\u093e\u0930\u0940', zonalPolice ? zonalPolice.name : null, zonalPolice ? zonalPolice.mobile : null, zonalPolice ? rh(zonalPolice.user_rank) : null)}
          </div>

          <!-- Sector officers -->
          <div style="flex:1;border-right:0.5px solid #999">
            ${officerBlock('\u0938\u0948\u0915\u094d\u0924\u0930 \u092e\u091c\u093f\u0938\u094d\u0920\u094d\u0930\u0947\u091f',    sectorMag    ? sectorMag.name    : null, sectorMag    ? sectorMag.mobile    : null, null)}
            ${officerBlock('\u0938\u0947\u0915\u094d\u0924\u0930 \u092a\u0941\u0932\u093f\u0938 \u0905\u0927\u093f\u0915\u093e\u0930\u0940', sectorPolice ? sectorPolice.name : null, sectorPolice ? sectorPolice.mobile : null, sectorPolice ? rh(sectorPolice.user_rank) : null)}
          </div>

          <!-- SP signature -->
          <div style="width:38px;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:3px;flex-shrink:0">
            <div style="height:18px;width:30px;border-bottom:0.5px solid #333"></div>
            <div style="font-size:5.5px;font-weight:700;text-align:center;margin-top:2px;line-height:1.3">\u092a\u0941\u0932\u093f\u0938 \u0905\u0927\u0940\u0915\u094d\u0937\u0915<br>${vd(s.adminDistrict || s.district || '')}</div>
          </div>

        </div>

      </div>`;
    }).join('<div style="page-break-after:always"></div>');

    const html = `<!DOCTYPE html><html><head>
      <meta charset="UTF-8">
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700&display=swap" rel="stylesheet">
      <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:'Noto Sans Devanagari',sans-serif;font-size:7px;background:#fff;color:#000}
        .card{border:1px solid #333;display:flex;flex-direction:column;width:148mm;overflow:hidden;page-break-after:always}
        @page{margin:4mm;size:A6 landscape}
        @media print{html,body{width:148mm;height:105mm}.card{page-break-after:always}}
      </style>
    </head><body>${cardsHTML}</body></html>`;

    const iframe = document.createElement('iframe');
    iframe.style.cssText = 'position:fixed;top:-9999px;left:-9999px;width:148mm;height:105mm;border:none';
    document.body.appendChild(iframe);
    iframe.contentDocument.open();
    iframe.contentDocument.write(html);
    iframe.contentDocument.close();
    iframe.onload = () => {
      setTimeout(() => {
        iframe.contentWindow.print();
        setTimeout(() => { document.body.removeChild(iframe); resolve(); }, 2000);
      }, 600);
    };
  });
}