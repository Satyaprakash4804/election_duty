import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFFF5F7FA);
const _kPrimary = Color(0xFF0F2B5B);
const _kGreen   = Color(0xFF186A3B);
const _kPurple  = Color(0xFF6C3483);
const _kRed     = Color(0xFFC0392B);
const _kDark    = Color(0xFF1A2332);
const _kSubtle  = Color(0xFF6B7C93);
const _kBorder  = Color(0xFFDDE3EE);
const _kAccent  = Color(0xFFFBBF24);
const _kGold    = Color(0xFFFFF8E7);
const _kCard    = Colors.white;

// ══════════════════════════════════════════════════════════════════════════════
class HierarchyReportPage extends StatefulWidget {
  const HierarchyReportPage({super.key});
  @override
  State<HierarchyReportPage> createState() => _HierarchyReportPageState();
}

class _HierarchyReportPageState extends State<HierarchyReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List _data = [];
  bool _loading = true;
  String? _error;
  String? _fSZ, _fZone, _fSector, _fGP;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) return;
      setState(() => _fSZ = _fZone = _fSector = _fGP = null);
    });
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/hierarchy/full', token: token);
      setState(() {
        _data    = res is List ? res : (res['data'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Filter helpers ────────────────────────────────────────────────────────
  List get _szList => _data;
  List get _filteredSZ => _fSZ == null ? _data
      : _data.where((s) => '${s['id']}' == _fSZ).toList();
  List get _allZones =>
      _filteredSZ.expand((s) => (s['zones'] as List? ?? [])).toList();
  List get _allSectors =>
      _allZones.expand((z) => (z['sectors'] as List? ?? [])).toList();
  List get _allGPs =>
      _allSectors.expand((s) => (s['panchayats'] as List? ?? [])).toList();

  // ── CRUD ─────────────────────────────────────────────────────────────────
  Future<void> _delete(String ep, int id, String name) async {
    final ok = await _confirm('"$name" को हटाना चाहते हैं?');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete('$ep/$id', token: token);
      _load(); _snack('हटाया गया', _kGreen);
    } catch (e) { _snack('त्रुटि: $e', _kRed); }
  }

  Future<bool?> _confirm(String msg) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text('पुष्टि करें', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('रद्द')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kRed),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('हटाएं', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));

  // ══════════════════════════════════════════════════════════════════════════
  // PRINT — Tab 1: matches images 2,3,6 exactly
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _print() async {
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();
    final doc  = pw.Document();
    final idx  = _tab.index;

    if (idx == 0) {
      // One page per super zone
      for (final sz in _filteredSZ) {
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(12),
          build: (_) => _pdfSuperZone(sz, font, bold),
        ));
      }
    } else if (idx == 1) {
      // Tab 2: matches images 4, 7, 8 — one page per super zone with all zones
      for (final sz in _filteredSZ) {
        final zones = (sz['zones'] as List? ?? [])
            .where((z) => _fZone == null || '${z['id']}' == _fZone)
            .toList();
        if (zones.isEmpty) continue;
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(10),
          build: (_) => _pdfZoneSector(sz, zones, font, bold),
        ));
      }
    } else {
      // Tab 3: matches images 5, 9 — one page per zone/sector group
      for (final sz in _filteredSZ) {
        for (final z in (sz['zones'] as List? ?? [])) {
          if (_fZone != null && '${z['id']}' != _fZone) continue;
          for (final s in (z['sectors'] as List? ?? [])) {
            if (_fSector != null && '${s['id']}' != _fSector) continue;
            final gps = (s['panchayats'] as List? ?? [])
                .where((g) => _fGP == null || '${g['id']}' == _fGP)
                .toList();
            if (gps.isEmpty) continue;
            doc.addPage(pw.MultiPage(
              pageFormat: PdfPageFormat.a4.landscape,
              margin: const pw.EdgeInsets.all(10),
              build: (_) => _pdfBoothDuty(sz, z, s, gps, font, bold),
            ));
          }
        }
      }
    }

    if (doc.document.pdfPageList.pages.isEmpty) {
      _snack('प्रिंट के लिए कोई डेटा नहीं', _kRed); return;
    }
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  // ── PDF: Tab 1 — matches images 2, 3, 6 ──────────────────────────────────
  List<pw.Widget> _pdfSuperZone(Map sz, pw.Font font, pw.Font bold) {
    final zones = sz['zones'] as List? ?? [];
    int gpTotal = 0;
    for (final z in zones) for (final s in (z['sectors'] as List? ?? []))
      gpTotal += ((s['panchayats'] as List?)?.length ?? 0);

    final thanas = <String>{};
    for (final z in zones) for (final s in (z['sectors'] as List? ?? []))
      for (final g in (s['panchayats'] as List? ?? []))
        if ((g['thana'] ?? '').toString().isNotEmpty) thanas.add(g['thana']);

    pw.Widget th(String t, {double? w, int flex = 1}) => pw.Container(
      width: w, constraints: w == null ? null : null,
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 6.5),
          textAlign: pw.TextAlign.center),
    );
    pw.Widget td(String t, {bool center = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: pw.Text(t, style: pw.TextStyle(font: font, fontSize: 6.5),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
    );

    // Build rows
    final rows = <List<String>>[];
    int globalSec = 0;
    for (int zi = 0; zi < zones.length; zi++) {
      final z = zones[zi] as Map;
      final sectors = z['sectors'] as List? ?? [];
      final zOff = z['officers'] as List? ?? [];
      final zStr = zOff.isNotEmpty
          ? zOff.map((o) => '${o['name'] ?? ''} ${o['user_rank'] ?? ''}').join(', ') : '—';
      final hq = '${z['hq_address'] ?? '—'}';
      for (final s in sectors) {
        globalSec++;
        final gps = s['panchayats'] as List? ?? [];
        final sOff = s['officers'] as List? ?? [];
        final sStr = sOff.isNotEmpty
            ? sOff.map((o) => '${o['name'] ?? ''} ${o['user_rank'] ?? ''}').join(', ') : '—';
        final gpStr = gps.map((g) => '${g['name']}').join(', ');
        final thStr = gps.map((g) => '${g['thana'] ?? ''}')
            .where((t) => t.isNotEmpty).toSet().join(', ');
        rows.add(['${zi+1}', zStr, hq, '$globalSec', sStr, '${s['name'] ?? ''}', gpStr, thStr]);
      }
      if (sectors.isEmpty) rows.add(['${zi+1}', zStr, hq, '—', '—', '—', '—', '—']);
    }

    return [
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: 'सुपर जोन–${sz['name']}  ब्लाक ${sz['block'] ?? ''}  ',
            style: pw.TextStyle(font: bold, fontSize: 12)),
        pw.TextSpan(text: '(थाना क्षेत्र–${thanas.join(', ')})  ',
            style: pw.TextStyle(font: font, fontSize: 9)),
        pw.TextSpan(text: 'कुल ग्राम पंचायत–$gpTotal',
            style: pw.TextStyle(font: bold, fontSize: 10,
                color: const PdfColor.fromInt(0xFFC0392B))),
      ])),
      pw.SizedBox(height: 5),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(22), 1: pw.FlexColumnWidth(1.8),
          2: pw.FlexColumnWidth(1.4), 3: pw.FixedColumnWidth(22),
          4: pw.FlexColumnWidth(2.2), 5: pw.FlexColumnWidth(1.4),
          6: pw.FlexColumnWidth(3.2), 7: pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(children: [
            th('सुपर\nजोन'), th('जोनल अधिकारी'), th('मुख्यालय'),
            th('सैक्टर'), th('सैक्टर पुलिस अधिकारी का नाम'),
            th('मुख्यालय'), th('सैक्टर में लगने वाले ग्राम पंचायत का नाम'),
            th('थाना'),
          ]),
          ...rows.map((r) => pw.TableRow(children: [
            td(r[0], center: true), td(r[1]), td(r[2]),
            td(r[3], center: true), td(r[4]), td(r[5]), td(r[6]), td(r[7]),
          ])),
        ],
      ),
    ];
  }

  // ── PDF: Tab 2 — matches images 4, 7, 8 ──────────────────────────────────
  // Format: super zone officer (left big cell), zone no, jonal officer, sector no,
  //         sector magistrate+police officer (full detail), GP, matdan sthal, kendra
  List<pw.Widget> _pdfZoneSector(Map sz, List zones, pw.Font font, pw.Font bold) {
    final szOff = (sz['officers'] as List? ?? []);
    final szOffStr = szOff.isNotEmpty
        ? szOff.map((o) =>
            '${o['name'] ?? ''}\n${o['user_rank'] ?? ''}\nमो: ${o['mobile'] ?? ''}').join('\n\n')
        : '—';

    pw.Widget th(String t) => pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 6),
          textAlign: pw.TextAlign.center),
    );
    pw.Widget td(String t, {bool center = false, bool isBold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(t, style: pw.TextStyle(
          font: isBold ? bold : font, fontSize: 6),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
    );

    // Header
    final widgets = <pw.Widget>[
      pw.Text('सुपर जोनल/जोनल/सैक्टर मजिस्ट्रेट एवं पुलिस अधिकारियों/बूथ ड्यूटी का विवरण  '
          'ब्लाक–${sz['block'] ?? sz['name']}',
          style: pw.TextStyle(font: bold, fontSize: 10)),
      pw.SizedBox(height: 4),
    ];

    // Build rows: for each zone, iterate sectors → GPs → centers
    final rows = <Map>[];
    int zSeq = 0;
    for (final z in zones) {
      zSeq++;
      final zOff = z['officers'] as List? ?? [];
      final zOffStr = zOff.isNotEmpty
          ? zOff.map((o) =>
              '${o['name'] ?? ''}\n${o['user_rank'] ?? ''}\nमो: ${o['mobile'] ?? ''}').join('\n\n')
          : '—';
      final sectors = z['sectors'] as List? ?? [];
      int sSeq = 0;
      for (final s in sectors) {
        sSeq++;
        final sOff = s['officers'] as List? ?? [];
        final magStr = sOff.isNotEmpty
            ? '${sOff[0]['name'] ?? ''}\n${sOff[0]['user_rank'] ?? ''}\n${sOff[0]['mobile'] ?? ''}'
            : '—';
        final polStr = sOff.length > 1
            ? '${sOff[1]['name'] ?? ''}\n${sOff[1]['user_rank'] ?? ''}\n${sOff[1]['mobile'] ?? ''}'
            : (sOff.length == 1 ? magStr : '—');

        final gps = s['panchayats'] as List? ?? [];
        if (gps.isEmpty) {
          rows.add({'zSeq': zSeq, 'z': z, 'zOff': zOffStr, 'sSeq': sSeq, 's': s,
              'mag': magStr, 'pol': polStr, 'gp': null, 'sthal': '—', 'kendra': '—',
              'firstZ': true, 'firstS': true});
        } else {
          for (int gi = 0; gi < gps.length; gi++) {
            final gp = gps[gi] as Map;
            final centers = gp['centers'] as List? ?? [];
            final sthalStr = centers.map((c) => '${c['name']}').join('\n');
            final kendraStr = centers.expand((c) => (c['kendras'] as List? ?? []))
                .map((k) => '${k['room_number']}').join('\n');
            // For kendra numbering like image
            final kendraFormatted = centers.expand((c) {
              final ks = c['kendras'] as List? ?? [];
              if (ks.isEmpty) return ['${c['name']} क0नं0–1'];
              return ks.map((k) => '${c['name']} क0नं0–${k['room_number']}');
            }).join('\n');

            rows.add({
              'zSeq': zSeq, 'z': z, 'zOff': zOffStr,
              'sSeq': sSeq, 's': s, 'mag': magStr, 'pol': polStr,
              'gp': gp, 'sthal': sthalStr, 'kendra': kendraFormatted,
              'firstZ': gi == 0, 'firstS': gi == 0,
            });
          }
        }
      }
    }

    widgets.add(pw.Table(
      border: pw.TableBorder.all(width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.6), // super zone + officer
        1: pw.FixedColumnWidth(18), // zone no
        2: pw.FlexColumnWidth(1.8), // jonal officer
        3: pw.FixedColumnWidth(18), // sector no
        4: pw.FlexColumnWidth(2.2), // sector magistrate + police
        5: pw.FlexColumnWidth(1.3), // GP
        6: pw.FlexColumnWidth(2.0), // matdan sthal
        7: pw.FlexColumnWidth(1.8), // matdan kendra
      },
      children: [
        pw.TableRow(children: [
          th('सुपर जोन व\nअधिकारी'),
          th('जोन\nसं.'),
          th('जोनल मजिस्ट्रेट/जोनल\nपुलिस अधिकारी का नाम'),
          th('सैक्टर'),
          th('सैक्टर मजिस्ट्रेट/सैक्टर पुलिस अधिकारी'),
          th('ग्राम\nपंचायत'),
          th('मतदेय स्थल'),
          th('मतदान केन्द्र'),
        ]),
        // Super zone officer spans all rows — simulate with first row only
        ...rows.asMap().entries.map((e) {
          final i = e.key; final r = e.value;
          final isFirstOverall = i == 0;
          final isFirstZ = r['firstZ'] as bool;
          final isFirstS = r['firstS'] as bool;
          final gp = r['gp'] as Map?;

          return pw.TableRow(children: [
            // Super zone officer — shown only on very first row
            isFirstOverall
                ? pw.Padding(padding: const pw.EdgeInsets.all(2),
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('सुपर जोनल\nअधिकारी',
                          style: pw.TextStyle(font: bold, fontSize: 5.5)),
                      pw.SizedBox(height: 2),
                      pw.Text(szOffStr, style: pw.TextStyle(font: font, fontSize: 5.5)),
                    ]))
                : pw.SizedBox(),
            // Zone no
            isFirstZ ? pw.Center(child: pw.Text('${r['zSeq']}',
                style: pw.TextStyle(font: bold, fontSize: 8))) : pw.SizedBox(),
            // Zonal officer
            isFirstZ ? td('${r['zOff']}') : pw.SizedBox(),
            // Sector no
            isFirstS ? pw.Center(child: pw.Text('${r['sSeq']}',
                style: pw.TextStyle(font: bold, fontSize: 7))) : pw.SizedBox(),
            // Sector mag + police
            isFirstS ? pw.Padding(padding: const pw.EdgeInsets.all(2),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('${r['mag']}', style: pw.TextStyle(font: font, fontSize: 5.5)),
                  if ((r['mag'] as String) != (r['pol'] as String)) ...[
                    pw.SizedBox(height: 3),
                    pw.Text('${r['pol']}', style: pw.TextStyle(font: font, fontSize: 5.5)),
                  ],
                ])) : pw.SizedBox(),
            // GP
            td('${gp?['name'] ?? '—'}'),
            // Sthal
            td('${r['sthal']}'),
            // Kendra
            td('${r['kendra']}'),
          ]);
        }),
      ],
    ));

    return widgets;
  }

  // ── PDF: Tab 3 — matches images 5, 9 ─────────────────────────────────────
  List<pw.Widget> _pdfBoothDuty(Map sz, Map z, Map s, List gps,
      pw.Font font, pw.Font bold) {
    pw.Widget th(String t) => pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 6),
          textAlign: pw.TextAlign.center),
    );
    pw.Widget td(String t, {bool center = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(t, style: pw.TextStyle(font: font, fontSize: 6),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
    );

    // Collect all rows across all GPs
    final rows = <Map>[];
    int sthalNo = 1, kendraG = 1;
    for (final gp in gps) {
      final centers = gp['centers'] as List? ?? [];
      for (final c in centers) {
        final kendras = c['kendras'] as List? ?? [];
        final duty    = c['duty_officers'] as List? ?? [];
        final dStr    = duty.map((d) =>
            'का.${d['pno'] ?? ''} ${d['name'] ?? ''} ${d['user_rank'] ?? ''}').join('\n');
        final mobStr  = duty.map((d) => '${d['mobile'] ?? ''}')
            .where((m) => m.isNotEmpty).join('\n');
        final busStr  = '${c['bus_no'] ?? '—'}';

        if (kendras.isEmpty) {
          rows.add({
            'gp': gp, 'c': c, 'k': null, 'kNo': kendraG,
            'sNo': sthalNo, 'sthalName': '${c['name']} क0नं0–1',
            'duty': dStr, 'mob': mobStr, 'bus': busStr, 'first': true,
          });
          sthalNo++; kendraG++;
        } else {
          for (int ki = 0; ki < kendras.length; ki++) {
            rows.add({
              'gp': gp, 'c': c, 'k': kendras[ki], 'kNo': kendraG,
              'sNo': ki == 0 ? sthalNo : null,
              'sthalName': '${c['name']} क0नं0–${kendras[ki]['room_number']}',
              'duty': ki == 0 ? dStr : '', 'mob': ki == 0 ? mobStr : '',
              'bus': ki == 0 ? busStr : '', 'first': ki == 0,
            });
            kendraG++;
          }
          sthalNo++;
        }
      }
    }

    int totalKendra = rows.length;
    int totalSthal  = rows.where((r) => r['first'] == true).length;

    final titleGP = gps.length == 1 ? 'ग्राम पंचायत: ${(gps[0] as Map)['name']}' : '';

    return [
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: 'बूथ ड्यूटी – ब्लाक ${sz['block'] ?? sz['name']}  ',
            style: pw.TextStyle(font: bold, fontSize: 11)),
        pw.TextSpan(text: 'मतदान दिनांकः ....../......./2026',
            style: pw.TextStyle(font: font, fontSize: 9)),
      ])),
      pw.SizedBox(height: 2),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('मतदान केन्द्र–$totalKendra  |  मतदेय स्थल–$totalSthal',
            style: pw.TextStyle(font: bold, fontSize: 8)),
        if (titleGP.isNotEmpty)
          pw.Text(titleGP, style: pw.TextStyle(font: font, fontSize: 8)),
        pw.Text('सैक्टर: ${s['name']}  |  जोन: ${z['name']}',
            style: pw.TextStyle(font: font, fontSize: 8)),
      ]),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(width: 0.4),
        columnWidths: const {
          0: pw.FixedColumnWidth(22),  // kendra serial
          1: pw.FlexColumnWidth(2.0),  // center name + type
          2: pw.FixedColumnWidth(20),  // matday no
          3: pw.FlexColumnWidth(1.8),  // sthal name
          4: pw.FixedColumnWidth(26),  // zone
          5: pw.FixedColumnWidth(26),  // sector
          6: pw.FlexColumnWidth(1.0),  // thana
          7: pw.FlexColumnWidth(2.5),  // duty police
          8: pw.FlexColumnWidth(1.3),  // mobile
          9: pw.FixedColumnWidth(22),  // bus
        },
        children: [
          pw.TableRow(children: [
            th('मतदान\nकेन्द्र\nकी\nसंख्या'),
            th('मतदान केन्द्र\nका नाम'),
            th('मतदेय\nसं.'),
            th('मतदान स्थल\nका नाम'),
            th('जोन\nसंख्या'),
            th('सैक्टर\nसंख्या'),
            th('थाना'),
            th('ड्यूटी पर लगाया\nपुलिस का नाम'),
            th('मोबाईल\nनम्बर'),
            th('बस\nनं.'),
          ]),
          ...rows.map((r) {
            final c   = r['c'] as Map;
            final gp  = r['gp'] as Map;
            final first = r['first'] as bool? ?? true;
            final typeC = c['center_type'] ?? 'C';
            return pw.TableRow(children: [
              pw.Center(child: pw.Text('${r['kNo']}',
                  style: pw.TextStyle(font: bold, fontSize: 7))),
              pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('${r['sthalName']}', style: pw.TextStyle(font: font, fontSize: 6)),
                pw.Text(typeC, style: pw.TextStyle(font: bold, fontSize: 6)),
              ])),
              first && r['sNo'] != null
                  ? pw.Center(child: pw.Text('${r['sNo']}',
                      style: pw.TextStyle(font: bold, fontSize: 7)))
                  : pw.SizedBox(),
              first ? td('${c['name']}') : pw.SizedBox(),
              td('${z['name']}', center: true),
              td('${s['name']}', center: true),
              td('${c['thana'] ?? gp['thana'] ?? '—'}'),
              td('${r['duty']}'),
              td('${r['mob']}'),
              td('${r['bus']}', center: true),
            ]);
          }),
        ],
      ),
    ];
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  void _dlgSZ({Map? sz}) => _openDlg(
    title: sz != null ? 'सुपर जोन संपादित करें' : 'सुपर जोन जोड़ें',
    color: _kPrimary, icon: Icons.layers_outlined,
    fields: {'name': 'नाम *', 'district': 'जिला', 'block': 'ब्लॉक'},
    initial: sz == null ? null : Map<String, dynamic>.from(sz),
    onSave: (data) async {
      final t = await AuthService.getToken();
      if (sz != null) await ApiService.put('/admin/hierarchy/super-zone/${sz['id']}', data, token: t);
      else await ApiService.post('/admin/super-zones', data, token: t);
      _load();
    },
  );

  void _dlgZone({Map? z, Map? sz}) => _openDlg(
    title: z != null ? 'जोन संपादित करें' : 'जोन जोड़ें – ${sz?['name'] ?? ''}',
    color: _kGreen, icon: Icons.map_outlined,
    fields: {'name': 'जोन का नाम *', 'hqAddress': 'मुख्यालय पता'},
    initial: z != null ? {'name': z['name'], 'hqAddress': z['hq_address'] ?? z['hqAddress']} : null,
    onSave: (data) async {
      final t = await AuthService.getToken();
      if (z != null) await ApiService.put('/admin/zones/${z['id']}', data, token: t);
      else await ApiService.post('/admin/super-zones/${sz!['id']}/zones', data, token: t);
      _load();
    },
  );

  void _dlgSector({Map? s, Map? z}) => _openDlg(
    title: s != null ? 'सैक्टर संपादित करें' : 'सैक्टर जोड़ें – ${z?['name'] ?? ''}',
    color: _kGreen, icon: Icons.grid_view_outlined,
    fields: {'name': 'सैक्टर का नाम *'},
    initial: s == null ? null : Map<String, dynamic>.from(s),
    onSave: (data) async {
      final t = await AuthService.getToken();
      if (s != null) await ApiService.put('/admin/hierarchy/sector/${s['id']}', data, token: t);
      else await ApiService.post('/admin/zones/${z!['id']}/sectors', data, token: t);
      _load();
    },
  );

  void _dlgGP({Map? s}) => _openDlg(
    title: 'ग्राम पंचायत जोड़ें – ${s?['name'] ?? ''}',
    color: _kPurple, icon: Icons.account_balance_outlined,
    fields: {'name': 'ग्राम पंचायत का नाम *', 'address': 'पता'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/sectors/${s!['id']}/gram-panchayats', data, token: t);
      _load();
    },
  );

  void _dlgCenter({Map? c, int? gpId}) {
    final nameC    = TextEditingController(text: c?['name'] ?? '');
    final addrC    = TextEditingController(text: c?['address'] ?? '');
    final thanaC   = TextEditingController(text: c?['thana'] ?? '');
    final busC     = TextEditingController(text: c?['bus_no'] ?? c?['busNo'] ?? '');
    String type    = c?['center_type'] ?? c?['centerType'] ?? 'C';
    final fk       = GlobalKey<FormState>();
    showDialog(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(c != null ? 'मतदेय स्थल संपादित करें' : 'मतदेय स्थल जोड़ें',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        content: SizedBox(width: 360, child: Form(key: fk, child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            _tf(nameC, 'नाम *', req: true),
            const SizedBox(height: 8), _tf(addrC, 'पता'),
            const SizedBox(height: 8), _tf(thanaC, 'थाना'),
            const SizedBox(height: 10),
            Row(children: [
              const Text('प्रकार:', style: TextStyle(fontSize: 12, color: _kSubtle)),
              const SizedBox(width: 8),
              ...['A', 'B', 'C'].map((t) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(t), selected: type == t,
                  selectedColor: t == 'A' ? Colors.red[100] : t == 'B' ? Colors.orange[100] : Colors.blue[100],
                  onSelected: (_) => ss(() => type = t)),
              )),
            ]),
            const SizedBox(height: 8), _tf(busC, 'बस संख्या'),
          ],
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kPurple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              if (!fk.currentState!.validate()) return;
              Navigator.pop(ctx);
              final data = {'name': nameC.text.trim(), 'address': addrC.text.trim(),
                  'thana': thanaC.text.trim(), 'centerType': type, 'center_type': type,
                  'busNo': busC.text.trim(), 'bus_no': busC.text.trim()};
              final tok = await AuthService.getToken();
              if (c != null) await ApiService.put('/admin/hierarchy/sthal/${c['id']}', data, token: tok);
              else await ApiService.post('/admin/gram-panchayats/$gpId/centers', data, token: tok);
              _load();
            },
            child: const Text('सहेजें', style: TextStyle(color: Colors.white)),
          ),
        ],
      )),
    );
  }

  void _dlgKendra(Map c) => _openDlg(
    title: 'कक्ष जोड़ें – ${c['name']}', color: _kPurple, icon: Icons.meeting_room_outlined,
    fields: {'roomNumber': 'कक्ष संख्या *'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/centers/${c['id']}/rooms', data, token: t);
      _load();
    },
  );

  void _dlgStaff(Map center) async {
    final tok = await AuthService.getToken();
    final sRes = await ApiService.get('/admin/staff', token: tok);
    final all = (sRes['data'] ?? []) as List;
    final unassigned = all.where((s) => s['isAssigned'] != true).toList();
    final assigned = (center['duty_officers'] as List? ?? []);
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => _StaffDlg(
      center: center, unassigned: unassigned, assigned: assigned,
      onAssign: (id, bus) async {
        final t = await AuthService.getToken();
        await ApiService.post('/admin/duties',
            {'staffId': id, 'centerId': center['id'], 'busNo': bus}, token: t);
        _load();
      },
      onRemove: (id) async {
        final t = await AuthService.getToken();
        await ApiService.delete('/admin/duties/$id', token: t);
        _load();
      },
    ));
  }

  void _openDlg({
    required String title, required Color color, required IconData icon,
    required Map<String, String> fields, Map<String, dynamic>? initial,
    required Future<void> Function(Map) onSave,
  }) {
    final ctrls = fields.map((k, v) =>
        MapEntry(k, TextEditingController(text: '${initial?[k] ?? ''}')));
    final fk = GlobalKey<FormState>();
    bool saving = false;
    showDialog(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
        ]),
        content: SizedBox(width: 340, child: Form(key: fk, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: fields.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _tf(ctrls[e.key]!, e.value, req: e.value.endsWith('*')),
          )).toList(),
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: saving ? null : () async {
              if (!fk.currentState!.validate()) return;
              ss(() => saving = true);
              try {
                await onSave(ctrls.map((k, c) => MapEntry(k, c.text.trim())));
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('सहेजा गया', _kGreen);
              } catch (e) { _snack('त्रुटि: $e', _kRed); }
              finally { if (ctx.mounted) ss(() => saving = false); }
            },
            child: saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('सहेजें', style: TextStyle(color: Colors.white)),
          ),
        ],
      )),
    );
  }

  Widget _tf(TextEditingController c, String label, {bool req = false}) =>
      TextFormField(controller: c,
        decoration: InputDecoration(labelText: label, isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kPrimary, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        validator: req ? (v) => (v?.trim().isEmpty ?? true)
            ? '${label.replaceAll(' *', '')} आवश्यक' : null : null);

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _kBg,
    appBar: AppBar(
      backgroundColor: _kPrimary, elevation: 0,
      leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context)),
      title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('प्रशासनिक पदानुक्रम',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        Text('Administrative Hierarchy Report',
            style: TextStyle(color: Colors.white54, fontSize: 10)),
      ]),
      actions: [
        IconButton(icon: const Icon(Icons.print_outlined, color: Colors.white),
            onPressed: _print, tooltip: 'प्रिंट'),
        IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            onPressed: () => _dlgSZ(), tooltip: 'सुपर जोन जोड़ें'),
        IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load),
      ],
      bottom: TabBar(
        controller: _tab,
        indicatorColor: _kAccent, indicatorWeight: 3,
        labelColor: Colors.white, unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        tabs: const [
          Tab(text: 'सुपर जोन', icon: Icon(Icons.layers_outlined, size: 15)),
          Tab(text: 'जोन/सैक्टर', icon: Icon(Icons.map_outlined, size: 15)),
          Tab(text: 'बूथ ड्यूटी', icon: Icon(Icons.how_to_vote_outlined, size: 15)),
        ],
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: _kPrimary))
        : _error != null
            ? _ErrView(error: _error!, onRetry: _load)
            : Column(children: [
                _filterBar(),
                Expanded(child: TabBarView(controller: _tab, children: [
                  _tab1(), _tab2(), _tab3(),
                ])),
              ]),
  );

  Widget _filterBar() {
    final idx = _tab.index;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: Row(children: [
          _Drop(label: 'सुपर जोन', value: _fSZ, hint: 'सभी',
              items: _szList.map((s) => _DI('${s['id']}', '${s['name']}')).toList(),
              onChanged: (v) => setState(() { _fSZ = v; _fZone = _fSector = _fGP = null; })),
          if (idx >= 1) ...[
            const SizedBox(width: 8),
            _Drop(label: 'जोन', value: _fZone, hint: 'सभी',
                items: _allZones.map((z) => _DI('${z['id']}', '${z['name']}')).toList(),
                onChanged: (v) => setState(() { _fZone = v; _fSector = _fGP = null; })),
          ],
          if (idx >= 2) ...[
            const SizedBox(width: 8),
            _Drop(label: 'सैक्टर', value: _fSector, hint: 'सभी',
                items: _allSectors.map((s) => _DI('${s['id']}', '${s['name']}')).toList(),
                onChanged: (v) => setState(() { _fSector = v; _fGP = null; })),
            const SizedBox(width: 8),
            _Drop(label: 'ग्राम पंचायत', value: _fGP, hint: 'सभी',
                items: _allGPs.map((g) => _DI('${g['id']}', '${g['name']}')).toList(),
                onChanged: (v) => setState(() => _fGP = v)),
          ],
        ]),
      ),
    );
  }

  // ══ TAB 1 ════════════════════════════════════════════════════════════════
  Widget _tab1() {
    if (_filteredSZ.isEmpty) return const _Empty(text: 'कोई सुपर जोन नहीं');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: _filteredSZ.length,
      itemBuilder: (_, i) {
        final sz = _filteredSZ[i] as Map;
        return _SZCard(
          sz: sz,
          onEdit: () => _dlgSZ(sz: sz),
          onDelete: () => _delete('/admin/hierarchy/super-zone', sz['id'], '${sz['name']}'),
          onAddZone: () => _dlgZone(sz: sz),
          onEditZone: (z) => _dlgZone(z: z, sz: sz),
          onDeleteZone: (z) => _delete('/admin/zones', z['id'], '${z['name']}'),
          onAddSector: (z) => _dlgSector(z: z),
        );
      },
    );
  }

  // ══ TAB 2 ════════════════════════════════════════════════════════════════
  Widget _tab2() {
    final items = <Map>[];
    for (final sz in _filteredSZ) {
      for (final z in (sz['zones'] as List? ?? [])) {
        if (_fZone != null && '${z['id']}' != _fZone) continue;
        items.add({'sz': sz, 'z': z});
      }
    }
    if (items.isEmpty) return const _Empty(text: 'कोई जोन नहीं मिला');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: items.length,
      itemBuilder: (_, i) => _ZoneCard(
        sz: items[i]['sz'], z: items[i]['z'],
        onEdit: () => _dlgZone(z: items[i]['z'], sz: items[i]['sz']),
        onDelete: () => _delete('/admin/zones', items[i]['z']['id'], '${items[i]['z']['name']}'),
        onAddSector: () => _dlgSector(z: items[i]['z']),
        onEditSector: (s) => _dlgSector(s: s),
        onDeleteSector: (s) => _delete('/admin/hierarchy/sector', s['id'], '${s['name']}'),
        onAddGP: (s) => _dlgGP(s: s),
      ),
    );
  }

  // ══ TAB 3 ════════════════════════════════════════════════════════════════
  Widget _tab3() {
    final items = <Map>[];
    for (final sz in _filteredSZ) {
      for (final z in (sz['zones'] as List? ?? [])) {
        if (_fZone != null && '${z['id']}' != _fZone) continue;
        for (final s in (z['sectors'] as List? ?? [])) {
          if (_fSector != null && '${s['id']}' != _fSector) continue;
          for (final gp in (s['panchayats'] as List? ?? [])) {
            if (_fGP != null && '${gp['id']}' != _fGP) continue;
            items.add({'sz': sz, 'z': z, 's': s, 'gp': gp});
          }
        }
      }
    }
    if (items.isEmpty) return const _Empty(text: 'कोई ग्राम पंचायत नहीं मिली');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: items.length,
      itemBuilder: (_, i) => _GPCard(
        sz: items[i]['sz'], z: items[i]['z'],
        s: items[i]['s'], gp: items[i]['gp'],
        onAddCenter: () => _dlgCenter(gpId: items[i]['gp']['id']),
        onEditCenter: (c) => _dlgCenter(c: c),
        onDeleteCenter: (c) => _delete('/admin/hierarchy/sthal', c['id'], '${c['name']}'),
        onAddKendra: (c) => _dlgKendra(c),
        onDeleteKendra: (k) => _delete('/admin/rooms', k['id'], '${k['room_number']}'),
        onManageStaff: (c) => _dlgStaff(c),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — SUPER ZONE CARD (responsive, no horizontal overflow)
// ══════════════════════════════════════════════════════════════════════════════
class _SZCard extends StatelessWidget {
  final Map sz;
  final VoidCallback onEdit, onDelete, onAddZone;
  final void Function(Map) onEditZone, onDeleteZone, onAddSector;
  const _SZCard({required this.sz, required this.onEdit, required this.onDelete,
      required this.onAddZone, required this.onEditZone, required this.onDeleteZone,
      required this.onAddSector});

  @override
  Widget build(BuildContext context) {
    final zones = sz['zones'] as List? ?? [];
    int gpTotal = 0, sTotal = 0;
    for (final z in zones) {
      final secs = z['sectors'] as List? ?? [];
      sTotal += secs.length;
      for (final s in secs) gpTotal += ((s['panchayats'] as List?)?.length ?? 0);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0F2B5B), Color(0xFF1E3F80)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('सुपर जोन – ${sz['name']}',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                if ((sz['block'] ?? '').toString().isNotEmpty)
                  Text('ब्लाक: ${sz['block']}  |  जिला: ${sz['district'] ?? ''}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              _Btn(icon: Icons.add, color: _kAccent, onTap: onAddZone, tip: 'जोन जोड़ें'),
              _Btn(icon: Icons.edit_outlined, color: _kAccent, onTap: onEdit),
              _Btn(icon: Icons.delete_outline, color: Colors.red[300]!, onTap: onDelete),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              _Chip('${zones.length} जोन', Colors.blue[300]!),
              _Chip('$sTotal सैक्टर', Colors.green[300]!),
              _Chip('$gpTotal ग्राम पंचायत', Colors.orange[300]!),
            ]),
          ]),
        ),
        // Officers strip
        if ((sz['officers'] as List?)?.isNotEmpty == true)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            color: _kGold,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('क्षेत्र अधिकारी:', style: TextStyle(
                  color: _kSubtle, fontSize: 10, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ...(sz['officers'] as List).map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  const Icon(Icons.person_pin_outlined, size: 12, color: _kPrimary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    '${o['name'] ?? ''}  ${o['user_rank'] ?? ''}'
                    '${(o['mobile'] ?? '').toString().isNotEmpty ? '  मो: ${o['mobile']}' : ''}',
                    style: const TextStyle(color: _kDark, fontSize: 11))),
                ]),
              )),
            ]),
          ),
        // Zones list — each zone is an expandable tile
        ...zones.asMap().entries.map((entry) {
          final zi = entry.key; final z = entry.value as Map;
          final sectors = z['sectors'] as List? ?? [];
          final zOff = z['officers'] as List? ?? [];
          return _ZoneTile(
            zi: zi + 1, z: z, sectors: sectors, zOff: zOff,
            onEditZone: () => onEditZone(z),
            onDeleteZone: () => onDeleteZone(z),
            onAddSector: () => onAddSector(z),
          );
        }),
      ]),
    );
  }
}

class _ZoneTile extends StatelessWidget {
  final int zi; final Map z; final List sectors, zOff;
  final VoidCallback onEditZone, onDeleteZone, onAddSector;
  const _ZoneTile({required this.zi, required this.z, required this.sectors,
      required this.zOff, required this.onEditZone, required this.onDeleteZone,
      required this.onAddSector});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      childrenPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 14, backgroundColor: _kPrimary.withOpacity(0.12),
        child: Text('$zi', style: const TextStyle(
            color: _kPrimary, fontWeight: FontWeight.w900, fontSize: 12)),
      ),
      title: Text(z['name'] ?? '—',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kDark)),
      subtitle: Text(
        'मुख्यालय: ${z['hq_address'] ?? '—'}  |  ${sectors.length} सैक्टर',
        style: const TextStyle(fontSize: 10, color: _kSubtle)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _Btn(icon: Icons.add, color: _kGreen, onTap: onAddSector, tip: 'सैक्टर जोड़ें', size: 16),
        _Btn(icon: Icons.edit_outlined, color: _kGreen, onTap: onEditZone, size: 16),
        _Btn(icon: Icons.delete_outline, color: _kRed, onTap: onDeleteZone, size: 16),
        const Icon(Icons.expand_more, color: _kSubtle, size: 18),
      ]),
      children: [
        // Zonal officers
        if (zOff.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('जोनल अधिकारी:',
                  style: TextStyle(color: _kGreen, fontSize: 10, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ...zOff.map((o) => Text(
                '• ${o['name'] ?? ''}  ${o['user_rank'] ?? ''}  PNO: ${o['pno'] ?? ''}  मो: ${o['mobile'] ?? ''}',
                style: const TextStyle(color: _kDark, fontSize: 11))),
            ]),
          ),
        // Sectors
        if (sectors.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
              child: Text('कोई सैक्टर नहीं', style: TextStyle(color: _kSubtle, fontSize: 12)))
        else
          ...sectors.asMap().entries.map((e) {
            final si = e.key; final s = e.value as Map;
            final gps = s['panchayats'] as List? ?? [];
            final sOff = s['officers'] as List? ?? [];
            final gpNames = gps.map((g) => '${g['name']}').join(' • ');
            return Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              decoration: BoxDecoration(
                  border: Border.all(color: _kBorder),
                  borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: CircleAvatar(
                  radius: 12, backgroundColor: _kGreen.withOpacity(0.12),
                  child: Text('${si + 1}', style: const TextStyle(
                      color: _kGreen, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
                title: Text('${s['name'] ?? ''}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (sOff.isNotEmpty)
                    Text(sOff.map((o) => '${o['name'] ?? ''} ${o['user_rank'] ?? ''}').join(', '),
                        style: const TextStyle(fontSize: 10, color: _kGreen)),
                  if (gpNames.isNotEmpty)
                    Text('GP: $gpNames',
                        style: const TextStyle(fontSize: 9.5, color: _kSubtle),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
                trailing: Text('${gps.length} GP',
                    style: const TextStyle(color: _kPrimary, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            );
          }),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — ZONE/SECTOR CARD (responsive)
// ══════════════════════════════════════════════════════════════════════════════
class _ZoneCard extends StatelessWidget {
  final Map sz, z;
  final VoidCallback onEdit, onDelete, onAddSector;
  final void Function(Map) onEditSector, onAddGP;
  final Future<void> Function(Map) onDeleteSector;
  const _ZoneCard({required this.sz, required this.z, required this.onEdit,
      required this.onDelete, required this.onAddSector, required this.onEditSector,
      required this.onDeleteSector, required this.onAddGP});

  @override
  Widget build(BuildContext context) {
    final sectors = z['sectors'] as List? ?? [];
    final zOff = z['officers'] as List? ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF186A3B), Color(0xFF239B56)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('जोन: ${z['name']}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                Text('सुपर जोन: ${sz['name']}  |  ब्लॉक: ${sz['block'] ?? ''}',
                    style: const TextStyle(color: Colors.white60, fontSize: 10)),
              ])),
              _Btn(icon: Icons.add, color: _kAccent, onTap: onAddSector, tip: 'सैक्टर जोड़ें'),
              _Btn(icon: Icons.edit_outlined, color: _kAccent, onTap: onEdit),
              _Btn(icon: Icons.delete_outline, color: Colors.red[300]!, onTap: onDelete),
            ]),
            if (zOff.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...zOff.map((o) => Text(
                '• ${o['name'] ?? ''}  ${o['user_rank'] ?? ''}  मो: ${o['mobile'] ?? ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 10))),
            ],
          ]),
        ),
        if (sectors.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
              child: Text('कोई सैक्टर नहीं', style: TextStyle(color: _kSubtle, fontSize: 12)))
        else
          ...sectors.asMap().entries.map((e) {
            final si = e.key; final s = e.value as Map;
            final gps = s['panchayats'] as List? ?? [];
            final sOff = s['officers'] as List? ?? [];
            return ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              childrenPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 13, backgroundColor: _kGreen.withOpacity(0.12),
                child: Text('${si + 1}', style: const TextStyle(
                    color: _kGreen, fontWeight: FontWeight.w900, fontSize: 11)),
              ),
              title: Text('${s['name']}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kDark)),
              subtitle: sOff.isNotEmpty
                  ? Text(sOff.map((o) => '${o['name'] ?? ''} ${o['user_rank'] ?? ''}').join(' | '),
                      style: const TextStyle(fontSize: 10, color: _kGreen))
                  : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                _Btn(icon: Icons.add, color: _kGreen, onTap: () => onAddGP(s), tip: 'GP जोड़ें', size: 16),
                _Btn(icon: Icons.edit_outlined, color: _kGreen, onTap: () => onEditSector(s), size: 16),
                _Btn(icon: Icons.delete_outline, color: _kRed, onTap: () => onDeleteSector(s), size: 16),
                const Icon(Icons.expand_more, color: _kSubtle, size: 18),
              ]),
              children: gps.isEmpty
                  ? [const Padding(padding: EdgeInsets.all(12),
                      child: Text('कोई ग्राम पंचायत नहीं', style: TextStyle(color: _kSubtle, fontSize: 11)))]
                  : gps.map((gp) {
                      final gpm = gp as Map;
                      final centers = gpm['centers'] as List? ?? [];
                      final sthalStr = centers.map((c) => '${c['name']}').join(', ');
                      final kendraCount = centers.fold<int>(0, (a, c) {
                        final k = c['kendras'] as List? ?? [];
                        return a + (k.isEmpty ? 1 : k.length);
                      });
                      return Container(
                        margin: const EdgeInsets.fromLTRB(40, 0, 14, 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF8FFF9),
                            border: Border.all(color: _kBorder),
                            borderRadius: BorderRadius.circular(8)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.account_balance_outlined, size: 12, color: _kGreen),
                            const SizedBox(width: 5),
                            Expanded(child: Text('${gpm['name']}', style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700, color: _kDark))),
                            Text('$kendraCount केन्द्र', style: const TextStyle(
                                fontSize: 10, color: _kGreen, fontWeight: FontWeight.w700)),
                          ]),
                          if (sthalStr.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(sthalStr, style: const TextStyle(fontSize: 10, color: _kSubtle),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ]),
                      );
                    }).toList(),
            );
          }),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 — GP/BOOTH CARD (responsive)
// ══════════════════════════════════════════════════════════════════════════════
class _GPCard extends StatelessWidget {
  final Map sz, z, s, gp;
  final VoidCallback onAddCenter;
  final void Function(Map) onEditCenter, onAddKendra, onManageStaff;
  final Future<void> Function(Map) onDeleteCenter, onDeleteKendra;
  const _GPCard({required this.sz, required this.z, required this.s, required this.gp,
      required this.onAddCenter, required this.onEditCenter, required this.onDeleteCenter,
      required this.onAddKendra, required this.onDeleteKendra, required this.onManageStaff});

  @override
  Widget build(BuildContext context) {
    final centers = gp['centers'] as List? ?? [];
    int kendraTotal = 0;
    for (final c in centers) {
      final k = c['kendras'] as List? ?? [];
      kendraTotal += k.isEmpty ? 1 : k.length;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF6C3483), Color(0xFF8E44AD)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${gp['name']}', style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                Wrap(spacing: 8, children: [
                  Text('सैक्टर: ${s['name']}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                  Text('जोन: ${z['name']}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                  Text('ब्लॉक: ${sz['block'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('${centers.length} स्थल  |  $kendraTotal केन्द्र',
                        style: const TextStyle(color: _kAccent, fontSize: 10, fontWeight: FontWeight.w700))),
                const SizedBox(height: 4),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.15), elevation: 0,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                  icon: const Icon(Icons.add, size: 13),
                  label: const Text('स्थल जोड़ें', style: TextStyle(fontSize: 10)),
                  onPressed: onAddCenter,
                ),
              ]),
            ]),
          ]),
        ),
        if (centers.isEmpty)
          const Padding(padding: EdgeInsets.all(20),
              child: Text('कोई मतदेय स्थल नहीं', style: TextStyle(color: _kSubtle)))
        else
          ...centers.asMap().entries.map((e) {
            final ci = e.key; final c = e.value as Map;
            final kendras = c['kendras'] as List? ?? [];
            final duty = c['duty_officers'] as List? ?? [];
            final type = c['center_type'] ?? 'C';
            final typeColor = type == 'A' ? _kRed : type == 'B' ? const Color(0xFFE67E22) : _kPrimary;

            return Container(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              decoration: BoxDecoration(
                  border: Border.all(color: _kBorder),
                  borderRadius: BorderRadius.circular(10)),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                childrenPadding: EdgeInsets.zero,
                leading: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                    radius: 13, backgroundColor: _kPurple.withOpacity(0.1),
                    child: Text('${ci + 1}', style: const TextStyle(
                        color: _kPurple, fontSize: 11, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: typeColor.withOpacity(0.4))),
                    child: Text(type, style: TextStyle(
                        color: typeColor, fontSize: 10, fontWeight: FontWeight.w800))),
                ]),
                title: Text('${c['name']}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kDark)),
                subtitle: Text(
                  '${kendras.length} कक्ष  •  ${duty.length} स्टाफ  •  थाना: ${c['thana'] ?? '—'}',
                  style: const TextStyle(fontSize: 10, color: _kSubtle)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _Btn(icon: Icons.people_alt_outlined, color: _kGreen, onTap: () => onManageStaff(c), tip: 'स्टाफ', size: 16),
                  _Btn(icon: Icons.add_box_outlined, color: _kPrimary, onTap: () => onAddKendra(c), tip: 'कक्ष', size: 16),
                  _Btn(icon: Icons.edit_outlined, color: _kPurple, onTap: () => onEditCenter(c), size: 16),
                  _Btn(icon: Icons.delete_outline, color: _kRed, onTap: () => onDeleteCenter(c), size: 16),
                  const Icon(Icons.expand_more, color: _kSubtle, size: 16),
                ]),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Duty staff
                      if (duty.isNotEmpty) ...[
                        const Text('ड्यूटी स्टाफ:', style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700, color: _kGreen)),
                        const SizedBox(height: 4),
                        ...duty.map((d) => Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF0FFF4),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _kGreen.withOpacity(0.3))),
                          child: Row(children: [
                            Expanded(child: Text(
                              '${d['name'] ?? ''}  PNO: ${d['pno'] ?? ''}  ${d['user_rank'] ?? ''}  मो: ${d['mobile'] ?? ''}',
                              style: const TextStyle(fontSize: 10, color: _kDark))),
                          ]),
                        )),
                        const SizedBox(height: 6),
                      ],
                      // Rooms/kendras
                      if (kendras.isNotEmpty) ...[
                        const Text('मतदान केन्द्र (कक्ष):', style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700, color: _kPurple)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 4, children: kendras.map((k) {
                          final km = k as Map;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: _kPurple.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _kPurple.withOpacity(0.3))),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('कक्ष ${km['room_number']}',
                                  style: const TextStyle(fontSize: 10, color: _kPurple, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => onDeleteKendra(km),
                                child: const Icon(Icons.remove_circle_outline, size: 14, color: _kRed)),
                            ]),
                          );
                        }).toList()),
                      ],
                    ]),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STAFF DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class _StaffDlg extends StatefulWidget {
  final Map center; final List unassigned, assigned;
  final Future<void> Function(int, String) onAssign;
  final Future<void> Function(int) onRemove;
  const _StaffDlg({required this.center, required this.unassigned,
      required this.assigned, required this.onAssign, required this.onRemove});
  @override State<_StaffDlg> createState() => _StaffDlgState();
}
class _StaffDlgState extends State<_StaffDlg> {
  final _busC = TextEditingController();
  final _srC  = TextEditingController();
  List _filtered = []; int? _selId;

  @override
  void initState() {
    super.initState();
    _filtered = widget.unassigned;
    _busC.text = '${widget.center['bus_no'] ?? ''}';
  }

  void _filter(String q) => setState(() {
    _filtered = q.isEmpty ? widget.unassigned
        : widget.unassigned.where((s) =>
            '${s['name']}'.toLowerCase().contains(q.toLowerCase()) ||
            '${s['pno']}'.toLowerCase().contains(q.toLowerCase()) ||
            '${s['thana']}'.toLowerCase().contains(q.toLowerCase())).toList();
  });

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 600),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: const BoxDecoration(color: _kPurple,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            const Icon(Icons.people_alt_outlined, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('स्टाफ – ${widget.center['name']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                overflow: TextOverflow.ellipsis)),
            IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.assigned.isNotEmpty) ...[
              const Text('असाइन स्टाफ:', style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 11, color: _kSubtle)),
              const SizedBox(height: 6),
              ...widget.assigned.map((d) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFF3E5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kPurple.withOpacity(0.3))),
                child: Row(children: [
                  Expanded(child: Text(
                    '${d['name']}  PNO: ${d['pno']}  ${d['user_rank'] ?? ''}\nमो: ${d['mobile'] ?? ''}',
                    style: const TextStyle(fontSize: 11, color: _kDark))),
                  IconButton(icon: const Icon(Icons.remove_circle_outline, color: _kRed, size: 18),
                      onPressed: () async { await widget.onRemove(d['id']); Navigator.pop(context); }),
                ]),
              )),
              const Divider(),
            ],
            if (widget.unassigned.isNotEmpty) ...[
              const Text('नया स्टाफ:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: _kSubtle)),
              const SizedBox(height: 6),
              TextField(controller: _srC, onChanged: _filter,
                decoration: InputDecoration(
                  hintText: 'खोजें...', isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 16, color: _kSubtle),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  filled: true, fillColor: const Color(0xFFF8F9FC)),
              ),
              const SizedBox(height: 6),
              Container(height: 160, decoration: BoxDecoration(
                border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(8)),
                child: ListView.separated(
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
                  itemBuilder: (_, i) {
                    final s = _filtered[i];
                    final sel = _selId == s['id'];
                    return InkWell(
                      onTap: () => setState(() => _selId = sel ? null : s['id'] as int),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        color: sel ? _kPurple.withOpacity(0.07) : Colors.transparent,
                        child: Row(children: [
                          AnimatedContainer(duration: const Duration(milliseconds: 150),
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                                color: sel ? _kPurple : const Color(0xFFF0EEF8),
                                shape: BoxShape.circle,
                                border: Border.all(color: sel ? _kPurple : _kBorder)),
                            child: sel ? const Icon(Icons.check, color: Colors.white, size: 12) : null),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${s['name']}', style: TextStyle(
                                color: sel ? _kPurple : _kDark,
                                fontWeight: FontWeight.w600, fontSize: 12)),
                            Text('PNO: ${s['pno']}  •  ${s['thana']}',
                                style: const TextStyle(color: _kSubtle, fontSize: 10)),
                          ])),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(controller: _busC,
                decoration: InputDecoration(
                  labelText: 'बस संख्या', isDense: true,
                  prefixIcon: const Icon(Icons.directions_bus_outlined, size: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8))),
            ],
          ]),
        )),
        Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child:
          Row(children: [
            Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context), child: const Text('बंद करें'))),
            if (_selId != null) ...[
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kPurple),
                onPressed: () async {
                  await widget.onAssign(_selId!, _busC.text);
                  Navigator.pop(context);
                },
                child: const Text('असाइन', style: TextStyle(color: Colors.white)))),
            ],
          ])),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TINY SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════
class _DI { final String value, label; const _DI(this.value, this.label); }

class _Drop extends StatelessWidget {
  final String label, hint; final String? value;
  final List<_DI> items; final ValueChanged<String?> onChanged;
  const _Drop({required this.label, required this.hint, required this.value,
      required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: _kSubtle, fontSize: 9, fontWeight: FontWeight.w700)),
    const SizedBox(height: 2),
    Container(
      height: 36, padding: const EdgeInsets.symmetric(horizontal: 10),
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 150),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: value != null ? _kPrimary : _kBorder, width: 1.5)),
      child: DropdownButton<String>(
        value: value, underline: const SizedBox(), isExpanded: true,
        hint: Text(hint, style: const TextStyle(color: _kSubtle, fontSize: 11),
            overflow: TextOverflow.ellipsis),
        style: const TextStyle(color: _kDark, fontSize: 11),
        dropdownColor: Colors.white,
        items: [
          DropdownMenuItem<String>(value: null,
              child: Text(hint, style: const TextStyle(color: _kSubtle, fontSize: 11))),
          ...items.map((i) => DropdownMenuItem<String>(value: i.value,
              child: Text(i.label, style: const TextStyle(color: _kDark, fontSize: 11),
                  overflow: TextOverflow.ellipsis))),
        ],
        onChanged: onChanged,
      ),
    ),
  ]);
}

class _Btn extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  final String? tip; final double size;
  const _Btn({required this.icon, required this.color, required this.onTap,
      this.tip, this.size = 18});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip ?? '',
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6),
        child: Padding(padding: const EdgeInsets.all(5),
            child: Icon(icon, color: color, size: size))),
  );
}

class _Chip extends StatelessWidget {
  final String label; final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: color.withOpacity(0.9),
        fontSize: 10, fontWeight: FontWeight.w700)));
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.inbox_outlined, size: 48, color: _kSubtle),
    const SizedBox(height: 10),
    Text(text, style: const TextStyle(color: _kSubtle, fontSize: 13)),
  ]));
}

class _ErrView extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: _kRed),
      const SizedBox(height: 10),
      const Text('डेटा लोड करने में त्रुटि',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(error, style: const TextStyle(color: _kSubtle, fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 14),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
        label: const Text('पुनः प्रयास', style: TextStyle(color: Colors.white))),
    ]),
  ));
}