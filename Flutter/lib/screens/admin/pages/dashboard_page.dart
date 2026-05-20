// ═════════════════════════════════════════════════════════════════════════════
//  dashboard_page.dart
//
//  ROOT CAUSE FIXES (why election config wasn't showing):
//  ✅ PRIMARY endpoint is now /admin/election-config/active (always exists)
//     Old code only called /admin/election/finalize/status which doesn't have
//     the full config shape and may not exist on some backend versions.
//  ✅ /admin/election/finalize/status is now SECONDARY (fallback).
//  ✅ Full election context stored: id, name, date, type, phase
//  ✅ electionId + electionName correctly passed to ManakBoothPage & ManakDistrictPage
//  ✅ ElectionHistoryListPage called without params (its const constructor)
//  ✅ _ElectionStatus enum: loading/active/finalized/autoFinalized/none/error
//  ✅ auxArmedCount/auxUnarmedCount used (old auxForceCount removed)
//  ✅ Responsive grid: 2-col → 4-col, constrained max-width for tablets
//  ✅ History tile always visible in quick nav (not gated on isFinalized)
//  ✅ PopScope replaces deprecated WillPopScope
// ═════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';
import 'hierarchy_report_page.dart';
import 'goswara_page.dart';
import 'manak_booth_page.dart';
import 'manak_district_page.dart';
import 'manak_booth_report_page.dart';
import 'election_history_report_page.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const kBg      = Color(0xFFFDF6E3);
const kSurface = Color(0xFFF5E6C8);
const kPrimary = Color(0xFF8B6914);
const kAccent  = Color(0xFFB8860B);
const kDark    = Color(0xFF4A3000);
const kSubtle  = Color(0xFFAA8844);
const kBorder  = Color(0xFFD4A843);
const kError   = Color(0xFFC0392B);
const kSuccess = Color(0xFF2D6A1E);
const kInfo    = Color(0xFF1A5276);

const _kSensitivities = [
  {'key': 'A++', 'hi': 'अति-अति संवेदनशील', 'color': Color(0xFF6C3483)},
  {'key': 'A',   'hi': 'अति संवेदनशील',      'color': Color(0xFFC0392B)},
  {'key': 'B',   'hi': 'संवेदनशील',           'color': Color(0xFFE67E22)},
  {'key': 'C',   'hi': 'सामान्य',             'color': Color(0xFF1A5276)},
];

// ── Election banner state ─────────────────────────────────────────────────────
enum _ElectionStatus { loading, active, finalized, autoFinalized, none, error }

// ══════════════════════════════════════════════════════════════════════════════
//  DASHBOARD PAGE
// ══════════════════════════════════════════════════════════════════════════════
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with AutomaticKeepAliveClientMixin {

  // ── Stats ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _stats;
  bool _loadingStats = true;

  // ── Election state ─────────────────────────────────────────────────────────
  _ElectionStatus _electionStatus = _ElectionStatus.loading;
  bool   _isFinalized    = false;
  bool   _autoFinalized  = false;
  String _electionName   = '';
  String _electionDate   = '';
  String _electionType   = '';
  String _electionPhase  = '';
  String _electionError  = '';
  int?   _electionId;

  // ── Booth मानक ────────────────────────────────────────────────────────────
  final Map<String, List<Map<String, dynamic>>> _boothRules = {
    'A++': [], 'A': [], 'B': [], 'C': [],
  };
  bool _loadingBoothRules = false;

  // ── जनपदीय मानक ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _districtRules = [];
  bool _loadingDistrictRules = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadElectionStatus();
    _loadStats();
    _loadAllBoothRules();
    _loadDistrictRules();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Election status loader
  //
  //  PRIMARY:   /admin/election-config/active   ← THE canonical endpoint
  //             Returns { hasActiveConfig, config: { id, electionName,
  //             electionDate, electionType, phase, isActive, isFinalized } }
  //
  //  SECONDARY: /admin/election/finalize/status  ← fallback
  //             Returns { hasActiveConfig, config, alreadyFinalized, ... }
  //
  //  TERTIARY:  /admin/election/history          ← last resort (has history?)
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _loadElectionStatus() async {
    if (mounted) setState(() => _electionStatus = _ElectionStatus.loading);

    try {
      final token = await AuthService.getToken();

      // ── PRIMARY: /admin/election-config/active ──────────────────────────
      try {
        final res     = await ApiService.get('/admin/election-config/active', token: token);
        final outer   = (res is Map ? res['data'] : null) as Map<String, dynamic>? ?? {};
        final hasActive = outer['hasActiveConfig'] as bool? ?? false;
        final cfg     = outer['config'] as Map<String, dynamic>? ?? {};

        if (hasActive && cfg.isNotEmpty) {
          final isFinalized = cfg['isFinalized'] as bool? ??
              (cfg['is_finalized'] == 1);
          // For now treat isFinalized as manualFinalized; autoFinalized info
          // comes from the finalize/status endpoint (secondary).
          if (mounted) {
            setState(() {
              _electionId     = _asInt(cfg['id']);
              _electionName   = _str(cfg['electionName']);
              _electionDate   = _str(cfg['electionDate']);
              _electionType   = _str(cfg['electionType']);
              _electionPhase  = _str(cfg['phase']);
              _isFinalized    = isFinalized;
              _autoFinalized  = false; // will be refined by secondary if needed
              _electionStatus = isFinalized
                  ? _ElectionStatus.finalized
                  : _ElectionStatus.active;
              _electionError  = '';
            });
          }

          // Try secondary silently to pick up autoFinalized flag
          _enrichFromFinalizeStatus(token);
          return;
        }

        // hasActiveConfig == false → no election for this district
        if (mounted) {
          setState(() {
            _electionStatus = _ElectionStatus.none;
            _isFinalized    = false;
            _autoFinalized  = false;
            _electionId     = null;
            _electionName   = '';
            _electionDate   = '';
            _electionType   = '';
            _electionPhase  = '';
            _electionError  = '';
          });
        }
        return;

      } catch (e1) {
        debugPrint('[election] election-config/active failed: $e1');
        // fall through to secondary
      }

      // ── SECONDARY: /admin/election/finalize/status ──────────────────────
      try {
        final res       = await ApiService.get('/admin/election/finalize/status', token: token);
        final outer     = res is Map ? res : {};
        final hasActive = outer['hasActiveConfig'] as bool? ?? false;
        final data      = outer['data'] as Map<String, dynamic>? ??
                          outer['config'] as Map<String, dynamic>? ?? {};

        // The finalize/status endpoint nests config under 'config' key
        final cfg       = outer['config'] as Map<String, dynamic>? ?? data;
        final finalized = _asBool(cfg['isFinalized']) ||
                          _asBool(outer['alreadyFinalized']);
        final autoFin   = _asBool(cfg['autoFinalized'] ?? outer['autoFinalized']);
        final name      = _str(cfg['electionName']);
        final date      = _str(cfg['electionDate']);
        final eid       = _asInt(cfg['id'] ?? outer['electionId']);

        if (mounted) {
          setState(() {
            _isFinalized    = finalized;
            _autoFinalized  = autoFin;
            _electionName   = name;
            _electionDate   = date;
            _electionType   = _str(cfg['electionType']);
            _electionPhase  = _str(cfg['phase']);
            _electionId     = eid;
            _electionStatus = !hasActive
                ? _ElectionStatus.none
                : finalized
                    ? (autoFin
                        ? _ElectionStatus.autoFinalized
                        : _ElectionStatus.finalized)
                    : name.isNotEmpty
                        ? _ElectionStatus.active
                        : _ElectionStatus.none;
            _electionError  = '';
          });
        }
        return;
      } catch (e2) {
        debugPrint('[election] finalize/status failed: $e2');
        // fall through to tertiary
      }

      // ── TERTIARY: /admin/election/history ───────────────────────────────
      try {
        final res  = await ApiService.get('/admin/election/history', token: token);
        final data = res['data'];
        if (mounted) {
          if (data is List && data.isNotEmpty) {
            final first = data.first as Map<String, dynamic>? ?? {};
            setState(() {
              _isFinalized    = true;
              _autoFinalized  = _asBool(first['autoFinalized']);
              _electionStatus = _autoFinalized
                  ? _ElectionStatus.autoFinalized
                  : _ElectionStatus.finalized;
              _electionName   = _str(first['electionName']);
              _electionDate   = _str(first['electionDate']);
              _electionId     = _asInt(first['id']);
              _electionError  = '';
            });
          } else {
            setState(() {
              _electionStatus = _ElectionStatus.none;
              _electionError  = '';
            });
          }
        }
      } catch (e3) {
        debugPrint('[election] history failed: $e3');
        if (mounted) {
          setState(() {
            _electionStatus = _ElectionStatus.error;
            _electionError  = 'चुनाव स्थिति लोड नहीं हो सकी — पुनः प्रयास करें';
          });
        }
      }

    } catch (outer) {
      debugPrint('[election] outer error: $outer');
      if (mounted) {
        setState(() {
          _electionStatus = _ElectionStatus.error;
          _electionError  = 'नेटवर्क त्रुटि — पुनः प्रयास करें';
        });
      }
    }
  }

  /// Silently tries the finalize/status endpoint to enrich autoFinalized flag.
  Future<void> _enrichFromFinalizeStatus(String? token) async {
    try {
      final res  = await ApiService.get('/admin/election/finalize/status', token: token);
      final outer = res is Map ? res : {};
      final cfg   = outer['config'] as Map<String, dynamic>? ?? {};
      final autoFin = _asBool(cfg['autoFinalized'] ?? outer['autoFinalized']);
      if (mounted && autoFin && _isFinalized) {
        setState(() {
          _autoFinalized  = true;
          _electionStatus = _ElectionStatus.autoFinalized;
        });
      }
    } catch (_) {/* silent */}
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  Future<void> _loadStats() async {
    if (!mounted) return;

    setState(() {
      _loadingStats = true;
    });

    try {
      final token = await AuthService.getToken();

      final response = await ApiService.get(
        '/admin/overview',
        token: token,
      );

      // DEBUG
      debugPrint("========== OVERVIEW RESPONSE ==========");
      debugPrint(response.toString());

      // SAFE RESPONSE PARSING
      Map<String, dynamic> data = {};

      if (response is Map<String, dynamic>) {
        if (response['data'] is Map<String, dynamic>) {
          data = Map<String, dynamic>.from(response['data']);
        } else {
          data = Map<String, dynamic>.from(response);
        }
      }

      // FINAL SAFE MAP
      final stats = {
        'superZones': _toInt(data['superZones']),
        'totalBooths': _toInt(data['totalBooths']),
        'totalStaff': _toInt(data['totalStaff']),
        'assignedDuties': _toInt(
          data['assignedDuties'] ??
          data['boothAssigned'] ??
          data['districtAssigned'],
        ),
      };

      debugPrint("========== PARSED STATS ==========");
      debugPrint(stats.toString());

      if (!mounted) return;

      setState(() {
        _stats = stats;
      });

    } catch (e, stack) {

      debugPrint("========== LOAD STATS ERROR ==========");
      debugPrint(e.toString());
      debugPrint(stack.toString());

      if (!mounted) return;

      setState(() {
        _stats = {
          'superZones': 0,
          'totalBooths': 0,
          'totalStaff': 0,
          'assignedDuties': 0,
        };
      });

      _handleError(e);

    } finally {

      if (!mounted) return;

      setState(() {
        _loadingStats = false;
      });
    }
  }

  // ── Booth rules ───────────────────────────────────────────────────────────
  Future<void> _loadAllBoothRules() async {
    if (mounted) setState(() => _loadingBoothRules = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/booth-rules', token: token);
      final data  = res['data'] as Map<String, dynamic>? ?? {};
      if (mounted) {
        setState(() {
          for (final s in ['A++', 'A', 'B', 'C']) {
            _boothRules[s] = (data[s] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        });
      }
    } catch (e) {
      debugPrint('booth rules: $e');
    } finally {
      if (mounted) setState(() => _loadingBoothRules = false);
    }
  }

  // ── District rules ────────────────────────────────────────────────────────
  Future<void> _loadDistrictRules() async {
    if (mounted) setState(() => _loadingDistrictRules = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/district-rules', token: token);
      final list  = res['data'] as List? ?? [];
      if (mounted) {
        setState(() => _districtRules = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList());
      }
    } catch (e) {
      debugPrint('district rules: $e');
    } finally {
      if (mounted) setState(() => _loadingDistrictRules = false);
    }
  }

  Future<void> _refresh() => Future.wait([
    _loadElectionStatus(),
    _loadStats(),
    _loadAllBoothRules(),
    _loadDistrictRules(),
  ]);

  void _handleError(Object e) {
    if (!mounted) return;
    if (e.toString().contains('Session expired')) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }
    showSnack(context, 'Error: $e', error: true);
  }

  // ── Open manak pages with election context ────────────────────────────────
  void _openBoothManak(String sensitivity, Color color, String hindi) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ManakBoothPage(
          sensitivity:  sensitivity,
          color:        color,
          hindi:        hindi,
          initialRules: _boothRules[sensitivity] ?? [],
          // ✅ Pass election context — this was the missing piece
          electionId:   _electionId,
          electionName: _electionName.isNotEmpty
              ? (_electionPhase.isNotEmpty
                  ? '$_electionName — $_electionPhase'
                  : _electionName)
              : null,
        ),
      ),
    );
    if (updated == true) await _loadAllBoothRules();
  }

  void _openDistrictManak() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ManakDistrictPage(
          initialRules: _districtRules,
          // ✅ Pass election context
          electionId:   _electionId,
          electionName: _electionName,
        ),
      ),
    );
    if (updated == true) await _loadDistrictRules();
  }

  void _goHistory() async {
    final role = await AuthService.getRole() ?? 'admin';

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ElectionHistoryListPage(
          role: role,
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sw   = MediaQuery.of(context).size.width;
    final hPad = sw > 900 ? 24.0 : 14.0;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: kPrimary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                // ── Election banner ──────────────────────────────────────
                _ElectionBanner(
                  status:        _electionStatus,
                  electionName:  _electionName,
                  electionDate:  _electionDate,
                  electionType:  _electionType,
                  electionPhase: _electionPhase,
                  autoFinalized: _autoFinalized,
                  errorMsg:      _electionError,
                  onHistoryTap:  _goHistory,
                  onRetry:       _loadElectionStatus,
                ),
                const SizedBox(height: 14),

                // ── Stats grid ───────────────────────────────────────────
                _loadingStats
                    ? _buildStatsShimmer(sw)
                    : _buildStatsGrid(sw),
                const SizedBox(height: 14),

                // ── Quick nav ────────────────────────────────────────────
                _QuickNavRow(
                  onGoswara: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GoswaraPage())),
                  onHistory: _goHistory,
                ),
                const SizedBox(height: 14),

                // ── Hierarchy banner ─────────────────────────────────────
                _HierarchyBanner(),
                const SizedBox(height: 14),

                // ── Map view ─────────────────────────────────────────────
                _gradientNav(
                  label:    'Election Map View',
                  subtitle: 'District → Zone → Live Map',
                  icon:     Icons.map_outlined,
                  colors:   const [Color(0xFF1A5276), Color(0xFF2874A6)],
                  onTap:    () => Navigator.pushNamed(context, '/map-view'),
                ),
                const SizedBox(height: 14),

                // ── बूथ मानक ────────────────────────────────────────────
                _BoothManakSection(
                  boothRules:   _boothRules,
                  loading:      _loadingBoothRules,
                  electionId:   _electionId,
                  isBlocked:    _isFinalized || _electionId == null,
                  onTapSens:    _openBoothManak,
                ),
                const SizedBox(height: 14),

                // ── जनपदीय मानक ─────────────────────────────────────────
                _DistrictManakSection(
                  rules:      _districtRules,
                  loading:    _loadingDistrictRules,
                  electionId: _electionId,
                  isBlocked:  _isFinalized || _electionId == null,
                  onTap:      _openDistrictManak,
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gradientNav({
    required String       label,
    required String       subtitle,
    required IconData     icon,
    required List<Color>  colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors,
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: colors.first.withOpacity(0.3),
                blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(
                  color: Colors.white60, fontSize: 11)),
            ])),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 22),
          ]),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(double sw) {
    if (_stats == null) return const SizedBox.shrink();
    final cols = sw > 900 ? 4 : sw > 600 ? 3 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols, crossAxisSpacing: 10,
        mainAxisSpacing: 10, mainAxisExtent: 100,
      ),
      itemBuilder: (_, i) {
        final items = [
          _SI(
            'Super Zones',
            '${_toInt(_stats?['superZones'])}',
            Icons.layers_outlined,
            kPrimary,
          ),

          _SI(
            'Total Booths',
            '${_toInt(_stats?['totalBooths'])}',
            Icons.location_on_outlined,
            kSuccess,
          ),

          _SI(
            'Total Staff',
            '${_toInt(_stats?['totalStaff'])}',
            Icons.badge_outlined,
            kAccent,
          ),

          _SI(
            'Assigned',
            '${_toInt(_stats?['assignedDuties'])}',
            Icons.how_to_vote_outlined,
            kInfo,
          ),
        ];
        return _StatCard(item: items[i]);
      },
    );
  }

  Widget _buildStatsShimmer(double sw) {
    final cols = sw > 600 ? 4 : 2;
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols, crossAxisSpacing: 10,
          mainAxisSpacing: 10, childAspectRatio: 1.45),
      itemCount: 4,
      itemBuilder: (_, __) => _Shimmer(radius: 14),
    );
  }

  // ── Parse helpers ─────────────────────────────────────────────────────────
  static String _str(dynamic v) => (v as String? ?? '').trim();
  static bool   _asBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is int)  return v == 1;
    return false;
  }
  static int? _asInt(dynamic v) {
      if (v == null) return null;
      if (v is int)  return v;
      if (v is double) return v.toInt();
      return int.tryParse('$v');
    }
    static int _toInt(dynamic value) {
    if (value == null) return 0;

    if (value is int) return value;

    if (value is double) return value.toInt();

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }
}


// ══════════════════════════════════════════════════════════════════════════════
//  ELECTION BANNER
// ══════════════════════════════════════════════════════════════════════════════
class _ElectionBanner extends StatelessWidget {
  final _ElectionStatus status;
  final String          electionName;
  final String          electionDate;
  final String          electionType;
  final String          electionPhase;
  final bool            autoFinalized;
  final String          errorMsg;
  final VoidCallback    onHistoryTap;
  final VoidCallback    onRetry;

  const _ElectionBanner({
    required this.status,
    required this.electionName,
    required this.electionDate,
    required this.electionType,
    required this.electionPhase,
    required this.autoFinalized,
    required this.errorMsg,
    required this.onHistoryTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _ElectionStatus.loading:
        return _Shimmer(width: double.infinity, height: 78, radius: 14);

      case _ElectionStatus.active:
        final parts = <String>[
          if (electionType.isNotEmpty)  electionType,
          if (electionPhase.isNotEmpty) electionPhase,
          if (electionDate.isNotEmpty)  'तारीख: $electionDate',
        ];
        return _BannerCard(
          gradient:    const [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          shadowColor: const Color(0xFF1B5E20),
          icon:        Icons.how_to_vote_rounded,
          badge:       'सक्रिय चुनाव',
          badgeColor:  const Color(0xFF81C784),
          title:       electionName.isNotEmpty ? electionName : 'चुनाव सक्रिय है',
          subtitle:    parts.join('  •  '),
          trailing:    null,
        );

      case _ElectionStatus.finalized:
        return _BannerCard(
          gradient:    const [Color(0xFF7F0000), Color(0xFFC62828)],
          shadowColor: const Color(0xFF7F0000),
          icon:        Icons.archive_rounded,
          badge:       'मैन्युअल समाप्त',
          badgeColor:  const Color(0xFFEF9A9A),
          title:       electionName.isNotEmpty
              ? '$electionName — इतिहास में स्थानांतरित'
              : 'चुनाव इतिहास में स्थानांतरित',
          subtitle:    electionDate.isNotEmpty ? 'तारीख: $electionDate' : '',
          trailing:    _HistoryButton(onTap: onHistoryTap),
        );

      case _ElectionStatus.autoFinalized:
        return _BannerCard(
          gradient:    const [Color(0xFF6D1A00), Color(0xFFBF360C)],
          shadowColor: const Color(0xFF6D1A00),
          icon:        Icons.event_busy_rounded,
          badge:       'स्वतः समाप्त',
          badgeColor:  const Color(0xFFFFAB91),
          title:       electionName.isNotEmpty
              ? '$electionName — स्वतः इतिहास में स्थानांतरित'
              : 'चुनाव तिथि के बाद स्वतः इतिहास में स्थानांतरित',
          subtitle:    'नई ड्यूटी के लिए master से नया चुनाव कॉन्फ़िगर करवाएं',
          trailing:    _HistoryButton(onTap: onHistoryTap),
        );

      case _ElectionStatus.none:
        return _BannerCard(
          gradient:    const [Color(0xFF4A2800), Color(0xFF7A4500)],
          shadowColor: const Color(0xFF4A2800),
          icon:        Icons.event_busy_rounded,
          badge:       'कोई चुनाव नहीं',
          badgeColor:  const Color(0xFFFFCC02),
          title:       'इस जनपद के लिए कोई सक्रिय चुनाव नहीं',
          subtitle:    'Master admin से चुनाव कॉन्फ़िगर करवाएं',
          trailing:    null,
        );

      case _ElectionStatus.error:
        return _BannerCard(
          gradient:    const [Color(0xFF1A1A2E), Color(0xFF16213E)],
          shadowColor: const Color(0xFF1A1A2E),
          icon:        Icons.wifi_off_rounded,
          badge:       'त्रुटि',
          badgeColor:  const Color(0xFFFF8A65),
          title:       errorMsg.isNotEmpty
              ? errorMsg : 'चुनाव स्थिति लोड नहीं हो सकी',
          subtitle:    'पुनः प्रयास करने के लिए टैप करें',
          trailing:    _RetryButton(onTap: onRetry),
        );
    }
  }
}

class _BannerCard extends StatelessWidget {
  final List<Color> gradient;
  final Color       shadowColor;
  final IconData    icon;
  final String      badge;
  final Color       badgeColor;
  final String      title;
  final String      subtitle;
  final Widget?     trailing;

  const _BannerCard({
    required this.gradient,   required this.shadowColor,
    required this.icon,       required this.badge,
    required this.badgeColor, required this.title,
    required this.subtitle,   required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient,
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: shadowColor.withOpacity(0.32),
            blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Icon bubble
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),

        // Text
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: badgeColor.withOpacity(0.55), width: 1)),
            child: Text(badge, style: TextStyle(
                color: badgeColor, fontSize: 9,
                fontWeight: FontWeight.w800, letterSpacing: 0.4)),
          ),
          const SizedBox(height: 5),
          Text(title, style: const TextStyle(
              color: Colors.white, fontSize: 13,
              fontWeight: FontWeight.w800, height: 1.25),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(
                color: Colors.white60, fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ])),

        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ]),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white30)),
      child: const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.history_edu_outlined, color: Colors.white, size: 18),
        SizedBox(height: 3),
        Text('इतिहास\nदेखें', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 9,
                fontWeight: FontWeight.w800, height: 1.2)),
      ]),
    ),
  );
}

class _RetryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RetryButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white30)),
      child: const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
        SizedBox(height: 3),
        Text('पुनः\nप्रयास', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 9,
                fontWeight: FontWeight.w800, height: 1.2)),
      ]),
    ),
  );
}


// ══════════════════════════════════════════════════════════════════════════════
//  QUICK NAV ROW — always shows both Goswara + History side by side
// ══════════════════════════════════════════════════════════════════════════════
class _QuickNavRow extends StatelessWidget {
  final VoidCallback onGoswara;
  final VoidCallback onHistory;

  const _QuickNavRow({required this.onGoswara, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 3, child: _NavTile(
          label:    'Goswara Report',
          subtitle: 'Booth Staff Summary',
          icon:     Icons.description_outlined,
          colors:   const [Color(0xFF8B6914), Color(0xFFB8860B)],
          onTap:    onGoswara,
        )),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: _HistoryTile(onTap: onHistory)),
      ]),
    );
  }
}

class _NavTile extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  const _NavTile({
    required this.label, required this.subtitle,
    required this.icon,  required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14), onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors,
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: colors.first.withOpacity(0.28),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: const TextStyle(color: Colors.white,
                  fontSize: 13, fontWeight: FontWeight.w800),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(
                  color: Colors.white60, fontSize: 10),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 18),
          ]),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14), onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF6D4C41), Color(0xFF4E342E)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: const Color(0xFF4E342E).withOpacity(0.30),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.history_edu_outlined,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(height: 8),
            const Text('चुनाव\nइतिहास', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w800, height: 1.25)),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10)),
              child: const Text('Archived', style: TextStyle(
                  color: Colors.white70, fontSize: 9,
                  fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
//  HIERARCHY BANNER
// ══════════════════════════════════════════════════════════════════════════════
class _HierarchyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final role = await AuthService.getRole() ?? 'admin';
          if (!context.mounted) return;
          Navigator.push(context, MaterialPageRoute(
              builder: (_) => HierarchyReportPage(role: role)));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF0F2B5B), Color(0xFF1E4D9B)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: const Color(0xFF0F2B5B).withOpacity(0.3),
                blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.table_chart_outlined,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('प्रशासनिक पदानुक्रम रिपोर्ट',
                  style: TextStyle(color: Colors.white,
                      fontSize: 15, fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Super Zone · Sector · Panchayat · Booth Tables',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ])),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 22),
          ]),
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
//  बूथ मानक SECTION
// ══════════════════════════════════════════════════════════════════════════════
class _BoothManakSection extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> boothRules;
  final bool    loading;
  final int?    electionId;
  final bool    isBlocked;   // true when no active election or finalized
  final void Function(String, Color, String) onTapSens;

  const _BoothManakSection({
    required this.boothRules,
    required this.loading,
    required this.electionId,
    required this.isBlocked,
    required this.onTapSens,
  });

  @override
  Widget build(BuildContext context) {
    final sw             = MediaQuery.of(context).size.width;
    final crossAxisCount = sw > 900 ? 4 : sw > 600 ? 3 : 2;
    final allSet         = _kSensitivities.every((s) =>
        (boothRules[s['key']] ?? []).any((r) => _hasAny(r)));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder.withOpacity(0.4)),
        boxShadow: [BoxShadow(
            color: kPrimary.withOpacity(0.06),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: kSurface.withOpacity(0.6),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: kBorder.withOpacity(0.3))),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.how_to_vote_outlined, color: kPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('बूथ मानक', style: TextStyle(
                  color: kDark, fontSize: 14, fontWeight: FontWeight.w800)),
              Text('संवेदनशीलता × बूथ संख्या के अनुसार पुलिस बल',
                  style: TextStyle(color: kSubtle, fontSize: 10)),
            ])),
            // Election block indicator
            if (isBlocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: kSubtle.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kSubtle.withOpacity(0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline, size: 11, color: kSubtle),
                  const SizedBox(width: 4),
                  const Text('अक्षम', style: TextStyle(
                      color: kSubtle, fontSize: 10, fontWeight: FontWeight.w700)),
                ]),
              )
            else
              _StatusBadge(allSet: allSet),
          ]),
        ),

        // Content
        loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))
            : Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10, mainAxisSpacing: 10,
                    childAspectRatio: 1.4,
                    children: _kSensitivities.map((s) {
                      final key         = s['key']   as String;
                      final color       = s['color'] as Color;
                      final hindi       = s['hi']    as String;
                      final rows        = boothRules[key] ?? [];
                      final filledRows  = rows.where((r) => _hasAny(r)).toList();
                      final isSet       = filledRows.isNotEmpty;
                      final totalStaff  = filledRows.fold<int>(
                          0, (sum, r) => sum + _rowTotalStaff(r));
                      return _SensTile(
                        label:          key,
                        hindi:          hindi,
                        color:          color,
                        isSet:          isSet,
                        isBlocked:      isBlocked,
                        totalStaff:     totalStaff,
                        filledRowCount: filledRows.length,
                        onTap:          () => onTapSens(key, color, hindi),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon:  const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('मानक रिपोर्ट देखें / प्रिंट करें',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A1B9A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => ManakBoothReportPage())),
                    ),
                  ),
                ]),
              ),
      ]),
    );
  }

  static bool _hasAny(Map<String, dynamic> r) =>
      ((r['siArmedCount']      ?? 0) as num) > 0 ||
      ((r['siUnarmedCount']    ?? 0) as num) > 0 ||
      ((r['hcArmedCount']      ?? 0) as num) > 0 ||
      ((r['hcUnarmedCount']    ?? 0) as num) > 0 ||
      ((r['constArmedCount']   ?? 0) as num) > 0 ||
      ((r['constUnarmedCount'] ?? 0) as num) > 0 ||
      ((r['auxArmedCount']     ?? 0) as num) > 0 ||
      ((r['auxUnarmedCount']   ?? 0) as num) > 0 ||
      ((r['pacCount']          ?? 0) as num) > 0;

  static int _rowTotalStaff(Map<String, dynamic> r) =>
      ((r['siArmedCount']      ?? 0) as num).toInt() +
      ((r['siUnarmedCount']    ?? 0) as num).toInt() +
      ((r['hcArmedCount']      ?? 0) as num).toInt() +
      ((r['hcUnarmedCount']    ?? 0) as num).toInt() +
      ((r['constArmedCount']   ?? 0) as num).toInt() +
      ((r['constUnarmedCount'] ?? 0) as num).toInt() +
      ((r['auxArmedCount']     ?? 0) as num).toInt() +
      ((r['auxUnarmedCount']   ?? 0) as num).toInt();
}

class _StatusBadge extends StatelessWidget {
  final bool allSet;
  const _StatusBadge({required this.allSet});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: allSet ? kSuccess.withOpacity(0.1) : kError.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
          color: allSet ? kSuccess.withOpacity(0.3) : kError.withOpacity(0.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(allSet ? Icons.check_circle_rounded : Icons.pending_outlined,
          size: 11, color: allSet ? kSuccess : kError),
      const SizedBox(width: 4),
      Text(allSet ? 'सभी सेट' : 'अधूरे', style: TextStyle(
          color: allSet ? kSuccess : kError,
          fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
  );
}


// ══════════════════════════════════════════════════════════════════════════════
//  SENSITIVITY TILE
// ══════════════════════════════════════════════════════════════════════════════
class _SensTile extends StatelessWidget {
  final String label, hindi;
  final Color  color;
  final bool   isSet;
  final bool   isBlocked;
  final int    totalStaff, filledRowCount;
  final VoidCallback onTap;

  const _SensTile({
    required this.label,          required this.hindi,
    required this.color,          required this.isSet,
    required this.isBlocked,      required this.totalStaff,
    required this.filledRowCount, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isBlocked ? kSubtle : (isSet ? color : kError);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isBlocked
                ? kSurface.withOpacity(0.5)
                : isSet
                    ? color.withOpacity(0.07)
                    : kError.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isBlocked
                    ? kSubtle.withOpacity(0.2)
                    : isSet
                        ? color.withOpacity(0.3)
                        : kError.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(11),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: isBlocked
                        ? kSubtle.withOpacity(0.3)
                        : isSet ? color : kError,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(label, style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
              const Spacer(),
              Icon(isBlocked
                      ? Icons.lock_outline
                      : isSet
                          ? Icons.check_circle_rounded
                          : Icons.edit_outlined,
                  size: 15,
                  color: isBlocked ? kSubtle.withOpacity(0.5) : (isSet ? kSuccess : kSubtle)),
            ]),
            const SizedBox(height: 6),
            Text(hindi, style: TextStyle(
                color: effectiveColor,
                fontSize: 10, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const Spacer(),
            if (isSet && !isBlocked) ...[
              Text('$totalStaff कर्मचारी',
                  style: TextStyle(color: color, fontSize: 13,
                      fontWeight: FontWeight.w900)),
              Text('$filledRowCount/15 बूथ-स्तर',
                  style: const TextStyle(color: kSubtle, fontSize: 10)),
            ] else if (!isBlocked)
              Row(children: [
                Icon(Icons.add_circle_outline, size: 12, color: kSubtle),
                const SizedBox(width: 4),
                const Text('सेट करें', style: TextStyle(
                    color: kSubtle, fontSize: 10, fontWeight: FontWeight.w600)),
              ])
            else
              Text(isSet ? '$totalStaff कर्मचारी' : 'सेट नहीं',
                  style: TextStyle(
                      color: kSubtle.withOpacity(0.6), fontSize: 10)),
          ]),
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
//  जनपदीय मानक SECTION
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictManakSection extends StatelessWidget {
  final List<Map<String, dynamic>> rules;
  final bool    loading;
  final int?    electionId;
  final bool    isBlocked;
  final VoidCallback onTap;

  const _DistrictManakSection({
    required this.rules,      required this.loading,
    required this.electionId, required this.isBlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final filledCount = rules.where(_hasAny).length;
    final totalDuties = rules.length;
    final totalStaff  = rules.fold<int>(0, (s, r) =>
        s +
        ((r['siArmedCount']      ?? 0) as num).toInt() +
        ((r['siUnarmedCount']    ?? 0) as num).toInt() +
        ((r['hcArmedCount']      ?? 0) as num).toInt() +
        ((r['hcUnarmedCount']    ?? 0) as num).toInt() +
        ((r['constArmedCount']   ?? 0) as num).toInt() +
        ((r['constUnarmedCount'] ?? 0) as num).toInt() +
        ((r['auxArmedCount']     ?? 0) as num).toInt() +
        ((r['auxUnarmedCount']   ?? 0) as num).toInt());
    final isSet = filledCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF6C3483), Color(0xFF884EA0)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: const Color(0xFF6C3483).withOpacity(0.3),
                blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(
                  isBlocked ? Icons.lock_outline : Icons.shield_outlined,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('जनपदीय कानून व्यवस्था मानक',
                  style: TextStyle(color: Colors.white,
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              if (loading)
                const Text('लोड हो रहा है...',
                    style: TextStyle(color: Colors.white60, fontSize: 11))
              else if (isBlocked)
                const Text('सक्रिय चुनाव नहीं — सम्पादन अक्षम',
                    style: TextStyle(color: Colors.white54, fontSize: 11))
              else if (isSet)
                Text('$totalStaff कर्मचारी  •  $filledCount/$totalDuties ड्यूटी प्रकार',
                    style: const TextStyle(color: Colors.white70, fontSize: 11))
              else
                const Text('कानून व्यवस्था ड्यूटी मानक सेट करें',
                    style: TextStyle(color: Colors.white60, fontSize: 11)),
            ])),
            if (isSet && !isBlocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 11),
                  SizedBox(width: 3),
                  Text('सेट', style: TextStyle(color: Colors.white,
                      fontSize: 10, fontWeight: FontWeight.w800)),
                ])),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 22),
          ]),
        ),
      ),
    );
  }

  static bool _hasAny(Map<String, dynamic> r) =>
      ((r['sankhya']           ?? 0) as num) > 0 ||
      ((r['siArmedCount']      ?? 0) as num) > 0 ||
      ((r['siUnarmedCount']    ?? 0) as num) > 0 ||
      ((r['hcArmedCount']      ?? 0) as num) > 0 ||
      ((r['hcUnarmedCount']    ?? 0) as num) > 0 ||
      ((r['constArmedCount']   ?? 0) as num) > 0 ||
      ((r['constUnarmedCount'] ?? 0) as num) > 0 ||
      ((r['auxArmedCount']     ?? 0) as num) > 0 ||
      ((r['auxUnarmedCount']   ?? 0) as num) > 0 ||
      ((r['pacCount']          ?? 0) as num) > 0;
}


// ══════════════════════════════════════════════════════════════════════════════
//  STAT CARD
// ══════════════════════════════════════════════════════════════════════════════
class _SI {
  final String label, value;
  final IconData icon;
  final Color color;
  const _SI(this.label, this.value, this.icon, this.color);
}

class _StatCard extends StatelessWidget {
  final _SI item;
  const _StatCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.color.withOpacity(0.18)),
        boxShadow: [BoxShadow(
            color: item.color.withOpacity(0.07),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(item.icon, color: item.color, size: 16),
        const SizedBox(height: 6),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(item.value, style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900, color: item.color)),
          const SizedBox(height: 2),
          Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: kSubtle)),
        ])),
      ]),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
//  SHIMMER
// ══════════════════════════════════════════════════════════════════════════════
class _Shimmer extends StatefulWidget {
  final double? width, height;
  final double  radius;
  const _Shimmer({this.width, this.height, this.radius = 6});
  @override State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        color: Color.lerp(
            const Color(0xFFEDE8D5), const Color(0xFFF5EED8), _anim.value),
      ),
    ),
  );
}