import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'dart:typed_data';

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  PALETTE
// ══════════════════════════════════════════════════════════════════════════════
const _kPrimary  = Color(0xFF1A3A6B);
const _kAccent   = Color(0xFF2E7D32);
const _kGold     = Color(0xFFD4A017);
const _kBg       = Color(0xFFF5F7FB);
const _kBorder   = Color(0xFFDDE3EE);
const _kSubtle   = Color(0xFF6B7C93);
const _kDark     = Color(0xFF1A2332);
const _kHeaderBg = Color(0xFFE8EDF5);
const _kTotalBg  = Color(0xFFDDE8F5);
const _kError    = Color(0xFFC0392B);

class GoswaraPage extends StatefulWidget {
  const GoswaraPage({super.key});

  @override
  State<GoswaraPage> createState() => _GoswaraPageState();
}

class _GoswaraPageState extends State<GoswaraPage> {
  List<Map<String, dynamic>> _data = [];
  bool   _loading     = true;
  bool   _saving      = false;
  String _electionDate = '';
  String _phase        = '';
  String _error        = '';

  // User info
  String _userRole     = '';
  String _userDistrict = '';

  // Editable nyay panchayat controllers — keyed by block_name
  final Map<String, TextEditingController> _nyayCtrls = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in _nyayCtrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final user = await AuthService.getUser();
      if (user != null && mounted) {
        setState(() {
          _userRole     = (user['role']     ?? '').toString();
          _userDistrict = (user['district'] ?? '').toString();
        });
      }
    } catch (_) {}
    await _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = ''; });

    try {
      final token = await AuthService.getToken();

      // Use the generic ApiService.get — same pattern as other pages
      final res = await ApiService.get('/admin/goswara', token: token);

      // Handle both { data: [...] } and direct list responses
      final rawData = res['data'] ?? res;
      final List<dynamic> rows =
          rawData is List ? rawData : [];

      final electionDate = (res['electionDate'] ?? '').toString();
      final phase        = (res['phase']        ?? '').toString();

      // Build typed list
      final parsed = rows.map<Map<String, dynamic>>((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return {
          'block_name':           (m['block_name'] ?? '').toString(),
          'zonal_count':          _toInt(m['zonal_count']),
          'sector_count':         _toInt(m['sector_count']),
          'nyay_panchayat_count': _toInt(m['nyay_panchayat_count']),
          'gram_panchayat_count': _toInt(m['gram_panchayat_count']),
        };
      }).toList();

      // Build/update controllers for nyay fields
      for (final r in parsed) {
        final block = r['block_name'] as String;
        if (!_nyayCtrls.containsKey(block)) {
          _nyayCtrls[block] = TextEditingController();
        }
        _nyayCtrls[block]!.text =
            '${r['nyay_panchayat_count']}';
      }

      if (mounted) {
        setState(() {
          _data         = parsed;
          _electionDate = electionDate;
          _phase        = phase;
          _loading      = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = e.toString();
          _loading = false;
        });
      }
    }
  }

  static int _toInt(dynamic v) =>
      v == null ? 0 : (v is int ? v : int.tryParse(v.toString()) ?? 0);

  // ── Save nyay panchayat count for a block ─────────────────────────────────
  Future<void> _saveNyay(String blockName) async {
    final ctrl = _nyayCtrls[blockName];
    if (ctrl == null) return;
    final count = int.tryParse(ctrl.text.trim()) ?? 0;

    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      await ApiService.post(
        '/admin/goswara/nyay-panchayat',
        {'blockName': blockName, 'nyayCount': count},
        token: token,
      );

      // Update local data
      final idx = _data.indexWhere((r) => r['block_name'] == blockName);
      if (idx >= 0 && mounted) {
        setState(() {
          _data[idx] = {..._data[idx], 'nyay_panchayat_count': count};
        });
      }
      _showSnack('$blockName — न्याय पंचायत सहेजा गया ✓');
    } catch (e) {
      _showSnack('सेव विफल: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _kError : _kAccent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Column sums ────────────────────────────────────────────────────────────
  int _sum(String key) =>
      _data.fold(0, (s, r) => s + _toInt(r[key]));

  int get _nyaySum => _data.fold(
      0, (s, r) =>
          s + (int.tryParse(_nyayCtrls[r['block_name']]?.text ?? '0') ?? 0));

  bool get _isSuperAdmin => _userRole == 'super_admin';

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : _error.isNotEmpty
              ? _ErrorView(error: _error, onRetry: _fetchData)
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  color: _kPrimary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 14),
                        _buildStatsRow(),
                        const SizedBox(height: 14),
                        _buildTable(),
                        const SizedBox(height: 16),
                        _buildNyayEditSection(),
                      ],
                    ),
                  ),
                ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: _kPrimary,
    foregroundColor: Colors.white,
    elevation: 0,
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('गोसवारा',
          style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, fontSize: 16)),
      Text(
        _phase.isNotEmpty
            ? 'चरण: $_phase  •  $_electionDate' : 'लोड हो रहा है...',
        style: const TextStyle(color: Colors.white60, fontSize: 10),
      ),
    ]),
    actions: [
      if (_saving)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
        ),
      IconButton(
        icon: const Icon(Icons.refresh_rounded, size: 20),
        tooltip: 'रिफ्रेश',
        onPressed: _loading ? null : _fetchData,
      ),
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kGold,
            foregroundColor: _kDark,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.print_outlined, size: 15),
          label: const Text('प्रिंट',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          onPressed: _data.isEmpty ? null : () async {
            await Printing.layoutPdf(
                onLayout: (_) async => _buildPdf());
          },
        ),
      ),
    ],
  );

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [_kPrimary, Color(0xFF2651A3)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('गोसवारा',
          style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 20)),
      const SizedBox(height: 4),
      const Text(
        'विकास खण्डवार जोनल एवं सेक्टर, न्याय पंचायत एवं ग्राम पंचायतों का विवरण',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      ),
      if (_isSuperAdmin && _userDistrict.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_city_outlined,
                size: 14, color: Colors.white70),
            const SizedBox(width: 5),
            Text('जनपद: $_userDistrict',
                style: const TextStyle(color: Colors.white,
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ],
      if (_phase.isNotEmpty || _electionDate.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          if (_phase.isNotEmpty)
            _Chip(Icons.layers_outlined, 'चरण: $_phase'),
          if (_electionDate.isNotEmpty)
            _Chip(Icons.calendar_today_outlined, _electionDate),
        ]),
      ],
    ]),
  );

  Widget _buildStatsRow() {
    if (_data.isEmpty) return const SizedBox.shrink();
    final items = [
      (_sum('zonal_count'),          'जोनल अधिकारी',    Icons.account_tree_outlined, const Color(0xFF1565C0)),
      (_sum('sector_count'),         'सेक्टर',          Icons.grid_view_outlined,     _kAccent),
      (_nyaySum,                     'न्याय पंचायत',    Icons.balance_outlined,        const Color(0xFF6A1B9A)),
      (_sum('gram_panchayat_count'), 'ग्राम पंचायत',    Icons.villa_outlined,          _kGold),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8, mainAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: items.map((item) {
        final (val, label, icon, color) = item;
        return Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.2)),
              boxShadow: [BoxShadow(
                  color: color.withOpacity(0.08),
                  blurRadius: 8, offset: const Offset(0, 3))]),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 6),
            Text('$val',
                style: TextStyle(color: color,
                    fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: _kSubtle, fontSize: 9),
                textAlign: TextAlign.center, maxLines: 1),
          ]),
        );
      }).toList(),
    );
  }

  Widget _buildTable() {
    if (_data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder)),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.table_chart_outlined, size: 48, color: _kSubtle),
          SizedBox(height: 12),
          Text('कोई डेटा उपलब्ध नहीं',
              style: TextStyle(color: _kSubtle, fontSize: 14)),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
          boxShadow: [BoxShadow(
              color: _kPrimary.withOpacity(0.06),
              blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Card header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: _kBorder))),
          child: Row(children: [
            const Icon(Icons.table_chart_outlined,
                size: 16, color: _kPrimary),
            const SizedBox(width: 8),
            const Text('विस्तृत विवरण',
                style: TextStyle(color: _kPrimary,
                    fontWeight: FontWeight.w800, fontSize: 13)),
            const Spacer(),
            Text('${_data.length} विकास खण्ड',
                style: const TextStyle(color: _kSubtle, fontSize: 11)),
          ]),
        ),

        // Horizontally scrollable table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Table(
            border: TableBorder.all(color: _kBorder, width: 0.7),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FixedColumnWidth(44),
              1: FixedColumnWidth(140),
              2: FixedColumnWidth(85),
              3: FixedColumnWidth(120),
              4: FixedColumnWidth(110),
              5: FixedColumnWidth(110),
              6: FixedColumnWidth(110),
              7: FixedColumnWidth(110),
            },
            children: [
              // Header
              TableRow(
                decoration: const BoxDecoration(color: _kHeaderBg),
                children: [
                  _hCell('क्र०सं०'),
                  _hCell('विकास खण्ड'),
                  _hCell('चरण'),
                  _hCell('मतदान तिथि'),
                  _hCell('जोनल मजिस्ट्रेट /\nपुलिस अधिकारी'),
                  _hCell('सेक्टर\nमजिस्ट्रेट'),
                  _hCell('न्याय\nपंचायत'),
                  _hCell('ग्राम\nपंचायत'),
                ],
              ),

              // Data rows
              ..._data.asMap().entries.map((e) {
                final i     = e.key;
                final r     = e.value;
                final nyay  = _toInt(r['nyay_panchayat_count']);
                final isEven = i.isEven;
                return TableRow(
                  decoration: BoxDecoration(
                      color: isEven ? Colors.white : const Color(0xFFF8FAFF)),
                  children: [
                    _dCell('${i + 1}', center: true),
                    _dCell(r['block_name'] as String? ?? '',
                        bold: true),
                    _dCell(i == 0 ? _phase : '', center: true),
                    _dCell(i == 0 ? _electionDate : '', center: true,
                        color: _kGold),
                    _dCell('${_toInt(r['zonal_count'])}', center: true,
                        color: const Color(0xFF1565C0)),
                    _dCell('${_toInt(r['sector_count'])}', center: true,
                        color: _kAccent),
                    _dCell('$nyay', center: true,
                        color: const Color(0xFF6A1B9A)),
                    _dCell('${_toInt(r['gram_panchayat_count'])}',
                        center: true, color: const Color(0xFF8B6914)),
                  ],
                );
              }),

              // Total row
              TableRow(
                decoration: const BoxDecoration(color: _kTotalBg),
                children: [
                  _dCell('', center: true),
                  _dCell('योग', bold: true, color: _kPrimary),
                  _dCell('', center: true),
                  _dCell('', center: true),
                  _dCell('${_sum("zonal_count")}',          center: true, bold: true, color: _kPrimary),
                  _dCell('${_sum("sector_count")}',         center: true, bold: true, color: _kPrimary),
                  _dCell('$_nyaySum',                       center: true, bold: true, color: _kPrimary),
                  _dCell('${_sum("gram_panchayat_count")}', center: true, bold: true, color: _kPrimary),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Nyay panchayat editable section ────────────────────────────────────
  Widget _buildNyayEditSection() {
    if (_data.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
          boxShadow: [BoxShadow(
              color: const Color(0xFF6A1B9A).withOpacity(0.06),
              blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
              color: const Color(0xFF6A1B9A).withOpacity(0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: _kBorder))),
          child: Row(children: [
            const Icon(Icons.edit_outlined, size: 16,
                color: Color(0xFF6A1B9A)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('न्याय पंचायत संख्या अपडेट करें',
                  style: TextStyle(color: Color(0xFF6A1B9A),
                      fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('विकास खण्डवार',
                  style: TextStyle(color: Color(0xFF6A1B9A), fontSize: 10)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10, runSpacing: 10,
            children: _data.map((r) {
              final block = r['block_name'] as String? ?? '';
              final ctrl  = _nyayCtrls[block];
              if (ctrl == null) return const SizedBox.shrink();
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 60) / 2,
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(block,
                          style: const TextStyle(color: _kDark,
                              fontWeight: FontWeight.w700, fontSize: 11),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onSubmitted: (_) => _saveNyay(block),
                        style: const TextStyle(
                            fontSize: 13, color: _kDark,
                            fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: const TextStyle(color: _kSubtle),
                          isDense: true,
                          filled: true, fillColor: _kBg,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: _kBorder)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: _kBorder)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xFF6A1B9A), width: 2)),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _saving ? null : () => _saveNyay(block),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                          color: _saving
                              ? _kSubtle.withOpacity(0.1)
                              : const Color(0xFF6A1B9A),
                          borderRadius: BorderRadius.circular(8)),
                      child: _saving
                          ? const Center(
                              child: SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: _kSubtle)))
                          : const Icon(Icons.check_rounded,
                              color: Colors.white, size: 18),
                    ),
                  ),
                ]),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  // ── Table cell helpers ──────────────────────────────────────────────────
  Widget _hCell(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Text(text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: _kPrimary)),
  );

  Widget _dCell(String text, {
    bool center = false, bool bold = false, Color? color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Text(text,
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            color: color ?? _kDark)),
  );

  // ══════════════════════════════════════════════════════════════════════════
  //  PDF BUILDER
  // ══════════════════════════════════════════════════════════════════════════
  Future<Uint8List> _buildPdf() async {
    final pdf = pw.Document();

    pw.Font regular, bold;
    try {
      regular = await PdfGoogleFonts.notoSansDevanagariRegular();
      bold    = await PdfGoogleFonts.notoSansDevanagariBold();
    } catch (_) {
      regular = await PdfGoogleFonts.nunitoRegular();
      bold    = await PdfGoogleFonts.nunitoBold();
    }

    final base     = pw.TextStyle(font: regular, fontSize: 9);
    final bld      = pw.TextStyle(font: bold,    fontSize: 9,
        fontWeight: pw.FontWeight.bold);
    final titleSt  = pw.TextStyle(font: bold,    fontSize: 16,
        fontWeight: pw.FontWeight.bold);
    final subSt    = pw.TextStyle(font: regular, fontSize: 8.5);

    const headerBg = PdfColor(0.910, 0.929, 0.961);
    const totalBg  = PdfColor(0.867, 0.902, 0.961);

    pw.Widget cell(String text, {
      bool isBold = false,
      PdfColor? bg,
      PdfColor? textColor,
      bool center = true,
    }) => pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(text,
          textAlign: center
              ? pw.TextAlign.center : pw.TextAlign.left,
          style: (isBold ? bld : base).copyWith(color: textColor)),
    );

    // Compute totals using current ctrl values for nyay
    final nyayTotal = _data.fold<int>(
        0, (s, r) {
          final block = r['block_name'] as String? ?? '';
          return s + (int.tryParse(
              _nyayCtrls[block]?.text ?? '0') ?? 0);
        });

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(22, 22, 22, 22),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Header
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text('गोसवारा', style: titleSt),
                pw.SizedBox(height: 3),
                pw.Text(
                  'विकास खण्डवार जोनल एवं सेक्टर, न्याय पंचायत एवं '
                  'ग्राम पंचायतों का विवरण',
                  style: subSt,
                ),
              ]),
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                if (_phase.isNotEmpty)
                  pw.Text('चरण: $_phase', style: bld),
                if (_electionDate.isNotEmpty)
                  pw.Text(_electionDate, style: subSt),
                if (_isSuperAdmin && _userDistrict.isNotEmpty)
                  pw.Text('जनपद: $_userDistrict', style: bld),
              ]),
            ]),
            pw.SizedBox(height: 3),
            pw.Divider(color: const PdfColor(0.7, 0.7, 0.8), thickness: 0.8),
            pw.SizedBox(height: 10),

            // Table
            pw.Table(
              border: pw.TableBorder.all(
                  width: 0.6,
                  color: const PdfColor(0.75, 0.78, 0.85)),
              defaultVerticalAlignment:
                  pw.TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: pw.FixedColumnWidth(28),
                1: pw.FixedColumnWidth(115),
                2: pw.FixedColumnWidth(60),
                3: pw.FixedColumnWidth(85),
                4: pw.FixedColumnWidth(115),
                5: pw.FixedColumnWidth(95),
                6: pw.FixedColumnWidth(90),
                7: pw.FixedColumnWidth(90),
              },
              children: [
                // Header row
                pw.TableRow(children: [
                  cell('क्र०',                               isBold: true, bg: headerBg),
                  cell('विकास खण्ड',                         isBold: true, bg: headerBg, center: false),
                  cell('चरण',                                isBold: true, bg: headerBg),
                  cell('मतदान तिथि',                         isBold: true, bg: headerBg),
                  cell('जोनल मजिस्ट्रेट /\nपुलिस अधिकारी', isBold: true, bg: headerBg),
                  cell('सेक्टर\nमजिस्ट्रेट',               isBold: true, bg: headerBg),
                  cell('न्याय\nपंचायत',                     isBold: true, bg: headerBg),
                  cell('ग्राम\nपंचायत',                     isBold: true, bg: headerBg),
                ]),

                // Data rows
                ..._data.asMap().entries.map((e) {
                  final i     = e.key;
                  final r     = e.value;
                  final block = r['block_name'] as String? ?? '';
                  final nyay  = int.tryParse(
                      _nyayCtrls[block]?.text ?? '0') ?? 0;
                  final bg    = i.isEven
                      ? PdfColors.white
                      : const PdfColor(0.972, 0.976, 0.996);
                  return pw.TableRow(children: [
                    cell('${i + 1}', bg: bg),
                    cell(block, bg: bg, center: false),
                    cell(i == 0 ? _phase        : '', bg: bg),
                    cell(i == 0 ? _electionDate : '', bg: bg),
                    cell('${_toInt(r['zonal_count'])}', bg: bg,
                        textColor: const PdfColor(0.086, 0.337, 0.690)),
                    cell('${_toInt(r['sector_count'])}', bg: bg,
                        textColor: const PdfColor(0.094, 0.416, 0.231)),
                    cell('$nyay', bg: bg,
                        textColor: const PdfColor(0.416, 0.106, 0.604)),
                    cell('${_toInt(r['gram_panchayat_count'])}', bg: bg,
                        textColor: const PdfColor(0.545, 0.412, 0.078)),
                  ]);
                }),

                // Total row
                pw.TableRow(children: [
                  cell('',                                       bg: totalBg),
                  cell('योग',                   isBold: true,   bg: totalBg, center: false),
                  cell('',                                       bg: totalBg),
                  cell('',                                       bg: totalBg),
                  cell('${_sum("zonal_count")}',  isBold: true, bg: totalBg),
                  cell('${_sum("sector_count")}', isBold: true, bg: totalBg),
                  cell('$nyayTotal',              isBold: true, bg: totalBg),
                  cell('${_sum("gram_panchayat_count")}',
                      isBold: true, bg: totalBg),
                ]),
              ],
            ),

            pw.Spacer(),

            // Footer
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
              pw.Text('गोसवारा — जनपदीय चुनाव विवरण',
                  style: pw.TextStyle(font: regular, fontSize: 7,
                      color: PdfColors.grey600)),
              pw.Text(
                'मुद्रण तिथि: ${DateTime.now().day.toString().padLeft(2, '0')}/'
                '${DateTime.now().month.toString().padLeft(2, '0')}/'
                '${DateTime.now().year}',
                style: pw.TextStyle(font: regular, fontSize: 7,
                    color: PdfColors.grey600),
              ),
            ]),
          ],
        ),
      ),
    );

    return Uint8List.fromList(await pdf.save());
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  HELPERS
// ══════════════════════════════════════════════════════════════════════════════
class _Chip extends StatelessWidget {
  final IconData icon; final String text;
  const _Chip(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.white70),
      const SizedBox(width: 5),
      Text(text,
          style: const TextStyle(color: Colors.white,
              fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _ErrorView extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
              color: _kError.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.cloud_off_outlined,
              size: 32, color: _kError),
        ),
        const SizedBox(height: 16),
        const Text('डेटा लोड करने में त्रुटि',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                color: _kDark)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _kError.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kError.withOpacity(0.2))),
          child: Text(error,
              style: const TextStyle(color: _kSubtle, fontSize: 11),
              textAlign: TextAlign.center),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('पुनः प्रयास',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    ),
  );
}