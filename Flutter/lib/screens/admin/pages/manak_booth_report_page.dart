import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  PALETTE
// ══════════════════════════════════════════════════════════════════════════════
const _kBg      = Color(0xFFFDF6E3);
const _kSurface = Color(0xFFF5E6C8);
const _kDark    = Color(0xFF4A3000);
const _kSubtle  = Color(0xFFAA8844);
const _kBorder  = Color(0xFFD4A843);

const _kColorApp = Color(0xFF6A1B9A); // A++
const _kColorA   = Color(0xFFC62828); // A
const _kColorB   = Color(0xFF1565C0); // B
const _kColorC   = Color(0xFF2E7D32); // C

// ══════════════════════════════════════════════════════════════════════════════
//  MODEL
// ══════════════════════════════════════════════════════════════════════════════
class _Row {
  final int    boothCount;
  final int    centerCount;

  // Scale (per-centre values from booth_rules)
  final int    scaleSi;
  final int    scaleHc;
  final int    scaleConst;
  final int    scaleAux;
  final double scalePac;

  // Raw armed/unarmed splits (needed for computed totals)
  final int _siA, _hcA, _hcU, _coA, _coU, _auxA;

  // Computed totals (centerCount × each field)
  int    get totSiArmed     => centerCount * _siA;
  int    get totHc          => centerCount * scaleHc;
  int    get totHcArmed     => centerCount * _hcA;
  int    get totHcUnarmed   => centerCount * _hcU;
  int    get totConst       => centerCount * scaleConst;
  int    get totConstArmed  => centerCount * _coA;
  int    get totConstUnarmed=> centerCount * _coU;
  int    get totAux         => centerCount * scaleAux;
  double get totPac         => centerCount * scalePac;

  _Row({
    required this.boothCount,
    required this.centerCount,
    required int siArmed,
    required int siUnarmed,
    required int hcArmed,
    required int hcUnarmed,
    required int constArmed,
    required int constUnarmed,
    required int auxArmed,
    required int auxUnarmed,
    required this.scalePac,
  })  : _siA  = siArmed,
        _hcA  = hcArmed,
        _hcU  = hcUnarmed,
        _coA  = constArmed,
        _coU  = constUnarmed,
        _auxA = auxArmed,
        scaleSi    = siArmed + siUnarmed,
        scaleHc    = hcArmed + hcUnarmed,
        scaleConst = constArmed + constUnarmed,
        scaleAux   = auxArmed + auxUnarmed;
}

// ══════════════════════════════════════════════════════════════════════════════
//  CONSTANTS
// ══════════════════════════════════════════════════════════════════════════════
const _sensOrder  = ['A++', 'A', 'B', 'C'];
const _sensHindi  = {
  'A++': 'अति संवेदनशील श्रेणी',
  'A':   'संवेदनशील श्रेणी',
  'B':   'साधारण संवेदनशील श्रेणी',
  'C':   'सामान्य श्रेणी',
};
const _sensColors = {
  'A++': _kColorApp,
  'A':   _kColorA,
  'B':   _kColorB,
  'C':   _kColorC,
};

// ══════════════════════════════════════════════════════════════════════════════
//  PAGE
// ══════════════════════════════════════════════════════════════════════════════
class ManakBoothReportPage extends StatefulWidget {
  const ManakBoothReportPage({super.key});
 
  @override
  State<ManakBoothReportPage> createState() => _ManakBoothReportPageState();
}

class _ManakBoothReportPageState extends State<ManakBoothReportPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tab;
  final Map<String, List<_Row>> _data = {
    'A++': [], 'A': [], 'B': [], 'C': [],
  };

  bool _loading  = true;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  // ── Data loading ────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();

      final rulesRes  = await ApiService.get('/admin/booth-rules', token: token);
      final rulesData = (rulesRes['data'] ?? rulesRes) as Map<String, dynamic>;

      // Centre counts endpoint:  GET /admin/booth-rules/center-counts
      // Returns { "A++": {"1":5,"2":3,...}, "A": {...}, ... }
      final cntRes  = await ApiService.get(
          '/admin/booth-rules/center-counts', token: token);
      final cntData = (cntRes['data'] ?? cntRes) as Map<String, dynamic>;

      for (final sens in _sensOrder) {
        final rules = (rulesData[sens] as List?)
                ?.cast<Map<String, dynamic>>() ?? [];
        final Map<int, Map<String, dynamic>> rMap = {
          for (final r in rules) (r['boothCount'] as int): r
        };

        final sensRaw = cntData[sens] as Map<String, dynamic>? ?? {};
        final Map<int, int> cnts = {};
        sensRaw.forEach((k, v) {
          cnts[int.tryParse(k) ?? 0] = (v as num).toInt();
        });

        _data[sens] = [
          for (int bc = 1; bc <= 15; bc++)
            _Row(
              boothCount:   bc,
              centerCount:  cnts[bc] ?? 0,
              siArmed:      _i(rMap[bc], 'siArmedCount'),
              siUnarmed:    _i(rMap[bc], 'siUnarmedCount'),
              hcArmed:      _i(rMap[bc], 'hcArmedCount'),
              hcUnarmed:    _i(rMap[bc], 'hcUnarmedCount'),
              constArmed:   _i(rMap[bc], 'constArmedCount'),
              constUnarmed: _i(rMap[bc], 'constUnarmedCount'),
              auxArmed:     _i(rMap[bc], 'auxArmedCount'),
              auxUnarmed:   _i(rMap[bc], 'auxUnarmedCount'),
              scalePac:     rMap[bc] == null
                  ? 0 : ((rMap[bc]!['pacCount'] ?? 0) as num).toDouble(),
            )
        ];
      }
    } catch (e) {
      if (mounted) showSnack(context, 'लोड विफल: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _i(Map<String, dynamic>? r, String k) =>
      r == null ? 0 : ((r[k] ?? 0) as num).toInt();

  // ── PDF ─────────────────────────────────────────────────────────────────────
  Future<Uint8List> _buildPdf({String? only}) async {
    final pdf    = pw.Document();
    final targets = only != null ? [only] : _sensOrder;

    for (final s in targets) {
      final rows  = _data[s] ?? [];
      final hindi = _sensHindi[s]!;
      final pc    = _pdfClr(_sensColors[s]!);

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(18),
        footer: (ctx) => _pdfFoot(ctx, s),
        build: (ctx) => [
          _pdfHdr(s, hindi, pc),
          pw.SizedBox(height: 8),
          _pdfTable(rows, pc),
        ],
      ));
    }
    return pdf.save();
  }

  PdfColor _pdfClr(Color c) =>
      PdfColor(c.red / 255, c.green / 255, c.blue / 255);

  pw.Widget _pdfHdr(String sens, String hindi, PdfColor c) {
    return pw.Column(children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('मानक रिपोर्ट — बूथ-वार पुलिस बल',
                style: pw.TextStyle(color: c, fontSize: 13,
                    fontWeight: pw.FontWeight.bold)),
            pw.Text('Manak Report — Booth-wise Police Force',
                style: const pw.TextStyle(
                    color: PdfColor(0.67, 0.53, 0.27), fontSize: 7.5)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: pw.BoxDecoration(
                  color: c, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Text(sens,
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 13,
                      fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 3),
            pw.Text(_now(),
                style: const pw.TextStyle(
                    color: PdfColor(0.67, 0.53, 0.27), fontSize: 7.5)),
          ]),
        ],
      ),
      pw.SizedBox(height: 5),
      pw.Divider(color: c, thickness: 1.5),
      pw.SizedBox(height: 4),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: pw.BoxDecoration(
            color: PdfColor(c.red, c.green, c.blue, 0.08),
            border: pw.Border(left: pw.BorderSide(color: c, width: 3))),
        child: pw.Text(hindi,
            style: pw.TextStyle(color: c, fontSize: 10,
                fontWeight: pw.FontWeight.bold)),
      ),
    ]);
  }

  pw.Widget _pdfTable(List<_Row> rows, PdfColor c) {
    // Column width map (17 columns total)
    const cw = {
      0:  pw.FixedColumnWidth(22),   // #
      1:  pw.FixedColumnWidth(52),   // Booth type
      2:  pw.FixedColumnWidth(36),   // Centre count
      3:  pw.FixedColumnWidth(26),   // Scale: SI
      4:  pw.FixedColumnWidth(26),   // Scale: HC
      5:  pw.FixedColumnWidth(28),   // Scale: Const.
      6:  pw.FixedColumnWidth(28),   // Scale: Aux.
      7:  pw.FixedColumnWidth(30),   // Scale: PAC
      8:  pw.FixedColumnWidth(28),   // Tot: SI सश
      9:  pw.FixedColumnWidth(24),   // Tot: HC
      10: pw.FixedColumnWidth(28),   // Tot: HC सश
      11: pw.FixedColumnWidth(28),   // Tot: HC निः
      12: pw.FixedColumnWidth(28),   // Tot: Const.
      13: pw.FixedColumnWidth(28),   // Tot: Con.सश
      14: pw.FixedColumnWidth(28),   // Tot: Con.निः
      15: pw.FixedColumnWidth(28),   // Tot: Aux.
      16: pw.FixedColumnWidth(30),   // Tot: PAC
    };

    const wh = PdfColors.white;
    const dk = PdfColor(0.29, 0.19, 0.0);
    const gr = PdfColor(0.95, 0.95, 0.97);

    final h  = pw.TextStyle(color: wh, fontSize: 7,
        fontWeight: pw.FontWeight.bold);
    final hs = pw.TextStyle(color: wh, fontSize: 6,
        fontWeight: pw.FontWeight.bold);
    final d  = pw.TextStyle(color: dk, fontSize: 7.5);
    final t  = pw.TextStyle(color: c,  fontSize: 7.5,
        fontWeight: pw.FontWeight.bold);
    final siStyle = pw.TextStyle(
        color: const PdfColor(0.42, 0.1, 0.6), fontSize: 7.5,
        fontWeight: pw.FontWeight.bold);

    pw.Widget hc(String v, pw.TextStyle s) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(v, style: s, textAlign: pw.TextAlign.center));

    pw.Widget dc(String v, pw.TextStyle s) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: pw.Text(v, style: s, textAlign: pw.TextAlign.center));

    String f(num v) => v == 0 ? '-' : '$v';
    String fd(double v) => v == 0
        ? '-' : (v == v.toInt() ? '${v.toInt()}' : '$v');

    // Totals accumulators
    int tCnt = 0, tSSi = 0, tSHc = 0, tSCo = 0, tSAx = 0;
    double tSPc = 0;
    int tSiA = 0, tHc = 0, tHcA = 0, tHcU = 0;
    int tCo = 0, tCoA = 0, tCoU = 0, tAx = 0;
    double tPc = 0;

    final tableRows = <pw.TableRow>[
      // ── Header row 1 ──────────────────────────────────────────────────────
      pw.TableRow(
        decoration: pw.BoxDecoration(color: c),
        children: [
          hc('#',        h),
          hc('मतदान\nकेन्द्र', hs),
          hc('संख्या\nसेन्टर', hs),
          // Scale span fake via colspan first cell
          pw.Container(
            decoration: pw.BoxDecoration(
                color: PdfColor(c.red * 0.85, c.green * 0.85, c.blue * 0.85),
                border: const pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.white, width: 0.5))),
            padding: const pw.EdgeInsets.all(3),
            child: pw.Center(child: pw.Text('Scale', style: h)),
          ),
          pw.SizedBox(), pw.SizedBox(), pw.SizedBox(), pw.SizedBox(),
          pw.Container(
            padding: const pw.EdgeInsets.all(3),
            child: pw.Center(child: pw.Text(
                'मानक के अनुसार व्यवस्थापित पुलिस बल का विवरण',
                style: hs, textAlign: pw.TextAlign.center)),
          ),
          pw.SizedBox(), pw.SizedBox(), pw.SizedBox(),
          pw.SizedBox(), pw.SizedBox(), pw.SizedBox(), pw.SizedBox(),
        ],
      ),
      // ── Header row 2 ──────────────────────────────────────────────────────
      pw.TableRow(
        decoration: pw.BoxDecoration(color: c),
        children: [
          hc('',             h),
          hc('',             h),
          hc('',             h),
          hc('SI',           h),
          hc('HC',           h),
          hc('Const.',       h),
          hc('Aux.\nForce',  hs),
          hc('PAC\n(sec.)',  hs),
          hc('SI\nसशस्त्र', hs),
          hc('HC',           h),
          hc('HC\nसशस्त्र', hs),
          hc('HC\nनिःशस्त्र', hs),
          hc('Const.',       h),
          hc('Const.\nसश्स्त्र', hs),
          hc('Const.\nनिःशस्त्र', hs),
          hc('Aux.\nForce',  hs),
          hc('PAC\n(sec.)',  hs),
        ],
      ),
    ];

    for (int i = 0; i < rows.length; i++) {
      final r  = rows[i];
      final bg = i.isEven ? wh : gr;
      final lbl = r.boothCount == 15
          ? '15 और\nउससे\nअधिक\nबूथ' : '${r.boothCount} बूथ';

      tCnt += r.centerCount;
      tSSi += r.scaleSi;  tSHc += r.scaleHc;
      tSCo += r.scaleConst; tSAx += r.scaleAux; tSPc += r.scalePac;
      tSiA += r.totSiArmed; tHc  += r.totHc;
      tHcA += r.totHcArmed; tHcU += r.totHcUnarmed;
      tCo  += r.totConst;   tCoA += r.totConstArmed;
      tCoU += r.totConstUnarmed; tAx += r.totAux; tPc += r.totPac;

      tableRows.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: bg),
        children: [
          dc('${i + 1}',          d),
          pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text(lbl, style: d)),
          dc(f(r.centerCount),    d),
          dc(f(r.scaleSi),        pw.TextStyle(color: c, fontSize: 7.5,
              fontWeight: pw.FontWeight.bold)),
          dc(f(r.scaleHc),        pw.TextStyle(color: c, fontSize: 7.5,
              fontWeight: pw.FontWeight.bold)),
          dc(f(r.scaleConst),     pw.TextStyle(color: c, fontSize: 7.5,
              fontWeight: pw.FontWeight.bold)),
          dc(f(r.scaleAux),       pw.TextStyle(color: c, fontSize: 7.5,
              fontWeight: pw.FontWeight.bold)),
          dc(fd(r.scalePac),      pw.TextStyle(color: c, fontSize: 7.5,
              fontWeight: pw.FontWeight.bold)),
          dc(f(r.totSiArmed),     siStyle),
          dc(f(r.totHc),          d),
          dc(f(r.totHcArmed),     d),
          dc(f(r.totHcUnarmed),   d),
          dc(f(r.totConst),       d),
          dc(f(r.totConstArmed),  d),
          dc(f(r.totConstUnarmed),d),
          dc(f(r.totAux),         d),
          dc(fd(r.totPac),        d),
        ],
      ));
    }

    // Totals row
    tableRows.add(pw.TableRow(
      decoration: pw.BoxDecoration(
          color: PdfColor(c.red, c.green, c.blue, 0.12)),
      children: [
        dc('',         t), 
        pw.Padding(padding: const pw.EdgeInsets.all(3),
            child: pw.Text('योग', style: t)),
        dc('$tCnt',    t),
        dc('$tSSi',    t), dc('$tSHc',  t),
        dc('$tSCo',    t), dc('$tSAx',  t), dc(fd(tSPc), t),
        dc('$tSiA',    t), dc('$tHc',   t),
        dc('$tHcA',    t), dc('$tHcU',  t),
        dc('$tCo',     t), dc('$tCoA',  t),
        dc('$tCoU',    t), dc('$tAx',   t), dc(fd(tPc),  t),
      ],
    ));

    return pw.Table(
      border: pw.TableBorder.all(
          color: PdfColor(c.red, c.green, c.blue, 0.4), width: 0.5),
      columnWidths: cw,
      children: tableRows,
    );
  }

  pw.Widget _pdfFoot(pw.Context ctx, String s) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 4),
    decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(
            color: PdfColor(0.67, 0.53, 0.27), width: 0.5))),
    child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('मानक रिपोर्ट — $s',
              style: const pw.TextStyle(
                  color: PdfColor(0.67, 0.53, 0.27), fontSize: 7)),
          pw.Text('पृष्ठ ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(
                  color: PdfColor(0.67, 0.53, 0.27), fontSize: 7)),
          pw.Text(_now(),
              style: const pw.TextStyle(
                  color: PdfColor(0.67, 0.53, 0.27), fontSize: 7)),
        ]),
  );

  String _now() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(n.day)}/${p(n.month)}/${n.year}  ${p(n.hour)}:${p(n.minute)}';
  }

  // ── Print helpers ────────────────────────────────────────────────────────────
  void _openSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrintSheet(
        onPrintAll:    () => _doPrint(null),
        onPreviewAll:  () => _doPreview(null),
        onPrintSens:   _doPrint,
        onPreviewSens: _doPreview,
      ),
    );
  }

  Future<void> _doPrint(String? s) async {
    setState(() => _printing = true);
    try {
      final b = await _buildPdf(only: s);
      await Printing.layoutPdf(onLayout: (_) async => b);
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _doPreview(String? s) async {
    setState(() => _printing = true);
    try {
      final b = await _buildPdf(only: s);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PdfPreviewPage(
            title: s != null ? '$s मानक रिपोर्ट' : 'सम्पूर्ण मानक रिपोर्ट',
            bytes: b,
          )));
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('मानक रिपोर्ट',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text('बूथ-वार पुलिस बल विवरण',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: _printing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print_outlined, size: 20),
            tooltip: 'Print / Preview',
            onPressed: (_loading || _printing) ? null : _openSheet,
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: _sensOrder.map((s) => Tab(text: s)).toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kDark))
          : TabBarView(
              controller: _tab,
              children: _sensOrder
                  .map((s) => _SensTable(
                        rows:  _data[s] ?? [],
                        color: _sensColors[s]!,
                        hindi: _sensHindi[s]!,
                        sens:  s,
                      ))
                  .toList(),
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SENSITIVITY TABLE WIDGET
// ══════════════════════════════════════════════════════════════════════════════
class _SensTable extends StatelessWidget {
  final List<_Row> rows;
  final Color      color;
  final String     hindi, sens;

  const _SensTable({
    required this.rows, required this.color,
    required this.hindi, required this.sens,
  });

  // Fixed column widths
  static const double _w0  = 36;   // #
  static const double _w1  = 92;   // Booth label
  static const double _w2  = 70;   // Centre count
  static const double _wSc = 44;   // Scale columns (5)
  static const double _wTt = 56;   // Total columns (9)

  @override
  Widget build(BuildContext context) {
    String f(int v) => v == 0 ? '-' : '$v';
    String fd(double v) => v == 0 ? '-' : (v == v.toInt() ? '${v.toInt()}' : '$v');

    // Accumulate totals
    int tCnt = 0, tSSi = 0, tSHc = 0, tSCo = 0, tSAx = 0;
    double tSPc = 0;
    int tSiA = 0, tHc = 0, tHcA = 0, tHcU = 0;
    int tCo = 0, tCoA = 0, tCoU = 0, tAx = 0;
    double tPc = 0;
    for (final r in rows) {
      tCnt += r.centerCount;
      tSSi += r.scaleSi;    tSHc += r.scaleHc;
      tSCo += r.scaleConst; tSAx += r.scaleAux; tSPc += r.scalePac;
      tSiA += r.totSiArmed; tHc  += r.totHc;
      tHcA += r.totHcArmed; tHcU += r.totHcUnarmed;
      tCo  += r.totConst;   tCoA += r.totConstArmed;
      tCoU += r.totConstUnarmed; tAx += r.totAux; tPc += r.totPac;
    }

    return Column(children: [
      // ── Category label strip ──────────────────────────────────────────────
      Container(
        color: color.withOpacity(0.09),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(6)),
            child: Text(sens,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(hindi,
                style: TextStyle(color: color, fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text('$tCnt केन्द्र',
                style: TextStyle(color: color, fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      ),

      // ── Scrollable table ──────────────────────────────────────────────────
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row 1 — span labels ─────────────────────────────
                Row(children: [
                  _hCell('क्र.\nसं.',         _w0,  color, sm: true),
                  _vd(color, thick: true),
                  _hCell('मतदान\nकेन्द्र\nप्रकार', _w1, color, sm: true),
                  _vd(color, thick: true),
                  _hCell('संख्या\nपोलिंग\nसेन्टर', _w2, color, sm: true),
                  _vd(color, thick: true),
                  _spanHdr('Scale', _wSc * 5 + 4 * 0.8, color.withOpacity(0.80)),
                  _vd(color, thick: true),
                  _spanHdr(
                      'मानक के अनुसार व्यवस्थापित पुलिस बल का विवरण',
                      _wTt * 9 + 8 * 0.8, color),
                ]),
                // ── Header row 2 — column labels ───────────────────────────
                Row(children: [
                  _hCell('',             _w0,  color),
                  _vd(color, thick: true),
                  _hCell('',             _w1,  color),
                  _vd(color, thick: true),
                  _hCell('',             _w2,  color),
                  _vd(color, thick: true),
                  // Scale sub-headers
                  _hCell('SI',           _wSc, color.withOpacity(0.82)),
                  _vd(color),
                  _hCell('HC',           _wSc, color.withOpacity(0.82)),
                  _vd(color),
                  _hCell('Const.',       _wSc, color.withOpacity(0.82)),
                  _vd(color),
                  _hCell('Aux.\nForce',  _wSc, color.withOpacity(0.82), sm: true),
                  _vd(color),
                  _hCell('PAC\n(sec.)',  _wSc, color.withOpacity(0.82), sm: true),
                  _vd(color, thick: true),
                  // Total sub-headers
                  _hCell('SI\nसशस्त्र',  _wTt, color, sm: true),
                  _vd(color),
                  _hCell('HC',           _wTt, color),
                  _vd(color),
                  _hCell('HC\nसशस्त्र', _wTt, color, sm: true),
                  _vd(color),
                  _hCell('HC\nनिःशस्त्र', _wTt, color, sm: true),
                  _vd(color),
                  _hCell('Const.',       _wTt, color),
                  _vd(color),
                  _hCell('Const.\nसशस्त्र', _wTt, color, sm: true),
                  _vd(color),
                  _hCell('Const.\nनिःशस्त्र', _wTt, color, sm: true),
                  _vd(color),
                  _hCell('Aux.\nForce',  _wTt, color, sm: true),
                  _vd(color),
                  _hCell('PAC\n(sec.)',  _wTt, color, sm: true),
                ]),

                // ── Data rows + totals row ──────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: color.withOpacity(0.25), width: 0.8),
                    borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(6),
                        bottomRight: Radius.circular(6)),
                  ),
                  child: Column(children: [
                    for (int i = 0; i < rows.length; i++)
                      _buildDataRow(rows[i], i, f, fd, color),
                    _buildTotalsRow(
                        tCnt, tSSi, tSHc, tSCo, tSAx, tSPc,
                        tSiA, tHc, tHcA, tHcU,
                        tCo, tCoA, tCoU, tAx, tPc,
                        f, fd, color),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  // ── Header cell ─────────────────────────────────────────────────────────────
  static Widget _hCell(String label, double w, Color color,
      {bool sm = false}) {
    return Container(
      width: w,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      color: color,
      alignment: Alignment.center,
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white,
              fontSize: sm ? 9 : 10.5,
              fontWeight: FontWeight.w700,
              height: 1.3)),
    );
  }

  // ── Span header ─────────────────────────────────────────────────────────────
  static Widget _spanHdr(String label, double width, Color color) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      color: color,
      alignment: Alignment.center,
      child: Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white, fontSize: 10,
              fontWeight: FontWeight.w800, height: 1.3)),
    );
  }

  // ── Vertical divider ────────────────────────────────────────────────────────
  static Widget _vd(Color color, {bool thick = false}) => Container(
    width: thick ? 1.5 : 0.8,
    color: color.withOpacity(thick ? 0.35 : 0.2),
  );

  // ── Data row ────────────────────────────────────────────────────────────────
  Widget _buildDataRow(
      _Row r, int idx,
      String Function(int) f,
      String Function(double) fd,
      Color color) {
    final isEven = idx.isEven;
    final bg     = isEven ? Colors.white : color.withOpacity(0.04);
    final label  = r.boothCount == 15
        ? '15 और\nउससे\nअधिक\nबूथ'
        : '${r.boothCount} बूथ';

    Widget dc(String v, {Color? fg, bool bold = false, bool scale = false}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          alignment: Alignment.center,
          child: Text(v,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: fg ?? _kDark,
                  fontSize: scale ? 12 : 10.5,
                  fontWeight: (bold || scale)
                      ? FontWeight.w800 : FontWeight.w500)),
        );

    return Container(
      color: bg,
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: color.withOpacity(0.12), width: 0.7))),
      child: Row(children: [
        // #
        SizedBox(
          width: _w0,
          child: Center(
            child: Text('${idx + 1}',
                style: TextStyle(color: _kSubtle, fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        _vd(color, thick: true),
        // Booth label
        SizedBox(
          width: _w1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(label,
                style: const TextStyle(color: _kDark, fontSize: 10.5,
                    fontWeight: FontWeight.w700, height: 1.35)),
          ),
        ),
        _vd(color, thick: true),
        // Centre count (badge if > 0)
        SizedBox(
          width: _w2,
          child: Center(
            child: r.centerCount == 0
                ? Text('-', style: TextStyle(color: _kSubtle, fontSize: 10))
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text('${r.centerCount}',
                        style: TextStyle(color: color, fontSize: 13,
                            fontWeight: FontWeight.w900)),
                  ),
          ),
        ),
        _vd(color, thick: true),
        // ── Scale ─────────────────────────────────────────────────────────
        SizedBox(width: _wSc,
            child: dc(f(r.scaleSi), fg: color, bold: true, scale: true)),
        _vd(color),
        SizedBox(width: _wSc,
            child: dc(f(r.scaleHc), fg: color, bold: true, scale: true)),
        _vd(color),
        SizedBox(width: _wSc,
            child: dc(f(r.scaleConst), fg: color, bold: true, scale: true)),
        _vd(color),
        SizedBox(width: _wSc,
            child: dc(f(r.scaleAux), fg: color, bold: true, scale: true)),
        _vd(color),
        SizedBox(width: _wSc,
            child: dc(fd(r.scalePac), fg: color, bold: true, scale: true)),
        _vd(color, thick: true),
        // ── Totals ────────────────────────────────────────────────────────
        SizedBox(width: _wTt,
            child: dc(f(r.totSiArmed),
                fg: r.totSiArmed > 0
                    ? const Color(0xFF6A1B9A) : null, bold: true)),
        _vd(color),
        SizedBox(width: _wTt, child: dc(f(r.totHc))),
        _vd(color),
        SizedBox(width: _wTt, child: dc(f(r.totHcArmed),
            fg: r.totHcArmed > 0 ? const Color(0xFF1565C0) : null)),
        _vd(color),
        SizedBox(width: _wTt, child: dc(f(r.totHcUnarmed))),
        _vd(color),
        SizedBox(width: _wTt, child: dc(f(r.totConst))),
        _vd(color),
        SizedBox(width: _wTt, child: dc(f(r.totConstArmed),
            fg: r.totConstArmed > 0 ? const Color(0xFF6A1B9A) : null)),
        _vd(color),
        SizedBox(width: _wTt, child: dc(f(r.totConstUnarmed))),
        _vd(color),
        SizedBox(width: _wTt, child: dc(f(r.totAux),
            fg: r.totAux > 0 ? const Color(0xFFE65100) : null)),
        _vd(color),
        SizedBox(width: _wTt, child: dc(fd(r.totPac),
            fg: r.totPac > 0 ? const Color(0xFF00695C) : null)),
      ]),
    );
  }

  // ── Totals row ───────────────────────────────────────────────────────────────
  Widget _buildTotalsRow(
      int tCnt, int tSSi, int tSHc, int tSCo, int tSAx, double tSPc,
      int tSiA, int tHc, int tHcA, int tHcU,
      int tCo, int tCoA, int tCoU, int tAx, double tPc,
      String Function(int) f,
      String Function(double) fd,
      Color color) {

    Widget tc(String v) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
      alignment: Alignment.center,
      child: Text(v,
          style: TextStyle(color: color, fontSize: 12,
              fontWeight: FontWeight.w900)),
    );

    return Container(
      color: color.withOpacity(0.10),
      child: Row(children: [
        SizedBox(width: _w0),
        _vd(color, thick: true),
        SizedBox(
          width: _w1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text('योग', style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w900)),
          ),
        ),
        _vd(color, thick: true),
        SizedBox(width: _w2, child: tc('$tCnt')),
        _vd(color, thick: true),
        SizedBox(width: _wSc, child: tc('$tSSi')),
        _vd(color),
        SizedBox(width: _wSc, child: tc('$tSHc')),
        _vd(color),
        SizedBox(width: _wSc, child: tc('$tSCo')),
        _vd(color),
        SizedBox(width: _wSc, child: tc('$tSAx')),
        _vd(color),
        SizedBox(width: _wSc, child: tc(fd(tSPc))),
        _vd(color, thick: true),
        SizedBox(width: _wTt, child: tc('$tSiA')),
        _vd(color),
        SizedBox(width: _wTt, child: tc('$tHc')),
        _vd(color),
        SizedBox(width: _wTt, child: tc('$tHcA')),
        _vd(color),
        SizedBox(width: _wTt, child: tc('$tHcU')),
        _vd(color),
        SizedBox(width: _wTt, child: tc('$tCo')),
        _vd(color),
        SizedBox(width: _wTt, child: tc('$tCoA')),
        _vd(color),
        SizedBox(width: _wTt, child: tc('$tCoU')),
        _vd(color),
        SizedBox(width: _wTt, child: tc('$tAx')),
        _vd(color),
        SizedBox(width: _wTt, child: tc(fd(tPc))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  PRINT BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════
class _PrintSheet extends StatefulWidget {
  final Future<void> Function()       onPrintAll;
  final Future<void> Function()       onPreviewAll;
  final Future<void> Function(String) onPrintSens;
  final Future<void> Function(String) onPreviewSens;

  const _PrintSheet({
    required this.onPrintAll,
    required this.onPreviewAll,
    required this.onPrintSens,
    required this.onPreviewSens,
  });

  @override
  State<_PrintSheet> createState() => _PrintSheetState();
}

class _PrintSheetState extends State<_PrintSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try { await fn(); } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: _kBorder.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: _kDark.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.print_outlined, color: _kDark, size: 20)),
              const SizedBox(width: 10),
              const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Print / Preview',
                    style: TextStyle(color: _kDark,
                        fontWeight: FontWeight.w800, fontSize: 16)),
                Text('मानक रिपोर्ट — बूथ-वार पुलिस बल',
                    style: TextStyle(color: _kSubtle, fontSize: 11)),
              ])),
              if (_busy)
                const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kDark)),
            ]),
          ),
          const Divider(height: 1, color: _kBorder),
          Expanded(child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
            children: [
              _SectionLabel('सम्मिलित रिपोर्ट'),
              const SizedBox(height: 8),
              _PrintTile(
                icon: Icons.auto_stories_outlined,
                title: 'सम्पूर्ण मानक रिपोर्ट',
                subtitle: 'A++ + A + B + C — सभी 4 श्रेणियां एक PDF में',
                color: _kDark,
                busy: _busy,
                onPreview: () => _run(widget.onPreviewAll),
                onPrint:   () => _run(widget.onPrintAll),
              ),
              const SizedBox(height: 16),
              _SectionLabel('श्रेणी-वार रिपोर्ट'),
              const SizedBox(height: 8),
              for (final s in _sensOrder) ...[
                _PrintTile(
                  icon: Icons.table_chart_outlined,
                  title: '$s — ${_sensHindi[s]}',
                  subtitle: '$s श्रेणी का बूथ-वार मानक विवरण',
                  color: _sensColors[s]!,
                  busy: _busy,
                  onPreview: () => _run(() => widget.onPreviewSens(s)),
                  onPrint:   () => _run(() => widget.onPrintSens(s)),
                ),
                const SizedBox(height: 8),
              ],
            ],
          )),
        ]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 14,
        decoration: BoxDecoration(
            color: _kDark, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label, style: const TextStyle(
        color: _kDark, fontSize: 12, fontWeight: FontWeight.w800)),
  ]);
}

class _PrintTile extends StatelessWidget {
  final IconData icon;
  final String   title, subtitle;
  final Color    color;
  final bool     busy;
  final VoidCallback onPreview, onPrint;

  const _PrintTile({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.busy,
    required this.onPreview, required this.onPrint,
  });

  Widget _btn(IconData ic, String lbl, Color bg, Color fg, VoidCallback? fn) =>
      GestureDetector(
        onTap: fn,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(lbl, style: TextStyle(
                color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3))),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(children: [
      Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            color: _kDark, fontSize: 12, fontWeight: FontWeight.w700)),
        Text(subtitle, style: const TextStyle(
            color: _kSubtle, fontSize: 10)),
      ])),
      const SizedBox(width: 8),
      _btn(Icons.visibility_outlined, 'Preview',
          color.withOpacity(0.12), color, busy ? null : onPreview),
      const SizedBox(width: 6),
      _btn(Icons.print_outlined, 'Print',
          color, Colors.white, busy ? null : onPrint),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  PDF PREVIEW PAGE
// ══════════════════════════════════════════════════════════════════════════════
class _PdfPreviewPage extends StatelessWidget {
  final String    title;
  final Uint8List bytes;
  const _PdfPreviewPage({required this.title, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),
      appBar: AppBar(
        backgroundColor: _kDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const Text('PDF Preview',
              style: TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => Printing.layoutPdf(onLayout: (_) async => bytes),
            icon: const Icon(Icons.print, color: Colors.white, size: 18),
            label: const Text('Print',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            onPressed: () =>
                Printing.sharePdf(bytes: bytes, filename: '$title.pdf'),
            icon: const Icon(Icons.share_outlined, color: Colors.white, size: 18),
            label: const Text('Share',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        allowPrinting: false, allowSharing: false,
        canChangePageFormat: false, canChangeOrientation: false,
        pdfFileName: '$title.pdf',
        previewPageMargin: const EdgeInsets.all(8),
        scrollViewDecoration: const BoxDecoration(color: Color(0xFFDDDDDD)),
        pdfPreviewPageDecoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15),
                blurRadius: 8, offset: const Offset(0, 2))]),
      ),
    );
  }
}