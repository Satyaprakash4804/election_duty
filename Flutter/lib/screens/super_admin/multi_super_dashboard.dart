import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import 'super_dashboard.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MULTI-DISTRICT SUPER ADMIN DASHBOARD
//  ─────────────────────────────────────
//  Landing page for users with role = MULTI_SUPER_ADMIN.
//
//  Shows:
//    • Header with the user's name + count of assigned districts.
//    • A UP-map banner (decorative).
//    • A responsive grid listing ALL 75 UP districts; assigned ones are
//      vivid + tappable, the rest are dimmed and disabled.
//    • Each assigned card shows election status (active / finalized / none).
//
//  On tap → sets `ApiService.activeDistrict` and pushes the normal
//  `SuperDashboard` which re-uses every existing /api/super/* route.
// ─────────────────────────────────────────────────────────────────────────────

const _kBg       = Color(0xFFFDF6E3);
const _kSurface  = Color(0xFFF5E6C8);
const _kPrimary  = Color(0xFF8B6914);
const _kAccent   = Color(0xFFB8860B);
const _kDark     = Color(0xFF4A3000);
const _kSubtle   = Color(0xFFAA8844);
const _kBorder   = Color(0xFFD4A843);
const _kError    = Color(0xFFC0392B);
const _kSuccess  = Color(0xFF2E7D32);
const _kInfo     = Color(0xFF1565C0);
const _kWarning  = Color(0xFFE65100);
const _kDisabled = Color(0xFFD8CFB8);

// Full UP district list (Hindi) — must match backend / master dashboard.
const List<String> _kUpDistricts = [
  'आगरा','आज़मगढ़','बिजनौर','इटावा','अलीगढ़','बागपत','बदायूं','फर्रुखाबाद',
  'अंबेडकर नगर','बहराइच','बुलंदशहर','फतेहपुर','अमेठी','बलिया','चंदौली','फिरोजाबाद',
  'अमरोहा','बलरामपुर','चित्रकूट','गौतम बुद्ध नगर','औरैया','बांदा','देवरिया','गाज़ियाबाद',
  'अयोध्या','बाराबंकी','एटा','गाज़ीपुर','गोंडा','जालौन','कासगंज','लखनऊ',
  'गोरखपुर','जौनपुर','कौशांबी','महाराजगंज','हमीरपुर','झांसी','कुशीनगर','महोबा',
  'हापुड़','कन्नौज','लखीमपुर खीरी','मैनपुरी','हरदोई','कानपुर देहात','ललितपुर','मथुरा',
  'हाथरस','कानपुर नगर','मऊ','पीलीभीत','संभल','सोनभद्र','मेरठ','प्रतापगढ़',
  'संतकबीर नगर','सुल्तानपुर','मिर्जापुर','प्रयागराज',
  'भदोही (संत रविदास नगर)','उन्नाव',
  'मुरादाबाद','रायबरेली','शाहजहाँपुर','वाराणसी','मुजफ्फरनगर','रामपुर',
  'शामली','सहारनपुर','श्रावस्ती','सिद्धार्थनगर','सीतापुर',
];

// ─────────────────────────────────────────────────────────────────────────────
//  MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _DistrictStatus {
  final String district;
  final String status;           // active / finalized / auto_final / archived / none
  final String electionName;
  final String electionDate;
  final int    adminCount;
  final int    superAdminCount;

  _DistrictStatus({
    required this.district,
    required this.status,
    required this.electionName,
    required this.electionDate,
    required this.adminCount,
    required this.superAdminCount,
  });

  factory _DistrictStatus.fromJson(Map<String, dynamic> j) => _DistrictStatus(
    district:        j['district']        ?? '',
    status:          j['status']          ?? 'none',
    electionName:    j['electionName']    ?? '',
    electionDate:    j['electionDate']    ?? '',
    adminCount:      j['adminCount']      ?? 0,
    superAdminCount: j['superAdminCount'] ?? 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  DASHBOARD
// ─────────────────────────────────────────────────────────────────────────────
class MultiSuperDashboard extends StatefulWidget {
  const MultiSuperDashboard({super.key});

  @override
  State<MultiSuperDashboard> createState() => _MultiSuperDashboardState();
}

class _MultiSuperDashboardState extends State<MultiSuperDashboard> {
  String _userName = '';
  String _userUsername = '';
  List<_DistrictStatus> _assigned = [];
  bool _loading = true;
  String? _error;

  // Search filter
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  // Show / hide unassigned (default: show all but disabled)
  bool _onlyAssigned = false;

  @override
  void initState() {
    super.initState();
    // Make sure no stale district header lingers from a previous session
    ApiService.activeDistrict = null;
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error   = null;
    });
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/multi-super/my-districts', token: token);
      final d     = res['data'] as Map<String, dynamic>? ?? {};
      final list  = d['districts'] as List? ?? [];
      final user  = d['user'] as Map<String, dynamic>? ?? {};
      setState(() {
        _assigned = list
            .map((e) => _DistrictStatus.fromJson(e as Map<String, dynamic>))
            .toList();
        _userName     = user['name']     ?? '';
        _userUsername = user['username'] ?? '';
      });
    } catch (e) {
      setState(() => _error = 'जिले लोड नहीं हो सके: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDistrict(String district) {
    // Set the global district context — every /api/super/* call from here
    // will carry `X-Active-District: <district>`.
    ApiService.activeDistrict = district;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SuperDashboard()),
    ).then((_) {
      // When user comes back to the picker, clear the active district.
      ApiService.activeDistrict = null;
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ───────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── TOP BAR ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    final assignedCount = _assigned.length;
    return Container(
      color: const Color(0xFF1A0A00),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.public, color: Colors.white, size: 12),
              SizedBox(width: 4),
              Text(
                'MULTI SUPER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName.isEmpty ? 'सुपर एडमिन (बहु-जनपद)' : _userName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kBorder,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$assignedCount जनपद नियुक्त',
                  style: const TextStyle(color: Colors.white60, fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _fetch,
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
            tooltip: 'रिफ्रेश',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            onPressed: () async {
              await AuthService.logout();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
            icon: const Icon(Icons.exit_to_app, color: Colors.white70, size: 20),
            tooltip: 'लॉगआउट',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ── BODY ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _kPrimary),
            SizedBox(height: 12),
            Text('जनपद लोड हो रहे हैं…',
                style: TextStyle(color: _kSubtle, fontSize: 12)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: _kError, size: 40),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: _kError, fontSize: 13)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _fetch,
                icon: const Icon(Icons.refresh),
                label: const Text('पुनः प्रयास'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetch,
      color: _kPrimary,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildMapBanner()),
          SliverToBoxAdapter(child: _buildStatusSummary()),
          SliverToBoxAdapter(child: _buildSearchBar()),
          _buildDistrictGrid(),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ],
      ),
    );
  }

  // ── MAP BANNER ─────────────────────────────────────────────────────────────
  Widget _buildMapBanner() {
    final assignedList = _assigned.map((e) => e.district).join('  •  ');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0A00), Color(0xFF3D1A00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title strip
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.map_outlined, color: _kBorder, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'उत्तर प्रदेश — आपके नियुक्त जनपद',
                  style: TextStyle(
                    color: _kBorder,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kPrimary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_assigned.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Map area — uses CustomPaint placeholder. If you add an asset image
          // to pubspec.yaml (e.g. assets/up_map.png), swap the Container child
          // with `Image.asset('assets/up_map.png', fit: BoxFit.contain)`.
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            height: 170,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder.withOpacity(0.25)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size.infinite,
                    painter: _UpStatePainter(),
                  ),
                  // Optional: swap with asset map if available
                  // Positioned.fill(
                  //   child: Image.asset('assets/up_map.png',
                  //       fit: BoxFit.contain, opacity:
                  //       const AlwaysStoppedAnimation(0.85)),
                  // ),
                  Positioned(
                    left: 12, bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'उत्तर प्रदेश (75 जनपद)',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (assignedList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Text(
                assignedList,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11.5, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }

  // ── STATUS SUMMARY CHIPS ───────────────────────────────────────────────────
  Widget _buildStatusSummary() {
    int active = 0, finalizedAny = 0, none = 0;
    for (final d in _assigned) {
      if (d.status == 'active') active++;
      else if (d.status == 'finalized' || d.status == 'auto_final') finalizedAny++;
      else if (d.status == 'none' || d.status == 'archived') none++;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _summaryChip('सक्रिय', '$active', _kSuccess, Icons.how_to_vote),
          const SizedBox(width: 8),
          _summaryChip('समाप्त', '$finalizedAny', _kWarning, Icons.task_alt),
          const SizedBox(width: 8),
          _summaryChip('कॉन्फ़िग नहीं', '$none', _kSubtle, Icons.hourglass_empty),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w900)),
                  Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _kSubtle, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SEARCH BAR / TOGGLE ────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'जनपद खोजें…',
                hintStyle: const TextStyle(color: _kSubtle, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: _kSubtle, size: 18),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _kBorder.withOpacity(0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _kBorder.withOpacity(0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kPrimary, width: 1.5),
                ),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _onlyAssigned = !_onlyAssigned),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: _onlyAssigned ? _kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _onlyAssigned ? _kPrimary : _kBorder.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _onlyAssigned ? Icons.check_box : Icons.filter_list,
                    size: 15,
                    color: _onlyAssigned ? Colors.white : _kSubtle,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'केवल नियुक्त',
                    style: TextStyle(
                      color: _onlyAssigned ? Colors.white : _kDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── DISTRICT GRID ──────────────────────────────────────────────────────────
  Widget _buildDistrictGrid() {
    final assignedMap = {for (final s in _assigned) s.district: s};

    // Build the list to render
    List<String> sourceList;
    if (_onlyAssigned) {
      sourceList = _assigned.map((s) => s.district).toList();
    } else {
      // All UP districts, with assigned ones first
      final assignedSet = assignedMap.keys.toSet();
      sourceList = [..._kUpDistricts]
        ..sort((a, b) {
          final aA = assignedSet.contains(a);
          final bA = assignedSet.contains(b);
          if (aA == bA) return a.compareTo(b);
          return aA ? -1 : 1;
        });
    }

    // Apply search
    final filtered = _search.isEmpty
        ? sourceList
        : sourceList.where((d) => d.toLowerCase().contains(_search)).toList();

    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.search_off, color: _kBorder, size: 36),
                const SizedBox(height: 8),
                Text(
                  _onlyAssigned && _assigned.isEmpty
                      ? 'आपको कोई जनपद नियुक्त नहीं किया गया है'
                      : 'कोई जनपद नहीं मिला',
                  style: const TextStyle(color: _kSubtle, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      sliver: SliverLayoutBuilder(
        builder: (ctx, constraints) {
          final w = constraints.crossAxisExtent;
          final cols = w >= 1024 ? 5 : w >= 720 ? 4 : w >= 480 ? 3 : 2;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.05,
            ),
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final d        = filtered[i];
              final status   = assignedMap[d];
              final assigned = status != null;
              return _DistrictCard(
                district: d,
                status:   status,
                onTap:    assigned ? () => _openDistrict(d) : null,
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DISTRICT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _DistrictCard extends StatelessWidget {
  final String district;
  final _DistrictStatus? status;
  final VoidCallback? onTap;

  const _DistrictCard({
    required this.district,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final assigned = onTap != null && status != null;

    // Status color
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (status?.status) {
      case 'active':
        statusColor = _kSuccess; statusLabel = 'सक्रिय'; statusIcon = Icons.how_to_vote;
        break;
      case 'finalized':
        statusColor = _kWarning; statusLabel = 'समाप्त'; statusIcon = Icons.task_alt;
        break;
      case 'auto_final':
        statusColor = _kError;   statusLabel = 'स्वतः समाप्त'; statusIcon = Icons.timelapse;
        break;
      case 'archived':
        statusColor = _kSubtle;  statusLabel = 'इतिहास'; statusIcon = Icons.archive_outlined;
        break;
      default:
        statusColor = _kInfo;    statusLabel = 'कॉन्फ़िग नहीं'; statusIcon = Icons.hourglass_empty;
    }

    return Opacity(
      opacity: assigned ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: assigned ? Colors.white : _kDisabled.withOpacity(0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: assigned
                    ? statusColor.withOpacity(0.55)
                    : _kBorder.withOpacity(0.4),
                width: assigned ? 1.4 : 1,
              ),
              boxShadow: assigned
                  ? [
                      BoxShadow(
                        color: statusColor.withOpacity(0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row — district icon + lock if disabled
                Row(
                  children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: (assigned ? statusColor : _kSubtle)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        assigned
                            ? Icons.location_city_outlined
                            : Icons.lock_outline,
                        size: 14,
                        color: assigned ? statusColor : _kSubtle,
                      ),
                    ),
                    const Spacer(),
                    if (assigned)
                      Icon(Icons.arrow_forward_ios,
                          size: 11, color: _kSubtle),
                  ],
                ),
                const SizedBox(height: 8),
                // District name
                Text(
                  district,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: assigned ? _kDark : _kSubtle,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const Spacer(),
                // Status chip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: (assigned ? statusColor : _kSubtle).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (assigned ? statusColor : _kSubtle)
                          .withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        assigned ? statusIcon : Icons.block,
                        size: 10,
                        color: assigned ? statusColor : _kSubtle,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          assigned ? statusLabel : 'अनधिकृत',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: assigned ? statusColor : _kSubtle,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (assigned && status!.adminCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${status!.adminCount} एडमिन',
                    style: const TextStyle(color: _kSubtle, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DECORATIVE UP-STATE PAINTER (placeholder background for the map banner)
//  This is intentionally stylised rather than geographically accurate —
//  it provides visual context without claiming pixel-perfect precision.
//  Swap in an asset image of the UP map in pubspec.yaml for a real map.
// ─────────────────────────────────────────────────────────────────────────────
class _UpStatePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kBorder.withOpacity(0.35)
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = _kBorder.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // Rough silhouette of UP (purely decorative)
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.35)
      ..quadraticBezierTo(w * 0.05, h * 0.18, w * 0.25, h * 0.10)
      ..quadraticBezierTo(w * 0.42, h * 0.05, w * 0.55, h * 0.15)
      ..lineTo(w * 0.70, h * 0.12)
      ..quadraticBezierTo(w * 0.88, h * 0.18, w * 0.92, h * 0.32)
      ..lineTo(w * 0.95, h * 0.50)
      ..quadraticBezierTo(w * 0.85, h * 0.70, w * 0.70, h * 0.78)
      ..lineTo(w * 0.55, h * 0.90)
      ..quadraticBezierTo(w * 0.35, h * 0.92, w * 0.22, h * 0.82)
      ..lineTo(w * 0.12, h * 0.65)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, stroke);

    // Dotted internal grid (district boundaries hint)
    final dot = Paint()
      ..color = _kBorder.withOpacity(0.35)
      ..strokeWidth = 0.8;
    for (double y = h * 0.18; y < h * 0.85; y += 14) {
      for (double x = w * 0.12; x < w * 0.9; x += 18) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
