import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
//  RE-USE PALETTE FROM login_page.dart
// ─────────────────────────────────────────────
const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kAccent  = Color(0xFFB8860B);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);
const kSuccess = Color(0xFF2E7D32);

// ─────────────────────────────────────────────
//  MOCK DATA MODELS
// ─────────────────────────────────────────────
class AdminUser {
  final String id;
  final String name;
  final String district;
  final String password;
  final DateTime createdAt;
  final int totalBooths;
  final int assignedStaff;

  AdminUser({
    required this.id,
    required this.name,
    required this.district,
    required this.password,
    required this.createdAt,
    required this.totalBooths,
    required this.assignedStaff,
  });
}

class FormDataEntry {
  final String district;
  final String adminName;
  final int superZones;
  final int zones;
  final int sectors;
  final int gramPanchayats;
  final int centers;
  final DateTime lastUpdated;

  FormDataEntry({
    required this.district,
    required this.adminName,
    required this.superZones,
    required this.zones,
    required this.sectors,
    required this.gramPanchayats,
    required this.centers,
    required this.lastUpdated,
  });
}

// ─────────────────────────────────────────────
//  SUPER ADMIN DASHBOARD
// ─────────────────────────────────────────────
class SuperDashboard extends StatefulWidget {
  const SuperDashboard({super.key});

  @override
  State<SuperDashboard> createState() => _SuperDashboardState();
}

class _SuperDashboardState extends State<SuperDashboard>
    with TickerProviderStateMixin {
  int _selectedTab = 0;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // Mock admin list
  final List<AdminUser> _admins = [
    AdminUser(
      id: 'ADM001', name: 'Rajesh Kumar Singh', district: 'Baghpat',
      password: '••••••••', createdAt: DateTime(2026, 1, 10),
      totalBooths: 85, assignedStaff: 120,
    ),
    AdminUser(
      id: 'ADM002', name: 'Priya Sharma', district: 'Meerut',
      password: '••••••••', createdAt: DateTime(2026, 1, 15),
      totalBooths: 142, assignedStaff: 210,
    ),
    AdminUser(
      id: 'ADM003', name: 'Anil Verma', district: 'Muzaffarnagar',
      password: '••••••••', createdAt: DateTime(2026, 2, 1),
      totalBooths: 97, assignedStaff: 145,
    ),
  ];

  // Mock form data
  final List<FormDataEntry> _formData = [
    FormDataEntry(
      district: 'Baghpat', adminName: 'Rajesh Kumar Singh',
      superZones: 6, zones: 12, sectors: 48,
      gramPanchayats: 240, centers: 85,
      lastUpdated: DateTime(2026, 3, 20),
    ),
    FormDataEntry(
      district: 'Meerut', adminName: 'Priya Sharma',
      superZones: 8, zones: 16, sectors: 64,
      gramPanchayats: 380, centers: 142,
      lastUpdated: DateTime(2026, 3, 22),
    ),
    FormDataEntry(
      district: 'Muzaffarnagar', adminName: 'Anil Verma',
      superZones: 5, zones: 10, sectors: 38,
      gramPanchayats: 195, centers: 97,
      lastUpdated: DateTime(2026, 3, 18),
    ),
  ];

  final List<String> _upDistricts = [
    'Agra', 'Aligarh', 'Allahabad', 'Baghpat', 'Bareilly', 'Bijnor',
    'Bulandshahr', 'Etah', 'Etawah', 'Farrukhabad', 'Firozabad',
    'Gautam Buddh Nagar', 'Ghaziabad', 'Hathras', 'Jhansi', 'Kanpur',
    'Kasganj', 'Lucknow', 'Mathura', 'Meerut', 'Moradabad',
    'Muzaffarnagar', 'Rampur', 'Saharanpur', 'Shamli',
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _switchTab(int i) {
    setState(() => _selectedTab = i);
    _fadeCtrl.forward(from: 0);
  }

  // ── CREATE ADMIN DIALOG ──────────────────────
  void _showCreateAdminDialog() {
    final nameCtrl     = TextEditingController();
    final idCtrl       = TextEditingController();
    final passCtrl     = TextEditingController();
    final confirmCtrl  = TextEditingController();
    String? selectedDistrict;
    bool obscurePass   = true;
    bool obscureConf   = true;
    final formKey      = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: kPrimary.withOpacity(0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dialog header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      color: kDark,
                      borderRadius: BorderRadius.only(
                        topLeft:  Radius.circular(15),
                        topRight: Radius.circular(15),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings,
                            color: kBorder, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Create New Admin',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close,
                              color: Colors.white70, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                  // Form body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _dlgField(
                              controller: nameCtrl,
                              label: 'Full Name',
                              icon: Icons.person_outline,
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            _dlgField(
                              controller: idCtrl,
                              label: 'Admin User ID',
                              icon: Icons.badge_outlined,
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),

                            // District dropdown
                            DropdownButtonFormField<String>(
                              value: selectedDistrict,
                              decoration: _dlgDecoration(
                                  'District', Icons.location_city_outlined),
                              dropdownColor: kBg,
                              items: _upDistricts
                                  .map((d) => DropdownMenuItem(
                                      value: d, child: Text(d)))
                                  .toList(),
                              onChanged: (v) =>
                                  setDlg(() => selectedDistrict = v),
                              validator: (v) =>
                                  v == null ? 'Select district' : null,
                            ),
                            const SizedBox(height: 12),

                            _dlgField(
                              controller: passCtrl,
                              label: 'Password',
                              icon: Icons.lock_outline,
                              obscure: obscurePass,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscurePass
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: kSubtle,
                                ),
                                onPressed: () =>
                                    setDlg(() => obscurePass = !obscurePass),
                              ),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'Min 6 characters' : null,
                            ),
                            const SizedBox(height: 12),

                            _dlgField(
                              controller: confirmCtrl,
                              label: 'Confirm Password',
                              icon: Icons.lock_outline,
                              obscure: obscureConf,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscureConf
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                  color: kSubtle,
                                ),
                                onPressed: () =>
                                    setDlg(() => obscureConf = !obscureConf),
                              ),
                              validator: (v) => v != passCtrl.text
                                  ? 'Passwords do not match' : null,
                            ),
                            const SizedBox(height: 20),

                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: kSubtle,
                                      side: const BorderSide(color: kBorder),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (formKey.currentState!.validate()) {
                                        setState(() {
                                          _admins.add(AdminUser(
                                            id: 'ADM00${_admins.length + 1}',
                                            name: nameCtrl.text,
                                            district: selectedDistrict!,
                                            password: passCtrl.text,
                                            createdAt: DateTime.now(),
                                            totalBooths: 0,
                                            assignedStaff: 0,
                                          ));
                                        });
                                        Navigator.pop(ctx);
                                        _showSnack('Admin created successfully');
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Create Admin'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── FORM DATA DETAIL DIALOG ──────────────────
  void _showFormDetail(FormDataEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder, width: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: kDark,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(15),
                      topRight: Radius.circular(15),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.article_outlined,
                          color: kBorder, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${entry.district} — Form Data',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close,
                            color: Colors.white70, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _detailRow('Admin', entry.adminName,
                          Icons.manage_accounts_outlined),
                      _detailRow('Last Updated',
                          _formatDate(entry.lastUpdated),
                          Icons.calendar_today_outlined),
                      const Divider(color: kBorder, height: 24),
                      // Stats grid
                      GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 3,
                        childAspectRatio: 1.4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _miniStat('Super Zones',
                              '${entry.superZones}', Icons.layers_outlined),
                          _miniStat('Zones', '${entry.zones}',
                              Icons.grid_view_outlined),
                          _miniStat('Sectors', '${entry.sectors}',
                              Icons.view_module_outlined),
                          _miniStat('Gram Panchayats',
                              '${entry.gramPanchayats}',
                              Icons.account_balance_outlined),
                          _miniStat('Centers', '${entry.centers}',
                              Icons.location_on_outlined),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Close'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kDark,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(msg),
          ],
        ),
        backgroundColor: kSuccess,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── HELPERS ──────────────────────────────────
  InputDecoration _dlgDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18, color: kPrimary),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 2)),
      labelStyle: const TextStyle(color: kSubtle),
    );
  }

  Widget _dlgField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: _dlgDecoration(label, icon).copyWith(suffixIcon: suffixIcon),
      validator: validator,
      style: const TextStyle(color: kDark, fontSize: 14),
    );
  }

  Widget _detailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: kSubtle),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  color: kSubtle,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: kDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: kPrimary),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: kDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(
                  color: kSubtle, fontSize: 9, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  // ── BUILD ─────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        children: [
          _buildTopBar(),
          _buildTabBar(),
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  // ── TOP BAR ───────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: kDark,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 12,
        left: 16,
        right: 16,
      ),
      child: Row(
        children: [
          // Emblem
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kPrimary,
              border: Border.all(color: kBorder, width: 1.5),
            ),
            child: const Icon(Icons.how_to_vote_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SUPER ADMIN PANEL',
                  style: TextStyle(
                    color: kBorder,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
                Text(
                  'UP Election Cell — District Monitoring',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Logout
          IconButton(
            onPressed: () =>
                Navigator.pushReplacementNamed(context, '/login'),
            icon: const Icon(Icons.logout_rounded,
                color: Colors.white70, size: 20),
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  // ── TAB BAR ───────────────────────────────────
  Widget _buildTabBar() {
    final tabs = [
      (Icons.dashboard_outlined,      'Overview'),
      (Icons.admin_panel_settings,    'Admins'),
      (Icons.article_outlined,        'Form Data'),
    ];

    return Container(
      color: kSurface,
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = _selectedTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => _switchTab(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? kBg : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? kPrimary : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tabs[i].$1,
                        size: 16,
                        color: selected ? kPrimary : kSubtle),
                    const SizedBox(width: 6),
                    Text(
                      tabs[i].$2,
                      style: TextStyle(
                        color: selected ? kPrimary : kSubtle,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── BODY ROUTER ───────────────────────────────
  Widget _buildBody() {
    switch (_selectedTab) {
      case 0:  return _buildOverview();
      case 1:  return _buildAdminList();
      case 2:  return _buildFormData();
      default: return _buildOverview();
    }
  }

  // ── TAB 0 : OVERVIEW ─────────────────────────
  Widget _buildOverview() {
    final totalBooths = _admins.fold(0, (s, a) => s + a.totalBooths);
    final totalStaff  = _admins.fold(0, (s, a) => s + a.assignedStaff);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat cards row
          LayoutBuilder(builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            final cols = w > 500 ? 4 : 2;
            return GridView.count(
              shrinkWrap: true,
              crossAxisCount: cols,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _statCard('Total Districts',
                    '${_admins.length}',
                    Icons.map_outlined, kPrimary),
                _statCard('Total Admins',
                    '${_admins.length}',
                    Icons.manage_accounts, kAccent),
                _statCard('Total Booths',
                    '$totalBooths',
                    Icons.location_on_outlined, const Color(0xFF1565C0)),
                _statCard('Staff Assigned',
                    '$totalStaff',
                    Icons.badge_outlined, const Color(0xFF2E7D32)),
              ],
            );
          }),

          const SizedBox(height: 20),

          // District summary list
          _sectionHeader('District Summary', null),
          const SizedBox(height: 10),

          ...List.generate(_admins.length, (i) {
            final a = _admins[i];
            return _districtCard(a);
          }),
        ],
      ),
    );
  }

  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(
                  color: kSubtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _districtCard(AdminUser a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: kSurface,
              shape: BoxShape.circle,
              border: Border.all(color: kBorder),
            ),
            child: const Icon(Icons.location_city,
                color: kPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.district,
                    style: const TextStyle(
                        color: kDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                Text(a.name,
                    style: const TextStyle(
                        color: kSubtle,
                        fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _pill('${a.totalBooths} Booths', kPrimary),
              const SizedBox(height: 4),
              _pill('${a.assignedStaff} Staff', kAccent),
            ],
          ),
        ],
      ),
    );
  }

  // ── TAB 1 : ADMIN LIST ────────────────────────
  Widget _buildAdminList() {
    return Column(
      children: [
        // Action bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: kSurface,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_admins.length} Admin(s) Registered',
                  style: const TextStyle(
                      color: kDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateAdminDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Admin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _admins.length,
            itemBuilder: (_, i) => _adminCard(_admins[i], i),
          ),
        ),
      ],
    );
  }

  Widget _adminCard(AdminUser a, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.only(
                topLeft:  Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(a.id,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(a.name,
                      style: const TextStyle(
                          color: kDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                // Delete
                IconButton(
                  onPressed: () {
                    setState(() => _admins.removeAt(index));
                    _showSnack('Admin removed');
                  },
                  icon: const Icon(Icons.delete_outline,
                      color: kError, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Remove Admin',
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(Icons.location_city_outlined, a.district),
                      const SizedBox(height: 4),
                      _infoRow(Icons.calendar_today_outlined,
                          'Created ${_formatDate(a.createdAt)}'),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _pill('${a.totalBooths} Booths', kPrimary),
                    const SizedBox(height: 4),
                    _pill('${a.assignedStaff} Staff', kAccent),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB 2 : FORM DATA ─────────────────────────
  Widget _buildFormData() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _formData.length,
      itemBuilder: (_, i) => _formDataCard(_formData[i]),
    );
  }

  Widget _formDataCard(FormDataEntry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: kDark,
              borderRadius: BorderRadius.only(
                topLeft:  Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.map_outlined,
                    color: kBorder, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'District: ${e.district}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                ),
                Text(
                  'Updated: ${_formatDate(e.lastUpdated)}',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _infoRow(Icons.manage_accounts_outlined,
                    'Admin: ${e.adminName}'),
                const SizedBox(height: 10),

                // Stats chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statChip('${e.superZones}', 'Super Zones'),
                    _statChip('${e.zones}',      'Zones'),
                    _statChip('${e.sectors}',    'Sectors'),
                    _statChip('${e.gramPanchayats}', 'Gram Panchayats'),
                    _statChip('${e.centers}',    'Centers'),
                  ],
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showFormDetail(e),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('View Full Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kPrimary,
                      side: const BorderSide(color: kBorder),
                      padding:
                          const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── SMALL WIDGETS ─────────────────────────────
  Widget _sectionHeader(String title, VoidCallback? onAdd) {
    return Row(
      children: [
        Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.circular(2),
            )),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: kDark,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
        const Spacer(),
        if (onAdd != null)
          GestureDetector(
            onTap: onAdd,
            child: const Icon(Icons.add_circle_outline,
                color: kPrimary, size: 22),
          ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: kSubtle),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: kSubtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }

  Widget _statChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder.withOpacity(0.5)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                  color: kPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(
                  color: kSubtle,
                  fontWeight: FontWeight.w500,
                  fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}