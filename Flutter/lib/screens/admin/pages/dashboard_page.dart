import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../core/widgets.dart';
import 'hierarchy_report_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with AutomaticKeepAliveClientMixin {

  Map<String, dynamic>? _stats;
  final List<dynamic>   _duties = [];

  bool _loadingStats  = true;
  bool _loadingDuties = true;
  bool _loadingMore   = false;
  bool _hasMore       = true;

  int _page  = 1;
  int _total = 0;
  static const int _pageSize = 20;

  final ScrollController _scrollCtrl = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadStats();
    _loadDuties(reset: true);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      if (!_loadingMore && _hasMore) _loadDuties();
    }
  }

  // ── Load overview ─────────────────────────────────────────────────────────
  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get('/admin/overview', token: token);
      // overview → { "data": { "superZones":N, "totalBooths":N, ... } }
      if (mounted) setState(() => _stats = res['data'] as Map<String, dynamic>?);
    } catch (e) {
      _handleError(e);
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  // ── Load duties (paginated) ───────────────────────────────────────────────
  Future<void> _loadDuties({bool reset = false}) async {
    if (reset) {
      setState(() {
        _duties.clear();
        _page = 1; _hasMore = true; _loadingDuties = true;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final token = await AuthService.getToken();
      final res   = await ApiService.get(
        '/admin/duties?page=$_page&limit=$_pageSize',
        token: token,
      );

      // ─────────────────────────────────────────────────────────────────────
      // CRITICAL FIX:
      // Paginated endpoints return:
      //   { "data": { "data": [...], "total": N, "page": N, "totalPages": N } }
      //
      // res['data'] is a MAP (the pagination wrapper), NOT a List.
      // Casting it as List was causing the crash shown in the screenshot.
      // ─────────────────────────────────────────────────────────────────────
      final wrapper    = (res['data'] as Map<String, dynamic>?) ?? {};
      final items      = (wrapper['data']       as List?)?.cast<dynamic>() ?? [];
      final total      = (wrapper['total']      as num?)?.toInt() ?? 0;
      final totalPages = (wrapper['totalPages'] as num?)?.toInt() ?? 1;

      if (mounted) {
        setState(() {
          _duties.addAll(items);
          _total   = total;
          _hasMore = _page < totalPages;
          _page++;
        });
      }
    } catch (e) {
      _handleError(e);
    } finally {
      if (mounted) setState(() { _loadingDuties = false; _loadingMore = false; });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadStats(), _loadDuties(reset: true)]);
  }

  void _handleError(Object e) {
    if (!mounted) return;
    if (e.toString().contains('Session expired')) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }
    showSnack(context, 'Error: $e', error: true);
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sw = MediaQuery.of(context).size.width;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: kPrimary,
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [

          // Stats
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: _loadingStats
                  ? _StatsShimmer(cols: sw > 500 ? 4 : 2)
                  : _StatsGrid(stats: _stats, sw: sw),
            ),
          ),

          // Hierarchy banner
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _HierarchyBanner(),
            ),
          ),

          // Section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SectionHeader('Recent Duty Assignments'),
                  if (_total > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: kPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$_total total',
                          style: const TextStyle(
                              fontSize: 11, color: kPrimary, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ),

          // Duty list / shimmer / empty
          if (_loadingDuties)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, __) => const _DutyShimmer(), childCount: 6,
              ),
            )
          else if (_duties.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: _EmptyDuties(),
              ),
            )
          else if (sw > 700)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _DutyCard(duty: _duties[i]),
                  childCount: _duties.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 10,
                  mainAxisSpacing: 10, childAspectRatio: 2.7,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _DutyCard(duty: _duties[i]),
                  childCount: _duties.length,
                ),
              ),
            ),

          // Load-more indicator
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: kPrimary)),
                ),
              ),
            ),

          if (!_hasMore && _duties.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text('— End of list —',
                      style: TextStyle(color: kSubtle, fontSize: 12)),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  STATS GRID
// ═══════════════════════════════════════════════════════════════════════════════

class _StatsGrid extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final double sw;
  const _StatsGrid({required this.stats, required this.sw});

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();
    final cols = sw > 600 ? 4 : 2;
    final items = [
      _SI('Super Zones',  '${stats!['superZones']     ?? 0}', Icons.layers_outlined,      kPrimary),
      _SI('Total Booths', '${stats!['totalBooths']    ?? 0}', Icons.location_on_outlined, kSuccess),
      _SI('Total Staff',  '${stats!['totalStaff']     ?? 0}', Icons.badge_outlined,       kAccent),
      _SI('Assigned',     '${stats!['assignedDuties'] ?? 0}', Icons.how_to_vote_outlined, kInfo),
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
}

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
        boxShadow: [BoxShadow(color: item.color.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: item.color.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
            child: Icon(item.icon, color: item.color, size: 17),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.value,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w900, color: item.color, height: 1)),
            const SizedBox(height: 3),
            Text(item.label,
                style: const TextStyle(fontSize: 11, color: kSubtle, fontWeight: FontWeight.w500)),
          ]),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  STATS SHIMMER
// ═══════════════════════════════════════════════════════════════════════════════

class _StatsShimmer extends StatelessWidget {
  final int cols;
  const _StatsShimmer({required this.cols});
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.45,
      ),
      itemCount: 4,
      itemBuilder: (_, __) => _Shimmer(radius: 14),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  HIERARCHY BANNER
// ═══════════════════════════════════════════════════════════════════════════════

class _HierarchyBanner extends StatelessWidget {
  const _HierarchyBanner();
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const HierarchyReportPage()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F2B5B), Color(0xFF1E4D9B)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: const Color(0xFF0F2B5B).withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.table_chart_outlined, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('प्रशासनिक पदानुक्रम रिपोर्ट',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Super Zone · Sector · Panchayat Tables',
                    style: TextStyle(color: Colors.white60, fontSize: 11)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyDuties extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: kPrimary.withOpacity(0.08), shape: BoxShape.circle),
          child: const Icon(Icons.how_to_vote_outlined, size: 40, color: kPrimary),
        ),
        const SizedBox(height: 14),
        const Text('No duties assigned yet',
            style: TextStyle(color: kDark, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Pull down to refresh', style: TextStyle(color: kSubtle, fontSize: 12)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DUTY CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _DutyCard extends StatelessWidget {
  final dynamic duty;
  const _DutyCard({required this.duty});

  Color _tc(String t) {
    switch (t.toUpperCase()) {
      case 'A': return kSuccess;
      case 'B': return kInfo;
      default:  return kAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = '${duty['centerType'] ?? 'C'}';
    final tc   = _tc(type);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder.withOpacity(0.28)),
        boxShadow: [BoxShadow(color: kDark.withOpacity(0.04), blurRadius: 7, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: tc.withOpacity(0.1), shape: BoxShape.circle,
                border: Border.all(color: tc.withOpacity(0.35))),
            child: Center(child: Text(type,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: tc))),
          ),
          const SizedBox(width: 11),
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${duty['name'] ?? '-'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kDark),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.badge_outlined, size: 10, color: kSubtle),
                const SizedBox(width: 3),
                Text('${duty['pno'] ?? '-'}',
                    style: const TextStyle(fontSize: 11, color: kSubtle)),
              ]),
            ]),
          ),
          Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 10),
              color: kBorder.withOpacity(0.3)),
          Expanded(
            flex: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Text('${duty['centerName'] ?? '-'}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kDark),
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
              const SizedBox(height: 2),
              Text('${duty['superZoneName'] ?? '-'}',
                  style: const TextStyle(fontSize: 11, color: kSubtle),
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DUTY SHIMMER
// ═══════════════════════════════════════════════════════════════════════════════

class _DutyShimmer extends StatelessWidget {
  const _DutyShimmer();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder.withOpacity(0.2)),
        ),
        child: Row(children: [
          const SizedBox(width: 13),
          _Shimmer(width: 36, height: 36, radius: 18),
          const SizedBox(width: 11),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Shimmer(width: 110, height: 11, radius: 4),
            const SizedBox(height: 6),
            _Shimmer(width: 75, height: 9, radius: 4),
          ])),
          Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end, children: [
            _Shimmer(width: 95, height: 11, radius: 4),
            const SizedBox(height: 6),
            _Shimmer(width: 65, height: 9, radius: 4),
          ]),
          const SizedBox(width: 13),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SHIMMER ANIMATION
// ═══════════════════════════════════════════════════════════════════════════════

class _Shimmer extends StatefulWidget {
  final double? width, height;
  final double radius;
  const _Shimmer({this.width, this.height, this.radius = 6});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>    _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width, height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(const Color(0xFFEDE8D5), const Color(0xFFF5EED8), _anim.value),
        ),
      ),
    );
  }
}