import 'package:flutter/material.dart';
import 'pages/dashboard_map.dart';
import 'pages/add_staff_page.dart';
import 'pages/form_page.dart';
import 'pages/duty_card_page.dart';
import 'pages/booth_page.dart';

class AdminDashboard extends StatefulWidget {
  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int selectedIndex = 0;

  final List<Widget> pages = [
    DashboardMapPage(),
    AddStaffPage(),
    FormPage(),
    DutyCardPage(),
    BoothPage(),
  ];

  final List<BottomNavigationBarItem> items = [
    BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Dashboard"),
    BottomNavigationBarItem(icon: Icon(Icons.people), label: "Staff"),
    BottomNavigationBarItem(icon: Icon(Icons.edit), label: "Form"),
    BottomNavigationBarItem(icon: Icon(Icons.picture_as_pdf), label: "Duty"),
    BottomNavigationBarItem(icon: Icon(Icons.location_on), label: "Booths"),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 15),
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Colors.blue),
            ),
          )
        ],
      ),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive padding
            double padding = constraints.maxWidth > 800 ? 40 : 10;

            return Padding(
              padding: EdgeInsets.all(padding),
              child: pages[selectedIndex],
            );
          },
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        items: items,
        selectedItemColor: Colors.blue.shade900,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
      ),
    );
  }

  String _getTitle() {
    switch (selectedIndex) {
      case 0:
        return "Dashboard";
      case 1:
        return "Staff Management";
      case 2:
        return "Election Form";
      case 3:
        return "Duty Cards";
      case 4:
        return "Booth Management";
      default:
        return "Dashboard";
    }
  }
}