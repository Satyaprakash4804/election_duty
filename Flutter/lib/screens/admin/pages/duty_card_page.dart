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
  List _all = [];
  List _filtered = [];
  Set<int> _selected = {};
  bool _loading = true;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
      _filtered = q.isEmpty
          ? _all
          : _all.where((s) =>
              '${s['name']}'.toLowerCase().contains(q) ||
              '${s['pno']}'.toLowerCase().contains(q) ||
              '${s['mobile']}'.toLowerCase().contains(q) ||
              '${s['centerName']}'.toLowerCase().contains(q) ||
              '${s['sectorName']}'.toLowerCase().contains(q) ||
              '${s['zoneName']}'.toLowerCase().contains(q) ||
              '${s['superZoneName']}'.toLowerCase().contains(q) ||
              '${s['gpName']}'.toLowerCase().contains(q) ||
              '${s['staffThana']}'.toLowerCase().contains(q)).toList();
      _selected.clear();
    });
  }

  Future<void> _printDutyCards(List<Map> staffList) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();

    for (final s in staffList) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(14),
        build: (_) => pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 2),
            color: PdfColor.fromHex('#FFE4EE'),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [

            // Header bar
            pw.Container(
              color: PdfColor.fromHex('#B71C5D'),
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              child: pw.Column(children: [
                pw.Text('ड्यूटी कार्ड', style: pw.TextStyle(font: bold, fontSize: 16, color: PdfColors.white)),
                pw.Text('पंचायत सामान्य निर्वाचन-2026', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.white)),
                pw.Text('जनपद: बागपत', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.white)),
              ]),
            ),

            pw.Padding(
              padding: const pw.EdgeInsets.all(10),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [

                pw.Text('दिनांक: ${s['dutyDate'] ?? '15 अप्रैल 2026'}  |  समय: 07:00 से 20:00 बजे तक',
                    style: pw.TextStyle(font: font, fontSize: 9)),
                pw.Text('थाना: ${s['staffThana'] ?? '-'}  |  जनपद: बागपत',
                    style: pw.TextStyle(font: font, fontSize: 9)),
                pw.SizedBox(height: 8),

                // Staff details
                pw.Text('कर्मचारी विवरण', style: pw.TextStyle(font: bold, fontSize: 10)),
                pw.SizedBox(height: 3),
                _buildTable([
                  ['PNO', '${s['pno']}'],
                  ['नाम', '${s['name']}'],
                  ['मोबाइल', '${s['mobile']}'],
                  ['थाना', '${s['staffThana'] ?? '-'}'],
                ], font, bold),

                pw.SizedBox(height: 8),

                // Posting details
                pw.Text('ड्यूटी स्थान', style: pw.TextStyle(font: bold, fontSize: 10)),
                pw.SizedBox(height: 3),
                _buildTable([
                  ['मतदान केंद्र', '${s['centerName']}'],
                  ['ग्राम पंचायत', '${s['gpName']}'],
                  ['सेक्टर', '${s['sectorName']}'],
                  ['जोन', '${s['zoneName']}'],
                  ['सुपर जोन', '${s['superZoneName']}'],
                  ['बस नं.', '${s['busNo'] ?? '-'}'],
                  ['प्रकार', 'Type ${s['centerType'] ?? 'C'}'],
                ], font, bold),

                pw.SizedBox(height: 8),

                // Officer details
                pw.Text('अधिकारी विवरण', style: pw.TextStyle(font: bold, fontSize: 10)),
                pw.SizedBox(height: 3),
                _buildTable([
                  ['जोनल अधिकारी', '${s['zonalOfficer'] ?? '-'}'],
                  ['मोबाइल', '${s['zonalMobile'] ?? '-'}'],
                  ['सेक्टर अधिकारी', '${s['sectorOfficer'] ?? '-'}'],
                  ['मोबाइल', '${s['sectorMobile'] ?? '-'}'],
                ], font, bold),

                pw.SizedBox(height: 20),

                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                    pw.Container(width: 80, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 3),
                    pw.Text('SP बागपत', style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('हस्ताक्षर / मुहर', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                  ]),
                ]),
              ]),
            ),
          ]),
        ),
      ));
    }

    await Printing.layoutPdf(onLayout: (_) => pdf.save());
  }

  pw.Widget _buildTable(List<List<String>> rows, pw.Font font, pw.Font bold) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(2)},
      children: rows.map((r) => pw.TableRow(children: [
        pw.Padding(padding: const pw.EdgeInsets.all(3),
            child: pw.Text(r[0], style: pw.TextStyle(font: bold, fontSize: 8))),
        pw.Padding(padding: const pw.EdgeInsets.all(3),
            child: pw.Text(r[1], style: pw.TextStyle(font: font, fontSize: 8))),
      ])).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search by PNO, name, center, zone, GP, thana...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (_filtered.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Text('${_filtered.length} results', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const Spacer(),
              if (_selected.isNotEmpty) ...[
                Text('${_selected.length} selected', style: const TextStyle(color: Colors.blue, fontSize: 13)),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    final sel = _filtered
                        .where((s) => _selected.contains(s['id']))
                        .map((s) => Map<String, dynamic>.from(s))
                        .toList();
                    _printDutyCards(sel);
                  },
                  icon: const Icon(Icons.print, size: 16),
                  label: Text('Print (${_selected.length})'),
                ),
                const SizedBox(width: 4),
              ],
              TextButton(
                onPressed: () => setState(() {
                  if (_selected.length == _filtered.length) {
                    _selected.clear();
                  } else {
                    _selected = _filtered.map((s) => s['id'] as int).toSet();
                  }
                }),
                child: Text(_selected.length == _filtered.length ? 'Deselect All' : 'Select All'),
              ),
            ]),
          ],
        ]),
      ),

      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_filtered.isEmpty)
        const Expanded(child: Center(child: Text('No assigned staff found')))
      else
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final s = _filtered[i];
              final id = s['id'] as int;
              final sel = _selected.contains(id);

              return ListTile(
                selected: sel,
                selectedTileColor: Colors.blue.shade50,
                onTap: () => setState(() => sel ? _selected.remove(id) : _selected.add(id)),
                leading: GestureDetector(
                  onTap: () => setState(() => sel ? _selected.remove(id) : _selected.add(id)),
                  child: CircleAvatar(
                    backgroundColor: sel ? Colors.blue : Colors.grey.shade200,
                    child: sel
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('PNO: ${s['pno']} • ${s['mobile']}'),
                  Text('${s['centerName']} • ${s['gpName']}', style: const TextStyle(fontSize: 12)),
                  Text('${s['sectorName']} › ${s['zoneName']} › ${s['superZoneName']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ]),
                trailing: IconButton(
                  icon: const Icon(Icons.print, color: Colors.blue),
                  onPressed: () => _printDutyCards([Map<String, dynamic>.from(s)]),
                ),
                isThreeLine: true,
              );
            },
          ),
        ),
    ]);
  }
}