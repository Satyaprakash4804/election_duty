import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'dart:typed_data';

class GoswaraPage extends StatefulWidget {
  const GoswaraPage({super.key});

  @override
  State<GoswaraPage> createState() => _GoswaraPageState();
}

class _GoswaraPageState extends State<GoswaraPage> {
  List   data         = [];
  bool   loading      = true;
  String electionDate = "";
  String phase        = "";

  // ── User info (to show district label for super_admin) ──────────────────
  String _userRole     = "";
  String _userDistrict = "";

  @override
  void initState() {
    super.initState();
    _loadUserThenFetch();
  }

  Future<void> _loadUserThenFetch() async {
    try {
      final user = await AuthService.getUser();          // returns Map or null
      if (user != null && mounted) {
        setState(() {
          _userRole     = (user["role"]     ?? "").toString();
          _userDistrict = (user["district"] ?? "").toString();
        });
      }
    } catch (_) {}
    await fetchData();
  }

  Future<void> fetchData() async {
    setState(() => loading = true);
    try {
      final res = await ApiService.getGoswara();
      setState(() {
        data         = res["data"]         ?? [];
        electionDate = res["electionDate"] ?? "";
        phase        = res["phase"]        ?? "";
      });
    } catch (e) {
      debugPrint(e.toString());
    }
    setState(() => loading = false);
  }

  int sum(String key) =>
      data.fold(0, (s, r) => s + (r[key] as int? ?? 0));

  bool get _isSuperAdmin => _userRole == "super_admin";

  // ── Fixed column widths for the screen table ──────────────────────────────
  static const Map<int, TableColumnWidth> _colWidths = {
    0: FixedColumnWidth(42),   // क्र०सं०
    1: FixedColumnWidth(130),  // विकास खण्ड
    2: FixedColumnWidth(80),   // चरण
    3: FixedColumnWidth(110),  // मतदान तिथि
    4: FixedColumnWidth(110),  // जोनल
    5: FixedColumnWidth(100),  // सेक्टर
    6: FixedColumnWidth(100),  // न्याय पंचायत
    7: FixedColumnWidth(100),  // ग्राम पंचायत
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          "गोसवारा",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: "Print / Save PDF",
            onPressed: () async {
              await Printing.layoutPdf(
                onLayout: (_) async => buildPdf(),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    // ── Title ──────────────────────────────────────────────
                    const Text(
                      "गोसवारा",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "-:: विकास खण्डवार जोनल एवं सेक्टर, न्याय पंचायत एवं ग्राम पंचायतों का विवरण ::-",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),

                    // ── District badge (super_admin only) ──────────────────
                    if (_isSuperAdmin && _userDistrict.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.blue.shade200, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_city_outlined,
                                  size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 5),
                              Text(
                                "जनपद: $_userDistrict",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // ── Horizontally scrollable table ──────────────────────
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildTable(),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Screen table ──────────────────────────────────────────────────────────
  Widget _buildTable() {
    final headerBg = Colors.grey.shade200;
    final border   = TableBorder.all(color: Colors.black54, width: 0.8);

    return Table(
      border: border,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: _colWidths,
      children: [

        // Header
        TableRow(
          decoration: BoxDecoration(color: headerBg),
          children: [
            _cell("क्र०सं०",                            bold: true),
            _cell("विकास खण्ड",                         bold: true),
            _cell("चरण",                                bold: true),
            _cell("मतदान की\nतिथि",                     bold: true),
            _cell("जोनल मजिस्ट्रेट /\nपुलिस अधिकारी", bold: true),
            _cell("सेक्टर\nमजिस्ट्रेट",                bold: true),
            _cell("न्याय\nपंचायत",                      bold: true),
            _cell("ग्राम\nपंचायत",                      bold: true),
          ],
        ),

        // Data rows — चरण & तिथि shown only in first row (mimics row-span)
        ...data.asMap().entries.map((e) {
          final i = e.key;
          final r = e.value;
          return TableRow(children: [
            _cell("${i + 1}"),
            _cell(r["block_name"] ?? ""),
            _cell(i == 0 ? phase        : ""),
            _cell(i == 0 ? electionDate : ""),
            _cell("${r["zonal_count"]          ?? 0}"),
            _cell("${r["sector_count"]         ?? 0}"),
            _cell("${r["nyay_panchayat_count"] ?? 0}"),
            _cell("${r["gram_panchayat_count"] ?? 0}"),
          ]);
        }),

        // Total row
        TableRow(
          decoration: BoxDecoration(color: headerBg),
          children: [
            _cell(""),
            _cell("योग",                            bold: true),
            _cell(""),
            _cell(""),
            _cell("${sum("zonal_count")}",          bold: true),
            _cell("${sum("sector_count")}",         bold: true),
            _cell("${sum("nyay_panchayat_count")}", bold: true),
            _cell("${sum("gram_panchayat_count")}", bold: true),
          ],
        ),
      ],
    );
  }

  Widget _cell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: Colors.black87,
        ),
      ),
    );
  }

  // ── PDF builder — same PdfGoogleFonts pattern as duty_card_page.dart ──────
  Future<Uint8List> buildPdf() async {
    final pdf  = pw.Document();

    // ✅ No asset files needed — downloaded automatically by printing package
    final font = await PdfGoogleFonts.notoSansDevanagariRegular();
    final bold = await PdfGoogleFonts.notoSansDevanagariBold();

    final baseStyle  = pw.TextStyle(font: font, fontSize: 10);
    final boldStyle  = pw.TextStyle(font: bold, fontSize: 10,
        fontWeight: pw.FontWeight.bold);
    final titleStyle = pw.TextStyle(font: bold, fontSize: 16,
        fontWeight: pw.FontWeight.bold);
    final subStyle   = pw.TextStyle(font: font, fontSize: 9);
    final distStyle  = pw.TextStyle(font: bold, fontSize: 10,
        fontWeight: pw.FontWeight.bold);

    // PDF column widths (A4 landscape ~800pt usable)
    const Map<int, pw.TableColumnWidth> pdfCols = {
      0: pw.FixedColumnWidth(30),
      1: pw.FixedColumnWidth(110),
      2: pw.FixedColumnWidth(65),
      3: pw.FixedColumnWidth(80),
      4: pw.FixedColumnWidth(115),
      5: pw.FixedColumnWidth(95),
      6: pw.FixedColumnWidth(90),
      7: pw.FixedColumnWidth(90),
    };

    pw.Widget pdfCell(String text, {bool isBold = false, PdfColor? bg}) {
      return pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: isBold ? boldStyle : baseStyle,
        ),
      );
    }

    const headerBg = PdfColors.grey300;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [

            // Title
            pw.Text("गोसवारा",
                textAlign: pw.TextAlign.center, style: titleStyle),
            pw.SizedBox(height: 5),
            pw.Text(
              "विकास खण्डवार जोनल एवं सेक्टर, न्याय पंचायत एवं ग्राम पंचायतों का विवरण",
              textAlign: pw.TextAlign.center,
              style: subStyle,
            ),

            // District line in PDF (super_admin only)
            if (_isSuperAdmin && _userDistrict.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                "जनपद: $_userDistrict",
                textAlign: pw.TextAlign.center,
                style: distStyle,
              ),
            ],

            pw.SizedBox(height: 12),

            // Table
            pw.Table(
              border: pw.TableBorder.all(width: 0.7),
              columnWidths: pdfCols,
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [

                // Header row
                pw.TableRow(children: [
                  pdfCell("क्र०",                              isBold: true, bg: headerBg),
                  pdfCell("विकास खण्ड",                        isBold: true, bg: headerBg),
                  pdfCell("चरण",                               isBold: true, bg: headerBg),
                  pdfCell("मतदान तिथि",                        isBold: true, bg: headerBg),
                  pdfCell("जोनल मजिस्ट्रेट /\nपुलिस अधिकारी",isBold: true, bg: headerBg),
                  pdfCell("सेक्टर मजिस्ट्रेट",                isBold: true, bg: headerBg),
                  pdfCell("न्याय पंचायत",                     isBold: true, bg: headerBg),
                  pdfCell("ग्राम पंचायत",                     isBold: true, bg: headerBg),
                ]),

                // Data rows
                ...data.asMap().entries.map((e) {
                  final i = e.key;
                  final r = e.value;
                  return pw.TableRow(children: [
                    pdfCell("${i + 1}"),
                    pdfCell(r["block_name"] ?? ""),
                    pdfCell(i == 0 ? phase        : ""),
                    pdfCell(i == 0 ? electionDate : ""),
                    pdfCell("${r["zonal_count"]          ?? 0}"),
                    pdfCell("${r["sector_count"]         ?? 0}"),
                    pdfCell("${r["nyay_panchayat_count"] ?? 0}"),
                    pdfCell("${r["gram_panchayat_count"] ?? 0}"),
                  ]);
                }),

                // Total row
                pw.TableRow(children: [
                  pdfCell("",                                        bg: headerBg),
                  pdfCell("योग",                   isBold: true,    bg: headerBg),
                  pdfCell("",                                        bg: headerBg),
                  pdfCell("",                                        bg: headerBg),
                  pdfCell("${sum("zonal_count")}",  isBold: true,   bg: headerBg),
                  pdfCell("${sum("sector_count")}", isBold: true,   bg: headerBg),
                  pdfCell("${sum("nyay_panchayat_count")}",
                      isBold: true, bg: headerBg),
                  pdfCell("${sum("gram_panchayat_count")}",
                      isBold: true, bg: headerBg),
                ]),
              ],
            ),
          ],
        ),
      ),
    );

    return Uint8List.fromList(await pdf.save());
  }
}