import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

import 'pages/dashboard_page.dart';
import 'pages/staff_page.dart';
import 'pages/form_page.dart';
import 'pages/duty_card_page.dart';
import 'pages/booth_page.dart';

// ── THEME ─────────────────────────────────────────────
const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kAccent  = Color(0xFFB8860B);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _idx = 0;

  static const _labels = [
    'Dashboard',
    'Staff',
    'Structure',
    'Duty Cards',
    'Booths'
  ];

  static const _icons = [
    Icons.dashboard_outlined,
    Icons.badge_outlined,
    Icons.account_tree_outlined,
    Icons.how_to_vote_outlined,
    Icons.location_on_outlined,
  ];

  static const _iconsSelected = [
    Icons.dashboard,
    Icons.badge,
    Icons.account_tree,
    Icons.how_to_vote,
    Icons.location_on,
  ];

  // ─────────────────────────────────────────────
  // 🔴 LOGOUT FUNCTION (FINAL)
  // ─────────────────────────────────────────────
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: kError, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: kError),
            SizedBox(width: 8),
            Text("Logout", style: TextStyle(color: kError)),
          ],
        ),
        content: const Text(
          "Do you want to logout?",
          style: TextStyle(color: kDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: kSubtle)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kError,
              foregroundColor: Colors.white,
            ),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 🔥 CLEAR TOKEN
      await AuthService.logout();

      // 🔥 REDIRECT TO LOGIN (CLEAR STACK)
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          "/login",
          (route) => false,
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  // BUILD UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,

      // ── APP BAR ─────────────────────────────
      appBar: AppBar(
        backgroundColor: kDark,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: kPrimary,
                shape: BoxShape.circle,
                border: Border.all(color: kBorder),
              ),
              child: const Icon(
                Icons.how_to_vote,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labels[_idx],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "Admin Panel",
                  style: TextStyle(fontSize: 10, color: Colors.white60),
                ),
              ],
            ),
          ],
        ),

        actions: [
          // 🔔 Notification
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),

          // 🔴 LOGOUT BUTTON
          IconButton(
            tooltip: "Logout",
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),

      // ── BODY ─────────────────────────────
      body: IndexedStack(
        index: _idx,
        children: const [
          DashboardPage(),
          StaffPage(),
          FormPage(),
          DutyCardPage(),
          BoothPage(),
        ],
      ),

      // ── BOTTOM NAV ───────────────────────
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: kBorder)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 65,
            child: Row(
              children: List.generate(5, (i) {
                final selected = _idx == i;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _idx = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: selected ? kBg : Colors.transparent,
                        border: Border(
                          top: BorderSide(
                            color: selected ? kPrimary : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            selected ? _iconsSelected[i] : _icons[i],
                            color: selected ? kPrimary : kSubtle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _labels[i],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: selected ? kPrimary : kSubtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}