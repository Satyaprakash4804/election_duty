// election_history_page.dart
// ─────────────────────────────────────────────────────────────────────────────
// Election History — List + Detail with 7 report tabs mirroring live pages.
//
// Tabs (mirrors exact live page format + PDF):
//   1. पदानुक्रम       → hierarchy-full (mirrors hierarchy_report_page.dart)
//   2. बूथ मानक        → booth-manak + booth-center-counts (mirrors manak_booth_report_page.dart)
//   3. जनपदीय मानक    → district-rules-full (mirrors manak_district_page.dart Manak tab)
//   4. जनपदीय ड्यूटी  → district-duty-summary + batches (mirrors manak_district_page.dart Duty tab)
//   5. बूथ ड्यूटी      → booth-assignments (mirrors booth duty list)
//   6. गोसवारा          → goswara (mirrors goswara_page.dart)
//   7. सारांश           → booth-assignments-summary + hierarchy-overview
//
// API base: /admin/election/history/<id>/...
// Active election uses live endpoints directly.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ── Palette (unified) ─────────────────────────────────────────────────────────
const _kBg          = Color(0xFFFAFAFA);
const _kPrimary     = Color(0xFF0F2B5B);
const _kGreen       = Color(0xFF186A3B);
const _kPurple      = Color(0xFF6C3483);
const _kRed         = Color(0xFFC0392B);
const _kDark        = Color(0xFF1A2332);
const _kSubtle      = Color(0xFF6B7C93);
const _kBorder      = Color(0xFFDDE3EE);
const _kAccent      = Color(0xFFFBBF24);
const _kOrange      = Color(0xFFE67E22);
const _kTeal        = Color(0xFF117A65);
const _kAmber       = Color(0xFFFFF3CD);
const _kAmberDk     = Color(0xFF856404);

// Manak palette (matches manak_booth_report_page.dart)
const _kManakBg     = Color(0xFFFDF6E3);
const _kManakSurf   = Color(0xFFF5E6C8);
const _kManakPrim   = Color(0xFF8B6914);
const _kManakDark   = Color(0xFF4A3000);
const _kManakSubtle = Color(0xFFAA8844);
const _kManakBorder = Color(0xFFD4A843);

// District palette
const _kDistrictColor = Color(0xFF6C3483);

// Goswara palette (matches goswara_page.dart)
const _kGosPrimary  = Color(0xFF1A3A6B);
const _kGosAccent   = Color(0xFF2E7D32);
const _kGosGold     = Color(0xFFD4A017);
const _kGosHdrBg    = Color(0xFFE8EDF5);
const _kGosTotalBg  = Color(0xFFDDE8F5);

const int _kPageSize = 30;

const List<Map<String, dynamic>> _kSensList = [
  {'key': 'A++', 'hi': 'अति-अति संवेदनशील', 'color': Color(0xFF6C3483)},
  {'key': 'A',   'hi': 'अति संवेदनशील',     'color': Color(0xFFC0392B)},
  {'key': 'B',   'hi': 'संवेदनशील',          'color': Color(0xFFE67E22)},
  {'key': 'C',   'hi': 'सामान्य',           'color': Color(0xFF1A5276)},
];

const List<Map<String, dynamic>> _kBoothTiers = [
  {'count': 1,  'label': '1 बूथ'},
  {'count': 2,  'label': '2 बूथ'},
  {'count': 3,  'label': '3 बूथ'},
  {'count': 4,  'label': '4 बूथ'},
  {'count': 5,  'label': '5 बूथ'},
  {'count': 6,  'label': '6 बूथ'},
  {'count': 7,  'label': '7 बूथ'},
  {'count': 8,  'label': '8 बूथ'},
  {'count': 9,  'label': '9 बूथ'},
  {'count': 10, 'label': '10 बूथ'},
  {'count': 11, 'label': '11 बूथ'},
  {'count': 12, 'label': '12 बूथ'},
  {'count': 13, 'label': '13 बूथ'},
  {'count': 14, 'label': '14 बूथ'},
  {'count': 15, 'label': '15 और उससे अधिक बूथ'},
];

// ── Responsive helper ─────────────────────────────────────────────────────────
class _R {
  final double width;
  const _R(this.width);
  double get t {
    if (width <= 320) return 0.0;
    if (width >= 480) return 1.0;
    return (width - 320) / 160;
  }
  double s(double small, double large) => small + (large - small) * t;
  bool get isCompact => width < 360;
  bool get isWide    => width >= 600;
  EdgeInsets symPad(double h, double v) =>
      EdgeInsets.symmetric(horizontal: h, vertical: v);
}
_R _rOf(BuildContext c) => _R(MediaQuery.of(c).size.width);

// ── Utility ───────────────────────────────────────────────────────────────────
int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

void _snack(BuildContext ctx, String msg, {bool error = false}) {
  if (!ctx.mounted) return;
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? _kRed : _kGreen,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 3),
  ));
}

// ── PDF shared helpers ────────────────────────────────────────────────────────
pw.Widget _pdfDocHeader(pw.Font font, pw.Font bold,
    String title, String subtitle) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title,
          style: pw.TextStyle(font: bold, fontSize: 10,
              fontWeight: pw.FontWeight.bold)),
      pw.Text(subtitle,
          style: pw.TextStyle(font: font, fontSize: 8,
              color: PdfColors.grey700)),
      pw.SizedBox(height: 4),
      pw.Container(height: 1.5,
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700)),
      pw.SizedBox(height: 4),
    ],
  );
}

pw.Widget _pdfTh(String t, pw.Font bold) => pw.Container(
  padding: const pw.EdgeInsets.all(4),
  decoration: const pw.BoxDecoration(
      color: PdfColor.fromInt(0xFF1A2332)),
  child: pw.Text(t,
      style: pw.TextStyle(font: bold, fontSize: 7,
          color: PdfColors.white, fontWeight: pw.FontWeight.bold),
      textAlign: pw.TextAlign.center),
);

pw.Widget _pdfTd(String t, pw.Font font,
    {bool center = false, PdfColor? color}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(t,
          style: pw.TextStyle(font: font, fontSize: 7.5,
              color: color),
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left),
    );

// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION CONTEXT  (shared across all tabs)
// ══════════════════════════════════════════════════════════════════════════════
class _ElectionContext {
  final int    electionId;
  final String electionName, electionDate, phase, district, role;
  final bool   isActive;
  const _ElectionContext({
    required this.electionId,   required this.electionName,
    required this.electionDate, required this.phase,
    required this.district,     required this.role,
    required this.isActive,
  });

  /// Base path for all history endpoints
  String get base => '/admin/election/history/$electionId';

  /// Resolve an endpoint — live vs archived
  String ep(String histPath, String livePath) =>
      isActive ? livePath : '$base/$histPath';
}

// ══════════════════════════════════════════════════════════════════════════════
//  LIST PAGE
// ══════════════════════════════════════════════════════════════════════════════
class ElectionHistoryListPage extends StatefulWidget {
  final String  role;
  final String? district;
  const ElectionHistoryListPage({
    super.key, required this.role, this.district,
  });
  @override
  State<ElectionHistoryListPage> createState() =>
      _ElectionHistoryListPageState();
}

class _ElectionHistoryListPageState
    extends State<ElectionHistoryListPage> {
  bool get _isMaster => widget.role.toLowerCase() == 'master';

  List<String> _districts     = [];
  String?      _selectedDist;
  bool         _loadingDists  = false;

  List        _elections      = [];
  bool        _loadingElec    = false;
  String?     _elecError;
  Map?        _activeElection;

  @override
  void initState() {
    super.initState();
    if (_isMaster) {
      _loadDistricts();
    } else {
      _selectedDist = widget.district;
      _loadElections();
    }
  }

  Future<void> _loadDistricts() async {
    setState(() => _loadingDists = true);
    try {
      final token = await AuthService.getToken();
      List<String> list = [];
      try {
        final res = await ApiService.get(
            '/admin/election/history/districts-list', token: token);
        list = (res['data'] as List? ?? []).map((e) => '$e').toList();
      } catch (_) {}
      if (list.isEmpty) {
        try {
          final res = await ApiService.get(
              '/admin/hierarchy/districts', token: token);
          list = (res['data'] as List? ?? []).map((e) => '$e').toList();
        } catch (_) {}
      }
      setState(() { _districts = list; _loadingDists = false; });
    } catch (_) {
      setState(() => _loadingDists = false);
    }
  }

  Future<void> _loadElections() async {
    if (_selectedDist == null && _isMaster) return;
    setState(() { _loadingElec = true; _elecError = null; });
    try {
      final token    = await AuthService.getToken();
      final district = _selectedDist ?? widget.district ?? '';
      String ep      = '/admin/election/history/list?limit=200';
      if (_isMaster && district.isNotEmpty)
        ep += '&district=${Uri.encodeComponent(district)}';
      final res    = await ApiService.get(ep, token: token);
      List items   = [];
      final w      = res['data'];
      if (w is Map) {
        items = w['data'] as List? ?? w['items'] as List? ?? [];
      } else if (w is List) {
        items = w;
      }
      Map? activeCfg;
      try {
        final ar = await ApiService.get(
            '/admin/election-config/active', token: token);
        final ad = ar['data'];
        if (ad is Map && ad['hasActiveConfig'] == true) {
          activeCfg = ad['config'] is Map ? ad['config'] as Map : null;
        }
      } catch (_) {}
      setState(() {
        _elections     = items;
        _activeElection = activeCfg;
        _loadingElec   = false;
      });
    } catch (e) {
      setState(() { _elecError = e.toString(); _loadingElec = false; });
    }
  }

  void _openDetail(Map election, {bool active = false}) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ElectionHistoryDetailPage(
        election:  election,
        role:      widget.role,
        district:  _selectedDist ?? widget.district,
        isActive:  active,
      ),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = _rOf(context);
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('चुनाव इतिहास', style: TextStyle(
              color: Colors.white,
              fontSize: r.s(14, 16), fontWeight: FontWeight.w800)),
          const Text('Election History — All Reports',
              style: TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadElections,
          ),
        ],
      ),
      body: Column(children: [
        if (_isMaster) _buildDistrictPicker(),
        if (_activeElection != null) _buildActiveBanner(),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildDistrictPicker() => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    child: _loadingDists
        ? const LinearProgressIndicator(color: _kPrimary)
        : Row(children: [
            const Icon(Icons.location_city_outlined,
                color: _kPrimary, size: 18),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDist, isExpanded: true,
                hint: const Text('जनपद चुनें',
                    style: TextStyle(color: _kSubtle, fontSize: 13)),
                style: const TextStyle(
                    color: _kDark, fontSize: 13,
                    fontWeight: FontWeight.w600),
                items: _districts.map((d) => DropdownMenuItem(
                    value: d,
                    child: Text(d,
                        style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedDist = v;
                    _elections    = [];
                    _activeElection = null;
                  });
                  _loadElections();
                },
              ),
            )),
          ]),
  );

  Widget _buildActiveBanner() {
    final e = _activeElection!;
    return InkWell(
      onTap: () => _openDetail({
        'id':           e['id'],
        'electionName': e['electionName'] ?? e['election_name'] ?? '',
        'electionType': e['electionType'] ?? '',
        'electionDate': e['electionDate'] ?? '',
        'phase':        e['phase']        ?? '',
        'electionYear': e['electionYear'] ?? '',
        'district':     e['district']     ?? '',
        'isFinalized':  false,
        'isActive':     true,
      }, active: true),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF186A3B), Color(0xFF239B56)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(
              color: _kGreen.withOpacity(0.25),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          const Icon(Icons.how_to_vote_outlined,
              color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['electionName'] ?? e['election_name'] ?? 'वर्तमान चुनाव'}',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 13)),
            Text('वर्तमान चुनाव • ${e['electionType'] ?? ''} • ${e['phase'] ?? ''}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6)),
            child: const Text('देखें →', style: TextStyle(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  Widget _buildBody() {
    if (_isMaster && _selectedDist == null) {
      return const Center(child: _EmptyHint(
          icon: Icons.location_city_outlined,
          title: 'जनपद चुनें',
          subtitle: 'ऊपर से जनपद का चयन करें'));
    }
    if (_loadingElec) {
      return const Center(
          child: CircularProgressIndicator(color: _kPrimary));
    }
    if (_elecError != null) {
      return Center(child: _ErrorCard(
          error: _elecError!, onRetry: _loadElections));
    }
    if (_elections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 30),
        child: _EmptyHint(
            icon: Icons.history_toggle_off_outlined,
            title: 'कोई पूर्व चुनाव नहीं',
            subtitle: 'वर्तमान चुनाव के लिए ऊपर बैनर टैप करें'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      itemCount: _elections.length,
      itemBuilder: (_, i) => _ElectionCard(
          election: _elections[i],
          onTap: (e) => _openDetail(e)),
    );
  }
}

// ── Election card ─────────────────────────────────────────────────────────────
class _ElectionCard extends StatelessWidget {
  final Map election;
  final void Function(Map) onTap;
  const _ElectionCard({required this.election, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final e        = election;
    final name     = '${e['electionName'] ?? e['election_name'] ?? '—'}';
    final district = '${e['district'] ?? '—'}';
    final phase    = '${e['phase'] ?? ''}';
    final eType    = '${e['electionType'] ?? e['election_type'] ?? ''}';
    final date     = '${e['electionDate'] ?? e['election_date'] ?? ''}';
    final autoFin  = (e['autoFinalized'] == true) || (_toInt(e['auto_finalized']) == 1);
    final finalized = (e['isFinalized'] == true) || (_toInt(e['is_finalized']) == 1);
    final year     = '${e['electionYear'] ?? e['election_year'] ?? ''}';

    final hdrColor = autoFin ? _kOrange
        : (finalized ? _kPrimary : _kSubtle);

    return InkWell(
      onTap: () => onTap(e),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
          boxShadow: [BoxShadow(
              color: hdrColor.withOpacity(0.08),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: hdrColor,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12)),
            ),
            child: Row(children: [
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 13)),
                Text('$district | $eType | $phase | $year',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 10)),
              ])),
              if (autoFin)
                _Badge('ऑटो फाइनल', Colors.orange[100]!, _kOrange)
              else if (finalized)
                _Badge('फाइनल', Colors.blue[100]!, _kPrimary),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  color: Colors.white70, size: 20),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 13, color: _kSubtle),
              const SizedBox(width: 4),
              Text('चुनाव तिथि: $date',
                  style: const TextStyle(color: _kSubtle, fontSize: 11)),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, size: 12, color: _kSubtle),
              const SizedBox(width: 4),
              const Text('रिपोर्ट देखें', style: TextStyle(
                  color: _kPrimary, fontSize: 11,
                  fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Badge(this.label, this.bg, this.fg);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(5)),
    child: Text(label, style: TextStyle(
        color: fg, fontSize: 9, fontWeight: FontWeight.w800)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  DETAIL PAGE — 7 tabs
// ══════════════════════════════════════════════════════════════════════════════
class ElectionHistoryDetailPage extends StatefulWidget {
  final Map     election;
  final String  role;
  final String? district;
  final bool    isActive;
  const ElectionHistoryDetailPage({
    super.key, required this.election, required this.role,
    this.district, this.isActive = false,
  });
  @override
  State<ElectionHistoryDetailPage> createState() =>
      _ElectionHistoryDetailPageState();
}

class _ElectionHistoryDetailPageState
    extends State<ElectionHistoryDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Map    get _e            => widget.election;
  int    get _electionId   => _toInt(_e['id'] ?? _e['election_id']);
  String get _electionName =>
      '${_e['electionName'] ?? _e['election_name'] ?? 'चुनाव'}';
  String get _district     =>
      widget.district ?? '${_e['district'] ?? ''}';
  String get _electionDate =>
      '${_e['electionDate'] ?? _e['election_date'] ?? ''}';
  String get _phase        => '${_e['phase'] ?? ''}';

  @override
  Widget build(BuildContext context) {
    final r   = _rOf(context);
    final ctx = _ElectionContext(
      electionId:   _electionId,
      electionName: _electionName,
      electionDate: _electionDate,
      phase:        _phase,
      district:     _district,
      role:         widget.role,
      isActive:     widget.isActive,
    );

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(_electionName, style: TextStyle(
              color: Colors.white,
              fontSize: r.s(13, 14.5), fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis),
          Text(
            'जनपद: $_district'
            '${widget.isActive ? "  • वर्तमान" : "  • इतिहास"}'
            '${_phase.isNotEmpty ? "  • चरण: $_phase" : ""}',
            style: const TextStyle(
                color: Colors.white54, fontSize: 9),
            overflow: TextOverflow.ellipsis,
          ),
        ]),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(r.s(74, 80)),
          child: Container(
            color: _kPrimary,
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              indicatorColor: _kAccent,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: TextStyle(
                  fontSize: r.s(9.5, 10.5),
                  fontWeight: FontWeight.w800),
              tabs: const [
                Tab(text: 'पदानुक्रम',
                    icon: Icon(Icons.account_tree_outlined, size: 14)),
                Tab(text: 'बूथ मानक',
                    icon: Icon(Icons.shield_outlined,       size: 14)),
                Tab(text: 'जनपदीय मानक',
                    icon: Icon(Icons.rule_outlined,         size: 14)),
                Tab(text: 'जनपदीय ड्यूटी',
                    icon: Icon(Icons.people_outline,        size: 14)),
                Tab(text: 'बूथ ड्यूटी',
                    icon: Icon(Icons.how_to_vote_outlined,  size: 14)),
                Tab(text: 'गोसवारा',
                    icon: Icon(Icons.table_chart_outlined,  size: 14)),
                Tab(text: 'सारांश',
                    icon: Icon(Icons.summarize_outlined,    size: 14)),
              ],
            ),
          ),
        ),
      ),
      body: Column(children: [
        if (!widget.isActive) _HistoryBanner(name: _electionName),
        Expanded(child: TabBarView(controller: _tab, children: [
          _HierarchyReportTab(ctx: ctx),
          _BoothManakReportTab(ctx: ctx),
          _DistrictManakReportTab(ctx: ctx),
          _DistrictDutyReportTab(ctx: ctx),
          _BoothDutyReportTab(ctx: ctx),
          _GoswaraReportTab(ctx: ctx),
          _SummaryReportTab(ctx: ctx),
        ])),
      ]),
    );
  }
}

class _HistoryBanner extends StatelessWidget {
  final String name;
  const _HistoryBanner({required this.name});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, color: _kAmber,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Row(children: [
      const Icon(Icons.lock_outline, size: 14, color: _kAmberDk),
      const SizedBox(width: 8),
      Expanded(child: Text('इतिहास मोड • $name • केवल पठन',
          style: const TextStyle(color: _kAmberDk,
              fontSize: 11.5, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis)),
    ]),
  );
}

// ── Shared print toolbar ──────────────────────────────────────────────────────
class _PrintToolbar extends StatelessWidget {
  final String      title, subtitle;
  final Color       color;
  final VoidCallback onPrint;
  const _PrintToolbar({
    required this.title, required this.subtitle,
    required this.color, required this.onPrint,
  });
  @override
  Widget build(BuildContext context) {
    final r = _rOf(context);
    return Container(
      color: color.withOpacity(0.06),
      padding: EdgeInsets.fromLTRB(r.s(10, 14), 8, r.s(10, 12), 8),
      child: Row(children: [
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(
              color: color, fontSize: r.s(12, 13.5),
              fontWeight: FontWeight.w800)),
          Text(subtitle, style: const TextStyle(
              color: _kSubtle, fontSize: 10),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          onPressed: onPrint,
          icon: const Icon(Icons.print_outlined,
              color: Colors.white, size: 15),
          label: const Text('PDF', style: TextStyle(
              color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 1 — पदानुक्रम (mirrors hierarchy_report_page.dart exactly)
// ══════════════════════════════════════════════════════════════════════════════
class _HierarchyReportTab extends StatefulWidget {
  final _ElectionContext ctx;
  const _HierarchyReportTab({required this.ctx});
  @override
  State<_HierarchyReportTab> createState() => _HierarchyReportTabState();
}

class _HierarchyReportTabState extends State<_HierarchyReportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List   _data    = [];
  bool   _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final ep = widget.ctx.ep(
          'hierarchy-full',
          '/admin/hierarchy/full?district=${Uri.encodeComponent(widget.ctx.district)}',
      );
      final res = await ApiService.get(ep, token: token);
      final d   = res['data'];
      setState(() {
        _data = d is List ? d
            : (d is Map && d['data'] is List ? d['data'] as List : []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  String _officerStr(List officers) {
    if (officers.isEmpty) return '—';
    return officers.map((o) {
      final n = (o['name']      ?? '').toString().trim();
      final r = (o['user_rank'] ?? '').toString().trim();
      final m = (o['mobile']    ?? '').toString().trim();
      final p = (o['pno']       ?? '').toString().trim();
      return [n, r, if (p.isNotEmpty) 'PNO:$p',
              if (m.isNotEmpty) 'मो:$m']
          .where((x) => x.isNotEmpty).join(' ');
    }).join('\n');
  }

  Future<void> _print() async {
    if (_data.isEmpty) {
      _snack(context, 'कोई डेटा नहीं', error: true);
      return;
    }
    try {
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc  = pw.Document();
      final ctx  = widget.ctx;

      for (final sz in _data) {
        final szm   = sz as Map;
        final zones = szm['zones'] as List? ?? [];
        int gpTotal = 0;
        for (final z in zones)
          for (final s in (z['sectors'] as List? ?? []))
            gpTotal += ((s['panchayats'] as List?)?.length ?? 0);

        final rows = <List<String>>[];
        int gSec   = 0;
        for (int zi = 0; zi < zones.length; zi++) {
          final z    = zones[zi] as Map;
          final secs = z['sectors'] as List? ?? [];
          final zOff = _officerStr(z['officers'] as List? ?? []);
          final hq   = '${z['hq_address'] ?? '—'}';
          if (secs.isEmpty) {
            rows.add(['${zi + 1}', zOff, hq, '—', '—', '—', '—', '—']);
          } else {
            for (final s in secs) {
              gSec++;
              final gps   = s['panchayats'] as List? ?? [];
              final gpNm  = gps.map((g) => '${g['name']}').join(', ');
              final thanas = gps.map((g) => '${g['thana'] ?? ''}')
                  .where((t) => t.isNotEmpty).toSet().join(', ');
              rows.add([
                '${zi + 1}', zOff, hq, '$gSec',
                _officerStr(s['officers'] as List? ?? []),
                '${s['hq'] ?? '—'}',
                gpNm.isEmpty ? '—' : gpNm,
                thanas.isEmpty ? '—' : thanas,
              ]);
            }
          }
        }

        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(14),
          header: (_) => _pdfDocHeader(font, bold,
              '${ctx.electionName} — पदानुक्रम रिपोर्ट',
              'जनपद: ${ctx.district}  •  चरण: ${ctx.phase}'
              '  •  तिथि: ${ctx.electionDate}'),
          build: (_) => [
            pw.RichText(text: pw.TextSpan(children: [
              pw.TextSpan(
                  text: 'सुपर जोन–${szm['name'] ?? ''}  '
                        'ब्लाक ${szm['block'] ?? ''}  ',
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
                  _pdfTh('सुपर\nजोन',             bold),
                  _pdfTh('जोनल अधिकारी',           bold),
                  _pdfTh('मुख्यालय',               bold),
                  _pdfTh('सैक्टर',                  bold),
                  _pdfTh('सैक्टर पुलिस अधिकारी',   bold),
                  _pdfTh('मुख्यालय',               bold),
                  _pdfTh('ग्राम पंचायत',            bold),
                  _pdfTh('थाना',                    bold),
                ]),
                ...rows.map((rr) => pw.TableRow(children: [
                  _pdfTd(rr[0], font, center: true),
                  _pdfTd(rr[1], font),
                  _pdfTd(rr[2], font),
                  _pdfTd(rr[3], font, center: true),
                  _pdfTd(rr[4], font),
                  _pdfTd(rr[5], font),
                  _pdfTd(rr[6], font),
                  _pdfTd(rr[7], font),
                ])),
              ],
            ),
          ],
        ));
      }
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      _snack(context, 'PDF विफल: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: _kPrimary));
    if (_error != null)
      return _ErrorCard(error: _error!, onRetry: _load);
    if (_data.isEmpty)
      return const _EmptyHint(
          icon: Icons.account_tree_outlined,
          title: 'कोई पदानुक्रम डेटा नहीं',
          subtitle: 'इस चुनाव के लिए अधिकारी अभिलेख उपलब्ध नहीं हैं');

    return Column(children: [
      _PrintToolbar(title: 'पदानुक्रम रिपोर्ट',
          subtitle: '${_data.length} सुपर जोन',
          color: _kPrimary, onPrint: _print),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: _data.length,
        itemBuilder: (_, i) => _SuperZoneCard(sz: _data[i]),
      )),
    ]);
  }
}

// ── SuperZone card ────────────────────────────────────────────────────────────
class _SuperZoneCard extends StatelessWidget {
  final Map sz;
  const _SuperZoneCard({required this.sz});
  @override
  Widget build(BuildContext context) {
    final r      = _rOf(context);
    final zones  = sz['zones'] as List? ?? [];
    int gpTotal  = 0, sTotal = 0;
    for (final z in zones) {
      final secs = z['sectors'] as List? ?? [];
      sTotal += secs.length;
      for (final s in secs)
        gpTotal += ((s['panchayats'] as List?)?.length ?? 0);
    }
    final officers = sz['officers'] as List? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.06),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF0F2B5B), Color(0xFF1E3F80)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('सुपर जोन–${sz['name'] ?? ''}  '
                'ब्लाक ${sz['block'] ?? '—'}',
                style: TextStyle(color: Colors.white,
                    fontSize: r.s(13, 14), fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _MiniChip('${zones.length} जोन',  Colors.blue),
              _MiniChip('$sTotal सैक्टर',        Colors.green),
              _MiniChip('$gpTotal ग्राम पंचायत', Colors.orange),
            ]),
          ]),
        ),
        // Officers
        if (officers.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            color: const Color(0xFFFFF8E7),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('क्षेत्राधिकारी:', style: TextStyle(
                  color: _kSubtle, fontSize: 10,
                  fontWeight: FontWeight.w700)),
              ...officers.map((o) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '• ${o['name'] ?? ''}  ${o['user_rank'] ?? ''}'
                  '${(o['pno'] ?? '').toString().isNotEmpty ? '  PNO:${o['pno']}' : ''}'
                  '${(o['mobile'] ?? '').toString().isNotEmpty ? '  मो:${o['mobile']}' : ''}',
                  style: const TextStyle(color: _kDark, fontSize: 11)),
              )),
            ]),
          ),
        // Table
        Padding(
          padding: const EdgeInsets.all(8),
          child: _HierarchyTable(sz: sz),
        ),
      ]),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final MaterialColor color;
  const _MiniChip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(
        color: color.shade800, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}

class _HierarchyTable extends StatelessWidget {
  final Map sz;
  const _HierarchyTable({required this.sz});

  static const _ws = <double>[40, 150, 110, 44, 165, 115, 220, 90];
  static const _hs = [
    'जोन', 'जोनल अधिकारी', 'मुख्यालय',
    'सैक्टर', 'सैक्टर पुलिस अधिकारी', 'मुख्यालय',
    'ग्राम पंचायत', 'थाना',
  ];

  String _officerLines(List officers) {
    if (officers.isEmpty) return '—';
    return officers.map((o) {
      final n = (o['name']      ?? '').toString().trim();
      final r = (o['user_rank'] ?? '').toString().trim();
      final m = (o['mobile']    ?? '').toString().trim();
      return [n, if (r.isNotEmpty) r, if (m.isNotEmpty) 'मो:$m'].join('\n');
    }).join('\n---\n');
  }

  @override
  Widget build(BuildContext context) {
    final zones = sz['zones'] as List? ?? [];
    if (zones.isEmpty) return const _EmptyHint(
        icon: Icons.inbox_outlined, title: 'कोई जोन नहीं', subtitle: '');

    final total = _ws.fold<double>(0, (a, b) => a + b);
    final rows  = <_HRow>[];
    int gSec    = 0;
    for (int zi = 0; zi < zones.length; zi++) {
      final z    = zones[zi] as Map;
      final secs = z['sectors'] as List? ?? [];
      if (secs.isEmpty) {
        rows.add(_HRow(z: z, s: null, sNum: null, zi: zi));
      } else {
        for (final s in secs) {
          gSec++;
          rows.add(_HRow(z: z, s: s as Map, sNum: gSec, zi: zi));
        }
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: total),
        child: Column(children: [
          // Header
          Container(
            decoration: BoxDecoration(
                color: const Color(0xFFEDE7F6),
                border: Border.all(color: _kBorder, width: 0.7)),
            child: Row(children: List.generate(_hs.length, (i) =>
                Container(
                  width: _ws[i], padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(border: Border(
                      right: i < _hs.length - 1
                          ? const BorderSide(color: _kBorder)
                          : BorderSide.none)),
                  child: Text(_hs[i], style: const TextStyle(
                      color: _kDark, fontSize: 10,
                      fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center),
                ))),
          ),
          // Rows
          ...rows.asMap().entries.map((entry) {
            final i   = entry.key;
            final row = entry.value;
            final z   = row.z;
            final s   = row.s;
            final isFirstInZone = i == 0 || rows[i - 1].zi != row.zi;
            final bg  = row.zi.isOdd
                ? Colors.white : const Color(0xFFFDFAFF);
            final gps    = s != null ? (s['panchayats'] as List? ?? []) : [];
            final gpNames = gps.map((g) => '${g['name']}').join(', ');
            final thanas  = gps.map((g) => '${g['thana'] ?? ''}')
                .where((t) => t.isNotEmpty).toSet().join(', ');
            final sHq = s != null
                ? '${s['hq'] ?? s['hq_address'] ?? '—'}' : '—';
            return Container(
              decoration: BoxDecoration(
                color: bg,
                border: const Border(
                  left:   BorderSide(color: _kBorder, width: 0.7),
                  right:  BorderSide(color: _kBorder, width: 0.7),
                  bottom: BorderSide(color: _kBorder, width: 0.7),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _hCell(_ws[0], isFirstInZone ? '${row.zi + 1}' : '',
                      center: true, color: _kPrimary, bold: true),
                  _hCell(_ws[1], isFirstInZone
                      ? _officerLines(z['officers'] as List? ?? []) : ''),
                  _hCell(_ws[2], isFirstInZone
                      ? '${z['hq_address'] ?? '—'}' : ''),
                  _hCell(_ws[3],
                      row.sNum != null ? '${row.sNum}' : '',
                      center: true, color: _kGreen, bold: true),
                  _hCell(_ws[4], s != null
                      ? _officerLines(s['officers'] as List? ?? []) : '—'),
                  _hCell(_ws[5], sHq),
                  _hCell(_ws[6], gpNames.isEmpty ? '—' : gpNames),
                  _hCell(_ws[7], thanas.isEmpty ? '—' : thanas),
                ],
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _hCell(double w, String txt,
      {bool center = false, Color? color, bool bold = false}) =>
      Container(
        width: w, padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: _kBorder))),
        child: Text(txt, style: TextStyle(
            color: color ?? _kDark, fontSize: 11,
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal),
            textAlign: center ? TextAlign.center : TextAlign.left),
      );
}

class _HRow {
  final Map z;
  final Map? s;
  final int? sNum;
  final int zi;
  _HRow({required this.z, this.s, this.sNum, required this.zi});
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 2 — बूथ मानक (mirrors manak_booth_report_page.dart EXACTLY)
// ══════════════════════════════════════════════════════════════════════════════
class _BoothManakReportTab extends StatefulWidget {
  final _ElectionContext ctx;
  const _BoothManakReportTab({required this.ctx});
  @override
  State<_BoothManakReportTab> createState() => _BoothManakReportTabState();
}

class _BoothManakReportTabState extends State<_BoothManakReportTab>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  final Map<String, List<Map<String, dynamic>>> _rules = {
    'A++': [], 'A': [], 'B': [], 'C': [],
  };
  final Map<String, Map<int, int>> _centerCounts = {
    'A++': {}, 'A': {}, 'B': {}, 'C': {},
  };
  bool   _loading = true;
  String? _error;
  late TabController _innerTab;
  int _activeInner = 0;

  @override
  void initState() {
    super.initState();
    _innerTab = TabController(length: 5, vsync: this);
    _innerTab.addListener(() =>
        setState(() => _activeInner = _innerTab.index));
    _load();
  }

  @override
  void dispose() { _innerTab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final ctx   = widget.ctx;

      // Rules
      final rulesEp = ctx.ep('booth-manak', '/admin/booth-rules');
      final res     = await ApiService.get(rulesEp, token: token);
      final data    = res['data'] as Map<String, dynamic>? ?? {};
      for (final s in ['A++', 'A', 'B', 'C']) {
        _rules[s] = (data[s] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      // Center counts
      final ccEp = ctx.ep('booth-center-counts',
          '/admin/booth-rules/center-counts-by-type');
      try {
        final ccRes  = await ApiService.get(ccEp, token: token);
        final ccData = ccRes['data'] as Map<String, dynamic>? ?? {};
        for (final sens in ['A++', 'A', 'B', 'C']) {
          final sd     = ccData[sens] as Map<String, dynamic>? ?? {};
          final counts = <int, int>{};
          sd.forEach((k, v) {
            final bc = int.tryParse(k.toString()) ?? 0;
            if (bc >= 1 && bc <= 15) counts[bc] = (v as num).toInt();
          });
          _centerCounts[sens] = counts;
        }
      } catch (_) {}

      setState(() => _loading = false);
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Map<String, dynamic>? _ruleFor(String sens, int bc) {
    try {
      return _rules[sens]!.firstWhere(
          (r) => _toInt(r['boothCount'] ?? r['booth_count']) == bc);
    } catch (_) { return null; }
  }

  int _g(Map<String, dynamic>? r, String k, [String? alt]) {
    if (r == null) return 0;
    return _toInt(r[k] ?? (alt != null ? r[alt] : null));
  }

  double _pac(Map<String, dynamic>? r) {
    if (r == null) return 0;
    return ((r['pacCount'] ?? r['pac_count'] ?? 0) as num).toDouble();
  }

  bool _hasAny(Map<String, dynamic>? r) {
    if (r == null) return false;
    return _g(r,'siArmedCount','si_armed_count')       > 0 ||
        _g(r,'siUnarmedCount','si_unarmed_count')      > 0 ||
        _g(r,'hcArmedCount','hc_armed_count')          > 0 ||
        _g(r,'hcUnarmedCount','hc_unarmed_count')      > 0 ||
        _g(r,'constArmedCount','const_armed_count')    > 0 ||
        _g(r,'constUnarmedCount','const_unarmed_count')> 0 ||
        _g(r,'auxArmedCount','aux_armed_count')        > 0 ||
        _g(r,'auxUnarmedCount','aux_unarmed_count')    > 0 ||
        _pac(r) > 0;
  }

  int _filledCount(String sens) {
    int c = 0;
    for (int i = 1; i <= 15; i++)
      if (_hasAny(_ruleFor(sens, i))) c++;
    return c;
  }

  String _fmtPac(double v) =>
      v == 0 ? '0' : (v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1));

  Future<void> _print() async {
    try {
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc  = pw.Document();
      final ctx  = widget.ctx;

      for (final s in _kSensList) {
        final sens     = s['key'] as String;
        final color    = s['color'] as Color;
        final pdfColor = PdfColor.fromInt(color.value);

        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(14),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'त्रिस्तरीय पंचायत सामान्य निर्वाचन — बूथ एवं कानून व्यवस्था ड्यूटी हेतु पुलिस व्यवस्थापन का विवरण',
                style: pw.TextStyle(font: bold, fontSize: 8,
                    fontWeight: pw.FontWeight.bold)),
              pw.Text('${ctx.electionName}  •  जनपद: ${ctx.district}'
                  '  •  चरण: ${ctx.phase}  •  तिथि: ${ctx.electionDate}',
                  style: pw.TextStyle(font: font, fontSize: 8,
                      color: PdfColors.grey700)),
              pw.SizedBox(height: 3),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                    color: pdfColor,
                    borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Text('${s['key']} — ${s['hi']} श्रेणी',
                    style: pw.TextStyle(font: bold, fontSize: 8,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
            ],
          ),
          build: (_) => [_buildPdfTable(sens, font, bold)],
        ));
      }
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      _snack(context, 'PDF विफल: $e', error: true);
    }
  }

  pw.Widget _buildPdfTable(String sens, pw.Font font, pw.Font bold) {
    final tHdr = pw.TextStyle(font: bold, fontSize: 6,
        fontWeight: pw.FontWeight.bold);
    final tCel = pw.TextStyle(font: font, fontSize: 6.5);
    final tBld = pw.TextStyle(font: bold, fontSize: 6.5,
        fontWeight: pw.FontWeight.bold);
    final tZro = pw.TextStyle(font: font, fontSize: 6.5,
        color: PdfColors.grey500);

    pw.Widget ph(String t, pw.TextStyle st, {bool left = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2.5),
          child: pw.Text(t, style: st,
              textAlign: left ? pw.TextAlign.left : pw.TextAlign.center),
        );

    int tCnt=0, tSI_A=0, tHC_A=0, tHC_U=0,
        tC_A=0,  tC_U=0, tAx_A=0, tAx_U=0;
    double tPAC = 0;

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#EDE0C4')),
        children: [
          ph('क्र.स.', tHdr),
          ph('मतदान केन्द्र का प्रकार', tHdr, left: true),
          ph('पोलिंग\nसेन्टर\nसंख्या', tHdr),
          ph('SI', tHdr), ph('HC', tHdr),
          ph('Const.', tHdr), ph('Aux.\nForce', tHdr), ph('PAC\n(section)', tHdr),
          ph('SI\nसश°', tHdr), ph('HC', tHdr),
          ph('HC\nसश°', tHdr), ph('HC\nनिः°', tHdr),
          ph('Const.', tHdr), ph('Const.\nसश°', tHdr), ph('Const.\nनिः°', tHdr),
          ph('Aux.\nForce', tHdr), ph('PAC\n(section)', tHdr),
        ],
      ),
    ];

    for (int i = 1; i <= 15; i++) {
      final r       = _ruleFor(sens, i);
      final centers = _centerCounts[sens]?[i] ?? 0;
      final si_a = _g(r,'siArmedCount','si_armed_count');
      final si_u = _g(r,'siUnarmedCount','si_unarmed_count');
      final hc_a = _g(r,'hcArmedCount','hc_armed_count');
      final hc_u = _g(r,'hcUnarmedCount','hc_unarmed_count');
      final c_a  = _g(r,'constArmedCount','const_armed_count');
      final c_u  = _g(r,'constUnarmedCount','const_unarmed_count');
      final ax_a = _g(r,'auxArmedCount','aux_armed_count');
      final ax_u = _g(r,'auxUnarmedCount','aux_unarmed_count');
      final pac  = _pac(r);
      final M_si_a = centers * si_a;
      final M_hc_a = centers * hc_a; final M_hc_u = centers * hc_u;
      final M_c_a  = centers * c_a;  final M_c_u  = centers * c_u;
      final M_ax_a = centers * ax_a; final M_ax_u = centers * ax_u;
      final M_pac  = centers * pac;
      tCnt += centers; tSI_A += M_si_a;
      tHC_A += M_hc_a; tHC_U += M_hc_u;
      tC_A  += M_c_a;  tC_U  += M_c_u;
      tAx_A += M_ax_a; tAx_U += M_ax_u;
      tPAC  += M_pac;
      pw.TextStyle st(num v) => v > 0 ? tBld : tZro;
      rows.add(pw.TableRow(
        decoration: i % 2 == 0
            ? const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFAF5EB)) : null,
        children: [
          ph('$i', tCel),
          ph(_kBoothTiers[i - 1]['label'], tCel, left: true),
          ph(centers > 0 ? '$centers' : '—', st(centers)),
          ph('${si_a+si_u}', st(si_a+si_u)),
          ph('${hc_a+hc_u}', st(hc_a+hc_u)),
          ph('${c_a+c_u}',   st(c_a+c_u)),
          ph('${ax_a+ax_u}', st(ax_a+ax_u)),
          ph(_fmtPac(pac),   st((pac*10).toInt())),
          ph('$M_si_a',           st(M_si_a)),
          ph('${M_hc_a+M_hc_u}', st(M_hc_a+M_hc_u)),
          ph('$M_hc_a',           st(M_hc_a)),
          ph('$M_hc_u',           st(M_hc_u)),
          ph('${M_c_a+M_c_u}',   st(M_c_a+M_c_u)),
          ph('$M_c_a',            st(M_c_a)),
          ph('$M_c_u',            st(M_c_u)),
          ph('${M_ax_a+M_ax_u}', st(M_ax_a+M_ax_u)),
          ph(_fmtPac(M_pac), st((M_pac*10).toInt())),
        ],
      ));
    }
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#D5F5E3')),
      children: [
        ph('', tHdr), ph('योग', tHdr, left: true),
        ph('$tCnt', tHdr),
        ph('', tHdr), ph('', tHdr),
        ph('', tHdr), ph('', tHdr), ph('', tHdr),
        ph('$tSI_A',          tHdr),
        ph('${tHC_A+tHC_U}',  tHdr),
        ph('$tHC_A',           tHdr), ph('$tHC_U',           tHdr),
        ph('${tC_A+tC_U}',    tHdr),
        ph('$tC_A',            tHdr), ph('$tC_U',            tHdr),
        ph('${tAx_A+tAx_U}',  tHdr),
        ph(_fmtPac(tPAC),     tHdr),
      ],
    ));

    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(18),   1: pw.FixedColumnWidth(60),
        2: pw.FixedColumnWidth(26),
        3: pw.FixedColumnWidth(22),   4: pw.FixedColumnWidth(22),
        5: pw.FixedColumnWidth(24),   6: pw.FixedColumnWidth(26),
        7: pw.FixedColumnWidth(28),
        8:  pw.FixedColumnWidth(24),  9:  pw.FixedColumnWidth(24),
        10: pw.FixedColumnWidth(26),  11: pw.FixedColumnWidth(26),
        12: pw.FixedColumnWidth(26),  13: pw.FixedColumnWidth(28),
        14: pw.FixedColumnWidth(28),  15: pw.FixedColumnWidth(28),
        16: pw.FixedColumnWidth(28),
      },
      border: const pw.TableBorder(
        horizontalInside:
            pw.BorderSide(width: 0.3, color: PdfColors.grey400),
        verticalInside:
            pw.BorderSide(width: 0.3, color: PdfColors.grey400),
        left:   pw.BorderSide(width: 0.5, color: PdfColors.grey600),
        right:  pw.BorderSide(width: 0.5, color: PdfColors.grey600),
        top:    pw.BorderSide(width: 0.5, color: PdfColors.grey600),
        bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey600),
      ),
      children: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: _kManakPrim));
    if (_error != null)
      return _ErrorCard(error: _error!, onRetry: _load);

    return Container(
      color: _kManakBg,
      child: Column(children: [
        _PrintToolbar(title: 'बूथ मानक रिपोर्ट',
            subtitle: '4 श्रेणियाँ (A++ / A / B / C)',
            color: _kManakPrim, onPrint: _print),
        Material(
          color: _kManakPrim,
          child: TabBar(
            controller: _innerTab, isScrollable: true,
            indicatorColor: Colors.white, indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'सभी'),
              Tab(text: 'A++'),
              Tab(text: 'A'),
              Tab(text: 'B'),
              Tab(text: 'C'),
            ],
          ),
        ),
        Expanded(child: TabBarView(controller: _innerTab, children: [
          // All
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
            itemCount: _kSensList.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _sensBlock(_kSensList[i]),
            ),
          ),
          // Per-sensitivity
          ..._kSensList.map((s) => ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
            children: [_sensBlock(s)],
          )),
        ])),
      ]),
    );
  }

  Widget _sensBlock(Map<String, dynamic> s) {
    final sk    = s['key'] as String;
    final color = s['color'] as Color;
    final isSet = _filledCount(sk) > 0;

    int tCnt=0, tSI=0, tHC=0, tC=0, tAx=0;
    double tPAC = 0;
    for (int i = 1; i <= 15; i++) {
      final r = _ruleFor(sk, i);
      final c = _centerCounts[sk]?[i] ?? 0;
      tCnt += c;
      tSI += c * (_g(r,'siArmedCount','si_armed_count') +
          _g(r,'siUnarmedCount','si_unarmed_count'));
      tHC += c * (_g(r,'hcArmedCount','hc_armed_count') +
          _g(r,'hcUnarmedCount','hc_unarmed_count'));
      tC  += c * (_g(r,'constArmedCount','const_armed_count') +
          _g(r,'constUnarmedCount','const_unarmed_count'));
      tAx += c * (_g(r,'auxArmedCount','aux_armed_count') +
          _g(r,'auxUnarmedCount','aux_unarmed_count'));
      tPAC += c * _pac(r);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kManakBorder.withOpacity(0.35)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _kManakSurf.withOpacity(0.7),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14)),
            border: Border(bottom: BorderSide(
                color: _kManakBorder.withOpacity(0.3))),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(sk, style: const TextStyle(
                  color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['hi']} श्रेणी', style: const TextStyle(
                  color: _kManakDark, fontSize: 13,
                  fontWeight: FontWeight.w800)),
              Text('${_filledCount(sk)}/15 मानक • $tCnt केन्द्र',
                  style: TextStyle(color: color, fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ])),
            if (isSet)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('सेट', style: TextStyle(
                    color: _kGreen, fontSize: 10,
                    fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        // Summary chips
        if (isSet)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            color: color.withOpacity(0.04),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _sumChip('केन्द्र', '$tCnt',
                    const Color(0xFF555555)),
                _sumChip('SI', '$tSI', color),
                _sumChip('HC', '$tHC', color),
                _sumChip('Const.', '$tC', color),
                _sumChip('Aux.', '$tAx',
                    const Color(0xFFE65100)),
                if (tPAC > 0)
                  _sumChip('PAC', _fmtPac(tPAC),
                      const Color(0xFF00695C)),
                _sumChip('कुल बल', '${tSI+tHC+tC+tAx}', _kGreen),
              ]),
            ),
          ),
        // Empty state
        if (!isSet)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Column(
                mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.table_chart_outlined, size: 36,
                  color: color.withOpacity(0.3)),
              const SizedBox(height: 10),
              Text('${s['hi']} ($sk) के लिए कोई मानक सेट नहीं है',
                  style: const TextStyle(color: _kManakSubtle,
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ])),
          )
        else
          _BoothManakTable(
            sensKey: sk,
            color: color,
            centerCounts: _centerCounts[sk] ?? {},
            ruleFor: (bc) => _ruleFor(sk, bc),
            g: _g,
            pac: _pac,
            fmtPac: _fmtPac,
          ),
      ]),
    );
  }

  Widget _sumChip(String label, String value, Color color) =>
      Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ', style: TextStyle(
              color: color.withOpacity(0.8), fontSize: 10,
              fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w900)),
        ]),
      );
}

// ── Booth manak table (same format as manak_booth_report_page.dart _ReportTable) ──
class _BoothManakTable extends StatelessWidget {
  final String sensKey;
  final Color  color;
  final Map<int, int> centerCounts;
  final Map<String, dynamic>? Function(int) ruleFor;
  final int Function(Map<String, dynamic>?, String, [String?]) g;
  final double Function(Map<String, dynamic>?) pac;
  final String Function(double) fmtPac;

  const _BoothManakTable({
    required this.sensKey, required this.color,
    required this.centerCounts, required this.ruleFor,
    required this.g, required this.pac, required this.fmtPac,
  });

  @override
  Widget build(BuildContext context) {
    int tCenters=0;
    int mSI_A=0,mSI_U=0,mHC_A=0,mHC_U=0,mC_A=0,mC_U=0,mAx_A=0,mAx_U=0;
    double mPAC=0;
    int tSI_A=0,tHC_A=0,tHC_U=0,tC_A=0,tC_U=0,tAx_A=0,tAx_U=0;
    double tPAC=0;

    final dataRows = <_BRow>[];
    for (int i = 1; i <= 15; i++) {
      final r  = ruleFor(i);
      final c  = centerCounts[i] ?? 0;
      final si_a = g(r,'siArmedCount','si_armed_count');
      final si_u = g(r,'siUnarmedCount','si_unarmed_count');
      final hc_a = g(r,'hcArmedCount','hc_armed_count');
      final hc_u = g(r,'hcUnarmedCount','hc_unarmed_count');
      final c_a  = g(r,'constArmedCount','const_armed_count');
      final c_u  = g(r,'constUnarmedCount','const_unarmed_count');
      final ax_a = g(r,'auxArmedCount','aux_armed_count');
      final ax_u = g(r,'auxUnarmedCount','aux_unarmed_count');
      final p    = pac(r);
      tCenters += c;
      mSI_A += si_a; mSI_U += si_u;
      mHC_A += hc_a; mHC_U += hc_u;
      mC_A  += c_a;  mC_U  += c_u;
      mAx_A += ax_a; mAx_U += ax_u;
      mPAC  += p;
      tSI_A += c*si_a;
      tHC_A += c*hc_a; tHC_U += c*hc_u;
      tC_A  += c*c_a;  tC_U  += c*c_u;
      tAx_A += c*ax_a; tAx_U += c*ax_u;
      tPAC  += c*p;
      dataRows.add(_BRow(
        boothNo: i, label: _kBoothTiers[i-1]['label'],
        centers: c, si_a: si_a, si_u: si_u,
        hc_a: hc_a, hc_u: hc_u,
        c_a: c_a,   c_u: c_u,
        ax_a: ax_a, ax_u: ax_u, p: p,
      ));
    }

    const colWidths = <int, TableColumnWidth>{
      0: FixedColumnWidth(28),   1: FixedColumnWidth(90),
      2: FixedColumnWidth(42),
      3: FixedColumnWidth(30),   4: FixedColumnWidth(30),
      5: FixedColumnWidth(34),   6: FixedColumnWidth(36),
      7: FixedColumnWidth(34),
      8:  FixedColumnWidth(32),  9:  FixedColumnWidth(34),
      10: FixedColumnWidth(34),  11: FixedColumnWidth(34),
      12: FixedColumnWidth(34),  13: FixedColumnWidth(36),
      14: FixedColumnWidth(36),  15: FixedColumnWidth(38),
      16: FixedColumnWidth(34),
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 780),
        child: Table(
          columnWidths: colWidths,
          border: TableBorder.all(
              color: _kManakBorder.withOpacity(0.25), width: 0.5),
          children: [
            // Group header
            TableRow(
              decoration:
                  BoxDecoration(color: color.withOpacity(0.10)),
              children: [
                _th2(''), _th2('', left: true), _th2(''),
                _th2('Scale', color: color, bold: true),
                _th2(''), _th2(''), _th2(''), _th2(''),
                _th2('मानक के अनुसार व्यवस्थापित पुलिस बल (कुल)',
                    color: color, bold: true),
                _th2(''), _th2(''), _th2(''),
                _th2(''), _th2(''), _th2(''), _th2(''), _th2(''),
              ],
            ),
            // Column headers
            TableRow(
              decoration: BoxDecoration(
                  color: _kManakSurf),
              children: [
                _th('क्र.\nस.'),
                _th('मतदान\nकेन्द्र का प्रकार', left: true),
                _th('पोलिंग\nसेन्टर\nसंख्या'),
                _th('SI'), _th('HC'),
                _th('Const.'), _th('Aux.\nForce'),
                _th('PAC\n(sec.)'),
                _th('SI\nसश°'), _th('HC'),
                _th('HC\nसश°'), _th('HC\nनिः°'),
                _th('Const.'), _th('Const.\nसश°'), _th('Const.\nनिः°'),
                _th('Aux.\nForce'), _th('PAC\n(sec.)'),
              ],
            ),
            // Data rows
            ...dataRows.asMap().entries.map((e) {
              final row    = e.value;
              final isEven = e.key % 2 == 1;
              final bg     = isEven
                  ? _kManakBg.withOpacity(0.4) : Colors.white;
              final hC     = row.centers > 0;
              return TableRow(
                decoration: BoxDecoration(color: bg),
                children: [
                  _td('${row.boothNo < 15 ? row.boothNo : "15+"}',
                      center: true),
                  _td(row.label, left: true),
                  _tdc(row.centers > 0 ? '${row.centers}' : '—',
                      center: true,
                      color: hC ? color : _kSubtle.withOpacity(0.4),
                      bold: hC),
                  // Scale
                  _td('${row.si_a+row.si_u}', center: true),
                  _td('${row.hc_a+row.hc_u}', center: true),
                  _td('${row.c_a+row.c_u}',   center: true),
                  _td('${row.ax_a+row.ax_u}',  center: true),
                  _td(fmtPac(row.p),            center: true),
                  // Deployed
                  _tdn(row.centers * row.si_a),
                  _tdn(row.centers * (row.hc_a+row.hc_u)),
                  _tdn(row.centers * row.hc_a),
                  _tdn(row.centers * row.hc_u),
                  _tdn(row.centers * (row.c_a+row.c_u)),
                  _tdn(row.centers * row.c_a),
                  _tdn(row.centers * row.c_u),
                  _tdn(row.centers * (row.ax_a+row.ax_u)),
                  _td(fmtPac(row.centers * row.p), center: true,
                      bold: row.centers * row.p > 0),
                ],
              );
            }),
            // Total row
            TableRow(
              decoration:
                  BoxDecoration(color: color.withOpacity(0.09)),
              children: [
                _td('', center: true),
                _td('योग', left: true, bold: true),
                _tdc('$tCenters', center: true, color: color, bold: true),
                _td('${mSI_A+mSI_U}', center: true, bold: true),
                _td('${mHC_A+mHC_U}', center: true, bold: true),
                _td('${mC_A+mC_U}',   center: true, bold: true),
                _td('${mAx_A+mAx_U}', center: true, bold: true),
                _td(fmtPac(mPAC),      center: true, bold: true),
                _td('$tSI_A',          center: true, bold: true),
                _td('${tHC_A+tHC_U}', center: true, bold: true),
                _td('$tHC_A',          center: true, bold: true),
                _td('$tHC_U',          center: true, bold: true),
                _td('${tC_A+tC_U}',   center: true, bold: true),
                _td('$tC_A',           center: true, bold: true),
                _td('$tC_U',           center: true, bold: true),
                _td('${tAx_A+tAx_U}', center: true, bold: true),
                _td(fmtPac(tPAC),      center: true, bold: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _th(String t, {bool left = false}) => TableCell(
    verticalAlignment: TableCellVerticalAlignment.middle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: Text(t, textAlign: left ? TextAlign.left : TextAlign.center,
          style: const TextStyle(fontSize: 9.5,
              fontWeight: FontWeight.w700, color: _kManakDark, height: 1.2)),
    ),
  );

  Widget _th2(String t,
      {Color? color, bool bold = false, bool left = false}) =>
      TableCell(
        verticalAlignment: TableCellVerticalAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: Text(t,
              textAlign: left ? TextAlign.left : TextAlign.center,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 8,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color ?? _kManakDark, height: 1.2)),
        ),
      );

  Widget _td(String t,
      {bool center = false, bool bold = false, bool left = false}) =>
      TableCell(
        verticalAlignment: TableCellVerticalAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Text(t,
              textAlign: center ? TextAlign.center
                  : (left ? TextAlign.left : TextAlign.center),
              style: TextStyle(fontSize: 11, height: 1.2,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  color: _kManakDark)),
        ),
      );

  Widget _tdc(String t,
      {bool center = false, Color? color, bool bold = false}) =>
      TableCell(
        verticalAlignment: TableCellVerticalAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Text(t,
              textAlign: center ? TextAlign.center : TextAlign.left,
              style: TextStyle(fontSize: 11, height: 1.2,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                  color: color ?? _kManakDark)),
        ),
      );

  Widget _tdn(int v) => TableCell(
    verticalAlignment: TableCellVerticalAlignment.middle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: Text('$v', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, height: 1.2,
              fontWeight: v > 0 ? FontWeight.w700 : FontWeight.w400,
              color: v > 0 ? _kManakDark : _kManakSubtle.withOpacity(0.4))),
    ),
  );
}

class _BRow {
  final int boothNo, centers, si_a, si_u, hc_a, hc_u, c_a, c_u, ax_a, ax_u;
  final double p;
  final String label;
  const _BRow({
    required this.boothNo, required this.label, required this.centers,
    required this.si_a, required this.si_u,
    required this.hc_a, required this.hc_u,
    required this.c_a,  required this.c_u,
    required this.ax_a, required this.ax_u,
    required this.p,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 3 — जनपदीय मानक (mirrors manak_district_page.dart Manak tab)
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictManakReportTab extends StatefulWidget {
  final _ElectionContext ctx;
  const _DistrictManakReportTab({required this.ctx});
  @override
  State<_DistrictManakReportTab> createState() =>
      _DistrictManakReportTabState();
}

class _DistrictManakReportTabState extends State<_DistrictManakReportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _rules   = [];
  bool   _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final ep    = widget.ctx.ep(
          'district-rules-full', '/admin/district-rules');
      final res   = await ApiService.get(ep, token: token);
      final d     = res['data'];
      setState(() {
        _rules = (d is List ? d : [])
            .map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  int    _n(Map<String, dynamic> r, String k) => _toInt(r[k]);
  double _p(Map<String, dynamic> r)           =>
      ((r['pacCount'] ?? r['pac_count'] ?? 0) as num).toDouble();

  int _total(Map<String, dynamic> r) {
    int t = 0;
    for (final k in ['siArmedCount','siUnarmedCount','hcArmedCount',
        'hcUnarmedCount','constArmedCount','constUnarmedCount',
        'auxArmedCount','auxUnarmedCount'])
      t += _toInt(r[k]);
    return t;
  }

  Future<void> _print() async {
    if (_rules.isEmpty) {
      _snack(context, 'कोई डेटा नहीं', error: true);
      return;
    }
    try {
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc  = pw.Document();
      final ctx  = widget.ctx;

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(14),
        header: (_) => _pdfDocHeader(font, bold,
            '${ctx.electionName} — जनपदीय मानक रिपोर्ट',
            'जनपद: ${ctx.district}  •  चरण: ${ctx.phase}'
            '  •  तिथि: ${ctx.electionDate}'),
        build: (_) {
          final colW = const <int, pw.FlexColumnWidth>{
            0: pw.FlexColumnWidth(0.4),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FlexColumnWidth(0.5),
            4: pw.FlexColumnWidth(0.5), 5: pw.FlexColumnWidth(0.5),
            6: pw.FlexColumnWidth(0.5), 7: pw.FlexColumnWidth(0.5),
            8: pw.FlexColumnWidth(0.5), 9: pw.FlexColumnWidth(0.5),
            10: pw.FlexColumnWidth(0.5), 11: pw.FlexColumnWidth(0.4),
            12: pw.FlexColumnWidth(0.5),
          };
          final rows = <pw.TableRow>[
            pw.TableRow(children: [
              _pdfTh('क्र.',            bold), _pdfTh('ड्यूटी प्रकार', bold),
              _pdfTh('लेबल', bold),           _pdfTh('संख्या', bold),
              _pdfTh('SI\nस.',         bold), _pdfTh('SI\nनि.',  bold),
              _pdfTh('HC\nस.',         bold), _pdfTh('HC\nनि.',  bold),
              _pdfTh('Con\nस.',        bold), _pdfTh('Con\nनि.', bold),
              _pdfTh('Aux\nस.',        bold), _pdfTh('Aux\nनि.', bold),
              _pdfTh('कुल', bold),
            ]),
          ];
          int srl = 0;
          for (final r in _rules) {
            srl++;
            rows.add(pw.TableRow(
              decoration: srl % 2 == 0 ? const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFAF5EB)) : null,
              children: [
                _pdfTd('$srl',                       font, center: true),
                _pdfTd('${r['dutyType'] ?? ''}',     font),
                _pdfTd('${r['dutyLabelHi'] ?? ''}',  font),
                _pdfTd('${r['sankhya'] ?? 0}',        font, center: true),
                _pdfTd('${_n(r,'siArmedCount')}',    font, center: true),
                _pdfTd('${_n(r,'siUnarmedCount')}',  font, center: true),
                _pdfTd('${_n(r,'hcArmedCount')}',    font, center: true),
                _pdfTd('${_n(r,'hcUnarmedCount')}',  font, center: true),
                _pdfTd('${_n(r,'constArmedCount')}', font, center: true),
                _pdfTd('${_n(r,'constUnarmedCount')}',font,center:true),
                _pdfTd('${_n(r,'auxArmedCount')}',   font, center: true),
                _pdfTd('${_n(r,'auxUnarmedCount')}', font, center: true),
                _pdfTd('${_total(r)}',               font, center: true),
              ],
            ));
          }
          return [
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: colW,
              children: rows,
            )
          ];
        },
      ));
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      _snack(context, 'PDF विफल: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: _kDistrictColor));
    if (_error != null)
      return _ErrorCard(error: _error!, onRetry: _load);
    if (_rules.isEmpty)
      return const _EmptyHint(
          icon: Icons.rule_outlined,
          title: 'कोई जनपदीय मानक नहीं',
          subtitle: 'इस चुनाव के लिए मानक उपलब्ध नहीं');

    return Column(children: [
      _PrintToolbar(title: 'जनपदीय मानक रिपोर्ट',
          subtitle: '${_rules.length} ड्यूटी प्रकार',
          color: _kDistrictColor, onPrint: _print),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: _DistrictManakTable(rules: _rules),
      )),
    ]);
  }
}

// ── District Manak Table ──────────────────────────────────────────────────────
class _DistrictManakTable extends StatelessWidget {
  final List<Map<String, dynamic>> rules;
  const _DistrictManakTable({required this.rules});

  static const _ws = <double>[
    36, 110, 140, 55, 50, 50, 50, 50, 55, 55, 50, 50, 52
  ];
  static const _hs = [
    '#', 'ड्यूटी', 'लेबल', 'संख्या',
    'SI स.', 'SI नि.', 'HC स.', 'HC नि.',
    'Con स.', 'Con नि.', 'Aux स.', 'Aux नि.', 'कुल'
  ];

  int _n(Map<String, dynamic> r, String k) => _toInt(r[k]);
  int _total(Map<String, dynamic> r) {
    int t = 0;
    for (final k in ['siArmedCount','siUnarmedCount','hcArmedCount',
        'hcUnarmedCount','constArmedCount','constUnarmedCount',
        'auxArmedCount','auxUnarmedCount'])
      t += _toInt(r[k]);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final total = _ws.fold(0.0, (a, b) => a + b);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: total),
        child: Column(children: [
          Container(
            decoration: BoxDecoration(
                color: const Color(0xFFEDE3F8),
                border: Border.all(color: _kBorder, width: 0.7)),
            child: Row(children: List.generate(_hs.length, (i) =>
                Container(
                  width: _ws[i],
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(border: Border(
                      right: i < _hs.length - 1
                          ? const BorderSide(color: _kBorder)
                          : BorderSide.none)),
                  child: Text(_hs[i], style: const TextStyle(
                      color: _kDistrictColor, fontSize: 9.5,
                      fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center),
                ))),
          ),
          ...rules.asMap().entries.map((e) {
            final i   = e.key;
            final r   = e.value;
            final bg  = i.isEven ? Colors.white
                : const Color(0xFFFAF8F0);
            final tot = _total(r);
            return Container(
              decoration: BoxDecoration(
                  color: bg,
                  border: const Border(
                    left:   BorderSide(color: _kBorder, width: 0.7),
                    right:  BorderSide(color: _kBorder, width: 0.7),
                    bottom: BorderSide(color: _kBorder, width: 0.7),
                  )),
              child: Row(children: [
                _dc(_ws[0],  '${i+1}', center: true),
                _dc(_ws[1],  '${r['dutyType'] ?? ''}'),
                _dc(_ws[2],  '${r['dutyLabelHi'] ?? ''}'),
                _dc(_ws[3],  '${r['sankhya'] ?? 0}', center: true,
                    bold: true, color: _kDistrictColor),
                _dc(_ws[4],  '${_n(r,'siArmedCount')}', center: true),
                _dc(_ws[5],  '${_n(r,'siUnarmedCount')}', center: true),
                _dc(_ws[6],  '${_n(r,'hcArmedCount')}', center: true),
                _dc(_ws[7],  '${_n(r,'hcUnarmedCount')}', center: true),
                _dc(_ws[8],  '${_n(r,'constArmedCount')}', center: true),
                _dc(_ws[9],  '${_n(r,'constUnarmedCount')}', center: true),
                _dc(_ws[10], '${_n(r,'auxArmedCount')}', center: true),
                _dc(_ws[11], '${_n(r,'auxUnarmedCount')}', center: true),
                _dc(_ws[12], '$tot', center: true, bold: true,
                    color: tot > 0 ? _kGreen : _kSubtle),
              ]),
            );
          }),
        ]),
      ),
    );
  }

  Widget _dc(double w, String t,
      {bool center = false, bool bold = false, Color? color}) =>
      Container(
        width: w, padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: _kBorder))),
        child: Text(t, style: TextStyle(
            fontSize: 11, color: color ?? _kDark,
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal),
            textAlign: center ? TextAlign.center : TextAlign.left),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 4 — जनपदीय ड्यूटी (mirrors manak_district_page.dart Duty tab)
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictDutyReportTab extends StatefulWidget {
  final _ElectionContext ctx;
  const _DistrictDutyReportTab({required this.ctx});
  @override
  State<_DistrictDutyReportTab> createState() =>
      _DistrictDutyReportTabState();
}

class _DistrictDutyReportTabState extends State<_DistrictDutyReportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _summary = [];
  final Map<String, List<Map<String, dynamic>>> _batchCache = {};
  bool   _loading   = true;
  String? _error;
  String? _expandedType;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final ctx   = widget.ctx;
      final ep    = ctx.ep('district-duty-summary',
          '/admin/district-duty/summary');
      final res   = await ApiService.get(ep, token: token);
      final d     = res['data'];
      List<Map<String, dynamic>> items = [];
      if (d is Map) {
        d.forEach((k, v) {
          if (v is Map) {
            items.add(Map<String, dynamic>.from(v)..['dutyType'] = k);
          }
        });
      } else if (d is List) {
        items = d.map((e) =>
            Map<String, dynamic>.from(e as Map)).toList();
      }
      setState(() { _summary = items; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _loadBatches(String dutyType) async {
    if (_batchCache.containsKey(dutyType)) return;
    try {
      final token = await AuthService.getToken();
      final ctx   = widget.ctx;
      final ep    = ctx.ep(
          'district-duty/$dutyType/batches',
          '/admin/district-duty/$dutyType/batches',
      );
      final res   = await ApiService.get(ep, token: token);
      final d     = res['data'];
      final batches = (d is List ? d : [])
          .map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() => _batchCache[dutyType] = batches);
    } catch (_) {
      setState(() => _batchCache[dutyType] = []);
    }
  }

  Future<void> _print() async {
    if (_summary.isEmpty) {
      _snack(context, 'कोई डेटा नहीं', error: true);
      return;
    }
    try {
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc  = pw.Document();
      final ctx  = widget.ctx;

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(14),
        header: (_) => _pdfDocHeader(font, bold,
            '${ctx.electionName} — जनपदीय ड्यूटी सारांश',
            'जनपद: ${ctx.district}  •  चरण: ${ctx.phase}'
            '  •  तिथि: ${ctx.electionDate}'),
        build: (_) {
          final rows = <pw.TableRow>[
            pw.TableRow(children: [
              _pdfTh('क्र.',           bold), _pdfTh('ड्यूटी प्रकार', bold),
              _pdfTh('लेबल',           bold), _pdfTh('आवश्यक',  bold),
              _pdfTh('Assigned', bold), _pdfTh('Batches', bold),
              _pdfTh('Armed',    bold), _pdfTh('Unarmed', bold),
              _pdfTh('स्थिति',   bold),
            ]),
          ];
          int srl = 0;
          for (final s in _summary) {
            srl++;
            final asgn  = _toInt(s['totalAssigned']);
            final req   = _toInt(s['sankhya']);
            final batch = _toInt(s['batchCount']);
            String status;
            if (req == 0)        status = 'मानक नहीं';
            else if (asgn >= req) status = 'पूर्ण';
            else if (asgn == 0)  status = 'खाली';
            else                 status = 'आंशिक';
            rows.add(pw.TableRow(
              decoration: srl % 2 == 0 ? const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFAF5EB)) : null,
              children: [
                _pdfTd('$srl',                         font, center: true),
                _pdfTd('${s['dutyType'] ?? ''}',       font),
                _pdfTd('${s['dutyLabelHi'] ?? ''}',    font),
                _pdfTd('${req > 0 ? req : '-'}',        font, center: true),
                _pdfTd('$asgn',                        font, center: true),
                _pdfTd('$batch',                       font, center: true),
                _pdfTd('${_toInt(s['armedCount'])}',   font, center: true),
                _pdfTd('${_toInt(s['unarmedCount'])}', font, center: true),
                _pdfTd(status,                         font, center: true),
              ],
            ));
          }
          return [
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.4),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(0.6),
                4: pw.FlexColumnWidth(0.7),
                5: pw.FlexColumnWidth(0.6),
                6: pw.FlexColumnWidth(0.6),
                7: pw.FlexColumnWidth(0.6),
                8: pw.FlexColumnWidth(0.7),
              },
              children: rows,
            )
          ];
        },
      ));
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      _snack(context, 'PDF विफल: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: _kDistrictColor));
    if (_error != null)
      return _ErrorCard(error: _error!, onRetry: _load);
    if (_summary.isEmpty)
      return const _EmptyHint(
          icon: Icons.people_outline,
          title: 'कोई जनपदीय ड्यूटी नहीं',
          subtitle: 'इस चुनाव के लिए ड्यूटी उपलब्ध नहीं');

    return Column(children: [
      _PrintToolbar(title: 'जनपदीय ड्यूटी रिपोर्ट',
          subtitle: '${_summary.length} ड्यूटी प्रकार',
          color: _kDistrictColor, onPrint: _print),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
        itemCount: _summary.length,
        itemBuilder: (_, i) {
          final s          = _summary[i];
          final dutyType   = '${s['dutyType'] ?? ''}';
          final label      = '${s['dutyLabelHi'] ?? s['label'] ?? dutyType}';
          final asgn       = _toInt(s['totalAssigned']);
          final req        = _toInt(s['sankhya']);
          final batch      = _toInt(s['batchCount']);
          final isExpanded = _expandedType == dutyType;
          final isDone     = req > 0 && asgn >= req;
          final pct        = req > 0
              ? (asgn / req).clamp(0.0, 1.0) : 0.0;
          final barColor   = isDone ? _kGreen
              : (pct > 0.5 ? _kOrange : _kDistrictColor);
          final batches    = _batchCache[dutyType];

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder.withOpacity(0.5)),
              boxShadow: [BoxShadow(
                  color: _kDistrictColor.withOpacity(0.05),
                  blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedType =
                        isExpanded ? null : dutyType;
                  });
                  if (!isExpanded) _loadBatches(dutyType);
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                            color: _kDistrictColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(9)),
                        child: Icon(Icons.assignment_outlined,
                            color: _kDistrictColor, size: 18)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(label, style: const TextStyle(
                            color: _kDark, fontSize: 13,
                            fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Wrap(spacing: 8, runSpacing: 2, children: [
                          if (req > 0)
                            Text('$asgn/$req',
                                style: TextStyle(
                                    color: barColor, fontSize: 11,
                                    fontWeight: FontWeight.w800)),
                          if (batch > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                  color: _kDistrictColor
                                      .withOpacity(0.1),
                                  borderRadius:
                                      BorderRadius.circular(5)),
                              child: Text('$batch batches',
                                  style: const TextStyle(
                                      color: _kDistrictColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700))),
                        ]),
                      ])),
                      if (isDone)
                        const Icon(Icons.check_circle_rounded,
                            color: _kGreen, size: 18),
                      const SizedBox(width: 4),
                      Icon(isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                          color: _kDistrictColor, size: 20),
                    ]),
                    if (req > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor:
                                barColor.withOpacity(0.12),
                            valueColor: AlwaysStoppedAnimation(barColor),
                            minHeight: 5)),
                    ],
                  ]),
                ),
              ),
              // Expanded batches
              if (isExpanded) ...[
                const Divider(height: 1, color: _kBorder),
                if (batches == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(
                        color: _kDistrictColor, strokeWidth: 2)),
                  )
                else if (batches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('कोई batch नहीं',
                        style: TextStyle(color: _kSubtle, fontSize: 12)),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    itemCount: batches.length,
                    itemBuilder: (_, bi) {
                      final b     = batches[bi];
                      final bNo   = _toInt(b['batchNo']);
                      final sc    = _toInt(b['staffCount']);
                      final bus   = '${b['busNo'] ?? ''}';
                      final staff = (b['staff'] as List? ?? [])
                          .cast<Map<String, dynamic>>();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF8F4FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _kDistrictColor
                                    .withOpacity(0.2))),
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                  color: _kDistrictColor,
                                  shape: BoxShape.circle),
                              child: Center(
                                child: Text('$bNo',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('Batch $bNo  •  $sc staff',
                                style: const TextStyle(
                                    color: _kDistrictColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                            if (bus.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text('Bus: $bus',
                                  style: const TextStyle(
                                      color: _kSubtle, fontSize: 10)),
                            ],
                          ]),
                          if (staff.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 4,
                              children: staff.take(6).map<Widget>((m) {
                                final rank = '${m['rank'] ?? ''}';
                                final rc   = _rankColor(rank);
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: rc.withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      border: Border.all(
                                          color: rc.withOpacity(0.3))),
                                  child: Text(
                                      '${m['name'] ?? ''}'
                                      ' (${m['rank'] ?? ''})',
                                      style: TextStyle(
                                          color: rc, fontSize: 10,
                                          fontWeight:
                                              FontWeight.w600)),
                                );
                              }).followedBy(staff.length > 6
                                  ? [Text('+${staff.length-6} और',
                                      style: const TextStyle(
                                          color: _kSubtle, fontSize: 10))]
                                  : []).toList(),
                            ),
                          ],
                        ]),
                      );
                    },
                  ),
              ],
            ]),
          );
        },
      )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 5 — बूथ ड्यूटी (paginated list with search)
// ══════════════════════════════════════════════════════════════════════════════
class _BoothDutyReportTab extends StatefulWidget {
  final _ElectionContext ctx;
  const _BoothDutyReportTab({required this.ctx});
  @override
  State<_BoothDutyReportTab> createState() =>
      _BoothDutyReportTabState();
}

class _BoothDutyReportTabState extends State<_BoothDutyReportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List   _rows      = [];
  bool   _loading   = false;
  String? _error;
  int    _page       = 1;
  int    _total      = 0;
  int    _totalPages = 1;
  String _q          = '';
  String _typeFilter = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = _searchCtrl.text.trim();
      if (q != _q) {
        setState(() { _q = q; _page = 1; });
        _load();
      }
    });
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final ctx   = widget.ctx;
      var ep      = ctx.ep(
          'booth-assignments',
          '/admin/duties/list',
      );
      ep += ep.contains('?') ? '&' : '?';
      ep += 'page=$_page&limit=$_kPageSize';
      if (ctx.district.isNotEmpty)
        ep += '&district=${Uri.encodeComponent(ctx.district)}';
      if (!ctx.isActive)
        ep += '&election_id=${ctx.electionId}';
      if (_q.isNotEmpty)
        ep += '&q=${Uri.encodeComponent(_q)}';
      if (_typeFilter.isNotEmpty)
        ep += '&centerType=${Uri.encodeComponent(_typeFilter)}';

      final res     = await ApiService.get(ep, token: token);
      final wrapper = res['data'];
      List items;
      int total = 0, totalPages = 1;
      if (wrapper is Map) {
        items      = wrapper['data'] as List? ??
                     wrapper['items'] as List? ?? [];
        total      = _toInt(wrapper['total']);
        totalPages = _toInt(wrapper['totalPages']);
        if (totalPages == 0) totalPages = 1;
      } else if (wrapper is List) {
        items = wrapper; total = items.length;
      } else {
        items = [];
      }
      setState(() {
        _rows       = items;
        _total      = total;
        _totalPages = totalPages;
        _loading    = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _print() async {
    if (_rows.isEmpty) {
      _snack(context, 'कोई डेटा नहीं', error: true);
      return;
    }
    try {
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc  = pw.Document();
      final ctx  = widget.ctx;

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(14),
        header: (_) => _pdfDocHeader(font, bold,
            '${ctx.electionName} — बूथ ड्यूटी रिपोर्ट',
            'जनपद: ${ctx.district}  •  चरण: ${ctx.phase}'
            '  •  कुल: $_total  •  पृष्ठ: $_page'),
        build: (_) {
          final rows = <pw.TableRow>[
            pw.TableRow(children: [
              _pdfTh('क्र.',          bold),
              _pdfTh('नाम',           bold),
              _pdfTh('PNO',           bold),
              _pdfTh('पद',            bold),
              _pdfTh('थाना',          bold),
              _pdfTh('जिला',          bold),
              _pdfTh('मतदेय स्थल',    bold),
              _pdfTh('केंद्र प्रकार', bold),
              _pdfTh('बस नं.',         bold),
              _pdfTh('तिथि',          bold),
            ]),
          ];
          int srl = 0;
          for (final r in _rows) {
            srl++;
            rows.add(pw.TableRow(
              decoration: srl % 2 == 0 ? const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFDF4FF)) : null,
              children: [
                _pdfTd('$srl',                                   font, center: true),
                _pdfTd('${r['staffName'] ?? r['staff_name'] ?? ''}', font),
                _pdfTd('${r['staffPno']  ?? r['staff_pno']  ?? ''}', font),
                _pdfTd('${r['staffRank'] ?? r['staff_rank'] ?? ''}', font),
                _pdfTd('${r['staffThana'] ?? r['staff_thana'] ?? ''}', font),
                _pdfTd('${r['staffDistrict'] ?? r['staff_district'] ?? ''}', font),
                _pdfTd('${r['centerName'] ?? r['center_name'] ?? ''}', font),
                _pdfTd('${r['centerType'] ?? r['center_type'] ?? ''}', font, center: true),
                _pdfTd('${r['busNo'] ?? r['bus_no'] ?? ''}',     font, center: true),
                _pdfTd('${r['electionDate'] ?? r['election_date'] ?? ''}', font),
              ],
            ));
          }
          return [pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(22),
              1: pw.FlexColumnWidth(1.8),
              2: pw.FixedColumnWidth(56),
              3: pw.FlexColumnWidth(0.9),
              4: pw.FlexColumnWidth(1.0),
              5: pw.FlexColumnWidth(0.9),
              6: pw.FlexColumnWidth(2.0),
              7: pw.FixedColumnWidth(52),
              8: pw.FixedColumnWidth(44),
              9: pw.FixedColumnWidth(64),
            },
            children: rows,
          )];
        },
      ));
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      _snack(context, 'PDF विफल: $e', error: true);
    }
  }

  void _changePage(int p) {
    final c = p.clamp(1, _totalPages < 1 ? 1 : _totalPages);
    if (c == _page) return;
    setState(() => _page = c);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _rOf(context);
    return Column(children: [
      // Toolbar
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          Expanded(child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'नाम, PNO, केंद्र...',
              hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 16, color: _kSubtle),
              isDense: true, fillColor: _kBg, filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              suffixIcon: _q.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          size: 15, color: _kSubtle),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() { _q = ''; _page = 1; });
                        _load();
                      })
                  : null,
            ),
          )),
          const SizedBox(width: 6),
          // Type filter
          DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                  border: Border.all(color: _kBorder),
                  borderRadius: BorderRadius.circular(8)),
              child: DropdownButton<String>(
                value: _typeFilter.isEmpty ? null : _typeFilter,
                hint: const Text('सभी', style: TextStyle(
                    color: _kSubtle, fontSize: 11)),
                style: const TextStyle(
                    color: _kDark, fontSize: 11),
                items: ['A++','A','B','C']
                    .map((t) => DropdownMenuItem(value: t,
                        child: Text(t))).toList(),
                onChanged: (v) {
                  setState(() {
                    _typeFilter = v ?? '';
                    _page = 1;
                  });
                  _load();
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0),
            onPressed: _print,
            icon: const Icon(Icons.print_outlined,
                color: Colors.white, size: 15),
            label: const Text('PDF', style: TextStyle(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
      if (_loading)
        const LinearProgressIndicator(
            color: _kPurple, minHeight: 2),
      // Pagination top
      _PagBar(page: _page, total: _total, totalPages: _totalPages,
          color: _kPurple, onPage: _changePage, top: true),
      Expanded(child: _buildList()),
      _PagBar(page: _page, total: _total, totalPages: _totalPages,
          color: _kPurple, onPage: _changePage, top: false),
    ]);
  }

  Widget _buildList() {
    if (_loading && _rows.isEmpty)
      return const Center(
          child: CircularProgressIndicator(color: _kPurple));
    if (_error != null)
      return _ErrorCard(error: _error!, onRetry: _load);
    if (_rows.isEmpty)
      return _EmptyHint(
          icon: Icons.how_to_vote_outlined,
          title: 'कोई बूथ ड्यूटी नहीं',
          subtitle: _q.isNotEmpty
              ? '"$_q" के लिए कोई परिणाम नहीं'
              : 'इस चुनाव में बूथ ड्यूटी उपलब्ध नहीं');

    final total = _ws.fold(0.0, (a, b) => a + b);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: total),
          child: Column(children: [
            // Header
            Container(
              decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  border: Border.all(color: _kBorder, width: 0.7)),
              child: Row(children: List.generate(_hs.length, (i) =>
                  Container(
                    width: _ws[i],
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(border: Border(
                        right: i < _hs.length - 1
                            ? const BorderSide(color: _kBorder)
                            : BorderSide.none)),
                    child: Text(_hs[i], style: const TextStyle(
                        color: _kPurple, fontSize: 9.5,
                        fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center),
                  ))),
            ),
            // Rows
            ..._rows.asMap().entries.map((e) {
              final i = e.key;
              final r = e.value as Map;
              final bg = i.isEven
                  ? Colors.white : const Color(0xFFFDF4FF);
              return Container(
                decoration: BoxDecoration(
                    color: bg,
                    border: const Border(
                      left:   BorderSide(color: _kBorder, width: 0.7),
                      right:  BorderSide(color: _kBorder, width: 0.7),
                      bottom: BorderSide(color: _kBorder, width: 0.7),
                    )),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dc(_ws[0], '${(_page-1)*_kPageSize+i+1}',
                        center: true),
                    _dc(_ws[1], '${r['staffName'] ?? r['staff_name'] ?? ''}'),
                    _dc(_ws[2], '${r['staffPno']  ?? r['staff_pno']  ?? ''}'),
                    _dc(_ws[3], '${r['staffRank'] ?? r['staff_rank'] ?? ''}'),
                    _dc(_ws[4], '${r['staffThana'] ?? r['staff_thana'] ?? ''}'),
                    _dc(_ws[5], '${r['staffDistrict'] ?? r['staff_district'] ?? ''}'),
                    _dc(_ws[6], '${r['centerName'] ?? r['center_name'] ?? ''}'),
                    _dc(_ws[7], '${r['centerType'] ?? r['center_type'] ?? ''}',
                        center: true),
                    _dc(_ws[8], '${r['busNo'] ?? r['bus_no'] ?? ''}',
                        center: true),
                    _dc(_ws[9], '${r['electionDate'] ?? r['election_date'] ?? ''}',
                        last: true),
                  ],
                ),
              );
            }),
          ]),
        ),
      ),
    );
  }

  static const List<double> _ws = [
    36, 130, 80, 90, 90, 90, 150, 70, 60, 80
  ];
  static const List<String> _hs = [
    '#', 'नाम', 'PNO', 'पद', 'थाना', 'जिला',
    'मतदेय स्थल', 'केंद्र प्रकार', 'बस नं.', 'तिथि'
  ];

  Widget _dc(double w, String t,
      {bool center = false, bool last = false}) =>
      Container(
        width: w, padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(border: Border(
            right: last ? BorderSide.none
                : const BorderSide(color: _kBorder))),
        child: Text(t, style: const TextStyle(
            fontSize: 11, color: _kDark),
            textAlign: center ? TextAlign.center : TextAlign.left,
            maxLines: 2, overflow: TextOverflow.ellipsis),
      );
}

// ── Pagination bar ─────────────────────────────────────────────────────────
class _PagBar extends StatelessWidget {
  final int page, total, totalPages;
  final Color color;
  final void Function(int) onPage;
  final bool top;
  const _PagBar({required this.page, required this.total,
      required this.totalPages, required this.color,
      required this.onPage, required this.top});

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1 && total == 0) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
          horizontal: 12, vertical: top ? 6 : 4),
      child: Row(children: [
        Expanded(child: Text('कुल: $total  |  पृष्ठ: $page / $totalPages',
            style: const TextStyle(fontSize: 11, color: _kSubtle))),
        _navBtn(Icons.first_page, page > 1, () => onPage(1)),
        _navBtn(Icons.chevron_left, page > 1, () => onPage(page - 1)),
        ..._pageNums(),
        _navBtn(Icons.chevron_right, page < totalPages,
            () => onPage(page + 1)),
        _navBtn(Icons.last_page, page < totalPages,
            () => onPage(totalPages)),
      ]),
    );
  }

  List<Widget> _pageNums() {
    final pages = <int>[];
    if (totalPages <= 6) {
      for (int i = 1; i <= totalPages; i++) pages.add(i);
    } else {
      pages.add(1);
      for (int i = (page-1).clamp(2, totalPages-1);
           i <= (page+1).clamp(2, totalPages-1); i++) pages.add(i);
      if (pages.last < totalPages) pages.add(totalPages);
    }
    return pages.map((p) {
      final active = p == page;
      return GestureDetector(
        onTap: () => onPage(p),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 28, height: 28,
          decoration: BoxDecoration(
              color: active ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color: active ? color : _kBorder)),
          child: Center(child: Text('$p', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: active ? Colors.white : _kDark))),
        ),
      );
    }).toList();
  }

  Widget _navBtn(IconData icon, bool enabled, VoidCallback onTap) =>
      InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 17,
              color: enabled ? color : _kBorder),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 6 — गोसवारा (mirrors goswara_page.dart EXACTLY)
// ══════════════════════════════════════════════════════════════════════════════
class _GoswaraReportTab extends StatefulWidget {
  final _ElectionContext ctx;
  const _GoswaraReportTab({required this.ctx});
  @override
  State<_GoswaraReportTab> createState() => _GoswaraReportTabState();
}

class _GoswaraReportTabState extends State<_GoswaraReportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _data = [];
  String _electionDate = '';
  String _phase        = '';
  bool   _loading      = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final ctx   = widget.ctx;
      final ep    = ctx.ep('goswara', '/admin/goswara');
      final res   = await ApiService.get(ep, token: token);
      final rawData = res['data'] ?? res;
      final rows    = rawData is Map
          ? (rawData['data'] as List? ?? [])
          : (rawData is List ? rawData : []);
      final parsed = (rows as List).map<Map<String, dynamic>>((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return {
          'block_name':           '${m['block_name'] ?? ''}',
          'zonal_count':          _toInt(m['zonal_count']),
          'sector_count':         _toInt(m['sector_count']),
          'nyay_panchayat_count': _toInt(m['nyay_panchayat_count']),
          'gram_panchayat_count': _toInt(m['gram_panchayat_count']),
        };
      }).toList();
      setState(() {
        _data         = parsed;
        _electionDate = '${(rawData is Map ? rawData['electionDate'] : null) ?? ctx.electionDate}';
        _phase        = '${(rawData is Map ? rawData['phase'] : null) ?? ctx.phase}';
        _loading      = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  int _sum(String key) =>
      _data.fold(0, (s, r) => s + _toInt(r[key]));

  Future<void> _print() async {
    if (_data.isEmpty) {
      _snack(context, 'कोई डेटा नहीं', error: true);
      return;
    }
    try {
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final ctx  = widget.ctx;
      final doc  = pw.Document();

      final base    = pw.TextStyle(font: font, fontSize: 9);
      final bld     = pw.TextStyle(font: bold,  fontSize: 9,
          fontWeight: pw.FontWeight.bold);
      const headerBg = PdfColor(0.910, 0.929, 0.961);
      const totalBg  = PdfColor(0.867, 0.902, 0.961);

      pw.Widget cell(String text,
          {bool isBold = false, PdfColor? bg, PdfColor? textColor,
           bool center = true}) =>
          pw.Container(
            color: bg,
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 5, vertical: 5),
            child: pw.Text(text,
                textAlign: center
                    ? pw.TextAlign.center : pw.TextAlign.left,
                style: (isBold ? bld : base).copyWith(
                    color: textColor)),
          );

      final nyayTotal = _data.fold<int>(
          0, (s, r) => s + _toInt(r['nyay_panchayat_count']));

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(22, 22, 22, 22),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text('गोसवारा',
                    style: pw.TextStyle(font: bold, fontSize: 16,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Text(
                  'विकास खण्डवार जोनल एवं सेक्टर, न्याय पंचायत'
                  ' एवं ग्राम पंचायतों का विवरण',
                  style: pw.TextStyle(font: font, fontSize: 8.5)),
                pw.Text('${ctx.electionName}  •  जनपद: ${ctx.district}',
                    style: bld),
              ]),
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                if (_phase.isNotEmpty)
                  pw.Text('चरण: $_phase', style: bld),
                if (_electionDate.isNotEmpty)
                  pw.Text(_electionDate,
                      style: pw.TextStyle(font: font, fontSize: 8.5)),
              ]),
            ]),
            pw.SizedBox(height: 3),
            pw.Divider(color: const PdfColor(0.7, 0.7, 0.8),
                thickness: 0.8),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(width: 0.6,
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
                ..._data.asMap().entries.map((e) {
                  final i = e.key;
                  final r = e.value;
                  final bg = i.isEven ? PdfColors.white
                      : const PdfColor(0.972, 0.976, 0.996);
                  return pw.TableRow(children: [
                    cell('${i+1}', bg: bg),
                    cell('${r['block_name']}', bg: bg, center: false),
                    cell(i == 0 ? _phase : '', bg: bg),
                    cell(i == 0 ? _electionDate : '', bg: bg),
                    cell('${_toInt(r['zonal_count'])}', bg: bg,
                        textColor: const PdfColor(0.086, 0.337, 0.690)),
                    cell('${_toInt(r['sector_count'])}', bg: bg,
                        textColor: const PdfColor(0.094, 0.416, 0.231)),
                    cell('${_toInt(r['nyay_panchayat_count'])}', bg: bg,
                        textColor: const PdfColor(0.416, 0.106, 0.604)),
                    cell('${_toInt(r['gram_panchayat_count'])}', bg: bg,
                        textColor: const PdfColor(0.545, 0.412, 0.078)),
                  ]);
                }),
                pw.TableRow(children: [
                  cell('',                              bg: totalBg),
                  cell('योग', isBold: true,             bg: totalBg, center: false),
                  cell('',                              bg: totalBg),
                  cell('',                              bg: totalBg),
                  cell('${_sum("zonal_count")}',        bg: totalBg, isBold: true),
                  cell('${_sum("sector_count")}',       bg: totalBg, isBold: true),
                  cell('$nyayTotal',                    bg: totalBg, isBold: true),
                  cell('${_sum("gram_panchayat_count")}',bg: totalBg, isBold: true),
                ]),
              ],
            ),
            pw.Spacer(),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
              pw.Text('गोसवारा — जनपदीय चुनाव विवरण',
                  style: pw.TextStyle(font: font, fontSize: 7,
                      color: PdfColors.grey600)),
              pw.Text(
                'मुद्रण तिथि: ${DateTime.now().day.toString().padLeft(2,'0')}/'
                '${DateTime.now().month.toString().padLeft(2,'0')}/'
                '${DateTime.now().year}',
                style: pw.TextStyle(font: font, fontSize: 7,
                    color: PdfColors.grey600)),
            ]),
          ],
        ),
      ));
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      _snack(context, 'PDF विफल: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: _kGosPrimary));
    if (_error != null)
      return _ErrorCard(error: _error!, onRetry: _load);

    final nyayTotal = _data.fold<int>(
        0, (s, r) => s + _toInt(r['nyay_panchayat_count']));

    return Column(children: [
      _PrintToolbar(title: 'गोसवारा रिपोर्ट',
          subtitle: '${_data.length} विकास खण्ड'
              '${_phase.isNotEmpty ? "  •  चरण: $_phase" : ""}',
          color: _kGosPrimary, onPrint: _print),
      Expanded(child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        child: Column(children: [
          // Stats row
          if (_data.isNotEmpty)
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8, mainAxisSpacing: 8,
              childAspectRatio: 1.15,
              children: [
                (_sum('zonal_count'),          'जोनल',       Icons.account_tree_outlined, const Color(0xFF1565C0)),
                (_sum('sector_count'),         'सेक्टर',     Icons.grid_view_outlined,     _kGosAccent),
                (nyayTotal,                    'न्याय पं.',  Icons.balance_outlined,        const Color(0xFF6A1B9A)),
                (_sum('gram_panchayat_count'), 'ग्राम पं.',  Icons.villa_outlined,          _kGosGold),
              ].map((item) {
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
                          color: color.withOpacity(0.1),
                          shape: BoxShape.circle),
                      child: Icon(icon, size: 16, color: color)),
                    const SizedBox(height: 6),
                    Text('$val', style: TextStyle(
                        color: color, fontWeight: FontWeight.w900,
                        fontSize: 20)),
                    const SizedBox(height: 2),
                    Text(label, style: const TextStyle(
                        color: _kSubtle, fontSize: 9),
                        textAlign: TextAlign.center,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                );
              }).toList(),
            ),
          const SizedBox(height: 14),
          // Table
          if (_data.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder)),
              child: const _EmptyHint(
                  icon: Icons.table_chart_outlined,
                  title: 'कोई डेटा उपलब्ध नहीं',
                  subtitle: ''),
            )
          else
            Container(
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                  boxShadow: [BoxShadow(
                      color: _kGosPrimary.withOpacity(0.06),
                      blurRadius: 10, offset: const Offset(0, 4))]),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                      color: _kGosPrimary.withOpacity(0.04),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12)),
                      border: Border(bottom: BorderSide(
                          color: _kBorder))),
                  child: Row(children: [
                    const Icon(Icons.table_chart_outlined,
                        size: 16, color: _kGosPrimary),
                    const SizedBox(width: 8),
                    const Text('विस्तृत विवरण',
                        style: TextStyle(color: _kGosPrimary,
                            fontWeight: FontWeight.w800, fontSize: 13)),
                    const Spacer(),
                    Text('${_data.length} विकास खण्ड',
                        style: const TextStyle(
                            color: _kSubtle, fontSize: 11)),
                  ]),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: Table(
                    border: TableBorder.all(
                        color: _kBorder, width: 0.7),
                    defaultVerticalAlignment:
                        TableCellVerticalAlignment.middle,
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
                      TableRow(
                        decoration: const BoxDecoration(
                            color: _kGosHdrBg),
                        children: [
                          _gh('क्र०सं०'), _gh('विकास खण्ड'),
                          _gh('चरण'), _gh('मतदान तिथि'),
                          _gh('जोनल मजिस्ट्रेट /\nपुलिस अधिकारी'),
                          _gh('सेक्टर\nमजिस्ट्रेट'),
                          _gh('न्याय\nपंचायत'),
                          _gh('ग्राम\nपंचायत'),
                        ],
                      ),
                      ..._data.asMap().entries.map((e) {
                        final i = e.key;
                        final r = e.value;
                        return TableRow(
                          decoration: BoxDecoration(
                              color: i.isEven
                                  ? Colors.white
                                  : const Color(0xFFF8FAFF)),
                          children: [
                            _gd('${i+1}', center: true),
                            _gd('${r['block_name']}', bold: true),
                            _gd(i == 0 ? _phase : '', center: true),
                            _gd(i == 0 ? _electionDate : '',
                                center: true, color: _kGosGold),
                            _gd('${_toInt(r['zonal_count'])}',
                                center: true,
                                color: const Color(0xFF1565C0)),
                            _gd('${_toInt(r['sector_count'])}',
                                center: true, color: _kGosAccent),
                            _gd('${_toInt(r['nyay_panchayat_count'])}',
                                center: true,
                                color: const Color(0xFF6A1B9A)),
                            _gd('${_toInt(r['gram_panchayat_count'])}',
                                center: true,
                                color: const Color(0xFF8B6914)),
                          ],
                        );
                      }),
                      TableRow(
                        decoration: const BoxDecoration(
                            color: _kGosTotalBg),
                        children: [
                          _gd('', center: true),
                          _gd('योग', bold: true,
                              color: _kGosPrimary),
                          _gd('', center: true),
                          _gd('', center: true),
                          _gd('${_sum("zonal_count")}',
                              center: true, bold: true,
                              color: _kGosPrimary),
                          _gd('${_sum("sector_count")}',
                              center: true, bold: true,
                              color: _kGosPrimary),
                          _gd('$nyayTotal',
                              center: true, bold: true,
                              color: _kGosPrimary),
                          _gd('${_sum("gram_panchayat_count")}',
                              center: true, bold: true,
                              color: _kGosPrimary),
                        ],
                      ),
                    ],
                  ),
                ),
              ]),
            ),
        ]),
      )),
    ]);
  }

  Widget _gh(String t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Text(t, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
            color: _kGosPrimary)),
  );
  Widget _gd(String t, {bool center = false, bool bold = false,
      Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Text(t,
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: TextStyle(fontSize: 12,
            fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
            color: color ?? _kDark)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  TAB 7 — सारांश (overall stats for this election)
// ══════════════════════════════════════════════════════════════════════════════
class _SummaryReportTab extends StatefulWidget {
  final _ElectionContext ctx;
  const _SummaryReportTab({required this.ctx});
  @override
  State<_SummaryReportTab> createState() => _SummaryReportTabState();
}

class _SummaryReportTabState extends State<_SummaryReportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Map<String, dynamic>?  _booths;
  Map<String, dynamic>?  _officers;
  bool   _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final ctx   = widget.ctx;
      final futures = await Future.wait([
        ApiService.get(ctx.ep(
            'booth-assignments-summary',
            '/admin/duties/summary'), token: token).catchError((_) => <String, dynamic>{}),
        ApiService.get(ctx.ep(
            'hierarchy-overview',
            '/admin/hierarchy/overview'), token: token).catchError((_) => <String, dynamic>{}),
      ]);
      setState(() {
        _booths   = futures[0]['data'] is Map
            ? Map<String, dynamic>.from(futures[0]['data'] as Map) : null;
        _officers = futures[1]['data'] is Map
            ? Map<String, dynamic>.from(futures[1]['data'] as Map) : null;
        _loading  = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _print() async {
    try {
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc  = pw.Document();
      final ctx  = widget.ctx;

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        header: (_) => _pdfDocHeader(font, bold,
            '${ctx.electionName} — सारांश रिपोर्ट',
            'जनपद: ${ctx.district}  •  चरण: ${ctx.phase}'
            '  •  तिथि: ${ctx.electionDate}'),
        build: (_) {
          final List<pw.Widget> widgets = [];
          final tot = _booths?['totals'] as Map<String, dynamic>?;
          if (tot != null) {
            widgets.add(pw.Text('बूथ ड्यूटी सारांश',
                style: pw.TextStyle(font: bold, fontSize: 11,
                    fontWeight: pw.FontWeight.bold)));
            widgets.add(pw.SizedBox(height: 6));
            widgets.add(pw.Row(children: [
              for (final entry in [
                ('कुल Assigned', '${tot['total'] ?? 0}'),
                ('Attended',     '${tot['attended'] ?? 0}'),
                ('केन्द्र',       '${tot['centers'] ?? 0}'),
                ('Armed',        '${tot['armed'] ?? 0}'),
                ('Unarmed',      '${tot['unarmed'] ?? 0}'),
              ])
                pw.Expanded(child: pw.Container(
                  margin: const pw.EdgeInsets.only(right: 8),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                        color: PdfColors.grey400, width: 0.5),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(children: [
                    pw.Text(entry.$2,
                        style: pw.TextStyle(font: bold, fontSize: 13,
                            fontWeight: pw.FontWeight.bold)),
                    pw.Text(entry.$1,
                        style: pw.TextStyle(font: font, fontSize: 7)),
                  ]),
                )),
            ]));
            widgets.add(pw.SizedBox(height: 14));

            // By type
            final byType = _booths?['byType'] as List?;
            if (byType != null && byType.isNotEmpty) {
              widgets.add(pw.Text('केंद्र प्रकार अनुसार',
                  style: pw.TextStyle(font: bold, fontSize: 10,
                      fontWeight: pw.FontWeight.bold)));
              widgets.add(pw.SizedBox(height: 4));
              final trows = <pw.TableRow>[
                pw.TableRow(children: [
                  _pdfTh('प्रकार', bold), _pdfTh('Staff', bold),
                  _pdfTh('केन्द्र', bold), _pdfTh('Attended', bold),
                  _pdfTh('Armed', bold),   _pdfTh('Unarmed', bold),
                ]),
              ];
              for (final t in byType) {
                trows.add(pw.TableRow(children: [
                  _pdfTd('${t['centerType'] ?? ''}',    font, center: true),
                  _pdfTd('${t['totalStaff'] ?? 0}',     font, center: true),
                  _pdfTd('${t['centersCovered'] ?? 0}', font, center: true),
                  _pdfTd('${t['attended'] ?? 0}',       font, center: true),
                  _pdfTd('${t['armed'] ?? 0}',          font, center: true),
                  _pdfTd('${t['unarmed'] ?? 0}',        font, center: true),
                ]));
              }
              widgets.add(pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                children: trows));
              widgets.add(pw.SizedBox(height: 14));
            }
          }

          // Officers summary
          final summary = _officers?['summary'] as Map<String, dynamic>?;
          if (summary != null) {
            widgets.add(pw.Text('अधिकारी सारांश',
                style: pw.TextStyle(font: bold, fontSize: 11,
                    fontWeight: pw.FontWeight.bold)));
            widgets.add(pw.SizedBox(height: 6));
            widgets.add(pw.Row(children: [
              for (final entry in [
                ('सुपर जोन',        '${summary['superZoneCount'] ?? 0}'),
                ('जोन',             '${summary['zoneCount'] ?? 0}'),
                ('सैक्टर',          '${summary['sectorCount'] ?? 0}'),
                ('क्षेत्र अधिकारी', '${summary['kshetraOfficers'] ?? 0}'),
                ('जोनल अधिकारी',   '${summary['zonalOfficers'] ?? 0}'),
                ('सेक्टर अधिकारी', '${summary['sectorOfficers'] ?? 0}'),
              ])
                pw.Expanded(child: pw.Container(
                  margin: const pw.EdgeInsets.only(right: 6),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                        color: PdfColors.grey400, width: 0.5),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(children: [
                    pw.Text(entry.$2,
                        style: pw.TextStyle(font: bold, fontSize: 13,
                            fontWeight: pw.FontWeight.bold)),
                    pw.Text(entry.$1,
                        style: pw.TextStyle(font: font, fontSize: 7)),
                  ]),
                )),
            ]));
          }
          return widgets.isEmpty
              ? [pw.Center(child: pw.Text('कोई डेटा नहीं',
                  style: pw.TextStyle(font: font, fontSize: 12)))]
              : widgets;
        },
      ));
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      _snack(context, 'PDF विफल: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _rOf(context);
    if (_loading)
      return const Center(
          child: CircularProgressIndicator(color: _kPrimary));
    if (_error != null)
      return _ErrorCard(error: _error!, onRetry: _load);

    return Column(children: [
      _PrintToolbar(title: 'सारांश रिपोर्ट',
          subtitle: 'चुनाव ${widget.ctx.electionName}',
          color: _kPrimary, onPrint: _print),
      Expanded(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            r.s(10, 14), 12, r.s(10, 14), 30),
        child: Column(children: [
          // Booth summary
          if (_booths != null) ...[
            _sectionTitle('बूथ ड्यूटी सारांश',
                Icons.how_to_vote_outlined, _kPurple),
            const SizedBox(height: 8),
            _boothTotals(_booths!),
            const SizedBox(height: 12),
            if ((_booths!['byType'] as List?)?.isNotEmpty == true)
              _byTypeTable(_booths!['byType'] as List),
            const SizedBox(height: 12),
            if ((_booths!['byRank'] as List?)?.isNotEmpty == true)
              _byRankTable(_booths!['byRank'] as List),
          ],
          // Officer summary
          if (_officers != null) ...[
            const SizedBox(height: 16),
            _sectionTitle('अधिकारी सारांश',
                Icons.account_tree_outlined, _kGreen),
            const SizedBox(height: 8),
            _officerSummary(_officers!),
          ],
          if (_booths == null && _officers == null)
            const _EmptyHint(
                icon: Icons.summarize_outlined,
                title: 'सारांश उपलब्ध नहीं',
                subtitle: 'इस चुनाव के लिए सारांश डेटा नहीं है'),
        ]),
      )),
    ]);
  }

  Widget _sectionTitle(String title, IconData icon, Color color) =>
      Row(children: [
        Container(width: 32, height: 32,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(
            color: color, fontSize: 13, fontWeight: FontWeight.w800)),
      ]);

  Widget _boothTotals(Map<String, dynamic> booths) {
    final r = _rOf(context);
    final tot = booths['totals'] as Map<String, dynamic>? ?? {};
    final items = [
      ('कुल Assigned', '${tot['total'] ?? 0}',     _kPurple),
      ('Attended',      '${tot['attended'] ?? 0}',  _kGreen),
      ('केन्द्र',        '${tot['centers'] ?? 0}',   _kOrange),
      ('Armed',         '${tot['armed'] ?? 0}',      _kRed),
      ('Unarmed',       '${tot['unarmed'] ?? 0}',    _kTeal),
    ];
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: items.map((item) {
        final (label, value, color) = item;
        return Container(
          width: (MediaQuery.of(context).size.width -
              r.s(20, 28) * 2 - 8 * 2) / 3 - 2,
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(children: [
            Text(value, style: TextStyle(
                color: color, fontSize: r.s(18, 20),
                fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(
                color: color.withOpacity(0.8), fontSize: 9.5,
                fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
          ]),
        );
      }).toList(),
    );
  }

  Widget _byTypeTable(List byType) {
    const ws = <double>[60, 70, 70, 70, 60, 60];
    const hs = ['प्रकार', 'Staff', 'केन्द्र', 'Attended', 'Armed', 'Unarmed'];
    final total = ws.fold(0.0, (a, b) => a + b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('केंद्र प्रकार अनुसार', style: TextStyle(
          color: _kDark, fontSize: 11.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: total),
          child: Table(
            border: TableBorder.all(color: _kBorder, width: 0.5),
            columnWidths: Map.fromIterables(
                List.generate(ws.length, (i) => i),
                ws.map((w) => FixedColumnWidth(w))),
            children: [
              TableRow(
                decoration: const BoxDecoration(
                    color: Color(0xFFEDE7F6)),
                children: hs.map((h) => Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(h, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _kPurple)),
                )).toList()),
              ...byType.asMap().entries.map((e) {
                final i = e.key;
                final t = e.value as Map;
                return TableRow(
                  decoration: BoxDecoration(
                      color: i.isEven
                          ? Colors.white : const Color(0xFFFDF4FF)),
                  children: [
                    '${t['centerType'] ?? ''}',
                    '${t['totalStaff'] ?? 0}',
                    '${t['centersCovered'] ?? 0}',
                    '${t['attended'] ?? 0}',
                    '${t['armed'] ?? 0}',
                    '${t['unarmed'] ?? 0}',
                  ].map((v) => Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(v, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11,
                            color: _kDark)),
                  )).toList());
              }),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _byRankTable(List byRank) {
    const ws = <double>[100, 60, 60, 60, 60];
    const hs = ['पद', 'कुल', 'Armed', 'Unarmed', 'Attended'];
    final total = ws.fold(0.0, (a, b) => a + b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('पद अनुसार', style: TextStyle(
          color: _kDark, fontSize: 11.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: total),
          child: Table(
            border: TableBorder.all(color: _kBorder, width: 0.5),
            columnWidths: Map.fromIterables(
                List.generate(ws.length, (i) => i),
                ws.map((w) => FixedColumnWidth(w))),
            children: [
              TableRow(
                decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9)),
                children: hs.map((h) => Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(h, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _kGreen)),
                )).toList()),
              ...byRank.asMap().entries.map((e) {
                final i = e.key;
                final t = e.value as Map;
                final rank = '${t['rank'] ?? ''}';
                final rc   = _rankColor(rank);
                return TableRow(
                  decoration: BoxDecoration(
                      color: i.isEven
                          ? Colors.white : const Color(0xFFF1F8E9)),
                  children: [
                    Padding(padding: const EdgeInsets.all(6),
                        child: Text(rank,
                            style: TextStyle(color: rc, fontSize: 11,
                                fontWeight: FontWeight.w700))),
                    Padding(padding: const EdgeInsets.all(6),
                        child: Text('${t['total'] ?? 0}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11,
                                color: _kDark))),
                    Padding(padding: const EdgeInsets.all(6),
                        child: Text('${t['armed'] ?? 0}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11,
                                color: _kDark))),
                    Padding(padding: const EdgeInsets.all(6),
                        child: Text('${t['unarmed'] ?? 0}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11,
                                color: _kDark))),
                    Padding(padding: const EdgeInsets.all(6),
                        child: Text('${t['attended'] ?? 0}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11,
                                color: _kDark))),
                  ]);
              }),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _officerSummary(Map<String, dynamic> officers) {
    final r = _rOf(context);
    final s = officers['summary'] as Map<String, dynamic>? ?? {};
    final items = [
      ('सुपर जोन',         '${s['superZoneCount'] ?? 0}',   _kPrimary),
      ('जोन',              '${s['zoneCount'] ?? 0}',         _kTeal),
      ('सैक्टर',           '${s['sectorCount'] ?? 0}',       _kGreen),
      ('क्षेत्र अधिकारी',  '${s['kshetraOfficers'] ?? 0}',   _kOrange),
      ('जोनल अधिकारी',    '${s['zonalOfficers'] ?? 0}',      _kPrimary),
      ('सेक्टर अधिकारी',  '${s['sectorOfficers'] ?? 0}',     _kDistrictColor),
    ];
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: items.map((item) {
        final (label, value, color) = item;
        return Container(
          width: (MediaQuery.of(context).size.width -
              r.s(20, 28) * 2 - 8 * 2) / 3 - 2,
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(children: [
            Text(value, style: TextStyle(
                color: color, fontSize: r.s(18, 20),
                fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(
                color: color.withOpacity(0.8), fontSize: 9.5,
                fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
          ]),
        );
      }).toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED TINY WIDGETS
// ══════════════════════════════════════════════════════════════════════════════
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _EmptyHint({
    required this.icon, required this.title, required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 52, color: _kBorder),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: _kDark)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(
              fontSize: 12, color: _kSubtle),
              textAlign: TextAlign.center),
        ],
      ]),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorCard({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 44, color: _kRed),
        const SizedBox(height: 10),
        const Text('डेटा लोड करने में त्रुटि',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: _kDark)),
        const SizedBox(height: 6),
        Text(error, style: const TextStyle(
            color: _kSubtle, fontSize: 11),
            textAlign: TextAlign.center, maxLines: 4,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
          label: const Text('पुनः प्रयास',
              style: TextStyle(color: Colors.white)),
        ),
      ]),
    ),
  );
}

// ── Rank color (shared, mirrors manak_district_page.dart) ────────────────────
Color _rankColor(String rank) {
  const m = {
    'SP':             Color(0xFF6A1B9A),
    'ASP':            Color(0xFF1565C0),
    'DSP':            Color(0xFF1A5276),
    'Inspector':      Color(0xFF2E7D32),
    'SI':             Color(0xFF558B2F),
    'ASI':            Color(0xFF8B6914),
    'Head Constable': Color(0xFFB8860B),
    'Constable':      Color(0xFF6D4C41),
  };
  return m[rank] ?? _kPrimary;
}