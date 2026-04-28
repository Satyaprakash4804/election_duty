import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';
import 'hierarchy_report_page.dart';
import 'goswara_page.dart';
import 'manak_booth_page.dart';
import 'manak_district_page.dart';

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

  // बूथ मानक — sensitivity → list of booth-rule rows (1..15)
  final Map<String, List<Map<String, dynamic>>> _boothRules = {
    'A++': [], 'A': [], 'B': [], 'C': [],
  };
  bool _loadingBoothRules = false;

  // जनपदीय मानक — list of duty rows
  List<Map<String, dynamic>> _districtRules = [];
  bool _loadingDistrictRules = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadAllBoothRules();
    _loadDistrictRules();
  }

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

  // ── BOOTH RULES ─────────────────────────────────────────────────────────
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
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        });
      }
    } catch (e) {
      debugPrint('booth rules load: $e');
    } finally {
      if (mounted) setState(() => _loadingBoothRules = false);
    }
  }

  // ── DISTRICT RULES ──────────────────────────────────────────────────────
  Future<void> _loadDistrictRules() async {
    if (mounted) setState(() => _loadingDistrictRules = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/district-rules', token: token);
      final list  = res['data'] as List? ?? [];
      if (mounted) {
        setState(() => _districtRules = list
            .map((e) => Map<String, dynamic>.from(e))
            .toList());
      }
    } catch (e) {
      debugPrint('district rules load: $e');
    } finally {
      if (mounted) setState(() => _loadingDistrictRules = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadStats(),
      _loadAllBoothRules(),
      _loadDistrictRules(),
    ]);
  }

  void _handleError(Object e) {
    if (!mounted) return;
    if (e.toString().contains('Session expired')) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }
    showSnack(context, 'Error: $e', error: true);
  }

  // ── Open booth manak page ───────────────────────────────────────────────
  void _openBoothManak(String sensitivity, Color color, String hindi) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ManakBoothPage(
          sensitivity:  sensitivity,
          color:        color,
          hindi:        hindi,
          initialRules: _boothRules[sensitivity] ?? [],
        ),
      ),
    );
    if (updated == true) await _loadAllBoothRules();
  }

  void _openDistrictManak() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ManakDistrictPage(initialRules: _districtRules),
      ),
    );
    if (updated == true) await _loadDistrictRules();
  }

  // ── BUILD ───────────────────────────────────────────────────────────────
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
            _loadingStats ? _buildStatsShimmer() : _buildStatsGrid(),
            const SizedBox(height: 14),

            // Goswara button
            _gradientNav(
              label: 'Goswara Report',
              subtitle: 'Summary Report of Booth Staff',
              icon: Icons.description_outlined,
              colors: const [Color(0xFF8B6914), Color(0xFFB8860B)],
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GoswaraPage())),
            ),
            const SizedBox(height: 14),

            _HierarchyBanner(),
            const SizedBox(height: 14),

            // Map view button
            _gradientNav(
              label: 'Election Map View',
              subtitle: 'District → Zone → Live Map',
              icon: Icons.map_outlined,
              colors: const [Color(0xFF1A5276), Color(0xFF2874A6)],
              onTap: () => Navigator.pushNamed(context, '/map-view'),
            ),
            const SizedBox(height: 14),

            // ── बूथ मानक section ───────────────────────────────────
            _BoothManakSection(
              boothRules: _boothRules,
              loading:    _loadingBoothRules,
              onTapSens:  _openBoothManak,
            ),
            const SizedBox(height: 14),

            // ── जनपदीय कानून व्यवस्था मानक section ─────────────────
            _DistrictManakSection(
              rules:   _districtRules,
              loading: _loadingDistrictRules,
              onTap:   _openDistrictManak,
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _gradientNav({
    required String label,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
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
            gradient: LinearGradient(
              colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                  color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.w800)),
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
//  बूथ मानक SECTION — 4 sensitivity tiles
// ══════════════════════════════════════════════════════════════════════════════
class _BoothManakSection extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> boothRules;
  final bool loading;
  final void Function(String, Color, String) onTapSens;

  const _BoothManakSection({
    required this.boothRules, required this.loading, required this.onTapSens,
  });

  @override
  Widget build(BuildContext context) {
    final allSet = _kSensitivities.every((s) =>
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
              child: const Icon(Icons.how_to_vote_outlined,
                  color: kPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('बूथ मानक', style: TextStyle(
                  color: kDark, fontSize: 14, fontWeight: FontWeight.w800)),
              Text('संवेदनशीलता × बूथ संख्या के अनुसार पुलिस बल',
                  style: TextStyle(color: kSubtle, fontSize: 10)),
            ])),
            _StatusBadge(allSet: allSet),
          ]),
        ),
        // 4 tiles
        loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: SizedBox(width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary))))
            : Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2, crossAxisSpacing: 10,
                  mainAxisSpacing: 10, childAspectRatio: 1.5,
                  children: _kSensitivities.map((s) {
                    final key       = s['key']   as String;
                    final color     = s['color'] as Color;
                    final hindi     = s['hi']    as String;
                    final rows      = boothRules[key] ?? [];
                    final filledRows = rows.where(_hasAny).toList();
                    final isSet     = filledRows.isNotEmpty;
                    final totalStaff = filledRows.fold<int>(
                      0, (sum, r) => sum + _rowTotalStaff(r));
                    return _SensTile(
                      label:   key, hindi: hindi, color: color,
                      isSet:   isSet, totalStaff: totalStaff,
                      filledRowCount: filledRows.length,
                      onTap:   () => onTapSens(key, color, hindi),
                    );
                  }).toList(),
                ),
              ),
      ]),
    );
  }

  bool _hasAny(Map<String, dynamic> r) =>
      ((r['siArmedCount']      ?? 0) as num) > 0 ||
      ((r['siUnarmedCount']    ?? 0) as num) > 0 ||
      ((r['hcArmedCount']      ?? 0) as num) > 0 ||
      ((r['hcUnarmedCount']    ?? 0) as num) > 0 ||
      ((r['constArmedCount']   ?? 0) as num) > 0 ||
      ((r['constUnarmedCount'] ?? 0) as num) > 0 ||
      ((r['auxForceCount']     ?? 0) as num) > 0 ||
      ((r['pacCount']          ?? 0) as num) > 0;

  int _rowTotalStaff(Map<String, dynamic> r) =>
      ((r['siArmedCount']      ?? 0) as num).toInt() +
      ((r['siUnarmedCount']    ?? 0) as num).toInt() +
      ((r['hcArmedCount']      ?? 0) as num).toInt() +
      ((r['hcUnarmedCount']    ?? 0) as num).toInt() +
      ((r['constArmedCount']   ?? 0) as num).toInt() +
      ((r['constUnarmedCount'] ?? 0) as num).toInt() +
      ((r['auxForceCount']     ?? 0) as num).toInt();
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
//  SENSITIVITY TILE — for booth manak grid
// ══════════════════════════════════════════════════════════════════════════════
class _SensTile extends StatelessWidget {
  final String label, hindi;
  final Color color;
  final bool isSet;
  final int totalStaff;
  final int filledRowCount;
  final VoidCallback onTap;

  const _SensTile({
    required this.label, required this.hindi, required this.color,
    required this.isSet, required this.totalStaff,
    required this.filledRowCount, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                color: isSet ? color.withOpacity(0.3) : kError.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(11),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSet ? color : kError,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label, style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
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
                    fontSize: 10, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const Spacer(),
            if (isSet) ...[
              Text('$totalStaff कर्मचारी', style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w900)),
              Text('$filledRowCount/15 बूथ-स्तर',
                  style: const TextStyle(color: kSubtle, fontSize: 10)),
            ] else
              Row(children: [
                Icon(Icons.add_circle_outline, size: 12, color: kSubtle),
                const SizedBox(width: 4),
                const Text('सेट करें',
                    style: TextStyle(color: kSubtle, fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ]),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  जनपदीय मानक SECTION — single banner card
// ══════════════════════════════════════════════════════════════════════════════
class _DistrictManakSection extends StatelessWidget {
  final List<Map<String, dynamic>> rules;
  final bool loading;
  final VoidCallback onTap;

  const _DistrictManakSection({
    required this.rules, required this.loading, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final filledCount = rules.where(_hasAny).length;
    final totalDuties = rules.length;
    final totalStaff = rules.fold<int>(0, (sum, r) =>
        sum +
        ((r['siArmedCount']       ?? 0) as num).toInt() +
        ((r['siUnarmedCount']     ?? 0) as num).toInt() +
        ((r['hcArmedCount']       ?? 0) as num).toInt() +
        ((r['hcUnarmedCount']     ?? 0) as num).toInt() +
        ((r['constArmedCount']    ?? 0) as num).toInt() +
        ((r['constUnarmedCount']  ?? 0) as num).toInt() +
        ((r['auxForceCount']      ?? 0) as num).toInt());
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
              child: const Icon(Icons.shield_outlined,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('जनपदीय कानून व्यवस्था मानक',
                  style: TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              if (loading)
                const Text('लोड हो रहा है...',
                    style: TextStyle(color: Colors.white60, fontSize: 11))
              else if (isSet)
                Text('$totalStaff कर्मचारी • $filledCount/$totalDuties ड्यूटी प्रकार',
                    style: const TextStyle(color: Colors.white70, fontSize: 11))
              else
                const Text('कानून व्यवस्था ड्यूटी मानक सेट करें',
                    style: TextStyle(color: Colors.white60, fontSize: 11)),
            ])),
            if (isSet)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 11),
                  SizedBox(width: 3),
                  Text('सेट', style: TextStyle(color: Colors.white,
                      fontSize: 10, fontWeight: FontWeight.w800)),
                ]),
              ),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 22),
          ]),
        ),
      ),
    );
  }

  bool _hasAny(Map<String, dynamic> r) =>
      ((r['sankhya']            ?? 0) as num) > 0 ||
      ((r['siArmedCount']       ?? 0) as num) > 0 ||
      ((r['siUnarmedCount']     ?? 0) as num) > 0 ||
      ((r['hcArmedCount']       ?? 0) as num) > 0 ||
      ((r['hcUnarmedCount']     ?? 0) as num) > 0 ||
      ((r['constArmedCount']    ?? 0) as num) > 0 ||
      ((r['constUnarmedCount']  ?? 0) as num) > 0 ||
      ((r['auxForceCount']      ?? 0) as num) > 0 ||
      ((r['pacCount']           ?? 0) as num) > 0;
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