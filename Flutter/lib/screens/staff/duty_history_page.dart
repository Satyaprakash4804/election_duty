import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kBg       = Color(0xFFFDF6E3);
const _kSurface  = Color(0xFFF5E6C8);
const _kPrimary  = Color(0xFF8B6914);
const _kAccent   = Color(0xFFB8860B);
const _kDark     = Color(0xFF4A3000);
const _kSubtle   = Color(0xFFAA8844);
const _kBorder   = Color(0xFFD4A843);
const _kError    = Color(0xFFC0392B);
const _kSuccess  = Color(0xFF2D6A1E);
const _kInfo     = Color(0xFF1A5276);
const _kDistrict = Color(0xFF4A148C);
const _kAmber    = Color(0xFFF59E0B);

// ── Rank display map ──────────────────────────────────────────────────────────
const _rankMap = {
  'constable':     'आरक्षी',
  'head constable':'मुख्य आरक्षी',
  'si':            'उप निरीक्षक',
  'sub inspector': 'उप निरीक्षक',
  'inspector':     'निरीक्षक',
  'asi':           'सहायक उप निरीक्षक',
  'dsp':           'उपाधीक्षक',
  'asp':           'सहा0 पुलिस अधीक्षक',
  'sp':            'पुलिस अधीक्षक',
};

String _rh(dynamic val) =>
    _rankMap[(val ?? '').toString().toLowerCase()] ?? val?.toString() ?? '—';

String _v(dynamic x) =>
    (x == null || x.toString().trim().isEmpty) ? '—' : x.toString();

const _districtDutyLabels = {
  'cluster_mobile':        'क्लस्टर मोबाईल',
  'thana_mobile':          'थाना मोबाईल',
  'thana_reserve':         'थाना रिजर्व',
  'thana_extra_mobile':    'थाना अतिरिक्त मोबाईल',
  'sector_pol_mag_mobile': 'सैक्टर पुलिस/मजिस्ट्रेट मोबाईल',
  'zonal_pol_mag_mobile':  'जोनल पुलिस/मजिस्ट्रेट मोबाईल',
  'sdm_co_mobile':         'एसडीएम/सीओ मोबाईल',
  'chowki_mobile':         'चौकी मोबाईल',
  'barrier_picket':        'बैरियर/पिकैट',
  'evm_security':          'ईवीएम सुरक्षा',
  'adm_sp_mobile':         'एडीएम/एसपी मोबाईल',
  'dm_sp_mobile':          'डीएम/एसपी मोबाईल',
  'observer_security':     'पर्यवेक्षक सुरक्षा',
  'hq_reserve':            'मुख्यालय रिजर्व',
};
String _dutyLabel(String? k) =>
    _districtDutyLabels[k] ?? k?.replaceAll('_', ' ') ?? '—';

// ── Rank colors ───────────────────────────────────────────────────────────────
const _rankColors = {
  'SP':             Color(0xFF6A1B9A),
  'ASP':            Color(0xFF1565C0),
  'DSP':            Color(0xFF1A5276),
  'Inspector':      Color(0xFF2E7D32),
  'SI':             Color(0xFF558B2F),
  'ASI':            Color(0xFF8B6914),
  'Head Constable': Color(0xFFB8860B),
  'Constable':      Color(0xFF6D4C41),
};

Color _rankColor(String? r) => _rankColors[r] ?? _kPrimary;

// ── Date formatting ───────────────────────────────────────────────────────────
String _fmtDate(String? d) {
  if (d == null || d.isEmpty) return '—';
  try {
    final dt = DateTime.parse(d);
    const m  = ['','जनवरी','फरवरी','मार्च','अप्रैल','मई','जून',
        'जुलाई','अगस्त','सितम्बर','अक्टूबर','नवम्बर','दिसम्बर'];
    return '${dt.day} ${m[dt.month]} ${dt.year}';
  } catch (_) { return d; }
}

bool _isUpcoming(String? d) {
  if (d == null) return false;
  try { return DateTime.parse(d).isAfter(DateTime.now()); }
  catch (_) { return false; }
}

// ── Responsive helper ─────────────────────────────────────────────────────────
class _R {
  final double w;
  const _R(this.w);
  bool get compact => w < 380;
  bool get wide    => w >= 600;
  double font(double sm, double lg) =>
      sm + (lg - sm) * ((w - 320) / 280).clamp(0.0, 1.0);
  double pad(double sm, double lg) =>
      sm + (lg - sm) * ((w - 320) / 280).clamp(0.0, 1.0);
  int get cols => wide ? 3 : compact ? 1 : 2;
}
_R _rr(BuildContext c) => _R(MediaQuery.of(c).size.width);

// ══════════════════════════════════════════════════════════════════════════════
//  GROUPED ELECTION MODEL
// ══════════════════════════════════════════════════════════════════════════════

class _ElectionGroup {
  final String electionName;
  final String electionDate;
  final int?   electionId;
  final List<Map<String, dynamic>> duties;

  _ElectionGroup({
    required this.electionName,
    required this.electionDate,
    required this.electionId,
    required this.duties,
  });

  /// Build groups ordered by election date desc (most recent first).
  static List<_ElectionGroup> fromList(List<Map<String, dynamic>> all) {
    // key: electionId (or electionName if no id)
    final Map<String, _ElectionGroup> map = {};

    for (final d in all) {
      final eid    = d['electionId']?.toString();
      final eName  = (d['electionName'] as String? ?? '').trim();
      final eDate  = d['electionDate'] as String? ?? d['date'] as String? ?? '';
      final key    = eid?.isNotEmpty == true ? eid! : (eName.isNotEmpty ? eName : 'unknown');

      if (map.containsKey(key)) {
        map[key]!.duties.add(d);
      } else {
        map[key] = _ElectionGroup(
          electionName: eName.isNotEmpty ? eName : 'अज्ञात चुनाव',
          electionDate: eDate,
          electionId:   int.tryParse(eid ?? ''),
          duties:       [d],
        );
      }
    }

    final groups = map.values.toList();
    groups.sort((a, b) {
      // Most recent election first
      try {
        if (a.electionDate.isNotEmpty && b.electionDate.isNotEmpty) {
          return DateTime.parse(b.electionDate)
              .compareTo(DateTime.parse(a.electionDate));
        }
      } catch (_) {}
      return b.electionName.compareTo(a.electionName);
    });
    return groups;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY HISTORY PAGE
// ══════════════════════════════════════════════════════════════════════════════

class DutyHistoryPage extends StatefulWidget {
  const DutyHistoryPage({super.key});
  @override
  State<DutyHistoryPage> createState() => _DutyHistoryPageState();
}

class _DutyHistoryPageState extends State<DutyHistoryPage>
    with SingleTickerProviderStateMixin {

  // ── Data ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allDuties = [];
  Map<String, dynamic>?      _profile;
  bool   _loading = true;
  String? _error;

  // ── UI state ──────────────────────────────────────────────────────────────
  String _filterKind   = 'all';      // all / booth / district / sector / zone / kshetra
  String _filterStatus = 'all';      // all / present / absent / upcoming
  String _searchQ      = '';
  bool   _groupByElect = true;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    _fadeCtrl.reset();
    try {
      final token   = await AuthService.getToken();
      final results = await Future.wait([
        ApiService.get('/staff/history',  token: token),
        ApiService.get('/staff/profile',  token: token),
      ]);

      final raw     = results[0]['data'];
      final profRaw = results[1]['data'];
      final list    = (raw is List)
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _allDuties = list;
        _profile   = (profRaw is Map)
            ? Map<String, dynamic>.from(profRaw as Map) : null;
        _loading   = false;
      });
      _fadeCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Filtering ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    var list = _allDuties.toList();

    // Kind filter
    if (_filterKind != 'all') {
      list = list.where((d) =>
          (d['dutyKind'] ?? '').toString().toLowerCase() == _filterKind).toList();
    }

    // Status filter
    if (_filterStatus == 'present') {
      list = list.where((d) => d['present'] == true).toList();
    } else if (_filterStatus == 'absent') {
      list = list.where((d) => d['present'] == false).toList();
    } else if (_filterStatus == 'upcoming') {
      list = list.where((d) =>
          _isUpcoming(d['electionDate'] as String? ?? d['date'] as String?)).toList();
    }

    // Search
    if (_searchQ.isNotEmpty) {
      final q = _searchQ.toLowerCase();
      list = list.where((d) {
        return (d['booth']         ?? '').toString().toLowerCase().contains(q) ||
               (d['electionName']  ?? '').toString().toLowerCase().contains(q) ||
               (d['sector']        ?? '').toString().toLowerCase().contains(q) ||
               (d['zone']          ?? '').toString().toLowerCase().contains(q) ||
               (d['superZone']     ?? '').toString().toLowerCase().contains(q) ||
               (d['dutyType']      ?? '').toString().toLowerCase().contains(q) ||
               (d['district']      ?? '').toString().toLowerCase().contains(q) ||
               (d['gramPanchayat'] ?? '').toString().toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  int get _total       => _allDuties.length;
  int get _boothCount  => _allDuties.where((d) => d['dutyKind'] == 'booth').length;
  int get _distCount   => _allDuties.where((d) => d['dutyKind'] == 'district').length;
  int get _officerCount => _allDuties.where((d) =>
      ['sector','zone','kshetra'].contains(d['dutyKind'])).length;
  int get _presentCount => _allDuties.where((d) => d['present'] == true).length;
  int get _absentCount  => _allDuties.where((d) => d['present'] == false).length;

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_buildSliverAppBar()],
        body: Column(children: [
          _buildFilterRow(),
          if (!_loading && _error == null) _buildSummaryStrip(),
          _buildSearchBar(),
          Expanded(child: _buildBody()),
        ]),
      ),
    );
  }

  // ── Sliver app bar ────────────────────────────────────────────────────────
  Widget _buildSliverAppBar() => SliverAppBar(
    expandedHeight: 120,
    floating: false, pinned: true,
    backgroundColor: _kDark, elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
      onPressed: () => Navigator.pop(context),
    ),
    actions: [
      // Group toggle
      GestureDetector(
        onTap: () => setState(() => _groupByElect = !_groupByElect),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _groupByElect
                ? _kSuccess.withOpacity(0.3)
                : Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white30),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_groupByElect ? Icons.workspaces_filled : Icons.list_outlined,
                color: Colors.white, size: 13),
            const SizedBox(width: 4),
            Text(_groupByElect ? 'समूह' : 'सूची',
                style: const TextStyle(color: Colors.white,
                    fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
        onPressed: _load, tooltip: 'ताज़ा करें',
      ),
    ],
    flexibleSpace: FlexibleSpaceBar(
      titlePadding: const EdgeInsets.fromLTRB(56, 0, 100, 14),
      title: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ड्यूटी इतिहास', style: TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800,
            letterSpacing: 0.3)),
        if (_profile != null)
          Text(_profile!['name'] as String? ?? '',
              style: const TextStyle(
                  color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w400)),
      ]),
      background: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
            colors: [Color(0xFF6B4A00), _kDark],
            begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Opacity(opacity: 0.04,
          child: GridView.count(crossAxisCount: 10,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(80, (_) =>
              const Icon(Icons.shield_outlined, color: Colors.white, size: 18)))),
      ),
    ),
  );

  // ── Filter row (kind + status) ────────────────────────────────────────────
  Widget _buildFilterRow() => Container(
    color: _kSurface,
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Kind chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (k, lbl) in [
            ('all',      'सभी'),
            ('booth',    '🗳 बूथ'),
            ('district', '🛡 जनपदीय'),
            ('sector',   '📍 सेक्टर'),
            ('zone',     '🗺 जोन'),
            ('kshetra',  '🏛 क्षेत्र'),
          ]) _filterChip(
              label: lbl, value: k,
              current: _filterKind,
              color: _kindColor(k),
              onTap: () => setState(() { _filterKind = k; })),
        ]),
      ),
      const SizedBox(height: 6),
      // Status chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (k, lbl) in [
            ('all',      'सभी'),
            ('upcoming', '🗓 आगामी'),
            ('present',  '✅ उपस्थित'),
            ('absent',   '❌ अनुपस्थित'),
          ]) _filterChip(
              label: lbl, value: k,
              current: _filterStatus,
              color: _statusColor(k),
              onTap: () => setState(() { _filterStatus = k; })),
        ]),
      ),
    ]),
  );

  Color _kindColor(String k) => switch (k) {
    'booth'    => _kError,
    'district' => _kDistrict,
    'sector'   => const Color(0xFF2E7D32),
    'zone'     => const Color(0xFF1565C0),
    'kshetra'  => _kDistrict,
    _          => _kPrimary,
  };

  Color _statusColor(String k) => switch (k) {
    'present'  => _kSuccess,
    'absent'   => _kError,
    'upcoming' => _kInfo,
    _          => _kPrimary,
  };

  Widget _filterChip({
    required String label, required String value,
    required String current, required Color color,
    required VoidCallback onTap,
  }) {
    final sel = current == value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? color : _kBorder.withOpacity(0.4)),
          boxShadow: sel ? [BoxShadow(color: color.withOpacity(0.25),
              blurRadius: 5, offset: const Offset(0, 2))] : [],
        ),
        child: Text(label, style: TextStyle(
          color: sel ? Colors.white : _kDark,
          fontSize: 11, fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
        )),
      ),
    );
  }

  // ── Summary strip ─────────────────────────────────────────────────────────
  Widget _buildSummaryStrip() {
    final r = _rr(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        _statCell('कुल',       '$_total',         _kPrimary),
        _div(),
        _statCell('बूथ',       '$_boothCount',    _kAccent),
        _div(),
        _statCell('उपस्थित',  '$_presentCount',  _kSuccess),
        _div(),
        _statCell('अनुपस्थित','$_absentCount',   _kError),
        _div(),
        _statCell('जनपदीय',   '$_distCount',     _kDistrict),
        if (!r.compact) ...[
          _div(),
          _statCell('अधिकारी', '$_officerCount',  _kInfo),
        ],
      ]),
    );
  }

  Widget _statCell(String lbl, String val, Color c) => Expanded(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      Text(val, style: TextStyle(color: c, fontSize: 17,
          fontWeight: FontWeight.w900, height: 1.1)),
      const SizedBox(height: 2),
      Text(lbl, style: const TextStyle(color: _kSubtle, fontSize: 9,
          fontWeight: FontWeight.w600)),
    ]));

  Widget _div() => Container(height: 30, width: 1, color: _kBorder.withOpacity(0.3));

  // ── Search bar ────────────────────────────────────────────────────────────
  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: TextField(
      controller: _searchCtrl,
      onChanged: (q) => setState(() => _searchQ = q.trim()),
      style: const TextStyle(color: _kDark, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'चुनाव/केंद्र/जोन/सेक्टर खोजें...',
        hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
        prefixIcon: const Icon(Icons.search, color: _kSubtle, size: 18),
        suffixIcon: _searchQ.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16, color: _kSubtle),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQ = '');
                })
            : null,
        filled: true, fillColor: Colors.white, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kPrimary, width: 2)),
      ),
    ),
  );

  // ── Body ─────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_loading) return _LoadingView();
    if (_error   != null) return _ErrorView(error: _error!, onRetry: _load);
    final filtered = _filtered;
    if (filtered.isEmpty) return _EmptyView(filter: _filterKind, search: _searchQ);

    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        onRefresh: _load,
        color: _kPrimary,
        child: _groupByElect
            ? _buildGroupedList(filtered)
            : _buildFlatList(filtered),
      ),
    );
  }

  // ── Grouped by election ───────────────────────────────────────────────────
  Widget _buildGroupedList(List<Map<String, dynamic>> filtered) {
    final groups = _ElectionGroup.fromList(filtered);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
      itemCount: groups.length,
      itemBuilder: (_, i) => _ElectionGroupSection(
        group:   groups[i],
        profile: _profile,
        onCertificate: (duty) => _generateCertificate(duty),
      ),
    );
  }

  // ── Flat list ─────────────────────────────────────────────────────────────
  Widget _buildFlatList(List<Map<String, dynamic>> filtered) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final d = filtered[i];
        return _DutyCard(
          duty:    d,
          profile: _profile,
          onCertificate: () => _generateCertificate(d),
        );
      },
    );
  }

  // ── Certificate PDF ───────────────────────────────────────────────────────
  Future<void> _generateCertificate(Map<String, dynamic> duty) async {
    try {
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc  = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(20),
        build: (_) => _buildCertificatePdf(duty, font, bold),
      ));
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF त्रुटि: $e'),
          backgroundColor: _kError, behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  pw.Widget _buildCertificatePdf(
    Map<String, dynamic> duty, pw.Font font, pw.Font bold,
  ) {
    final profile     = _profile ?? {};
    final dutyKind    = duty['dutyKind'] as String? ?? 'booth';
    final isDistrict  = dutyKind == 'district';
    final isOfficer   = ['sector','zone','kshetra'].contains(dutyKind);
    final elecName    = _v(duty['electionName'] ?? duty['election_name']);
    final elecDate    = _fmtDate(duty['electionDate'] as String? ?? duty['date'] as String?);
    final centerName  = isDistrict
        ? _dutyLabel(duty['dutyType'] as String?)
        : isOfficer
            ? (duty['sectorName'] ?? duty['zoneName'] ??
               duty['superZoneName'] ?? '—').toString()
            : _v(duty['booth']);
    final present     = duty['present'] as bool?;
    final presentText = present == true ? 'उपस्थित' : present == false ? 'अनुपस्थित' : '—';
    final batchNo     = duty['batchNo']?.toString() ?? '';
    final busNo       = duty['busNo']?.toString()   ?? '';

    pw.TextStyle ts(pw.Font f, {double size = 11, PdfColor? color}) =>
        pw.TextStyle(font: f, fontSize: size, color: color ?? PdfColors.black);

    pw.Widget row(String lbl, String val) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(children: [
        pw.SizedBox(width: 130,
          child: pw.Text(lbl, style: ts(font, color: PdfColors.grey700))),
        pw.Text(': ', style: ts(font)),
        pw.Expanded(child: pw.Text(val, style: ts(bold))),
      ]),
    );

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      // Header
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFF4A3000),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Text('चुनाव ड्यूटी प्रमाण-पत्र',
              style: ts(bold, size: 16, color: PdfColors.white),
              textAlign: pw.TextAlign.center),
          pw.Text('Election Duty Certificate',
              style: ts(font, size: 10, color: PdfColors.grey300),
              textAlign: pw.TextAlign.center),
        ]),
      ),
      pw.SizedBox(height: 16),

      // Election block
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF5E6C8),
          border: pw.Border.all(color: const PdfColor.fromInt(0xFFD4A843)),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('चुनाव विवरण', style: ts(bold, size: 11,
              color: const PdfColor.fromInt(0xFF4A3000))),
          pw.SizedBox(height: 6),
          row('चुनाव का नाम', elecName),
          row('मतदान तिथि',   elecDate),
        ]),
      ),
      pw.SizedBox(height: 12),

      // Staff block
      pw.Text('कर्मचारी विवरण', style: ts(bold, size: 11,
          color: const PdfColor.fromInt(0xFF4A3000))),
      pw.SizedBox(height: 6),
      row('नाम',    _v(profile['name'])),
      row('PNO',    _v(profile['pno'])),
      row('पद',     _rh(profile['rank'] ?? profile['user_rank'])),
      row('थाना',   _v(profile['thana'])),
      row('जनपद',   _v(profile['district'])),
      pw.SizedBox(height: 12),

      // Duty block
      pw.Text('ड्यूटी विवरण', style: ts(bold, size: 11,
          color: const PdfColor.fromInt(0xFF4A3000))),
      pw.SizedBox(height: 6),
      row('ड्यूटी प्रकार', isDistrict ? 'जनपदीय ड्यूटी'
          : isOfficer   ? '${dutyKind[0].toUpperCase()}${dutyKind.substring(1)} अधिकारी'
                        : 'बूथ ड्यूटी'),
      row('केंद्र / स्थान', centerName),
      if (!isDistrict && !isOfficer) ...[
        if ((duty['sector']    ?? '').toString().isNotEmpty)
          row('सेक्टर',     _v(duty['sector'])),
        if ((duty['zone']      ?? '').toString().isNotEmpty)
          row('जोन',         _v(duty['zone'])),
        if ((duty['superZone'] ?? '').toString().isNotEmpty)
          row('सुपर जोन',   _v(duty['superZone'])),
      ],
      if (isDistrict) ...[
        if (batchNo.isNotEmpty) row('बैच संख्या', 'बैच $batchNo'),
        if (busNo.isNotEmpty)   row('बस संख्या',  busNo),
      ],
      if (present != null) row('उपस्थिति', presentText),
      pw.SizedBox(height: 20),

      // Footer
      pw.Divider(color: const PdfColor.fromInt(0xFFD4A843)),
      pw.SizedBox(height: 6),
      pw.Text(
        'यह प्रमाण-पत्र स्वचालित रूप से तैयार किया गया है।\n'
        'This certificate is auto-generated from the Election Duty System.',
        style: ts(font, size: 8, color: PdfColors.grey600),
        textAlign: pw.TextAlign.center,
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION GROUP SECTION  — header + collapsible cards
// ══════════════════════════════════════════════════════════════════════════════

class _ElectionGroupSection extends StatefulWidget {
  final _ElectionGroup group;
  final Map<String, dynamic>? profile;
  final Future<void> Function(Map<String, dynamic>) onCertificate;
  const _ElectionGroupSection({
    required this.group, required this.profile, required this.onCertificate,
  });
  @override State<_ElectionGroupSection> createState() =>
      _ElectionGroupSectionState();
}

class _ElectionGroupSectionState extends State<_ElectionGroupSection> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final upcoming = _isUpcoming(g.electionDate);
    final Color headerColor = upcoming ? _kInfo : _kDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Election header ────────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: upcoming
                    ? [const Color(0xFF1A237E), const Color(0xFF283593)]
                    : [const Color(0xFF4A3000), const Color(0xFF6B4A00)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(14),
                bottom: _collapsed ? const Radius.circular(14) : Radius.zero,
              ),
              boxShadow: [BoxShadow(
                color: headerColor.withOpacity(0.3),
                blurRadius: 10, offset: const Offset(0, 4),
              )],
            ),
            child: Row(children: [
              Container(width: 38, height: 38,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.13),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24)),
                child: Icon(upcoming
                    ? Icons.upcoming_outlined : Icons.how_to_vote_outlined,
                    color: Colors.white, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (upcoming)
                  Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kAmber.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('आगामी', style: TextStyle(
                        color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                  ),
                Text(g.electionName, style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(children: [
                  if (g.electionDate.isNotEmpty) ...[
                    const Icon(Icons.calendar_today_outlined, size: 10, color: Colors.white60),
                    const SizedBox(width: 3),
                    Text(_fmtDate(g.electionDate),
                        style: const TextStyle(color: Colors.white60, fontSize: 10)),
                    const SizedBox(width: 10),
                  ],
                  const Icon(Icons.receipt_long_outlined, size: 10, color: Colors.white60),
                  const SizedBox(width: 3),
                  Text('${g.duties.length} रिकॉर्ड',
                      style: const TextStyle(color: Colors.white60, fontSize: 10)),
                ]),
              ])),
              AnimatedRotation(
                turns: _collapsed ? -0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Container(width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      shape: BoxShape.circle),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white, size: 20)),
              ),
            ]),
          ),
        ),

        // ── Duty cards ─────────────────────────────────────────────────────
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _collapsed
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.4),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14)),
              border: Border.all(color: _kBorder.withOpacity(0.3)),
            ),
            child: Column(children: [
              for (int i = 0; i < g.duties.length; i++) ...[
                _DutyCard(
                  duty:    g.duties[i],
                  profile: widget.profile,
                  onCertificate: () => widget.onCertificate(g.duties[i]),
                  isInGroup: true,
                  isLast: i == g.duties.length - 1,
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY CARD  — handles all types: booth, district, sector, zone, kshetra
// ══════════════════════════════════════════════════════════════════════════════

class _DutyCard extends StatefulWidget {
  final Map<String, dynamic> duty;
  final Map<String, dynamic>? profile;
  final Future<void> Function() onCertificate;
  final bool isInGroup;
  final bool isLast;

  const _DutyCard({
    required this.duty,
    required this.profile,
    required this.onCertificate,
    this.isInGroup = false,
    this.isLast    = false,
  });

  @override State<_DutyCard> createState() => _DutyCardState();
}

class _DutyCardState extends State<_DutyCard> {
  bool _expanded  = false;
  bool _printing  = false;

  @override
  Widget build(BuildContext context) {
    final d        = widget.duty;
    final r        = _rr(context);
    final kind     = (d['dutyKind'] as String? ?? 'booth').toLowerCase();
    final isDistrict = kind == 'district';
    final isOfficer  = ['sector','zone','kshetra'].contains(kind);
    final isBooth    = kind == 'booth';

    // ── Status
    final present    = d['present'] as bool?;
    final elecDate   = d['electionDate'] as String? ?? d['date'] as String?;
    final upcoming   = _isUpcoming(elecDate);

    final (statusColor, statusIcon, statusText) = upcoming
        ? (_kInfo,    Icons.schedule_rounded,      'आगामी')
        : isOfficer
            ? (_kDistrict, Icons.verified_user_outlined, _officerLabel(kind))
            : isDistrict
                ? (_kDistrict, Icons.shield_outlined, 'जनपदीय')
                : present == true
                    ? (_kSuccess, Icons.check_circle_rounded,  'उपस्थित')
                    : present == false
                        ? (_kError,   Icons.cancel_rounded,        'अनुपस्थित')
                        : (_kSubtle,  Icons.help_outline_rounded,  'अज्ञात');

    // ── Title
    final title = isDistrict
        ? _dutyLabel(d['dutyType'] as String?)
        : isOfficer
            ? _officerTitle(kind, d)
            : _v(d['booth']);

    // ── Election info (for flat list; groups already have header)
    final elecName = (d['electionName'] as String? ?? '').trim();

    // ── Card decoration
    final cardDecoration = widget.isInGroup
        ? BoxDecoration(
            border: !widget.isLast
                ? Border(bottom: BorderSide(color: _kBorder.withOpacity(0.3)))
                : null,
          )
        : BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: statusColor.withOpacity(0.22), width: 1.5),
            boxShadow: [BoxShadow(color: statusColor.withOpacity(0.08),
                blurRadius: 10, offset: const Offset(0, 3))],
          );

    return Container(
      margin: widget.isInGroup ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      decoration: cardDecoration,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header row ──────────────────────────────────────────────────────
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: widget.isInGroup ? null : BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.fromLTRB(r.pad(12, 16), 12, 10, 10),
            child: Row(children: [
              // Status dot + icon
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    statusColor.withOpacity(0.18),
                    statusColor.withOpacity(0.06),
                  ]),
                  border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
                ),
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 10),
              // Labels
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Badge row
                Wrap(spacing: 5, runSpacing: 3, children: [
                  _badge(statusText, statusColor),
                  if (!widget.isInGroup && elecName.isNotEmpty)
                    _badge(elecName, _kPrimary, icon: Icons.how_to_vote_outlined),
                  _badge(_fmtDate(elecDate), _kSubtle,
                      icon: Icons.calendar_today_outlined),
                  if (isDistrict && (d['batchNo'] ?? '').toString().isNotEmpty)
                    _badge('बैच ${d['batchNo']}', _kDistrict),
                  _kindBadge(kind),
                ]),
                const SizedBox(height: 5),
                Text(title, style: TextStyle(
                    color: _kDark, fontWeight: FontWeight.w700,
                    fontSize: r.font(13, 15)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ])),
              // Expand + certificate
              Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: _printing ? null : () async {
                    setState(() => _printing = true);
                    await widget.onCertificate();
                    if (mounted) setState(() => _printing = false);
                  },
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kPrimary.withOpacity(0.3)),
                    ),
                    child: _printing
                        ? const Padding(padding: EdgeInsets.all(7),
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary))
                        : const Icon(Icons.download_outlined, size: 16, color: _kPrimary),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08), shape: BoxShape.circle),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: statusColor, size: 20)),
                ),
              ]),
            ]),
          ),
        ),

        // ── Hierarchy breadcrumb ─────────────────────────────────────────
        if (isBooth || isOfficer)
          Padding(
            padding: EdgeInsets.fromLTRB(r.pad(12, 16), 0, 12, 8),
            child: _HierarchyRow(duty: d, kind: kind),
          ),

        if (isDistrict)
          Padding(
            padding: EdgeInsets.fromLTRB(r.pad(12, 16), 0, 12, 8),
            child: _DistrictChips(duty: d),
          ),

        // ── Expanded detail ──────────────────────────────────────────────
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _DutyExpandedDetail(
            duty: d, kind: kind, profile: widget.profile),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
      ]),
    );
  }

  String _officerLabel(String kind) => switch (kind) {
    'sector'  => 'सेक्टर अधिकारी',
    'zone'    => 'जोनल अधिकारी',
    'kshetra' => 'क्षेत्र अधिकारी',
    _         => 'अधिकारी',
  };

  String _officerTitle(String kind, Map d) => switch (kind) {
    'sector'  => _v(d['sectorName'] ?? d['sector']),
    'zone'    => _v(d['zoneName']   ?? d['zone']),
    'kshetra' => _v(d['superZoneName'] ?? d['superZone']),
    _         => '—',
  };

  Widget _badge(String text, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[
        Icon(icon, size: 9, color: color), const SizedBox(width: 3),
      ],
      Text(text, style: TextStyle(color: color, fontSize: 9.5,
          fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _kindBadge(String kind) {
    final (lbl, color) = switch (kind) {
      'booth'    => ('बूथ',          _kAccent),
      'district' => ('जनपदीय',       _kDistrict),
      'sector'   => ('सेक्टर',        const Color(0xFF2E7D32)),
      'zone'     => ('जोन',           const Color(0xFF1565C0)),
      'kshetra'  => ('क्षेत्र',       _kDistrict),
      _          => ('अज्ञात',        _kSubtle),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(lbl, style: TextStyle(color: color, fontSize: 9,
          fontWeight: FontWeight.w800)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  DUTY EXPANDED DETAIL  — shows all fields per type
// ══════════════════════════════════════════════════════════════════════════════

class _DutyExpandedDetail extends StatelessWidget {
  final Map<String, dynamic> duty;
  final String kind;
  final Map<String, dynamic>? profile;

  const _DutyExpandedDetail({required this.duty, required this.kind,
      required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (kind == 'booth')    ..._boothRows()
        else if (kind == 'district') ..._districtRows()
        else ..._officerRows(),
      ]),
    );
  }

  List<Widget> _boothRows() {
    final assigned = (duty['assignedStaff'] as List?)?.cast<Map>() ?? [];
    return [
      if ((duty['booth'] ?? '').toString().isNotEmpty)
        _drow(Icons.location_on_outlined,     'मतदान केंद्र', duty['booth'], _kError),
      if ((duty['address'] ?? '').toString().isNotEmpty)
        _drow(Icons.place_outlined,            'पता',          duty['address'], _kSubtle),
      if ((duty['thana'] ?? '').toString().isNotEmpty)
        _drow(Icons.local_police_outlined,     'थाना',         duty['thana'], _kSubtle),
      if ((duty['centerType'] ?? '').toString().isNotEmpty)
        _drow(Icons.category_outlined,         'केंद्र प्रकार',duty['centerType'], _kAccent),
      if ((duty['gramPanchayat'] ?? '').toString().isNotEmpty)
        _drow(Icons.account_balance_outlined,  'ग्राम पंचायत', duty['gramPanchayat'],
            const Color(0xFF6D4C41)),
      if ((duty['busNo'] ?? '').toString().isNotEmpty)
        _drow(Icons.directions_bus_outlined,   'बस संख्या',    'बस—${duty['busNo']}', _kAccent),
      if (duty['present'] != null)
        _drow(
          duty['present'] == true
              ? Icons.check_circle_outlined : Icons.cancel_outlined,
          'उपस्थिति',
          duty['present'] == true ? 'उपस्थित ✓' : 'अनुपस्थित ✗',
          duty['present'] == true ? _kSuccess : _kError,
        ),
      if (assigned.isNotEmpty) ...[
        const _StaffDivider(label: 'सहयोगी स्टाफ'),
        _StaffChips(staffList: assigned),
      ],
    ];
  }

  List<Widget> _districtRows() {
    final batchStaff = (duty['batchStaff'] as List?)?.cast<Map>() ?? [];
    return [
      _drow(Icons.shield_outlined, 'ड्यूटी प्रकार',
          _dutyLabel(duty['dutyType'] as String?), _kDistrict),
      if ((duty['batchNo'] ?? '').toString().isNotEmpty)
        _drow(Icons.confirmation_number_outlined, 'बैच संख्या',
            'बैच ${duty['batchNo']}', _kPrimary),
      if ((duty['district'] ?? '').toString().isNotEmpty)
        _drow(Icons.location_city_outlined, 'जनपद', duty['district'], _kInfo),
      if ((duty['busNo'] ?? '').toString().isNotEmpty)
        _drow(Icons.directions_bus_outlined, 'बस संख्या', duty['busNo'], _kAccent),
      if ((duty['note'] ?? '').toString().isNotEmpty)
        _drow(Icons.notes_outlined, 'विशेष नोट', duty['note'], _kSubtle),
      if (batchStaff.isNotEmpty) ...[
        const _StaffDivider(label: 'बैच सहयोगी'),
        _StaffChips(staffList: batchStaff),
      ],
    ];
  }

  List<Widget> _officerRows() => [
    if ((duty['sectorName'] ?? duty['sector'] ?? '').toString().isNotEmpty)
      _drow(Icons.view_module_outlined, 'सेक्टर',
          duty['sectorName'] ?? duty['sector'], const Color(0xFF2E7D32)),
    if ((duty['zoneName'] ?? duty['zone'] ?? '').toString().isNotEmpty)
      _drow(Icons.grid_view_outlined, 'जोन',
          duty['zoneName'] ?? duty['zone'], const Color(0xFF1565C0)),
    if ((duty['superZoneName'] ?? duty['superZone'] ?? '').toString().isNotEmpty)
      _drow(Icons.layers_outlined, 'सुपर जोन',
          duty['superZoneName'] ?? duty['superZone'], _kDistrict),
    if ((duty['hqAddress'] ?? '').toString().isNotEmpty)
      _drow(Icons.home_work_outlined, 'मुख्यालय', duty['hqAddress'], _kSubtle),
    if ((duty['district'] ?? '').toString().isNotEmpty)
      _drow(Icons.location_city_outlined, 'जनपद', duty['district'], _kInfo),
    _drow(Icons.groups_outlined, 'कुल बूथ',
        '${duty['totalBooths'] ?? duty['center_count'] ?? '—'}', _kPrimary),
    _drow(Icons.people_outlined, 'असाइन स्टाफ',
        '${duty['totalAssigned'] ?? duty['staff_assigned'] ?? '—'}', _kSuccess),
  ];

  Widget _drow(IconData icon, String label, dynamic val, Color color) =>
    Padding(padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        Container(width: 28, height: 28,
          decoration: BoxDecoration(color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, size: 13, color: color)),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _kSubtle, fontSize: 9.5)),
          Text(_v(val), style: const TextStyle(color: _kDark, fontSize: 12,
              fontWeight: FontWeight.w700)),
        ])),
      ]));
}

// ── Hierarchy breadcrumb ──────────────────────────────────────────────────────

class _HierarchyRow extends StatelessWidget {
  final Map<String, dynamic> duty;
  final String kind;
  const _HierarchyRow({required this.duty, required this.kind});

  @override
  Widget build(BuildContext context) {
    final items = <({String label, IconData icon, Color color})>[];

    if ((duty['superZone'] ?? duty['superZoneName'] ?? '').toString().isNotEmpty)
      items.add((label: duty['superZone'] ?? duty['superZoneName'] as String,
          icon: Icons.layers_outlined,         color: const Color(0xFF6A1B9A)));
    if ((duty['zone'] ?? duty['zoneName'] ?? '').toString().isNotEmpty)
      items.add((label: duty['zone'] ?? duty['zoneName'] as String,
          icon: Icons.grid_view_outlined,       color: const Color(0xFF1565C0)));
    if ((duty['sector'] ?? duty['sectorName'] ?? '').toString().isNotEmpty)
      items.add((label: duty['sector'] ?? duty['sectorName'] as String,
          icon: Icons.view_module_outlined,     color: const Color(0xFF2E7D32)));
    if ((duty['gramPanchayat'] ?? duty['gpName'] ?? '').toString().isNotEmpty)
      items.add((label: duty['gramPanchayat'] ?? duty['gpName'] as String,
          icon: Icons.account_balance_outlined, color: const Color(0xFF6D4C41)));

    if (items.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.chevron_right, size: 11, color: _kSubtle)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: items[i].color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: items[i].color.withOpacity(0.2)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(items[i].icon, size: 9, color: items[i].color),
              const SizedBox(width: 3),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 80),
                child: Text(items[i].label, style: TextStyle(
                    color: items[i].color, fontSize: 9.5,
                    fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── District chips ────────────────────────────────────────────────────────────

class _DistrictChips extends StatelessWidget {
  final Map<String, dynamic> duty;
  const _DistrictChips({required this.duty});

  Widget _chip(IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.22))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: color), const SizedBox(width: 4),
      Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if ((duty['district'] as String?)?.isNotEmpty == true)
      chips.add(_chip(Icons.location_city_outlined, duty['district'] as String, _kDistrict));
    if ((duty['busNo'] as String?)?.isNotEmpty == true)
      chips.add(_chip(Icons.directions_bus_outlined, 'बस: ${duty['busNo']}', _kAccent));
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }
}

// ── Staff chips ───────────────────────────────────────────────────────────────

class _StaffChips extends StatelessWidget {
  final List<Map> staffList;
  const _StaffChips({required this.staffList});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6, runSpacing: 5,
    children: staffList.map((s) {
      final rank = s['rank'] as String? ?? s['user_rank'] as String? ?? '';
      final rc   = _rankColor(rank);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kBorder.withOpacity(0.4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
              blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7,
              decoration: BoxDecoration(color: rc, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 80),
            child: Text(s['name'] as String? ?? '',
                style: const TextStyle(color: _kDark, fontSize: 11,
                    fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          if ((s['pno'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(width: 4),
            Text('(${s['pno']})', style: TextStyle(color: rc, fontSize: 9.5)),
          ],
        ]),
      );
    }).toList(),
  );
}

class _StaffDivider extends StatelessWidget {
  final String label;
  const _StaffDivider({required this.label});
  @override
  Widget build(BuildContext context) => Column(children: [
    const SizedBox(height: 8),
    const Divider(height: 1, color: _kBorder),
    const SizedBox(height: 8),
    Row(children: [
      const Icon(Icons.people_outline, size: 12, color: _kSubtle),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: _kSubtle, fontSize: 10,
          fontWeight: FontWeight.w700)),
    ]),
    const SizedBox(height: 7),
  ]);
}

// ══════════════════════════════════════════════════════════════════════════════
//  LOADING / ERROR / EMPTY
// ══════════════════════════════════════════════════════════════════════════════

class _LoadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: _kPrimary, strokeWidth: 2.5,
          backgroundColor: _kPrimary.withOpacity(0.1)),
      const SizedBox(height: 14),
      const Text('लोड हो रहा है…',
          style: TextStyle(color: _kSubtle, fontSize: 13)),
    ]));
}

class _ErrorView extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72,
          decoration: BoxDecoration(color: _kError.withOpacity(0.08),
              shape: BoxShape.circle),
          child: const Icon(Icons.error_outline, size: 36, color: _kError)),
      const SizedBox(height: 16),
      const Text('डेटा लोड नहीं हो सका', style: TextStyle(
          color: _kDark, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(error, style: const TextStyle(color: _kSubtle, fontSize: 12),
          textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('दोबारा कोशिश करें'),
        style: ElevatedButton.styleFrom(backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
}

class _EmptyView extends StatelessWidget {
  final String filter, search;
  const _EmptyView({required this.filter, required this.search});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80,
          decoration: BoxDecoration(color: _kSubtle.withOpacity(0.08),
              shape: BoxShape.circle),
          child: Icon(Icons.history_rounded, size: 40,
              color: _kSubtle.withOpacity(0.4))),
      const SizedBox(height: 16),
      Text(
        search.isNotEmpty
            ? '"$search" नहीं मिला'
            : filter == 'all'
                ? 'कोई ड्यूटी रिकॉर्ड नहीं'
                : 'इस फ़िल्टर में कोई रिकॉर्ड नहीं',
        style: const TextStyle(color: _kSubtle, fontSize: 14,
            fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      const Text('फ़िल्टर बदलें या खोज हटाएं',
          style: TextStyle(color: _kSubtle, fontSize: 12)),
    ])));
}