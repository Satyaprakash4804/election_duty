import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';

// ── Palette ──────────────────────────────────────────────────────────────────
const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);
const kSuccess = Color(0xFF2D6A1E);

const List<Map<String, dynamic>> kBoothTiers = [
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

const List<Map<String, dynamic>> kSensitivities = [
  {'key': 'A++', 'hi': 'अति-अति संवेदनशील',    'color': Color(0xFF6C3483)},
  {'key': 'A',   'hi': 'अति संवेदनशील',         'color': Color(0xFFC0392B)},
  {'key': 'B',   'hi': 'संवेदनशील',              'color': Color(0xFFE67E22)},
  {'key': 'C',   'hi': 'सामान्य',               'color': Color(0xFF1A5276)},
];

// ══════════════════════════════════════════════════════════════════════════════
//  MANAK BOOTH REPORT PAGE
// ══════════════════════════════════════════════════════════════════════════════
class ManakBoothReportPage extends StatefulWidget {
  const ManakBoothReportPage({super.key});

  @override
  State<ManakBoothReportPage> createState() => _ManakBoothReportPageState();
}

class _ManakBoothReportPageState extends State<ManakBoothReportPage>
    with SingleTickerProviderStateMixin {

  final Map<String, List<Map<String, dynamic>>> _rules = {
    'A++': [], 'A': [], 'B': [], 'C': [],
  };

  final Map<String, Map<int, int>> _centerCounts = {
    'A++': {}, 'A': {}, 'B': {}, 'C': {},
  };

  String _districtName = '';
  bool _loading = true;
  late TabController _tabCtrl;
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(() => setState(() => _activeTab = _tabCtrl.index));
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Data Loading ─────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();

      final res = await ApiService.get('/admin/booth-rules', token: token);
      final data = res['data'] as Map<String, dynamic>? ?? {};
      for (final s in ['A++', 'A', 'B', 'C']) {
        _rules[s] = (data[s] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      try {
        final ccRes = await ApiService.get(
            '/admin/booth-rules/center-counts-by-type', token: token);
        final ccData = ccRes['data'] as Map<String, dynamic>? ?? {};

        for (final sens in ['A++', 'A', 'B', 'C']) {
          final sensData = ccData[sens] as Map<String, dynamic>? ?? {};
          final Map<int, int> counts = {};
          sensData.forEach((boothCountStr, centerCount) {
            final bc = int.tryParse(boothCountStr.toString()) ?? 0;
            if (bc >= 1 && bc <= 15) {
              counts[bc] = (centerCount as num).toInt();
            }
          });
          _centerCounts[sens] = counts;
        }
      } catch (e) {
        debugPrint('Center counts load failed: $e');
        try {
          final centersRes = await ApiService.get(
              '/admin/centers/all?limit=9999', token: token);
          final centers = (centersRes['data'] as List? ?? []);
          final Map<String, Map<int, int>> counts = {
            'A++': {}, 'A': {}, 'B': {}, 'C': {},
          };
          for (final c in centers) {
            final ct = (c['centerType'] ?? 'C') as String;
            final bc = ((c['boothCount'] ?? 1) as num).toInt().clamp(1, 15);
            if (counts.containsKey(ct)) {
              counts[ct]![bc] = (counts[ct]![bc] ?? 0) + 1;
            }
          }
          _centerCounts.addAll(counts);
        } catch (_) {}
      }

      try {
        final profileRes = await ApiService.get('/auth/me', token: token);
        _districtName = (profileRes['data']?['district'] ?? '') as String;
      } catch (_) {}

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('लोड विफल: $e'), backgroundColor: kError),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  Map<String, dynamic>? _ruleFor(String sens, int boothCount) {
    final list = _rules[sens] ?? [];
    try {
      return list.firstWhere(
        (r) => ((r['boothCount'] ?? r['booth_count'] ?? 0) as num).toInt() == boothCount,
      );
    } catch (_) {
      return null;
    }
  }

  int _get(Map<String, dynamic>? r, String key, [String? alt]) {
    if (r == null) return 0;
    return ((r[key] ?? (alt != null ? r[alt] : null) ?? 0) as num).toInt();
  }

  double _getPAC(Map<String, dynamic>? r) {
    if (r == null) return 0;
    return ((r['pacCount'] ?? r['pac_count'] ?? 0) as num).toDouble();
  }

  bool _hasAny(Map<String, dynamic>? r) {
    if (r == null) return false;
    return _get(r, 'siArmedCount', 'si_armed_count') > 0 ||
        _get(r, 'siUnarmedCount', 'si_unarmed_count') > 0 ||
        _get(r, 'hcArmedCount', 'hc_armed_count') > 0 ||
        _get(r, 'hcUnarmedCount', 'hc_unarmed_count') > 0 ||
        _get(r, 'constArmedCount', 'const_armed_count') > 0 ||
        _get(r, 'constUnarmedCount', 'const_unarmed_count') > 0 ||
        _get(r, 'auxArmedCount', 'aux_armed_count') > 0 ||
        _get(r, 'auxUnarmedCount', 'aux_unarmed_count') > 0 ||
        _getPAC(r) > 0;
  }

  int _filledCount(String sens) {
    int count = 0;
    for (int i = 1; i <= 15; i++) {
      if (_hasAny(_ruleFor(sens, i))) count++;
    }
    return count;
  }

  String _fmtPac(double v) =>
      v == 0 ? '0' : (v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1));

  // ── PDF Export ───────────────────────────────────────────────────────────
  Future<void> _printReport() async {
    final doc  = pw.Document();
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();

    for (final s in kSensitivities) {
      final sensKey  = s['key'] as String;
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
              style: pw.TextStyle(font: bold, fontSize: 8),
            ),
            if (_districtName.isNotEmpty)
              pw.Text('जनपद: $_districtName',
                  style: pw.TextStyle(font: font, fontSize: 8)),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: pw.BoxDecoration(
                color: pdfColor,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                '${s['key']} — ${s['hi']} श्रेणी',
                style: pw.TextStyle(
                    font: bold, fontSize: 8, color: PdfColors.white),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(height: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 4),
          ],
        ),
        build: (_) => [_buildPdfTable(sensKey, pdfColor, font, bold)],
      ));
    }

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'manak_booth_report',
    );
  }

  pw.Widget _buildPdfTable(
      String sens,
      PdfColor color,
      pw.Font font,
      pw.Font bold) {

    pw.TextStyle hStyle() => pw.TextStyle(
        font: bold, fontSize: 6, color: PdfColors.black);
    pw.TextStyle cStyle()   => pw.TextStyle(font: font, fontSize: 6.5);
    pw.TextStyle zStyle()   => pw.TextStyle(font: font, fontSize: 6.5, color: PdfColors.grey500);
    pw.TextStyle bStyle()   => pw.TextStyle(font: bold, fontSize: 6.5);

    String fmt(int v) => '$v';
    String fmtP(double v) => _fmtPac(v);

    int tCenters = 0;
    int tSI_A=0, tHC_A=0, tHC_U=0, tC_A=0, tC_U=0, tAx_A=0, tAx_U=0;
    double tPAC = 0;

    final rows = <pw.TableRow>[];

    // ── Header Row ──────────────────────────────────────────────────────
    // 17 columns: 3 fixed + 5 scale + 9 deployed
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EDE0C4')),
      children: [
        _ph('क्र.स.', hStyle()),
        _ph('मतदान केन्द्र का प्रकार', hStyle(), left: true),
        _ph('पोलिंग\nसेन्टर\nसंख्या', hStyle()),
        // Scale (5)
        _ph('SI', hStyle()), _ph('HC', hStyle()),
        _ph('Const.', hStyle()), _ph('Aux.\nForce', hStyle()), _ph('PAC\n(section)', hStyle()),
        // Deployed (9)
        _ph('SI\nसश°', hStyle()), _ph('HC', hStyle()),
        _ph('HC\nसश°', hStyle()), _ph('HC\nनिः°', hStyle()),
        _ph('Const.', hStyle()), _ph('Const.\nसश°', hStyle()), _ph('Const.\nनिः°', hStyle()),
        _ph('Aux.\nForce', hStyle()), _ph('PAC\n(section)', hStyle()),
      ],
    ));

    // ── Data Rows ─────────────────────────────────────────────────────────
    for (int i = 1; i <= 15; i++) {
      final r       = _ruleFor(sens, i);
      final centers = _centerCounts[sens]?[i] ?? 0;

      final si_a = _get(r, 'siArmedCount',     'si_armed_count');
      final si_u = _get(r, 'siUnarmedCount',   'si_unarmed_count');
      final hc_a = _get(r, 'hcArmedCount',     'hc_armed_count');
      final hc_u = _get(r, 'hcUnarmedCount',   'hc_unarmed_count');
      final c_a  = _get(r, 'constArmedCount',  'const_armed_count');
      final c_u  = _get(r, 'constUnarmedCount','const_unarmed_count');
      final ax_a = _get(r, 'auxArmedCount',    'aux_armed_count');
      final ax_u = _get(r, 'auxUnarmedCount',  'aux_unarmed_count');
      final pac  = _getPAC(r);

      final M_si_a = centers * si_a;
      final M_hc_a = centers * hc_a; final M_hc_u = centers * hc_u;
      final M_c_a  = centers * c_a;  final M_c_u  = centers * c_u;
      final M_ax_a = centers * ax_a; final M_ax_u = centers * ax_u;
      final M_pac  = centers * pac;

      tCenters += centers;
      tSI_A += M_si_a;
      tHC_A += M_hc_a; tHC_U += M_hc_u;
      tC_A  += M_c_a;  tC_U  += M_c_u;
      tAx_A += M_ax_a; tAx_U += M_ax_u;
      tPAC  += M_pac;

      pw.TextStyle ns(int v) => v > 0 ? bStyle() : zStyle();

      rows.add(pw.TableRow(
        decoration: i % 2 == 0
            ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFAF5EB))
            : null,
        children: [
          _ph('$i', cStyle()),
          _ph(kBoothTiers[i - 1]['label'], cStyle(), left: true),
          _ph(centers > 0 ? '$centers' : '—', ns(centers)),
          // Scale
          _ph(fmt(si_a + si_u), ns(si_a + si_u)),
          _ph(fmt(hc_a + hc_u), ns(hc_a + hc_u)),
          _ph(fmt(c_a  + c_u),  ns(c_a + c_u)),
          _ph(fmt(ax_a + ax_u), ns(ax_a + ax_u)),
          _ph(fmtP(pac),        ns((pac * 10).toInt())),
          // Deployed
          _ph(fmt(M_si_a),           ns(M_si_a)),
          _ph(fmt(M_hc_a + M_hc_u), ns(M_hc_a + M_hc_u)),
          _ph(fmt(M_hc_a),           ns(M_hc_a)),
          _ph(fmt(M_hc_u),           ns(M_hc_u)),
          _ph(fmt(M_c_a + M_c_u),   ns(M_c_a + M_c_u)),
          _ph(fmt(M_c_a),            ns(M_c_a)),
          _ph(fmt(M_c_u),            ns(M_c_u)),
          _ph(fmt(M_ax_a + M_ax_u), ns(M_ax_a + M_ax_u)),
          _ph(fmtP(M_pac),           ns((M_pac * 10).toInt())),
        ],
      ));
    }

    // ── Total Row ─────────────────────────────────────────────────────────
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#D5F5E3')),
      children: [
        _ph('', hStyle()),
        _ph('योग', hStyle(), left: true),
        _ph('$tCenters', hStyle()),
        // Scale totals (sum of per-row manak, not deployed)
        _ph('', hStyle()), _ph('', hStyle()), _ph('', hStyle()),
        _ph('', hStyle()), _ph('', hStyle()),
        // Deployed totals
        _ph('$tSI_A',          hStyle()),
        _ph('${tHC_A+tHC_U}', hStyle()),
        _ph('$tHC_A',          hStyle()),
        _ph('$tHC_U',          hStyle()),
        _ph('${tC_A+tC_U}',   hStyle()),
        _ph('$tC_A',           hStyle()),
        _ph('$tC_U',           hStyle()),
        _ph('${tAx_A+tAx_U}', hStyle()),
        _ph(_fmtPac(tPAC),    hStyle()),
      ],
    ));

    // Column widths: 3 fixed + 5 scale + 9 deployed = 17 cols
    return pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(18),   // क्र.स.
        1: const pw.FixedColumnWidth(60),   // मतदान केन्द्र का प्रकार
        2: const pw.FixedColumnWidth(26),   // संख्या
        // Scale
        3: const pw.FixedColumnWidth(22),
        4: const pw.FixedColumnWidth(22),
        5: const pw.FixedColumnWidth(24),
        6: const pw.FixedColumnWidth(26),
        7: const pw.FixedColumnWidth(28),
        // Deployed
        8:  const pw.FixedColumnWidth(24),
        9:  const pw.FixedColumnWidth(24),
        10: const pw.FixedColumnWidth(26),
        11: const pw.FixedColumnWidth(26),
        12: const pw.FixedColumnWidth(26),
        13: const pw.FixedColumnWidth(28),
        14: const pw.FixedColumnWidth(28),
        15: const pw.FixedColumnWidth(28),
        16: const pw.FixedColumnWidth(28),
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(width: 0.3, color: PdfColors.grey400),
        verticalInside:   pw.BorderSide(width: 0.3, color: PdfColors.grey400),
        left:   pw.BorderSide(width: 0.5, color: PdfColors.grey600),
        right:  pw.BorderSide(width: 0.5, color: PdfColors.grey600),
        top:    pw.BorderSide(width: 0.5, color: PdfColors.grey600),
        bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey600),
      ),
      children: rows,
    );
  }

  pw.Widget _ph(String text, pw.TextStyle style, {bool left = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2.5),
        child: pw.Text(text,
            style: style,
            textAlign: left ? pw.TextAlign.left : pw.TextAlign.center),
      );

  // ── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isNarrow = screenW < 600;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'मानक बूथ रिपोर्ट',
              style: TextStyle(
                  fontSize: isNarrow ? 14 : 16,
                  fontWeight: FontWeight.w800),
            ),
            Text(
              'बूथ-वार पुलिस व्यवस्थापन'
              '${_districtName.isNotEmpty ? ' — $_districtName' : ''}',
              style: TextStyle(
                  fontSize: isNarrow ? 9 : 10,
                  color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded, size: 20),
            tooltip: 'Print / PDF',
            onPressed: _loading ? null : _printReport,
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: TextStyle(
              fontSize: isNarrow ? 11 : 12,
              fontWeight: FontWeight.w700),
          unselectedLabelStyle: TextStyle(fontSize: isNarrow ? 11 : 12),
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'सभी'),
            Tab(text: 'A++ अति-अति'),
            Tab(text: 'A अति'),
            Tab(text: 'B संवेदनशील'),
            Tab(text: 'C सामान्य'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: kPrimary, strokeWidth: 2.5))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _AllSensitivityView(
                    rules: _rules,
                    centerCounts: _centerCounts,
                    ruleFor: _ruleFor,
                    get: _get,
                    getPAC: _getPAC,
                    hasAny: _hasAny,
                    filledCount: _filledCount,
                    districtName: _districtName),
                ...kSensitivities.map((s) => _SingleSensView(
                      sensKey: s['key'] as String,
                      sensHindi: s['hi'] as String,
                      color: s['color'] as Color,
                      rules: _rules[s['key'] as String] ?? [],
                      centerCounts: _centerCounts[s['key'] as String] ?? {},
                      ruleFor: (bc) => _ruleFor(s['key'] as String, bc),
                      get: _get,
                      getPAC: _getPAC,
                      hasAny: _hasAny,
                      filledCount: _filledCount(s['key'] as String),
                    )),
              ],
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ALL SENSITIVITY VIEW
// ══════════════════════════════════════════════════════════════════════════════
class _AllSensitivityView extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> rules;
  final Map<String, Map<int, int>> centerCounts;
  final Map<String, dynamic>? Function(String, int) ruleFor;
  final int Function(Map<String, dynamic>?, String, [String?]) get;
  final double Function(Map<String, dynamic>?) getPAC;
  final bool Function(Map<String, dynamic>?) hasAny;
  final int Function(String) filledCount;
  final String districtName;

  const _AllSensitivityView({
    required this.rules, required this.centerCounts, required this.ruleFor,
    required this.get, required this.getPAC, required this.hasAny,
    required this.filledCount, required this.districtName,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {},
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        itemCount: kSensitivities.length,
        itemBuilder: (_, i) {
          final s  = kSensitivities[i];
          final sk = s['key'] as String;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _SensBlock(
              sensKey: sk,
              sensHindi: s['hi'] as String,
              color: s['color'] as Color,
              rules: rules[sk] ?? [],
              centerCounts: centerCounts[sk] ?? {},
              ruleFor: (bc) => ruleFor(sk, bc),
              get: get, getPAC: getPAC, hasAny: hasAny,
              filledCount: filledCount(sk),
              districtName: districtName,
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SINGLE SENSITIVITY VIEW
// ══════════════════════════════════════════════════════════════════════════════
class _SingleSensView extends StatelessWidget {
  final String sensKey, sensHindi;
  final Color color;
  final List<Map<String, dynamic>> rules;
  final Map<int, int> centerCounts;
  final Map<String, dynamic>? Function(int) ruleFor;
  final int Function(Map<String, dynamic>?, String, [String?]) get;
  final double Function(Map<String, dynamic>?) getPAC;
  final bool Function(Map<String, dynamic>?) hasAny;
  final int filledCount;

  const _SingleSensView({
    required this.sensKey, required this.sensHindi, required this.color,
    required this.rules, required this.centerCounts, required this.ruleFor,
    required this.get, required this.getPAC, required this.hasAny,
    required this.filledCount,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
      children: [
        _SensBlock(
          sensKey: sensKey, sensHindi: sensHindi, color: color,
          rules: rules, centerCounts: centerCounts,
          ruleFor: ruleFor, get: get, getPAC: getPAC, hasAny: hasAny,
          filledCount: filledCount, districtName: '',
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SENSITIVITY BLOCK
// ══════════════════════════════════════════════════════════════════════════════
class _SensBlock extends StatelessWidget {
  final String sensKey, sensHindi, districtName;
  final Color color;
  final List<Map<String, dynamic>> rules;
  final Map<int, int> centerCounts;
  final Map<String, dynamic>? Function(int) ruleFor;
  final int Function(Map<String, dynamic>?, String, [String?]) get;
  final double Function(Map<String, dynamic>?) getPAC;
  final bool Function(Map<String, dynamic>?) hasAny;
  final int filledCount;

  const _SensBlock({
    required this.sensKey, required this.sensHindi, required this.color,
    required this.rules, required this.centerCounts, required this.ruleFor,
    required this.get, required this.getPAC, required this.hasAny,
    required this.filledCount, required this.districtName,
  });

  @override
  Widget build(BuildContext context) {
    final isSet = filledCount > 0;

    int tCenters = 0, tSI = 0, tHC = 0, tC = 0, tAx = 0;
    double tPAC = 0;
    for (int i = 1; i <= 15; i++) {
      final r = ruleFor(i);
      final c = centerCounts[i] ?? 0;
      tCenters += c;
      tSI += c * (get(r, 'siArmedCount', 'si_armed_count') + get(r, 'siUnarmedCount', 'si_unarmed_count'));
      tHC += c * (get(r, 'hcArmedCount', 'hc_armed_count') + get(r, 'hcUnarmedCount', 'hc_unarmed_count'));
      tC  += c * (get(r, 'constArmedCount', 'const_armed_count') + get(r, 'constUnarmedCount', 'const_unarmed_count'));
      tAx += c * (get(r, 'auxArmedCount', 'aux_armed_count') + get(r, 'auxUnarmedCount', 'aux_unarmed_count'));
      tPAC += c * getPAC(r);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: kSurface.withOpacity(0.6),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                  bottom: BorderSide(color: kBorder.withOpacity(0.3))),
            ),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(sensKey,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$sensHindi श्रेणी',
                        style: const TextStyle(
                            color: kDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                    Row(children: [
                      Text('$filledCount/15 मानक सेट  •  ',
                          style: const TextStyle(
                              color: kSubtle, fontSize: 10)),
                      Text('$tCenters केन्द्र',
                          style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ],
                ),
              ),
              _StatusPill(isSet: isSet, color: color),
            ]),
          ),

          // ── Summary chips ────────────────────────────────────────────────
          if (isSet)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: color.withOpacity(0.04),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _SummaryChip('केन्द्र', '$tCenters',
                      const Color(0xFF555555)),
                  _SummaryChip('SI', '$tSI', color),
                  _SummaryChip('HC', '$tHC', color),
                  _SummaryChip('Const.', '$tC', color),
                  _SummaryChip('Aux.', '$tAx',
                      const Color(0xFFE65100)),
                  if (tPAC > 0)
                    _SummaryChip(
                        'PAC',
                        tPAC % 1 == 0
                            ? '${tPAC.toInt()}'
                            : tPAC.toStringAsFixed(1),
                        const Color(0xFF00695C)),
                  _SummaryChip(
                      'कुल बल', '${tSI + tHC + tC + tAx}', kSuccess),
                ]),
              ),
            ),

          // ── Table ────────────────────────────────────────────────────────
          if (!isSet)
            _EmptyState(
                sensKey: sensKey,
                sensHindi: sensHindi,
                color: color)
          else
            _ReportTable(
              sensKey: sensKey,
              color: color,
              centerCounts: centerCounts,
              ruleFor: ruleFor,
              get: get,
              getPAC: getPAC,
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  REPORT TABLE
//
//  Columns (Per Centre Manak section REMOVED):
//  क्र.स | मतदान केन्द्र का प्रकार | संख्या पोलिंग सेन्टर |
//  --- Scale (5 cols): SI | HC | Const | Aux.Force | PAC ---
//  --- Deployed total (9 cols): SI सश | HC | HC सश | HC निः |
//                                Const | Const सश | Const निः | Aux.Force | PAC ---
//  Total: 3 + 5 + 9 = 17 columns
// ══════════════════════════════════════════════════════════════════════════════
class _ReportTable extends StatelessWidget {
  final String sensKey;
  final Color color;
  final Map<int, int> centerCounts;
  final Map<String, dynamic>? Function(int) ruleFor;
  final int Function(Map<String, dynamic>?, String, [String?]) get;
  final double Function(Map<String, dynamic>?) getPAC;

  const _ReportTable({
    required this.sensKey, required this.color,
    required this.centerCounts, required this.ruleFor,
    required this.get, required this.getPAC,
  });

  String _fp(double v) =>
      v == 0 ? '0' : (v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1));

  @override
  Widget build(BuildContext context) {
    int tCenters = 0;
    int mSI_A=0, mSI_U=0, mHC_A=0, mHC_U=0;
    int mC_A=0,  mC_U=0,  mAx_A=0, mAx_U=0;
    double mPAC = 0;
    int tSI_A=0, tHC_A=0, tHC_U=0;
    int tC_A=0,  tC_U=0,  tAx_A=0, tAx_U=0;
    double tPAC = 0;

    final dataRows = <_RowData>[];
    for (int i = 1; i <= 15; i++) {
      final r = ruleFor(i);
      final c = centerCounts[i] ?? 0;
      final si_a = get(r, 'siArmedCount',     'si_armed_count');
      final si_u = get(r, 'siUnarmedCount',   'si_unarmed_count');
      final hc_a = get(r, 'hcArmedCount',     'hc_armed_count');
      final hc_u = get(r, 'hcUnarmedCount',   'hc_unarmed_count');
      final c_a  = get(r, 'constArmedCount',  'const_armed_count');
      final c_u  = get(r, 'constUnarmedCount','const_unarmed_count');
      final ax_a = get(r, 'auxArmedCount',    'aux_armed_count');
      final ax_u = get(r, 'auxUnarmedCount',  'aux_unarmed_count');
      final pac  = getPAC(r);

      tCenters += c;
      mSI_A += si_a; mSI_U += si_u;
      mHC_A += hc_a; mHC_U += hc_u;
      mC_A  += c_a;  mC_U  += c_u;
      mAx_A += ax_a; mAx_U += ax_u;
      mPAC  += pac;
      tSI_A += c * si_a;
      tHC_A += c * hc_a; tHC_U += c * hc_u;
      tC_A  += c * c_a;  tC_U  += c * c_u;
      tAx_A += c * ax_a; tAx_U += c * ax_u;
      tPAC  += c * pac;

      dataRows.add(_RowData(
        boothNo: i,
        label: kBoothTiers[i - 1]['label'],
        centers: c,
        si_a: si_a, si_u: si_u,
        hc_a: hc_a, hc_u: hc_u,
        c_a: c_a,   c_u: c_u,
        ax_a: ax_a, ax_u: ax_u,
        pac: pac,
      ));
    }

    // 17 columns: 0=क्र.स., 1=label, 2=centers,
    // 3-7=scale, 8-16=deployed
    const Map<int, TableColumnWidth> colWidths = {
      0: FixedColumnWidth(28),   // क्र.स.
      1: FixedColumnWidth(90),   // मतदान केन्द्र का प्रकार
      2: FixedColumnWidth(42),   // संख्या
      // Scale (5)
      3: FixedColumnWidth(30), 4: FixedColumnWidth(30),
      5: FixedColumnWidth(34), 6: FixedColumnWidth(36), 7: FixedColumnWidth(34),
      // Deployed (9)
      8:  FixedColumnWidth(32), 9:  FixedColumnWidth(34),
      10: FixedColumnWidth(34), 11: FixedColumnWidth(34),
      12: FixedColumnWidth(34), 13: FixedColumnWidth(36), 14: FixedColumnWidth(36),
      15: FixedColumnWidth(38), 16: FixedColumnWidth(34),
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 760),
        child: Table(
          columnWidths: colWidths,
          border:
              TableBorder.all(color: kBorder.withOpacity(0.25), width: 0.5),
          children: [
            // ── Group header row ─────────────────────────────────────────
            TableRow(
              decoration:
                  BoxDecoration(color: color.withOpacity(0.10)),
              children: [
                _TH(''), _TH('', alignLeft: true), _TH(''),
                // Scale group label (spans 5)
                _TH2('Scale', color: color, bold: true),
                _TH(''), _TH(''), _TH(''), _TH(''),
                // Deployed group label (spans 9)
                _TH2('मानक के अनुसार व्यवस्थापित पुलिस बल (कुल)',
                    color: color, bold: true),
                _TH(''), _TH(''), _TH(''),
                _TH(''), _TH(''), _TH(''), _TH(''), _TH(''),
              ],
            ),

            // ── Column headers ────────────────────────────────────────────
            TableRow(
              decoration: const BoxDecoration(color: kSurface),
              children: [
                _TH('क्र.\nस.'),
                _TH('मतदान\nकेन्द्र का प्रकार', alignLeft: true),
                _TH('पोलिंग\nसेन्टर\nसंख्या'),
                // Scale
                _TH('SI'), _TH('HC'),
                _TH('Const.'), _TH('Aux.\nForce'), _TH('PAC\n(sec.)'),
                // Deployed
                _TH('SI\nसश°'), _TH('HC'),
                _TH('HC\nसश°'), _TH('HC\nनिः°'),
                _TH('Const.'), _TH('Const.\nसश°'), _TH('Const.\nनिः°'),
                _TH('Aux.\nForce'), _TH('PAC\n(sec.)'),
              ],
            ),

            // ── Data rows ─────────────────────────────────────────────────
            ...dataRows.asMap().entries.map((e) {
              final row    = e.value;
              final isEven = e.key % 2 == 1;
              final bg     = isEven ? kBg.withOpacity(0.4) : Colors.white;
              final hC     = row.centers > 0;

              return TableRow(
                decoration: BoxDecoration(color: bg),
                children: [
                  _TD(row.boothNo < 15 ? '${row.boothNo}' : '15+',
                      center: true),
                  _TD(row.label, alignLeft: true),
                  _TDc(row.centers > 0 ? '${row.centers}' : '—',
                      center: true,
                      color: hC ? color : kSubtle.withOpacity(0.4),
                      bold: hC),
                  // Scale
                  _TD('${row.si_a + row.si_u}', center: true),
                  _TD('${row.hc_a + row.hc_u}', center: true),
                  _TD('${row.c_a  + row.c_u}',  center: true),
                  _TD('${row.ax_a + row.ax_u}',  center: true),
                  _TD(_fp(row.pac),              center: true),
                  // Deployed
                  _TDn(row.centers * row.si_a),
                  _TDn(row.centers * (row.hc_a + row.hc_u)),
                  _TDn(row.centers * row.hc_a),
                  _TDn(row.centers * row.hc_u),
                  _TDn(row.centers * (row.c_a + row.c_u)),
                  _TDn(row.centers * row.c_a),
                  _TDn(row.centers * row.c_u),
                  _TDn(row.centers * (row.ax_a + row.ax_u)),
                  _TD(_fp(row.centers * row.pac),
                      center: true,
                      bold: row.centers * row.pac > 0),
                ],
              );
            }),

            // ── Total row ─────────────────────────────────────────────────
            TableRow(
              decoration:
                  BoxDecoration(color: color.withOpacity(0.09)),
              children: [
                _TD('', center: true),
                _TD('योग', alignLeft: true, bold: true),
                _TDc('$tCenters',
                    center: true, color: color, bold: true),
                // Scale totals (sum of manak, not deployed)
                _TD('${mSI_A+mSI_U}', center: true, bold: true),
                _TD('${mHC_A+mHC_U}', center: true, bold: true),
                _TD('${mC_A+mC_U}',   center: true, bold: true),
                _TD('${mAx_A+mAx_U}', center: true, bold: true),
                _TD(_fp(mPAC),         center: true, bold: true),
                // Deployed totals
                _TD('$tSI_A',          center: true, bold: true),
                _TD('${tHC_A+tHC_U}', center: true, bold: true),
                _TD('$tHC_A',          center: true, bold: true),
                _TD('$tHC_U',          center: true, bold: true),
                _TD('${tC_A+tC_U}',   center: true, bold: true),
                _TD('$tC_A',           center: true, bold: true),
                _TD('$tC_U',           center: true, bold: true),
                _TD('${tAx_A+tAx_U}', center: true, bold: true),
                _TD(_fp(tPAC),         center: true, bold: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Row data ──────────────────────────────────────────────────────────────────
class _RowData {
  final int boothNo, centers, si_a, si_u, hc_a, hc_u, c_a, c_u, ax_a, ax_u;
  final double pac;
  final String label;
  const _RowData({
    required this.boothNo, required this.label, required this.centers,
    required this.si_a, required this.si_u,
    required this.hc_a, required this.hc_u,
    required this.c_a,  required this.c_u,
    required this.ax_a, required this.ax_u,
    required this.pac,
  });
}

// ── Table cell helpers ────────────────────────────────────────────────────────
Widget _TH(String text, {bool alignLeft = false}) => TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Text(text,
            textAlign:
                alignLeft ? TextAlign.left : TextAlign.center,
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: kDark,
                height: 1.2)),
      ),
    );

Widget _TH2(String text,
        {Color? color, bool bold = false}) =>
    TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Text(text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 8,
                fontWeight:
                    bold ? FontWeight.w800 : FontWeight.w600,
                color: color ?? kDark,
                height: 1.2)),
      ),
    );

Widget _TD(String text,
        {bool center = false,
        bool bold = false,
        bool alignLeft = false}) =>
    TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Text(text,
            textAlign: center
                ? TextAlign.center
                : (alignLeft ? TextAlign.left : TextAlign.center),
            style: TextStyle(
                fontSize: 11,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w400,
                color: bold ? kDark : kDark.withOpacity(0.8),
                height: 1.2)),
      ),
    );

Widget _TDc(String text,
        {bool center = false, Color? color, bool bold = false}) =>
    TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Text(text,
            textAlign:
                center ? TextAlign.center : TextAlign.left,
            style: TextStyle(
                fontSize: 11,
                fontWeight:
                    bold ? FontWeight.w800 : FontWeight.w400,
                color: color ?? kDark,
                height: 1.2)),
      ),
    );

Widget _TDn(int v) => TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Text('$v',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                fontWeight:
                    v > 0 ? FontWeight.w700 : FontWeight.w400,
                color: v > 0
                    ? kDark
                    : kSubtle.withOpacity(0.4),
                height: 1.2)),
      ),
    );

// ── Status pill ───────────────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final bool isSet;
  final Color color;
  const _StatusPill({required this.isSet, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSet
              ? kSuccess.withOpacity(0.1)
              : kError.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSet
                  ? kSuccess.withOpacity(0.35)
                  : kError.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              isSet
                  ? Icons.check_circle_rounded
                  : Icons.pending_outlined,
              size: 11,
              color: isSet ? kSuccess : kError),
          const SizedBox(width: 4),
          Text(isSet ? 'सेट' : 'अधूरा',
              style: TextStyle(
                  color: isSet ? kSuccess : kError,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

// ── Summary chip ──────────────────────────────────────────────────────────────
class _SummaryChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SummaryChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ',
              style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900)),
        ]),
      );
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String sensKey, sensHindi;
  final Color color;
  const _EmptyState(
      {required this.sensKey,
      required this.sensHindi,
      required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(children: [
          Icon(Icons.table_chart_outlined,
              size: 36, color: color.withOpacity(0.3)),
          const SizedBox(height: 10),
          Text(
              '$sensHindi ($sensKey) के लिए कोई मानक सेट नहीं है।',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: kSubtle,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('डैशबोर्ड से मानक सेट करें।',
              style: TextStyle(color: kSubtle, fontSize: 11)),
        ]),
      );
}