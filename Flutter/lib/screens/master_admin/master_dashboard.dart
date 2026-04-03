import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../screens/admin/pages/hierarchy_report_page.dart';
// ─────────────────────────────────────────────
//  PALETTE
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
const kInfo    = Color(0xFF1565C0);
const kWarning = Color(0xFFE65100);
const kDevAccent = Color(0xFF00695C);
const kDevLight  = Color(0xFFE0F2F1);

// ─────────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────────
class SuperAdminModel {
  final int id;
  final String name;
  final String username;
  final DateTime createdAt;
  final int adminsUnder;
  final bool isActive;

  SuperAdminModel({
    required this.id,
    required this.name,
    required this.username,
    required this.createdAt,
    required this.adminsUnder,
    required this.isActive,
  });

  factory SuperAdminModel.fromJson(Map<String, dynamic> j) => SuperAdminModel(
        id:          j['id'],
        name:        j['name'],
        username:    j['username'],
        createdAt:   DateTime.parse(j['createdAt']),
        adminsUnder: j['adminsUnder'] ?? 0,
        isActive:    j['isActive'] ?? true,
      );
}

class SystemLogEntry {
  final int id;
  final String level;
  final String message;
  final String module;
  final DateTime time;

  SystemLogEntry({
    required this.id,
    required this.level,
    required this.message,
    required this.module,
    required this.time,
  });

  factory SystemLogEntry.fromJson(Map<String, dynamic> j) => SystemLogEntry(
        id:      j['id'] ?? 0,
        level:   j['level'],
        message: j['message'],
        module:  j['module'],
        time:    DateTime.parse(j['time']),
      );
}

class ApiHealthItem {
  final String endpoint;
  final String status;
  final int latencyMs;

  ApiHealthItem({
    required this.endpoint,
    required this.status,
    required this.latencyMs,
  });

  factory ApiHealthItem.fromJson(Map<String, dynamic> j) => ApiHealthItem(
        endpoint:  j['endpoint'],
        status:    j['status'],
        latencyMs: j['latencyMs'] ?? 0,
      );
}

// ─────────────────────────────────────────────
//  MASTER DASHBOARD
// ─────────────────────────────────────────────
class MasterDashboard extends StatefulWidget {
  const MasterDashboard({super.key});

  @override
  State<MasterDashboard> createState() => _MasterDashboardState();
}

class _MasterDashboardState extends State<MasterDashboard>
    with TickerProviderStateMixin {
  int _selectedTab = 0;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── State ──────────────────────────────────
  List<SuperAdminModel> _superAdmins = [];
  List<SystemLogEntry>  _logs        = [];
  List<ApiHealthItem>   _apiHealth   = [];
  Map<String, String>   _sysStats    = {};
  Map<String, dynamic>  _appConfig   = {};

  bool _loadingAdmins = true;
  bool _loadingLogs   = true;
  bool _loadingHealth = true;
  bool _loadingStats  = true;

  // ── Init ───────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _fetchAll();
  }

  Future<void> _fetchAll() async {
    await Future.wait([
      _fetchSuperAdmins(),
      _fetchLogs(),
      _fetchApiHealth(),
      _fetchSystemStats(),
      _fetchConfig(),
    ]);
  }

  // ── API Calls ──────────────────────────────

  Future<void> _fetchSuperAdmins() async {
    setState(() => _loadingAdmins = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/super-admins", token: token);
      setState(() {
        _superAdmins = (res["data"] as List)
            .map((e) => SuperAdminModel.fromJson(e))
            .toList();
      });
    } catch (e) {
      _snack("Failed to load Super Admins", kError);
    } finally {
      setState(() => _loadingAdmins = false);
    }
  }

  Future<void> _fetchLogs({String level = 'ALL'}) async {
    setState(() => _loadingLogs = true);
    try {
      final token = await AuthService.getToken();
      final query = level == 'ALL' ? '' : '?level=$level';
      final res   = await ApiService.get("/master/logs$query", token: token);
      setState(() {
        _logs = (res["data"] as List)
            .map((e) => SystemLogEntry.fromJson(e))
            .toList();
      });
    } catch (e) {
      _snack("Failed to load logs", kError);
    } finally {
      setState(() => _loadingLogs = false);
    }
  }

  Future<void> _fetchApiHealth() async {
    setState(() => _loadingHealth = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/health", token: token);
      setState(() {
        _apiHealth = (res["data"] as List)
            .map((e) => ApiHealthItem.fromJson(e))
            .toList();
      });
    } catch (e) {
      _snack("Failed to load API health", kError);
    } finally {
      setState(() => _loadingHealth = false);
    }
  }

  Future<void> _fetchSystemStats() async {
    setState(() => _loadingStats = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/system-stats", token: token);
      final d     = res["data"] as Map<String, dynamic>;
      setState(() {
        _sysStats = {
          'DB Size':       d['dbSize']       ?? 'N/A',
          'Total Records': '${d['totalRecords'] ?? 0}',
          'Flutter Build': d['flutterBuild'] ?? 'v1.0.0+1',
          'Backend':       d['backend']      ?? 'Flask 3.0',
          'Last Backup':   d['lastBackup']   ?? 'Never',
        };
      });
    } catch (_) {
      setState(() => _sysStats = {
        'DB Size': 'N/A', 'Total Records': 'N/A',
        'Flutter Build': 'v1.0.0+1', 'Backend': 'Flask 3.0',
        'Last Backup': 'N/A',
      });
    } finally {
      setState(() => _loadingStats = false);
    }
  }

  Future<void> _fetchConfig() async {
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/config", token: token);
      setState(() => _appConfig = res["data"] ?? {});
    } catch (_) {}
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

  // ──────────────────────────────────────────────
  //  CREATE SUPER ADMIN DIALOG
  // ──────────────────────────────────────────────
  void _showCreateSuperAdmin() {
    final nameCtrl    = TextEditingController();
    final userCtrl    = TextEditingController();
    final passCtrl    = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool  obscureP    = true;
    bool  obscureC    = true;
    final formKey     = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: kPrimary.withOpacity(0.2),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dlgHeader('Create Super Admin',
                      Icons.supervised_user_circle_outlined, ctx),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _dlgField(nameCtrl, 'Full Name',
                                Icons.person_outline,
                                validator: _notEmpty),
                            const SizedBox(height: 12),
                            _dlgField(userCtrl, 'Username',
                                Icons.alternate_email,
                                validator: _notEmpty),
                            const SizedBox(height: 12),
                            _dlgField(passCtrl, 'Password',
                                Icons.lock_outline,
                                obscure: obscureP,
                                suffixIcon: _eyeIcon(obscureP,
                                    () => setDlg(() => obscureP = !obscureP)),
                                validator: (v) => (v == null || v.length < 6)
                                    ? 'Min 6 chars'
                                    : null),
                            const SizedBox(height: 12),
                            _dlgField(confirmCtrl, 'Confirm Password',
                                Icons.lock_outline,
                                obscure: obscureC,
                                suffixIcon: _eyeIcon(obscureC,
                                    () => setDlg(() => obscureC = !obscureC)),
                                validator: (v) => v != passCtrl.text
                                    ? 'Passwords do not match'
                                    : null),
                            const SizedBox(height: 20),
                            _dlgActions(
                              onCancel: () => Navigator.pop(ctx),
                              // ✅ FIX 1 — correct async onConfirm (no nested setState)
                              onConfirm: () async {
                                if (formKey.currentState!.validate()) {
                                  try {
                                    final token =
                                        await AuthService.getToken();
                                    await ApiService.post(
                                      "/master/create-super-admin",
                                      {
                                        "name":     nameCtrl.text.trim(),
                                        "username": userCtrl.text.trim(),
                                        "password": passCtrl.text,
                                      },
                                      token: token,
                                    );
                                    Navigator.pop(ctx);
                                    _snack('Super Admin created', kSuccess);
                                    _fetchSuperAdmins();
                                  } catch (e) {
                                    _snack("Error creating admin", kError);
                                  }
                                }
                              },
                              confirmLabel: 'Create',
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

  // ──────────────────────────────────────────────
  //  DB TOOLS DIALOG
  // ──────────────────────────────────────────────
  void _showDbTools() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder, width: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dlgHeader('Database Tools', Icons.storage_outlined, ctx),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _dbToolTile(
                        Icons.backup_outlined, 'Backup Database',
                        'Export full MySQL dump to server', kSuccess,
                        () async {
                          Navigator.pop(ctx);
                          try {
                            final token = await AuthService.getToken();
                            await ApiService.post("/master/db/backup", {},
                                token: token);
                            _snack('Backup completed ✓', kSuccess);
                            _fetchSystemStats();
                          } catch (_) {
                            _snack('Backup failed', kError);
                          }
                        },
                      ),
                      _dbToolTile(
                        Icons.cleaning_services_outlined, 'Flush Cache',
                        'Clear server-side response cache', kInfo,
                        () async {
                          Navigator.pop(ctx);
                          try {
                            final token = await AuthService.getToken();
                            await ApiService.post(
                                "/master/db/flush-cache", {},
                                token: token);
                            _snack('Cache flushed', kInfo);
                          } catch (_) {
                            _snack('Failed to flush cache', kError);
                          }
                        },
                      ),
                      _dbToolTile(
                        Icons.delete_sweep_outlined, 'Reset All Duties',
                        'Remove all duty assignments (irreversible)', kError,
                        () {
                          Navigator.pop(ctx);
                          _confirmDestructive(
                            'Reset all duties?',
                            'This will delete every duty assignment in the system.',
                            () async {
                              try {
                                final token = await AuthService.getToken();
                                await ApiService.post(
                                    "/master/db/reset-duties", {},
                                    token: token);
                                _snack('All duties reset', kError);
                              } catch (_) {
                                _snack('Reset failed', kError);
                              }
                            },
                          );
                        },
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

  // ──────────────────────────────────────────────
  //  CONFIRM DESTRUCTIVE
  // ──────────────────────────────────────────────
  void _confirmDestructive(
      String title, String body, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: kError, width: 1.5)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: kError),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  color: kError, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Text(body,
            style: const TextStyle(color: kDark, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: kSubtle))),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); onConfirm(); },
            style: ElevatedButton.styleFrom(
                backgroundColor: kError, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  BUILD
  // ──────────────────────────────────────────────
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
      color: const Color(0xFF1A0A00),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 10, left: 16, right: 8,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: kDevAccent,
                borderRadius: BorderRadius.circular(6)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal, color: Colors.white, size: 13),
                SizedBox(width: 4),
                Text('DEV',
                    style: TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MASTER ADMIN CONSOLE',
                    style: TextStyle(
                        color: kBorder, fontSize: 11,
                        fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                Text('UP Election Cell — Developer Access',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _showDbTools,
            icon: const Icon(Icons.storage, size: 15, color: kBorder),
            label: const Text('DB Tools',
                style: TextStyle(
                    color: kBorder, fontSize: 12,
                    fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6)),
          ),
          // ✅ FIX 2 — correct logout (no double onPressed)
          IconButton(
            onPressed: () async {
              await AuthService.logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Icons.logout_rounded,
                color: Colors.white54, size: 20),
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  // ── TAB BAR ───────────────────────────────────
  Widget _buildTabBar() {
    final tabs = [
      (Icons.dashboard_outlined,          'Overview'),
      (Icons.supervised_user_circle,      'Super Admins'),
      (Icons.monitor_heart_outlined,      'API Health'),
      (Icons.receipt_long_outlined,       'Logs'),
      (Icons.settings_outlined,           'Config'),
    ];

    return Container(
      color: kSurface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final selected = _selectedTab == i;
            return GestureDetector(
              onTap: () => _switchTab(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? kBg : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                        color: selected ? kDevAccent : Colors.transparent,
                        width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(tabs[i].$1,
                        size: 15,
                        color: selected ? kDevAccent : kSubtle),
                    const SizedBox(width: 6),
                    Text(tabs[i].$2,
                        style: TextStyle(
                          color: selected ? kDevAccent : kSubtle,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 12,
                        )),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedTab) {
      case 0: return _buildOverview();
      case 1: return _buildSuperAdmins();
      case 2: return _buildApiHealth();
      case 3: return _buildLogs();
      case 4: return _buildConfig();
      default: return _buildOverview();
    }
  }

  // ──────────────────────────────────────────────
  //  TAB 0 — OVERVIEW
  // ──────────────────────────────────────────────
  Widget _buildOverview() {
    if (_loadingAdmins || _loadingStats) {
      return const Center(child: CircularProgressIndicator(color: kDevAccent));
    }

    return RefreshIndicator(
      onRefresh: _fetchAll,
      color: kDevAccent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth > 480 ? 4 : 2;
              return GridView.count(
                shrinkWrap: true,
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.45,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _statCard('Super Admins',
                      '${_superAdmins.length}',
                      Icons.supervised_user_circle_outlined, kDevAccent),
                  _statCard('Admins',
                      '${_superAdmins.fold(0, (s, a) => s + a.adminsUnder)}',
                      Icons.manage_accounts, kPrimary),
                  _statCard('API Endpoints',
                      '${_apiHealth.where((a) => a.status == "UP").length}/${_apiHealth.length} UP',
                      Icons.api_outlined, kInfo),
                  _statCard('System Errors',
                      '${_logs.where((l) => l.level == "ERROR").length}',
                      Icons.error_outline, kError),
                ],
              );
            }),

             // After the GridView in _buildOverview, add:
const SizedBox(height: 16),
GestureDetector(
  onTap: () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const HierarchyReportPage())),
  child: Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
          colors: [Color(0xFF0F2B5B), Color(0xFF1A3D7C)]),
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(
          color: kPrimary.withOpacity(0.25),
          blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: const Row(children: [
      Icon(Icons.table_chart_outlined, color: Colors.white, size: 22),
      SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hierarchy Report', style: TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
        Text('Super Zone · Sector · Panchayat',
            style: TextStyle(color: Colors.white60, fontSize: 11)),
      ])),
      Icon(Icons.chevron_right, color: Colors.white54),
    ]),
  ),
),



            const SizedBox(height: 18),
            _sectionLabel('System Information'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder.withOpacity(0.4)),
              ),
              child: Column(
                children: _sysStats.entries.toList().asMap().entries.map((e) {
                  final isLast = e.key == _sysStats.length - 1;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      border: isLast
                          ? null
                          : Border(
                              bottom: BorderSide(
                                  color: kBorder.withOpacity(0.3))),
                    ),
                    child: Row(
                      children: [
                        Text(e.value.key,
                            style: const TextStyle(
                                color: kSubtle,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: kSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: kBorder.withOpacity(0.4)),
                          ),
                          child: Text(e.value.value,
                              style: const TextStyle(
                                  color: kDark,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace')),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 18),
            _sectionLabel('Recent Activity'),
            const SizedBox(height: 10),

            if (_loadingLogs)
              const Center(child: CircularProgressIndicator(color: kDevAccent))
            else ...[
              ..._logs.take(4).map((l) => _logTile(l)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _switchTab(3),
                child: const Center(
                  child: Text('View All Logs →',
                      style: TextStyle(
                          color: kDevAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

 
  // ──────────────────────────────────────────────
  //  TAB 1 — SUPER ADMINS
  // ──────────────────────────────────────────────
  Widget _buildSuperAdmins() {
    if (_loadingAdmins) {
      return const Center(
          child: CircularProgressIndicator(color: kDevAccent));
    }

    return Column(
      children: [
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_superAdmins.length} Super Admin(s)',
                  style: const TextStyle(
                      color: kDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateSuperAdmin,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Super Admin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDevAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchSuperAdmins,
            color: kDevAccent,
            child: _superAdmins.isEmpty
                ? const Center(
                    child: Text('No Super Admins found',
                        style: TextStyle(color: kSubtle, fontSize: 14)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _superAdmins.length,
                    itemBuilder: (_, i) =>
                        _superAdminCard(_superAdmins[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _superAdminCard(SuperAdminModel sa) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
              color: kPrimary.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sa.isActive
                  ? kDevAccent.withOpacity(0.08)
                  : kError.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: kDark,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('SA${sa.id.toString().padLeft(3, '0')}',
                      style: const TextStyle(
                          color: kBorder,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(sa.name,
                      style: const TextStyle(
                          color: kDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                // ✅ FIX 3 — correct async onTap for toggle
                GestureDetector(
                  onTap: () async {
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.put(
                        "/master/super-admin/${sa.id}/status",
                        {"isActive": !sa.isActive},
                        token: token,
                      );
                      _fetchSuperAdmins();
                    } catch (_) {
                      _snack('Failed to update status', kError);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: sa.isActive
                          ? kSuccess.withOpacity(0.12)
                          : kError.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sa.isActive ? kSuccess : kError,
                          width: 1),
                    ),
                    child: Text(
                      sa.isActive ? 'ACTIVE' : 'INACTIVE',
                      style: TextStyle(
                          color: sa.isActive ? kSuccess : kError,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // ✅ FIX 4 — correct async delete (no await inside setState)
                IconButton(
                  onPressed: () => _confirmDestructive(
                    'Remove Super Admin?',
                    'This will also affect all admins under ${sa.name}.',
                    () async {
                      try {
                        final token = await AuthService.getToken();
                        await ApiService.delete(
                          "/master/super-admin/${sa.id}",
                          token: token,
                        );
                        _fetchSuperAdmins();
                        _snack('Super Admin removed', kError);
                      } catch (_) {
                        _snack('Failed to delete', kError);
                      }
                    },
                  ),
                  icon: const Icon(Icons.delete_outline,
                      color: kError, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(Icons.alternate_email, '@${sa.username}'),
                      const SizedBox(height: 4),
                      _infoRow(Icons.calendar_today_outlined,
                          'Created ${_fmt(sa.createdAt)}'),
                    ],
                  ),
                ),
                _pill('${sa.adminsUnder} Admins', kPrimary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  TAB 2 — API HEALTH
  // ──────────────────────────────────────────────
  Widget _buildApiHealth() {
    if (_loadingHealth) {
      return const Center(
          child: CircularProgressIndicator(color: kDevAccent));
    }

    final upCount   = _apiHealth.where((a) => a.status == 'UP').length;
    final downCount = _apiHealth.where((a) => a.status == 'DOWN').length;
    final slowCount = _apiHealth.where((a) => a.status == 'SLOW').length;

    return RefreshIndicator(
      onRefresh: _fetchApiHealth,
      color: kDevAccent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _healthSummary('$upCount UP',     kSuccess),
                const SizedBox(width: 8),
                _healthSummary('$downCount DOWN', kError),
                const SizedBox(width: 8),
                _healthSummary('$slowCount SLOW', kWarning),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    _fetchApiHealth();
                    _snack('Pinging all endpoints…', kInfo);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: kDevAccent,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(
                      children: [
                        Icon(Icons.refresh, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('Ping All',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder.withOpacity(0.4)),
              ),
              child: Column(
                children: _apiHealth.asMap().entries.map((e) {
                  final isLast = e.key == _apiHealth.length - 1;
                  return _apiRow(e.value, isLast);
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),
            _sectionLabel('Flask Backend Info'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _codeRow('Host',    'localhost:5000'),
                  _codeRow('DB',      'mysql://election_db'),
                  _codeRow('CORS',    'enabled'),
                  _codeRow('JWT Exp', '10 hours'),
                  _codeRow('Mode',    'debug=True'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _apiRow(ApiHealthItem item, bool isLast) {
    Color statusColor;
    IconData statusIcon;
    switch (item.status) {
      case 'UP':
        statusColor = kSuccess;
        statusIcon  = Icons.check_circle;
        break;
      case 'DOWN':
        statusColor = kError;
        statusIcon  = Icons.cancel;
        break;
      default:
        statusColor = kWarning;
        statusIcon  = Icons.warning_amber;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: kBorder.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(item.endpoint,
                style: const TextStyle(
                    color: kDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace')),
          ),
          if (item.latencyMs > 0)
            Text('${item.latencyMs} ms',
                style: TextStyle(
                    color: item.latencyMs > 500 ? kWarning : kSubtle,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Text(item.status,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _codeRow(String key, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$key:  ',
              style: const TextStyle(
                  color: Color(0xFF64B5F6),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600)),
          Text(val,
              style: const TextStyle(
                  color: Color(0xFFA5D6A7),
                  fontSize: 12,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  TAB 3 — SYSTEM LOGS
  // ──────────────────────────────────────────────
  Widget _buildLogs() {
    return StatefulBuilder(builder: (ctx, setLocal) {
      String filter = 'ALL';

      void applyFilter(String f) {
        setLocal(() => filter = f);
        _fetchLogs(level: f);
      }

      final filtered = filter == 'ALL'
          ? _logs
          : _logs.where((l) => l.level == filter).toList();

      return Column(
        children: [
          Container(
            color: kSurface,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Row(
              children: ['ALL', 'INFO', 'WARN', 'ERROR']
                  .map((f) => GestureDetector(
                        onTap: () => applyFilter(f),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: filter == f
                                ? _logColor(f)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _logColor(f).withOpacity(0.5)),
                          ),
                          child: Text(f,
                              style: TextStyle(
                                color: filter == f
                                    ? Colors.white
                                    : _logColor(f),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              )),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: _loadingLogs
                ? const Center(
                    child:
                        CircularProgressIndicator(color: kDevAccent))
                : RefreshIndicator(
                    onRefresh: () => _fetchLogs(level: filter),
                    color: kDevAccent,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _logTile(filtered[i]),
                    ),
                  ),
          ),
        ],
      );
    });
  }

  Widget _logTile(SystemLogEntry log) {
    final color = _logColor(log.level);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(4)),
            child: Text(log.level,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.message,
                    style: const TextStyle(
                        color: kDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('${log.module}  •  ',
                        style:
                            const TextStyle(color: kSubtle, fontSize: 11)),
                    Text(_fmtTime(log.time),
                        style:
                            const TextStyle(color: kSubtle, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  TAB 4 — CONFIG
  // ──────────────────────────────────────────────
  Widget _buildConfig() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Application Settings'),
          const SizedBox(height: 10),
          _configGroup([
            _configToggle(
              'Maintenance Mode',
              'Disable app for all users',
              _appConfig['maintenanceMode'] == 'true',
              (v) => _updateConfig('maintenanceMode', v),
            ),
            _configToggle(
              'Allow Staff Login',
              'Enable/disable staff access',
              _appConfig['allowStaffLogin'] != 'false',
              (v) => _updateConfig('allowStaffLogin', v),
            ),
            _configToggle(
              'Force Password Reset',
              'Prompt all admins to reset password',
              _appConfig['forcePasswordReset'] == 'true',
              (v) => _updateConfig('forcePasswordReset', v),
            ),
          ]),

          const SizedBox(height: 18),
          _sectionLabel('Election Settings'),
          const SizedBox(height: 10),
          _configGroup([
            _configInfo('Election Year', _appConfig['electionYear']  ?? '2026'),
            _configInfo('State',         _appConfig['state']         ?? 'Uttar Pradesh'),
            _configInfo('Phase',         _appConfig['phase']         ?? 'Phase 1'),
            _configInfo('Election Date', _appConfig['electionDate']  ?? '15 Apr 2026'),
          ]),

          const SizedBox(height: 18),
          _sectionLabel('Developer Tools'),
          const SizedBox(height: 10),
          _configGroup([
            _devAction(
              Icons.bug_report_outlined, 'Run Diagnostics',
              'Check DB, API and storage health',
              () => _snack('Running diagnostics…', kInfo),
            ),
            _devAction(
              Icons.data_object_outlined, 'Export All Data (JSON)',
              'Download full system data snapshot',
              () => _snack('Export initiated…', kSuccess),
            ),
            _devAction(
              Icons.delete_forever_outlined, 'Wipe All Test Data',
              'Remove all non-production records',
              () => _confirmDestructive(
                'Wipe test data?',
                'This permanently deletes all test records.',
                () => _snack('Test data wiped', kError),
              ),
            ),
            _devAction(
              Icons.info_outline, 'App Version Info',
              'Flutter 3.x · Flask 3.0 · MySQL 8.0',
              () {},
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _updateConfig(String key, dynamic value) async {
    try {
      final token = await AuthService.getToken();
      await ApiService.post(
        "/master/config",
        {"key": key, "value": value},
        token: token,
      );
      _fetchConfig();
      _snack('Config updated', kSuccess);
    } catch (_) {
      _snack('Failed to update config', kError);
    }
  }

  // ── CONFIG HELPERS ────────────────────────────
  Widget _configGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.4)),
      ),
      child: Column(
        children: children.asMap().entries.map((e) {
          final isLast = e.key == children.length - 1;
          return Container(
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(color: kBorder.withOpacity(0.25))),
            ),
            child: e.value,
          );
        }).toList(),
      ),
    );
  }

  Widget _configToggle(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return StatefulBuilder(builder: (ctx, setLocal) {
      bool val = value;
      return ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        title: Text(title,
            style: const TextStyle(
                color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: kSubtle, fontSize: 11)),
        trailing: Switch(
          value: val,
          onChanged: (v) {
            setLocal(() => val = v);
            onChanged(v);
          },
          activeColor: kDevAccent,
        ),
      );
    });
  }

  Widget _configInfo(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Text(key,
              style: const TextStyle(
                  color: kSubtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: kDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _devAction(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
            color: kDevLight, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: kDevAccent, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: kSubtle, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, color: kSubtle, size: 18),
    );
  }

  Widget _dbToolTile(IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: kSubtle, fontSize: 11)),
      trailing: Icon(Icons.arrow_forward_ios, color: color, size: 14),
    );
  }

  // ── SHARED SMALL WIDGETS ──────────────────────
  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.07),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(
                  color: kSubtle, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Row(
      children: [
        Container(
            width: 4, height: 16,
            decoration: BoxDecoration(
                color: kDevAccent,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: kDark, fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 13, color: kSubtle),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: kSubtle, fontSize: 12)),
    ]);
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
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _healthSummary(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }

  Color _logColor(String level) {
    switch (level) {
      case 'ERROR': return kError;
      case 'WARN':  return kWarning;
      default:      return kInfo;
    }
  }

  // ── DIALOG HELPERS ────────────────────────────
  Widget _dlgHeader(String title, IconData icon, BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: kDark,
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(15), topRight: Radius.circular(15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: kBorder, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
          IconButton(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _dlgField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      validator: validator,
      style: const TextStyle(color: kDark, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: kPrimary),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kPrimary, width: 2)),
        labelStyle: const TextStyle(color: kSubtle),
      ),
    );
  }

  Widget _eyeIcon(bool obscure, VoidCallback onTap) {
    return IconButton(
      icon: Icon(
          obscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 18,
          color: kSubtle),
      onPressed: onTap,
    );
  }

  Widget _dlgActions({
    required VoidCallback onCancel,
    required VoidCallback onConfirm,
    required String confirmLabel,
  }) {
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: kSubtle,
            side: const BorderSide(color: kBorder),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Cancel'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: kDevAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(confirmLabel),
        ),
      ),
    ]);
  }

  String? _notEmpty(String? v) =>
      (v == null || v.isEmpty) ? 'Required' : null;

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  String _fmtTime(DateTime dt) =>
      '${_fmt(dt)}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }
}