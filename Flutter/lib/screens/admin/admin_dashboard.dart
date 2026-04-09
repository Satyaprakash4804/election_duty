import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';

import 'pages/dashboard_page.dart';
import 'pages/staff_page.dart';
import 'pages/form_page.dart';
import 'pages/duty_card_page.dart';
import 'pages/booth_page.dart';

// ── THEME CONSTANTS ───────────────────────────────────────────────────────────
const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kAccent  = Color(0xFFB8860B);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);
const kSuccess = Color(0xFF2E7D32);
const kInfo    = Color(0xFF1565C0);

// ── NAV ITEM MODEL ────────────────────────────────────────────────────────────
class _NavItem {
  final String label;
  final IconData icon;
  final IconData iconFilled;
  const _NavItem(this.label, this.icon, this.iconFilled);
}

const _navItems = [
  _NavItem('Dashboard', Icons.dashboard_outlined,      Icons.dashboard),
  _NavItem('Staff',     Icons.badge_outlined,           Icons.badge),
  _NavItem('Structure', Icons.account_tree_outlined,    Icons.account_tree),
  _NavItem('Duties',    Icons.how_to_vote_outlined,     Icons.how_to_vote),
  _NavItem('Booths',    Icons.location_on_outlined,     Icons.location_on),
];

// ══════════════════════════════════════════════════════════════════════════════
//  ADMIN DASHBOARD
// ══════════════════════════════════════════════════════════════════════════════

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _idx = 0;

  // Cached page widgets — prevents rebuilds on tab switch
  static const List<Widget> _pages = [
    DashboardPage(),
    StaffPage(),
    FormPage(),
    DutyCardPage(),
    BoothPage(),
  ];

  // ── Logout ──────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _LogoutDialog(),
    );
    if (confirm != true || !mounted) return;
    await AuthService.logout();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isWide  = screenW >= 720;   // tablet / desktop breakpoint

    // Wide layout: permanent side rail
    if (isWide) return _WideLayout(idx: _idx, onSelect: _setIdx, onLogout: _logout, pages: _pages);

    // Phone layout: bottom nav
    return _PhoneLayout(idx: _idx, onSelect: _setIdx, onLogout: _logout, pages: _pages);
  }

  void _setIdx(int i) => setState(() => _idx = i);
}

// ══════════════════════════════════════════════════════════════════════════════
//  PHONE LAYOUT
// ══════════════════════════════════════════════════════════════════════════════

class _PhoneLayout extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final List<Widget> pages;

  const _PhoneLayout({
    required this.idx,
    required this.onSelect,
    required this.onLogout,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: _AdminAppBar(
        title: _navItems[idx].label,
        onLogout: onLogout,
      ),
      body: IndexedStack(index: idx, children: pages),
      bottomNavigationBar: _BottomNav(idx: idx, onSelect: onSelect),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  WIDE LAYOUT  (tablet / desktop — NavigationRail)
// ══════════════════════════════════════════════════════════════════════════════

class _WideLayout extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final List<Widget> pages;

  const _WideLayout({
    required this.idx,
    required this.onSelect,
    required this.onLogout,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: _AdminAppBar(
        title: _navItems[idx].label,
        onLogout: onLogout,
      ),
      body: Row(
        children: [
          // ── Side rail ──────────────────────────────────────────────────
          Container(
            width: 200,
            color: kDark,
            child: Column(
              children: [
                const SizedBox(height: 12),
                ...List.generate(_navItems.length, (i) {
                  final selected = idx == i;
                  return InkWell(
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? kPrimary.withOpacity(0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: selected
                            ? Border.all(color: kBorder.withOpacity(0.4))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? _navItems[i].iconFilled
                                : _navItems[i].icon,
                            color: selected ? kBorder : Colors.white54,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _navItems[i].label,
                            style: TextStyle(
                              color:
                                  selected ? Colors.white : Colors.white54,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          // ── Page body ──────────────────────────────────────────────────
          Expanded(
            child: IndexedStack(index: idx, children: pages),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  APP BAR
// ══════════════════════════════════════════════════════════════════════════════

class _AdminAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback onLogout;

  const _AdminAppBar({required this.title, required this.onLogout});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: kDark,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: kPrimary,
              shape: BoxShape.circle,
              border: Border.all(color: kBorder, width: 1.5),
            ),
            child: const Icon(Icons.how_to_vote, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const Text(
                'Admin Panel',
                style: TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Colors.white70),
          tooltip: 'Notifications',
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white70),
          tooltip: 'Logout',
          onPressed: onLogout,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOTTOM NAV BAR
// ══════════════════════════════════════════════════════════════════════════════

class _BottomNav extends StatelessWidget {
  final int idx;
  final ValueChanged<int> onSelect;

  const _BottomNav({required this.idx, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kBorder, width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_navItems.length, (i) {
              final selected = idx == i;
              return Expanded(
                child: _NavTab(
                  item: _navItems[i],
                  selected: selected,
                  onTap: () => onSelect(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? kBg : Colors.transparent,
          border: Border(
            top: BorderSide(
              color: selected ? kPrimary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? item.iconFilled : item.icon,
                key: ValueKey(selected),
                color: selected ? kPrimary : kSubtle,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.normal,
                color: selected ? kPrimary : kSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  LOGOUT DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class _LogoutDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kError, width: 1.5),
      ),
      title: const Row(
        children: [
          Icon(Icons.logout, color: kError),
          SizedBox(width: 8),
          Text('Logout', style: TextStyle(color: kError)),
        ],
      ),
      content: const Text(
        'Do you want to logout?',
        style: TextStyle(color: kDark),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: kSubtle)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: kError,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Logout'),
        ),
      ],
    );
  }
}