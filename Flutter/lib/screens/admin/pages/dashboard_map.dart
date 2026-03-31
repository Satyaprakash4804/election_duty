import 'package:flutter/material.dart';


class DashboardMapPage extends StatelessWidget {
  Widget card(String title, String value) {
    return Container(
      width: 200,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(blurRadius: 5, color: Colors.grey.shade300)],
      ),
      child: Column(
        children: [
          Text(title),
          SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 20,
          children: [
            card("Total Staff", "120"),
            card("Total Booths", "85"),
            card("Assigned Duties", "95"),
          ],
        ),
        Expanded(
          child: Center(child: Text("Mappls Map Here")),
        )
      ],
    );
  }
}