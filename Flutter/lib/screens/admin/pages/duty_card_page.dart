import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';

class DutyCardPage extends StatefulWidget {
  const DutyCardPage({super.key});
  @override
  State<DutyCardPage> createState() => _DutyCardPageState();
}

class _DutyCardPageState extends State<DutyCardPage> {
  List   _all      = [];
  List   _filtered = [];
  Set<int> _selected = {};
  bool   _loading  = true;
  final  _search   = TextEditingController();

  @override
  void initState() { super.initState(); _load(); _search.addListener(_filter); }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await ApiService.get('/admin/duties', token: token);
      setState(() {
        _all = res['data'] ?? [];
        _filtered = _all;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) showSnack(context, 'Failed to load: $e', error: true);
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _selected.clear();
      _filtered = q.isEmpty ? _all : _all.where((s) =>
          '${s['name']}'.toLowerCase().contains(q)          ||
          '${s['pno']}'.toLowerCase().contains(q)           ||
          '${s['mobile']}'.toLowerCase().contains(q)        ||
          '${s['centerName']}'.toLowerCase().contains(q)    ||
          '${s['sectorName']}'.toLowerCase().contains(q)    ||
          '${s['zoneName']}'.toLowerCase().contains(q)      ||
          '${s['superZoneName']}'.toLowerCase().contains(q) ||
          '${s['gpName']}'.toLowerCase().contains(q)        ||
          '${s['staffThana']}'.toLowerCase().contains(q)).toList();
    });
  }

  // ── PDF Generation ─────────────────────────────────────────────────────────
  Future<void> _print(List<Map> list) async {
  final pdf  = pw.Document();
  final font = await PdfGoogleFonts.notoSansDevanagariRegular();
  final bold = await PdfGoogleFonts.notoSansDevanagariBold();

  for (final s in list) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6.landscape,
        margin: const pw.EdgeInsets.all(6),
        build: (_) => pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1.5),
          ),
          child: pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [

                // HEADER
                pw.Center(
                  child: pw.Column(children: [
                    pw.Text('ड्यूटी कार्ड', style: pw.TextStyle(font: bold, fontSize: 12)),
                    pw.Text('लोकसभा निर्वाचन', style: pw.TextStyle(font: font, fontSize: 8)),
                    pw.Text('जनपद: बागपत', style: pw.TextStyle(font: font, fontSize: 7)),
                  ]),
                ),

                pw.SizedBox(height: 4),

                // STAFF
                pw.Text(
                  '${s['name']} (${s['rank']}) | ${s['pno']} | ${s['mobile']}',
                  style: pw.TextStyle(font: bold, fontSize: 8),
                ),

                pw.Text(
                  'थाना: ${s['staffThana']} | जिला: ${s['district']}',
                  style: pw.TextStyle(font: font, fontSize: 7),
                ),

                pw.Divider(),

                // OFFICERS
                _officerBlock('क्षेत्राधिकारी', s['superOfficers'], bold, font),
                _officerBlock('जोनल अधिकारी', s['zonalOfficers'], bold, font),
                _officerBlock('सेक्टर अधिकारी', s['sectorOfficers'], bold, font),

                pw.Divider(),

                // SAHYOGI
                pw.Text('सहयोगी कर्मचारी', style: pw.TextStyle(font: bold, fontSize: 8)),

                pw.Table(
                  border: pw.TableBorder.all(width: 0.3),
                  children: [
                    pw.TableRow(
                      children: [
                        _cell('नाम', bold),
                        _cell('PNO', bold),
                        _cell('रैंक', bold),
                        _cell('मोबाइल', bold),
                        _cell('जिला', bold),
                      ],
                    ),
                    ...((s['sahyogi'] ?? []) as List).map((e) =>
                      pw.TableRow(children: [
                        _cell('${e['name']}', font),
                        _cell('${e['pno']}', font),
                        _cell('${e['user_rank']}', font),
                        _cell('${e['mobile']}', font),
                        _cell('${e['district']}', font),
                      ])
                    )
                  ],
                ),

                pw.Spacer(),

                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('पुलिस अधीक्षक बागपत',
                      style: pw.TextStyle(font: font, fontSize: 7)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  await Printing.layoutPdf(onLayout: (_) => pdf.save());
}
  


  pw.Widget _officerBlock(String title, List list, pw.Font bold, pw.Font font) {
  return pw.Container(
    margin: const pw.EdgeInsets.symmetric(vertical: 2),
    padding: const pw.EdgeInsets.all(3),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.5),
      color: PdfColors.grey200,
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 7)),
        ...list.map((o) => pw.Text(
          '${o['name']} (${o['user_rank']}) - ${o['mobile']}',
          style: pw.TextStyle(font: font, fontSize: 7),
        ))
      ],
    ),
  );
}


pw.Widget _cell(String text, pw.Font f) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(2),
    child: pw.Text(text, style: pw.TextStyle(font: f, fontSize: 6)),
  );
}

  pw.Widget _tbl(List<List<String>> rows, pw.Font f, pw.Font b) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(2),
      },
      children: rows.map((r) => pw.TableRow(children: [
        pw.Padding(padding: const pw.EdgeInsets.all(3),
            child: pw.Text(r[0], style: pw.TextStyle(font: b, fontSize: 8))),
        pw.Padding(padding: const pw.EdgeInsets.all(3),
            child: pw.Text(r[1], style: pw.TextStyle(font: f, fontSize: 8))),
      ])).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Search ──────────────────────────────────────────────────────────────
      Container(
        color: kSurface,
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _search,
          style: const TextStyle(color: kDark, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search by PNO, name, center, zone, GP, thana...',
            hintStyle: const TextStyle(color: kSubtle, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
            filled: true, fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kPrimary, width: 2)),
            isDense: true,
          ),
        ),
      ),

      // ── Action Bar ─────────────────────────────────────────────────────────
      if (_filtered.isNotEmpty)
        Container(
          color: kBg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Text('${_filtered.length} results',
                style: const TextStyle(color: kSubtle, fontSize: 12)),
            const Spacer(),
            if (_selected.isNotEmpty) ...[
              GestureDetector(
                onTap: () {
                  final sel = _filtered
                      .where((s) => _selected.contains(s['id'] ?? 0))
                      .map((s) => Map<String, dynamic>.from(s))
                      .toList();
                  _print(sel);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.print, color: Colors.white, size: 15),
                    const SizedBox(width: 6),
                    Text('Print (${_selected.length})',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
            ],
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _filtered.length) {
                  _selected.clear();
                } else {
                  _selected = _filtered.map((s) => s['id'] as int).toSet();
                }
              }),
              style: TextButton.styleFrom(foregroundColor: kPrimary),
              child: Text(_selected.length == _filtered.length
                  ? 'Deselect All' : 'Select All',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),

      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator(color: kPrimary)))
      else if (_filtered.isEmpty)
        Expanded(child: emptyState('No assigned staff found', Icons.how_to_vote_outlined))
      else
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final s   = _filtered[i];
              final id  = s['id'] as int;
              final sel = _selected.contains(id);

              return GestureDetector(
                onTap: () => setState(() =>
                    sel ? _selected.remove(id) : _selected.add(id)),
                child: Container(
                  decoration: BoxDecoration(
                    color: sel ? kPrimary.withOpacity(0.06) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: sel ? kPrimary : kBorder.withOpacity(0.4),
                        width: sel ? 1.5 : 1),
                    boxShadow: [BoxShadow(
                        color: kPrimary.withOpacity(0.05),
                        blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    leading: GestureDetector(
                      onTap: () => setState(() =>
                          sel ? _selected.remove(id) : _selected.add(id)),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? kPrimary : kSurface,
                          border: Border.all(
                              color: sel ? kPrimary : kBorder),
                        ),
                        child: Center(child: sel
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : Text('${i + 1}', style: const TextStyle(
                                color: kPrimary, fontWeight: FontWeight.w800,
                                fontSize: 12))),
                      ),
                    ),
                    title: Text('${s['name']}', style: const TextStyle(
                        color: kDark, fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const SizedBox(height: 3),
                      Row(children: [
                        _tag(Icons.badge_outlined, '${s['pno']}'),
                        const SizedBox(width: 8),
                        _tag(Icons.phone_outlined, '${s['mobile']}'),
                      ]),
                      const SizedBox(height: 3),
                      _tag(Icons.location_on_outlined,
                          '${s['centerName']} • ${s['gpName']}',
                          color: kInfo),
                      const SizedBox(height: 2),
                      _tag(Icons.layers_outlined,
                          '${s['sectorName']} › ${s['zoneName']} › ${s['superZoneName']}'),
                    ]),
                    trailing: IconButton(
                      icon: const Icon(Icons.print_outlined, color: kPrimary),
                      onPressed: () =>
                          _print([Map<String, dynamic>.from(s)]),
                    ),
                    isThreeLine: true,
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _tag(IconData icon, String text, {Color? color}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color ?? kSubtle),
      const SizedBox(width: 3),
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color ?? kSubtle, fontSize: 11,
              fontWeight: FontWeight.w500))),
    ]);
  }
}