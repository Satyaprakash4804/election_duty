import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

const _rankMap = {
  'constable': 'कां0',
  'head constable': 'हो0गा0',
  'si': 'उ0नि0',
  'sub inspector': 'उ0नि0',
  'inspector': 'निरीक्षक',
  'asi': 'स0उ0नि0',
  'assistant sub inspector': 'स0उ0नि0',
  'dsp': 'उपाधीक्षक',
  'sp': 'पुलिस अधीक्षक',
  'circle officer': 'क्षेत्राधिकारी',
  'co': 'क्षेत्राधिकारी',
};
String _rh(dynamic val) =>
    _rankMap[(val ?? '').toString().toLowerCase()] ?? val?.toString() ?? '—';
String _vd(dynamic x) =>
    (x == null || x.toString().trim().isEmpty) ? '—' : x.toString();

// ─── shared PDF builder (used by both admin page and staff section) ───────────
pw.Widget buildDutyCardPdf(Map s, pw.Font font, pw.Font bold) {
  final sahyogi = (s['sahyogi'] ?? s['allStaff'] ?? s['all_staff'] ?? []) as List;
  final totalRows = sahyogi.length < 12 ? 12 : sahyogi.length;
  final zonalOfficers =
      (s['zonalOfficers'] ?? s['zonal_officers'] ?? []) as List;
  final sectorOfficers =
      (s['sectorOfficers'] ?? s['sector_officers'] ?? []) as List;
  final superOfficers =
      (s['superOfficers'] ?? s['super_officers'] ?? []) as List;

  final zonalMag = zonalOfficers.isNotEmpty ? zonalOfficers[0] : null;
  final sectorMag = sectorOfficers.isNotEmpty ? sectorOfficers[0] : null;
  final zonalPolice = superOfficers.isNotEmpty ? superOfficers[0] : null;
  final sectorPolice = sectorOfficers.length > 1
      ? sectorOfficers[1]
      : sectorOfficers.isNotEmpty
          ? sectorOfficers[0]
          : null;

  // ── RULE: never use color: + decoration: together on pw.Container ───────────
  // All grey backgrounds go inside BoxDecoration(color: ...).

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
    pw.Expanded(
      flex: 2,
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border(
            right: pw.BorderSide(width: 0.3),
            bottom: pw.BorderSide(width: 0.3),
          ),
        ),
        padding: const pw.EdgeInsets.all(1),
        child: pw.Text(
          label,
          style: pw.TextStyle(font: bold, fontSize: 4.5),
        ),
      ),
    ),
    pw.Expanded(
      flex: 3,
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(width: 0.3),
          ),
        ),
        padding: const pw.EdgeInsets.all(1),
        child: pw.Text(
          value,
          style: pw.TextStyle(font: font, fontSize: 4.5),
        ),
      ),
    ),
  ]);

  

  pw.Widget sHdr(String text, {int flex = 1, bool isLast = false}) =>
      pw.Expanded(
        flex: flex,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfColors.grey300,
            border: isLast
                ? null
                : const pw.Border(right: pw.BorderSide(width: 0.3)),
          ),
          padding: const pw.EdgeInsets.all(1),
          child: pw.Center(
              child: pw.Text(text,
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
            border: isLast
                ? null
                : const pw.Border(right: pw.BorderSide(width: 0.3)),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 0.5),
          child: pw.Text(text,
              style: pw.TextStyle(font: isBold ? bold : font, fontSize: 4.8),
              overflow: pw.TextOverflow.clip),
        ),
      );

  pw.Widget officerBlock(
          String title, String? name, String? mobile, String? rank) =>
      pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              decoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                  border: pw.Border(bottom: pw.BorderSide(width: 0.4))),
              padding: const pw.EdgeInsets.all(1),
              child: pw.Center(
                  child: pw.Text(title,
                      style: pw.TextStyle(font: bold, fontSize: 5),
                      textAlign: pw.TextAlign.center)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(2),
              child: pw.Text(
                [if (rank != null) rank, name ?? '—', if (mobile != null) mobile]
                    .join('\n'),
                style: pw.TextStyle(font: font, fontSize: 4.5),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ]);

  return pw.Container(
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── HEADER ────────────────────────────────────────────────────────────
        pw.Container(
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.8))),
          child: pw.Row(children: [
            pw.Container(
              width: 42,
              padding: const pw.EdgeInsets.all(3),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(right: pw.BorderSide(width: 0.5))),
              child: pw.Center(
                  child: pw.Text('ECI',
                      style: pw.TextStyle(font: bold, fontSize: 7))),
            ),
            pw.Expanded(
              child: pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ड्यूटी कार्ड',
                        style: pw.TextStyle(
                            font: bold,
                            fontSize: 10,
                            decoration: pw.TextDecoration.underline)),
                    pw.Text('लोकसभा सामान्य निर्वाचन–2024',
                        style: pw.TextStyle(font: bold, fontSize: 7)),
                    pw.Text(
                        'जनपद ${_vd(s['district'] ?? s['staffThana'] ?? 'बागपत')}',
                        style: pw.TextStyle(font: font, fontSize: 6.5)),
                    pw.SizedBox(height: 1),
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                          border:
                              pw.Border(top: pw.BorderSide(width: 0.5))),
                      padding: const pw.EdgeInsets.only(top: 1),
                      child: pw.Text(
                        'मतदान चरण–द्वितीय  दिनांक 26.04.2024'
                        '  प्रातः 07:00 से सांय 06:00 तक',
                        style: pw.TextStyle(font: bold, fontSize: 5.5),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.Container(
              width: 42,
              padding: const pw.EdgeInsets.all(3),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(left: pw.BorderSide(width: 0.5))),
              child: pw.Center(
                  child: pw.Text('उ0प्र0\nपुलिस',
                      style: pw.TextStyle(font: bold, fontSize: 6),
                      textAlign: pw.TextAlign.center)),
            ),
          ]),
        ),

        // ── PRIMARY OFFICER ────────────────────────────────────────────────────
        pw.Table(
          border: const pw.TableBorder(
            left: pw.BorderSide(width: 0.5),
            right: pw.BorderSide(width: 0.5),
            top: pw.BorderSide(width: 0.5),
            bottom: pw.BorderSide(width: 0.5),
            horizontalInside: pw.BorderSide(width: 0.5),
            verticalInside: pw.BorderSide(width: 0.5),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.0),
            1: pw.FlexColumnWidth(1.1),
            2: pw.FlexColumnWidth(1.8),
            3: pw.FlexColumnWidth(2.8),
            4: pw.FlexColumnWidth(1.8),
            5: pw.FlexColumnWidth(1.5),
            6: pw.FlexColumnWidth(1.3),
            7: pw.FlexColumnWidth(1.0),
            8: pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(children: [
              th('नाम अधि0/\nकर्म0 गण'),
              th('पद'),
              th('बैज नंबर'),
              th('नाम अधि0/कर्म0'),
              th('मोबाइल न0'),
              th('तैनाती'),
              th('जनपद'),
              th('स0/\nनि0'),
              th('वाहन\nसंख्या'),
            ]),
            pw.TableRow(children: [
              td(''),
              td(_rh(s['rank'] ?? s['user_rank']), center: true, isBold: true),
              td(_vd(s['pno']), center: true),
              td(_vd(s['name']), isBold: true),
              td(_vd(s['mobile']), center: true),
              td(_vd(s['staffThana'] ?? s['thana']), center: true),
              td(_vd(s['district']), center: true),
              td('सशस्त्र', center: true, fs: 4.5),
              td(
                  (s['busNo'] ?? s['bus_no']) != null &&
                          (s['busNo'] ?? s['bus_no']).toString().isNotEmpty
                      ? 'बस–${s['busNo'] ?? s['bus_no']}'
                      : '—',
                  center: true,
                  isBold: true),
            ]),
          ],
        ),

        // ── DUTY LOCATION + SAHYOGI + RIGHT PANEL ──────────────────────────────
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // LEFT: place + type
              pw.Container(
                width: 50,
                decoration: const pw.BoxDecoration(
                    border: pw.Border(
                        right: pw.BorderSide(width: 0.5),
                        bottom: pw.BorderSide(width: 0.5))),
                child: pw.Column(children: [
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                        border: pw.Border(
                            bottom: pw.BorderSide(width: 0.5))),
                    padding: const pw.EdgeInsets.all(1),
                    child: pw.Center(
                        child: pw.Text('डियूटी स्थान',
                            style:
                                pw.TextStyle(font: bold, fontSize: 5.5))),
                  ),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(2),
                      child: pw.Center(
                        child: pw.Text(
                            _vd(s['centerName'] ?? s['center_name']),
                            style: pw.TextStyle(font: bold, fontSize: 5.5),
                            textAlign: pw.TextAlign.center),
                      ),
                    ),
                  ),
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                        border: pw.Border(
                            top: pw.BorderSide(width: 0.5),
                            bottom: pw.BorderSide(width: 0.5))),
                    padding: const pw.EdgeInsets.all(1),
                    child: pw.Center(
                        child: pw.Text('डियूटी प्रकार',
                            style:
                                pw.TextStyle(font: bold, fontSize: 5.5))),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(2),
                    child: pw.Center(
                      child: pw.Text('बूथ डियूटी',
                          style: pw.TextStyle(font: bold, fontSize: 5.5)),
                    ),
                  ),
                ]),
              ),

              // CENTRE: sahyogi table
              pw.Expanded(
                child: pw.Column(children: [
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                        border: pw.Border(
                            bottom: pw.BorderSide(width: 0.5))),
                    child: pw.Row(children: [
                      sHdr('पद', flex: 1),
                      sHdr('बैज नंबर', flex: 2),
                      sHdr('नाम', flex: 3),
                      sHdr('मोबाइल न0', flex: 2),
                      sHdr('तैनाती', flex: 2),
                      sHdr('जनपद', flex: 2),
                      sHdr('स0/नि0', flex: 1, isLast: true),
                    ]),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      children: List.generate(totalRows, (i) {
                        final e = i < sahyogi.length ? sahyogi[i] : null;
                        return pw.Expanded(
                          child: pw.Container(
                            decoration: pw.BoxDecoration(
                              color: i.isEven
                                  ? PdfColors.white
                                  : PdfColors.grey100,
                              border: const pw.Border(
                                  bottom: pw.BorderSide(width: 0.3)),
                            ),
                            child: pw.Row(children: [
                              sCell(e != null ? _rh(e['user_rank']) : '0',
                                  flex: 1),
                              sCell(e != null ? _vd(e['pno']) : '0',
                                  flex: 2),
                              sCell(e != null ? _vd(e['name']) : '0',
                                  flex: 3, isBold: e != null),
                              sCell(e != null ? _vd(e['mobile']) : '0',
                                  flex: 2),
                              sCell(e != null ? _vd(e['thana']) : '0',
                                  flex: 2),
                              sCell(e != null ? _vd(e['district']) : '0',
                                  flex: 2),
                              sCell('0', flex: 1, isLast: true),
                            ]),
                          ),
                        );
                      }),
                    ),
                  ),
                ]),
              ),

              // RIGHT: bus / info panel
              pw.Container(
                width: 28,
                decoration: const pw.BoxDecoration(
                    border: pw.Border(
                        left: pw.BorderSide(width: 0.5),
                        bottom: pw.BorderSide(width: 0.5))),
                child: pw.Column(children: [
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                        border: pw.Border(
                            bottom: pw.BorderSide(width: 0.5))),
                    padding: const pw.EdgeInsets.all(1),
                    child: pw.Center(
                        child: pw.Text(
                            'बस–${_vd(s['busNo'] ?? s['bus_no'])}',
                            style:
                                pw.TextStyle(font: bold, fontSize: 5))),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Center(
                      child: pw.Text('दिनांक',
                          style: pw.TextStyle(font: bold, fontSize: 5))),
                  pw.SizedBox(height: 2),
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                        border: pw.Border(
                            top: pw.BorderSide(width: 0.5),
                            bottom: pw.BorderSide(width: 0.5))),
                    padding: const pw.EdgeInsets.all(1),
                    child: pw.Center(
                        child: pw.Text('15.2.17',
                            style: pw.TextStyle(font: font, fontSize: 5))),
                  ),
                  pw.Expanded(child: pw.SizedBox()),
                  pw.Center(
                      child: pw.Text('सीपीएम\nएफ',
                          style: pw.TextStyle(font: font, fontSize: 5),
                          textAlign: pw.TextAlign.center)),
                  pw.SizedBox(height: 3),
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                        border:
                            pw.Border(top: pw.BorderSide(width: 0.5))),
                    padding: const pw.EdgeInsets.all(1),
                    child: pw.Center(
                        child: pw.Text('1/2 सै0',
                            style:
                                pw.TextStyle(font: font, fontSize: 5))),
                  ),
                ]),
              ),
            ],
          ),
        ),

        // ── BOTTOM ROW ────────────────────────────────────────────────────────
        pw.Container(
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(width: 0.8))),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Meta
              pw.Container(
                width: 50,
                decoration: const pw.BoxDecoration(
                    border: pw.Border(right: pw.BorderSide(width: 0.5))),
                child: pw.Column(children: [
                  metaRow('म0 केंद्र सं0', '—'),
                  metaRow('बूथ सं0', '—'),
                  metaRow('थाना', _vd(s['staffThana'] ?? s['thana'])),
                  metaRow('जोन न0', _vd(s['zoneName'] ?? s['zone_name'])),
                  metaRow('सेक्टर न0',
                      _vd(s['sectorName'] ?? s['sector_name'])),
                  metaRow('वि0स0', '—'),
                  metaRow('श्रेणी', '0'),
                ]),
              ),
              // Zonal officers
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                      border:
                          pw.Border(right: pw.BorderSide(width: 0.5))),
                  child: pw.Column(children: [
                    officerBlock(
                        'जोनल मजिस्ट्रेट',
                        zonalMag?['name']?.toString(),
                        zonalMag?['mobile']?.toString(),
                        null),
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                          border: pw.Border(
                              top: pw.BorderSide(width: 0.4))),
                      child: officerBlock(
                          'जोनल पुलिस अधिकारी',
                          zonalPolice?['name']?.toString(),
                          zonalPolice?['mobile']?.toString(),
                          zonalPolice != null
                              ? _rh(zonalPolice['user_rank'])
                              : null),
                    ),
                  ]),
                ),
              ),
              // Sector officers
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                      border:
                          pw.Border(right: pw.BorderSide(width: 0.5))),
                  child: pw.Column(children: [
                    officerBlock(
                        'सैक्टर मजिस्ट्रेट',
                        sectorMag?['name']?.toString(),
                        sectorMag?['mobile']?.toString(),
                        null),
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                          border: pw.Border(
                              top: pw.BorderSide(width: 0.4))),
                      child: officerBlock(
                          'सेक्टर पुलिस अधिकारी',
                          sectorPolice?['name']?.toString(),
                          sectorPolice?['mobile']?.toString(),
                          sectorPolice != null
                              ? _rh(sectorPolice['user_rank'])
                              : null),
                    ),
                  ]),
                ),
              ),
              // SP
              pw.Container(
                width: 38,
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.SizedBox(height: 10),
                      pw.Text('पुलिस अधीक्षक',
                          style: pw.TextStyle(font: bold, fontSize: 5.5),
                          textAlign: pw.TextAlign.center),
                      pw.Text(_vd(s['district']),
                          style: pw.TextStyle(font: bold, fontSize: 5.5),
                          textAlign: pw.TextAlign.center),
                    ]),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
class DutyCardPage extends StatefulWidget {
  const DutyCardPage({super.key});
  @override
  State<DutyCardPage> createState() => _DutyCardPageState();
}

class _DutyCardPageState extends State<DutyCardPage> {
  List _all = [];
  List _filtered = [];
  Set<int> _selected = {};
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get('/admin/duties', token: token);
      setState(() {
        _all = res['data'] ?? [];
        _filtered = _all;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) showSnack(context, 'Failed to load: $e', error: true);
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _selected.clear();
      _filtered = q.isEmpty
          ? _all
          : _all
              .where((s) =>
                  '${s['name']}'.toLowerCase().contains(q) ||
                  '${s['pno']}'.toLowerCase().contains(q) ||
                  '${s['mobile']}'.toLowerCase().contains(q) ||
                  '${s['centerName']}'.toLowerCase().contains(q) ||
                  '${s['sectorName']}'.toLowerCase().contains(q) ||
                  '${s['zoneName']}'.toLowerCase().contains(q) ||
                  '${s['superZoneName']}'.toLowerCase().contains(q) ||
                  '${s['gpName']}'.toLowerCase().contains(q) ||
                  '${s['staffThana']}'.toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _print(List<Map> list) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();
    for (final s in list) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a6.landscape,
        margin: const pw.EdgeInsets.all(4),
        build: (_) => buildDutyCardPdf(s, font, bold),
      ));
    }
    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: kSurface,
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _search,
          style: const TextStyle(color: kDark, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search by PNO, name, center, zone, GP, thana...',
            hintStyle: const TextStyle(color: kSubtle, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kPrimary, width: 2)),
            isDense: true,
          ),
        ),
      ),
      if (_filtered.isNotEmpty)
        Container(
          color: kBg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Text('${_filtered.length} results',
                style: const TextStyle(color: kSubtle, fontSize: 12)),
            const Spacer(),
            if (_selected.isNotEmpty) ...[
              GestureDetector(
                onTap: () {
                  final sel = _filtered
                      .where((s) => _selected.contains(s['id'] ?? 0))
                      .map((s) => Map<String, dynamic>.from(s))
                      .toList();
                  _print(sel);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                      color: kPrimary,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.print, color: Colors.white, size: 15),
                    const SizedBox(width: 6),
                    Text('Print (${_selected.length})',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
            ],
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _filtered.length) {
                  _selected.clear();
                } else {
                  _selected = _filtered.map((s) => s['id'] as int).toSet();
                }
              }),
              style: TextButton.styleFrom(foregroundColor: kPrimary),
              child: Text(
                  _selected.length == _filtered.length
                      ? 'Deselect All'
                      : 'Select All',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      if (_loading)
        const Expanded(
            child:
                Center(child: CircularProgressIndicator(color: kPrimary)))
      else if (_filtered.isEmpty)
        Expanded(
            child: emptyState(
                'No assigned staff found', Icons.how_to_vote_outlined))
      else
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final s = _filtered[i];
              final id = s['id'] as int;
              final sel = _selected.contains(id);
              return GestureDetector(
                onTap: () => setState(
                    () => sel ? _selected.remove(id) : _selected.add(id)),
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        sel ? kPrimary.withOpacity(0.06) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: sel ? kPrimary : kBorder.withOpacity(0.4),
                        width: sel ? 1.5 : 1),
                    boxShadow: [
                      BoxShadow(
                          color: kPrimary.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    leading: GestureDetector(
                      onTap: () => setState(() =>
                          sel ? _selected.remove(id) : _selected.add(id)),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? kPrimary : kSurface,
                          border: Border.all(
                              color: sel ? kPrimary : kBorder),
                        ),
                        child: Center(
                            child: sel
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 18)
                                : Text('${i + 1}',
                                    style: const TextStyle(
                                        color: kPrimary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12))),
                      ),
                    ),
                    title: Text('${s['name']}',
                        style: const TextStyle(
                            color: kDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 3),
                          Row(children: [
                            _tag(Icons.badge_outlined, '${s['pno']}'),
                            const SizedBox(width: 8),
                            _tag(Icons.phone_outlined, '${s['mobile']}'),
                          ]),
                          const SizedBox(height: 3),
                          _tag(
                              Icons.location_on_outlined,
                              '${s['centerName']} • ${s['gpName']}',
                              color: kInfo),
                          const SizedBox(height: 2),
                          _tag(
                              Icons.layers_outlined,
                              '${s['sectorName']} › ${s['zoneName']} › ${s['superZoneName']}'),
                        ]),
                    trailing: IconButton(
                      icon: const Icon(Icons.print_outlined,
                          color: kPrimary),
                      onPressed: () =>
                          _print([Map<String, dynamic>.from(s)]),
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

  Widget _tag(IconData icon, String text, {Color? color}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color ?? kSubtle),
      const SizedBox(width: 3),
      Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color ?? kSubtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w500))),
    ]);
  }
}