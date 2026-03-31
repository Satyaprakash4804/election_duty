import 'package:flutter/material.dart';

class BoothPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text("Add Booth"),
        TextField(decoration: InputDecoration(labelText: "Booth Number")),
        TextField(decoration: InputDecoration(labelText: "Booth Name")),
        ElevatedButton(onPressed: () {}, child: Text("Save")),
      ],
    );
  }
}