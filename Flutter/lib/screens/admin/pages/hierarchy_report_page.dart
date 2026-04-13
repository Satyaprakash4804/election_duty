import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFFFAFAFA);
const _kPrimary = Color(0xFF0F2B5B);
const _kGreen   = Color(0xFF186A3B);
const _kPurple  = Color(0xFF6C3483);
const _kRed     = Color(0xFFC0392B);
const _kDark    = Color(0xFF1A2332);
const _kSubtle  = Color(0xFF6B7C93);
const _kBorder  = Color(0xFFDDE3EE);
const _kAccent  = Color(0xFFFBBF24);
const _kGold    = Color(0xFFFFF8E7);
const _kOrange  = Color(0xFFE67E22);

// Sensitivity color map — now includes A++
Color _sensitivityColor(String? t) {
  switch (t) {
    case 'A++': return const Color(0xFF6C3483);
    case 'A':   return _kRed;
    case 'B':   return _kOrange;
    default:    return const Color(0xFF1A5276);
  }
}

// ── Cell border helper ────────────────────────────────────────────────────────
BoxDecoration _cellDec({bool right = true, bool bottom = true, Color? bg}) =>
    BoxDecoration(
      color: bg,
      border: Border(
        right:  right  ? const BorderSide(color: _kBorder) : BorderSide.none,
        bottom: bottom ? const BorderSide(color: _kBorder) : BorderSide.none,
      ),
    );

// ── Rank list ─────────────────────────────────────────────────────────────────
const _kRanks = [
  {'en': 'SP',             'hi': 'पुलिस अधीक्षक'},
  {'en': 'ASP',            'hi': 'सह0 पुलिस अधीक्षक'},
  {'en': 'DSP',            'hi': 'पुलिस उपाधीक्षक'},
  {'en': 'Inspector',      'hi': 'निरीक्षक'},
  {'en': 'SI',             'hi': 'उप निरीक्षक'},
  {'en': 'ASI',            'hi': 'सह0 उप निरीक्षक'},
  {'en': 'Head Constable', 'hi': 'मुख्य आरक्षी'},
  {'en': 'Constable',      'hi': 'आरक्षी'},
];

// ── Sensitivity options ───────────────────────────────────────────────────────
const _kCenterTypes = ['A++', 'A', 'B', 'C'];

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

  // Filters
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

  // ── Filtered lists ────────────────────────────────────────────────────────
  List get _szList => _data;
  List get _filteredSZ => _fSZ == null ? _data
      : _data.where((s) => '${s['id']}' == _fSZ).toList();
  List get _allZones =>
      _filteredSZ.expand((s) => (s['zones'] as List? ?? [])).toList();
  List get _filteredZones => _fZone == null ? _allZones
      : _allZones.where((z) => '${z['id']}' == _fZone).toList();
  List get _allSectors =>
      _allZones.expand((z) => (z['sectors'] as List? ?? [])).toList();
  List get _filteredSectors => _fSector == null ? _allSectors
      : _allSectors.where((s) => '${s['id']}' == _fSector).toList();
  List get _allGPs =>
      _allSectors.expand((s) => (s['panchayats'] as List? ?? [])).toList();

  // ── CRUD helpers ─────────────────────────────────────────────────────────
  Future<void> _delete(String ep, int id, String name) async {
    final ok = await _confirm('हटाएं', '"$name" को हटाना चाहते हैं?');
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete('$ep/$id', token: token);
      _load();
      _snack('सफलतापूर्वक हटाया गया', _kGreen);
    } catch (e) { _snack('त्रुटि: $e', _kRed); }
  }

  Future<bool?> _confirm(String title, String msg) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('रद्द')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kRed),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('हटाएं', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
  }

  // ── Print ─────────────────────────────────────────────────────────────────
  Future<void> _print() async {
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();
    final doc  = pw.Document();
    final idx  = _tab.index;

    if (idx == 0) {
      // FIX: ALL super zones on a SINGLE landscape page
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(14),
        build: (_) {
          final widgets = <pw.Widget>[];
          for (final sz in _filteredSZ) {
            widgets.addAll(_pdfTab1(sz, font, bold));
            widgets.add(pw.SizedBox(height: 10));
          }
          return widgets;
        },
      ));
    } else if (idx == 1) {
      for (final sz in _filteredSZ) {
        for (final z in (sz['zones'] as List? ?? [])) {
          if (_fZone != null && '${z['id']}' != _fZone) continue;
          doc.addPage(pw.MultiPage(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(14),
            build: (_) => _pdfTab2(sz, z, font, bold),
          ));
        }
      }
    } else {
      for (final sz in _filteredSZ) {
        for (final z in (sz['zones'] as List? ?? [])) {
          if (_fZone != null && '${z['id']}' != _fZone) continue;
          for (final s in (z['sectors'] as List? ?? [])) {
            if (_fSector != null && '${s['id']}' != _fSector) continue;
            for (final gp in (s['panchayats'] as List? ?? [])) {
              if (_fGP != null && '${gp['id']}' != _fGP) continue;
              doc.addPage(pw.MultiPage(
                pageFormat: PdfPageFormat.a4.landscape,
                margin: const pw.EdgeInsets.all(14),
                build: (_) => _pdfTab3(sz, z, s, gp, font, bold),
              ));
            }
          }
        }
      }
    }

    if (doc.document.pdfPageList.pages.isEmpty) {
      _snack('प्रिंट के लिए कोई डेटा नहीं', _kRed); return;
    }
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  // ─── PDF Tab 1 — all super zones on one page ──────────────────────────────
  List<pw.Widget> _pdfTab1(Map sz, pw.Font font, pw.Font bold) {
    final zones = sz['zones'] as List? ?? [];
    int globalSector = 0;
    final rows = <List<String>>[];

    for (int zi = 0; zi < zones.length; zi++) {
      final z       = zones[zi] as Map;
      final sectors = z['sectors'] as List? ?? [];
      final zOff    = (z['officers'] as List? ?? []);
      final zOffStr = zOff.isNotEmpty
          ? zOff.map((o) => '${o['name'] ?? ''} ${o['user_rank'] ?? ''}').join(', ')
          : '—';
      final hq = z['hq_address'] ?? '—';

      for (final s in sectors) {
        globalSector++;
        final gps      = s['panchayats'] as List? ?? [];
        final gpNames  = gps.map((g) => '${g['name']}').join(', ');
        final thanas   = gps.map((g) => '${g['thana'] ?? ''}')
            .where((t) => t.isNotEmpty).toSet().join(', ');
        final sOff     = (s['officers'] as List? ?? []);
        final sOffStr  = sOff.isNotEmpty
            ? sOff.map((o) => '${o['name'] ?? ''} ${o['user_rank'] ?? ''} ${o['mobile'] ?? ''}').join(', ')
            : '—';
        rows.add([
          '${zi + 1}', zOffStr, '$hq',
          '$globalSector', sOffStr, s['name'] ?? '—',
          gpNames.isEmpty ? '—' : gpNames,
          thanas.isEmpty  ? '—' : thanas,
        ]);
      }
    }

    int gpTotal = 0;
    for (final z in zones) for (final s in (z['sectors'] as List? ?? []))
      gpTotal += ((s['panchayats'] as List?)?.length ?? 0);

    pw.Widget th(String t) => pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 7),
          textAlign: pw.TextAlign.center),
    );
    pw.Widget td(String t, {bool center = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(t, style: pw.TextStyle(font: font, fontSize: 7),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
    );

    return [
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: 'सुपर जोन–${sz['name']}  ब्लाक ${sz['block'] ?? ''}  ',
            style: pw.TextStyle(font: bold, fontSize: 11)),
        pw.TextSpan(text: 'कुल ग्राम पंचायत–$gpTotal',
            style: pw.TextStyle(font: bold, fontSize: 11)),
      ])),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(28), 1: pw.FlexColumnWidth(2.0),
          2: pw.FlexColumnWidth(1.5), 3: pw.FixedColumnWidth(28),
          4: pw.FlexColumnWidth(2.5), 5: pw.FlexColumnWidth(1.5),
          6: pw.FlexColumnWidth(3.0), 7: pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(children: [
            th('सुपर\nजोन'), th('जोनल अधिकारी'), th('मुख्यालय'),
            th('सैक्टर'), th('सैक्टर पुलिस अधिकारी का नाम'),
            th('मुख्यालय'), th('सैक्टर में लगने वाले ग्राम पंचायत का नाम'), th('थाना'),
          ]),
          ...rows.map((r) => pw.TableRow(children: [
            td(r[0], center: true), td(r[1]), td(r[2]),
            td(r[3], center: true), td(r[4]), td(r[5]), td(r[6]), td(r[7]),
          ])),
        ],
      ),
    ];
  }

  // ─── PDF Tab 2 ────────────────────────────────────────────────────────────
  List<pw.Widget> _pdfTab2(Map sz, Map z, pw.Font font, pw.Font bold) {
    final sectors = z['sectors'] as List? ?? [];
    final zOff    = (z['officers'] as List? ?? []);
    final szOff   = (sz['officers'] as List? ?? []);

    pw.Widget th(String t) => pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 7),
          textAlign: pw.TextAlign.center),
    );
    pw.Widget td(String t) => pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(t, style: pw.TextStyle(font: font, fontSize: 7)),
    );

    final rows = <List<String>>[];
    int sSeq = 0;
    for (final s in sectors) {
      sSeq++;
      final sOff   = (s['officers'] as List? ?? []);
      final magStr = sOff.isNotEmpty
          ? '${sOff[0]['name'] ?? ''} ${sOff[0]['user_rank'] ?? ''}\n${sOff[0]['mobile'] ?? ''}'
          : '—';
      final polStr = sOff.length > 1
          ? '${sOff[1]['name'] ?? ''} ${sOff[1]['user_rank'] ?? ''}\n${sOff[1]['mobile'] ?? ''}'
          : magStr;

      final gps = s['panchayats'] as List? ?? [];
      if (gps.isEmpty) {
        rows.add(['$sSeq', magStr, polStr, '—', '—', '—']);
      } else {
        for (final gp in gps) {
          final centers    = gp['centers'] as List? ?? [];
          final sthalNames = centers.map((c) => '${c['name']}').join('\n');
          final kendraStrs = centers.expand((c) => (c['kendras'] as List? ?? []))
              .map((k) => '${k['room_number']}').join(', ');
          rows.add([
            '$sSeq', magStr, polStr, '${gp['name']}',
            sthalNames.isEmpty ? '—' : sthalNames,
            kendraStrs.isEmpty ? '—' : kendraStrs,
          ]);
        }
      }
    }

    final zOffStr  = zOff.map((o) =>
        '${o['name'] ?? ''} (${o['user_rank'] ?? ''}) मो: ${o['mobile'] ?? ''}').join('\n');
    final szOffStr = szOff.map((o) =>
        '${o['name'] ?? ''} (${o['user_rank'] ?? ''}) मो: ${o['mobile'] ?? ''}').join('\n');

    return [
      pw.Text('जोन: ${z['name']}  |  सुपर जोन: ${sz['name']}  |  ब्लॉक: ${sz['block'] ?? ''}',
          style: pw.TextStyle(font: bold, fontSize: 11)),
      if (zOffStr.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text('जोनल अधिकारी: $zOffStr', style: pw.TextStyle(font: font, fontSize: 8)),
      ],
      if (szOffStr.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text('सुपर जोन अधिकारी: $szOffStr', style: pw.TextStyle(font: font, fontSize: 8)),
      ],
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(28), 1: pw.FlexColumnWidth(2.5),
          2: pw.FlexColumnWidth(2.5), 3: pw.FlexColumnWidth(1.8),
          4: pw.FlexColumnWidth(2.5), 5: pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(children: [
            th('सैक्टर\nसं.'), th('सैक्टर मजिस्ट्रेट\n(नाम/पद/मोबाइल)'),
            th('सैक्टर पुलिस अधिकारी\n(नाम/पद/मोबाइल)'),
            th('ग्राम पंचायत'), th('मतदेय स्थल'), th('मतदान केन्द्र'),
          ]),
          ...rows.map((r) => pw.TableRow(children: r.map(td).toList())),
        ],
      ),
    ];
  }

  // ─── PDF Tab 3 ────────────────────────────────────────────────────────────
  List<pw.Widget> _pdfTab3(Map sz, Map z, Map s, Map gp, pw.Font font, pw.Font bold) {
    final centers = gp['centers'] as List? ?? [];
    pw.Widget th(String t) => pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 6.5),
          textAlign: pw.TextAlign.center),
    );
    pw.Widget td(String t, {bool center = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(t, style: pw.TextStyle(font: font, fontSize: 6.5),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
    );

    int totalKendra = 0;
    for (final c in centers) {
      final k = (c['kendras'] as List? ?? []);
      totalKendra += k.isEmpty ? 1 : k.length;
    }

    final rows = <List<String>>[];
    int sthalNo = 1, kendraGlobal = 1;
    for (final c in centers) {
      final kendras      = c['kendras'] as List? ?? [];
      final dutyOfficers = c['duty_officers'] as List? ?? [];
      final dutyText     = dutyOfficers.isNotEmpty
          ? dutyOfficers.map((d) =>
              '${d['name'] ?? ''} ${d['pno'] ?? ''}\n${d['user_rank'] ?? ''}').join('\n')
          : '—';
      final mobileText = dutyOfficers.isNotEmpty
          ? dutyOfficers.map((d) => '${d['mobile'] ?? ''}').where((m) => m.isNotEmpty).join('\n')
          : '—';

      if (kendras.isEmpty) {
        rows.add([
          '$kendraGlobal', '${c['name']}\n${c['center_type'] ?? 'C'}',
          '$sthalNo', '${c['name']}', '${z['name']}', '${s['name']}',
          '${c['thana'] ?? gp['thana'] ?? '—'}', dutyText, mobileText,
          '${c['bus_no'] ?? '—'}',
        ]);
        sthalNo++; kendraGlobal++;
      } else {
        for (int ki = 0; ki < kendras.length; ki++) {
          rows.add([
            '$kendraGlobal',
            '${c['name']} क.नं. ${kendras[ki]['room_number']}\n${c['center_type'] ?? 'C'}',
            ki == 0 ? '$sthalNo' : '', ki == 0 ? '${c['name']}' : '',
            '${z['name']}', '${s['name']}',
            '${c['thana'] ?? gp['thana'] ?? '—'}',
            ki == 0 ? dutyText : '', ki == 0 ? mobileText : '',
            ki == 0 ? '${c['bus_no'] ?? '—'}' : '',
          ]);
          kendraGlobal++;
        }
        sthalNo++;
      }
    }

    return [
      pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: 'बूथ ड्यूटी – ब्लॉक ${sz['block'] ?? sz['name']}  ',
            style: pw.TextStyle(font: bold, fontSize: 11)),
        pw.TextSpan(text: 'मतदान दिनांकः ....../......./2026',
            style: pw.TextStyle(font: font, fontSize: 10)),
      ])),
      pw.SizedBox(height: 2),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('मतदान केन्द्र–$totalKendra', style: pw.TextStyle(font: bold, fontSize: 9)),
        pw.Text('मतदेय स्थल–${centers.length}', style: pw.TextStyle(font: bold, fontSize: 9)),
      ]),
      pw.Text('ग्राम पंचायत: ${gp['name']}  |  सैक्टर: ${s['name']}  |  जोन: ${z['name']}',
          style: pw.TextStyle(font: font, fontSize: 8)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(24), 1: pw.FlexColumnWidth(2.2),
          2: pw.FixedColumnWidth(24), 3: pw.FlexColumnWidth(2.0),
          4: pw.FixedColumnWidth(30), 5: pw.FixedColumnWidth(30),
          6: pw.FlexColumnWidth(1.2), 7: pw.FlexColumnWidth(2.5),
          8: pw.FlexColumnWidth(1.4), 9: pw.FixedColumnWidth(28),
        },
        children: [
          pw.TableRow(children: [
            th('मतदान\nकेन्द्र की\nसंख्या'), th('मतदान केन्द्र\nका नाम'),
            th('मतदेय\nसं.'), th('मतदान स्थल\nका नाम'),
            th('जोन\nसंख्या'), th('सैक्टर\nसंख्या'), th('थाना'),
            th('ड्यूटी पर लगाया\nपुलिस का नाम'), th('मोबाईल\nनम्बर'), th('बस\nनं.'),
          ]),
          ...rows.map((r) => pw.TableRow(children: [
            td(r[0], center: true), td(r[1]), td(r[2], center: true), td(r[3]),
            td(r[4], center: true), td(r[5], center: true), td(r[6]),
            td(r[7]), td(r[8]), td(r[9], center: true),
          ])),
        ],
      ),
    ];
  }

  // ── CRUD dialogs ──────────────────────────────────────────────────────────

  void _addSuperZone() => _openDialog(
    title: 'सुपर जोन जोड़ें', color: _kPrimary, icon: Icons.layers_outlined,
    fields: {'name': 'नाम', 'district': 'जिला', 'block': 'ब्लॉक'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/super-zones', Map<String, dynamic>.from(data), token: t);
      _load();
    },
  );

  void _editSZ(Map sz) => _openDialog(
    title: 'सुपर जोन संपादित करें', color: _kPrimary, icon: Icons.edit_outlined,
    fields: {'name': 'नाम', 'district': 'जिला', 'block': 'ब्लॉक'},
    initial: {'name': sz['name'], 'district': sz['district'], 'block': sz['block']},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.put('/admin/hierarchy/super-zone/${sz['id']}', Map<String, dynamic>.from(data), token: t);
      _load();
    },
  );

  void _addZone(Map sz) => _openDialog(
    title: 'जोन जोड़ें – ${sz['name']}', color: _kGreen, icon: Icons.map_outlined,
    fields: {'name': 'जोन का नाम', 'hqAddress': 'मुख्यालय पता'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/super-zones/${sz['id']}/zones', Map<String, dynamic>.from(data), token: t);
      _load();
    },
  );

  void _editZone(Map z) => _openDialog(
    title: 'जोन संपादित करें', color: _kGreen, icon: Icons.edit_outlined,
    fields: {'name': 'जोन का नाम', 'hqAddress': 'मुख्यालय पता'},
    initial: {'name': z['name'], 'hqAddress': z['hq_address'] ?? z['hqAddress']},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.put('/admin/zones/${z['id']}', Map<String, dynamic>.from(data), token: t);
      _load();
    },
  );

  void _addSector(Map z) => _openDialog(
    title: 'सैक्टर जोड़ें – ${z['name']}', color: _kGreen, icon: Icons.add,
    fields: {'name': 'सैक्टर का नाम'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/zones/${z['id']}/sectors', Map<String, dynamic>.from(data), token: t);
      _load();
    },
  );

  void _editSector(Map s) => _openDialog(
    title: 'सैक्टर संपादित करें', color: _kGreen, icon: Icons.edit_outlined,
    fields: {'name': 'सैक्टर का नाम'},
    initial: {'name': s['name']},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.put('/admin/hierarchy/sector/${s['id']}', Map<String, dynamic>.from(data), token: t);
      _load();
    },
  );

  void _addGP(Map s) => _openDialog(
    title: 'ग्राम पंचायत जोड़ें – ${s['name']}', color: _kPurple, icon: Icons.add,
    fields: {'name': 'ग्राम पंचायत का नाम', 'address': 'पता'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/sectors/${s['id']}/gram-panchayats', Map<String, dynamic>.from(data), token: t);
      _load();
    },
  );

  void _addCenter(Map gp) => _openCenterDialog(null, gpId: gp['id']);
  void _editCenter(Map c)  => _openCenterDialog(c);

  void _addKendra(Map c) => _openDialog(
    title: 'मतदेय स्थल (कक्ष) जोड़ें', color: _kPurple, icon: Icons.add,
    fields: {'roomNumber': 'कक्ष संख्या'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/centers/${c['id']}/rooms', Map<String, dynamic>.from(data), token: t);
      _load();
    },
  );

  // ── Officers dialog ───────────────────────────────────────────────────────
  void _manageOfficers(String title, Color color, String endpoint,
      List currentOfficers, VoidCallback onDone) {
    showDialog(
      context: context,
      builder: (ctx) => _OfficersDialog(
        title: title, color: color,
        endpoint: endpoint, officers: List<Map>.from(currentOfficers),
        onSave: (officers) async {
          onDone();
        },
      ),
    );
  }

  void _openCenterDialog(Map? center, {int? gpId}) {
    final nameCtrl    = TextEditingController(text: center?['name'] ?? '');
    final addressCtrl = TextEditingController(text: center?['address'] ?? '');
    final thanaCtrl   = TextEditingController(text: center?['thana'] ?? '');
    final busCtrl     = TextEditingController(text: center?['bus_no'] ?? center?['busNo'] ?? '');
    // Support A++ now
    String type = center?['center_type'] ?? center?['centerType'] ?? 'C';
    if (!_kCenterTypes.contains(type)) type = 'C';
    final fk = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(center != null ? 'मतदेय स्थल संपादित करें' : 'मतदेय स्थल जोड़ें'),
          content: SizedBox(
            width: 380,
            child: Form(key: fk, child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                _field(nameCtrl, 'नाम *', required: true),
                const SizedBox(height: 8),
                _field(addressCtrl, 'पता'),
                const SizedBox(height: 8),
                _field(thanaCtrl, 'थाना'),
                const SizedBox(height: 8),
                // Sensitivity chips — now includes A++
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: _kCenterTypes.map((t) => GestureDetector(
                    onTap: () => ss(() => type = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: type == t ? _sensitivityColor(t) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _sensitivityColor(t)),
                      ),
                      child: Text(t, style: TextStyle(
                          color: type == t ? Colors.white : _sensitivityColor(t),
                          fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 8),
                _field(busCtrl, 'बस संख्या'),
              ],
            ))),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kPurple),
              onPressed: () async {
                if (!fk.currentState!.validate()) return;
                Navigator.pop(ctx);
                final data = <String, dynamic>{
                  'name': nameCtrl.text.trim(), 'address': addressCtrl.text.trim(),
                  'thana': thanaCtrl.text.trim(), 'centerType': type,
                  'busNo': busCtrl.text.trim(), 'center_type': type,
                };
                final tok = await AuthService.getToken();
                if (center != null) {
                  await ApiService.put('/admin/hierarchy/sthal/${center['id']}', data, token: tok);
                } else {
                  await ApiService.post('/admin/gram-panchayats/$gpId/centers', data, token: tok);
                }
                _load();
              },
              child: const Text('सहेजें', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Staff assignment dialog — PAGINATED ───────────────────────────────────
  void _openStaffDialog(Map center) {
    showDialog(
      context: context,
      builder: (ctx) => _PaginatedStaffDialog(
        center: center,
        onChanged: _load,
      ),
    );
  }

  // ── Generic text dialog ───────────────────────────────────────────────────
  void _openDialog({
    required String title, required Color color, required IconData icon,
    required Map<String, String> fields,
    Map<String, dynamic>? initial,
    required Future<void> Function(Map<String, dynamic>) onSave,
  }) {
    final ctrls = fields.map((k, v) =>
        MapEntry(k, TextEditingController(text: '${initial?[k] ?? ''}')));
    final fk = GlobalKey<FormState>();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(children: [
            Icon(icon, color: color, size: 20), const SizedBox(width: 8),
            Expanded(child: Text(title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          ]),
          content: SizedBox(
            width: 340,
            child: Form(key: fk, child: Column(
              mainAxisSize: MainAxisSize.min,
              children: fields.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _field(ctrls[e.key]!, e.value, required: e.key == 'name'),
              )).toList(),
            )),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: saving ? null : () async {
                if (!fk.currentState!.validate()) return;
                ss(() => saving = true);
                try {
                  final data = <String, dynamic>{
                    for (final e in ctrls.entries) e.key: e.value.text.trim(),
                  };
                  await onSave(data);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('सफलतापूर्वक सहेजा गया', _kGreen);
                } catch (e) {
                  _snack('त्रुटि: $e', _kRed);
                } finally {
                  if (ctx.mounted) ss(() => saving = false);
                }
              },
              child: saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('सहेजें', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool required = false}) =>
      TextFormField(
        controller: c,
        decoration: InputDecoration(
          labelText: label, isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kPrimary, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        validator: required ? (v) => (v?.trim().isEmpty ?? true) ? '$label आवश्यक' : null : null,
      );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
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
              onPressed: _addSuperZone, tooltip: 'सुपर जोन जोड़ें'),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _kAccent, indicatorWeight: 3,
          labelColor: Colors.white, unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'सुपर जोन', icon: Icon(Icons.layers_outlined, size: 16)),
            Tab(text: 'जोन/सैक्टर', icon: Icon(Icons.map_outlined, size: 16)),
            Tab(text: 'बूथ ड्यूटी', icon: Icon(Icons.how_to_vote_outlined, size: 16)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : Column(children: [
                  _buildFilterBar(),
                  Expanded(child: TabBarView(controller: _tab, children: [
                    _buildTab1(), _buildTab2(), _buildTab3(),
                  ])),
                ]),
    );
  }

  Widget _buildFilterBar() {
    final tabIdx = _tab.index;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _FDrop(label: 'सुपर जोन', value: _fSZ, placeholder: 'सभी सुपर जोन',
              items: _szList.map((s) => _DI('${s['id']}', '${s['name']}')).toList(),
              onChanged: (v) => setState(() { _fSZ = v; _fZone = _fSector = _fGP = null; })),
          if (tabIdx >= 1) ...[
            const SizedBox(width: 10),
            _FDrop(label: 'जोन', value: _fZone, placeholder: 'सभी जोन',
                items: _allZones.map((z) => _DI('${z['id']}', '${z['name']}')).toList(),
                onChanged: (v) => setState(() { _fZone = v; _fSector = _fGP = null; })),
          ],
          if (tabIdx >= 2) ...[
            const SizedBox(width: 10),
            _FDrop(label: 'सैक्टर', value: _fSector, placeholder: 'सभी सैक्टर',
                items: _allSectors.map((s) => _DI('${s['id']}', '${s['name']}')).toList(),
                onChanged: (v) => setState(() { _fSector = v; _fGP = null; })),
            const SizedBox(width: 10),
            _FDrop(label: 'ग्राम पंचायत', value: _fGP, placeholder: 'सभी GP',
                items: _allGPs.map((g) => _DI('${g['id']}', '${g['name']}')).toList(),
                onChanged: (v) => setState(() => _fGP = v)),
          ],
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTab1() {
    if (_filteredSZ.isEmpty) return const _Empty(text: 'कोई सुपर जोन नहीं मिला');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _filteredSZ.length,
      itemBuilder: (_, i) => _Tab1Card(
        sz: _filteredSZ[i],
        onEdit:    () => _editSZ(_filteredSZ[i]),
        onDelete:  () => _delete('/admin/hierarchy/super-zone', _filteredSZ[i]['id'], '${_filteredSZ[i]['name']}'),
        onAddZone: () => _addZone(_filteredSZ[i]),
        onManageOfficers: () => _openOfficerDialog(
          'सुपर जोन अधिकारी',
          _kPrimary,
          '/admin/super-zones/${_filteredSZ[i]['id']}/officers',
          (_filteredSZ[i]['officers'] as List? ?? []),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTab2() {
    final items = <Map>[];
    for (final sz in _filteredSZ) {
      for (final z in (sz['zones'] as List? ?? [])) {
        if (_fZone != null && '${z['id']}' != _fZone) continue;
        items.add({'sz': sz, 'z': z});
      }
    }
    if (items.isEmpty) return const _Empty(text: 'कोई जोन नहीं मिला');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: items.length,
      itemBuilder: (_, i) => _Tab2Card(
        sz: items[i]['sz'], z: items[i]['z'],
        onEditZone:   () => _editZone(items[i]['z']),
        onDeleteZone: () => _delete('/admin/zones', items[i]['z']['id'], '${items[i]['z']['name']}'),
        onAddSector:  () => _addSector(items[i]['z']),
        onManageZoneOfficers: () => _openOfficerDialog(
          'जोनल अधिकारी', _kGreen,
          '/admin/zones/${items[i]['z']['id']}/officers',
          (items[i]['z']['officers'] as List? ?? []),
        ),
        onEditSector:   _editSector,
        onDeleteSector: (s) => _delete('/admin/hierarchy/sector', s['id'], '${s['name']}'),
        onAddGP:        _addGP,
        onManageSectorOfficers: (s) => _openOfficerDialog(
          'सैक्टर अधिकारी', _kGreen,
          '/admin/sectors/${s['id']}/officers',
          (s['officers'] as List? ?? []),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTab3() {
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
    if (items.isEmpty) return const _Empty(text: 'कोई पंचायत नहीं मिली');
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: items.length,
      itemBuilder: (_, i) => _Tab3Card(
        sz: items[i]['sz'], z: items[i]['z'],
        s: items[i]['s'],   gp: items[i]['gp'],
        onAddCenter:    () => _addCenter(items[i]['gp']),
        onEditCenter:   _editCenter,
        onDeleteCenter: (c) => _delete('/admin/hierarchy/sthal', c['id'], '${c['name']}'),
        onAddKendra:    _addKendra,
        onDeleteKendra: (k) => _delete('/admin/rooms', k['id'], '${k['room_number']}'),
        onManageStaff:  _openStaffDialog,
      ),
    );
  }

  // ── Officer management dialog ─────────────────────────────────────────────
  void _openOfficerDialog(String title, Color color, String endpoint, List officers) {
    showDialog(
      context: context,
      builder: (ctx) => _OfficersDialog(
        title: title, color: color, endpoint: endpoint,
        officers: List<Map>.from(officers),
        onSave: (_) => _load(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGINATED STAFF DIALOG — handles 1000s of centers
// ══════════════════════════════════════════════════════════════════════════════
class _PaginatedStaffDialog extends StatefulWidget {
  final Map center;
  final VoidCallback onChanged;
  const _PaginatedStaffDialog({required this.center, required this.onChanged});
  @override
  State<_PaginatedStaffDialog> createState() => _PaginatedStaffDialogState();
}

class _PaginatedStaffDialogState extends State<_PaginatedStaffDialog> {
  final List<Map> _staff    = [];
  int  _page                = 1;
  int  _total               = 0;
  bool _loading             = false;
  bool _hasMore             = true;
  String _q                 = '';
  Timer? _debounce;
  final _searchCtrl         = TextEditingController();
  final _scroll             = ScrollController();
  final _busCtrl            = TextEditingController();
  int? _selectedId;
  bool _saving              = false;

  List _assigned = [];

  @override
  void initState() {
    super.initState();
    _assigned = List.from(widget.center['duty_officers'] as List? ?? []);
    _busCtrl.text = '${widget.center['bus_no'] ?? ''}';
    _scroll.addListener(_onScroll);
    _searchCtrl.addListener(_onSearch);
    _loadStaff(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _searchCtrl.removeListener(_onSearch);
    _scroll.dispose();
    _searchCtrl.dispose();
    _busCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 150
        && !_loading && _hasMore) {
      _loadStaff();
    }
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final q = _searchCtrl.text.trim();
      if (q != _q) { _q = q; _loadStaff(reset: true); }
    });
  }

  Future<void> _loadStaff({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    if (reset) setState(() { _staff.clear(); _page = 1; _hasMore = true; });
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get(
        '/admin/staff?assigned=no&page=$_page&limit=30&q=${Uri.encodeComponent(_q)}',
        token: token,
      );
      final wrapper    = (res['data'] as Map<String, dynamic>?) ?? {};
      final items      = List<Map>.from((wrapper['data'] as List?) ?? []);
      final total      = (wrapper['total']      as num?)?.toInt() ?? 0;
      final totalPages = (wrapper['totalPages'] as num?)?.toInt() ?? 1;
      if (!mounted) return;
      setState(() {
        _staff.addAll(items);
        _total   = total;
        _hasMore = _page < totalPages;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign() async {
    if (_selectedId == null || _saving) return;
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      await ApiService.post('/admin/duties', {
        'staffId': _selectedId, 'centerId': widget.center['id'],
        'busNo': _busCtrl.text.trim(),
      }, token: token);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('त्रुटि: $e'), backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeDuty(Map d) async {
    try {
      final token = await AuthService.getToken();
      await ApiService.delete('/admin/duties/${d['id']}', token: token);
      widget.onChanged();
      setState(() => _assigned.removeWhere((a) => a['id'] == d['id']));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('त्रुटि: $e'), backgroundColor: _kRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: const BoxDecoration(color: _kPurple,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(children: [
              const Icon(Icons.people_alt_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('स्टाफ – ${widget.center['name']}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),

          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Assigned staff
              if (_assigned.isNotEmpty) ...[
                const Text('असाइन किए गए स्टाफ:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _kSubtle)),
                const SizedBox(height: 6),
                ..._assigned.map((d) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kPurple.withOpacity(0.3))),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${d['name']}', style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13, color: _kDark)),
                      Text('PNO: ${d['pno']}  •  ${d['user_rank'] ?? ''}  •  ${d['mobile'] ?? ''}',
                          style: const TextStyle(color: _kSubtle, fontSize: 11)),
                    ])),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: _kRed, size: 20),
                      onPressed: () => _removeDuty(d),
                    ),
                  ]),
                )),
                const Divider(height: 20),
              ],

              // Search
              const Text('नया स्टाफ जोड़ें:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _kSubtle)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'नाम, PNO, थाना से खोजें... ($_total उपलब्ध)',
                  prefixIcon: const Icon(Icons.search, size: 18, color: _kSubtle),
                  isDense: true, fillColor: const Color(0xFFF8F9FC), filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _kBorder)),
                  suffixIcon: _q.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 16, color: _kSubtle),
                          onPressed: () { _searchCtrl.clear(); })
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
              ),
              const SizedBox(height: 8),

              // Staff list — fixed height with scroll
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: _kBorder),
                        borderRadius: BorderRadius.circular(8)),
                    child: _loading && _staff.isEmpty
                        ? const Center(child: CircularProgressIndicator(
                            color: _kPurple, strokeWidth: 2))
                        : _staff.isEmpty
                            ? Center(child: Text(
                                _q.isNotEmpty ? '"$_q" नहीं मिला' : 'सभी स्टाफ असाइन किए जा चुके हैं',
                                style: const TextStyle(color: _kSubtle, fontSize: 12)))
                            : ListView.separated(
                                controller: _scroll,
                                itemCount: _staff.length + (_hasMore ? 1 : 0),
                                separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
                                itemBuilder: (_, i) {
                                  if (i >= _staff.length) {
                                    return const Padding(padding: EdgeInsets.all(8),
                                        child: Center(child: SizedBox(width: 16, height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: _kPurple))));
                                  }
                                  final s   = _staff[i];
                                  final sel = _selectedId == s['id'];
                                  return InkWell(
                                    onTap: () => setState(() =>
                                        _selectedId = sel ? null : s['id'] as int),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 9),
                                      color: sel ? _kPurple.withOpacity(0.07) : Colors.transparent,
                                      child: Row(children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          width: 24, height: 24,
                                          decoration: BoxDecoration(
                                              color: sel ? _kPurple : const Color(0xFFF5EAD0),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: sel ? _kPurple : _kBorder)),
                                          child: sel
                                              ? const Icon(Icons.check, color: Colors.white, size: 13)
                                              : null),
                                        const SizedBox(width: 10),
                                        Expanded(child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text('${s['name']}', style: TextStyle(
                                              color: sel ? _kPurple : _kDark,
                                              fontWeight: FontWeight.w600, fontSize: 13)),
                                          Text('PNO: ${s['pno']}  •  ${s['thana'] ?? ''}  •  ${s['rank'] ?? ''}',
                                              style: const TextStyle(color: _kSubtle, fontSize: 10),
                                              overflow: TextOverflow.ellipsis),
                                        ])),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ),
              if (_hasMore && !_loading)
                const Padding(padding: EdgeInsets.only(top: 4),
                    child: Text('↓ स्क्रॉल करें — और स्टाफ लोड होंगे',
                        style: TextStyle(color: _kSubtle, fontSize: 10))),

              const SizedBox(height: 10),
              TextFormField(
                controller: _busCtrl,
                decoration: InputDecoration(
                  labelText: 'बस संख्या', isDense: true,
                  prefixIcon: const Icon(Icons.directions_bus_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ]),
          )),

          // Footer
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child:
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context), child: const Text('बंद करें'))),
              if (_selectedId != null) ...[
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kPurple),
                  onPressed: _saving ? null : _assign,
                  child: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('असाइन करें', style: TextStyle(color: Colors.white)),
                )),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// OFFICERS MANAGEMENT DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class _OfficersDialog extends StatefulWidget {
  final String title, endpoint;
  final Color color;
  final List<Map> officers;
  final void Function(List<Map>) onSave;
  const _OfficersDialog({required this.title, required this.color,
      required this.endpoint, required this.officers, required this.onSave});
  @override
  State<_OfficersDialog> createState() => _OfficersDialogState();
}

class _OfficersDialogState extends State<_OfficersDialog> {
  late List<Map<String, dynamic>> _officers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _officers = widget.officers.map((o) => Map<String, dynamic>.from(o)).toList();
  }

  void _add() => setState(() => _officers.add({
    'name': '', 'pno': '', 'mobile': '', 'user_rank': '',
  }));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();

      // Build payload
      final payload = _officers
          .where((o) => (o['name'] ?? '').toString().isNotEmpty)
          .map((o) => {
                'name': o['name'] ?? '',
                'pno': o['pno'] ?? '',
                'mobile': o['mobile'] ?? '',
                'rank': o['user_rank'] ?? '',
              })
          .toList();

      // 🔥 Convert OLD endpoint → NEW replace endpoint
      // Example:
      // /admin/zones/5/officers
      // → /admin/hierarchy/zone/5/officers/replace

      final parts = widget.endpoint.split('/');

      String type = '';
      String id = '';

      if (widget.endpoint.contains('super-zones')) {
        type = 'super-zone';
        id = parts[3];
      } else if (widget.endpoint.contains('zones')) {
        type = 'zone';
        id = parts[3];
      } else if (widget.endpoint.contains('sectors')) {
        type = 'sector';
        id = parts[3];
      }

      final newEndpoint =
          '/admin/hierarchy/$type/$id/officers/replace';

      // 🚀 SINGLE API CALL
      await ApiService.post(newEndpoint, {
        'officers': payload,
      }, token: token);

      widget.onSave(_officers);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('अधिकारी अपडेट किए गए'),
          backgroundColor: _kGreen,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('त्रुटि: $e'),
          backgroundColor: _kRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: BoxDecoration(color: widget.color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
            child: Row(children: [
              const Icon(Icons.people_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              ..._officers.asMap().entries.map((e) {
                final i = e.key;
                final o = e.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kBg, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder.withOpacity(0.5)),
                  ),
                  child: Column(children: [
                    Row(children: [
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(color: widget.color.withOpacity(0.15),
                            shape: BoxShape.circle),
                        child: Center(child: Text('${i + 1}',
                            style: TextStyle(color: widget.color,
                                fontSize: 10, fontWeight: FontWeight.w900))),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _officers.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: _kRed.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.delete_outline, color: _kRed, size: 16),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    _officerField(o, 'name', 'नाम', Icons.person_outline),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: _officerField(o, 'pno', 'PNO', Icons.badge_outlined)),
                      const SizedBox(width: 8),
                      Expanded(child: _officerField(o, 'mobile', 'मोबाइल', Icons.phone_outlined)),
                    ]),
                    const SizedBox(height: 6),
                    // Rank dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kBorder)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _kRanks.any((r) => r['en'] == o['user_rank'])
                              ? o['user_rank'] as String? : null,
                          isExpanded: true, isDense: true,
                          hint: const Text('पद चुनें', style: TextStyle(fontSize: 12, color: _kSubtle)),
                          style: const TextStyle(color: _kDark, fontSize: 12),
                          items: _kRanks.map((r) => DropdownMenuItem<String>(
                            value: r['en'],
                            child: Text('${r['hi']} (${r['en']})',
                                style: const TextStyle(fontSize: 12)),
                          )).toList(),
                          onChanged: (v) => setState(() => o['user_rank'] = v ?? ''),
                        ),
                      ),
                    ),
                  ]),
                );
              }),
              OutlinedButton.icon(
                onPressed: _add,
                icon: Icon(Icons.add, color: widget.color),
                label: Text('अधिकारी जोड़ें', style: TextStyle(color: widget.color)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: widget.color),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ]),
          )),
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context), child: const Text('रद्द'))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: widget.color),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('सहेजें', style: TextStyle(color: Colors.white)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _officerField(Map<String, dynamic> o, String key, String label, IconData icon) {
    return TextFormField(
      initialValue: '${o[key] ?? ''}',
      style: const TextStyle(fontSize: 12, color: _kDark),
      decoration: InputDecoration(
        labelText: label, isDense: true,
        prefixIcon: Icon(icon, size: 16, color: _kSubtle),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: const TextStyle(fontSize: 11, color: _kSubtle),
      ),
      onChanged: (v) => o[key] = v,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 CARD
// ══════════════════════════════════════════════════════════════════════════════
class _Tab1Card extends StatelessWidget {
  final Map sz;
  final VoidCallback onEdit, onDelete, onAddZone, onManageOfficers;
  const _Tab1Card({required this.sz, required this.onEdit,
      required this.onDelete, required this.onAddZone,
      required this.onManageOfficers});

  @override
  Widget build(BuildContext context) {
    final zones = sz['zones'] as List? ?? [];
    int gpTotal = 0, sTotal = 0;
    for (final z in zones) {
      final secs = z['sectors'] as List? ?? [];
      sTotal += secs.length;
      for (final s in secs) gpTotal += ((s['panchayats'] as List?)?.length ?? 0);
    }

    final rows = <_R1>[];
    int globalSec = 0;
    for (int zi = 0; zi < zones.length; zi++) {
      final z       = zones[zi] as Map;
      final sectors = z['sectors'] as List? ?? [];
      final zOff    = z['officers'] as List? ?? [];
      for (int si = 0; si < (sectors.isEmpty ? 1 : sectors.length); si++) {
        if (sectors.isEmpty) {
          rows.add(_R1(zi: zi, z: z, s: null, sGlobal: null,
              zOff: zOff, gpNames: '—', thanas: '—'));
        } else {
          final s   = sectors[si] as Map;
          globalSec++;
          final gps = s['panchayats'] as List? ?? [];
          rows.add(_R1(
            zi: zi, z: z, s: s, sGlobal: globalSec, zOff: zOff,
            gpNames: gps.map((g) => '${g['name']}').join('، '),
            thanas: gps.map((g) => '${g['thana'] ?? ''}')
                .where((t) => t.isNotEmpty).toSet().join('، '),
          ));
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.07),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0F2B5B), Color(0xFF1E3F80)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('सुपर जोन–${sz['name']}  ब्लाक ${sz['block'] ?? '—'}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                Text('जिला: ${sz['district'] ?? '—'}  |  कुल ग्राम पंचायत: $gpTotal',
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              _IAB(icon: Icons.person_add_outlined, color: Colors.teal[200]!,
                  onTap: onManageOfficers, tooltip: 'अधिकारी'),
              _IAB(icon: Icons.add_circle_outline, color: _kAccent,
                  onTap: onAddZone, tooltip: 'जोन जोड़ें'),
              _IAB(icon: Icons.edit_outlined, color: _kAccent, onTap: onEdit),
              _IAB(icon: Icons.delete_outline, color: Colors.red[300]!, onTap: onDelete),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              _MC('${zones.length} जोन', Colors.blue),
              const SizedBox(width: 6),
              _MC('$sTotal सैक्टर', Colors.green),
              const SizedBox(width: 6),
              _MC('$gpTotal ग्राम पंचायत', Colors.orange),
            ]),
          ]),
        ),

        if ((sz['officers'] as List?)?.isNotEmpty == true)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: _kGold,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('सुपर जोन / क्षेत्र अधिकारी:',
                  style: TextStyle(color: _kSubtle, fontSize: 10, fontWeight: FontWeight.w700)),
              ...(sz['officers'] as List).map((o) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  const Icon(Icons.person_pin_outlined, size: 12, color: _kPrimary),
                  const SizedBox(width: 5),
                  Expanded(child: Text(
                    '${o['name'] ?? '—'}  ${o['user_rank'] ?? ''}'
                    '${(o['pno'] ?? '').toString().isNotEmpty ? '  PNO: ${o['pno']}' : ''}'
                    '${(o['mobile'] ?? '').toString().isNotEmpty ? '  मो: ${o['mobile']}' : ''}',
                    style: const TextStyle(color: _kDark, fontSize: 11),
                  )),
                ]),
              )),
            ]),
          ),

        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: _Empty(text: 'कोई जोन/सैक्टर नहीं'))
        else
          Padding(padding: const EdgeInsets.all(8),
              child: _Tab1Table(rows: rows, sz: sz)),
      ]),
    );
  }
}

class _R1 {
  final int zi; final Map z; final Map? s; final int? sGlobal;
  final List zOff; final String gpNames, thanas;
  const _R1({required this.zi, required this.z, required this.s,
      required this.sGlobal, required this.zOff,
      required this.gpNames, required this.thanas});
}

class _Tab1Table extends StatelessWidget {
  final List<_R1> rows; final Map sz;
  const _Tab1Table({required this.rows, required this.sz});
  static const _ws = <int, double>{
    0: 54, 1: 40, 2: 155, 3: 110, 4: 44, 5: 165, 6: 115, 7: 230, 8: 88,
  };

  @override
  Widget build(BuildContext context) {
    final totalW = _ws.values.fold(0.0, (a, b) => a + b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: totalW),
        child: Column(children: [
          _header(),
          ...rows.asMap().entries.map((e) => _row(e.key, rows, sz)),
        ]),
      ),
    );
  }

  Widget _header() {
    const labels = [
      'सुपर\nजोन', 'जोन', 'जोनल अधिकारी\n/ जोनल पुलिस\nअधिकारी',
      'मुख्यालय', 'सैक्टर\nसं.', 'सैक्टर पुलिस\nअधिकारी का नाम',
      'मुख्यालय', 'ग्राम पंचायत का नाम', 'थाना',
    ];
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF5EAD0),
          border: Border.all(color: _kBorder, width: 0.7)),
      child: Row(children: List.generate(9, (i) => Container(
        width: _ws[i], padding: const EdgeInsets.all(6),
        decoration: _cellDec(right: i < 8, bottom: false),
        child: Text(labels[i],
            style: const TextStyle(color: _kDark, fontWeight: FontWeight.w800, fontSize: 10),
            textAlign: TextAlign.center),
      ))),
    );
  }

  Widget _row(int i, List<_R1> rows, Map sz) {
    final r = rows[i];
    final isFirstInZone = i == 0 || rows[i-1].zi != r.zi;
    final bg = r.zi.isOdd ? Colors.white : const Color(0xFFFFFDF7);
    final zOffText = r.zOff.isNotEmpty
        ? r.zOff.map((o) => '${o['name'] ?? ''}\n${o['user_rank'] ?? ''}').join('\n')
        : '—';
    final sOff  = (r.s?['officers'] as List? ?? []);
    final sText = sOff.isNotEmpty
        ? sOff.map((o) => '${o['name'] ?? ''}\n${o['user_rank'] ?? ''}\n${o['mobile'] ?? ''}').join('\n')
        : '—';

    return Container(
      decoration: BoxDecoration(color: bg,
          border: const Border(
            left: BorderSide(color: _kBorder, width: 0.7),
            right: BorderSide(color: _kBorder, width: 0.7),
            bottom: BorderSide(color: _kBorder, width: 0.7),
          )),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: _ws[0], height: 48, decoration: _cellDec(right: true, bottom: false),
          child: Center(child: i == 0
              ? RotatedBox(quarterTurns: 3,
                  child: Text('सुपर जोन–${sz['name']}',
                      style: const TextStyle(color: _kPrimary, fontSize: 9, fontWeight: FontWeight.w700)))
              : const SizedBox())),
        Container(width: _ws[1], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: isFirstInZone
              ? Center(child: Text('${r.zi + 1}',
                  style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w900, fontSize: 14)))
              : const SizedBox()),
        Container(width: _ws[2], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: isFirstInZone ? Text(zOffText, style: const TextStyle(fontSize: 11, color: _kDark))
              : const SizedBox()),
        Container(width: _ws[3], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: isFirstInZone
              ? Text('${r.z['hq_address'] ?? r.z['hqAddress'] ?? '—'}',
                  style: const TextStyle(fontSize: 11, color: _kDark))
              : const SizedBox()),
        Container(width: _ws[4], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: r.sGlobal != null
              ? Center(child: Text('${r.sGlobal}',
                  style: const TextStyle(color: _kGreen, fontWeight: FontWeight.w800, fontSize: 12)))
              : const SizedBox()),
        Container(width: _ws[5], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: Text(sText, style: const TextStyle(fontSize: 11, color: _kDark))),
        Container(width: _ws[6], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: Text('${r.s?['hq'] ?? r.z['hq_address'] ?? '—'}',
              style: const TextStyle(fontSize: 11, color: _kDark))),
        Container(width: _ws[7], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: Text(r.gpNames, style: const TextStyle(fontSize: 11, color: _kDark))),
        Container(width: _ws[8], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: false, bottom: false),
          child: Text(r.thanas, style: const TextStyle(fontSize: 11, color: _kDark))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 CARD — FIX: use IntrinsicHeight + proper widths to prevent overflow
// ══════════════════════════════════════════════════════════════════════════════
class _Tab2Card extends StatelessWidget {
  final Map sz, z;
  final VoidCallback onEditZone, onDeleteZone, onAddSector, onManageZoneOfficers;
  final void Function(Map) onEditSector, onAddGP, onManageSectorOfficers;
  final Future<void> Function(Map) onDeleteSector;
  const _Tab2Card({
    required this.sz, required this.z,
    required this.onEditZone, required this.onDeleteZone,
    required this.onAddSector, required this.onManageZoneOfficers,
    required this.onEditSector, required this.onDeleteSector,
    required this.onAddGP, required this.onManageSectorOfficers,
  });

  @override
  Widget build(BuildContext context) {
    final sectors = z['sectors'] as List? ?? [];
    final zOff    = z['officers'] as List? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kGreen.withOpacity(0.08),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF186A3B), Color(0xFF239B56)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('जोन: ${z['name']}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                Text('सुपर जोन: ${sz['name']}  |  ब्लॉक: ${sz['block'] ?? '—'}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              _IAB(icon: Icons.person_add_outlined, color: Colors.teal[200]!,
                  onTap: onManageZoneOfficers, tooltip: 'अधिकारी'),
              _IAB(icon: Icons.add_circle_outline, color: _kAccent,
                  onTap: onAddSector, tooltip: 'सैक्टर जोड़ें'),
              _IAB(icon: Icons.edit_outlined, color: _kAccent, onTap: onEditZone),
              _IAB(icon: Icons.delete_outline, color: Colors.red[300]!, onTap: onDeleteZone),
            ]),
            if (zOff.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 4),
              const Text('जोनल अधिकारी:', style: TextStyle(color: Colors.white70, fontSize: 10)),
              ...zOff.map((o) => Text(
                '• ${o['name'] ?? '—'}  ${o['user_rank'] ?? ''}  PNO: ${o['pno'] ?? '—'}  मो: ${o['mobile'] ?? '—'}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              )),
            ],
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(8),
          child: _Tab2Table(sectors: sectors,
              onEdit: onEditSector, onDelete: onDeleteSector,
              onAddGP: onAddGP, onManageOfficers: onManageSectorOfficers),
        ),
      ]),
    );
  }
}

class _Tab2Table extends StatelessWidget {
  final List sectors;
  final void Function(Map) onEdit, onAddGP, onManageOfficers;
  final Future<void> Function(Map) onDelete;
  const _Tab2Table({required this.sectors, required this.onEdit,
      required this.onDelete, required this.onAddGP,
      required this.onManageOfficers});

  // FIX overflow: reduced action column width, tightened others
  static const _ws = <int, double>{
    0: 40, 1: 180, 2: 180, 3: 120, 4: 180, 5: 90, 6: 88,
  };

  @override
  Widget build(BuildContext context) {
    final totalW = _ws.values.fold(0.0, (a, b) => a + b);
    final rows = <Map>[];
    int sSeq = 0;
    for (final s in sectors) {
      sSeq++;
      final gps    = s['panchayats'] as List? ?? [];
      final sOff   = s['officers'] as List? ?? [];
      final magStr = sOff.isNotEmpty
          ? '${sOff[0]['name'] ?? ''}\n${sOff[0]['user_rank'] ?? ''}\n${sOff[0]['mobile'] ?? ''}'
          : '—';
      final polStr = sOff.length > 1
          ? '${sOff[1]['name'] ?? ''}\n${sOff[1]['user_rank'] ?? ''}\n${sOff[1]['mobile'] ?? ''}'
          : magStr;

      if (gps.isEmpty) {
        rows.add({'s': s, 'sSeq': sSeq, 'mag': magStr, 'pol': polStr, 'gp': null, 'first': true});
      } else {
        for (int gi = 0; gi < gps.length; gi++) {
          rows.add({'s': s, 'sSeq': sSeq, 'mag': gi == 0 ? magStr : '',
              'pol': gi == 0 ? polStr : '', 'gp': gps[gi], 'first': gi == 0});
        }
      }
    }

    if (rows.isEmpty) return const _Empty(text: 'कोई सैक्टर नहीं');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: totalW),
        child: Column(children: [
          // Header
          Container(
            decoration: BoxDecoration(color: const Color(0xFFE8F5E9),
                border: Border.all(color: _kBorder, width: 0.7)),
            child: Row(children: [
              _th(0, 'सैक्टर\nसं.'),
              _th(1, 'सैक्टर मजिस्ट्रेट\n(नाम/पद/मोबाइल)'),
              _th(2, 'सैक्टर पुलिस अधिकारी\n(नाम/पद/मोबाइल)'),
              _th(3, 'ग्राम पंचायत'),
              _th(4, 'मतदेय स्थल\n(केन्द्र)'),
              _th(5, 'मतदान\nकेन्द्र'),
              _th(6, 'एक्शन', last: true),
            ]),
          ),
          ...rows.asMap().entries.map((e) {
            final i     = e.key; final r = e.value;
            final gp    = r['gp'] as Map?;
            final s     = r['s'] as Map;
            final first = r['first'] as bool;
            final bg    = i.isEven ? Colors.white : const Color(0xFFF1F8E9);

            final centers  = gp != null ? (gp['centers'] as List? ?? []) : <Map>[];
            final sthalStr = centers.map((c) => '${c['name']}').join('\n');
            // FIX: matdan kendra = room numbers of matdan sthal
            final kStr = centers.map((c) {
              final kendras = c['kendras'];
              if (kendras is List) return kendras.map((k) => '${k['room_number']}').join(', ');
              if (kendras is String) return kendras;
              if (kendras is int) return kendras.toString();
              return '';
            }).where((e) => e.isNotEmpty).join(' | ');

            return Container(
              decoration: BoxDecoration(color: bg,
                  border: const Border(
                    left: BorderSide(color: _kBorder, width: 0.7),
                    right: BorderSide(color: _kBorder, width: 0.7),
                    bottom: BorderSide(color: _kBorder, width: 0.7),
                  )),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _cell(0, first ? Text('${r['sSeq']}',
                    style: const TextStyle(color: _kGreen, fontWeight: FontWeight.w900, fontSize: 14),
                    textAlign: TextAlign.center) : const SizedBox()),
                _cell(1, first ? Text('${r['mag']}', style: const TextStyle(fontSize: 11, color: _kDark)) : const SizedBox()),
                _cell(2, first ? Text('${r['pol']}', style: const TextStyle(fontSize: 11, color: _kDark)) : const SizedBox()),
                _cell(3, Text('${gp?['name'] ?? '—'}', style: const TextStyle(fontSize: 11, color: _kDark))),
                _cell(4, Text(sthalStr.isEmpty ? '—' : sthalStr, style: const TextStyle(fontSize: 11, color: _kDark))),
                _cell(5, Text(kStr.isEmpty ? '—' : kStr, style: const TextStyle(fontSize: 11, color: _kDark))),
                // FIX: use Wrap instead of Row to prevent overflow
                _cell(6, Wrap(spacing: 2, runSpacing: 2, children: [
                  _IAB(icon: Icons.person_add_outlined, color: Colors.teal, tooltip: 'अधिकारी',
                      onTap: () => onManageOfficers(s)),
                  _IAB(icon: Icons.add, color: _kGreen, onTap: () => onAddGP(s), tooltip: 'GP जोड़ें'),
                  _IAB(icon: Icons.edit_outlined, color: _kGreen, onTap: () => onEdit(s)),
                  _IAB(icon: Icons.delete_outline, color: _kRed, onTap: () => onDelete(s)),
                ]), last: true),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  Widget _th(int i, String t, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false, bg: const Color(0xFFE8F5E9)),
    child: Text(t, style: const TextStyle(color: Color(0xFF1B5E20),
        fontWeight: FontWeight.w800, fontSize: 10), textAlign: TextAlign.center),
  );

  Widget _cell(int i, Widget child, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false),
    child: child,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 CARD
// ══════════════════════════════════════════════════════════════════════════════
class _Tab3Card extends StatelessWidget {
  final Map sz, z, s, gp;
  final VoidCallback onAddCenter;
  final void Function(Map) onEditCenter, onAddKendra, onManageStaff;
  final Future<void> Function(Map) onDeleteCenter, onDeleteKendra;
  const _Tab3Card({required this.sz, required this.z, required this.s,
      required this.gp, required this.onAddCenter, required this.onEditCenter,
      required this.onDeleteCenter, required this.onAddKendra,
      required this.onDeleteKendra, required this.onManageStaff});

  @override
  Widget build(BuildContext context) {
    final centers = gp['centers'] as List? ?? [];
    int totalKendra = 0;
    for (final c in centers) {
      final k = c['kendras'] as List? ?? [];
      totalKendra += k.isEmpty ? 1 : k.length;
    }

    final rows = <Map>[];
    int sthalNo = 1, kendraG = 1;
    for (final c in centers) {
      final kendras = c['kendras'] as List? ?? [];
      if (kendras.isEmpty) {
        rows.add({'c': c, 'k': null, 'kNo': kendraG, 'sNo': sthalNo, 'first': true});
        sthalNo++; kendraG++;
      } else {
        for (int ki = 0; ki < kendras.length; ki++) {
          rows.add({'c': c, 'k': kendras[ki], 'kNo': kendraG,
              'sNo': ki == 0 ? sthalNo : null, 'first': ki == 0});
          kendraG++;
        }
        sthalNo++;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kPurple.withOpacity(0.08),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF6C3483), Color(0xFF8E44AD)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('बूथ ड्यूटी – ब्लॉक ${sz['block'] ?? sz['name']}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                Wrap(spacing: 12, children: [
                  Text('ग्राम पंचायत: ${gp['name']}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  Text('सैक्टर: ${s['name']}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  Text('जोन: ${z['name']}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _GoldChip('मतदेय स्थल: ${centers.length}'),
                const SizedBox(height: 4),
                _GoldChip('मतदान केन्द्र: $totalKendra'),
              ]),
            ]),
            const SizedBox(height: 6),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  foregroundColor: Colors.white, elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('मतदेय स्थल जोड़ें', style: TextStyle(fontSize: 11)),
              onPressed: onAddCenter,
            ),
          ]),
        ),

        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: _Empty(text: 'कोई मतदेय स्थल नहीं'))
        else
          Padding(
            padding: const EdgeInsets.all(8),
            child: _Tab3Table(rows: rows, z: z, s: s, gp: gp,
                onEditCenter: onEditCenter, onDeleteCenter: onDeleteCenter,
                onAddKendra: onAddKendra, onDeleteKendra: onDeleteKendra,
                onManageStaff: onManageStaff),
          ),
      ]),
    );
  }
}

class _Tab3Table extends StatelessWidget {
  final List<Map> rows; final Map z, s, gp;
  final void Function(Map) onEditCenter, onAddKendra, onManageStaff;
  final Future<void> Function(Map) onDeleteCenter, onDeleteKendra;
  const _Tab3Table({required this.rows, required this.z, required this.s,
      required this.gp, required this.onEditCenter, required this.onDeleteCenter,
      required this.onAddKendra, required this.onDeleteKendra,
      required this.onManageStaff});

  static const _ws = <int, double>{
    0: 44, 1: 160, 2: 44, 3: 160, 4: 54, 5: 58, 6: 80,
    7: 200, 8: 115, 9: 50, 10: 88,
  };

  @override
  Widget build(BuildContext context) {
    final totalW = _ws.values.fold(0.0, (a, b) => a + b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: totalW),
        child: Column(children: [
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF3E5F5),
                border: Border.all(color: _kBorder, width: 0.7)),
            child: Row(children: [
              _th(0, 'मतदान\nकेन्द्र की\nसंख्या'),
              _th(1, 'मतदान केन्द्र\nका नाम'),
              _th(2, 'मतदेय\nसं.'),
              _th(3, 'मतदान स्थल\nका नाम'),
              _th(4, 'जोन\nसंख्या'),
              _th(5, 'सैक्टर\nसंख्या'),
              _th(6, 'थाना'),
              _th(7, 'ड्यूटी पर लगाया\nपुलिस का नाम'),
              _th(8, 'मोबाईल\nनम्बर'),
              _th(9, 'बस\nनं.'),
              _th(10, 'एक्शन', last: true),
            ]),
          ),
          ...rows.asMap().entries.map((e) {
            final i     = e.key; final r = e.value;
            final c     = r['c'] as Map;
            final k     = r['k'] as Map?;
            final first = r['first'] as bool? ?? true;
            final bg    = i.isEven ? Colors.white : const Color(0xFFFDF4FF);

            final duty  = c['duty_officers'] as List? ?? [];
            final dText = duty.isNotEmpty
                ? duty.map((d) => '${d['name'] ?? ''}  ${d['pno'] ?? ''}\n${d['user_rank'] ?? ''}').join('\n')
                : '—';
            final mText = duty.isNotEmpty
                ? duty.map((d) => '${d['mobile'] ?? ''}').where((m) => m.isNotEmpty).join('\n')
                : '—';

            final kLabel = k != null
                ? '${c['name']} क.नं. ${k['room_number']}'
                : '${c['name']}';
            final typeColor = _sensitivityColor(c['center_type'] as String?);

            return Container(
              decoration: BoxDecoration(color: bg,
                  border: const Border(
                    left: BorderSide(color: _kBorder, width: 0.7),
                    right: BorderSide(color: _kBorder, width: 0.7),
                    bottom: BorderSide(color: _kBorder, width: 0.7),
                  )),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _cell(0, Center(child: Text('${r['kNo']}',
                    style: const TextStyle(color: _kPurple, fontWeight: FontWeight.w800, fontSize: 13)))),
                _cell(1, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kLabel, style: const TextStyle(color: _kDark, fontSize: 11)),
                  Container(margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: typeColor.withOpacity(0.4))),
                    child: Text('${c['center_type'] ?? 'C'}',
                        style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.w800))),
                ])),
                _cell(2, first && r['sNo'] != null
                    ? Center(child: Text('${r['sNo']}',
                        style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 12)))
                    : const SizedBox()),
                _cell(3, first ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c['name']}', style: const TextStyle(color: _kDark, fontSize: 11)),
                    if ((c['address'] ?? '').toString().isNotEmpty)
                      Text('${c['address']}', style: const TextStyle(color: _kSubtle, fontSize: 9)),
                  ]) : const SizedBox()),
                _cell(4, Center(child: Text('${z['name']}',
                    style: const TextStyle(color: _kDark, fontSize: 10)))),
                _cell(5, Center(child: Text('${s['name']}',
                    style: const TextStyle(color: _kDark, fontSize: 10)))),
                _cell(6, Text('${c['thana'] ?? gp['thana'] ?? '—'}',
                    style: const TextStyle(color: _kDark, fontSize: 11))),
                _cell(7, Text(dText, style: const TextStyle(color: _kDark, fontSize: 11))),
                _cell(8, Text(mText,
                    style: const TextStyle(color: _kDark, fontSize: 11, fontFamily: 'monospace'))),
                _cell(9, Center(child: Text('${c['bus_no'] ?? '—'}',
                    style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 11)))),
                _cell(10, Wrap(spacing: 2, runSpacing: 2, children: [
                  _IAB(icon: Icons.people_alt_outlined, color: _kGreen, tooltip: 'स्टाफ',
                      onTap: () => onManageStaff(c)),
                  _IAB(icon: Icons.add_box_outlined, color: _kPrimary, tooltip: 'कक्ष जोड़ें',
                      onTap: () => onAddKendra(c)),
                  _IAB(icon: Icons.edit_outlined, color: _kPurple, onTap: () => onEditCenter(c)),
                  _IAB(icon: Icons.delete_outline, color: _kRed, onTap: () => onDeleteCenter(c)),
                  if (k != null) _IAB(icon: Icons.remove_circle_outline, color: Colors.orange,
                      tooltip: 'कक्ष हटाएं', onTap: () => onDeleteKendra(k)),
                ]), last: true),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  Widget _th(int i, String t, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false, bg: const Color(0xFFF3E5F5)),
    child: Text(t, style: const TextStyle(color: _kPurple,
        fontWeight: FontWeight.w800, fontSize: 9.5), textAlign: TextAlign.center),
  );
  Widget _cell(int i, Widget child, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false), child: child,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TINY SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════
class _DI { final String value, label; const _DI(this.value, this.label); }

class _FDrop extends StatelessWidget {
  final String label, placeholder; final String? value;
  final List<_DI> items; final ValueChanged<String?> onChanged;
  const _FDrop({required this.label, required this.placeholder, required this.value,
      required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: _kSubtle, fontSize: 9, fontWeight: FontWeight.w700)),
    const SizedBox(height: 3),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 165),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: value != null ? _kPrimary : _kBorder, width: 1.5)),
      child: DropdownButton<String>(
        value: value, underline: const SizedBox(), isExpanded: true,
        hint: Text(placeholder, style: const TextStyle(color: _kSubtle, fontSize: 12),
            overflow: TextOverflow.ellipsis),
        style: const TextStyle(color: _kDark, fontSize: 12),
        dropdownColor: Colors.white,
        items: [
          DropdownMenuItem<String>(value: null,
              child: Text(placeholder, style: const TextStyle(color: _kSubtle, fontSize: 12))),
          ...items.map((i) => DropdownMenuItem<String>(value: i.value,
              child: Text(i.label, style: const TextStyle(color: _kDark, fontSize: 12),
                  overflow: TextOverflow.ellipsis))),
        ],
        onChanged: onChanged,
      ),
    ),
  ]);
}

class _IAB extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  final String? tooltip;
  const _IAB({required this.icon, required this.color, required this.onTap, this.tooltip});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6),
        child: Padding(padding: const EdgeInsets.all(4),
            child: Icon(icon, color: color, size: 18))),
  );
}

class _GoldChip extends StatelessWidget {
  final String label;
  const _GoldChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(7)),
    child: Text(label, style: const TextStyle(
        color: _kAccent, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

class _MC extends StatelessWidget {
  final String label; final Color color;
  const _MC(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.inbox_outlined, size: 44, color: _kSubtle),
      const SizedBox(height: 8),
      Text(text, style: const TextStyle(color: _kSubtle, fontSize: 13)),
    ],
  ));
}

class _ErrorView extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: _kRed),
      const SizedBox(height: 10),
      const Text('डेटा लोड करने में त्रुटि',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _kDark)),
      const SizedBox(height: 6),
      Text(error, style: const TextStyle(color: _kSubtle, fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 14),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
        label: const Text('पुनः प्रयास', style: TextStyle(color: Colors.white)),
      ),
    ]),
  ));
}