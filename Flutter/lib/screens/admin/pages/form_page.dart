import 'package:flutter/material.dart';

class FormPage extends StatefulWidget {
  @override
  _FormPageState createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  List superZones = [];

  // 🔹 ADD FUNCTIONS
  void addSuperZone() {
    setState(() {
      superZones.add({"name": "", "zones": []});
    });
  }

  void addZone(int sz) {
    setState(() {
      superZones[sz]["zones"].add({
        "name": "",
        "hq": "",
        "zonalOfficer": {"name": "", "pno": "", "mobile": ""},
        "sectors": []
      });
    });
  }

  void addSector(int sz, int z) {
    setState(() {
      superZones[sz]["zones"][z]["sectors"].add({
        "name": "",
        "officers": [],
        "gps": []
      });
    });
  }

  void addOfficer(int sz, int z, int s) {
    setState(() {
      superZones[sz]["zones"][z]["sectors"][s]["officers"].add({
        "name": "",
        "pno": "",
        "mobile": ""
      });
    });
  }

  void addGP(int sz, int z, int s) {
    setState(() {
      superZones[sz]["zones"][z]["sectors"][s]["gps"].add({
        "name": "",
        "address": "",
        "centers": []
      });
    });
  }

  void addCenter(int sz, int z, int s, int gp) {
    setState(() {
      superZones[sz]["zones"][z]["sectors"][s]["gps"][gp]["centers"].add({
        "name": "",
        "address": "",
        "thana": "",
        "count": "",
        "type": "C"
      });
    });
  }

  // 🔹 COMMON INPUT
  Widget input(String label, Function(String) onChanged) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }

  // 🔹 DROPDOWN
  Widget typeDropdown(Map center) {
    return DropdownButtonFormField<String>(
      value: center["type"],
      decoration: InputDecoration(labelText: "Center Type"),
      items: ["A", "B", "C"].map((e) {
        return DropdownMenuItem(value: e, child: Text("Type $e"));
      }).toList(),
      onChanged: (val) => setState(() => center["type"] = val),
    );
  }

  // 🔹 CARD
  Widget card(Widget child) {
    return Card(
      elevation: 3,
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(10),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(12),
      children: [

        // 🔥 HEADER
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Election Structure",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: addSuperZone,
              icon: Icon(Icons.add),
              label: Text("Super Zone"),
            )
          ],
        ),

        // 🔹 SUPER ZONES
        ...List.generate(superZones.length, (sz) {
          var superZone = superZones[sz];

          return card(
            ExpansionTile(
              title: Text("Super Zone ${sz + 1}"),
              children: [
                input("Super Zone Name",
                    (val) => superZone["name"] = val),

                ElevatedButton(
                    onPressed: () => addZone(sz),
                    child: Text("Add Zone")),

                // 🔹 ZONES
                ...List.generate(superZone["zones"].length, (z) {
                  var zone = superZone["zones"][z];

                  return card(
                    ExpansionTile(
                      title: Text("Zone ${z + 1}"),
                      children: [

                        input("Zone Name", (val) => zone["name"] = val),
                        input("Zone HQ Address", (val) => zone["hq"] = val),

                        Text("Zonal Adhikari",
                            style: TextStyle(fontWeight: FontWeight.bold)),

                        input("Name",
                            (val) => zone["zonalOfficer"]["name"] = val),
                        input("PNO",
                            (val) => zone["zonalOfficer"]["pno"] = val),
                        input("Mobile",
                            (val) => zone["zonalOfficer"]["mobile"] = val),

                        ElevatedButton(
                            onPressed: () => addSector(sz, z),
                            child: Text("Add Sector")),

                        // 🔹 SECTORS
                        ...List.generate(zone["sectors"].length, (s) {
                          var sector = zone["sectors"][s];

                          return card(
                            ExpansionTile(
                              title: Text("Sector ${s + 1}"),
                              children: [

                                input("Sector Name",
                                    (val) => sector["name"] = val),

                                Text("Police Adhikari",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)),

                                TextButton(
                                    onPressed: () =>
                                        addOfficer(sz, z, s),
                                    child: Text("+ Add Officer")),

                                ...List.generate(
                                    sector["officers"].length, (o) {
                                  var officer = sector["officers"][o];

                                  return card(Column(
                                    children: [
                                      input("Name",
                                          (val) =>
                                              officer["name"] = val),
                                      input("PNO",
                                          (val) =>
                                              officer["pno"] = val),
                                      input("Mobile",
                                          (val) => officer["mobile"] = val),
                                    ],
                                  ));
                                }),

                                ElevatedButton(
                                    onPressed: () => addGP(sz, z, s),
                                    child: Text("Add Gram Panchayat")),

                                // 🔹 GP
                                ...List.generate(
                                    sector["gps"].length, (gp) {
                                  var g = sector["gps"][gp];

                                  return card(
                                    ExpansionTile(
                                      title: Text("GP ${gp + 1}"),
                                      children: [

                                        input("GP Name",
                                            (val) => g["name"] = val),
                                        input("GP Address",
                                            (val) => g["address"] = val),

                                        ElevatedButton(
                                            onPressed: () =>
                                                addCenter(sz, z, s, gp),
                                            child: Text(
                                                "Add Election Center")),

                                        // 🔹 CENTERS
                                        ...List.generate(
                                            g["centers"].length, (c) {
                                          var center =
                                              g["centers"][c];

                                          return card(Column(
                                            children: [
                                              input("Center Name",
                                                  (val) => center["name"] =
                                                      val),
                                              input("Address",
                                                  (val) =>
                                                      center["address"] = val),
                                              input("Thana",
                                                  (val) =>
                                                      center["thana"] = val),
                                              input("Matdan Kendra Sankhya",
                                                  (val) =>
                                                      center["count"] = val),

                                              typeDropdown(center),
                                            ],
                                          ));
                                        })
                                      ],
                                    ),
                                  );
                                })
                              ],
                            ),
                          );
                        })
                      ],
                    ),
                  );
                })
              ],
            ),
          );
        }),

        SizedBox(height: 20),

        ElevatedButton(
          onPressed: () {
            print(superZones);
          },
          child: Text("Save Data"),
        )
      ],
    );
  }
}