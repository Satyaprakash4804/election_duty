import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

const _rankMap = {
  'constable':               'कां0',
  'head constable':          'हो0गा0',
  'si':                      'उ0नि0',
  'sub inspector':           'उ0नि0',
  'inspector':               'निरीक्षक',
  'asi':                     'स0उ0नि0',
  'assistant sub inspector': 'स0उ0नि0',
  'dsp':                     'उपाधीक्षक',
  'asp':                     'सहा0 पुलिस अधीक्षक',
  'sp':                      'पुलिस अधीक्षक',
  'circle officer':          'क्षेत्राधिकारी',
  'co':                      'क्षेत्राधिकारी',
};

const _kAllRanks = [
  'SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable',
];

enum _ArmedFilter    { all, armed, unarmed }
enum _DownloadFilter { all, downloaded, notDownloaded }
enum _DutyTabFilter  { booth, district }

String _rh(dynamic val) =>
    _rankMap[(val ?? '').toString().toLowerCase().trim()] ??
    val?.toString() ?? '—';

String _vd(dynamic x) =>
    (x == null || x.toString().trim().isEmpty) ? '—' : x.toString();

// ─────────────────────────────────────────────────────────────────────────────
//  Election config model
// ─────────────────────────────────────────────────────────────────────────────
class _ElectionConfig {
  final String district;
  final String state;
  final String electionType;
  final String electionName;
  final String phase;
  final String electionYear;
  final String electionDate;
  final String pratahSamay;
  final String sayaSamay;

  const _ElectionConfig({
    this.district    = '',
    this.state       = '',
    this.electionType = '',
    this.electionName = '',
    this.phase       = 'द्वितीय',
    this.electionYear = '2024',
    this.electionDate = '26.04.2024',
    this.pratahSamay  = '07:00',
    this.sayaSamay    = '06:00',
  });

  factory _ElectionConfig.fromMap(Map<String, dynamic> m) {
    // Format date from yyyy-mm-dd → dd.mm.yyyy
    String rawDate = (m['election_date'] ?? '').toString();
    String fmtDate = rawDate;
    if (rawDate.contains('-') && rawDate.length == 10) {
      final parts = rawDate.split('-');
      fmtDate = '${parts[2]}.${parts[1]}.${parts[0]}';
    }
    final year = fmtDate.length >= 4
        ? fmtDate.substring(fmtDate.length - 4)
        : (m['election_year'] ?? '2024').toString();

    return _ElectionConfig(
      district:     (m['district']     ?? '').toString(),
      state:        (m['state']        ?? '').toString(),
      electionType: (m['election_type'] ?? '').toString(),
      electionName: (m['election_name'] ?? '').toString(),
      phase:        (m['phase']        ?? 'द्वितीय').toString(),
      electionYear: year,
      electionDate: fmtDate.isNotEmpty ? fmtDate : '26.04.2024',
      pratahSamay:  (m['pratah_samay'] ?? '07:00').toString(),
      sayaSamay:    (m['saya_samay']   ?? '06:00').toString(),
    );
  }

  Map<String, String> toConfigMap() => {
    'district':     district,
    'state':        state,
    'electionType': electionType,
    'electionName': electionName,
    'phase':        phase,
    'electionYear': electionYear,
    'electionDate': electionDate,
    'pratahSamay':  pratahSamay,
    'sayaSamay':    sayaSamay,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH DUTY CARD PDF  (format unchanged — only config keys extended)
// ══════════════════════════════════════════════════════════════════════════════
pw.Widget buildDutyCardPdf(Map s, pw.Font font, pw.Font bold,
    {Map<String, String> config = const {}}) {

  final String districtLabel =
      (s['adminDistrict'] ?? '').toString().trim().isNotEmpty
          ? s['adminDistrict'].toString().trim()
          : (config['district']?.isNotEmpty == true ? config['district']! : 'बागपत');

  final String stateName    = config['state']?.isNotEmpty == true        ? config['state']!        : 'उत्तर प्रदेश';
  final String electionName = config['electionName']?.isNotEmpty == true ? config['electionName']! : 'लोकसभा सामान्य निर्वाचन';
  final String electionPhase = config['phase']?.isNotEmpty == true       ? config['phase']!        : 'द्वितीय';
  final String electionDate  = config['electionDate']?.isNotEmpty == true ? config['electionDate']! : '26.04.2024';
  final String electionYear  = config['electionYear']?.isNotEmpty == true
      ? config['electionYear']!
      : (electionDate.length >= 4 ? electionDate.substring(electionDate.length - 4) : '2024');
  final String pratahSamay   = config['pratahSamay']?.isNotEmpty == true  ? config['pratahSamay']!  : '07:00';
  final String sayaSamay     = config['sayaSamay']?.isNotEmpty == true     ? config['sayaSamay']!    : '06:00';

  final sahyogi        = (s['sahyogi']        ?? s['allStaff']       ?? s['all_staff']       ?? []) as List;
  final int totalRows  = sahyogi.length < 12 ? 12 : sahyogi.length;

  final zonalOfficers  = (s['zonalOfficers']  ?? s['zonal_officers']  ?? []) as List;
  final sectorOfficers = (s['sectorOfficers'] ?? s['sector_officers'] ?? []) as List;
  final superOfficers  = (s['superOfficers']  ?? s['super_officers']  ?? []) as List;

  final zonalMag     = zonalOfficers.isNotEmpty  ? zonalOfficers[0]  : null;
  final sectorMag    = sectorOfficers.isNotEmpty ? sectorOfficers[0] : null;
  final zonalPolice  = superOfficers.isNotEmpty  ? superOfficers[0]  : null;
  final sectorPolice = sectorOfficers.length > 1
      ? sectorOfficers[1]
      : (sectorOfficers.isNotEmpty ? sectorOfficers[0] : null);

  // ── helpers (identical to original) ──────────────────────────────────────
  pw.Widget th(String t) => pw.Container(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        child: pw.Center(
            child: pw.Text(t,
                style: pw.TextStyle(font: bold, fontSize: 5.5),
                textAlign: pw.TextAlign.center)),
      );

  pw.Widget td(String t,
          {bool center = false, bool isBold = false, double fs = 5.5}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        child: pw.Text(t,
            style: pw.TextStyle(font: isBold ? bold : font, fontSize: fs),
            textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
      );

  pw.Widget metaRow(String label, String value) => pw.Row(children: [
        pw.Expanded(flex: 2,
          child: pw.Container(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200,
                border: pw.Border(right: pw.BorderSide(width: 0.3), bottom: pw.BorderSide(width: 0.3))),
            padding: const pw.EdgeInsets.all(1),
            child: pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 4.5)),
          ),
        ),
        pw.Expanded(flex: 3,
          child: pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
            padding: const pw.EdgeInsets.all(1),
            child: pw.Text(value, style: pw.TextStyle(font: font, fontSize: 4.5)),
          ),
        ),
      ]);

  pw.Widget sHdr(String text, {int flex = 1, bool isLast = false}) => pw.Expanded(
        flex: flex,
        child: pw.Container(
          decoration: pw.BoxDecoration(color: PdfColors.grey300,
              border: isLast ? null : const pw.Border(right: pw.BorderSide(width: 0.3))),
          padding: const pw.EdgeInsets.all(1),
          child: pw.Center(child: pw.Text(text,
              style: pw.TextStyle(font: bold, fontSize: 4.8),
              textAlign: pw.TextAlign.center)),
        ),
      );

  pw.Widget sCell(String text,
          {int flex = 1, bool isBold = false, bool isLast = false}) =>
      pw.Expanded(
        flex: flex,
        child: pw.Container(
          decoration: pw.BoxDecoration(
              border: isLast ? null : const pw.Border(right: pw.BorderSide(width: 0.3))),
          padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 0.5),
          child: pw.Text(text,
              style: pw.TextStyle(font: isBold ? bold : font, fontSize: 4.8),
              overflow: pw.TextOverflow.clip),
        ),
      );

  pw.Widget officerBlock(String title, String? name, String? mobile, String? rank) =>
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Container(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300,
              border: pw.Border(bottom: pw.BorderSide(width: 0.4))),
          padding: const pw.EdgeInsets.all(1),
          child: pw.Center(child: pw.Text(title,
              style: pw.TextStyle(font: bold, fontSize: 5),
              textAlign: pw.TextAlign.center)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(2),
          child: pw.Text(
            [if (rank != null && rank.isNotEmpty) rank, name ?? '—',
             if (mobile != null && mobile.isNotEmpty && mobile != '—') mobile].join('\n'),
            style: pw.TextStyle(font: font, fontSize: 4.5),
            textAlign: pw.TextAlign.center,
          ),
        ),
      ]);

  // ── CARD LAYOUT ───────────────────────────────────────────────────────────
  return pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [

      // HEADER
      pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.8))),
        child: pw.Row(children: [
          pw.Container(width: 42, padding: const pw.EdgeInsets.all(3),
            decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Center(child: pw.Text('ECI', style: pw.TextStyle(font: bold, fontSize: 7)))),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ड्यूटी कार्ड',
                        style: pw.TextStyle(font: bold, fontSize: 10,
                            decoration: pw.TextDecoration.underline)),
                    pw.Text('$electionName–$electionYear',
                        style: pw.TextStyle(font: bold, fontSize: 7)),
                    // STATE line (new)
                    if (stateName.isNotEmpty)
                      pw.Text('राज्य: $stateName',
                          style: pw.TextStyle(font: font, fontSize: 5.5)),
                    pw.Text('जनपद $districtLabel',
                        style: pw.TextStyle(font: font, fontSize: 6.5)),
                    pw.SizedBox(height: 1),
                    pw.Container(
                      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5))),
                      padding: const pw.EdgeInsets.only(top: 1),
                      child: pw.Text(
                          'मतदान चरण–$electionPhase  दिनांक $electionDate  प्रातः $pratahSamay से सांय $sayaSamay तक',
                          style: pw.TextStyle(font: bold, fontSize: 5.5),
                          textAlign: pw.TextAlign.center),
                    ),
                  ]),
            ),
          ),
          pw.Container(width: 42, padding: const pw.EdgeInsets.all(3),
            decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: 0.5))),
            child: pw.Center(child: pw.Text('उ0प्र0\nपुलिस',
                style: pw.TextStyle(font: bold, fontSize: 6),
                textAlign: pw.TextAlign.center))),
        ]),
      ),

      // PRIMARY OFFICER TABLE
      pw.Table(
        border: const pw.TableBorder(
          left: pw.BorderSide(width: 0.5), right: pw.BorderSide(width: 0.5),
          top: pw.BorderSide(width: 0.5),  bottom: pw.BorderSide(width: 0.5),
          horizontalInside: pw.BorderSide(width: 0.5),
          verticalInside:   pw.BorderSide(width: 0.5),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.0), 1: pw.FlexColumnWidth(1.1),
          2: pw.FlexColumnWidth(1.8), 3: pw.FlexColumnWidth(2.8),
          4: pw.FlexColumnWidth(1.8), 5: pw.FlexColumnWidth(1.5),
          6: pw.FlexColumnWidth(1.3), 7: pw.FlexColumnWidth(1.0),
          8: pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(children: [
            th('नाम अधि0/\nकर्म0 गण'), th('पद'), th('बैज नंबर'),
            th('नाम अधि0/कर्म0'), th('मोबाइल न0'), th('तैनाती'),
            th('जनपद'), th('स0/\nनि0'), th('वाहन\nसंख्या'),
          ]),
          pw.TableRow(children: [
            td(''),
            td(_rh(s['rank'] ?? s['user_rank']), center: true, isBold: true),
            td(_vd(s['pno']), center: true),
            td(_vd(s['name']), isBold: true),
            td(_vd(s['mobile']), center: true),
            td(_vd(s['staffThana'] ?? s['thana']), center: true),
            td(_vd(s['district']), center: true),
            td((s['isArmed'] == true || s['is_armed'] == true || s['is_armed'] == 1)
                ? 'सशस्त्र' : 'निःशस्त्र', center: true, fs: 4.5),
            td((s['busNo'] ?? s['bus_no'] ?? '').toString().isNotEmpty
                ? 'बस–${s['busNo'] ?? s['bus_no']}' : '—', center: true, isBold: true),
          ]),
        ],
      ),

      // MIDDLE
      pw.Expanded(
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          // Duty location
          pw.Container(width: 50,
            decoration: const pw.BoxDecoration(border: pw.Border(
                right: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5))),
            child: pw.Column(children: [
              pw.Container(decoration: const pw.BoxDecoration(color: PdfColors.grey300,
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                  padding: const pw.EdgeInsets.all(1),
                  child: pw.Center(child: pw.Text('डियूटी स्थान',
                      style: pw.TextStyle(font: bold, fontSize: 5.5)))),
              pw.Expanded(child: pw.Padding(
                  padding: const pw.EdgeInsets.all(2),
                  child: pw.Center(child: pw.Text(
                      _vd(s['centerName'] ?? s['center_name']),
                      style: pw.TextStyle(font: bold, fontSize: 5.5),
                      textAlign: pw.TextAlign.center)))),
              pw.Container(decoration: const pw.BoxDecoration(color: PdfColors.grey300,
                  border: pw.Border(top: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5))),
                  padding: const pw.EdgeInsets.all(1),
                  child: pw.Center(child: pw.Text('डियूटी प्रकार',
                      style: pw.TextStyle(font: bold, fontSize: 5.5)))),
              pw.Padding(padding: const pw.EdgeInsets.all(2),
                  child: pw.Center(child: pw.Text('बूथ डियूटी',
                      style: pw.TextStyle(font: bold, fontSize: 5.5)))),
            ]),
          ),
          // Staff table
          pw.Expanded(
            child: pw.Column(children: [
              pw.Container(
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                child: pw.Row(children: [
                  sHdr('पद', flex: 1), sHdr('बैज नंबर', flex: 2), sHdr('नाम', flex: 3),
                  sHdr('मोबाइल न0', flex: 2), sHdr('तैनाती', flex: 2),
                  sHdr('जनपद', flex: 2), sHdr('स0/नि0', flex: 1, isLast: true),
                ]),
              ),
              pw.Expanded(
                child: pw.Column(children: List.generate(totalRows, (i) {
                  final e = i < sahyogi.length ? sahyogi[i] : null;
                  return pw.Expanded(
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        color: i.isEven ? PdfColors.white : PdfColors.grey100,
                        border: const pw.Border(bottom: pw.BorderSide(width: 0.3)),
                      ),
                      child: pw.Row(children: [
                        sCell(e != null ? _rh(e['user_rank'] ?? e['rank']) : '0', flex: 1),
                        sCell(e != null ? _vd(e['pno']) : '0', flex: 2),
                        sCell(e != null ? _vd(e['name']) : '0', flex: 3, isBold: e != null),
                        sCell(e != null ? _vd(e['mobile']) : '0', flex: 2),
                        sCell(e != null ? _vd(e['thana']) : '0', flex: 2),
                        sCell(e != null ? _vd(e['district']) : '0', flex: 2),
                        sCell(e != null
                            ? ((e['isArmed'] == true || e['is_armed'] == true || e['is_armed'] == 1)
                                ? 'सशस्त्र' : 'निःशस्त्र')
                            : '', flex: 1, isLast: true),
                      ]),
                    ),
                  );
                })),
              ),
            ]),
          ),
          // Bus/Date column
          pw.Container(width: 28,
            decoration: const pw.BoxDecoration(border: pw.Border(
                left: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5))),
            child: pw.Column(children: [
              pw.Container(decoration: const pw.BoxDecoration(color: PdfColors.grey300,
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                  padding: const pw.EdgeInsets.all(1),
                  child: pw.Center(child: pw.Text(
                      'बस–${_vd(s['busNo'] ?? s['bus_no'])}',
                      style: pw.TextStyle(font: bold, fontSize: 5)))),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text('दिनांक', style: pw.TextStyle(font: bold, fontSize: 5))),
              pw.SizedBox(height: 2),
              pw.Container(decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5))),
                  padding: const pw.EdgeInsets.all(1),
                  child: pw.Center(child: pw.Text(electionDate,
                      style: pw.TextStyle(font: font, fontSize: 5)))),
              pw.Expanded(child: pw.SizedBox()),
              pw.Center(child: pw.Text('सीपीएम\nएफ',
                  style: pw.TextStyle(font: font, fontSize: 5),
                  textAlign: pw.TextAlign.center)),
              pw.SizedBox(height: 3),
              pw.Container(decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(width: 0.5))),
                  padding: const pw.EdgeInsets.all(1),
                  child: pw.Center(child: pw.Text('1/2 सै0',
                      style: pw.TextStyle(font: font, fontSize: 5)))),
            ]),
          ),
        ]),
      ),

      // BOTTOM
      pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.8))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: 50,
            decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(children: [
              metaRow('म0 केंद्र सं0', _vd(s['centerId'] ?? s['center_id'] ?? '—')),
              metaRow('बूथ सं0',       _vd(s['boothNo']  ?? s['booth_no']  ?? '—')),
              metaRow('थाना',          _vd(s['staffThana'] ?? s['thana'])),
              metaRow('जोन न0',        _vd(s['zoneName']   ?? s['zone_name'])),
              metaRow('सेक्टर न0',     _vd(s['sectorName'] ?? s['sector_name'])),
              metaRow('वि0स0',         '—'),
              metaRow('श्रेणी',        _vd(s['centerType'] ?? s['center_type'] ?? '0')),
            ]),
          ),
          pw.Expanded(
            child: pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
              child: pw.Column(children: [
                officerBlock('जोनल मजिस्ट्रेट',
                    zonalMag?['name']?.toString(), zonalMag?['mobile']?.toString(), null),
                pw.Container(decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(width: 0.4))),
                  child: officerBlock('जोनल पुलिस अधिकारी',
                      zonalPolice?['name']?.toString(), zonalPolice?['mobile']?.toString(),
                      zonalPolice != null ? _rh(zonalPolice['user_rank']) : null)),
              ]),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
              child: pw.Column(children: [
                officerBlock('सैक्टर मजिस्ट्रेट',
                    sectorMag?['name']?.toString(), sectorMag?['mobile']?.toString(), null),
                pw.Container(decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(width: 0.4))),
                  child: officerBlock('सेक्टर पुलिस अधिकारी',
                      sectorPolice?['name']?.toString(), sectorPolice?['mobile']?.toString(),
                      sectorPolice != null ? _rh(sectorPolice['user_rank']) : null)),
              ]),
            ),
          ),
          pw.Container(width: 38, padding: const pw.EdgeInsets.all(4),
            child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
              pw.SizedBox(height: 10),
              pw.Text('पुलिस अधीक्षक',
                  style: pw.TextStyle(font: bold, fontSize: 5.5), textAlign: pw.TextAlign.center),
              pw.Text(districtLabel,
                  style: pw.TextStyle(font: bold, fontSize: 5.5), textAlign: pw.TextAlign.center),
            ]),
          ),
        ]),
      ),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  DISTRICT DUTY CARD PDF  (new — same visual language as booth card)
// ══════════════════════════════════════════════════════════════════════════════
pw.Widget buildDistrictDutyCardPdf(
  Map s,
  pw.Font font,
  pw.Font bold, {
  Map<String, String> config = const {},
}) {
  final String districtLabel = config['district']?.isNotEmpty == true
      ? config['district']! : 'बागपत';
  final String stateName      = config['state']?.isNotEmpty == true
      ? config['state']!    : 'उत्तर प्रदेश';
  final String electionName   = config['electionName']?.isNotEmpty == true
      ? config['electionName']! : 'लोकसभा सामान्य निर्वाचन';
  final String electionPhase  = config['phase']?.isNotEmpty == true
      ? config['phase']!    : 'द्वितीय';
  final String electionDate   = config['electionDate']?.isNotEmpty == true
      ? config['electionDate']! : '26.04.2024';
  final String electionYear   = config['electionYear']?.isNotEmpty == true
      ? config['electionYear']!
      : (electionDate.length >= 4 ? electionDate.substring(electionDate.length - 4) : '2024');
  final String pratahSamay    = config['pratahSamay']?.isNotEmpty == true
      ? config['pratahSamay']! : '07:00';
  final String sayaSamay      = config['sayaSamay']?.isNotEmpty == true
      ? config['sayaSamay']!  : '06:00';

  // District-duty specific fields
  final String dutyLabelHi  = _vd(s['dutyLabelHi'] ?? s['duty_label_hi']);
  final int    batchNo      = (s['batchNo'] ?? s['batch_no'] ?? 1) as int;
  final String busNo        = _vd(s['busNo'] ?? s['bus_no']);
  final String note         = _vd(s['note']);

  // Staff in this batch
  final List staffList = (s['staff'] ?? []) as List;
  final int totalRows  = staffList.length < 14 ? 14 : staffList.length;

  // ── helpers ───────────────────────────────────────────────────────────────
  pw.Widget th(String t) => pw.Container(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        child: pw.Center(child: pw.Text(t,
            style: pw.TextStyle(font: bold, fontSize: 5.5),
            textAlign: pw.TextAlign.center)),
      );

  pw.Widget sHdr(String text, {int flex = 1, bool isLast = false}) => pw.Expanded(
        flex: flex,
        child: pw.Container(
          decoration: pw.BoxDecoration(color: PdfColors.grey300,
              border: isLast ? null : const pw.Border(right: pw.BorderSide(width: 0.3))),
          padding: const pw.EdgeInsets.all(1),
          child: pw.Center(child: pw.Text(text,
              style: pw.TextStyle(font: bold, fontSize: 4.8),
              textAlign: pw.TextAlign.center)),
        ),
      );

  pw.Widget sCell(String text, {int flex = 1, bool isBold = false, bool isLast = false}) =>
      pw.Expanded(
        flex: flex,
        child: pw.Container(
          decoration: pw.BoxDecoration(
              border: isLast ? null : const pw.Border(right: pw.BorderSide(width: 0.3))),
          padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 0.5),
          child: pw.Text(text,
              style: pw.TextStyle(font: isBold ? bold : font, fontSize: 4.8),
              overflow: pw.TextOverflow.clip),
        ),
      );

  pw.Widget metaRow(String label, String value) => pw.Row(children: [
        pw.Expanded(flex: 2,
          child: pw.Container(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200,
                border: pw.Border(right: pw.BorderSide(width: 0.3), bottom: pw.BorderSide(width: 0.3))),
            padding: const pw.EdgeInsets.all(1),
            child: pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 4.5)),
          ),
        ),
        pw.Expanded(flex: 3,
          child: pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
            padding: const pw.EdgeInsets.all(1),
            child: pw.Text(value, style: pw.TextStyle(font: font, fontSize: 4.5)),
          ),
        ),
      ]);

  // ── CARD ──────────────────────────────────────────────────────────────────
  return pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [

      // HEADER (same structure as booth card)
      pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.8))),
        child: pw.Row(children: [
          pw.Container(width: 42, padding: const pw.EdgeInsets.all(3),
            decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Center(child: pw.Text('ECI', style: pw.TextStyle(font: bold, fontSize: 7)))),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ड्यूटी कार्ड (जनपदीय)',
                        style: pw.TextStyle(font: bold, fontSize: 9,
                            decoration: pw.TextDecoration.underline)),
                    pw.Text('$electionName–$electionYear',
                        style: pw.TextStyle(font: bold, fontSize: 7)),
                    if (stateName.isNotEmpty)
                      pw.Text('राज्य: $stateName',
                          style: pw.TextStyle(font: font, fontSize: 5.5)),
                    pw.Text('जनपद $districtLabel',
                        style: pw.TextStyle(font: font, fontSize: 6.5)),
                    pw.SizedBox(height: 1),
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                          border: pw.Border(top: pw.BorderSide(width: 0.5))),
                      padding: const pw.EdgeInsets.only(top: 1),
                      child: pw.Text(
                          'मतदान चरण–$electionPhase  दिनांक $electionDate  '
                          'प्रातः $pratahSamay से सांय $sayaSamay तक',
                          style: pw.TextStyle(font: bold, fontSize: 5.5),
                          textAlign: pw.TextAlign.center),
                    ),
                  ]),
            ),
          ),
          pw.Container(width: 42, padding: const pw.EdgeInsets.all(3),
            decoration: const pw.BoxDecoration(
                border: pw.Border(left: pw.BorderSide(width: 0.5))),
            child: pw.Center(child: pw.Text('उ0प्र0\nपुलिस',
                style: pw.TextStyle(font: bold, fontSize: 6),
                textAlign: pw.TextAlign.center))),
        ]),
      ),

      // DUTY TYPE + BATCH INFO ROW
      pw.Table(
        border: const pw.TableBorder(
          left: pw.BorderSide(width: 0.5), right: pw.BorderSide(width: 0.5),
          top: pw.BorderSide(width: 0.5),  bottom: pw.BorderSide(width: 0.5),
          horizontalInside: pw.BorderSide(width: 0.5),
          verticalInside:   pw.BorderSide(width: 0.5),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(3.0), 1: pw.FlexColumnWidth(1.5),
          2: pw.FlexColumnWidth(2.0), 3: pw.FlexColumnWidth(2.0),
          4: pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(children: [
            th('ड्यूटी प्रकार'),
            th('बैच सं0'),
            th('बस सं0'),
            th('दिनांक'),
            th('कुल कर्मी'),
          ]),
          pw.TableRow(children: [
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: pw.Text(dutyLabelHi,
                  style: pw.TextStyle(font: bold, fontSize: 6.0))),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: pw.Center(child: pw.Text('$batchNo',
                  style: pw.TextStyle(font: bold, fontSize: 6.0)))),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: pw.Center(child: pw.Text(busNo,
                  style: pw.TextStyle(font: bold, fontSize: 5.5)))),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: pw.Center(child: pw.Text(electionDate,
                  style: pw.TextStyle(font: font, fontSize: 5.5)))),
            pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: pw.Center(child: pw.Text('${staffList.length}',
                  style: pw.TextStyle(font: bold, fontSize: 6.0)))),
          ]),
        ],
      ),

      // NOTE row (if any)
      if (note.isNotEmpty && note != '—')
        pw.Container(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100,
              border: pw.Border(bottom: pw.BorderSide(width: 0.4))),
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: pw.Row(children: [
            pw.Text('विशेष टिप्पणी: ', style: pw.TextStyle(font: bold, fontSize: 5)),
            pw.Expanded(child: pw.Text(note,
                style: pw.TextStyle(font: font, fontSize: 5))),
          ]),
        ),

      // STAFF LIST
      pw.Expanded(
        child: pw.Column(children: [
          // Column headers
          pw.Container(
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
            child: pw.Row(children: [
              sHdr('क्र0', flex: 1),
              sHdr('पद', flex: 2),
              sHdr('बैज सं0', flex: 2),
              sHdr('नाम', flex: 4),
              sHdr('मोबाइल', flex: 3),
              sHdr('थाना', flex: 3),
              sHdr('जनपद', flex: 3),
              sHdr('स0/नि0', flex: 2, isLast: true),
            ]),
          ),
          pw.Expanded(
            child: pw.Column(children: List.generate(totalRows, (i) {
              final e = i < staffList.length ? staffList[i] : null;
              return pw.Expanded(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    color: i.isEven ? PdfColors.white : PdfColors.grey100,
                    border: const pw.Border(bottom: pw.BorderSide(width: 0.3)),
                  ),
                  child: pw.Row(children: [
                    sCell('${i + 1}', flex: 1),
                    sCell(e != null ? _rh(e['rank'] ?? e['user_rank']) : '', flex: 2),
                    sCell(e != null ? _vd(e['pno']) : '', flex: 2),
                    sCell(e != null ? _vd(e['name']) : '', flex: 4, isBold: e != null),
                    sCell(e != null ? _vd(e['mobile']) : '', flex: 3),
                    sCell(e != null ? _vd(e['thana']) : '', flex: 3),
                    sCell(e != null ? _vd(e['district']) : '', flex: 3),
                    sCell(e != null
                        ? ((e['isArmed'] == true || e['is_armed'] == true || e['is_armed'] == 1)
                            ? 'सशस्त्र' : 'निःशस्त्र')
                        : '', flex: 2, isLast: true),
                  ]),
                ),
              );
            })),
          ),
        ]),
      ),

      // BOTTOM — meta + signature
      pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.8))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(width: 80,
            decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
            child: pw.Column(children: [
              metaRow('ड्यूटी प्रकार', dutyLabelHi),
              metaRow('बैच सं0',        '$batchNo'),
              metaRow('बस सं0',         busNo),
              metaRow('चरण',            electionPhase),
              metaRow('मतदान दिनांक',   electionDate),
              metaRow('जनपद',           districtLabel),
            ]),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(height: 12),
                    pw.Text('पुलिस अधीक्षक',
                        style: pw.TextStyle(font: bold, fontSize: 6),
                        textAlign: pw.TextAlign.center),
                    pw.Text(districtLabel,
                        style: pw.TextStyle(font: bold, fontSize: 6),
                        textAlign: pw.TextAlign.center),
                  ]),
            ),
          ),
        ]),
      ),
    ]),
  );
}

// ── Page format helpers ────────────────────────────────────────────────────────
PdfPageFormat _pageFormatFor(Map s) {
  final count = ((s['sahyogi'] ?? s['allStaff'] ?? s['all_staff'] ?? []) as List).length;
  if (count > 20) return PdfPageFormat.a4.landscape;
  if (count > 12) return PdfPageFormat.a5.landscape;
  return PdfPageFormat.a6.landscape;
}

PdfPageFormat _districtPageFormat(int staffCount) {
  if (staffCount > 20) return PdfPageFormat.a4.landscape;
  if (staffCount > 12) return PdfPageFormat.a5.landscape;
  return PdfPageFormat.a5.landscape;
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY CARD PAGE
// ══════════════════════════════════════════════════════════════════════════════
class DutyCardPage extends StatefulWidget {
  const DutyCardPage({super.key});
  @override
  State<DutyCardPage> createState() => _DutyCardPageState();
}

class _DutyCardPageState extends State<DutyCardPage>
    with SingleTickerProviderStateMixin {

  // ── Tab ──────────────────────────────────────────────────────────────────
  late final TabController _tabCtrl;
  _DutyTabFilter _activeTab = _DutyTabFilter.booth;

  // ── booth list state ──────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _items = [];
  int  _page       = 1;
  int  _totalCount = 0;
  int  _totalPages = 1;
  bool _loading    = false;
  bool _hasMore    = true;
  static const int _kLimit = 50;

  // ── district duty state ───────────────────────────────────────────────────
  // Map<dutyType, { rule info + batches: [ {batchNo, staff:[]} ] }>
  Map<String, dynamic>         _districtSummary = {};
  Map<String, List<dynamic>>   _districtBatches = {};  // dutyType → batches
  bool _districtLoading = false;
  String? _expandedDutyType;

  // ── filter state ──────────────────────────────────────────────────────────
  String          _q              = '';
  String?         _rankFilter;
  _ArmedFilter    _armedFilter    = _ArmedFilter.all;
  _DownloadFilter _downloadFilter = _DownloadFilter.all;

  // ── election config fetched from server ───────────────────────────────────
  _ElectionConfig _electionConfig = const _ElectionConfig();

  Timer?       _debounce;
  final        _searchCtrl = TextEditingController();
  Set<int>     _selected   = {};
  final        _scroll     = ScrollController();

  // ── lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() {
          _activeTab = _DutyTabFilter.values[_tabCtrl.index];
        });
        if (_tabCtrl.index == 1 && _districtSummary.isEmpty) {
          _loadDistrictDutySummary();
        }
      }
    });

    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300)
        _loadMore();
    });
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        final q = _searchCtrl.text.trim();
        if (q != _q) { _q = q; _reload(); }
      });
    });
    _reload();
    _fetchConfig();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _scroll.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── fetch active election config for this district ────────────────────────
  Future<void> _fetchConfig() async {
    try {
      final token = await AuthService.getToken();

      // Active election config for this district (new endpoint)
      final configRes  = await ApiService.get('/admin/election-config/active', token: token);
      final configData = (configRes['data'] as Map<String, dynamic>?) ?? {};

      if (!mounted) return;
      setState(() {
        _electionConfig = _ElectionConfig.fromMap(configData);
      });
    } catch (_) {
      // Fallback to app_config
      try {
        final token     = await AuthService.getToken();
        final legacyRes = await ApiService.get('/admin/config', token: token);
        final legacyData = (legacyRes['data'] as Map<String, dynamic>?) ?? {};
        final profileRes = await ApiService.get('/auth/me', token: token);
        final profileData = (profileRes['data'] as Map<String, dynamic>?) ?? {};

        if (!mounted) return;
        setState(() {
          _electionConfig = _ElectionConfig(
            district:    (profileData['district'] ?? '').toString(),
            phase:       (legacyData['phase']        ?? 'द्वितीय').toString(),
            electionDate: (legacyData['electionDate'] ?? '26.04.2024').toString(),
            electionYear: (legacyData['electionYear'] ?? '2024').toString(),
          );
        });
      } catch (_) {
        // silently keep defaults
      }
    }
  }

  // ── district duty summary ────────────────────────────────────────────────
  Future<void> _loadDistrictDutySummary() async {
    if (_districtLoading) return;
    setState(() => _districtLoading = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/district-duty/summary', token: token);
      if (!mounted) return;
      setState(() {
        _districtSummary  = Map<String, dynamic>.from(res['data'] as Map? ?? {});
        _districtLoading  = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _districtLoading = false);
        showSnack(context, 'District duty load failed: $e', error: true);
      }
    }
  }

  Future<void> _loadBatchesForDutyType(String dutyType) async {
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get(
          '/admin/district-duty/$dutyType/batches', token: token);
      if (!mounted) return;
      setState(() {
        _districtBatches[dutyType] =
            (res['data'] as List?)?.map((e) => e as Map).toList() ?? [];
      });
    } catch (e) {
      if (mounted) showSnack(context, 'Failed: $e', error: true);
    }
  }

  // ── booth data loading ────────────────────────────────────────────────────
  void _reload() {
    setState(() {
      _items.clear(); _page = 1; _totalCount = 0;
      _totalPages = 1; _hasMore = true; _selected.clear();
    });
    _fetch();
  }

  Future<void> _fetch() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final url   = StringBuffer('/admin/duties?page=$_page&limit=$_kLimit');
      if (_q.isNotEmpty) url.write('&q=${Uri.encodeComponent(_q)}');

      final res     = await ApiService.get(url.toString(), token: token);
      final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
      final items   = (wrapper['data'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      final total      = (wrapper['total']      as num?)?.toInt() ?? 0;
      final totalPages = (wrapper['totalPages'] as num?)?.toInt() ?? 1;

      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _totalCount = total;
        _totalPages = totalPages;
        _hasMore    = _page < totalPages;
        _page++;
        _loading    = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showSnack(context, 'Failed to load: $e', error: true);
      }
    }
  }

  void _loadMore() { if (!_loading && _hasMore) _fetch(); }

  // ── client-side filter ────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _visible {
    return _items.where((s) {
      if (_rankFilter != null && _rankFilter!.isNotEmpty) {
        final rf      = _rankFilter!.toLowerCase();
        final primary = (s['rank'] ?? s['user_rank'] ?? '').toString().toLowerCase();
        final rankOk  = primary == rf ||
            ((s['sahyogi'] ?? []) as List).any((e) =>
                (e['user_rank'] ?? e['rank'] ?? '').toString().toLowerCase() == rf);
        if (!rankOk) return false;
      }
      if (_armedFilter != _ArmedFilter.all) {
        final wantArmed = _armedFilter == _ArmedFilter.armed;
        final isArmed   = s['isArmed'] == true || s['is_armed'] == true || s['is_armed'] == 1;
        if (wantArmed != isArmed) return false;
      }
      if (_downloadFilter != _DownloadFilter.all) {
        final downloaded = s['cardDownloaded'] == true;
        if (_downloadFilter == _DownloadFilter.downloaded   && !downloaded) return false;
        if (_downloadFilter == _DownloadFilter.notDownloaded &&  downloaded) return false;
      }
      return true;
    }).toList();
  }

  // ── label helpers ─────────────────────────────────────────────────────────
  String   _armedLabel(_ArmedFilter f)    => const ['सभी', 'सशस्त्र', 'निःशस्त्र'][f.index];
  Color    _armedColor(_ArmedFilter f)    => [kPrimary, const Color(0xFFC62828), const Color(0xFF1565C0)][f.index];
  IconData _armedIcon(_ArmedFilter f)     => [Icons.people_outline, Icons.shield_outlined, Icons.person_outline][f.index];
  String   _dlLabel(_DownloadFilter f)    => ['सभी', 'डाउनलोड', 'शेष'][f.index];
  Color    _dlColor(_DownloadFilter f)    => [kPrimary, kSuccess, const Color(0xFFE65100)][f.index];
  IconData _dlIcon(_DownloadFilter f)     => [Icons.list_outlined, Icons.check_circle_outline, Icons.pending_outlined][f.index];

  // ── print helpers ─────────────────────────────────────────────────────────
  Future<void> _print(List<Map> list) async {
    if (list.isEmpty) return;
    final pdf  = pw.Document();
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();
    final cfg  = _electionConfig.toConfigMap();
    for (final s in list) {
      pdf.addPage(pw.Page(
        pageFormat: _pageFormatFor(s),
        margin:     const pw.EdgeInsets.all(4),
        build: (_) => buildDutyCardPdf(s, font, bold, config: cfg),
      ));
    }
    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  Future<void> _printDistrictBatch(Map batchData, String dutyLabelHi) async {
    final pdf  = pw.Document();
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();
    final cfg  = _electionConfig.toConfigMap();

    final staffList = (batchData['staff'] as List?) ?? [];
    final payload   = {
      ...batchData,
      'dutyLabelHi': dutyLabelHi,
    };

    pdf.addPage(pw.Page(
      pageFormat: _districtPageFormat(staffList.length),
      margin:     const pw.EdgeInsets.all(4),
      build: (_) => buildDistrictDutyCardPdf(payload, font, bold, config: cfg),
    ));
    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  Future<void> _printAllDistrictBatches(String dutyType, String dutyLabelHi) async {
    final batches = _districtBatches[dutyType] ?? [];
    if (batches.isEmpty) {
      showSnack(context, 'पहले batches लोड करें', error: true);
      return;
    }
    final pdf  = pw.Document();
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();
    final cfg  = _electionConfig.toConfigMap();

    for (final batch in batches) {
      final staffList = (batch['staff'] as List?) ?? [];
      final payload   = { ...Map<String, dynamic>.from(batch as Map), 'dutyLabelHi': dutyLabelHi };
      pdf.addPage(pw.Page(
        pageFormat: _districtPageFormat(staffList.length),
        margin:     const pw.EdgeInsets.all(4),
        build: (_) => buildDistrictDutyCardPdf(payload, font, bold, config: cfg),
      ));
    }
    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  Future<void> _printAll() async {
    if (!_hasMore) { await _print(_visible); return; }
    try {
      final token = await AuthService.getToken();
      final all   = List<Map<String, dynamic>>.from(_items);
      int pg      = _page;
      while (pg <= _totalPages) {
        final url = StringBuffer('/admin/duties?page=$pg&limit=200');
        if (_q.isNotEmpty) url.write('&q=${Uri.encodeComponent(_q)}');
        final res     = await ApiService.get(url.toString(), token: token);
        final wrapper = (res['data'] as Map<String, dynamic>?) ?? {};
        all.addAll((wrapper['data'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? []);
        pg++;
      }
      final toPrint = all.where((s) {
        if (_rankFilter != null && _rankFilter!.isNotEmpty) {
          final rf = _rankFilter!.toLowerCase();
          final pr = (s['rank'] ?? s['user_rank'] ?? '').toString().toLowerCase();
          if (pr != rf && !((s['sahyogi'] ?? []) as List).any((e) =>
              (e['user_rank'] ?? e['rank'] ?? '').toString().toLowerCase() == rf))
            return false;
        }
        if (_armedFilter != _ArmedFilter.all) {
          final wantArmed = _armedFilter == _ArmedFilter.armed;
          final isArmed   = s['isArmed'] == true || s['is_armed'] == true || s['is_armed'] == 1;
          if (wantArmed != isArmed) return false;
        }
        if (_downloadFilter != _DownloadFilter.all) {
          final downloaded = s['cardDownloaded'] == true;
          if (_downloadFilter == _DownloadFilter.downloaded   && !downloaded) return false;
          if (_downloadFilter == _DownloadFilter.notDownloaded &&  downloaded) return false;
        }
        return true;
      }).toList();
      await _print(toPrint);
    } catch (e) {
      if (mounted) showSnack(context, 'Print failed: $e', error: true);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Tab bar ──────────────────────────────────────────────────────────
      Container(
        color: kSurface,
        child: TabBar(
          controller: _tabCtrl,
          labelColor: kPrimary,
          unselectedLabelColor: kSubtle,
          indicatorColor: kPrimary,
          tabs: const [
            Tab(icon: Icon(Icons.how_to_vote_outlined, size: 18), text: 'बूथ ड्यूटी'),
            Tab(icon: Icon(Icons.location_city_outlined, size: 18), text: 'जनपदीय ड्यूटी'),
          ],
        ),
      ),

      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildBoothTab(),
            _buildDistrictTab(),
          ],
        ),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BOOTH TAB (original UI — untouched)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildBoothTab() {
    final visible = _visible;
    return Column(children: [

      // Search + Filter bar
      Container(
        color: kSurface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(children: [
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: kDark, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'नाम, PNO, केंद्र, जोन, थाना से खोजें...',
              hintStyle: const TextStyle(color: kSubtle, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: kSubtle, size: 16),
                      onPressed: () { _searchCtrl.clear(); _q = ''; _reload(); })
                  : null,
              filled: true, fillColor: Colors.white, isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPrimary, width: 2)),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('शस्त्र:', style: TextStyle(color: kSubtle, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            ..._ArmedFilter.values.map((f) => Padding(
              padding: const EdgeInsets.only(right: 5),
              child: _FilterChip(label: _armedLabel(f), color: _armedColor(f),
                icon: _armedIcon(f), selected: _armedFilter == f,
                onTap: () {
                  if (_armedFilter != f)
                    setState(() { _armedFilter = f; _selected.clear(); });
                }),
            )),
          ]),
          const SizedBox(height: 8),
          SizedBox(height: 32,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _RankChip(label: 'सभी पद', selected: _rankFilter == null, color: kPrimary,
                onTap: () { if (_rankFilter != null) setState(() => _rankFilter = null); }),
              const SizedBox(width: 6),
              ..._kAllRanks.map((rank) {
                final selected = _rankFilter == rank;
                return Padding(padding: const EdgeInsets.only(right: 6),
                  child: _RankChip(label: rank, selected: selected, color: _rankColor(rank),
                    onTap: () => setState(() { _rankFilter = selected ? null : rank; _selected.clear(); })));
              }),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('कार्ड:', style: TextStyle(color: kSubtle, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            ..._DownloadFilter.values.map((f) => Padding(
              padding: const EdgeInsets.only(right: 5),
              child: _FilterChip(label: _dlLabel(f), color: _dlColor(f),
                icon: _dlIcon(f), selected: _downloadFilter == f,
                onTap: () {
                  if (_downloadFilter != f)
                    setState(() { _downloadFilter = f; _selected.clear(); });
                }),
            )),
          ]),
        ]),
      ),

      if (visible.isNotEmpty)
        Container(
          color: kBg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                (_rankFilter != null || _armedFilter != _ArmedFilter.all || _downloadFilter != _DownloadFilter.all)
                    ? '${visible.length} / $_totalCount'
                    : _totalCount > _items.length ? '${_items.length} / $_totalCount' : '$_totalCount',
                style: const TextStyle(color: kDark, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              Text(_buildCountLabel(), style: const TextStyle(color: kSubtle, fontSize: 10)),
            ]),
            const Spacer(),
            if (_selected.isNotEmpty) ...[
              _ActionBtn(label: 'Print (${_selected.length})', icon: Icons.print, color: kPrimary,
                onTap: () {
                  final sel = visible.where((s) => _selected.contains(s['id'] as int))
                      .map((s) => Map<String, dynamic>.from(s)).toList();
                  _print(sel);
                }),
              const SizedBox(width: 6),
            ],
            _ActionBtn(label: 'Print All (${visible.length})',
                icon: Icons.print_outlined, color: kDark, onTap: _printAll),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == visible.length) _selected.clear();
                else _selected = visible.map((s) => s['id'] as int).toSet();
              }),
              style: TextButton.styleFrom(foregroundColor: kPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              child: Text(_selected.length == visible.length ? 'Deselect' : 'Select All',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),

      if (_loading && _items.isEmpty)
        const Expanded(child: Center(child: CircularProgressIndicator(color: kPrimary)))
      else if (visible.isEmpty && !_loading)
        Expanded(child: emptyState(_buildEmptyLabel(), Icons.how_to_vote_outlined))
      else
        Expanded(
          child: ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: visible.length +
                (_hasMore && _rankFilter == null && _armedFilter == _ArmedFilter.all &&
                    _downloadFilter == _DownloadFilter.all ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              if (i >= visible.length)
                return const Padding(padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))));

              final s          = visible[i];
              final id         = s['id'] as int;
              final sel        = _selected.contains(id);
              final primaryRank = s['rank'] ?? s['user_rank'] ?? '';
              final rankHindi  = _rh(primaryRank);
              final isArmed    = s['isArmed'] == true || s['is_armed'] == true || s['is_armed'] == 1;
              final downloaded = s['cardDownloaded'] == true;

              return GestureDetector(
                onTap: () => setState(() => sel ? _selected.remove(id) : _selected.add(id)),
                child: Container(
                  decoration: BoxDecoration(
                    color: sel ? kPrimary.withOpacity(0.06) : downloaded ? kSuccess.withOpacity(0.03) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel ? kPrimary : downloaded ? kSuccess.withOpacity(0.35) : kBorder.withOpacity(0.4),
                      width: sel ? 1.5 : downloaded ? 1.5 : 1,
                    ),
                    boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: GestureDetector(
                      onTap: () => setState(() => sel ? _selected.remove(id) : _selected.add(id)),
                      child: Stack(children: [
                        Container(width: 40, height: 40,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: sel ? kPrimary : kSurface,
                              border: Border.all(color: sel ? kPrimary : kBorder)),
                          child: Center(child: sel
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : Text('${i + 1}', style: const TextStyle(
                                  color: kPrimary, fontWeight: FontWeight.w800, fontSize: 12)))),
                        if (downloaded && !sel)
                          Positioned(right: 0, bottom: 0,
                            child: Container(width: 16, height: 16,
                              decoration: const BoxDecoration(color: kSuccess, shape: BoxShape.circle),
                              child: const Icon(Icons.check, color: Colors.white, size: 10))),
                      ]),
                    ),
                    title: Row(children: [
                      Expanded(child: Text('${s['name']}',
                          style: const TextStyle(color: kDark, fontWeight: FontWeight.w700, fontSize: 14))),
                      Container(margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isArmed ? const Color(0xFFC62828).withOpacity(0.1) : const Color(0xFF1565C0).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: isArmed ? const Color(0xFFC62828).withOpacity(0.35) : const Color(0xFF1565C0).withOpacity(0.35)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isArmed ? Icons.shield_outlined : Icons.person_outline, size: 9,
                              color: isArmed ? const Color(0xFFC62828) : const Color(0xFF1565C0)),
                          const SizedBox(width: 3),
                          Text(isArmed ? 'सशस्त्र' : 'निःशस्त्र',
                              style: TextStyle(color: isArmed ? const Color(0xFFC62828) : const Color(0xFF1565C0),
                                  fontSize: 9, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: _rankColor(primaryRank).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _rankColor(primaryRank).withOpacity(0.3))),
                        child: Text(rankHindi, style: TextStyle(color: _rankColor(primaryRank),
                            fontSize: 10, fontWeight: FontWeight.w700))),
                    ]),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 3),
                      Row(children: [
                        _tag(Icons.badge_outlined, '${s['pno']}'),
                        const SizedBox(width: 8),
                        _tag(Icons.phone_outlined, '${s['mobile']}'),
                        const SizedBox(width: 8),
                        if ((s['busNo'] ?? '').toString().isNotEmpty)
                          _tag(Icons.directions_bus, 'बस–${s['busNo']}', color: kAccent),
                      ]),
                      const SizedBox(height: 3),
                      _tag(Icons.location_on_outlined, '${s['centerName']} • ${s['gpName']}', color: kInfo),
                      const SizedBox(height: 2),
                      _tag(Icons.layers_outlined, '${s['sectorName']} › ${s['zoneName']} › ${s['superZoneName']}'),
                    ]),
                    trailing: IconButton(
                      icon: const Icon(Icons.print_outlined, color: kPrimary),
                      onPressed: () => _print([Map<String, dynamic>.from(s)]),
                    ),
                    isThreeLine: true,
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  DISTRICT DUTY TAB
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildDistrictTab() {
    if (_districtLoading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    if (_districtSummary.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          emptyState('कोई जनपदीय ड्यूटी नहीं मिली', Icons.location_city_outlined),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('पुनः लोड करें'),
            onPressed: _loadDistrictDutySummary,
          ),
        ]),
      );
    }

    final entries = _districtSummary.entries.toList();

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final dutyType   = entries[i].key;
        final info       = entries[i].value as Map;
        final labelHi    = (info['dutyLabelHi'] ?? dutyType).toString();
        final sankhya    = (info['sankhya'] ?? 0) as int;
        final assigned   = (info['totalAssigned'] ?? 0) as int;
        final batchCount = (info['batchCount'] ?? 0) as int;
        final isExpanded = _expandedDutyType == dutyType;
        final batches    = _districtBatches[dutyType] ?? [];

        final pct = sankhya == 0 ? 0.0 : (assigned / sankhya).clamp(0.0, 1.0);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isExpanded ? kPrimary : kBorder.withOpacity(0.5),
                width: isExpanded ? 1.5 : 1),
            boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Header row ────────────────────────────────────────────────
            InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              onTap: () async {
                setState(() {
                  _expandedDutyType = isExpanded ? null : dutyType;
                });
                if (!isExpanded && !_districtBatches.containsKey(dutyType)) {
                  await _loadBatchesForDutyType(dutyType);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(labelHi,
                          style: const TextStyle(color: kDark, fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                    // Print all batches
                    if (batchCount > 0)
                      IconButton(
                        icon: const Icon(Icons.print_outlined, color: kPrimary, size: 20),
                        tooltip: 'सभी बैच प्रिंट करें',
                        onPressed: () async {
                          if (!_districtBatches.containsKey(dutyType))
                            await _loadBatchesForDutyType(dutyType);
                          await _printAllDistrictBatches(dutyType, labelHi);
                        },
                      ),
                    Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: kSubtle),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    _statBadge('कुल आवश्यक', '$sankhya', kAccent),
                    const SizedBox(width: 6),
                    _statBadge('नियुक्त', '$assigned',
                        assigned >= sankhya ? kSuccess : kPrimary),
                    const SizedBox(width: 6),
                    _statBadge('बैच', '$batchCount', kInfo),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: kBorder.withOpacity(0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          assigned >= sankhya ? kSuccess : kPrimary),
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('${(pct * 100).toStringAsFixed(0)}% पूर्ण',
                      style: const TextStyle(color: kSubtle, fontSize: 10)),
                ]),
              ),
            ),

            // ── Expanded: batch list ──────────────────────────────────────
            if (isExpanded) ...[
              const Divider(height: 1, color: kBorder),
              if (batches.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))),
                )
              else
                ...batches.map((batch) {
                  final batchNo    = (batch['batchNo'] ?? batch['batch_no'] ?? 0) as int;
                  final staffCount = (batch['staffCount'] ?? batch['staff_count'] ?? 0) as int;
                  final staffList  = (batch['staff'] ?? []) as List;
                  final busNo      = (batch['busNo'] ?? batch['bus_no'] ?? '').toString();
                  final note       = (batch['note'] ?? '').toString();

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kBg.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBorder.withOpacity(0.4)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Batch header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(children: [
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: kPrimary,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('बैच $batchNo',
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 11, fontWeight: FontWeight.w800))),
                          const SizedBox(width: 8),
                          if (busNo.isNotEmpty)
                            _tag(Icons.directions_bus, 'बस–$busNo', color: kAccent),
                          const SizedBox(width: 6),
                          _tag(Icons.people_outline, '$staffCount कर्मी'),
                          const Spacer(),
                          // Print this batch
                          GestureDetector(
                            onTap: () => _printDistrictBatch(
                                {  ...Map<String, dynamic>.from(batch as Map), 'dutyLabelHi': labelHi },
                                labelHi),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: kPrimary,
                                  borderRadius: BorderRadius.circular(7)),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.print, color: Colors.white, size: 13),
                                SizedBox(width: 4),
                                Text('Print', style: TextStyle(color: Colors.white,
                                    fontSize: 11, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                        ]),
                      ),
                      if (note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _tag(Icons.note_outlined, note, color: kSubtle),
                        ),
                      // Staff mini list
                      if (staffList.isNotEmpty) ...[
                        const Divider(height: 1, indent: 12, endIndent: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Column(
                            children: staffList.take(5).map((e) {
                              final isArmed = e['isArmed'] == true || e['is_armed'] == true;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(children: [
                                  Container(width: 3, height: 3,
                                    decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(e['name'] ?? '',
                                      style: const TextStyle(color: kDark, fontSize: 11,
                                          fontWeight: FontWeight.w600))),
                                  Text(_rh(e['rank'] ?? e['user_rank']),
                                      style: TextStyle(color: _rankColor(e['rank'] ?? ''),
                                          fontSize: 10, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 6),
                                  Icon(isArmed ? Icons.shield_outlined : Icons.person_outline,
                                      size: 11,
                                      color: isArmed ? const Color(0xFFC62828) : const Color(0xFF1565C0)),
                                ]),
                              );
                            }).toList(),
                          ),
                        ),
                        if (staffList.length > 5)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, bottom: 8),
                            child: Text('+ ${staffList.length - 5} और कर्मी...',
                                style: const TextStyle(color: kSubtle, fontSize: 10)),
                          ),
                      ],
                      const SizedBox(height: 4),
                    ]),
                  );
                }).toList(),
              const SizedBox(height: 8),
            ],
          ]),
        );
      },
    );
  }

  // ── helper widgets ─────────────────────────────────────────────────────────
  Widget _statBadge(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
      const SizedBox(width: 4),
      Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    ]),
  );

  String _buildCountLabel() {
    final parts = <String>[];
    if (_rankFilter    != null)                 parts.add('पद: $_rankFilter');
    if (_armedFilter   != _ArmedFilter.all)     parts.add(_armedLabel(_armedFilter));
    if (_downloadFilter != _DownloadFilter.all) parts.add(_dlLabel(_downloadFilter));
    return parts.isNotEmpty ? parts.join(' • ') : 'कुल ड्यूटी';
  }

  String _buildEmptyLabel() {
    final parts = <String>[];
    if (_rankFilter    != null)                 parts.add('"$_rankFilter"');
    if (_armedFilter   != _ArmedFilter.all)     parts.add('"${_armedLabel(_armedFilter)}"');
    if (_downloadFilter != _DownloadFilter.all) parts.add('"${_dlLabel(_downloadFilter)}"');
    if (parts.isNotEmpty) return '${parts.join(' + ')} के लिए कोई ड्यूटी नहीं';
    return 'No assigned staff found';
  }

  Widget _tag(IconData icon, String text, {Color? color}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color ?? kSubtle),
        const SizedBox(width: 3),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color ?? kSubtle, fontSize: 11, fontWeight: FontWeight.w500))),
      ]);
}

// ══════════════════════════════════════════════════════════════════════════════
//  HELPERS
// ══════════════════════════════════════════════════════════════════════════════
Color _rankColor(String rank) {
  switch (rank.toUpperCase()) {
    case 'SP':             return const Color(0xFF6C3483);
    case 'ASP':            return const Color(0xFF1A5276);
    case 'DSP':            return const Color(0xFF0E6655);
    case 'INSPECTOR':      return const Color(0xFF1F618D);
    case 'SI':             return const Color(0xFF117A65);
    case 'ASI':            return const Color(0xFFB7950B);
    case 'HEAD CONSTABLE': return const Color(0xFFBA4A00);
    case 'CONSTABLE':      return const Color(0xFF6E2F1A);
    default:               return kPrimary;
  }
}

class _FilterChip extends StatelessWidget {
  final String label; final Color color; final IconData icon;
  final bool selected; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.color, required this.icon,
      required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? color : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : color.withOpacity(0.35),
            width: selected ? 1.5 : 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: selected ? Colors.white : color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: selected ? Colors.white : color,
            fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _RankChip extends StatelessWidget {
  final String label; final bool selected; final Color color; final VoidCallback onTap;
  const _RankChip({required this.label, required this.selected,
      required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? color : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : color.withOpacity(0.3),
            width: selected ? 1.5 : 1),
      ),
      child: Text(label, style: TextStyle(color: selected ? Colors.white : color,
          fontSize: 11, fontWeight: FontWeight.w700)),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon,
      required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 14),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white,
            fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

// ── Palette ───────────────────────────────────────────────────────────────────
const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kAccent  = Color(0xFFB8860B);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);
const kSuccess = Color(0xFF2D6A1E);
const kInfo    = Color(0xFF1A5276);