import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../admin/pages/hierarchy_report_page.dart';
import '../admin/map_view.dart';

// ─────────────────────────────────────────────
//  PALETTE
// ─────────────────────────────────────────────
const kBg       = Color(0xFFFDF6E3);
const kSurface  = Color(0xFFF5E6C8);
const kPrimary  = Color(0xFF8B6914);
const kAccent   = Color(0xFFB8860B);
const kDark     = Color(0xFF4A3000);
const kSubtle   = Color(0xFFAA8844);
const kBorder   = Color(0xFFD4A843);
const kError    = Color(0xFFC0392B);
const kSuccess  = Color(0xFF2E7D32);
const kInfo     = Color(0xFF1565C0);
const kWarning  = Color(0xFFE65100);
const kDevAccent = Color(0xFF00695C);
const kDevLight  = Color(0xFFE0F2F1);

// ─────────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────────
class SuperAdminModel {
  final int    id;
  final String name;
  final String username;
  final DateTime createdAt;
  final int    adminsUnder;
  final bool   isActive;
  final Map<String, dynamic> electionInfo;

  SuperAdminModel({
    required this.id,
    required this.name,
    required this.username,
    required this.createdAt,
    required this.adminsUnder,
    required this.isActive,
    this.electionInfo = const {},
  });

  factory SuperAdminModel.fromJson(Map<String, dynamic> j) => SuperAdminModel(
        id:           j['id'],
        name:         j['name'] ?? '',
        username:     j['username'] ?? '',
        createdAt:    DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        adminsUnder:  j['adminsUnder'] ?? 0,
        isActive:     j['isActive'] ?? true,
        electionInfo: Map<String, dynamic>.from(j['electionInfo'] ?? {}),
      );
}

class AdminModel {
  final int    id;
  final String name;
  final String username;
  final String district;
  final bool   isActive;
  final DateTime createdAt;
  final String createdBy;
  final int    superZoneCount;

  AdminModel({
    required this.id,
    required this.name,
    required this.username,
    required this.district,
    required this.isActive,
    required this.createdAt,
    required this.createdBy,
    required this.superZoneCount,
  });

  factory AdminModel.fromJson(Map<String, dynamic> j) => AdminModel(
        id:             j['id'],
        name:           j['name'] ?? '',
        username:       j['username'] ?? '',
        district:       j['district'] ?? '',
        isActive:       j['isActive'] ?? true,
        createdAt:      DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        createdBy:      j['createdBy'] ?? 'master',
        superZoneCount: j['superZoneCount'] ?? 0,
      );
}

class SystemLogEntry {
  final int    id;
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
        level:   j['level'] ?? 'INFO',
        message: j['message'] ?? '',
        module:  j['module'] ?? '',
        time:    DateTime.tryParse(j['time'] ?? '') ?? DateTime.now(),
      );
}

class OverviewStats {
  final int totalSuperAdmins;
  final int totalAdmins;
  final int totalStaff;
  final int totalBooths;
  final int assignedDuties;
  final Map<String, String> electionInfo;

  OverviewStats({
    this.totalSuperAdmins = 0,
    this.totalAdmins      = 0,
    this.totalStaff       = 0,
    this.totalBooths      = 0,
    this.assignedDuties   = 0,
    this.electionInfo     = const {},
  });

  factory OverviewStats.fromJson(Map<String, dynamic> j) => OverviewStats(
        totalSuperAdmins: j['totalSuperAdmins'] ?? 0,
        totalAdmins:      j['totalAdmins']      ?? 0,
        totalStaff:       j['totalStaff']       ?? 0,
        totalBooths:      j['totalBooths']      ?? 0,
        assignedDuties:   j['assignedDuties']   ?? 0,
        electionInfo: Map<String, String>.from(
          (j['electionInfo'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, v?.toString() ?? '')),
        ),
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
  late final Animation<double>   _fadeAnim;

  // ── Data ───────────────────────────────────
  List<SuperAdminModel> _superAdmins = [];
  List<AdminModel>      _admins      = [];
  List<SystemLogEntry>  _logs        = [];
  Map<String, String>   _sysStats    = {};
  Map<String, dynamic>  _appConfig   = {};
  OverviewStats         _overview    = OverviewStats();

  // ── Loading flags ──────────────────────────
  bool _loadingOverview    = true;
  bool _loadingSuperAdmins = true;
  bool _loadingAdmins      = true;
  bool _loadingLogs        = true;
  bool _loadingStats       = true;
  bool _loadingConfig      = true;

  String _logFilter = 'ALL';

  // ─────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _fetchAll();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── FETCH ALL ─────────────────────────────
  Future<void> _fetchAll() => Future.wait([
        _fetchOverview(),
        _fetchSuperAdmins(),
        _fetchAdmins(),
        _fetchLogs(),
        _fetchSystemStats(),
        _fetchConfig(),
      ]);

  // ── Individual fetches ────────────────────
  Future<void> _fetchOverview() async {
    setState(() => _loadingOverview = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/overview", token: token);
      setState(() => _overview = OverviewStats.fromJson(res["data"] ?? {}));
    } catch (_) {
      // keep defaults
    } finally {
      if (mounted) setState(() => _loadingOverview = false);
    }
  }

  Future<void> _fetchSuperAdmins() async {
    setState(() => _loadingSuperAdmins = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/super-admins", token: token);
      setState(() {
        _superAdmins = (res["data"] as List? ?? [])
            .map((e) => SuperAdminModel.fromJson(e))
            .toList();
      });
    } catch (e) {
      _snack("Failed to load Super Admins", kError);
    } finally {
      if (mounted) setState(() => _loadingSuperAdmins = false);
    }
  }

  Future<void> _fetchAdmins() async {
    setState(() => _loadingAdmins = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/admins", token: token);
      setState(() {
        _admins = (res["data"] as List? ?? [])
            .map((e) => AdminModel.fromJson(e))
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => _admins = []);
    } finally {
      if (mounted) setState(() => _loadingAdmins = false);
    }
  }

  Future<void> _fetchLogs({String level = 'ALL'}) async {
    setState(() => _loadingLogs = true);
    try {
      final token = await AuthService.getToken();
      final query = level == 'ALL' ? '' : '?level=$level';
      final res   = await ApiService.get("/master/logs$query", token: token);
      setState(() {
        _logs = (res["data"] as List? ?? [])
            .map((e) => SystemLogEntry.fromJson(e))
            .toList();
      });
    } catch (e) {
      _snack("Failed to load logs", kError);
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _fetchSystemStats() async {
    setState(() => _loadingStats = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/system-stats", token: token);
      final d     = res["data"] as Map<String, dynamic>? ?? {};
      setState(() {
        _sysStats = {
          'DB Size':       d['dbSize']?.toString()       ?? 'N/A',
          'Total Records': '${d['totalRecords']          ?? 0}',
          'Uptime':        d['uptime']?.toString()       ?? 'N/A',
          'Last Backup':   d['lastBackup']?.toString()   ?? 'Never',
          'Backend':       d['backend']?.toString()      ?? 'Flask',
        };
      });
    } catch (_) {
      if (mounted) setState(() => _sysStats = {
        'DB Size': 'N/A', 'Total Records': 'N/A',
        'Uptime': 'N/A', 'Last Backup': 'N/A', 'Backend': 'Flask',
      });
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _fetchConfig() async {
    setState(() => _loadingConfig = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/config", token: token);
      setState(() {
        _appConfig = Map<String, dynamic>.from(res["data"] ?? {});
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  // ─────────────────────────────────────────
  void _switchTab(int i) {
    setState(() => _selectedTab = i);
    _fadeCtrl.forward(from: 0);
  }

  // ══════════════════════════════════════════
  //  DIALOGS — CREATE SUPER ADMIN
  // ══════════════════════════════════════════
  void _showCreateSuperAdmin() {
    final nameCtrl     = TextEditingController();
    final userCtrl     = TextEditingController();
    final districtCtrl = TextEditingController(); // ✅ NEW
    final passCtrl     = TextEditingController();
    final confirmCtrl  = TextEditingController();

    bool obscureP = true;
    bool obscureC = true;

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => _styledDialog(
          title: 'Create Super Admin',
          icon: Icons.supervised_user_circle_outlined,
          ctx: ctx,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dlgField(nameCtrl, 'Full Name', Icons.person_outline,
                    validator: _notEmpty),
                const SizedBox(height: 12),

                _dlgField(userCtrl, 'Username', Icons.alternate_email,
                    validator: _notEmpty),
                const SizedBox(height: 12),

                // ✅ NEW DISTRICT FIELD
                _dlgField(
                  districtCtrl,
                  'District',
                  Icons.location_city_outlined,
                  validator: _notEmpty,
                ),
                const SizedBox(height: 12),

                _dlgField(passCtrl, 'Password', Icons.lock_outline,
                    obscure: obscureP,
                    suffixIcon: _eyeIcon(
                        obscureP, () => setDlg(() => obscureP = !obscureP)),
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'Min 6 chars' : null),
                const SizedBox(height: 12),

                _dlgField(confirmCtrl, 'Confirm Password', Icons.lock_outline,
                    obscure: obscureC,
                    suffixIcon: _eyeIcon(
                        obscureC, () => setDlg(() => obscureC = !obscureC)),
                    validator: (v) =>
                        v != passCtrl.text ? 'Passwords do not match' : null),

                const SizedBox(height: 20),

                _dlgActions(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () async {
                    if (!formKey.currentState!.validate()) return;

                    try {
                      final token = await AuthService.getToken();

                      await ApiService.post(
                        "/master/super-admins",
                        {
                          "name": nameCtrl.text.trim(),
                          "username": userCtrl.text.trim(),
                          "password": passCtrl.text,
                          "district": districtCtrl.text.trim(), // ✅ SEND
                        },
                        token: token,
                      );

                      if (ctx.mounted) Navigator.pop(ctx);

                      _snack('Super Admin created ✓', kSuccess);
                      _fetchSuperAdmins();
                      _fetchOverview();

                    } catch (e) {
                      _snack("Error: $e", kError);
                    }
                  },
                  confirmLabel: 'Create',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── CREATE ADMIN DIALOG ───────────────────
  void _showCreateAdmin() {
    final nameCtrl     = TextEditingController();
    final userCtrl     = TextEditingController();
    final districtCtrl = TextEditingController();
    final passCtrl     = TextEditingController();
    final confirmCtrl  = TextEditingController();
    bool  obscureP     = true;
    bool  obscureC     = true;
    final formKey      = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => _styledDialog(
          title: 'Create Admin',
          icon: Icons.manage_accounts_outlined,
          ctx: ctx,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dlgField(nameCtrl, 'Full Name', Icons.person_outline,
                    validator: _notEmpty),
                const SizedBox(height: 12),
                _dlgField(userCtrl, 'Username', Icons.alternate_email,
                    validator: _notEmpty),
                const SizedBox(height: 12),
                _dlgField(districtCtrl, 'District', Icons.location_city_outlined,
                    validator: _notEmpty),
                const SizedBox(height: 12),
                _dlgField(passCtrl, 'Password', Icons.lock_outline,
                    obscure: obscureP,
                    suffixIcon: _eyeIcon(
                        obscureP, () => setDlg(() => obscureP = !obscureP)),
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'Min 6 chars' : null),
                const SizedBox(height: 12),
                _dlgField(confirmCtrl, 'Confirm Password', Icons.lock_outline,
                    obscure: obscureC,
                    suffixIcon: _eyeIcon(
                        obscureC, () => setDlg(() => obscureC = !obscureC)),
                    validator: (v) =>
                        v != passCtrl.text ? 'Passwords do not match' : null),
                const SizedBox(height: 20),
                _dlgActions(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.post(
                        "/master/admins",
                        {
                          "name":     nameCtrl.text.trim(),
                          "username": userCtrl.text.trim(),
                          "district": districtCtrl.text.trim(),
                          "password": passCtrl.text,
                        },
                        token: token,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('Admin created ✓', kSuccess);
                      _fetchAdmins();
                      _fetchOverview();
                    } catch (e) {
                      _snack("Error: $e", kError);
                    }
                  },
                  confirmLabel: 'Create',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── EDIT ELECTION CONFIG DIALOG ───────────
  void _showEditElectionConfig() {
    final stateCtrl = TextEditingController(text: _appConfig['state'] ?? '');
    final yearCtrl  = TextEditingController(text: _appConfig['electionYear'] ?? '');
    final dateCtrl  = TextEditingController(text: _appConfig['electionDate'] ?? '');
    final phaseCtrl = TextEditingController(text: _appConfig['phase'] ?? '');
    final formKey   = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _styledDialog(
        title: 'Edit Election Settings',
        icon: Icons.how_to_vote_outlined,
        ctx: ctx,
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              _dlgField(stateCtrl, 'State', Icons.map_outlined,
                  validator: _notEmpty),
              const SizedBox(height: 12),

              _dlgField(yearCtrl, 'Election Year',
                  Icons.calendar_today_outlined,
                  validator: _notEmpty),
              const SizedBox(height: 12),

              // 🔥🔥 UPDATED DATE PICKER FIELD
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dateCtrl.text.isNotEmpty
                        ? DateTime.tryParse(dateCtrl.text) ?? DateTime.now()
                        : DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );

                  if (picked != null) {
                    // ✅ store clean ISO format
                    dateCtrl.text =
                        picked.toIso8601String().split("T")[0];
                  }
                },
                child: AbsorbPointer(
                  child: _dlgField(
                    dateCtrl,
                    'Election Date',
                    Icons.event_outlined,
                    validator: _notEmpty,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              _dlgField(phaseCtrl, 'Phase (e.g. Phase 1)',
                  Icons.flag_outlined,
                  validator: _notEmpty),

              const SizedBox(height: 20),

              _dlgActions(
                onCancel: () => Navigator.pop(ctx),
                onConfirm: () async {
                  if (!formKey.currentState!.validate()) return;

                  try {
                    final token = await AuthService.getToken();

                    await ApiService.post(
                      "/master/config",
                      {
                        "state":        stateCtrl.text.trim(),
                        "electionYear": yearCtrl.text.trim(),
                        "electionDate": dateCtrl.text.trim(), // ✅ clean date
                        "phase":        phaseCtrl.text.trim(),
                      },
                      token: token,
                    );

                    if (ctx.mounted) Navigator.pop(ctx);

                    _snack('Election settings updated ✓', kSuccess);
                    _fetchConfig();
                    _fetchOverview();

                  } catch (e) {
                    _snack("Error: $e", kError);
                  }
                },
                confirmLabel: 'Save',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── RESET PASSWORD DIALOG ─────────────────
  void _showResetPassword(int id, String name, String role) {
    final passCtrl    = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool  obscureP    = true;
    bool  obscureC    = true;
    final formKey     = GlobalKey<FormState>();
    final endpoint    = role == 'super_admin'
        ? "/master/super-admins/$id/reset-password"
        : "/master/admins/$id/reset-password";

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => _styledDialog(
          title: 'Reset Password — $name',
          icon: Icons.lock_reset_outlined,
          ctx: ctx,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dlgField(passCtrl, 'New Password', Icons.lock_outline,
                    obscure: obscureP,
                    suffixIcon: _eyeIcon(
                        obscureP, () => setDlg(() => obscureP = !obscureP)),
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'Min 6 chars' : null),
                const SizedBox(height: 12),
                _dlgField(confirmCtrl, 'Confirm Password', Icons.lock_outline,
                    obscure: obscureC,
                    suffixIcon: _eyeIcon(
                        obscureC, () => setDlg(() => obscureC = !obscureC)),
                    validator: (v) =>
                        v != passCtrl.text ? 'Passwords do not match' : null),
                const SizedBox(height: 20),
                _dlgActions(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.patch(endpoint,
                          {"password": passCtrl.text}, token: token);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('Password reset ✓', kSuccess);
                    } catch (e) {
                      _snack("Error: $e", kError);
                    }
                  },
                  confirmLabel: 'Reset',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── DB TOOLS DIALOG ───────────────────────
  void _showDbTools() {
    showDialog(
      context: context,
      builder: (ctx) => _styledDialog(
        title: 'Database Tools',
        icon: Icons.storage_outlined,
        ctx: ctx,
        child: Column(
          children: [
            _dbToolTile(Icons.backup_outlined, 'Backup Database',
                'Export full MySQL dump to server', kSuccess, () async {
              Navigator.pop(ctx);
              try {
                final token = await AuthService.getToken();
                await ApiService.post("/master/db/backup", {}, token: token);
                _snack('Backup completed ✓', kSuccess);
                _fetchSystemStats();
              } catch (_) {
                _snack('Backup failed', kError);
              }
            }),
            _dbToolTile(Icons.cleaning_services_outlined, 'Flush Cache',
                'Clear server-side response cache', kInfo, () async {
              Navigator.pop(ctx);
              try {
                final token = await AuthService.getToken();
                await ApiService.post("/master/db/flush-cache", {},
                    token: token);
                _snack('Cache flushed ✓', kInfo);
              } catch (_) {
                _snack('Failed to flush cache', kError);
              }
            }),
            _dbToolTile(Icons.build_outlined, 'Run Migrations',
                'Apply DB schema updates safely', kWarning, () async {
              Navigator.pop(ctx);
              try {
                final token = await AuthService.getToken();
                await ApiService.post("/master/migrate", {}, token: token);
                _snack('Migrations completed ✓', kSuccess);
              } catch (_) {
                _snack('Migration failed', kError);
              }
            }),
          ],
        ),
      ),
    );
  }

  // ── CONFIRM DESTRUCTIVE ───────────────────
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
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: kError,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ),
        ]),
        content: Text(body,
            style: const TextStyle(color: kDark, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: kSubtle))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: kError, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
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
      ),
    );
  }

  // ── TOP BAR ───────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: const Color(0xFF1A0A00),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // DEV badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: kDevAccent, borderRadius: BorderRadius.circular(6)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal, color: Colors.white, size: 12),
                SizedBox(width: 4),
                Text('MASTER',
                    style: TextStyle(
                        color: Colors.white, fontSize: 10,
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
                        fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                Text('Election Management — Developer Access',
                    style: TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
          // DB Tools
          _topBarBtn(Icons.storage, 'DB', _showDbTools),
          // Refresh
          _topBarBtn(Icons.refresh, 'Sync', () {
            _fetchAll();
            _snack('Refreshing all data…', kInfo);
          }),
          // Logout
          IconButton(
            onPressed: () async {
              await AuthService.logout();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Icons.logout_rounded,
                color: Colors.white54, size: 20),
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  Widget _topBarBtn(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: kBorder),
      label: Text(label,
          style: const TextStyle(
              color: kBorder, fontSize: 11, fontWeight: FontWeight.w700)),
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
    );
  }

  // ── TAB BAR ───────────────────────────────
  Widget _buildTabBar() {
    final tabs = [
      (Icons.dashboard_outlined,        'Overview'),
      (Icons.supervised_user_circle,    'Super Admins'),
      (Icons.manage_accounts_outlined,  'Admins'),
      (Icons.receipt_long_outlined,     'Logs'),
      (Icons.settings_outlined,         'Config'),
    ];
    return Container(
      color: kSurface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final sel = _selectedTab == i;
            return GestureDetector(
              onTap: () => _switchTab(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: sel ? kBg : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                        color: sel ? kDevAccent : Colors.transparent,
                        width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(tabs[i].$1,
                        size: 14,
                        color: sel ? kDevAccent : kSubtle),
                    const SizedBox(width: 6),
                    Text(tabs[i].$2,
                        style: TextStyle(
                          color: sel ? kDevAccent : kSubtle,
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w500,
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
      case 2: return _buildAdmins();
      case 3: return _buildLogs();
      case 4: return _buildConfig();
      default: return _buildOverview();
    }
  }

  // ══════════════════════════════════════════
  //  TAB 0 — OVERVIEW
  // ══════════════════════════════════════════
  Widget _buildOverview() {
    if (_loadingOverview && _loadingStats) {
      return const Center(
          child: CircularProgressIndicator(color: kDevAccent));
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

            // ── Election Banner ─────────
            _electionBanner(),
            const SizedBox(height: 14),

            // ── Stats Grid ─────────────
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth > 480 ? 4 : 2;
              return GridView.count(
                shrinkWrap: true,
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.4,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _statCard('Super Admins',
                      '${_overview.totalSuperAdmins}',
                      Icons.supervised_user_circle_outlined, kDevAccent),
                  _statCard('Admins',
                      '${_overview.totalAdmins}',
                      Icons.manage_accounts, kPrimary),
                  _statCard('Staff',
                      '${_overview.totalStaff}',
                      Icons.groups_outlined, kInfo),
                  _statCard('Booths',
                      '${_overview.totalBooths}',
                      Icons.how_to_vote_outlined, kSuccess),
                ],
              );
            }),

            const SizedBox(height: 16),

            // 🔥 ── HIERARCHY REPORT BUTTON ─────────
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const HierarchyReportPage(role: "master"),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F2B5B), Color(0xFF1A3D7C)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.table_chart_outlined,
                        color: Colors.white, size: 22),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Hierarchy Report',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 🔥 ── MAP VIEW BUTTON ─────────
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MapViewPage(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00695C), Color(0xFF00897B)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.map, color: Colors.white, size: 22),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Map View',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ── System Info ─────────
            _sectionLabel('System Information'),
            const SizedBox(height: 10),
            _infoTable(_sysStats),

            const SizedBox(height: 18),

            // ── Logs ─────────
            _sectionLabel('Recent Activity'),
            const SizedBox(height: 10),

            if (_loadingLogs)
              const Center(
                  child: CircularProgressIndicator(color: kDevAccent))
            else ...[
              ..._logs.take(5).map(_logTile),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _electionBanner() {
    final ei = _overview.electionInfo;
    final state = ei['state'] ?? _appConfig['state'] ?? '';
    final year  = ei['electionYear'] ?? _appConfig['electionYear'] ?? '';
    final date  = ei['electionDate'] ?? _appConfig['electionDate'] ?? '';
    final phase = ei['phase'] ?? _appConfig['phase'] ?? '';

    final hasData = state.isNotEmpty || year.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1A0A00), Color(0xFF3D1A00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.5)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.how_to_vote, color: kBorder, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: hasData
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$state Election $year',
                          style: const TextStyle(
                              color: kBorder,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      if (phase.isNotEmpty || date.isNotEmpty)
                        Text('$phase  •  $date',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11)),
                    ],
                  )
                : const Text('No election details configured yet',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          GestureDetector(
            onTap: _showEditElectionConfig,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: kDevAccent,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.edit, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text('Edit',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 1 — SUPER ADMINS
  // ══════════════════════════════════════════
  Widget _buildSuperAdmins() {
    return Column(
      children: [
        _listHeader(
          title: '${_superAdmins.length} Super Admin(s)',   // ← named param
          onRefresh: _fetchSuperAdmins,
          buttonLabel: 'New Super Admin',
          buttonIcon: Icons.add,
          onButton: _showCreateSuperAdmin,
        ),
        Expanded(
          child: _loadingSuperAdmins
              ? const Center(
                  child: CircularProgressIndicator(color: kDevAccent))
              : RefreshIndicator(
                  onRefresh: _fetchSuperAdmins,
                  color: kDevAccent,
                  child: _superAdmins.isEmpty
                      ? _emptyState(
                          'No Super Admins yet',
                          'Tap "New Super Admin" to create one',
                          Icons.supervised_user_circle_outlined)
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
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sa.isActive
                  ? kDevAccent.withOpacity(0.07)
                  : kError.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                _idBadge('SA', sa.id),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(sa.name,
                      style: const TextStyle(
                          color: kDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                // Status toggle
                GestureDetector(
                  onTap: () async {
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.patch(
                        "/master/super-admins/${sa.id}/status",
                        {"isActive": !sa.isActive},
                        token: token,
                      );
                      _fetchSuperAdmins();
                    } catch (_) {
                      _snack('Failed to update status', kError);
                    }
                  },
                  child: _statusBadge(sa.isActive),
                ),
                const SizedBox(width: 6),
                // Menu
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'reset') _showResetPassword(sa.id, sa.name, 'super_admin');
                    if (v == 'delete') {
                      _confirmDestructive(
                        'Remove Super Admin?',
                        'This will affect all admins under ${sa.name}.',
                        () async {
                          try {
                            final token = await AuthService.getToken();
                            await ApiService.delete(
                                "/master/super-admins/${sa.id}",
                                token: token);
                            _fetchSuperAdmins();
                            _fetchOverview();
                            _snack('Super Admin removed', kError);
                          } catch (_) {
                            _snack('Failed to delete', kError);
                          }
                        },
                      );
                    }
                  },
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: kSubtle),
                  itemBuilder: (_) => [
                    _menuItem('reset',  'Reset Password', Icons.lock_reset),
                    _menuItem('delete', 'Delete',         Icons.delete_outline,
                        color: kError),
                  ],
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRowWidget(
                          Icons.alternate_email, '@${sa.username}'),
                      const SizedBox(height: 4),
                      _infoRowWidget(Icons.calendar_today_outlined,
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

  // ══════════════════════════════════════════
  //  TAB 2 — ADMINS
  // ══════════════════════════════════════════
  Widget _buildAdmins() {
    return Column(
      children: [
        _listHeader(
          title: '${_admins.length} Admin(s)',              // ← named param
          onRefresh: _fetchAdmins,
          buttonLabel: 'New Admin',
          buttonIcon: Icons.add,
          onButton: _showCreateAdmin,
        ),
        Expanded(                                           // ← comma was missing before here
          child: _loadingAdmins
              ? const Center(
                  child: CircularProgressIndicator(color: kDevAccent))
              : RefreshIndicator(
                  onRefresh: _fetchAdmins,
                  color: kDevAccent,
                  child: _admins.isEmpty
                      ? _emptyState(
                          'No Admins yet',
                          'Tap "New Admin" to create one',
                          Icons.manage_accounts_outlined)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _admins.length,
                          itemBuilder: (_, i) => _adminCard(_admins[i]),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _adminCard(AdminModel admin) {
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
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: admin.isActive
                  ? kPrimary.withOpacity(0.07)
                  : kError.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                _idBadge('AD', admin.id),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(admin.name,
                          style: const TextStyle(
                              color: kDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      Text(admin.district,
                          style: const TextStyle(
                              color: kSubtle, fontSize: 11)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.patch(
                        "/master/admins/${admin.id}/status",
                        {"isActive": !admin.isActive},
                        token: token,
                      );
                      _fetchAdmins();
                    } catch (_) {
                      _snack('Failed to update status', kError);
                    }
                  },
                  child: _statusBadge(admin.isActive),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'reset')
                      _showResetPassword(admin.id, admin.name, 'admin');
                    if (v == 'delete') {
                      _confirmDestructive(
                        'Delete Admin?',
                        'Admin "${admin.name}" will be permanently removed.',
                        () async {
                          try {
                            final token = await AuthService.getToken();
                            await ApiService.delete(
                                "/master/admins/${admin.id}",
                                token: token);
                            _fetchAdmins();
                            _fetchOverview();
                            _snack('Admin deleted', kError);
                          } catch (_) {
                            _snack('Failed to delete', kError);
                          }
                        },
                      );
                    }
                  },
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: kSubtle),
                  itemBuilder: (_) => [
                    _menuItem('reset',  'Reset Password', Icons.lock_reset),
                    _menuItem('delete', 'Delete',         Icons.delete_outline,
                        color: kError),
                  ],
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRowWidget(
                          Icons.alternate_email, '@${admin.username}'),
                      const SizedBox(height: 4),
                      _infoRowWidget(Icons.person_outline,
                          'By: ${admin.createdBy}'),
                      const SizedBox(height: 4),
                      _infoRowWidget(Icons.calendar_today_outlined,
                          'Created ${_fmt(admin.createdAt)}'),
                    ],
                  ),
                ),
                _pill('${admin.superZoneCount} Zones', kAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 3 — LOGS
  // ══════════════════════════════════════════
  Widget _buildLogs() {
    final filtered = _logFilter == 'ALL'
        ? _logs
        : _logs.where((l) => l.level == _logFilter).toList();

    return Column(
      children: [
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
          child: Row(
            children: ['ALL', 'INFO', 'WARN', 'ERROR']
                .map((f) => GestureDetector(
                      onTap: () {
                        setState(() => _logFilter = f);
                        _fetchLogs(level: f);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _logFilter == f
                              ? _logColor(f)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color:
                                  _logColor(f).withOpacity(0.5)),
                        ),
                        child: Text(f,
                            style: TextStyle(
                              color: _logFilter == f
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
                  child: CircularProgressIndicator(color: kDevAccent))
              : RefreshIndicator(
                  onRefresh: () => _fetchLogs(level: _logFilter),
                  color: kDevAccent,
                  child: filtered.isEmpty
                      ? _emptyState('No ${_logFilter == 'ALL' ? '' : _logFilter} logs',
                            'Nothing to show for this filter',
                            Icons.receipt_long_outlined)
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _logTile(filtered[i]),
                        ),
                ),
        ),
      ],
    );
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
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                        style: const TextStyle(
                            color: kSubtle, fontSize: 11)),
                    Text(_fmtTime(log.time),
                        style: const TextStyle(
                            color: kSubtle, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 4 — CONFIG
  // ══════════════════════════════════════════
  Widget _buildConfig() {
    if (_loadingConfig) {
      return const Center(
          child: CircularProgressIndicator(color: kDevAccent));
    }
    return RefreshIndicator(
      onRefresh: _fetchConfig,
      color: kDevAccent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Election Info ─────────────────
            Row(
              children: [
                Expanded(child: _sectionLabel('Election Settings')),
                GestureDetector(
                  onTap: _showEditElectionConfig,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: kDevAccent,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text('Edit',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _configGroup([
              _configInfo('State',
                  _appConfig['state']?.toString()         ?? 'Not set'),
              _configInfo('Election Year',
                  _appConfig['electionYear']?.toString()  ?? 'Not set'),
              _configInfo('Election Date',
                  _appConfig['electionDate']?.toString()  ?? 'Not set'),
              _configInfo('Phase',
                  _appConfig['phase']?.toString()         ?? 'Not set'),
            ]),

            const SizedBox(height: 18),
            _sectionLabel('Application Settings'),
            const SizedBox(height: 10),
            _configGroup([
              _configToggle(
                'Maintenance Mode',
                'Disable app for all users',
                _appConfig['maintenanceMode']?.toString() == 'true',
                (v) => _updateConfig('maintenanceMode', v.toString()),
              ),
              _configToggle(
                'Allow Staff Login',
                'Enable/disable staff access',
                _appConfig['allowStaffLogin']?.toString() != 'false',
                (v) => _updateConfig('allowStaffLogin', v.toString()),
              ),
              _configToggle(
                'Force Password Reset',
                'Prompt all admins to reset on next login',
                _appConfig['forcePasswordReset']?.toString() == 'true',
                (v) => _updateConfig('forcePasswordReset', v.toString()),
              ),
            ]),

            const SizedBox(height: 18),
            _sectionLabel('All Config Keys'),
            const SizedBox(height: 10),
            _configGroup(
              _appConfig.entries
                  .map((e) => _configInfo(e.key, e.value?.toString() ?? ''))
                  .toList(),
            ),

            const SizedBox(height: 18),
            _sectionLabel('Developer Tools'),
            const SizedBox(height: 10),
            _configGroup([
              _devAction(Icons.build_outlined, 'Run DB Migrations',
                  'Apply schema updates to the database', () async {
                try {
                  final token = await AuthService.getToken();
                  await ApiService.post("/master/migrate", {},
                      token: token);
                  _snack('Migrations completed ✓', kSuccess);
                } catch (_) {
                  _snack('Migration failed', kError);
                }
              }),
              _devAction(Icons.lock_reset, 'Change Master Password',
                  'Update master account password', _showChangeMasterPassword),
              _devAction(
                  Icons.info_outline,
                  'System Info',
                  'Flask · MySQL · SHA256+Salt auth',
                  () => _snack('Flask · MySQL 8 · SHA256+Salt', kInfo)),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showChangeMasterPassword() {
    final oldCtrl  = TextEditingController();
    final newCtrl  = TextEditingController();
    final confCtrl = TextEditingController();
    bool  obsOld   = true;
    bool  obsNew   = true;
    bool  obsConf  = true;
    final formKey  = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => _styledDialog(
          title: 'Change Master Password',
          icon: Icons.lock_person_outlined,
          ctx: ctx,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dlgField(oldCtrl, 'Current Password', Icons.lock_outline,
                    obscure: obsOld,
                    suffixIcon: _eyeIcon(
                        obsOld, () => setDlg(() => obsOld = !obsOld)),
                    validator: _notEmpty),
                const SizedBox(height: 12),
                _dlgField(newCtrl, 'New Password', Icons.lock_reset_outlined,
                    obscure: obsNew,
                    suffixIcon: _eyeIcon(
                        obsNew, () => setDlg(() => obsNew = !obsNew)),
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'Min 6 chars' : null),
                const SizedBox(height: 12),
                _dlgField(confCtrl, 'Confirm New Password', Icons.lock_outline,
                    obscure: obsConf,
                    suffixIcon: _eyeIcon(
                        obsConf, () => setDlg(() => obsConf = !obsConf)),
                    validator: (v) =>
                        v != newCtrl.text ? 'Passwords do not match' : null),
                const SizedBox(height: 20),
                _dlgActions(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.patch(
                        "/master/change-password",
                        {
                          "oldPassword": oldCtrl.text,
                          "newPassword": newCtrl.text,
                        },
                        token: token,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('Password changed ✓', kSuccess);
                    } catch (e) {
                      _snack("Error: $e", kError);
                    }
                  },
                  confirmLabel: 'Change',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateConfig(String key, dynamic value) async {
    try {
      final token = await AuthService.getToken();
      await ApiService.post("/master/config", {"key": key, "value": value},
          token: token);
      _fetchConfig();
      _snack('Config updated ✓', kSuccess);
    } catch (_) {
      _snack('Failed to update config', kError);
    }
  }

  // ══════════════════════════════════════════
  //  REUSABLE WIDGETS
  // ══════════════════════════════════════════

  Widget _listHeader({
    required String title,
    required VoidCallback onRefresh,
    required String buttonLabel,
    required IconData buttonIcon,
    required VoidCallback onButton,
  }) {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: kDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: kSubtle, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onButton,
            icon: Icon(buttonIcon, size: 15),
            label: Text(buttonLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDevAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kBorder, size: 48),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  color: kDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: kSubtle, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _infoTable(Map<String, String> data) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.4)),
      ),
      child: Column(
        children: data.entries.toList().asMap().entries.map((e) {
          final isLast = e.key == data.length - 1;
          final kv     = e.value;
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
                Text(kv.key,
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
                  child: Text(kv.value,
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
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.35)),
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
            width: 28, height: 28,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 15, color: color),
          ),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 17, fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(
                  color: kSubtle, fontSize: 10, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
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
                color: kDark,
                fontSize: 14,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _infoRowWidget(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 13, color: kSubtle),
      const SizedBox(width: 6),
      Flexible(
        child: Text(text,
            style: const TextStyle(color: kSubtle, fontSize: 12),
            overflow: TextOverflow.ellipsis),
      ),
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

  Widget _idBadge(String prefix, int id) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: kDark, borderRadius: BorderRadius.circular(6)),
      child: Text(
        '$prefix${id.toString().padLeft(3, '0')}',
        style: const TextStyle(
            color: kBorder,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8),
      ),
    );
  }

  Widget _statusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? kSuccess.withOpacity(0.1)
            : kError.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isActive ? kSuccess : kError, width: 1),
      ),
      child: Text(
        isActive ? 'ACTIVE' : 'INACTIVE',
        style: TextStyle(
            color: isActive ? kSuccess : kError,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8),
      ),
    );
  }

  Color _logColor(String level) {
    switch (level) {
      case 'ERROR': return kError;
      case 'WARN':  return kWarning;
      default:      return kInfo;
    }
  }

  // ── Config helpers ────────────────────────
  Widget _configGroup(List<Widget> children) {
    if (children.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder.withOpacity(0.4)),
        ),
        child: const Text('No config found',
            style: TextStyle(color: kSubtle, fontSize: 12)),
      );
    }
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
                      bottom: BorderSide(
                          color: kBorder.withOpacity(0.25))),
            ),
            child: e.value,
          );
        }).toList(),
      ),
    );
  }

  Widget _configToggle(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
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
          Expanded(
            child: Text(key,
                style: const TextStyle(
                    color: kSubtle,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: kDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
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

  // ── Dialog frame ──────────────────────────
  Widget _styledDialog({
    required String title,
    required IconData icon,
    required BuildContext ctx,
    required Widget child,
  }) {
    return Dialog(
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
                  blurRadius: 28,
                  offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dlgHeader(title, icon, ctx),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          Icon(icon, color: kBorder, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: const Icon(Icons.close,
                color: Colors.white54, size: 20),
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

  PopupMenuItem<String> _menuItem(String value, String label, IconData icon,
      {Color color = kDark}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Utils ─────────────────────────────────
  String? _notEmpty(String? v) =>
      (v == null || v.isEmpty) ? 'Required' : null;

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  String _fmtTime(DateTime dt) =>
      '${_fmt(dt)}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }
}