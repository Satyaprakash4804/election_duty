import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ── PALETTE ───────────────────────────────────────────────────────────────────
const _kBg      = Color(0xFFFDF6E3);
const _kPrimary = Color(0xFF0F2B5B);
const _kGreen   = Color(0xFF186A3B);
const _kPurple  = Color(0xFF6C3483);
const _kRed     = Color(0xFFC0392B);
const _kDark    = Color(0xFF1A2332);
const _kSubtle  = Color(0xFF6B7C93);
const _kBorder  = Color(0xFFE8EDF7);
const _kGold    = Color(0xFFF5EAD0);
const _kAccent  = Color(0xFFFBBF24);

// ─────────────────────────────────────────────────────────────────────────────
class HierarchyReportPage extends StatefulWidget {
  const HierarchyReportPage({super.key});
  @override
  State<HierarchyReportPage> createState() => _HierarchyReportPageState();
}

class _HierarchyReportPageState extends State<HierarchyReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List _data = [];
  bool _loading = true;
  String? _error;

  String? _selSZ, _selZone, _selSector, _selGP;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) return;
      setState(() => _selSZ = _selZone = _selSector = _selGP = null);
    });
    _load();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/hierarchy/full', token: token);
      setState(() {
        _data    = res is List ? res : (res['data'] ?? res ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── filter helpers ────────────────────────────────────────────────────────
  List get _szList => _data;

  List get _zoneList {
    if (_selSZ == null) return _data.expand((s) => (s['zones'] as List? ?? [])).toList();
    final sz = _data.firstWhere((s) => '${s['id']}' == _selSZ, orElse: () => null);
    return sz == null ? [] : (sz['zones'] as List? ?? []);
  }

  List get _sectorList {
    final zones = _selZone == null ? _zoneList
        : _zoneList.where((z) => '${z['id']}' == _selZone).toList();
    return zones.expand((z) => (z['sectors'] as List? ?? [])).toList();
  }

  List get _gpList {
    final secs = _selSector == null ? _sectorList
        : _sectorList.where((s) => '${s['id']}' == _selSector).toList();
    return secs.expand((s) => (s['panchayats'] as List? ?? [])).toList();
  }

  List get _filteredSZ {
    if (_selSZ == null) return _data;
    return _data.where((sz) => '${sz['id']}' == _selSZ).toList();
  }

  List get _filteredZonePairs {
    final pairs = <Map>[];
    for (final sz in _filteredSZ) {
      for (final z in (sz['zones'] as List? ?? [])) {
        if (_selZone == null || '${z['id']}' == _selZone) pairs.add({'sz': sz, 'z': z});
      }
    }
    return pairs;
  }

  List get _filteredGPItems {
    final items = <Map>[];
    for (final sz in _filteredSZ) {
      for (final z in (sz['zones'] as List? ?? [])) {
        if (_selZone != null && '${z['id']}' != _selZone) continue;
        for (final s in (z['sectors'] as List? ?? [])) {
          if (_selSector != null && '${s['id']}' != _selSector) continue;
          for (final gp in (s['panchayats'] as List? ?? [])) {
            if (_selGP != null && '${gp['id']}' != _selGP) continue;
            items.add({'sz': sz, 'z': z, 's': s, 'gp': gp});
          }
        }
      }
    }
    return items;
  }

  // ── CRUD helpers ──────────────────────────────────────────────────────────
  Future<void> _deleteItem(String endpoint, int id, String name) async {
    final ok = await _confirmDelete(name);
    if (ok != true) return;
    try {
      final token = await AuthService.getToken();
      await ApiService.delete('$endpoint/$id', token: token);
      _load();
      if (mounted) _snack('सफलतापूर्वक हटाया गया', Colors.green);
    } catch (e) {
      if (mounted) _snack('त्रुटि: $e', _kRed);
    }
  }

  Future<bool?> _confirmDelete(String name) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('हटाने की पुष्टि करें',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      content: Text('"$name" को हटाना चाहते हैं?'),
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

  void _snack(String msg, Color color) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  // ── Print ─────────────────────────────────────────────────────────────────
  Future<void> _printCurrentTab() async {
    final doc = pw.Document();
    final tabIndex = _tabCtrl.index;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      build: (ctx) {
        if (tabIndex == 0) return _buildPdfTab1();
        if (tabIndex == 1) return _buildPdfTab2();
        return _buildPdfTab3();
      },
    ));

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  List<pw.Widget> _buildPdfTab1() {
    final widgets = <pw.Widget>[];
    for (final sz in _filteredSZ) {
      final zones = sz['zones'] as List? ?? [];
      int sNum = 0;
      final rows = <List<String>>[];
      for (final z in zones) {
        final sectors = z['sectors'] as List? ?? [];
        final zi = (zones.indexOf(z) + 1).toString();
        final zOfficers = (z['officers'] as List? ?? []);
        final zOfficerStr = zOfficers.isNotEmpty
            ? zOfficers.map((o) => '${o['name'] ?? ''} ${o['user_rank'] ?? ''}').join(', ') : '—';
        for (final s in sectors) {
          sNum++;
          final gps = s['panchayats'] as List? ?? [];
          final gpNames = gps.map((g) => '${g['name']}').join(', ');
          final thanas = gps.map((g) => '${g['thana'] ?? ''}').where((t) => t.isNotEmpty).toSet().join(', ');
          rows.add([zi, zOfficerStr, '${z['hq_address'] ?? '—'}',
            '$sNum', '${s['name']}', gpNames.isEmpty ? '—' : gpNames, thanas.isEmpty ? '—' : thanas]);
        }
      }
      widgets.add(pw.Text('सुपर जोन–${sz['name']}  |  जिला: ${sz['district'] ?? ''}  |  ब्लॉक: ${sz['block'] ?? ''}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(25), 1: const pw.FlexColumnWidth(2),
          2: const pw.FlexColumnWidth(2),   3: const pw.FixedColumnWidth(25),
          4: const pw.FlexColumnWidth(2),   5: const pw.FlexColumnWidth(3),
          6: const pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: ['जोन', 'जोनल अधिकारी', 'मुख्यालय', 'सैक्टर',
              'सैक्टर पुलिस अधिकारी', 'ग्राम पंचायत', 'थाना']
                .map((h) => pw.Padding(padding: const pw.EdgeInsets.all(4),
                child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))))
                .toList(),
          ),
          ...rows.map((r) => pw.TableRow(
            children: r.map((c) => pw.Padding(padding: const pw.EdgeInsets.all(3),
                child: pw.Text(c, style: const pw.TextStyle(fontSize: 8)))).toList(),
          )),
        ],
      ));
      widgets.add(pw.SizedBox(height: 12));
    }
    return widgets;
  }

  List<pw.Widget> _buildPdfTab2() {
    final widgets = <pw.Widget>[];
    for (final p in _filteredZonePairs) {
      final sz = p['sz'] as Map; final z = p['z'] as Map;
      final sectors = z['sectors'] as List? ?? [];
      final zOfficers = (z['officers'] as List? ?? []);
      final zStr = zOfficers.map((o) => '${o['name'] ?? ''} (${o['user_rank'] ?? ''}) मो: ${o['mobile'] ?? ''}').join(', ');
      final rows = <List<String>>[];
      int sSeq = 0;
      for (final s in sectors) {
        sSeq++;
        final sOfficers = s['officers'] as List? ?? [];
        final sStr = sOfficers.isNotEmpty
            ? sOfficers.map((o) => '${o['name'] ?? ''} ${o['user_rank'] ?? ''} ${o['mobile'] ?? ''}').join(', ') : '—';
        final gps = s['panchayats'] as List? ?? [];
        if (gps.isEmpty) {
          rows.add(['$sSeq', sStr, sStr, '—', '—', '—']);
        } else {
          for (final gp in gps) {
            final centers = gp['centers'] as List? ?? [];
            final centerNames = centers.map((c) => '${c['name']}').join(', ');
            final centerNums = centers.expand((c) => (c['kendras'] as List? ?? []))
                .map((k) => '${k['room_number']}').join(', ');
            rows.add(['$sSeq', sStr, sStr, '${gp['name']}', centerNames, centerNums.isEmpty ? '—' : centerNums]);
          }
        }
      }
      widgets.add(pw.Text('जोन: ${z['name']}  |  सुपर जोन: ${sz['name']}  |  ब्लॉक: ${sz['block'] ?? ''}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)));
      if (zStr.isNotEmpty) widgets.add(pw.Text('जोनल अधिकारी: $zStr', style: const pw.TextStyle(fontSize: 8)));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(25), 1: const pw.FlexColumnWidth(2.5),
          2: const pw.FlexColumnWidth(2.5), 3: const pw.FlexColumnWidth(2),
          4: const pw.FlexColumnWidth(2.5), 5: const pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: ['सैक्टर', 'सैक्टर मजिस्ट्रेट', 'सैक्टर पुलिस अधिकारी',
              'ग्राम पंचायत', 'मतदेय स्थल', 'मतदान केन्द्र']
                .map((h) => pw.Padding(padding: const pw.EdgeInsets.all(4),
                child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))))
                .toList(),
          ),
          ...rows.map((r) => pw.TableRow(
            children: r.map((c) => pw.Padding(padding: const pw.EdgeInsets.all(3),
                child: pw.Text(c, style: const pw.TextStyle(fontSize: 8)))).toList(),
          )),
        ],
      ));
      widgets.add(pw.SizedBox(height: 12));
    }
    return widgets;
  }

  List<pw.Widget> _buildPdfTab3() {
    final widgets = <pw.Widget>[];
    for (final item in _filteredGPItems) {
      final sz = item['sz'] as Map; final z = item['z'] as Map;
      final s = item['s'] as Map;  final gp = item['gp'] as Map;
      final centers = gp['centers'] as List? ?? [];
      final rows = <List<String>>[];
      int sno = 1;
      for (final c in centers) {
        final kendras = c['kendras'] as List? ?? [];
        final dutyOfficers = c['duty_officers'] as List? ?? [];
        final dutyStr = dutyOfficers.map((d) =>
          '${d['name'] ?? ''} ${d['pno'] ?? ''} ${d['user_rank'] ?? ''}').join(', ');
        if (kendras.isEmpty) {
          rows.add(['$sno', '${c['name']}', '${c['center_type'] ?? 'C'}', '—',
            '${c['name']}', '${z['name']}', '${s['name']}',
            '${c['thana'] ?? gp['thana'] ?? '—'}', dutyStr.isEmpty ? '—' : dutyStr,
            '${c['mobile'] ?? '—'}', '${c['bus_no'] ?? '—'}']);
          sno++;
        } else {
          for (int ki = 0; ki < kendras.length; ki++) {
            final k = kendras[ki];
            rows.add([ki == 0 ? '$sno' : '', '${c['name']}', '${c['center_type'] ?? 'C'}',
              '${k['room_number']}', '${c['name']}', '${z['name']}', '${s['name']}',
              '${c['thana'] ?? gp['thana'] ?? '—'}', dutyStr.isEmpty ? '—' : dutyStr,
              '${c['mobile'] ?? '—'}', '${c['bus_no'] ?? '—'}']);
            if (ki == 0) sno++;
          }
        }
      }
      widgets.add(pw.Text(
        'बूथ ड्यूटी — ब्लॉक ${sz['block'] ?? sz['name']}  |  '
        'ग्राम पंचायत: ${gp['name']}  |  सैक्टर: ${s['name']}  |  जोन: ${z['name']}',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(20),  1: const pw.FlexColumnWidth(2),
          2: const pw.FixedColumnWidth(25),  3: const pw.FixedColumnWidth(30),
          4: const pw.FlexColumnWidth(2),    5: const pw.FlexColumnWidth(1.5),
          6: const pw.FlexColumnWidth(1.5),  7: const pw.FlexColumnWidth(1.5),
          8: const pw.FlexColumnWidth(2.5),  9: const pw.FlexColumnWidth(1.5),
          10: const pw.FixedColumnWidth(25),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: ['सं.', 'मतदान केन्द्र', 'टाइप', 'मतदेय सं.',
              'मतदान स्थल', 'जोन', 'सैक्टर', 'थाना',
              'ड्यूटी पुलिस', 'मोबाईल', 'बस नं.']
                .map((h) => pw.Padding(padding: const pw.EdgeInsets.all(3),
                child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7))))
                .toList(),
          ),
          ...rows.map((r) => pw.TableRow(
            children: r.map((c) => pw.Padding(padding: const pw.EdgeInsets.all(3),
                child: pw.Text(c, style: const pw.TextStyle(fontSize: 7)))).toList(),
          )),
        ],
      ));
      widgets.add(pw.SizedBox(height: 12));
    }
    return widgets;
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  void _openEditSuperZone(Map sz) => showDialog(
    context: context,
    builder: (_) => _SuperZoneDialog(superZone: sz, onSave: (data) async {
      final token = await AuthService.getToken();
      await ApiService.put('/admin/hierarchy/super-zone/${sz['id']}', data, token: token);
      _load();
    }),
  );

  void _openAddSuperZone() => showDialog(
    context: context,
    builder: (_) => _SuperZoneDialog(superZone: null, onSave: (data) async {
      final token = await AuthService.getToken();
      await ApiService.post('/admin/super-zones', data, token: token);
      _load();
    }),
  );

  void _openEditSector(Map sector) => showDialog(
    context: context,
    builder: (_) => _SectorDialog(sector: sector, onSave: (data) async {
      final token = await AuthService.getToken();
      await ApiService.put('/admin/hierarchy/sector/${sector['id']}', data, token: token);
      _load();
    }),
  );

  void _openEditSthal(Map sthal) => showDialog(
    context: context,
    builder: (_) => _SthalDialog(sthal: sthal, onSave: (data) async {
      final token = await AuthService.getToken();
      await ApiService.put('/admin/hierarchy/sthal/${sthal['id']}', data, token: token);
      _load();
    }),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        elevation: 0,
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
          IconButton(
            icon: const Icon(Icons.print_outlined, color: Colors.white),
            tooltip: 'प्रिंट करें',
            onPressed: _printCurrentTab,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'रिफ्रेश',
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _kAccent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'सुपर जोन', icon: Icon(Icons.layers_outlined, size: 16)),
            Tab(text: 'सैक्टर',   icon: Icon(Icons.map_outlined, size: 16)),
            Tab(text: 'बूथ ड्यूटी', icon: Icon(Icons.how_to_vote_outlined, size: 16)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _SuperZoneTab(
                      data: _filteredSZ, allSZ: _szList, selSZ: _selSZ,
                      onSZChanged: (v) => setState(() { _selSZ = v; _selZone = null; }),
                      onDelete: (id, name) => _deleteItem('/admin/hierarchy/super-zone', id, name),
                      onEdit: _openEditSuperZone,
                      onAdd: _openAddSuperZone,
                    ),
                    _SectorTab(
                      pairs: _filteredZonePairs, allSZ: _szList, allZones: _zoneList,
                      selSZ: _selSZ, selZone: _selZone,
                      onSZChanged: (v) => setState(() { _selSZ = v; _selZone = null; }),
                      onZoneChanged: (v) => setState(() => _selZone = v),
                      onDeleteSector: (id, name) => _deleteItem('/admin/hierarchy/sector', id, name),
                      onEditSector: _openEditSector,
                    ),
                    _BoothDutyTab(
                      items: _filteredGPItems, allSZ: _szList, allZones: _zoneList,
                      allSectors: _sectorList, allGPs: _gpList,
                      selSZ: _selSZ, selZone: _selZone, selSector: _selSector, selGP: _selGP,
                      onSZChanged: (v) => setState(() { _selSZ = v; _selZone = _selSector = _selGP = null; }),
                      onZoneChanged: (v) => setState(() { _selZone = v; _selSector = _selGP = null; }),
                      onSectorChanged: (v) => setState(() { _selSector = v; _selGP = null; }),
                      onGPChanged: (v) => setState(() => _selGP = v),
                      onDeleteSthal: (id, name) => _deleteItem('/admin/hierarchy/sthal', id, name),
                      onEditSthal: _openEditSthal,
                    ),
                  ],
                ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 1 — सुपर जोन  (matches Image 1)
// Columns: सुपर जोन | जोन | जोनल अधिकारी | मुख्यालय | सैक्टर | सैक्टर पुलिस अधिकारी | मुख्यालय | ग्राम पंचायत | थाना
// ══════════════════════════════════════════════════════════════════════════════
class _SuperZoneTab extends StatelessWidget {
  final List data, allSZ;
  final String? selSZ;
  final ValueChanged<String?> onSZChanged;
  final Future<void> Function(int, String) onDelete;
  final void Function(Map) onEdit;
  final VoidCallback onAdd;

  const _SuperZoneTab({
    required this.data, required this.allSZ, required this.selSZ,
    required this.onSZChanged, required this.onDelete,
    required this.onEdit, required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _FilterBar(children: [
        _FilterDrop(label: 'सुपर जोन', value: selSZ, placeholder: 'सभी सुपर जोन',
          items: allSZ.map((s) => _DI('${s['id']}', '${s['name']}')).toList(),
          onChanged: onSZChanged),
        const Spacer(),
        _AddBtn(label: 'सुपर जोन जोड़ें', onTap: onAdd),
      ]),
      Expanded(
        child: data.isEmpty
            ? const _Empty(text: 'कोई सुपर जोन नहीं मिला')
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: data.length,
                itemBuilder: (_, i) => _SuperZoneCard(
                  sz: data[i],
                  onEdit: () => onEdit(data[i]),
                  onDelete: () => onDelete(data[i]['id'], '${data[i]['name']}'),
                ),
              ),
      ),
    ]);
  }
}

class _SuperZoneCard extends StatelessWidget {
  final Map sz;
  final VoidCallback onEdit, onDelete;
  const _SuperZoneCard({required this.sz, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final zones = sz['zones'] as List? ?? [];
    int sectorCount = 0, gpCount = 0;
    for (final z in zones) {
      final secs = z['sectors'] as List? ?? [];
      sectorCount += secs.length;
      for (final s in secs) gpCount += ((s['panchayats'] as List?)?.length ?? 0);
    }

    // Build flat row data: one row per zone×sector
    final rows = <_SZRow>[];
    for (int zi = 0; zi < zones.length; zi++) {
      final z = zones[zi] as Map;
      final sectors = z['sectors'] as List? ?? [];
      final zOfficers = z['officers'] as List? ?? [];

      if (sectors.isEmpty) {
        rows.add(_SZRow(
          zoneIdx: zi + 1, zone: z, sector: null, sectorGlobalIdx: null,
          gpNames: '—', thanas: '—', zOfficers: zOfficers,
        ));
      } else {
        for (int si = 0; si < sectors.length; si++) {
          final s = sectors[si] as Map;
          final gps = s['panchayats'] as List? ?? [];
          final gpNames = gps.map((g) => '${g['name']}').join(', ');
          final thanas = gps.map((g) => '${g['thana'] ?? ''}')
              .where((t) => t.isNotEmpty).toSet().join(', ');
          rows.add(_SZRow(
            zoneIdx: zi + 1, zone: z, sector: s,
            sectorGlobalIdx: rows.where((r) => r.sector != null).length + 1,
            gpNames: gpNames.isEmpty ? '—' : gpNames,
            thanas: thanas.isEmpty ? '—' : thanas,
            zOfficers: zOfficers,
          ));
        }
      }
    }

    // Column widths
    const w = <int, double>{
      0: 36, 1: 40, 2: 160, 3: 120, 4: 44, 5: 150, 6: 120, 7: 220, 8: 90,
    };
    final totalW = w.values.fold(0.0, (a, b) => a + b);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.07), blurRadius: 10, offset: const Offset(0,4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Card Header ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF0F2B5B), Color(0xFF1E3F80)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('सुपर जोन–${sz['name']}',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                if ('${sz['district'] ?? ''}'.isNotEmpty)
                  Text('जिला: ${sz['district']}  |  ब्लॉक: ${sz['block'] ?? ''}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              _GoldChip('कुल GP: $gpCount'),
              const SizedBox(width: 8),
              _IAB(icon: Icons.edit_outlined,   color: _kAccent,       onTap: onEdit),
              _IAB(icon: Icons.delete_outline,   color: Colors.red[300]!, onTap: onDelete),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              _MC('${zones.length} जोन', Colors.blue),
              const SizedBox(width: 8),
              _MC('$sectorCount सैक्टर', Colors.green),
              const SizedBox(width: 8),
              _MC('$gpCount ग्राम पंचायत', Colors.orange),
            ]),
          ]),
        ),

        // ── Kshetra officers strip ─────────────────────────────────────────
        if ((sz['officers'] as List?)?.isNotEmpty == true)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: _kGold,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('सुपर जोन/क्षेत्र अधिकारी:', style: TextStyle(color: _kSubtle, fontSize: 10, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              ...(sz['officers'] as List).map((o) => Row(children: [
                const Icon(Icons.person_pin_outlined, size: 12, color: _kPrimary),
                const SizedBox(width: 4),
                Expanded(child: Text(
                  '${o['name'] ?? '—'} · ${o['user_rank'] ?? ''}'
                  '${(o['pno'] ?? '').toString().isNotEmpty ? ' · PNO: ${o['pno']}' : ''}'
                  '${(o['mobile'] ?? '').toString().isNotEmpty ? ' · ${o['mobile']}' : ''}',
                  style: const TextStyle(color: _kDark, fontSize: 11, fontWeight: FontWeight.w500),
                )),
              ])),
            ]),
          ),

        // ── Table ──────────────────────────────────────────────────────────
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: _Empty(text: 'कोई जोन/सैक्टर नहीं'))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: totalW,
              child: Column(children: [
                // Header
                _tableHeader(const {
                  0: 'सुपर\nजोन', 1: 'जोन', 2: 'जोनल अधिकारी / जोनल\nपुलिस अधिकारी का नाम',
                  3: 'मुख्यालय', 4: 'सैक्टर\nसं.', 5: 'सैक्टर पुलिस\nअधिकारी का नाम',
                  6: 'सैक्टर\nमुख्यालय', 7: 'ग्राम पंचायत का नाम', 8: 'थाना',
                }, w, const Color(0xFFF5EAD0),
                    const TextStyle(color: _kDark, fontWeight: FontWeight.w800, fontSize: 10)),

                // Data rows — group by zone for spanning visual
                ..._buildDataRows(rows, w, sz),
              ]),
            ),
          ),
      ]),
    );
  }

  List<Widget> _buildDataRows(List<_SZRow> rows, Map<int, double> w, Map sz) {
    // Track zone span: for the same zone, only first row shows zone idx + zonal officer
    final result = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      final isFirstInZone = i == 0 || rows[i - 1].zoneIdx != r.zoneIdx;
      final bg = r.zoneIdx.isOdd ? Colors.white : const Color(0xFFFFFDF7);

      // Zone officer text
      final zOfficerText = r.zOfficers.isNotEmpty
          ? r.zOfficers.map((o) => '${o['name'] ?? ''}\n${o['user_rank'] ?? ''}').join('\n')
          : '—';
      // Sector officer text
      final sOfficers = (r.sector?['officers'] as List? ?? []);
      final sOfficerText = sOfficers.isNotEmpty
          ? sOfficers.map((o) => '${o['name'] ?? ''}\n${o['user_rank'] ?? ''}\n${o['mobile'] ?? ''}').join('\n')
          : (r.sector?['name'] != null ? '—' : '');

      result.add(_tableRow([
        // col 0: super zone — shown only on very first row
        i == 0 ? _rotatedSZ('सुपर जोन–${sz['name']}') : const SizedBox(),
        // col 1: zone number — shown only on first row of that zone
        isFirstInZone ? _centerBold('${r.zoneIdx}', color: _kPrimary) : const SizedBox(),
        // col 2: zonal officer — shown only on first row of that zone
        isFirstInZone ? _cellText(zOfficerText) : const SizedBox(),
        // col 3: hq address — shown only on first row of that zone
        isFirstInZone ? _cellText('${r.zone['hq_address'] ?? r.zone['hqAddress'] ?? '—'}') : const SizedBox(),
        // col 4: sector number
        r.sectorGlobalIdx != null ? _centerBold('${r.sectorGlobalIdx}', color: _kGreen) : const SizedBox(),
        // col 5: sector officer
        _cellText(sOfficerText),
        // col 6: sector hq (use zone hq for now or could be separate)
        _cellText('${r.sector?['hq'] ?? r.zone['hq_address'] ?? '—'}'),
        // col 7: GP names
        _cellText(r.gpNames, maxLines: 4),
        // col 8: thana
        _cellText(r.thanas),
      ], w, bg));
    }
    return result;
  }

  Widget _rotatedSZ(String text) => RotatedBox(
    quarterTurns: 3,
    child: Text(text, style: const TextStyle(color: _kPrimary, fontSize: 8, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
  );
}

// Row data model for Tab 1
class _SZRow {
  final int zoneIdx;
  final Map zone;
  final Map? sector;
  final int? sectorGlobalIdx;
  final String gpNames, thanas;
  final List zOfficers;
  const _SZRow({
    required this.zoneIdx, required this.zone, required this.sector,
    required this.sectorGlobalIdx, required this.gpNames, required this.thanas,
    required this.zOfficers,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 2 — सैक्टर (matches Image 2)
// ══════════════════════════════════════════════════════════════════════════════
class _SectorTab extends StatelessWidget {
  final List pairs, allSZ, allZones;
  final String? selSZ, selZone;
  final ValueChanged<String?> onSZChanged, onZoneChanged;
  final Future<void> Function(int, String) onDeleteSector;
  final void Function(Map) onEditSector;

  const _SectorTab({
    required this.pairs, required this.allSZ, required this.allZones,
    required this.selSZ, required this.selZone,
    required this.onSZChanged, required this.onZoneChanged,
    required this.onDeleteSector, required this.onEditSector,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _FilterBar(children: [
        _FilterDrop(label: 'सुपर जोन', value: selSZ, placeholder: 'सभी',
            items: allSZ.map((s) => _DI('${s['id']}', '${s['name']}')).toList(),
            onChanged: onSZChanged),
        const SizedBox(width: 10),
        _FilterDrop(label: 'जोन', value: selZone, placeholder: 'सभी',
            items: allZones.map((z) => _DI('${z['id']}', '${z['name']}')).toList(),
            onChanged: onZoneChanged),
      ]),
      Expanded(
        child: pairs.isEmpty
            ? const _Empty(text: 'कोई जोन नहीं मिला')
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: pairs.length,
                itemBuilder: (_, i) {
                  final p = pairs[i] as Map;
                  return _SectorCard(sz: p['sz'], zone: p['z'],
                      onDeleteSector: onDeleteSector, onEditSector: onEditSector);
                },
              ),
      ),
    ]);
  }
}

class _SectorCard extends StatelessWidget {
  final Map sz, zone;
  final Future<void> Function(int, String) onDeleteSector;
  final void Function(Map) onEditSector;
  const _SectorCard({required this.sz, required this.zone,
      required this.onDeleteSector, required this.onEditSector});

  @override
  Widget build(BuildContext context) {
    final sectors = zone['sectors'] as List? ?? [];
    final zOfficers = zone['officers'] as List? ?? [];

    // Build row data
    final rows = <Map>[];
    int sSeq = 0;
    for (final s in sectors) {
      sSeq++;
      final sOfficers = s['officers'] as List? ?? [];
      final gps = s['panchayats'] as List? ?? [];
      if (gps.isEmpty) {
        rows.add({'s': s, 'sSeq': sSeq, 'sOfficers': sOfficers,
            'gp': null, 'centers': <Map>[], 'firstInSector': true});
      } else {
        for (int gi = 0; gi < gps.length; gi++) {
          final gp = gps[gi] as Map;
          final centers = gp['centers'] as List? ?? [];
          rows.add({'s': s, 'sSeq': sSeq,
              'sOfficers': gi == 0 ? sOfficers : <Map>[],
              'gp': gp, 'centers': centers, 'firstInSector': gi == 0});
        }
      }
    }

    const w = <int, double>{
      0: 44, 1: 180, 2: 180, 3: 130, 4: 160, 5: 100, 6: 70,
    };
    final totalW = w.values.fold(0.0, (a, b) => a + b);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kGreen.withOpacity(0.08), blurRadius: 10, offset: const Offset(0,4))],
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
                Text('जोन: ${zone['name']}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                Text('सुपर जोन: ${sz['name']}  |  ब्लॉक: ${sz['block'] ?? ''}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
              _MC('${sectors.length} सैक्टर', Colors.white),
            ]),
            if (zOfficers.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 5),
              const Text('जोनल मजिस्ट्रेट / जोनल पुलिस अधिकारी:',
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
              const SizedBox(height: 3),
              ...zOfficers.map((o) => Text(
                '• ${o['name'] ?? '—'} (${o['user_rank'] ?? ''})  '
                'PNO: ${o['pno'] ?? '—'}  मो: ${o['mobile'] ?? '—'}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              )),
            ],
          ]),
        ),

        // Table
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(14), child: _Empty(text: 'कोई डेटा नहीं'))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: totalW,
              child: Column(children: [
                _tableHeader(const {
                  0: 'सैक्टर\nसं.',
                  1: 'सैक्टर मजिस्ट्रेट\n(नाम/पद/मोबाइल)',
                  2: 'सैक्टर पुलिस अधिकारी\n(नाम/पद/मोबाइल)',
                  3: 'ग्राम पंचायत',
                  4: 'मतदेय स्थल',
                  5: 'मतदान केन्द्र',
                  6: 'एक्शन',
                }, w, const Color(0xFFE8F5E9),
                    const TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.w800, fontSize: 10)),

                ...rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final r = entry.value;
                  final s = r['s'] as Map;
                  final gp = r['gp'] as Map?;
                  final centers = r['centers'] as List? ?? [];
                  final sOfficers = r['sOfficers'] as List? ?? [];
                  final firstInSec = r['firstInSector'] as bool;
                  final bg = i.isEven ? Colors.white : const Color(0xFFF1F8E9);

                  final sOfficerText = sOfficers.isNotEmpty
                      ? sOfficers.map((o) =>
                          '${o['name'] ?? ''}\n${o['user_rank'] ?? ''}\n${o['mobile'] ?? ''}').join('\n─\n')
                      : '—';

                  // Center names list
                  final centerNamesList = centers.map((c) => '${c['name']}').join('\n');
                  // Kendra room numbers
                  final kendrasList = centers.expand((c) => (c['kendras'] as List? ?? []))
                      .map((k) => '${k['room_number']}').join(', ');

                  return _tableRow([
                    firstInSec ? _centerBold('${r['sSeq']}', color: _kGreen, size: 14) : const SizedBox(),
                    firstInSec ? _cellText(sOfficerText) : const SizedBox(),
                    firstInSec ? _cellText(sOfficerText) : const SizedBox(), // police officer col
                    _cellText('${gp?['name'] ?? '—'}'),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(centerNamesList.isEmpty ? '—' : centerNamesList,
                          style: const TextStyle(color: _kDark, fontSize: 11)),
                      if (gp?['address'] != null && '${gp!['address']}'.isNotEmpty)
                        Text('${gp['address']}', style: const TextStyle(color: _kSubtle, fontSize: 9)),
                    ]),
                    _cellText(kendrasList.isEmpty ? '—' : kendrasList),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _IAB(icon: Icons.edit_outlined, color: _kGreen, onTap: () => onEditSector(s)),
                      _IAB(icon: Icons.delete_outline, color: _kRed, onTap: () => onDeleteSector(s['id'], '${s['name']}')),
                    ]),
                  ], w, bg);
                }),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TAB 3 — बूथ ड्यूटी (matches Image 3)
// ══════════════════════════════════════════════════════════════════════════════
class _BoothDutyTab extends StatelessWidget {
  final List items, allSZ, allZones, allSectors, allGPs;
  final String? selSZ, selZone, selSector, selGP;
  final ValueChanged<String?> onSZChanged, onZoneChanged, onSectorChanged, onGPChanged;
  final Future<void> Function(int, String) onDeleteSthal;
  final void Function(Map) onEditSthal;

  const _BoothDutyTab({
    required this.items, required this.allSZ, required this.allZones,
    required this.allSectors, required this.allGPs,
    required this.selSZ, required this.selZone,
    required this.selSector, required this.selGP,
    required this.onSZChanged, required this.onZoneChanged,
    required this.onSectorChanged, required this.onGPChanged,
    required this.onDeleteSthal, required this.onEditSthal,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _FilterBar(children: [
        _FilterDrop(label: 'सुपर जोन', value: selSZ, placeholder: 'सभी',
            items: allSZ.map((s) => _DI('${s['id']}', '${s['name']}')).toList(), onChanged: onSZChanged),
        const SizedBox(width: 8),
        _FilterDrop(label: 'जोन', value: selZone, placeholder: 'सभी',
            items: allZones.map((z) => _DI('${z['id']}', '${z['name']}')).toList(), onChanged: onZoneChanged),
        const SizedBox(width: 8),
        _FilterDrop(label: 'सैक्टर', value: selSector, placeholder: 'सभी',
            items: allSectors.map((s) => _DI('${s['id']}', '${s['name']}')).toList(), onChanged: onSectorChanged),
        const SizedBox(width: 8),
        _FilterDrop(label: 'ग्राम पंचायत', value: selGP, placeholder: 'सभी',
            items: allGPs.map((g) => _DI('${g['id']}', '${g['name']}')).toList(), onChanged: onGPChanged),
      ]),
      Expanded(
        child: items.isEmpty
            ? const _Empty(text: 'कोई पंचायत नहीं मिली')
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i] as Map;
                  return _BoothDutyCard(
                    gp: item['gp'], sector: item['s'],
                    zone: item['z'], sz: item['sz'],
                    onDeleteSthal: onDeleteSthal, onEditSthal: onEditSthal,
                  );
                },
              ),
      ),
    ]);
  }
}

class _BoothDutyCard extends StatelessWidget {
  final Map gp, sector, zone, sz;
  final Future<void> Function(int, String) onDeleteSthal;
  final void Function(Map) onEditSthal;
  const _BoothDutyCard({required this.gp, required this.sector,
      required this.zone, required this.sz,
      required this.onDeleteSthal, required this.onEditSthal});

  @override
  Widget build(BuildContext context) {
    final centers = gp['centers'] as List? ?? [];

    // Build rows: each center can have multiple kendras (rooms)
    final rows = <Map>[];
    int sthalNo = 1;  // मतदेय स्थल serial
    int kendraGlobal = 1; // मतदान केन्द्र serial

    for (final c in centers) {
      final kendras = c['kendras'] as List? ?? [];
      if (kendras.isEmpty) {
        rows.add({
          'sthalNo': sthalNo, 'center': c, 'kendra': null,
          'kendraNo': kendraGlobal, 'showSthal': true,
        });
        sthalNo++; kendraGlobal++;
      } else {
        for (int ki = 0; ki < kendras.length; ki++) {
          rows.add({
            'sthalNo': ki == 0 ? sthalNo : null,
            'center': c, 'kendra': kendras[ki],
            'kendraNo': kendraGlobal, 'showSthal': ki == 0,
          });
          kendraGlobal++;
        }
        sthalNo++;
      }
    }

    const w = <int, double>{
      0: 40,  // मतदान केन्द्र की संख्या
      1: 150, // मतदान केन्द्र का नाम + type
      2: 44,  // मतदेय सं.
      3: 150, // मतदान स्थल का नाम
      4: 50,  // जोन संख्या
      5: 55,  // सैक्टर संख्या
      6: 80,  // थाना
      7: 190, // ड्यूटी पुलिस
      8: 110, // मोबाईल
      9: 55,  // बस नं.
      10: 70, // एक्शन
    };
    final totalW = w.values.fold(0.0, (a, b) => a + b);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kPurple.withOpacity(0.08), blurRadius: 10, offset: const Offset(0,4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
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
                Text('बूथ ड्यूटी — ब्लॉक ${sz['block'] ?? sz['name']}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Wrap(spacing: 12, children: [
                  Text('ग्राम पंचायत: ${gp['name']}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  Text('सैक्टर: ${sector['name']}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  Text('जोन: ${zone['name']}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
              ])),
              _GoldChip('मतदेय स्थल: ${centers.length}'),
            ]),
          ]),
        ),

        // Table
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(14), child: _Empty(text: 'कोई मतदेय स्थल नहीं'))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: totalW,
              child: Column(children: [
                _tableHeader(const {
                  0: 'मतदान\nकेन्द्र की\nसंख्या',
                  1: 'मतदान केन्द्र\nका नाम',
                  2: 'मतदेय\nसं.',
                  3: 'मतदान स्थल\nका नाम',
                  4: 'जोन\nसंख्या',
                  5: 'सैक्टर\nसंख्या',
                  6: 'थाना',
                  7: 'ड्यूटी पर लगाया\nपुलिस का नाम',
                  8: 'मोबाईल नम्बर',
                  9: 'बस नं.',
                  10: 'एक्शन',
                }, w, const Color(0xFFF3E5F5),
                    const TextStyle(color: _kPurple, fontWeight: FontWeight.w800, fontSize: 10)),

                ...rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final r = entry.value;
                  final c = r['center'] as Map;
                  final k = r['kendra'] as Map?;
                  final bg = i.isEven ? Colors.white : const Color(0xFFFDF4FF);
                  final showSthal = r['showSthal'] as bool;

                  final dutyOfficers = c['duty_officers'] as List? ?? [];
                  final dutyText = dutyOfficers.isNotEmpty
                      ? dutyOfficers.map((d) =>
                          '${d['name'] ?? ''} ${d['pno'] ?? ''}\n${d['user_rank'] ?? ''}').join('\n')
                      : '—';
                  final mobileText = dutyOfficers.isNotEmpty
                      ? dutyOfficers.map((d) => '${d['mobile'] ?? ''}').where((m) => m.isNotEmpty).join('\n')
                      : '${c['mobile'] ?? '—'}';

                  return _tableRow([
                    // col 0: मतदान केन्द्र की संख्या (kendra global serial)
                    _centerBold('${r['kendraNo']}', color: _kPurple),

                    // col 1: मतदान केन्द्र का नाम + type badge — shown per kendra row
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k != null ? '${c['name']} क.नं. ${k['room_number']}' : '${c['name']}',
                          style: const TextStyle(color: _kDark, fontSize: 11)),
                      _TypeBadge(type: '${c['center_type'] ?? 'C'}'),
                    ]),

                    // col 2: मतदेय सं — shown only for first kendra of sthal
                    showSthal
                        ? _centerBold('${r['sthalNo']}', color: _kDark)
                        : const SizedBox(),

                    // col 3: मतदान स्थल का नाम — shown only for first kendra
                    showSthal
                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${c['name']}', style: const TextStyle(color: _kDark, fontSize: 11)),
                            if ((c['address'] ?? '').toString().isNotEmpty)
                              Text('${c['address']}', style: const TextStyle(color: _kSubtle, fontSize: 9)),
                          ])
                        : const SizedBox(),

                    // col 4: जोन संख्या
                    _cellText('${zone['name']}', align: TextAlign.center),
                    // col 5: सैक्टर संख्या
                    _cellText('${sector['name']}', align: TextAlign.center),
                    // col 6: थाना
                    _cellText('${c['thana'] ?? gp['thana'] ?? '—'}'),
                    // col 7: ड्यूटी पुलिस
                    _cellText(dutyText),
                    // col 8: मोबाईल
                    Text(mobileText, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: _kDark)),
                    // col 9: बस नं.
                    _centerBold('${c['bus_no'] ?? '—'}', color: _kDark),
                    // col 10: actions
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _IAB(icon: Icons.edit_outlined, color: _kPurple, onTap: () => onEditSthal(c)),
                      _IAB(icon: Icons.delete_outline, color: _kRed, onTap: () => onDeleteSthal(c['id'], '${c['name']}')),
                    ]),
                  ], w, bg);
                }),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED TABLE BUILDER HELPERS
// ══════════════════════════════════════════════════════════════════════════════

Widget _tableHeader(Map<int, String> labels, Map<int, double> widths,
    Color bgColor, TextStyle style) {
  return Container(
    decoration: BoxDecoration(
      color: bgColor,
      border: Border.all(color: _kBorder, width: 0.7),
    ),
    child: Row(
      children: List.generate(labels.length, (i) => Container(
        width: widths[i],
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: i < labels.length - 1
            ? const BoxDecoration(border: Border(right: BorderSide(color: _kBorder, width: 0.7)))
            : null,
        child: Text(labels[i]!, style: style, textAlign: TextAlign.center),
      )),
    ),
  );
}

Widget _tableRow(List<Widget> cells, Map<int, double> widths, Color bg) {
  return Container(
    decoration: BoxDecoration(
      color: bg,
      border: const Border(
        left: BorderSide(color: _kBorder, width: 0.7),
        right: BorderSide(color: _kBorder, width: 0.7),
        bottom: BorderSide(color: _kBorder, width: 0.7),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(cells.length, (i) => Container(
        width: widths[i],
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: i < cells.length - 1
            ? const BoxDecoration(border: Border(right: BorderSide(color: _kBorder, width: 0.7)))
            : null,
        child: cells[i],
      )),
    ),
  );
}

Widget _cellText(String text, {TextAlign align = TextAlign.left, int maxLines = 5}) =>
    Text(text, style: const TextStyle(color: _kDark, fontSize: 11),
        textAlign: align, maxLines: maxLines, overflow: TextOverflow.ellipsis);

Widget _centerBold(String text, {required Color color, double size = 13}) =>
    Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: size),
        textAlign: TextAlign.center);

// ══════════════════════════════════════════════════════════════════════════════
// EDIT DIALOGS
// ══════════════════════════════════════════════════════════════════════════════

class _SuperZoneDialog extends StatefulWidget {
  final Map? superZone;
  final Future<void> Function(Map) onSave;
  const _SuperZoneDialog({required this.superZone, required this.onSave});
  @override State<_SuperZoneDialog> createState() => _SuperZoneDialogState();
}
class _SuperZoneDialogState extends State<_SuperZoneDialog> {
  final _fk = GlobalKey<FormState>();
  late TextEditingController _name, _district, _block;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name     = TextEditingController(text: widget.superZone?['name'] ?? '');
    _district = TextEditingController(text: widget.superZone?['district'] ?? '');
    _block    = TextEditingController(text: widget.superZone?['block'] ?? '');
  }
  @override void dispose() { _name.dispose(); _district.dispose(); _block.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_fk.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave({'name': _name.text.trim(), 'district': _district.text.trim(), 'block': _block.text.trim()});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('त्रुटि: $e'), backgroundColor: _kRed, behavior: SnackBarBehavior.floating));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => _FormDialog(
    icon: Icons.layers_outlined, color: _kPrimary,
    title: widget.superZone != null ? 'सुपर जोन संपादित करें' : 'सुपर जोन जोड़ें',
    formKey: _fk, saving: _saving, onSave: _save,
    fields: [
      _FF(ctrl: _name, label: 'सुपर जोन का नाम', required: true),
      _FF(ctrl: _district, label: 'जिला'),
      _FF(ctrl: _block, label: 'ब्लॉक'),
    ],
  );
}

class _SectorDialog extends StatefulWidget {
  final Map sector;
  final Future<void> Function(Map) onSave;
  const _SectorDialog({required this.sector, required this.onSave});
  @override State<_SectorDialog> createState() => _SectorDialogState();
}
class _SectorDialogState extends State<_SectorDialog> {
  final _fk = GlobalKey<FormState>();
  late TextEditingController _name;
  bool _saving = false;

  @override void initState() { super.initState(); _name = TextEditingController(text: widget.sector['name'] ?? ''); }
  @override void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_fk.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave({'name': _name.text.trim()});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('त्रुटि: $e'), backgroundColor: _kRed, behavior: SnackBarBehavior.floating));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => _FormDialog(
    icon: Icons.map_outlined, color: _kGreen,
    title: 'सैक्टर संपादित करें',
    formKey: _fk, saving: _saving, onSave: _save,
    fields: [_FF(ctrl: _name, label: 'सैक्टर का नाम', required: true)],
  );
}

class _SthalDialog extends StatefulWidget {
  final Map sthal;
  final Future<void> Function(Map) onSave;
  const _SthalDialog({required this.sthal, required this.onSave});
  @override State<_SthalDialog> createState() => _SthalDialogState();
}
class _SthalDialogState extends State<_SthalDialog> {
  final _fk = GlobalKey<FormState>();
  late TextEditingController _name, _address, _thana, _busNo;
  String _centerType = 'C';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name    = TextEditingController(text: widget.sthal['name'] ?? '');
    _address = TextEditingController(text: widget.sthal['address'] ?? '');
    _thana   = TextEditingController(text: widget.sthal['thana'] ?? '');
    _busNo   = TextEditingController(text: widget.sthal['bus_no'] ?? widget.sthal['busNo'] ?? '');
    _centerType = widget.sthal['center_type'] ?? widget.sthal['centerType'] ?? 'C';
  }
  @override void dispose() { _name.dispose(); _address.dispose(); _thana.dispose(); _busNo.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_fk.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave({
        'name': _name.text.trim(), 'address': _address.text.trim(),
        'thana': _thana.text.trim(), 'bus_no': _busNo.text.trim(),
        'center_type': _centerType,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('त्रुटि: $e'), backgroundColor: _kRed, behavior: SnackBarBehavior.floating));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _fk,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: _kPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.how_to_vote_outlined, color: _kPurple, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text('मतदेय स्थल संपादित करें',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kDark))),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 18),
              _FF(ctrl: _name, label: 'मतदेय स्थल का नाम', required: true),
              const SizedBox(height: 10),
              _FF(ctrl: _address, label: 'पता'),
              const SizedBox(height: 10),
              _FF(ctrl: _thana, label: 'थाना'),
              const SizedBox(height: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('केन्द्र का प्रकार', style: TextStyle(color: _kSubtle, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(children: ['A', 'B', 'C'].map((t) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: _centerType == t,
                    selectedColor: t == 'A' ? Colors.red[100] : t == 'B' ? Colors.orange[100] : Colors.blue[100],
                    onSelected: (_) => setState(() => _centerType = t),
                  ),
                )).toList()),
              ]),
              const SizedBox(height: 10),
              _FF(ctrl: _busNo, label: 'बस नम्बर'),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द करें'))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kPurple,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('सहेजें', style: TextStyle(color: Colors.white)),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Generic form dialog wrapper ───────────────────────────────────────────────
class _FormDialog extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final GlobalKey<FormState> formKey;
  final bool saving;
  final VoidCallback onSave;
  final List<Widget> fields;

  const _FormDialog({
    required this.icon, required this.color, required this.title,
    required this.formKey, required this.saving, required this.onSave,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Container(
      width: 380,
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kDark))),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 18),
          ...fields.expand((f) => [f, const SizedBox(height: 10)]).toList()..removeLast(),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द करें'))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('सहेजें', style: TextStyle(color: Colors.white)),
            )),
          ]),
        ]),
      ),
    ),
  );
}

// ── Form Field ────────────────────────────────────────────────────────────────
class _FF extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool required;
  final TextInputType? inputType;
  const _FF({required this.ctrl, required this.label, this.required = false, this.inputType});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: ctrl,
    keyboardType: inputType,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _kSubtle, fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kPrimary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    ),
    validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label आवश्यक है' : null : null,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SMALL SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _DI { final String value, label; const _DI(this.value, this.label); }

class _FilterBar extends StatelessWidget {
  final List<Widget> children;
  const _FilterBar({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    color: _kBg,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: children)),
  );
}

class _FilterDrop extends StatelessWidget {
  final String label, placeholder;
  final String? value;
  final List<_DI> items;
  final ValueChanged<String?> onChanged;
  const _FilterDrop({required this.label, required this.value, required this.items,
      required this.onChanged, required this.placeholder});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: _kSubtle, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    const SizedBox(height: 3),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 160),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: value != null ? _kPrimary : _kBorder, width: 1.5),
      ),
      child: DropdownButton<String>(
        value: value, underline: const SizedBox(), isExpanded: true,
        hint: Text(placeholder, style: const TextStyle(color: _kSubtle, fontSize: 12), overflow: TextOverflow.ellipsis),
        style: const TextStyle(color: _kDark, fontSize: 12),
        dropdownColor: Colors.white,
        items: [
          DropdownMenuItem<String>(value: null,
              child: Text(placeholder, style: const TextStyle(color: _kSubtle, fontSize: 12), overflow: TextOverflow.ellipsis)),
          ...items.map((i) => DropdownMenuItem<String>(value: i.value,
              child: Text(i.label, style: const TextStyle(color: _kDark, fontSize: 12), overflow: TextOverflow.ellipsis))),
        ],
        onChanged: onChanged,
      ),
    ),
  ]);
}

class _AddBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(
      backgroundColor: _kPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    icon: const Icon(Icons.add, color: Colors.white, size: 16),
    label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    onPressed: onTap,
  );
}

class _IAB extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  const _IAB({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(6),
    child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, color: color, size: 17)),
  );
}

class _GoldChip extends StatelessWidget {
  final String label;
  const _GoldChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(7)),
    child: Text(label, style: const TextStyle(color: _kAccent, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

class _MC extends StatelessWidget {
  final String label; final Color color;
  const _MC(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: color == Colors.white ? Colors.white : color, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});
  @override
  Widget build(BuildContext context) {
    final color = type == 'A' ? Colors.red : type == 'B' ? Colors.orange : Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(type, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.inbox_outlined, size: 40, color: _kSubtle),
      const SizedBox(height: 8),
      Text(text, style: const TextStyle(color: _kSubtle, fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _ErrorView extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
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
        label: const Text('पुनः प्रयास करें', style: TextStyle(color: Colors.white)),
      ),
    ]),
  );
}