import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kBg       = Color(0xFFFDF6E3);
const _kSurface  = Color(0xFFF5E6C8);
const _kPrimary  = Color(0xFF0F2B5B);
const _kGold     = Color(0xFF8B6914);
const _kDark     = Color(0xFF1A2332);
const _kSubtle   = Color(0xFF6B7C93);
const _kBorder   = Color(0xFFDDE3EE);
const _kSuccess  = Color(0xFF186A3B);
const _kError    = Color(0xFFC0392B);
const _kOrange   = Color(0xFFE67E22);
const _kPurple   = Color(0xFF6C3483);
const _kTeal     = Color(0xFF00796B);
const _kIndigo   = Color(0xFF283593);

// Sensitivity colours
Color _sensColor(String? t) {
  switch (t) {
    case 'A++': return _kPurple;
    case 'A':   return _kError;
    case 'B':   return _kOrange;
    default:    return _kIndigo;
  }
}

Color _rankColor(String r) {
  const m = {
    'SP':            Color(0xFF6A1B9A),
    'ASP':           Color(0xFF1565C0),
    'DSP':           Color(0xFF1A5276),
    'Inspector':     Color(0xFF2E7D32),
    'SI':            Color(0xFF558B2F),
    'ASI':           Color(0xFF8B6914),
    'Head Constable':Color(0xFFB8860B),
    'Constable':     Color(0xFF6D4C41),
  };
  return m[r] ?? _kGold;
}

// Responsive scale
class _RS {
  final double w;
  _RS(this.w);
  double get t => w <= 320 ? 0.0 : w >= 600 ? 1.0 : (w - 320) / 280;
  double s(double a, double b) => a + (b - a) * t;
  bool get isNarrow => w < 400;
  bool get isWide   => w >= 700;
}
_RS rOf(BuildContext c) => _RS(MediaQuery.of(c).size.width);

// ══════════════════════════════════════════════════════════════════════════════
//  ENTRY: ELECTION HISTORY LIST PAGE
//  – admins see their district's elections
//  – master sees all districts with a filter
// ══════════════════════════════════════════════════════════════════════════════
class ElectionHistoryListPage extends StatefulWidget {
  const ElectionHistoryListPage({super.key});
  @override
  State<ElectionHistoryListPage> createState() => _ElectionHistoryListPageState();
}

class _ElectionHistoryListPageState extends State<ElectionHistoryListPage> {
  List<Map<String, dynamic>> _elections = [];
  List<String>               _districts = [];
  bool   _loading   = true;
  String _role      = '';
  String _distFilter = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final token = await AuthService.getToken();
    final me    = await ApiService.get('/auth/me', token: token);
    setState(() => _role = (me['data']?['role'] ?? '') as String);
    if (_role == 'master') {
      try {
        final dr = await ApiService.get('/admin/election/history/districts-list', token: token);
        final data = dr['data'];
        setState(() => _districts = (data is List) ? List<String>.from(data) : []);
      } catch (_) {}
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final url   = _role == 'master'
          ? '/admin/election/history/all-elections'
              '${_distFilter.isNotEmpty ? '?district=${Uri.encodeComponent(_distFilter)}' : ''}'
          : '/admin/election/history';
      final res  = await ApiService.get(url, token: token);
      final data = res['data'];
      setState(() =>
        _elections = (data is List)
            ? data.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : []);
    } catch (e) {
      if (mounted) showSnack(context, 'लोड विफल: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('चुनाव इतिहास',
              style: TextStyle(fontSize: r.s(14, 16), fontWeight: FontWeight.w800)),
          Text('Finalized Election Reports',
              style: TextStyle(fontSize: r.s(10, 11), color: Colors.white70)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
        ],
      ),
      body: Column(children: [
        if (_role == 'master' && _districts.isNotEmpty)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              const Icon(Icons.filter_list, size: 16, color: _kSubtle),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _distFilter.isEmpty ? null : _distFilter,
                  hint: const Text('सभी जनपद', style: TextStyle(color: _kSubtle, fontSize: 13)),
                  isExpanded: true, isDense: true,
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('सभी जनपद')),
                    ..._districts.map((d) => DropdownMenuItem<String>(value: d, child: Text(d))),
                  ],
                  onChanged: (v) => setState(() {
                    _distFilter = v ?? '';
                    _load();
                  }),
                ),
              )),
            ]),
          ),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: _kPrimary))
            : _elections.isEmpty
                ? const _EmptyState(
                    icon: Icons.history_edu,
                    title: 'कोई इतिहास नहीं',
                    subtitle: 'Finalized election reports यहाँ दिखेंगे')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: _elections.length,
                    itemBuilder: (_, i) => _ElectionCard(
                      election: _elections[i],
                      isMaster: _role == 'master',
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ElectionHistoryReportPage(
                              electionId: _elections[i]['id'] as int,
                              election: _elections[i],
                              isMaster: _role == 'master'))),
                    ))),
      ]),
    );
  }
}

// ── Election list card ────────────────────────────────────────────────────────
class _ElectionCard extends StatelessWidget {
  final Map<String, dynamic> election;
  final bool isMaster;
  final VoidCallback onTap;
  const _ElectionCard({required this.election, required this.isMaster, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
          boxShadow: [BoxShadow(
              color: _kPrimary.withOpacity(0.06),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0F2B5B), Color(0xFF1A3F80)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(children: [
              const Icon(Icons.how_to_vote_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(election['electionName'] ?? election['election_name'] ?? '',
                    style: TextStyle(color: Colors.white,
                        fontSize: r.s(13, 14), fontWeight: FontWeight.w800),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (isMaster && (election['district'] ?? '').isNotEmpty)
                  Text('जनपद: ${election['district']}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('देखें →',
                    style: TextStyle(color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w700))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Wrap(spacing: 10, runSpacing: 6, children: [
              _infoChip(Icons.calendar_today_outlined,
                  election['electionDate'] ?? election['election_date'] ?? ''),
              _infoChip(Icons.category_outlined,
                  election['electionType'] ?? election['election_type'] ?? ''),
              _infoChip(Icons.layers_outlined,
                  'Phase: ${election['phase'] ?? ''}'),
              if ((election['boothAssigned'] ?? election['boothAssignmentsArchived'] ?? 0) > 0)
                _countChip('Booth',
                    '${election['boothAssigned'] ?? election['boothAssignmentsArchived'] ?? 0}',
                    _kSuccess),
              if ((election['districtAssigned'] ?? election['districtAssignmentsArchived'] ?? 0) > 0)
                _countChip('District Duty',
                    '${election['districtAssigned'] ?? election['districtAssignmentsArchived'] ?? 0}',
                    _kPurple),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) => label.isEmpty
      ? const SizedBox.shrink()
      : Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: _kSubtle),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: _kDark, fontSize: 11)),
        ]);

  Widget _countChip(String label, String value, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: TextStyle(color: c.withOpacity(0.8), fontSize: 10)),
      Text(value, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w900)),
    ]));
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN HISTORY REPORT PAGE
// ══════════════════════════════════════════════════════════════════════════════
class ElectionHistoryReportPage extends StatefulWidget {
  final int                 electionId;
  final Map<String, dynamic> election;
  final bool                isMaster;

  const ElectionHistoryReportPage({
    super.key,
    required this.electionId,
    required this.election,
    required this.isMaster,
  });

  @override
  State<ElectionHistoryReportPage> createState() => _ElectionHistoryReportPageState();
}

class _ElectionHistoryReportPageState extends State<ElectionHistoryReportPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tab;

  // data per tab
  Map<String, List<Map<String, dynamic>>> _boothManak = {'A++': [], 'A': [], 'B': [], 'C': []};
  List<Map<String, dynamic>>              _districtRules    = [];
  Map<String, Map<String, dynamic>> _dutySummary = {}; 
  Map<String, dynamic>                    _hierarchyData    = {};
  Map<String, dynamic>                    _boothSummary     = {};
  List<Map<String, dynamic>>              _boothStaff       = [];
  int                                     _boothStaffTotal  = 0;
  int                                     _boothStaffPage   = 1;
  Map<String, List<Map<String, dynamic>>> _dutyBatches      = {};

  bool _loading = true;
  bool _printing = false;
  Set<String> _loadedDutyTypes = {};
  bool _disposed = false;

  String get _eid => '${widget.electionId}';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _tab.addListener(() => setState(() {}));
    _loadAll();
  }

  @override
  void dispose() {
    _disposed = true;
    _tab.dispose();
    super.dispose();
  }

  void _safe(VoidCallback fn) { if (!_disposed && mounted) setState(fn); }

  Future<void> _loadAll() async {
    _safe(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final base  = '/admin/election/history/$_eid';

      final results = await Future.wait([
        ApiService.get('$base/booth-manak',           token: token),
        ApiService.get('$base/district-rules-full',   token: token),
        ApiService.get('$base/district-duty-summary', token: token),
        ApiService.get('$base/hierarchy-overview',    token: token),
        ApiService.get('$base/booth-assignments-summary', token: token),
        ApiService.get('$base/booth-assignments?page=1&limit=50', token: token),
      ]);

      final bm  = results[0]['data'] as Map<String, dynamic>? ?? {};
      final dr  = results[1]['data'] as List? ?? [];
      final ds  = results[2]['data'] as List? ?? [];
      final hie = results[3]['data'] as Map<String, dynamic>? ?? {};
      final bs  = results[4]['data'] as Map<String, dynamic>? ?? {};
      final bsf = results[5]['data'] as Map<String, dynamic>? ?? {};

      _safe(() {
        for (final s in ['A++', 'A', 'B', 'C']) {
          _boothManak[s] = (bm[s] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        _districtRules = dr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _dutySummary   = {
          for (final e in ds)
            (e['dutyType'] as String): Map<String, dynamic>.from(e as Map)
        };
        _hierarchyData = hie;
        _boothSummary  = bs;
        final staffData = bsf['data'] as List? ?? [];
        _boothStaff     = staffData.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _boothStaffTotal = (bsf['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      _safe(() => _loading = false);
      if (!_disposed && mounted) showSnack(context, 'लोड विफल: $e', error: true);
    }
  }

  Future<void> _loadDutyBatches(String dutyType) async {
    if (_loadedDutyTypes.contains(dutyType)) return;
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
          '/admin/election/history/$_eid/district-duty/$dutyType/batches',
          token: token);
      final data = res['data'] as List? ?? [];
      _safe(() {
        _dutyBatches[dutyType] = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loadedDutyTypes.add(dutyType);
      });
    } catch (_) {}
  }

  Future<void> _loadMoreBoothStaff() async {
    final nextPage = _boothStaffPage + 1;
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get(
          '/admin/election/history/$_eid/booth-assignments?page=$nextPage&limit=50',
          token: token);
      final data = (res['data'] as Map?)?.containsKey('data') == true
          ? (res['data']['data'] as List? ?? [])
          : (res['data'] as List? ?? []);
      _safe(() {
        _boothStaff.addAll(data.map((e) => Map<String, dynamic>.from(e as Map)));
        _boothStaffPage = nextPage;
      });
    } catch (_) {}
  }

  // ── getters ─────────────────────────────────────────────────────────────────
  String get _electionName =>
      (widget.election['electionName'] ?? widget.election['election_name'] ?? '') as String;
  String get _district =>
      (widget.election['district'] ?? '') as String;
  String get _electionDate =>
      (widget.election['electionDate'] ?? widget.election['election_date'] ?? '') as String;
  String get _phase =>
      (widget.election['phase'] ?? '') as String;

  // ── PDF helpers ─────────────────────────────────────────────────────────────
  Future<pw.Font> get _font async => PdfGoogleFonts.notoSansDevanagariRegular();
  Future<pw.Font> get _bold async => PdfGoogleFonts.notoSansDevanagariBold();

  String get _headerLine =>
      '$_electionName'
      '${_district.isNotEmpty ? " — $_district" : ""}'
      '${_electionDate.isNotEmpty ? " | $_electionDate" : ""}'
      '${_phase.isNotEmpty ? " | Phase: $_phase" : ""}';

  pw.Widget _pdfTH(String t, pw.Font bold, {double? w}) => pw.Container(
    width: w,
    color: const PdfColor.fromInt(0xFF0F2B5B),
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
    child: pw.Text(t,
        style: pw.TextStyle(font: bold, fontSize: 7, color: PdfColors.white),
        textAlign: pw.TextAlign.center));

  pw.Widget _pdfTD(String t, pw.Font font,
      {double? w, bool left = false, bool bold2 = false, PdfColor? bg}) =>
      pw.Container(
          width: w, color: bg,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: pw.Text(t,
              style: pw.TextStyle(font: font, fontSize: 7,
                  fontWeight: bold2 ? pw.FontWeight.bold : pw.FontWeight.normal),
              textAlign: left ? pw.TextAlign.left : pw.TextAlign.center));

  pw.Widget _pdfHeader(String title, pw.Font bold, pw.Font font) =>
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(_headerLine, style: pw.TextStyle(font: bold, fontSize: 10)),
        pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 8,
            color: PdfColor.fromInt(0xFF3A3A5C))),
        pw.SizedBox(height: 3),
        pw.Container(height: 1, color: PdfColors.black),
        pw.SizedBox(height: 6),
      ]);

  // ── Print dispatcher ────────────────────────────────────────────────────────
  Future<void> _print(String section) async {
    setState(() => _printing = true);
    try {
      // Pre-load duty batches for duty section
      if (section == 'duty' || section == 'all') {
        for (final dt in _districtRules) {
          await _loadDutyBatches(dt['dutyType'] as String);
        }
      }
      await Printing.layoutPdf(
        onLayout: (_) async => _buildPdf(section),
        name: 'election_history_${widget.electionId}',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Print विफल: $e', error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<Uint8List> _buildPdf(String section) async {
    final font = await _font;
    final bold = await _bold;
    final doc  = pw.Document();
    final A4L  = PdfPageFormat.a4.landscape;
    final A4P  = PdfPageFormat.a4;
    final alt  = const PdfColor.fromInt(0xFFF5F0FF);
    final footBg = const PdfColor.fromInt(0xFFE0D8F5);

    pw.Widget footer(pw.Context ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.5))),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(_headerLine, style: pw.TextStyle(font: font, fontSize: 6)),
              pw.Text('पृष्ठ ${ctx.pageNumber}/${ctx.pagesCount}',
                  style: pw.TextStyle(font: font, fontSize: 6)),
            ]));

    // ── 1. Booth Manak ──────────────────────────────────────────────────────
    if (section == 'all' || section == 'booth_manak') {
      for (final sens in ['A++', 'A', 'B', 'C']) {
        final list = _boothManak[sens] ?? [];
        if (list.isEmpty) continue;
        final rows = <pw.TableRow>[
          pw.TableRow(children: [
            _pdfTH('बूथ', bold, w: 22), _pdfTH('केन्द्र', bold, w: 36),
            _pdfTH('SI स.', bold, w: 28), _pdfTH('SI नि.', bold, w: 28),
            _pdfTH('HC स.', bold, w: 28), _pdfTH('HC नि.', bold, w: 28),
            _pdfTH('Con स.', bold, w: 30), _pdfTH('Con नि.', bold, w: 30),
            _pdfTH('Aux स.', bold, w: 28), _pdfTH('Aux नि.', bold, w: 28),
            _pdfTH('PAC', bold, w: 26), _pdfTH('कुल', bold, w: 32),
          ]),
        ];
        final totals = List.filled(10, 0.0);
        for (int i = 0; i < list.length; i++) {
          final r = list[i];
          final vals = [
            _d(r,'siArmedCount'), _d(r,'siUnarmedCount'),
            _d(r,'hcArmedCount'), _d(r,'hcUnarmedCount'),
            _d(r,'constArmedCount'), _d(r,'constUnarmedCount'),
            _d(r,'auxArmedCount'), _d(r,'auxUnarmedCount'),
            _d(r,'pacCount'), 0.0,
          ];
          vals[9] = vals.take(8).fold(0.0, (a, b) => a + b);
          for (int j = 0; j < 10; j++) totals[j] += vals[j];
          final bg = i.isEven ? PdfColors.white : alt;
          rows.add(pw.TableRow(children: [
            _pdfTD('${_n(r,"boothCount")}', font, w: 22, bg: bg),
            _pdfTD('—', font, w: 36, bg: bg),
            _pdfTD('${_n(r,"siArmedCount")}',     font, w: 28, bg: bg),
            _pdfTD('${_n(r,"siUnarmedCount")}',   font, w: 28, bg: bg),
            _pdfTD('${_n(r,"hcArmedCount")}',     font, w: 28, bg: bg),
            _pdfTD('${_n(r,"hcUnarmedCount")}',   font, w: 28, bg: bg),
            _pdfTD('${_n(r,"constArmedCount")}',  font, w: 30, bg: bg),
            _pdfTD('${_n(r,"constUnarmedCount")}',font, w: 30, bg: bg),
            _pdfTD('${_n(r,"auxArmedCount")}',    font, w: 28, bg: bg),
            _pdfTD('${_n(r,"auxUnarmedCount")}',  font, w: 28, bg: bg),
            _pdfTD('${_f(r,"pacCount")}',         font, w: 26, bg: bg),
            _pdfTD('${vals[9].toInt()}',           font, w: 32, bold2: true, bg: bg),
          ]));
        }
        doc.addPage(pw.MultiPage(
          pageFormat: A4L, margin: const pw.EdgeInsets.all(14), footer: footer,
          build: (_) => [
            _pdfHeader('बूथ मानक — $sens श्रेणी (Archived)', bold, font),
            pw.Table(border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
                children: rows),
          ],
        ));
      }
    }

    // ── 2. District Rules ───────────────────────────────────────────────────
    if (section == 'all' || section == 'district_rules') {
      if (_districtRules.isNotEmpty) {
        final rows = <pw.TableRow>[
          pw.TableRow(children: [
            _pdfTH('क्र.',    bold, w: 20), _pdfTH('ड्यूटी',   bold, w: 110),
            _pdfTH('संख्या', bold, w: 32),
            _pdfTH('SI स.', bold, w: 24), _pdfTH('SI नि.', bold, w: 24),
            _pdfTH('HC स.', bold, w: 24), _pdfTH('HC नि.', bold, w: 24),
            _pdfTH('Con स.', bold, w: 26), _pdfTH('Con नि.', bold, w: 26),
            _pdfTH('Aux', bold, w: 26), _pdfTH('PAC', bold, w: 26),
            _pdfTH('कुल/बैच', bold, w: 34),
          ]),
        ];
        for (int i = 0; i < _districtRules.length; i++) {
          final r  = _districtRules[i];
          final bg = i.isEven ? PdfColors.white : alt;
          final tot = _n(r,'siArmedCount') + _n(r,'siUnarmedCount')
              + _n(r,'hcArmedCount') + _n(r,'hcUnarmedCount')
              + _n(r,'constArmedCount') + _n(r,'constUnarmedCount')
              + _n(r,'auxArmedCount') + _n(r,'auxUnarmedCount');
          rows.add(pw.TableRow(children: [
            _pdfTD('${i+1}',                       font, w: 20, bg: bg),
            _pdfTD(r['dutyLabelHi'] as String? ?? '', font, w: 110, left: true, bg: bg),
            _pdfTD('${r['sankhya'] ?? 0}',         font, w: 32, bg: bg),
            _pdfTD('${_n(r,"siArmedCount")}',      font, w: 24, bg: bg),
            _pdfTD('${_n(r,"siUnarmedCount")}',    font, w: 24, bg: bg),
            _pdfTD('${_n(r,"hcArmedCount")}',      font, w: 24, bg: bg),
            _pdfTD('${_n(r,"hcUnarmedCount")}',    font, w: 24, bg: bg),
            _pdfTD('${_n(r,"constArmedCount")}',   font, w: 26, bg: bg),
            _pdfTD('${_n(r,"constUnarmedCount")}', font, w: 26, bg: bg),
            _pdfTD('${_n(r,"auxArmedCount") + _n(r,"auxUnarmedCount")}',
                font, w: 26, bg: bg),
            _pdfTD(_f(r,'pacCount'),               font, w: 26, bg: bg),
            _pdfTD('$tot',                         font, w: 34, bold2: true, bg: bg),
          ]));
        }
        doc.addPage(pw.MultiPage(
          pageFormat: A4L, margin: const pw.EdgeInsets.all(14), footer: footer,
          build: (_) => [
            _pdfHeader('जनपदीय ड्यूटी मानक (Archived)', bold, font),
            pw.Table(border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
                children: rows),
          ],
        ));
      }
    }

    // ── 3. District duty batch-wise ─────────────────────────────────────────
    if (section == 'all' || section == 'duty') {
      for (final dr in _districtRules) {
        final dutyType = dr['dutyType'] as String;
        final batches  = _dutyBatches[dutyType] ?? [];
        if (batches.isEmpty) continue;
        final label = dr['dutyLabelHi'] as String? ?? dutyType;
        final staffRows = <pw.TableRow>[
          pw.TableRow(children: [
            _pdfTH('क्र.',  bold, w: 22), _pdfTH('नाम',    bold, w: 90),
            _pdfTH('PNO',   bold, w: 50), _pdfTH('पद',     bold, w: 58),
            _pdfTH('थाना',  bold, w: 70), _pdfTH('मोबाइल', bold, w: 68),
            _pdfTH('Armed', bold, w: 32), _pdfTH('बस',     bold, w: 30),
          ]),
        ];
        int gSrl = 0;
        for (final b in batches) {
          final bNo    = b['batchNo'] as int? ?? 0;
          final staff  = (b['staff'] as List?)?.cast<Map>() ?? [];
          final busNo  = b['busNo'] as String? ?? '';
          final note   = b['note']  as String? ?? '';
          staffRows.add(pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDE3F8)),
            children: [
              _pdfTD('B$bNo', bold, w: 22),
              _pdfTD('Batch $bNo • ${staff.length} staff'
                  '${busNo.isNotEmpty ? " • Bus: $busNo" : ""}'
                  '${note.isNotEmpty ? " • $note" : ""}',
                  font, w: 418, left: true),
              for (int _ = 0; _ < 6; _++) _pdfTD('', font, w: 0),
            ],
          ));
          for (final s in staff) {
            gSrl++;
            final bg = gSrl.isEven ? alt : PdfColors.white;
            staffRows.add(pw.TableRow(children: [
              _pdfTD('$gSrl',                           font, w: 22, bg: bg),
              _pdfTD(s['name'] as String? ?? '',        font, w: 90, left: true, bg: bg),
              _pdfTD(s['pno']  as String? ?? '',        font, w: 50, bg: bg),
              _pdfTD(s['rank'] as String? ?? '',        font, w: 58, bg: bg),
              _pdfTD(s['thana'] as String? ?? '',       font, w: 70, left: true, bg: bg),
              _pdfTD(s['mobile'] as String? ?? '',      font, w: 68, bg: bg),
              _pdfTD((s['isArmed'] as bool? ?? false) ? 'हाँ' : 'नहीं', font, w: 32, bg: bg),
              _pdfTD(busNo.isEmpty ? '-' : busNo,       font, w: 30, bg: bg),
            ]));
          }
        }
        doc.addPage(pw.MultiPage(
          pageFormat: A4P, margin: const pw.EdgeInsets.all(14), footer: footer,
          build: (_) => [
            _pdfHeader('$label — Batch-wise Staff', bold, font),
            pw.Table(border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
                children: staffRows),
          ],
        ));
      }
    }

    // ── 4. Officers ─────────────────────────────────────────────────────────
    if (section == 'all' || section == 'officers') {
      final szList = (_hierarchyData['superZones'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      for (final sz in szList) {
        final zones = (sz['zones'] as List? ?? []).cast<Map<String, dynamic>>();
        final koff  = (sz['kshetraOfficers'] as List? ?? []).cast<Map>();
        final rows  = <pw.TableRow>[
          pw.TableRow(children: [
            _pdfTH('स्तर', bold, w: 44), _pdfTH('क्षेत्र / नाम', bold, w: 130),
            _pdfTH('अधिकारी का नाम', bold, w: 110), _pdfTH('PNO', bold, w: 52),
            _pdfTH('पद', bold, w: 60), _pdfTH('मोबाइल', bold, w: 68),
          ]),
        ];
        int rowIdx = 0;
        for (final o in koff) {
          final bg = rowIdx.isEven ? PdfColors.white : alt;
          rows.add(pw.TableRow(children: [
            _pdfTD('क्षेत्र', font, w: 44, bg: bg),
            _pdfTD('${sz['superZoneName']}', font, w: 130, left: true, bg: bg),
            _pdfTD(o['name'] as String? ?? '',   font, w: 110, left: true, bg: bg),
            _pdfTD(o['pno']  as String? ?? '',   font, w: 52, bg: bg),
            _pdfTD(o['rank'] as String? ?? '',   font, w: 60, bg: bg),
            _pdfTD(o['mobile'] as String? ?? '', font, w: 68, bg: bg),
          ]));
          rowIdx++;
        }
        for (final z in zones) {
          final zoff  = (z['zonalOfficers'] as List? ?? []).cast<Map>();
          final sects = (z['sectors'] as List? ?? []).cast<Map<String, dynamic>>();
          for (final o in zoff) {
            final bg = rowIdx.isEven ? PdfColors.white : alt;
            rows.add(pw.TableRow(children: [
              _pdfTD('जोन', font, w: 44, bg: bg),
              _pdfTD('${z['zoneName']}', font, w: 130, left: true, bg: bg),
              _pdfTD(o['name'] as String? ?? '',   font, w: 110, left: true, bg: bg),
              _pdfTD(o['pno']  as String? ?? '',   font, w: 52, bg: bg),
              _pdfTD(o['rank'] as String? ?? '',   font, w: 60, bg: bg),
              _pdfTD(o['mobile'] as String? ?? '', font, w: 68, bg: bg),
            ]));
            rowIdx++;
          }
          for (final s in sects) {
            final soff = (s['sectorOfficers'] as List? ?? []).cast<Map>();
            for (final o in soff) {
              final bg = rowIdx.isEven ? PdfColors.white : alt;
              rows.add(pw.TableRow(children: [
                _pdfTD('सैक्टर', font, w: 44, bg: bg),
                _pdfTD('${s['sectorName']}', font, w: 130, left: true, bg: bg),
                _pdfTD(o['name'] as String? ?? '',   font, w: 110, left: true, bg: bg),
                _pdfTD(o['pno']  as String? ?? '',   font, w: 52, bg: bg),
                _pdfTD(o['rank'] as String? ?? '',   font, w: 60, bg: bg),
                _pdfTD(o['mobile'] as String? ?? '', font, w: 68, bg: bg),
              ]));
              rowIdx++;
            }
          }
        }
        if (rows.length > 1) {
          doc.addPage(pw.MultiPage(
            pageFormat: A4P, margin: const pw.EdgeInsets.all(14), footer: footer,
            build: (_) => [
              _pdfHeader(
                  'अधिकारी विवरण — सुपर जोन: ${sz['superZoneName']}', bold, font),
              pw.Table(border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
                  children: rows),
            ],
          ));
        }
      }
    }

    // ── 5. Booth Staff ──────────────────────────────────────────────────────
    if (section == 'all' || section == 'booth_staff') {
      if (_boothStaff.isNotEmpty) {
        final rows = <pw.TableRow>[
          pw.TableRow(children: [
            _pdfTH('क्र.', bold, w: 22), _pdfTH('नाम', bold, w: 90),
            _pdfTH('PNO',  bold, w: 50), _pdfTH('पद', bold, w: 55),
            _pdfTH('केन्द्र', bold, w: 90), _pdfTH('प्रकार', bold, w: 28),
            _pdfTH('थाना', bold, w: 65), _pdfTH('मोबाइल', bold, w: 65),
            _pdfTH('Armed', bold, w: 28), _pdfTH('उपस्थित', bold, w: 36),
          ]),
        ];
        for (int i = 0; i < _boothStaff.length; i++) {
          final r = _boothStaff[i];
          final bg = i.isEven ? PdfColors.white : alt;
          rows.add(pw.TableRow(children: [
            _pdfTD('${i+1}', font, w: 22, bg: bg),
            _pdfTD(r['staffName'] as String? ?? r['name'] as String? ?? '', font, w: 90, left: true, bg: bg),
            _pdfTD(r['staffPno']  as String? ?? r['pno']  as String? ?? '', font, w: 50, bg: bg),
            _pdfTD(r['staffRank'] as String? ?? r['rank'] as String? ?? '', font, w: 55, bg: bg),
            _pdfTD(r['centerName'] as String? ?? '', font, w: 90, left: true, bg: bg),
            _pdfTD(r['centerType'] as String? ?? '', font, w: 28, bg: bg),
            _pdfTD(r['staffThana'] as String? ?? r['thana'] as String? ?? '', font, w: 65, left: true, bg: bg),
            _pdfTD(r['staffMobile'] as String? ?? r['mobile'] as String? ?? '', font, w: 65, bg: bg),
            _pdfTD((r['isArmed'] as bool? ?? false) ? 'हाँ' : 'नहीं', font, w: 28, bg: bg),
            _pdfTD((r['attended'] as bool? ?? false) ? 'हाँ' : '-', font, w: 36, bg: bg),
          ]));
        }
        doc.addPage(pw.MultiPage(
          pageFormat: A4L, margin: const pw.EdgeInsets.all(14), footer: footer,
          build: (_) => [
            _pdfHeader('बूथ ड्यूटी स्टाफ (Archived, ${_boothStaff.length})', bold, font),
            pw.Table(border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
                children: rows),
          ],
        ));
      }
    }

    if (doc.document.pdfPageList.pages.isEmpty) {
      doc.addPage(pw.Page(build: (_) => pw.Center(
          child: pw.Text('कोई डेटा नहीं',
              style: pw.TextStyle(font: bold, fontSize: 14)))));
    }
    return Uint8List.fromList(await doc.save());
  }

  int  _n(Map r, String k) => ((r[k] ?? 0) as num).toInt();
  double _d(Map r, String k) => ((r[k] ?? 0) as num).toDouble();
  String _f(Map r, String k) {
    final v = _d(r, k);
    return v == 0 ? '0' : (v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1));
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary, foregroundColor: Colors.white, elevation: 0,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_electionName.isEmpty ? 'Election History' : _electionName,
              style: TextStyle(fontSize: r.s(13, 15), fontWeight: FontWeight.w800),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('$_district${_electionDate.isNotEmpty ? " | $_electionDate" : ""}',
              style: TextStyle(fontSize: r.s(9, 11), color: Colors.white70),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          if (_printing)
            const Padding(padding: EdgeInsets.all(14),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.print_outlined, color: Colors.white),
              tooltip: 'प्रिंट / PDF',
              onSelected: _print,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'all', child: Text('सभी रिपोर्ट')),
                const PopupMenuItem(value: 'booth_manak', child: Text('बूथ मानक')),
                const PopupMenuItem(value: 'district_rules', child: Text('जनपदीय मानक')),
                const PopupMenuItem(value: 'duty', child: Text('ड्यूटी Batch-wise')),
                const PopupMenuItem(value: 'officers', child: Text('अधिकारी विवरण')),
                const PopupMenuItem(value: 'booth_staff', child: Text('बूथ स्टाफ')),
              ],
            ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true, tabAlignment: TabAlignment.start,
          indicatorColor: Colors.white, indicatorWeight: 3,
          labelColor: Colors.white, unselectedLabelColor: Colors.white60,
          labelStyle: TextStyle(fontSize: r.s(10.5, 12), fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'बूथ मानक',       icon: Icon(Icons.how_to_vote_outlined,  size: 14)),
            Tab(text: 'जनपदीय मानक',     icon: Icon(Icons.shield_outlined,       size: 14)),
            Tab(text: 'ड्यूटी Batches',  icon: Icon(Icons.people_outlined,       size: 14)),
            Tab(text: 'अधिकारी',         icon: Icon(Icons.account_tree_outlined, size: 14)),
            Tab(text: 'बूथ स्टाफ',       icon: Icon(Icons.badge_outlined,        size: 14)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Column(children: [
              _ElectionInfoBanner(election: widget.election),
              Expanded(child: TabBarView(controller: _tab, children: [
                _BoothManakHistoryTab(
                    rules: _boothManak,
                    onPrint: _printing ? null : () => _print('booth_manak')),
                _DistrictRulesHistoryTab(
                    rules: _districtRules,
                    dutySummary: _dutySummary,
                    onPrint: _printing ? null : () => _print('district_rules')),
                _DutyBatchesHistoryTab(
                    districtRules: _districtRules,
                    dutySummary: _dutySummary,
                    dutyBatches: _dutyBatches,
                    loadedTypes: _loadedDutyTypes,
                    onLoadBatches: _loadDutyBatches,
                    electionId: widget.electionId,
                    onPrint: _printing ? null : () => _print('duty')),
                _OfficersHistoryTab(
                    data: _hierarchyData,
                    onPrint: _printing ? null : () => _print('officers')),
                _BoothStaffHistoryTab(
                    staff: _boothStaff,
                    total: _boothStaffTotal,
                    summary: _boothSummary,
                    onLoadMore: _loadMoreBoothStaff,
                    onPrint: _printing ? null : () => _print('booth_staff')),
              ])),
            ]),
    );
  }
}

// ── Election info banner ──────────────────────────────────────────────────────
class _ElectionInfoBanner extends StatelessWidget {
  final Map<String, dynamic> election;
  const _ElectionInfoBanner({required this.election});

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    final name  = (election['electionName'] ?? election['election_name'] ?? '') as String;
    final dist  = (election['district'] ?? '') as String;
    final date  = (election['electionDate'] ?? election['election_date'] ?? '') as String;
    final phase = (election['phase'] ?? '') as String;
    final year  = (election['electionYear'] ?? election['election_year'] ?? '') as String;
    final state = (election['state'] ?? '') as String;
    return Container(
      color: _kGold.withOpacity(0.09),
      padding: EdgeInsets.symmetric(horizontal: r.s(10, 14), vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _chip(Icons.how_to_vote_outlined, name, _kPrimary),
          if (dist.isNotEmpty)   _chip(Icons.location_city, dist, _kTeal),
          if (date.isNotEmpty)   _chip(Icons.calendar_today, date, _kGold),
          if (phase.isNotEmpty)  _chip(Icons.layers_outlined, 'Phase $phase', _kOrange),
          if (year.isNotEmpty)   _chip(Icons.access_time, year, _kSubtle),
          if (state.isNotEmpty)  _chip(Icons.map_outlined, state, _kSubtle),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _kSuccess.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kSuccess.withOpacity(0.3))),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.archive_outlined, size: 11, color: _kSuccess),
              SizedBox(width: 4),
              Text('Archived', style: TextStyle(color: _kSuccess, fontSize: 10,
                  fontWeight: FontWeight.w800)),
            ])),
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color c) =>
      Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: c.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.withOpacity(0.25))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: c, fontSize: 10.5,
              fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]));
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 1 — BOOTH MANAK HISTORY
// ══════════════════════════════════════════════════════════════════════════════
class _BoothManakHistoryTab extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> rules;
  final VoidCallback? onPrint;
  const _BoothManakHistoryTab({required this.rules, required this.onPrint});

  int _n(Map r, String k) => ((r[k] ?? 0) as num).toInt();
  String _fp(Map r, String k) {
    final v = ((r[k] ?? 0) as num).toDouble();
    return v == 0 ? '0' : (v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1));
  }

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    final hasSome = rules.values.any((l) => l.isNotEmpty);
    return Column(children: [
      _SectionHeader(title: 'बूथ मानक (Archived)', icon: Icons.how_to_vote_outlined,
          color: _kPrimary, onPrint: onPrint),
      Expanded(child: !hasSome
          ? const _EmptyState(icon: Icons.table_chart_outlined, title: 'कोई बूथ मानक नहीं')
          : ListView(
              padding: EdgeInsets.fromLTRB(r.s(8, 12), 10, r.s(8, 12), 24),
              children: [
                for (final s in ['A++', 'A', 'B', 'C'])
                  if ((rules[s] ?? []).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ManakTable(
                        sens: s, color: _sensColor(s),
                        rows: rules[s]!,
                        n: _n, fp: _fp,
                      ),
                    ),
              ],
            )),
    ]);
  }
}

class _ManakTable extends StatelessWidget {
  final String sens;
  final Color  color;
  final List<Map<String, dynamic>> rows;
  final int Function(Map, String) n;
  final String Function(Map, String) fp;
  const _ManakTable({required this.sens, required this.color,
      required this.rows, required this.n, required this.fp});

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    const heads = ['बूथ','SI स.','SI नि.','HC स.','HC नि.',
        'Con स.','Con नि.','Aux स.','Aux नि.','PAC','कुल'];
    const ws    = [36.0, 38.0, 38.0, 38.0, 38.0, 40.0, 40.0, 38.0, 38.0, 34.0, 38.0];

    int tSIA=0,tSIU=0,tHCA=0,tHCU=0,tCA=0,tCU=0,tAxA=0,tAxU=0;
    double tPAC=0;
    for (final row in rows) {
      tSIA += n(row,'siArmedCount'); tSIU += n(row,'siUnarmedCount');
      tHCA += n(row,'hcArmedCount'); tHCU += n(row,'hcUnarmedCount');
      tCA  += n(row,'constArmedCount'); tCU  += n(row,'constUnarmedCount');
      tAxA += n(row,'auxArmedCount'); tAxU += n(row,'auxUnarmedCount');
      tPAC += ((row['pacCount'] ?? 0) as num).toDouble();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: color.withOpacity(0.09),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11))),
          child: Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
                child: Text(sens, style: const TextStyle(color: Colors.white,
                    fontSize: 12, fontWeight: FontWeight.w900))),
            const SizedBox(width: 10),
            Expanded(child: Text('${rows.length} बूथ-स्तर',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))),
            Text('Total: ${tSIA+tSIU+tHCA+tHCU+tCA+tCU+tAxA+tAxU} per-batch',
                style: TextStyle(color: color.withOpacity(0.8), fontSize: 10)),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: ws.fold<double>(0.0, (a, b) => a + (b ?? 0)),
            child: Table(
              border: TableBorder.all(color: _kBorder.withOpacity(0.3), width: 0.5),
              columnWidths: {for (int i = 0; i < ws.length; i++) i: FixedColumnWidth(ws[i])},
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
                  children: heads.map((h) => _th(h)).toList(),
                ),
                ...rows.asMap().entries.map((e) {
                  final i = e.key; final row = e.value;
                  final tot = n(row,'siArmedCount') + n(row,'siUnarmedCount')
                      + n(row,'hcArmedCount') + n(row,'hcUnarmedCount')
                      + n(row,'constArmedCount') + n(row,'constUnarmedCount')
                      + n(row,'auxArmedCount') + n(row,'auxUnarmedCount');
                  final bg = i.isEven ? Colors.white : const Color(0xFFFBF7FF);
                  return TableRow(
                    decoration: BoxDecoration(color: bg),
                    children: [
                      _td('${n(row,"boothCount")}',  center: true),
                      _td('${n(row,"siArmedCount")}',    center: true),
                      _td('${n(row,"siUnarmedCount")}',  center: true),
                      _td('${n(row,"hcArmedCount")}',    center: true),
                      _td('${n(row,"hcUnarmedCount")}',  center: true),
                      _td('${n(row,"constArmedCount")}', center: true),
                      _td('${n(row,"constUnarmedCount")}',center: true),
                      _td('${n(row,"auxArmedCount")}',   center: true),
                      _td('${n(row,"auxUnarmedCount")}', center: true),
                      _td(fp(row,'pacCount'),             center: true),
                      _td('$tot',                         center: true, bold: true),
                    ],
                  );
                }),
                // totals row
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFECE5F5)),
                  children: [
                    _td('योग', bold: true),
                    _td('$tSIA', bold: true, center: true),
                    _td('$tSIU', bold: true, center: true),
                    _td('$tHCA', bold: true, center: true),
                    _td('$tHCU', bold: true, center: true),
                    _td('$tCA',  bold: true, center: true),
                    _td('$tCU',  bold: true, center: true),
                    _td('$tAxA', bold: true, center: true),
                    _td('$tAxU', bold: true, center: true),
                    _td(tPAC == 0 ? '0' : tPAC.toStringAsFixed(1),
                        bold: true, center: true),
                    _td('${tSIA+tSIU+tHCA+tHCU+tCA+tCU+tAxA+tAxU}',
                        bold: true, center: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  static Widget _th(String t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
    child: Text(t, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 9.5,
            fontWeight: FontWeight.w800)));

  static Widget _td(String t, {bool center = false, bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: Text(t, textAlign: center ? TextAlign.center : TextAlign.left,
        style: TextStyle(color: _kDark, fontSize: 10.5,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w400)));
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 2 — DISTRICT RULES HISTORY
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictRulesHistoryTab extends StatelessWidget {
  final List<Map<String, dynamic>>       rules;
  final Map<String, Map<String, dynamic>> dutySummary;
  final VoidCallback? onPrint;
  const _DistrictRulesHistoryTab(
      {required this.rules, required this.dutySummary, required this.onPrint});

  int _n(Map r, String k) => ((r[k] ?? 0) as num).toInt();

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    if (rules.isEmpty) {
      return Column(children: [
        _SectionHeader(title: 'जनपदीय मानक (Archived)',
            icon: Icons.shield_outlined, color: _kPurple, onPrint: onPrint),
        const Expanded(child: _EmptyState(
            icon: Icons.shield_outlined, title: 'कोई मानक नहीं')),
      ]);
    }
    // totals
    int tSan=0, tSIA=0, tSIU=0, tHCA=0, tHCU=0, tCA=0, tCU=0, tAxA=0, tAxU=0;
    double tPAC = 0;
    for (final row in rules) {
      tSan += _n(row,'sankhya');
      tSIA += _n(row,'siArmedCount'); tSIU += _n(row,'siUnarmedCount');
      tHCA += _n(row,'hcArmedCount'); tHCU += _n(row,'hcUnarmedCount');
      tCA  += _n(row,'constArmedCount'); tCU  += _n(row,'constUnarmedCount');
      tAxA += _n(row,'auxArmedCount'); tAxU += _n(row,'auxUnarmedCount');
      tPAC += ((row['pacCount'] ?? 0) as num).toDouble();
    }
    const List<double?> ws = [28.0, null, 42.0, 30.0, 30.0, 30.0, 30.0, 32.0, 32.0, 32.0, 30.0, 38.0];
    final heads = ['क्र.', 'ड्यूटी', 'संख्या', 'SI स.', 'SI नि.',
        'HC स.', 'HC नि.', 'Con स.', 'Con नि.', 'Aux', 'PAC', 'कुल'];

    return Column(children: [
      _SectionHeader(title: 'जनपदीय मानक (Archived)', icon: Icons.shield_outlined,
          color: _kPurple, onPrint: onPrint),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: r.s(8, 12), vertical: 8),
        child: Row(children: [
          _StatChipH('${rules.length}',     'ड्यूटी',    _kPurple),
          _StatChipH('$tSan',              'संख्या',     _kOrange),
          _StatChipH('${tSIA+tSIU+tHCA+tHCU+tCA+tCU+tAxA+tAxU}', 'बल/बैच', _kSuccess),
        ]),
      ),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(r.s(8, 12), 0, r.s(8, 12), 24),
        child: _GovHTable(
          headers: heads, widths: ws,
          rows: rules.asMap().entries.map((e) {
            final i = e.key; final row = e.value;
            final tot = _n(row,'siArmedCount') + _n(row,'siUnarmedCount')
                + _n(row,'hcArmedCount') + _n(row,'hcUnarmedCount')
                + _n(row,'constArmedCount') + _n(row,'constUnarmedCount')
                + _n(row,'auxArmedCount') + _n(row,'auxUnarmedCount');
            final pac = ((row['pacCount'] ?? 0) as num).toDouble();
            return [
              '${i+1}',
              row['dutyLabelHi'] as String? ?? '',
              '${_n(row,"sankhya")}',
              '${_n(row,"siArmedCount")}',   '${_n(row,"siUnarmedCount")}',
              '${_n(row,"hcArmedCount")}',   '${_n(row,"hcUnarmedCount")}',
              '${_n(row,"constArmedCount")}','${_n(row,"constUnarmedCount")}',
              '${_n(row,"auxArmedCount") + _n(row,"auxUnarmedCount")}',
              pac == 0 ? '0' : pac.toStringAsFixed(1),
              '$tot',
            ];
          }).toList(),
          footerRow: [
            '', 'योग', '$tSan',
            '$tSIA', '$tSIU', '$tHCA', '$tHCU', '$tCA', '$tCU',
            '${tAxA+tAxU}',
            tPAC == 0 ? '0' : tPAC.toStringAsFixed(1),
            '${tSIA+tSIU+tHCA+tHCU+tCA+tCU+tAxA+tAxU}',
          ],
          nameColIdx: 1,
          color: _kPurple,
        ),
      )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 3 — DUTY BATCHES HISTORY
// ══════════════════════════════════════════════════════════════════════════════
class _DutyBatchesHistoryTab extends StatefulWidget {
  final List<Map<String, dynamic>>        districtRules;
  final Map<String, Map<String, dynamic>> dutySummary;
  final Map<String, List<Map<String, dynamic>>> dutyBatches;
  final Set<String>   loadedTypes;
  final Future<void>  Function(String) onLoadBatches;
  final int           electionId;
  final VoidCallback? onPrint;

  const _DutyBatchesHistoryTab({
    required this.districtRules, required this.dutySummary,
    required this.dutyBatches,  required this.loadedTypes,
    required this.onLoadBatches, required this.electionId,
    required this.onPrint,
  });

  @override
  State<_DutyBatchesHistoryTab> createState() => _DutyBatchesHistoryTabState();
}

class _DutyBatchesHistoryTabState extends State<_DutyBatchesHistoryTab> {
  Set<String> _expanded = {};
  Set<String> _loading  = {};

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    if (widget.districtRules.isEmpty) {
      return Column(children: [
        _SectionHeader(title: 'ड्यूटी Batches (Archived)',
            icon: Icons.people_outlined, color: _kTeal, onPrint: widget.onPrint),
        const Expanded(child: _EmptyState(icon: Icons.people_outline,
            title: 'कोई ड्यूटी नहीं')),
      ]);
    }
    return Column(children: [
      _SectionHeader(title: 'ड्यूटी Batches (Archived)',
          icon: Icons.people_outlined, color: _kTeal, onPrint: widget.onPrint),
      Expanded(child: ListView.builder(
        padding: EdgeInsets.fromLTRB(r.s(8, 12), 10, r.s(8, 12), 24),
        itemCount: widget.districtRules.length,
        itemBuilder: (_, i) {
          final dr       = widget.districtRules[i];
          final dutyType = dr['dutyType'] as String;
          final label    = dr['dutyLabelHi'] as String? ?? dutyType;
          final summary  = widget.dutySummary[dutyType] ?? {};
          final total    = (summary['totalStaff'] ?? 0) as int;
          final batches  = (summary['batchCount']  ?? 0) as int;
          final sankhya  = _n(dr, 'sankhya');
          final isExp    = _expanded.contains(dutyType);
          final isLoading = _loading.contains(dutyType);
          final batchData = widget.dutyBatches[dutyType] ?? [];

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kTeal.withOpacity(0.3)),
              boxShadow: [BoxShadow(color: _kTeal.withOpacity(0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: () async {
                  if (!isExp && !widget.loadedTypes.contains(dutyType)) {
                    setState(() => _loading.add(dutyType));
                    await widget.onLoadBatches(dutyType);
                    if (mounted) setState(() => _loading.remove(dutyType));
                  }
                  if (mounted) setState(() {
                    if (isExp) _expanded.remove(dutyType);
                    else _expanded.add(dutyType);
                  });
                },
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  decoration: BoxDecoration(
                      color: _kTeal.withOpacity(0.07),
                      borderRadius: BorderRadius.vertical(
                          top: const Radius.circular(11),
                          bottom: isExp ? Radius.zero : const Radius.circular(11))),
                  child: Row(children: [
                    Container(width: 36, height: 36,
                        decoration: BoxDecoration(
                            color: total > 0 ? _kTeal : _kSubtle.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(9)),
                        child: Icon(Icons.assignment_outlined,
                            color: total > 0 ? Colors.white : _kSubtle, size: 18)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: const TextStyle(color: _kDark,
                          fontSize: 13, fontWeight: FontWeight.w700),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Wrap(spacing: 10, children: [
                        Text('$total Staff', style: const TextStyle(
                            color: _kTeal, fontSize: 11, fontWeight: FontWeight.w800)),
                        Text('$batches Batches',
                            style: const TextStyle(color: _kSubtle, fontSize: 11)),
                        if (sankhya > 0)
                          Text('संख्या: $sankhya',
                              style: const TextStyle(color: _kOrange, fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                      ]),
                    ])),
                    if (isLoading)
                      const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _kTeal))
                    else
                      Icon(isExp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: _kTeal, size: 20),
                  ]),
                ),
              ),
              if (isExp) ...[
                if (batchData.isEmpty)
                  const Padding(padding: EdgeInsets.all(16),
                      child: _EmptyState(icon: Icons.people_outline,
                          title: 'कोई batch नहीं'))
                else
                  _BatchGroupedView(batches: batchData),
              ],
            ]),
          );
        },
      )),
    ]);
  }

  int _n(Map r, String k) => ((r[k] ?? 0) as num).toInt();
}

class _BatchGroupedView extends StatelessWidget {
  final List<Map<String, dynamic>> batches;
  const _BatchGroupedView({required this.batches});

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: _GovHTable(
        headers: const ['क्र.', 'नाम', 'PNO', 'पद', 'थाना', 'मोबाइल', 'Armed'],
        widths:  const [28.0, null, 72.0, 64.0, 80.0, 78.0, 44.0],
        nameColIdx: 1,
        color: _kTeal,
        rows: const [],
        groupedRows: () {
          final out = <_GovRowH>[];
          int gSrl = 0;
          for (final b in batches) {
            final bNo   = b['batchNo'] as int? ?? 0;
            final staff = (b['staff'] as List?)?.cast<Map>() ?? [];
            final busNo = b['busNo'] as String? ?? '';
            final note  = b['note']  as String? ?? '';
            final lbl   = StringBuffer('Batch $bNo  •  ${staff.length} staff');
            if (busNo.isNotEmpty) lbl.write('  •  Bus: $busNo');
            if (note.isNotEmpty)  lbl.write('  •  $note');
            out.add(_GovRowH.batch(lbl.toString()));
            for (final s in staff) {
              gSrl++;
              out.add(_GovRowH.data([
                '$gSrl',
                s['name']   as String? ?? '',
                s['pno']    as String? ?? '',
                s['rank']   as String? ?? '',
                s['thana']  as String? ?? '',
                s['mobile'] as String? ?? '',
                (s['isArmed'] as bool? ?? false) ? 'हाँ' : 'नहीं',
              ]));
            }
          }
          return out;
        }(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 4 — OFFICERS HISTORY
// ══════════════════════════════════════════════════════════════════════════════
class _OfficersHistoryTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onPrint;
  const _OfficersHistoryTab({required this.data, required this.onPrint});
  @override State<_OfficersHistoryTab> createState() => _OfficersHistoryTabState();
}

class _OfficersHistoryTabState extends State<_OfficersHistoryTab> {
  Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    final summary = widget.data['summary'] as Map<String, dynamic>? ?? {};
    final szList  = (widget.data['superZones'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    return Column(children: [
      _SectionHeader(title: 'अधिकारी विवरण (Archived)',
          icon: Icons.account_tree_outlined, color: _kIndigo, onPrint: widget.onPrint),
      if (summary.isNotEmpty)
        Container(
          color: _kIndigo.withOpacity(0.06),
          padding: EdgeInsets.symmetric(horizontal: r.s(10, 14), vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _StatChipH('${summary['superZoneCount'] ?? 0}', 'सुपर जोन', _kPrimary),
              _StatChipH('${summary['zoneCount'] ?? 0}',      'जोन',      _kTeal),
              _StatChipH('${summary['sectorCount'] ?? 0}',    'सैक्टर',   _kSuccess),
              _StatChipH('${summary['kshetraOfficers'] ?? 0}','क्षेत्र अ.',_kGold),
              _StatChipH('${summary['zonalOfficers'] ?? 0}',  'जोनल अ.',  _kOrange),
              _StatChipH('${summary['sectorOfficers'] ?? 0}', 'सैक्टर अ.',_kPurple),
            ]),
          ),
        ),
      Expanded(child: szList.isEmpty
          ? const _EmptyState(icon: Icons.people_outline, title: 'कोई अधिकारी नहीं')
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(r.s(8, 12), 10, r.s(8, 12), 24),
              itemCount: szList.length,
              itemBuilder: (_, i) {
                final sz     = szList[i];
                final szId   = sz['superZoneId'] as int? ?? i;
                final isExp  = _expanded.contains(szId);
                final zones  = (sz['zones'] as List? ?? []).cast<Map<String, dynamic>>();
                final koff   = (sz['kshetraOfficers'] as List? ?? []).cast<Map>();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kIndigo.withOpacity(0.3)),
                    boxShadow: [BoxShadow(color: _kIndigo.withOpacity(0.05),
                        blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    InkWell(
                      onTap: () => setState(() {
                        if (isExp) _expanded.remove(szId);
                        else _expanded.add(szId);
                      }),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Color(0xFF0F2B5B), Color(0xFF1E4080)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.layers_outlined, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${sz['superZoneName']}',
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 13, fontWeight: FontWeight.w800),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('Block: ${sz['superZoneBlock'] ?? ''}  •  '
                                '${zones.length} जोन  •  '
                                '${koff.length} क्षेत्र अ.',
                                style: const TextStyle(color: Colors.white60, fontSize: 10)),
                          ])),
                          Icon(isExp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              color: Colors.white, size: 20),
                        ]),
                      ),
                    ),
                    if (isExp) ...[
                      if (koff.isNotEmpty) ...[
                        _OfficerGroupTitle('क्षेत्र अधिकारी', _kGold),
                        _OfficerList(officers: koff, level: 'kshetra'),
                      ],
                      for (final z in zones) ...[
                        _OfficerGroupTitle('जोन: ${z['zoneName']}', _kTeal),
                        if ((z['zonalOfficers'] as List?)?.isNotEmpty == true)
                          _OfficerList(officers:
                              (z['zonalOfficers'] as List).cast<Map>(),
                              level: 'zonal'),
                        for (final s in (z['sectors'] as List? ?? [])
                            .cast<Map<String, dynamic>>()) ...[
                          _OfficerGroupTitle('  ↳ सैक्टर: ${s['sectorName']}',
                              _kPurple, indent: true),
                          if ((s['sectorOfficers'] as List?)?.isNotEmpty == true)
                            _OfficerList(officers:
                                (s['sectorOfficers'] as List).cast<Map>(),
                                level: 'sector'),
                        ],
                      ],
                    ],
                  ]),
                );
              })),
    ]);
  }
}

class _OfficerGroupTitle extends StatelessWidget {
  final String title;
  final Color  color;
  final bool   indent;
  const _OfficerGroupTitle(this.title, this.color, {this.indent = false});

  @override
  Widget build(BuildContext context) => Container(
    color: color.withOpacity(0.07),
    padding: EdgeInsets.fromLTRB(indent ? 20 : 12, 6, 12, 6),
    child: Row(children: [
      Container(width: 3, height: 14,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 7),
      Text(title, style: TextStyle(color: color, fontSize: 11.5,
          fontWeight: FontWeight.w700)),
    ]));
}

class _OfficerList extends StatelessWidget {
  final List<Map> officers;
  final String    level;
  const _OfficerList({required this.officers, required this.level});

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: _GovHTable(
        headers: const ['नाम', 'PNO', 'पद', 'मोबाइल'],
        widths:  const [null, 76.0, 64.0, 82.0],
        nameColIdx: 0, color: _kIndigo,
        rows: officers.map((o) => [
          o['name']   as String? ?? '',
          o['pno']    as String? ?? '',
          o['rank']   as String? ?? '',
          o['mobile'] as String? ?? '',
        ]).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 5 — BOOTH STAFF HISTORY
// ══════════════════════════════════════════════════════════════════════════════
class _BoothStaffHistoryTab extends StatelessWidget {
  final List<Map<String, dynamic>> staff;
  final int                        total;
  final Map<String, dynamic>       summary;
  final VoidCallback               onLoadMore;
  final VoidCallback?              onPrint;
  const _BoothStaffHistoryTab({required this.staff, required this.total,
      required this.summary, required this.onLoadMore, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    final r      = rOf(context);
    final totals = (summary['totals'] as Map<String, dynamic>?) ?? {};
    final byType = (summary['byType'] as List? ?? []).cast<Map<String, dynamic>>();
    final byRank = (summary['byRank'] as List? ?? []).cast<Map<String, dynamic>>();

    return Column(children: [
      _SectionHeader(title: 'बूथ स्टाफ (Archived)', icon: Icons.badge_outlined,
          color: _kGold, onPrint: onPrint),
      // summary chips
      if (totals.isNotEmpty)
        Container(
          color: _kGold.withOpacity(0.07),
          padding: EdgeInsets.symmetric(horizontal: r.s(10, 14), vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _StatChipH('${totals['total'] ?? 0}',    'कुल स्टाफ',  _kPrimary),
              _StatChipH('${totals['attended'] ?? 0}', 'उपस्थित',    _kSuccess),
              _StatChipH('${totals['centers'] ?? 0}',  'केन्द्र',     _kTeal),
              _StatChipH('${totals['armed'] ?? 0}',    'सशस्त्र',    _kPurple),
            ]),
          ),
        ),
      Expanded(child: ListView(
        padding: EdgeInsets.fromLTRB(r.s(8, 12), 10, r.s(8, 12), 24),
        children: [
          // By type summary
          if (byType.isNotEmpty) ...[
            _GroupLabel('केन्द्र-प्रकार सारांश', _kGold),
            const SizedBox(height: 6),
            _GovHTable(
              headers: const ['प्रकार', 'स्टाफ', 'केन्द्र', 'उपस्थित', 'सशस्त्र', 'निःशस्त्र'],
              widths:  const [44.0, 52.0, 52.0, 60.0, 58.0, 64.0],
              nameColIdx: -1, color: _kGold,
              rows: byType.map((r2) => [
                r2['centerType'] as String? ?? '',
                '${r2['totalStaff'] ?? 0}',
                '${r2['centersCovered'] ?? 0}',
                '${r2['attended'] ?? 0}',
                '${r2['armed'] ?? 0}',
                '${r2['unarmed'] ?? 0}',
              ]).toList(),
            ),
            const SizedBox(height: 14),
          ],
          // By rank summary
          if (byRank.isNotEmpty) ...[
            _GroupLabel('पद-वार सारांश', _kGold),
            const SizedBox(height: 6),
            _GovHTable(
              headers: const ['पद', 'कुल', 'सशस्त्र', 'निःशस्त्र', 'उपस्थित'],
              widths:  const [null, 48.0, 56.0, 70.0, 58.0],
              nameColIdx: 0, color: _kGold,
              rows: byRank.map((r2) => [
                r2['rank'] as String? ?? '',
                '${r2['total'] ?? 0}', '${r2['armed'] ?? 0}',
                '${r2['unarmed'] ?? 0}', '${r2['attended'] ?? 0}',
              ]).toList(),
            ),
            const SizedBox(height: 14),
          ],
          // Staff list
          _GroupLabel('स्टाफ सूची (${staff.length} / $total)', _kGold),
          const SizedBox(height: 6),
          _GovHTable(
            headers: const ['क्र.', 'नाम', 'PNO', 'पद', 'केन्द्र', 'प्र.', 'थाना', 'Armed', 'उपस्थित'],
            widths:  const [28.0, null, 68.0, 60.0, 90.0, 28.0, 72.0, 44.0, 50.0],
            nameColIdx: 1, color: _kGold,
            rows: staff.asMap().entries.map((e) {
              final i = e.key; final s = e.value;
              return [
                '${i+1}',
                s['staffName'] as String? ?? s['name'] as String? ?? '',
                s['staffPno']  as String? ?? s['pno']  as String? ?? '',
                s['staffRank'] as String? ?? s['rank'] as String? ?? '',
                s['centerName'] as String? ?? '',
                s['centerType'] as String? ?? '',
                s['staffThana'] as String? ?? '',
                (s['isArmed'] as bool? ?? false) ? 'हाँ' : 'नहीं',
                (s['attended'] as bool? ?? false) ? 'हाँ' : '-',
              ];
            }).toList(),
          ),
          if (staff.length < total) ...[
            const SizedBox(height: 10),
            Center(child: OutlinedButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more, size: 16),
              label: Text('और लोड करें (${total - staff.length} बाकी)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kGold,
                side: const BorderSide(color: _kGold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            )),
          ],
        ],
      )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED COMPONENTS
// ══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String    title;
  final IconData  icon;
  final Color     color;
  final VoidCallback? onPrint;
  const _SectionHeader({required this.title, required this.icon,
      required this.color, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    final r = rOf(context);
    return Container(
      color: color.withOpacity(0.07),
      padding: EdgeInsets.fromLTRB(r.s(10, 14), 10, r.s(10, 14), 10),
      child: Row(children: [
        Container(width: 32, height: 32,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.white, size: 16)),
        const SizedBox(width: 10),
        Expanded(child: Text(title,
            style: TextStyle(color: color, fontSize: r.s(12, 13.5),
                fontWeight: FontWeight.w800))),
        if (onPrint != null)
          GestureDetector(
            onTap: onPrint,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: r.s(9, 12), vertical: 7),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.print_outlined, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text('प्रिंट', style: TextStyle(color: Colors.white,
                    fontSize: r.s(10.5, 11.5), fontWeight: FontWeight.w700)),
              ]),
            ))
        else
          const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)),
      ]),
    );
  }
}

class _StatChipH extends StatelessWidget {
  final String value, label;
  final Color  color;
  const _StatChipH(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: color.withOpacity(0.09), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: color, fontSize: 14,
          fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(color: color.withOpacity(0.8),
          fontSize: 9.5, fontWeight: FontWeight.w600)),
    ]));
}

class _GroupLabel extends StatelessWidget {
  final String label;
  final Color  color;
  const _GroupLabel(this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 4, height: 16,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label, style: TextStyle(color: color, fontSize: 12,
        fontWeight: FontWeight.w800)),
  ]);
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String?  subtitle;
  const _EmptyState({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 56, color: _kSubtle.withOpacity(0.3)),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(color: _kSubtle, fontSize: 13,
          fontWeight: FontWeight.w600)),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(subtitle!, style: const TextStyle(color: _kSubtle, fontSize: 11)),
      ],
    ]),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
//  Universal Gov-style Table (with batch-group row support)
// ──────────────────────────────────────────────────────────────────────────────

class _GovRowH {
  final List<String> cells;
  final bool         isBatch;
  final String?      batchLabel;
  const _GovRowH.data(this.cells) : isBatch = false, batchLabel = null;
  const _GovRowH.batch(this.batchLabel) : isBatch = true, cells = const [];
}

class _GovHTable extends StatelessWidget {
  final List<String>       headers;
  final List<double?>      widths;       // null = flex
  final List<List<String>> rows;
  final List<_GovRowH>?    groupedRows;
  final List<String>?      footerRow;
  final int                nameColIdx;
  final Color              color;
  final int?               statusColIdx;

  const _GovHTable({
    required this.headers, required this.widths,
    required this.rows, this.groupedRows, this.footerRow,
    required this.nameColIdx, required this.color, this.statusColIdx,
  });

  @override
  Widget build(BuildContext context) {
    final eff = groupedRows ?? rows.map((r) => _GovRowH.data(r)).toList();
    if (eff.isEmpty && footerRow == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('कोई डेटा नहीं',
            style: TextStyle(color: _kSubtle, fontSize: 12))));
    }

    // compute flex width
    final flexIdx = widths.indexOf(null);
    double fixedSum = 0;
    for (final w in widths) if (w != null) fixedSum += w;

    // measure longest content in flex col
    double minFlex = 130;
    if (flexIdx >= 0) {
      int maxLen = headers[flexIdx].length;
      for (final r in eff) {
        if (!r.isBatch && flexIdx < r.cells.length) {
          final l = r.cells[flexIdx].length;
          if (l > maxLen) maxLen = l;
        }
      }
      minFlex = (maxLen * 7.0 + 24).clamp(110.0, 200.0);
    }

    return LayoutBuilder(builder: (ctx, cons) {
      final avail = cons.maxWidth.isFinite ? cons.maxWidth : MediaQuery.of(ctx).size.width;
      final flexW = (flexIdx >= 0 && avail > fixedSum + minFlex)
          ? (avail - fixedSum - 2) : minFlex;
      final tableW = fixedSum + (flexIdx >= 0 ? flexW : 0);

      final table = SizedBox(
        width: tableW,
        child: Table(
          border: TableBorder.all(color: _kBorder.withOpacity(0.3), width: 0.6),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            for (int i = 0; i < widths.length; i++)
              i: FixedColumnWidth(widths[i] ?? (i == flexIdx ? flexW : 100)),
          },
          children: [
            // header
            TableRow(
              decoration: BoxDecoration(color: color.withOpacity(0.85)),
              children: headers.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Text(e.value, style: const TextStyle(color: Colors.white,
                    fontSize: 10, fontWeight: FontWeight.w800),
                    textAlign: e.key == nameColIdx ? TextAlign.left : TextAlign.center),
              )).toList(),
            ),
            // data
            ...eff.asMap().entries.map((e) {
              final i = e.key; final row = e.value;
              if (row.isBatch) {
                return TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFEDE3F8)),
                  children: List.generate(headers.length, (ci) {
                    String t = ci == 0 ? 'B' : (ci == 1 ? row.batchLabel ?? '' : '');
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Text(t, style: const TextStyle(color: Color(0xFF4A2A6A),
                          fontSize: 11, fontWeight: FontWeight.w900),
                          textAlign: ci <= 1 ? TextAlign.left : TextAlign.center));
                  }),
                );
              }
              final bg = i.isEven ? Colors.white : const Color(0xFFF8F5FF);
              return TableRow(
                decoration: BoxDecoration(color: bg),
                children: row.cells.asMap().entries.map((ce) {
                  final ci = ce.key; final cell = ce.value;
                  Color? textC;
                  if (ci == statusColIdx) {
                    if (cell.contains('✓') || cell == 'पूर्ण') textC = _kSuccess;
                    else if (cell == 'खाली') textC = _kError;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(cell,
                        style: TextStyle(color: textC ?? _kDark, fontSize: 11,
                            fontWeight: (ci == 0 || ci == nameColIdx || textC != null)
                                ? FontWeight.w600 : FontWeight.normal),
                        textAlign: ci == nameColIdx ? TextAlign.left : TextAlign.center));
                }).toList(),
              );
            }),
            // footer
            if (footerRow != null)
              TableRow(
                decoration: BoxDecoration(color: color.withOpacity(0.1)),
                children: footerRow!.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text(e.value, style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w900, color: _kDark),
                      textAlign: e.key == nameColIdx ? TextAlign.left : TextAlign.center),
                )).toList(),
              ),
          ],
        ),
      );

      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05),
              blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: tableW <= avail ? table
              : SingleChildScrollView(scrollDirection: Axis.horizontal, child: table),
        ),
      );
    });
  }
}
