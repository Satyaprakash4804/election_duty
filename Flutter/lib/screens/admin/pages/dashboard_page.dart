import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';
import 'hierarchy_report_page.dart';
import 'goswara_page.dart';

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

// ── All ranks (matches image + armed variants) ────────────────────────────────
const _kRanks = [
  {'en': 'ASP',              'hi': 'अपर पुलिस अधीक्षक',           'armVariant': false},
  {'en': 'DSP',              'hi': 'पुलिस उपाधीक्षक',             'armVariant': false},
  {'en': 'Inspector',        'hi': 'निरीक्षक',                     'armVariant': false},
  {'en': 'Inspector_Arms',   'hi': 'निरीक्षक (आर्म्स पुलिस)',      'armVariant': true},
  {'en': 'SI',               'hi': 'उप निरीक्षक',                  'armVariant': false},
  {'en': 'SI_Arms',          'hi': 'उप निरीक्षक (आर्म्स पुलिस)',   'armVariant': true},
  {'en': 'Head Constable',   'hi': 'मुख्य आरक्षी',                 'armVariant': false},
  {'en': 'Head Constable_Arms',          'hi': 'मुख्य आरक्षी (आर्म्स पुलिस)', 'armVariant': true},
  {'en': 'Constable',        'hi': 'आरक्षी',                       'armVariant': false},
  {'en': 'Constable_Arms',   'hi': 'आरक्षी (आर्म्स पुलिस)',        'armVariant': true},
];

const _kSensitivities = [
  {'key': 'A++', 'hi': 'अति-अति संवेदनशील', 'color': Color(0xFF6C3483)},
  {'key': 'A',   'hi': 'अति संवेदनशील',      'color': Color(0xFFC0392B)},
  {'key': 'B',   'hi': 'संवेदनशील',           'color': Color(0xFFE67E22)},
  {'key': 'C',   'hi': 'सामान्य',             'color': Color(0xFF1A5276)},
];

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

  Map<String, dynamic>? _stats;
  bool _loadingStats = true;

  // Rules: sensitivity → { rankKey → count }
  // rankKey examples: 'SI' (unarmed), 'SI_Arms' (armed)
  final Map<String, Map<String, int>> _rules = {
    'A++': {}, 'A': {}, 'B': {}, 'C': {},
  };
  bool _loadingRules = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadAllRules();
  }

  // ── Load overview stats ───────────────────────────────────────────────────
  Future<void> _loadStats() async {
    if (mounted) setState(() => _loadingStats = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/overview', token: token);
      if (mounted) setState(() => _stats = res['data'] ?? res);
    } catch (e) {
      _handleError(e);
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  // ── Load rules for ALL 4 sensitivities from DB ────────────────────────────
  // This is the authoritative load — always reads from server.
  Future<void> _loadAllRules() async {
    if (mounted) setState(() => _loadingRules = true);
    try {
      final token = await AuthService.getToken();
      await Future.wait(['A++', 'A', 'B', 'C'].map((s) async {
        try {
          final res = await ApiService.get(
            '/admin/rules?sensitivity=${Uri.encodeComponent(s)}',
            token: token,
          );

          // API returns: { "data": [ {"rank":"SI","isArmed":true,"count":2}, ... ] }
          // or directly: [ {...}, ... ]
          final dynamic raw = res['data'] ?? res;
          final List<dynamic> list = raw is List ? raw : [];

          // Build rankKey map:
          // unarmed SI  → key = 'SI'
          // armed   SI  → key = 'SI_Arms'
          // This matches _kRanks 'en' keys exactly.
          final Map<String, int> rankMap = {};
          for (final r in list) {
            final rank    = (r['rank'] ?? '').toString().trim();
            final isArmed = r['isArmed'] == true || r['is_armed'] == 1;
            final count   = ((r['count'] ?? r['required_count'] ?? 0) as num).toInt();
            if (rank.isEmpty || count <= 0) continue;

            // For armed variants, append '_Arms' to match _kRanks key
            final key = isArmed ? '${rank}_Arms' : rank;
            rankMap[key] = count;
          }

          if (mounted) setState(() => _rules[s] = rankMap);
        } catch (e) {
          debugPrint('Rules load failed for $s: $e');
        }
      }));
    } catch (e) {
      _handleError(e);
    } finally {
      if (mounted) setState(() => _loadingRules = false);
    }
  }

  // ── Save rules then reload from DB ───────────────────────────────────────
  // Critical: always reload after save so display matches DB truth.
  Future<bool> _saveRules(
      String sensitivity, Map<String, int> rankMap) async {
    try {
      final token = await AuthService.getToken();

      final List<Map<String, dynamic>> rules = [];
      for (final e in rankMap.entries) {
        final count = e.value;
        if (count <= 0) continue;

        final isArmed   = e.key.endsWith('_Arms');
        final cleanRank = isArmed
            ? e.key.substring(0, e.key.length - 5) // strip '_Arms'
            : e.key;

        rules.add({
          'rank':    cleanRank,
          'count':   count,
          'isArmed': isArmed,
        });
      }

      await ApiService.post('/admin/rules', {
        'sensitivity': sensitivity,
        'rules':       rules,
      }, token: token);

      // ── RELOAD FROM DB immediately after save ────────────────────────────
      // This guarantees the UI shows what's actually stored, not local state.
      await _loadAllRules();

      return true;
    } catch (e) {
      debugPrint('Save rules error: $e');
      return false;
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadStats(), _loadAllRules()]);
  }

  void _handleError(Object e) {
    if (!mounted) return;
    if (e.toString().contains('Session expired')) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }
    showSnack(context, 'Error: $e', error: true);
  }

  void _openManakModal(String sensitivity, Color color, String hindi) {
    showModalBottomSheet(
      context:         context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManakModal(
        sensitivity:  sensitivity,
        color:        color,
        hindi:        hindi,
        initialRules: Map.from(_rules[sensitivity] ?? {}),
        onSave: (updated) async {
          final ok = await _saveRules(sensitivity, updated);
          if (mounted) {
            showSnack(context,
              ok ? '$sensitivity मानक सेव हो गया ✓'
                 : 'सेव विफल, पुनः प्रयास करें',
              error: !ok,
            );
          }
          return ok;
        },
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      color: kPrimary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stats ───────────────────────────────
            _loadingStats
                ? _buildStatsShimmer()
                : _buildStatsGrid(),

            const SizedBox(height: 14),

            // 📄 ── GOSWARA REPORT BUTTON ───────────
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GoswaraPage(),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B6914), Color(0xFFB8860B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B6914).withOpacity(0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Goswara Report',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Summary Report of Booth Staff',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Colors.white54, size: 22),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // ── Hierarchy Banner ────────────────────
            _HierarchyBanner(),

            const SizedBox(height: 14),

            // 🗺️ ── MAP VIEW BUTTON (NEW) ───────────
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.pushNamed(context, '/map-view');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A5276), Color(0xFF2874A6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1A5276).withOpacity(0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.map_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Election Map View',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'District → Zone → Live Map',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Colors.white54, size: 22),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── मानक section ───────────────────────
            _ManakSection(
              rules: _rules,
              loading: _loadingRules,
              onTapSens: _openManakModal,
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    if (_stats == null) return const SizedBox.shrink();
    final sw   = MediaQuery.of(context).size.width;
    final cols = sw > 600 ? 4 : 2;
    final items = [
      _SI('Super Zones',  '${_stats!['superZones']     ?? 0}', Icons.layers_outlined,       kPrimary),
      _SI('Total Booths', '${_stats!['totalBooths']    ?? 0}', Icons.location_on_outlined,   kSuccess),
      _SI('Total Staff',  '${_stats!['totalStaff']     ?? 0}', Icons.badge_outlined,         kAccent),
      _SI('Assigned',     '${_stats!['assignedDuties'] ?? 0}', Icons.how_to_vote_outlined,   kInfo),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols, crossAxisSpacing: 10,
        mainAxisSpacing: 10, childAspectRatio: sw > 600 ? 1.7 : 1.45,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _StatCard(item: items[i]),
    );
  }

  Widget _buildStatsShimmer() {
    final sw = MediaQuery.of(context).size.width;
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: sw > 600 ? 4 : 2, crossAxisSpacing: 10,
        mainAxisSpacing: 10, childAspectRatio: 1.45,
      ),
      itemCount: 4,
      itemBuilder: (_, __) => _Shimmer(radius: 14),
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
          final role = await AuthService.getRole() ?? "admin";

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HierarchyReportPage(role: role),
            ),
          );
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
                  style: TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w800)),
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
//  मानक SECTION
// ══════════════════════════════════════════════════════════════════════════════
class _ManakSection extends StatelessWidget {
  final Map<String, Map<String, int>> rules;
  final bool loading;
  final void Function(String, Color, String) onTapSens;

  const _ManakSection({
    required this.rules, required this.loading, required this.onTapSens,
  });

  @override
  Widget build(BuildContext context) {
    final allSet = _kSensitivities
        .every((s) => (rules[s['key']] ?? {}).isNotEmpty);

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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(
                bottom: BorderSide(color: kBorder.withOpacity(0.3))),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.rule_folder_outlined,
                  color: kPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('मानक (Rules)', style: TextStyle(
                  color: kDark, fontSize: 14, fontWeight: FontWeight.w800)),
              Text('संवेदनशीलता पर टैप करें — सेट/संपादित करें',
                  style: TextStyle(color: kSubtle, fontSize: 10)),
            ])),
            _StatusBadge(allSet: allSet),
          ]),
        ),

        // 4 tiles
        (loading && rules.values.every((e) => e.isEmpty))
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kPrimary))))
            : Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2, crossAxisSpacing: 10,
                  mainAxisSpacing: 10, childAspectRatio: 1.5,
                  children: _kSensitivities.map((s) {
                    final key     = s['key']   as String;
                    final color   = s['color'] as Color;
                    final hindi   = s['hi']    as String;
                    final rankMap = rules[key] ?? {};
                    final isSet   = rankMap.isNotEmpty;
                    final total   = rankMap.values.fold(0, (a, b) => a + b);
                    return _SensTile(
                      label:   key, hindi: hindi, color: color,
                      isSet:   isSet, total: total, rankMap: rankMap,
                      onTap:   () => onTapSens(key, color, hindi),
                    );
                  }).toList(),
                ),
              ),

        // Footer hint
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(children: const [
            Icon(Icons.info_outline, size: 12, color: kSubtle),
            SizedBox(width: 5),
            Expanded(child: Text(
              'बूथ की संवेदनशीलता के अनुसार सशस्त्र/निःशस्त्र स्टाफ स्वतः असाइन होगा',
              style: TextStyle(color: kSubtle, fontSize: 10))),
          ]),
        ),
      ]),
    );
  }
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
  final Color color;
  final bool isSet;
  final int total;
  final Map<String, int> rankMap;
  final VoidCallback onTap;

  const _SensTile({
    required this.label, required this.hindi, required this.color,
    required this.isSet, required this.total, required this.rankMap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final armedTotal  = rankMap.entries
        .where((e) => e.key.endsWith('_Arms'))
        .fold(0, (a, b) => a + b.value);
    final normalTotal = total - armedTotal;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSet ? color.withOpacity(0.07) : kError.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSet
                    ? color.withOpacity(0.3)
                    : kError.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(11),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSet ? color : kError,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label, style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11, fontWeight: FontWeight.w900)),
              ),
              const Spacer(),
              Icon(
                isSet ? Icons.check_circle_rounded : Icons.edit_outlined,
                size: 15,
                color: isSet ? kSuccess : kSubtle,
              ),
            ]),
            const SizedBox(height: 6),
            Text(hindi,
                style: TextStyle(
                    color: isSet ? color : kSubtle,
                    fontSize: 9, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const Spacer(),
            if (isSet && total > 0) ...[
              Text('$total कर्मचारी', style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w900)),
              Row(children: [
                if (normalTotal > 0) ...[
                  const Icon(Icons.security_outlined, size: 9, color: kSubtle),
                  const SizedBox(width: 2),
                  Text('$normalTotal', style: const TextStyle(
                      color: kSubtle, fontSize: 9)),
                  const SizedBox(width: 6),
                ],
                if (armedTotal > 0) ...[
                  const Icon(Icons.gavel, size: 9, color: kSubtle),
                  const SizedBox(width: 2),
                  Text('$armedTotal सशस्त्र', style: const TextStyle(
                      color: kSubtle, fontSize: 9)),
                ],
              ]),
            ] else
              Row(children: [
                Icon(Icons.add_circle_outline, size: 12,
                    color: isSet ? color : kSubtle),
                const SizedBox(width: 4),
                Text(isSet ? 'संपादित करें' : 'सेट करें',
                    style: TextStyle(
                        color: isSet ? color : kSubtle,
                        fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  मानक MODAL — bottom sheet with armed/unarmed groups
// ══════════════════════════════════════════════════════════════════════════════
class _ManakModal extends StatefulWidget {
  final String sensitivity, hindi;
  final Color color;
  final Map<String, int> initialRules;
  final Future<bool> Function(Map<String, int>) onSave;

  const _ManakModal({
    required this.sensitivity, required this.hindi, required this.color,
    required this.initialRules, required this.onSave,
  });

  @override
  State<_ManakModal> createState() => _ManakModalState();
}

class _ManakModalState extends State<_ManakModal> {
  late final Map<String, TextEditingController> _ctrls;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final r in _kRanks)
        r['en'] as String: TextEditingController(
          text: '${widget.initialRules[r['en']] ?? 0}',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  int get _totalStaff => _ctrls.values.fold(0, (sum, c) {
    final n = int.tryParse(c.text) ?? 0;
    return sum + (n < 0 ? 0 : n);
  });

  int get _armedTotal => _kRanks
      .where((r) => (r['armVariant'] as bool? ?? false))
      .fold(0, (sum, r) {
    final n = int.tryParse(_ctrls[r['en']]?.text ?? '0') ?? 0;
    return sum + (n < 0 ? 0 : n);
  });

  int get _normalTotal => _totalStaff - _armedTotal;

  Future<void> _save() async {
    setState(() => _saving = true);
    final map = <String, int>{};
    for (final r in _kRanks) {
      final n = int.tryParse(_ctrls[r['en'] as String]!.text) ?? 0;
      if (n > 0) map[r['en'] as String] = n;
    }
    final ok = await widget.onSave(map);
    if (mounted) {
      setState(() => _saving = false);
      if (ok) Navigator.pop(context);
    }
  }

  void _change(String rankKey, int delta) {
    final ctrl = _ctrls[rankKey]!;
    final cur  = int.tryParse(ctrl.text) ?? 0;
    final next = (cur + delta).clamp(0, 99);
    setState(() => ctrl.text = '$next');
  }

  @override
  Widget build(BuildContext context) {
    final bottom      = MediaQuery.of(context).viewInsets.bottom;
    final normalRanks = _kRanks.where((r) => !(r['armVariant'] as bool? ?? false)).toList();
    final armedRanks  = _kRanks.where((r) =>  (r['armVariant'] as bool? ?? false)).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDF6E3),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Drag handle
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: kBorder.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2)),
        ),

        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(
                  color: kBorder.withOpacity(0.25)))),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: widget.color.withOpacity(0.3))),
              child: Center(child: Text(widget.sensitivity,
                  style: TextStyle(color: widget.color,
                      fontSize: widget.sensitivity.length > 2 ? 10 : 15,
                      fontWeight: FontWeight.w900))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${widget.sensitivity} मानक', style: const TextStyle(
                  color: kDark, fontSize: 16, fontWeight: FontWeight.w800)),
              Text(widget.hindi, style: TextStyle(
                  color: widget.color, fontSize: 11)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _TotalChip(label: 'कुल: $_totalStaff',
                  color: widget.color),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _TotalChip(label: '⚔ $_armedTotal',
                    color: const Color(0xFF6A1B9A)),
                const SizedBox(width: 4),
                _TotalChip(label: '🛡 $_normalTotal',
                    color: const Color(0xFF1A5276)),
              ]),
            ]),
          ]),
        ),

        // Rank list
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Unarmed group
              _GroupHeader(label: 'निःशस्त्र पुलिस (Unarmed)',
                  color: kInfo, icon: Icons.security_outlined),
              const SizedBox(height: 8),
              ...normalRanks.map((r) => _RankRow(
                rankKey:   r['en'] as String,
                hindi:     r['hi'] as String,
                ctrl:      _ctrls[r['en'] as String]!,
                color:     widget.color,
                onChange:  _change,
                onRebuild: () => setState(() {}),
              )),

              const SizedBox(height: 10),

              // Armed group
              _GroupHeader(
                  label: 'सशस्त्र पुलिस — आर्म्स (Armed)',
                  color: const Color(0xFF6A1B9A),
                  icon:  Icons.gavel),
              const SizedBox(height: 8),
              ...armedRanks.map((r) => _RankRow(
                rankKey:   r['en'] as String,
                hindi:     r['hi'] as String,
                ctrl:      _ctrls[r['en'] as String]!,
                color:     const Color(0xFF6A1B9A),
                onChange:  _change,
                onRebuild: () => setState(() {}),
              )),

              const SizedBox(height: 14),
            ]),
          ),
        ),

        // Save button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(
                _saving
                    ? 'सेव हो रहा है...'
                    : '${widget.sensitivity} मानक सेव करें',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _saving ? kSubtle : widget.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Group header ──────────────────────────────────────────────────────────────
class _GroupHeader extends StatelessWidget {
  final String label; final Color color; final IconData icon;
  const _GroupHeader(
      {required this.label, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    ]),
  );
}

// ── Total chip ────────────────────────────────────────────────────────────────
class _TotalChip extends StatelessWidget {
  final String label; final Color color;
  const _TotalChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 11, fontWeight: FontWeight.w800)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  RANK ROW — stepper control
// ══════════════════════════════════════════════════════════════════════════════
class _RankRow extends StatelessWidget {
  final String rankKey, hindi;
  final TextEditingController ctrl;
  final Color color;
  final void Function(String, int) onChange;
  final VoidCallback onRebuild;

  const _RankRow({
    required this.rankKey, required this.hindi, required this.ctrl,
    required this.color, required this.onChange, required this.onRebuild,
  });

  @override
  Widget build(BuildContext context) {
    final count  = int.tryParse(ctrl.text) ?? 0;
    final active = count > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: active
                ? color.withOpacity(0.3)
                : kBorder.withOpacity(0.4)),
      ),
      child: Row(children: [
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(hindi, style: TextStyle(
              color: active ? color : kDark,
              fontSize: 13, fontWeight: FontWeight.w700)),
          Text(rankKey.replaceAll('_Arms', ' (Arms)'),
              style: const TextStyle(color: kSubtle, fontSize: 10)),
        ])),
        Row(children: [
          _StepBtn(
            icon:    Icons.remove,
            color:   count > 0 ? kError : kSubtle.withOpacity(0.4),
            enabled: count > 0,
            onTap:   () { onChange(rankKey, -1); onRebuild(); },
          ),
          const SizedBox(width: 8),
          Container(
            width: 48, height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: active ? color : kBorder.withOpacity(0.6),
                  width: active ? 1.5 : 1),
            ),
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              style: TextStyle(
                  color: active ? color : kDark,
                  fontSize: 17, fontWeight: FontWeight.w900),
              decoration: const InputDecoration(
                border: InputBorder.none, isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 9),
              ),
              onChanged: (_) => onRebuild(),
            ),
          ),
          const SizedBox(width: 8),
          _StepBtn(
            icon:    Icons.add,
            color:   color,
            enabled: count < 99,
            onTap:   () { onChange(rankKey, 1); onRebuild(); },
          ),
        ]),
      ]),
    );
  }
}

// ── Step button ───────────────────────────────────────────────────────────────
class _StepBtn extends StatelessWidget {
  final IconData icon; final Color color;
  final bool enabled; final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.color,
      required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: enabled
            ? color.withOpacity(0.12)
            : Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: enabled
                ? color.withOpacity(0.35)
                : Colors.grey.withOpacity(0.2),
            width: 1.5),
      ),
      child: Icon(icon, size: 18,
          color: enabled ? color : Colors.grey.withOpacity(0.35)),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  STAT CARD
// ══════════════════════════════════════════════════════════════════════════════
class _SI {
  final String label, value; final IconData icon; final Color color;
  const _SI(this.label, this.value, this.icon, this.color);
}

class _StatCard extends StatelessWidget {
  final _SI item;
  const _StatCard({required this.item});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: item.color.withOpacity(0.18)),
      boxShadow: [BoxShadow(
          color: item.color.withOpacity(0.07),
          blurRadius: 10, offset: const Offset(0, 4))],
    ),
    padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: item.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9)),
          child: Icon(item.icon, color: item.color, size: 17),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.value, style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w900,
              color: item.color, height: 1)),
          const SizedBox(height: 3),
          Text(item.label, style: const TextStyle(
              fontSize: 11, color: kSubtle, fontWeight: FontWeight.w500)),
        ]),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHIMMER
// ══════════════════════════════════════════════════════════════════════════════
class _Shimmer extends StatefulWidget {
  final double? width, height; final double radius;
  const _Shimmer({this.width, this.height, this.radius = 6});
  @override State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>    _anim;
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
            const Color(0xFFEDE8D5),
            const Color(0xFFF5EED8), _anim.value),
      ),
    ),
  );
}