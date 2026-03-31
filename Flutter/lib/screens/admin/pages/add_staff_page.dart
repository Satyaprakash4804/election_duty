import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';

class AddStaffPage extends StatefulWidget {
  @override
  _AddStaffPageState createState() => _AddStaffPageState();
}

class _AddStaffPageState extends State<AddStaffPage> {

  final pnoController = TextEditingController();
  final nameController = TextEditingController();
  final mobileController = TextEditingController();
  final thanaController = TextEditingController();

  List<Map<String, String>> staffList = [];

  // ✅ EXCEL FUNCTION HERE
  Future<void> pickExcel() async {
    var result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );

    if (result != null) {
      var bytes = result.files.single.bytes!;
      var excel = Excel.decodeBytes(bytes);

      List<Map<String, String>> tempList = [];

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table]!;

        for (int i = 1; i < sheet.rows.length; i++) {
          var row = sheet.rows[i];

          String pno = row[0]?.value.toString() ?? "";
          String name = row[1]?.value.toString() ?? "";
          String mobile = row[2]?.value.toString() ?? "";
          String thana = row[3]?.value.toString() ?? "";

          tempList.add({
            "pno": pno,
            "name": name,
            "mobile": mobile,
            "thana": thana,
          });
        }
      }

      setState(() {
        staffList = tempList;
      });

      print("Excel Uploaded: ${staffList.length} staff");
    }
  }

  // ✅ MANUAL ADD
  void addStaff() {
    setState(() {
      staffList.add({
        "pno": pnoController.text,
        "name": nameController.text,
        "mobile": mobileController.text,
        "thana": thanaController.text,
      });
    });

    pnoController.clear();
    nameController.clear();
    mobileController.clear();
    thanaController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [

          // 🔹 FORM
          Card(
            child: Padding(
              padding: EdgeInsets.all(15),
              child: Column(
                children: [
                  Text("Add Staff Manually", style: TextStyle(fontSize: 18)),

                  TextField(controller: pnoController, decoration: InputDecoration(labelText: "PNO")),
                  TextField(controller: nameController, decoration: InputDecoration(labelText: "Name")),
                  TextField(controller: mobileController, decoration: InputDecoration(labelText: "Mobile")),
                  TextField(controller: thanaController, decoration: InputDecoration(labelText: "Thana")),

                  SizedBox(height: 10),

                  ElevatedButton(
                    onPressed: addStaff,
                    child: Text("Add Staff"),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 20),

          // 🔹 EXCEL BUTTON
          ElevatedButton.icon(
            onPressed: pickExcel,
            icon: Icon(Icons.upload_file),
            label: Text("Upload Excel"),
          ),

          SizedBox(height: 20),

          // 🔹 STAFF LIST TABLE
          Expanded(
            child: Card(
              child: ListView.builder(
                itemCount: staffList.length,
                itemBuilder: (context, index) {
                  final staff = staffList[index];

                  return ListTile(
                    leading: Text("${index + 1}"),
                    title: Text(staff["name"] ?? ""),
                    subtitle: Text("PNO: ${staff["pno"]} | ${staff["thana"]}"),
                    trailing: Text(staff["mobile"] ?? ""),
                  );
                },
              ),
            ),
          )
        ],
      ),
    );
  }
}