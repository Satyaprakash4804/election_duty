import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../admin/pages/duty_card_page.dart';
import 'duty_history_page.dart';

// ── PALETTE ───────────────────────────────────────────────────────────────────
const kBg        = Color(0xFFFDF6E3);
const kSurface   = Color(0xFFF5E6C8);
const kPrimary   = Color(0xFF8B6914);
const kAccent    = Color(0xFFB8860B);
const kDark      = Color(0xFF4A3000);
const kSubtle    = Color(0xFFAA8844);
const kBorder    = Color(0xFFD4A843);
const kError     = Color(0xFFC0392B);
const kSuccess   = Color(0xFF2D6A1E);
const kSuccessBg = Color(0xFFE6F2DF);
const kInfo      = Color(0xFF1A5276);
const kArmed     = Color(0xFF1B5E20);
const kUnarmed   = Color(0xFF37474F);

// ── Helpers ───────────────────────────────────────────────────────────────────
const _rankMap = {
  'constable': 'आरक्षी', 'head constable': 'मुख्य आरक्षी',
  'si': 'उप निरीक्षक', 'sub inspector': 'उप निरीक्षक',
  'inspector': 'निरीक्षक', 'asi': 'सहायक उप निरीक्षक',
  'assistant sub inspector': 'सहायक उप निरीक्षक',
  'dsp': 'उपाधीक्षक', 'asp': 'सहा0 पुलिस अधीक्षक',
  'sp': 'पुलिस अधीक्षक',
  'circle officer': 'क्षेत्राधिकारी', 'co': 'क्षेत्राधिकारी',
};

String rh(dynamic val) =>
    _rankMap[(val ?? '').toString().toLowerCase()] ?? val?.toString() ?? '—';

String v(dynamic x) =>
    (x == null || x.toString().trim().isEmpty) ? '—' : x.toString();

const _centerTypeMap = {
  'a++': 'अत्यति संवेदनशील',
  'a': 'अति संवेदनशील',
  'b': 'संवेदनशील',
  'c': 'सामान्य',
};
String ct(dynamic x) =>
    _centerTypeMap[(x ?? '').toString().toLowerCase()] ?? x?.toString() ?? '—';

Color _typeColor(String? t) {
  switch ((t ?? '').toUpperCase()) {
    case 'A++': return const Color(0xFF6C3483);
    case 'A':   return kError;
    case 'B':   return kAccent;
    default:    return kInfo;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  MAIN DASHBOARD
// ══════════════════════════════════════════════════════════════════════════════
class StaffDashboardPage extends StatefulWidget {
  const StaffDashboardPage({super.key});
  @override
  State<StaffDashboardPage> createState() => _StaffDashboardPageState();
}

class _StaffDashboardPageState extends State<StaffDashboardPage>
    with TickerProviderStateMixin {
  int _navIdx = 0;

  Map? _duty, _user;
  bool _loading = true;
  String? _error;
  String _roleType = 'none'; // booth | sector | zone | kshetra | none
  String? _electionDate;
  bool _isAfterElection = false;

  late AnimationController _fadeCtrl;
  late Animation<double>    _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() { _fadeCtrl.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await AuthService.getToken();

      final results = await Future.wait([
        ApiService.get('/staff/profile', token: token),
        ApiService.get('/staff/my-duty', token: token),
        ApiService.get('/staff/election-date', token: token), // ✅ NEW API
      ]);

      final userResp = results[0];
      final resp = results[1];
      final electionResp = results[2];

      Map? dutyData;
      if (resp is Map) {
        dutyData = resp.containsKey('data')
            ? (resp['data'] is Map ? resp['data'] as Map : null)
            : resp;
      }

      final roleType = (dutyData?['roleType'] ?? 'none').toString();

      String? electionDate = electionResp['data'];

      bool isAfter = false;
      if (electionDate != null) {
        final ed = DateTime.tryParse(electionDate);
        if (ed != null) {
          isAfter = DateTime.now().isAfter(ed);
        }
      }

      setState(() {
        _user = userResp['data'] is Map ? userResp['data'] as Map : {};
        _duty = dutyData;
        _roleType = roleType;

        _electionDate = electionDate;     // ✅ NEW
        _isAfterElection = isAfter;       // ✅ NEW

        _loading = false;
      });

      _fadeCtrl.forward(from: 0);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _goTo(int idx) {
    setState(() => _navIdx = idx);
    _fadeCtrl.forward(from: 0);
  }

  // Nav config depends on role
  List<_NavItem> get _navItems {
    switch (_roleType) {
      case 'sector':
        return [
          _NavItem('डैशबोर्ड', Icons.dashboard_outlined, Icons.dashboard),
          _NavItem('ड्यूटी', Icons.location_on_outlined, Icons.location_on),
          _NavItem('बूथ & उपस्थिति', Icons.how_to_vote_outlined, Icons.how_to_vote),
          _NavItem('मानक', Icons.rule_folder_outlined, Icons.rule_folder),
          _NavItem('पासवर्ड', Icons.key_outlined, Icons.key),
        ];
      case 'zone':
        return [
          _NavItem('डैशबोर्ड', Icons.dashboard_outlined, Icons.dashboard),
          _NavItem('ड्यूटी', Icons.location_on_outlined, Icons.location_on),
          _NavItem('सेक्टर', Icons.grid_view_outlined, Icons.grid_view),
          _NavItem('मानक', Icons.rule_folder_outlined, Icons.rule_folder),
          _NavItem('पासवर्ड', Icons.key_outlined, Icons.key),
        ];
      case 'kshetra':
        return [
          _NavItem('डैशबोर्ड', Icons.dashboard_outlined, Icons.dashboard),
          _NavItem('ड्यूटी', Icons.location_on_outlined, Icons.location_on),
          _NavItem('जोन', Icons.map_outlined, Icons.map),
          _NavItem('मानक', Icons.rule_folder_outlined, Icons.rule_folder),
          _NavItem('पासवर्ड', Icons.key_outlined, Icons.key),
        ];
      default: // booth
        return [
          _NavItem('डैशबोर्ड', Icons.dashboard_outlined, Icons.dashboard),
          _NavItem('ड्यूटी', Icons.location_on_outlined, Icons.location_on),
          _NavItem('सहयोगी', Icons.groups_outlined, Icons.groups),
          _NavItem('ड्यूटी कार्ड', Icons.badge_outlined, Icons.badge),
          _NavItem('पासवर्ड', Icons.key_outlined, Icons.key),
        ];
    }
  }

  Future<void> _openMap() async {
    final lat = _duty?['latitude'];
    final lng = _duty?['longitude'];
    if (lat == null || lng == null) {
      _showNoLocationDialog();
      return;
    }
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showNoLocationDialog();
      }
    } catch (_) { _showNoLocationDialog(); }
  }

  void _showNoLocationDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kError.withOpacity(0.4))),
      title: const Row(children: [
        Icon(Icons.location_off_outlined, color: kError, size: 20),
        SizedBox(width: 8),
        Expanded(child: Text('लोकेशन उपलब्ध नहीं',
            style: TextStyle(color: kDark, fontSize: 15, fontWeight: FontWeight.w800))),
      ]),
      content: const Text('इस केंद्र की GPS लोकेशन अभी तक दर्ज नहीं है।',
          style: TextStyle(color: kDark, fontSize: 13)),
      actions: [ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(backgroundColor: kPrimary, foregroundColor: Colors.white),
          child: const Text('ठीक है'))],
    ));
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: kError, width: 1.5)),
      title: const Row(children: [
        Icon(Icons.logout, color: kError), SizedBox(width: 8),
        Text('लॉग आउट', style: TextStyle(color: kError)),
      ]),
      content: const Text('क्या आप लॉग आउट करना चाहते हैं?',
          style: TextStyle(color: kDark)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रद्द', style: TextStyle(color: kSubtle))),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kError, foregroundColor: Colors.white),
            child: const Text('लॉग आउट')),
      ],
    ));
    if (ok == true) {
      await AuthService.logout();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _navItems;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: kBg,
        appBar: _buildAppBar(items),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : _error != null
                ? _ErrorState(error: _error!, onRetry: _loadData)
                : FadeTransition(opacity: _fadeAnim, child: _buildBody()),
        bottomNavigationBar: _buildBottomNav(items),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(List<_NavItem> items) => AppBar(
    backgroundColor: kDark,
    elevation: 0,
    automaticallyImplyLeading: false,
    title: Row(children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: kPrimary,
          shape: BoxShape.circle,
          border: Border.all(color: kBorder),
        ),
        child: Icon(_roleIcon(), color: Colors.white, size: 18),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(items[_navIdx].label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(_user?['name'] ?? 'Staff Portal',
              style: const TextStyle(fontSize: 10, color: Colors.white60)),
        ],
      ),
    ]),
    actions: [
      // ✅ HISTORY BUTTON
      IconButton(
        icon: const Icon(Icons.history, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DutyHistoryPage()),
          );
        },
      ),

      Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: kSuccessBg.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kSuccess.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: kSuccess, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(_roleLabel(),
              style: const TextStyle(
                  color: kSuccess,
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ]),
      ),

      IconButton(
          icon: const Icon(Icons.refresh_rounded,
              color: Colors.white70, size: 20),
          onPressed: _loadData),

      IconButton(
          icon: const Icon(Icons.logout_rounded,
              color: Colors.white70),
          onPressed: _confirmLogout),
    ],
  );

  IconData _roleIcon() {
    switch (_roleType) {
      case 'sector':  return Icons.grid_view;
      case 'zone':    return Icons.map;
      case 'kshetra': return Icons.layers;
      default:        return Icons.how_to_vote;
    }
  }

  String _roleLabel() {
    switch (_roleType) {
      case 'sector':  return 'सेक्टर अधिकारी';
      case 'zone':    return 'जोनल अधिकारी';
      case 'kshetra': return 'क्षेत्र अधिकारी';
      case 'booth':   return 'बूथ स्टाफ';
      default:        return 'सक्रिय';
    }
  }

  Widget _buildBody() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Center(
        child: Column(
          children: [

            // ✅ ELECTION BANNER
            if (_electionDate != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isAfterElection
                      ? kSuccess.withOpacity(0.1)
                      : kInfo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isAfterElection
                          ? Icons.check_circle
                          : Icons.event,
                      color: _isAfterElection
                          ? kSuccess
                          : kInfo,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isAfterElection
                            ? "चुनाव संपन्न — इतिहास देखें"
                            : "चुनाव तिथि: $_electionDate",
                        style: const TextStyle(
                            fontWeight: FontWeight.w600),
                      ),
                    ),

                    // ✅ SHOW BUTTON ONLY AFTER ELECTION
                    if (_isAfterElection)
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const DutyHistoryPage()),
                          );
                        },
                        child: const Text("इतिहास देखें"),
                      )
                  ],
                ),
              ),

            _buildSection(),
          ],
        ),
      ),
    ),
  );

  Widget _buildSection() {
    switch (_roleType) {
      case 'sector':
        return _buildSectorSection();
      case 'zone':
        return _buildZoneSection();
      case 'kshetra':
        return _buildKshetraSection();
      default:
        return _buildBoothSection();
    }
  }

  // ── BOOTH sections ─────────────────────────────────────────────────────────
  Widget _buildBoothSection() {
    switch (_navIdx) {
      case 0: return _OverviewSection(duty: _duty, user: _user,
          noDuty: _duty == null, onGoToDutyCard: () => _goTo(3), onOpenMap: _openMap);
      case 1: return _DutyDetailSection(duty: _duty, noDuty: _duty == null, onOpenMap: _openMap);
      case 2: return _CoStaffSection(duty: _duty, noDuty: _duty == null);
      case 3: return _DutyCardSection(duty: _duty, user: _user, noDuty: _duty == null);
      case 4: return const _ChangePasswordSection();
      default: return const SizedBox();
    }
  }

  // ── SECTOR sections ────────────────────────────────────────────────────────
  Widget _buildSectorSection() {
    switch (_navIdx) {
      case 0: return _SectorOverviewSection(duty: _duty, user: _user);
      case 1: return _SectorInfoSection(duty: _duty);
      case 2: return _SectorBoothAttendanceSection(duty: _duty, onRefresh: _loadData);
      case 3: return _RulesSection(rules: _duty?['boothRules'] ?? []);
      case 4: return const _ChangePasswordSection();
      default: return const SizedBox();
    }
  }

  // ── ZONE sections ──────────────────────────────────────────────────────────
  Widget _buildZoneSection() {
    switch (_navIdx) {
      case 0: return _ZoneOverviewSection(duty: _duty, user: _user);
      case 1: return _ZoneInfoSection(duty: _duty);
      case 2: return _ZoneSectorsSection(duty: _duty);
      case 3: return _RulesSection(rules: _duty?['boothRules'] ?? []);
      case 4: return const _ChangePasswordSection();
      default: return const SizedBox();
    }
  }

  // ── KSHETRA sections ───────────────────────────────────────────────────────
  Widget _buildKshetraSection() {
    switch (_navIdx) {
      case 0: return _KshetraOverviewSection(duty: _duty, user: _user);
      case 1: return _KshetraInfoSection(duty: _duty);
      case 2: return _KshetraZonesSection(duty: _duty);
      case 3: return _RulesSection(rules: _duty?['boothRules'] ?? []);
      case 4: return const _ChangePasswordSection();
      default: return const SizedBox();
    }
  }

  Widget _buildBottomNav(List<_NavItem> items) => Container(
    decoration: const BoxDecoration(
        color: kSurface, border: Border(top: BorderSide(color: kBorder))),
    child: SafeArea(
      child: SizedBox(
        height: 65,
        child: Row(children: List.generate(items.length, (i) {
          final sel = _navIdx == i;
          return Expanded(child: GestureDetector(
            onTap: () => _goTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: sel ? kBg : Colors.transparent,
                border: Border(top: BorderSide(
                    color: sel ? kPrimary : Colors.transparent, width: 3)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(sel ? items[i].filledIcon : items[i].icon,
                    color: sel ? kPrimary : kSubtle, size: 22),
                const SizedBox(height: 3),
                Text(items[i].label, style: TextStyle(
                    fontSize: 9,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    color: sel ? kPrimary : kSubtle),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ));
        })),
      ),
    ),
  );
}

class _NavItem {
  final String label;
  final IconData icon, filledIcon;
  const _NavItem(this.label, this.icon, this.filledIcon);
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH — OVERVIEW
// ══════════════════════════════════════════════════════════════════════════════
class _OverviewSection extends StatelessWidget {
  final Map? duty, user;
  final bool noDuty;
  final VoidCallback onGoToDutyCard, onOpenMap;
  const _OverviewSection({required this.duty, required this.user,
      required this.noDuty, required this.onGoToDutyCard, required this.onOpenMap});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _HeroCard(user: user, duty: duty, noDuty: noDuty),
      const SizedBox(height: 18),
      if (!noDuty && duty != null) ...[
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.45,
          children: [
            _StatCard(icon: Icons.location_on_outlined, label: 'मतदान केंद्र',
                value: v(duty?['centerName']), color: kPrimary),
            _StatCard(icon: Icons.directions_bus_outlined, label: 'बस संख्या',
                value: (duty?['busNo']?.toString().isNotEmpty == true)
                    ? 'बस–${duty!['busNo']}' : '—', color: kInfo),
            _StatCard(icon: Icons.map_outlined, label: 'सेक्टर',
                value: v(duty?['sectorName']), color: kSuccess),
            _StatCard(icon: Icons.groups_outlined, label: 'सहयोगी कर्मी',
                value: '${(duty?['allStaff'] as List?)?.length ?? 0} कर्मी',
                color: const Color(0xFFD84315)),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(icon: Icons.info_outline_rounded, title: 'संक्षिप्त विवरण',
          child: Column(children: [
            _InfoTile(Icons.local_police_outlined, 'थाना', duty?['thana']),
            _InfoTile(Icons.account_balance_outlined, 'ग्राम पंचायत', duty?['gpName']),
            _InfoTile(Icons.layers_outlined, 'जोन', duty?['zoneName']),
            _InfoTile(Icons.public_outlined, 'सुपर जोन', duty?['superZoneName']),
            _InfoTile(Icons.category_outlined, 'केंद्र प्रकार', ct(duty?['centerType'])),
          ]),
        ),
        const SizedBox(height: 12),
        _NavButton(icon: Icons.navigation_rounded, label: 'Google Maps पर नेविगेट करें',
            color: kPrimary, onTap: onOpenMap),
        const SizedBox(height: 12),
        _NavButton(icon: Icons.print_outlined, label: 'ड्यूटी कार्ड प्रिंट करें',
            color: kDark, onTap: onGoToDutyCard),
      ] else
        const _NoDutyState(),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH — DUTY DETAILS
// ══════════════════════════════════════════════════════════════════════════════
class _DutyDetailSection extends StatelessWidget {
  final Map? duty; final bool noDuty; final VoidCallback onOpenMap;
  const _DutyDetailSection({required this.duty, required this.noDuty, required this.onOpenMap});

  @override
  Widget build(BuildContext context) {
    if (noDuty) return const _NoDutyState();
    return Column(children: [
      _SectionCard(icon: Icons.location_on_outlined, title: 'ड्यूटी स्थान',
        child: Column(children: [
          _InfoTile(Icons.how_to_vote_outlined, 'मतदान केंद्र', duty?['centerName']),
          _InfoTile(Icons.home_outlined, 'पता', duty?['centerAddress']),
          _InfoTile(Icons.category_outlined, 'केंद्र प्रकार', ct(duty?['centerType'])),
          _InfoTile(Icons.local_police_outlined, 'थाना', duty?['thana']),
          _InfoTile(Icons.account_balance_outlined, 'ग्राम पंचायत', duty?['gpName']),
        ]),
      ),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.map_outlined, title: 'प्रशासनिक विवरण',
        child: Column(children: [
          _InfoTile(Icons.map_outlined, 'सेक्टर', duty?['sectorName']),
          _InfoTile(Icons.layers_outlined, 'जोन', duty?['zoneName']),
          _InfoTile(Icons.home_work_outlined, 'जोन मुख्यालय', duty?['zoneHq']),
          _InfoTile(Icons.public_outlined, 'सुपर जोन', duty?['superZoneName']),
          _InfoTile(Icons.directions_bus_outlined, 'बस संख्या',
              (duty?['busNo']?.toString().isNotEmpty == true) ? 'बस–${duty!['busNo']}' : null),
          _InfoTile(Icons.person_outlined, 'नियुक्त किया', duty?['assignedBy']),
        ]),
      ),
      const SizedBox(height: 14),
      if ((duty?['sectorOfficers'] as List?)?.isNotEmpty == true)
        _OfficerCard(label: 'सेक्टर अधिकारी', officers: duty!['sectorOfficers'] as List),
      if ((duty?['zonalOfficers'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 12),
        _OfficerCard(label: 'जोनल अधिकारी', officers: duty!['zonalOfficers'] as List),
      ],
      if ((duty?['superOfficers'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 12),
        _OfficerCard(label: 'क्षेत्र अधिकारी', officers: duty!['superOfficers'] as List),
      ],
      const SizedBox(height: 14),
      _NavButton(icon: Icons.navigation_rounded, label: 'Google Maps पर नेविगेट करें',
          color: kPrimary, onTap: onOpenMap),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH — CO-STAFF
// ══════════════════════════════════════════════════════════════════════════════
class _CoStaffSection extends StatelessWidget {
  final Map? duty; final bool noDuty;
  const _CoStaffSection({required this.duty, required this.noDuty});

  @override
  Widget build(BuildContext context) {
    if (noDuty) return const _NoDutyState();
    final staff = duty?['allStaff'] as List? ?? [];
    return _SectionCard(
      icon: Icons.groups_outlined,
      title: 'सहयोगी कर्मी (${staff.length})',
      child: staff.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('कोई सहयोगी नहीं',
                  style: TextStyle(color: kSubtle, fontSize: 13))))
          : Column(children: staff.asMap().entries.map((e) {
              final i = e.key;
              final s = e.value is Map ? e.value as Map : {};
              final armed = s['is_armed'] == 1 || s['is_armed'] == true;
              return _StaffRow(index: i, staff: s, total: staff.length, armed: armed);
            }).toList()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  BOOTH — DUTY CARD
// ══════════════════════════════════════════════════════════════════════════════
class _DutyCardSection extends StatefulWidget {
  final Map? duty, user;
  final bool noDuty;
  const _DutyCardSection(
      {required this.duty, required this.user, required this.noDuty});
  @override
  State<_DutyCardSection> createState() => _DutyCardSectionState();
}

class _DutyCardSectionState extends State<_DutyCardSection> {
  bool _printing    = false;
  bool _hasMarked   = false; // true once the user has printed this session
 
  Map<String, dynamic> _toAdminShape() {
    final d = widget.duty ?? {};
    final u = widget.user ?? {};
    final sahyogi = (d['allStaff'] ?? []) as List;
    return {
      'name':          u['name']              ?? '',
      'pno':           u['pno']               ?? '',
      'mobile':        u['mobile']            ?? '',
      'rank':          u['rank']              ?? u['user_rank'] ?? '',
      'user_rank':     u['rank']              ?? u['user_rank'] ?? '',
      'isArmed':       u['isArmed']           ?? false,
      'staffThana':    u['thana']             ?? '',
      'thana':         u['thana']             ?? '',
      'district':      u['district']          ?? '',
      'centerName':    d['centerName']        ?? '',
      'centerType':    d['centerType']        ?? '',
      'gpName':        d['gpName']            ?? '',
      'sectorName':    d['sectorName']        ?? '',
      'zoneName':      d['zoneName']          ?? '',
      'superZoneName': d['superZoneName']     ?? '',
      'busNo':         d['busNo']             ?? '',
      'bus_no':        d['busNo']             ?? '',
      'zonalOfficers':  d['zonalOfficers']    ?? [],
      'sectorOfficers': d['sectorOfficers']   ?? [],
      'superOfficers':  d['superOfficers']    ?? [],
      'sahyogi':       sahyogi,
      'allStaff':      sahyogi,
    };
  }
 
  Future<void> _printCard() async {
    setState(() => _printing = true);
    try {
      // ── 1. Generate & print PDF ───────────────────────────────────────────
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      final doc  = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a6.landscape,
        margin:     const pw.EdgeInsets.all(4),
        build:      (_) => buildDutyCardPdf(_toAdminShape(), font, bold),
      ));
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
 
      // ── 2. Mark card as downloaded on the backend ─────────────────────────
      try {
        final token = await AuthService.getToken();
        await ApiService.post(
          '/staff/mark-card-downloaded',
          {},
          token: token,
        );
      } catch (e) {
        // Non-fatal — print succeeded; marking failed silently
        debugPrint('mark-card-downloaded error: $e');
      }
 
      // ── 3. Update local state ─────────────────────────────────────────────
      if (mounted) setState(() => _hasMarked = true);
 
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('प्रिंट त्रुटि: $e'),
          backgroundColor: kError,
          behavior:        SnackBarBehavior.floating,
        ));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    if (widget.noDuty) return const _NoDutyState();
    final d = widget.duty ?? {};
    final u = widget.user ?? {};
 
    return Column(children: [
      // ── Header card ─────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kDark, Color(0xFF5A3E08)],
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.badge_outlined,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ड्यूटी कार्ड',
                  style: TextStyle(
                      color:      Colors.white,
                      fontSize:   16,
                      fontWeight: FontWeight.w800)),
              Text('आधिकारिक चुनाव ड्यूटी कार्ड',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ],
          )),
 
          // ── Print button ───────────────────────────────────────────────
          GestureDetector(
            onTap: _printing ? null : _printCard,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: _printing
                      ? kPrimary.withOpacity(0.6)
                      : kPrimary,
                  borderRadius: BorderRadius.circular(12)),
              child: _printing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.print_outlined,
                          color: Colors.white, size: 15),
                      SizedBox(width: 6),
                      Text('प्रिंट',
                          style: TextStyle(
                              color:      Colors.white,
                              fontSize:   12,
                              fontWeight: FontWeight.w700)),
                    ]),
            ),
          ),
        ]),
      ),
 
      const SizedBox(height: 12),
 
      // ── Downloaded confirmation banner ───────────────────────────────────
      if (_hasMarked)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:  kSuccess.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kSuccess.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: kSuccess, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text(
              'ड्यूटी कार्ड डाउनलोड हो गया ✓',
              style: TextStyle(
                  color:      kSuccess,
                  fontSize:   13,
                  fontWeight: FontWeight.w700),
            )),
          ]),
        ),
 
      // ── Preview card ──────────────────────────────────────────────────────
      _SectionCard(
        icon:  Icons.preview_outlined,
        title: 'कार्ड विवरण',
        child: Column(children: [
          _PreviewRow('नाम',        u['name']),
          _PreviewRow('PNO',        u['pno']),
          _PreviewRow('पद',         rh(u['rank'] ?? u['user_rank'])),
          _PreviewRow('केंद्र',      d['centerName']),
          _PreviewRow('केंद्र प्रकार', ct(d['centerType'])),
          _PreviewRow('बस',
              (d['busNo'] ?? '').toString().isNotEmpty
                  ? 'बस–${d['busNo']}'
                  : null),
          _PreviewRow('सेक्टर',     d['sectorName']),
          _PreviewRow('जोन',        d['zoneName']),
          _PreviewRow('सहयोगी',
              '${(d['allStaff'] as List?)?.length ?? 0} कर्मी'),
        ]),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SECTOR OFFICER — OVERVIEW
// ══════════════════════════════════════════════════════════════════════════════
class _SectorOverviewSection extends StatelessWidget {
  final Map? duty, user;
  const _SectorOverviewSection({required this.duty, required this.user});

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    return Column(children: [
      _HeroCard(user: user, duty: duty, noDuty: false, subtitle: 'सेक्टर अधिकारी'),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.45,
        children: [
          _StatCard(icon: Icons.how_to_vote_outlined, label: 'कुल बूथ',
              value: '${duty!['totalBooths'] ?? 0}', color: kPrimary),
          _StatCard(icon: Icons.groups_outlined, label: 'असाइन स्टाफ',
              value: '${duty!['totalAssigned'] ?? 0}', color: kSuccess),
          _StatCard(icon: Icons.account_balance_outlined, label: 'ग्राम पंचायत',
              value: '${(duty!['gramPanchayats'] as List?)?.length ?? 0}', color: kInfo),
          _StatCard(icon: Icons.map_outlined, label: 'जोन',
              value: v(duty!['zoneName']), color: kAccent),
        ],
      ),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.info_outline_rounded, title: 'सेक्टर विवरण',
        child: Column(children: [
          _InfoTile(Icons.grid_view_outlined, 'सेक्टर', duty!['sectorName']),
          _InfoTile(Icons.home_work_outlined, 'मुख्यालय', duty!['hqAddress']),
          _InfoTile(Icons.layers_outlined, 'जोन', duty!['zoneName']),
          _InfoTile(Icons.public_outlined, 'सुपर जोन', duty!['superZoneName']),
        ]),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SECTOR OFFICER — INFO
// ══════════════════════════════════════════════════════════════════════════════
class _SectorInfoSection extends StatelessWidget {
  final Map? duty;
  const _SectorInfoSection({required this.duty});

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final coOfficers   = (duty!['coOfficers']   as List? ?? []);
    final zonalOfficers = (duty!['zonalOfficers'] as List? ?? []);
    return Column(children: [
      _SectionCard(icon: Icons.grid_view_outlined, title: 'सेक्टर जानकारी',
        child: Column(children: [
          _InfoTile(Icons.grid_view_outlined, 'सेक्टर', duty!['sectorName']),
          _InfoTile(Icons.home_work_outlined, 'HQ पता', duty!['hqAddress']),
          _InfoTile(Icons.map_outlined, 'जोन', duty!['zoneName']),
          _InfoTile(Icons.public_outlined, 'सुपर जोन', duty!['superZoneName']),
        ]),
      ),
      const SizedBox(height: 14),
      if (coOfficers.isNotEmpty)
        _OfficerCard(label: 'सह-सेक्टर अधिकारी', officers: coOfficers),
      if (zonalOfficers.isNotEmpty) ...[
        const SizedBox(height: 12),
        _OfficerCard(label: 'जोनल अधिकारी (वरिष्ठ)', officers: zonalOfficers),
      ],
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SECTOR OFFICER — BOOTH ATTENDANCE
// ══════════════════════════════════════════════════════════════════════════════
class _SectorBoothAttendanceSection extends StatefulWidget {
  final Map? duty;
  final VoidCallback onRefresh;
  const _SectorBoothAttendanceSection({required this.duty, required this.onRefresh});
  @override
  State<_SectorBoothAttendanceSection> createState() => _SectorBoothAttendanceSectionState();
}

class _SectorBoothAttendanceSectionState extends State<_SectorBoothAttendanceSection> {
  final Map<int, bool> _pendingUpdates = {}; // dutyId → attended
  bool _saving = false;
  String _searchQ = '';

  List<Map> get _centers => List<Map>.from(widget.duty?['centers'] ?? []);

  List<Map> get _filteredCenters {
    if (_searchQ.isEmpty) return _centers;
    final q = _searchQ.toLowerCase();
    return _centers.where((c) =>
      (c['name'] ?? '').toString().toLowerCase().contains(q) ||
      (c['gp_name'] ?? '').toString().toLowerCase().contains(q) ||
      (c['thana'] ?? '').toString().toLowerCase().contains(q)
    ).toList();
  }

  void _toggleAttendance(int dutyId, bool current) {
    setState(() => _pendingUpdates[dutyId] = !current);
  }

  bool _getAttended(Map staffRow) {
    final dutyId = staffRow['duty_id'] as int?;
    if (dutyId != null && _pendingUpdates.containsKey(dutyId)) {
      return _pendingUpdates[dutyId]!;
    }
    return staffRow['attended'] == 1 || staffRow['attended'] == true;
  }

  Future<void> _saveAll() async {
    if (_pendingUpdates.isEmpty) return;
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      final updates = _pendingUpdates.entries
          .map((e) => {'dutyId': e.key, 'attended': e.value})
          .toList();
      await ApiService.post('/staff/attendance/bulk',
          {'updates': updates}, token: token);
      _pendingUpdates.clear();
      widget.onRefresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('उपस्थिति सेव हो गई ✓'),
              backgroundColor: kSuccess, behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('त्रुटि: $e'),
              backgroundColor: kError, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.duty == null) return const _NoDutyState();
    final centers = _filteredCenters;

    // Count totals
    int totalStaff = 0, presentStaff = 0;
    for (final c in _centers) {
      for (final s in (c['staff'] as List? ?? [])) {
        totalStaff++;
        if (_getAttended(s as Map)) presentStaff++;
      }
    }

    return Column(children: [
      // Summary header
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kDark, Color(0xFF5A3E08)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.how_to_vote_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('बूथ उपस्थिति',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
            if (_pendingUpdates.isNotEmpty)
              GestureDetector(
                onTap: _saving ? null : _saveAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: kSuccess, borderRadius: BorderRadius.circular(10)),
                  child: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('${_pendingUpdates.length} सेव करें',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _AttendanceStat('कुल स्टाफ', '$totalStaff', kPrimary)),
            const SizedBox(width: 8),
            Expanded(child: _AttendanceStat('उपस्थित', '$presentStaff', kSuccess)),
            const SizedBox(width: 8),
            Expanded(child: _AttendanceStat('अनुपस्थित',
                '${totalStaff - presentStaff}', kError)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),

      // Search
      TextField(
        onChanged: (v) => setState(() => _searchQ = v.trim()),
        style: const TextStyle(color: kDark, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'बूथ/थाना/GP खोजें...',
          hintStyle: const TextStyle(color: kSubtle, fontSize: 12),
          prefixIcon: const Icon(Icons.search, color: kSubtle, size: 18),
          filled: true, fillColor: Colors.white, isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: kPrimary, width: 2)),
        ),
      ),
      const SizedBox(height: 12),

      // Centers list
      ...centers.map((center) => _BoothAttendanceCard(
        center: center,
        getAttended: _getAttended,
        onToggle: _toggleAttendance,
      )),

      if (centers.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('कोई बूथ नहीं मिला',
              style: TextStyle(color: kSubtle, fontSize: 13)))),
    ]);
  }
}

class _AttendanceStat extends StatelessWidget {
  final String label, value; final Color color;
  const _AttendanceStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10)),
    child: Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
    ]),
  );
}

class _BoothAttendanceCard extends StatelessWidget {
  final Map center;
  final bool Function(Map) getAttended;
  final void Function(int, bool) onToggle;
  const _BoothAttendanceCard({required this.center,
      required this.getAttended, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final staff   = (center['staff'] as List? ?? []);
    final type    = '${center['center_type'] ?? 'C'}';
    final tc      = _typeColor(type);
    int present   = staff.where((s) => getAttended(s as Map)).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: tc.withOpacity(0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: tc.withOpacity(0.2))),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: tc, borderRadius: BorderRadius.circular(6)),
              child: Text(type, style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${center['name'] ?? '—'}', style: const TextStyle(
                  color: kDark, fontSize: 13, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${center['gp_name'] ?? ''} • ${center['thana'] ?? ''}',
                  style: const TextStyle(color: kSubtle, fontSize: 10)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: present == staff.length && staff.isNotEmpty
                    ? kSuccess.withOpacity(0.1) : kSubtle.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: present == staff.length && staff.isNotEmpty
                    ? kSuccess.withOpacity(0.3) : kBorder.withOpacity(0.3)),
              ),
              child: Text('$present/${staff.length}',
                  style: TextStyle(
                      color: present == staff.length && staff.isNotEmpty
                          ? kSuccess : kSubtle,
                      fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        // Staff rows
        if (staff.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
              child: Text('कोई स्टाफ असाइन नहीं',
                  style: TextStyle(color: kSubtle, fontSize: 12)))
        else
          ...staff.asMap().entries.map((e) {
            final i = e.key;
            final s = e.value as Map;
            final dutyId   = s['duty_id'] as int?;
            final attended = getAttended(s);
            final armed    = s['is_armed'] == 1 || s['is_armed'] == true;
            return Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                border: i < staff.length - 1
                    ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.3)))
                    : null,
              ),
              child: Row(children: [
                // Avatar
                Container(width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: (armed ? kArmed : kUnarmed).withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: (armed ? kArmed : kUnarmed).withOpacity(0.3))),
                    child: Icon(armed ? Icons.security : Icons.person_outline,
                        size: 16, color: armed ? kArmed : kUnarmed)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s['name'] ?? '—'}', style: const TextStyle(
                      color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
                  Row(children: [
                    Text(rh(s['user_rank']),
                        style: const TextStyle(color: kSubtle, fontSize: 10)),
                    const Text(' • ', style: TextStyle(color: kSubtle, fontSize: 10)),
                    Text('${s['pno'] ?? ''}',
                        style: const TextStyle(color: kSubtle, fontSize: 10)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: (armed ? kArmed : kUnarmed).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(armed ? 'सशस्त्र' : 'निःशस्त्र',
                          style: TextStyle(
                              color: armed ? kArmed : kUnarmed,
                              fontSize: 8, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ])),
                // Attendance toggle
                GestureDetector(
                  onTap: dutyId != null
                      ? () => onToggle(dutyId, attended)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56, height: 30,
                    decoration: BoxDecoration(
                      color: attended ? kSuccess : kError.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                          color: attended ? kSuccess : kError.withOpacity(0.4),
                          width: 1.5),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(attended ? Icons.check : Icons.close,
                          size: 14,
                          color: attended ? Colors.white : kError),
                      const SizedBox(width: 2),
                      Text(attended ? 'हाँ' : 'नहीं',
                          style: TextStyle(
                              color: attended ? Colors.white : kError,
                              fontSize: 10, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
            );
          }),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ZONE OFFICER — OVERVIEW
// ══════════════════════════════════════════════════════════════════════════════
class _ZoneOverviewSection extends StatelessWidget {
  final Map? duty, user;
  const _ZoneOverviewSection({required this.duty, required this.user});

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    return Column(children: [
      _HeroCard(user: user, duty: duty, noDuty: false, subtitle: 'जोनल अधिकारी'),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.45,
        children: [
          _StatCard(icon: Icons.grid_view_outlined, label: 'कुल सेक्टर',
              value: '${duty!['totalSectors'] ?? 0}', color: kPrimary),
          _StatCard(icon: Icons.how_to_vote_outlined, label: 'कुल बूथ',
              value: '${duty!['totalBooths'] ?? 0}', color: kInfo),
          _StatCard(icon: Icons.groups_outlined, label: 'असाइन स्टाफ',
              value: '${duty!['totalAssigned'] ?? 0}', color: kSuccess),
          _StatCard(icon: Icons.public_outlined, label: 'सुपर जोन',
              value: v(duty!['superZoneName']), color: kAccent),
        ],
      ),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.map_outlined, title: 'जोन विवरण',
        child: Column(children: [
          _InfoTile(Icons.map_outlined, 'जोन', duty!['zoneName']),
          _InfoTile(Icons.home_work_outlined, 'मुख्यालय', duty!['hqAddress']),
          _InfoTile(Icons.public_outlined, 'सुपर जोन', duty!['superZoneName']),
        ]),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ZONE OFFICER — INFO
// ══════════════════════════════════════════════════════════════════════════════
class _ZoneInfoSection extends StatelessWidget {
  final Map? duty;
  const _ZoneInfoSection({required this.duty});

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final co    = (duty!['coOfficers']    as List? ?? []);
    final super_ = (duty!['superOfficers'] as List? ?? []);
    return Column(children: [
      _SectionCard(icon: Icons.map_outlined, title: 'जोन विस्तार जानकारी',
        child: Column(children: [
          _InfoTile(Icons.map_outlined, 'जोन', duty!['zoneName']),
          _InfoTile(Icons.home_work_outlined, 'HQ', duty!['hqAddress']),
          _InfoTile(Icons.public_outlined, 'सुपर जोन', duty!['superZoneName']),
          _InfoTile(Icons.grid_view_outlined, 'कुल सेक्टर', '${duty!['totalSectors'] ?? 0}'),
          _InfoTile(Icons.how_to_vote_outlined, 'कुल बूथ', '${duty!['totalBooths'] ?? 0}'),
          _InfoTile(Icons.groups_outlined, 'असाइन स्टाफ', '${duty!['totalAssigned'] ?? 0}'),
        ]),
      ),
      if (co.isNotEmpty) ...[const SizedBox(height: 14), _OfficerCard(label: 'जोनल अधिकारी', officers: co)],
      if (super_.isNotEmpty) ...[const SizedBox(height: 12), _OfficerCard(label: 'क्षेत्र अधिकारी (वरिष्ठ)', officers: super_)],
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ZONE OFFICER — SECTORS LIST
// ══════════════════════════════════════════════════════════════════════════════
class _ZoneSectorsSection extends StatelessWidget {
  final Map? duty;
  const _ZoneSectorsSection({required this.duty});

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final sectors = (duty!['sectors'] as List? ?? []);
    return Column(children: [
      _SectionCard(icon: Icons.grid_view_outlined,
          title: 'सेक्टर (${sectors.length})',
        child: sectors.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('कोई सेक्टर नहीं', style: TextStyle(color: kSubtle))))
            : Column(children: sectors.asMap().entries.map((e) {
                final i = e.key;
                final s = e.value as Map;
                final officers = (s['officers'] as List? ?? []);
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: i < sectors.length - 1
                        ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.4)))
                        : null,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: kPrimary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.grid_view_outlined, color: kPrimary, size: 16)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${s['name'] ?? '—'}', style: const TextStyle(
                            color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
                        Text('${s['gp_count'] ?? 0} GP  •  ${s['center_count'] ?? 0} बूथ  •  ${s['staff_assigned'] ?? 0} स्टाफ',
                            style: const TextStyle(color: kSubtle, fontSize: 11)),
                      ])),
                    ]),
                    if (officers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 4,
                          children: officers.map((o) => _OfficerChip(o as Map)).toList()),
                    ],
                  ]),
                );
              }).toList()),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  KSHETRA — OVERVIEW
// ══════════════════════════════════════════════════════════════════════════════
class _KshetraOverviewSection extends StatelessWidget {
  final Map? duty, user;
  const _KshetraOverviewSection({required this.duty, required this.user});

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    return Column(children: [
      _HeroCard(user: user, duty: duty, noDuty: false, subtitle: 'क्षेत्र अधिकारी'),
      const SizedBox(height: 16),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.45,
        children: [
          _StatCard(icon: Icons.map_outlined, label: 'कुल जोन',
              value: '${duty!['totalZones'] ?? 0}', color: kPrimary),
          _StatCard(icon: Icons.grid_view_outlined, label: 'कुल सेक्टर',
              value: '${duty!['totalSectors'] ?? 0}', color: kInfo),
          _StatCard(icon: Icons.how_to_vote_outlined, label: 'कुल बूथ',
              value: '${duty!['totalBooths'] ?? 0}', color: kSuccess),
          _StatCard(icon: Icons.groups_outlined, label: 'असाइन स्टाफ',
              value: '${duty!['totalAssigned'] ?? 0}', color: kAccent),
        ],
      ),
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.layers_outlined, title: 'क्षेत्र विवरण',
        child: Column(children: [
          _InfoTile(Icons.layers_outlined, 'सुपर जोन', duty!['superZoneName']),
          _InfoTile(Icons.location_city_outlined, 'जिला', duty!['district']),
          _InfoTile(Icons.business_outlined, 'ब्लॉक', duty!['block']),
        ]),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  KSHETRA — INFO
// ══════════════════════════════════════════════════════════════════════════════
class _KshetraInfoSection extends StatelessWidget {
  final Map? duty;
  const _KshetraInfoSection({required this.duty});

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final co = (duty!['coOfficers'] as List? ?? []);
    return Column(children: [
      _SectionCard(icon: Icons.layers_outlined, title: 'क्षेत्र जानकारी',
        child: Column(children: [
          _InfoTile(Icons.layers_outlined, 'सुपर जोन', duty!['superZoneName']),
          _InfoTile(Icons.location_city_outlined, 'जिला', duty!['district']),
          _InfoTile(Icons.business_outlined, 'ब्लॉक', duty!['block']),
          _InfoTile(Icons.map_outlined, 'कुल जोन', '${duty!['totalZones'] ?? 0}'),
          _InfoTile(Icons.grid_view_outlined, 'कुल सेक्टर', '${duty!['totalSectors'] ?? 0}'),
          _InfoTile(Icons.how_to_vote_outlined, 'कुल बूथ', '${duty!['totalBooths'] ?? 0}'),
          _InfoTile(Icons.groups_outlined, 'असाइन स्टाफ', '${duty!['totalAssigned'] ?? 0}'),
        ]),
      ),
      if (co.isNotEmpty) ...[const SizedBox(height: 14), _OfficerCard(label: 'सह-क्षेत्र अधिकारी', officers: co)],
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  KSHETRA — ZONES LIST
// ══════════════════════════════════════════════════════════════════════════════
class _KshetraZonesSection extends StatelessWidget {
  final Map? duty;
  const _KshetraZonesSection({required this.duty});

  @override
  Widget build(BuildContext context) {
    if (duty == null) return const _NoDutyState();
    final zones = (duty!['zones'] as List? ?? []);
    return _SectionCard(
      icon: Icons.map_outlined, title: 'जोन (${zones.length})',
      child: zones.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('कोई जोन नहीं', style: TextStyle(color: kSubtle))))
          : Column(children: zones.asMap().entries.map((e) {
              final i = e.key;
              final z = e.value as Map;
              final officers = (z['officers'] as List? ?? []);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: i < zones.length - 1
                      ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.4)))
                      : null,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: kInfo.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.map_outlined, color: kInfo, size: 16)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${z['name'] ?? '—'}', style: const TextStyle(
                          color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
                      Text('${z['sector_count'] ?? 0} सेक्टर  •  ${z['center_count'] ?? 0} बूथ  •  ${z['staff_assigned'] ?? 0} स्टाफ',
                          style: const TextStyle(color: kSubtle, fontSize: 11)),
                      if ((z['hq_address'] ?? '').toString().isNotEmpty)
                        Text('HQ: ${z['hq_address']}',
                            style: const TextStyle(color: kSubtle, fontSize: 10)),
                    ])),
                  ]),
                  if (officers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4,
                        children: officers.map((o) => _OfficerChip(o as Map)).toList()),
                  ],
                ]),
              );
            }).toList()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  RULES SECTION — for officers to view booth rules
// ══════════════════════════════════════════════════════════════════════════════
class _RulesSection extends StatelessWidget {
  final List rules;
  const _RulesSection({required this.rules});

  @override
  Widget build(BuildContext context) {
    // Group by sensitivity
    final grouped = <String, List<Map>>{};
    for (final r in rules) {
      final s = (r['sensitivity'] ?? '?').toString();
      grouped.putIfAbsent(s, () => []).add(r as Map);
    }

    final order = ['A++', 'A', 'B', 'C'];
    final colors = {
      'A++': const Color(0xFF6C3483),
      'A':   kError,
      'B':   kAccent,
      'C':   kInfo,
    };
    final labels = {
      'A++': 'अत्यति संवेदनशील',
      'A':   'अति संवेदनशील',
      'B':   'संवेदनशील',
      'C':   'सामान्य',
    };

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kDark, Color(0xFF5A3E08)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(children: [
          Icon(Icons.rule_folder_outlined, color: Colors.white, size: 20),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('बूथ स्टाफ मानक', style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            Text('संवेदनशीलता के अनुसार आवश्यक स्टाफ',
                style: TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
        ]),
      ),
      const SizedBox(height: 14),
      if (rules.isEmpty)
        _SectionCard(icon: Icons.info_outline, title: 'मानक',
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('कोई मानक सेट नहीं है',
                  style: TextStyle(color: kSubtle, fontSize: 13)))))
      else
        ...order.where((s) => grouped.containsKey(s)).map((s) {
          final color = colors[s] ?? kPrimary;
          final label = labels[s] ?? s;
          final list  = grouped[s]!;
          final total = list.fold(0, (a, r) => a + ((r['count'] as num?)?.toInt() ?? 0));

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.07),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(bottom: BorderSide(color: color.withOpacity(0.2))),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                    child: Text(s, style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label,
                      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13))),
                  Text('$total कर्मी', style: TextStyle(
                      color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: list.map((r) {
                  final isArmed = r['isArmed'] == true || r['is_armed'] == 1;
                  final count   = (r['count'] as num?)?.toInt() ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: kBg, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBorder.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      Icon(isArmed ? Icons.security : Icons.person_outline,
                          size: 16, color: isArmed ? kArmed : kUnarmed),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(rh(r['rank']),
                            style: const TextStyle(color: kDark, fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(isArmed ? 'सशस्त्र' : 'निःशस्त्र',
                            style: TextStyle(color: isArmed ? kArmed : kUnarmed, fontSize: 10)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: color.withOpacity(0.3))),
                        child: Text('$count', style: TextStyle(
                            color: color, fontSize: 14, fontWeight: FontWeight.w900)),
                      ),
                    ]),
                  );
                }).toList()),
              ),
            ]),
          );
        }),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CHANGE PASSWORD
// ══════════════════════════════════════════════════════════════════════════════
class _ChangePasswordSection extends StatefulWidget {
  const _ChangePasswordSection();
  @override State<_ChangePasswordSection> createState() => _ChangePasswordSectionState();
}

class _ChangePasswordSectionState extends State<_ChangePasswordSection> {
  final _fk = GlobalKey<FormState>();
  final _curCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _saving = false, _done = false;
  bool _showCur = false, _showNew = false, _showConf = false;

  int get _strength {
    final p = _newCtrl.text;
    return (p.length >= 6 ? 1 : 0) + (p.length >= 10 ? 1 : 0) +
        (RegExp(r'[A-Z0-9]').hasMatch(p) ? 1 : 0) +
        (RegExp(r'[^A-Za-z0-9]').hasMatch(p) ? 1 : 0);
  }

  @override
  void dispose() { _curCtrl.dispose(); _newCtrl.dispose(); _confCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_fk.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      await ApiService.post('/staff/change-password', {
        'currentPassword': _curCtrl.text, 'newPassword': _newCtrl.text,
      }, token: token);
      setState(() { _done = true; _curCtrl.clear(); _newCtrl.clear(); _confCtrl.clear(); });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('पासवर्ड सफलतापूर्वक बदल दिया गया'),
          backgroundColor: kSuccess, behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('त्रुटि: $e'),
          backgroundColor: kError, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = [Colors.transparent, Colors.red, Colors.orange, Colors.yellow[700]!, kSuccess];
    final sl = ['', 'बहुत छोटा', 'ठीक है', 'अच्छा', 'बहुत मजबूत'];
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kDark, Color(0xFF5A3E08)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 22)),
          const SizedBox(width: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('पासवर्ड बदलें', style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            Text('अपना लॉगिन पासवर्ड अपडेट करें',
                style: TextStyle(color: Colors.white60, fontSize: 11)),
          ])),
        ]),
      ),
      const SizedBox(height: 14),
      if (_done)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kSuccessBg, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kSuccess.withOpacity(0.3))),
          child: const Row(children: [
            Icon(Icons.verified_outlined, color: kSuccess, size: 16),
            SizedBox(width: 8),
            Text('पासवर्ड सफलतापूर्वक बदल दिया गया!',
                style: TextStyle(color: kSuccess, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      _SectionCard(icon: Icons.key_outlined, title: 'नया पासवर्ड',
          child: Form(key: _fk, child: Column(children: [
            _PwdField(ctrl: _curCtrl, label: 'वर्तमान पासवर्ड *',
                placeholder: 'मौजूदा पासवर्ड', show: _showCur,
                onToggle: () => setState(() => _showCur = !_showCur),
                validator: (vv) => (vv == null || vv.isEmpty) ? 'आवश्यक' : null),
            const SizedBox(height: 12),
            _PwdField(ctrl: _newCtrl, label: 'नया पासवर्ड *',
                placeholder: 'न्यूनतम 6 अक्षर', show: _showNew,
                onToggle: () => setState(() => _showNew = !_showNew),
                onChanged: (_) => setState(() {}),
                validator: (vv) => (vv == null || vv.length < 6) ? 'कम से कम 6 अक्षर' : null),
            if (_newCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: List.generate(4, (i) => Expanded(child: Container(
                  height: 4, margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                      color: i < _strength ? sc[_strength] : const Color(0x40D4A843),
                      borderRadius: BorderRadius.circular(10)))))),
              const SizedBox(height: 4),
              Text(sl[_strength], style: TextStyle(color: sc[_strength], fontSize: 10)),
            ],
            const SizedBox(height: 12),
            _PwdField(ctrl: _confCtrl, label: 'पासवर्ड दोबारा डालें *',
                placeholder: 'पुष्टि करें', show: _showConf,
                onToggle: () => setState(() => _showConf = !_showConf),
                onChanged: (_) => setState(() {}),
                validator: (vv) => vv != _newCtrl.text ? 'पासवर्ड मेल नहीं खाते' : null),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _saving ? null : _submit,
              child: Container(width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: _saving ? kPrimary.withOpacity(0.6) : kPrimary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.35),
                          blurRadius: 10, offset: const Offset(0, 4))]),
                  child: _saving
                      ? const Center(child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.key_rounded, size: 15, color: Colors.white),
                          SizedBox(width: 8),
                          Text('पासवर्ड बदलें', style: TextStyle(
                              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                        ])),
            ),
          ]))),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _HeroCard extends StatelessWidget {
  final Map? user, duty;
  final bool noDuty;
  final String? subtitle;
  const _HeroCard({required this.user, required this.duty,
      required this.noDuty, this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [kDark, Color(0xFF6B4E0A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: kDark.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 48, height: 48,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle, border: Border.all(color: kBorder.withOpacity(0.4))),
            child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 24)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(
                color: Colors.white60, fontSize: 10, letterSpacing: 1.0, fontWeight: FontWeight.w600)),
          Text(user?['name'] ?? '—', style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          Text('PNO: ${user?['pno'] ?? '—'}',
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ])),
      ]),
      const SizedBox(height: 14),
      Container(height: 1, color: Colors.white.withOpacity(0.15)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 8, children: [
        if ((user?['thana'] ?? '').toString().isNotEmpty)
          _HeroBadge(Icons.local_police_outlined, user!['thana']),
        if ((user?['district'] ?? '').toString().isNotEmpty)
          _HeroBadge(Icons.location_city_outlined, user!['district']),
        _HeroBadge(Icons.military_tech_outlined, rh(user?['rank'] ?? user?['user_rank'])),
      ]),
      if (!noDuty && duty != null && duty!['centerName'] != null) ...[
        const SizedBox(height: 12),
        Container(height: 1, color: Colors.white.withOpacity(0.15)),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.how_to_vote_outlined, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Expanded(child: Text('ड्यूटी: ${duty!['centerName'] ?? duty!['sectorName'] ?? duty!['zoneName'] ?? duty!['superZoneName'] ?? '—'}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis)),
        ]),
      ],
    ]),
  );
}

class _HeroBadge extends StatelessWidget {
  final IconData icon; final String label;
  const _HeroBadge(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.white60),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]),
  );
}

class _SectionCard extends StatelessWidget {
  final IconData icon; final String title; final Widget child;
  const _SectionCard({required this.icon, required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorder.withOpacity(0.5)),
      boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: kSurface.withOpacity(0.6),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          border: Border(bottom: BorderSide(color: kBorder.withOpacity(0.4))),
        ),
        child: Row(children: [
          Container(width: 28, height: 28,
              decoration: BoxDecoration(color: kPrimary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: kPrimary, size: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(
              color: kDark, fontSize: 14, fontWeight: FontWeight.w800))),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(16), child: child),
    ]),
  );
}

class _StatCard extends StatelessWidget {
  final IconData icon; final String label, value; final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorder.withOpacity(0.5)),
      boxShadow: [BoxShadow(color: color.withOpacity(0.07), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 32, height: 32,
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: color)),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: kSubtle, fontSize: 10, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: kDark, fontSize: 13, fontWeight: FontWeight.w800),
          overflow: TextOverflow.ellipsis),
    ]),
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon; final String label; final dynamic value;
  const _InfoTile(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final val = (value == null || value.toString().trim().isEmpty) ? null : value.toString();
    if (val == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 30, height: 30,
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 13, color: kPrimary)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kSubtle, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(val, style: const TextStyle(color: kDark, fontSize: 13, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }
}

class _OfficerCard extends StatelessWidget {
  final String label; final List officers;
  const _OfficerCard({required this.label, required this.officers});
  @override
  Widget build(BuildContext context) => _SectionCard(
    icon: Icons.verified_user_outlined, title: label,
    child: Column(children: officers.asMap().entries.map((e) {
      final i = e.key;
      final o = e.value is Map ? e.value as Map : {};
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: i < officers.length - 1
            ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.4))) : null),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: kSurface, shape: BoxShape.circle,
                  border: Border.all(color: kBorder)),
              child: const Icon(Icons.person_outline_rounded, color: kPrimary, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v(o['name']), style: const TextStyle(
                color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
            Text('${rh(o['user_rank'] ?? o['rank'])}  ·  PNO: ${v(o['pno'])}',
                style: const TextStyle(color: kSubtle, fontSize: 10)),
          ])),
          if ((o['mobile'] ?? '').toString().isNotEmpty)
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('tel:${o['mobile']}');
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
              child: Container(width: 34, height: 34,
                  decoration: BoxDecoration(color: kSuccessBg, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.phone_outlined, size: 15, color: kSuccess)),
            ),
        ]),
      );
    }).toList()),
  );
}

class _StaffRow extends StatelessWidget {
  final int index, total; final Map staff; final bool armed;
  const _StaffRow({required this.index, required this.total,
      required this.staff, required this.armed});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(border: index < total - 1
        ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.4))) : null),
    child: Row(children: [
      Container(width: 38, height: 38,
          decoration: BoxDecoration(
              color: (armed ? kArmed : kUnarmed).withOpacity(0.1), shape: BoxShape.circle,
              border: Border.all(color: (armed ? kArmed : kUnarmed).withOpacity(0.3))),
          child: Center(child: Text('${index + 1}',
              style: TextStyle(color: armed ? kArmed : kUnarmed,
                  fontSize: 12, fontWeight: FontWeight.w800)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v(staff['name']), style: const TextStyle(
            color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
        Text('${v(staff['pno'])} · ${v(staff['thana'])}',
            style: const TextStyle(color: kSubtle, fontSize: 11)),
        Row(children: [
          Text(rh(staff['user_rank'] ?? staff['rank']),
              style: const TextStyle(color: kAccent, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: (armed ? kArmed : kUnarmed).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4)),
            child: Text(armed ? 'सशस्त्र' : 'निःशस्त्र',
                style: TextStyle(color: armed ? kArmed : kUnarmed,
                    fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        ]),
      ])),
      if ((staff['mobile'] ?? '').toString().isNotEmpty)
        GestureDetector(
          onTap: () async {
            final uri = Uri.parse('tel:${staff['mobile']}');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          },
          child: Container(width: 36, height: 36,
              decoration: BoxDecoration(color: kSuccessBg, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.phone_outlined, size: 15, color: kSuccess)),
        ),
    ]),
  );
}

class _OfficerChip extends StatelessWidget {
  final Map officer;
  const _OfficerChip(this.officer);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.08), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimary.withOpacity(0.2))),
    child: Text('${officer['name']} (${rh(officer['user_rank'] ?? officer['rank'])})',
        style: const TextStyle(color: kPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

class _NavButton extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _NavButton({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _PreviewRow extends StatelessWidget {
  final String label; final dynamic value;
  const _PreviewRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final display = (value == null || value.toString().trim().isEmpty) ? '—' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(flex: 2, child: Text(label,
            style: const TextStyle(color: kSubtle, fontSize: 12))),
        Expanded(flex: 3, child: Text(display,
            style: const TextStyle(color: kDark, fontSize: 12, fontWeight: FontWeight.w700),
            textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _PwdField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, placeholder;
  final bool show; final VoidCallback onToggle;
  final void Function(String)? onChanged;
  final String? Function(String?)? validator;
  const _PwdField({required this.ctrl, required this.label, required this.placeholder,
      required this.show, required this.onToggle, this.onChanged, this.validator});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: kSubtle, fontSize: 12, fontWeight: FontWeight.w600)),
    const SizedBox(height: 6),
    TextFormField(controller: ctrl, obscureText: !show,
        onChanged: onChanged, validator: validator,
        style: const TextStyle(color: kDark, fontSize: 13),
        decoration: InputDecoration(hintText: placeholder,
          hintStyle: const TextStyle(color: Color(0xFFBBA060), fontSize: 12),
          filled: true, fillColor: kBg,
          suffixIcon: IconButton(
              icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: kSubtle, size: 18), onPressed: onToggle),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kBorder.withOpacity(0.5))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPrimary, width: 2)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kError)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          isDense: true)),
  ]);
}

class _NoDutyState extends StatelessWidget {
  const _NoDutyState();
  @override
  Widget build(BuildContext context) => Center(child: Container(
    margin: const EdgeInsets.only(top: 60),
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))]),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64,
          decoration: BoxDecoration(color: kSurface, shape: BoxShape.circle, border: Border.all(color: kBorder)),
          child: const Icon(Icons.location_off_outlined, color: kPrimary, size: 30)),
      const SizedBox(height: 16),
      const Text('अभी तक ड्यूटी नहीं सौंपी गई',
          style: TextStyle(color: kDark, fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('व्यवस्थापक द्वारा ड्यूटी सौंपे जाने पर यहाँ दिखेगी।',
          style: TextStyle(color: kSubtle, fontSize: 12), textAlign: TextAlign.center),
    ]),
  ));
}

class _ErrorState extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline_rounded, size: 52, color: kError),
      const SizedBox(height: 14),
      const Text('डेटा लोड करने में त्रुटि',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kDark)),
      const SizedBox(height: 8),
      Text(error, style: const TextStyle(color: kSubtle, fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 18),
      GestureDetector(onTap: onRetry, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(12)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('पुनः प्रयास करें',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ]))),
    ]),
  ));
}