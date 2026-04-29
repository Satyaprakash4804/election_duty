import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../admin/pages/hierarchy_report_page.dart';
import '../admin/map_view.dart';
import '../admin/pages/goswara_page.dart';

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
const kOrange  = Color(0xFFE65100);
const kPurple  = Color(0xFF6A1B9A);

// ─────────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────────
class AdminUser {
  final int    id;
  final String name;
  final String username;
  final String district;
  final bool   isActive;
  final int    totalBooths;
  final int    assignedStaff;
  final String createdAt;

  AdminUser.fromJson(Map<String, dynamic> j)
      : id           = j['id'],
        name         = j['name']          ?? '',
        username     = j['username']      ?? '',
        district     = j['district']      ?? '',
        isActive     = j['isActive']      ?? true,
        totalBooths  = j['totalBooths']   ?? 0,
        assignedStaff= j['assignedStaff'] ?? 0,
        createdAt    = j['createdAt']     ?? '';
}

class FormDataEntry {
  final int    adminId;
  final String adminName;
  final String district;
  final int    superZones;
  final int    zones;
  final int    sectors;
  final int    gramPanchayats;
  final int    centers;
  final String? lastUpdated;

  FormDataEntry.fromJson(Map<String, dynamic> j)
      : adminId        = j['adminId']        ?? 0,
        adminName      = j['adminName']      ?? '',
        district       = j['district']       ?? '',
        superZones     = j['superZones']     ?? 0,
        zones          = j['zones']          ?? 0,
        sectors        = j['sectors']        ?? 0,
        gramPanchayats = j['gramPanchayats'] ?? 0,
        centers        = j['centers']        ?? 0,
        lastUpdated    = j['lastUpdated'];
}

class UnlockRequest {
  final int    id;
  final int    superZoneId;
  final String superZoneName;
  final String adminName;
  final String reason;
  final String status;
  final String createdAt;

  UnlockRequest.fromJson(Map<String, dynamic> j)
      : id            = j['id']             ?? 0,
        superZoneId   = j['super_zone_id']  ?? 0,
        superZoneName = j['super_zone_name']?? '',
        adminName     = j['admin_name']     ?? '',
        reason        = j['reason']         ?? '',
        status        = j['status']         ?? 'pending',
        createdAt     = j['created_at']     ?? '';
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
  late final Animation<double>   _fadeAnim;

  // ── Data ──────────────────────────────────
  List<AdminUser>      _admins         = [];
  List<FormDataEntry>  _formData       = [];
  List<UnlockRequest>  _unlockRequests = [];
  Map<String, dynamic> _overview       = {};

  bool _loadingAdmins         = true;
  bool _loadingFormData       = true;
  bool _loadingOverview       = true;
  bool _loadingUnlockRequests = true;

  // pending count for badge
  int get _pendingUnlockCount =>
      _unlockRequests.where((r) => r.status == 'pending').length;

  final List<String> _upDistricts = [
    'आगरा','आज़मगढ़','बिजनौर','इटावा','अलीगढ़','बागपत','बदायूं','फर्रुखाबाद',
    'अंबेडकर नगर','बहराइच','बुलंदशहर','फतेहपुर','अमेठी','बलिया','चंदौली','फिरोजाबाद',
    'अमरोहा','बलरामपुर','चित्रकूट','गौतम बुद्ध नगर','औरैया','बांदा','देवरिया','गाज़ियाबाद',
    'अयोध्या','बाराबंकी','एटा','गाज़ीपुर','गोंडा','जालौन','कासगंज','लखनऊ',
    'गोरखपुर','जौनपुर','कौशांबी','महाराजगंज','हमीरपुर','झांसी','कुशीनगर','महोबा',
    'हापुड़','कन्नौज','लखीमपुर खीरी','मैनपुरी','हरदोई','कानपुर देहात','ललितपुर','मथुरा',
    'हाथरस','कानपुर नगर','मऊ','पीलीभीत','संभल','सोनभद्र','मेरठ','प्रतापगढ़',
    'संतकबीर नगर','सुल्तानपुर','मिर्जापुर','प्रयागराज','भदोही (संत रविदास नगर)','उन्नाव',
    'मुरादाबाद','रायबरेली','शाहजहाँपुर','वाराणसी','मुजफ्फरनगर','रामपुर','शामली',
    'सहारनपुर','श्रावस्ती','सिद्धार्थनगर','सीतापुर',
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _fetchAll();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── API CALLS ──────────────────────────────
  Future<void> _fetchAll() async {
    await Future.wait([
      _fetchOverview(),
      _fetchAdmins(),
      _fetchFormData(),
      _fetchUnlockRequests(),
    ]);
  }

  Future<void> _fetchOverview() async {
    setState(() => _loadingOverview = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/super/overview", token: token);
      setState(() => _overview = res['data'] ?? {});
    } catch (_) {
      _snack('Failed to load overview', kError);
    } finally {
      setState(() => _loadingOverview = false);
    }
  }

  Future<void> _fetchAdmins() async {
    setState(() => _loadingAdmins = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/super/admins", token: token);
      setState(() {
        _admins = (res['data'] as List)
            .map((e) => AdminUser.fromJson(e))
            .toList();
      });
    } catch (_) {
      _snack('Failed to load admins', kError);
    } finally {
      setState(() => _loadingAdmins = false);
    }
  }

  Future<void> _fetchFormData() async {
    setState(() => _loadingFormData = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/super/form-data", token: token);
      setState(() {
        _formData = (res['data'] as List)
            .map((e) => FormDataEntry.fromJson(e))
            .toList();
      });
    } catch (_) {
      _snack('Failed to load form data', kError);
    } finally {
      setState(() => _loadingFormData = false);
    }
  }

  Future<void> _fetchUnlockRequests() async {
    setState(() => _loadingUnlockRequests = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/super/unlock-requests", token: token);
      setState(() {
        _unlockRequests = (res['data'] as List)
            .map((e) => UnlockRequest.fromJson(e))
            .toList();
      });
    } catch (_) {
      _snack('Failed to load unlock requests', kError);
    } finally {
      setState(() => _loadingUnlockRequests = false);
    }
  }

  Future<void> _handleUnlockAction(UnlockRequest req, String action) async {
    try {
      final token = await AuthService.getToken();
      await ApiService.post(
        "/super/unlock-requests/${req.id}/action",
        {"action": action},
        token: token,
      );
      _snack(
        action == 'approve' ? '✅ Unlock Approved!' : '❌ Request Rejected',
        action == 'approve' ? kSuccess : kError,
      );
      await _fetchUnlockRequests();
    } catch (e) {
      _snack('Error: ${_errMsg(e)}', kError);
    }
  }

  void _switchTab(int i) {
    setState(() => _selectedTab = i);
    _fadeCtrl.forward(from: 0);
  }

  // ─────────────────────────────────────────────
  //  CREATE ADMIN DIALOG
  // ─────────────────────────────────────────────
  void _showCreateAdminDialog() {
    final nameCtrl    = TextEditingController();
    final userCtrl    = TextEditingController();
    final passCtrl    = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? selectedDistrict;
    bool obscureP = true;
    bool obscureC = true;
    final formKey = GlobalKey<FormState>();

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
                boxShadow: [BoxShadow(
                    color: kPrimary.withOpacity(0.2),
                    blurRadius: 28, offset: const Offset(0, 10))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dlgHeader('Create New Admin', Icons.admin_panel_settings, ctx),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _dlgField(nameCtrl, 'Full Name', Icons.person_outline, validator: _notEmpty),
                            const SizedBox(height: 12),
                            _dlgField(userCtrl, 'Admin User ID', Icons.badge_outlined, validator: _notEmpty),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: selectedDistrict,
                              dropdownColor: kBg,
                              decoration: _dlgDecoration('District', Icons.location_city_outlined),
                              items: _upDistricts
                                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                                  .toList(),
                              onChanged: (v) => setDlg(() => selectedDistrict = v),
                              validator: (v) => v == null ? 'Select a district' : null,
                            ),
                            const SizedBox(height: 12),
                            _dlgField(passCtrl, 'Password', Icons.lock_outline,
                                obscure: obscureP,
                                suffixIcon: _eyeBtn(obscureP, () => setDlg(() => obscureP = !obscureP)),
                                validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null),
                            const SizedBox(height: 12),
                            _dlgField(confirmCtrl, 'Confirm Password', Icons.lock_outline,
                                obscure: obscureC,
                                suffixIcon: _eyeBtn(obscureC, () => setDlg(() => obscureC = !obscureC)),
                                validator: (v) => v != passCtrl.text ? 'Passwords do not match' : null),
                            const SizedBox(height: 20),
                            Row(children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kSubtle,
                                    side: const BorderSide(color: kBorder),
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    if (!formKey.currentState!.validate()) return;
                                    try {
                                      final token = await AuthService.getToken();
                                      await ApiService.post(
                                        "/super/admins",
                                        {
                                          "name":     nameCtrl.text.trim(),
                                          "username": userCtrl.text.trim(),
                                          "district": selectedDistrict,
                                          "password": passCtrl.text,
                                        },
                                        token: token,
                                      );
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _snack('Admin created successfully', kSuccess);
                                      _fetchAdmins();
                                      _fetchOverview();
                                    } catch (e) {
                                      _snack('Error: ${_errMsg(e)}', kError);
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: const Text('Create Admin'),
                                ),
                              ),
                            ]),
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

  // ─────────────────────────────────────────────
  //  FORM DATA DETAIL DIALOG
  // ─────────────────────────────────────────────
  void _showFormDetail(FormDataEntry e) {
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
                _dlgHeader('${e.district} — Form Data', Icons.article_outlined, ctx),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _detailRow('Admin', e.adminName, Icons.manage_accounts_outlined),
                      if (e.lastUpdated != null)
                        _detailRow('Last Updated', _fmtIso(e.lastUpdated!), Icons.calendar_today_outlined),
                      const Divider(color: kBorder, height: 24),
                      GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 3,
                        childAspectRatio: 1.4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _miniStat('Super Zones',    '${e.superZones}',     Icons.layers_outlined),
                          _miniStat('Zones',           '${e.zones}',          Icons.grid_view_outlined),
                          _miniStat('Sectors',         '${e.sectors}',        Icons.view_module_outlined),
                          _miniStat('Gram Panchayats', '${e.gramPanchayats}', Icons.account_balance_outlined),
                          _miniStat('Centers',         '${e.centers}',        Icons.location_on_outlined),
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  // ─────────────────────────────────────────────
  //  UNLOCK REQUEST DETAIL DIALOG
  // ─────────────────────────────────────────────
  void _showUnlockDetail(UnlockRequest req) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: req.status == 'pending' ? kOrange : kBorder,
                  width: 1.5),
              boxShadow: [BoxShadow(
                  color: kOrange.withOpacity(0.15),
                  blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
                  decoration: BoxDecoration(
                    color: req.status == 'pending' ? kOrange : kDark,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(15),
                        topRight: Radius.circular(15)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(7)),
                      child: const Icon(Icons.lock_open_rounded,
                          color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Unlock Request Detail',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close,
                          color: Colors.white70, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Super Zone info
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kPurple.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: kPurple.withOpacity(0.25)),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: kPurple.withOpacity(0.12),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.layers_outlined,
                                color: kPurple, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(req.superZoneName,
                                  style: const TextStyle(color: kDark,
                                      fontWeight: FontWeight.w800, fontSize: 15)),
                              Text('Super Zone ID: ${req.superZoneId}',
                                  style: const TextStyle(
                                      color: kSubtle, fontSize: 11)),
                            ],
                          )),
                        ]),
                      ),
                      const SizedBox(height: 12),

                      // Admin who requested
                      _detailRow('Requested By', req.adminName,
                          Icons.manage_accounts_outlined),
                      _detailRow('Requested At', _fmtIso(req.createdAt),
                          Icons.access_time_outlined),
                      const SizedBox(height: 8),

                      // Reason
                      const Text('कारण (Reason)',
                          style: TextStyle(color: kSubtle, fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: kBorder.withOpacity(0.5)),
                        ),
                        child: Text(
                          req.reason.isNotEmpty ? req.reason : '(कोई कारण नहीं दिया)',
                          style: TextStyle(
                              color: req.reason.isNotEmpty ? kDark : kSubtle,
                              fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (req.status == 'pending') ...[
                        Row(children: [
                          Expanded(child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _handleUnlockAction(req, 'reject');
                            },
                            icon: const Icon(Icons.cancel_outlined, size: 16),
                            label: const Text('Reject'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kError,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _handleUnlockAction(req, 'approve');
                            },
                            icon: const Icon(Icons.lock_open_rounded, size: 16),
                            label: const Text('Approve Unlock'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kSuccess,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          )),
                        ]),
                      ] else
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kSubtle,
                              side: const BorderSide(color: kBorder),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('बंद करें'),
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

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
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

  Widget _buildTopBar() {
    return Container(
      color: kDark,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 12, left: 16, right: 16,
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: kPrimary,
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
                Text('SUPER ADMIN PANEL',
                    style: TextStyle(
                        color: kBorder, fontSize: 11,
                        fontWeight: FontWeight.w800, letterSpacing: 1.8)),
                Text('UP Election Cell — District Monitoring',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          // Unlock requests indicator in top bar
          if (_pendingUnlockCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kOrange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_open, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Text('$_pendingUnlockCount',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ]),
            ),
          IconButton(
            onPressed: () async {
              await AuthService.logout();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
            icon: const Icon(Icons.logout_rounded,
                color: Colors.white70, size: 20),
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    // tabs: Overview, Admins, Unlock Requests, Form Data
    final tabs = [
      (Icons.dashboard_outlined,        'Overview',   null),
      (Icons.admin_panel_settings,       'Admins',     null),
      (Icons.lock_open_rounded,          'Unlocks',    _pendingUnlockCount),
      (Icons.article_outlined,           'Form Data',  null),
    ];
    return Container(
      color: kSurface,
      child: Row(
        children: List.generate(tabs.length, (i) {
          final sel   = _selectedTab == i;
          final badge = tabs[i].$3;
          return Expanded(
            child: GestureDetector(
              onTap: () => _switchTab(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: sel ? kBg : Colors.transparent,
                  border: Border(
                      bottom: BorderSide(
                          color: sel
                              ? (i == 2 ? kOrange : kPrimary)
                              : Colors.transparent,
                          width: 3)),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(tabs[i].$1, size: 16,
                            color: sel
                                ? (i == 2 ? kOrange : kPrimary)
                                : kSubtle),
                        const SizedBox(height: 3),
                        Text(tabs[i].$2,
                            style: TextStyle(
                                color: sel
                                    ? (i == 2 ? kOrange : kPrimary)
                                    : kSubtle,
                                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                fontSize: 11)),
                      ],
                    ),
                    if (badge != null && badge > 0)
                      Positioned(
                        top: -4, right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: kOrange,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: kBg, width: 1.5),
                          ),
                          child: Text('$badge',
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 9, fontWeight: FontWeight.w900)),
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

  Widget _buildBody() {
    switch (_selectedTab) {
      case 0:  return _buildOverview();
      case 1:  return _buildAdminList();
      case 2:  return _buildUnlockRequests();
      case 3:  return _buildFormData();
      default: return _buildOverview();
    }
  }

  // ── TAB 0: OVERVIEW ──────────────────────────
  Widget _buildOverview() {
    if (_loadingOverview || _loadingAdmins) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    final totalBooths = _overview['totalBooths']    ?? 0;
    final totalStaff  = _overview['totalStaff']     ?? 0;
    final assigned    = _overview['assignedDuties'] ?? 0;

    return RefreshIndicator(
      onRefresh: _fetchAll,
      color: kPrimary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Pending unlock banner
            if (_pendingUnlockCount > 0)
              GestureDetector(
                onTap: () => _switchTab(2),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: kOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kOrange.withOpacity(0.5)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                          color: kOrange, shape: BoxShape.circle),
                      child: const Icon(Icons.lock_open_rounded,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_pendingUnlockCount Pending Unlock Request${_pendingUnlockCount > 1 ? 's' : ''}',
                          style: const TextStyle(color: kOrange,
                              fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                        const Text('Tap to review and approve/reject',
                            style: TextStyle(color: kOrange, fontSize: 11)),
                      ],
                    )),
                    const Icon(Icons.chevron_right, color: kOrange, size: 20),
                  ]),
                ),
              ),

            // Stats grid
            LayoutBuilder(builder: (_, c) {
              final cols = c.maxWidth > 500 ? 4 : 2;
              return GridView.count(
                shrinkWrap: true,
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _statCard('Total Admins', '${_admins.length}',
                      Icons.manage_accounts, kPrimary),
                  _statCard('Total Booths', '$totalBooths',
                      Icons.location_on_outlined, kInfo),
                  _statCard('Total Staff', '$totalStaff',
                      Icons.badge_outlined, kAccent),
                  _statCard('Assigned', '$assigned',
                      Icons.how_to_vote, kSuccess),
                ],
              );
            }),

            const SizedBox(height: 14),

            // Goswara Report
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const GoswaraPage())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B6914), Color(0xFFB8860B)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                        color: const Color(0xFF8B6914).withOpacity(0.3),
                        blurRadius: 14, offset: const Offset(0, 5))],
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(9)),
                      child: const Icon(Icons.description_outlined,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Goswara Report',
                            style: TextStyle(color: Colors.white,
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        SizedBox(height: 2),
                        Text('Summary Report of Booth Staff',
                            style: TextStyle(color: Colors.white60, fontSize: 11)),
                      ],
                    )),
                    const Icon(Icons.chevron_right,
                        color: Colors.white54, size: 22),
                  ]),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Hierarchy Report
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) =>
                      const HierarchyReportPage(role: "master"))),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF0F2B5B), Color(0xFF1A3D7C)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(children: [
                  Icon(Icons.table_chart_outlined, color: Colors.white, size: 22),
                  SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hierarchy Report',
                          style: TextStyle(color: Colors.white,
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      Text('Super Zone · Sector · Panchayat',
                          style: TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  )),
                  Icon(Icons.chevron_right, color: Colors.white54),
                ]),
              ),
            ),

            const SizedBox(height: 12),

            // Map View
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MapViewPage())),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF00695C), Color(0xFF00897B)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(children: [
                  Icon(Icons.map, color: Colors.white, size: 22),
                  SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Map View',
                          style: TextStyle(color: Colors.white,
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      Text('View all centers on map',
                          style: TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  )),
                  Icon(Icons.chevron_right, color: Colors.white54),
                ]),
              ),
            ),

            const SizedBox(height: 20),

            _sectionHeader('District Summary'),
            const SizedBox(height: 10),

            if (_admins.isEmpty)
              const Center(child: Text('No admins found',
                  style: TextStyle(color: kSubtle)))
            else
              ..._admins.map((a) => _districtCard(a)),
          ],
        ),
      ),
    );
  }

  // ── TAB 1: ADMIN LIST ─────────────────────────
  Widget _buildAdminList() {
    if (_loadingAdmins) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    return Column(
      children: [
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text('${_admins.length} Admin(s) Registered',
                    style: const TextStyle(color: kDark,
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateAdminDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Admin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),

        // Pending unlock requests summary strip
        if (_pendingUnlockCount > 0)
          GestureDetector(
            onTap: () => _switchTab(2),
            child: Container(
              color: kOrange.withOpacity(0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                const Icon(Icons.lock_open_rounded, color: kOrange, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '$_pendingUnlockCount unlock request${_pendingUnlockCount > 1 ? 's' : ''} pending approval',
                  style: const TextStyle(color: kOrange,
                      fontWeight: FontWeight.w700, fontSize: 13),
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: kOrange,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('Review →',
                      style: TextStyle(color: Colors.white,
                          fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchAdmins,
            color: kPrimary,
            child: _admins.isEmpty
                ? const Center(child: Text('No admins yet',
                    style: TextStyle(color: kSubtle)))
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

  // ── TAB 2: UNLOCK REQUESTS ────────────────────
  Widget _buildUnlockRequests() {
    if (_loadingUnlockRequests) {
      return const Center(child: CircularProgressIndicator(color: kOrange));
    }

    final pending  = _unlockRequests.where((r) => r.status == 'pending').toList();
    final resolved = _unlockRequests.where((r) => r.status != 'pending').toList();

    return RefreshIndicator(
      onRefresh: _fetchUnlockRequests,
      color: kOrange,
      child: CustomScrollView(
        slivers: [
          // Header summary bar
          SliverToBoxAdapter(
            child: Container(
              color: kSurface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                _summaryPill('${pending.length}', 'Pending',  kOrange),
                const SizedBox(width: 10),
                _summaryPill('${resolved.where((r) => r.status == 'approved').length}',
                    'Approved', kSuccess),
                const SizedBox(width: 10),
                _summaryPill('${resolved.where((r) => r.status == 'rejected').length}',
                    'Rejected', kError),
              ]),
            ),
          ),

          if (_unlockRequests.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_open_rounded, size: 56,
                      color: Color(0x44E65100)),
                  SizedBox(height: 14),
                  Text('कोई Unlock Request नहीं',
                      style: TextStyle(color: kSubtle,
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text('All zones are currently locked or unlocked normally.',
                      style: TextStyle(color: kSubtle, fontSize: 12)),
                ],
              )),
            ),

          // Pending section
          if (pending.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  Container(width: 4, height: 16,
                      decoration: BoxDecoration(color: kOrange,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Text('Pending Approval (${pending.length})',
                      style: const TextStyle(color: kOrange,
                          fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _unlockRequestCard(pending[i]),
                  childCount: pending.length,
                ),
              ),
            ),
          ],

          // Resolved section
          if (resolved.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  Container(width: 4, height: 16,
                      decoration: BoxDecoration(color: kSubtle,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Text('Resolved (${resolved.length})',
                      style: const TextStyle(color: kSubtle,
                          fontWeight: FontWeight.w800, fontSize: 14)),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _unlockRequestCard(resolved[i]),
                  childCount: resolved.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── TAB 3: FORM DATA ──────────────────────────
  Widget _buildFormData() {
    if (_loadingFormData) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    return RefreshIndicator(
      onRefresh: _fetchFormData,
      color: kPrimary,
      child: _formData.isEmpty
          ? const Center(child: Text('No form data submitted yet',
              style: TextStyle(color: kSubtle)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _formData.length,
              itemBuilder: (_, i) => _formDataCard(_formData[i]),
            ),
    );
  }

  // ─────────────────────────────────────────────
  //  CARD WIDGETS
  // ─────────────────────────────────────────────

  Widget _districtCard(AdminUser a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.4)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
              color: kSurface, shape: BoxShape.circle,
              border: Border.all(color: kBorder)),
          child: const Icon(Icons.location_city, color: kPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.district,
                style: const TextStyle(color: kDark, fontSize: 14,
                    fontWeight: FontWeight.w700)),
            Text(a.name,
                style: const TextStyle(color: kSubtle, fontSize: 12)),
          ],
        )),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _pill('${a.totalBooths} Booths', kPrimary),
            const SizedBox(height: 4),
            _pill('${a.assignedStaff} Staff', kAccent),
          ],
        ),
      ]),
    );
  }

  Widget _adminCard(AdminUser a) {
    // Count pending unlock requests for THIS admin's zones
    final adminPendingCount = _unlockRequests
        .where((r) => r.status == 'pending' && r.adminName == a.name)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: adminPendingCount > 0
                ? kOrange.withOpacity(0.5)
                : kBorder.withOpacity(0.5)),
        boxShadow: [BoxShadow(
            color: adminPendingCount > 0
                ? kOrange.withOpacity(0.08)
                : kPrimary.withOpacity(0.06),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: adminPendingCount > 0 ? kOrange.withOpacity(0.06) : kSurface,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('ADM${a.id.toString().padLeft(3, '0')}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(a.name,
                  style: const TextStyle(color: kDark,
                      fontWeight: FontWeight.w700, fontSize: 14))),

              // Pending unlock badge
              if (adminPendingCount > 0) ...[
                GestureDetector(
                  onTap: () => _switchTab(2),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: kOrange,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock_open, size: 11,
                          color: Colors.white),
                      const SizedBox(width: 4),
                      Text('$adminPendingCount Unlock',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 10, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              ],

              IconButton(
                onPressed: () => _confirmDelete(
                  'Remove Admin?',
                  'This will remove all data under ${a.name}.',
                  () async {
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.delete("/super/admins/${a.id}", token: token);
                      _fetchAdmins();
                      _fetchOverview();
                      _snack('Admin removed', kError);
                    } catch (e) {
                      _snack('Error: ${_errMsg(e)}', kError);
                    }
                  },
                ),
                icon: const Icon(Icons.delete_outline, color: kError, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(Icons.location_city_outlined, a.district),
                  const SizedBox(height: 4),
                  _infoRow(Icons.calendar_today_outlined,
                      'Created ${_fmtIso(a.createdAt)}'),
                ],
              )),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _pill('${a.totalBooths} Booths', kPrimary),
                  const SizedBox(height: 4),
                  _pill('${a.assignedStaff} Staff', kAccent),
                ],
              ),
            ]),
          ),

          // Show this admin's pending unlock requests inline
          if (adminPendingCount > 0) ...[
            const Divider(height: 1, color: Color(0x22E65100)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.lock_open_rounded, size: 13, color: kOrange),
                    SizedBox(width: 6),
                    Text('Pending Unlock Requests',
                        style: TextStyle(color: kOrange,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  ..._unlockRequests
                      .where((r) =>
                          r.status == 'pending' && r.adminName == a.name)
                      .map((req) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: kOrange.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: kOrange.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.layers_outlined,
                                      size: 13, color: kPurple),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(req.superZoneName,
                                        style: const TextStyle(
                                            color: kDark,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)),
                                  ),
                                  Text(_fmtIso(req.createdAt),
                                      style: const TextStyle(
                                          color: kSubtle, fontSize: 10)),
                                ]),
                                if (req.reason.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(req.reason,
                                      style: const TextStyle(
                                          color: kSubtle, fontSize: 11),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ],
                                const SizedBox(height: 8),
                                Row(children: [
                                  Expanded(child: GestureDetector(
                                    onTap: () =>
                                        _handleUnlockAction(req, 'reject'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 7),
                                      decoration: BoxDecoration(
                                        color: kError.withOpacity(0.08),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: kError.withOpacity(0.3)),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.cancel_outlined,
                                              size: 13, color: kError),
                                          SizedBox(width: 5),
                                          Text('Reject',
                                              style: TextStyle(
                                                  color: kError,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                  )),
                                  const SizedBox(width: 8),
                                  Expanded(child: GestureDetector(
                                    onTap: () =>
                                        _handleUnlockAction(req, 'approve'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 7),
                                      decoration: BoxDecoration(
                                        color: kSuccess.withOpacity(0.08),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color:
                                                kSuccess.withOpacity(0.35)),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.lock_open_rounded,
                                              size: 13, color: kSuccess),
                                          SizedBox(width: 5),
                                          Text('Approve',
                                              style: TextStyle(
                                                  color: kSuccess,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                  )),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _showUnlockDetail(req),
                                    child: Container(
                                      width: 34, height: 34,
                                      decoration: BoxDecoration(
                                        color: kInfo.withOpacity(0.08),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: kInfo.withOpacity(0.3)),
                                      ),
                                      child: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 14,
                                          color: kInfo),
                                    ),
                                  ),
                                ]),
                              ],
                            ),
                          )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _unlockRequestCard(UnlockRequest req) {
    final isPending  = req.status == 'pending';
    final isApproved = req.status == 'approved';
    final statusColor = isPending
        ? kOrange
        : isApproved
            ? kSuccess
            : kError;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.2),
        boxShadow: [BoxShadow(
            color: statusColor.withOpacity(0.06),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          // Header strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.07),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(13),
                  topRight: Radius.circular(13)),
            ),
            child: Row(children: [
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    isPending
                        ? Icons.hourglass_top_rounded
                        : isApproved
                            ? Icons.check_circle
                            : Icons.cancel,
                    size: 11, color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(req.status.toUpperCase(),
                      style: const TextStyle(color: Colors.white,
                          fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Request #${req.id}',
                    style: TextStyle(color: statusColor,
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              Text(_fmtIso(req.createdAt),
                  style: const TextStyle(color: kSubtle, fontSize: 11)),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Super Zone info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kPurple.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kPurple.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                          color: kPurple.withOpacity(0.12),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.layers_outlined,
                          color: kPurple, size: 17),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(req.superZoneName,
                            style: const TextStyle(color: kDark,
                                fontWeight: FontWeight.w800, fontSize: 14)),
                        Text('Super Zone ID: ${req.superZoneId}',
                            style: const TextStyle(
                                color: kSubtle, fontSize: 11)),
                      ],
                    )),
                  ]),
                ),
                const SizedBox(height: 10),

                // Admin info
                Row(children: [
                  const Icon(Icons.manage_accounts_outlined,
                      size: 14, color: kSubtle),
                  const SizedBox(width: 6),
                  Text('Admin: ',
                      style: const TextStyle(
                          color: kSubtle, fontSize: 12)),
                  Text(req.adminName,
                      style: const TextStyle(color: kDark,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),

                // Reason
                if (req.reason.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kBorder.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Reason',
                            style: TextStyle(color: kSubtle,
                                fontSize: 10, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(req.reason,
                            style: const TextStyle(
                                color: kDark, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Action buttons (only for pending)
                if (isPending)
                  Row(children: [
                    Expanded(child: ElevatedButton.icon(
                      onPressed: () => _handleUnlockAction(req, 'reject'),
                      icon: const Icon(Icons.cancel_outlined, size: 14),
                      label: const Text('Reject'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kError,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(
                      onPressed: () => _handleUnlockAction(req, 'approve'),
                      icon: const Icon(Icons.lock_open_rounded, size: 14),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSuccess,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    )),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showUnlockDetail(req),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: kInfo.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: kInfo.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.open_in_new_rounded,
                            size: 16, color: kInfo),
                      ),
                    ),
                  ])
                else
                  // Resolved status row
                  Row(children: [
                    Icon(
                      isApproved ? Icons.lock_open : Icons.lock_outline,
                      size: 14, color: statusColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isApproved
                          ? 'Zone was successfully unlocked'
                          : 'Request was rejected',
                      style: TextStyle(color: statusColor,
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _showUnlockDetail(req),
                      child: const Text('Details →',
                          style: TextStyle(color: kInfo,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formDataCard(FormDataEntry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.06),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: kDark,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            ),
            child: Row(children: [
              const Icon(Icons.map_outlined, color: kBorder, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('District: ${e.district}',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 14))),
              if (e.lastUpdated != null)
                Text('Updated: ${_fmtIso(e.lastUpdated!)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              _infoRow(Icons.manage_accounts_outlined, 'Admin: ${e.adminName}'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  _statChip('${e.superZones}',    'Super Zones'),
                  _statChip('${e.zones}',          'Zones'),
                  _statChip('${e.sectors}',        'Sectors'),
                  _statChip('${e.gramPanchayats}', 'Gram Panchayats'),
                  _statChip('${e.centers}',        'Centers'),
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
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  CONFIRM DELETE DIALOG
  // ─────────────────────────────────────────────
  void _confirmDelete(String title, String body, VoidCallback onConfirm) {
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
              style: const TextStyle(color: kError,
                  fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: Text(body,
            style: const TextStyle(color: kDark, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: kSubtle))),
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

  // ─────────────────────────────────────────────
  //  SMALL WIDGETS
  // ─────────────────────────────────────────────

  Widget _summaryPill(String count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(count,
            style: TextStyle(color: color,
                fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(color: color,
                fontWeight: FontWeight.w600, fontSize: 11)),
      ]),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(children: [
      Container(width: 4, height: 18,
          decoration: BoxDecoration(color: kPrimary,
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(color: kDark,
              fontSize: 15, fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: color),
          ),
          const Spacer(),
          Text(value,
              style: TextStyle(color: color,
                  fontSize: 22, fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(color: kSubtle,
                  fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 14, color: kSubtle),
      const SizedBox(width: 6),
      Expanded(child: Text(text,
          style: const TextStyle(color: kSubtle, fontSize: 12,
              fontWeight: FontWeight.w500))),
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
          style: TextStyle(color: color,
              fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _statChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kSurface, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder.withOpacity(0.5)),
      ),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(text: '$value ',
              style: const TextStyle(color: kPrimary,
                  fontWeight: FontWeight.w900, fontSize: 14)),
          TextSpan(text: label,
              style: const TextStyle(color: kSubtle,
                  fontWeight: FontWeight.w500, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: kPrimary),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(color: kDark,
                  fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: kSubtle, fontSize: 9,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: kSubtle),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(color: kSubtle,
                fontSize: 13, fontWeight: FontWeight.w600)),
        Expanded(child: Text(value,
            style: const TextStyle(color: kDark,
                fontSize: 13, fontWeight: FontWeight.w700))),
      ]),
    );
  }

  // ── Dialog helpers ────────────────────────────
  Widget _dlgHeader(String title, IconData icon, BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: kDark,
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(15), topRight: Radius.circular(15)),
      ),
      child: Row(children: [
        Icon(icon, color: kBorder, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(title,
            style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 15))),
        IconButton(
          onPressed: () => Navigator.pop(ctx),
          icon: const Icon(Icons.close, color: Colors.white70, size: 20),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
        ),
      ]),
    );
  }

  InputDecoration _dlgDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18, color: kPrimary),
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 2)),
      labelStyle: const TextStyle(color: kSubtle),
    );
  }

  Widget _dlgField(TextEditingController ctrl, String label, IconData icon,
      {bool obscure = false, Widget? suffixIcon,
        String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      validator: validator,
      style: const TextStyle(color: kDark, fontSize: 14),
      decoration: _dlgDecoration(label, icon).copyWith(suffixIcon: suffixIcon),
    );
  }

  Widget _eyeBtn(bool obscure, VoidCallback onTap) {
    return IconButton(
      icon: Icon(obscure
          ? Icons.visibility_off_outlined
          : Icons.visibility_outlined,
          size: 18, color: kSubtle),
      onPressed: onTap,
    );
  }

  // ── Utilities ─────────────────────────────────
  String? _notEmpty(String? v) =>
      (v == null || v.isEmpty) ? 'Required' : null;

  String _fmtIso(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _errMsg(Object e) {
    final s = e.toString();
    if (s.contains('Exception:')) return s.split('Exception:').last.trim();
    return s;
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }
}