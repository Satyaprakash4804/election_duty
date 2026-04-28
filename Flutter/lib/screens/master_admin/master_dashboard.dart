import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
//  HINDI MASTER DATA
// ─────────────────────────────────────────────
const List<String> kUpDistricts = [
  'आगरा','आज़मगढ़','बिजनौर','इटावा','अलीगढ़','बागपत','बदायूं','फर्रुखाबाद',
  'अंबेडकर नगर','बहराइच','बुलंदशहर','फतेहपुर','अमेठी','बलिया','चंदौली','फिरोजाबाद',
  'अमरोहा','बलरामपुर','चित्रकूट','गौतम बुद्ध नगर','औरैया','बांदा','देवरिया','गाज़ियाबाद',
  'अयोध्या','बाराबंकी','एटा','गाज़ीपुर','गोंडा','जालौन','कासगंज','लखनऊ',
  'गोरखपुर','जौनपुर','कौशांबी','महाराजगंज','हमीरपुर','झांसी','कुशीनगर','महोबा',
  'हापुड़','कन्नौज','लखीमपुर खीरी','मैनपुरी','हरदोई','कानपुर देहात','ललितपुर','मथुरा',
  'हाथरस','कानपुर नगर','मऊ','पीलीभीत','संभल','सोनभद्र','मेरठ','प्रतापगढ़',
  'संतकबीर नगर','सुल्तानपुर','मिर्जापुर','प्रयागराज','भदोही (संत रविदास नगर)','उन्नाव',
  'मुरादाबाद','रायबरेली','शाहजहाँपुर','वाराणसी','मुजफ्फरनगर','रामपुर','शामली','सहारनपुर',
  'श्रावस्ती','सिद्धार्थनगर','सीतापुर',
];

const List<String> kStates = [
  'उत्तर प्रदेश',
];

const List<String> kElectionTypes = [
  'लोक सभा निर्वाचन',
  'विधान सभा निर्वाचन',
  'पंचायत निर्वाचन',
  'नगर निकाय निर्वाचन',
  'विधान परिषद निर्वाचन',
  'उप-निर्वाचन',
];

const List<String> kElectionPhases = [
  'प्रथम चरण',
  'द्वितीय चरण',
  'तृतीय चरण',
  'चतुर्थ चरण',
  'पंचम चरण',
  'षष्ठम चरण',
  'सप्तम चरण',
];

// ─────────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────────
class SuperAdminModel {
  final int    id;
  final String name;
  final String username;
  final String district;
  final DateTime createdAt;
  final int    adminsUnder;
  final bool   isActive;

  SuperAdminModel({
    required this.id,
    required this.name,
    required this.username,
    required this.district,
    required this.createdAt,
    required this.adminsUnder,
    required this.isActive,
  });

  factory SuperAdminModel.fromJson(Map<String, dynamic> j) => SuperAdminModel(
        id:           j['id'],
        name:         j['name'] ?? '',
        username:     j['username'] ?? '',
        district:     j['district'] ?? '',
        createdAt:    DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        adminsUnder:  j['adminsUnder'] ?? 0,
        isActive:     j['isActive'] ?? true,
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

class ElectionConfigModel {
  final int    id;
  final String district;
  final String state;
  final String electionType;
  final String electionName;
  final String phase;
  final String electionYear;
  final String electionDate;
  final String pratahSamay;
  final String sayaSamay;
  final String instructions;
  final bool   isActive;
  final bool   isArchived;
  final String? archivedAt;
  final String? createdAt;

  ElectionConfigModel({
    required this.id,
    required this.district,
    required this.state,
    required this.electionType,
    required this.electionName,
    required this.phase,
    required this.electionYear,
    required this.electionDate,
    required this.pratahSamay,
    required this.sayaSamay,
    required this.instructions,
    required this.isActive,
    required this.isArchived,
    this.archivedAt,
    this.createdAt,
  });

  factory ElectionConfigModel.fromJson(Map<String, dynamic> j) =>
      ElectionConfigModel(
        id:           j['id'] ?? 0,
        district:     j['district']     ?? '',
        state:        j['state']        ?? '',
        electionType: j['electionType'] ?? '',
        electionName: j['electionName'] ?? '',
        phase:        j['phase']        ?? '',
        electionYear: j['electionYear'] ?? '',
        electionDate: j['electionDate'] ?? '',
        pratahSamay:  j['pratahSamay']  ?? '',
        sayaSamay:    j['sayaSamay']    ?? '',
        instructions: j['instructions'] ?? '',
        isActive:     j['isActive']     ?? false,
        isArchived:   j['isArchived']   ?? false,
        archivedAt:   j['archivedAt'],
        createdAt:    j['createdAt'],
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

class ApiLogEntry {
  final int    id;
  final String method;
  final String path;
  final int    statusCode;
  final int    durationMs;
  final String username;
  final String role;
  final String ipAddress;
  final String requestBody;
  final String errorMessage;
  final String level;
  final DateTime createdAt;

  ApiLogEntry({
    required this.id,
    required this.method,
    required this.path,
    required this.statusCode,
    required this.durationMs,
    required this.username,
    required this.role,
    required this.ipAddress,
    required this.requestBody,
    required this.errorMessage,
    required this.level,
    required this.createdAt,
  });

  factory ApiLogEntry.fromJson(Map<String, dynamic> j) => ApiLogEntry(
        id:           j['id'] ?? 0,
        method:       j['method']       ?? '',
        path:         j['path']         ?? '',
        statusCode:   j['statusCode']   ?? 0,
        durationMs:   j['durationMs']   ?? 0,
        username:     j['username']     ?? '',
        role:         j['role']         ?? '',
        ipAddress:    j['ipAddress']    ?? '',
        requestBody:  j['requestBody']  ?? '',
        errorMessage: j['errorMessage'] ?? '',
        level:        j['level']        ?? 'INFO',
        createdAt:    DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class OverviewStats {
  final int totalSuperAdmins;
  final int totalAdmins;
  final int totalStaff;
  final int totalBooths;
  final int assignedDuties;
  final int activeElectionConfigs;
  final int archivedElectionConfigs;

  OverviewStats({
    this.totalSuperAdmins = 0,
    this.totalAdmins      = 0,
    this.totalStaff       = 0,
    this.totalBooths      = 0,
    this.assignedDuties   = 0,
    this.activeElectionConfigs   = 0,
    this.archivedElectionConfigs = 0,
  });

  factory OverviewStats.fromJson(Map<String, dynamic> j) => OverviewStats(
        totalSuperAdmins:        j['totalSuperAdmins']        ?? 0,
        totalAdmins:             j['totalAdmins']             ?? 0,
        totalStaff:              j['totalStaff']              ?? 0,
        totalBooths:             j['totalBooths']             ?? 0,
        assignedDuties:          j['assignedDuties']          ?? 0,
        activeElectionConfigs:   j['activeElectionConfigs']   ?? 0,
        archivedElectionConfigs: j['archivedElectionConfigs'] ?? 0,
      );
}

// ═══════════════════════════════════════════════════════════════════════
//  MASTER DASHBOARD
// ═══════════════════════════════════════════════════════════════════════
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
  List<SuperAdminModel>      _superAdmins      = [];
  List<AdminModel>           _admins           = [];
  List<SystemLogEntry>       _logs             = [];
  List<ApiLogEntry>          _apiLogs          = [];
  List<ElectionConfigModel>  _electionConfigs  = [];
  Map<String, String>        _sysStats         = {};
  Map<String, dynamic>       _appConfig        = {};
  OverviewStats              _overview         = OverviewStats();

  // ── Loading flags ──────────────────────────
  bool _loadingOverview    = true;
  bool _loadingSuperAdmins = true;
  bool _loadingAdmins      = true;
  bool _loadingLogs        = true;
  bool _loadingApiLogs     = false;
  bool _loadingStats       = true;
  bool _loadingConfig      = true;
  bool _loadingElectionCfg = true;

  // ── Filters ────────────────────────────────
  String _logFilter = 'ALL';
  bool   _showArchivedConfigs = false;

  // ── API Logs pagination/filter ─────────────
  int    _apiLogsPage    = 0;
  int    _apiLogsTotal   = 0;
  static const int _apiLogsLimit = 50;
  String _apiLogLevel    = 'ALL';
  String _apiLogMethod   = 'ALL';
  String _apiLogStatus   = 'ALL';
  String _apiLogRole     = 'ALL';
  final  TextEditingController _apiLogQueryCtrl = TextEditingController();

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
    _apiLogQueryCtrl.dispose();
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
        _fetchElectionConfigs(),
      ]);

  Future<void> _fetchOverview() async {
    setState(() => _loadingOverview = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get("/master/overview", token: token);
      setState(() => _overview = OverviewStats.fromJson(res["data"] ?? {}));
    } catch (_) {} finally {
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
            .map((e) => SuperAdminModel.fromJson(e)).toList();
      });
    } catch (_) {
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
            .map((e) => AdminModel.fromJson(e)).toList();
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
            .map((e) => SystemLogEntry.fromJson(e)).toList();
      });
    } catch (_) {
      _snack("Failed to load logs", kError);
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _fetchApiLogs() async {
    setState(() => _loadingApiLogs = true);
    try {
      final token  = await AuthService.getToken();
      final params = <String, String>{
        'limit':  '$_apiLogsLimit',
        'offset': '${_apiLogsPage * _apiLogsLimit}',
        if (_apiLogLevel  != 'ALL') 'level':  _apiLogLevel,
        if (_apiLogMethod != 'ALL') 'method': _apiLogMethod,
        if (_apiLogStatus != 'ALL') 'status': _apiLogStatus,
        if (_apiLogRole   != 'ALL') 'role':   _apiLogRole,
        if (_apiLogQueryCtrl.text.trim().isNotEmpty) 'q': _apiLogQueryCtrl.text.trim(),
      };
      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      final res = await ApiService.get("/master/api-logs?$qs", token: token);
      final d = res["data"] as Map<String, dynamic>? ?? {};
      setState(() {
        _apiLogs = (d['items'] as List? ?? [])
            .map((e) => ApiLogEntry.fromJson(e)).toList();
        _apiLogsTotal = d['total'] ?? 0;
      });
    } catch (_) {
      _snack("Failed to load API logs", kError);
    } finally {
      if (mounted) setState(() => _loadingApiLogs = false);
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

  Future<void> _fetchElectionConfigs() async {
    setState(() => _loadingElectionCfg = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get(
        "/master/election-configs?includeArchived=${_showArchivedConfigs ? 1 : 0}",
        token: token,
      );
      setState(() {
        _electionConfigs = (res["data"] as List? ?? [])
            .map((e) => ElectionConfigModel.fromJson(e)).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _electionConfigs = []);
    } finally {
      if (mounted) setState(() => _loadingElectionCfg = false);
    }
  }

  void _switchTab(int i) {
    setState(() => _selectedTab = i);
    _fadeCtrl.forward(from: 0);
    if (i == 4 && _apiLogs.isEmpty) {
      _fetchApiLogs();
    }
  }

  // ══════════════════════════════════════════
  //  CREATE/EDIT ELECTION CONFIG DIALOG
  // ══════════════════════════════════════════
  void _showCreateOrEditElectionConfig({ElectionConfigModel? existing}) {
    final isEdit = existing != null;

    String? selectedDistrict = existing?.district;
    String? selectedState    = existing?.state.isNotEmpty == true ? existing!.state : kStates.first;
    String? selectedType     = existing?.electionType;
    String? selectedPhase    = existing?.phase;

    
    final yearCtrl  = TextEditingController(
        text: existing?.electionYear ?? DateTime.now().year.toString());
    final dateCtrl  = TextEditingController(text: existing?.electionDate ?? '');
    final pratahCtrl = TextEditingController(text: existing?.pratahSamay ?? '');
    final sayaCtrl   = TextEditingController(text: existing?.sayaSamay ?? '');
    final instrCtrl  = TextEditingController(text: existing?.instructions ?? '');

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => _styledDialog(
          title: isEdit ? 'निर्वाचन कॉन्फ़िग संपादित करें' : 'नई निर्वाचन कॉन्फ़िग जोड़ें',
          icon: Icons.how_to_vote_outlined,
          ctx: ctx,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // District (locked when editing)
                AbsorbPointer(
                  absorbing: isEdit,
                  child: Opacity(
                    opacity: isEdit ? 0.55 : 1,
                    child: DropdownButtonFormField<String>(
                      value: selectedDistrict,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      decoration: _dlgDecoration('जनपद *', Icons.location_city_outlined),
                      items: kUpDistricts
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text(d, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setDlg(() => selectedDistrict = v),
                      validator: (v) => v == null || v.isEmpty ? 'जनपद चुनें' : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // State
                DropdownButtonFormField<String>(
                  value: selectedState,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  decoration: _dlgDecoration('राज्य *', Icons.map_outlined),
                  items: kStates.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setDlg(() => selectedState = v),
                  validator: (v) => v == null || v.isEmpty ? 'राज्य चुनें' : null,
                ),
                const SizedBox(height: 12),

                // Type
                DropdownButtonFormField<String>(
                  value: selectedType,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  decoration: _dlgDecoration('निर्वाचन प्रकार *', Icons.how_to_vote_outlined),
                  items: kElectionTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setDlg(() => selectedType = v),
                  validator: (v) => v == null || v.isEmpty ? 'प्रकार चुनें' : null,
                ),
                const SizedBox(height: 12),


                // Phase
                DropdownButtonFormField<String>(
                  value: selectedPhase,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  decoration: _dlgDecoration('चरण *', Icons.flag_outlined),
                  items: kElectionPhases
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setDlg(() => selectedPhase = v),
                  validator: (v) => v == null || v.isEmpty ? 'चरण चुनें' : null,
                ),
                const SizedBox(height: 12),

                // Year
                _dlgField(yearCtrl, 'वर्ष *', Icons.calendar_today_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    validator: (v) => (v == null || v.length != 4) ? 'सही वर्ष दर्ज करें' : null),
                const SizedBox(height: 12),

                // Date picker
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
                      dateCtrl.text = picked.toIso8601String().split("T")[0];
                      setDlg(() {});
                    }
                  },
                  child: AbsorbPointer(
                    child: _dlgField(dateCtrl, 'मतदान तिथि *', Icons.event_outlined,
                        validator: _notEmpty),
                  ),
                ),
                const SizedBox(height: 12),

                // Pratah samay + Saya samay (two columns on wide, stack on narrow)
                LayoutBuilder(builder: (ctx, c) {
                  final wide = c.maxWidth > 380;
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(child: _timePickerField(
                          context: context, ctrl: pratahCtrl,
                          label: 'प्रातः समय', icon: Icons.wb_sunny_outlined,
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _timePickerField(
                          context: context, ctrl: sayaCtrl,
                          label: 'सायं समय', icon: Icons.nights_stay_outlined,
                        )),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _timePickerField(
                        context: context, ctrl: pratahCtrl,
                        label: 'प्रातः समय', icon: Icons.wb_sunny_outlined,
                      ),
                      const SizedBox(height: 12),
                      _timePickerField(
                        context: context, ctrl: sayaCtrl,
                        label: 'सायं समय', icon: Icons.nights_stay_outlined,
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 12),

                // Instructions
                _dlgField(instrCtrl, 'विशेष निर्देश (वैकल्पिक)', Icons.notes_outlined,
                    maxLines: 3),

                if (!isEdit && selectedDistrict != null) ...[
                  const SizedBox(height: 14),
                  _hasActiveConfigForDistrict(selectedDistrict!),
                ],

                const SizedBox(height: 18),
                _dlgActions(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final token = await AuthService.getToken();
                      final body = {
                        "district":      selectedDistrict,
                        "state":         selectedState,
                        "electionType":  selectedType,
                        "electionName":  "$selectedType ${yearCtrl.text.trim()}",
                        "phase":         selectedPhase,
                        "electionYear":  yearCtrl.text.trim(),
                        "electionDate":  dateCtrl.text.trim(),
                        "pratahSamay":   pratahCtrl.text.trim(),
                        "sayaSamay":     sayaCtrl.text.trim(),
                        "instructions":  instrCtrl.text.trim(),
                      };
                      if (isEdit) {
                        await ApiService.put(
                          "/master/election-configs/${existing.id}",
                          body, token: token,
                        );
                      } else {
                        await ApiService.post(
                          "/master/election-configs", body, token: token,
                        );
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack(isEdit ? 'कॉन्फ़िग अपडेट हुई ✓' : 'नई कॉन्फ़िग सहेजी गई ✓', kSuccess);
                      _fetchElectionConfigs();
                      _fetchOverview();
                    } catch (e) {
                      _snack("Error: $e", kError);
                    }
                  },
                  confirmLabel: isEdit ? 'अपडेट करें' : 'सहेजें',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hasActiveConfigForDistrict(String district) {
    final has = _electionConfigs.any(
        (c) => c.district == district && c.isActive && !c.isArchived);
    if (!has) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kWarning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kWarning.withOpacity(0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: kWarning, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'इस जनपद की पुरानी सक्रिय कॉन्फ़िग स्वतः इतिहास में चली जाएगी।',
              style: TextStyle(color: kWarning, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timePickerField({
    required BuildContext context,
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: () async {
        TimeOfDay initial = TimeOfDay.now();
        if (ctrl.text.isNotEmpty) {
          final p = ctrl.text.split(':');
          if (p.length == 2) {
            initial = TimeOfDay(
              hour:   int.tryParse(p[0]) ?? 8,
              minute: int.tryParse(p[1]) ?? 0,
            );
          }
        }
        final picked = await showTimePicker(
          context: context, initialTime: initial,
        );
        if (picked != null) {
          ctrl.text = '${picked.hour.toString().padLeft(2, '0')}:'
                      '${picked.minute.toString().padLeft(2, '0')}';
        }
      },
      child: AbsorbPointer(
        child: _dlgField(ctrl, label, icon),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  CREATE SUPER ADMIN
  // ══════════════════════════════════════════
  void _showCreateSuperAdmin() {
    final nameCtrl    = TextEditingController();
    final userCtrl    = TextEditingController();
    String? selectedDistrict;
    final passCtrl    = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureP = true;
    bool obscureC = true;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => _styledDialog(
          title: 'सुपर एडमिन जोड़ें',
          icon: Icons.supervised_user_circle_outlined,
          ctx: ctx,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dlgField(nameCtrl, 'पूरा नाम', Icons.person_outline,
                    validator: _notEmpty),
                const SizedBox(height: 12),
                _dlgField(userCtrl, 'यूज़रनेम', Icons.alternate_email,
                    validator: _notEmpty),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedDistrict,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  decoration: _dlgDecoration('जनपद', Icons.location_city_outlined),
                  items: kUpDistricts.map((d) =>
                      DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setDlg(() => selectedDistrict = v),
                  validator: (v) => v == null ? 'जनपद चुनें' : null,
                ),
                const SizedBox(height: 12),
                _dlgField(passCtrl, 'पासवर्ड', Icons.lock_outline,
                    obscure: obscureP,
                    suffixIcon: _eyeIcon(obscureP, () => setDlg(() => obscureP = !obscureP)),
                    validator: (v) => (v == null || v.length < 6) ? 'न्यूनतम 6 अक्षर' : null),
                const SizedBox(height: 12),
                _dlgField(confirmCtrl, 'पासवर्ड पुष्टि करें', Icons.lock_outline,
                    obscure: obscureC,
                    suffixIcon: _eyeIcon(obscureC, () => setDlg(() => obscureC = !obscureC)),
                    validator: (v) => v != passCtrl.text ? 'पासवर्ड समान नहीं हैं' : null),
                const SizedBox(height: 20),
                _dlgActions(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.post("/master/super-admins", {
                        "name": nameCtrl.text.trim(),
                        "username": userCtrl.text.trim(),
                        "password": passCtrl.text,
                        "district": selectedDistrict,
                      }, token: token);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('सुपर एडमिन जोड़ा गया ✓', kSuccess);
                      _fetchSuperAdmins();
                      _fetchOverview();
                    } catch (e) {
                      _snack("Error: $e", kError);
                    }
                  },
                  confirmLabel: 'जोड़ें',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── CREATE ADMIN ──────────────────────────
  void _showCreateAdmin() {
    final nameCtrl    = TextEditingController();
    final userCtrl    = TextEditingController();
    String? selectedDistrict;
    final passCtrl    = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureP = true;
    bool obscureC = true;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => _styledDialog(
          title: 'एडमिन जोड़ें',
          icon: Icons.manage_accounts_outlined,
          ctx: ctx,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dlgField(nameCtrl, 'पूरा नाम', Icons.person_outline, validator: _notEmpty),
                const SizedBox(height: 12),
                _dlgField(userCtrl, 'यूज़रनेम', Icons.alternate_email, validator: _notEmpty),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedDistrict,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  decoration: _dlgDecoration('जनपद', Icons.location_city_outlined),
                  items: kUpDistricts.map((d) =>
                      DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setDlg(() => selectedDistrict = v),
                  validator: (v) => v == null ? 'जनपद चुनें' : null,
                ),
                const SizedBox(height: 12),
                _dlgField(passCtrl, 'पासवर्ड', Icons.lock_outline,
                    obscure: obscureP,
                    suffixIcon: _eyeIcon(obscureP, () => setDlg(() => obscureP = !obscureP)),
                    validator: (v) => (v == null || v.length < 6) ? 'न्यूनतम 6 अक्षर' : null),
                const SizedBox(height: 12),
                _dlgField(confirmCtrl, 'पासवर्ड पुष्टि करें', Icons.lock_outline,
                    obscure: obscureC,
                    suffixIcon: _eyeIcon(obscureC, () => setDlg(() => obscureC = !obscureC)),
                    validator: (v) => v != passCtrl.text ? 'पासवर्ड समान नहीं हैं' : null),
                const SizedBox(height: 20),
                _dlgActions(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.post("/master/admins", {
                        "name":     nameCtrl.text.trim(),
                        "username": userCtrl.text.trim(),
                        "district": selectedDistrict,
                        "password": passCtrl.text,
                      }, token: token);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('एडमिन जोड़ा गया ✓', kSuccess);
                      _fetchAdmins();
                      _fetchOverview();
                    } catch (e) {
                      _snack("Error: $e", kError);
                    }
                  },
                  confirmLabel: 'जोड़ें',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  FORCE-LOGOUT DIALOG
  // ══════════════════════════════════════════
  void _showForceLogout() {
    final Map<String, bool> selected = {
      'super_admin': false,
      'admin':       false,
      'staff':       false,
    };
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => _styledDialog(
          title: 'सभी उपयोगकर्ताओं को लॉगआउट करें',
          icon: Icons.logout_rounded,
          ctx: ctx,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kError.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kError.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: kError, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'चयनित भूमिकाओं के सभी सक्रिय सत्र तुरंत समाप्त हो जाएंगे। '
                        'उपयोगकर्ताओं को फिर से लॉगिन करना होगा।',
                        style: TextStyle(color: kError, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('भूमिकाएँ चुनें:',
                  style: TextStyle(color: kDark, fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 8),

              _roleCheckboxTile(
                'सुपर एडमिन', 'super_admin', selected,
                Icons.supervised_user_circle, kDevAccent,
                onChanged: (v) => setDlg(() => selected['super_admin'] = v),
              ),
              _roleCheckboxTile(
                'एडमिन', 'admin', selected,
                Icons.manage_accounts, kPrimary,
                onChanged: (v) => setDlg(() => selected['admin'] = v),
              ),
              _roleCheckboxTile(
                'स्टाफ', 'staff', selected,
                Icons.groups_outlined, kInfo,
                onChanged: (v) => setDlg(() => selected['staff'] = v),
              ),

              const SizedBox(height: 14),
              _dlgField(reasonCtrl, 'कारण (वैकल्पिक)', Icons.edit_note_outlined),

              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'मास्टर अकाउंट सुरक्षित है — लॉगआउट नहीं होगा।',
                  style: TextStyle(color: kSubtle, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ),

              const SizedBox(height: 16),
              _dlgActions(
                onCancel: () => Navigator.pop(ctx),
                onConfirm: () async {
                  final roles = selected.entries.where((e) => e.value).map((e) => e.key).toList();
                  if (roles.isEmpty) {
                    _snack('कम से कम एक भूमिका चुनें', kError);
                    return;
                  }
                  // Confirm
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: kBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: kError, width: 1.5),
                      ),
                      title: const Row(children: [
                        Icon(Icons.warning_amber_rounded, color: kError),
                        SizedBox(width: 8),
                        Text('पुष्टि करें', style: TextStyle(color: kError, fontWeight: FontWeight.w800)),
                      ]),
                      content: Text(
                        '${roles.map((r) => _roleHindi(r)).join(', ')} '
                        'के सभी सत्र समाप्त किए जाएंगे। क्या आप सुनिश्चित हैं?',
                        style: const TextStyle(color: kDark, fontSize: 13),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('रद्द करें', style: TextStyle(color: kSubtle)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(c, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kError, foregroundColor: Colors.white),
                          child: const Text('हाँ, लॉगआउट करें'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;

                  try {
                    final token = await AuthService.getToken();
                    await ApiService.post("/master/force-logout", {
                      "roles":  roles,
                      "reason": reasonCtrl.text.trim(),
                    }, token: token);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('${roles.length} भूमिका(एं) लॉगआउट हुईं ✓', kSuccess);
                  } catch (e) {
                    _snack('त्रुटि: $e', kError);
                  }
                },
                confirmLabel: 'लॉगआउट करें',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleCheckboxTile(
    String label, String roleKey, Map<String, bool> selected,
    IconData icon, Color color,
    {required ValueChanged<bool> onChanged}
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: selected[roleKey]! ? color.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected[roleKey]! ? color : kBorder.withOpacity(0.4),
          width: selected[roleKey]! ? 1.5 : 1,
        ),
      ),
      child: CheckboxListTile(
        value: selected[roleKey],
        onChanged: (v) => onChanged(v ?? false),
        activeColor: color,
        controlAffinity: ListTileControlAffinity.trailing,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        title: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: kDark, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  String _roleHindi(String r) {
    switch (r) {
      case 'super_admin': return 'सुपर एडमिन';
      case 'admin':       return 'एडमिन';
      case 'staff':       return 'स्टाफ';
      default:            return r;
    }
  }

  InputDecoration _dlgDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: kSubtle),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kBorder.withOpacity(0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kBorder.withOpacity(0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kDevAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kError),
      ),
    );
  }

  // ── RESET PASSWORD ────────────────────────
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
          title: 'पासवर्ड रीसेट — $name',
          icon: Icons.lock_reset_outlined,
          ctx: ctx,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dlgField(passCtrl, 'नया पासवर्ड', Icons.lock_outline,
                    obscure: obscureP,
                    suffixIcon: _eyeIcon(obscureP, () => setDlg(() => obscureP = !obscureP)),
                    validator: (v) => (v == null || v.length < 6) ? 'न्यूनतम 6 अक्षर' : null),
                const SizedBox(height: 12),
                _dlgField(confirmCtrl, 'पासवर्ड पुष्टि करें', Icons.lock_outline,
                    obscure: obscureC,
                    suffixIcon: _eyeIcon(obscureC, () => setDlg(() => obscureC = !obscureC)),
                    validator: (v) => v != passCtrl.text ? 'पासवर्ड समान नहीं हैं' : null),
                const SizedBox(height: 20),
                _dlgActions(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.patch(endpoint, {"password": passCtrl.text}, token: token);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('पासवर्ड रीसेट हुआ ✓', kSuccess);
                    } catch (e) {
                      _snack("Error: $e", kError);
                    }
                  },
                  confirmLabel: 'रीसेट करें',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── DB TOOLS ──────────────────────────────
  void _showDbTools() {
    showDialog(
      context: context,
      builder: (ctx) => _styledDialog(
        title: 'डेटाबेस टूल्स',
        icon: Icons.storage_outlined,
        ctx: ctx,
        child: Column(
          children: [
            _dbToolTile(Icons.backup_outlined, 'बैकअप बनाएँ',
                'पूरा MySQL डंप सर्वर पर सहेजें', kSuccess, () async {
              Navigator.pop(ctx);
              try {
                final token = await AuthService.getToken();
                await ApiService.post("/master/db/backup", {}, token: token);
                _snack('बैकअप पूरा ✓', kSuccess);
                _fetchSystemStats();
              } catch (_) {
                _snack('बैकअप विफल', kError);
              }
            }),
            _dbToolTile(Icons.archive_outlined, 'पुरानी कॉन्फ़िग आर्काइव करें',
                'समाप्त निर्वाचन तिथियों को इतिहास में भेजें', kInfo, () async {
              Navigator.pop(ctx);
              try {
                final token = await AuthService.getToken();
                final res = await ApiService.post(
                  "/master/election-configs/auto-archive", {}, token: token);
                final n = res['data']?['archived'] ?? 0;
                _snack('$n कॉन्फ़िग आर्काइव हुई ✓', kSuccess);
                _fetchElectionConfigs();
                _fetchOverview();
              } catch (_) {
                _snack('आर्काइव विफल', kError);
              }
            }),
            _dbToolTile(Icons.cleaning_services_outlined, 'कैश साफ़ करें',
                'सर्वर रिस्पॉन्स कैश साफ़ करें', kWarning, () async {
              Navigator.pop(ctx);
              try {
                final token = await AuthService.getToken();
                await ApiService.post("/master/db/flush-cache", {}, token: token);
                _snack('कैश साफ़ हुआ ✓', kInfo);
              } catch (_) {
                _snack('कैश साफ़ करने में विफल', kError);
              }
            }),
            _dbToolTile(Icons.build_outlined, 'माइग्रेशन चलाएँ',
                'DB स्कीमा अपडेट लागू करें', kPrimary, () async {
              Navigator.pop(ctx);
              try {
                final token = await AuthService.getToken();
                await ApiService.post("/master/migrate", {}, token: token);
                _snack('माइग्रेशन पूरा ✓', kSuccess);
              } catch (_) {
                _snack('माइग्रेशन विफल', kError);
              }
            }),
          ],
        ),
      ),
    );
  }

  // ── CONFIRM DESTRUCTIVE ───────────────────
  void _confirmDestructive(String title, String body, VoidCallback onConfirm) {
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
                style: const TextStyle(color: kError,
                    fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ]),
        content: Text(body, style: const TextStyle(color: kDark, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('रद्द करें', style: TextStyle(color: kSubtle))),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); onConfirm(); },
            style: ElevatedButton.styleFrom(
                backgroundColor: kError, foregroundColor: Colors.white),
            child: const Text('पुष्टि करें'),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
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
                    style: TextStyle(color: Colors.white, fontSize: 10,
                        fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('मास्टर एडमिन कंसोल',
                    style: TextStyle(color: kBorder, fontSize: 11,
                        fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                Text('Election Management — Developer Access',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white54, fontSize: 9.5)),
              ],
            ),
          ),
          _topBarBtn(Icons.logout_rounded, 'लॉगआउट सभी', _showForceLogout),
          _topBarBtn(Icons.storage, 'DB', _showDbTools),
          _topBarBtn(Icons.refresh, 'रिफ्रेश', () {
            _fetchAll();
            _snack('रिफ्रेश हो रहा है…', kInfo);
          }),
          IconButton(
            onPressed: () async {
              await AuthService.logout();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Icons.exit_to_app, color: Colors.white54, size: 20),
            tooltip: 'लॉगआउट',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _topBarBtn(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 13, color: kBorder),
        label: Text(label, style: const TextStyle(
            color: kBorder, fontSize: 10.5, fontWeight: FontWeight.w700)),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: const Size(0, 32)),
      ),
    );
  }

  // ── TAB BAR ───────────────────────────────
  Widget _buildTabBar() {
    final tabs = [
      (Icons.dashboard_outlined,        'सारांश'),
      (Icons.how_to_vote_outlined,      'निर्वाचन'),
      (Icons.supervised_user_circle,    'सुपर एडमिन'),
      (Icons.manage_accounts_outlined,  'एडमिन'),
      (Icons.api_outlined,              'API लॉग'),
      (Icons.receipt_long_outlined,     'सिस्टम लॉग'),
      (Icons.settings_outlined,         'सेटिंग्स'),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: sel ? kBg : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                        color: sel ? kDevAccent : Colors.transparent, width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(tabs[i].$1, size: 14, color: sel ? kDevAccent : kSubtle),
                    const SizedBox(width: 6),
                    Text(tabs[i].$2,
                        style: TextStyle(
                          color: sel ? kDevAccent : kSubtle,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
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
      case 1: return _buildElectionConfigs();
      case 2: return _buildSuperAdmins();
      case 3: return _buildAdmins();
      case 4: return _buildApiLogs();
      case 5: return _buildLogs();
      case 6: return _buildConfig();
      default: return _buildOverview();
    }
  }

  // ══════════════════════════════════════════
  //  TAB 0 — OVERVIEW
  // ══════════════════════════════════════════
  Widget _buildOverview() {
    if (_loadingOverview && _loadingStats) {
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
            _electionSummaryBanner(),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth > 720 ? 6 : (c.maxWidth > 480 ? 3 : 2);
              return GridView.count(
                shrinkWrap: true,
                crossAxisCount: cols,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.4,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _statCard('सक्रिय निर्वाचन',
                      '${_overview.activeElectionConfigs}',
                      Icons.how_to_vote, kDevAccent),
                  _statCard('इतिहास',
                      '${_overview.archivedElectionConfigs}',
                      Icons.archive_outlined, kSubtle),
                  _statCard('सुपर एडमिन',
                      '${_overview.totalSuperAdmins}',
                      Icons.supervised_user_circle_outlined, kPrimary),
                  _statCard('एडमिन',
                      '${_overview.totalAdmins}',
                      Icons.manage_accounts, kAccent),
                  _statCard('स्टाफ',
                      '${_overview.totalStaff}',
                      Icons.groups_outlined, kInfo),
                  _statCard('बूथ',
                      '${_overview.totalBooths}',
                      Icons.location_on_outlined, kSuccess),
                ],
              );
            }),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const HierarchyReportPage(role: "master"))),
              child: _navTile('पदानुक्रम रिपोर्ट',
                  Icons.table_chart_outlined,
                  const [Color(0xFF0F2B5B), Color(0xFF1A3D7C)]),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const MapViewPage())),
              child: _navTile('मानचित्र दृश्य',
                  Icons.map,
                  const [Color(0xFF00695C), Color(0xFF00897B)]),
            ),
            const SizedBox(height: 18),
            _sectionLabel('सिस्टम जानकारी'),
            const SizedBox(height: 10),
            _infoTable(_sysStats),
            const SizedBox(height: 18),
            _sectionLabel('हालिया गतिविधि'),
            const SizedBox(height: 10),
            if (_loadingLogs)
              const Center(child: CircularProgressIndicator(color: kDevAccent))
            else
              ..._logs.take(5).map(_logTile),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _navTile(String label, IconData icon, List<Color> gradient) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const Icon(Icons.chevron_right, color: Colors.white),
        ],
      ),
    );
  }

  Widget _electionSummaryBanner() {
    final active = _electionConfigs.where((c) => c.isActive && !c.isArchived).toList();
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1A0A00), Color(0xFF3D1A00)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.5)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.how_to_vote, color: kBorder, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: active.isEmpty
                ? const Text('कोई सक्रिय निर्वाचन कॉन्फ़िग नहीं',
                    style: TextStyle(color: Colors.white60, fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${active.length} जनपद में सक्रिय',
                          style: const TextStyle(color: kBorder, fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(active.take(3).map((c) => c.district).join(' • '),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
          ),
          GestureDetector(
            onTap: () => _switchTab(1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: kDevAccent, borderRadius: BorderRadius.circular(8)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text('प्रबंधित करें',
                      style: TextStyle(color: Colors.white, fontSize: 11,
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
  //  TAB 1 — ELECTION CONFIGS
  // ══════════════════════════════════════════
  Widget _buildElectionConfigs() {
    return Column(
      children: [
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_electionConfigs.where((c) => !c.isArchived).length} सक्रिय • '
                  '${_electionConfigs.where((c) => c.isArchived).length} इतिहास',
                  style: const TextStyle(color: kDark,
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              IconButton(
                tooltip: _showArchivedConfigs ? 'इतिहास छुपाएँ' : 'इतिहास दिखाएँ',
                onPressed: () {
                  setState(() => _showArchivedConfigs = !_showArchivedConfigs);
                  _fetchElectionConfigs();
                },
                icon: Icon(
                  _showArchivedConfigs ? Icons.visibility_off : Icons.history,
                  size: 18, color: kSubtle,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                onPressed: _fetchElectionConfigs,
                icon: const Icon(Icons.refresh, color: kSubtle, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: () => _showCreateOrEditElectionConfig(),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('नई कॉन्फ़िग'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDevAccent, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingElectionCfg
              ? const Center(child: CircularProgressIndicator(color: kDevAccent))
              : RefreshIndicator(
                  onRefresh: _fetchElectionConfigs,
                  color: kDevAccent,
                  child: _electionConfigs.isEmpty
                      ? _emptyState(
                          'कोई कॉन्फ़िग नहीं',
                          '"नई कॉन्फ़िग" पर टैप करके जोड़ें',
                          Icons.how_to_vote_outlined)
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _electionConfigs.length,
                          itemBuilder: (_, i) =>
                              _electionConfigCard(_electionConfigs[i]),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _electionConfigCard(ElectionConfigModel cfg) {
    final isHistory = cfg.isArchived;
    final headerColor = isHistory
        ? kSubtle.withOpacity(0.18)
        : kDevAccent.withOpacity(0.10);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHistory ? kSubtle.withOpacity(0.5) : kDevAccent.withOpacity(0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(color: kPrimary.withOpacity(0.05), blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13), topRight: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Icon(
                  isHistory ? Icons.archive : Icons.how_to_vote,
                  color: isHistory ? kSubtle : kDevAccent, size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cfg.district,
                          style: const TextStyle(color: kDark,
                              fontWeight: FontWeight.w800, fontSize: 14.5)),
                      Text(cfg.electionName,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kSubtle, fontSize: 11.5)),
                    ],
                  ),
                ),
                if (isHistory)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kSubtle.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kSubtle, width: 1),
                    ),
                    child: const Text('इतिहास',
                        style: TextStyle(color: kSubtle, fontSize: 10,
                            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kSuccess.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kSuccess, width: 1),
                    ),
                    child: const Text('सक्रिय',
                        style: TextStyle(color: kSuccess, fontSize: 10,
                            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                const SizedBox(width: 4),
                if (!isHistory)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _showCreateOrEditElectionConfig(existing: cfg);
                      if (v == 'archive') {
                        _confirmDestructive(
                          'कॉन्फ़िग आर्काइव करें?',
                          '${cfg.district} की सक्रिय कॉन्फ़िग इतिहास में चली जाएगी।',
                          () async {
                            try {
                              final token = await AuthService.getToken();
                              await ApiService.patch(
                                "/master/election-configs/${cfg.id}/archive",
                                {}, token: token);
                              _fetchElectionConfigs();
                              _fetchOverview();
                              _snack('कॉन्फ़िग आर्काइव हुई ✓', kSuccess);
                            } catch (_) {
                              _snack('आर्काइव विफल', kError);
                            }
                          },
                        );
                      }
                      if (v == 'delete') {
                        _confirmDestructive(
                          'स्थायी रूप से हटाएँ?',
                          'यह क्रिया वापस नहीं ली जा सकती।',
                          () async {
                            try {
                              final token = await AuthService.getToken();
                              await ApiService.delete(
                                "/master/election-configs/${cfg.id}",
                                token: token);
                              _fetchElectionConfigs();
                              _fetchOverview();
                              _snack('कॉन्फ़िग हटाई गई', kError);
                            } catch (_) {
                              _snack('हटाने में विफल', kError);
                            }
                          },
                        );
                      }
                    },
                    icon: const Icon(Icons.more_vert, size: 18, color: kSubtle),
                    itemBuilder: (_) => [
                      _menuItem('edit',    'संपादित करें', Icons.edit_outlined),
                      _menuItem('archive', 'आर्काइव',     Icons.archive_outlined),
                      _menuItem('delete',  'हटाएँ',        Icons.delete_outline, color: kError),
                    ],
                  ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kvRow(Icons.flag_outlined, 'चरण', cfg.phase),
                _kvRow(Icons.how_to_vote_outlined, 'प्रकार', cfg.electionType),
                _kvRow(Icons.event_outlined, 'तिथि',
                    '${cfg.electionDate}  ·  ${cfg.electionYear}'),
                if (cfg.pratahSamay.isNotEmpty || cfg.sayaSamay.isNotEmpty)
                  _kvRow(Icons.access_time, 'समय',
                      '${cfg.pratahSamay.isEmpty ? "—" : "प्रातः ${cfg.pratahSamay}"}'
                      '   |   '
                      '${cfg.sayaSamay.isEmpty ? "—" : "सायं ${cfg.sayaSamay}"}'),
                if (cfg.instructions.isNotEmpty)
                  _kvRow(Icons.notes_outlined, 'निर्देश', cfg.instructions, multiline: true),
                if (isHistory && cfg.archivedAt != null)
                  _kvRow(Icons.archive_outlined, 'आर्काइव तिथि', cfg.archivedAt!.split('T').first),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvRow(IconData icon, String k, String v, {bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: kSubtle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(k,
                style: const TextStyle(color: kSubtle,
                    fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(v.isEmpty ? '—' : v,
                maxLines: multiline ? 5 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kDark,
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 2 — SUPER ADMINS
  // ══════════════════════════════════════════
  Widget _buildSuperAdmins() {
    return Column(
      children: [
        _listHeader(
          title: '${_superAdmins.length} सुपर एडमिन',
          onRefresh: _fetchSuperAdmins,
          buttonLabel: 'नया',
          buttonIcon: Icons.add,
          onButton: _showCreateSuperAdmin,
        ),
        Expanded(
          child: _loadingSuperAdmins
              ? const Center(child: CircularProgressIndicator(color: kDevAccent))
              : RefreshIndicator(
                  onRefresh: _fetchSuperAdmins,
                  color: kDevAccent,
                  child: _superAdmins.isEmpty
                      ? _emptyState('कोई सुपर एडमिन नहीं',
                          '"नया" पर टैप करें',
                          Icons.supervised_user_circle_outlined)
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _superAdmins.length,
                          itemBuilder: (_, i) => _superAdminCard(_superAdmins[i]),
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
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sa.isActive
                  ? kDevAccent.withOpacity(0.07)
                  : kError.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13), topRight: Radius.circular(13)),
            ),
            child: Row(
              children: [
                _idBadge('SA', sa.id),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sa.name, style: const TextStyle(color: kDark,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                      if (sa.district.isNotEmpty)
                        Text(sa.district, style: const TextStyle(
                            color: kSubtle, fontSize: 11)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.patch(
                        "/master/super-admins/${sa.id}/status",
                        {"isActive": !sa.isActive}, token: token);
                      _fetchSuperAdmins();
                    } catch (_) { _snack('स्थिति अपडेट विफल', kError); }
                  },
                  child: _statusBadge(sa.isActive),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'reset') _showResetPassword(sa.id, sa.name, 'super_admin');
                    if (v == 'delete') {
                      _confirmDestructive(
                        'सुपर एडमिन हटाएँ?',
                        '${sa.name} के अधीन सभी एडमिन प्रभावित होंगे।',
                        () async {
                          try {
                            final token = await AuthService.getToken();
                            await ApiService.delete(
                                "/master/super-admins/${sa.id}", token: token);
                            _fetchSuperAdmins();
                            _fetchOverview();
                            _snack('सुपर एडमिन हटाया गया', kError);
                          } catch (_) { _snack('हटाने में विफल', kError); }
                        },
                      );
                    }
                  },
                  icon: const Icon(Icons.more_vert, size: 18, color: kSubtle),
                  itemBuilder: (_) => [
                    _menuItem('reset',  'पासवर्ड रीसेट', Icons.lock_reset),
                    _menuItem('delete', 'हटाएँ',         Icons.delete_outline, color: kError),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRowWidget(Icons.alternate_email, '@${sa.username}'),
                      const SizedBox(height: 4),
                      _infoRowWidget(Icons.calendar_today_outlined,
                          'जोड़ा ${_fmt(sa.createdAt)}'),
                    ],
                  ),
                ),
                _pill('${sa.adminsUnder} एडमिन', kPrimary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 3 — ADMINS
  // ══════════════════════════════════════════
  Widget _buildAdmins() {
    return Column(
      children: [
        _listHeader(
          title: '${_admins.length} एडमिन',
          onRefresh: _fetchAdmins,
          buttonLabel: 'नया',
          buttonIcon: Icons.add,
          onButton: _showCreateAdmin,
        ),
        Expanded(
          child: _loadingAdmins
              ? const Center(child: CircularProgressIndicator(color: kDevAccent))
              : RefreshIndicator(
                  onRefresh: _fetchAdmins,
                  color: kDevAccent,
                  child: _admins.isEmpty
                      ? _emptyState('कोई एडमिन नहीं',
                          '"नया" पर टैप करें',
                          Icons.manage_accounts_outlined)
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
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
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: admin.isActive
                  ? kPrimary.withOpacity(0.07)
                  : kError.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13), topRight: Radius.circular(13)),
            ),
            child: Row(
              children: [
                _idBadge('AD', admin.id),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(admin.name, style: const TextStyle(color: kDark,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(admin.district, style: const TextStyle(
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
                        {"isActive": !admin.isActive}, token: token);
                      _fetchAdmins();
                    } catch (_) { _snack('स्थिति अपडेट विफल', kError); }
                  },
                  child: _statusBadge(admin.isActive),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'reset') _showResetPassword(admin.id, admin.name, 'admin');
                    if (v == 'delete') {
                      _confirmDestructive(
                        'एडमिन हटाएँ?',
                        '"${admin.name}" स्थायी रूप से हटाया जाएगा।',
                        () async {
                          try {
                            final token = await AuthService.getToken();
                            await ApiService.delete(
                                "/master/admins/${admin.id}", token: token);
                            _fetchAdmins();
                            _fetchOverview();
                            _snack('एडमिन हटाया गया', kError);
                          } catch (_) { _snack('हटाने में विफल', kError); }
                        },
                      );
                    }
                  },
                  icon: const Icon(Icons.more_vert, size: 18, color: kSubtle),
                  itemBuilder: (_) => [
                    _menuItem('reset',  'पासवर्ड रीसेट', Icons.lock_reset),
                    _menuItem('delete', 'हटाएँ',         Icons.delete_outline, color: kError),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRowWidget(Icons.alternate_email, '@${admin.username}'),
                      const SizedBox(height: 4),
                      _infoRowWidget(Icons.person_outline, 'द्वारा: ${admin.createdBy}'),
                      const SizedBox(height: 4),
                      _infoRowWidget(Icons.calendar_today_outlined,
                          'जोड़ा ${_fmt(admin.createdAt)}'),
                    ],
                  ),
                ),
                _pill('${admin.superZoneCount} ज़ोन', kAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 4 — API LOGS (paginated, filterable, scalable)
  // ══════════════════════════════════════════
  Widget _buildApiLogs() {
    final totalPages = (_apiLogsTotal / _apiLogsLimit).ceil().clamp(1, 99999);
    return Column(
      children: [
        // Filter row 1 — search + refresh
        Container(
          color: kSurface,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _apiLogQueryCtrl,
                  onSubmitted: (_) {
                    _apiLogsPage = 0;
                    _fetchApiLogs();
                  },
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'पथ, यूज़र, या त्रुटि खोजें…',
                    hintStyle: const TextStyle(fontSize: 12, color: kSubtle),
                    prefixIcon: const Icon(Icons.search, size: 16, color: kSubtle),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: kBorder.withOpacity(0.5))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: kBorder.withOpacity(0.5))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: kDevAccent, width: 1.5)),
                    suffixIcon: _apiLogQueryCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _apiLogQueryCtrl.clear();
                              _apiLogsPage = 0;
                              _fetchApiLogs();
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () { _apiLogsPage = 0; _fetchApiLogs(); },
                icon: const Icon(Icons.refresh, color: kSubtle, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        // Filter row 2 — chips (level, method, status, role)
        Container(
          color: kSurface,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterDropdown(
                  label: 'स्तर',
                  value: _apiLogLevel,
                  options: const ['ALL', 'INFO', 'WARN', 'ERROR'],
                  onChanged: (v) {
                    setState(() => _apiLogLevel = v);
                    _apiLogsPage = 0;
                    _fetchApiLogs();
                  },
                ),
                const SizedBox(width: 6),
                _filterDropdown(
                  label: 'मेथड',
                  value: _apiLogMethod,
                  options: const ['ALL', 'GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
                  onChanged: (v) {
                    setState(() => _apiLogMethod = v);
                    _apiLogsPage = 0;
                    _fetchApiLogs();
                  },
                ),
                const SizedBox(width: 6),
                _filterDropdown(
                  label: 'स्थिति',
                  value: _apiLogStatus,
                  options: const ['ALL', '2xx', '4xx', '5xx', '200', '401', '403', '404', '500'],
                  onChanged: (v) {
                    setState(() => _apiLogStatus = v);
                    _apiLogsPage = 0;
                    _fetchApiLogs();
                  },
                ),
                const SizedBox(width: 6),
                _filterDropdown(
                  label: 'भूमिका',
                  value: _apiLogRole,
                  options: const ['ALL', 'master', 'super_admin', 'admin', 'staff'],
                  onChanged: (v) {
                    setState(() => _apiLogRole = v);
                    _apiLogsPage = 0;
                    _fetchApiLogs();
                  },
                ),
              ],
            ),
          ),
        ),
        // Stats strip
        Container(
          color: kBg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Text('कुल: $_apiLogsTotal',
                  style: const TextStyle(color: kSubtle, fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              if (totalPages > 1)
                Text('पृष्ठ ${_apiLogsPage + 1} / $totalPages',
                    style: const TextStyle(color: kSubtle, fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        // List
        Expanded(
          child: _loadingApiLogs
              ? const Center(child: CircularProgressIndicator(color: kDevAccent))
              : _apiLogs.isEmpty
                  ? _emptyState('कोई API लॉग नहीं मिला',
                      'फ़िल्टर बदलें या सर्वर पर अनुरोध करें',
                      Icons.api_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      itemCount: _apiLogs.length,
                      itemBuilder: (_, i) => _apiLogTile(_apiLogs[i]),
                    ),
        ),
        // Pagination footer
        if (_apiLogsTotal > 0)
          Container(
            color: kSurface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _apiLogsPage > 0
                      ? () { setState(() => _apiLogsPage = 0); _fetchApiLogs(); }
                      : null,
                  icon: const Icon(Icons.first_page, size: 22),
                  color: kDevAccent,
                  disabledColor: kSubtle.withOpacity(0.4),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  onPressed: _apiLogsPage > 0
                      ? () { setState(() => _apiLogsPage--); _fetchApiLogs(); }
                      : null,
                  icon: const Icon(Icons.chevron_left, size: 22),
                  color: kDevAccent,
                  disabledColor: kSubtle.withOpacity(0.4),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: kDevAccent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${_apiLogsPage + 1} / $totalPages',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w800, fontSize: 12)),
                ),
                IconButton(
                  onPressed: _apiLogsPage < totalPages - 1
                      ? () { setState(() => _apiLogsPage++); _fetchApiLogs(); }
                      : null,
                  icon: const Icon(Icons.chevron_right, size: 22),
                  color: kDevAccent,
                  disabledColor: kSubtle.withOpacity(0.4),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  onPressed: _apiLogsPage < totalPages - 1
                      ? () {
                          setState(() => _apiLogsPage = totalPages - 1);
                          _fetchApiLogs();
                        }
                      : null,
                  icon: const Icon(Icons.last_page, size: 22),
                  color: kDevAccent,
                  disabledColor: kSubtle.withOpacity(0.4),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: kSubtle, fontSize: 11)),
          DropdownButton<String>(
            value: value,
            underline: const SizedBox.shrink(),
            isDense: true,
            iconSize: 16,
            style: const TextStyle(color: kDark, fontSize: 11.5,
                fontWeight: FontWeight.w700),
            items: options
                .map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(o,
                        style: const TextStyle(color: kDark, fontSize: 11.5,
                            fontWeight: FontWeight.w700))))
                .toList(),
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ],
      ),
    );
  }

  Widget _apiLogTile(ApiLogEntry log) {
    final color = _logColor(log.level);
    final methodColor = _methodColor(log.method);
    final isError = log.statusCode >= 400;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? color.withOpacity(0.4) : kBorder.withOpacity(0.3),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        dense: true,
        iconColor: kSubtle,
        collapsedIconColor: kSubtle,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: methodColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(log.method,
                  style: const TextStyle(color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.w900, letterSpacing: 0.4)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${log.statusCode}',
                  style: const TextStyle(color: Colors.white, fontSize: 9.5,
                      fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(log.path,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kDark, fontSize: 11.5,
                      fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            ),
            Text('${log.durationMs}ms',
                style: const TextStyle(color: kSubtle, fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              if (log.username.isNotEmpty) ...[
                const Icon(Icons.person, size: 11, color: kSubtle),
                const SizedBox(width: 3),
                Text(log.username,
                    style: const TextStyle(color: kSubtle, fontSize: 10.5)),
                const SizedBox(width: 8),
              ],
              if (log.role.isNotEmpty) ...[
                _miniPill(log.role, _roleColor(log.role)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(_fmtTime(log.createdAt),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: kSubtle, fontSize: 10.5)),
              ),
            ],
          ),
        ),
        children: [
          if (log.errorMessage.isNotEmpty)
            _detailRow('त्रुटि', log.errorMessage, valueColor: kError, mono: true),
          if (log.requestBody.isNotEmpty)
            _detailRow('बॉडी', log.requestBody, mono: true),
          if (log.ipAddress.isNotEmpty)
            _detailRow('IP', log.ipAddress, mono: true),
          _detailRow('समय', log.createdAt.toIso8601String()),
        ],
      ),
    );
  }

  Widget _detailRow(String k, String v, {Color? valueColor, bool mono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: kBorder.withOpacity(0.2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(k,
                style: const TextStyle(color: kSubtle, fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: SelectableText(v,
                style: TextStyle(color: valueColor ?? kDark,
                    fontSize: 11,
                    fontFamily: mono ? 'monospace' : null,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _miniPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 9.5,
              fontWeight: FontWeight.w800)),
    );
  }

  Color _methodColor(String m) {
    switch (m) {
      case 'GET':    return const Color(0xFF1565C0);
      case 'POST':   return const Color(0xFF2E7D32);
      case 'PUT':    return const Color(0xFFE65100);
      case 'PATCH':  return const Color(0xFF6A1B9A);
      case 'DELETE': return const Color(0xFFC0392B);
      default:       return kSubtle;
    }
  }

  Color _roleColor(String r) {
    switch (r) {
      case 'master':      return kDevAccent;
      case 'super_admin': return kDark;
      case 'admin':       return kPrimary;
      case 'staff':       return kInfo;
      default:            return kSubtle;
    }
  }

  // ══════════════════════════════════════════
  //  TAB 5 — SYSTEM LOGS (legacy)
  // ══════════════════════════════════════════
  Widget _buildLogs() {
    final filtered = _logFilter == 'ALL'
        ? _logs
        : _logs.where((l) => l.level == _logFilter).toList();

    return Column(
      children: [
        Container(
          color: kSurface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
                            color: _logFilter == f ? _logColor(f) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _logColor(f).withOpacity(0.5)),
                          ),
                          child: Text(f,
                              style: TextStyle(
                                color: _logFilter == f ? Colors.white : _logColor(f),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              )),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        Expanded(
          child: _loadingLogs
              ? const Center(child: CircularProgressIndicator(color: kDevAccent))
              : RefreshIndicator(
                  onRefresh: () => _fetchLogs(level: _logFilter),
                  color: kDevAccent,
                  child: filtered.isEmpty
                      ? _emptyState('कोई लॉग नहीं', 'इस फ़िल्टर के लिए कुछ नहीं',
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            child: Text(log.level,
                style: const TextStyle(color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.message,
                    style: const TextStyle(color: kDark, fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('${log.module}  •  ',
                        style: const TextStyle(color: kSubtle, fontSize: 11)),
                    Text(_fmtTime(log.time),
                        style: const TextStyle(color: kSubtle, fontSize: 11)),
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
  //  TAB 6 — SETTINGS / CONFIG
  // ══════════════════════════════════════════
  Widget _buildConfig() {
    if (_loadingConfig) {
      return const Center(child: CircularProgressIndicator(color: kDevAccent));
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
            _sectionLabel('एप्लिकेशन सेटिंग्स'),
            const SizedBox(height: 10),
            _configGroup([
              _configToggle(
                'मेंटेनेंस मोड',
                'सभी उपयोगकर्ताओं के लिए ऐप अक्षम करें',
                _appConfig['maintenanceMode']?.toString() == 'true',
                (v) => _updateConfig('maintenanceMode', v.toString()),
              ),
              _configToggle(
                'स्टाफ लॉगिन की अनुमति',
                'स्टाफ का लॉगिन सक्षम/अक्षम करें',
                _appConfig['allowStaffLogin']?.toString() != 'false',
                (v) => _updateConfig('allowStaffLogin', v.toString()),
              ),
              _configToggle(
                'पासवर्ड रीसेट अनिवार्य',
                'अगले लॉगिन पर सभी एडमिन को रीसेट करना होगा',
                _appConfig['forcePasswordReset']?.toString() == 'true',
                (v) => _updateConfig('forcePasswordReset', v.toString()),
              ),
            ]),
            const SizedBox(height: 18),
            _sectionLabel('सभी कॉन्फ़िग कीज़'),
            const SizedBox(height: 10),
            _configGroup(
              _appConfig.entries
                  .map((e) => _configInfo(e.key, e.value?.toString() ?? ''))
                  .toList(),
            ),
            const SizedBox(height: 18),
            _sectionLabel('डेवलपर टूल्स'),
            const SizedBox(height: 10),
            _configGroup([
              _devAction(Icons.archive_outlined, 'पुरानी कॉन्फ़िग आर्काइव करें',
                  'समाप्त निर्वाचन तिथियों को इतिहास में भेजें', () async {
                try {
                  final token = await AuthService.getToken();
                  final res = await ApiService.post(
                    "/master/election-configs/auto-archive", {}, token: token);
                  final n = res['data']?['archived'] ?? 0;
                  _snack('$n कॉन्फ़िग आर्काइव हुईं ✓', kSuccess);
                  _fetchElectionConfigs();
                  _fetchOverview();
                } catch (_) { _snack('आर्काइव विफल', kError); }
              }),
              _devAction(Icons.build_outlined, 'DB माइग्रेशन चलाएँ',
                  'डेटाबेस स्कीमा अपडेट लागू करें', () async {
                try {
                  final token = await AuthService.getToken();
                  await ApiService.post("/master/migrate", {}, token: token);
                  _snack('माइग्रेशन पूरा ✓', kSuccess);
                } catch (_) { _snack('माइग्रेशन विफल', kError); }
              }),
              _devAction(Icons.lock_reset, 'मास्टर पासवर्ड बदलें',
                  'मास्टर अकाउंट का पासवर्ड अपडेट करें', _showChangeMasterPassword),
              _devAction(Icons.delete_sweep_outlined, 'पुराने API लॉग साफ़ करें',
                  '30 दिन से पुराने लॉग हटाएँ', () async {
                try {
                  final token = await AuthService.getToken();
                  final res = await ApiService.delete(
                      "/master/api-logs/clear?days=30", token: token);
                  final n = res['data']?['deleted'] ?? 0;
                  _snack('$n पुराने लॉग हटाए गए', kSuccess);
                } catch (_) { _snack('विफल', kError); }
              }),
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
    bool obsOld  = true;
    bool obsNew  = true;
    bool obsConf = true;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => _styledDialog(
          title: 'मास्टर पासवर्ड बदलें',
          icon: Icons.lock_person_outlined,
          ctx: ctx,
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dlgField(oldCtrl, 'वर्तमान पासवर्ड', Icons.lock_outline,
                    obscure: obsOld,
                    suffixIcon: _eyeIcon(obsOld, () => setDlg(() => obsOld = !obsOld)),
                    validator: _notEmpty),
                const SizedBox(height: 12),
                _dlgField(newCtrl, 'नया पासवर्ड', Icons.lock_reset_outlined,
                    obscure: obsNew,
                    suffixIcon: _eyeIcon(obsNew, () => setDlg(() => obsNew = !obsNew)),
                    validator: (v) => (v == null || v.length < 6) ? 'न्यूनतम 6 अक्षर' : null),
                const SizedBox(height: 12),
                _dlgField(confCtrl, 'पुष्टि करें', Icons.lock_outline,
                    obscure: obsConf,
                    suffixIcon: _eyeIcon(obsConf, () => setDlg(() => obsConf = !obsConf)),
                    validator: (v) => v != newCtrl.text ? 'पासवर्ड समान नहीं हैं' : null),
                const SizedBox(height: 20),
                _dlgActions(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final token = await AuthService.getToken();
                      await ApiService.patch("/master/change-password", {
                        "oldPassword": oldCtrl.text,
                        "newPassword": newCtrl.text,
                      }, token: token);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _snack('पासवर्ड बदला गया ✓', kSuccess);
                    } catch (e) {
                      _snack("त्रुटि: $e", kError);
                    }
                  },
                  confirmLabel: 'बदलें',
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
      await ApiService.post("/master/config",
          {"key": key, "value": value}, token: token);
      _fetchConfig();
      _snack('कॉन्फ़िग अपडेट हुई ✓', kSuccess);
    } catch (_) {
      _snack('कॉन्फ़िग अपडेट विफल', kError);
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(color: kDark,
                fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: kSubtle, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: onButton,
            icon: Icon(buttonIcon, size: 14),
            label: Text(buttonLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDevAccent, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String title, String subtitle, IconData icon) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(icon, color: kBorder, size: 48),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center,
            style: const TextStyle(color: kDark,
                fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center,
            style: const TextStyle(color: kSubtle, fontSize: 12)),
      ],
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
          final kv = e.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: isLast ? null : Border(
                  bottom: BorderSide(color: kBorder.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Text(kv.key, style: const TextStyle(color: kSubtle,
                    fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kBorder.withOpacity(0.4)),
                  ),
                  child: Text(kv.value, style: const TextStyle(color: kDark,
                      fontSize: 12, fontWeight: FontWeight.w700,
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
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, size: 14, color: color),
          ),
          const Spacer(),
          Text(value, style: TextStyle(color: color,
              fontSize: 17, fontWeight: FontWeight.w900)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kSubtle, fontSize: 10,
                  fontWeight: FontWeight.w600)),
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
                color: kDevAccent, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: kDark,
            fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _infoRowWidget(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 13, color: kSubtle),
      const SizedBox(width: 6),
      Flexible(
        child: Text(text, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kSubtle, fontSize: 12)),
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
      child: Text(text, style: TextStyle(color: color,
          fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _idBadge(String prefix, int id) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(6)),
      child: Text('$prefix${id.toString().padLeft(3, '0')}',
          style: const TextStyle(color: kBorder, fontSize: 10,
              fontWeight: FontWeight.w900, letterSpacing: 0.8)),
    );
  }

  Widget _statusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? kSuccess.withOpacity(0.1) : kError.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? kSuccess : kError, width: 1),
      ),
      child: Text(isActive ? 'सक्रिय' : 'निष्क्रिय',
          style: TextStyle(color: isActive ? kSuccess : kError,
              fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
    );
  }

  Color _logColor(String level) {
    switch (level) {
      case 'ERROR': return kError;
      case 'WARN':  return kWarning;
      default:      return kInfo;
    }
  }

  Widget _configGroup(List<Widget> children) {
    if (children.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder.withOpacity(0.4)),
        ),
        child: const Text('कोई कॉन्फ़िग नहीं',
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
              border: isLast ? null : Border(
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        title: Text(title, style: const TextStyle(color: kDark,
            fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: kSubtle, fontSize: 11)),
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
            child: Text(key, style: const TextStyle(color: kSubtle,
                fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value, textAlign: TextAlign.right,
                style: const TextStyle(color: kDark,
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _devAction(IconData icon, String title, String subtitle,
      VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
            color: kDevLight, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: kDevAccent, size: 18),
      ),
      title: Text(title, style: const TextStyle(color: kDark,
          fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(color: kSubtle, fontSize: 11)),
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
      title: Text(title, style: const TextStyle(color: kDark,
          fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(color: kSubtle, fontSize: 11)),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder, width: 1.2),
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
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
            child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: const Icon(Icons.close, color: Colors.white54, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _dlgField(
    TextEditingController ctrl, String label, IconData icon, {
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      validator: validator,
      maxLines: obscure ? 1 : maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: kDark, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: kPrimary),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 18, color: kSubtle),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('रद्द करें'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: kDevAccent, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color,
            fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Utils ─────────────────────────────────
  String? _notEmpty(String? v) =>
      (v == null || v.trim().isEmpty) ? 'आवश्यक' : null;

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  String _fmtTime(DateTime dt) =>
      '${_fmt(dt)}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }
}