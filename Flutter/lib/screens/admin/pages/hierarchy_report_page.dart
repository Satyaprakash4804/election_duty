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

// ── Cell border helper ────────────────────────────────────────────────────────
BoxDecoration _cellDec({bool right = true, bool bottom = true, Color? bg}) =>
    BoxDecoration(
      color: bg,
      border: Border(
        right:  right  ? const BorderSide(color: _kBorder) : BorderSide.none,
        bottom: bottom ? const BorderSide(color: _kBorder) : BorderSide.none,
      ),
    );

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

  // ── CRUD ─────────────────────────────────────────────────────────────────
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

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));

  // ── Print ─────────────────────────────────────────────────────────────────
  Future<void> _print() async {
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();
    final doc  = pw.Document();
    final idx  = _tab.index;

    if (idx == 0) {
      for (final sz in _filteredSZ) {
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(14),
          build: (_) => _pdfTab1(sz, font, bold),
        ));
      }
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

  // ─── PDF Tab 1 ─────────────────────────────────────────────────────────────
  // Matches Image 1: super zone title + table
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

    // GP count
    int gpTotal = 0;
    for (final z in zones) for (final s in (z['sectors'] as List? ?? []))
      gpTotal += ((s['panchayats'] as List?)?.length ?? 0);

    pw.Widget _th(String t) => pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 7),
          textAlign: pw.TextAlign.center),
    );
    pw.Widget _td(String t, {bool center = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(t, style: pw.TextStyle(font: font, fontSize: 7),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
    );

    return [
      // Title matching Image 1
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
          0: pw.FixedColumnWidth(28),
          1: pw.FlexColumnWidth(2.0),
          2: pw.FlexColumnWidth(1.5),
          3: pw.FixedColumnWidth(28),
          4: pw.FlexColumnWidth(2.5),
          5: pw.FlexColumnWidth(1.5),
          6: pw.FlexColumnWidth(3.0),
          7: pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(children: [
            _th('सुपर\nजोन'), _th('जोनल अधिकारी'), _th('मुख्यालय'),
            _th('सैक्टर'), _th('सैक्टर पुलिस अधिकारी का नाम'),
            _th('मुख्यालय'), _th('सैक्टर में लगने वाले ग्राम पंचायत का नाम'),
            _th('थाना'),
          ]),
          ...rows.map((r) => pw.TableRow(children: [
            _td(r[0], center: true), _td(r[1]), _td(r[2]),
            _td(r[3], center: true), _td(r[4]), _td(r[5]),
            _td(r[6]), _td(r[7]),
          ])),
        ],
      ),
    ];
  }

  // ─── PDF Tab 2 ─────────────────────────────────────────────────────────────
  // Matches Image 2
  List<pw.Widget> _pdfTab2(Map sz, Map z, pw.Font font, pw.Font bold) {
    final sectors = z['sectors'] as List? ?? [];
    final zOff    = (z['officers'] as List? ?? []);
    final szOff   = (sz['officers'] as List? ?? []);

    pw.Widget _th(String t) => pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 7),
          textAlign: pw.TextAlign.center),
    );
    pw.Widget _td(String t) => pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(t, style: pw.TextStyle(font: font, fontSize: 7)),
    );

    // Build rows: sector × gp × sthal/kendra
    final rows = <List<String>>[];
    int sSeq = 0;
    for (final s in sectors) {
      sSeq++;
      final sOff    = (s['officers'] as List? ?? []);
      // magistrate = first officer, police = second (or same if only one)
      final magStr  = sOff.isNotEmpty
          ? '${sOff[0]['name'] ?? ''} ${sOff[0]['user_rank'] ?? ''}\n${sOff[0]['mobile'] ?? ''}'
          : '—';
      final polStr  = sOff.length > 1
          ? '${sOff[1]['name'] ?? ''} ${sOff[1]['user_rank'] ?? ''}\n${sOff[1]['mobile'] ?? ''}'
          : magStr;

      final gps = s['panchayats'] as List? ?? [];
      if (gps.isEmpty) {
        rows.add(['$sSeq', magStr, polStr, '—', '—', '—']);
      } else {
        for (final gp in gps) {
          final centers = gp['centers'] as List? ?? [];
          final sthalNames = centers.map((c) => '${c['name']}').join('\n');
          final kendraStrs = centers.expand((c) => (c['kendras'] as List? ?? []))
              .map((k) => '${k['room_number']}').join(', ');
          rows.add([
            '$sSeq', magStr, polStr,
            '${gp['name']}',
            sthalNames.isEmpty ? '—' : sthalNames,
            kendraStrs.isEmpty ? '—' : kendraStrs,
          ]);
        }
      }
    }

    // Zone officer string
    final zOffStr = zOff.map((o) =>
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
          0: pw.FixedColumnWidth(28),
          1: pw.FlexColumnWidth(2.5),
          2: pw.FlexColumnWidth(2.5),
          3: pw.FlexColumnWidth(1.8),
          4: pw.FlexColumnWidth(2.5),
          5: pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(children: [
            _th('सैक्टर\nसं.'), _th('सैक्टर मजिस्ट्रेट\n(नाम/पद/मोबाइल)'),
            _th('सैक्टर पुलिस अधिकारी\n(नाम/पद/मोबाइल)'),
            _th('ग्राम पंचायत'), _th('मतदेय स्थल'), _th('मतदान केन्द्र'),
          ]),
          ...rows.map((r) => pw.TableRow(children: r.map(_td).toList())),
        ],
      ),
    ];
  }

  // ─── PDF Tab 3 ─────────────────────────────────────────────────────────────
  // Matches Image 3 exactly
  List<pw.Widget> _pdfTab3(Map sz, Map z, Map s, Map gp,
      pw.Font font, pw.Font bold) {
    final centers = gp['centers'] as List? ?? [];

    pw.Widget _th(String t) => pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 6.5),
          textAlign: pw.TextAlign.center),
    );
    pw.Widget _td(String t, {bool center = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(t, style: pw.TextStyle(font: font, fontSize: 6.5),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
    );

    // Count totals for header
    int totalKendra = 0;
    for (final c in centers) {
      final k = (c['kendras'] as List? ?? []);
      totalKendra += k.isEmpty ? 1 : k.length;
    }

    // Build rows — exactly as Image 3
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
          '$kendraGlobal',
          '${c['name']}\n${c['center_type'] ?? 'C'}',
          '$sthalNo',
          '${c['name']}',
          '${z['name']}', '${s['name']}',
          '${c['thana'] ?? gp['thana'] ?? '—'}',
          dutyText, mobileText,
          '${c['bus_no'] ?? '—'}',
        ]);
        sthalNo++; kendraGlobal++;
      } else {
        for (int ki = 0; ki < kendras.length; ki++) {
          rows.add([
            '$kendraGlobal',
            '${c['name']} क.नं. ${kendras[ki]['room_number']}\n${c['center_type'] ?? 'C'}',
            ki == 0 ? '$sthalNo' : '',
            ki == 0 ? '${c['name']}' : '',
            '${z['name']}', '${s['name']}',
            '${c['thana'] ?? gp['thana'] ?? '—'}',
            ki == 0 ? dutyText : '',
            ki == 0 ? mobileText : '',
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
        pw.Text('मतदान केन्द्र–$totalKendra',
            style: pw.TextStyle(font: bold, fontSize: 9)),
        pw.Text('मतदेय स्थल–${centers.length}',
            style: pw.TextStyle(font: bold, fontSize: 9)),
      ]),
      pw.Text('ग्राम पंचायत: ${gp['name']}  |  सैक्टर: ${s['name']}  |  जोन: ${z['name']}',
          style: pw.TextStyle(font: font, fontSize: 8)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: const {
          0: pw.FixedColumnWidth(24),
          1: pw.FlexColumnWidth(2.2),
          2: pw.FixedColumnWidth(24),
          3: pw.FlexColumnWidth(2.0),
          4: pw.FixedColumnWidth(30),
          5: pw.FixedColumnWidth(30),
          6: pw.FlexColumnWidth(1.2),
          7: pw.FlexColumnWidth(2.5),
          8: pw.FlexColumnWidth(1.4),
          9: pw.FixedColumnWidth(28),
        },
        children: [
          pw.TableRow(children: [
            _th('मतदान\nकेन्द्र की\nसंख्या'),
            _th('मतदान केन्द्र\nका नाम'),
            _th('मतदेय\nसं.'),
            _th('मतदान स्थल\nका नाम'),
            _th('जोन\nसंख्या'),
            _th('सैक्टर\nसंख्या'),
            _th('थाना'),
            _th('ड्यूटी पर लगाया\nपुलिस का नाम'),
            _th('मोबाईल\nनम्बर'),
            _th('बस\nनं.'),
          ]),
          ...rows.map((r) => pw.TableRow(children: [
            _td(r[0], center: true), _td(r[1]),
            _td(r[2], center: true), _td(r[3]),
            _td(r[4], center: true), _td(r[5], center: true),
            _td(r[6]), _td(r[7]), _td(r[8]),
            _td(r[9], center: true),
          ])),
        ],
      ),
    ];
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  void _addSuperZone() => _openDialog(
    title: 'सुपर जोन जोड़ें', color: _kPrimary, icon: Icons.layers_outlined,
    fields: {'name': 'नाम', 'district': 'जिला', 'block': 'ब्लॉक'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/super-zones',
          Map<String, dynamic>.from(data), token: t);          // ← cast
      _load();
    },
  );
  void _editSZ(Map sz) => _openDialog(
    title: 'सुपर जोन संपादित करें', color: _kPrimary, icon: Icons.edit_outlined,
    fields: {'name': 'नाम', 'district': 'जिला', 'block': 'ब्लॉक'},
    initial: {'name': sz['name'], 'district': sz['district'], 'block': sz['block']},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.put('/admin/hierarchy/super-zone/${sz['id']}',
          Map<String, dynamic>.from(data), token: t);           // ← cast
      _load();
    },
  );

  void _addZone(Map sz) => _openDialog(
    title: 'जोन जोड़ें – ${sz['name']}', color: _kGreen, icon: Icons.map_outlined,
    fields: {'name': 'जोन का नाम', 'hqAddress': 'मुख्यालय पता'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/super-zones/${sz['id']}/zones',
          Map<String, dynamic>.from(data), token: t);           // ← cast
      _load();
    },
  );

  void _editZone(Map z) => _openDialog(
    title: 'जोन संपादित करें', color: _kGreen, icon: Icons.edit_outlined,
    fields: {'name': 'जोन का नाम', 'hqAddress': 'मुख्यालय पता'},
    initial: {'name': z['name'], 'hqAddress': z['hq_address'] ?? z['hqAddress']},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.put('/admin/zones/${z['id']}',
          Map<String, dynamic>.from(data), token: t);           // ← cast
      _load();
    },
  );

  void _addSector(Map z) => _openDialog(
    title: 'सैक्टर जोड़ें – ${z['name']}', color: _kGreen, icon: Icons.add,
    fields: {'name': 'सैक्टर का नाम'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/zones/${z['id']}/sectors',
          Map<String, dynamic>.from(data), token: t);           // ← cast
      _load();
    },
  );

  void _editSector(Map s) => _openDialog(
    title: 'सैक्टर संपादित करें', color: _kGreen, icon: Icons.edit_outlined,
    fields: {'name': 'सैक्टर का नाम'},
    initial: {'name': s['name']},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.put('/admin/hierarchy/sector/${s['id']}',
          Map<String, dynamic>.from(data), token: t);           // ← cast
      _load();
    },
  );

  void _addGP(Map s) => _openDialog(
    title: 'ग्राम पंचायत जोड़ें – ${s['name']}', color: _kPurple, icon: Icons.add,
    fields: {'name': 'ग्राम पंचायत का नाम', 'address': 'पता'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/sectors/${s['id']}/gram-panchayats',
          Map<String, dynamic>.from(data), token: t);           // ← cast
      _load();
    },
  );

  void _addCenter(Map gp) => _openCenterDialog(null, gpId: gp['id']);
 
  void _editCenter(Map c) => _openCenterDialog(c);
 
  void _addKendra(Map c) => _openDialog(
    title: 'मतदान केन्द्र (कक्ष) जोड़ें', color: _kPurple, icon: Icons.add,
    fields: {'roomNumber': 'कक्ष संख्या'},
    onSave: (data) async {
      final t = await AuthService.getToken();
      await ApiService.post('/admin/centers/${c['id']}/rooms',
          Map<String, dynamic>.from(data), token: t);           // ← cast
      _load();
    },
  );

  void _openCenterDialog(Map? center, {int? gpId}) {
    final nameCtrl    = TextEditingController(text: center?['name'] ?? '');
    final addressCtrl = TextEditingController(text: center?['address'] ?? '');
    final thanaCtrl   = TextEditingController(text: center?['thana'] ?? '');
    final busCtrl     = TextEditingController(
        text: center?['bus_no'] ?? center?['busNo'] ?? '');
    String type       = center?['center_type'] ?? center?['centerType'] ?? 'C';
    final fk          = GlobalKey<FormState>();
 
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(center != null
              ? 'मतदेय स्थल संपादित करें'
              : 'मतदेय स्थल जोड़ें'),
          content: SizedBox(
            width: 360,
            child: Form(
              key: fk,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _field(nameCtrl, 'नाम *', required: true),
                const SizedBox(height: 8),
                _field(addressCtrl, 'पता'),
                const SizedBox(height: 8),
                _field(thanaCtrl, 'थाना'),
                const SizedBox(height: 8),
                Row(
                  children: ['A', 'B', 'C'].map((t) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ChoiceChip(
                      label: Text(t),
                      selected: type == t,
                      selectedColor: t == 'A'
                          ? Colors.red[100]
                          : t == 'B'
                              ? Colors.orange[100]
                              : Colors.blue[100],
                      onSelected: (_) => ss(() => type = t),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 8),
                _field(busCtrl, 'बस संख्या'),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kPurple),
              onPressed: () async {
                if (!fk.currentState!.validate()) return;
                Navigator.pop(ctx);
                // Explicit Map<String,dynamic> — fixes the cast error
                final data = <String, dynamic>{
                  'name':        nameCtrl.text.trim(),
                  'address':     addressCtrl.text.trim(),
                  'thana':       thanaCtrl.text.trim(),
                  'centerType':  type,
                  'busNo':       busCtrl.text.trim(),
                  'center_type': type,
                };
                final tok = await AuthService.getToken();
                if (center != null) {
                  await ApiService.put(
                      '/admin/hierarchy/sthal/${center['id']}',
                      data,
                      token: tok);
                } else {
                  await ApiService.post(
                      '/admin/gram-panchayats/$gpId/centers',
                      data,
                      token: tok);
                }
                _load();
              },
              child: const Text('सहेजें',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Staff assignment on election center
  void _openStaffDialog(Map center) async {
    final tok   = await AuthService.getToken();
    final sRes  = await ApiService.get('/admin/staff', token: tok);
    final all   = (sRes['data'] ?? []) as List;
    final unassigned = all.where((s) => s['isAssigned'] != true).toList();
    final assigned = (center['duty_officers'] as List? ?? []);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _StaffAssignDialog(
        center: center,
        unassigned: unassigned,
        assigned: assigned,
        onAssign: (staffId, busNo) async {
          final t = await AuthService.getToken();
          await ApiService.post('/admin/duties', {
            'staffId': staffId, 'centerId': center['id'], 'busNo': busNo,
          }, token: t);
          _load();
        },
        onRemove: (dutyId) async {
          final t = await AuthService.getToken();
          await ApiService.delete('/admin/duties/$dutyId', token: t);
          _load();
        },
      ),
    );
  }

  // Generic text dialog
  void _openDialog({
    required String title,
    required Color color,
    required IconData icon,
    required Map<String, String> fields,
    Map<String, dynamic>? initial,
    required Future<void> Function(Map<String, dynamic>) onSave, // ← typed
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
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800))),
          ]),
          content: SizedBox(
            width: 340,
            child: Form(
              key: fk,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: fields.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _field(ctrls[e.key]!, e.value,
                      required: e.key == 'name'),
                )).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: saving
                  ? null
                  : () async {
                      if (!fk.currentState!.validate()) return;
                      ss(() => saving = true);
                      try {
                        // Build Map<String,dynamic> explicitly — no cast needed
                        final data = <String, dynamic>{
                          for (final e in ctrls.entries)
                            e.key: e.value.text.trim(),
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
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('सहेजें',
                      style: TextStyle(color: Colors.white)),
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
                  // Filter bar
                  _buildFilterBar(),
                  Expanded(child: TabBarView(controller: _tab, children: [
                    _buildTab1(),
                    _buildTab2(),
                    _buildTab3(),
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

  // ══════════════════════════════════════════════════════════════════
  // TAB 1 — Super Zone view (Image 1)
  // ══════════════════════════════════════════════════════════════════
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
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // TAB 2 — Zone/Sector view (Image 2)
  // ══════════════════════════════════════════════════════════════════
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
        onEditZone:    () => _editZone(items[i]['z']),
        onDeleteZone:  () => _delete('/admin/zones', items[i]['z']['id'], '${items[i]['z']['name']}'),
        onAddSector:   () => _addSector(items[i]['z']),
        onEditSector:  _editSector,
        onDeleteSector: (s) => _delete('/admin/hierarchy/sector', s['id'], '${s['name']}'),
        onAddGP:       _addGP,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // TAB 3 — Booth Duty view (Image 3)
  // ══════════════════════════════════════════════════════════════════
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
        onAddCenter:  () => _addCenter(items[i]['gp']),
        onEditCenter: _editCenter,
        onDeleteCenter: (c) => _delete('/admin/hierarchy/sthal', c['id'], '${c['name']}'),
        onAddKendra:  _addKendra,
        onDeleteKendra: (k) => _delete('/admin/rooms', k['id'], '${k['room_number']}'),
        onManageStaff: _openStaffDialog,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 CARD — matches Image 1 table layout
// ══════════════════════════════════════════════════════════════════════════════
class _Tab1Card extends StatelessWidget {
  final Map sz;
  final VoidCallback onEdit, onDelete, onAddZone;
  const _Tab1Card({required this.sz, required this.onEdit,
      required this.onDelete, required this.onAddZone});

  @override
  Widget build(BuildContext context) {
    final zones = sz['zones'] as List? ?? [];
    int gpTotal = 0, sTotal = 0;
    for (final z in zones) {
      final secs = z['sectors'] as List? ?? [];
      sTotal += secs.length;
      for (final s in secs) gpTotal += ((s['panchayats'] as List?)?.length ?? 0);
    }

    // Build flat rows for table
    final rows = <_R1>[];
    int globalSec = 0;
    for (int zi = 0; zi < zones.length; zi++) {
      final z = zones[zi] as Map;
      final sectors = z['sectors'] as List? ?? [];
      final zOff = z['officers'] as List? ?? [];
      for (int si = 0; si < (sectors.isEmpty ? 1 : sectors.length); si++) {
        if (sectors.isEmpty) {
          rows.add(_R1(zi: zi, z: z, s: null, sGlobal: null,
              zOff: zOff, gpNames: '—', thanas: '—'));
        } else {
          final s    = sectors[si] as Map;
          globalSec++;
          final gps  = s['panchayats'] as List? ?? [];
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
        // ── Header (matches Image 1 title row)
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
              _IAB(icon: Icons.add_circle_outline, color: _kAccent, onTap: onAddZone, tooltip: 'जोन जोड़ें'),
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

        // ── Kshetra officers
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

        // ── Table matching Image 1
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
              child: _Empty(text: 'कोई जोन/सैक्टर नहीं'))
        else
          Padding(
            padding: const EdgeInsets.all(8),
            child: _Tab1Table(rows: rows,
  sz: sz,)
          ),
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
        child: Column(
          children: [
            _header(),
            ...rows.asMap().entries.map((e) => _row(e.key, rows, sz)),
          ],
        ),
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
        // Col 0: super zone (rotated, only first row)
        Container(width: _ws[0], height: 48,
          decoration: _cellDec(right: true, bottom: false),
          child: Center(child: i == 0
              ? RotatedBox(quarterTurns: 3,
                  child: Text('सुपर जोन–${sz['name']}',
                      style: const TextStyle(color: _kPrimary, fontSize: 9, fontWeight: FontWeight.w700)))
              : const SizedBox())),
        // Col 1: zone number
        Container(width: _ws[1], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: isFirstInZone
              ? Center(child: Text('${r.zi + 1}',
                  style: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w900, fontSize: 14)))
              : const SizedBox()),
        // Col 2: zonal officer
        Container(width: _ws[2], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: isFirstInZone ? Text(zOffText, style: const TextStyle(fontSize: 11, color: _kDark)) : const SizedBox()),
        // Col 3: zone HQ
        Container(width: _ws[3], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: isFirstInZone
              ? Text('${r.z['hq_address'] ?? r.z['hqAddress'] ?? '—'}',
                  style: const TextStyle(fontSize: 11, color: _kDark))
              : const SizedBox()),
        // Col 4: sector number
        Container(width: _ws[4], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: r.sGlobal != null
              ? Center(child: Text('${r.sGlobal}',
                  style: const TextStyle(color: _kGreen, fontWeight: FontWeight.w800, fontSize: 12)))
              : const SizedBox()),
        // Col 5: sector officer
        Container(width: _ws[5], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: Text(sText, style: const TextStyle(fontSize: 11, color: _kDark))),
        // Col 6: sector HQ (zone HQ fallback)
        Container(width: _ws[6], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: Text('${r.s?['hq'] ?? r.z['hq_address'] ?? '—'}',
              style: const TextStyle(fontSize: 11, color: _kDark))),
        // Col 7: GP names
        Container(width: _ws[7], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: true, bottom: false),
          child: Text(r.gpNames, style: const TextStyle(fontSize: 11, color: _kDark))),
        // Col 8: thana
        Container(width: _ws[8], padding: const EdgeInsets.all(6),
          decoration: _cellDec(right: false, bottom: false),
          child: Text(r.thanas, style: const TextStyle(fontSize: 11, color: _kDark))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 CARD — matches Image 2
// ══════════════════════════════════════════════════════════════════════════════
class _Tab2Card extends StatelessWidget {
  final Map sz, z;
  final VoidCallback onEditZone, onDeleteZone, onAddSector;
  final void Function(Map) onEditSector, onAddGP;
  final Future<void> Function(Map) onDeleteSector;
  const _Tab2Card({required this.sz, required this.z,
      required this.onEditZone, required this.onDeleteZone,
      required this.onAddSector, required this.onEditSector,
      required this.onDeleteSector, required this.onAddGP});

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
        // Header
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
              _IAB(icon: Icons.add_circle_outline, color: _kAccent, onTap: onAddSector, tooltip: 'सैक्टर जोड़ें'),
              _IAB(icon: Icons.edit_outlined, color: _kAccent, onTap: onEditZone),
              _IAB(icon: Icons.delete_outline, color: Colors.red[300]!, onTap: onDeleteZone),
            ]),
            if (zOff.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 4),
              const Text('जोनल मजिस्ट्रेट / जोनल पुलिस अधिकारी:',
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
              ...zOff.map((o) => Text(
                '• ${o['name'] ?? '—'}  ${o['user_rank'] ?? ''}  PNO: ${o['pno'] ?? '—'}  मो: ${o['mobile'] ?? '—'}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              )),
            ],
          ]),
        ),

        // Table
        Padding(
          padding: const EdgeInsets.all(8),
          child: _Tab2Table(sectors: sectors,
              onEdit: onEditSector, onDelete: onDeleteSector, onAddGP: onAddGP),
        ),
      ]),
    );
  }
}

class _Tab2Table extends StatelessWidget {
  final List sectors;
  final void Function(Map) onEdit, onAddGP;
  final Future<void> Function(Map) onDelete;
  const _Tab2Table({required this.sectors, required this.onEdit,
      required this.onDelete, required this.onAddGP});

  static const _ws = <int, double>{
    0: 44, 1: 190, 2: 190, 3: 130, 4: 190, 5: 100, 6: 76,
  };

  @override
  Widget build(BuildContext context) {
    final totalW = _ws.values.fold(0.0, (a, b) => a + b);
    // Build rows: one per GP per sector
    final rows = <Map>[];
    int sSeq = 0;
    for (final s in sectors) {
      sSeq++;
      final gps     = s['panchayats'] as List? ?? [];
      final sOff    = s['officers'] as List? ?? [];
      final magStr  = sOff.isNotEmpty
          ? '${sOff[0]['name'] ?? ''}\n${sOff[0]['user_rank'] ?? ''}\n${sOff[0]['mobile'] ?? ''}'
          : '—';
      final polStr  = sOff.length > 1
          ? '${sOff[1]['name'] ?? ''}\n${sOff[1]['user_rank'] ?? ''}\n${sOff[1]['mobile'] ?? ''}'
          : magStr;

      if (gps.isEmpty) {
        rows.add({'s': s, 'sSeq': sSeq, 'mag': magStr, 'pol': polStr,
            'gp': null, 'first': true});
      } else {
        for (int gi = 0; gi < gps.length; gi++) {
          rows.add({'s': s, 'sSeq': sSeq, 'mag': gi == 0 ? magStr : '',
              'pol': gi == 0 ? polStr : '',
              'gp': gps[gi], 'first': gi == 0});
        }
      }
    }

    if (rows.isEmpty) return const _Empty(text: 'कोई सैक्टर नहीं');

    return SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: ConstrainedBox(
    constraints: BoxConstraints(minWidth: totalW),
    child: Column(
      children: [
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
        final i   = e.key; final r = e.value;
        final gp  = r['gp'] as Map?;
        final s   = r['s'] as Map;
        final first = r['first'] as bool;
        final bg  = (i ~/ 1).isEven ? Colors.white : const Color(0xFFF1F8E9);

        final centers = gp != null ? (gp['centers'] as List? ?? []) : <Map>[];
        final sthalStr = centers.map((c) => '${c['name']}').join('\n');
        final kStr = centers.map((c) {
          final kendras = c['kendras'];

          if (kendras is List) {
            return kendras.map((k) => '${k['room_number']}').join(', ');
          } else if (kendras is String) {
            return kendras; // already "4, 3"
          } else if (kendras is int) {
            return kendras.toString();
          }

          return '';
        }).where((e) => e.isNotEmpty).join(', ');
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
            _cell(6, Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _IAB(icon: Icons.add, color: _kGreen, onTap: () => onAddGP(s), tooltip: 'GP जोड़ें'),
              _IAB(icon: Icons.edit_outlined, color: _kGreen, onTap: () => onEdit(s)),
              _IAB(icon: Icons.delete_outline, color: _kRed, onTap: () => onDelete(s)),
            ]), last: true),
          ]),
        );
      }),
    ])));
  }

  Widget _th(int i, String t, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false,
        bg: const Color(0xFFE8F5E9)),
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
// TAB 3 CARD — matches Image 3
// ══════════════════════════════════════════════════════════════════════════════
class _Tab3Card extends StatelessWidget {
  final Map sz, z, s, gp;
  final VoidCallback onAddCenter;
  final void Function(Map) onEditCenter, onAddKendra, onManageStaff;
  final Future<void> Function(Map) onDeleteCenter;
  final Future<void> Function(Map) onDeleteKendra;
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

    // Build rows — Image 3 layout
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
        // Header — matches Image 3
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

        // Table — exactly Image 3 columns
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
              child: _Empty(text: 'कोई मतदेय स्थल नहीं'))
        else
          Padding(
            padding: const EdgeInsets.all(8),
            child: _Tab3Table(rows: rows, z: z, s: s, gp: gp,
                onEditCenter: onEditCenter,
                onDeleteCenter: onDeleteCenter,
                onAddKendra: onAddKendra,
                onDeleteKendra: onDeleteKendra,
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
    0: 44,  // मतदान केन्द्र की संख्या
    1: 160, // मतदान केन्द्र का नाम + type
    2: 44,  // मतदेय सं.
    3: 160, // मतदान स्थल का नाम + address
    4: 54,  // जोन
    5: 58,  // सैक्टर
    6: 80,  // थाना
    7: 200, // ड्यूटी पुलिस
    8: 115, // मोबाईल
    9: 50,  // बस नं.
    10: 88, // एक्शन
  };

  @override
  Widget build(BuildContext context) {
    final totalW = _ws.values.fold(0.0, (a, b) => a + b);
    return SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: ConstrainedBox(
    constraints: BoxConstraints(minWidth: totalW),
    child: Column(
      children: [
      // Header row
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
        final i   = e.key; final r = e.value;
        final c   = r['c'] as Map;
        final k   = r['k'] as Map?;
        final first = r['first'] as bool? ?? true;
        final bg  = i.isEven ? Colors.white : const Color(0xFFFDF4FF);

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
        final typeColor = c['center_type'] == 'A' ? _kRed
            : c['center_type'] == 'B' ? const Color(0xFFE67E22)
            : const Color(0xFF1A5276);

        return Container(
          decoration: BoxDecoration(color: bg,
              border: const Border(
                left: BorderSide(color: _kBorder, width: 0.7),
                right: BorderSide(color: _kBorder, width: 0.7),
                bottom: BorderSide(color: _kBorder, width: 0.7),
              )),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Col 0: kendra serial
            _cell(0, Center(child: Text('${r['kNo']}',
                style: const TextStyle(color: _kPurple, fontWeight: FontWeight.w800, fontSize: 13)))),
            // Col 1: center name + type badge
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
            // Col 2: matday number (sthalNo) — only first kendra
            _cell(2, first && r['sNo'] != null
                ? Center(child: Text('${r['sNo']}',
                    style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 12)))
                : const SizedBox()),
            // Col 3: sthal name + address — only first kendra
            _cell(3, first
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c['name']}', style: const TextStyle(color: _kDark, fontSize: 11)),
                    if ((c['address'] ?? '').toString().isNotEmpty)
                      Text('${c['address']}', style: const TextStyle(color: _kSubtle, fontSize: 9)),
                  ])
                : const SizedBox()),
            // Col 4: zone
            _cell(4, Center(child: Text('${z['name']}',
                style: const TextStyle(color: _kDark, fontSize: 10)))),
            // Col 5: sector
            _cell(5, Center(child: Text('${s['name']}',
                style: const TextStyle(color: _kDark, fontSize: 10)))),
            // Col 6: thana
            _cell(6, Text('${c['thana'] ?? gp['thana'] ?? '—'}',
                style: const TextStyle(color: _kDark, fontSize: 11))),
            // Col 7: duty police
            _cell(7, Text(dText, style: const TextStyle(color: _kDark, fontSize: 11))),
            // Col 8: mobile
            _cell(8, Text(mText,
                style: const TextStyle(color: _kDark, fontSize: 11, fontFamily: 'monospace'))),
            // Col 9: bus
            _cell(9, Center(child: Text('${c['bus_no'] ?? '—'}',
                style: const TextStyle(color: _kDark, fontWeight: FontWeight.w700, fontSize: 11)))),
            // Col 10: actions
            _cell(10, Wrap(spacing: 2, runSpacing: 2, children: [
              _IAB(icon: Icons.people_alt_outlined, color: _kGreen, tooltip: 'स्टाफ',
                  onTap: () => onManageStaff(c)),
              _IAB(icon: Icons.add_box_outlined, color: _kPrimary, tooltip: 'कक्ष जोड़ें',
                  onTap: () => onAddKendra(c)),
              _IAB(icon: Icons.edit_outlined, color: _kPurple,
                  onTap: () => onEditCenter(c)),
              _IAB(icon: Icons.delete_outline, color: _kRed,
                  onTap: () => onDeleteCenter(c)),
              // Delete kendra if on a kendra row
              if (k != null) _IAB(icon: Icons.remove_circle_outline, color: Colors.orange,
                  tooltip: 'कक्ष हटाएं', onTap: () => onDeleteKendra(k)),
            ]), last: true),
          ]),
        );
      }),
    ])));
  }

  Widget _th(int i, String t, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false, bg: const Color(0xFFF3E5F5)),
    child: Text(t, style: const TextStyle(color: _kPurple,
        fontWeight: FontWeight.w800, fontSize: 9.5), textAlign: TextAlign.center),
  );

  Widget _cell(int i, Widget child, {bool last = false}) => Container(
    width: _ws[i], padding: const EdgeInsets.all(6),
    decoration: _cellDec(right: !last, bottom: false),
    child: child,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// STAFF ASSIGN DIALOG
// ══════════════════════════════════════════════════════════════════════════════
class _StaffAssignDialog extends StatefulWidget {
  final Map center; final List unassigned, assigned;
  final Future<void> Function(int, String) onAssign;
  final Future<void> Function(int) onRemove;
  const _StaffAssignDialog({required this.center, required this.unassigned,
      required this.assigned, required this.onAssign, required this.onRemove});
  @override State<_StaffAssignDialog> createState() => _StaffAssignDialogState();
}
class _StaffAssignDialogState extends State<_StaffAssignDialog> {
  final _busCtrl    = TextEditingController();
  final _searchCtrl = TextEditingController();
  List _filtered    = [];
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _filtered = widget.unassigned;
    _busCtrl.text = '${widget.center['bus_no'] ?? ''}';
  }

  void _filterStaff(String q) => setState(() {
    _filtered = q.isEmpty ? widget.unassigned
        : widget.unassigned.where((s) =>
            '${s['name']}'.toLowerCase().contains(q.toLowerCase()) ||
            '${s['pno']}'.toLowerCase().contains(q.toLowerCase()) ||
            '${s['thana']}'.toLowerCase().contains(q.toLowerCase())).toList();
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            decoration: const BoxDecoration(color: _kPurple,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(children: [
              const Icon(Icons.people_alt_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('स्टाफ प्रबंधन – ${widget.center['name']}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Already assigned staff
              if (widget.assigned.isNotEmpty) ...[
                const Text('असाइन किए गए स्टाफ:', style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12, color: _kSubtle)),
                const SizedBox(height: 6),
                ...widget.assigned.map((d) => Container(
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
                      onPressed: () async {
                        await widget.onRemove(d['id']);
                        Navigator.pop(context);
                      },
                    ),
                  ]),
                )),
                const Divider(height: 20),
              ],
              // Add staff
              if (widget.unassigned.isNotEmpty) ...[
                const Text('नया स्टाफ जोड़ें:', style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12, color: _kSubtle)),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl, onChanged: _filterStaff,
                  decoration: InputDecoration(
                    hintText: 'नाम, PNO, थाना से खोजें...',
                    prefixIcon: const Icon(Icons.search, size: 18, color: _kSubtle),
                    isDense: true, fillColor: const Color(0xFFF8F9FC), filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _kBorder)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Container(height: 180, decoration: BoxDecoration(
                  border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(8)),
                  child: ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
                    itemBuilder: (_, i) {
                      final s = _filtered[i];
                      final sel = _selectedId == s['id'];
                      return InkWell(
                        onTap: () => setState(() => _selectedId = sel ? null : s['id'] as int),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          color: sel ? _kPurple.withOpacity(0.07) : Colors.transparent,
                          child: Row(children: [
                            AnimatedContainer(duration: const Duration(milliseconds: 150),
                              width: 26, height: 26,
                              decoration: BoxDecoration(
                                  color: sel ? _kPurple : const Color(0xFFF5EAD0),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: sel ? _kPurple : _kBorder)),
                              child: sel ? const Icon(Icons.check, color: Colors.white, size: 14) : null),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${s['name']}', style: TextStyle(
                                  color: sel ? _kPurple : _kDark,
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                              Text('PNO: ${s['pno']}  •  ${s['thana']}',
                                  style: const TextStyle(color: _kSubtle, fontSize: 10)),
                            ])),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
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
              ] else
                const Text('सभी स्टाफ असाइन किए जा चुके हैं',
                    style: TextStyle(color: _kSubtle, fontSize: 12)),
            ]),
          )),
          // Footer
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child:
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('बंद करें'),
              )),
              if (_selectedId != null) ...[
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kPurple),
                  onPressed: () async {
                    await widget.onAssign(_selectedId!, _busCtrl.text);
                    Navigator.pop(context);
                  },
                  child: const Text('असाइन करें', style: TextStyle(color: Colors.white)),
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
        color: color == Colors.white ? Colors.white : color,
        fontSize: 10, fontWeight: FontWeight.w700)),
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