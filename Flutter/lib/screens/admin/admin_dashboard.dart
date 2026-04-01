import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'pages/dashboard_page.dart';
import 'pages/staff_page.dart';
import 'pages/form_page.dart';
import 'pages/duty_card_page.dart';
import 'pages/booth_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _idx = 0;

  // Pages are created once — token is fetched inside each page
  final _pages = const [
    DashboardPage(),
    StaffPage(),
    FormPage(),
    DutyCardPage(),
    BoothPage(),
  ];

  final _labels = ['Dashboard', 'Staff', 'Structure', 'Duty Cards', 'Booths'];
  final _icons = [
    Icons.dashboard,
    Icons.people,
    Icons.account_tree,
    Icons.badge,
    Icons.location_on,
  ];

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AuthService.logout();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_labels[_idx]),
        actions: [
          PopupMenuButton(
            icon: const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white, size: 20),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'logout', child: Row(
                children: [Icon(Icons.logout, size: 18), SizedBox(width: 8), Text('Logout')],
              )),
            ],
            onSelected: (v) { if (v == 'logout') _logout(); },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _pages[_idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: List.generate(5, (i) => NavigationDestination(
          icon: Icon(_icons[i]),
          label: _labels[i],
        )),
      ),
    );
  }
}