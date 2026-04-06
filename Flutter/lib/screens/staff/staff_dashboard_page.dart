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
import '../admin/pages/hierarchy_report_page.dart';

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

// ── Helpers ───────────────────────────────────────────────────────────────────
const _rankMap = {
  'constable': 'आरक्षी', 'head constable': 'मुख्य आरक्षी',
  'si': 'उप निरीक्षक', 'sub inspector': 'उप निरीक्षक',
  'inspector': 'निरीक्षक', 'asi': 'सहायक उप निरीक्षक',
  'assistant sub inspector': 'सहायक उप निरीक्षक',
  'dsp': 'उपाधीक्षक', 'sp': 'पुलिस अधीक्षक',
  'circle officer': 'क्षेत्राधिकारी', 'co': 'क्षेत्राधिकारी',
};
String rh(dynamic val) =>
    _rankMap[(val ?? '').toString().toLowerCase()] ?? val?.toString() ?? '—';
String v(dynamic x) =>
    (x == null || x.toString().trim().isEmpty) ? '—' : x.toString();

const _centerTypeMap = {
  'sensitive': 'संवेदनशील', 'normal': 'सामान्य',
  'critical': 'अति संवेदनशील', 'general': 'सामान्य',
  'a': 'अति संवेदनशील', 'b': 'संवेदनशील', 'c': 'सामान्य',
};
String ct(dynamic x) =>
    _centerTypeMap[(x ?? '').toString().toLowerCase()] ?? x?.toString() ?? '—';

// ══════════════════════════════════════════════════════════════════════════════
class StaffDashboardPage extends StatefulWidget {
  const StaffDashboardPage({super.key});
  @override
  State<StaffDashboardPage> createState() => _StaffDashboardPageState();
}

class _StaffDashboardPageState extends State<StaffDashboardPage>
    with TickerProviderStateMixin {
  int _navIdx = 0;

  static const _navLabels = ['Dashboard', 'Duty', 'Co-Staff', 'Duty Card', 'Password'];
  static const _navHindi  = ['डैशबोर्ड', 'ड्यूटी विवरण', 'सहयोगी', 'ड्यूटी कार्ड', 'पासवर्ड'];
  static const _navIcons  = [
    Icons.dashboard_outlined, Icons.location_on_outlined,
    Icons.groups_outlined, Icons.badge_outlined, Icons.key_outlined,
  ];
  static const _navFilled = [
    Icons.dashboard, Icons.location_on,
    Icons.groups, Icons.badge, Icons.key,
  ];

  Map? _duty, _user;
  bool _loading = true, _noDuty = false;
  String? _error;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token    = await AuthService.getToken();
      final userResp = await ApiService.get('/staff/profile', token: token);
      final userData = userResp['data'];
      final resp     = await ApiService.get('/staff/my-duty', token: token);

      Map? dutyData;
      if (resp is Map) {
        dutyData = resp.containsKey('data')
            ? (resp['data'] is Map ? resp['data'] as Map : null)
            : resp;
      }

      setState(() {
        _user    = userData is Map ? userData : {};
        _duty    = dutyData;
        _noDuty  = dutyData == null ||
            (dutyData['centerName'] == null && dutyData['center_name'] == null);
        _loading = false;
      });
      if (_duty != null) _normalize();
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _normalize() {
    if (_duty == null) return;
    final d = Map<String, dynamic>.from(_duty!);
    d['centerName']     ??= d['center_name'];
    d['centerAddress']  ??= d['center_address'];
    d['centerType']     ??= d['center_type'];
    d['gpName']         ??= d['gp_name'];
    d['gpAddress']      ??= d['gp_address'];
    d['sectorName']     ??= d['sector_name'];
    d['zoneName']       ??= d['zone_name'];
    d['zoneHq']         ??= d['zone_hq'];
    d['superZoneName']  ??= d['super_zone_name'];
    d['assignedBy']     ??= d['assigned_by'];
    d['busNo']          ??= d['bus_no'];
    d['allStaff']       ??= d['all_staff']       ?? [];
    d['sectorOfficers'] ??= d['sector_officers'] ?? [];
    d['zonalOfficers']  ??= d['zonal_officers']  ?? [];
    d['superOfficers']  ??= d['super_officers']  ?? [];
    setState(() => _duty = d);
  }

  void _goTo(int idx) {
    setState(() => _navIdx = idx);
    _fadeCtrl.forward(from: 0);
  }

  // ── Google Maps with proper error dialog ──────────────────────────────────
  Future<void> _openMap() async {
    final lat = _duty?['latitude'];
    final lng = _duty?['longitude'];
    final hasLocation = lat != null &&
        lng != null &&
        lat.toString().trim().isNotEmpty &&
        lng.toString().trim().isNotEmpty &&
        lat.toString() != 'null' &&
        lng.toString() != 'null';

    if (!hasLocation) {
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
    } catch (_) {
      _showNoLocationDialog();
    }
  }

  void _showNoLocationDialog() {
    final assignedBy = (_duty?['assignedBy'] ?? '').toString().trim();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: kError.withOpacity(0.4)),
        ),
        title: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: kError.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.location_off_outlined, color: kError, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('लोकेशन उपलब्ध नहीं',
                style: TextStyle(color: kDark, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'इस मतदान केंद्र की GPS लोकेशन अभी तक डेटाबेस में दर्ज नहीं है।',
            style: TextStyle(color: kDark, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kSurface, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder.withOpacity(0.5)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, color: kPrimary, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                assignedBy.isNotEmpty
                    ? 'कृपया "$assignedBy" (ड्यूटी असाइन करने वाले व्यवस्थापक) से संपर्क करके लोकेशन अपडेट करवाएं।'
                    : 'कृपया अपने व्यवस्थापक (Admin) से संपर्क करके इस केंद्र की लोकेशन डेटाबेस में अपडेट करवाएं।',
                style: const TextStyle(color: kSubtle, fontSize: 11, height: 1.5),
              )),
            ]),
          ),
        ]),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('ठीक है'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: kError, width: 1.5),
        ),
        title: const Row(children: [
          Icon(Icons.logout, color: kError),
          SizedBox(width: 8),
          Text('लॉग आउट', style: TextStyle(color: kError)),
        ]),
        content: const Text('क्या आप लॉग आउट करना चाहते हैं?',
            style: TextStyle(color: kDark)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रद्द करें', style: TextStyle(color: kSubtle)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: kError, foregroundColor: Colors.white),
            child: const Text('लॉग आउट'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AuthService.logout();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: kBg,
        appBar: _buildAppBar(),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : _error != null
                ? _ErrorState(error: _error!, onRetry: _loadData)
                : FadeTransition(opacity: _fadeAnim, child: _buildBody()),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: kDark,
    elevation: 0,
    automaticallyImplyLeading: false,
    title: Row(children: [
      Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
            color: kPrimary, shape: BoxShape.circle, border: Border.all(color: kBorder)),
        child: const Icon(Icons.how_to_vote, color: Colors.white, size: 18),
      ),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_navHindi[_navIdx], style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(_user?['name'] ?? 'Staff Portal',
            style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ]),
    ]),
    actions: [
      Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: kSuccessBg.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kSuccess.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6,
              decoration: const BoxDecoration(color: kSuccess, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          const Text('सक्रिय',
              style: TextStyle(color: kSuccess, fontSize: 9, fontWeight: FontWeight.w700)),
        ]),
      ),
      IconButton(
        icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
        onPressed: _loadData,
      ),
      IconButton(
        icon: const Icon(Icons.logout_rounded, color: Colors.white70),
        onPressed: _confirmLogout,
      ),
    ],
  );

  Widget _buildBody() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Center(child: _buildSection()),
    ),
  );

  Widget _buildSection() {
    switch (_navIdx) {
      case 0: return _OverviewSection(duty: _duty, user: _user, noDuty: _noDuty,
          onGoToDutyCard: () => _goTo(3), onOpenMap: _openMap);
      case 1: return _DutyDetailSection(duty: _duty, noDuty: _noDuty, onOpenMap: _openMap);
      case 2: return _CoStaffSection(duty: _duty, noDuty: _noDuty);
      case 3: return _DutyCardSection(duty: _duty, user: _user, noDuty: _noDuty);
      case 4: return const _ChangePasswordSection();
      default: return const SizedBox();
    }
  }

  Widget _buildBottomNav() => Container(
    decoration: const BoxDecoration(
      color: kSurface, border: Border(top: BorderSide(color: kBorder)),
    ),
    child: SafeArea(
      child: SizedBox(
        height: 65,
        child: Row(
          children: List.generate(5, (i) {
            final sel = _navIdx == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => _goTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: sel ? kBg : Colors.transparent,
                    border: Border(top: BorderSide(
                        color: sel ? kPrimary : Colors.transparent, width: 3)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(sel ? _navFilled[i] : _navIcons[i],
                        color: sel ? kPrimary : kSubtle, size: 22),
                    const SizedBox(height: 3),
                    Text(_navLabels[i], style: TextStyle(
                        fontSize: 9,
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        color: sel ? kPrimary : kSubtle)),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SECTION 0 — OVERVIEW
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
      // Hero card
      Container(
        width: double.infinity, padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kDark, Color(0xFF6B4E0A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: kDark.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12), shape: BoxShape.circle,
                border: Border.all(color: kBorder.withOpacity(0.4)),
              ),
              child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('स्वागत है', style: TextStyle(color: Colors.white54, fontSize: 11,
                  letterSpacing: 1.2, fontWeight: FontWeight.w600)),
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
            _HeroBadge(Icons.local_police_outlined, user?['thana'] ?? '—'),
            _HeroBadge(Icons.location_city_outlined, user?['district'] ?? '—'),
            _HeroBadge(Icons.military_tech_outlined, rh(user?['user_rank'] ?? user?['rank'])),
          ]),
          if (!noDuty) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.how_to_vote_outlined, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              Expanded(child: Text('ड्यूटी: ${duty?['centerName'] ?? '—'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 18),

      if (!noDuty && duty != null) ...[
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.45,
          children: [
            _StatCard(icon: Icons.location_on_outlined, label: 'मतदान केंद्र',
                value: duty?['centerName'] ?? '—', color: kPrimary),
            _StatCard(icon: Icons.directions_bus_outlined, label: 'बस संख्या',
                value: duty?['busNo']?.toString().isNotEmpty == true
                    ? 'बस–${duty!['busNo']}' : '—',
                color: kInfo),
            _StatCard(icon: Icons.map_outlined, label: 'सेक्टर',
                value: duty?['sectorName'] ?? '—', color: kSuccess),
            _StatCard(icon: Icons.groups_outlined, label: 'सहयोगी कर्मी',
                value: '${(duty?['allStaff'] as List?)?.length ?? 0} कर्मी',
                color: const Color(0xFFD84315)),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.info_outline_rounded, title: 'संक्षिप्त विवरण',
          child: Column(children: [
            _InfoTile(Icons.local_police_outlined, 'थाना', duty?['thana']),
            _InfoTile(Icons.account_balance_outlined, 'ग्राम पंचायत', duty?['gpName']),
            _InfoTile(Icons.layers_outlined, 'जोन', duty?['zoneName']),
            _InfoTile(Icons.public_outlined, 'सुपर जोन', duty?['superZoneName']),
            _InfoTile(Icons.category_outlined, 'केंद्र प्रकार', ct(duty?['centerType'])),
          ]),
        ),
        const SizedBox(height: 12),

        // Google Maps navigation button
        GestureDetector(
          onTap: onOpenMap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: kPrimary, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.4),
                  blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('Google Maps पर नेविगेट करें', style: TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Duty card shortcut
        GestureDetector(
          onTap: onGoToDutyCard,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kBorder),
              boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.08),
                  blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Row(children: [
              Container(width: 44, height: 44,
                  decoration: BoxDecoration(
                      color: kPrimary, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.print_outlined, color: Colors.white, size: 20)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ड्यूटी कार्ड प्रिंट करें', style: TextStyle(
                    color: kDark, fontSize: 14, fontWeight: FontWeight.w700)),
                Text('आधिकारिक चुनाव ड्यूटी कार्ड देखें',
                    style: TextStyle(color: kSubtle, fontSize: 11)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: kSubtle),
            ]),
          ),
        ),
      ] else
        const _NoDutyState(),
    ]);
  }
}

class _HeroBadge extends StatelessWidget {
  final IconData icon; final String label;
  const _HeroBadge(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white24),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.white60),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]),
  );
}

class _StatCard extends StatelessWidget {
  final IconData icon; final String label, value; final Color color;
  const _StatCard({required this.icon, required this.label,
      required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorder.withOpacity(0.5)),
      boxShadow: [BoxShadow(
          color: color.withOpacity(0.07), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 32, height: 32,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: color)),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(
          color: kSubtle, fontSize: 10, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: kDark, fontSize: 13, fontWeight: FontWeight.w800),
          overflow: TextOverflow.ellipsis),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SECTION 1 — DUTY DETAILS
// ══════════════════════════════════════════════════════════════════════════════
class _DutyDetailSection extends StatelessWidget {
  final Map? duty; final bool noDuty; final VoidCallback onOpenMap;
  const _DutyDetailSection(
      {required this.duty, required this.noDuty, required this.onOpenMap});

  @override
  Widget build(BuildContext context) {
    if (noDuty) return const _NoDutyState();
    return Column(children: [
      _SectionCard(
        icon: Icons.location_on_outlined, title: 'ड्यूटी स्थान विवरण',
        child: Column(children: [
          _InfoTile(Icons.how_to_vote_outlined, 'मतदान केंद्र', duty?['centerName']),
          _InfoTile(Icons.home_outlined, 'केंद्र पता', duty?['centerAddress']),
          _InfoTile(Icons.category_outlined, 'केंद्र प्रकार', ct(duty?['centerType'])),
          _InfoTile(Icons.local_police_outlined, 'थाना', duty?['thana']),
          _InfoTile(Icons.account_balance_outlined, 'ग्राम पंचायत', duty?['gpName']),
        ]),
      ),
      const SizedBox(height: 14),
      _SectionCard(
        icon: Icons.map_outlined, title: 'प्रशासनिक विवरण',
        child: Column(children: [
          _InfoTile(Icons.map_outlined, 'सेक्टर', duty?['sectorName']),
          _InfoTile(Icons.layers_outlined, 'जोन', duty?['zoneName']),
          _InfoTile(Icons.home_work_outlined, 'जोन मुख्यालय', duty?['zoneHq']),
          _InfoTile(Icons.public_outlined, 'सुपर जोन', duty?['superZoneName']),
          _InfoTile(Icons.directions_bus_outlined, 'बस संख्या',
              duty?['busNo']?.toString().isNotEmpty == true
                  ? 'बस–${duty!['busNo']}' : null),
          _InfoTile(Icons.person_outlined, 'नियुक्त किया', duty?['assignedBy']),
        ]),
      ),
      const SizedBox(height: 14),
      if ((duty?['sectorOfficers'] as List?)?.isNotEmpty == true) ...[
        _OfficerCard(label: 'सेक्टर अधिकारी',
            officers: duty!['sectorOfficers'] as List),
        const SizedBox(height: 12),
      ],
      if ((duty?['zonalOfficers'] as List?)?.isNotEmpty == true) ...[
        _OfficerCard(label: 'जोनल अधिकारी',
            officers: duty!['zonalOfficers'] as List),
        const SizedBox(height: 12),
      ],
      if ((duty?['superOfficers'] as List?)?.isNotEmpty == true) ...[
        _OfficerCard(label: 'क्षेत्र अधिकारी (सुपर जोन)',
            officers: duty!['superOfficers'] as List),
        const SizedBox(height: 14),
      ],
      GestureDetector(
        onTap: onOpenMap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: kPrimary, borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.4),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Google Maps पर नेविगेट करें', style: TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    ]);
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
                  decoration: BoxDecoration(
                      color: kSuccessBg, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.phone_outlined, size: 15, color: kSuccess)),
            ),
        ]),
      );
    }).toList()),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SECTION 2 — CO-STAFF
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
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('कोई सहयोगी कर्मी नहीं मिला',
                  style: TextStyle(color: kSubtle, fontSize: 13))))
          : Column(children: staff.asMap().entries.map((e) {
              final i = e.key;
              final s = e.value is Map ? e.value as Map : {};
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(border: i < staff.length - 1
                    ? Border(bottom: BorderSide(color: kBorder.withOpacity(0.4))) : null),
                child: Row(children: [
                  Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: kSurface, shape: BoxShape.circle,
                          border: Border.all(color: kBorder)),
                      child: Center(child: Text('${i + 1}', style: const TextStyle(
                          color: kPrimary, fontSize: 12, fontWeight: FontWeight.w800)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v(s['name']), style: const TextStyle(
                        color: kDark, fontSize: 13, fontWeight: FontWeight.w700)),
                    Text('${v(s['pno'])} · ${v(s['thana'])}',
                        style: const TextStyle(color: kSubtle, fontSize: 11)),
                    if ((s['user_rank'] ?? s['rank'] ?? '').toString().isNotEmpty)
                      Text(rh(s['user_rank'] ?? s['rank']),
                          style: const TextStyle(color: kAccent, fontSize: 10,
                              fontWeight: FontWeight.w600)),
                  ])),
                  if ((s['mobile'] ?? '').toString().isNotEmpty)
                    GestureDetector(
                      onTap: () async {
                        final uri = Uri.parse('tel:${s['mobile']}');
                        if (await canLaunchUrl(uri)) launchUrl(uri);
                      },
                      child: Container(width: 36, height: 36,
                          decoration: BoxDecoration(
                              color: kSuccessBg, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.phone_outlined, size: 15, color: kSuccess)),
                    ),
                ]),
              );
            }).toList()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SECTION 3 — DUTY CARD  (PDF matches web DutyCardPrint exactly)
// ══════════════════════════════════════════════════════════════════════════════


// ══════════════════════════════════════════════════════════════════════════════
// STAFF DUTY CARD SECTION
// Replace _DutyCardSection, _DutyCardSectionState, _PreviewRow in
// staff_dashboard_page.dart with this code.
//
// Also add this import at top of staff_dashboard_page.dart:
//   import 'duty_card_page.dart'; // for buildDutyCardPdf
// ══════════════════════════════════════════════════════════════════════════════

// NOTE: This file assumes buildDutyCardPdf() is imported from duty_card_page.dart
// It reuses the exact same PDF builder so both pages produce identical cards.

class _DutyCardSection extends StatefulWidget {
  final Map? duty, user;
  final bool noDuty;
  const _DutyCardSection(
      {required this.duty, required this.user, required this.noDuty});
  @override
  State<_DutyCardSection> createState() => _DutyCardSectionState();
}
 
class _DutyCardSectionState extends State<_DutyCardSection> {
  bool _printing = false;
 
  // ── Build the staff-data map in the shape buildDutyCardPdf() expects ───────
  Map<String, dynamic> _toAdminShape() {
    final d = widget.duty ?? {};
    final u = widget.user ?? {};
 
    // allStaff / sahyogi: each item already has user_rank, name, pno, mobile,
    // thana, district — matching what buildDutyCardPdf reads.
    final sahyogi = (d['allStaff'] ?? d['all_staff'] ?? []) as List;
 
    return {
      // ── Primary officer ──────────────────────────────────────────────────
      'name':       u['name']     ?? '',
      'pno':        u['pno']      ?? '',
      'mobile':     u['mobile']   ?? '',
      'rank':       u['rank']     ?? u['user_rank'] ?? '',
      'user_rank':  u['rank']     ?? u['user_rank'] ?? '',
      'staffThana': u['thana']    ?? '',
      'thana':      u['thana']    ?? '',
      'district':   u['district'] ?? d['district'] ?? '',
 
      // ── Center / location ────────────────────────────────────────────────
      'centerName':    d['centerName']    ?? d['center_name']    ?? '',
      'centerType':    d['centerType']    ?? d['center_type']    ?? '',
      'gpName':        d['gpName']        ?? d['gp_name']        ?? '',
      'sectorName':    d['sectorName']    ?? d['sector_name']    ?? '',
      'zoneName':      d['zoneName']      ?? d['zone_name']      ?? '',
      'superZoneName': d['superZoneName'] ?? d['super_zone_name'] ?? '',
      'busNo':         d['busNo']         ?? d['bus_no']         ?? '',
      'bus_no':        d['busNo']         ?? d['bus_no']         ?? '',
 
      // ── Officers (already List<Map>) ─────────────────────────────────────
      // buildDutyCardPdf reads:
      //   zonalOfficers[0]  → zonal magistrate
      //   superOfficers[0]  → zonal police officer
      //   sectorOfficers[0] → sector magistrate
      //   sectorOfficers[1] → sector police officer  (or [0] if only one)
      'zonalOfficers':  d['zonalOfficers']  ?? d['zonal_officers']  ?? [],
      'sectorOfficers': d['sectorOfficers'] ?? d['sector_officers'] ?? [],
      'superOfficers':  d['superOfficers']  ?? d['super_officers']  ?? [],
 
      // ── Sahyogi (co-staff) ───────────────────────────────────────────────
      'sahyogi':   sahyogi,
      'allStaff':  sahyogi,
      'all_staff': sahyogi,
    };
  }
 
  Future<void> _printCard() async {
    setState(() => _printing = true);
    try {
      // Same font loading as admin DutyCardPage._print()
      final font = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
 
      final doc = pw.Document();
      doc.addPage(pw.Page(
        // ✅ A6 landscape — exactly the same as admin
        pageFormat: PdfPageFormat.a6.landscape,
        margin: const pw.EdgeInsets.all(4),
        build: (_) => buildDutyCardPdf(_toAdminShape(), font, bold),
      ));
 
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('प्रिंट त्रुटि: $e'),
            backgroundColor: kError,
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    if (widget.noDuty) return const _NoDutyState();
    final d = widget.duty ?? {};
    final u = widget.user ?? {};
    final allStaff = d['allStaff'] as List? ?? [];
 
    return Column(children: [
      // ── Header banner ──────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kDark, Color(0xFF5A3E08)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: kDark.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.badge_outlined,
                  color: Colors.white, size: 24)),
          const SizedBox(width: 14),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('ड्यूटी कार्ड',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                Text('आधिकारिक चुनाव ड्यूटी कार्ड',
                    style:
                        TextStyle(color: Colors.white60, fontSize: 11)),
              ])),
          // Print button
          GestureDetector(
            onTap: _printing ? null : _printCard,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: _printing
                      ? kPrimary.withOpacity(0.6)
                      : kPrimary,
                  borderRadius: BorderRadius.circular(12)),
              child: _printing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.print_outlined,
                          color: Colors.white, size: 15),
                      SizedBox(width: 6),
                      Text('प्रिंट',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
 
      // ── Preview card ────────────────────────────────────────────────────────
      _SectionCard(
        icon: Icons.preview_outlined,
        title: 'कार्ड में शामिल जानकारी',
        child: Column(children: [
          _PreviewRow('कर्मी का नाम',   u['name']),
          _PreviewRow('पुलिस नं0',      u['pno']),
          _PreviewRow('पद',             rh(u['rank'] ?? u['user_rank'])),
          _PreviewRow('मतदान केंद्र',   d['centerName']),
          _PreviewRow('केंद्र पता',     d['centerAddress']),
          _PreviewRow('केंद्र प्रकार',  ct(d['centerType'])),
          _PreviewRow('बस संख्या',
              (d['busNo'] ?? d['bus_no'])?.toString().isNotEmpty == true
                  ? 'बस–${d['busNo'] ?? d['bus_no']}'
                  : null),
          _PreviewRow('थाना',           u['thana']),
          _PreviewRow('ग्राम पंचायत',  d['gpName']),
          _PreviewRow('सेक्टर',         d['sectorName']),
          _PreviewRow('जोन',            d['zoneName']),
          _PreviewRow('सुपर जोन',       d['superZoneName']),
          _PreviewRow('सहयोगी कर्मी',   '${allStaff.length} कर्मी'),
          _PreviewRow('नियुक्त किया',   d['assignedBy']),
        ]),
      ),
    ]);
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final dynamic value;
  const _PreviewRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final display =
        (value == null || value.toString().trim().isEmpty) ? '—' : value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(color: kSubtle, fontSize: 12))),
        Expanded(
            flex: 3,
            child: Text(display,
                style: const TextStyle(
                    color: kDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.right)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SECTION 4 — CHANGE PASSWORD
// ══════════════════════════════════════════════════════════════════════════════
class _ChangePasswordSection extends StatefulWidget {
  const _ChangePasswordSection();
  @override
  State<_ChangePasswordSection> createState() => _ChangePasswordSectionState();
}

class _ChangePasswordSectionState extends State<_ChangePasswordSection> {
  final _fk       = GlobalKey<FormState>();
  final _curCtrl  = TextEditingController();
  final _newCtrl  = TextEditingController();
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
  void dispose() {
    _curCtrl.dispose(); _newCtrl.dispose(); _confCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_fk.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      await ApiService.post('/staff/change-password', {
        'currentPassword': _curCtrl.text, 'newPassword': _newCtrl.text,
      }, token: token);
      setState(() {
        _done = true;
        _curCtrl.clear(); _newCtrl.clear(); _confCtrl.clear();
      });
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
      Container(padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kDark, Color(0xFF5A3E08)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
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
          ])),
      const SizedBox(height: 14),
      if (_done)
        Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kSuccessBg, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kSuccess.withOpacity(0.3))),
            child: const Row(children: [
              Icon(Icons.verified_outlined, color: kSuccess, size: 16),
              SizedBox(width: 8),
              Text('पासवर्ड सफलतापूर्वक बदल दिया गया!',
                  style: TextStyle(color: kSuccess, fontSize: 13, fontWeight: FontWeight.w600)),
            ])),
      _SectionCard(icon: Icons.key_outlined, title: 'नया पासवर्ड सेट करें',
          child: Form(key: _fk, child: Column(children: [
            _PwdField(ctrl: _curCtrl, label: 'वर्तमान पासवर्ड *',
                placeholder: 'अपना मौजूदा पासवर्ड डालें',
                show: _showCur, onToggle: () => setState(() => _showCur = !_showCur),
                validator: (vv) => (vv == null || vv.isEmpty) ? 'पासवर्ड आवश्यक है' : null),
            const SizedBox(height: 12),
            const Divider(color: Color(0x30AA8844)),
            const SizedBox(height: 12),
            _PwdField(ctrl: _newCtrl, label: 'नया पासवर्ड * (न्यूनतम 6 अक्षर)',
                placeholder: 'नया पासवर्ड डालें',
                show: _showNew, onToggle: () => setState(() => _showNew = !_showNew),
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
            _PwdField(ctrl: _confCtrl, label: 'नया पासवर्ड पुनः डालें *',
                placeholder: 'पासवर्ड की पुष्टि करें',
                show: _showConf, onToggle: () => setState(() => _showConf = !_showConf),
                onChanged: (_) => setState(() {}),
                validator: (vv) => vv != _newCtrl.text ? 'पासवर्ड मेल नहीं खाते' : null),
            if (_confCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(_newCtrl.text == _confCtrl.text
                    ? Icons.check_circle_outline : Icons.cancel_outlined,
                    size: 13,
                    color: _newCtrl.text == _confCtrl.text ? kSuccess : kError),
                const SizedBox(width: 5),
                Text(_newCtrl.text == _confCtrl.text
                    ? 'पासवर्ड मेल खाते हैं' : 'पासवर्ड मेल नहीं खाते',
                    style: TextStyle(
                        color: _newCtrl.text == _confCtrl.text ? kSuccess : kError,
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ],
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
      const SizedBox(height: 14),
      _SectionCard(icon: Icons.shield_outlined, title: 'सुरक्षा सुझाव',
          child: Column(children: [
            'पासवर्ड कम से कम 6 अक्षर का रखें',
            'अक्षर, अंक और विशेष चिह्न मिलाकर उपयोग करें',
            'अपना पासवर्ड किसी के साथ साझा न करें',
            'नियमित रूप से पासवर्ड बदलते रहें',
          ].map((tip) => Padding(padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration: BoxDecoration(
                        color: kPrimary.withOpacity(0.5), shape: BoxShape.circle)),
                Expanded(child: Text(tip, style: const TextStyle(color: kSubtle, fontSize: 12))),
              ]))).toList()),
      ),
    ]);
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          color: kSubtle, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextFormField(controller: ctrl, obscureText: !show,
          onChanged: onChanged, validator: validator,
          style: const TextStyle(color: kDark, fontSize: 13),
          decoration: InputDecoration(hintText: placeholder,
            hintStyle: const TextStyle(color: Color(0xFFBBA060), fontSize: 12),
            filled: true, fillColor: kBg,
            suffixIcon: IconButton(
                icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: kSubtle, size: 18),
                onPressed: onToggle),
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

// ══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════════
class _SectionCard extends StatelessWidget {
  final IconData icon; final String title; final Widget child;
  const _SectionCard({required this.icon, required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorder.withOpacity(0.5)),
      boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.04),
          blurRadius: 10, offset: const Offset(0, 3))],
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
            decoration: BoxDecoration(
                color: kSurface, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 13, color: kPrimary)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kSubtle, fontSize: 10,
              fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(val, style: const TextStyle(
              color: kDark, fontSize: 13, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }
}

class _NoDutyState extends StatelessWidget {
  const _NoDutyState();
  @override
  Widget build(BuildContext context) => Center(child: Container(
    margin: const EdgeInsets.only(top: 60),
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: kBorder.withOpacity(0.5)),
      boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.05),
          blurRadius: 16, offset: const Offset(0, 4))],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64,
          decoration: BoxDecoration(color: kSurface, shape: BoxShape.circle,
              border: Border.all(color: kBorder)),
          child: const Icon(Icons.location_off_outlined, color: kPrimary, size: 30)),
      const SizedBox(height: 16),
      const Text('अभी तक ड्यूटी नहीं सौंपी गई', style: TextStyle(
          color: kDark, fontSize: 16, fontWeight: FontWeight.w800)),
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
      const Text('डेटा लोड करने में त्रुटि', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, color: kDark)),
      const SizedBox(height: 8),
      Text(error, style: const TextStyle(color: kSubtle, fontSize: 12),
          textAlign: TextAlign.center),
      const SizedBox(height: 18),
      GestureDetector(onTap: onRetry, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(12)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('पुनः प्रयास करें', style: TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ]))),
    ]),
  ));
}