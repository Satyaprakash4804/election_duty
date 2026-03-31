import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class DutyCardPage extends StatefulWidget {
  @override
  _DutyCardPageState createState() => _DutyCardPageState();
}

class _DutyCardPageState extends State<DutyCardPage> {
  TextEditingController searchController = TextEditingController();

  // 🔹 Dummy Data (later from API)
  List<Map<String, String>> staffList = [
    {
      "name": "राम कुमार",
      "pno": "1234",
      "mobile": "9876543210",
      "booth": "प्राथमिक विद्यालय",
      "gp": "XYZ पंचायत"
    },
    {
      "name": "श्याम सिंह",
      "pno": "5678",
      "mobile": "9999999999",
      "booth": "इंटर कॉलेज",
      "gp": "ABC पंचायत"
    }
  ];

  List<Map<String, String>> filteredList = [];

  @override
  void initState() {
    super.initState();
    filteredList = staffList;
  }

  // 🔍 SEARCH FUNCTION
  void search(String value) {
    setState(() {
      filteredList = staffList.where((staff) {
        return staff["name"]!.contains(value) ||
            staff["pno"]!.contains(value);
      }).toList();
    });
  }

  // 📄 PDF GENERATION (DYNAMIC)
  Future<void> generateDutyCard(Map<String, String> staff) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Container(
            color: PdfColors.pink100,
            padding: pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [

                // 🔹 HEADER
                pw.Center(
                  child: pw.Text(
                    "ड्यूटी कार्ड\nपंचायत चुनाव 2026",
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),

                pw.SizedBox(height: 10),

                pw.Text("थाना: बागपत | जनपद: बागपत"),
                pw.Text("समय: 07:00 बजे से 20:00 बजे तक"),

                pw.SizedBox(height: 10),

                // 🔹 STAFF TABLE
                pw.Table(
                  border: pw.TableBorder.all(),
                  children: [
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text("PNO"),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text("नाम"),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text("मोबाइल"),
                      ),
                    ]),
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text(staff["pno"]!),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text(staff["name"]!),
                      ),
                      pw.Padding(
                        padding: pw.EdgeInsets.all(5),
                        child: pw.Text(staff["mobile"]!),
                      ),
                    ]),
                  ],
                ),

                pw.SizedBox(height: 12),

                pw.Text("मतदान केंद्र: ${staff["booth"]}"),
                pw.Text("ग्राम पंचायत: ${staff["gp"]}"),

                pw.SizedBox(height: 30),

                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text("SP बागपत"),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [

        // 🔹 TITLE
        Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            "Duty Card Management",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),

        // 🔍 SEARCH BAR
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 15),
          child: TextField(
            controller: searchController,
            onChanged: search,
            decoration: InputDecoration(
              labelText: "Search by PNO / Name",
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),

        SizedBox(height: 10),

        // 📋 LIST
        Expanded(
          child: ListView.builder(
            itemCount: filteredList.length,
            itemBuilder: (context, index) {
              final staff = filteredList[index];

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                elevation: 3,
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text("${index + 1}"),
                  ),
                  title: Text(staff["name"]!),
                  subtitle: Text(
                      "PNO: ${staff["pno"]}\nBooth: ${staff["booth"]}"),
                  trailing: ElevatedButton.icon(
                    icon: Icon(Icons.print),
                    label: Text("Print"),
                    onPressed: () => generateDutyCard(staff),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}